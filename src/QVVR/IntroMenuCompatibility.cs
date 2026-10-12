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

        internal void Initialize(OpenVrRenderer owner)
        {
            renderer = owner; active = this;
            try
            {
                harmony = new Harmony(Plugin.Guid + ".intro-menus");
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
                Plugin.Log.LogInfo("QVVR intro menu compatibility: costume/map state hooks; unknown states stay 2D.");
            }
            catch (Exception exception)
            {
                Release();
                Plugin.Log.LogWarning("QVVR intro menu compatibility unavailable; captured 2D fallback retained: " + exception);
            }
        }

        private void Publish(IntroPresentation state) { if (renderer != null) renderer.SetIntroPresentation(state); }
        private static void TitleEntered() { if (active != null) active.Publish(IntroPresentation.Title); }
        private static void WorldEntered() { if (active != null) active.Publish(IntroPresentation.World); }
        private static void CostumeEntered() { if (active != null) active.Publish(IntroPresentation.Costume); }
        private static void StageEntered() { if (active != null) active.Publish(IntroPresentation.Stage); }
        private static void ExitEntered() { if (active != null) active.Publish(IntroPresentation.Exit); }

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
        internal void Reset() { if (holders != null) for (int i = 0; i < holders.Length; ++i) if (holders[i] != null) holders[i].Instance = null; }
        internal void Release()
        {
            if (active == this) active = null;
            if (harmony != null) harmony.UnpatchSelf();
            harmony = null; holders = null; renderer = null;
        }
    }
}
