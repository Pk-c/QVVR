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
    $resources = $renderer.Methods | Where-Object Name -eq 'CreateResources'
    if (-not ($resources.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.FullName -like '*CommandBuffer::IssuePluginEvent*' })) { throw 'Missing cached opaque/transparent cap event boundary.' }
    Write-Host "Liquid depth: $count assertions and compiled per-eye depth integration passed. No game/VR session started."
} finally { $assembly.Dispose() }
