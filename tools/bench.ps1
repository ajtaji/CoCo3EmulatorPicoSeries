# Several board runs under ONE lease of a shared board: build every image first (nothing waits on the
# board for a compile), then take C:\PMFBuild\board-leases\<port>.lease once, upload and run each
# board.py script in turn, and give the lease back.
#
#   tools\bench.ps1 -Compiler <pmf> -Port COM7 -Jobs 'rp2040\Diagnostics\video_modes.picow|tests\video_modes.txt|50','rp2040\Diagnostics\cpu_machine.picow|tests\cpu_machine.txt|30'
#
# A job is source|script|seconds; an image file (.uf2) as the source is sent as it is (a ROM or disk region).
param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][string[]]$Jobs,
    [string]$Lease = 'coco3'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$compilerPath = (Resolve-Path -LiteralPath $Compiler).Path
$compilerRoot = Split-Path $compilerPath -Parent
$plan = @()
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
$leaseFile = "C:\PMFBuild\board-leases\$Port.lease"
[IO.Directory]::CreateDirectory((Split-Path $leaseFile)) | Out-Null
$waited = 0
while ($true) {
    try { New-Item -ItemType File -Path $leaseFile -ErrorAction Stop | Out-Null; break }
    catch {
        if ($waited -ge 3600) { throw "The $Port lease is still held after 60 minutes; nothing was uploaded." }
        Start-Sleep -Seconds 30; $waited += 30
    }
}
$failed = 0
try {
    Set-Content -LiteralPath $leaseFile -Value "$Lease $(Get-Date -Format o) bench $($plan.Count) jobs"
    "Lease taken after $waited s"
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
    # another session may have the file open to read who holds it: retry until it is really gone
    for ($i = 0; $i -lt 50 -and (Test-Path -LiteralPath $leaseFile); $i++) {
        Remove-Item -LiteralPath $leaseFile -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $leaseFile) { Start-Sleep -Milliseconds 200 }
    }
    if (Test-Path -LiteralPath $leaseFile) { Write-Warning "COULD NOT REMOVE $leaseFile - delete it by hand; it blocks the board" }
    "Lease released"
}
if ($failed) { exit 1 }
