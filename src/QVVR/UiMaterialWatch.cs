using System;
using System.Reflection;
using UnityEngine;
using UnityEngine.UI;

namespace QVVR
{
    // Cold binding only. Never invoke Graphic.material on an unknown subtype:
    // TMP_SubMeshUI.material creates instances and can throw before initialization.
    internal sealed class UiMaterialWatch
    {
        private readonly Func<Material> shared;
        private Material material;
        private Shader shader;
        private bool supported, scrolling;
        private static readonly int FaceX = Shader.PropertyToID("_FaceUVSpeedX"), FaceY = Shader.PropertyToID("_FaceUVSpeedY");
        private static readonly int OutlineX = Shader.PropertyToID("_OutlineUVSpeedX"), OutlineY = Shader.PropertyToID("_OutlineUVSpeedY");

        internal UiMaterialWatch(Graphic graphic)
        {
            Type type = graphic.GetType();
            if (type.Assembly.GetName().Name != "Unity.TextMeshPro") return;
            string property;
            if (type.FullName == "TMPro.TextMeshProUGUI" || type.FullName == "TMPro.TextMeshPro") property = "fontSharedMaterial";
            else if (type.FullName == "TMPro.TMP_SubMeshUI") property = "sharedMaterial";
            else return;
            PropertyInfo info = type.GetProperty(property, BindingFlags.Public | BindingFlags.Instance);
            MethodInfo getter = info == null ? null : info.GetGetMethod();
            if (getter == null || getter.ReturnType != typeof(Material) || getter.GetParameters().Length != 0) return;
            shared = (Func<Material>)Delegate.CreateDelegate(typeof(Func<Material>), graphic, getter);
            Refresh();
        }

        internal void Refresh()
        {
            if (shared == null) return;
            Material next = shared();
            Shader nextShader = next == null ? null : next.shader;
            if (next == material && nextShader == shader) return;
            material = next; shader = nextShader; supported = scrolling = false;
            if (material == null || shader == null) return;
            string name = shader.name; // Shader.name allocates; never read it in the hot path.
            scrolling = name == "TextMeshPro/Distance Field";
            supported = scrolling || StaticShader(name);
        }

        // TMP shaders without time-driven UV scrolling. QV's HUD text uses
        // Bitmap and its inline icons Sprite; text edits still dirty the cache.
        private static bool StaticShader(string name)
        {
            return name == "TextMeshPro/Mobile/Distance Field" || name == "TextMeshPro/Bitmap" ||
                name == "TextMeshPro/Mobile/Bitmap" || name == "TextMeshPro/Bitmap Custom Atlas" ||
                name == "TextMeshPro/Sprite";
        }

        internal bool Continuous()
        {
            if (shared == null) return true;
            Material current = shared();
            // No material draws nothing (e.g. an unused TMP submesh); assigning
            // one raises TMP's dirty-material callback, which invalidates capture.
            if (current == null) return material != null;
            if (!supported || current != material || material.shader != shader) return true;
            // Full TMP SDF has time-driven texture scrolling. Mobile SDF does not.
            // Unknown shaders/material replacements fail open until the next scan.
            return scrolling && (material.GetFloat(FaceX) != 0f || material.GetFloat(FaceY) != 0f ||
                material.GetFloat(OutlineX) != 0f || material.GetFloat(OutlineY) != 0f);
        }
    }
}
