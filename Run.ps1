param([ValidateSet(1,2,3)][int]$Level=1,[string]$Godot='E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\tmp\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference='Stop'
if (!(Test-Path -LiteralPath $Godot)) { throw 'Pass -Godot with the existing Godot 4.7.2 executable; no automatic installation.' }
& $Godot --path $PSScriptRoot -- ('--level=' + $Level)
exit $LASTEXITCODE
