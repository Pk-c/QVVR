[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$policy = Get-Content (Join-Path $root 'src/QVVR/MenuScenePolicy.cs') -Raw
$compat = Get-Content (Join-Path $root 'src/QVVR/IntroMenuCompatibility.cs') -Raw
$fixture = @'
namespace UnityEngine {
 public class Object {
  public static readonly System.Collections.Generic.Dictionary<System.Type,Object> Instances=new System.Collections.Generic.Dictionary<System.Type,Object>();
  public static int Finds;
  public static Object FindObjectOfType(System.Type type){Finds++;Object value;return Instances.TryGetValue(type,out value)?value:null;}
 }
 public class Transform : Object { public Vector3 position; }
 public class Renderer : Object { public bool enabled=true; public float Alpha=.8f; }
 public struct Vector3 {
  public float x,y,z; public Vector3(float x,float y,float z){this.x=x;this.y=y;this.z=z;}
  public static Vector3 forward{get{return new Vector3(0,0,1);}}
  public static Vector3 operator+(Vector3 a,Vector3 b){return new Vector3(a.x+b.x,a.y+b.y,a.z+b.z);}
  public static Vector3 operator-(Vector3 a,Vector3 b){return new Vector3(a.x-b.x,a.y-b.y,a.z-b.z);}
  public static Vector3 operator*(Vector3 a,float b){return new Vector3(a.x*b,a.y*b,a.z*b);}
  public static float Dot(Vector3 a,Vector3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
 }
 public struct Quaternion {
  public float Yaw;
  public static Vector3 operator*(Quaternion q,Vector3 v){double a=q.Yaw*System.Math.PI/180;return new Vector3((float)(v.x*System.Math.Cos(a)+v.z*System.Math.Sin(a)),v.y,(float)(v.z*System.Math.Cos(a)-v.x*System.Math.Sin(a)));}
 }
}
namespace HarmonyLib {
 public class Harmony {public Harmony(string id){} public void Patch(System.Reflection.MethodInfo method,HarmonyMethod postfix=null,HarmonyMethod prefix=null){} public void UnpatchSelf(){} }
 public class HarmonyMethod {public HarmonyMethod(System.Type type,string name){} }
 public static class AccessTools {
  public static System.Type TypeByName(string name){return System.Type.GetType(name);}
  public static System.Reflection.FieldInfo Field(System.Type type,string name){return type.GetField(name,System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.Public|System.Reflection.BindingFlags.NonPublic);}
  public static System.Reflection.MethodInfo DeclaredMethod(System.Type type,string name){return type.GetMethod(name);}
 }
}
namespace UnityEngine.UI { public class Image {} }
public class StubMachine { public object currentState=new object(); }
public class IntroHolder : UnityEngine.Object { public StubMachine _stateMachine=new StubMachine(); }
public class IntroWorldManager : UnityEngine.Object { public UnityEngine.Transform _worldTransform=new UnityEngine.Transform(); }
public class IntroStageUIManager : UnityEngine.Object { public UnityEngine.Renderer _dim=new UnityEngine.Renderer(); }
namespace QVVR {
 public class StubLog {public void LogInfo(string value){} public void LogWarning(string value){} }
 public class Plugin {public const string Guid="test"; public static StubLog Log=new StubLog();}
 internal class OpenVrRenderer {internal void SetIntroPresentation(IntroPresentation state){} internal void BeginStageFade(UnityEngine.UI.Image panel){} }
 public static class IntroVisualTests {
  static int checks;
  static void Check(bool ok,string message){checks++;if(!ok)throw new System.Exception(message);}
  static bool Near(float a,float b){return System.Math.Abs(a-b)<.00001f;}
  public static int Run(){
   var world=new IntroWorldManager();world._worldTransform.position=new UnityEngine.Vector3(0,0,20);
   var ui=new IntroStageUIManager();
   UnityEngine.Object.Instances[typeof(IntroWorldManager)]=world;
   UnityEngine.Object.Instances[typeof(IntroStageUIManager)]=ui;
   UnityEngine.Object.Instances[typeof(IntroHolder)]=new IntroHolder();
   var compat=new IntroMenuCompatibility();compat.Initialize(new OpenVrRenderer());compat.Refresh();
   int finds=UnityEngine.Object.Finds;
   var pos=compat.HubPosition(new UnityEngine.Vector3(0,0,0),new UnityEngine.Quaternion(),.35f);
   Check(Near(pos.z,13)&&Near(pos.x,0)&&Near(pos.y,0),"Dolly only the VR pose along the view direction.");
   Check(Near(world._worldTransform.position.z,20),"Game anchor never modified.");
   var original=compat.HubPosition(new UnityEngine.Vector3(0,0,0),new UnityEngine.Quaternion(),1);
   Check(Near(original.z,0),"Original-distance recovery works.");
   world._worldTransform.position=new UnityEngine.Vector3(20,0,0);
   var rotated=compat.HubPosition(new UnityEngine.Vector3(0,0,0),new UnityEngine.Quaternion{Yaw=90},.35f);
   Check(Near(rotated.x,13)&&Near(rotated.z,0),"Dolly follows the original camera axis, not global Z.");
   world._worldTransform.position=new UnityEngine.Vector3(0,0,-20);
   Check(Near(compat.HubPosition(new UnityEngine.Vector3(0,0,0),new UnityEngine.Quaternion(),.35f).z,0),"Behind-camera focus falls back safely.");
   compat.HideStageDim();compat.HideStageDim();Check(!ui._dim.enabled,"Nested suppression hides just the cached renderer.");
   ui._dim.Alpha=.3f;compat.RestoreStageDim();Check(ui._dim.enabled&&Near(ui._dim.Alpha,.3f),"Restore enable state without overwriting the game's fade alpha.");
   ui._dim.enabled=false;compat.HideStageDim();compat.RestoreStageDim();Check(!ui._dim.enabled,"Already disabled dimmer stays disabled.");
   ui._dim.enabled=true;
   try{compat.HideStageDim();throw new System.InvalidOperationException();}catch(System.InvalidOperationException){}finally{compat.RestoreStageDim();}
   Check(ui._dim.enabled,"Render exception finally restores dimmer.");
   Check(UnityEngine.Object.Finds==finds,"Hot camera/suppression methods never search scene objects.");
   compat.HideStageDim();compat.Reset();Check(ui._dim.enabled,"Scene reset restores suppression.");
   Check(Near(compat.HubPosition(new UnityEngine.Vector3(1,2,3),new UnityEngine.Quaternion(),.35f).z,3),"Missing/reset anchor retains original framing.");
   compat.Refresh();compat.HideStageDim();compat.Release();Check(ui._dim.enabled,"Shutdown/desktop recovery restores dimmer.");
   return checks;
  }
 }
}
'@
$source = "using System; using System.Reflection; using UnityEngine; using HarmonyLib;`n" +
    $policy + $compat.Replace('using System;', '').Replace('using System.Reflection;', '').Replace('using HarmonyLib;', '').Replace('using UnityEngine;', '') + $fixture
Add-Type -TypeDefinition $source
$count = [QVVR.IntroVisualTests]::Run()
Write-Host "Intro camera/dimmer: $count assertions passed against actual compatibility source; no game or VR session started."
