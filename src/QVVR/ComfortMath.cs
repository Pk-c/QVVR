using System;

namespace QVVR
{
    internal static class ComfortMath
    {
        internal static bool GripPressed(ulong buttons, float axisX, float axisY)
        {
            // Frame's installed legacy binding maps grip click to button2;
            // analogue fallback accepts either axis2 component across runtimes.
            return (buttons & (1UL << 2)) != 0 || axisX >= 0.55f || axisY >= 0.55f;
        }

        internal static float ClampPitch(float degrees)
        {
            return float.IsNaN(degrees) ? 0f : Math.Max(-60f, Math.Min(60f, degrees));
        }

        internal static float FollowWeight(float deltaSeconds, float lagSeconds)
        {
            if (lagSeconds <= 0f) return 1f;
            return (float)(1.0 - Math.Exp(-Math.Max(0f, deltaSeconds) / lagSeconds));
        }

        internal static bool BothSticksPressed(ulong leftButtons, ulong rightButtons)
        {
            const ulong stick = 1UL << 32;
            return (leftButtons & stick) != 0 && (rightButtons & stick) != 0;
        }
    }
}
