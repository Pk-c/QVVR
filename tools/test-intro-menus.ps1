[CmdletBinding()]
param([string]$GameDir)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $root 'src/QVVR/MenuScenePolicy.cs') -Raw
$fixture = @'
namespace QVVR {
 public static class IntroMenuTests {
  static int checks;
  static void Check(bool ok,string message){checks++;if(!ok)throw new System.Exception(message);}
  public static int Run(){
   Check(MenuScenePolicy.IsIntroScene("001_Intro"),"Verified selection scene recognized.");
   foreach(string scene in new string[]{null,"Landing","Loading","Splash","1_1","EDScene","OtherIntro"})
    Check(!MenuScenePolicy.IsIntroScene(scene),"Do not promote titles/cutscenes/gameplay/unknown scenes.");
   foreach(string name in new string[]{"IntroState.CostumeState","IntroState.StageState","NewIntroState.StageState"}){
    var state=MenuScenePolicy.State(name);
    Check(MenuScenePolicy.StereoSelection(true,true,state),"Known costume/map states are stereo.");
    Check(!MenuScenePolicy.StereoSelection(false,true,state),"Recovery switch retains 2D capture.");
    Check(!MenuScenePolicy.StereoSelection(true,false,state),"Late callback must not affect another scene.");
   }
   foreach(string name in new string[]{null,"IntroState.TitleState","IntroState.WorldState","IntroState.ExitState","NewIntroState.TitleState","OtherGame.StageState"})
    Check(!MenuScenePolicy.StereoSelection(true,true,MenuScenePolicy.State(name)),"All other presentation states stay 2D.");
   Check(MenuScenePolicy.CaptureCanvas(false,0,false),"Original overlay capture preserved.");
   Check(MenuScenePolicy.CaptureCanvas(true,1,true),"Source-camera map labels/controls remain on readable UI panel.");
   Check(!MenuScenePolicy.CaptureCanvas(false,1,true),"Unrelated camera-space game UI not reclassified.");
   Check(!MenuScenePolicy.CaptureCanvas(true,1,false),"Other camera targets preserved.");
   Check(!MenuScenePolicy.CaptureCanvas(true,2,true),"World-space geometry/labels preserved.");
   return checks;
  }
 }
}
'@
Add-Type -TypeDefinition ($source + $fixture)
$count = [QVVR.IntroMenuTests]::Run()
Add-Type -Path (Join-Path $root '.deps/bepinex-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
    $renderer = $assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
    foreach ($name in @('RenderEye','LateUpdate','UpdateRig')) {
        $method = $renderer.Methods | Where-Object Name -eq $name
        if (-not ($method.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'stereoMenuScene' })) { throw "Missing 3D menu separation: $name" }
    }
    $eye = $renderer.Methods | Where-Object Name -eq 'RenderEye'
    if (-not ($eye.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'gameplayScene' })) { throw 'Cylinder/passthrough clipping must be gameplay-only.' }
    $grab = $renderer.Methods | Where-Object Name -eq 'get_CanGrabWorld'
    if (-not ($grab.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq 'gameplayScene' })) { throw 'Diorama manipulation must remain gameplay-only.' }
    $compat = $assembly.MainModule.Types | Where-Object Name -eq 'IntroMenuCompatibility'
    foreach ($name in @('TitleEntered','WorldEntered','CostumeEntered','StageEntered','ExitEntered')) {
        if (-not ($compat.Methods | Where-Object Name -eq $name)) { throw "Missing intro state hook: $name" }
    }
} finally { $assembly.Dispose() }
if ($GameDir) {
    # Metadata only. Never load/execute game code, patch assemblies, or export IL.
    $game = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $GameDir 'QV_Data/Managed/Assembly-CSharp.dll'))
    try {
        foreach ($name in @('IntroState.TitleState','IntroState.WorldState','IntroState.CostumeState','IntroState.StageState','IntroState.ExitState')) {
            $type = $game.MainModule.Types | Where-Object FullName -eq $name
            if (-not ($type.Methods | Where-Object { $_.Name -eq 'Enter' -and $_.HasBody -and $_.Parameters.Count -eq 1 })) { throw "Verified state entry point unavailable: $name" }
        }
        $holder = $game.MainModule.Types | Where-Object Name -eq 'IntroHolder'
        if (-not ($holder.Fields | Where-Object Name -eq '_stateMachine')) { throw 'Intro holder state field unavailable.' }
        $machine = $game.MainModule.Types | Where-Object Name -eq 'StateMachine`1'
        if (-not ($machine.Fields | Where-Object Name -eq 'currentState')) { throw 'Initial state recovery field unavailable.' }
        Write-Host 'Installed QV menu hook metadata verified (read-only).'
    } finally { $game.Dispose() }
}
Write-Host "Intro selection menus: $count policy assertions and compiled routing/interaction guards passed. No game/VR session started."
