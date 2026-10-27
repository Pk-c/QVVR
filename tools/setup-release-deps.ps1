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

# Unmodified official ADB (Android SDK Platform Tools r37.0.1) bundled with the
# Frame USB installer so users install nothing. Google only publishes a "latest"
# URL: extract the exact pinned files, refuse anything else.
$adbDirectory=Join-Path $root '.deps/android-platform-tools/platform-tools'
$adbFiles=[ordered]@{
 'adb.exe'='B4A6B455702684652CCCF7B46258B29E653538904359A58FD4931CF3EF286B3F'
 'AdbWinApi.dll'='C1D653030B4BDE65D3E07E4D0B0979E17BE56DF1436CDD15528630F27808050D'
 'AdbWinUsbApi.dll'='0710E894D9B40F71A670C13C694079D564C92C1279DA382CFE4850983AAEBE1B'
 'NOTICE.txt'='38EC8C6F5B7799C223FFEAB1F9E81C2D5FC67B5E56D6424F649630CA1EE1A811'
}
if(@($adbFiles.Keys | Where-Object {!(Test-Path -LiteralPath (Join-Path $adbDirectory $_) -PathType Leaf)}).Count -gt 0){
 if($Offline){throw 'Missing bundled ADB (Android SDK Platform Tools). Run tools/setup-release-deps.ps1 once online.'}
 New-Item -ItemType Directory -Force -Path $adbDirectory | Out-Null
 $download=Join-Path ([IO.Path]::GetTempPath()) ('qvvr-platform-tools-'+[Guid]::NewGuid().ToString('N')+'.zip')
 try {
  Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $download
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive=[IO.Compression.ZipFile]::OpenRead($download)
  try { foreach($name in $adbFiles.Keys){[IO.Compression.ZipFileExtensions]::ExtractToFile($archive.GetEntry("platform-tools/$name"),(Join-Path $adbDirectory $name),$true)} }
  finally { $archive.Dispose() }
 } finally { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
}
foreach($name in $adbFiles.Keys){
 if((Get-FileHash -LiteralPath (Join-Path $adbDirectory $name) -Algorithm SHA256).Hash -ne $adbFiles[$name]){throw "Bundled ADB checksum mismatch: $name. Google may have published a newer platform-tools; review it and update the pins."}
}
Write-Host 'Pinned ADB r37.0.1 (adb.exe, AdbWinApi.dll, AdbWinUsbApi.dll, NOTICE.txt) verified (ignored .deps).'
