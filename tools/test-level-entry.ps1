[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=(Get-Content (Join-Path $root 'src/QVVR/LevelEntryCompatibility.cs') -Raw) -replace '(?m)^using .*;\r?\n',''
# Actual policy/transpiler with API doubles. Execute its emitted IL, not Unity.
$fixture=@'
namespace UnityEngine { public class CanvasGroup {} public class OtherGroup {} }
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
  public static int Patches,Unpatches;public static bool Fail;public static MethodInfo Target;
  public Harmony(string id){}
  public void Patch(MethodInfo original,HarmonyMethod transpiler){if(Fail)throw new InvalidOperationException("Fixture patch failure");Patches++;Target=original;}
  public void UnpatchSelf(){Unpatches++;}
 }
 public static class AccessTools {
  public static Type TypeByName(string name){return Assembly.GetExecutingAssembly().GetType(name);}
  public static MethodInfo DeclaredMethod(Type type,string name,Type[] args){return type.GetMethod(name,args);}
  public static MethodInfo Method(Type type,string name){return type.GetMethod(name,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Static|BindingFlags.Instance);}
 }
}
public class GameManager {public void GameStart(){}}
namespace QVVR {
 internal class ConfigDouble<T> {internal T Value;}
 internal class LogDouble {internal int Warnings;internal void LogInfo(string text){}internal void LogWarning(string text){Warnings++;}}
 internal class Plugin {internal const string Guid="test";internal static LogDouble Log=new LogDouble();internal ConfigDouble<float> LevelEntrySeconds=new ConfigDouble<float>{Value=1.5f};}
 internal class OpenVrRenderer {internal bool ShortenLevelEntry;}
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
    else Check(Object.ReferenceEquals(instruction,original[cursor++]),"All original instructions/labels/callback sites retained in order.");
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
   Check(Harmony.Patches==1&&Harmony.Target.DeclaringType==typeof(GameManager)&&Harmony.Target.Name=="GameStart","Patch only GameManager.GameStart.");
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
$usings="using System;using System.Collections.Generic;using System.Reflection;using System.Reflection.Emit;using HarmonyLib;`n"
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
 }finally{$game.Dispose()}
 Write-Host 'Installed QV GameStart fade branches and original dialog/control callbacks verified read-only.'
}
Write-Host "Level entry: $count production policy/transpiler assertions plus emitted-IL execution and compiled lifecycle/guard checks passed. Not Unity/Frame timing validation."
