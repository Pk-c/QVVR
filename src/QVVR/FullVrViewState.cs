using UnityEngine;

namespace QVVR
{
    // Normal-scale view, separate from the saved tracking-space diorama pose.
    // Position maps the tracking origin into game space; Rotation is yaw only.
    internal sealed class FullVrViewState
    {
        internal bool Valid { get; private set; }
        internal Vector3 Position { get; private set; }
        internal Quaternion Rotation { get; private set; } = Quaternion.identity;
        private Vector3 previousPlayer;

        internal void Place(Vector3 player, Quaternion sourceYaw, Vector3 head, Quaternion headYaw)
        {
            if (!SpatialMath.Finite(player) || !SpatialMath.Finite(head)) return;
            Rotation = sourceYaw * Quaternion.Inverse(headYaw);
            Vector3 view = player + Vector3.up * 1.6f - sourceYaw * Vector3.forward * 3f;
            Position = view - Rotation * head;
            previousPlayer = player;
            Valid = true;
        }

        internal void FollowPlayer(Vector3 player)
        {
            if (!Valid || !SpatialMath.Finite(player)) return;
            Position += player - previousPlayer;
            previousPlayer = player;
        }

        internal Vector3 EyePosition(Vector3 trackingEye) { return Position + Rotation * trackingEye; }

        internal void MoveStick(Vector2 stick, Vector3 head, Quaternion headYaw, float deltaTime,
            float turnSpeed, float moveSpeed)
        {
            if (!Valid || !SpatialMath.Finite(head) || !SpatialMath.Finite(stick.x) ||
                !SpatialMath.Finite(stick.y) || !SpatialMath.Finite(deltaTime) || deltaTime <= 0f) return;
            float dt = Mathf.Clamp(deltaTime, 0f, 0.05f);
            float yaw = Mathf.Clamp(stick.x, -1f, 1f) * dt *
                (SpatialMath.Finite(turnSpeed) ? Mathf.Clamp(turnSpeed, 0f, 180f) : 60f);
            float move = Mathf.Clamp(stick.y, -1f, 1f) * dt *
                (SpatialMath.Finite(moveSpeed) ? Mathf.Clamp(moveSpeed, 0f, 3f) : 0.6f);
            if (yaw != 0f)
            {
                // Turn around the virtual head, not the tracking-space origin
                // or the player. Room-scale walking must not create an orbit.
                Vector3 pivot = EyePosition(head);
                Rotation = Quaternion.AngleAxis(yaw, Vector3.up) * Rotation;
                Position = pivot - Rotation * head;
            }
            Position += Rotation * (headYaw * Vector3.forward) * move;
        }

        internal void Reset() { Valid = false; }

        internal static bool ClipWorld(bool gameplay, bool panelOnly, bool shaderReady, bool diorama)
        {
            // Alpha-blend composition must never force cylinder clipping on.
            return gameplay && !panelOnly && shaderReady && diorama;
        }
    }
}
