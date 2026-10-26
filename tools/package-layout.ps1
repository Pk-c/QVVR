# Shared exact archive inventory. Never recursively copy a developer's loader tree.
function Get-QvvrPackageFiles([string]$Root,[string]$Configuration='Release') {
 $files=[ordered]@{}
 foreach($name in @('0Harmony.dll','0Harmony20.dll','BepInEx.dll','BepInEx.Harmony.dll','BepInEx.Preloader.dll','HarmonyXInterop.dll','Mono.Cecil.dll','Mono.Cecil.Mdb.dll','Mono.Cecil.Pdb.dll','Mono.Cecil.Rocks.dll','MonoMod.RuntimeDetour.dll','MonoMod.Utils.dll')){
  $files["BepInEx/core/$name"]=Join-Path $Root ".deps/bepinex-5.4.23.5/BepInEx/core/$name"
 }
 foreach($name in @('winhttp.dll','doorstop_config.ini','.doorstop_version')){$files[$name]=Join-Path $Root ".deps/bepinex-5.4.23.5/$name"}
 $prefix='BepInEx/plugins/QVVR'
 $files["$prefix/QVVR.dll"]=Join-Path $Root "src/QVVR/bin/$Configuration/netstandard2.0/QVVR.dll"
 $files["$prefix/QVVR.Native.dll"]=Join-Path $Root "src/QVVR.Native/bin/$Configuration/QVVR.Native.dll"
 $files["$prefix/openvr_api.dll"]=Join-Path $Root '.deps/openvr-2.15.6/bin/win64/openvr_api.dll'
 $files["$prefix/openxr_loader.dll"]=Join-Path $Root '.deps/openxr/sdk/native/x64/bin/openxr_loader.dll'
 foreach($name in @('BepInEx','UnityDoorstop','HarmonyX','Harmony','BepInEx.Harmony','MonoMod','Mono.Cecil')){
  $files["$prefix/licenses/$name.txt"]=Join-Path $Root ".deps/release-licenses/$name.txt"
 }
 $files["$prefix/licenses/source/UnityDoorstop-v4.5.0-source.zip"]=Join-Path $Root '.deps/release-licenses/UnityDoorstop-v4.5.0-source.zip'
 $files["$prefix/licenses/OpenVR.txt"]=Join-Path $Root '.deps/openvr-2.15.6/LICENSE'
 $files["$prefix/licenses/OpenXR.txt"]=Join-Path $Root '.deps/openxr/LICENSE.txt'
 $files["$prefix/licenses/DirectX-Headers.txt"]=Join-Path $Root '.deps/directx-headers/LICENSE-Headers.txt'
 $files["$prefix/licenses/DirectX-Hash.txt"]=Join-Path $Root '.deps/directx-headers/LICENSE-Hash.txt'
 $files['BepInEx/config/dev.qvvr.prototype.cfg']=Join-Path $Root 'package-assets/dev.qvvr.prototype.cfg'
 foreach($name in @('README.txt','RELEASE-NOTES.txt','QVVR-THIRD-PARTY-NOTICES.txt','uninstall.bat','uninstall.ps1','qvvr-launch-options.txt')){$files[$name]=Join-Path $Root "package-assets/$name"}
 $files['LICENSE.txt']=Join-Path $Root 'LICENSE'
 return $files
}

# Release ZIP files outside PC/ (the game overlay): Frame USB installer + guide.
function Get-QvvrReleaseExtraFiles([string]$Root) {
 $files=[ordered]@{}
 $files['README.txt']=Join-Path $Root 'package-assets/RELEASE-README.txt'
 foreach($name in @('QVVR-Frame-Setup.bat','QVVR-Frame-Setup.ps1','QVVR-Frame-Setup.txt','QVVR-Frame-Defaults.cfg')){$files["SteamFrame/$name"]=Join-Path $Root "package-assets/$name"}
 return $files
}
