[CmdletBinding()]
param(
    [string]$FrameHost = 'frame',
    [string]$FrameUser = 'steamos',
    [string]$RemoteGameDir = '/home/steamos/.local/share/Steam/steamapps/common/QV'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$destination = Join-Path $root "artifacts\frame-$stamp"
New-Item -ItemType Directory -Force -Path $destination | Out-Null

$remote = "$FrameUser@$FrameHost"
$items = @(
    "$RemoteGameDir/BepInEx/LogOutput.log",
    '/home/steamos/.local/share/Steam/logs/vrcompositor.txt',
    '/home/steamos/.local/share/Steam/logs/vrserver.txt',
    '/home/steamos/.local/share/Steam/logs/perfcriteria.txt'
)

foreach ($item in $items) {
    & scp "${remote}:$item" $destination
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not collect $item"
    }
}

Write-Host "Frame logs collected under $destination"
