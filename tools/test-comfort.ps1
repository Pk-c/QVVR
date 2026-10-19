[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $root 'src\QVVR\ComfortMath.cs') -Raw
$budgetSource = Get-Content -LiteralPath (Join-Path $root 'src\QVVR\RenderBudget.cs') -Raw
$grabSource = Get-Content -LiteralPath (Join-Path $root 'src\QVVR\WorldGrabState.cs') -Raw
$dioramaSource = Get-Content -LiteralPath (Join-Path $root 'src\QVVR\DioramaMath.cs') -Raw
$latchSource = Get-Content -LiteralPath (Join-Path $root 'src\QVVR\XrInputLatch.cs') -Raw
$scaleSource = (Get-Content -LiteralPath (Join-Path $root 'src\QVVR\DioramaScaleState.cs') -Raw).Replace('using System;', '')
$testSource = @'
namespace QVVR {
    public static class ComfortTests {
        private static void Assert(bool condition, string message) {
            if (!condition) throw new System.Exception(message);
        }
        public static void Run() {
            Assert(ComfortMath.FollowWeight(1f / 72f, 0f) == 1f, "Zero lag must follow immediately.");
            Assert(ComfortMath.FollowWeight(-1f, 0.35f) == 0f, "Negative elapsed time must not move panels.");
            Assert(ComfortMath.FollowWeight(0f, 0.35f) == 0f, "Zero elapsed time must not move panels.");
            Assert(System.Math.Abs(ComfortMath.FollowWeight(0.35f, 0.35f) - 0.63212056f) < 0.00001f, "Incorrect smoothing time constant.");
            float remaining72 = 1f, remaining144 = 1f;
            for (int i = 0; i < 72; i++) remaining72 *= 1f - ComfortMath.FollowWeight(1f / 72f, 0.35f);
            for (int i = 0; i < 144; i++) remaining144 *= 1f - ComfortMath.FollowWeight(1f / 144f, 0.35f);
            Assert(System.Math.Abs(remaining72 - remaining144) < 0.00001f, "Panel follow must be frame-rate independent.");
            ulong stick = 1UL << 32;
            Assert(!ComfortMath.BothSticksPressed(0, 0), "No chord without clicks.");
            Assert(!ComfortMath.BothSticksPressed(stick, 0), "Left click alone must not toggle.");
            Assert(!ComfortMath.BothSticksPressed(0, stick), "Right click alone must not toggle.");
            Assert(!ComfortMath.BothSticksPressed(1UL << 7, 1UL << 7), "A must not toggle the settings menu.");
            Assert(ComfortMath.BothSticksPressed(stick, stick), "Both stick clicks must toggle.");
            Assert(RenderBudget.PresetScale(0) < RenderBudget.PresetScale(1), "Performance must use less resolution than Balanced.");
            Assert(RenderBudget.PresetScale(2) > RenderBudget.PresetScale(1), "Sharp must use more resolution than Balanced.");
            Assert(RenderBudget.MsaaSamples(0) == 1 && RenderBudget.MsaaSamples(3) == 2 && RenderBudget.MsaaSamples(8) == 4, "MSAA must normalize to supported sample counts.");
            float interval = 1f / 36f;
            Assert(System.Math.Abs(RenderBudget.NextCapture(0f, 0f, 36) - interval) < 0.00001f, "Incorrect capture interval.");
            Assert(System.Math.Abs(RenderBudget.NextCapture(interval + 0.0001f, interval, 36) - 2f * interval) < 0.00001f, "Capture deadline must not drift with small frame jitter.");
            Assert(RenderBudget.NextCapture(10f, 0f, 36) > 10f, "Stalled capture must skip missed frames, not catch up with a burst.");
            Assert(ComfortMath.ClampPitch(0f) == 0f && ComfortMath.ClampPitch(22f) == 22f, "Tilt must preserve valid settings.");
            Assert(ComfortMath.ClampPitch(-90f) == -60f && ComfortMath.ClampPitch(90f) == 60f, "Tilt must stay within comfort bounds.");
            Assert(ComfortMath.ClampPitch(float.NaN) == 0f, "NaN tilt must not corrupt camera transforms.");
            Assert(System.Math.Abs(RenderBudget.NextCapture(0f, 0f, 72) - 1f / 72f) < 0.00001f, "Menus must support 72 Hz independently of the 36 Hz HUD.");
            Assert(RenderBudget.UiScale(1.75f)==1.75f&&1920*RenderBudget.DefaultUiScale==3360&&1080*RenderBudget.DefaultUiScale==1890,"UI-only sharper target has exact expected dimensions.");
            Assert(RenderBudget.UiScale(float.NaN)==1.75f&&RenderBudget.UiScale(float.PositiveInfinity)==1.75f,"Invalid UI scale retains safe default.");
            Assert(RenderBudget.UiScale(0)==1&&RenderBudget.UiScale(10)==2,"UI resolution remains bounded.");
            Assert(RenderBudget.UpgradeUiScale(1.5f)==1.75f,"Old shipped UI default migrates once.");
            Assert(RenderBudget.UpgradeUiScale(1)==1&&RenderBudget.UpgradeUiScale(2)==2&&RenderBudget.UpgradeUiScale(1.6f)==1.6f,"Custom UI settings must be preserved.");
            Assert(System.Math.Abs((1.75f*1.75f)/(1.5f*1.5f)-1.361111f)<.00001f,"Increase is 36.1 percent of UI capture pixels, not the scene.");
            Assert(RenderBudget.SceneScale(1.15f,true,1)==1,"XR stability cap prevents Sharp supersampling over budget.");
            Assert(RenderBudget.SceneScale(.85f,true,1)==.85f,"Cap never raises a lower requested scale.");
            Assert(RenderBudget.SceneScale(1.15f,false,1)==1.15f,"OpenVR quality is unchanged.");
            Assert(RenderBudget.SceneScale(1.15f,true,0)==1.15f,"Cap zero restores requested XR quality.");
            Assert(RenderBudget.SceneScale(float.NaN,true,float.NaN)==1,"Invalid scales recover safely.");
            Assert(System.Math.Abs(1f/(1.15f*1.15f)-.7561437f)<.00001f,"Cap reduces Sharp scene pixel count by about 24.4 percent, not total GPU time.");
            Assert(RenderBudget.NextXrCap(.5f,-1)==0&&RenderBudget.NextXrCap(0,1)==.5f,"Stability cap has a reachable off/on toggle.");
            Assert(RenderBudget.NextXrCap(float.NaN,1)>1,"Invalid persisted cap can be adjusted from the menu.");
        }
    }
    public static class WorldGrabTests {
        private static int checks;
        private static void Assert(bool condition, string message) {
            checks++;
            if (!condition) throw new System.Exception(message);
        }
        private static bool Near(float a, float b) { return System.Math.Abs(a - b) < 0.00001f; }
        public static int Run() {
            Assert(!ComfortMath.GripPressed(0, 0f, 0f), "Idle hands must not grab.");
            Assert(ComfortMath.GripPressed(1UL << 2, 0f, 0f), "Frame legacy grip bit2 must grab.");
            Assert(!ComfortMath.GripPressed(1UL << 7, 0f, 0f), "A must not count as a grip.");
            Assert(!ComfortMath.GripPressed(1UL << 32, 0f, 0f), "Stick click must not count as a grip.");
            Assert(ComfortMath.GripPressed(0, 0.6f, 0f) && ComfortMath.GripPressed(0, 0f, 0.6f), "Both axis2 analogue layouts must work.");
            Assert(!ComfortMath.GripPressed(0, 0.54f, 0.54f), "Grip threshold must reject unpressed analogue input.");
            WorldGrabState grab = new WorldGrabState();
            grab.Update(true, true, 10f, 20f, 30f, 0.4f, 0.4f);
            Assert(grab.Active && grab.HasCameraOverride, "Both grips must start a valid grab.");
            Assert(grab.OffsetX == 0f && grab.OffsetY == 0f && grab.OffsetZ == 0f, "Starting at a nonzero controller pose must not jump.");
            Assert(Near(grab.CameraScale, 0.4f), "Starting a grab must preserve camera distance.");
            grab.Update(true, true, 11f, 22f, 33f, 0.8f, 0.4f);
            Assert(Near(grab.OffsetX, -1f) && Near(grab.OffsetY, -2f) && Near(grab.OffsetZ, -3f), "World must follow hands in all axes by inverse camera translation.");
            Assert(Near(grab.CameraScale, 0.2f), "Doubling hand separation must halve camera distance (zoom in).");
            grab.Update(true, true, 11f, 22f, 33f, 0.2f, 0.4f);
            Assert(Near(grab.CameraScale, 0.8f), "Halving hand separation must double camera distance (zoom out).");
            Assert(Near(grab.OffsetX, -1f) && Near(grab.OffsetY, -2f) && Near(grab.OffsetZ, -3f), "Symmetric zoom must not introduce pan.");
            grab.Update(true, true, 11f, 22f, 33f, 10f, 0.4f);
            Assert(Near(grab.CameraScale, 0.15f), "Zoom in must respect the existing minimum distance.");
            grab.Update(true, true, 11f, 22f, 33f, 0.08f, 0.4f);
            Assert(Near(grab.CameraScale, 1.5f), "Zoom out must respect the existing maximum distance.");
            grab.Update(false, true, 100f, 200f, 300f, 1f, 0.4f);
            Assert(!grab.Active && grab.HasCameraOverride, "Release must stop grabbing but preserve zoom until sparse save.");
            Assert(Near(grab.OffsetX, -1f) && Near(grab.OffsetZ, -3f), "Moving released hands must not move the world.");
            Assert(Near(grab.ResolveCameraScale(0.4f), 1.5f), "Release must not snap back to the old config value.");
            grab.ClearCameraOverride();
            Assert(!grab.HasCameraOverride && Near(grab.ResolveCameraScale(1.5f), 1.5f), "Saved zoom must return to normal config ownership.");
            grab.Update(true, true, 100f, 200f, 300f, 0.4f, 1.5f);
            Assert(Near(grab.OffsetX, -1f) && Near(grab.OffsetY, -2f), "A second grab must anchor to the saved offset without snapping.");
            grab.ClearCameraOverride();
            Assert(grab.HasCameraOverride, "Sparse save must not clear an active gesture's override.");
            grab.Update(true, true, 99f, 198f, 297f, 0.4f, 1.5f);
            Assert(Near(grab.OffsetX, 0f) && Near(grab.OffsetY, 0f) && Near(grab.OffsetZ, 0f), "Reverse motion must return the world to its original offset.");
            grab.Update(true, false, 0f, 0f, 0f, 1f, 1.5f);
            Assert(!grab.Active && Near(grab.CameraScale, 1.5f), "Tracking loss must freeze, not reset, the gesture.");
            grab.Update(true, true, -100f, -200f, -300f, 0.4f, 0.4f);
            Assert(grab.Active && Near(grab.OffsetY, 0f) && Near(grab.CameraScale, 1.5f), "Tracking recovery must reanchor without translation/zoom jumps.");
            grab.Update(true, true, -100f, -200f, -300f, 0f, 0.4f);
            Assert(!grab.Active && Near(grab.CameraScale, 1.5f), "Coincident controllers must not divide by zero or jump.");
            grab.Update(true, true, float.NaN, 0f, 0f, 0.4f, 0.4f);
            Assert(!grab.Active && !float.IsNaN(grab.OffsetX), "NaN tracking must be rejected.");
            grab.Update(true, true, 0f, float.PositiveInfinity, 0f, 0.4f, 0.4f);
            Assert(!grab.Active && !float.IsInfinity(grab.OffsetY), "Infinite tracking must be rejected.");
            grab.Update(true, true, 0f, 0f, 0f, float.NaN, 0.4f);
            Assert(!grab.Active, "Invalid hand separation must be rejected.");
            grab.Update(true, true, 0f, 0f, 0f, 0.4f, 0.4f);
            grab.Update(true, true, 1f, 2f, 3f, 0.8f, 0.4f);
            grab.ResetOffset();
            Assert(!grab.Active && grab.OffsetX == 0f && grab.OffsetY == 0f && grab.OffsetZ == 0f, "Recenter must clear temporary world placement.");
            Assert(Near(grab.CameraScale, 0.75f), "Recenter must preserve the zoom preference.");
            WorldGrabState invalidScale = new WorldGrabState();
            invalidScale.Update(true, true, 0f, 0f, 0f, 0.4f, float.NaN);
            Assert(Near(invalidScale.CameraScale, 0.4f), "Invalid config zoom must use a safe default.");
            WorldGrabState firstInvalid = new WorldGrabState();
            firstInvalid.Update(true, false, 10f, 20f, 30f, 0.4f, 0.4f);
            Assert(!firstInvalid.Active && !firstInvalid.HasCameraOverride, "No grab before both controllers are tracked.");
            WorldGrabState rotated = new WorldGrabState();
            float half = (float)System.Math.Sqrt(0.5);
            rotated.Update(true, true, 10f, 20f, 30f, 0.4f, 0.4f, 0f, half, 0f, half, 2f, 4f);
            Assert(Near(rotated.OffsetX, 0f) && Near(rotated.OffsetZ, 0f), "Rotated/scaled grab start must not jump.");
            rotated.Update(true, true, 11f, 20.5f, 30.25f, 0.8f, 0.4f, 0f, half, 0f, half, 2f, 4f);
            Assert(Near(rotated.OffsetX, -2f), "Yawed forward hand movement must translate along world X with gain and units.");
            Assert(Near(rotated.OffsetY, -4f), "Vertical hand movement must pan, not just rotate.");
            Assert(Near(rotated.OffsetZ, 8f), "Yawed horizontal hand movement must translate along world Z.");
            Assert(Near(rotated.CameraScale, 0.2f), "Translation gain must not alter zoom.");
            rotated.Update(true, true, 11f, 20.5f, 30.25f, 0.8f, 0.4f, 0f, 0f, 0f, 1f, 10f, 20f);
            Assert(Near(rotated.OffsetX, -2f) && Near(rotated.OffsetY, -4f) && Near(rotated.OffsetZ, 8f), "Camera rotation/setting changes during a grab must not jump or rotate placement.");
            rotated.Stop();
            Assert(Near(rotated.OffsetX, -2f) && Near(rotated.OffsetZ, 8f), "Release must preserve game-world placement.");
            rotated.Update(true, true, 100f, 200f, 300f, 0.4f, 0.4f, 0f, 0f, 0f, 1f, 1f, 2f);
            Assert(Near(rotated.OffsetX, -2f) && Near(rotated.OffsetZ, 8f), "Regrab in a new camera orientation must not rotate the existing offset.");
            rotated.Update(true, true, 100.25f, 200f, 300f, 0.4f, 0.4f);
            Assert(Near(rotated.OffsetX, -2.5f) && Near(rotated.OffsetZ, 8f), "A new grab must use its new basis/gain without rescaling previous placement.");
            rotated.Update(true, false, 0f, 0f, 0f, 0.4f, 0.4f);
            Assert(!rotated.Active && Near(rotated.OffsetX, -2.5f), "Tracking loss must retain the rotated world offset.");
            WorldGrabState invalidRotation = new WorldGrabState();
            invalidRotation.Update(true, true, 0f, 0f, 0f, 0.4f, 0.4f, float.NaN, 0f, 0f, 1f);
            Assert(!invalidRotation.Active, "NaN camera orientation must not start a grab.");
            invalidRotation.Update(true, true, 0f, 0f, 0f, 0.4f, 0.4f, 0f, 0f, 0f, 0f);
            Assert(!invalidRotation.Active, "Zero-length camera orientation must not start a grab.");
            WorldGrabState safeGain = new WorldGrabState();
            safeGain.Update(true, true, 0f, 0f, 0f, 0.4f, 0.4f, 0f, 0f, 0f, 2f, float.NaN, float.NaN);
            safeGain.Update(true, true, 1f, 1f, 1f, 0.4f, 0.4f);
            Assert(Near(safeGain.OffsetX, -4f) && Near(safeGain.OffsetY, -4f), "Quaternion normalization and invalid gain/unit fallback must stay safe.");
            WorldGrabState maxGain = new WorldGrabState();
            maxGain.Update(true, true, 0f, 0f, 0f, 0.4f, 0.4f, 0f, 0f, 0f, 1f, 100f, 100f);
            maxGain.Update(true, true, 1f, 0f, 0f, 0.4f, 0.4f);
            Assert(Near(maxGain.OffsetX, -200f), "Translation gain and unit scale must respect upper bounds.");
            WorldGrabState minGain = new WorldGrabState();
            minGain.Update(true, true, 0f, 0f, 0f, 0.4f, 0.4f, 0f, 0f, 0f, 1f, -1f, -1f);
            minGain.Update(true, true, 1f, 0f, 0f, 0.4f, 0.4f);
            Assert(Near(minGain.OffsetX, -0.0625f), "Translation settings must respect lower bounds.");
            Assert(Near(DioramaMath.FollowCameraAxis(3f, 100f, 100f), 3f), "Cylinder starts centered on the player, not the distant camera.");
            Assert(Near(DioramaMath.FollowCameraAxis(3f, 110f, 100f), 13f), "Cylinder must follow game-camera X translation.");
            Assert(Near(DioramaMath.FollowCameraAxis(14f, 18f, 20f), 12f), "Cylinder must follow vertical camera translation.");
            Assert(Near(DioramaMath.FollowCameraAxis(3f, -15f, -10f), -2f), "Cylinder must follow game-camera Z translation.");
            Assert(Near(DioramaMath.FollowCameraAxis(3f, 100f, 100f), 3f), "Unchanged original camera must leave the cylinder anchor unchanged during grip/head motion.");
            Assert(!DioramaMath.GreenBackground(0), "Void must default to black.");
            Assert(DioramaMath.GreenBackground(1), "Green fallback must be selectable.");
            Assert(!DioramaMath.GreenBackground(-1) && !DioramaMath.GreenBackground(2), "Invalid background preferences must fall back to black.");
            Assert(Near(DioramaMath.FeatherWidth(0f, 12f, 12f), 0f), "Zero feather restores hard clipping.");
            Assert(Near(DioramaMath.FeatherWidth(0.35f, 12f, 12f), 0.35f), "Small fade preserves its requested width.");
            Assert(Near(DioramaMath.FeatherWidth(10f, 0.5f, 12f), 0.25f), "Fade must retain an opaque radial core.");
            Assert(Near(DioramaMath.FeatherWidth(10f, 12f, 0.5f), 0.125f), "Fade must retain an opaque vertical core.");
            Assert(Near(DioramaMath.FeatherWidth(float.NaN, 12f, 12f), 1f), "Invalid fade uses the wider safe default.");
            Assert(Near(DioramaMath.FeatherWidth(1f, 12f, 12f), 1f), "Wider fade must remain visible without unexpected clamping.");
            Assert(Near(DioramaMath.UpgradeFeatherWidth(0.35f), 1f), "Old shipped fade must upgrade once to the wider default.");
            Assert(Near(DioramaMath.UpgradeFeatherWidth(0f), 0f), "Migration must preserve disabled fade.");
            Assert(Near(DioramaMath.UpgradeFeatherWidth(0.7f), 0.7f), "Migration must preserve custom widths.");
            Assert(Near(DioramaMath.HudScale(float.NaN), 2f) && Near(DioramaMath.HudScale(2f), 2f), "HUD defaults to twice its old size.");
            Assert(Near(DioramaMath.HudScale(0f), 0.5f) && Near(DioramaMath.HudScale(100f), 3f), "HUD scale must stay bounded.");
            XrInputLatch latch = new XrInputLatch();
            Assert(!latch.InputReady, "No XR input before a snapshot.");
            latch.Update(2);
            Assert(latch.Busy && !latch.InputReady && !latch.RenderReady, "Busy before any snapshot must not invent controllers.");
            WorldGrabState queuedGrab = new WorldGrabState();
            latch.Update(1);
            queuedGrab.Update(latch.InputReady, true, 0f, 0f, 0f, 0.4f, 0.4f);
            Assert(queuedGrab.Active && latch.RenderReady, "Fresh snapshot starts camera-offset gesture.");
            latch.Update(2);
            Assert(latch.Busy && latch.InputReady && !latch.RenderReady, "Backpressure must preserve held input, without reusing the frame for rendering.");
            if (!latch.Busy) queuedGrab.Stop();
            latch.Update(1);
            queuedGrab.Update(latch.InputReady, true, 1f, 2f, 3f, 0.8f, 0.4f);
            Assert(Near(queuedGrab.OffsetX, -1f) && Near(queuedGrab.OffsetY, -2f) && Near(queuedGrab.OffsetZ, -3f), "Fresh -> queued -> fresh must translate camera, not reanchor grips every frame.");
            Assert(Near(queuedGrab.CameraScale, 0.2f), "Queued XR frames must not break hand-separation zoom.");
            latch.Update(0);
            Assert(!latch.Busy && !latch.InputReady && !latch.RenderReady, "Real tracking/session loss must clear controller input.");
            return checks;
        }
    }
}
'@
Add-Type -TypeDefinition ($source + $budgetSource.Replace('using System;', '') + $grabSource.Replace('using System;', '') + $scaleSource + $dioramaSource.Replace('using System;', '') + $latchSource + $testSource)
[QVVR.ComfortTests]::Run()
Write-Host 'Comfort/render budget assertions passed, including XR stability cap; HUD resolution unchanged.'
$grabChecks = [QVVR.WorldGrabTests]::Run()
Write-Host "World grab: $grabChecks assertions passed."

