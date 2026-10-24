# Put the CoCo 3 on the Pico W's panel for someone to look at: upload, type a program through board.py,
# then keep the board leased for -Minutes so nobody reflashes it, and give it back.
param([Parameter(Mandatory = $true)][string]$Compiler, [string]$Port = 'COM7', [int]$Minutes = 10,
      [string]$Script = 'tests\show_ron.txt', [string]$Who = 'Ron')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. 'C:\PMFBuild\board-leases\lease.ps1'
$until = (Get-Date).AddMinutes($Minutes + 3).ToString('HH:mm')
$l = Get-BoardLease -Port $Port -Owner "coco3 showing CoCo 3 to $Who until $until" -Minutes ($Minutes + 3)
try {
    "Lease taken: $($l.Tag)"
    $img = Join-Path $root 'build\coco3.uf2'
    $compilerRoot = Split-Path (Resolve-Path $Compiler).Path -Parent
    $up = Start-Process -FilePath $Compiler -ArgumentList ('--radio-firmware "' + $img + '" --port ' + $Port) -WorkingDirectory $compilerRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$img.upload.log" -RedirectStandardError "$img.upload.err"
    if ($up.ExitCode -ne 0) { throw "upload failed ($($up.ExitCode))" }
    Push-Location $root
    try { & py -3 (Join-Path $PSScriptRoot 'board.py') --port $Port --seconds 2 --output "$img.show.log" --script (Join-Path $root $Script) } finally { Pop-Location }
    "ON SCREEN $(Get-Date -Format HH:mm:ss); holding the board $Minutes minutes"
    Start-Sleep -Seconds ($Minutes * 60)
} finally {
    Release-BoardLease $l
    "Lease released $(Get-Date -Format HH:mm:ss)"
}
