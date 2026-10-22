[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = (Get-Content (Join-Path $root 'src/QVVR/DialogHudLayout.cs') -Raw) -replace '(?m)^using .*;\r?\n',''
# Compile the production capture-layout helper against small Unity API doubles.
$fixture = @'
namespace UnityEngine {
 public class Object {
  public bool Destroyed;
  public static bool operator==(Object a,Object b){bool an=ReferenceEquals(a,null)||a.Destroyed,bn=ReferenceEquals(b,null)||b.Destroyed;return an||bn?an==bn:ReferenceEquals(a,b);}
  public static bool operator!=(Object a,Object b){return !(a==b);}public override bool Equals(object v){return ReferenceEquals(this,v);}public override int GetHashCode(){return base.GetHashCode();}
 }
 public struct Vector2 {public float x,y;public Vector2(float x,float y){this.x=x;this.y=y;}public static implicit operator Vector3(Vector2 v){return new Vector3(v.x,v.y,0);}}
 public struct Vector3 {
  public float x,y,z;public Vector3(float x,float y,float z){this.x=x;this.y=y;this.z=z;}
  public static Vector3 operator+(Vector3 a,Vector3 b){return new Vector3(a.x+b.x,a.y+b.y,a.z+b.z);}
  public static Vector3 operator-(Vector3 a,Vector3 b){return new Vector3(a.x-b.x,a.y-b.y,a.z-b.z);}
 }
 public struct Rect {public float x,y,width,height;public Rect(float x,float y,float w,float h){this.x=x;this.y=y;width=w;height=h;}public Vector2 center{get{return new Vector2(x+width*.5f,y+height*.5f);}}}
 public class GameObject {public bool activeInHierarchy=true;}
 public class Component:Object {
  public Transform transform;public CanvasGroup Group;
  public T GetComponent<T>() where T:class{return Group as T;}
 }
 public class Transform:Component {
  public Transform parent;public Vector3 LocalScale=new Vector3(1,1,1);public float Radians;
  public GameObject gameObject=new GameObject();public Vector3 LocalPosition;
  public Transform(){transform=this;}
  Vector3 Rotate(Vector3 v,float r){float c=(float)Math.Cos(r),s=(float)Math.Sin(r);return new Vector3(c*v.x-s*v.y,s*v.x+c*v.y,v.z);}
  public Vector3 TransformVector(Vector3 v){v=Rotate(new Vector3(v.x*LocalScale.x,v.y*LocalScale.y,v.z*LocalScale.z),Radians);return parent==null?v:parent.TransformVector(v);}
  public Vector3 TransformPoint(Vector3 v){v=Rotate(new Vector3(v.x*LocalScale.x,v.y*LocalScale.y,v.z*LocalScale.z),Radians)+LocalPosition;return parent==null?v:parent.TransformPoint(v);}
  public Vector3 InverseTransformVector(Vector3 v){if(parent!=null)v=parent.InverseTransformVector(v);v=Rotate(v,-Radians);return new Vector3(v.x/LocalScale.x,v.y/LocalScale.y,v.z/LocalScale.z);}
  public bool IsChildOf(Transform other){for(Transform t=this;t!=null;t=t.parent)if(t==other)return true;return false;}
 }
 public class RectTransform:Transform {
  public Rect rect;public bool ThrowOnce;
  public Vector3 anchoredPosition3D{get{return LocalPosition;}set{LocalPosition=value;if(ThrowOnce){ThrowOnce=false;throw new InvalidOperationException("setter failed after changing position");}}}
 }
 public class Canvas:Component {
  public bool enabled=true;public Component[] Dialogs=new Component[0];
  public Component[] GetComponentsInChildren(Type type,bool inactive){return Dialogs;}
 }
 public class CanvasGroup:Object {public bool enabled=true;public float alpha=1;}
}
namespace HarmonyLib {public static class AccessTools {public static Type TypeByName(string name){return name=="Dialog"?typeof(QVVR.Dialog):null;}}}
namespace QVVR {
 internal class Dialog:Component {}
 public static class DialogHudTests {
  static int checks;static void Check(bool value,string message){checks++;if(!value)throw new Exception(message);}
  static bool Near(Vector3 a,Vector3 b){var d=a-b;return Math.Abs(d.x)+Math.Abs(d.y)+Math.Abs(d.z)<.001f;}
  public static int Run(){
   var root=new RectTransform{rect=new Rect(-960,-540,1920,1080),LocalPosition=new Vector3(7,3,1),LocalScale=new Vector3(2,2,2),Radians=.35f};
   var parent=new RectTransform{parent=root,rect=new Rect(-800,-400,1600,800),LocalScale=new Vector3(.75f,1.2f,1),LocalPosition=new Vector3(340,-200,0),Radians=-.2f};
   var rect=new RectTransform{parent=parent,rect=new Rect(-120,-80,600,200),LocalPosition=new Vector3(-700,290,0),LocalScale=new Vector3(.7f,.8f,1)};
   var group=new CanvasGroup();var dialog=new Dialog{transform=rect,Group=group};var canvas=new Canvas{transform=root,Dialogs=new Component[]{dialog}};
   var layout=new DialogHudLayout();layout.Initialize();layout.Watch(canvas);var original=rect.anchoredPosition3D;
   Check(layout.HasVisibleDialog,"Visible QV dialogue discovered through the captured canvas.");
   layout.Prepare();Check(Near(rect.TransformPoint(rect.rect.center),root.TransformPoint(root.rect.center)),"Visual center matches the HUD center through nested rotated/scaled parents and off-center pivot.");
   Check(Near(rect.LocalScale,new Vector3(.7f,.8f,1))&&rect.Radians==0,"Do not alter portraits/text size, popup animation scale or rotation.");
   var prepared=rect.anchoredPosition3D;layout.Prepare();Check(Near(prepared,rect.anchoredPosition3D),"Repeated preparation does not compound centering.");
   layout.Restore();Check(Near(rect.anchoredPosition3D,original),"Original actor-projected game layout is restored exactly.");
   layout.Restore();Check(Near(rect.anchoredPosition3D,original),"Restore is idempotent.");
   rect.anchoredPosition3D=new Vector3(900,-300,0);original=rect.anchoredPosition3D;
   layout.Prepare();Check(Near(rect.TransformPoint(rect.rect.center),root.TransformPoint(root.rect.center)),"Game actor movement cannot push the VR box out of view.");layout.Restore();Check(Near(rect.anchoredPosition3D,original),"Game-side position updates survive VR capture.");
   group.alpha=0;Check(!layout.HasVisibleDialog,"Hidden CanvasGroup is not treated as an open dialogue.");layout.Prepare();Check(Near(rect.anchoredPosition3D,original),"Hidden dialogue is not moved or dirtied.");group.alpha=1;
   rect.gameObject.activeInHierarchy=false;Check(!layout.HasVisibleDialog,"Inactive dialogue stays inactive.");rect.gameObject.activeInHierarchy=true;
   canvas.enabled=false;Check(!layout.HasVisibleDialog,"Disabled capture canvas is ignored.");canvas.enabled=true;
   rect.parent=null;Check(!layout.HasVisibleDialog,"A dialogue reparented outside its capture root is ignored.");rect.parent=parent;
   bool failed=false;rect.ThrowOnce=true;try{layout.Prepare();}catch(InvalidOperationException){failed=true;}finally{layout.Restore();}
   Check(failed&&Near(rect.anchoredPosition3D,original),"Partial setup errors still restore the original layout.");
   layout.Prepare();try{throw new InvalidOperationException();}catch(InvalidOperationException){}finally{layout.Restore();}
   Check(Near(rect.anchoredPosition3D,original),"Render failure leaves the game layout intact.");
   layout.Prepare();layout.BeginScan();Check(!layout.HasVisibleDialog&&Near(rect.anchoredPosition3D,original),"Rescan restores pending capture state and releases stale entries.");
   layout.Watch(canvas);rect.Destroyed=true;layout.Prepare();layout.Restore();Check(!layout.HasVisibleDialog,"Destroyed dialogue is safe between scans.");rect.Destroyed=false;
   layout.Clear();layout.Watch(canvas);for(int i=0;i<64;i++){layout.Prepare();layout.Restore();}
   long bytes=GC.GetAllocatedBytesForCurrentThread();for(int i=0;i<512;i++){bool visible=layout.HasVisibleDialog;layout.Prepare();layout.Restore();}
   Check(bytes==GC.GetAllocatedBytesForCurrentThread(),"Warmed visible-dialog preparation/restoration allocates zero managed bytes.");
   layout.Clear();Check(!layout.HasVisibleDialog,"Scene/shutdown clears cached dialogue references.");
   return checks;
  }
 }
}
'@
Add-Type -TypeDefinition ('using System;using System.Collections.Generic;using UnityEngine;using HarmonyLib;'+$fixture+$source)
$count=[QVVR.DialogHudTests]::Run()

Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
 $renderer=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
 $capture=($renderer.Methods | Where-Object Name -eq 'CaptureUi').Body
 $prepare=$capture.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'DialogHudLayout' -and $_.Operand.Name -eq 'Prepare'}
 $restore=$capture.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'DialogHudLayout' -and $_.Operand.Name -eq 'Restore'}
 $render=@($capture.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'Camera' -and $_.Operand.Name -eq 'Render'})
 $snapshot=$capture.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'Captured'}
 if(!$prepare -or $render.Count -ne 1 -or $prepare.Offset -ge $render[0].Offset -or $restore.Offset -le $render[0].Offset -or $snapshot.Offset -le $restore.Offset){throw 'Center only the existing UI capture; restore before the adaptive cache snapshots original layout.'}
 if(!($capture.ExceptionHandlers | Where-Object {$_.HandlerType -eq 'Finally' -and $restore.Offset -ge $_.HandlerStart.Offset -and $restore.Offset -lt $_.HandlerEnd.Offset})){throw 'Dialogue capture override must restore in finally.'}
 foreach($call in @('get_FixedCinemaPanel','UseGameplayHud')){if(!($capture.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq $call})){throw "Missing flat/menu gating: $call"}}
 if(!($capture.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'CenterDialogs'})){throw 'Missing live desktop-safe rollback setting.'}
 $scan=($renderer.Methods | Where-Object Name -eq 'RedirectOverlayCanvases').Body.Instructions
 if(!($scan | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'DialogHudLayout' -and $_.Operand.Name -eq 'Watch'})){throw 'Dialogue discovery must be integrated with the cold canvas scan.'}
} finally {$assembly.Dispose()}
if($GameDir){
 $game=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $GameDir 'QV_Data/Managed/Assembly-CSharp.dll'))
 try {
  $dialog=$game.MainModule.Types | Where-Object FullName -eq 'Dialog'
  foreach($name in @('Init','InitDialog','UpdatePosition','GetActorPosition')){if(!($dialog.Methods | Where-Object Name -eq $name)){throw "Missing verified QV Dialog method: $name"}}
  foreach($name in @('_canvasGroup','_transform')){if(!($dialog.Fields | Where-Object Name -eq $name)){throw "Missing verified QV Dialog field: $name"}}
  $manager=$game.MainModule.Types | Where-Object FullName -eq 'DialogManager'
  if(!((($manager.Methods | Where-Object Name -eq 'GetPosition').Body.Instructions) | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'WorldToScreenPoint'})){throw 'QV dialogue projection architecture changed.'}
 }finally{$game.Dispose()}
 Write-Host 'Installed QV dialogue projection/layout references verified by read-only metadata.'
}
Write-Host "Dialogue HUD: $count production-layout assertions, zero warmed managed allocations and compiled capture/cache/finally integration passed. Not headset visual QA."