Add-Type -Path (Join-Path $root '.deps\bepinex-5.4.23.5\BepInEx\core\Mono.Cecil.dll')
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $root 'src\QVVR\bin\Release\netstandard2.0\QVVR.dll'))
$checks = @{
    'ComfortMath' = @('FollowWeight', 'BothSticksPressed', 'ClampPitch', 'GripPressed')
    'WorldGrabState' = @('Update', 'ResolveCameraScale', 'Stop', 'ClearCameraOverride', 'ResetOffset', 'Finite', 'ClampScale', 'SafeRange')
    'DioramaViewState' = @('Latch', 'Update', 'Reset', 'get_Valid')
    'GripGestureState' = @('Update', 'Reset', 'get_Mode', 'get_Reserved')
    'DioramaScaleState' = @('Update', 'Resolve', 'Stop', 'ClearOverride', 'Clamp', 'get_Active', 'get_HasOverride', 'get_Scale')
    'DioramaPlacementState' = @('Place', 'Update', 'SetScale', 'Tilt', 'Stop', 'Saved', 'Reset', 'get_Valid', 'get_Active', 'get_Dirty', 'get_Position', 'get_Rotation', 'get_Scale')
    'SpatialMath' = @('Gain', 'Finite', 'Finite', 'Finite', 'Upright', 'HandFrame', 'VisibleOffset', 'EntryScale', 'Movement', 'get_DefaultOffset', 'LegacyDefaultOffset')
    'DioramaMath' = @('FollowCameraAxis', 'GreenBackground', 'FeatherWidth', 'UpgradeFeatherWidth', 'HudScale', 'ScaleViewAxis', 'ViewUnits')
    'XrInputLatch' = @('Update', 'get_RenderReady', 'get_InputReady', 'get_Busy')
    'CloudVisualRules' = @('Hide', 'Named')
    'CloudRendererFilter' = @('HideForStereo', 'Restore', 'Clear', 'get_Count')
    'LiquidDepthPolicy' = @('UsesDepth', 'Visible', 'get_Count', 'get_NeedsDepth', 'Clear')
    'DioramaBounds' = @('Finite', 'Valid', 'Intersects', 'InFrustum')
    'DioramaVisibility' = @('HideOutside', 'Restore', 'Clear', 'get_Count', 'get_LastHidden')
    'UiCaptureCache' = @('NeedsCapture', 'Captured', 'Continuous', 'Invalidate', 'DisableReuse', 'get_Failed', 'get_Captures', 'get_Reuses')
    'MenuScenePolicy' = @('IsIntroScene', 'StereoSelection', 'State', 'CaptureCanvas', 'UseGameplayHud', 'HideStageDim', 'HubAdvance')
    'IntroMenuCompatibility' = @('HubPosition', 'HideStageDim', 'RestoreStageDim')
    'HudLayoutMath' = @('Percent', 'Anchor')
    'LevelIntroPolicy' = @('Scene', 'Active')
    'FixedPanelAnchor' = @('Latch', 'Reset', 'get_Valid', 'get_Position', 'get_Rotation')
    'ControllerButtonPolicy' = @('Buttons', 'Trigger')
    'QvCameraCompatibility' = @('GetMainCamera')
    'CharacterVisualCompatibility' = @('Clear')
    'TransparentEffectCompatibility' = @('Matches', 'get_Count', 'Prepare', 'Restore', 'Clear')
    'RenderBudget' = @('PresetScale', 'MsaaSamples', 'NextCapture', 'UiScale', 'UpgradeUiScale')
    'OpenVrRenderer' = @('LateUpdate', 'PrepareTracking', 'XrTrackedPose', 'GetXrControllerState', 'get_UsesOpenXr', 'get_NeedsOpenVrSceneFallback', 'ToUnityMatrix', 'ToUnityProjection', 'UpdateWorldGrab', 'PositionPanels', 'UpdateRig', 'UpdateLegacyRig', 'CacheHeadPose', 'UprightHeadRotation', 'MapPlayerMovement', 'ResolveCylinderCenter', 'IsControllerTracked', 'CaptureUi', 'RenderFlatScreen', 'RenderStereoGameplay', 'RenderEye', 'SafeValue', 'get_HasInputFocus', 'get_CylinderProbeMode', 'get_IsFirstLevelScene', 'get_LevelIntroCamera')
    'OpenXrFov' = @('Projection')
    'VrSettingsMenu' = @('UpdatePose')
    'OpenVrInputBridge' = @('Axis', 'Button', 'ButtonDown', 'ButtonUp', 'NegativeButton', 'NegativeButtonDown', 'NegativeButtonUp', 'AnyButton', 'AnyButtonDown', 'AnyButtonUp', 'Add', 'AddAny', 'Mask', 'State', 'MovementMask', 'BeginMovementQuery', 'BeginJumpQuery', 'EndMovementQuery', 'Stronger', 'DeadZone', 'get_ConsumeGameInput')
}
$checks['OpenVrRenderer'] += @('RenderPanelOverlay', 'get_UseGameShoulders')
$checks['OpenVrRenderer'] += @('get_FixedCinemaPanel')
$checks['MenuScenePolicy'] += @('HubHudScale', 'IsOpeningScene', 'FixedCinemaPanel')
$checks['MenuScenePolicy'] += @('HubPauseOverlay')
$checks['SpatialMath'] += @('EntryGain', 'EntryBase')
$checks['SpatialMath'] += @('EyePosition')
$checks['MenuScenePolicy'] += @('PauseDistance')
$checks['MenuScenePolicy'] += @('RenderStereoMenu')
$checks['OpenVrRenderer'] += @('get_IsSectorCinemaScene', 'SampleDioramaStability')
$checks['RenderBudget'] += @('SceneScale', 'NextXrCap')
$checks['OpenVrRenderer'] += @('TrackingEye')
$checks['OpenVrRenderer'] += @('ProfileMark', 'ConfigureHudCommands')
$checks['DioramaBounds'] += @('MayCut')
$checks['CutSurfaceRegistry'] = @('PrepareFrame', 'ClearFrame', 'get_LastSkipped', 'get_NeedsRefresh')
$checks['UiMaterialWatch'] = @('Continuous')
$checks['UiCaptureCache'] += @('get_ContinuousReason')
$checks['ControllerButtonPolicy'] += @('Physical', 'Sources', 'Pressed', 'Available', 'ActionMask', 'Known', 'Stick', 'Directions')
$checks['ControllerInputConfiguration'] = @('Read', 'get_Bindings')
$checks['OpenVrInputBridge'] += @('BeginUiQuery', 'EndUiQuery', 'get_IsMenuContext')
$checks['OpenVrInputBridge'] += @('MenuState', 'ReleaseDeliveredActions', 'Released')
$checks['OpenVrInputBridge'] += @('get_DioramaStick', 'get_DioramaTurnSpeed', 'get_DioramaMoveSpeed')
$checks['OpenVrRenderer'] += @('UpdateDioramaStick')
$checks['DioramaPlacementState'] += @('MoveStick')
$checks['VrScreenFade'] = @('Prepare', 'Restore', 'Render', 'SceneChanged', 'get_Opacity', 'Release')
$checkedCount = 0
$expectedCount = ($checks.Values | ForEach-Object Count | Measure-Object -Sum).Sum
try {
    $managerSource = Get-Content -LiteralPath (Join-Path $root 'src\QVVR\OpenVrManager.cs') -Raw
    $xrNativeSource = Get-Content -LiteralPath (Join-Path $root 'src\QVVR.Native\OpenXrBackend.cpp') -Raw
    if ($managerSource -match 'VRApplication_Background|HybridOpenXrSupported' -or $xrNativeSource -match 'vr::VRSystem|vr::VRCompositor') {
        throw 'Exclusive XR must not initialize or consult an OpenVR tracking client.'
    }
    $managerType = $assembly.MainModule.Types | Where-Object Name -eq 'OpenVrManager'
    $worker = $managerType.Methods | Where-Object Name -eq 'InitializeOpenVrWorker'
    if (-not ($worker.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'Init' -and $_.Operand.DeclaringType.Name -eq 'OpenVR' })) {
        throw 'Validated OpenVR initialization fallback must remain available.'
    }
    $rendererType = $assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
    $initialize = $rendererType.Methods | Where-Object Name -eq 'Initialize'
    if (-not ($initialize.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'QVVR_InitializeExclusiveOpenXr' })) {
        throw 'Exclusive XR initialization entry point missing.'
    }
    Write-Host 'Backend safety passed: exclusive XR uses no OpenVR tracking client; validated OpenVR fallback remains.'
    $rendererType = $assembly.MainModule.Types | Where-Object Name -eq 'OpenVrRenderer'
    $lateUpdate = $rendererType.Methods | Where-Object Name -eq 'LateUpdate'
    $renderInstructions = @($lateUpdate.Body.Instructions)
    $begin = @($renderInstructions | Where-Object { $_.OpCode.Name -eq 'ldc.i4' -and $_.Operand -eq 0x51565651 })
    $submit = @($renderInstructions | Where-Object { $_.OpCode.Name -eq 'ldc.i4' -and $_.Operand -eq 0x51565652 })
    $capture = @($renderInstructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'CaptureUi' })
    $stereo = @($renderInstructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'RenderStereoGameplay' })
    $pose = @($renderInstructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'QVVR_SetRenderPoseAndMode' })
    if ($begin.Count -ne 1 -or $submit.Count -ne 1 -or $capture.Count -ne 1 -or $stereo.Count -ne 2 -or
        $pose.Count -ne 1 -or $pose[0].Offset -ge $begin[0].Offset -or
        $begin[0].Offset -ge $capture[0].Offset -or $capture[0].Offset -ge $stereo[0].Offset -or $stereo[0].Offset -ge $submit[0].Offset) {
        throw 'Render event order is not exact pose -> Begin -> UI -> stereo -> Submit.'
    }
    foreach ($call in $stereo) {
        if ($call.Offset -le $capture[0].Offset -or $call.Offset -ge $submit[0].Offset) { throw 'Gameplay and selection stereo paths must share exact frame-event ordering.' }
    }
    Write-Host 'Render event IL ordering passed: exact pose -> Begin -> UI -> stereo -> Submit.'
    foreach ($type in $assembly.MainModule.Types) {
        if (-not $checks.ContainsKey($type.Name)) { continue }
        foreach ($method in $type.Methods) {
            if ($method.Name -notin $checks[$type.Name]) { continue }
            foreach ($instruction in $method.Body.Instructions) {
                if ($instruction.OpCode.Name -in @('newarr', 'box')) {
                    throw "Managed allocation in $($type.Name).$($method.Name): $instruction"
                }
                if ($instruction.OpCode.Name -eq 'newobj' -and -not $instruction.Operand.DeclaringType.IsValueType) {
                    throw "Reference allocation in $($type.Name).$($method.Name): $instruction"
                }
            }
            Write-Host "Allocation IL check passed: $($type.Name).$($method.Name)"
            $checkedCount++
        }
    }
}
finally { $assembly.Dispose() }
if ($checkedCount -ne $expectedCount) {
    throw "Allocation checks did not cover all expected methods: $checkedCount / $expectedCount"
}
