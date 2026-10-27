using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using System.Reflection.Emit;
using HarmonyLib;
using UnityEngine;

namespace QVVR
{
    internal static class LevelEntryPolicy
    {
        internal static float Duration(float original, bool independentVr, float requested)
        {
            if (!independentVr || original != 5.5f) return original;
            // GameStart also starts a 1.5 s camera focus tween. Keep that order
            // intact rather than invoking StartDialog/controls before it ends.
            if (float.IsNaN(requested) || float.IsInfinity(requested)) requested = 1.5f;
            return Math.Max(1.5f, Math.Min(5.5f, requested));
        }

        // The level-start camera tour cannot be followed from an independent VR
        // view. Level 1-1's director is the story intro, shown on a flat screen.
        internal static bool SkipTour(bool independentVr, bool enabled, bool firstLevel)
        {
            return independentVr && enabled && !firstLevel;
        }
    }

    internal sealed class LevelEntryCompatibility
    {
        private static LevelEntryCompatibility active;
        private OpenVrRenderer renderer;
        private Plugin plugin;
        private Harmony harmony;
        private FieldInfo directorField;
        private MethodInfo stopMethod;
        private PropertyInfo stateProperty;

        internal void Initialize(OpenVrRenderer owner, Plugin settings)
        {
            renderer = owner; plugin = settings;
            try
            {
                Type manager = AccessTools.TypeByName("GameManager");
                MethodInfo start = manager == null ? null : AccessTools.DeclaredMethod(manager, "GameStart", Type.EmptyTypes);
                if (start == null) throw new MissingMethodException("GameManager.GameStart unavailable.");
                harmony = new Harmony(Plugin.Guid + ".level-entry");
                harmony.Patch(start, transpiler: new HarmonyMethod(typeof(LevelEntryCompatibility), "ShortenFade"));
                active = this;
                Plugin.Trace("QVVR level-entry timing compatibility active: independent VR only; original callbacks and cinematics retained.");
                PatchTour(manager);
            }
            catch (Exception error)
            {
                Release();
                Plugin.Log.LogWarning("QVVR level-entry timing unavailable; original duration retained: " + error);
            }
        }

        // Cold patching only. Match both verified CanvasGroup fade durations in
        // GameStart, not arbitrary tween constants or global DOTween methods.
        private static IEnumerable<CodeInstruction> ShortenFade(IEnumerable<CodeInstruction> instructions)
        {
            var code = new List<CodeInstruction>(instructions);
            int matches = 0;
            for (int i = 0; i + 1 < code.Count; i++) if (EntryFade(code[i], code[i + 1])) matches++;
            if (matches != 2) throw new InvalidOperationException("Expected exactly two 5.5 s GameStart CanvasGroup fades.");
            MethodInfo duration = AccessTools.Method(typeof(LevelEntryCompatibility), "ResolveDuration");
            for (int i = code.Count - 2; i >= 0; i--)
                if (EntryFade(code[i], code[i + 1])) code.Insert(i + 1, new CodeInstruction(OpCodes.Call, duration));
            return code;
        }

        private static bool EntryFade(CodeInstruction duration, CodeInstruction call)
        {
            if (duration.opcode != OpCodes.Ldc_R4 || !(duration.operand is float) || (float)duration.operand != 5.5f ||
                call.opcode != OpCodes.Call) return false;
            MethodInfo fade = call.operand as MethodInfo;
            if (fade == null || fade.Name != "DOFade" || fade.DeclaringType.FullName != "DG.Tweening.DOTweenModuleUI") return false;
            ParameterInfo[] parameters = fade.GetParameters();
            return parameters.Length == 3 && parameters[0].ParameterType.FullName == "UnityEngine.CanvasGroup" &&
                parameters[1].ParameterType == typeof(float) && parameters[2].ParameterType == typeof(float);
        }

        // Optional: failure keeps the original tour and the fade shortening.
        private void PatchTour(Type manager)
        {
            try
            {
                MethodInfo setDirector = AccessTools.DeclaredMethod(manager, "SetDirector", Type.EmptyTypes);
                directorField = AccessTools.Field(manager, "_playableDirector");
                Type directorType = directorField == null ? null : directorField.FieldType;
                stopMethod = directorType == null ? null : AccessTools.Method(directorType, "Stop", Type.EmptyTypes);
                stateProperty = directorType == null ? null : AccessTools.Property(directorType, "state");
                if (setDirector == null || stopMethod == null || stateProperty == null) throw new MissingMemberException("GameManager.SetDirector / PlayableDirector.Stop unavailable.");
                harmony.Patch(setDirector, postfix: new HarmonyMethod(typeof(LevelEntryCompatibility), "TourStarted"));
                Plugin.Trace("QVVR level tour skip available: independent VR, setting Comfort.SkipLevelTour.");
            }
            catch (Exception error)
            {
                directorField = null; stopMethod = null; stateProperty = null;
                Plugin.Log.LogWarning("QVVR level tour skip unavailable; the original tour plays: " + error);
            }
        }

        private static void TourStarted(UnityEngine.Object __instance)
        {
            LevelEntryCompatibility entry = active;
            if (entry == null || entry.directorField == null) return;
            Component director = entry.directorField.GetValue(__instance) as Component;
            if (director == null) return;
            // Let GameManager.Start finish first, then use the game's own skip:
            // PlayableDirector.Stop raises stopped -> GameManager.OnEndDirector.
            entry.renderer.StartCoroutine(entry.SkipTour(director));
        }

        private IEnumerator SkipTour(Component director)
        {
            yield return null;
            if (renderer == null || director == null || !director.gameObject.activeInHierarchy) yield break;
            if (!LevelEntryPolicy.SkipTour(renderer.ShortenLevelEntry, plugin.SkipLevelTour.Value, renderer.IsFirstLevelScene)) yield break;
            if (Convert.ToInt32(stateProperty.GetValue(director, null)) != 1) yield break; // PlayState.Playing only.
            stopMethod.Invoke(director, null);
            Plugin.Trace("QVVR level tour skipped (independent VR); the level starts normally.");
        }

        private static float ResolveDuration(float original)
        {
            LevelEntryCompatibility entry = active;
            return entry == null ? original : LevelEntryPolicy.Duration(original, entry.renderer.ShortenLevelEntry, entry.plugin.LevelEntrySeconds.Value);
        }

        internal void Release()
        {
            if (active == this) active = null;
            if (harmony != null) harmony.UnpatchSelf();
            harmony = null; renderer = null; plugin = null;
            directorField = null; stopMethod = null; stateProperty = null;
        }
    }
}
