[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$anchor=(Get-Content (Join-Path $root 'src/QVVR/FixedPanelAnchor.cs') -Raw).Replace('using UnityEngine;','')
$buttons=Get-Content (Join-Path $root 'src/QVVR/ControllerButtonPolicy.cs') -Raw
$rendererSource=Get-Content (Join-Path $root 'src/QVVR/OpenVrManager.cs') -Raw
$start=$rendererSource.IndexOf('        private static void RenderPanelOverlay(')
$end=$rendererSource.IndexOf('        private void ProfileMark(', $start)
$overlay=$rendererSource.Substring($start,$end-$start).Replace('private static void','public static void')
# Execute actual production code with headless API doubles; no game/VR session.
$fixture=@'
namespace UnityEngine {
 public struct Vector3 { public float x,y,z; public Vector3(float x,float y,float z){this.x=x;this.y=y;this.z=z;} }
 public struct Quaternion { public float x,y,z,w; public Quaternion(float x,float y,float z,float w){this.x=x;this.y=y;this.z=z;this.w=w;} }
 public enum CameraClearFlags { SolidColor=2, Depth=3, Nothing=4 }
 public enum DepthTextureMode { None=0, Depth=1 }
 public class Camera {
  public CameraClearFlags clearFlags; public int cullingMask; public DepthTextureMode depthTextureMode;
  public bool useOcclusionCulling, DepthOccludesHud=true, HudVisible; public int Renders;
  public float R=.2f,G=.3f,B=.4f,A=.5f;
  public void Render(){Renders++;if(clearFlags==CameraClearFlags.Depth)DepthOccludesHud=false;
   if(clearFlags==CameraClearFlags.SolidColor)R=G=B=A=0;HudVisible=!DepthOccludesHud;}
 }
}
namespace QVVR {
 internal static class SpatialMath {
  static bool Finite(float v){return !float.IsNaN(v)&&!float.IsInfinity(v);}
  internal static bool Finite(UnityEngine.Vector3 v){return Finite(v.x)&&Finite(v.y)&&Finite(v.z);}
  internal static bool Finite(UnityEngine.Quaternion q){return Finite(q.x)&&Finite(q.y)&&Finite(q.z)&&Finite(q.w)&&q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w>.000001f;}
 }
 public static class CorrectionTests {
  static int checks;static void Check(bool ok,string message){checks++;if(!ok)throw new System.Exception(message);}
  static uint Buttons(ulong left,float lt,ulong right,float rt,bool game){return ControllerButtonPolicy.Buttons(ControllerButtonPolicy.Physical(left,lt,right,rt),ControllerButtonPolicy.Defaults(new ControllerBindings{Layout=ControllerLayout.FaceButtons,MovementStick=ControllerStick.Left,DioramaStick=ControllerStick.Right,DioramaTurnSpeed=60,DioramaMoveSpeed=.6f,DioramaDeadZone=.4f,MenuStick=ControllerStick.Either,Exclusive=true}),game);}
  public static int Run(){
   var anchor=new FixedPanelAnchor();
   anchor.Latch(new UnityEngine.Vector3(float.NaN,0,0),new UnityEngine.Quaternion(0,0,0,1));Check(!anchor.Valid,"Invalid tracking never latches.");
   anchor.Latch(new UnityEngine.Vector3(1,2,3),new UnityEngine.Quaternion(0,.5f,0,.866f));Check(anchor.Valid,"First valid pose latches.");
   for(int i=0;i<200;i++)anchor.Latch(new UnityEngine.Vector3(i,i+1,i+2),new UnityEngine.Quaternion(0,0,0,1));
   Check(anchor.Position.x==1&&anchor.Position.y==2&&anchor.Position.z==3&&anchor.Rotation.y==.5f,"Head movement cannot move a cinematic anchor.");
   anchor.Reset();Check(!anchor.Valid,"Recenter/scene/intro reset releases anchor.");
   anchor.Latch(new UnityEngine.Vector3(7,8,9),new UnityEngine.Quaternion(0,0,0,1));Check(anchor.Position.x==7,"Reset allows new placement.");
   Check(Buttons(0,0,0,0,true)==0,"Idle gameplay has no buttons.");
   Check(Buttons(0,1,0,1,true)==ControllerButtonPolicy.Load,"Analog trigger chord emits Load, not Dash/Cam.");
   Check(Buttons(1UL<<33,0,1UL<<33,0,true)==ControllerButtonPolicy.Load,"Digital trigger chord also emits Load.");
   Check((Buttons(0,1,0,0,true)&ControllerButtonPolicy.Camera)!=0,"Left trigger emits semantic camera.");
   Check((Buttons(0,0,0,1,true)&ControllerButtonPolicy.Dash)!=0,"Right trigger emits semantic dash.");
   Check((Buttons(0,1,0,1,false)&ControllerButtonPolicy.Confirm)==0,"Menu paging no longer also confirms.");
   Check((Buttons(0,1,(1UL<<7)|(1UL<<1),1,true)&(ControllerButtonPolicy.Primary|ControllerButtonPolicy.Secondary))==768,"A/B remain independent of the trigger chord.");
   Check(Buttons(1UL<<2,0,1UL<<2,0,true)==0,"Grips never emit gameplay commands.");
   Check(Buttons(0,float.NaN,0,float.NaN,true)==0,"Invalid analog state is idle.");
   Check(Buttons(0,.55f,0,.55f,true)==0,"Exact threshold is idle.");
   Check((Buttons(0,0,1UL<<7,0,true)&ControllerButtonPolicy.Primary)!=0,"A retains gameplay primary.");
   Check(ControllerButtonPolicy.ActionMask("L",false,true)==64&&ControllerButtonPolicy.ActionMask("R",false,true)==128,"Actual menu L/R names retain page commands.");
   Check(ControllerButtonPolicy.ActionMask("L",true,true)==0&&ControllerButtonPolicy.ActionMask("R",true,true)==0,"Shoulders have no negative axis action.");
   Check(ControllerButtonPolicy.ActionMask("Pause",false,false)!=ControllerButtonPolicy.ActionMask("Fire2",false,false),"Pause and secondary action are separate.");
   Check(ControllerButtonPolicy.ActionMask("Unknown",false,false)==0,"Unknown actions preserve original game input.");
   var camera=new UnityEngine.Camera{clearFlags=UnityEngine.CameraClearFlags.Nothing,cullingMask=123,
    depthTextureMode=UnityEngine.DepthTextureMode.Depth,useOcclusionCulling=true};
   OverlayFixture.RenderPanelOverlay(camera);
   Check(camera.HudVisible&&camera.Renders==1,"HUD clears scene depth and renders once.");
   Check(camera.R==.2f&&camera.G==.3f&&camera.B==.4f&&camera.A==.5f,"Overlay preserves color/passthrough alpha.");
   Check(camera.cullingMask==unchecked((int)0x80000000),"Only mod panel layer is drawn.");
   Check(camera.depthTextureMode==UnityEngine.DepthTextureMode.None&&!camera.useOcclusionCulling,"No scene depth generation/baked occlusion in HUD pass.");
   return checks;
  }
 }
}
'@
Add-Type -TypeDefinition ('using UnityEngine;'+$anchor+$buttons+$fixture+'namespace QVVR { public static class OverlayFixture { const int PanelMask=1<<31;'+$overlay+'}}')
$count=[QVVR.CorrectionTests]::Run()
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
 $renderer=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
 $order=$renderer.CustomAttributes | Where-Object {$_.AttributeType.Name -eq 'DefaultExecutionOrder'}
 if(!$order -or $order.ConstructorArguments[0].Value -ne 10000){throw 'Rendering must run after game/DynamicBone LateUpdate.'}
 $eye=($renderer.Methods | Where-Object Name -eq 'RenderEye').Body.Instructions
 $overlayCall=$eye | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'RenderPanelOverlay'}
 $resolve=$eye | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'ResolveAntiAliasedSurface'}
 if(@($overlayCall).Count -ne 1 -or $overlayCall.Offset -ge $resolve.Offset){throw 'One overlay must render after world/clip and before MSAA resolve.'}
 $panels=($renderer.Methods | Where-Object Name -eq 'PositionPanels').Body.Instructions
 foreach($call in @('Latch','MultiplyPoint3x4','get_Position','get_Rotation')){
  if(!($panels | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq $call})){throw "Missing fixed panel route: $call"}
 }
 foreach($name in @('SetLevelIntro','Recenter','OnActiveSceneChanged')){
  if(!(($renderer.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'cinemaPanelAnchor'})){throw "Missing anchor reset: $name"}
 }
 $compat=$assembly.MainModule.Types | Where-Object Name -eq 'QvCameraCompatibility'
 $tracking=($renderer.Methods | Where-Object Name -eq 'TrackingEye').Body.Instructions
 foreach($field in @('LeftEye','RightEye')){
  if(!($tracking | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq $field})){throw "Exact runtime eye snapshot missing: $field"}
 }
 $prepareTracking=($renderer.Methods | Where-Object Name -eq 'PrepareTracking').Body.Instructions
 if($prepareTracking | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -in @('leftEyeToHead','rightEyeToHead')}){throw 'Do not reconstruct XR eye poses through inverse head transforms.'}
 if(!($eye | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'EyePosition'})){throw 'Direct physical-space diorama eye mapping missing.'}
 if(!($panels | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'HubPauseDistance'})){throw 'Dedicated hub pause setting not routed into panel placement.'}
 $init=($renderer.Methods | Where-Object Name -eq 'Initialize').Body.Instructions
 if(!($init | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'SceneScale'})){throw 'XR stability cap not applied at texture creation.'}
 $settings=$assembly.MainModule.Types | Where-Object Name -eq 'VrSettingsMenu'
 foreach($name in @('Adjust','RefreshText')){
  if(($settings.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'HubPauseDistance'}){throw "Config-only pause distance must not be exposed: $name"}
 }
 if(!(($settings.Methods | Where-Object Name -eq 'ResetDefaults').Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'HubPauseDistance'})){throw 'Comfort reset must retain the config-only pause distance default.'}
 if(($compat.Methods | Where-Object Name -eq 'Initialize').Body.Instructions | Where-Object {$_.OpCode.Name -eq 'ldstr' -and $_.Operand -eq 'CheckDistance'}){throw 'Do not patch DynamicBone camera-distance decisions.'}
 foreach($name in @('UpdateRig','PositionPanels')){
  if(!(($renderer.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'get_FixedCinemaPanel'})){throw "Opening/level cinema fixed-panel route missing: $name"}
 }
 $rig=($renderer.Methods | Where-Object Name -eq 'UpdateRig').Body.Instructions
 $firstSource=$rig | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'sourceCamera'} | Select-Object -First 1
 $fixedReturn=$rig | Where-Object {$_.OpCode.Name -eq 'ret'} | Select-Object -First 1
 if(!$fixedReturn -or !$firstSource -or $fixedReturn.Offset -ge $firstSource.Offset){throw 'Fixed cinema rig must return before reading the animated source camera.'}
 foreach($name in @('Initialize','OnActiveSceneChanged')){
  if(!(($renderer.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'IsOpeningScene'})){throw "Opening scene classification missing: $name"}
 }
 if(!($panels | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'HubHudScale'})){throw 'Hub-only scale override missing.'}
 $bridge=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrInputBridge'
 foreach($call in @('Buttons','get_UseGameShoulders')){
  if(!(($bridge.Methods | Where-Object Name -eq 'Update').Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq $call})){throw "Missing runtime shoulder policy: $call"}
 }
}finally{$assembly.Dispose()}
if($GameDir){
 $game=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $GameDir 'QV_Data/Managed/Assembly-CSharp.dll'))
 try {
  $bone=$game.MainModule.Types | Where-Object Name -eq 'DynamicBone'
  foreach($name in @('LateUpdate','CheckDistance')){if(!($bone.Methods | Where-Object {$_.Name -eq $name -and $_.HasBody})){throw "Missing bone hook: $name"}}
  $late=($bone.Methods | Where-Object Name -eq 'LateUpdate').Body.Instructions
  if(@($late | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'UpdateDynamicBones'}).Count -ne 1){throw 'Unexpected bone simulation path.'}
  $joystick=$game.MainModule.Types | Where-Object Name -eq 'VirtualJoystick'
  $update=($joystick.Methods | Where-Object Name -eq 'Update').Body.Instructions
  foreach($action in @('L','R')){if(!($update | Where-Object {$_.OpCode.Name -eq 'ldstr' -and $_.Operand -eq $action})){throw "Missing game action: $action"}}
  if(!($update | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'SetLoadPressed'})){throw 'Verified LB+RB command unavailable.'}
 }finally{$game.Dispose()}
}
Write-Host "Render corrections: $count production-code assertions plus compiled lifecycle/order/input and optional game metadata checks passed. No game/VR session started."
