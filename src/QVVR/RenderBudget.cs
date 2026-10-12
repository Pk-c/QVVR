using System;

namespace QVVR
{
    internal static class RenderBudget
    {
        internal static float PresetScale(int preset)
        {
            return preset == 0 ? 0.85f : preset == 2 ? 1.15f : 1f;
        }

        internal static int MsaaSamples(int requested)
        {
            return requested >= 4 ? 4 : requested >= 2 ? 2 : 1;
        }

        internal static float NextCapture(float now, float previousDeadline, int rate)
        {
            float interval = 1f / Math.Max(1, rate);
            float next = previousDeadline + interval;
            return next > now ? next : now + interval;
        }
    }
}
