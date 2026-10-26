# Build the desktop CoCo 3 and prove it in console runs: BASIC boots and runs a typed program, BASIC's own
# 10-second loop count, and a .DSK file saved, then loaded and run by a second session. Exit 1 on a failure.
#   tools\desktop_check.ps1 [-Rom <folder with coco3.rom and disk11.rom>] [-EngineDir <engine folder>]
#   (-Rom default: build\roms, as build_roms.ps1 leaves them; -EngineDir default: the engine cloned beside)
param([string]$Rom = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\roms'), [string]$EngineDir = '', [switch]$NoBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root 'build\CoCo3.exe'
New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
if (!$NoBuild) {
    $engine = @(); if ($EngineDir) { $engine = @('/CONSTANT', ('GL_ENGINE_DIR$=' + $EngineDir.TrimEnd('\', '/').Replace('\', '/') + '/')) }
    & 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe' (Join-Path $root 'desktop\CoCo3.pb') /EXE $exe /THREAD /DPIAWARE @engine | Select-Object -Last 3
    if ($LASTEXITCODE -ne 0) { throw 'the desktop build failed' }
}
$roms = @('--rom', "$Rom\coco3.rom", '--cart', "$Rom\disk11.rom")
$failed = 0
function Check($name, $args2, $pattern) {
    $out = (& $exe @roms @args2 2>&1 | Out-String)
    $speed = ($out -split "`n" | Where-Object { $_ -match '^done:' }) -join ''
    if ($out -match $pattern) { "PASS  $name   $speed" } else { "FAIL  $name   (wanted /$pattern/)"; $out; $script:failed++ }
}
Check 'boot and a typed program' @('--log', '2000', '--type-file', (Join-Path $root 'tests\hello.bas')) 'HELLO FROM THE DESKTOP[\s\S]*216'
Check 'BASIC TIMER loop, 10 s at 0.89 MHz' @('--log', '2400', '--type-file', (Join-Path $root 'tests\timer.bas')) 'LOOPS IN 600 TICKS +\d+'
$dsk = Join-Path $root 'build\check.dsk'; Remove-Item $dsk -ErrorAction SilentlyContinue
Check 'disk: SAVE to a new .DSK' @('--log', '2000', '--new-disk0', $dsk, '--type-file', (Join-Path $root 'tests\disk_save.bas')) 'PCDISK +BAS +0 +B +1'
Check 'disk: LOAD and RUN in a new session' @('--log', '2000', '--disk0', $dsk, '--type-file', (Join-Path $root 'tests\disk_load.bas')) 'RUN +\r?\nSAVED ON THE PC'
# the README's Controls section is the controls table (desktop/controls.pbi) as --controls-md writes it
$md = Join-Path $root 'build\controls.md'
Start-Process $exe -ArgumentList @('--controls-md', "`"$md`"") -Wait -NoNewWindow
$want = ((Get-Content $md -Raw) -replace "`r", '').Trim()
$readme = (Get-Content (Join-Path $root 'README.md') -Raw) -replace "`r", ''
$have = if ($readme -match '(?s)<!-- controls table: CoCo3\.exe --controls-md -->\n(.*?)\n<!-- end controls table -->') { $Matches[1].Trim() } else { '' }
if ($have -eq $want) { 'PASS  README Controls section = the controls table' } else { 'FAIL  README Controls section differs from CoCo3.exe --controls-md'; $failed++ }
if ($failed) { "$failed check(s) failed"; exit 1 }
'all desktop checks passed'
