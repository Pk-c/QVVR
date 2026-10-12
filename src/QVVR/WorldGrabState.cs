using System;

namespace QVVR
{
    // Accept tracking-space meters; retain offsets in game-world coordinates.
    // Created once, no per-frame
    // objects, config events or disk writes. Tests do not require Unity/runtime.
    internal sealed class WorldGrabState
    {
        private float startX, startY, startZ, startSeparation, startScale;
        private float startOffsetX, startOffsetY, startOffsetZ;
        private float rotationX, rotationY, rotationZ, rotationW, translationScale;
        private bool zoomGesture;
        internal bool Active { get; private set; }
        internal bool HasCameraOverride { get; private set; }
        internal float CameraScale { get; private set; }
        internal float OffsetX { get; private set; }
        internal float OffsetY { get; private set; }
        internal float OffsetZ { get; private set; }

        internal void Update(bool held, bool valid, float x, float y, float z,
            float separation, float configuredScale,
            float qx = 0f, float qy = 0f, float qz = 0f, float qw = 1f,
            float unitsPerMeter = 1f, float translationGain = 1f, bool zoom = true)
        {
            if (!held || !valid || !Finite(x) || !Finite(y) || !Finite(z) ||
                (zoom && (!Finite(separation) || separation < 0.08f)))
            {
                Stop();
                return;
            }
            if (Active && zoomGesture != zoom) Stop();
            if (!Active)
            {
                float lengthSquared = qx * qx + qy * qy + qz * qz + qw * qw;
                if (!Finite(lengthSquared) || lengthSquared < 0.000001f) return;
                float inverseLength = 1f / (float)Math.Sqrt(lengthSquared);
                rotationX = qx * inverseLength; rotationY = qy * inverseLength;
                rotationZ = qz * inverseLength; rotationW = qw * inverseLength;
                translationScale = SafeRange(unitsPerMeter, 1f, 0.25f, 10f) *
                    SafeRange(translationGain, zoom ? 4f : 20f, zoom ? 0.25f : 1f, zoom ? 20f : 100f);
                startX = x; startY = y; startZ = z;
                startOffsetX = OffsetX; startOffsetY = OffsetY; startOffsetZ = OffsetZ;
                startSeparation = separation;
                zoomGesture = zoom;
                startScale = HasCameraOverride ? CameraScale : ClampScale(configuredScale);
                CameraScale = startScale;
                if (zoom) HasCameraOverride = true;
                Active = true;
                return; // Grab starts at the CURRENT pose; never snap to origin.
            }
            // Moving the virtual camera opposite to the hands moves the viewed
            // world WITH the hands, without touching any game object transforms.
            // Freeze the game-camera basis at grab start. Later QV camera
            // rotations or scale changes must not rotate an existing placement.
            float dx = x - startX, dy = y - startY, dz = z - startZ;
            float tx = 2f * (rotationY * dz - rotationZ * dy);
            float ty = 2f * (rotationZ * dx - rotationX * dz);
            float tz = 2f * (rotationX * dy - rotationY * dx);
            OffsetX = startOffsetX - (dx + rotationW * tx + rotationY * tz - rotationZ * ty) * translationScale;
            OffsetY = startOffsetY - (dy + rotationW * ty + rotationZ * tx - rotationX * tz) * translationScale;
            OffsetZ = startOffsetZ - (dz + rotationW * tz + rotationX * ty - rotationY * tx) * translationScale;
            // Wider hands -> smaller original camera/pivot offset -> zoom in.
            if (zoom) CameraScale = ClampScale(startScale * startSeparation / separation);
        }

        internal float ResolveCameraScale(float configuredScale)
        {
            return HasCameraOverride ? CameraScale : ClampScale(configuredScale);
        }

        internal void Stop() { Active = false; }
        internal void ClearCameraOverride() { if (!Active) HasCameraOverride = false; }

        internal void ResetOffset()
        {
            Stop();
            OffsetX = OffsetY = OffsetZ = 0f;
        }

        private static bool Finite(float value) { return !float.IsNaN(value) && !float.IsInfinity(value); }
        private static float SafeRange(float value, float fallback, float min, float max)
        {
            return Finite(value) ? Math.Max(min, Math.Min(max, value)) : fallback;
        }
        private static float ClampScale(float scale)
        {
            return Finite(scale) ? Math.Max(0.15f, Math.Min(1.5f, scale)) : 0.4f;
        }
    }
}
