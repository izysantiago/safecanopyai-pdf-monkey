#!/usr/bin/env bash
set -euo pipefail

# Synchronize a local Liquid template file to a PDFMonkey template via API.
#
# Usage:
#   ./sync_pdfmonkey.sh -k <api_key> -i <template_id> -f <template_file> [-n <template_name>]
# or set env vars:
#   PDFMONKEY_API_KEY, PDFMONKEY_TEMPLATE_ID, PDFMONKEY_TEMPLATE_NAME
#
# Notes:
# - Tries multiple payload wrappers (template, document_template, plain) and auth schemes
#   because PDFMonkey API variants differ. Succeeds on the first 200/201 response.
# - Requires python3 for safe JSON escaping of the Liquid template content.

API_URL_BASE=${PDFMONKEY_API_URL_BASE:-"https://api.pdfmonkey.io/api/v1"}
API_KEY=${PDFMONKEY_API_KEY:-""}
TEMPLATE_ID=${PDFMONKEY_TEMPLATE_ID:-""}
TEMPLATE_FILE=""
TEMPLATE_NAME=${PDFMONKEY_TEMPLATE_NAME:-""}

usage() {
  echo "Usage: $0 -k <api_key> -i <template_id> -f <template_file> [-n <template_name>]" >&2
  exit 1
}

# Parse flags
while getopts ":k:i:f:n:" opt; do
  case $opt in
    k) API_KEY="$OPTARG" ;;
    i) TEMPLATE_ID="$OPTARG" ;;
    f) TEMPLATE_FILE="$OPTARG" ;;
    n) TEMPLATE_NAME="$OPTARG" ;;
    *) usage ;;
  esac
done

if [[ -z "${API_KEY}" || -z "${TEMPLATE_ID}" ]]; then
  echo "Missing API key or template id." >&2
  usage
fi

if [[ -z "${TEMPLATE_FILE}" ]]; then
  # Default to repo's main template
  if [[ -f "body.html.liquid" ]]; then
    TEMPLATE_FILE="body.html.liquid"
  else
    echo "-f <template_file> is required (no default template found)." >&2
    usage
  fi
fi

if [[ ! -f "${TEMPLATE_FILE}" ]]; then
  echo "Template file not found: ${TEMPLATE_FILE}" >&2
  exit 2
fi

# Safely JSON-escape the template content via Python
CONTENT_JSON=$(python3 -c 'import json,sys; print(json.dumps(open(sys.argv[1],"r",encoding="utf-8").read()))' "${TEMPLATE_FILE}")

if [[ -z "${TEMPLATE_NAME}" ]]; then
  # Derive a reasonable default name from filename
  BASENAME=$(basename "${TEMPLATE_FILE}")
  TEMPLATE_NAME="${BASENAME%.*}"
fi

URL="${API_URL_BASE}/templates/${TEMPLATE_ID}"
TMP_RESP=$(mktemp)

try_update() {
  local auth_header="$1"
  local wrapper="$2"

  local data
  case "$wrapper" in
    template)
      data='{"template":{"content":'"${CONTENT_JSON}"',"name":'"$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "${TEMPLATE_NAME}")"'}}'
      ;;
    document_template)
      data='{"document_template":{"content":'"${CONTENT_JSON}"',"name":'"$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "${TEMPLATE_NAME}")"'}}'
      ;;
    plain)
      data='{"content":'"${CONTENT_JSON}"',"name":'"$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "${TEMPLATE_NAME}")"'}'
      ;;
    *) echo "Unknown wrapper: $wrapper" >&2; return 1 ;;
  esac

  # Try PATCH, then PUT as fallback
  for method in PATCH PUT; do
    http_code=$(curl -sS -o "${TMP_RESP}" -w "%{http_code}" -X "$method" \
      -H "${auth_header}" \
      -H "Content-Type: application/json" \
      "${URL}" --data "$data" || true)

    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
      echo "Sync succeeded (${method}, ${wrapper}, ${auth_header%% *})."
      rm -f "${TMP_RESP}"
      return 0
    fi
  done

  echo "Attempt failed with ${wrapper} using ${auth_header%% *}. HTTP=${http_code}" >&2
  echo "Response:" >&2
  sed -e 's/.*/  &/' "${TMP_RESP}" >&2 || true
  echo >&2
  return 1
}

# Try a matrix of auth schemes and payload wrappers until one works
AUTH_HEADERS=(
  "Authorization: Bearer ${API_KEY}"
  "Authorization: Token token=${API_KEY}"
)
WRAPPERS=(template document_template plain)

for ah in "${AUTH_HEADERS[@]}"; do
  for wr in "${WRAPPERS[@]}"; do
    if try_update "$ah" "$wr"; then
      echo "Updated template ${TEMPLATE_ID} from ${TEMPLATE_FILE}" >&2
      exit 0
    fi
  done
done

rm -f "${TMP_RESP}"
echo "All attempts failed. Check your API key, template id, and PDFMonkey API variant." >&2
exit 3
