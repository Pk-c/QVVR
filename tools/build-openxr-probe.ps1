$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$outputDir = Join-Path $root 'artifacts\openxr-probe'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$compile = 'call "{0}" -no_logo -arch=x64 -host_arch=x64 && cl.exe /nologo /std:c++17 /EHsc /W4 /O2 /MT /I"{1}\.deps\openxr\sdk\include" /Fo"{2}\probe.obj" /Fe:"{2}\probe.exe" "{1}\tools\openxr-windows-probe.cpp" /link advapi32.lib shell32.lib ole32.lib "{1}\.deps\openxr\sdk\native\x64\lib\openxr_loader.lib"' -f (Join-Path $vsRoot 'Common7\Tools\VsDevCmd.bat'), $root, $outputDir
& $env:ComSpec /d /c $compile
if ($LASTEXITCODE -ne 0) { throw 'OpenXR probe compilation failed.' }
