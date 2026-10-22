[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$sources=@('DioramaVisibility.cs','UiCaptureCache.cs','UiMaterialWatch.cs','LiquidDepthPolicy.cs','CutSurfaceRegistry.cs') | ForEach-Object {
 (Get-Content (Join-Path $root "src/QVVR/$_") -Raw) -replace '(?m)^using .*;\r?\n',''
}
$fixture=Get-Content (Join-Path $PSScriptRoot 'performance-fixture.cs') -Raw
$tests=@'
namespace QVVR {
 internal static class TmpFixture {
  static readonly System.Reflection.Emit.ModuleBuilder Module=System.Reflection.Emit.AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("Unity.TextMeshPro"),System.Reflection.Emit.AssemblyBuilderAccess.Run).DefineDynamicModule("Fixture");
  static readonly Type Text=Build("TMPro.TextMeshProUGUI","fontSharedMaterial"), Sub=Build("TMPro.TMP_SubMeshUI","sharedMaterial");
  static Type Build(string name,string property){
   var t=Module.DefineType(name,TypeAttributes.Public,typeof(UnityEngine.UI.UninitializedSubMesh));
   var getter=t.DefineMethod("get_"+property,MethodAttributes.Public|MethodAttributes.SpecialName|MethodAttributes.HideBySig,typeof(Material),Type.EmptyTypes);
   var il=getter.GetILGenerator();il.Emit(System.Reflection.Emit.OpCodes.Ldarg_0);il.Emit(System.Reflection.Emit.OpCodes.Ldfld,typeof(UnityEngine.UI.UninitializedSubMesh).GetField("Shared"));il.Emit(System.Reflection.Emit.OpCodes.Ret);
   t.DefineProperty(property,PropertyAttributes.None,typeof(Material),Type.EmptyTypes).SetGetMethod(getter);return t.CreateTypeInfo().AsType();
  }
  internal static UnityEngine.UI.UninitializedSubMesh Create(bool sub,Material shared){var g=(UnityEngine.UI.UninitializedSubMesh)Activator.CreateInstance(sub?Sub:Text);g.Shared=shared;return g;}
 }
 internal static class NativeBridge {
  internal struct CapMeshBounds{internal Vector3 Minimum,Maximum;}
  internal static bool ShaderClipReady=true;internal static bool Bounded;internal static CapMeshBounds LastBounds;internal static int Registrations;
  internal static void QVVR_ClearCapMeshes(){Registrations=0;}
  internal static void QVVR_RegisterCapMesh(System.IntPtr buffer){Registrations++;Bounded=false;}
  internal static void QVVR_RegisterCapMeshBounds(System.IntPtr buffer,ref CapMeshBounds b){Registrations++;Bounded=true;LastBounds=b;}
  internal static int Skipped;internal static System.IntPtr FirstSkipped;
  internal static void QVVR_SetCapSkipMeshes(int slot,System.IntPtr pointer,int count){Skipped=count;FirstSkipped=count>0?System.Runtime.InteropServices.Marshal.ReadIntPtr(pointer):System.IntPtr.Zero;}
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
   batchA.isPartOfStaticBatch=false;batchB.isPartOfStaticBatch=false;
   batchA.bounds=Box(0,0,0);batchB.bounds=Box(0,0,0);Resources.Snapshot=new Renderer[]{batchA,batchB};caps.Refresh();
   caps.PrepareFrame(0,new Vector3(),2,2);Check(NativeBridge.Skipped==1&&NativeBridge.FirstSkipped==new System.IntPtr(42),"Live ordinary shared meshes wholly inside cylinder skip caps");
   batchB.bounds=Box(2,0,0);caps.PrepareFrame(1,new Vector3(),2,2);Check(NativeBridge.Skipped==0,"Moving one shared contributor onto boundary restores full caps");
   batchB.bounds=Box(float.NaN,0,0);caps.PrepareFrame(2,new Vector3(),2,2);Check(NativeBridge.Skipped==0,"Invalid live contributor fails open for entire shared buffer");
   batchB.bounds=Box(0,0,0,100);caps.PrepareFrame(3,new Vector3(),2,2);Check(NativeBridge.Skipped==0,"Cylinder-enclosing terrain retains caps");
   batchA.bounds=Box(10,0,0);batchB.bounds=Box(10,0,0);caps.PrepareFrame(4,new Vector3(),2,2);Check(NativeBridge.Skipped==1,"Wholly exterior buffer needs no boundary stencil");
   caps.PrepareFrame(5,new Vector3(float.NaN,0,0),2,2);Check(NativeBridge.Skipped==0,"Invalid cylinder keeps full replay");
   batchB.Filter.sharedMesh=new Mesh{Buffer=new System.IntPtr(99)};caps.PrepareFrame(6,new Vector3(),2,2);
   Check(caps.NeedsRefresh&&NativeBridge.Skipped==0,"Mesh replacement clears all skips until cold registry refresh");
   caps.PrepareFrame(7,new Vector3(),2,2);Check(NativeBridge.Skipped==0,"Pending topology discovery keeps replay enabled");
   caps.Refresh();caps.PrepareFrame(8,new Vector3(),2,2);Check(!caps.NeedsRefresh&&NativeBridge.Skipped==2,"Cold discovery recovers correct buffer groups after replacement");
   caps.Clear();caps.PrepareFrame(0,new Vector3(),2,2);Check(NativeBridge.Skipped==0&&caps.LastSkipped==0,"Clear unpins staging and clears future frame snapshot");
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
   cache.BeginScan();cache.Watch(canvas);cache.Captured();graphic.canvasRenderer.Color=new Color{a=.5f};
   Check(cache.NeedsCapture(),"CanvasRenderer alpha tween without graphic dirtiness");cache.Captured();Check(!cache.NeedsCapture(),"Settled color tween is reusable");
   var animator=new Animator();canvas.Children=new object[]{graphic,animator};cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(cache.NeedsCapture(),"Animation retains configured cadence");animator.enabled=false;cache.Captured();Check(!cache.NeedsCapture(),"Disabled animation does not force capture");
   graphic.enabled=true;graphic.material=new Material();cache.BeginScan();cache.Watch(canvas);cache.Captured();Check(cache.NeedsCapture(),"Custom material animation conservative fallback");
   cache.BeginScan();cache.Watch(canvas);Check(graphic.Listeners==3,"Repeated cache refresh never duplicates callbacks");cache.Clear();
   var subMesh=new UnityEngine.UI.UninitializedSubMesh{enabled=false};canvas.Children=new object[]{subMesh};
   cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(subMesh.MaterialReads==0&&!cache.NeedsCapture(),"Disabled unknown graphics do not poison the HUD or touch virtual getters");
   subMesh.enabled=true;cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(subMesh.MaterialReads==0&&cache.NeedsCapture(),"Active unknown graphics also retain normal cadence without cloning material");
   subMesh.gameObject.activeInHierarchy=false;cache.Captured();Check(!cache.NeedsCapture(),"Inactive custom submesh does not force continuous capture");
   var sdf=new Material{shader=new Shader{name="TextMeshPro/Mobile/Distance Field"}};
   var text=TmpFixture.Create(false,sdf);var tmpSub=TmpFixture.Create(true,sdf);canvas.Children=new object[]{text,tmpSub};
   cache.BeginScan();cache.Watch(canvas);cache.Captured();Check(!cache.NeedsCapture()&&text.MaterialReads==0&&tmpSub.MaterialReads==0,"Known TMP SDF and submesh reuse safely through shared getters");
   var observerMap=(Dictionary<UnityEngine.UI.Graphic,UiMaterialWatch>)typeof(UiCaptureCache).GetField("cachedMaterialWatches",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(cache);
   var observer=observerMap[text];cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(object.ReferenceEquals(observer,observerMap[text])&&!cache.NeedsCapture(),"Regular maintenance retains cold-bound shared getter delegates");
   text.Dirty(0);Check(cache.NeedsCapture(),"TMP text edits invalidate capture");cache.Captured();
   text.Shared=new Material{shader=sdf.shader};Check(cache.NeedsCapture(),"TMP shared material replacement cannot freeze UI");text.Shared=sdf;
   sdf.shader=new Shader{name="Custom/AnimatedText"};Check(cache.NeedsCapture(),"In-place shader replacement fails open");
   sdf.shader=new Shader{name="TextMeshPro/Distance Field"};cache.BeginScan();cache.Watch(canvas);cache.Captured();Check(!cache.NeedsCapture(),"Non-scrolling full SDF is reusable");
   sdf.Floats[Shader.PropertyToID("_FaceUVSpeedX")]=1;Check(cache.NeedsCapture(),"Time-driven face texture scrolling retains capture rate");
   sdf.Floats.Clear();sdf.Floats[Shader.PropertyToID("_OutlineUVSpeedY")]=1;Check(cache.NeedsCapture(),"Time-driven outline texture scrolling retains capture rate");
   var uninitialized=TmpFixture.Create(true,null);canvas.Children=new object[]{uninitialized};cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(cache.NeedsCapture()&&uninitialized.MaterialReads==0,"Null TMP shared material safely retains cadence without cloning");
   var light=new UiCaptureCache();var ordinary=new UnityEngine.UI.Image();canvas.Children=new object[]{ordinary};
   Check(light.BeginMaintenance(0,true,true),"First lightweight maintenance discovers UI");light.Watch(canvas);light.EndMaintenance(0,true);light.Captured();
   Check(!light.Suspended&&!light.NeedsCapture()&&ordinary.Listeners==3,"Static UI retains adaptive capture");
   light.BeginMaintenance(.5f,true,true);light.Watch(canvas);light.EndMaintenance(.5f,true);light.Captured();
   Check(ordinary.Registrations==3&&ordinary.Listeners==3,"Unchanged graphics keep existing subscriptions across maintenance");
   var replacement=new UnityEngine.UI.Image();canvas.Children=new object[]{replacement};light.BeginMaintenance(1,true,true);light.Watch(canvas);light.EndMaintenance(1,true);light.Captured();
   Check(ordinary.Listeners==0&&replacement.Listeners==3,"Removed widgets are unsubscribed and new widgets watched");
   replacement.material=new Material();light.BeginMaintenance(2,true,true);light.Watch(canvas);light.EndMaintenance(2,true);
   Check(light.Suspended&&light.ContinuousReason==2&&replacement.Listeners==0&&light.NeedsCapture(),"Unknown/animated UI keeps full capture rate without dead snapshot subscriptions");
   Check(!light.BeginMaintenance(2.5f,true,true),"Suspended cache skips repeated heavy rebuilds until the recovery probe");
   replacement.material=null;light.Captured();Check(light.NeedsCapture(),"Untracked changes during suspension cannot freeze capture");
   Check(light.BeginMaintenance(4,true,true),"Periodic recovery probe still runs");light.Watch(canvas);light.EndMaintenance(4,true);light.Captured();
   Check(!light.Suspended&&!light.NeedsCapture()&&replacement.Listeners==3,"Ordinary UI can recover adaptive reuse after suspension");
   replacement.material=new Material();light.BeginMaintenance(5,true,true);light.Watch(canvas);light.EndMaintenance(5,true);
   Check(light.BeginMaintenance(5.1f,true,false),"Rollback switch bypasses suspension immediately");light.Watch(canvas);light.EndMaintenance(5.1f,false);light.Captured();
   Check(!light.Suspended&&replacement.Listeners==3&&light.NeedsCapture(),"Legacy full-tracking fallback retains animated material updates");
   Check(!light.BeginMaintenance(6,false,true)&&replacement.Listeners==0,"Disabling adaptive UI releases its tracking work");
   light.BeginMaintenance(7,true,true);light.Watch(canvas);light.EndMaintenance(7,true);
   for(int i=0;i<64;i++){light.NeedsCapture();light.Captured();}
   long allocated=GC.GetAllocatedBytesForCurrentThread();for(int i=0;i<512;i++){light.NeedsCapture();light.Captured();}
   Check(allocated==GC.GetAllocatedBytesForCurrentThread(),"Suspended full-rate capture accounting allocates zero warmed managed bytes");
   light.Clear();Check(!light.Suspended&&replacement.Listeners==0,"Scene cleanup resets lightweight recovery and subscriptions");
   cache.DisableReuse();Check(cache.Failed&&cache.NeedsCapture()&&subMesh.Listeners==0,"Failed cache releases listeners and fails open");
   cache.BeginScan();cache.Watch(canvas);cache.Captured();
   Check(cache.Failed&&cache.NeedsCapture()&&subMesh.MaterialReads==0&&subMesh.Listeners==0,"Circuit breaker survives scene/maintenance scans");
   return count;
  }
 }
}
'@
Add-Type -TypeDefinition ("using System;using System.Reflection;using System.Runtime.InteropServices;using System.Collections.Generic;using UnityEngine;using UnityEngine.Events;using UnityEngine.UI;`n"+$fixture+($sources -join "`n")+$tests)
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
 $prepareCaps=$late.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'CutSurfaceRegistry' -and $_.Operand.Name -eq 'PrepareFrame'}
 $stereo=$late.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'RenderStereoGameplay'}
 if(!$prepareCaps -or $prepareCaps.Offset -ge $stereo[0].Offset){throw 'Live cap snapshot must precede both manual eyes.'}
 $maintenance=$renderer.NestedTypes | Where-Object Name -like '<CanvasMaintenance>*'
 $move=($maintenance.Methods | Where-Object Name -eq 'MoveNext').Body.Instructions
 $endFrame=$move | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'WaitForEndOfFrame'}
 $scan=$move | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'RedirectOverlayCanvases'}
 if(!$endFrame -or $endFrame.Count -ne 1 -or !$scan -or $endFrame.Offset -ge $scan.Offset){throw 'Maintenance must reuse a cached end-of-frame yield before cold scans.'}
 foreach($methodName in @('BeginMaintenance','EndMaintenance')){
  if(!($redirect.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'UiCaptureCache' -and $_.Operand.Name -eq $methodName})){throw "Missing lightweight cache lifecycle integration: $methodName"}
 }
 # Verify the release branch can actually jump over validation-only hot work.
 foreach($pair in @(@('LateUpdate','SampleDioramaStability'),@('RenderEye','get_determinant'))){
  $body=($renderer.Methods | Where-Object Name -eq $pair[0]).Body.Instructions
  $call=$body | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq $pair[1]}
  $guard=$body | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'diagnosticsEnabled' -and $_.Next.OpCode.Name -like 'brfalse*' -and $_.Offset -lt $call.Offset -and $_.Next.Operand.Offset -gt $call.Offset}
  if(!$call -or !$guard){throw "Developer-only render work must be guarded: $($pair -join '.')"}
 }
 $log=($renderer.Methods | Where-Object Name -eq 'LogFrameTiming').Body.Instructions
 if(!($log | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'lastDiagnosticLogMilliseconds'})){throw 'Log batch time must be reported separately from maintenance.'}
 if(!($move | Where-Object {$_.OpCode.Name -eq 'ldc.r4' -and [float]$_.Operand -eq 30}) -or !($move | Where-Object {$_.OpCode.Name -eq 'ldc.r4' -and [float]$_.Operand -eq 5})){throw 'Normal and developer logging cadences must both remain available.'}
} finally {$assembly.Dispose()}
if($GameDir){
 $tmp=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $GameDir 'QV_Data/Managed/Unity.TextMeshPro.dll'))
 try {
  if($tmp.Name.Name -ne 'Unity.TextMeshPro'){throw 'Unexpected installed TMP assembly identity.'}
  foreach($pair in @(@('TMP_Text','get_fontSharedMaterial'),@('TMP_SubMeshUI','get_sharedMaterial'))){
   $type=$tmp.MainModule.Types | Where-Object Name -eq $pair[0]
   $method=$type.Methods | Where-Object Name -eq $pair[1]
   $il=@($method.Body.Instructions)
   if($il.Count -ne 3 -or $il[0].OpCode.Name -ne 'ldarg.0' -or $il[1].OpCode.Name -ne 'ldfld' -or $il[2].OpCode.Name -ne 'ret' -or $il[1].Operand.FieldType.FullName -ne 'UnityEngine.Material'){
    throw "Installed TMP shared getter is no longer a direct non-cloning field read: $($pair[1])"
   }
  }
 }finally{$tmp.Dispose()}
 Write-Host 'Installed TMP shared getters verified by read-only metadata: direct Material field reads, no instantiation or calls.'
}
Write-Host "Performance policies: $count assertions plus compiled HUD/visibility/depth/lifecycle integration passed. API doubles, not a Frame benchmark."
