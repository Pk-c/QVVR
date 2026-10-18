[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$sources=@('DioramaVisibility.cs','UiCaptureCache.cs','LiquidDepthPolicy.cs','CutSurfaceRegistry.cs') | ForEach-Object {
 (Get-Content (Join-Path $root "src/QVVR/$_") -Raw) -replace '(?m)^using .*;\r?\n',''
}
$fixture=Get-Content (Join-Path $PSScriptRoot 'performance-fixture.cs') -Raw
$tests=@'
namespace QVVR {
 internal static class NativeBridge {
  internal struct CapMeshBounds{internal Vector3 Minimum,Maximum;}
  internal static bool ShaderClipReady=true;internal static bool Bounded;internal static CapMeshBounds LastBounds;internal static int Registrations;
  internal static void QVVR_ClearCapMeshes(){Registrations=0;}
  internal static void QVVR_RegisterCapMesh(System.IntPtr buffer){Registrations++;Bounded=false;}
  internal static void QVVR_RegisterCapMeshBounds(System.IntPtr buffer,ref CapMeshBounds b){Registrations++;Bounded=true;LastBounds=b;}
 }
 public static class PerformanceTests {
  static int count;static void Check(bool ok,string name){count++;if(!ok)throw new System.Exception(name);}
  static Bounds Box(float x,float y,float z,float size=1){return new Bounds(new Vector3(x,y,z),new Vector3(size,size,size));}
  public static int Run(){
   Check(DioramaBounds.Intersects(Box(0,0,0),new Vector3(),2,2),"Interior mesh retained");
   Check(!DioramaBounds.Intersects(Box(4,0,0),new Vector3(),2,2),"Radial outside omitted");
   Check(!DioramaBounds.Intersects(Box(0,4,0),new Vector3(),2,2),"Height outside omitted");
   Check(!DioramaBounds.Intersects(Box(2.4f,0,2.4f),new Vector3(),2,2),"Cylinder, not a cube");
   Check(DioramaBounds.Intersects(Box(2.5f,0,0),new Vector3(),2,2),"Tangency and boundary mesh retained");
   Check(DioramaBounds.Intersects(Box(0,0,0,100),new Vector3(),2,2),"Cylinder-enclosing terrain retained");
   Check(DioramaBounds.Intersects(Box(float.NaN,0,0),new Vector3(),2,2),"Invalid bounds fail open");
   Check(DioramaBounds.Intersects(Box(20,0,0),new Vector3(float.NaN,0,0),2,2),"Invalid center fails open");
   Check(DioramaBounds.Intersects(Box(10,0,0),new Vector3(10,0,0),2,2),"Follow original game cylinder center");
   Check(!DioramaBounds.InFrustum(Box(5,0,0),Matrix4x4.identity),"Offscreen bound rejected");
   Check(DioramaBounds.InFrustum(Box(0,0,0),Matrix4x4.identity),"Inside bound retained");
   Check(DioramaBounds.InFrustum(Box(float.PositiveInfinity,0,0),Matrix4x4.identity),"Bad frustum input never hides geometry");
   var inside=new MeshRenderer{bounds=Box(0,0,0)};var outside=new MeshRenderer{bounds=Box(6,0,0)};
   var disabled=new MeshRenderer{bounds=Box(6,0,0),enabled=false};var prefab=new MeshRenderer{bounds=Box(6,0,0)};prefab.gameObject.scene=new Scene();
   var inactive=new MeshRenderer{bounds=Box(6,0,0)};inactive.gameObject.activeInHierarchy=false;
   var ui=new MeshRenderer{bounds=Box(6,0,0)};ui.gameObject.layer=5;
   Resources.Snapshot=new Renderer[]{inside,outside,disabled,prefab,inactive,ui};
   var visibility=new DioramaVisibility();visibility.Refresh(~(1<<5));visibility.HideOutside(new Vector3(),2,2);
   Check(visibility.Count==4&&visibility.LastHidden==1&&!outside.enabled&&inside.enabled,"Only eligible exterior scene meshes suppressed");
   Check(!disabled.enabled&&prefab.enabled&&inactive.enabled&&ui.enabled,"Game disabled, inactive, prefab and UI states preserved");
   visibility.Restore();visibility.Restore();Check(outside.enabled&&!disabled.enabled,"Idempotent restore does not enable game-disabled meshes");
   outside.bounds=Box(0,0,0);visibility.HideOutside(new Vector3(),2,2);Check(visibility.LastHidden==0,"Moving bounds are live, not stale");
   outside.bounds=Box(6,0,0);visibility.HideOutside(new Vector3(),2,2);visibility.Clear();Check(outside.enabled&&visibility.Count==0,"Cleanup restores hidden geometry");
   var solidMaterial=new Material{shader=new Shader{name="Standard"}};
   var batchA=new MeshRenderer{bounds=Box(0,0,0),isPartOfStaticBatch=true,Filter=new MeshFilter{sharedMesh=new Mesh{Buffer=new System.IntPtr(42)}},sharedMaterials=new[]{solidMaterial}};
   var batchB=new MeshRenderer{bounds=Box(50,0,0),isPartOfStaticBatch=true,Filter=new MeshFilter{sharedMesh=batchA.Filter.sharedMesh},sharedMaterials=new[]{solidMaterial}};
   Resources.Snapshot=new Renderer[]{batchA,batchB};var caps=new CutSurfaceRegistry();caps.Refresh();
   Check(NativeBridge.Registrations==1&&NativeBridge.Bounded&&NativeBridge.LastBounds.Maximum.x>50,"Union every contributor of shared static index buffer");
   var mixed=new MeshRenderer{bounds=Box(100,0,0),Filter=new MeshFilter{sharedMesh=batchA.Filter.sharedMesh},sharedMaterials=new[]{new Material{renderQueue=3000,shader=new Shader{name="Transparent"}}}};
   Resources.Snapshot=new Renderer[]{batchA,batchB,mixed};caps.Refresh();
   Check(NativeBridge.Registrations==1&&!NativeBridge.Bounded,"Moving/mixed-material contributor disables shared-buffer pruning");caps.Clear();
   var liquid=new Renderer{bounds=Box(0,0,0),sharedMaterials=new[]{new Material{shader=new Shader{name="Toony Colors Pro 2/Examples/Cat Demo/Water"}}}};
   Resources.Snapshot=new[]{liquid};var depth=new LiquidDepthPolicy();depth.Refresh();var camera=new Camera();
   Check(depth.Visible(camera,true,new Vector3(),2,2),"Visible liquid requests depth");
   liquid.bounds=Box(6,0,0);Check(depth.NeedsDepth&&!depth.Visible(camera,false,new Vector3(),2,2),"Active offscreen water no longer forces depth");
   liquid.bounds=Box(0,0,0);Check(!depth.Visible(camera,true,new Vector3(8,0,0),2,2),"In-frustum water outside cylinder does not request depth");
   camera.cullingMask=0;Check(!depth.Visible(camera,false,new Vector3(),2,2),"Layer-hidden liquid needs no depth");camera.cullingMask=-1;
   liquid.enabled=false;Check(!depth.Visible(camera,false,new Vector3(),2,2),"Game-disabled water unchanged");
   var graphic=new UnityEngine.UI.Image();var rect=new RectTransform();var group=new CanvasGroup();var nested=new Canvas();
   var parent=new Transform{ParentGroup=new CanvasGroup()};var canvas=new Canvas{Children=new object[]{graphic,rect,group,nested}};canvas.transform.parent=parent;
   var cache=new UiCaptureCache();cache.BeginScan();cache.Watch(canvas);
   Check(cache.NeedsCapture()&&graphic.Listeners==3,"Initial capture and dirty listeners");cache.Captured();
   Check(!cache.NeedsCapture()&&cache.Reuses==1,"Static UI reuses full-resolution target");
   for(int i=0;i<3;i++){graphic.Dirty(i);Check(cache.NeedsCapture(),"Vertex/material/layout event invalidates capture");cache.Captured();}
   rect.localPosition=new Vector3(1,0,0);Check(cache.NeedsCapture(),"Tweened transform position");cache.Captured();
   rect.rect=new Rect{width=12,height=2};Check(cache.NeedsCapture(),"Layout rect change");cache.Captured();
   rect.gameObject.activeInHierarchy=false;Check(cache.NeedsCapture(),"Inactive UI visibility");cache.Captured();
   graphic.enabled=false;Check(cache.NeedsCapture(),"Disabled Graphic without dirty callback");cache.Captured();
   nested.enabled=false;Check(cache.NeedsCapture(),"Nested canvas disable without Graphic callback");cache.Captured();
   group.alpha=.2f;Check(cache.NeedsCapture(),"CanvasGroup alpha animation");cache.Captured();
   group.ignoreParentGroups=true;Check(cache.NeedsCapture(),"CanvasGroup inheritance switch");cache.Captured();
   parent.ParentGroup.alpha=.5f;Check(cache.NeedsCapture(),"Parent group outside canvas hierarchy");cache.Captured();
   Check(!cache.NeedsCapture(),"Settled UI becomes reusable again");cache.Clear();Check(graphic.Listeners==0,"Unsubscribe on cleanup");
   var animator=new Animator();canvas.Children=new object[]{graphic,animator};cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(cache.NeedsCapture(),"Animation retains configured cadence");animator.enabled=false;cache.Captured();Check(!cache.NeedsCapture(),"Disabled animation does not force capture");
   graphic.material=new Material();cache.BeginScan();cache.Watch(canvas);cache.Captured();Check(cache.NeedsCapture(),"Custom material animation conservative fallback");
   cache.BeginScan();cache.Watch(canvas);Check(graphic.Listeners==3,"Repeated cache refresh never duplicates callbacks");cache.Clear();
   var subMesh=new UnityEngine.UI.UninitializedSubMesh{enabled=false};canvas.Children=new object[]{subMesh};
   cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(subMesh.MaterialReads==0&&cache.NeedsCapture(),"Uninitialized/inactive TMP-like virtual material getters never touched");
   subMesh.enabled=true;cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(subMesh.MaterialReads==0&&cache.NeedsCapture(),"Active unknown graphics also retain normal cadence without cloning material");
   cache.DisableReuse();Check(cache.Failed&&cache.NeedsCapture()&&subMesh.Listeners==0,"Failed cache releases listeners and fails open");
   cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(cache.Failed&&cache.NeedsCapture()&&subMesh.MaterialReads==0&&subMesh.Listeners==0,"Circuit breaker survives scene/maintenance scans");
   return count;
  }
 }
}
'@
Add-Type -TypeDefinition ("using System;using System.Collections.Generic;using UnityEngine;using UnityEngine.Events;using UnityEngine.UI;`n"+$fixture+($sources -join "`n")+$tests)
$count=[QVVR.PerformanceTests]::Run()
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
 $renderer=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
 $eye=($renderer.Methods | Where-Object Name -eq 'RenderEye').Body.Instructions
 foreach($call in @('Visible','ConfigureHudCommands','QVVR_SetCapCullVolume','ResolveAntiAliasedSurface')){
  if(!($eye | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq $call})){throw "Missing optimization integration: $call"}
 }
 $hud=($renderer.Methods | Where-Object Name -eq 'ConfigureHudCommands').Body.Instructions
 foreach($call in @('ClearRenderTarget','DrawMesh','IssuePluginEvent')){
  if(!($hud | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq $call})){throw "Missing direct HUD safety route: $call"}
 }
 $clear=$hud | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'ClearRenderTarget'}
 $draw=$hud | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'DrawMesh'}
 if($clear.Offset -ge $draw.Offset){throw 'HUD must clear depth before direct draw.'}
 $late=($renderer.Methods | Where-Object Name -eq 'LateUpdate').Body
 $restore=$late.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'DioramaVisibility' -and $_.Operand.Name -eq 'Restore'}
 if(!$restore -or !($late.ExceptionHandlers | Where-Object {$_.HandlerType -eq 'Finally' -and $restore.Offset -ge $_.HandlerStart.Offset -and $restore.Offset -lt $_.HandlerEnd.Offset})){throw 'Temporary world culling must restore in finally.'}
 $ui=$assembly.MainModule.Types | Where-Object Name -eq 'UiCaptureCache'
 $redirect=($renderer.Methods | Where-Object Name -eq 'RedirectOverlayCanvases').Body
 $disable=$redirect.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'DisableReuse'}
 if(!$disable -or !($redirect.ExceptionHandlers | Where-Object {$_.HandlerType -eq 'Catch' -and $disable.Offset -ge $_.HandlerStart.Offset -and $disable.Offset -lt $_.HandlerEnd.Offset})){throw 'Optional UI cache errors must not kill scene maintenance.'}
 if(($ui.Methods | Where-Object Name -eq 'NeedsCapture').Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'set_hasChanged'}){throw 'Never consume game-owned transform flags.'}
} finally {$assembly.Dispose()}
Write-Host "Performance policies: $count assertions plus compiled HUD/visibility/depth/lifecycle integration passed. API doubles, not a Frame benchmark."
