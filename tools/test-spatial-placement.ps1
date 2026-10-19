[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sources = @('DioramaPlacementState','DioramaScaleState') | ForEach-Object {
    (Get-Content (Join-Path $root "src/QVVR/$_.cs") -Raw).Replace('using UnityEngine;', '').Replace('using System;', '')
}
# Headless Unity math doubles using .NET's quaternion/vector primitives. Execute
# actual production placement/SpatialMath sources; never open Unity or VR.
$fixture = @'
namespace UnityEngine {
 public struct Vector2 {
  public float x,y; public Vector2(float x,float y){this.x=x;this.y=y;}
  public float magnitude{get{return (float)System.Math.Sqrt(x*x+y*y);}}
  public float sqrMagnitude{get{return x*x+y*y;}}
  public static Vector2 zero{get{return new Vector2(0,0);}}
 }
 public struct Vector3 {
  public float x,y,z; public Vector3(float x,float y,float z){this.x=x;this.y=y;this.z=z;}
  public float sqrMagnitude{get{return x*x+y*y+z*z;}}
  public float magnitude{get{return (float)System.Math.Sqrt(sqrMagnitude);}}
  public Vector3 normalized{get{return this/magnitude;}}
  public static Vector3 up{get{return new Vector3(0,1,0);}}
  public static Vector3 right{get{return new Vector3(1,0,0);}}
  public static Vector3 forward{get{return new Vector3(0,0,1);}}
  public static Vector3 zero{get{return new Vector3(0,0,0);}}
  public static Vector3 operator+(Vector3 a,Vector3 b){return new Vector3(a.x+b.x,a.y+b.y,a.z+b.z);}
  public static Vector3 operator-(Vector3 a,Vector3 b){return new Vector3(a.x-b.x,a.y-b.y,a.z-b.z);}
  public static Vector3 operator*(Vector3 a,float b){return new Vector3(a.x*b,a.y*b,a.z*b);}
  public static Vector3 operator/(Vector3 a,float b){return a*(1f/b);}
  public static float Dot(Vector3 a,Vector3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
  public static Vector3 Cross(Vector3 a,Vector3 b){return new Vector3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x);}
 }
 public struct Quaternion {
  public float x,y,z,w; public Quaternion(float x,float y,float z,float w){this.x=x;this.y=y;this.z=z;this.w=w;}
  private System.Numerics.Quaternion N(){return new System.Numerics.Quaternion(x,y,z,w);}
  private static Quaternion U(System.Numerics.Quaternion q){return new Quaternion(q.X,q.Y,q.Z,q.W);}
  public static Quaternion identity{get{return new Quaternion(0,0,0,1);}}
  public static Quaternion Inverse(Quaternion q){return U(System.Numerics.Quaternion.Inverse(q.N()));}
  public static float Dot(Quaternion a,Quaternion b){return System.Numerics.Quaternion.Dot(a.N(),b.N());}
  public static Quaternion Lerp(Quaternion a,Quaternion b,float t){return U(System.Numerics.Quaternion.Lerp(a.N(),b.N(),t));}
  public static Quaternion Slerp(Quaternion a,Quaternion b,float t){return U(System.Numerics.Quaternion.Slerp(a.N(),b.N(),t));}
  public static Quaternion SlerpUnclamped(Quaternion a,Quaternion b,float t){return Slerp(a,b,t);}
  public static float Angle(Quaternion a,Quaternion b){return 2f*(float)System.Math.Acos(System.Math.Min(1f,System.Math.Abs(System.Numerics.Quaternion.Dot(a.N(),b.N()))))*180f/(float)System.Math.PI;}
  public static Quaternion AngleAxis(float a,Vector3 v){return U(System.Numerics.Quaternion.CreateFromAxisAngle(new System.Numerics.Vector3(v.x,v.y,v.z),a*(float)System.Math.PI/180));}
  public static Quaternion operator*(Quaternion a,Quaternion b){return U(a.N()*b.N());}
  public static Vector3 operator*(Quaternion q,Vector3 v){var r=System.Numerics.Vector3.Transform(new System.Numerics.Vector3(v.x,v.y,v.z),q.N());return new Vector3(r.X,r.Y,r.Z);}
  public static Quaternion LookRotation(Vector3 f,Vector3 u){
   f=f.normalized;var r=Vector3.Cross(u,f).normalized;u=Vector3.Cross(f,r);
   var m=new System.Numerics.Matrix4x4(r.x,r.y,r.z,0,u.x,u.y,u.z,0,f.x,f.y,f.z,0,0,0,0,1);
   return U(System.Numerics.Quaternion.CreateFromRotationMatrix(m));
  }
 }
 public static class Mathf {
  public static float Max(float a,float b){return System.Math.Max(a,b);}
  public static float Abs(float x){return System.Math.Abs(x);}
  public static float Sqrt(float x){return (float)System.Math.Sqrt(x);}
  public static float Clamp(float x,float a,float b){return System.Math.Max(a,System.Math.Min(b,x));}
  public static bool Approximately(float a,float b){return System.Math.Abs(a-b)<.000001f;}
 }
}
namespace QVVR {
 public static class SpatialTests {
  static int checks;
  static void Check(bool value,string message){checks++;if(!value)throw new System.Exception(message);}
  static bool Near(float a,float b){return System.Math.Abs(a-b)<.00015f;}
  static bool Near(Vector3 a,Vector3 b){return (a-b).magnitude<.00015f;}
  public static int Run(){
   var identity=Quaternion.identity;
   var state=new DioramaPlacementState();
   state.Place(new Vector3(0,0,2),identity,.05f);
   var left=new Vector3(-.2f,0,0);var right=new Vector3(.2f,0,0);
   state.Update(true,true,left,identity,right,identity);
   Check(state.Active&&Near(state.Position,new Vector3(0,0,2)),"Activation must not snap.");
   var delta=new Vector3(1,.4f,-.2f);
   state.Update(true,true,left+delta,identity,right+delta,identity);
   Check(Near(state.Position,new Vector3(0,0,2)+delta),"Both hands translating together must move naturally 1:1 in xyz.");
   Check(Near(state.Scale,.05f),"Translation must not resize.");
   state.Stop();state.Saved();Check(!state.Dirty,"Sparse save clears dirty state.");
   state.Place(new Vector3(0,0,2),identity,.05f);
   state.Update(true,true,left,identity,right,identity);
   state.Update(true,true,left*2,identity,right*2,identity);
   Check(Near(state.Scale,.1f)&&Near(state.Position,new Vector3(0,0,4)),"Scale about hand midpoint must preserve grasped transform, not fake camera zoom.");
   state.Stop();
   foreach(var axis in new Vector3[]{Vector3.right,Vector3.up,Vector3.forward}) {
    state.Place(new Vector3(0,0,2),identity,.05f);
    state.Update(true,true,left,identity,right,identity);
    var q=Quaternion.AngleAxis(35,axis);
    state.Update(true,true,q*left,q,q*right,q);
    Check(Near(state.Rotation*Vector3.forward,q*Vector3.forward),"Rotate hands around each physical axis: diorama uses same axis.");
    Check(Near(state.Rotation*Vector3.up,q*Vector3.up),"Controller twist must rotate even along hand-baseline axis.");
    Check(Near(state.Position,q*new Vector3(0,0,2)),"Rotation uses shared grab pivot.");
    state.Stop();
    state.Place(new Vector3(0,0,2),identity,.05f);
    state.Update(true,true,left,identity,right,identity);
    state.Update(true,true,left,q,right,q);
    Check(Near(state.Rotation*Vector3.forward,q*Vector3.forward)&&Near(state.Rotation*Vector3.up,q*Vector3.up),"Common wrist rotation on every axis works with stationary hand centers.");
    state.Stop();
   }
   state.Place(new Vector3(0,0,2),identity,.05f);
   state.Update(true,true,left,identity,right,identity);
   var compound=Quaternion.AngleAxis(50,Vector3.up);
   state.Update(true,true,compound*(left*2)+delta,compound,compound*(right*2)+delta,compound);
   Check(Near(state.Position,delta+compound*new Vector3(0,0,4))&&Near(state.Scale,.1f),"Combined translation+rotation+scale must compose as one similarity transform.");
   var frozen=state.Position;state.Update(false,true,right,identity,left,identity);
   Check(!state.Active&&Near(state.Position,frozen),"Release freezes placement.");
   state.Update(true,true,new Vector3(-10,3,1),identity,new Vector3(-9,3,1),identity);
   Check(Near(state.Position,frozen),"Regrab anchors at current pose.");
   state.Update(true,false,left,identity,right,identity);Check(!state.Active&&Near(state.Position,frozen),"Tracking loss freezes state.");
   state.Update(true,true,Vector3.zero,identity,Vector3.zero,identity);Check(!state.Active,"Coincident hands rejected.");
   state.Update(true,true,new Vector3(float.NaN,0,0),identity,right,identity);Check(!state.Active,"Invalid position rejected.");
   state.Update(true,true,left,new Quaternion(0,0,0,0),right,identity);Check(!state.Active,"Invalid hand orientation rejected.");
   state.Update(true,true,left,identity,right,Quaternion.AngleAxis(180,Vector3.up));Check(!state.Active,"Opposing wrist orientations freeze instead of causing an averaging flip.");
   var yaw=Quaternion.AngleAxis(75,Vector3.up);
   var tilted=yaw*Quaternion.AngleAxis(45,Vector3.right)*Quaternion.AngleAxis(35,Vector3.forward);
   var upright=SpatialMath.Upright(tilted,identity);
   Check(Near(upright*Vector3.up,Vector3.up),"Panels never inherit physical pitch or roll.");
   Check(Near(upright*Vector3.forward,yaw*Vector3.forward),"Panel horizontal heading remains responsive.");
   Check(Near(SpatialMath.Upright(Quaternion.AngleAxis(90,Vector3.right),yaw)*Vector3.forward,yaw*Vector3.forward),"Vertical head gaze uses stable last yaw.");
   foreach(float heading in new float[]{0,90,180,270}) {
    var h=Quaternion.AngleAxis(heading,Vector3.up);
    var objectRot=Quaternion.AngleAxis(40,Vector3.up)*Quaternion.AngleAxis(25,Vector3.right);
    var source=Quaternion.AngleAxis(-35,Vector3.up);
    var mapped=SpatialMath.Movement(new Vector2(0,1),objectRot,h,source);
    var actualGame=source*new Vector3(mapped.x,0,mapped.y);
    var expected=Quaternion.Inverse(objectRot)*(h*Vector3.forward);expected.y=0;expected=expected.normalized;
    Check(Near(actualGame,expected),"Heading-dependent movement cancels QV's source-camera yaw at every side.");
    Check(Near(mapped.magnitude,1),"Movement magnitude preserved under tilt.");
    var jump=SpatialMath.Movement(new Vector2(0,1),objectRot,h,identity);
    Check(Near(new Vector3(jump.x,0,jump.y),expected),"CharacterJump uses direct world-grid axes, without extra source-camera yaw cancellation.");
   }
   var input=SpatialMath.Movement(new Vector2(.2f,.3f),identity,identity,identity);
   Check(Near(input.x,.2f)&&Near(input.y,.3f),"Analogue magnitude must not be boosted.");
   Check(Near(SpatialMath.Movement(Vector2.zero,identity,yaw,identity).magnitude,0),"Idle input remains idle.");
   var offset=SpatialMath.VisibleOffset(new Vector3(100,-100,-5),.8f,.8f);
   Check(offset.z>=.35f&&System.Math.Abs(offset.x)<=offset.z*.35f&&offset.y>=-offset.z*.5f,"Offscreen old layout corrected to visible front cone.");
   var closer=SpatialMath.VisibleOffset(new Vector3(.2f,-.2f,.65f),.9f,.9f);
   Check(Near(closer.z,(float)System.Math.Sqrt(1.0125f)+.08f)&&Near(closer.x,.2f)&&Near(closer.y,-.2f),"Short saved reach uses an 8cm bounding-sphere margin, preserving valid lateral/vertical placement.");
   var entry=SpatialMath.VisibleOffset(SpatialMath.DefaultOffset,.8f,.8f);
   Check(Near(entry,new Vector3(0,-.45f,1.2f)),"Default diorama center is closer and below the eyes, without visibility guard pushing it up.");
   Check(SpatialMath.LegacyDefaultOffset(new Vector3(0,-.35f,1.6f))&&SpatialMath.LegacyDefaultOffset(new Vector3(0,-.35f,2)),"Recognize both old untouched first-entry defaults.");
   Check(!SpatialMath.LegacyDefaultOffset(new Vector3(.1f,-.35f,1.6f))&&!SpatialMath.LegacyDefaultOffset(new Vector3(0,-.5f,1.6f)),"Custom lateral/height settings must not be migrated.");
   Check(!SpatialMath.LegacyDefaultOffset(new Vector3(float.NaN,0,0)),"Invalid values are not mistaken for untouched defaults.");
   Check(Near(SpatialMath.VisibleOffset(Vector3.zero,.05f,.05f).z,.35f),"Tiny diorama is no longer pushed back to 1m.");
   var measured=SpatialMath.VisibleOffset(new Vector3(0,-.1f,.3f),.3f,.6f);
   Check(measured.z>.45f&&measured.z<.55f,"Small saved cylinder can spawn around half a meter, outside its bounding sphere.");
   var anchor=new Vector3(.2f,-.1f,1f);var origin=new Vector3(120,4,-80);
   var rotation=Quaternion.AngleAxis(37,Vector3.up)*Quaternion.AngleAxis(22,Vector3.right);
   var inverse=Quaternion.Inverse(rotation);var eye=new Vector3(.1f,1.6f,.3f);
   foreach(float eyeUnits in new float[]{1,70,1000}){
    var world=SpatialMath.EyePosition(origin,anchor,inverse,eye,eyeUnits);
    Check(Near(anchor+rotation*(world-origin)/eyeUnits,eye),"Direct eye mapping round-trips tracking at tiny world sizes.");
    var leftEye=eye+new Vector3(-.032f,0,0);var rightEye=eye+new Vector3(.032f,0,0);
    var leftWorld=SpatialMath.EyePosition(origin,anchor,inverse,leftEye,eyeUnits);
    var rightWorld=SpatialMath.EyePosition(origin,anchor,inverse,rightEye,eyeUnits);
    Check(Near((rightWorld-leftWorld).magnitude/eyeUnits,.064f),"Stereo IPD stays physically 1:1 at every diorama scale.");
    var movedOrigin=origin+new Vector3(.2f,0,0);
    Check(Near(SpatialMath.EyePosition(movedOrigin,anchor,inverse,eye,eyeUnits)-world,new Vector3(.2f,0,0)),"Character follow translates the eye and cylinder origin coherently.");
   }
   var far=SpatialMath.VisibleOffset(new Vector3(.1f,-.2f,4),.8f,.8f);
   Check(Near(far.z,4)&&Near(far.x,.1f)&&Near(far.y,-.2f),"Do not shorten intentionally distant saved layouts.");
   var tall=SpatialMath.VisibleOffset(Vector3.zero,1,4);
   Check(tall.z>(float)System.Math.Sqrt(5),"Tall/tilted dioramas retain bounding-sphere clearance.");
   var invalid=SpatialMath.VisibleOffset(new Vector3(float.NaN,0,0),float.NaN,float.NaN);
   Check(Near(invalid.z,1.2f)&&Near(invalid.y,-.45f),"Invalid entry values recover to the new finite lower/closer default.");
   Check(Near(SpatialMath.EntryScale(40,1.6f,1),.04f),"First huge level fitted to reasonable physical size.");
   Check(Near(80*SpatialMath.EntryScale(80,.8f,2)/2,.8f),"Next level reuses saved physical size despite changed bounds/units.");
   Check(SpatialMath.EntryScale(40,100,1)<=.1f,"Entry fit clamps huge saved preference.");
   Check(Near(SpatialMath.EntryGain(.85f,1),.85f)&&Near(SpatialMath.EntryGain(.8f,1),.8f),"New entry size/distance gains.");
   Check(Near(SpatialMath.EntryGain(float.NaN,.85f),.85f)&&Near(SpatialMath.EntryGain(float.PositiveInfinity,.8f),.8f),"Invalid gains use safe defaults.");
   Check(Near(SpatialMath.EntryGain(0,1),.25f)&&Near(SpatialMath.EntryGain(10,1),1.5f),"Entry gains are bounded away from zero.");
   float savedSize=1.6f,savedDepth=2f;
   for(int i=0;i<100;i++){
    float actualSize=savedSize*.85f,actualDepth=savedDepth*.8f;
    Check(Near(actualSize,1.36f)&&Near(actualDepth,1.6f),"Repeated entry/save must not compound shrink or forward motion.");
    savedSize=SpatialMath.EntryBase(actualSize,.85f);savedDepth=SpatialMath.EntryBase(actualDepth,.8f);
   }
   Check(Near(SpatialMath.EntryBase(2,.85f)*.85f,2)&&Near(SpatialMath.EntryBase(1.5f,.8f)*.8f,1.5f),"Hand-adjusted size/depth survives next entry exactly.");
   // Inverse camera transform must leave world points fixed while head walks.
   state.Place(new Vector3(1,-.3f,2),Quaternion.AngleAxis(45,Vector3.up),.04f);
   var center=new Vector3(20,5,-10);float units=1/state.Scale;
   foreach(var head in new Vector3[]{Vector3.zero,new Vector3(1,0,0),new Vector3(-1,.5f,1)}) {
    var gameEye=center+Quaternion.Inverse(state.Rotation)*(head-state.Position)*units;
    var observed=head+state.Rotation*((center-gameEye)/units);
    Check(Near(observed,state.Position),"Moving head must not move placed cylinder center.");
   }
   state.Stop();state.Place(new Vector3(0,0,2),identity,.05f);
   state.Update(true,true,left,identity,right,identity,1.15f,1.1f);
   state.Update(true,true,left+delta,identity,right+delta,identity,3f,3f);
   Check(Near(state.Position,new Vector3(0,0,2)+delta*1.15f),"Translation gain is 15% faster and stays latched while held.");
   Check(Near(state.Scale,.05f),"Sensitivity does not change resize.");
   state.Stop();state.Place(new Vector3(0,0,2),identity,.05f);
   state.Update(true,true,left,identity,right,identity,1.15f,1.1f);
   var turn=Quaternion.AngleAxis(30,Vector3.up);
   state.Update(true,true,turn*left,turn,turn*right,turn,1.15f,1.1f);
   var faster=Quaternion.AngleAxis(33,Vector3.up);
   Check(Near(state.Rotation*Vector3.forward,faster*Vector3.forward),"Rotation gain is 10% faster, not doubled between wrists/baseline.");
   Check(Near(state.Position,faster*new Vector3(0,0,2)),"Amplified rotation retains the shared grab pivot.");
   Check(Near(SpatialMath.Gain(float.NaN),1)&&Near(SpatialMath.Gain(100),3)&&Near(SpatialMath.Gain(-1),.25f),"Invalid sensitivity values are safe.");
   state.Stop();state.Place(new Vector3(0,-.45f,2),identity,.05f);state.Saved();
   state.MoveStick(new Vector2(1,1),Vector3.zero,.05f,60,.6f);
   Check(Near(state.Position,new Vector3(0,-.45f,1.97f)),"Forward brings the diorama closer at constant height.");
   Check(Near(state.Rotation*Vector3.forward,Quaternion.AngleAxis(3,Vector3.up)*Vector3.forward),"Right turns about tracking-space vertical without orbiting the center.");
   Check(Near(state.Scale,.05f)&&state.Dirty&&!state.Active,"Stick preserves size and marks placement for sparse save.");
   state.MoveStick(new Vector2(-1,-1),Vector3.zero,.05f,60,.6f);
   Check(Near(state.Position,new Vector3(0,-.45f,2))&&Near(state.Rotation*Vector3.forward,Vector3.forward),"Opposite input reverses rotation and distance.");
   state.Place(new Vector3(2,-.45f,0),identity,.005f);
   state.MoveStick(new Vector2(0,1),Vector3.zero,.05f,60,.6f);
   Check(Near(state.Position,new Vector3(1.97f,-.45f,0)),"Approach follows the viewer-to-diorama direction even after walking around.");
   Check(Near(state.Scale,.005f),"Physical stick translation is independent of scale.");
   state.Place(new Vector3(0,-.45f,.26f),identity,.05f);
   state.MoveStick(new Vector2(0,1),Vector3.zero,.05f,60,3);
   Check(Near(state.Position.z,.25f),"Approach stops at minimum horizontal distance, never passes through the viewer.");
   state.Place(new Vector3(0,-.45f,9.99f),identity,.05f);
   state.MoveStick(new Vector2(0,-1),Vector3.zero,.05f,60,3);
   Check(Near(state.Position.z,10),"Retreat has a bounded physical range.");
   state.Place(new Vector3(0,0,15),identity,.05f);
   state.MoveStick(new Vector2(0,1),Vector3.zero,.05f,60,.6f);
   Check(Near(state.Position.z,14.97f),"A far two-hand placement returns gradually, never snaps to the stick limit.");
   state.Place(new Vector3(0,0,.1f),identity,.05f);
   state.MoveStick(new Vector2(0,-1),Vector3.zero,.05f,60,.6f);
   Check(Near(state.Position.z,.13f),"A near two-hand placement can retreat without snapping.");
   state.Place(new Vector3(0,0,2),identity,.05f);
   state.MoveStick(new Vector2(0,1),Vector3.zero,10,60,.6f);
   Check(Near(state.Position.z,1.97f),"A stall cannot cause a huge placement step.");
   var beforeStick=state.Position;state.Saved();
   state.MoveStick(Vector2.zero,Vector3.zero,.05f,60,.6f);
   Check(!state.Dirty&&Near(state.Position,beforeStick),"Neutral input leaves position and persistence state untouched.");
   state.MoveStick(new Vector2(float.NaN,1),Vector3.zero,.05f,60,.6f);
   state.MoveStick(new Vector2(0,1),Vector3.zero,float.PositiveInfinity,60,.6f);
   Check(!state.Dirty&&Near(state.Position,beforeStick),"Invalid input/timing cannot corrupt placement.");
   state.Update(true,true,left,identity,right,identity);
   state.MoveStick(new Vector2(1,1),Vector3.zero,.05f,60,.6f);
   Check(Near(state.Position,beforeStick),"An active two-hand grab cannot be overwritten by stick placement.");
   state.Reset();Check(!state.Valid,"Level reset triggers restored entry layout.");
   return checks;
  }
 }
}
'@
Add-Type -TypeDefinition ('using System; using UnityEngine;' + $fixture + ($sources -join "`n"))
$count = [QVVR.SpatialTests]::Run()
Write-Host "Natural placement / visible entry / viewer input / upright panels: $count assertions passed."
