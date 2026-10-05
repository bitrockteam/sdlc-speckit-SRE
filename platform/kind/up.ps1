# Creates the capped kind cluster "sdlc".
# The node container is limited with docker update; the kubelet reserves everything above the cap
# so that node allocatable reflects the cap seen by the scheduler.
param(
    [double]$Cpus = 2,
    [int]$MemoryGiB = 4,
    # Headroom inside the cap for kubelet, containerd and the node OS.
    [int]$NodeOverheadMiB = 512
)

# No ErrorActionPreference=Stop: kind writes progress to stderr, which PowerShell 5.1 would turn
# into a terminating error. Native failures are checked through $LASTEXITCODE instead.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$vmCpus = [int](docker info --format '{{.NCPU}}')
$vmMemBytes = [int64](docker info --format '{{.MemTotal}}')
if ($Cpus -gt $vmCpus) { throw "Requested $Cpus CPU, Docker VM has $vmCpus" }

$capBytes = [int64]$MemoryGiB * 1GB
$sysCpuMilli = [int](($vmCpus - $Cpus) * 1000) + 250
$sysMemMiB = [int](($vmMemBytes - $capBytes) / 1MB) + $NodeOverheadMiB

$config = (Get-Content "$here\cluster.template.yaml" -Raw) `
    -replace '__SYS_CPU__', "${sysCpuMilli}m" `
    -replace '__SYS_MEM__', "${sysMemMiB}Mi"
$rendered = Join-Path $env:TEMP 'sdlc-kind-cluster.yaml'
# UTF-8 without BOM: PowerShell 5.1 adds a BOM with -Encoding utf8.
[IO.File]::WriteAllText($rendered, $config, (New-Object Text.UTF8Encoding $false))

Write-Host "Docker VM: $vmCpus CPU, $([math]::Round($vmMemBytes / 1GB, 1)) GiB"
Write-Host "Cap: $Cpus CPU, $MemoryGiB GiB; kubelet systemReserved: ${sysCpuMilli}m CPU, ${sysMemMiB}Mi"

kind create cluster --config $rendered --wait 180s
if ($LASTEXITCODE -ne 0) { throw 'kind create cluster failed' }

docker update --cpus $Cpus --memory "${MemoryGiB}g" --memory-swap "${MemoryGiB}g" sdlc-control-plane | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docker update failed' }

$alloc = (kubectl --context kind-sdlc get node sdlc-control-plane -o json | ConvertFrom-Json).status.allocatable
Write-Host "Node allocatable: $($alloc.cpu) CPU, $($alloc.memory) memory"
