[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sources = @('DioramaViewState', 'GripGestureState', 'WorldGrabState', 'DioramaScaleState', 'DioramaMath') | ForEach-Object {
    (Get-Content -LiteralPath (Join-Path $root "src/QVVR/$_.cs") -Raw).Replace('using System;', '')
}
$tests = @'
namespace QVVR {
    public static class IndependentViewTests {
        private static int checks;
        private static void Check(bool ok, string message) {
            checks++; if (!ok) throw new System.Exception(message);
        }
        private static bool Near(float a, float b) { return System.Math.Abs(a-b)<0.00001f; }
        public static int Run() {
            var view = new DioramaViewState();
            Check(!view.Valid, "No uninitialized view anchor.");
            view.Latch(10, 2, 30, 10, 12, 10, 0, 0, 0, 1);
            view.Update(10, 2, 30, .5f, 0, 0, 0);
            Check(view.Valid && Near(view.PositionX,10) && Near(view.PositionY,7) && Near(view.PositionZ,20), "Initial zoom around player anchor.");
            // Tracking head/eyes are deliberately NOT parameters of the view.
            for(int h=0; h<1000; h++) view.Update(10,2,30,.5f,0,0,0);
            Check(Near(view.PositionX,10) && Near(view.PositionY,7) && Near(view.PositionZ,20), "Head snapshots never move game anchor.");
            view.Update(13, 4, 25, .5f, 0, 0, 0);
            Check(Near(view.PositionX,13) && Near(view.PositionY,9) && Near(view.PositionZ,15), "Player xyz motion translates rig by exactly same delta as cylinder, not zoom-scaled delta.");
            Check(Near(view.PositionX-13,0) && Near(view.PositionY-4,5) && Near(view.PositionZ-25,-10), "Player/cylinder remain fixed relative to VR base after movement.");
            Check(view.RotationW==1 && view.RotationX==0, "Game rotations after entry cannot rotate view.");
            view.Update(13,4,25,.5f,-1,-2,-3);
            Check(Near(view.PositionX,12) && Near(view.PositionY,7) && Near(view.PositionZ,12), "Grip offsets pan all axes without touching cylinder center.");
            view.Reset(); Check(!view.Valid, "Scene/recenter clears frozen basis.");
            view.Latch(0,0,0,0,10,-10,0,.70710677f,0,.70710677f);
            Check(Near(view.RotationY,.70710677f), "Recenter may latch a new game orientation.");

            var grip = new GripGestureState();
            grip.Update(true,false,true,false,true,true,true);
            Check(!grip.Reserved, "Held grip on focus recovery must not start.");
            grip.Update(true,false,true,false,false,true,true);
            grip.Update(true,false,true,false,true,true,true);
            Check(grip.Reserved && grip.Mode==1, "Right-only drag activates immediately; no left controller or timer required.");
            grip.Update(true,false,true,false,true,true,true);
            Check(grip.Mode==1, "Cached/busy XR snapshot does not falsely release drag.");
            var grab = new WorldGrabState();
            grab.Update(true,true,2,3,4,0,.6f,0,0,0,1,1,4,false);
            Check(grab.Active && !grab.HasCameraOverride && grab.OffsetX==0, "Right-only mode starts at CURRENT pose with no zoom ownership.");
            grab.Update(true,true,2.25f,3.5f,3.75f,0,.6f,0,0,0,1,1,4,false);
            Check(Near(grab.OffsetX,-1) && Near(grab.OffsetY,-2) && Near(grab.OffsetZ,1), "Right controller physically pans xyz with gain.");
            Check(Near(grab.ResolveCameraScale(.6f),.6f), "Single hand must not alter zoom.");
            grip.Update(true,false,true,false,false,true,true); grab.Stop();
            Check(grip.Mode==0 && !grip.Reserved && Near(grab.OffsetY,-2), "Release freezes placement.");
            grip.Update(true,true,true,true,true,true,true);
            Check(grip.Mode==2, "Adding left grip immediately selects size mode.");
            grab.Update(true,true,100,200,300,.4f,.6f);
            Check(Near(grab.OffsetX,-1), "Right to both starts without placement snap.");
            grab.Update(true,true,100,200,300,.8f,.6f);
            Check(Near(grab.ResolveCameraScale(.6f),.3f), "Legacy camera-distance helper remains compatible; renderer now uses physical-size state instead.");
            grab.Update(true,true,-100,-200,-300,0,.6f,0,0,0,1,1,4,false);
            Check(Near(grab.OffsetX,-1) && Near(grab.CameraScale,.3f), "Gesture mode change rebases at new pose without pan/zoom snap.");
            grip.Update(true,true,true,false,true,true,true);
            Check(grip.Mode==1 && grip.Reserved, "Release left: immediate move mode without waiting.");
            grip.Update(true,true,false,false,true,true,true);
            Check(!grip.Reserved, "Tracking loss cancels and disarms.");
            grip.Update(true,true,true,false,true,true,true);
            Check(!grip.Reserved, "Tracking recovery with held grip cannot jump.");
            grip.Update(true,true,true,false,false,true,true);
            grip.Update(true,true,true,false,true,true,true);
            grip.Update(false,true,true,false,true,true,true);
            Check(!grip.Reserved, "Menu/focus/scene disallows gesture.");
            grip.Update(true,true,true,false,false,true,false);
            grip.Update(true,true,true,false,true,true,false);
            Check(!grip.Reserved, "Right gesture config can be disabled independently.");
            grip.Update(true,true,true,true,true,true,false);
            Check(grip.Mode==2, "Both-grip size mode stays available when right placement is disabled.");
            grab.ResetOffset();
            Check(grab.OffsetX==0 && grab.OffsetY==0 && grab.OffsetZ==0, "Recenter clears placement.");
            var reach = new WorldGrabState();
            reach.Update(true,true,0,0,0,0,.6f,0,0,0,1,1,20,false);
            reach.Update(true,true,.1f,.2f,-.3f,0,.6f,0,0,0,1,1,20,false);
            Check(Near(reach.OffsetX,-2) && Near(reach.OffsetY,-4) && Near(reach.OffsetZ,6), "New right-only gain must give five times old displacement on all axes.");
            Check(Near(reach.ResolveCameraScale(.6f),.6f), "Higher placement gain must not change zoom.");
            reach.Update(true,true,.1f,.2f,-.3f,0,.6f,0,0,0,1,1,100,false);
            Check(Near(reach.OffsetX,-2), "Changing gain during drag must not snap the diorama.");
            reach.Stop();
            reach.Update(true,true,10,10,10,0,.6f,0,0,0,1,1,100,false);
            reach.Update(true,true,10.1f,10,10,0,.6f,0,0,0,1,1,100,false);
            Check(System.Math.Abs(reach.OffsetX+12)<.0001f, "Next grab applies higher menu sensitivity without rescaling old placement.");
            reach.ResetOffset();
            reach.Update(true,true,0,0,0,0,.6f,0,0,0,1,1,500,false);
            reach.Update(true,true,1,0,0,0,.6f,0,0,0,1,1,500,false);
            Check(Near(reach.OffsetX,-100), "Right-only sensitivity is capped at 100.");
            reach.ResetOffset();
            reach.Update(true,true,0,0,0,0,.6f,0,0,0,1,1,float.NaN,false);
            reach.Update(true,true,1,0,0,0,.6f,0,0,0,1,1,float.NaN,false);
            Check(Near(reach.OffsetX,-20), "Invalid single-hand gain falls back to new default.");
            reach.ResetOffset();
            reach.Update(true,true,0,0,0,0,.6f,0,0,0,1,1,-1,false);
            reach.Update(true,true,1,0,0,0,.6f,0,0,0,1,1,-1,false);
            Check(Near(reach.OffsetX,-1), "Right-only minimum gain must allow precise 1:1 placement.");
            var size = new DioramaScaleState();
            size.Update(true,true,.4f,1f);
            Check(size.Active && size.HasOverride && Near(size.Scale,1f), "Size gesture rebases with no jump.");
            size.Update(true,true,.8f,1f);
            Check(Near(size.Scale,2f), "Spread hands enlarges real geometry, not camera distance.");
            size.Update(true,true,.2f,1f);
            Check(Near(size.Scale,.5f), "Bring hands together shrinks real geometry.");
            size.Stop();
            Check(Near(size.Resolve(1f),.5f), "Release retains unsaved size.");
            size.ClearOverride();
            Check(Near(size.Resolve(.5f),.5f), "Sparse save returns config ownership.");
            float small = .5f;
            for(int i=0;i<12;i++) {
                size.Update(true,true,.4f,small);
                size.Update(true,true,.2f,small);
                small = size.Scale; size.Stop(); size.ClearOverride();
            }
            Check(Near(small,.001f), "Repeated size grabs can reach 1/1000, without old camera-distance limit.");
            size.Update(true,true,.4f,small);
            size.Update(true,true,.08f,small);
            Check(Near(size.Scale,.001f), "Lower size bound stays safe.");
            size.Update(true,false,.8f,small);
            Check(!size.Active && Near(size.Scale,.001f), "Tracking loss freezes size.");
            size.Update(true,true,.8f,1f);
            Check(Near(size.Scale,.001f), "Tracking recovery rebases size, never snaps to config.");
            size.Update(true,true,float.NaN,1f);
            Check(!size.Active, "Invalid scale gesture poses are rejected.");
            Check(Near(DioramaScaleState.Clamp(100),10) && Near(DioramaScaleState.Clamp(float.NaN),1), "Size bounds/fallback safe.");
            foreach(float s in new float[] {1f,.1f,.01f,.001f,10f}) {
                float center=20, originalView=-10, units=DioramaMath.ViewUnits(1,s);
                float scaledView=DioramaMath.ScaleViewAxis(center,originalView,s);
                Check(Near((center-scaledView)/units,30), "Resizing retains placed physical cylinder center.");
                Check(Near(41/units,41*s), "Cylinder diameter scales physically, not merely apparent distance.");
                foreach(float head in new float[] {-2,-.5f,0,.5f,2}) {
                    float eye=scaledView+head*units;
                    float perceivedWorld=head+(center-eye)/units;
                    Check(Near(perceivedWorld,30), "Walking/leaning moves only eye: diorama remains fixed in tracking space.");
                }
                float left=scaledView-.032f*units, right=scaledView+.032f*units;
                Check(System.Math.Abs((right-left)/units-.064f)<.00002f, "Physical stereo IPD stays unchanged at every size.");
                float draggedView=DioramaMath.ScaleViewAxis(center,originalView-2,s);
                Check(Near((center-draggedView)/units,32), "Right-hand reach remains independent of scale.");
                float followedView=DioramaMath.ScaleViewAxis(center+5,originalView+5,s);
                Check(Near((center+5-followedView)/units,30), "Player-following cylinder stays physically fixed while character moves.");
            }
            return checks;
        }
    }
}
'@
Add-Type -TypeDefinition ('using System;' + ($sources -join "`n") + $tests)
$count = [QVVR.IndependentViewTests]::Run()
Write-Host "Independent view / right-hand placement: $count assertions passed."

# Integration guards on actual compiled renderer, not only scalar helpers.
Add-Type -Path (Join-Path $root '.deps/BepInEx-5.4.23.5/BepInEx/core/Mono.Cecil.dll')
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src/QVVR/bin/Release/netstandard2.0/QVVR.dll'))
try {
    $renderer = $assembly.MainModule.Types | Where-Object Name -eq OpenVrRenderer
    $rig = $renderer.Methods | Where-Object Name -eq UpdateRig
    $calls = @($rig.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] } | ForEach-Object { $_.Operand.DeclaringType.Name + '.' + $_.Operand.Name })
    foreach ($required in @('DioramaPlacementState.Place','SpatialMath.EntryScale','SpatialMath.VisibleOffset','DioramaMath.ViewUnits')) {
        if ($required -notin $calls) { throw "Actual rig missing $required" }
    }
    $eye = $renderer.Methods | Where-Object Name -eq RenderEye
    foreach($field in @('frameCylinderCenter')) {
        if (-not ($eye.Body.Instructions | Where-Object { $_.OpCode.Name -eq 'ldfld' -and $_.Operand.Name -eq $field })) { throw "Eye must use frame-latched $field" }
    }
    $grab = $renderer.Methods | Where-Object Name -eq UpdateWorldGrab
    if ($grab.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'get_RightGripGrabHeld' }) { throw 'Right-hand-alone gesture must be removed.' }
    if (-not ($grab.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'Update' -and $_.Operand.DeclaringType.Name -eq 'DioramaPlacementState' })) { throw 'Both grips must manipulate physical pose and size.' }
    foreach($name in @('Recenter','OnActiveSceneChanged')) {
        $method = $renderer.Methods | Where-Object Name -eq $name
        if (-not ($method.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'Reset' -and $_.Operand.DeclaringType.Name -eq 'DioramaPlacementState' })) { throw "Missing placement reset: $name" }
    }
    $bridge = $assembly.MainModule.Types | Where-Object Name -eq OpenVrInputBridge
    $update = $bridge.Methods | Where-Object Name -eq Update
    $gestureCall = $update.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'Update' -and $_.Operand.DeclaringType.Name -eq 'GripGestureState' }
    if ($gestureCall.Previous.OpCode.Name -ne 'ldc.i4.0') { throw 'Production input must disable right-only manipulation even for old configs.' }
    $initialize = $bridge.Methods | Where-Object Name -eq Initialize
    foreach($scope in @('BeginMovementQuery','BeginJumpQuery','EndMovementQuery')) {
        if (-not ($initialize.Body.Instructions | Where-Object { $_.Operand -eq $scope })) { throw "Movement-only query scope missing: $scope" }
    }
    $panel = $renderer.Methods | Where-Object Name -eq PositionPanels
    if (-not ($panel.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'UprightHeadRotation' })) { throw 'Panels must use physical upright heading.' }
    $save = $renderer.Methods | Where-Object Name -eq SavePlacementSettings
    foreach($field in @('PlacementOffset','PlacementEuler','PreferredSizeMeters','PlacementSaved')) {
        if (-not ($save.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq $field })) { throw "Reusable layout not saved: $field" }
    }
    Write-Host 'Compiled renderer integration passed: independent rig, shared stereo cylinder anchor, right-hand gesture and reset lifecycle.'
} finally { $assembly.Dispose() }
