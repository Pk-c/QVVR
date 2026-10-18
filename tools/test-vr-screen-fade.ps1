[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=(Get-Content (Join-Path $root 'src/QVVR/VrScreenFade.cs') -Raw).Replace('using UnityEngine;','').Replace('using UnityEngine.UI;','')
# Actual production fade with API doubles. Synthetic framebuffer math only:
# never reads, creates or captures game/headset eye images.
$fixture=@'
namespace UnityEngine {
 public class Object { public static int Destroyed;public static void Destroy(Object value){Destroyed++;} }
 public enum HideFlags { HideAndDontSave }
 public class Shader:Object {public static bool Available=true;public bool isSupported=true;public static Shader Find(string name){return Available?new Shader():null;} }
 public class Texture2D:Object {public static Texture2D whiteTexture=new Texture2D();}
 public struct Color { public float r,g,b,a;public Color(float r,float g,float b,float a){this.r=r;this.g=g;this.b=b;this.a=a;}public static Color white{get{return new Color(1,1,1,1);}}public static Color clear{get{return new Color(0,0,0,0);}} }
 public class Material:Object {public static bool Pass=true;public static int Created;public string name;public HideFlags hideFlags;public Texture2D mainTexture;public Color color;public Material(Shader shader){Created++;}public bool SetPass(int pass){return Pass;} }
 public class GameObject {public bool activeInHierarchy=true;}
 public class CanvasRenderer {public bool cull;}
 public class RenderTexture {public static RenderTexture active;public Color Pixel;}
 public static class Mathf {public static float Clamp01(float value){return System.Math.Max(0,System.Math.Min(1,value));}}
 public static class GL {
  public const int QUADS=7;public static int Stack,Draws,Vertices,DepthClears;static Color color;
  public static void PushMatrix(){Stack++;}public static void PopMatrix(){Stack--;}
  public static void LoadOrtho(){}public static void Begin(int mode){if(mode!=QUADS)throw new System.Exception("Not a full-screen quad");}
  public static void Color(Color value){color=value;}public static void Vertex3(float x,float y,float z){Vertices++;}
  public static void Clear(bool depth,bool clearColor,Color value){if(clearColor)throw new System.Exception("World color cleared");if(depth)DepthClears++;}
  public static void End(){Draws++;var pixel=RenderTexture.active.Pixel;float inverse=1-color.a;
   RenderTexture.active.Pixel=new Color(pixel.r*inverse,pixel.g*inverse,pixel.b*inverse,color.a+pixel.a*inverse);}
 }
}
namespace UnityEngine.UI {public class Image {public bool enabled=true;public UnityEngine.Color color;public UnityEngine.GameObject gameObject=new UnityEngine.GameObject();public UnityEngine.CanvasRenderer canvasRenderer=new UnityEngine.CanvasRenderer();}}
namespace QVVR {
 public static class ScreenFadeTests {
  static int checks;static void Check(bool ok,string message){checks++;if(!ok)throw new System.Exception(message);}
  static bool Near(float a,float b){return System.Math.Abs(a-b)<.00001f;}
  public static int Run(){
   var fade=new VrScreenFade();fade.Initialize();var image=new Image{color=new Color(0,0,0,0)};fade.Begin(image);
   var previous=new RenderTexture();RenderTexture.active=previous;
   var left=new RenderTexture{Pixel=new Color(.4f,.2f,.1f,.25f)};var right=new RenderTexture{Pixel=left.Pixel};
   fade.Prepare();fade.Render(left);Check(GL.Draws==0,"No additional draw while alpha is zero.");
   Check(image.canvasRenderer.cull&&image.enabled,"Only original graphic draw is culled; no Image enable/layout callbacks.");fade.Restore();Check(!image.canvasRenderer.cull,"Original cull state restored.");
   image.color=new Color(0,0,0,.5f);fade.Prepare();fade.Render(left);fade.Render(right);
   Check(Near(left.Pixel.r,.2f)&&Near(left.Pixel.a,.625f),"Premultiplied fade darkens game RGB and covers passthrough alpha correctly.");
   Check(Near(right.Pixel.r,left.Pixel.r)&&Near(right.Pixel.a,left.Pixel.a),"Both eyes use exactly one sampled fade opacity.");
   Check(RenderTexture.active==previous&&GL.Stack==0,"Render target/matrix stack restored after each eye.");
   Check(GL.Vertices==8&&GL.DepthClears==2,"Exactly one full-eye quad/depth-only clear per eye.");
   Check(Near(image.color.a,.5f),"Game-owned tween alpha untouched.");fade.Prepare();fade.Restore();
   Check(!image.canvasRenderer.cull,"Retried preparation never loses original graphic cull state.");
   fade.SceneChanged(false,true);image.color=Color.clear;fade.Prepare();fade.Restore();
   Check(Near(fade.Opacity,0),"Loading fade-in can reach zero without releasing transition.");
   image.color=new Color(0,0,0,1);fade.Prepare();fade.Render(left);fade.Restore();
   Check(Near(left.Pixel.r,0)&&Near(left.Pixel.a,1),"Subsequent Loading fade-out is full opaque black, including passthrough.");
   fade.SceneChanged(true,false);image.color=new Color(0,0,0,.25f);fade.Prepare();Check(Near(fade.Opacity,.25f),"Gameplay fade-in is still mirrored.");fade.Restore();
   image.color=Color.clear;fade.Prepare();Check(image.enabled&&Near(fade.Opacity,0),"Gameplay clear completes replacement without leaving source hidden.");
   image.color=new Color(0,0,0,.9f);fade.Prepare();Check(Near(fade.Opacity,0)&&image.enabled,"Unrelated later fades remain original after transition.");
   fade.Begin(image);fade.Prepare();fade.SceneChanged(false,false);Check(!image.canvasRenderer.cull&&Near(fade.Opacity,0),"Aborted scene restores source and clears fade.");
   fade.Begin(image);fade.Prepare();fade.Release();Check(!image.canvasRenderer.cull&&Near(fade.Opacity,0),"Shutdown/desktop recovery restores source.");
   Check(Material.Created==1,"Reentry reuses one material; no per-frame resource creation.");
   Shader.Available=false;var fallback=new VrScreenFade();fallback.Initialize();fallback.Begin(image);fallback.Prepare();
   Check(image.enabled&&Near(fallback.Opacity,0),"Missing shader preserves original fade rectangle as safe fallback.");Shader.Available=true;
   var failed=new VrScreenFade();failed.Initialize();failed.Begin(image);failed.Prepare();Material.Pass=false;failed.Render(right);
   Check(image.enabled&&RenderTexture.active==previous&&GL.Stack==0&&Near(failed.Opacity,0),"SetPass failure restores source/target/matrices.");Material.Pass=true;
   return checks;
  }
 }
}
'@
Add-Type -TypeDefinition ('using UnityEngine;using UnityEngine.UI;'+$source+$fixture)
$count=[QVVR.ScreenFadeTests]::Run()
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try{
 $renderer=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
 $eye=($renderer.Methods | Where-Object Name -eq 'RenderEye').Body.Instructions
 $resolve=$eye | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'ResolveAntiAliasedSurface'}
 $fadeCall=$eye | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'VrScreenFade' -and $_.Operand.Name -eq 'Render'}
 if(@($fadeCall).Count -ne 1 -or $fadeCall.Offset -le $resolve.Offset){throw 'VR fade must draw once per eye after HUD/MSAA resolve.'}
 $late=$renderer.Methods | Where-Object Name -eq 'LateUpdate'
 $prepare=$late.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'VrScreenFade' -and $_.Operand.Name -eq 'Prepare'}
 $ui=$late.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'CaptureUi'}
 if(!$prepare -or $prepare.Offset -ge $ui.Offset){throw 'Hide source before UI capture.'}
 $restored=$false
 foreach($handler in $late.Body.ExceptionHandlers | Where-Object HandlerType -eq 'Finally'){
  if($late.Body.Instructions | Where-Object {$_.Offset -ge $handler.HandlerStart.Offset -and $_.Offset -lt $handler.HandlerEnd.Offset -and $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'VrScreenFade' -and $_.Operand.Name -eq 'Restore'}){$restored=$true}
 }
 if(!$restored){throw 'Source fade must restore in a rendering finally block.'}
 foreach($name in @('BeginStageFade','PositionPanels')){
  if(!(($renderer.Methods | Where-Object Name -eq $name).Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'introScene'})){throw "Intro-only guard missing: $name"}
 }
 $scene=($renderer.Methods | Where-Object Name -eq 'OnActiveSceneChanged').Body.Instructions
 if(!($scene | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'VrScreenFade' -and $_.Operand.Name -eq 'SceneChanged'})){throw 'Fade must survive Loading and finish in gameplay.'}
}finally{$assembly.Dispose()}
if($GameDir){
 $game=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $GameDir 'QV_Data/Managed/Assembly-CSharp.dll'))
 try{
  $cloud=$game.MainModule.Types | Where-Object Name -eq 'Cloud'
  if(!($cloud.Fields | Where-Object {$_.Name -eq 'Panel' -and $_.FieldType.FullName -eq 'UnityEngine.UI.Image'})){throw 'Verified Cloud.Panel image unavailable.'}
  if(!($cloud.Methods | Where-Object {$_.Name -eq 'FadeOut' -and $_.Parameters.Count -eq 2})){throw 'Verified Cloud.FadeOut hook unavailable.'}
  $stage=$game.MainModule.Types | Where-Object Name -eq 'IntroStageManager'
  $wait=$stage.NestedTypes | Where-Object Name -match '^<WaitGoGame>'
  $next=($wait.Methods | Where-Object Name -eq 'MoveNext').Body.Instructions
  foreach($call in @('FadeOut','LoadScene')){if(!($next | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq $call})){throw "Verified level transition changed: $call"}}
  $exit=$game.MainModule.Types | Where-Object Name -eq 'IntroExitManager'
  if(!($exit.Fields | Where-Object {$_.FieldType.Name -eq 'AchievementDisplay'})){throw 'Hub achievements owner changed.'}
  foreach($method in @('Enter','OpenAchievementWindow')){if(!($exit.Methods | Where-Object Name -eq $method)){throw "Hub pause entry point missing: $method"}}
 }finally{$game.Dispose()}
}
Write-Host "VR screen fade: $count production-code assertions plus compiled render/lifecycle/scope guards passed. Synthetic API doubles, not headset GPU validation."
