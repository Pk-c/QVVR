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
        internal ConfigEntry<float> EyeTextureResolutionScale;
        internal ConfigEntry<bool> FlipEyeTextureY;
        internal ConfigEntry<bool> VrControllerInput;
        internal ConfigEntry<bool> TwoGripWorldGrab;
        internal ConfigEntry<bool> RightGripWorldGrab;
        internal ConfigEntry<float> RightGripTranslationGain;
        internal ConfigEntry<bool> IndependentDioramaView;
        internal ConfigEntry<float> DioramaWorldScale;
        internal ConfigEntry<bool> PlacementSaved;
        internal ConfigEntry<Vector3> PlacementOffset, PlacementEuler;
        internal ConfigEntry<float> PreferredSizeMeters;
        internal ConfigEntry<float> WorldGrabTranslationGain;
        internal ConfigEntry<float> DioramaMoveSensitivity, DioramaRotationSensitivity;
        internal ConfigEntry<float> PanelWidth;
        internal ConfigEntry<float> PanelDistance;
        internal ConfigEntry<float> PanelFollowLag;
        internal ConfigEntry<float> GameplayHudScale;
        internal ConfigEntry<float> GameplayHudDistance;
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
        internal ConfigEntry<int> UiCaptureRate;
        internal ConfigEntry<int> MenuCaptureRate;
        internal ConfigEntry<float> UiTextureScale;
        internal ConfigEntry<int> EyeMsaaSamples;
        internal ConfigEntry<int> QualityPreset;
        private ConfigEntry<int> qualityRevision;
        private ConfigEntry<int> featherRevision;
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
            StereoSelectionMenus = Config.Bind("VR", "StereoSelectionMenus", false,
                "Experimental full stereo costume/map selections without gameplay placement/cylinder/passthrough. Off until Frame framing/performance testing. Title/loading/unknown states remain 2D. False restores captured 2D menus. Live setting.");
            EyeTextureResolutionScale = Config.Bind("VR", "EyeTextureResolutionScale", 1f,
                "Scale applied to runtime-recommended per-eye size; applies on next launch.");
            EyeMsaaSamples = Config.Bind("VR", "EyeMsaaSamples", 2,
                "Eye geometry MSAA: 1 (off), 2 or 4; resolved on GPU before OpenVR submission. Requires relaunch.");
            QualityPreset = Config.Bind("VR", "QualityPreset", 1,
                "0=Performance, 1=Balanced, 2=Sharp; settings-menu presets apply on next launch.");
            qualityRevision = Config.Bind("VR", "QualityRevision", 0, "One-time migration of the old shipped 0.8 eye scale.");
            FlipEyeTextureY = Config.Bind("VR", "FlipEyeTextureY", true,
                "Invert the submitted eye texture V bounds for Unity D3D11 render targets.");
            VrControllerInput = Config.Bind("Controls", "VrControllerInput", true,
                "Bridge OpenVR controller sticks and buttons into QV's Rewired actions.");
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
            PanelWidth = Config.Bind("Comfort", "PanelWidthMeters", 2.4f,
                "Physical width of the 16:9 game/UI panel; range 1 to 4 meters.");
            PanelDistance = Config.Bind("Comfort", "PanelDistanceMeters", 2.8f,
                "Physical distance of the game/UI panel; range 1.5 to 5 meters.");
            PanelFollowLag = Config.Bind("Comfort", "PanelFollowLagSeconds", 0.35f,
                "Exponential follow time constant for panels only, not the HMD; range 0 to 1.5 seconds.");
            GameplayHudScale = Config.Bind("Comfort", "GameplayHudScale", 2f,
                "Gameplay HUD panel size multiplier, 0.5 to 3. Independent of 2D title/menu UI. Live setting.");
            GameplayHudDistance = Config.Bind("Comfort", "GameplayHudDistanceMeters", 2.8f,
                "Gameplay HUD distance, 1 to 5 physical meters. Does not change the title/menu panel distance. Live setting.");
            CameraDistanceScale = Config.Bind("Comfort", "CameraDistanceScale", 0.4f,
                "Scale of the original camera-to-character offset in playable scenes; 1 is original, range 0.15 to 1.5.");
            WorldUnitsPerMeter = Config.Bind("Comfort", "WorldUnitsPerMeter", 1f,
                "Game units per physical VR meter for head translation and IPD; range 0.25 to 10.");
            ViewPitchDegrees = Config.Bind("Comfort", "ViewPitchDegrees", 0f,
                "Live gameplay view tilt relative to QV's camera, -60 to +60 degrees. Positive looks downward; HMD tracking is never smoothed.");
            DioramaEnabled = Config.Bind("Diorama", "Enabled", true,
                "Clip gameplay fragments to a vertical cylinder. HUD and 2D menus remain independent. Live setting.");
            DioramaWorldScale = Config.Bind("Diorama", "WorldScale", 1f,
                "Physical diorama size multiplier, 0.001 to 10. Both grips adjust size alongside translation/rotation; live menu size changes preserve center. Entry fits saved preferred physical size. Full stereo head translation is preserved.");
            PlacementSaved = Config.Bind("Diorama", "PlacementSaved", false, "A reusable physical layout has been saved after a placement or first automatic fit.");
            PlacementOffset = Config.Bind("Diorama", "PlacementOffsetMeters", new Vector3(0f, -0.35f, 1.6f),
                "Saved cylinder center relative to the user's upright heading at gesture release; next level reuses it with front/visibility safeguards.");
            PlacementEuler = Config.Bind("Diorama", "PlacementEulerDegrees", Vector3.zero, "Saved diorama orientation relative to the user's upright heading.");
            PreferredSizeMeters = Config.Bind("Diorama", "PreferredSizeMeters", 1.6f, "Saved physical largest cylinder dimension; first entry defaults to 1.6 m. Entry fit clamps 0.05-4 m; in-level gestures keep full size range.");
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
            BlackCutSurfaces = Config.Bind("Diorama", "BlackCutSurfaces", false,
                "Experimental GPU stencil caps: close clipped opaque solids in black, leaving empty space transparent. Extra geometry pass; off until headset correctness/performance testing. Open/non-manifold meshes may not cap correctly. Live setting.");
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
            UiCaptureRate = Config.Bind("Performance", "UiCaptureRate", 36,
                "Maximum GPU capture refresh for gameplay HUD; HMD/eye tracking remains compositor-paced.");
            MenuCaptureRate = Config.Bind("Performance", "MenuCaptureRate", 72,
                "Maximum GPU capture refresh for 2D scenes and their UI; separate from gameplay HUD capture.");
            UiTextureScale = Config.Bind("VR", "UiTextureScale", 1.5f,
                "UI supersampling relative to 1920x1080, range 1 to 2; GPU mipmaps reduce text shimmer. Requires relaunch.");
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
            if (vrManager != null)
                Destroy(vrManager);
        }
    }
}
