using System;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using UnityEngine;

namespace QVVR
{
    [BepInPlugin(Guid, Name, Version)]
    public sealed class Plugin : BaseUnityPlugin
    {
        public const string Guid = "dev.qvvr.prototype";
        public const string Name = "QVVR";
        public const string Version = "0.1.0";

        internal static ManualLogSource Log;

        internal ConfigEntry<bool> VrEnabled;
        internal ConfigEntry<bool> StereoSelectionMenus;
        internal ConfigEntry<float> IntroHubDistanceScale;
        internal ConfigEntry<float> EyeTextureResolutionScale;
        internal ConfigEntry<bool> FlipEyeTextureY;
        internal ConfigEntry<bool> VrControllerInput;
        internal ControllerInputConfiguration InputControls;
        internal ConfigEntry<bool> TwoGripWorldGrab;
        internal ConfigEntry<bool> RightGripWorldGrab;
        internal ConfigEntry<float> RightGripTranslationGain;
        internal ConfigEntry<bool> IndependentDioramaView;
        internal ConfigEntry<float> DioramaWorldScale;
        internal ConfigEntry<bool> PlacementSaved;
        internal ConfigEntry<Vector3> PlacementOffset, PlacementEuler;
        internal ConfigEntry<float> PreferredSizeMeters;
        internal ConfigEntry<float> EntrySizeMultiplier, EntryDistanceMultiplier;
        internal ConfigEntry<float> WorldGrabTranslationGain;
        internal ConfigEntry<float> DioramaMoveSensitivity, DioramaRotationSensitivity;
        internal ConfigEntry<float> PanelWidth;
        internal ConfigEntry<float> PanelDistance;
        internal ConfigEntry<float> PanelFollowLag;
        internal ConfigEntry<bool> CenterDialogs;
        internal ConfigEntry<float> LevelEntrySeconds;
        internal ConfigEntry<float> GameplayHudScale;
        internal ConfigEntry<float> GameplayHudDistance;
        internal ConfigEntry<float> HubPauseDistance, XrResolutionCap;
        internal ConfigEntry<float> GameplayHudInset;
        internal ConfigEntry<float> CameraDistanceScale;
        internal ConfigEntry<float> WorldUnitsPerMeter;
        internal ConfigEntry<float> ViewPitchDegrees;
        internal ConfigEntry<bool> DioramaEnabled;
        internal ConfigEntry<float> DioramaRadius;
        internal ConfigEntry<float> DioramaHeight;
        internal ConfigEntry<float> DioramaCenterHeight;
        internal ConfigEntry<float> DioramaFeatherWidth;
        internal ConfigEntry<bool> HideDecorativeClouds;
        internal ConfigEntry<bool> LiquidDepthFix, BlackCutSurfaces;
        internal ConfigEntry<bool> DioramaFollowPlayer;
        internal ConfigEntry<bool> DioramaFollowCamera;
        internal ConfigEntry<bool> PassthroughEnabled;
        internal ConfigEntry<int> VoidBackground;
        internal ConfigEntry<int> TargetFrameRate;
        internal ConfigEntry<int> MaxQueuedFrames;
        internal ConfigEntry<bool> DisableVSync;
        internal ConfigEntry<bool> CompositorFramePacing;
        internal ConfigEntry<bool> DisableRealtimeShadows;
        internal ConfigEntry<bool> CullOutsideDiorama, AdaptiveUiCapture, DirectHudOverlay, DetailedGpuTimings, PostSubmitMaintenance, LiveCapBounds;
        internal ConfigEntry<bool> LightweightUiMaintenance, DiagnosticsEnabled;
        internal ConfigEntry<bool> WaterFoamFix;
        internal ConfigEntry<int> UiCaptureRate;
        internal ConfigEntry<int> MenuCaptureRate;
        internal ConfigEntry<float> UiTextureScale;
        internal ConfigEntry<int> EyeMsaaSamples;
        internal ConfigEntry<int> QualityPreset;
        private ConfigEntry<int> qualityRevision;
        private ConfigEntry<int> featherRevision;
        private ConfigEntry<int> uiQualityRevision;
        internal ConfigEntry<KeyboardShortcut> RecenterKey;
        internal ConfigEntry<KeyboardShortcut> ToggleVrKey;

