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
   foreach(string name in new string[]{"IntroState.WorldState","NewIntroState.WorldState","IntroState.CostumeState","IntroState.StageState","NewIntroState.StageState"}){
    var state=MenuScenePolicy.State(name);
    Check(MenuScenePolicy.StereoSelection(true,true,state),"Known hub/costume/map states are stereo.");
    Check(!MenuScenePolicy.StereoSelection(false,true,state),"Recovery switch retains 2D capture.");
    Check(!MenuScenePolicy.StereoSelection(true,false,state),"Late callback must not affect another scene.");
   }
   foreach(string name in new string[]{null,"IntroState.TitleState","IntroState.ExitState","NewIntroState.TitleState","NewIntroState.ExitState","OtherGame.StageState"})
    Check(!MenuScenePolicy.StereoSelection(true,true,MenuScenePolicy.State(name)),"All other presentation states stay 2D.");
   Check(MenuScenePolicy.UseGameplayHud(true,false),"Existing gameplay HUD treatment preserved.");
   Check(MenuScenePolicy.UseGameplayHud(false,true),"Stereo intro UI shares gameplay HUD scale, distance and capture cadence.");
   Check(MenuScenePolicy.UseGameplayHud(true,true),"Gameplay still uses its HUD if both flags are present.");
   Check(!MenuScenePolicy.UseGameplayHud(false,false),"Title/unknown/disabled-option 2D recovery retains menu UI treatment.");
   Check(MenuScenePolicy.HubHudScale(true,IntroPresentation.World,2)==4,"Only costume-access hub HUD gets scale 4.");
   Check(MenuScenePolicy.HubHudScale(false,IntroPresentation.World,2)==2,"Flat recovery keeps aligned original panel treatment.");
   foreach(IntroPresentation state in new IntroPresentation[]{IntroPresentation.Unknown,IntroPresentation.Costume,IntroPresentation.Stage,IntroPresentation.Title,IntroPresentation.Exit})
    Check(MenuScenePolicy.HubHudScale(true,state,2.5f)==2.5f,"Other screens preserve user HUD scale.");
   Check(MenuScenePolicy.IsOpeningScene("Opening")&&MenuScenePolicy.IsOpeningScene("Opening2"),"Both New Game opening scenes recognized.");
   foreach(string scene in new string[]{null,"Landing","001_Intro","1_1","OtherOpening"})
    Check(!MenuScenePolicy.IsOpeningScene(scene),"Unknown/non-opening scenes not reclassified.");
   Check(MenuScenePolicy.FixedCinemaPanel(false,true)&&MenuScenePolicy.FixedCinemaPanel(true,false)&&MenuScenePolicy.FixedCinemaPanel(true,true),"New Game and first-level intros share stationary panel route.");
   Check(!MenuScenePolicy.FixedCinemaPanel(false,false),"Regular menus keep upright lagged follow.");
   Check(MenuScenePolicy.HubPauseOverlay(true,IntroPresentation.Exit),"Hub pause/achievements use a readable overlay.");
   Check(!MenuScenePolicy.HubPauseOverlay(false,IntroPresentation.Exit),"Never enlarge gameplay pause via the hub exception.");
   Check(MenuScenePolicy.PauseDistance(1.2f)==1.2f&&MenuScenePolicy.PauseDistance(.8f)==.8f,"Hub pause distance has its own live adjustable value.");
   Check(MenuScenePolicy.PauseDistance(0)==.6f&&MenuScenePolicy.PauseDistance(20)==3,"Hub pause distance is safely bounded.");
   Check(MenuScenePolicy.PauseDistance(float.NaN)==1.2f&&MenuScenePolicy.PauseDistance(float.PositiveInfinity)==1.2f,"Invalid dedicated distance restores its own default.");
   foreach(IntroPresentation state in new IntroPresentation[]{IntroPresentation.World,IntroPresentation.Stage,IntroPresentation.Costume,IntroPresentation.Title,IntroPresentation.Unknown})
    Check(!MenuScenePolicy.HubPauseOverlay(true,state),"Other menu states retain their normal HUD placement.");
   Check(MenuScenePolicy.HideStageDim(true,IntroPresentation.Stage),"Hide the specific map dimmer during stereo capture.");
   Check(!MenuScenePolicy.HideStageDim(false,IntroPresentation.Stage),"Flat map dimmer retained.");
   foreach(IntroPresentation state in new IntroPresentation[]{IntroPresentation.Unknown,IntroPresentation.World,IntroPresentation.Costume,IntroPresentation.Title,IntroPresentation.Exit})
    Check(!MenuScenePolicy.HideStageDim(true,state),"Never suppress other-screen fades.");
   Check(System.Math.Abs(MenuScenePolicy.HubAdvance(20,.35f)-13)<.00001f,"Costume-access hub is 65% closer along original view axis.");
   Check(MenuScenePolicy.HubAdvance(20,1)==0,"Distance scale 1 retains original framing.");
   Check(MenuScenePolicy.HubAdvance(.5f,.35f)==0&&MenuScenePolicy.HubAdvance(-2,.35f)==0,"Do not cross near/behind focus.");
   Check(MenuScenePolicy.HubAdvance(2,.15f)==1,"Leave at least one game unit of forward clearance.");
   Check(MenuScenePolicy.HubAdvance(float.NaN,.35f)==0&&MenuScenePolicy.HubAdvance(float.PositiveInfinity,.35f)==0,"Invalid focus depth retains game camera.");
   Check(MenuScenePolicy.HubAdvance(20,float.NaN)==MenuScenePolicy.HubAdvance(20,.35f),"Invalid setting uses safe default.");
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
    foreach ($name in @('PositionPanels','CaptureUi')) {
        $method = $renderer.Methods | Where-Object Name -eq $name
        if (-not ($method.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'MenuScenePolicy' -and $_.Operand.Name -eq 'UseGameplayHud' })) { throw "Missing shared gameplay/stereo-menu HUD policy: $name" }
        foreach ($field in @('gameplayScene','stereoMenuScene')) {
            if (-not ($method.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq $field })) { throw "Missing HUD routing input $field in $name" }
        }
    }
    $panels = $renderer.Methods | Where-Object Name -eq 'PositionPanels'
    foreach ($field in @('GameplayHudScale','GameplayHudDistance','PanelFollowLag')) {
        if (-not ($panels.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq $field })) { throw "Shared HUD setting unavailable: $field" }
    }
    $capture = $renderer.Methods | Where-Object Name -eq 'CaptureUi'
    foreach ($field in @('UiCaptureRate','MenuCaptureRate')) {
        if (-not ($capture.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq $field })) { throw "HUD/menu capture fallback setting unavailable: $field" }
    }
    $late = $renderer.Methods | Where-Object Name -eq 'LateUpdate'
    $hide = @($late.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.Name -eq 'IntroMenuCompatibility' -and $_.Operand.Name -eq 'HideStageDim' })
    $ui = @($late.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'CaptureUi' })
    if ($hide.Count -ne 1 -or $ui.Count -ne 1 -or $hide[0].Offset -ge $ui[0].Offset) { throw 'Dimmer suppression must precede UI capture.' }
    $restoreFinally = $false
    foreach ($handler in $late.Body.ExceptionHandlers | Where-Object HandlerType -eq 'Finally') {
        if ($late.Body.Instructions | Where-Object { $_.Offset -ge $handler.HandlerStart.Offset -and $_.Offset -lt $handler.HandlerEnd.Offset -and $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'RestoreStageDim' }) { $restoreFinally = $true }
    }
    if (-not $restoreFinally) { throw 'Dimmer must restore in a render finally block.' }
    $rig = $renderer.Methods | Where-Object Name -eq 'UpdateRig'
    if (-not ($rig.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'HubPosition' })) { throw 'Hub dolly not integrated in stereo rig.' }
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
        $world = $game.MainModule.Types | Where-Object Name -eq 'IntroWorldManager'
        $costumeAccess = $world.Methods | Where-Object Name -eq 'EnterTheCostume'
        if (-not ($costumeAccess.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MemberReference] -and $_.Operand.Name -eq 'ChangeTheCostume' })) { throw 'World hub costume-access transition unavailable.' }
        if (-not ($world.Fields | Where-Object { $_.Name -eq '_worldTransform' -and $_.FieldType.FullName -eq 'UnityEngine.Transform' })) { throw 'Hub framing anchor unavailable.' }
        $stageUi = $game.MainModule.Types | Where-Object Name -eq 'IntroStageUIManager'
        if (-not ($stageUi.Fields | Where-Object { $_.Name -eq '_dim' -and $_.FieldType.FullName -eq 'UnityEngine.SpriteRenderer' })) { throw 'Specific map dimmer reference unavailable.' }
        Write-Host 'Installed QV menu hook metadata verified (read-only).'
    } finally { $game.Dispose() }
}
Write-Host "Intro selection menus: $count policy assertions and compiled routing/interaction guards passed. No game/VR session started."
