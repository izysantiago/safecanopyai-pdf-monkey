$env:PDFMONKEY_API_KEY = "YOUR_REAL_KEY_HERE"
$pdfPath   = "C:\Users\izysa\D9CFE9A0-D565-4E10-A278-5746E830F156"
$template  = "D9CFE9A0-D565-4E10-A278-5746E830F156"

pdfmonkey watch $pdfPath -t $template
