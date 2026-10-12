namespace QVVR
{
    internal enum IntroPresentation { Unknown, Title, World, Costume, Stage, Exit }

    internal static class MenuScenePolicy
    {
        // Verified Windows QV build: Landing is 2D; 001_Intro contains the
        // actual costume models, map meshes and both selection state machines.
        internal static bool IsIntroScene(string name) { return name == "001_Intro"; }
        internal static bool StereoSelection(bool enabled, bool introScene, IntroPresentation state)
        { return enabled && introScene && (state == IntroPresentation.Costume || state == IntroPresentation.Stage); }
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
