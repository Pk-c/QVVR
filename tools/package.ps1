[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = '0.1.0'
$releaseRoot = Join-Path $root 'build\release'
$stage = Join-Path $releaseRoot "QVVR-v$version"
$zip = Join-Path $releaseRoot "QVVR-v$version.zip"
$hashFile = "$zip.sha256"
$loader = Join-Path $root '.deps\bepinex-5.4.23.5'
$pluginDll = Join-Path $root "src\QVVR\bin\$Configuration\netstandard2.0\QVVR.dll"
$nativeDll = Join-Path $root "src\QVVR.Native\bin\$Configuration\QVVR.Native.dll"
$openVr = Join-Path $root '.deps\openvr-2.15.6\bin\win64\openvr_api.dll'
$openXrLoader = Join-Path $root '.deps\openxr\sdk\native\x64\bin\openxr_loader.dll'

foreach ($required in @($loader, $pluginDll, $nativeDll, $openVr, $openXrLoader)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required package input missing: $required"
    }
}

$resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\')
$resolvedStage = [IO.Path]::GetFullPath($stage)
if (-not $resolvedStage.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace staging path outside project: $resolvedStage"
}

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'BepInEx\plugins\QVVR') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'BepInEx\config') | Out-Null

Copy-Item -Path (Join-Path $loader 'BepInEx\*') -Destination (Join-Path $stage 'BepInEx') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $loader 'winhttp.dll') -Destination $stage
Copy-Item -LiteralPath (Join-Path $loader 'doorstop_config.ini') -Destination $stage
if (Test-Path -LiteralPath (Join-Path $loader '.doorstop_version')) {
    Copy-Item -LiteralPath (Join-Path $loader '.doorstop_version') -Destination $stage
}
Copy-Item -LiteralPath $pluginDll -Destination (Join-Path $stage 'BepInEx\plugins\QVVR')
Copy-Item -LiteralPath $nativeDll -Destination (Join-Path $stage 'BepInEx\plugins\QVVR')
Copy-Item -LiteralPath $openVr -Destination (Join-Path $stage 'BepInEx\plugins\QVVR')
Copy-Item -LiteralPath $openXrLoader -Destination (Join-Path $stage 'BepInEx\plugins\QVVR')
$licenses = Join-Path $stage 'BepInEx\plugins\QVVR\licenses'
New-Item -ItemType Directory -Force -Path $licenses | Out-Null
Copy-Item -LiteralPath (Join-Path $root '.deps\openxr\LICENSE.txt') -Destination (Join-Path $licenses 'OpenXR.txt')
Copy-Item -LiteralPath (Join-Path $root '.deps\directx-headers\LICENSE-Headers.txt') -Destination (Join-Path $licenses 'DirectX-Headers.txt')
Copy-Item -LiteralPath (Join-Path $root '.deps\directx-headers\LICENSE-Hash.txt') -Destination (Join-Path $licenses 'DirectX-Hash.txt')
Copy-Item -LiteralPath (Join-Path $root 'package-assets\dev.qvvr.prototype.cfg') -Destination (Join-Path $stage 'BepInEx\config')
Copy-Item -LiteralPath (Join-Path $root 'package-assets\README.txt') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'package-assets\QVVR-THIRD-PARTY-NOTICES.txt') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'package-assets\uninstall.bat') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'package-assets\qvvr-launch-options.txt') -Destination $stage
Set-Content -LiteralPath (Join-Path $stage '.qvvr-loader-owner') -Value 'QVVR 0.1.0 installed BepInEx 5.4.23.5' -Encoding Ascii

$manifest = [ordered]@{
    name = 'QVVR'
    version = $version
    steamAppId = 1494110
    createdUtc = [DateTime]::UtcNow.ToString('o')
    backend = 'Exclusive-OpenXR-with-OpenVR-fallback'
    passthrough = 'OpenXR-ALPHA_BLEND-opt-in'
    clipping = 'D3D11-global-fragment-cylinder'
    controls = 'two-hand-natural-placement'
    layout = 'persistent-physical-entry-fit'
    experimental = $true
    architecture = 'win-x64'
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'qvvr-package.json') -Encoding UTF8

if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
$hash = Get-FileHash -LiteralPath $zip -Algorithm SHA256
Set-Content -LiteralPath $hashFile -Value ($hash.Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zip)) -Encoding Ascii

Write-Host "Package tree: $stage"
Write-Host "Archive:      $zip"
Write-Host "SHA-256:      $($hash.Hash.ToLowerInvariant())"
