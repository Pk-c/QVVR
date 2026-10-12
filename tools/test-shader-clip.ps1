[CmdletBinding()]
param([string]$CapturedShader)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$outputDir = Join-Path $root 'artifacts\shader-clip-tests'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$exe = Join-Path $outputDir 'shader-clip-tests.exe'
$compile = 'call "{0}" -no_logo -arch=x64 -host_arch=x64 && cl.exe /nologo /std:c++17 /EHsc /W4 /O2 /MT /DQVVR_CLIP_TEST /I"{1}" /I"{2}" /Fo"{3}\\" /Fe:"{4}" "{5}" "{6}" /link d3d11.lib d3dcompiler.lib' -f (Join-Path $vsRoot 'Common7\Tools\VsDevCmd.bat'), (Join-Path $root 'src\QVVR.Native'), (Join-Path $root '.deps\directx-headers'), $outputDir, $exe, (Join-Path $PSScriptRoot 'shader-clip-tests.cpp'), (Join-Path $root 'src\QVVR.Native\ShaderClip.cpp')
& $env:ComSpec /d /c $compile
if ($LASTEXITCODE -ne 0) { throw 'Shader clip tests did not compile.' }
if ($CapturedShader) { $testArguments = @((Resolve-Path -LiteralPath $CapturedShader).Path) } else { $testArguments = @() }
& $exe @testArguments | Select-String 'Diagnostic|Captured QV|Unused SV_Position|Create shader=|GPU clipping:|GPU feather|GPU caps|Depth-only prepass|Perspective clipping|constant-buffer diagnostic|validation passed|failed|GPU-copy variants'
if ($LASTEXITCODE -ne 0) { throw 'Shader clip tests failed.' }
