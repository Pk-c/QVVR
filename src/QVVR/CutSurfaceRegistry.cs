using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;

namespace QVVR
{
    internal sealed class CutSurfaceRegistry
    {
        private readonly HashSet<Mesh> meshes = new HashSet<Mesh>();
        private sealed class Entry
        {
            internal IntPtr Buffer;
            internal bool Solid, Bounded, FrameValid, HasFrameBounds;
            internal Bounds Bounds, FrameBounds;
        }
        private struct Contributor { internal MeshRenderer Renderer; internal MeshFilter Filter; internal Mesh Mesh; internal Entry Buffer; }
        private readonly Dictionary<IntPtr, Entry> buffers = new Dictionary<IntPtr, Entry>();
        private readonly List<Entry> entries = new List<Entry>(64);
        private readonly List<Contributor> contributors = new List<Contributor>(256);
        private readonly IntPtr[] skipBuffers = new IntPtr[256]; // Native fixed-slot capacity; excess buffers fail open.
        private GCHandle skipPin;
        internal int LastSkipped { get; private set; }
        internal bool NeedsRefresh { get; private set; }
        internal int Count { get { return meshes.Count; } }

        // Cold opt-in maintenance. Identify opaque static mesh buffers, not
        // water, particles, UI or skinned characters. Native references keep
        // buffers alive until the next scene/config refresh. Static batching
        // may share a buffer; actual replay still requires an opaque depth pass.
        internal void Refresh()
        {
            Clear();
            if (!NativeBridge.ShaderClipReady) return;
            skipPin = GCHandle.Alloc(skipBuffers, GCHandleType.Pinned);
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
                    // Opaque queue only (< AlphaTest 2450): the same-pass stencil
                    // count cannot run a material's alpha test, so cutout cards
                    // would otherwise cap their whole quad black.
                    solid = material != null && material.shader != null && material.renderQueue < 2450 &&
                        !LiquidDepthPolicy.UsesDepth(material.shader.name);
                }
                if (solid) meshes.Add(filter.sharedMesh);
                IntPtr buffer = filter.sharedMesh.GetNativeIndexBufferPtr();
                Bounds bounds = renderer.bounds;
                bool bounded = renderer.isPartOfStaticBatch && DioramaBounds.Valid(bounds);
                Entry entry;
                // Include even mixed-material contributors to a shared index
                // buffer; otherwise their opaque draws could use a false bound.
                if (buffers.TryGetValue(buffer, out entry))
                {
                    entry.Solid |= solid;
                    entry.Bounded &= bounded;
                    if (entry.Bounded) entry.Bounds.Encapsulate(bounds);
                }
                else
                {
                    entry = new Entry { Buffer = buffer, Solid = solid, Bounded = bounded, Bounds = bounds };
                    entries.Add(entry);
                }
                buffers[buffer] = entry;
                contributors.Add(new Contributor { Renderer = renderer, Filter = filter, Mesh = filter.sharedMesh, Buffer = entry });
            }
            foreach (KeyValuePair<IntPtr, Entry> item in buffers)
            {
                if (!item.Value.Solid) continue;
                if (item.Value.Bounded)
                {
                    NativeBridge.CapMeshBounds bounds = new NativeBridge.CapMeshBounds { Minimum = item.Value.Bounds.min, Maximum = item.Value.Bounds.max };
                    NativeBridge.QVVR_RegisterCapMeshBounds(item.Key, ref bounds);
                }
                else NativeBridge.QVVR_RegisterCapMesh(item.Key);
            }
        }

        // Bounds are sampled after game Update, once for BOTH eyes. No frozen
        // transform assumptions: ordinary (non-static-batched) QV meshes move.
        // Every contributor counts, including inactive and mixed-material ones.
        // Native copies this small pointer list into the exact queued pose slot.
        internal void PrepareFrame(int slot, Vector3 center, float radius, float halfHeight)
        {
            if (NeedsRefresh) { ClearFrame(slot); return; }
            for (int i = 0; i < entries.Count; i++) { entries[i].FrameValid = true; entries[i].HasFrameBounds = false; }
            for (int i = 0; i < contributors.Count; i++)
            {
                Contributor contributor = contributors[i]; Entry entry = contributor.Buffer;
                if (contributor.Renderer == null || contributor.Filter == null || contributor.Filter.sharedMesh != contributor.Mesh)
                {
                    // A replacement can become a contributor of ANOTHER cached
                    // buffer. Keep full replay until cold discovery rebuilds all
                    // unions; never query a GPU buffer pointer in this hot path.
                    NeedsRefresh = true; ClearFrame(slot); return;
                }
                if (!entry.FrameValid) continue;
                Bounds bounds = contributor.Renderer.bounds;
                if (!DioramaBounds.Valid(bounds)) { entry.FrameValid = false; continue; }
                if (entry.HasFrameBounds) entry.FrameBounds.Encapsulate(bounds);
                else { entry.FrameBounds = bounds; entry.HasFrameBounds = true; }
            }
            int count = 0;
            for (int i = 0; i < entries.Count && count < skipBuffers.Length; i++)
            {
                Entry entry = entries[i];
                if (entry.Solid && entry.Buffer != IntPtr.Zero && entry.FrameValid && entry.HasFrameBounds &&
                    !DioramaBounds.MayCut(entry.FrameBounds, center, radius, halfHeight)) skipBuffers[count++] = entry.Buffer;
            }
            LastSkipped = count;
            NativeBridge.QVVR_SetCapSkipMeshes(slot, skipPin.IsAllocated ? skipPin.AddrOfPinnedObject() : IntPtr.Zero, count);
        }
        internal void ClearFrame(int slot)
        {
            LastSkipped = 0;
            NativeBridge.QVVR_SetCapSkipMeshes(slot, IntPtr.Zero, 0);
        }

        internal void Clear()
        {
            if (NativeBridge.ShaderClipReady) NativeBridge.QVVR_ClearCapMeshes();
            meshes.Clear();
            buffers.Clear();
            entries.Clear(); contributors.Clear(); LastSkipped = 0; NeedsRefresh = false;
            if (skipPin.IsAllocated) skipPin.Free();
        }
    }
}
