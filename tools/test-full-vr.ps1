[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
# Reuse the existing headless Unity vector/quaternion doubles, not the tests.
$spatial=Get-Content (Join-Path $PSScriptRoot 'test-spatial-placement.ps1') -Raw
$fixture=[regex]::Match($spatial,"(?s)\`$fixture = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
if(!$fixture){throw 'Spatial math fixture missing.'}
$math=$fixture.Substring(0,$fixture.IndexOf('namespace QVVR'))
$sources=@('DioramaPlacementState','DioramaScaleState','FullVrViewState') | ForEach-Object {
 (Get-Content (Join-Path $root "src/QVVR/$_.cs") -Raw).Replace('using UnityEngine;','').Replace('using System;','')
}
$tests=@'
namespace QVVR {
 public static class FullVrTests {
  static int checks;
  static void Check(bool condition,string message){checks++;if(!condition)throw new System.Exception(message);}
  static bool Near(Vector3 a,Vector3 b){return (a-b).magnitude<.0002f;}
  public static int Run(){
   var identity=Quaternion.identity;var state=new FullVrViewState();
   var player=new Vector3(20,3,-7);var head=new Vector3(2,1.7f,-4);
   var yaw=Quaternion.AngleAxis(70,Vector3.up);
   state.Place(player,identity,head,yaw);
   Check(state.Valid,"Full VR initializes independently of diorama placement.");
   Check(Near(state.EyePosition(head),player+new Vector3(0,1.6f,-3)),"Starts close behind Q at normal eye height.");
   Check(Near(state.Rotation*(yaw*Vector3.forward),Vector3.forward),"Spawn faces Q regardless of physical heading.");
   var delta=new Vector3(.3f,.2f,-.4f);
   Check(Near(state.EyePosition(head+delta)-state.EyePosition(head),state.Rotation*delta),"Room-scale head translation is exactly 1:1.");
   Check(System.Math.Abs((state.EyePosition(head+new Vector3(.032f,0,0))-state.EyePosition(head-new Vector3(.032f,0,0))).magnitude-.064f)<.0001f,"Stereo IPD is normal scale, not miniature.");
   var before=state.EyePosition(head);
   state.FollowPlayer(player+delta);state.FollowPlayer(player+delta);
   Check(Near(state.EyePosition(head),before+delta),"Follows Q once even with two rig updates per frame.");
   before=state.EyePosition(head);
   state.MoveStick(new Vector2(1,0),head,yaw,.05f,60,.6f);
   Check(Near(state.EyePosition(head),before),"Yaw pivots at the head even after room-scale walking.");
   Check(Near(state.Rotation*(yaw*Vector3.forward),Quaternion.AngleAxis(3,Vector3.up)*Vector3.forward),"Right turns camera right, not world right.");
   before=state.EyePosition(head);
   var forward=state.Rotation*(yaw*Vector3.forward);
   state.MoveStick(new Vector2(0,1),head,yaw,.05f,60,.6f);
   Check(Near(state.EyePosition(head),before+forward*.03f),"Forward travels along viewer's upright heading.");
   state.MoveStick(new Vector2(0,-1),head,yaw,.05f,60,.6f);
   Check(Near(state.EyePosition(head),before),"Back reverses free-camera movement.");
   var movement=SpatialMath.Movement(new Vector2(0,1),Quaternion.Inverse(state.Rotation),yaw,identity);
   Check(Near(new Vector3(movement.x,0,movement.y),forward),"Character movement follows the full VR viewing direction.");
   var sourceYaw=Quaternion.AngleAxis(-35,Vector3.up);
   movement=SpatialMath.Movement(new Vector2(0,1),Quaternion.Inverse(state.Rotation),yaw,sourceYaw);
   Check(Near(sourceYaw*new Vector3(movement.x,0,movement.y),forward),"Cancels game's source-camera yaw exactly once.");
   before=state.Position;
   state.MoveStick(new Vector2(float.NaN,1),head,yaw,.05f,60,.6f);
   state.MoveStick(new Vector2(0,1),head,yaw,float.PositiveInfinity,60,.6f);
   state.MoveStick(new Vector2(0,1),head,yaw,-1,60,.6f);
   state.FollowPlayer(new Vector3(float.NaN,0,0));
   Check(Near(state.Position,before),"Invalid input/player/timing does not poison camera.");
   state.MoveStick(new Vector2(0,1),head,yaw,10,60,.6f);
   Check(Near(state.Position,before+forward*.03f),"Stalls cannot teleport camera.");
   foreach(int hz in new[]{60,72,90,120}){
    state.Place(player,identity,head,identity);before=state.EyePosition(head);
    for(int i=0;i<hz;i++)state.MoveStick(new Vector2(0,1),head,identity,1f/hz,60,.6f);
    Check(Near(state.EyePosition(head),before+Vector3.forward*.6f),"Translation is refresh-rate independent.");
    for(int i=0;i<hz;i++)state.MoveStick(new Vector2(1,0),head,identity,1f/hz,60,.6f);
    Check(Near(state.Rotation*Vector3.forward,Quaternion.AngleAxis(60,Vector3.up)*Vector3.forward),"Yaw is refresh-rate independent.");
   }
   var miniature=new DioramaPlacementState();miniature.Place(new Vector3(1,0,2),yaw,.01f);miniature.Saved();
   state.Place(player,identity,head,identity);state.MoveStick(new Vector2(1,1),head,identity,.05f,60,.6f);state.Reset();
   Check(!state.Valid&&miniature.Valid&&Near(miniature.Position,new Vector3(1,0,2))&&miniature.Scale==.01f&&!miniature.Dirty,"Free VR session/reset cannot overwrite saved miniature placement/scale.");
   state.Place(new Vector3(float.NaN,0,0),identity,head,identity);Check(!state.Valid,"Invalid spawn does not initialize camera.");
   for(int bits=0;bits<16;bits++){
    bool gameplay=(bits&1)!=0,panel=(bits&2)!=0,shader=(bits&4)!=0,diorama=(bits&8)!=0;
    Check(FullVrViewState.ClipWorld(gameplay,panel,shader,diorama)==(bits==13),"Cylinder requires gameplay, world eye, shader and enabled diorama.");
   }
   state.Place(player,identity,head,identity);
   for(int i=0;i<1000;i++){state.MoveStick(new Vector2(1,1),head,identity,.01f,60,.6f);state.FollowPlayer(player);state.EyePosition(head);}
   long allocated=System.GC.GetAllocatedBytesForCurrentThread();
   for(int i=0;i<50000;i++){state.MoveStick(new Vector2(1,1),head,identity,.01f,60,.6f);state.FollowPlayer(player);state.EyePosition(head);}
   Check(System.GC.GetAllocatedBytesForCurrentThread()==allocated,"Warmed full VR state update/eye mapping has zero managed allocations.");
   return checks;
  }
 }
}
'@
Add-Type -TypeDefinition ('using System; using UnityEngine;'+$math+($sources -join "`n")+$tests)
Write-Host "Full-scale VR camera: $([QVVR.FullVrTests]::Run()) assertions passed."

# Verify these policies are actually wired into the shipped renderer, including
# mode-specific input, physical-space panels and both OpenVR/OpenXR eyes.
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
 $renderer=$assembly.MainModule.Types | Where-Object Name -eq OpenVrRenderer
 $required=@{
  UpdateRig=@('OpenVrRenderer.UpdateFullVrRig','FullVrViewState.Reset')
  UpdateFullVrRig=@('FullVrViewState.Place','FullVrViewState.FollowPlayer','FullVrViewState.EyePosition')
  RenderEye=@('FullVrViewState.EyePosition','FullVrViewState.ClipWorld')
  UpdateDioramaStick=@('FullVrViewState.MoveStick','DioramaPlacementState.MoveStick')
  MapPlayerMovement=@('FullVrViewState.get_Rotation','SpatialMath.Movement')
  Recenter=@('FullVrViewState.Reset')
  OnActiveSceneChanged=@('FullVrViewState.Reset')
  PlaceInFront=@('FullVrViewState.Reset')
 }
 foreach($name in $required.Keys){
  $method=$renderer.Methods | Where-Object Name -eq $name
  $calls=@($method.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference]} | ForEach-Object {$_.Operand.DeclaringType.Name+'.'+$_.Operand.Name})
  foreach($call in $required[$name]){if($call -notin $calls){throw "Missing full VR integration: $name -> $call"}}
 }
 foreach($name in @('SavePlacementSettings','get_CanGrabWorld','RenderEye','UpdateDioramaStick','MapPlayerMovement')){
  $method=$renderer.Methods | Where-Object Name -eq $name
  if(!($method.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'DioramaEnabled'})){throw "Missing mode guard: $name"}
 }
} finally {$assembly.Dispose()}
Write-Host 'Full VR renderer integration guards passed; no headset validation implied.'
