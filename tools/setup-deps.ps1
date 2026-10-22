[CmdletBinding()]
param(
    [string]$GameDir,
    [Parameter(Mandatory = $true)][string]$BepInExSource,
    [Parameter(Mandatory = $true)][string]$OpenVrSource,
    [string]$OpenVrSdkSource,
    [string]$FallbackUnityReferenceDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$deps = Join-Path $root '.deps'
$referenceDestination = Join-Path $deps 'unity-reference'

New-Item -ItemType Directory -Force -Path $deps | Out-Null
New-Item -ItemType Directory -Force -Path $referenceDestination | Out-Null

if (-not (Test-Path -LiteralPath $BepInExSource -PathType Container)) {
    throw "BepInEx source not found: $BepInExSource"
}
if (-not (Test-Path -LiteralPath $OpenVrSource -PathType Container)) {
    throw "OpenVR source not found: $OpenVrSource"
}

$bepDestination = Join-Path $deps 'bepinex-5.4.23.5'
$openVrDestination = Join-Path $deps 'openvr-2.15.6'
foreach ($copy in @(@($BepInExSource, $bepDestination), @($OpenVrSource, $openVrDestination))) {
    if ([IO.Path]::GetFullPath($copy[0]).TrimEnd('\') -eq [IO.Path]::GetFullPath($copy[1]).TrimEnd('\')) { continue }
    New-Item -ItemType Directory -Force -Path $copy[1] | Out-Null
    Copy-Item -Path (Join-Path $copy[0] '*') -Destination $copy[1] -Recurse -Force
}

$openVrSdkDestination = Join-Path $deps 'openvr-sdk'
if ($OpenVrSdkSource) {
    if (-not (Test-Path -LiteralPath (Join-Path $OpenVrSdkSource 'headers\openvr.h') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $OpenVrSdkSource 'lib\win64\openvr_api.lib') -PathType Leaf)) {
        throw "OpenVR SDK headers or win64 library not found: $OpenVrSdkSource"
    }
    New-Item -ItemType Directory -Force -Path $openVrSdkDestination | Out-Null
    Copy-Item -Path (Join-Path $OpenVrSdkSource '*') -Destination $openVrSdkDestination -Recurse -Force
}
elseif (-not (Test-Path -LiteralPath (Join-Path $openVrSdkDestination 'headers\openvr.h') -PathType Leaf)) {
    git clone --depth 1 --branch v2.15.6 https://github.com/ValveSoftware/openvr.git $openVrSdkDestination
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to fetch the official OpenVR SDK v2.15.6. Pass -OpenVrSdkSource with a local checkout.'
    }
}

$managedSource = $null
$useRecursiveReferenceLookup = $false
if ($GameDir) {
    $candidate = Join-Path $GameDir 'QV_Data\Managed'
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "QV managed directory not found: $candidate"
    }
    $managedSource = $candidate
}
elseif ($FallbackUnityReferenceDir -and (Test-Path -LiteralPath $FallbackUnityReferenceDir -PathType Container)) {
    $managedSource = $FallbackUnityReferenceDir
    $useRecursiveReferenceLookup = $true
    Write-Warning 'QV is not available locally; using compatible Unity 2019 reference assemblies for the first build only.'
}
else {
    throw 'Pass -GameDir with the local QV installation. No fallback Unity reference directory exists.'
}

$assemblies = @(
    'UnityEngine.dll',
    'UnityEngine.CoreModule.dll',
    'UnityEngine.InputLegacyModule.dll',
    'UnityEngine.PhysicsModule.dll',
    'UnityEngine.AnimationModule.dll',
    'UnityEngine.UIModule.dll',
    'UnityEngine.UI.dll',
    'UnityEngine.TextRenderingModule.dll'
)

foreach ($assembly in $assemblies) {
    $source = Join-Path $managedSource $assembly
    if ($useRecursiveReferenceLookup) {
        $match = Get-ChildItem -LiteralPath $managedSource -Recurse -Filter $assembly -File | Select-Object -First 1
        if ($match) {
            $source = $match.FullName
        }
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required Unity reference missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination $referenceDestination -Force
}

Write-Host "Dependencies ready under $deps"
Write-Host "Unity compile references: $managedSource"
& (Join-Path $PSScriptRoot 'setup-render-deps.ps1')
& (Join-Path $PSScriptRoot 'setup-release-deps.ps1')
