namespace QVVR
{
    internal enum IntroPresentation { Unknown, Title, World, Costume, Stage, Exit }

    internal static class MenuScenePolicy
    {
        // Verified Windows QV build: Landing is 2D; 001_Intro contains the
        // actual costume models, map meshes and both selection state machines.
        internal static bool IsIntroScene(string name) { return name == "001_Intro"; }
        internal static bool StereoSelection(bool enabled, bool introScene, IntroPresentation state)
        { return enabled && introScene && (state == IntroPresentation.World || state == IntroPresentation.Costume || state == IntroPresentation.Stage); }
        // Full-scene menus use the same readable, upright HUD as gameplay.
        // Captured 2D recovery/title panels retain their original menu settings.
        internal static bool UseGameplayHud(bool gameplay, bool stereoMenu) { return gameplay || stereoMenu; }
        // Stereo selection screens keep the gameplay HUD size and distance, but
        // their cursor and camera-space map labels refresh at the menu rate.
        internal static int CaptureRate(bool gameplay, int hudRate, int menuRate)
        {
            int rate = gameplay ? hudRate : menuRate;
            return rate < 1 ? 1 : rate > 72 ? 72 : rate;
        }
        internal static bool RenderStereoMenu(bool stereoMenu, bool cinema) { return stereoMenu && !cinema; }
        internal static float HubHudScale(bool stereoMenu, IntroPresentation state, float normal)
        { return stereoMenu && state == IntroPresentation.World ? 4f : normal; }
        internal static bool HubPauseOverlay(bool introScene, IntroPresentation state)
        { return introScene && state == IntroPresentation.Exit; }
        internal static float PauseDistance(float value)
        { return float.IsNaN(value) || float.IsInfinity(value) ? 1.2f : System.Math.Max(0.6f, System.Math.Min(3f, value)); }
        internal static bool IsOpeningScene(string name) { return name == "Opening" || name == "Opening2"; }
        internal static bool FixedCinemaPanel(bool levelIntro, bool opening) { return levelIntro || opening; }
        internal static bool HideStageDim(bool stereoMenu, IntroPresentation state)
        { return stereoMenu && state == IntroPresentation.Stage; }
        internal static float HubAdvance(float depth, float scale)
        {
            if (float.IsNaN(depth) || float.IsInfinity(depth) || depth <= 1f) return 0f;
            float gain = float.IsNaN(scale) || float.IsInfinity(scale) ? 0.35f : System.Math.Min(1f, System.Math.Max(0.15f, scale));
            return depth - System.Math.Max(1f, depth * gain);
        }
        internal static IntroPresentation State(string name)
        {
            switch (name)
            {
                case "IntroState.TitleState": case "NewIntroState.TitleState": return IntroPresentation.Title;
                case "IntroState.WorldState": case "NewIntroState.WorldState": return IntroPresentation.World;
                case "IntroState.CostumeState": return IntroPresentation.Costume;
                case "IntroState.StageState": case "NewIntroState.StageState": return IntroPresentation.Stage;
                case "IntroState.ExitState": case "NewIntroState.ExitState": return IntroPresentation.Exit;
                default: return IntroPresentation.Unknown;
            }
        }
        internal static bool CaptureCanvas(bool introScene, int mode, bool sourceCamera)
        { return mode == 0 || (introScene && mode == 1 && sourceCamera); }
    }
}
