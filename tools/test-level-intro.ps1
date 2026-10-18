[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Get-Content (Join-Path $root 'src/QVVR/FirstLevelIntroCompatibility.cs') -Raw
# Pure production policy only; no game/Unity/native code is loaded or executed.
$policy=$source.Substring($source.IndexOf('    internal static class LevelIntroPolicy'),$source.IndexOf('    internal sealed class FirstLevelIntroCompatibility')-$source.IndexOf('    internal static class LevelIntroPolicy'))
$fixture=@'
 public static class LevelIntroTests {
  static int checks;static void Check(bool ok,string text){checks++;if(!ok)throw new System.Exception(text);}
  public static int Run(){
   Check(LevelIntroPolicy.Scene("1_1"),"Verified first-level timeline scene.");
   foreach(string scene in new string[]{null,"Landing","001_Intro","Opening","1_0","1_2","2_1"})Check(!LevelIntroPolicy.Scene(scene),"No unrelated scene promotion.");
   Check(LevelIntroPolicy.Active(true,true,1,0,40,false),"Already playing when injection arrives.");
   Check(LevelIntroPolicy.Active(true,true,0,5,40,true),"A paused intro remains flat after a start event.");
   Check(LevelIntroPolicy.Active(true,true,0,5,40,false),"Late injection during an in-progress paused intro.");
   Check(!LevelIntroPolicy.Active(true,false,1,5,40,true),"Hidden/stopped director ends flat mode.");
   Check(!LevelIntroPolicy.Active(false,true,1,5,40,true),"Callbacks in other levels do not affect rendering.");
   Check(!LevelIntroPolicy.Active(true,true,0,0,40,false),"Not-started/already-watched intro stays stereo.");
   Check(!LevelIntroPolicy.Active(true,true,0,40,40,false),"Natural completion remains stereo.");
   Check(!LevelIntroPolicy.Active(true,true,0,double.NaN,40,false),"Invalid paused timeline is not promoted.");
   Check(!LevelIntroPolicy.Active(true,true,2,5,40,true),"Unknown playback states fail safe.");
   return checks;
  }
 }
'@
Add-Type -TypeDefinition ('namespace QVVR {'+$policy+$fixture+'}')
$count=[QVVR.LevelIntroTests]::Run()
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
 $renderer=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
 foreach($name in @('LateUpdate','UpdateRig','CaptureUi','PositionPanels','MapPlayerMovement','get_CanGrabWorld')) {
  $method=$renderer.Methods | Where-Object Name -eq $name
  if(-not ($method.Body.Instructions | Where-Object {
    ($_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'levelIntroFlat') -or
    ($_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'get_FixedCinemaPanel')
   })){throw "Missing cinematic guard: $name"}
 }
 $rig=$renderer.Methods | Where-Object Name -eq 'UpdateRig'
 $flat=$rig.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'get_FixedCinemaPanel' } | Select-Object -First 1
 $place=$rig.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'Place' } | Select-Object -First 1
 if($flat.Offset -ge $place.Offset){throw 'Cinematic must bypass gameplay placement.'}
 $transition=$renderer.Methods | Where-Object Name -eq 'SetLevelIntro'
 foreach($call in @('Reset','SavePlacementSettings','RequireGripRelease','SetSourceCamera','RedirectOverlayCanvases')) {
  if(-not ($transition.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq $call })){throw "Missing transition cleanup: $call"}
 }
 $compat=$assembly.MainModule.Types | Where-Object Name -eq 'FirstLevelIntroCompatibility'
 foreach($name in @('Started','Stopped','Refresh','Reset','Release')){if(-not ($compat.Methods | Where-Object Name -eq $name)){throw "Missing intro lifecycle method: $name"}}
}finally{$assembly.Dispose()}
if($GameDir){
 $game=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $GameDir 'QV_Data/Managed/Assembly-CSharp.dll'))
 try {
  $manager=$game.MainModule.Types | Where-Object Name -eq 'GameManager'
  $director=$manager.Fields | Where-Object Name -eq '_playableDirector'
  if($director.FieldType.FullName -ne 'UnityEngine.Playables.PlayableDirector'){throw 'Verified timeline reference unavailable.'}
  if(-not ($manager.Fields | Where-Object { $_.Name -eq 'mainCam' -and $_.FieldType.FullName -eq 'UnityEngine.Camera' })){throw 'Original gameplay camera reference unavailable.'}
  foreach($name in @('SetDirector','OnEndDirector')){if(-not ($manager.Methods | Where-Object { $_.Name -eq $name -and $_.HasBody })){throw "Missing game entry point: $name"}}
 }finally{$game.Dispose()}
}
Write-Host "First-level intro: $count policy assertions and compiled routing/lifecycle guards passed. No game/VR session started."
