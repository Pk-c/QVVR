using System.Collections.Generic;
using UnityEngine;

namespace QVVR
{
    internal sealed class CloudRendererFilter
    {
        private struct Entry
        {
            internal Renderer Renderer;
            internal bool Enabled;
        }
        private readonly List<Entry> renderers = new List<Entry>(4);
        private int appliedCount;
        internal int Count { get { return renderers.Count; } }

        // Cold scene/config maintenance ONLY. Includes inactive scene clouds,
        // excludes prefab assets; never scans names/materials per rendered eye.
        internal void Refresh()
        {
            Restore();
            renderers.Clear();
            Renderer[] found = Resources.FindObjectsOfTypeAll<Renderer>();
            for (int index = 0; index < found.Length; ++index)
            {
                Renderer renderer = found[index];
                if (renderer == null || !renderer.gameObject.scene.IsValid() || !renderer.gameObject.scene.isLoaded) continue;
                Material[] materials = renderer.sharedMaterials;
                bool cloud = materials.Length > 0;
                for (int materialIndex = 0; materialIndex < materials.Length && cloud; ++materialIndex)
                {
                    Material material = materials[materialIndex];
                    cloud = material != null && material.shader != null &&
                        CloudVisualRules.Hide(renderer.gameObject.name, material.name, material.shader.name);
                }
                // A mixed cloud/building renderer is deliberately left intact.
                if (cloud) renderers.Add(new Entry { Renderer = renderer });
            }
        }

        // Only the manual stereo render sees this suppression. Original states
        // are sampled live, never forced true on restore. No game object removal.
        internal void HideForStereo()
        {
            if (appliedCount != 0) return;
            for (int index = 0; index < renderers.Count; ++index)
            {
                Entry entry = renderers[index];
                if (entry.Renderer != null)
                {
                    entry.Enabled = entry.Renderer.enabled;
                    renderers[index] = entry;
                    appliedCount = index + 1;
                    if (entry.Enabled) entry.Renderer.enabled = false;
                }
            }
        }

        internal void Restore()
        {
            for (int index = 0; index < appliedCount; ++index)
            {
                Entry entry = renderers[index];
                if (entry.Renderer != null && entry.Renderer.enabled != entry.Enabled)
                    entry.Renderer.enabled = entry.Enabled;
            }
            appliedCount = 0;
        }

        internal void Clear()
        {
            Restore();
            renderers.Clear();
        }
    }
}
