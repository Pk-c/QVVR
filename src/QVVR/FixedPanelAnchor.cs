using UnityEngine;

namespace QVVR
{
    // Captured once in physical tracking space, not the movie camera's space.
    // Reset only on movie entry/exit, explicit recenter or a scene change.
    internal sealed class FixedPanelAnchor
    {
        internal bool Valid { get; private set; }
        internal Vector3 Position { get; private set; }
        internal Quaternion Rotation { get; private set; }

        internal void Latch(Vector3 position, Quaternion rotation)
        {
            if (Valid || !SpatialMath.Finite(position) || !SpatialMath.Finite(rotation)) return;
            Position = position; Rotation = rotation; Valid = true;
        }

        internal void Reset() { Valid = false; }
    }
}
