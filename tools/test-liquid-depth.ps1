[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$policy = Get-Content -LiteralPath (Join-Path $root 'src/QVVR/LiquidDepthPolicy.cs') -Raw
$fixture = @'
namespace QVVR {
 public static class LiquidTests {
  static int checks;
  static void Check(bool ok,string message){checks++;if(!ok)throw new System.Exception(message);}
  static Renderer Make(string shader,bool loaded=true){return new Renderer{gameObject=new GameObject{scene=new Scene{Valid=loaded,isLoaded=loaded}},sharedMaterials=new[]{new Material{shader=new Shader{name=shader}}}};}
  public static int Run(){
   Check(LiquidDepthPolicy.UsesDepth("Toony Colors Pro 2/Examples/Cat Demo/Water"),"Verified water/ink shader requires depth.");
   Check(LiquidDepthPolicy.UsesDepth("Toony Colors Pro 2/Examples/Water/Realistic"),"Realistic fog/water requires depth.");
   Check(LiquidDepthPolicy.UsesDepth("Toony Colors Pro 2/Examples/Water/Poison"),"RainCore water requires depth.");
   Check(!LiquidDepthPolicy.UsesDepth("UI/Default")&&!LiquidDepthPolicy.UsesDepth("Standard")&&!LiquidDepthPolicy.UsesDepth(null),"Do not match ordinary geometry, UI or missing metadata.");
   var water=Make("Toony Colors Pro 2/Examples/Cat Demo/Water");
   var disabled=Make("Toony Colors Pro 2/Examples/Water/Poison");disabled.enabled=false;
   var inactive=Make("Toony Colors Pro 2/Examples/Water/Realistic");inactive.gameObject.activeInHierarchy=false;
   var prefab=Make("Toony Colors Pro 2/Examples/Cat Demo/Water",false);
   var stone=Make("Standard");var missing=Make("Standard");missing.sharedMaterials=new Material[]{null};
   Resources.Snapshot=new[]{water,disabled,inactive,prefab,stone,missing};
   var policy=new LiquidDepthPolicy();policy.Refresh();
   Check(policy.Count==3&&policy.NeedsDepth,"Cache loaded liquids only; active water requests depth.");
   water.enabled=false;Check(!policy.NeedsDepth,"Inactive/disabled liquids avoid the extra depth pass.");
   inactive.gameObject.activeInHierarchy=true;Check(policy.NeedsDepth,"A cached liquid becoming active immediately requests fresh depth.");
   Check(!water.enabled&&stone.enabled&&prefab.enabled,"No renderer or game material changes.");
   policy.Clear();Check(policy.Count==0&&!policy.NeedsDepth,"Scene/fallback cleanup clears depth requirement.");
   const string waterShader="Toony Colors Pro 2/Examples/Cat Demo/Water";
   Check(LiquidDepthPolicy.WaterFoamMaterial("WaterBlockMat",waterShader)&&LiquidDepthPolicy.WaterFoamMaterial("WaterBlockMat (Instance)",waterShader),"Target only the inspected blue water material and its runtime instance.");
   Check(!LiquidDepthPolicy.WaterFoamMaterial("InkSpring",waterShader)&&!LiquidDepthPolicy.WaterFoamMaterial("WaterBlockMat","Standard"),"Ink and unrelated materials are excluded.");
   int foam=Shader.PropertyToID("_FoamColor"),waterColor=Shader.PropertyToID("_Color");
   var blue=new Material{name="WaterBlockMat",shader=new Shader{name=waterShader}};
   var originalFoam=new Color{r=1,g=1,b=1,a=1};var originalBlue=new Color{r=.3f,g=.91f,b=.88f,a=1};
   blue.Colors[foam]=originalFoam;blue.Colors[waterColor]=originalBlue;
   var ink=new Material{name="InkSpring",shader=blue.shader};ink.Colors[foam]=originalFoam;
   var live=new Renderer{sharedMaterials=new[]{blue,ink}};var duplicate=new Renderer{sharedMaterials=new[]{blue}};
   Resources.Snapshot=new[]{live,duplicate};policy.Refresh();Check(policy.WaterMaterialCount==1,"Blue-water material shared by many renderers is deduplicated.");
   policy.PrepareWater();policy.PrepareWater();Check(blue.GetColor(foam).a==0&&blue.GetColor(waterColor)==originalBlue&&ink.GetColor(foam)==originalFoam,"Only white-foam coverage is suppressed; native water colors and ink remain intact.");
   policy.RestoreWater();Check(blue.GetColor(foam)==originalFoam,"Restore original foam exactly after both eyes.");
   var changedFoam=new Color{r=.5f,g=.7f,b=.9f,a=.6f};blue.Colors[foam]=changedFoam;policy.PrepareWater();policy.RestoreWater();
   Check(blue.GetColor(foam)==changedFoam,"Live game-side foam changes survive the scoped override.");
   bool failed=false;blue.FailColor=true;try{policy.PrepareWater();}catch(System.InvalidOperationException){failed=true;}finally{policy.RestoreWater();}
   Check(failed&&blue.GetColor(foam)==changedFoam,"Partial material-setup errors restore the live original.");
   policy.PrepareWater();policy.Clear();Check(blue.GetColor(foam)==changedFoam&&policy.WaterMaterialCount==0,"Scene/desktop cleanup restores outstanding foam state.");
   return checks;
  }
 }
}
'@
$visibility=(Get-Content (Join-Path $root 'src/QVVR/DioramaVisibility.cs') -Raw).Replace('using System.Collections.Generic;','').Replace('using UnityEngine;','')
$api=Get-Content (Join-Path $PSScriptRoot 'performance-fixture.cs') -Raw
Add-Type -TypeDefinition ("using System.Collections.Generic; using UnityEngine;`n" + $api + $visibility + $fixture +
    $policy.Replace('using System.Collections.Generic;', '').Replace('using UnityEngine;', ''))
$count = [QVVR.LiquidTests]::Run()

Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
    $renderer = $assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
    $eye = $renderer.Methods | Where-Object Name -eq 'RenderEye'
    if (-not ($eye.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.FullName -like '*LiquidDepthPolicy::get_NeedsDepth*' })) { throw 'Eye rendering does not consult the liquid depth cache.' }
    if (-not ($eye.Body.Instructions | Where-Object { $_.OpCode.Name -eq 'or' })) { throw 'Liquid eye pass must preserve and augment the original depth modes.' }
    if ($eye.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -like 'SetGlobal*' }) { throw 'Do not fake Unity camera globals to freeze liquid shading.' }
    $late=($renderer.Methods | Where-Object Name -eq 'LateUpdate').Body
    $prepare=$late.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'PrepareWater'}
    $restore=$late.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'RestoreWater'}
    $stereo=$late.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'RenderStereoGameplay'}
    if(!$prepare -or !$restore -or $prepare.Offset -ge $stereo[0].Offset){throw 'Water override must precede both stereo eyes.'}
    if(!($late.ExceptionHandlers | Where-Object {$_.HandlerType -eq 'Finally' -and $restore.Offset -ge $_.HandlerStart.Offset -and $restore.Offset -lt $_.HandlerEnd.Offset})){throw 'Water material must restore in finally.'}
    $resources = $renderer.Methods | Where-Object Name -eq 'CreateResources'
    if (-not ($resources.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.FullName -like '*CommandBuffer::IssuePluginEvent*' })) { throw 'Missing cached opaque/transparent cap event boundary.' }
    Write-Host "Liquid depth: $count assertions and compiled per-eye depth integration passed. No game/VR session started."
} finally { $assembly.Dispose() }
