using System.Collections.Generic;
using UnityEngine;

namespace QVVR
{
    internal sealed class CutSurfaceRegistry
    {
        private readonly HashSet<Mesh> meshes = new HashSet<Mesh>();
        internal int Count { get { return meshes.Count; } }

        // Cold opt-in maintenance. Identify opaque static mesh buffers, not
        // water, particles, UI or skinned characters. Native references keep
        // buffers alive until the next scene/config refresh. Static batching
        // may share a buffer; actual replay still requires an opaque depth pass.
        internal void Refresh()
        {
            Clear();
            if (!NativeBridge.ShaderClipReady) return;
            MeshRenderer[] found = Resources.FindObjectsOfTypeAll<MeshRenderer>();
            for (int index = 0; index < found.Length; ++index)
            {
                MeshRenderer renderer = found[index];
                if (renderer == null || !renderer.gameObject.scene.IsValid() || !renderer.gameObject.scene.isLoaded) continue;
                MeshFilter filter = renderer.GetComponent<MeshFilter>();
                if (filter == null || filter.sharedMesh == null) continue;
                Material[] materials = renderer.sharedMaterials;
                bool solid = materials.Length > 0;
                for (int slot = 0; slot < materials.Length && solid; ++slot)
                {
                    Material material = materials[slot];
                    solid = material != null && material.shader != null && material.renderQueue <= 2500 &&
                        !LiquidDepthPolicy.UsesDepth(material.shader.name);
                }
                if (solid && meshes.Add(filter.sharedMesh))
                    NativeBridge.QVVR_RegisterCapMesh(filter.sharedMesh.GetNativeIndexBufferPtr());
            }
        }

        internal void Clear()
        {
            if (NativeBridge.ShaderClipReady) NativeBridge.QVVR_ClearCapMeshes();
            meshes.Clear();
        }
    }
}
