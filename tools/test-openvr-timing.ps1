[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$policy=(Get-Content (Join-Path $root 'src/QVVR/OpenVrPoseTiming.cs') -Raw) -replace '(?m)^using .*;\r?\n',''
$renderer=Get-Content (Join-Path $root 'src/QVVR/OpenVrManager.cs') -Raw
$start=$renderer.IndexOf('        private void RefreshOpenVrTiming()')
$end=$renderer.IndexOf('        private void LateUpdate()', $start)
$methods=$renderer.Substring($start,$end-$start)
$fixture=@'
using System;
using UnityEngine;
using Valve.VR;
namespace UnityEngine {internal static class Time {internal static float unscaledTime;}}
namespace Valve.VR {
 internal enum ETrackedPropertyError {TrackedProp_Success,TrackedProp_UnknownProperty}
 internal enum ETrackedDeviceProperty {Prop_DisplayFrequency_Float,Prop_SecondsFromVsyncToPhotons_Float}
 internal enum ETrackingUniverseOrigin {TrackingUniverseStanding}
 internal struct TrackedDevicePose_t {}
 internal static class OpenVR {internal const uint k_unTrackedDeviceIndex_Hmd=0;}
 internal class CVRSystem {
  internal float Hz=90f,Photons=.004f,Since=.002f,Prediction;internal bool HasVsync=true,FrequencyError,PhotonsError;
  internal int PropertyCalls,VsyncCalls,PoseCalls;internal TrackedDevicePose_t[] Poses;internal ETrackingUniverseOrigin Origin;
  internal float GetFloatTrackedDeviceProperty(uint id,ETrackedDeviceProperty property,ref ETrackedPropertyError error){
   PropertyCalls++;bool hz=property==ETrackedDeviceProperty.Prop_DisplayFrequency_Float;
   error=(hz?FrequencyError:PhotonsError)?ETrackedPropertyError.TrackedProp_UnknownProperty:ETrackedPropertyError.TrackedProp_Success;
   return hz?Hz:Photons;
  }
  internal bool GetTimeSinceLastVsync(ref float elapsed,ref ulong counter){VsyncCalls++;elapsed=Since;counter=1;return HasVsync;}
  internal void GetDeviceToAbsoluteTrackingPose(ETrackingUniverseOrigin origin,float prediction,TrackedDevicePose_t[] poses){PoseCalls++;Origin=origin;Prediction=prediction;Poses=poses;}
 }
}
namespace QVVR {
 public sealed class OpenVrTimingTests {
  CVRSystem system=new CVRSystem();bool UsesOpenXr;
  readonly OpenVrPoseTiming openVrTiming=new OpenVrPoseTiming();float nextOpenVrTimingRefresh;
  readonly TrackedDevicePose_t[] renderPoses=new TrackedDevicePose_t[4];
  static int checks;static void Check(bool ok,string message){checks++;if(!ok)throw new Exception(message);}
  static bool Near(float a,float b){return Math.Abs(a-b)<0.000001f;}
  public static int Run(){
   var p=new OpenVrPoseTiming();
   foreach(float hz in new[]{60f,72f,80f,90f,120f,144f,240f}){
    p.Configure(hz,.003f);float period=1f/hz;
    Check(Near(p.Prediction(true,0f),period+.003f),"Prediction follows runtime refresh, not a fixed 72 Hz value.");
    Check(Near(p.Prediction(true,period*.5f),period*.5f+.003f),"Elapsed vsync time subtracted.");
    Check(Near(p.Prediction(true,period),.003f),"Vsync boundary retains display delay.");
    Check(Near(p.Prediction(false,0f),period+.003f),"Missing vsync uses a known runtime interval.");
    foreach(float elapsed in new[]{-1f,1f,float.NaN,float.PositiveInfinity,float.NegativeInfinity})
     Check(Near(p.Prediction(true,elapsed),period+.003f),"Invalid/stale vsync cannot produce negative, nonfinite or excessive prediction.");
   }
   foreach(float hz in new[]{0f,1f,-72f,501f,10000f,float.NaN,float.PositiveInfinity,float.NegativeInfinity}){
    p.Configure(hz,.01f);Check(p.Prediction(true,0f)==0f,"Unknown/invalid cadence uses current pose rather than inventing a headset rate.");
   }
   foreach(float delay in new[]{-1f,.11f,float.NaN,float.PositiveInfinity,float.NegativeInfinity}){
    p.Configure(90f,delay);Check(Near(p.Prediction(false,0f),1f/90f),"Invalid display delay is ignored.");
   }
   p.Configure(20f,.1f);Check(p.Prediction(false,0f)==.1f,"Bound extreme but finite extrapolation.");
   p.Reset();Check(p.Prediction(false,0f)==0f,"Reset removes cached cadence.");
   var t=new OpenVrTimingTests();Time.unscaledTime=10f;t.RefreshOpenVrTiming();
   Check(t.system.PropertyCalls==2&&t.nextOpenVrTimingRefresh==11f,"Properties sampled cold with one-second refresh deadline.");
   t.PredictOpenVrTracking();
   Check(Near(t.system.Prediction,1f/90f+.004f-.002f)&&t.system.VsyncCalls==1&&t.system.PoseCalls==1,"Production runtime query uses calculated prediction.");
   Check(Object.ReferenceEquals(t.system.Poses,t.renderPoses)&&t.system.Origin==ETrackingUniverseOrigin.TrackingUniverseStanding,"Reuse pose array and existing standing space.");
   t.system.Hz=120f;t.RefreshOpenVrTiming();t.PredictOpenVrTracking();
   Check(Near(t.system.Prediction,1f/120f+.004f-.002f),"Runtime refresh changes update cached timing.");
   t.system.FrequencyError=true;t.RefreshOpenVrTiming();t.PredictOpenVrTracking();Check(t.system.Prediction==0f,"Property error cannot reuse garbage frequency.");
   t.system.FrequencyError=false;t.system.PhotonsError=true;t.RefreshOpenVrTiming();t.PredictOpenVrTracking();Check(Near(t.system.Prediction,1f/120f-.002f),"Display-delay property failure keeps valid frequency.");
   t.system.HasVsync=false;t.system.Since=float.NaN;t.PredictOpenVrTracking();Check(Near(t.system.Prediction,1f/120f),"Runtime vsync failure safely falls back.");
   int propertyCalls=t.system.PropertyCalls,poseCalls=t.system.PoseCalls,vsyncCalls=t.system.VsyncCalls;
   t.UsesOpenXr=true;t.RefreshOpenVrTiming();t.PredictOpenVrTracking();
   Check(t.system.PropertyCalls==propertyCalls&&t.system.PoseCalls==poseCalls&&t.system.VsyncCalls==vsyncCalls,"Exclusive XR never touches the OpenVR timing/tracking API.");
   t.UsesOpenXr=false;for(int i=0;i<1024;i++)t.PredictOpenVrTracking();
   long before=GC.GetAllocatedBytesForCurrentThread();for(int i=0;i<1024;i++)t.PredictOpenVrTracking();long allocated=GC.GetAllocatedBytesForCurrentThread()-before;
   Check(allocated==0&&t.system.PropertyCalls==propertyCalls,"Warmed prediction reuses storage and does not requery device properties per frame.");
   t.system=null;t.RefreshOpenVrTiming();t.PredictOpenVrTracking();Check(true,"No-runtime helpers are inert.");
   return checks;
  }
'@
Add-Type -TypeDefinition ($fixture+$methods+'}}'+$policy)
$count=[QVVR.OpenVrTimingTests]::Run()
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly=[Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
 $type=$assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
 foreach($pair in @(@('Initialize','RefreshOpenVrTiming'),@('CanvasMaintenance','RefreshOpenVrTiming'),@('LateUpdate','PredictOpenVrTracking'),@('ReleaseResources','Reset'))){
  $method=$type.Methods | Where-Object Name -eq $pair[0]
  if($pair[0] -eq 'CanvasMaintenance'){$method=($type.NestedTypes | Where-Object Name -like '<CanvasMaintenance>*').Methods | Where-Object Name -eq 'MoveNext'}
  if(!($method.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq $pair[1] -and $_.Operand.DeclaringType.Name -in @('OpenVrRenderer','OpenVrPoseTiming')})){throw "Missing timing lifecycle integration: $($pair[0])"}
 }
 $late=($type.Methods | Where-Object Name -eq 'LateUpdate').Body.Instructions
 if($late | Where-Object {$_.OpCode.Name -eq 'ldc.r4' -and [Math]::Abs($_.Operand-1.0/72.0) -lt .0000001}){throw 'Fixed 72 Hz OpenVR prediction returned.'}
 $prediction=$late | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'PredictOpenVrTracking'} | Select-Object -First 1
 $submitPose=$late | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'QVVR_SetRenderPoseAndMode'} | Select-Object -First 1
 if(!$prediction -or !$submitPose -or $prediction.Offset -ge $submitPose.Offset){throw 'Native submit must retain the exact pose predicted for the eyes.'}
 foreach($name in @('PredictOpenVrTracking','PrepareTracking','TrackingEye')){
  $il=($type.Methods | Where-Object Name -eq $name).Body.Instructions
  if($il | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'GetFloatTrackedDeviceProperty'}){throw "Device property queried on render path: $name"}
 }
}finally{$assembly.Dispose()}
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'test-controller-input.ps1') -Backend OpenVR
if($LASTEXITCODE -ne 0){throw 'OpenVR-only input regression failed.'}
Write-Host "OpenVR prediction: $count production timing/runtime-integration assertions, zero warmed managed allocations and compiled lifecycle/pose guards passed. Synthetic API doubles, not Quest/Steam Link/Virtual Desktop headset validation."
