using System;
using System.Runtime.InteropServices;
using UnityEngine;
using Valve.VR;

namespace QVVR
{
    [StructLayout(LayoutKind.Sequential)]
    internal struct OpenXrPacing
    {
        internal ulong Intervals, LongGaps;
        internal double AverageMs, MaximumMs, P95UpperMs, PeriodMs, MaximumQueueAgeMs, MaximumCopySubmitMs;
    }
    // Blittable snapshots: no marshalled arrays, strings or managed bools.
    // Matrix34 is only a data format here; exclusive XR never calls OpenVR.
    [StructLayout(LayoutKind.Sequential)]
    internal struct OpenXrHand
    {
        internal HmdMatrix34_t Pose;
        internal uint Valid, Buttons;
        internal float StickX, StickY, Trigger, Grip;
    }
    [StructLayout(LayoutKind.Sequential)]
    internal struct OpenXrFov
    {
        internal float Left, Right, Up, Down;

        internal Matrix4x4 Projection(float near, float far)
        {
            float left = (float)Math.Tan(Left), right = (float)Math.Tan(Right);
            float up = (float)Math.Tan(Up), down = (float)Math.Tan(Down);
            // Unity camera projection uses RH view space and OpenGL depth.
            // GL.GetGPUProjectionMatrix handles D3D11 Y/depth/reversed-Z.
            Matrix4x4 result = new Matrix4x4();
            result.m00 = 2f / (right - left);
            result.m02 = (right + left) / (right - left);
            result.m11 = 2f / (up - down);
            result.m12 = (up + down) / (up - down);
            result.m22 = -(far + near) / (far - near);
            result.m23 = -2f * far * near / (far - near);
            result.m32 = -1f;
            return result;
        }
    }
    [StructLayout(LayoutKind.Sequential)]
    internal struct OpenXrFrame
    {
        internal HmdMatrix34_t Head, LeftEye, RightEye;
        internal OpenXrFov LeftFov, RightFov;
        internal OpenXrHand LeftHand, RightHand;
    }
    // Native qvvr::HudLayer: compositor quad pose/size in the XR base space.
    [StructLayout(LayoutKind.Sequential)]
    internal struct OpenXrHudLayer
    {
        internal float PositionX, PositionY, PositionZ, RotationX, RotationY, RotationZ, RotationW, Width, Height;
        internal uint Visible, Version;

        // Inverse of the eye mapping world = rigPosition + rigRotation *
        // (calibrationInverse * tracking) * unitsPerMeter, then Unity's
        // left-handed tracking space back to OpenXR right-handed (mirror Z).
        // Managed math only (no engine calls): callers pass the calibration
        // matrix and its rotation. Allocation-free, safe every frame.
        internal void SetFromWorld(Vector3 worldPosition, Quaternion worldRotation, Vector3 worldScale,
            Vector3 rigPosition, Quaternion rigRotation, float unitsPerMeter,
            Matrix4x4 calibration, Quaternion calibrationRotation, uint version)
        {
            Visible = 0;
            if (!(unitsPerMeter > 0f) || float.IsInfinity(unitsPerMeter)) return;
            Quaternion inverseRig = new Quaternion(-rigRotation.x, -rigRotation.y, -rigRotation.z, rigRotation.w);
            Vector3 local = inverseRig * (worldPosition - rigPosition) / unitsPerMeter;
            Vector3 tracking = calibration.MultiplyPoint3x4(local);
            Quaternion rotation = calibrationRotation * inverseRig * worldRotation;
            PositionX = tracking.x; PositionY = tracking.y; PositionZ = -tracking.z;
            RotationX = -rotation.x; RotationY = -rotation.y; RotationZ = rotation.z; RotationW = rotation.w;
            Width = Mathf.Abs(worldScale.x) / unitsPerMeter;
            Height = Mathf.Abs(worldScale.y) / unitsPerMeter;
            Version = version;
            Visible = Finite(PositionX) && Finite(PositionY) && Finite(PositionZ) && Finite(RotationW) &&
                Width > 0f && Height > 0f && Finite(Width) && Finite(Height) ? 1u : 0u;
        }

        private static bool Finite(float value) { return !float.IsNaN(value) && !float.IsInfinity(value); }
    }
}
