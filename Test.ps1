param([switch]$Capture,[string]$Godot='E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\tmp\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference='Stop'
if (!(Test-Path -LiteralPath $Godot)) { throw 'Pass -Godot with the existing verified executable.' }
if (!$Capture) { & $Godot --headless --path $PSScriptRoot --fixed-fps 60 -- --test; exit $LASTEXITCODE }
$lockPath='E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\tmp\bridge-render.lock'
$token=[guid]::NewGuid().ToString()
try { $lockStream=[System.IO.File]::Open($lockPath,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read) }
catch { throw 'GPU_BUSY: existing bridge-render.lock; ask its owner to release it. This helper never force-unlocks.' }
$writer=[System.IO.StreamWriter]::new($lockStream)
$writer.Write((@{pid=$PID;token=$token;output=(Join-Path $PSScriptRoot 'evidence');created=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Compress))
$writer.Dispose()
try { & $Godot --path $PSScriptRoot --fixed-fps 60 -- --capture; $runExit=$LASTEXITCODE }
finally {
  $current=Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
  if ($current.pid -eq $PID -and $current.token -eq $token) { Remove-Item -LiteralPath $lockPath }
}
exit $runExit
