[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsRoot) { throw 'Visual Studio x64 C++ build tools are required.' }
$outputDir = Join-Path $root 'artifacts\native-pose-tests'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$exe = Join-Path $outputDir 'native-pose-tests.exe'
$compile = 'call "{0}" -no_logo -arch=x64 -host_arch=x64 && cl.exe /nologo /std:c++17 /EHsc /W4 /O2 /MT /I"{1}" /I"{2}" /Fo"{3}" /Fe:"{4}" "{5}"' -f `
    (Join-Path $vsRoot 'Common7\Tools\VsDevCmd.bat'), `
    (Join-Path $root 'src\QVVR.Native'), `
    (Join-Path $root '.deps\openvr-sdk\headers'), `
    (Join-Path $outputDir 'native-pose-tests.obj'), $exe, `
    (Join-Path $PSScriptRoot 'native-pose-tests.cpp')
& $env:ComSpec /d /c $compile
if ($LASTEXITCODE -ne 0) { throw 'Native pose test compilation failed.' }
& $exe
if ($LASTEXITCODE -ne 0) { throw 'Native pose tests failed.' }
