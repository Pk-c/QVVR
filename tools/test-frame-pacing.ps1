[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vsRoot=& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vsRoot){throw 'Visual Studio x64 C++ build tools are required.'}
$output=Join-Path $root 'artifacts/frame-pacing-tests'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$exe=Join-Path $output 'frame-pacing-tests.exe'
$compile='call "{0}" -no_logo -arch=x64 -host_arch=x64 && cl.exe /nologo /std:c++17 /EHsc /W4 /O2 /MT /I"{1}" /Fo"{2}\\" /Fe:"{3}" "{4}"' -f (Join-Path $vsRoot 'Common7/Tools/VsDevCmd.bat'),(Join-Path $root 'src/QVVR.Native'),$output,$exe,(Join-Path $PSScriptRoot 'frame-pacing-tests.cpp')
& $env:ComSpec /d /c $compile
if($LASTEXITCODE -ne 0){throw 'XR cadence tests did not compile.'}
& $exe
if($LASTEXITCODE -ne 0){throw 'XR cadence tests failed.'}
