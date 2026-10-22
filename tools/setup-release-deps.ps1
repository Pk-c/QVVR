[CmdletBinding()]
param([switch]$Offline)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$directory=Join-Path $root '.deps/release-licenses'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
# Complete upstream texts and corresponding source for the unmodified, replaceable
# Doorstop DLL. Versioned official inputs; no game data or user credentials.
$inputs=@(
 @('BepInEx.txt','https://raw.githubusercontent.com/BepInEx/BepInEx/v5.4.23.5/LICENSE','E6E534EF6F4347B6449407EE046A3D09CB0174C6F688C996AD0BED94B74B3933'),
 @('UnityDoorstop.txt','https://raw.githubusercontent.com/NeighTools/UnityDoorstop/v4.5.0/LICENSE','20C17D8B8C48A600800DFD14F95D5CB9FF47066A9641DDEAB48DC54AEC96E331'),
 @('HarmonyX.txt','https://raw.githubusercontent.com/BepInEx/HarmonyX/v2.9.0/LICENSE','7E54AB4766EF78637A05FB3454663A66DE6BB960DBD4C7088890ED76B0844F36'),
 @('Harmony.txt','https://raw.githubusercontent.com/BepInEx/HarmonyX/v2.9.0/LICENSE.Harmony','27E65B8ADEEDD73C2F76088346EFA3756A00E4E88CCA5ACE0C196CE1733EF570'),
 @('BepInEx.Harmony.txt','https://raw.githubusercontent.com/BepInEx/BepInEx.Harmony/d4cdcb4cdeac14a0b77012165f5f5a9f5032a9fa/LICENSE','FEB87A2E0C305DE3464CC44077DA5393C52D8CA6362D37427157D04EC6F4510D'),
 @('MonoMod.txt','https://raw.githubusercontent.com/MonoMod/MonoMod/v22.01.29.01/LICENSE','0B64833222E3C6A426AD29362D26334619FE02EAF2B89EA9C37805521896C920'),
 @('Mono.Cecil.txt','https://raw.githubusercontent.com/jbevain/cecil/0.10.4/LICENSE.txt','13D58ECBED676511C0C4C4009BFF107025E50007FF5E7901DC562700EC62509E'),
 @('UnityDoorstop-v4.5.0-source.zip','https://codeload.github.com/NeighTools/UnityDoorstop/zip/refs/tags/v4.5.0','7F0C963104AA08BF5FEFEF8FF85E7FECD8306838F5AF3101487D9DB4E9188D63')
)
foreach($releaseInput in $inputs){
 $target=Join-Path $directory $releaseInput[0]
 if(!(Test-Path -LiteralPath $target -PathType Leaf)){
  if($Offline){throw "Missing release dependency: $($releaseInput[0]). Run tools/setup-release-deps.ps1 once online."}
  Invoke-WebRequest -Uri $releaseInput[1] -OutFile $target
 }
 if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $releaseInput[2]){throw "Release dependency checksum mismatch: $($releaseInput[0])"}
}
Write-Host 'Pinned release licenses and Doorstop source verified (ignored .deps).'
