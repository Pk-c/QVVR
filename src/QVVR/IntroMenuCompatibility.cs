using System;
using System.Reflection;
using HarmonyLib;
using UnityEngine;

namespace QVVR
{
    internal sealed class IntroMenuCompatibility
    {
        private sealed class Holder
        {
            internal Type Type;
            internal FieldInfo Machine, State;
            internal UnityEngine.Object Instance;
        }
        private static IntroMenuCompatibility active;
        private OpenVrRenderer renderer;
        private Harmony harmony;
        private Holder[] holders;
        private Type worldType, stageUiType;
        private FieldInfo worldAnchorField, stageDimField;
        private Transform hubAnchor;
        private Renderer stageDim;
        private bool dimHidden, dimWasEnabled;
        private FieldInfo cloudPanelField;

        internal void Initialize(OpenVrRenderer owner)
        {
            renderer = owner; active = this;
            try
            {
                harmony = new Harmony(Plugin.Guid + ".intro-menus");
                worldType = AccessTools.TypeByName("IntroWorldManager");
                stageUiType = AccessTools.TypeByName("IntroStageUIManager");
                worldAnchorField = worldType == null ? null : AccessTools.Field(worldType, "_worldTransform");
                stageDimField = stageUiType == null ? null : AccessTools.Field(stageUiType, "_dim");
                Type cloudType = AccessTools.TypeByName("Cloud");
                cloudPanelField = cloudType == null ? null : AccessTools.Field(cloudType, "Panel");
                MethodInfo fadeOut = cloudType == null ? null : AccessTools.DeclaredMethod(cloudType, "FadeOut");
                if (fadeOut != null && cloudPanelField != null)
                    harmony.Patch(fadeOut, prefix: new HarmonyMethod(typeof(IntroMenuCompatibility), "StageFadeStarted"));
                holders = new Holder[2];
                string[] names = { "IntroHolder", "NewIntroHolder" };
                for (int i = 0; i < names.Length; ++i)
                {
                    Type type = AccessTools.TypeByName(names[i]);
                    FieldInfo machine = type == null ? null : AccessTools.Field(type, "_stateMachine");
                    if (machine == null) continue;
                    holders[i] = new Holder { Type = type, Machine = machine,
                        State = AccessTools.Field(machine.FieldType, "currentState") };
                }
                foreach (string prefix in new[] { "IntroState.", "NewIntroState." })
                    foreach (string state in new[] { "Title", "World", "Costume", "Stage", "Exit" })
                    {
                        Type type = AccessTools.TypeByName(prefix + state + "State");
                        MethodInfo enter = type == null ? null : AccessTools.DeclaredMethod(type, "Enter");
                        if (enter != null) harmony.Patch(enter, postfix: new HarmonyMethod(typeof(IntroMenuCompatibility), state + "Entered"));
                    }
                Plugin.Log.LogInfo("QVVR intro menu compatibility: hub/costume/map state hooks; unknown states stay 2D.");
            }
            catch (Exception exception)
            {
                Release();
                Plugin.Log.LogWarning("QVVR intro menu compatibility unavailable; captured 2D fallback retained: " + exception);
            }
        }

        private void Publish(IntroPresentation state)
        {
            CacheVisuals();
            if (renderer != null) renderer.SetIntroPresentation(state);
        }
        private static void TitleEntered() { if (active != null) active.Publish(IntroPresentation.Title); }
        private static void WorldEntered() { if (active != null) active.Publish(IntroPresentation.World); }
        private static void CostumeEntered() { if (active != null) active.Publish(IntroPresentation.Costume); }
        private static void StageEntered() { if (active != null) active.Publish(IntroPresentation.Stage); }
        private static void ExitEntered() { if (active != null) active.Publish(IntroPresentation.Exit); }
        private static void StageFadeStarted(UnityEngine.Object __instance)
        {
            if (active == null || active.renderer == null || active.cloudPanelField == null) return;
            active.renderer.BeginStageFade(active.cloudPanelField.GetValue(__instance) as UnityEngine.UI.Image);
        }

        // Exact game-owned references, resolved on state events/maintenance only.
        // Never search by a broad UI name or modify the game's camera/tweens.
        private void CacheVisuals()
        {
            if (hubAnchor == null && worldAnchorField != null)
            {
                UnityEngine.Object manager = UnityEngine.Object.FindObjectOfType(worldType);
                if (manager != null) hubAnchor = worldAnchorField.GetValue(manager) as Transform;
            }
            if (stageDim == null && stageDimField != null)
            {
                UnityEngine.Object manager = UnityEngine.Object.FindObjectOfType(stageUiType);
                if (manager != null) stageDim = stageDimField.GetValue(manager) as Renderer;
            }
        }
        internal Vector3 HubPosition(Vector3 cameraPosition, Quaternion rotation, float distanceScale)
        {
            if (hubAnchor == null) return cameraPosition;
            Vector3 forward = rotation * Vector3.forward;
            float depth = Vector3.Dot(hubAnchor.position - cameraPosition, forward);
            return cameraPosition + forward * MenuScenePolicy.HubAdvance(depth, distanceScale);
        }
        // Only our manual stage eye/UI capture sees suppression. Do not remove
        // the object or disable its game-side fade tween/input/state machine.
        internal void HideStageDim()
        {
            if (dimHidden || stageDim == null) return;
            dimWasEnabled = stageDim.enabled;
            dimHidden = true;
            if (dimWasEnabled) stageDim.enabled = false;
        }
        internal void RestoreStageDim()
        {
            if (!dimHidden) return;
            if (stageDim != null) stageDim.enabled = dimWasEnabled;
            dimHidden = false;
        }

        // Cold maintenance only: catches injection AFTER Enter and initialization
        // ordering without reflecting/searching/allocating in the render loop.
        internal void Refresh()
        {
            if (holders == null || renderer == null) return;
            for (int i = 0; i < holders.Length; ++i)
            {
                Holder holder = holders[i];
                if (holder == null || holder.State == null) continue;
                if (holder.Instance == null) holder.Instance = UnityEngine.Object.FindObjectOfType(holder.Type);
                if (holder.Instance == null) continue;
                object machine = holder.Machine.GetValue(holder.Instance);
                object state = machine == null ? null : holder.State.GetValue(machine);
                if (state != null) { Publish(MenuScenePolicy.State(state.GetType().FullName)); return; }
            }
        }
        internal void Reset()
        {
            RestoreStageDim(); hubAnchor = null; stageDim = null;
            if (holders != null) for (int i = 0; i < holders.Length; ++i) if (holders[i] != null) holders[i].Instance = null;
        }
        internal void Release()
        {
            Reset();
            if (active == this) active = null;
            if (harmony != null) harmony.UnpatchSelf();
            harmony = null; holders = null; renderer = null;
            worldType = stageUiType = null; worldAnchorField = stageDimField = null;
            cloudPanelField = null;
        }
    }
}
