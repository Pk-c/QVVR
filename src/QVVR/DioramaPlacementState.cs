using UnityEngine;

namespace QVVR
{
    // Entire state lives in physical tracking-space meters, never head space.
    internal sealed class DioramaPlacementState
    {
        internal bool Valid { get; private set; }
        internal bool Active { get; private set; }
        internal bool Dirty { get; private set; }
        internal Vector3 Position { get; private set; }
        internal Quaternion Rotation { get; private set; } = Quaternion.identity;
        internal float Scale { get; private set; } = 1f;
        private Vector3 startPosition, startMidpoint;
        private Quaternion startRotation, startHands, startControllers;
        private float startScale, startSeparation;

        internal void Place(Vector3 position, Quaternion rotation, float scale)
        {
            Position = position; Rotation = rotation; Scale = DioramaScaleState.Clamp(scale);
            Valid = Dirty = true; Active = false;
        }

        internal void Update(bool held, bool tracked, Vector3 left, Quaternion leftRotation,
            Vector3 right, Quaternion rightRotation)
        {
            if (!held || !tracked || !Valid) { Stop(); return; }
            // A quaternion mean is ambiguous for opposing wrist orientations.
            // Freeze/rebase through that singularity instead of flipping 180 deg.
            if (Mathf.Abs(Quaternion.Dot(leftRotation, rightRotation)) < 0.05f)
            { Stop(); return; }
            Quaternion hands;
            float separation;
            if (!SpatialMath.HandFrame(left, leftRotation, right, rightRotation,
                Active ? startHands : Quaternion.identity, out hands, out separation))
            { Stop(); return; }
            Vector3 midpoint = (left + right) * 0.5f;
            if (!Active)
            {
                startPosition = Position; startRotation = Rotation; startScale = Scale;
                startMidpoint = midpoint; startHands = hands; startSeparation = separation;
                startControllers = Quaternion.Lerp(leftRotation, rightRotation, 0.5f);
                Active = true;
                return; // Always rebase at the current hands; never snap.
            }
            Scale = DioramaScaleState.Clamp(startScale * separation / startSeparation);
            Quaternion delta = hands * Quaternion.Inverse(startHands);
            Quaternion controllerDelta = Quaternion.Lerp(leftRotation, rightRotation, 0.5f) * Quaternion.Inverse(startControllers);
            float handAngle = Quaternion.Angle(Quaternion.identity, delta);
            float wristAngle = Quaternion.Angle(Quaternion.identity, controllerDelta);
            // Full common wrist rotation works even with stationary hand centers.
            // Baseline motion still rotates if wrists stay still; when they agree
            // both estimates produce exactly the same rotation, not double it.
            if (handAngle + wristAngle > 0.001f)
                delta = Quaternion.Slerp(delta, controllerDelta, wristAngle / (handAngle + wristAngle));
            Position = midpoint + delta * (startPosition - startMidpoint) * (Scale / startScale);
            Rotation = delta * startRotation;
            Dirty = true;
        }

        internal void SetScale(float scale) { Scale = DioramaScaleState.Clamp(scale); Dirty = true; }
        internal void Tilt(float delta) { Rotation = Rotation * Quaternion.AngleAxis(-delta, Vector3.right); Dirty = true; }
        internal void Stop() { Active = false; }
        internal void Saved() { Dirty = false; }
        internal void Reset() { Valid = Active = false; }
    }

    internal static class SpatialMath
    {
        internal static bool Finite(float value) { return !float.IsNaN(value) && !float.IsInfinity(value); }
        internal static bool Finite(Vector3 value) { return Finite(value.x) && Finite(value.y) && Finite(value.z); }
        internal static bool Finite(Quaternion value)
        {
            return Finite(value.x) && Finite(value.y) && Finite(value.z) && Finite(value.w) &&
                value.x * value.x + value.y * value.y + value.z * value.z + value.w * value.w > 0.000001f;
        }

        internal static Quaternion Upright(Quaternion rotation, Quaternion fallback)
        {
            Vector3 forward = rotation * Vector3.forward;
            forward.y = 0f;
            return forward.sqrMagnitude > 0.0001f ? Quaternion.LookRotation(forward, Vector3.up) : fallback;
        }

        internal static bool HandFrame(Vector3 left, Quaternion leftRotation, Vector3 right,
            Quaternion rightRotation, Quaternion fallback, out Quaternion rotation, out float separation)
        {
            rotation = fallback; separation = 0f;
            if (!Finite(left) || !Finite(right) || !Finite(leftRotation) || !Finite(rightRotation)) return false;
            Vector3 x = right - left;
            separation = x.magnitude;
            if (!Finite(separation) || separation < 0.08f) return false;
            x /= separation;
            Vector3 up = leftRotation * Vector3.up + rightRotation * Vector3.up;
            up -= x * Vector3.Dot(up, x);
            if (up.sqrMagnitude < 0.0001f)
            {
                up = fallback * Vector3.up;
                up -= x * Vector3.Dot(up, x);
            }
            if (up.sqrMagnitude < 0.0001f) return false;
            rotation = Quaternion.LookRotation(Vector3.Cross(x, up), up);
            return Finite(rotation);
        }

        internal static Vector3 VisibleOffset(Vector3 requested, float extent)
        {
            float distance = Mathf.Max(1.5f, extent * 0.9f + 0.5f);
            if (!Finite(requested)) return new Vector3(0f, -0.35f, distance);
            float z = Mathf.Clamp(requested.z, distance, 6f);
            // Saved settings may come from behind/under the user while walking.
            // Reuse depth/height, but ensure the next level is in front and visible.
            return new Vector3(Mathf.Clamp(requested.x, -z * 0.35f, z * 0.35f),
                Mathf.Clamp(requested.y, -z * 0.35f, z * 0.25f), z);
        }

        internal static float EntryScale(float extent, float preferredMeters, float units)
        {
            float preferred = Finite(preferredMeters) ? Mathf.Clamp(preferredMeters, 0.05f, 4f) : 1.6f;
            return DioramaScaleState.Clamp(preferred * units / Mathf.Max(0.5f, extent));
        }

        internal static Vector2 Movement(Vector2 stick, Quaternion gameToTracking,
            Quaternion headYaw, Quaternion sourceYaw)
        {
            Vector3 direction = Quaternion.Inverse(gameToTracking) * (headYaw * new Vector3(stick.x, 0f, stick.y));
            direction.y = 0f;
            float length = direction.magnitude;
            if (length < 0.0001f) return Vector2.zero;
            direction *= stick.magnitude / length;
            // QV CharacterMove rotates joystickVector by its original mainCam yaw.
            direction = Quaternion.Inverse(sourceYaw) * direction;
            return new Vector2(direction.x, direction.z);
        }
    }
}