        private OpenVrManager vrManager;

        private void Awake()
        {
            Log = Logger;
            BindConfiguration();
            if (qualityRevision.Value < 1)
            {
                // Migrate only the old shipped scale; preserve custom scales
                // and every saved camera/comfort setting.
                if (Mathf.Approximately(EyeTextureResolutionScale.Value, 0.8f))
                    EyeTextureResolutionScale.Value = 1f;
                qualityRevision.Value = 1;
                Config.Save();
            }
            if (featherRevision.Value < 1)
            {
                DioramaFeatherWidth.Value = DioramaMath.UpgradeFeatherWidth(DioramaFeatherWidth.Value);
                featherRevision.Value = 1;
                Config.Save();
            }
            if (uiQualityRevision.Value < 1)
            {
                UiTextureScale.Value = RenderBudget.UpgradeUiScale(UiTextureScale.Value);
                uiQualityRevision.Value = 1;
                Config.Save();
            }
            // Update only untouched first-entry defaults, never saved/custom poses.
            if (!PlacementSaved.Value && SpatialMath.LegacyDefaultOffset(PlacementOffset.Value))
            {
                PlacementOffset.Value = SpatialMath.DefaultOffset;
                Config.Save();
            }
            // Settings changed interactively are saved once on menu close.
            Config.SaveOnConfigSet = false;

            Application.runInBackground = true;
            if (TargetFrameRate.Value > 0)
                Application.targetFrameRate = TargetFrameRate.Value;
            if (MaxQueuedFrames.Value >= 0)
                QualitySettings.maxQueuedFrames = MaxQueuedFrames.Value;
            if (DisableVSync.Value)
                QualitySettings.vSyncCount = 0;

            vrManager = gameObject.AddComponent<OpenVrManager>();
            vrManager.Initialize(this);

            Logger.LogInfo(
                "QVVR 0.1.0 loaded. F7 recenters; F8 toggles VR. " +
                "OpenVR injection starts immediately; desktop fallback remains available.");
        }

        private void Update()
        {
            if (RecenterKey.Value.IsDown() && vrManager != null)
                vrManager.Recenter();

            if (ToggleVrKey.Value.IsDown())
            {
                VrEnabled.Value = !VrEnabled.Value;
                Config.Save();
                Logger.LogInfo("VR " + (VrEnabled.Value ? "enabled" : "disabled"));
            }
        }

