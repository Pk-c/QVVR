using System.Collections.Generic;
using UnityEngine;

namespace QVVR
{
    internal sealed class LiquidDepthPolicy
    {
        private readonly List<Renderer> renderers = new List<Renderer>(16);
        internal int Count { get { return renderers.Count; } }
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

        // Scene maintenance only. Inspect shared assets, never instantiate/change
        // a game material, and never search names/material arrays per rendered eye.
        internal void Refresh()
        {
            renderers.Clear();
            Renderer[] found = Resources.FindObjectsOfTypeAll<Renderer>();
            for (int index = 0; index < found.Length; ++index)
            {
                Renderer renderer = found[index];
                if (renderer == null || !renderer.gameObject.scene.IsValid() || !renderer.gameObject.scene.isLoaded) continue;
                Material[] materials = renderer.sharedMaterials;
                for (int slot = 0; slot < materials.Length; ++slot)
                {
                    Material material = materials[slot];
                    if (material != null && material.shader != null && UsesDepth(material.shader.name))
                    { renderers.Add(renderer); break; }
                }
            }
        }

        internal static bool UsesDepth(string shader)
        {
            return shader == "Toony Colors Pro 2/Examples/Cat Demo/Water" ||
                shader == "Toony Colors Pro 2/Examples/Water/Realistic" ||
                shader == "Toony Colors Pro 2/Examples/Water/Poison" ||
                shader == "StylizedWater/Particle/Desktop" || shader == "StylizedWater/Particle/Mobile";
        }
        internal void Clear() { renderers.Clear(); }
    }
}
