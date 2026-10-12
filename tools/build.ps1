[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$SkipPackage
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'src\QVVR\QVVR.csproj'
$nativeSource = Join-Path $root 'src\QVVR.Native'
$openVrSdk = Join-Path $root '.deps\openvr-sdk'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$required = @(
    (Join-Path $root '.deps\bepinex-5.4.23.5\BepInEx\core\BepInEx.dll'),
    (Join-Path $root '.deps\openvr-2.15.6\headers\openvr_api.cs'),
    (Join-Path $root '.deps\openvr-2.15.6\bin\win64\openvr_api.dll'),
    (Join-Path $root '.deps\unity-reference\UnityEngine.dll'),
    (Join-Path $root '.deps\unity-reference\UnityEngine.CoreModule.dll'),
    (Join-Path $root '.deps\unity-reference\UnityEngine.InputLegacyModule.dll'),
    (Join-Path $root '.deps\unity-reference\UnityEngine.PhysicsModule.dll'),
    (Join-Path $root '.deps\unity-reference\UnityEngine.UIModule.dll'),
    (Join-Path $root '.deps\unity-reference\UnityEngine.UI.dll'),
    (Join-Path $root '.deps\unity-reference\UnityEngine.TextRenderingModule.dll'),
    (Join-Path $openVrSdk 'headers\openvr.h'),
    (Join-Path $openVrSdk 'lib\win64\openvr_api.lib'),
    (Join-Path $root '.deps\openxr\sdk\native\x64\lib\openxr_loader.lib'),
    (Join-Path $root '.deps\openxr\sdk\native\x64\bin\openxr_loader.dll'),
    (Join-Path $root '.deps\directx-headers\D3D12TokenizedProgramFormat.hpp'),
    (Join-Path $root '.deps\directx-headers\DxilHash.cpp')
)

$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count -gt 0) {
    throw "Build dependencies are missing. Run tools\setup-deps.ps1 first.`n$($missing -join "`n")"
}

if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw 'Visual Studio Installer (vswhere.exe) is required to locate the x64 C++ compiler.'
}

$vsRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsRoot) {
    throw 'The Visual Studio x64 C++ build tools are required.'
}
$vsDevCmd = Join-Path $vsRoot 'Common7\Tools\VsDevCmd.bat'
$nativeOutput = Join-Path $nativeSource "bin\$Configuration"
$nativeObjects = Join-Path $nativeSource "obj-direct\$Configuration"
New-Item -ItemType Directory -Force -Path $nativeOutput, $nativeObjects | Out-Null

$nativeDll = Join-Path $nativeOutput 'QVVR.Native.dll'
$nativeObject = Join-Path $nativeObjects 'QVVR.Native.obj'
$nativeCpp = Join-Path $nativeSource 'QVVR.Native.cpp'
$nativeOptimize = if ($Configuration -eq 'Release') { '/O2 /MT' } else { '/Od /MTd /Zi' }
$nativeCommand = 'call "{0}" -no_logo -arch=x64 -host_arch=x64 && cl.exe /nologo /std:c++17 /EHsc /W4 {1} /LD /I"{2}" /I"{7}\.deps\directx-headers" /I"{7}\.deps\openxr\sdk\include" /Fo"{8}\\" /Fe:"{4}" "{5}" "{9}" "{10}" /link /LIBPATH:"{6}" openvr_api.lib d3d11.lib d3dcompiler.lib advapi32.lib shell32.lib ole32.lib "{7}\.deps\openxr\sdk\native\x64\lib\openxr_loader.lib"' -f `
    $vsDevCmd, `
    $nativeOptimize, `
    (Join-Path $openVrSdk 'headers'), `
    $nativeObject, `
    $nativeDll, `
    $nativeCpp, `
    (Join-Path $openVrSdk 'lib\win64'), $root, $nativeObjects, (Join-Path $nativeSource 'ShaderClip.cpp'), (Join-Path $nativeSource 'OpenXrBackend.cpp')

& $env:ComSpec /d /c $nativeCommand
if ($LASTEXITCODE -ne 0) {
    throw 'QVVR native bridge build failed.'
}

dotnet build $project -c $Configuration --nologo
if ($LASTEXITCODE -ne 0) {
    throw 'QVVR plugin build failed.'
}

if (-not $SkipPackage) {
    & (Join-Path $PSScriptRoot 'package.ps1') -Configuration $Configuration
}
