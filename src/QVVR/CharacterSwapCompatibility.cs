using System;
using HarmonyLib;

namespace QVVR
{
    // GameManager's swap methods replace newPlayerClass with the other character.
    // Observe them so the diorama/full-VR anchor follows on the same frame;
    // cold maintenance still re-reads the field if a callback is missed.
    internal sealed class CharacterSwapCompatibility
    {
        private static readonly string[] SwapMethods = { "CharacterSwap", "CharacterGoalSwap", "CharacterSwapForDialog" };
        private static CharacterSwapCompatibility active;
        private OpenVrRenderer renderer;
        private Harmony harmony;

        internal void Initialize(OpenVrRenderer owner)
        {
            renderer = owner; active = this;
            try
            {
                Type managerType = AccessTools.TypeByName("GameManager");
                if (managerType == null) throw new MissingMemberException("GameManager unavailable.");
                harmony = new Harmony(Plugin.Guid + ".character-swap");
                int patched = 0;
                foreach (System.Reflection.MethodInfo method in AccessTools.GetDeclaredMethods(managerType))
                {
                    if (Array.IndexOf(SwapMethods, method.Name) < 0 || method.IsAbstract) continue;
                    harmony.Patch(method, postfix: new HarmonyMethod(typeof(CharacterSwapCompatibility), "Swapped"));
                    patched++;
                }
                if (patched == 0) throw new MissingMemberException("GameManager character swap methods unavailable.");
                Plugin.Trace("QVVR character swap compatibility active: " + patched + " swap methods observed.");
            }
            catch (Exception error)
            {
                Release(); renderer = owner; active = this;
                Plugin.Log.LogWarning("QVVR character swap hook unavailable; maintenance refresh retained: " + error.Message);
            }
        }

        private static void Swapped()
        {
            if (active != null && active.renderer != null) active.renderer.RefreshGameplayTarget();
        }

        internal void Release()
        {
            if (active == this) active = null;
            if (harmony != null) harmony.UnpatchSelf();
            harmony = null; renderer = null;
        }
    }
}
