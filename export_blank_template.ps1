param(
    [string]$TemplatePath = "body.html.liquid",
    [string]$OutputDirectory = "output",
    [string]$HtmlFileName = "blank-template.html",
    [string]$PdfFileName = "blank-template.pdf"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $TemplatePath -PathType Leaf)) {
    throw "Template file '$TemplatePath' was not found."
}

$resolvedTemplate = (Resolve-Path -Path $TemplatePath).ProviderPath

if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$outputDirectory = (Resolve-Path -Path $OutputDirectory).ProviderPath
$htmlPath = Join-Path -Path $outputDirectory -ChildPath $HtmlFileName
$pdfPath = Join-Path -Path $outputDirectory -ChildPath $PdfFileName

$content = Get-Content -Path $resolvedTemplate -Raw

# Preserve Zoho Sign merge tags.
$placeholderProtector = [char]0x27EC, [char]0x27ED
$content = [regex]::Replace(
    $content,
    "{{\s*(Signature(:[^\}]+)?|Date(:[^\}]+)?)\s*}}",
    { param($m) $m.Value.Replace("{", $placeholderProtector[0]).Replace("}", $placeholderProtector[1]) }
)

# Normalize composite Zoho placeholders that are built from concatenated pieces.
$content = [regex]::Replace(
    $content,
    "{{\s*""\{\{SIGNATURE:Seller""\s*}}\s*{{\s*seller_index\s*}}\s*{{\s*""\}\}""\s*}}",
    "$($placeholderProtector[0])$($placeholderProtector[0])SIGNATURE:Seller#$($placeholderProtector[1])$($placeholderProtector[1])"
)
$content = [regex]::Replace(
    $content,
    "{{\s*""\{\{DATE:Seller""\s*}}\s*{{\s*seller_index\s*}}\s*{{\s*""\}\}""\s*}}",
    "$($placeholderProtector[0])$($placeholderProtector[0])DATE:Seller#$($placeholderProtector[1])$($placeholderProtector[1])"
)
$content = [regex]::Replace(
    $content,
    "{{\s*""\{\{SIGNATURE:Buyer""\s*}}\s*{{\s*buyer_index\s*}}\s*{{\s*""\}\}""\s*}}",
    "$($placeholderProtector[0])$($placeholderProtector[0])SIGNATURE:Buyer#$($placeholderProtector[1])$($placeholderProtector[1])"
)
$content = [regex]::Replace(
    $content,
    "{{\s*""\{\{DATE:Buyer""\s*}}\s*{{\s*buyer_index\s*}}\s*{{\s*""\}\}""\s*}}",
    "$($placeholderProtector[0])$($placeholderProtector[0])DATE:Buyer#$($placeholderProtector[1])$($placeholderProtector[1])"
)

# Strip Liquid comments and logic tags.
$content = [regex]::Replace(
    $content,
    "{%-?\s*comment\s*-?%}.*?{%-?\s*endcomment\s*-?%}",
    "",
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)
$content = [regex]::Replace(
    $content,
    "{%-?[\s\S]*?-?%}",
    "",
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

# Render simple default fallbacks.
$content = [regex]::Replace(
    $content,
    "{{\s*[^{}|]+\|\s*default:\s*'([^']*)'\s*}}",
    { param($m) $m.Groups[1].Value }
)
$content = [regex]::Replace(
    $content,
    "{{\s*[^{}|]+\|\s*default:\s*""([^""]*)""\s*}}",
    { param($m) $m.Groups[1].Value }
)

# Trim any remaining simple Liquid outputs (leave blanks).
$content = [regex]::Replace(
    $content,
    "{{.*?}}",
    "",
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

# Restore Zoho Sign merge tags.
$content = $content.Replace($placeholderProtector[0], "{").Replace($placeholderProtector[1], "}")

# Expand additional signature placeholders into fixed Zoho Sign anchor tags.
$additionalStart = $content.IndexOf('<h3>Additional Signatures</h3>')
if ($additionalStart -ge 0) {
    $appendixIndex = $content.IndexOf('<div class="appendix">', $additionalStart)
    if ($appendixIndex -gt $additionalStart) {
$pairSections = New-Object System.Collections.Generic.List[string]
for ($i = 2; $i -le 10; $i++) {
$section = @"
<div class="sig-pair" style="break-inside: avoid; page-break-inside: avoid; margin-top: 24px;">
          <div class="sig-grid">
            <div>
              <div class="sig-cap">Signature of Seller $i</div>
              <div class="sig-box"><span class="zsign-tag">{{SIGNATURE:Seller$($i)}}</span></div>
              <div style="margin-top:6px;">Date</div>
              <div class="sig-box" style="height:24px;"><span class="zsign-tag">{{DATE:Seller$($i)}}</span></div>
            </div>
            <div>
              <div class="sig-cap">Signature of Buyer $i</div>
              <div class="sig-box"><span class="zsign-tag">{{SIGNATURE:Buyer$($i)}}</span></div>
              <div style="margin-top:6px;">Date</div>
              <div class="sig-box" style="height:24px;"><span class="zsign-tag">{{DATE:Buyer$($i)}}</span></div>
            </div>
          </div>
        </div>
"@
[void]$pairSections.Add($section)
if ($i -lt 10) {
[void]$pairSections.Add('<div class="page-break"></div>')
}
}

$replacement = "<h3>Additional Signatures</h3>`r`n" + ($pairSections -join "`r`n")
        $content = $content.Substring(0, $additionalStart) + $replacement + $content.Substring($appendixIndex, $content.Length - $appendixIndex)
    }
}

# Normalize whitespace a bit for cleaner output.
$content = [regex]::Replace($content, "(\r?\n){3,}", "`r`n`r`n")

Set-Content -Path $htmlPath -Value $content -Encoding UTF8

$userDataDir = Join-Path -Path $outputDirectory -ChildPath ".edge-headless-profile"
if (-not (Test-Path -Path $userDataDir)) {
    New-Item -ItemType Directory -Path $userDataDir | Out-Null
}

$edgeCandidates = @()
if ($Env:ProgramFiles) {
    $edgeCandidates += (Join-Path -Path $Env:ProgramFiles -ChildPath "Microsoft\Edge\Application\msedge.exe")
}
if (${Env:ProgramFiles(x86)}) {
    $edgeCandidates += (Join-Path -Path ${Env:ProgramFiles(x86)} -ChildPath "Microsoft\Edge\Application\msedge.exe")
}

$edgePath = $edgeCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $edgePath) {
    throw "Microsoft Edge (Chromium) was not found. Install Edge or update the script with the correct path."
}

$edgeArgs = @(
    "--headless",
    "--disable-gpu",
    "--no-first-run",
    "--allow-file-access-from-files",
    "--user-data-dir=$userDataDir",
    "--print-to-pdf=$pdfPath",
    "--virtual-time-budget=10000",
    $htmlPath
)

$edgeProcess = Start-Process -FilePath $edgePath -ArgumentList $edgeArgs -NoNewWindow -PassThru -Wait
if ($edgeProcess.ExitCode -ne 0) {
    throw "Edge headless print failed with exit code $($edgeProcess.ExitCode)."
}

Write-Host "Generated blank HTML template at: $htmlPath"
Write-Host "Generated PDF template at:      $pdfPath"
