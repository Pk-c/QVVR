using System.Collections.Generic;
using UnityEngine;

namespace QVVR
{
    // Conservative tests in ORIGINAL game coordinates. Rotation/scale of the
    // physical diorama changes the eye transform, not this vertical cylinder.
    internal static class DioramaBounds
    {
        internal static bool Finite(float value) { return !float.IsNaN(value) && !float.IsInfinity(value); }
        internal static bool Valid(Bounds bounds)
        {
            Vector3 c = bounds.center, e = bounds.extents;
            return Finite(c.x) && Finite(c.y) && Finite(c.z) && Finite(e.x) && Finite(e.y) && Finite(e.z) && e.x >= 0f && e.y >= 0f && e.z >= 0f;
        }
        internal static bool Intersects(Bounds bounds, Vector3 center, float radius, float halfHeight)
        {
            if (!Valid(bounds) || !Finite(center.x) || !Finite(center.y) || !Finite(center.z) ||
                !Finite(radius) || !Finite(halfHeight) || radius <= 0f || halfHeight <= 0f) return true;
            Vector3 d = bounds.center - center, e = bounds.extents;
            float x = Mathf.Max(0f, Mathf.Abs(d.x) - e.x), z = Mathf.Max(0f, Mathf.Abs(d.z) - e.z);
            // A small guard band prevents numerical edge popping.
            return Mathf.Abs(d.y) <= halfHeight + e.y + 0.05f && x * x + z * z <= (radius + 0.05f) * (radius + 0.05f);
        }
        internal static bool InFrustum(Bounds bounds, Matrix4x4 viewProjection)
        {
            if (!Valid(bounds)) return true;
            Vector3 c = bounds.center, e = bounds.extents;
            for (int axis = 0; axis < 3; axis++)
            {
                for (int side = -1; side <= 1; side += 2)
                {
                    float x = viewProjection[3, 0] + side * viewProjection[axis, 0];
                    float y = viewProjection[3, 1] + side * viewProjection[axis, 1];
                    float z = viewProjection[3, 2] + side * viewProjection[axis, 2];
                    float w = viewProjection[3, 3] + side * viewProjection[axis, 3];
                    float distance = x * c.x + y * c.y + z * c.z + w;
                    float extent = Mathf.Abs(x) * e.x + Mathf.Abs(y) * e.y + Mathf.Abs(z) * e.z;
                    if (Finite(distance) && Finite(extent) && distance + extent < -0.05f * (Mathf.Abs(x) + Mathf.Abs(y) + Mathf.Abs(z))) return false;
                }
            }
            return true;
        }
    }

    internal sealed class DioramaVisibility
    {
        private readonly List<MeshRenderer> renderers = new List<MeshRenderer>(128);
        private readonly List<MeshRenderer> hidden = new List<MeshRenderer>(128);
        internal int LastHidden { get; private set; }
        internal int Count { get { return renderers.Count; } }
        // Cold discovery includes inactive scene meshes, never prefab assets,
        // characters/particles (potentially late-changing bounds), or mod UI.
        internal void Refresh(int mask)
        {
            Clear();
            MeshRenderer[] found = Resources.FindObjectsOfTypeAll<MeshRenderer>();
            for (int i = 0; i < found.Length; i++)
            {
                MeshRenderer renderer = found[i];
                if (renderer == null || !renderer.gameObject.scene.IsValid() || !renderer.gameObject.scene.isLoaded ||
                    (mask & (1 << renderer.gameObject.layer)) == 0) continue;
                renderers.Add(renderer);
            }
            if (hidden.Capacity < renderers.Count) hidden.Capacity = renderers.Count;
        }
        internal void HideOutside(Vector3 center, float radius, float halfHeight)
        {
            if (hidden.Count != 0) return;
            for (int i = 0; i < renderers.Count; i++)
            {
                MeshRenderer renderer = renderers[i];
                if (renderer == null || !renderer.enabled || !renderer.gameObject.activeInHierarchy) continue;
                if (DioramaBounds.Intersects(renderer.bounds, center, radius, halfHeight)) continue;
                renderer.enabled = false;
                hidden.Add(renderer);
            }
            LastHidden = hidden.Count;
        }
        internal void Restore()
        {
            for (int i = 0; i < hidden.Count; i++) if (hidden[i] != null) hidden[i].enabled = true;
            hidden.Clear();
        }
        internal void Clear() { Restore(); renderers.Clear(); LastHidden = 0; }
    }
}
