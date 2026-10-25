# Several board runs in one go: build every image first (nothing waits on the board for a compile), then
# upload and run each board.py script in turn. On a bench where boards are shared, pass -LeaseScript (or set
# COCO3_LEASE_SCRIPT) to a lease.ps1 that defines Get-BoardLease / Release-BoardLease: the board is then
# taken once for all the runs and given back at the end, whatever happens.
#
#   tools\bench.ps1 -Compiler <pmf> -Port COM7 -Jobs 'rp2040\Diagnostics\video_modes.picow|tests\video_modes.txt|50','rp2040\coco3.picow|tests\basic_boot.txt|60'
#
# A job is source|script|seconds; an image file (.uf2) as the source is sent as it is. One whose name says
# region, disks or rom (a ROM or disk region for the flash) is only sent; its script is not run.
param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][string[]]$Jobs,
    [string]$Lease = 'coco3',
    [string]$LeaseScript = $env:COCO3_LEASE_SCRIPT
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$compilerPath = (Resolve-Path -LiteralPath $Compiler).Path
$compilerRoot = Split-Path $compilerPath -Parent
$plan = @()
# powershell -File passes 'a,b' as one string: split it
$Jobs = @($Jobs | ForEach-Object { $_.Split(',') } | Where-Object { $_ })
foreach ($job in $Jobs) {
    $parts = $job.Split('|')
    $src = [IO.Path]::GetFullPath((Join-Path $root $parts[0]))
    if ($src.EndsWith('.uf2')) { $img = $src }
    else {
        $img = Join-Path $root ('build\' + [IO.Path]::GetFileNameWithoutExtension($src) + '.uf2')
        & (Join-Path $PSScriptRoot 'build.ps1') -Compiler $Compiler -Source $parts[0] -Output ('build\' + [IO.Path]::GetFileName($img)) | Select-Object -Last 3
    }
    $plan += , @($img, $(if ($parts.Count -gt 1 -and $parts[1]) { [IO.Path]::GetFullPath((Join-Path $root $parts[1])) } else { '' }), $(if ($parts.Count -gt 2) { $parts[2] } else { '10' }))
}
$leaseObj = $null
if ($LeaseScript) {
    . $LeaseScript
    $leaseObj = Get-BoardLease -Port $Port -Owner $Lease -Minutes (2 + 2 * $plan.Count)
}
$failed = 0
try {
    if ($leaseObj) { "Lease taken: $($leaseObj.Tag)" }
    foreach ($p in $plan) {
        "=== $($p[0])"
        $up = Start-Process -FilePath $compilerPath -ArgumentList ('--radio-firmware "' + $p[0] + '" --port ' + $Port) `
            -WorkingDirectory $compilerRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput ($p[0] + '.upload.log') -RedirectStandardError ($p[0] + '.upload.err')
        Get-Content ($p[0] + '.upload.log') | Select-Object -Last 4
        if ($up.ExitCode -ne 0) { "UPLOAD FAILED (exit $($up.ExitCode))"; $failed++; break }
        if ($p[0] -match 'region|disks|rom') { continue }
        $a = @((Join-Path $PSScriptRoot 'board.py'), '--port', $Port, '--seconds', $p[2], '--output', ($p[0] + '.board.log'))
        if ($p[1]) { $a += @('--script', $p[1]) }
        Push-Location $root
        try { & py -3 @a } finally { Pop-Location }
        if ($LASTEXITCODE -ne 0) { "BOARD RUN FAILED (exit $LASTEXITCODE)"; $failed++ }
    }
} finally {
    if ($leaseObj) { Release-BoardLease $leaseObj; "Lease released" }
}
if ($failed) { exit 1 }
