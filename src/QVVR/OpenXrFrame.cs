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
}
