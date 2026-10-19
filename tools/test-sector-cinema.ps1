[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=(Get-Content (Join-Path $root 'src/QVVR/SectorCinemaCompatibility.cs') -Raw) -replace '(?m)^using .*;\r?\n',''
$intro=Get-Content (Join-Path $root 'src/QVVR/FirstLevelIntroCompatibility.cs') -Raw
$policy=$intro.Substring($intro.IndexOf('    internal static class LevelIntroPolicy'),$intro.IndexOf('    internal sealed class FirstLevelIntroCompatibility')-$intro.IndexOf('    internal static class LevelIntroPolicy'))
$fixture=@'
namespace UnityEngine {
 public class Object {public static System.Collections.Generic.Dictionary<System.Type,Object> Objects=new System.Collections.Generic.Dictionary<System.Type,Object>();public static Object FindObjectOfType(System.Type t){Object o;return Objects.TryGetValue(t,out o)?o:null;}}
 public class GameObject {public bool activeInHierarchy=true;}
 public class Component:Object {public GameObject gameObject=new GameObject();public Camera Child;public T GetComponentInChildren<T>(bool inactive)where T:class{return Child!=null&&(inactive||Child.gameObject.activeInHierarchy)?Child as T:null;}}
 public class Camera:Component {public bool enabled=true;}
 public class Director:Component {public int state{get;set;}public double time{get;set;}public double duration{get;set;}}
}
namespace HarmonyLib {
 public static class AccessTools {
  public static System.Type TypeByName(string name){return typeof(AccessTools).Assembly.GetType(name);}
  public static System.Reflection.FieldInfo Field(System.Type t,string name){return t.GetField(name);}
  public static System.Reflection.PropertyInfo Property(System.Type t,string name){return t.GetProperty(name);}
  public static System.Reflection.MethodInfo DeclaredMethod(System.Type t,string name){return t.GetMethod(name);}
 }
 public class HarmonyMethod {public HarmonyMethod(System.Type type,string name){}}
 public class Harmony {public Harmony(string id){}public void Patch(System.Reflection.MethodInfo method,HarmonyMethod postfix){if(method==null)throw new System.Exception("Missing hook");}public void UnpatchSelf(){}}
}
public class IntroEventManager:UnityEngine.Object {
 public UnityEngine.Director _playableDirector;public UnityEngine.Camera _camera;public bool IsPlaying{get;set;}
 public void PlayCinema(UnityEngine.Camera camera,int sector){}public void OnEndCinema(UnityEngine.Director director){}
}
public class IntroWorldManager:UnityEngine.Object {public UnityEngine.Camera _camera;}
namespace QVVR {
 internal static class Plugin {public const string Guid="test";public static Logger Log=new Logger();internal class Logger{public void LogWarning(string text){throw new System.Exception(text);}}}
 internal class OpenVrRenderer {internal bool IsSectorCinemaScene=true;internal bool Flat;internal UnityEngine.Camera Source;internal int Changes;internal void SetLevelIntro(bool playing,UnityEngine.Camera camera){if(playing&&camera==null)return;Flat=playing;Source=camera;Changes++;}}
 public static class SectorTests {
  static int checks;static void Check(bool ok,string text){checks++;if(!ok)throw new System.Exception(text);}
  static void Invoke(string name,params object[] args){typeof(SectorCinemaCompatibility).GetMethod(name,System.Reflection.BindingFlags.Static|System.Reflection.BindingFlags.NonPublic).Invoke(null,args);}
  public static int Run(){
   var normal=new UnityEngine.Camera();var movie=new UnityEngine.Camera();var director=new UnityEngine.Director{state=1,duration=40,Child=movie};
   var manager=new IntroEventManager{_camera=movie,_playableDirector=director,IsPlaying=true};
   UnityEngine.Object.Objects[typeof(IntroEventManager)]=manager;UnityEngine.Object.Objects[typeof(IntroWorldManager)]=new IntroWorldManager{_camera=normal};
   var renderer=new OpenVrRenderer();var compat=new SectorCinemaCompatibility();compat.Initialize(renderer);
   Invoke("Started",manager,normal);Check(renderer.Flat&&renderer.Source==movie,"Sector PlayCinema selects active director camera and flat route");
   Check(!normal.enabled,"Game-disabled hub camera must not perform an extra background render");
   director.state=0;director.time=12;compat.Refresh();Check(renderer.Flat,"Paused cinema remains flat");
   manager.IsPlaying=false;director.gameObject.activeInHierarchy=false;Invoke("Stopped");Check(!renderer.Flat&&renderer.Source==normal,"End callback restores exact original camera");
   compat.Reset();director.gameObject.activeInHierarchy=true;director.state=1;manager.IsPlaying=true;compat.Refresh();
   Check(renderer.Flat&&renderer.Source==movie,"Late injection recovers active movie");
   director.state=0;director.time=40;director.gameObject.activeInHierarchy=false;manager.IsPlaying=false;compat.Refresh();
   Check(!renderer.Flat&&renderer.Source==normal,"Cold recovery handles skipped/completed director without callback");
   compat.Reset();manager._camera=null;director.Child=movie;director.gameObject.activeInHierarchy=true;director.state=1;manager.IsPlaying=true;compat.Refresh();
   Check(renderer.Flat&&renderer.Source==movie,"Unused/unassigned manager camera is not required");
   compat.Reset();renderer.Flat=false;director.Child.gameObject.activeInHierarchy=false;compat.Refresh();
   Check(!renderer.Flat,"Do not capture an inactive virtual-camera rig");director.Child.gameObject.activeInHierarchy=true;compat.Refresh();
   Check(renderer.Flat&&renderer.Source==movie,"Late camera activation recovers without a scene reload");
   int changes=renderer.Changes;renderer.IsSectorCinemaScene=false;Invoke("Started",manager,normal);Invoke("Stopped");compat.Refresh();
   Check(renderer.Changes==changes,"Outside 001_Intro no scene promotion");renderer.IsSectorCinemaScene=true;
   compat.Release();changes=renderer.Changes;Invoke("Started",manager,normal);Check(renderer.Changes==changes,"Release detaches callbacks");
   compat=new SectorCinemaCompatibility();compat.Initialize(renderer);manager._camera=movie;compat.Refresh();UnityEngine.Object.Objects.Remove(typeof(IntroEventManager));compat.Reset();
   changes=renderer.Changes;compat.Refresh();Check(renderer.Changes==changes,"Absent manager does not start a movie");compat.Release();
   return checks;
  }
 }
}
'@
Add-Type -TypeDefinition ('using System;using System.Reflection;using HarmonyLib;using UnityEngine;'+$fixture+$source+'namespace QVVR {'+$policy+'}')
$count=[QVVR.SectorTests]::Run()
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
 $renderer=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
 foreach($name in @('LateUpdate','CaptureUi','PositionPanels','RedirectOverlayCanvases')){
  if(!(($renderer.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'RenderStereoMenu'})){throw "Movie must bypass stereo-menu routing: $name"}
 }
 foreach($name in @('Initialize','OnActiveSceneChanged','ReleaseResources')){
  if(!(($renderer.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'sectorCinema'})){throw "Missing sector movie lifecycle: $name"}
 }
 $compat=$assembly.MainModule.Types | Where-Object Name -eq 'SectorCinemaCompatibility'
 foreach($name in @('LateUpdate','RenderEye','RenderFlatScreen')){
  if(($renderer.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq $compat.Name}){throw 'No cinema reflection/discovery per frame/eye.'}
 }
}finally{$assembly.Dispose()}
if($GameDir){
 $game=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $GameDir 'QV_Data/Managed/Assembly-CSharp.dll'))
 try {
  $manager=$game.MainModule.Types | Where-Object Name -eq 'IntroEventManager'
  foreach($field in @('_camera','_playableDirector')){if(!($manager.Fields | Where-Object Name -eq $field)){throw "Game field missing: $field"}}
  if(!($manager.Methods | Where-Object {$_.Name -eq 'PlayCinema' -and $_.Parameters.Count -eq 2 -and $_.Parameters[0].ParameterType.FullName -eq 'UnityEngine.Camera'})){throw 'Sector movie camera argument changed.'}
  foreach($method in @('OnEndCinema','get_IsPlaying')){if(!($manager.Methods | Where-Object Name -eq $method)){throw "Game hook missing: $method"}}
  $world=$game.MainModule.Types | Where-Object Name -eq 'IntroWorldManager'
  if(!(($world.Methods | Where-Object Name -eq 'PlayClearDirection').Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'IntroEventManager' -and $_.Operand.Name -eq 'PlayCinema'})){throw 'Verified sector-clear route changed.'}
 }finally{$game.Dispose()}
}
Write-Host "Sector cinema: $count production-code lifecycle assertions plus compiled routing and optional read-only game metadata guards passed. Not headset visual QA."
