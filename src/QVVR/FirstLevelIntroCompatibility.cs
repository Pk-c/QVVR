using System;
using System.Reflection;
using HarmonyLib;
using UnityEngine;

namespace QVVR
{
    internal static class LevelIntroPolicy
    {
        internal static bool Scene(string name) { return name == "1_1"; }
        internal static bool Active(bool firstScene, bool directorActive, int state, double time, double duration, bool started)
        {
            if (!firstScene || !directorActive) return false;
            if (state == 1) return true; // Unity PlayState.Playing
            return state == 0 && (started || (!double.IsNaN(time) && !double.IsNaN(duration) && time > 0 && time < duration));
        }
    }
    internal sealed class FirstLevelIntroCompatibility
    {
        private static FirstLevelIntroCompatibility active;
        private OpenVrRenderer renderer;
        private Harmony harmony;
        private Type managerType;
        private FieldInfo directorField, cameraField;
        private PropertyInfo stateProperty, timeProperty, durationProperty;
        private UnityEngine.Object manager;
        private Component director;
        private Camera cinemaCamera;
        private bool started;
        internal void Initialize(OpenVrRenderer owner)
        {
            renderer = owner; active = this;
            try
            {
                managerType = AccessTools.TypeByName("GameManager");
                directorField = AccessTools.Field(managerType, "_playableDirector");
                cameraField = AccessTools.Field(managerType, "mainCam");
                stateProperty = AccessTools.Property(directorField.FieldType, "state");
                timeProperty = AccessTools.Property(directorField.FieldType, "time");
                durationProperty = AccessTools.Property(directorField.FieldType, "duration");
                if (stateProperty == null || timeProperty == null || durationProperty == null) throw new MissingMemberException("Director state/time/duration unavailable.");
                harmony = new Harmony(Plugin.Guid + ".first-level-intro");
                harmony.Patch(AccessTools.DeclaredMethod(managerType, "SetDirector"), postfix: new HarmonyMethod(typeof(FirstLevelIntroCompatibility), "Started"));
                harmony.Patch(AccessTools.DeclaredMethod(managerType, "OnEndDirector"), postfix: new HarmonyMethod(typeof(FirstLevelIntroCompatibility), "Stopped"));
            }
            catch (Exception error)
            {
                Release(); Plugin.Log.LogWarning("QVVR first-level intro compatibility unavailable; normal scene rendering retained: " + error);
            }
        }
        private static void Started(UnityEngine.Object __instance)
        {
            if (active == null || !active.renderer.IsFirstLevelScene) return;
            active.manager = __instance; active.started = true; active.Refresh();
        }
        private static void Stopped(UnityEngine.Object __instance)
        {
            if (active == null || !active.renderer.IsFirstLevelScene) return;
            active.manager = __instance; active.started = false;
            active.renderer.SetLevelIntro(false, active.cameraField.GetValue(__instance) as Camera);
        }
        // State hooks plus cold recovery handle late injection, paused timelines,
        // natural completion and skip. Never reflect/discover objects per eye/frame.
        internal void Refresh()
        {
            if (renderer == null || !renderer.IsFirstLevelScene || directorField == null) return;
            if (manager == null) manager = UnityEngine.Object.FindObjectOfType(managerType);
            if (manager == null) return;
            Component current = directorField.GetValue(manager) as Component;
            if (current != director)
            {
                director = current; cinemaCamera = director == null ? null : director.GetComponentInChildren<Camera>(true);
            }
            bool playing = director != null && LevelIntroPolicy.Active(true, director.gameObject.activeInHierarchy,
                Convert.ToInt32(stateProperty.GetValue(director, null)),
                Convert.ToDouble(timeProperty.GetValue(director, null)), Convert.ToDouble(durationProperty.GetValue(director, null)), started);
            if (!playing) started = false;
            renderer.SetLevelIntro(playing, playing ? cinemaCamera : cameraField.GetValue(manager) as Camera);
        }
        internal void Reset() { manager = null; director = null; cinemaCamera = null; started = false; }
        internal void Release()
        {
            if (active == this) active = null;
            if (harmony != null) harmony.UnpatchSelf();
            harmony = null; Reset(); renderer = null; directorField = cameraField = null;
        }
    }
}