        private void BindConfiguration()
        {
            VrEnabled = Config.Bind("VR", "Enabled", true,
                "Initialize OpenVR and submit stereoscopic frames.");
            StereoSelectionMenus = Config.Bind("VR", "StereoSelectionMenus", true,
                "Full stereo intro hub/costume/map screens with gameplay HUD settings, without gameplay placement/cylinder/passthrough. Enabled by the reference Frame profile. Title/loading/unknown states remain 2D. False restores captured 2D menus. Config-only live setting.");
            IntroHubDistanceScale = Config.Bind("VR", "IntroHubDistanceScale", 0.35f,
                "Stereo costume-access hub camera distance: 0.35 retains 35% of original forward depth to its world anchor; range 0.15-1, with a 1-unit near guard. 1 restores original framing. Does not affect costume/map cameras, head tracking or desktop. Live setting.");
            EyeTextureResolutionScale = Config.Bind("VR", "EyeTextureResolutionScale", 1f,
                "Scale applied to runtime-recommended per-eye size; applies on next launch.");
            XrResolutionCap = Config.Bind("VR", "XrResolutionCap", 1f,
                "Exclusive OpenXR 3D eye-scale ceiling to reduce missed 72 Hz frames; default 1.0, 0 disables, positive range 0.5-1.5. Does not change requested profile, OpenVR or HUD capture resolution. Requires manual relaunch.");
            HubPauseDistance = Config.Bind("Comfort", "HubPauseDistanceMeters", 1.2f,
                "Only the costume-access hub pause/options/achievements overlay distance, 0.6-3 m. Independent of game HUD, map/costume screens and the VR settings panel. Config-only setting.");
            CenterDialogs = Config.Bind("Comfort", "CenterDialogs", true,
                "Center QV dialogue boxes in the viewer-following VR HUD instead of projecting them beside game actors. Capture-only: preserves desktop and fixed flat cinematics, portraits, text and animations. No additional render pass.");
            LevelEntrySeconds = Config.Bind("Comfort", "LevelEntrySeconds", 1.5f,
                "Standard level-entry fade before dialogue/controls in independent diorama VR, range 1.5-5.5 seconds. Default 1.5 retains the game's internal camera-focus duration; 5.5 restores original timing. Does not skip story cinematics or change desktop timing. Applies when GameStart next runs, not to a transition already playing.");
            EyeMsaaSamples = Config.Bind("VR", "EyeMsaaSamples", 2,
                "Eye geometry MSAA: 1 (off), 2 or 4; resolved on GPU before OpenVR submission. Requires relaunch.");
            QualityPreset = Config.Bind("VR", "QualityPreset", 1,
                "0=Performance, 1=Balanced, 2=Sharp; settings-menu presets apply on next launch.");
            qualityRevision = Config.Bind("VR", "QualityRevision", 0, "One-time migration of the old shipped 0.8 eye scale.");
            FlipEyeTextureY = Config.Bind("VR", "FlipEyeTextureY", true,
                "Invert the submitted eye texture V bounds for Unity D3D11 render targets.");
            VrControllerInput = Config.Bind("Controls", "VrControllerInput", true,
                "Bridge OpenVR controller sticks and buttons into QV's Rewired actions.");
            InputControls = new ControllerInputConfiguration(Config);
            TwoGripWorldGrab = Config.Bind("Controls", "TwoGripWorldGrab", true,
                "In gameplay, hold both grips to translate, resize and rotate the diorama using the shared hand frame. Release either grip to retain the pose; sensitivity is configurable.");
            DioramaMoveSensitivity = Config.Bind("Controls", "DioramaMoveSensitivity", 1.15f,
                "Two-hand translation gain in tracking space, default 1.15 (15% faster), range 0.25-3. Does not affect head tracking or resize. Latched on grab.");
            DioramaRotationSensitivity = Config.Bind("Controls", "DioramaRotationSensitivity", 1.1f,
                "Two-hand rotation gain, default 1.1 (10% faster), range 0.25-3. Does not affect head tracking or resize. Latched on grab.");
            RightGripWorldGrab = Config.Bind("Controls", "RightGripWorldGrab", false,
                "Legacy setting retained for configuration compatibility; right grip alone no longer manipulates the diorama. Hold both grips for natural translation, size and rotation.");
            RightGripTranslationGain = Config.Bind("Controls", "RightGripTranslationGain", 20f,
                "Right-only placement sensitivity, 1 to 100, default 20 (5x the old gain 4). Independent of two-hand pan/zoom and world scale. Live menu setting; sampled at each grab start.");
            IndependentDioramaView = Config.Bind("Comfort", "IndependentDioramaView", true,
                "Latch the game view pose at level entry/recenter, then follow player translation only. Head tracking affects eyes, never the diorama anchor. False restores the legacy game-camera view/follow settings.");
            WorldGrabTranslationGain = Config.Bind("Controls", "WorldGrabTranslationGain", 4f,
                "Legacy pan sensitivity retained for configuration compatibility. The physical two-hand gesture uses DioramaMoveSensitivity and DioramaRotationSensitivity instead.");
            PanelWidth = Config.Bind("Comfort", "PanelWidthMeters", 1.8f,
                "Physical width of the 16:9 game/UI panel; range 1 to 4 meters. Config-only setting.");
            PanelDistance = Config.Bind("Comfort", "PanelDistanceMeters", 1.5f,
                "Physical distance of the game/UI panel; range 1.5 to 5 meters. Config-only setting.");
            PanelFollowLag = Config.Bind("Comfort", "PanelFollowLagSeconds", 0.6f,
                "Exponential follow time constant for panels only, not the HMD; range 0 to 1.5 seconds. Config-only setting.");
            GameplayHudScale = Config.Bind("Comfort", "GameplayHudScale", 1.8f,
                "Gameplay and stereo intro HUD panel size multiplier, 0.5 to 3. Independent of captured 2D title/menu UI. Config-only setting.");
            GameplayHudDistance = Config.Bind("Comfort", "GameplayHudDistanceMeters", 1.4f,
                "Gameplay and stereo intro HUD distance, 1 to 5 physical meters. Does not change captured 2D title/menu panel distance. Config-only setting.");
            GameplayHudInset = Config.Bind("Comfort", "GameplayHudInsetPercent", 29f,
                "Move captured gameplay/stereo intro UI toward center by insetting root layout anchors, 0-45 percent per edge. Below 50 prevents collapsed/inverted stretch panels. Keeps local font/widget size and game references; 0 restores anchors. Title/cinematic/flat recovery unchanged. Config-only setting.");
            CameraDistanceScale = Config.Bind("Comfort", "CameraDistanceScale", 0.4f,
                "Scale of the original camera-to-character offset in playable scenes; 1 is original, range 0.15 to 1.5.");
            WorldUnitsPerMeter = Config.Bind("Comfort", "WorldUnitsPerMeter", 1f,
                "Game units per physical VR meter for head translation and IPD; range 0.25 to 10.");
            ViewPitchDegrees = Config.Bind("Comfort", "ViewPitchDegrees", -16f,
                "Live gameplay view tilt relative to QV's camera, -60 to +60 degrees. Positive looks downward; HMD tracking is never smoothed.");
            DioramaEnabled = Config.Bind("Diorama", "Enabled", true,
                "True: miniature cylindrical diorama. False: full-world stereo VR at 1 game unit per meter, with right-stick yaw/forward/back camera navigation and player follow. Keeps saved diorama placement/size; HUD and 2D menus remain independent. Live VR menu toggle.");
            DioramaWorldScale = Config.Bind("Diorama", "WorldScale", 1f,
                "Physical diorama size multiplier, 0.001 to 10. Both grips adjust size alongside translation/rotation; live menu size changes preserve center. Entry fits saved preferred physical size. Full stereo head translation is preserved.");
            PlacementSaved = Config.Bind("Diorama", "PlacementSaved", false, "A reusable physical layout has been saved after a placement or first automatic fit.");
            PlacementOffset = Config.Bind("Diorama", "PlacementOffsetMeters", SpatialMath.DefaultOffset,
                "Saved cylinder center relative to upright heading; first-entry default is 1.2 m forward, 0.45 m below eyes. Next level reuses saved pose with visibility/size-clearance safeguards.");
            PlacementEuler = Config.Bind("Diorama", "PlacementEulerDegrees", Vector3.zero, "Saved diorama orientation relative to the user's upright heading.");
            PreferredSizeMeters = Config.Bind("Diorama", "PreferredSizeMeters", 1.6f, "Saved base largest cylinder dimension, before EntrySizeMultiplier. Default base 1.6 m gives 1.36 m with gain 0.85. Saves invert entry gains; fitted actual size clamps 0.05-4 m while in-level gestures keep the full range.");
            EntrySizeMultiplier = Config.Bind("Diorama", "EntrySizeMultiplier", 0.85f,
                "Level-entry size relative to the saved base preference, default 0.85 (15% smaller). Range 0.25-1.5; 1 restores prior framing. Saves invert this gain so entries never repeatedly shrink.");
            EntryDistanceMultiplier = Config.Bind("Diorama", "EntryDistanceMultiplier", 0.8f,
                "Level-entry forward distance relative to saved base offset, default 0.8 (20% closer), subject to cylinder clearance. Range 0.25-1.5; 1 restores prior distance. Height/rotation stay unchanged; saves invert this gain.");
            DioramaRadius = Config.Bind("Diorama", "Radius", 12f,
                "Cylinder radius in original game units, 0.5 to 200. Live setting.");
            DioramaHeight = Config.Bind("Diorama", "Height", 12f,
                "Cylinder total height in original game units, 0.5 to 200. Live setting.");
            DioramaCenterHeight = Config.Bind("Diorama", "CenterHeight", 3f,
                "Cylinder center Y offset from the initial player anchor, translated with the original game camera when FollowCamera is enabled. Live setting.");
            DioramaFeatherWidth = Config.Bind("Diorama", "FeatherWidth", DioramaMath.DefaultFeatherWidth,
                "Inward smooth alpha/color fade at cylinder sides and caps, default 1 game unit; 0 disables. Clamped to preserve an opaque core. Live setting.");
            featherRevision = Config.Bind("Diorama", "FeatherRevision", 0,
                "One-time widening of the old shipped 0.35 feather to 1; custom widths and disabled fade are preserved.");
            HideDecorativeClouds = Config.Bind("Diorama", "HideDecorativeClouds", true,
                "Hide QV's decorative Clouds mesh and screen-space cloud shadow during VR gameplay renders only. RainCloud gameplay, UI, menus and desktop rendering are preserved. Live setting.");
            LiquidDepthFix = Config.Bind("Diorama", "LiquidDepthFix", true,
                "Generate a fresh depth texture for each gameplay eye when a known depth-dependent liquid is active. Fixes stale/missing water/ink depth without faking camera position; adds an opaque depth pass. Live setting.");
            WaterFoamFix = Config.Bind("Diorama", "WaterFoamFix", true,
                "Experimental VR-only blue WaterBlockMat compatibility: suppress its depth/view-dependent white foam while preserving original water/depth colors, geometry and alpha. Restores the live original material after stereo rendering; ink, fog, movies and desktop are untouched. False restores foam for A/B testing. No extra render pass.");
            BlackCutSurfaces = Config.Bind("Diorama", "BlackCutSurfaces", true,
                "Experimental GPU stencil caps: close clipped opaque solids in black, leaving empty space transparent. Enabled by the reference Frame profile; adds geometry work. Open/non-manifold meshes may not cap correctly. Config-only live setting; false disables.");
            DioramaFollowCamera = Config.Bind("Diorama", "FollowCamera", true,
                "Move the cylinder with the original game camera, preserving its initial player-centered offset. Does not follow HMD motion or manual grip translation. Takes priority over FollowPlayer.");
            DioramaFollowPlayer = Config.Bind("Diorama", "FollowPlayer", false,
                "Legacy option when FollowCamera is false: true follows the player, false anchors the cylinder at level entry.");
            PassthroughEnabled = Config.Bind("Diorama", "Passthrough", false,
                "Experimental exclusive OpenXR ALPHA_BLEND with XR tracking/controllers. Requires restart. If unsupported/failing, returns to the validated OpenVR diorama with the selected opaque void color; no simultaneous API clients.");
            VoidBackground = Config.Bind("Diorama", "VoidBackground", 0,
                "Opaque fallback exterior color: 0=black (default), 1=green. Live menu setting; ignored during OpenXR passthrough.");
            TargetFrameRate = Config.Bind("Performance", "TargetFrameRate", 72,
                "Unity target frame rate. SteamVR remains authoritative.");
            MaxQueuedFrames = Config.Bind("Performance", "MaxQueuedFrames", 1,
                "Limit queued GPU frames to reduce head-motion latency.");
            DisableVSync = Config.Bind("Performance", "DisableVSync", true,
                "Disable desktop VSync so SteamVR controls frame pacing.");
            CompositorFramePacing = Config.Bind("Performance", "CompositorFramePacing", true,
                "Use graphics-thread WaitGetPoses before rendering instead of also sleeping at Unity targetFrameRate.");
            DisableRealtimeShadows = Config.Bind("Performance", "DisableRealtimeShadowsInVr", true,
                "Disable repeated realtime shadow-map rendering in VR; original shadow setting is restored on fallback.");
            CullOutsideDiorama = Config.Bind("Performance", "CullOutsideDiorama", true,
                "Conservatively omit cached scene meshes outside the cylinder during stereo draws only. Also prune invisible liquid depth and eligible cap bounds. Live A/B switch; original states restored after both eyes.");
            LiveCapBounds = Config.Bind("Performance", "LiveCapBounds", true,
                "Sample live shared-mesh bounds once per stereo frame to omit cap replays that cannot cross the cylinder. Requires CullOutsideDiorama. Disable for a controlled cap-cost comparison.");
            AdaptiveUiCapture = Config.Bind("Performance", "AdaptiveUiCapture", true,
                "Reuse unchanged full-resolution HUD captures. Dirty graphics, transforms, CanvasGroups, animation and custom materials retain updates at the configured capture rate. Live A/B switch.");
            LightweightUiMaintenance = Config.Bind("Performance", "LightweightUiMaintenance", true,
                "Retain unchanged UI dirty subscriptions across scans. For continuously animated/unknown UI, use normal full-rate capture without snapshot tracking and retry caching every 2 seconds. False restores full cache rebuilds for A/B testing.");
            DiagnosticsEnabled = Config.Bind("Performance", "DiagnosticsEnabled", false,
                "Developer diagnostics: verbose 5-second logs, per-eye cylinder validation math and one-shot GPU constant-buffer/shader capture. False uses concise 30-second performance summaries without shader dumps. Requires manual relaunch.");
            DirectHudOverlay = Config.Bind("Performance", "DirectHudOverlay", true,
                "Draw the ordinary captured HUD quad at the end of each world camera instead of rendering another camera. Settings canvas and flat scenes keep the validated camera path. Live A/B switch.");
            DetailedGpuTimings = Config.Bind("Performance", "DetailedGpuTimings", false,
                "Enable nonblocking GPU timestamps for UI, world eyes, depth, HUD and XR copy; log every 5 seconds. Diagnostic overhead; requires restart. No eye texture readback.");
            PostSubmitMaintenance = Config.Bind("Performance", "PostSubmitMaintenance", true,
                "Move cold UI/scene scans and diagnostics after stereo enqueue, outside the fresh-pose-to-eye path. Disable for a controlled scheduling comparison; no head-pose smoothing.");
            UiCaptureRate = Config.Bind("Performance", "UiCaptureRate", 36,
                "Maximum GPU capture refresh for gameplay and stereo intro HUD; HMD/eye tracking remains compositor-paced.");
            MenuCaptureRate = Config.Bind("Performance", "MenuCaptureRate", 72,
                "Maximum GPU capture refresh for captured 2D scenes and their UI; separate from gameplay/stereo intro HUD capture.");
            UiTextureScale = Config.Bind("VR", "UiTextureScale", RenderBudget.DefaultUiScale,
                "UI-only supersampling relative to 1920x1080, default 1.75 (3360x1890), range 1-2. GPU mipmaps/trilinear filtering retained; world/eye resolution and capture cadence unchanged. Set 1.5 for rollback after migration. Requires manual relaunch.");
            uiQualityRevision = Config.Bind("VR", "UiQualityRevision", 0,
                "One-time migration of old default UI scale 1.5 to 1.75; custom values and subsequent manual rollback are preserved.");
            RecenterKey = Config.Bind("Controls", "RecenterVR", new KeyboardShortcut(KeyCode.F7),
                "Recenter the current HMD pose.");
            ToggleVrKey = Config.Bind("Controls", "ToggleVR", new KeyboardShortcut(KeyCode.F8),
                "Toggle VR rendering without unloading the plugin.");
        }

        internal void SelectQualityPreset(int preset)
        {
            QualityPreset.Value = Mathf.Clamp(preset, 0, 2);
            EyeTextureResolutionScale.Value = RenderBudget.PresetScale(QualityPreset.Value);
            EyeMsaaSamples.Value = 2;
        }

        private void OnDestroy()
        {
            if (InputControls != null) InputControls.Dispose();
            if (vrManager != null)
                Destroy(vrManager);
        }
    }
}
