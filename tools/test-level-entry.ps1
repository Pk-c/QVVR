[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=(Get-Content (Join-Path $root 'src/QVVR/LevelEntryCompatibility.cs') -Raw) -replace '(?m)^using .*;\r?\n',''
# Actual policy/transpiler with API doubles. Execute its emitted IL, not Unity.
$fixture=@'
namespace UnityEngine {
 public class CanvasGroup {} public class OtherGroup {}
 public class Object {}
 public class GameObject : Object {public bool activeInHierarchy=true;}
 public class Component : Object {public GameObject gameObject=new GameObject();}
}
// PlayableDirector double: state 1 = Playing; Stop raises the game's stopped path.
public class DirectorDouble : UnityEngine.Component {public int state{get;set;}=1;public int Stops;public void Stop(){Stops++;state=0;}}
namespace DG.Tweening {
 public static class DOTweenModuleUI {
  public static float First,Last;public static int Calls;
  public static void DOFade(UnityEngine.CanvasGroup target,float alpha,float seconds){if(Calls++==0)First=seconds;Last=seconds;}
  public static void DOFade(UnityEngine.OtherGroup target,float alpha,float seconds){}
 }
}
namespace HarmonyLib {
 public class CodeInstruction {public OpCode opcode;public object operand;public CodeInstruction(OpCode code,object value=null){opcode=code;operand=value;}}
 public class HarmonyMethod {public HarmonyMethod(Type type,string name){}}
 public class Harmony {
  public static int Patches,Unpatches;public static bool Fail;public static MethodInfo Target;public static List<MethodInfo> Targets=new List<MethodInfo>();
  public Harmony(string id){}
  public void Patch(MethodInfo original,HarmonyMethod transpiler=null,HarmonyMethod postfix=null){if(Fail)throw new InvalidOperationException("Fixture patch failure");Patches++;if(Target==null)Target=original;Targets.Add(original);}
  public void UnpatchSelf(){Unpatches++;}
 }
 public static class AccessTools {
  public static Type TypeByName(string name){return Assembly.GetExecutingAssembly().GetType(name);}
  public static MethodInfo DeclaredMethod(Type type,string name,Type[] args){return type.GetMethod(name,args);}
  public static MethodInfo Method(Type type,string name){return type.GetMethod(name,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Static|BindingFlags.Instance);}
  public static MethodInfo Method(Type type,string name,Type[] args){return type.GetMethod(name,args);}
  public static FieldInfo Field(Type type,string name){return type.GetField(name,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance);}
  public static PropertyInfo Property(Type type,string name){return type.GetProperty(name)??(PropertyInfo)null;}
 }
}
public class GameManager : UnityEngine.Object {public void GameStart(){}public void SetDirector(){}DirectorDouble _playableDirector=new DirectorDouble();public DirectorDouble Director{get{return _playableDirector;}}}
namespace QVVR {
 internal class ConfigDouble<T> {internal T Value;}
 internal class LogDouble {internal int Warnings;internal void LogInfo(string text){}internal void LogWarning(string text){Warnings++;}}
 internal class Plugin {internal const string Guid="test";internal static LogDouble Log=new LogDouble();internal static void Trace(string text){}internal ConfigDouble<float> LevelEntrySeconds=new ConfigDouble<float>{Value=1.5f};internal ConfigDouble<bool> SkipLevelTour=new ConfigDouble<bool>{Value=true};}
 internal class OpenVrRenderer {internal bool ShortenLevelEntry,IsFirstLevelScene;internal IEnumerator Pending;internal object StartCoroutine(IEnumerator routine){Pending=routine;return null;}
  internal void Frame(){if(Pending!=null&&!Pending.MoveNext())Pending=null;}}
 public static class LevelEntryTests {
  static int checks;
  static void Check(bool value,string message){checks++;if(!value)throw new Exception(message);}
  static MethodInfo fade=typeof(DG.Tweening.DOTweenModuleUI).GetMethod("DOFade",new[]{typeof(UnityEngine.CanvasGroup),typeof(float),typeof(float)});
  static List<CodeInstruction> Body(int count=2){
   var code=new List<CodeInstruction>();
   for(int i=0;i<count;i++){code.Add(new CodeInstruction(OpCodes.Ldnull));code.Add(new CodeInstruction(OpCodes.Ldc_R4,1f));code.Add(new CodeInstruction(OpCodes.Ldc_R4,5.5f));code.Add(new CodeInstruction(OpCodes.Call,fade));}
   code.Add(new CodeInstruction(OpCodes.Ret));return code;
  }
  static List<CodeInstruction> Patch(List<CodeInstruction> code){
   return new List<CodeInstruction>((IEnumerable<CodeInstruction>)typeof(LevelEntryCompatibility).GetMethod("ShortenFade",BindingFlags.Static|BindingFlags.NonPublic).Invoke(null,new object[]{code}));
  }
  static void Run(List<CodeInstruction> code){
   DG.Tweening.DOTweenModuleUI.Calls=0;
   var method=new DynamicMethod("EntryTest",typeof(void),Type.EmptyTypes,typeof(LevelEntryCompatibility),true);var il=method.GetILGenerator();
   foreach(var instruction in code){if(instruction.operand==null)il.Emit(instruction.opcode);else if(instruction.operand is float)il.Emit(instruction.opcode,(float)instruction.operand);else il.Emit(instruction.opcode,(MethodInfo)instruction.operand);}
   ((Action)method.CreateDelegate(typeof(Action)))();
  }
  public static int Run(){
   foreach(float value in new[]{0f,0.5f,1.5f,3f,5.5f,9f,float.NaN,float.PositiveInfinity,float.NegativeInfinity}){
    Check(LevelEntryPolicy.Duration(5.5f,false,value)==5.5f,"Desktop, cinema or non-independent VR must retain timing.");
    float resolved=LevelEntryPolicy.Duration(5.5f,true,value);
    Check(resolved>=1.5f&&resolved<=5.5f,"Entry duration must retain focus ordering and reject invalid settings.");
   }
   Check(LevelEntryPolicy.Duration(5.5f,true,1.5f)==1.5f,"Default short entry.");
   Check(LevelEntryPolicy.Duration(5.5f,true,5.5f)==5.5f,"Rollback duration.");
   Check(LevelEntryPolicy.Duration(5.5f,true,3f)==3f,"Custom duration.");
   Check(LevelEntryPolicy.Duration(0.5f,true,1.5f)==0.5f,"Unrelated durations untouched.");
   var original=Body();var patched=Patch(original);
   Check(original.Count==9&&patched.Count==11,"Only two resolver calls added, source list retained.");
   int cursor=0,helpers=0;
   foreach(var instruction in patched){
    var call=instruction.operand as MethodInfo;
    if(call!=null&&call.DeclaringType==typeof(LevelEntryCompatibility)){Check(call.Name=="ResolveDuration","Only duration helper inserted.");helpers++;}
    else Check(object.ReferenceEquals(instruction,original[cursor++]),"All original instructions/labels/callback sites retained in order.");
   }
   Check(helpers==2&&cursor==original.Count,"Both GameStart branches covered.");
   foreach(int count in new[]{0,1,3}){
    bool failed=false;try{Patch(Body(count));}catch(TargetInvocationException e){failed=e.InnerException is InvalidOperationException;}
    Check(failed,"Unknown game layout must fail closed before patching.");
   }
   var wrong=Body();wrong[3].operand=typeof(DG.Tweening.DOTweenModuleUI).GetMethod("DOFade",new[]{typeof(UnityEngine.OtherGroup),typeof(float),typeof(float)});
   bool rejected=false;try{Patch(wrong);}catch(TargetInvocationException e){rejected=e.InnerException is InvalidOperationException;}
   Check(rejected,"Reject a same-name fade with another target type.");
   Run(patched);Check(DG.Tweening.DOTweenModuleUI.First==5.5f&&DG.Tweening.DOTweenModuleUI.Last==5.5f,"No renderer retains native duration.");
   var renderer=new OpenVrRenderer{ShortenLevelEntry=true};var settings=new Plugin();var compatibility=new LevelEntryCompatibility();compatibility.Initialize(renderer,settings);
   Check(Harmony.Patches==2&&Harmony.Target.DeclaringType==typeof(GameManager)&&Harmony.Target.Name=="GameStart"&&Harmony.Targets[1].Name=="SetDirector","Patch GameManager.GameStart and SetDirector only.");
   // Level tour: stopped one frame after SetDirector, via the game's own Stop path.
   MethodInfo tour=typeof(LevelEntryCompatibility).GetMethod("TourStarted",BindingFlags.Static|BindingFlags.NonPublic);
   var game=new GameManager();tour.Invoke(null,new object[]{game});
   Check(game.Director.Stops==0&&renderer.Pending!=null,"Tour is never stopped inside GameManager.Start.");
   renderer.Frame();renderer.Frame();Check(game.Director.Stops==1,"Tour stopped on the next frame.");
   game=new GameManager();renderer.IsFirstLevelScene=true;tour.Invoke(null,new object[]{game});renderer.Frame();renderer.Frame();
   Check(game.Director.Stops==0,"Level 1-1 story intro is kept.");renderer.IsFirstLevelScene=false;
   game=new GameManager();settings.SkipLevelTour.Value=false;tour.Invoke(null,new object[]{game});renderer.Frame();renderer.Frame();
   Check(game.Director.Stops==0,"Setting false plays the original tour.");settings.SkipLevelTour.Value=true;
   game=new GameManager();renderer.ShortenLevelEntry=false;tour.Invoke(null,new object[]{game});renderer.Frame();renderer.Frame();
   Check(game.Director.Stops==0,"Desktop/cinema keeps the tour.");renderer.ShortenLevelEntry=true;
   game=new GameManager();tour.Invoke(null,new object[]{game});game.Director.state=0;renderer.Frame();renderer.Frame();
   Check(game.Director.Stops==0,"A tour already ended or skipped is not stopped twice.");
   game=new GameManager();tour.Invoke(null,new object[]{game});game.Director.gameObject.activeInHierarchy=false;renderer.Frame();renderer.Frame();
   Check(game.Director.Stops==0,"A retry-deactivated director is left alone.");
   Run(patched);Check(DG.Tweening.DOTweenModuleUI.Calls==2&&DG.Tweening.DOTweenModuleUI.First==1.5f&&DG.Tweening.DOTweenModuleUI.Last==1.5f,"Emitted IL shortens both VR branches without skipping the fade.");
   renderer.ShortenLevelEntry=false;Run(patched);Check(DG.Tweening.DOTweenModuleUI.First==5.5f,"Desktop/cinema guard evaluated at entry, not baked into patch.");
   renderer.ShortenLevelEntry=true;settings.LevelEntrySeconds.Value=3f;Run(patched);Check(DG.Tweening.DOTweenModuleUI.First==3f,"Live setting used at next GameStart.");
   compatibility.Release();Run(patched);Check(DG.Tweening.DOTweenModuleUI.First==5.5f&&Harmony.Unpatches==1,"Shutdown restores fallback and removes patch.");
   Harmony.Fail=true;compatibility.Initialize(renderer,settings);Run(patched);
   Check(Plugin.Log.Warnings==1&&DG.Tweening.DOTweenModuleUI.First==5.5f,"Patch failure keeps original timing.");
   for(int i=0;i<1024;i++)LevelEntryPolicy.Duration(5.5f,true,1.5f);
   long before=GC.GetAllocatedBytesForCurrentThread();float sum=0;
   for(int i=0;i<1024;i++)sum+=LevelEntryPolicy.Duration(5.5f,true,1.5f);
   long allocated=GC.GetAllocatedBytesForCurrentThread()-before;
   Check(sum==1536f&&allocated==0,"Warmed duration policy allocates no managed memory.");
   return checks;
  }
 }
}
'@
$usings="using System;using System.Collections;using System.Collections.Generic;using System.Reflection;using System.Reflection.Emit;using HarmonyLib;using UnityEngine;`n"
Add-Type -TypeDefinition ($usings+$fixture+$source)
$count=[QVVR.LevelEntryTests]::Run()
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
 $renderer=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
 $guard=$renderer.Methods | Where-Object Name -eq 'get_ShortenLevelEntry'
 foreach($field in @('initialized','resourcesReleased','gameplayScene','VrEnabled','IndependentDioramaView')){
  if(!($guard.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq $field})){throw "Missing entry guard: $field"}
 }
 if(!($guard.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'get_FixedCinemaPanel'})){throw 'Entry must preserve fixed cinematics.'}
 foreach($pair in @(@('Initialize','Initialize'),@('ReleaseResources','Release'))){
  $method=$renderer.Methods | Where-Object Name -eq $pair[0]
  if(!($method.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'LevelEntryCompatibility' -and $_.Operand.Name -eq $pair[1]})){throw "Missing entry lifecycle: $($pair[0])"}
 }
}finally{$assembly.Dispose()}
if($GameDir){
 $game=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $GameDir 'QV_Data/Managed/Assembly-CSharp.dll'))
 try {
  $manager=$game.MainModule.Types | Where-Object Name -eq 'GameManager'
  $start=$manager.Methods | Where-Object Name -eq 'GameStart';$matches=0
  foreach($instruction in $start.Body.Instructions){
   if($instruction.OpCode.Name -ne 'ldc.r4' -or $instruction.Operand -ne [single]5.5){continue}
   $call=$instruction.Next.Operand
   if($call -is [Mono.Cecil.MethodReference] -and $call.DeclaringType.FullName -eq 'DG.Tweening.DOTweenModuleUI' -and $call.Name -eq 'DOFade' -and $call.Parameters.Count -eq 3 -and $call.Parameters[0].ParameterType.FullName -eq 'UnityEngine.CanvasGroup'){$matches++}
  }
  if($matches -ne 2){throw 'Installed GameStart fade layout differs from the verified two branches.'}
  foreach($name in @('<GameStart>b__327_0','<GameStart>b__327_1')){
   $callback=$manager.Methods | Where-Object Name -eq $name
   foreach($field in @('StartDialog','moveEnable')){
    if(!($callback.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq $field})){throw "Missing original entry callback action: $name / $field"}
   }
  }
  # Level tour skip relies on: SetDirector plays the director, and its stopped
  # event (raised by PlayableDirector.Stop, as the game's SkipManager does)
  # runs OnEndDirector, which starts the level.
  if(!($manager.Methods | Where-Object {$_.Name -eq 'SetDirector' -and $_.Parameters.Count -eq 0})){throw 'Installed GameManager.SetDirector() missing.'}
  $register=($manager.Methods | Where-Object Name -eq 'RegisterEvent').Body.Instructions
  $wired=$register | Where-Object {$_.OpCode.Name -eq 'ldftn' -and $_.Operand.Name -eq 'OnEndDirector' -and $_.Next.Next.Operand -is [Mono.Cecil.MethodReference] -and $_.Next.Next.Operand.Name -eq 'add_stopped'}
  if(!$wired){throw 'Installed director stopped event no longer runs GameManager.OnEndDirector.'}
 }finally{$game.Dispose()}
 Write-Host 'Installed QV GameStart fade branches, original dialog/control callbacks and director stop -> OnEndDirector wiring verified read-only.'
}
Write-Host "Level entry: $count production policy/transpiler assertions plus emitted-IL execution and compiled lifecycle/guard checks passed. Not Unity/Frame timing validation."
