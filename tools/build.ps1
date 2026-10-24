# Build the CoCo 3 firmware with PureMetalForge, and optionally upload it and talk to it.
#
#   tools\build.ps1 -Compiler <PureMetalForge.exe>                          # rp2040\coco3.picow -> firmware\coco3-pico-w.uf2
#   tools\build.ps1 -Compiler <pmf> -Source rp2040\Diagnostics\video_modes.picow -Output build\video_modes.uf2 -Port COM7 -Seconds 30
#   tools\build.ps1 -Compiler <pmf> -Port COM7 -Script tests\basic_hello.txt  # upload, then run a board.py script
#
# The image must end below flash $10050000 (the NES ROM store other programs on a shared board keep
# at $50000) and below the CoCo 3's own regions ($140000 up), which the compiler checks itself
# through FlashRegion. A board shared between sessions is leased while it is used:
# C:\PMFBuild\board-leases\<port>.lease is created exclusively and removed afterwards.
param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [string]$Source = 'rp2040\coco3.picow',
    [string]$Output = '',
    [string]$Port = '',
    [int]$Seconds = 15,
    [string]$Script = '',
    [string]$Lease = 'coco3',
    [switch]$NoUpload
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sourcePath = [IO.Path]::GetFullPath((Join-Path $root $Source))
if (!$Output) {
    $name = if ($sourcePath -match '\.pico2w?$') { 'coco3-pico2-w.uf2' } else { 'coco3-pico-w.uf2' }
    $Output = "firmware\$name"
}
$outputPath = [IO.Path]::GetFullPath((Join-Path $root $Output))
[IO.Directory]::CreateDirectory((Split-Path $outputPath -Parent)) | Out-Null
$compilerPath = (Resolve-Path -LiteralPath $Compiler).Path
$compilerRoot = Split-Path $compilerPath -Parent
$stdout = $outputPath + '.build.log'
$stderr = $outputPath + '.stderr.log'
$previous = $env:PMF_ROOT
try {
    $env:PMF_ROOT = $compilerRoot
    $p = Start-Process -FilePath $compilerPath -ArgumentList ('--compile "' + $sourcePath + '" -o "' + $outputPath + '"') `
        -WorkingDirectory $compilerRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
} finally { $env:PMF_ROOT = $previous }
Get-Content $stdout | Select-Object -Last 25
Get-Content $stderr
if ($p.ExitCode -ne 0) { throw "Compiler exit $($p.ExitCode); see $stdout" }

$uf2 = [IO.File]::ReadAllBytes($outputPath); $end = 0
for ($o = 0; $o -lt $uf2.Length; $o += 512) {
    $blockEnd = [BitConverter]::ToUInt32($uf2, $o + 12) + [BitConverter]::ToUInt32($uf2, $o + 16)
    if ($blockEnd -gt $end) { $end = $blockEnd }
}
'Image ends at 0x{0:X8} ({1} bytes of flash)' -f $end, ($end - 0x10000000)
if ($end -gt 0x10050000) { throw ('Image reaches 0x{0:X8}, past 0x10050000: on a shared board it would overwrite the NES ROM store' -f $end) }
"SHA-256 $((Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash) $outputPath"
if (!$Port -or $NoUpload) { return }

$leaseDir = 'C:\PMFBuild\board-leases'
[IO.Directory]::CreateDirectory($leaseDir) | Out-Null
$leaseFile = Join-Path $leaseDir "$Port.lease"
$waited = 0
while ($true) {
    try { New-Item -ItemType File -Path $leaseFile -ErrorAction Stop | Out-Null; break }
    catch {
        $holder = Get-Content -LiteralPath $leaseFile -Raw -ErrorAction SilentlyContinue
        if ($waited -ge 3600) { throw "The $Port lease is still held after 60 minutes ($holder); nothing was uploaded." }
        if ($waited % 300 -eq 0) { "Lease held ($holder); waiting, retrying every 30 s." }
        Start-Sleep -Seconds 30; $waited += 30
    }
}
try {
    Set-Content -LiteralPath $leaseFile -Value "$Lease $(Get-Date -Format o)"
    $up = Start-Process -FilePath $compilerPath -ArgumentList ('--radio-firmware "' + $outputPath + '" --port ' + $Port) `
        -WorkingDirectory $compilerRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput ($outputPath + '.upload.log') -RedirectStandardError ($outputPath + '.upload.err')
    Get-Content ($outputPath + '.upload.log') | Select-Object -Last 8
    if ($up.ExitCode -ne 0) { throw "Upload exit $($up.ExitCode); see $outputPath.upload.log" }
    $args2 = @((Join-Path $PSScriptRoot 'board.py'), '--port', $Port, '--seconds', $Seconds, '--output', ($outputPath + '.board.log'))
    if ($Script) { $args2 += @('--script', [IO.Path]::GetFullPath((Join-Path $root $Script))) }
    & py -3 @args2
    if ($LASTEXITCODE -ne 0) { throw "board.py exit $LASTEXITCODE" }
} finally {
    # Rename first, then delete. A delete while another session's poller has the file open only marks it
    # "delete pending", and the name stays taken (and unreadable) until that handle closes - which held
    # COM7 for minutes on 2026-10-23. A rename frees the name at once; the renamed file goes when it can.
    $gone = "$leaseFile.$PID.released"
    for ($i = 0; $i -lt 50 -and (Test-Path -LiteralPath $leaseFile); $i++) {
        try { [IO.File]::Move($leaseFile, $gone) } catch { Start-Sleep -Milliseconds 200 }
    }
    Remove-Item -LiteralPath $gone -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $leaseFile) { Write-Warning "COULD NOT RELEASE $leaseFile - delete it by hand; it blocks the board" }
}
