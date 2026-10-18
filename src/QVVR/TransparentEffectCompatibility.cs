using System.Collections.Generic;
using UnityEngine;

namespace QVVR
{
    internal sealed class TransparentEffectCompatibility
    {
        private struct Entry
        {
            internal Material Material;
            internal float Source, Destination;
            internal bool Changed;
        }
        private static readonly int SourceBlend = Shader.PropertyToID("_SrcBlend");
        private static readonly int DestinationBlend = Shader.PropertyToID("_DstBlend");
        private readonly List<Entry> entries = new List<Entry>(4);
        private int applied;
        internal int Count { get { return entries.Count; } }
        internal static bool Matches(string material, string shader)
        {
            return shader == "Custom/2SideShader" &&
                (material == "FairyMaterial" || material == "FairyMaterial (Instance)");
        }
        // Cold loaded-scene metadata cache. Verified material's PS samples texture
        // alpha but its dynamic _SrcBlend=One/_DstBlend=Zero makes it opaque.
        internal void Refresh()
        {
            Clear();
            var seen = new HashSet<Material>();
            Renderer[] renderers = Resources.FindObjectsOfTypeAll<Renderer>();
            for (int i = 0; i < renderers.Length; ++i)
            {
                Renderer renderer = renderers[i];
                if (renderer == null || !renderer.gameObject.scene.IsValid() || !renderer.gameObject.scene.isLoaded) continue;
                foreach (Material material in renderer.sharedMaterials)
                    if (material != null && material.shader != null && Matches(material.name, material.shader.name) &&
                        seen.Add(material)) entries.Add(new Entry { Material = material });
            }
        }
        internal void Prepare()
        {
            if (applied != 0) return;
            for (int i = 0; i < entries.Count; ++i)
            {
                Entry entry = entries[i];
                if (entry.Material == null) continue;
                entry.Source = entry.Material.GetFloat(SourceBlend);
                entry.Destination = entry.Material.GetFloat(DestinationBlend);
                entry.Changed = entry.Source == 1f && entry.Destination == 0f;
                entries[i] = entry; applied = i + 1;
                if (entry.Changed)
                {
                    entry.Material.SetFloat(SourceBlend, 5f); // SrcAlpha
                    entry.Material.SetFloat(DestinationBlend, 10f); // OneMinusSrcAlpha
                }
            }
        }
        internal void Restore()
        {
            for (int i = 0; i < applied; ++i)
            {
                Entry entry = entries[i];
                if (entry.Material == null || !entry.Changed) continue;
                entry.Material.SetFloat(SourceBlend, entry.Source);
                entry.Material.SetFloat(DestinationBlend, entry.Destination);
            }
            applied = 0;
        }
        internal void Clear() { Restore(); entries.Clear(); }
    }
}
