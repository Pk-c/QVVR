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
        private float translationGain = 1f, rotationGain = 1f;

        internal void Place(Vector3 position, Quaternion rotation, float scale)
        {
            Position = position; Rotation = rotation; Scale = DioramaScaleState.Clamp(scale);
            Valid = Dirty = true; Active = false;
        }

        internal void Update(bool held, bool tracked, Vector3 left, Quaternion leftRotation,
            Vector3 right, Quaternion rightRotation, float moveSensitivity = 1f, float turnSensitivity = 1f)
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
                // Latch gains on regrab: changing a setting must not snap a held world.
                translationGain = SpatialMath.Gain(moveSensitivity);
                rotationGain = SpatialMath.Gain(turnSensitivity);
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
            delta = Quaternion.SlerpUnclamped(Quaternion.identity, delta, rotationGain);
            Position = startMidpoint + (midpoint - startMidpoint) * translationGain +
                delta * (startPosition - startMidpoint) * (Scale / startScale);
            Rotation = delta * startRotation;
            Dirty = true;
        }

        internal void SetScale(float scale) { Scale = DioramaScaleState.Clamp(scale); Dirty = true; }
        internal void MoveStick(Vector2 stick, Vector3 head, float deltaTime, float turnSpeed, float moveSpeed)
        {
            if (!Valid || Active || !SpatialMath.Finite(head) || !SpatialMath.Finite(stick.x) ||
                !SpatialMath.Finite(stick.y) || !SpatialMath.Finite(deltaTime) || deltaTime <= 0f) return;
            // Limit the displacement after stalls. Physical meters and world-up
            // yaw are independent of game scale, HMD tilt and game camera yaw.
            float dt = Mathf.Clamp(deltaTime, 0f, 0.05f);
            float yaw = Mathf.Clamp(stick.x, -1f, 1f) * dt *
                (SpatialMath.Finite(turnSpeed) ? Mathf.Clamp(turnSpeed, 0f, 180f) : 60f);
            float move = Mathf.Clamp(stick.y, -1f, 1f) * dt *
                (SpatialMath.Finite(moveSpeed) ? Mathf.Clamp(moveSpeed, 0f, 3f) : 0.6f);
            if (yaw == 0f && move == 0f) return;
            if (yaw != 0f) Rotation = Quaternion.AngleAxis(yaw, Vector3.up) * Rotation;
            Vector3 direction = Position - head;
            direction.y = 0f;
            float distance = direction.magnitude;
            if (move != 0f && distance > 0.0001f)
                // A previous two-hand grab can be outside the stick's limits.
                // Allow a gradual return, never snap it back onto a limit.
                Position += direction / distance * (Mathf.Clamp(distance - move,
                    distance < 0.25f ? distance : 0.25f, distance > 10f ? distance : 10f) - distance);
            Dirty = true;
        }
        internal void Tilt(float delta) { Rotation = Rotation * Quaternion.AngleAxis(-delta, Vector3.right); Dirty = true; }
        internal void Stop() { Active = false; }
        internal void Saved() { Dirty = false; }
        internal void Reset() { Valid = Active = false; }
    }

    internal static class SpatialMath
    {
        internal static Vector3 DefaultOffset { get { return new Vector3(0f, -0.45f, 1.2f); } }
        internal static bool LegacyDefaultOffset(Vector3 offset)
        {
            return Mathf.Approximately(offset.x, 0f) && Mathf.Approximately(offset.y, -0.35f) &&
                (Mathf.Approximately(offset.z, 1.6f) || Mathf.Approximately(offset.z, 2f));
        }
        internal static float Gain(float value) { return Finite(value) ? Mathf.Clamp(value, 0.25f, 3f) : 1f; }
        internal static float EntryGain(float value, float fallback)
        { return Mathf.Clamp(Finite(value) ? value : fallback, 0.25f, 1.5f); }
        internal static float EntryBase(float actual, float gain) { return actual / EntryGain(gain, 1f); }
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

        internal static Vector3 VisibleOffset(Vector3 requested, float radiusMeters, float heightMeters)
        {
            // Actual cylinder bounding sphere, not nearly a full DIAMETER of
            // clearance. Stay outside even after tilt, but allow a closer entry.
            float radius = Finite(radiusMeters) ? Mathf.Max(0f, radiusMeters) : 0.8f;
            float halfHeight = Finite(heightMeters) ? Mathf.Max(0f, heightMeters * 0.5f) : 0.4f;
            // A small diorama must not be pushed back to an arbitrary 1 m floor.
            // Keep 8 cm outside its bounding sphere (also safe after rotation).
            float distance = Mathf.Max(0.35f, Mathf.Sqrt(radius * radius + halfHeight * halfHeight) + 0.08f);
            if (!Finite(requested)) return new Vector3(0f, DefaultOffset.y, Mathf.Max(DefaultOffset.z, distance));
            float z = Mathf.Clamp(requested.z, distance, 6f);
            // Saved settings may come from behind/under the user while walking.
            // Reuse depth/height, but ensure the next level is in front and visible.
            return new Vector3(Mathf.Clamp(requested.x, -z * 0.35f, z * 0.35f),
                Mathf.Clamp(requested.y, -z * 0.5f, z * 0.25f), z);
        }

        internal static float EntryScale(float extent, float preferredMeters, float units)
        {
            float preferred = Finite(preferredMeters) ? Mathf.Clamp(preferredMeters, 0.05f, 4f) : 1.6f;
            return DioramaScaleState.Clamp(preferred * units / Mathf.Max(0.5f, extent));
        }

        internal static Vector3 EyePosition(Vector3 origin, Vector3 placement,
            Quaternion trackingToWorld, Vector3 trackingEye, float units)
        {
            // One direct physical-space difference, never head-relative or a
            // subtract/add of large calibrated rig terms at tiny world scales.
            return origin + trackingToWorld * (trackingEye - placement) * units;
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
