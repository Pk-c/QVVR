[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=(Get-Content (Join-Path $root 'src/QVVR/CharacterVisualCompatibility.cs') -Raw).Replace('using UnityEngine;','')
# Execute the actual cold compatibility cache with API doubles, no game session.
$fixture=@'
namespace UnityEngine {
 public enum AnimatorCullingMode { AlwaysAnimate=0,CullUpdateTransforms=1,CullCompletely=2 }
 public class Animator { public AnimatorCullingMode cullingMode; public bool enabled=true; }
 public class SkinnedMeshRenderer { public bool updateWhenOffscreen,enabled=true; }
 public class Transform {
  public Animator[] Animators=new Animator[0];public SkinnedMeshRenderer[] Skins=new SkinnedMeshRenderer[0];
  public int Scans;
  public void GetComponentsInChildren<T>(bool inactive,System.Collections.Generic.List<T> results){Scans++;if(!inactive)throw new System.Exception("Inactive costume coverage lost");results.Clear();foreach(var item in (T[])(object)(typeof(T)==typeof(Animator)?(object)Animators:Skins))results.Add(item);}
 }
}
namespace QVVR {
 public static class CharacterVisualTests {
  static int checks;static void Check(bool ok,string text){checks++;if(!ok)throw new System.Exception(text);}
  public static int Run(){
   var a=new UnityEngine.Animator{cullingMode=UnityEngine.AnimatorCullingMode.CullUpdateTransforms};
   var b=new UnityEngine.Animator{cullingMode=UnityEngine.AnimatorCullingMode.AlwaysAnimate,enabled=false};
   var skin=new UnityEngine.SkinnedMeshRenderer();var inactive=new UnityEngine.SkinnedMeshRenderer{enabled=false,updateWhenOffscreen=true};
   var npc=new UnityEngine.Animator{cullingMode=UnityEngine.AnimatorCullingMode.CullCompletely};
   var player=new UnityEngine.Transform{Animators=new[]{a,b},Skins=new[]{skin,inactive}};
   var compat=new CharacterVisualCompatibility();compat.Refresh(player);
   Check(a.cullingMode==UnityEngine.AnimatorCullingMode.AlwaysAnimate,"Player animation not suspended by manual camera culling.");
   Check(skin.updateWhenOffscreen,"Skinned hair can update its deformed bounds outside the old isometric view.");
   Check(!b.enabled&&!inactive.enabled,"No inactive animation/model/renderer is enabled.");
   Check(npc.cullingMode==UnityEngine.AnimatorCullingMode.CullCompletely,"Unrelated NPC animation untouched.");
   compat.Refresh(player);compat.Clear();
   Check(a.cullingMode==UnityEngine.AnimatorCullingMode.CullUpdateTransforms&&!skin.updateWhenOffscreen,"Repeated maintenance never compounds originals.");
   Check(b.cullingMode==UnityEngine.AnimatorCullingMode.AlwaysAnimate&&inactive.updateWhenOffscreen,"Originally unrestricted settings preserved.");
   compat.Clear();Check(!skin.updateWhenOffscreen,"Clear is idempotent.");
   compat.Refresh(player);a.cullingMode=UnityEngine.AnimatorCullingMode.CullCompletely;compat.Refresh(player);compat.Clear();
   Check(a.cullingMode==UnityEngine.AnimatorCullingMode.CullCompletely,"Later game-side culling changes become new baseline.");
   a.cullingMode=UnityEngine.AnimatorCullingMode.CullUpdateTransforms;compat.Refresh(player);
   player.Animators=new[]{b};player.Skins=new[]{inactive};compat.Refresh(player);
   Check(a.cullingMode==UnityEngine.AnimatorCullingMode.CullUpdateTransforms&&!skin.updateWhenOffscreen,"Reparented/removed models restore immediately in cold scan.");
   player.Animators=new[]{a,b};player.Skins=new[]{skin,inactive};compat.Refresh(player);
   var replacementSkin=new UnityEngine.SkinnedMeshRenderer();var replacement=new UnityEngine.Transform{Skins=new[]{replacementSkin}};
   compat.Refresh(replacement);
   Check(a.cullingMode==UnityEngine.AnimatorCullingMode.CullUpdateTransforms&&!skin.updateWhenOffscreen,"New player root releases prior overrides.");
   Check(replacementSkin.updateWhenOffscreen,"New costume/player root is covered.");
   compat.Refresh(null);Check(!replacementSkin.updateWhenOffscreen,"Null/destroyed target releases overrides.");
   return checks;
  }
 }
}
'@
Add-Type -TypeDefinition ('using UnityEngine;'+$source+$fixture)
$count=[QVVR.CharacterVisualTests]::Run()
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try{
 $renderer=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
 foreach($name in @('LateUpdate','RenderEye','RenderFlatScreen')){
  if(($renderer.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'CharacterVisualCompatibility'}){throw "Visual discovery/overrides must not occur in hot renderer: $name"}
 }
 foreach($name in @('OnActiveSceneChanged','ReleaseResources')){
  if(!(($renderer.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'characterVisuals'})){throw "Missing visual restore lifecycle: $name"}
 }
 $refresh=($renderer.Methods | Where-Object Name -eq 'RefreshCharacterVisuals').Body.Instructions
 foreach($field in @('trackingHeadValid','levelIntroFlat','gameplayTarget')){
  if(!($refresh | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq $field})){throw "Missing player-only tracking/cinematic guard: $field"}
 }
 $visual=$assembly.MainModule.Types | Where-Object Name -eq 'CharacterVisualCompatibility'
 foreach($method in $visual.Methods | Where-Object HasBody){
  if($method.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -match 'FindObjects|UpdateDynamicBones|SetWeight'}){throw 'Do not scan the scene or alter bone physics.'}
 }
}finally{$assembly.Dispose()}
Write-Host "Character visual culling: $count production-code assertions plus compiled cold-only/lifecycle/scope guards passed. Headset hair motion still needs visual verification."
