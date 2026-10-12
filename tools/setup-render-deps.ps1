[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dx = Join-Path $root '.deps\directx-headers'
$xr = Join-Path $root '.deps\openxr'
New-Item -ItemType Directory -Force -Path $dx, $xr | Out-Null

function Fetch-Checked([string]$Url, [string]$Target, [string]$Sha256) {
    if (Test-Path -LiteralPath $Target) {
        if ((Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash -eq $Sha256) { return }
        throw "Existing render dependency differs from pinned input: $Target"
    }
    Invoke-WebRequest -Uri $Url -OutFile $Target
    if ((Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Render dependency checksum mismatch: $Target. Not used by the build."
    }
}

$headerRevision = 'c526f205c5f96cd2884bf0834c14c7e61bb726c8'
$hashRevision = '84f68ed1a40db3f3444a306162cab6ac0adfe842'
Fetch-Checked "https://raw.githubusercontent.com/microsoft/DirectX-Headers/$headerRevision/include/directx/D3D12TokenizedProgramFormat.hpp" (Join-Path $dx 'D3D12TokenizedProgramFormat.hpp') '5862EF7C8B819F0D02BA73563A9DF4DC0E89F11FE59D8F598DEF39122273C626'
Fetch-Checked "https://raw.githubusercontent.com/microsoft/DirectXShaderCompiler/$hashRevision/lib/DxilHash/DxilHash.cpp" (Join-Path $dx 'DxilHash.cpp') 'D66B631EA28D4C90A8217FAC004F9290EAAC07F79115451E0C4E954C0B0C94AF'
Fetch-Checked 'https://api.nuget.org/v3-flatcontainer/openxr/1.1.47/openxr.1.1.47.nupkg' (Join-Path $xr 'sdk.zip') '344C173E6FB3D4C4C2CE49562433BB4898781048C5EBA2BD25E9311CBFA087C8'
Expand-Archive -LiteralPath (Join-Path $xr 'sdk.zip') -DestinationPath (Join-Path $xr 'sdk') -Force
if (-not (Test-Path -LiteralPath (Join-Path $dx 'LICENSE-Headers.txt'))) {
    Invoke-WebRequest "https://raw.githubusercontent.com/microsoft/DirectX-Headers/$headerRevision/LICENSE" -OutFile (Join-Path $dx 'LICENSE-Headers.txt')
}
if (-not (Test-Path -LiteralPath (Join-Path $dx 'LICENSE-Hash.txt'))) {
    Invoke-WebRequest "https://raw.githubusercontent.com/microsoft/DirectXShaderCompiler/$hashRevision/LICENSE.TXT" -OutFile (Join-Path $dx 'LICENSE-Hash.txt')
}
if (-not (Test-Path -LiteralPath (Join-Path $xr 'LICENSE.txt'))) {
    Invoke-WebRequest 'https://raw.githubusercontent.com/KhronosGroup/OpenXR-SDK/release-1.1.47/LICENSE' -OutFile (Join-Path $xr 'LICENSE.txt')
}
Write-Host 'Pinned OpenXR and shader-clipping dependencies ready (ignored, not redistributed as SDKs).'
