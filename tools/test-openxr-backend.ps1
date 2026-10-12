[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vsRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsRoot) { throw 'Visual Studio x64 C++ build tools are required.' }
$outputDir = Join-Path $root 'artifacts/openxr-backend-tests'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$exe = Join-Path $outputDir 'openxr-backend-tests.exe'
# Intentionally no OpenVR or OpenXR loader import library. XR calls resolve to
# the fake runtime; accidentally calling OpenVR in the backend fails to link.
$compile = 'call "{0}" -no_logo -arch=x64 -host_arch=x64 && cl.exe /nologo /std:c++17 /EHsc /W4 /O2 /MT /I"{1}" /I"{2}" /I"{3}" /Fo"{4}\\" /Fe:"{5}" "{6}" "{7}" /link d3d11.lib d3dcompiler.lib' -f `
    (Join-Path $vsRoot 'Common7/Tools/VsDevCmd.bat'), `
    (Join-Path $root 'src/QVVR.Native'), (Join-Path $root '.deps/openvr-sdk/headers'), `
    (Join-Path $root '.deps/openxr/sdk/include'), $outputDir, $exe, `
    (Join-Path $PSScriptRoot 'openxr-backend-tests.cpp'), (Join-Path $root 'src/QVVR.Native/OpenXrBackend.cpp')
& $env:ComSpec /d /c $compile
if ($LASTEXITCODE -ne 0) { throw 'OpenXR backend test compilation failed.' }
& $exe
if ($LASTEXITCODE -ne 0) { throw 'OpenXR backend tests failed.' }
