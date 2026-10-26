[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Get-Content (Join-Path $root 'src/QVVR/VrSettingsMenu.cs') -Raw
$enum=[regex]::Match($source,'private enum Item\s*\{[^}]+\}').Value
$begin=$source.IndexOf('        internal void HandleInput(')
$end=$source.IndexOf('        internal void Release()')
$methods=$source.Substring($begin,$end-$begin)
# Production navigation/adjust/reset/text methods; rendering APIs and helper
# policies have doubles here, with their own production regression suites.
$fixture=@'
using System;
using System.Globalization;
using BepInEx.Configuration;
using UnityEngine;
using UnityEngine.UI;
namespace BepInEx.Configuration { internal class ConfigEntry<T> {internal T Value;internal object DefaultValue;internal ConfigEntry(T value){Value=value;DefaultValue=value;}} }
namespace UnityEngine {
 internal struct Color {internal Color(float r,float g,float b){}internal static Color white=new Color();}
 internal static class Mathf {internal static float Abs(float v){return Math.Abs(v);}internal static float Clamp(float v,float min,float max){return Math.Max(min,Math.Min(max,v));}}
 internal static class Time {internal static float unscaledTime;}
}
namespace UnityEngine.UI {internal class Text {internal string text;internal Color color;}}
namespace QVVR {
 internal class Plugin {
  internal ConfigEntry<float> ViewPitchDegrees=new ConfigEntry<float>(-16f),WorldUnitsPerMeter=new ConfigEntry<float>(1f),PanelWidth=new ConfigEntry<float>(1.8f),PanelDistance=new ConfigEntry<float>(1.5f),PanelFollowLag=new ConfigEntry<float>(0.6f),
   GameplayHudScale=new ConfigEntry<float>(1.8f),GameplayHudDistance=new ConfigEntry<float>(1.4f),GameplayHudInset=new ConfigEntry<float>(29f),HubPauseDistance=new ConfigEntry<float>(1.2f),CameraDistanceScale=new ConfigEntry<float>(0.4f),RightGripTranslationGain=new ConfigEntry<float>(20f),
   DioramaWorldScale=new ConfigEntry<float>(1f),DioramaMoveSensitivity=new ConfigEntry<float>(1.15f),DioramaRotationSensitivity=new ConfigEntry<float>(1.1f),DioramaRadius=new ConfigEntry<float>(12f),DioramaHeight=new ConfigEntry<float>(12f),DioramaCenterHeight=new ConfigEntry<float>(3f),DioramaFeatherWidth=new ConfigEntry<float>(1f),XrResolutionCap=new ConfigEntry<float>(1f),EyeTextureResolutionScale=new ConfigEntry<float>(1.15f);
  internal ConfigEntry<bool> DioramaEnabled=new ConfigEntry<bool>(true),BlackCutSurfaces=new ConfigEntry<bool>(true),StereoSelectionMenus=new ConfigEntry<bool>(true),PassthroughEnabled=new ConfigEntry<bool>(false),HideDecorativeClouds=new ConfigEntry<bool>(true);
  internal ConfigEntry<int> QualityPreset=new ConfigEntry<int>(1),VoidBackground=new ConfigEntry<int>(0),EyeMsaaSamples=new ConfigEntry<int>(2);
  internal void SelectQualityPreset(int value){QualityPreset.Value=(value+3)%3;}
 }
 internal class OpenVrRenderer {internal int Recentered,Placed;internal void Recenter(){Recentered++;}internal void PlaceInFront(){Placed++;}}
 internal static class ComfortMath {internal static float ClampPitch(float value){return Mathf.Clamp(value,-60f,60f);}}
 internal static class DioramaMath {internal static bool GreenBackground(int value){return value==1;}}
 internal static class DioramaScaleState {internal static float Clamp(float value){return Mathf.Clamp(value,0.001f,10f);}}
 internal static class RenderBudget {
  internal static float SceneScale(float requested,bool xr,float cap){return xr&&cap>0f?Math.Min(requested,cap):requested;}
  internal static float NextRenderScale(float value,float sign){return Mathf.Clamp((float)Math.Round((value+sign*0.05f)*20f)/20f,0.5f,1.5f);}
  internal static int MsaaSamples(int value){return value>=4?4:value>=2?2:1;}
  internal static int NextMsaa(int value,float sign){int c=MsaaSamples(value);return sign>0f?(c>=2?4:2):(c<=2?1:2);}
 }
 public sealed class VrSettingsMenu {
  Plugin plugin;OpenVrRenderer renderer;Text[] rows;int selected,lastDirection;bool anchorNeeded;float nextRepeat;
  internal bool Visible=true;
  void Close(){Visible=false;}
  VrSettingsMenu(){plugin=new Plugin();renderer=new OpenVrRenderer();rows=new Text[15];for(int i=0;i<rows.Length;i++)rows[i]=new Text();RefreshText();}
  static int checks;
  static void Check(bool value,string text){checks++;if(!value)throw new Exception(text);}
  static string Hidden(Plugin p){return p.WorldUnitsPerMeter.Value+"/"+p.PanelWidth.Value+"/"+p.PanelDistance.Value+"/"+p.PanelFollowLag.Value+"/"+p.GameplayHudScale.Value+"/"+p.GameplayHudDistance.Value+"/"+p.GameplayHudInset.Value+"/"+p.HubPauseDistance.Value+"/"+p.BlackCutSurfaces.Value+"/"+p.StereoSelectionMenus.Value;}
  public static int Run(){
   Check((int)Item.Count==15,"Fifteen entries including restored cylinder mode.");
   Check(string.Join(",",Enum.GetNames(typeof(Item)))=="ViewTilt,RenderScale,Msaa,Recenter,RestoreDefaults,CylindricalDiorama,Radius,Height,CenterHeight,VoidColor,Passthrough,EdgeFade,Clouds,PlaceInFront,Size,Count","Requested menu order and whitelist.");
   var m=new VrSettingsMenu();
   foreach(var row in m.rows)Check(!string.IsNullOrEmpty(row.text),"Every retained entry has a label.");
   m.HandleInput(0f,1f,false,false);Check(m.selected==14,"Up wraps to final real entry.");
   for(int i=0;i<15;i++){Time.unscaledTime+=1f;m.HandleInput(0f,-1f,false,false);Check(m.selected==i,"Down visits each retained entry without hidden holes.");}
   for(int i=0;i<15;i++){
    m=new VrSettingsMenu();m.selected=i;string before=Hidden(m.plugin);m.Adjust(1f);
    Check(Hidden(m.plugin)==before,"Left/right must not edit a removed setting.");
    switch((Item)i){
     case Item.ViewTilt:Check(m.plugin.ViewPitchDegrees.Value==-14f&&m.anchorNeeded,"Tilt retained.");break;
     case Item.RenderScale:Check(Math.Abs(m.plugin.EyeTextureResolutionScale.Value-1.2f)<0.0001f&&Math.Abs(m.plugin.XrResolutionCap.Value-1.2f)<0.0001f,"Render scale steps the requested scale; the cap follows.");break;
     case Item.Msaa:Check(m.plugin.EyeMsaaSamples.Value==4,"MSAA steps 2x to 4x.");break;
     case Item.CylindricalDiorama:Check(!m.plugin.DioramaEnabled.Value&&m.anchorNeeded,"Cylinder toggle enables full-scale VR.");break;
     case Item.Radius:Check(m.plugin.DioramaRadius.Value==13f,"Radius retained.");break;
     case Item.Height:Check(m.plugin.DioramaHeight.Value==13f,"Height retained.");break;
     case Item.CenterHeight:Check(m.plugin.DioramaCenterHeight.Value==3.5f,"Center height retained.");break;
     case Item.VoidColor:Check(m.plugin.VoidBackground.Value==1,"Void color retained.");break;
     case Item.Passthrough:Check(m.plugin.PassthroughEnabled.Value,"Passthrough retained.");break;
     case Item.EdgeFade:Check(Math.Abs(m.plugin.DioramaFeatherWidth.Value-1.05f)<0.0001f,"Edge fade retained.");break;
     case Item.Clouds:Check(!m.plugin.HideDecorativeClouds.Value,"Cloud toggle retained.");break;
     case Item.PlaceInFront:Check(m.renderer.Placed==1&&m.anchorNeeded,"Place action retained.");break;
     case Item.Size:Check(m.plugin.DioramaWorldScale.Value==1.25f,"Size retained.");break;
     default:Check(m.renderer.Recentered==0,"Action-only rows cannot be triggered with left/right.");break;
    }
   }
   m=new VrSettingsMenu();m.selected=(int)Item.Recenter;m.HandleInput(0f,0f,true,false);Check(m.renderer.Recentered==1,"A invokes recenter, not another row.");
   m.selected=(int)Item.PlaceInFront;m.HandleInput(0f,0f,true,false);Check(m.renderer.Placed==1,"A invokes placement.");
   foreach(Item item in new[]{Item.CylindricalDiorama,Item.VoidColor,Item.Passthrough,Item.Clouds}){m=new VrSettingsMenu();m.selected=(int)item;string old=m.rows[m.selected].text;m.HandleInput(0f,0f,true,false);Check(m.rows[m.selected].text!=old,"A toggles only retained toggle rows.");}
   m=new VrSettingsMenu();m.selected=(int)Item.CylindricalDiorama;m.HandleInput(0f,0f,true,false);
   Check(m.rows[(int)Item.PlaceInFront].text=="Reset camera behind Q (A)","Placement action describes full VR.");
   m.HandleInput(0f,0f,true,false);Check(m.plugin.DioramaEnabled.Value,"Mode can return to diorama.");
   m=new VrSettingsMenu();m.plugin.PanelWidth.Value=3f;m.plugin.GameplayHudScale.Value=2.8f;m.plugin.ViewPitchDegrees.Value=10f;m.plugin.BlackCutSurfaces.Value=false;m.plugin.StereoSelectionMenus.Value=false;m.plugin.DioramaEnabled.Value=false;
   m.selected=(int)Item.RestoreDefaults;m.HandleInput(0f,0f,true,false);
   Check(m.plugin.PanelWidth.Value==1.8f&&m.plugin.GameplayHudScale.Value==1.8f&&m.plugin.ViewPitchDegrees.Value==-16f,"Restore uses the configured reference profile, not obsolete hardcoded values.");
   Check(m.plugin.BlackCutSurfaces.Value&&m.plugin.StereoSelectionMenus.Value&&m.plugin.DioramaEnabled.Value,"Hidden toggles restore correctly.");
   m.plugin.PanelWidth.DefaultValue=2.25f;m.ResetDefaults();Check(m.plugin.PanelWidth.Value==2.25f,"Reset reads Config.Bind default metadata, not a duplicated constant.");
   // Exclusive OpenXR: the row shows and steps the CAPPED scale, and moves the cap with it.
   m=new VrSettingsMenu();m.plugin.PassthroughEnabled.Value=true;m.RefreshText();
   Check(m.rows[(int)Item.RenderScale].text=="Render scale: 1.00 (restart)","OpenXR row shows the effective capped scale.");
   m.selected=(int)Item.RenderScale;m.Adjust(1f);m.RefreshText();
   Check(Math.Abs(m.plugin.EyeTextureResolutionScale.Value-1.05f)<0.0001f&&Math.Abs(m.plugin.XrResolutionCap.Value-1.05f)<0.0001f&&m.rows[(int)Item.RenderScale].text=="Render scale: 1.05 (restart)","OpenXR step raises scale and cap together.");
   m.plugin.XrResolutionCap.Value=0f;m.Adjust(-1f);Check(m.plugin.XrResolutionCap.Value==0f&&Math.Abs(m.plugin.EyeTextureResolutionScale.Value-1.0f)<0.0001f,"A disabled cap stays disabled.");
   for(int i=0;i<40;i++)m.Adjust(1f);Check(m.plugin.EyeTextureResolutionScale.Value==1.5f,"Render scale upper bound.");
   for(int i=0;i<40;i++)m.Adjust(-1f);Check(m.plugin.EyeTextureResolutionScale.Value==0.5f,"Render scale lower bound.");
   m.selected=(int)Item.Msaa;m.plugin.EyeMsaaSamples.Value=4;m.Adjust(1f);Check(m.plugin.EyeMsaaSamples.Value==4,"MSAA upper bound.");
   m.Adjust(-1f);m.Adjust(-1f);m.RefreshText();Check(m.plugin.EyeMsaaSamples.Value==1&&m.rows[(int)Item.Msaa].text=="Anti-aliasing (MSAA): Off (restart)","MSAA steps down to off.");
   m.Adjust(-1f);Check(m.plugin.EyeMsaaSamples.Value==1,"MSAA lower bound.");m.Adjust(1f);m.RefreshText();Check(m.rows[(int)Item.Msaa].text=="Anti-aliasing (MSAA): 2x (restart)","MSAA label.");
   m.HandleInput(0f,0f,false,true);Check(!m.Visible,"Back still closes menu.");
   return checks;
  }
'@
Add-Type -TypeDefinition ($fixture+$enum+$methods+'}}')
$count=[QVVR.VrSettingsMenu]::Run()
# Verify package defaults match the defaults actually bound by the plugin.
$plugin=Get-Content (Join-Path $root 'src/QVVR/Plugin.cs') -Raw
$cfg=Get-Content (Join-Path $root 'package-assets/dev.qvvr.prototype.cfg') -Raw
$expected=@{ViewPitchDegrees='-16f';PanelWidth='1.8f';PanelDistance='1.5f';PanelFollowLag='0.6f';GameplayHudScale='1.8f';GameplayHudDistance='1.4f';GameplayHudInset='29f';HubPauseDistance='1.2f';DioramaEnabled='true';BlackCutSurfaces='true';StereoSelectionMenus='true'}
foreach($field in $expected.Keys){
 $match=[regex]::Match($plugin,('\b'+$field+' = Config.Bind\("([^"]+)", "([^"]+)", ([^,\r\n]+),'))
 if(!$match.Success -or $match.Groups[3].Value -ne $expected[$field]){throw "Wrong reference profile default: $field"}
 $value=$expected[$field] -replace 'f$',''
 $section=[regex]::Match($cfg,('(?ms)^\['+[regex]::Escape($match.Groups[1].Value)+'\]\r?\n(.*?)(?=^\[|\z)')).Groups[1].Value
 if($section -notmatch ('(?m)^'+[regex]::Escape($match.Groups[2].Value)+' = '+[regex]::Escape($value)+'\r?$')){throw "Package default differs: $field"}
}
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
 $menu=$assembly.MainModule.Types | Where-Object Name -eq 'VrSettingsMenu'
 foreach($name in @('Adjust','RefreshText')){
  $il=($menu.Methods | Where-Object Name -eq $name).Body.Instructions
  foreach($hidden in @('WorldUnitsPerMeter','PanelWidth','PanelDistance','PanelFollowLag','GameplayHudScale','GameplayHudDistance','BlackCutSurfaces','StereoSelectionMenus','GameplayHudInset','HubPauseDistance')){
   if($il | Where-Object {$_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq $hidden}){throw "Removed setting remains in menu: $name / $hidden"}
  }
  if($il | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -in @('AdjustPlacementDistance','get_PlacementDistance','SetCylinderProbe','get_CylinderProbeMode')}){throw "Removed placement/probe control remains: $name"}
 }
 $toggle=($menu.Methods | Where-Object Name -eq 'Toggle').Body.Instructions
 if($toggle | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'set_Value'}){throw 'Opening a menu must not reset saved configuration.'}
}finally{$assembly.Dispose()}
Write-Host "Simplified settings: $count production navigation/action/reset/text assertions plus reference-default/package and compiled hidden-setting guards passed. Not headset layout validation."
