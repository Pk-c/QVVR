using System;
using System.Collections.Generic;
using System.Reflection;
using HarmonyLib;
using UnityEngine;

namespace QVVR
{
    internal sealed class QvCameraCompatibility
    {
        private static OpenVrRenderer active;
        private Harmony harmony;

        internal void Initialize(OpenVrRenderer renderer)
        {
            try
            {
                Type listener = AccessTools.TypeByName("CameraListener");
                MethodInfo update = listener == null ? null : AccessTools.Method(listener, "Update", Type.EmptyTypes);
                if (update == null) return;
                harmony = new Harmony(Plugin.Guid + ".camera-listener");
                harmony.Patch(update, transpiler: new HarmonyMethod(typeof(QvCameraCompatibility), "ReplaceMainCamera"));
                active = renderer;
                Plugin.Log.LogInfo("QVVR CameraListener compatibility active: disabled source camera remains accessible.");
            }
            catch (Exception exception)
            {
                Release(renderer);
                Plugin.Log.LogWarning("QVVR CameraListener compatibility unavailable: " + exception);
            }
        }

        // Rewrite only CameraListener, never hair simulation or Unity's getter.
        // Iterator/reflection allocations happen while patching, not rendering.
        private static IEnumerable<CodeInstruction> ReplaceMainCamera(IEnumerable<CodeInstruction> instructions)
        {
            MethodInfo getter = AccessTools.PropertyGetter(typeof(Camera), "main");
            MethodInfo replacement = AccessTools.Method(typeof(QvCameraCompatibility), "GetMainCamera");
            foreach (CodeInstruction instruction in instructions)
            {
                if (instruction.Calls(getter))
                    instruction.operand = replacement;
                yield return instruction;
            }
        }

        private static Camera GetMainCamera()
        {
            Camera camera = Camera.main;
            return camera != null || active == null ? camera : active.SourceCamera;
        }

        internal void Release(OpenVrRenderer renderer)
        {
            if (active == renderer) active = null;
            if (harmony != null)
            {
                harmony.UnpatchSelf();
                harmony = null;
            }
        }
    }
}
