# Check that every file listed in assets/manifest.json exists and matches its SHA-256.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_assets.ps1
# Exit 0 = all good. Entries whose id starts with EXAMPLE_ are skipped.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = [System.IO.File]::ReadAllText((Join-Path $root 'assets/manifest.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$bad = 0; $ok = 0
foreach ($a in $manifest.assets) {
    if ($a.id -like 'EXAMPLE_*') { continue }
    foreach ($f in $a.files) {
        $p = Join-Path $root $f.path
        if (-not (Test-Path -LiteralPath $p)) { Write-Output "MISSING $($a.id) $($f.path)"; $bad++; continue }
        $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $f.sha256.ToLower()) { Write-Output "HASH    $($a.id) $($f.path)"; $bad++ } else { $ok++ }
    }
}
Write-Output "ok $ok, problems $bad"
if ($bad) { exit 1 }
