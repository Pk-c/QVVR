using System.Collections.Generic;
using UnityEngine;

namespace QVVR
{
    internal sealed class LiquidDepthPolicy
    {
        private readonly List<Renderer> renderers = new List<Renderer>(16);
        private struct WaterMaterial { internal Material Material; internal Color Foam; internal bool Changed; }
        private readonly List<WaterMaterial> waterMaterials = new List<WaterMaterial>(4);
        private static readonly int FoamColor = Shader.PropertyToID("_FoamColor");
        private int appliedWater;
        internal int Count { get { return renderers.Count; } }
        internal int WaterMaterialCount { get { return waterMaterials.Count; } }
        internal bool Visible(Camera camera, bool cylinder, Vector3 center, float radius, float halfHeight)
        {
            Matrix4x4 viewProjection = camera.projectionMatrix * camera.worldToCameraMatrix;
            for (int i = 0; i < renderers.Count; i++)
            {
                Renderer renderer = renderers[i];
                if (renderer == null || !renderer.enabled || !renderer.gameObject.activeInHierarchy ||
                    (camera.cullingMask & (1 << renderer.gameObject.layer)) == 0) continue;
                Bounds bounds = renderer.bounds;
                if ((!cylinder || DioramaBounds.Intersects(bounds, center, radius, halfHeight)) && DioramaBounds.InFrustum(bounds, viewProjection)) return true;
            }
            return false;
        }
        internal bool NeedsDepth
        {
            get
            {
                for (int index = 0; index < renderers.Count; ++index)
                {
                    Renderer renderer = renderers[index];
                    if (renderer != null && renderer.enabled && renderer.gameObject.activeInHierarchy) return true;
                }
                return false;
            }
        }

        // Scene maintenance only. Inspect shared assets without instantiating
        // materials; never search names/material arrays per rendered eye.
        internal void Refresh()
        {
            RestoreWater(); waterMaterials.Clear();
            renderers.Clear();
            var seenWater = new HashSet<Material>();
            Renderer[] found = Resources.FindObjectsOfTypeAll<Renderer>();
            for (int index = 0; index < found.Length; ++index)
            {
                Renderer renderer = found[index];
                if (renderer == null || !renderer.gameObject.scene.IsValid() || !renderer.gameObject.scene.isLoaded) continue;
                Material[] materials = renderer.sharedMaterials;
                bool depth = false;
                for (int slot = 0; slot < materials.Length; ++slot)
                {
                    Material material = materials[slot];
                    if (material == null || material.shader == null) continue;
                    string shader = material.shader.name;
                    if (UsesDepth(shader)) depth = true;
                    if (WaterFoamMaterial(material.name, shader) && material.HasProperty(FoamColor) && seenWater.Add(material))
                        waterMaterials.Add(new WaterMaterial { Material = material });
                }
                if (depth) renderers.Add(renderer);
            }
        }

        // Exact inspected blue-water material. Ink, fog and RainCore share the
        // shader family but must retain their own effect/color behavior.
        internal static bool WaterFoamMaterial(string material, string shader)
        {
            return shader == "Toony Colors Pro 2/Examples/Cat Demo/Water" &&
                (material == "WaterBlockMat" || material == "WaterBlockMat (Instance)");
        }
        internal void PrepareWater()
        {
            if (appliedWater != 0) return;
            for (int i = 0; i < waterMaterials.Count; i++)
            {
                WaterMaterial entry = waterMaterials[i];
                if (entry.Material == null) continue;
                entry.Foam = entry.Material.GetColor(FoamColor);
                entry.Changed = entry.Foam.a > 0f && !float.IsInfinity(entry.Foam.a);
                waterMaterials[i] = entry; appliedWater = i + 1;
                if (!entry.Changed) continue;
                Color foam = entry.Foam; foam.a = 0f;
                entry.Material.SetColor(FoamColor, foam);
            }
        }
        internal void RestoreWater()
        {
            for (int i = 0; i < appliedWater; i++)
            {
                WaterMaterial entry = waterMaterials[i];
                if (entry.Material != null && entry.Changed) entry.Material.SetColor(FoamColor, entry.Foam);
            }
            appliedWater = 0;
        }

        internal static bool UsesDepth(string shader)
        {
            return shader == "Toony Colors Pro 2/Examples/Cat Demo/Water" ||
                shader == "Toony Colors Pro 2/Examples/Water/Realistic" ||
                shader == "Toony Colors Pro 2/Examples/Water/Poison" ||
                shader == "StylizedWater/Particle/Desktop" || shader == "StylizedWater/Particle/Mobile";
        }
        internal void Clear() { RestoreWater(); waterMaterials.Clear(); renderers.Clear(); }
    }
}
