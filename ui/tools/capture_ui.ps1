param(
  [string]$Out = (Join-Path $PSScriptRoot '..\screenshots'),
  [string]$Godot = 'E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\tmp\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe',
  [string]$Lock = 'E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\tmp\bridge-render.lock'
)
# UI 预览截图：在 1920×1080 窗口里把 ui/preview 的 10 个状态各截一张 PNG。
# 要用本机 GPU，所以照 Test.ps1 的做法拿共享锁 bridge-render.lock；锁被占用就退出，不强行解锁。
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $Godot)) { throw 'Pass -Godot with the Godot 4.7.2 executable; no automatic installation.' }
$project = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$outAbs = (Resolve-Path $Out).Path
$token = [guid]::NewGuid().ToString()
try { $stream = [System.IO.File]::Open($Lock, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read) }
catch { throw 'GPU_BUSY: bridge-render.lock exists; wait for its owner. This helper never force-unlocks.' }
$writer = [System.IO.StreamWriter]::new($stream)
$writer.Write((@{ pid = $PID; token = $token; output = $outAbs; job = 'renou-godot ui capture'; created = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress))
$writer.Dispose()
try {
  & $Godot --path $project --resolution 1920x1080 res://ui/preview/ui_preview.tscn -- ('--ui-capture=' + $outAbs)
  $code = $LASTEXITCODE
}
finally {
  $current = Get-Content -LiteralPath $Lock -Raw | ConvertFrom-Json
  if ($current.pid -eq $PID -and $current.token -eq $token) { Remove-Item -LiteralPath $Lock }
}
exit $code
