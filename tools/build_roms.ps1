# Build coco3.rom and disk11.rom from the disassembled sources of github.com/tomctomc/coco_roms, check
# them against the SHA-1s that project's Makefile expects (MESS/MAME's), and pack the ROM region UF2.
#
#   tools\build_roms.ps1 [-Source ..\coco_roms] [-Work build\roms] [-Out private\coco_rom.uf2] [-Target rp2040|rp2350]
#
# The clone is not changed: its HEAD is exported into -Work and built there. a09.c is compiled with
# MSVC (no make or gcc on this machine); the steps are the Makefile's, in its order. A ROM whose SHA-1
# differs is refused and nothing is packed. The ROMs and the UF2 stay out of git.
param(
    [string]$Source = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'coco_roms'),
    [string]$Work = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\roms'),
    [string]$Out = 'private\coco_rom.uf2',
    [ValidateSet('rp2040', 'rp2350')][string]$Target = 'rp2040'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory $Work | Out-Null
git -C $Source archive HEAD -o (Join-Path $Work 'src.tar')
tar -x -f (Join-Path $Work 'src.tar') -C $Work
Set-Content -Path (Join-Path $Work 'cl.cmd') -Encoding ascii -Value @(
    'call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul',
    'cl /nologo /O2 /D_CRT_SECURE_NO_WARNINGS a09.c /Fe:a09.exe')
Push-Location $Work
try {
    cmd /c (Join-Path $Work 'cl.cmd') | Out-Null
    if (!(Test-Path a09.exe)) { throw 'a09.c did not compile (MSVC); nothing was built.' }
    $a = @('-oNOW', '-oTXT', '-oEXP', '-oNCL')
    $steps = @(
        @('-Bauto_tmp', '-Yauto_symbols_coco.asm', 'cocodefs.asm'),
        @('-Bauto_tmp', '-Yauto_symbols_bas.asm', 'auto_symbols_coco.asm', 'bas.asm', '-DVERBAS=20'),
        @('-Bauto_tmp', '-Yauto_symbols_extbas.asm', 'auto_symbols_bas.asm', 'extbas.asm', '-DVEREXTBAS=20'),
        @('-Bbas20.rom', '-Lbas20.lst', 'auto_symbols_coco.asm', 'bas.asm', '-DVERBAS=20'),
        @('-Bextbas20.rom', '-Lextbas20.lst', 'auto_symbols_bas.asm', 'extbas.asm', '-DVEREXTBAS=20'),
        @('-Bsupbas20.rom', '-Lsupbas20.lst', 'auto_symbols_extbas.asm', 'supbas.asm', '-DCOCOPAL=0'),
        @('-Bdisk11.rom', '-Ldisk11.lst', 'auto_symbols_extbas.asm', 'disk.asm', '-DVERDISK=11'))
    foreach ($s in $steps) { & .\a09.exe @a @s | Out-Null }
    $bytes = [IO.File]::ReadAllBytes("$Work\extbas20.rom") + [IO.File]::ReadAllBytes("$Work\bas20.rom") + [IO.File]::ReadAllBytes("$Work\supbas20.rom")
    [IO.File]::WriteAllBytes("$Work\coco3.rom", $bytes)
    $want = @{ 'coco3.rom' = 'E0D82953FB6FD03768604933DF1CE8BC51FC427D'; 'disk11.rom' = '10BDC5AA2D7D7F205F67B47B19003A4BD89DEFD1' }
    foreach ($k in $want.Keys) {
        $h = (Get-FileHash -Algorithm SHA1 "$Work\$k").Hash
        if ($h -ne $want[$k]) { throw "$k has SHA-1 $h, not the expected $($want[$k]); nothing was packed." }
        "$k SHA-1 $h OK"
    }
} finally { Pop-Location }
# The region for the flash (the Pico W at $140000, the Feather RP2350 at $4A2000) and, as rom_region.bin
# in -Work, the same region for a Pico 2 W build that takes it over USB at boot (board.py's images verb).
& py -3 (Join-Path $PSScriptRoot 'make_rom_region.py') --rom "$Work\coco3.rom" --cart "$Work\disk11.rom" --target $Target `
    --offset $(if ($Target -eq 'rp2350') { '0x4A2000' } else { '0x140000' }) --out (Join-Path $root $Out) --bin "$Work\rom_region.bin"
if ($LASTEXITCODE -ne 0) { throw 'make_rom_region.py refused the ROMs.' }
