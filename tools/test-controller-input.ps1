[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$files=@('ControllerButtonPolicy.cs','ControllerInputConfiguration.cs','OpenVrInputBridge.cs','GripGestureState.cs','ComfortMath.cs')
$sources=$files | ForEach-Object {(Get-Content (Join-Path $root "src/QVVR/$_") -Raw) -replace '(?m)^using .*;\r?\n',''}
# Production bridge/config/policy, fake APIs only. No game, SteamVR or XR session.
$fixture=@'
namespace BepInEx.Configuration {
 public class ConfigDefinition {public string Section,Key;}
 public class ConfigEntryBase {public ConfigDefinition Definition;}
 public class SettingChangedEventArgs:EventArgs {public ConfigEntryBase ChangedSetting;}
 public class ConfigEntry<T>:ConfigEntryBase {
  T value;ConfigFile owner;public ConfigEntry(ConfigFile f,string section,string key,T v){owner=f;Definition=new ConfigDefinition{Section=section,Key=key};value=v;}
  public T Value{get{return value;}set{this.value=value;owner.Changed(this);}}
 }
 public class ConfigFile {
  Dictionary<string,ConfigEntryBase> values=new Dictionary<string,ConfigEntryBase>();public event EventHandler<SettingChangedEventArgs> SettingChanged;
  public ConfigEntry<T> Bind<T>(string section,string key,T value,string description){var entry=new ConfigEntry<T>(this,section,key,value);values[section+"/"+key]=entry;return entry;}
  public ConfigEntry<T> Get<T>(string key){return (ConfigEntry<T>)values["Input/"+key];}
  public void Changed(ConfigEntryBase entry){if(SettingChanged!=null)SettingChanged(this,new SettingChangedEventArgs{ChangedSetting=entry});}
 }
}
namespace UnityEngine {
 public class MonoBehaviour {}
 public static class Time {public static int frameCount;public static float timeScale=1f;}
 [AttributeUsage(AttributeTargets.Class)]public class DefaultExecutionOrder:Attribute{public DefaultExecutionOrder(int order){}}
 public struct Vector2 {public float x,y;public Vector2(float a,float b){x=a;y=b;}public float sqrMagnitude{get{return x*x+y*y;}}}
 public static class Mathf {public static float Abs(float v){return Math.Abs(v);}}
}
namespace Valve.VR {
 public struct Axis {public float x,y;}
 public struct VRControllerState_t {public ulong ulButtonPressed;public Axis rAxis0,rAxis1,rAxis2;}
 public enum ETrackedControllerRole {LeftHand,RightHand}
 public static class OpenVR {public const uint k_unTrackedDeviceIndexInvalid=0xffffffff;}
 public class CVRCompositor {}
 public class CVRSystem {
  public VRControllerState_t Left,Right;public bool HasLeft=true,HasRight=true;
  public uint GetTrackedDeviceIndexForControllerRole(ETrackedControllerRole r){return r==ETrackedControllerRole.LeftHand?1u:2u;}
  public bool GetControllerState(uint id,ref VRControllerState_t state,uint size){bool has=id==1?HasLeft:HasRight;if(has)state=id==1?Left:Right;return has;}
 }
}
namespace HarmonyLib {
 public class Harmony {public Harmony(string id){} public void Patch(MethodInfo m,HarmonyMethod prefix=null,HarmonyMethod postfix=null,HarmonyMethod finalizer=null){}public void UnpatchSelf(){}}
 public class HarmonyMethod {public HarmonyMethod(Type t,string name){}}
 public static class AccessTools {
  public static Type TypeByName(string name){return null;}
  public static MethodInfo Method(Type t,string name,Type[] args=null){return t.GetMethod(name,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance|BindingFlags.Static);}
 }
}
namespace QVVR {
 internal class Logger {public void LogInfo(string s){}public void LogError(string s){}public void LogWarning(string s){}}
 internal class Plugin {
  internal const string Guid="fixture";internal static Logger Log=new Logger();
  internal ConfigEntry<bool> VrEnabled,VrControllerInput,TwoGripWorldGrab;internal ControllerInputConfiguration InputControls;
  internal ConfigFile File=new ConfigFile();
  internal Plugin(){VrEnabled=File.Bind("Controls","VR",true,"");VrControllerInput=File.Bind("Controls","Input",true,"");TwoGripWorldGrab=File.Bind("Controls","Grips",true,"");InputControls=new ControllerInputConfiguration(File);}
 }
 internal class VrSettingsMenu {
  internal bool Visible;internal float X,Y;internal bool Confirm,Back;internal void Toggle(){Visible=!Visible;}
  internal void HandleInput(float x,float y,bool confirm,bool back){X=x;Y=y;Confirm=confirm;Back=back;if(back)Visible=false;}
 }
 internal class OpenVrRenderer {
  internal bool UsesOpenXr=true,HasInputFocus=true,CanGrabWorld=true,UseGameShoulders=true;
  internal VRControllerState_t Left,Right;internal bool HasLeft=true,HasRight=true;internal bool Rotate=false;
  internal bool PrepareTracking(){return true;}
  internal bool GetXrControllerState(bool left,ref VRControllerState_t state){bool has=left?HasLeft:HasRight;if(has)state=left?Left:Right;return has;}
  internal bool IsControllerTracked(uint id){return id==1?HasLeft:HasRight;}
  internal Vector2 MapPlayerMovement(Vector2 v,bool yaw){return Rotate?new Vector2(-v.y,v.x):v;}
 }
 public static class ControllerInputTests {
  static int checks;static void Check(bool ok,string message){checks++;if(!ok)throw new Exception(message);}
  static readonly BindingFlags Flags=BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance|BindingFlags.Static;
  static OpenVrInputBridge bridge;static Plugin plugin;static OpenVrRenderer renderer;static VrSettingsMenu menu;static CVRSystem system;
  delegate void AddCall(string action,bool negative,int edge,ref bool result);delegate void AxisCall(string action,ref float result);
  delegate void AnyCall(int edge,ref bool result);
  static AddCall add;static AxisCall axis;static AnyCall any;static Action update;
  static object Invoke(string name,params object[] args){return typeof(OpenVrInputBridge).GetMethod(name,Flags).Invoke(bridge,args);}
  static void Set(string name,object value){typeof(OpenVrInputBridge).GetField(name,Flags).SetValue(bridge,value);}
  static bool Button(string name,int edge=0,bool original=false){bool value=original;add(name,false,edge,ref value);return value;}
  static float Axis(string name,float original=0){float value=original;axis(name,ref value);return value;}
  static int Ui(){object[] args={0};Invoke("BeginUiQuery",args);return (int)args[0];}
  static void EndUi(int previous){Invoke("EndUiQuery",previous);}
  static void Step(ulong left=0,ulong right=0,float lt=0,float rt=0,float lx=0,float ly=0,float rx=0,float ry=0){
   renderer.Left=new VRControllerState_t{ulButtonPressed=left,rAxis1=new Valve.VR.Axis{x=lt},rAxis0=new Valve.VR.Axis{x=lx,y=ly}};
   renderer.Right=new VRControllerState_t{ulButtonPressed=right,rAxis1=new Valve.VR.Axis{x=rt},rAxis0=new Valve.VR.Axis{x=rx,y=ry}};
   system.Left=renderer.Left;system.Right=renderer.Right;Time.frameCount++;update();
  }
  static uint Word(ControllerBindings b,ulong l=0,ulong r=0,float lt=0,float rt=0,bool gameplay=true){return ControllerButtonPolicy.Buttons(ControllerButtonPolicy.Physical(l,lt,r,rt),b,gameplay);}
  public static int Run(){
   const ulong primary=1UL<<7,secondary=1UL<<1,click=1UL<<32,grip=1UL<<2;
   var face=ControllerButtonPolicy.Defaults(new ControllerBindings());
   Check(Word(face)==0,"Idle policy");Check((Word(face,r:secondary)&ControllerButtonPolicy.Secondary)!=0&&(Word(face,r:secondary)&ControllerButtonPolicy.Pause)==0,"B does not pause");
   Check((Word(face,l:secondary)&ControllerButtonPolicy.Pause)!=0&&(Word(face,l:secondary)&ControllerButtonPolicy.Secondary)==0,"Left upper button pauses independently");
   Check(Word(face,lt:1,rt:1)==ControllerButtonPolicy.Load,"Trigger chord emits only Load");
   Check((Word(face,rt:1)&ControllerButtonPolicy.Dash)!=0&&(Word(face,rt:1)&ControllerButtonPolicy.Primary)==0,"Right trigger dashes, not primary");
   Check(Word(face,l:grip,r:grip)==0,"Grips remain reserved");Check(ControllerButtonPolicy.Physical(0,float.NaN,0,float.PositiveInfinity)==0,"Invalid analog trigger values stay idle");
   Check(ControllerButtonPolicy.ActionMask("Fire1",false,false)!=ControllerButtonPolicy.ActionMask("Fire1",false,true),"Gameplay and menu primary are separate");
   Check(ControllerButtonPolicy.ActionMask("R",false,false)==0&&ControllerButtonPolicy.ActionMask("R",false,true)==128,"No duplicate gamepad R path in gameplay");
   Check(!ControllerButtonPolicy.Pressed(255,(ControllerBinding)999),"Invalid binding is inert");
   Check(ControllerButtonPolicy.Stick(ControllerStick.Either,.7f,float.NaN)==.7f,"Bad peer axis cannot hide valid navigation");
   var wand=ControllerButtonPolicy.Defaults(new ControllerBindings{Layout=ControllerLayout.TrackpadWands});
   Check((Word(wand,rt:1)&ControllerButtonPolicy.Primary)!=0,"Wand trigger primary needs no A button");
   Check((Word(wand,lt:1)&ControllerButtonPolicy.Dash)!=0,"Wand left trigger dash");
   Check((Word(wand,l:click)&ControllerButtonPolicy.Swap)!=0,"Wand left pad swaps");
   Check(ControllerButtonPolicy.Pressed(ControllerButtonPolicy.Physical(0,0,click,0),wand.VrMenu),"Wand right pad opens VR settings without a conflicting chord");
   Check(wand.Camera==ControllerBinding.None,"Limited-button preset leaves optional game camera unbound");
   plugin=new Plugin();renderer=new OpenVrRenderer();menu=new VrSettingsMenu();system=new CVRSystem();bridge=new OpenVrInputBridge();
   Set("plugin",plugin);Set("renderer",renderer);Set("settingsMenu",menu);Set("system",system);Set("active",bridge);
   update=(Action)Delegate.CreateDelegate(typeof(Action),bridge,typeof(OpenVrInputBridge).GetMethod("Update",Flags));
   add=(AddCall)Delegate.CreateDelegate(typeof(AddCall),typeof(OpenVrInputBridge).GetMethod("Add",Flags));
   axis=(AxisCall)Delegate.CreateDelegate(typeof(AxisCall),typeof(OpenVrInputBridge).GetMethod("Axis",Flags));
   any=(AnyCall)Delegate.CreateDelegate(typeof(AnyCall),typeof(OpenVrInputBridge).GetMethod("AddAny",Flags));
   Step();Step(right:primary);Check(Button("Fire1",1)&&!Button("Fire1",2),"Primary rising edge");Step(right:primary);Check(Button("Fire1")&&!Button("Fire1",1),"Held primary has one down edge");
   Step();Check(Button("Fire1",2)&&!Button("Fire1"),"Primary release edge");
   Step(right:secondary);Check(Button("Fire2")&&!Button("Pause",original:true),"Real bridge erases mirrored pause on B");
   Step();Step(left:secondary);Check(Button("Pause")&&!Button("Fire2"),"Real bridge separates pause");
   Step();Step(rt:1);Check(Button("Dash")&&!Button("R",original:true),"Semantic dash suppresses native R duplication");
   Step(lt:1,rt:1);Check(Button("Load")&&!Button("Dash")&&!Button("Cam")&&Button("Dash",2),"Load takes trigger ownership and releases dash");
   Step();Step(rx:.8f,ry:.7f);Check(Axis("Horizontal",.9f)==0&&Axis("Horizontal2",.9f)==0&&Axis("Vertical2",.8f)==0,"Diorama stick cannot drive game camera, walk or mirrored secondary axes");
   Check(bridge.DioramaStick.x==.8f&&bridge.DioramaStick.y==.7f,"Right stick exposes independent yaw/approach axes to LateUpdate");
   int ui=Ui();Check(Axis("Horizontal")==.8f&&Button("Right"),"UI uses separate both-stick navigation");int nested=Ui();EndUi(nested);Check(Axis("Horizontal")==.8f,"Nested UI scope restore");EndUi(ui);Check(Axis("Horizontal")==0,"Finalizer restores gameplay navigation");
   Check(bridge.DioramaStick.sqrMagnitude==0,"A UI navigation query reserves placement for the rest of this frame");
   Step(rx:.8f);Check(bridge.DioramaStick.x==.8f,"Menu navigation reservation expires on the next frame");
   Time.timeScale=0;Check(bridge.DioramaStick.sqrMagnitude==0,"Game pause freezes stick placement");Time.timeScale=1;
   Step(left:grip,right:grip,rx:.8f);Check(bridge.DioramaStick.sqrMagnitude==0,"Two-hand placement owns the diorama over stick input");Step();
   plugin.File.Get<ControllerStick>("DioramaStick").Value=ControllerStick.None;Step();Step(rx:.8f);Check(bridge.DioramaStick.sqrMagnitude==0,"Diorama stick can be disabled");Step();
   plugin.File.Get<ControllerStick>("DioramaStick").Value=ControllerStick.Left;Step();Step(lx:.7f);Check(bridge.DioramaStick.x==.7f,"Portable placement stick can be reassigned");Step();
   plugin.File.Get<ControllerStick>("DioramaStick").Value=ControllerStick.Right;Step();
   Step();renderer.Rotate=true;Step(lx:.8f);object[] movementState={null};Invoke("BeginMovementQuery",movementState);
   Check(Axis("Horizontal")==0&&Axis("Vertical")==.8f&&Button("Up",1)&&!Button("Right"),"Viewer-relative movement axes and button edges survive separate stick routing");
   ui=Ui();Check(Axis("Horizontal")==.8f&&Button("Right"),"UI navigation remains unrotated inside a nested movement scope");EndUi(ui);
   Invoke("EndMovementQuery",movementState[0]);renderer.Rotate=false;Step();
   Step();plugin.File.Get<ControllerBinding>("PrimaryAction").Value=ControllerBinding.LeftTrigger;plugin.File.Get<ControllerBinding>("Camera").Value=ControllerBinding.None;
   Step(lt:1);Check(!Button("Fire1"),"Live remap cannot reinterpret a held control");Step();Step(lt:1);Check(Button("Fire1"),"Remapped primary after neutral");
   ui=Ui();Check(!Button("Fire1"),"Dialog does not consume remapped game primary");EndUi(ui);
   Step();Step(right:primary);Check(!Button("Fire1"),"Old primary no longer invokes game action");ui=Ui();Check(Button("Fire1")&&Button("Confirm"),"Dialogs retain configured menu confirm");EndUi(ui);
   Step();plugin.File.Get<ControllerBinding>("MenuConfirm").Value=ControllerBinding.LeftPrimary;Step();Step(left:primary);
   ui=Ui();Check(Button("Fire1"),"Game swap reservation cannot suppress a separately configured menu confirm");EndUi(ui);
   Step();plugin.File.Get<ControllerBinding>("MenuConfirm").Value=ControllerBinding.RightTrigger;plugin.File.Get<ControllerBinding>("NextPage").Value=ControllerBinding.None;Step();Step(rt:1);
   ui=Ui();Check(Button("Fire1",1),"Custom menu trigger confirms on down");EndUi(ui);Check(!Button("Dash"),"Resume/dialog confirm cannot leak into held dash later in the frame");
   Step(rt:1);Check(!Button("Dash"),"UI-consumed held action remains blocked until neutral");Step();Step(rt:1);Check(Button("Dash"),"Gameplay returns after release and new press");Step();
   plugin.File.Get<ControllerBinding>("MenuConfirm").Value=ControllerBinding.Default;Step();
   Step(rt:1);Check(Button("Dash"),"Held dash delivered before modal input ownership");Step(right:click,left:click,rt:1);
   Check(menu.Visible&&!Button("Dash")&&Button("Dash",2)&&Button("Dash",2),"Modal ownership emits one shared dash-release edge to all same-frame consumers");
   Step(rt:1);Check(!Button("Dash",2),"Acknowledged release is not repeated on later frames");Step();Step(right:secondary);Step();
   Step(lt:1);Check(Button("Fire1"),"Action reported before consumer stops polling");Step(right:click,left:click,lt:1);Step();Step();
   Check(Button("Fire1",2),"Unpolled release survives several modal frames until the game asks");Step();Check(!Button("Fire1",2),"Deferred release is acknowledged only once");Step(right:secondary);Step();
   Step(lt:1);Check(Button("Fire1"),"Custom held action delivered before focus loss");renderer.HasInputFocus=false;Step();
   Check(Button("Fire1",2),"Controller focus loss forwards the final release before desktop fallback");renderer.HasInputFocus=true;Step();
   Step();Step(left:click,right:click);Check(menu.Visible&&!Button("Fire1",original:true),"VR settings chord owns game input");
   Step();Step(rx:.8f);Check(menu.X==.8f&&bridge.DioramaStick.sqrMagnitude==0,"Settings uses menu stick, not locomotion or placement");Step();Step(right:secondary);Check(!menu.Visible,"Configured back closes VR settings");Step();
   Step(left:grip,right:grip);Check(!Button("Pause",original:true)&&bridge.BothGripsHeld,"Diorama gesture reserves game input");Step();
   renderer.HasInputFocus=false;Step(right:primary);Check(Button("Fire1",original:true)&&Axis("Horizontal",.6f)==.6f,"Unfocused original input fallback");
   renderer.HasInputFocus=true;Step(right:primary);Check(!Button("Fire1",1),"Focus return held button suppressed");Step();
   renderer.HasInputFocus=false;Step(rx:.8f);Check(bridge.DioramaStick.sqrMagnitude==0,"Unfocused stick cannot move placement");
   renderer.HasInputFocus=true;Step(rx:.8f);Check(bridge.DioramaStick.sqrMagnitude==0,"Held stick on focus return waits for neutral");Step();Step(rx:.8f);Check(bridge.DioramaStick.x==.8f,"Fresh stick movement works after neutral");Step();
   renderer.HasLeft=renderer.HasRight=false;Step();Check(Button("Fire2",original:true),"No-controller desktop fallback");renderer.HasLeft=renderer.HasRight=true;
   Step(right:primary);Check(!Button("Confirm",1),"Reconnected held button suppressed");Step();
   plugin.File.Get<bool>("ExclusiveVrControls").Value=false;Step();Check(Button("Fire2",original:true),"Mixed mode preserves keyboard/gamepad input");Check(Axis("Horizontal2",.8f)==0,"Mixed mode cannot leak mirrored diorama input into camera axes");
   plugin.File.Get<bool>("ExclusiveVrControls").Value=true;Step();Check(Button("UnrecognizedAction",original:true),"Unknown action preserved");
   renderer.UsesOpenXr=false;Step(right:secondary);Check(Button("Fire2")&&!Button("Pause",original:true),"OpenVR path uses the same portable roles");Step();renderer.UsesOpenXr=true;
   plugin.File.Get<ControllerBinding>("PrimaryAction").Value=ControllerBinding.Default;plugin.File.Get<ControllerBinding>("Camera").Value=ControllerBinding.Default;
   plugin.File.Get<ControllerLayout>("Layout").Value=ControllerLayout.TrackpadWands;Step();Step(rt:1);Check(Button("Fire1",1),"Wand preset runs through real polling, not just the policy");Step();
   Step(left:click);Check(Button("Swap",1),"Wand swap polling");Step();Step(right:click);Check(menu.Visible,"Wand single-pad settings binding");Step();
   Step(rt:1);Check(menu.Confirm,"Wand trigger confirms inside settings");Step();Step(right:secondary);Check(!menu.Visible,"Wand menu button closes settings");Step();
   plugin.File.Get<ControllerLayout>("Layout").Value=ControllerLayout.FaceButtons;Step();
   renderer.UseGameShoulders=false;Step();Step(rx:.8f);Check(bridge.DioramaStick.sqrMagnitude==0,"Non-game presentation does not move placement");Step();Step(left:primary);bool anyDown=false;any(1,ref anyDown);
   Check(anyDown,"Title press-any-button accepts a face button with no menu binding");Step(left:primary);anyDown=false;any(1,ref anyDown);Check(!anyDown,"Any-button physical press has one down edge");Step();
   renderer.UseGameShoulders=true;Step();
   plugin.VrControllerInput.Value=false;Step();Check(Button("Fire2",original:true),"Disabled mod input preserves desktop controls");plugin.VrControllerInput.Value=true;Step();
   Step(rx:.8f,ry:.7f);
   for(int i=0;i<64;i++){update();bool value=true;add("Fire2",false,0,ref value);float v=1;axis("Horizontal",ref v);var stick=bridge.DioramaStick;}
   long before=GC.GetAllocatedBytesForCurrentThread();
   for(int i=0;i<512;i++){update();bool value=true;add("Fire2",false,0,ref value);float v=1;axis("Horizontal",ref v);var stick=bridge.DioramaStick;}
   Check(GC.GetAllocatedBytesForCurrentThread()==before,"Warmed production polling and query path allocate zero managed bytes");
   bridge.Release();Check(Button("Fire1",original:true),"Release preserves game input");plugin.InputControls.Dispose();return checks;
  }
 }
}
'@
$using='using System;using System.Collections.Generic;using System.Reflection;using System.Runtime.InteropServices;using BepInEx.Configuration;using HarmonyLib;using UnityEngine;using Valve.VR;'
Add-Type -TypeDefinition ($using+$fixture+($sources -join "`n"))
$count=[QVVR.ControllerInputTests]::Run()
Write-Host "Portable controller input: $count production bridge/config/policy assertions passed, including zero warmed managed allocations. API doubles, not headset QA."

Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
if($GameDir){
 $game=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $GameDir 'QV_Data/Managed/Assembly-CSharp.dll'))
 try {
  $joystick=$game.MainModule.Types | Where-Object Name -eq 'VirtualJoystick'
  $il=($joystick.Methods | Where-Object Name -eq 'Update').Body.Instructions
  foreach($action in @('Fire1','Fire2','Swap','Dash','Cam','Load')){if(!($il | Where-Object {$_.OpCode.Name -eq 'ldstr' -and $_.Operand -eq $action})){throw "Missing native semantic action: $action"}}
  foreach($pair in @(@('Pause','Update'),@('DialogManager','DialogUpdate'),@('PrevDialogManager','Update'),@('ClearUI','Update'),@('IntroWorldManager','Excute'),@('NewIntroWorldManager','Excute'))){
   $type=$game.MainModule.Types | Where-Object Name -eq $pair[0];if(!($type.Methods | Where-Object Name -eq $pair[1])){throw "Missing UI context method: $($pair -join '.')"}
  }
 }finally{$game.Dispose()}
 Write-Host 'Installed QV semantic input actions and UI query scopes verified by read-only metadata.'
}
