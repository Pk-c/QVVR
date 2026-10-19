using System;
using System.Reflection;
using HarmonyLib;
using UnityEngine;

namespace QVVR
{
    // Verified sector-clear movie in 001_Intro, NOT an arbitrary director or
    // the normal hub camera tween. Observe game events; never drive its timeline.
    internal sealed class SectorCinemaCompatibility
    {
        private static SectorCinemaCompatibility active;
        private OpenVrRenderer renderer;
        private Harmony harmony;
        private Type managerType, worldType;
        private FieldInfo directorField, worldCameraField;
        private PropertyInfo playingProperty, stateProperty, timeProperty, durationProperty;
        private UnityEngine.Object manager;
        private Component director;
        private Camera returnCamera, cinemaCamera;
        private bool wasPlaying;

        internal void Initialize(OpenVrRenderer owner)
        {
            renderer = owner; active = this;
            try
            {
                managerType = AccessTools.TypeByName("IntroEventManager");
                worldType = AccessTools.TypeByName("IntroWorldManager");
                directorField = AccessTools.Field(managerType, "_playableDirector");
                worldCameraField = AccessTools.Field(worldType, "_camera");
                playingProperty = AccessTools.Property(managerType, "IsPlaying");
                stateProperty = AccessTools.Property(directorField.FieldType, "state");
                timeProperty = AccessTools.Property(directorField.FieldType, "time");
                durationProperty = AccessTools.Property(directorField.FieldType, "duration");
                if (playingProperty == null || stateProperty == null || timeProperty == null || durationProperty == null)
                    throw new MissingMemberException("Sector movie state unavailable.");
                harmony = new Harmony(Plugin.Guid + ".sector-cinema");
                harmony.Patch(AccessTools.DeclaredMethod(managerType, "PlayCinema"),
                    postfix: new HarmonyMethod(typeof(SectorCinemaCompatibility), "Started"));
                harmony.Patch(AccessTools.DeclaredMethod(managerType, "OnEndCinema"),
                    postfix: new HarmonyMethod(typeof(SectorCinemaCompatibility), "Stopped"));
            }
            catch (Exception error)
            {
                Release(); Plugin.Log.LogWarning("QVVR sector cinema compatibility unavailable; existing rendering retained: " + error);
            }
        }
        private static void Started(UnityEngine.Object __instance, Camera __0)
        {
            if (active == null || active.renderer == null || !active.renderer.IsSectorCinemaScene) return;
            active.manager = __instance;
            active.returnCamera = __0; // Exact original camera argument, not Camera.main.
            active.Refresh();
        }
        private static void Stopped()
        {
            if (active == null || active.renderer == null || !active.renderer.IsSectorCinemaScene) return;
            active.wasPlaying = false;
            active.renderer.SetLevelIntro(false, active.returnCamera);
            active.director = null; active.cinemaCamera = null;
        }
        // Cold recovery also handles injection during a movie, paused movies,
        // skipped movies and an inactive director when a callback was missed.
        internal void Refresh()
        {
            if (renderer == null || !renderer.IsSectorCinemaScene || directorField == null) return;
            if (manager == null) manager = UnityEngine.Object.FindObjectOfType(managerType);
            if (manager == null)
            {
                if (wasPlaying) { wasPlaying = false; renderer.SetLevelIntro(false, returnCamera); }
                return;
            }
            if (returnCamera == null && worldCameraField != null)
            {
                UnityEngine.Object world = UnityEngine.Object.FindObjectOfType(worldType);
                if (world != null) returnCamera = worldCameraField.GetValue(world) as Camera;
            }
            Component current = directorField.GetValue(manager) as Component;
            if (current != director || cinemaCamera == null)
            {
                director = current;
                // Installed scene: CINE_LOBBY contains one active camera with
                // CinemachineBrain plus inactive virtual-camera rigs. The
                // manager's unused _camera field is NOT serialized/assigned.
                // Do not select a dormant virtual-camera Camera component.
                cinemaCamera = director == null ? null : director.GetComponentInChildren<Camera>(false);
            }
            bool playing = director != null && LevelIntroPolicy.Active(true, director.gameObject.activeInHierarchy,
                Convert.ToInt32(stateProperty.GetValue(director, null)), Convert.ToDouble(timeProperty.GetValue(director, null)),
                Convert.ToDouble(durationProperty.GetValue(director, null)), Convert.ToBoolean(playingProperty.GetValue(manager, null)));
            if (playing || wasPlaying) renderer.SetLevelIntro(playing, playing ? cinemaCamera : returnCamera);
            // Switching the mod's source restores its previous camera state.
            // Preserve PlayCinema's explicit disable of the hub camera, rather
            // than letting it perform an extra automatic render behind the movie.
            if (playing && cinemaCamera != null && returnCamera != null && returnCamera != cinemaCamera) returnCamera.enabled = false;
            wasPlaying = playing;
        }
        internal void Reset() { manager = null; director = null; returnCamera = cinemaCamera = null; wasPlaying = false; }
        internal void Release()
        {
            if (active == this) active = null;
            if (harmony != null) harmony.UnpatchSelf();
            harmony = null; Reset(); renderer = null; directorField = null;
        }
    }
}
