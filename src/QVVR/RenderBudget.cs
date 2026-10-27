using System;

namespace QVVR
{
    internal static class RenderBudget
    {
        internal const float DefaultUiScale = 1.75f;
        internal static float UiScale(float value)
        {
            return float.IsNaN(value) || float.IsInfinity(value) ? DefaultUiScale : Math.Max(1f, Math.Min(2f, value));
        }
        internal static float UpgradeUiScale(float value)
        {
            // Only the old shipped default migrates. The persisted revision
            // lets a later manual rollback to 1.5 remain unchanged on relaunch.
            return Math.Abs(value - 1.5f) < 0.00001f ? DefaultUiScale : value;
        }
        internal static float PresetScale(int preset)
        {
            return preset == 0 ? 0.85f : preset == 2 ? 1.15f : 1f;
        }

        internal static int MsaaSamples(int requested)
        {
            return requested >= 4 ? 4 : requested >= 2 ? 2 : 1;
        }
        internal static float SceneScale(float requested, bool exclusiveXr, float xrCap)
        {
            float scale = float.IsNaN(requested) || float.IsInfinity(requested) ? 1f : Math.Max(0.25f, Math.Min(1.5f, requested));
            if (!exclusiveXr || xrCap <= 0f) return scale;
            float cap = float.IsNaN(xrCap) || float.IsInfinity(xrCap) ? 1f : Math.Max(0.5f, Math.Min(1.5f, xrCap));
            return Math.Min(scale, cap);
        }
        // Settings menu: 0.05 steps of the effective eye scale, 0.5-1.5.
        internal static float NextRenderScale(float value, float direction)
        {
            if (float.IsNaN(value) || float.IsInfinity(value)) value = 1f;
            float next = (float)Math.Round((value + direction * 0.05f) * 20f) / 20f;
            return Math.Max(0.5f, Math.Min(1.5f, next));
        }
        // Settings menu: 1 (off) / 2 / 4 samples, clamped at both ends.
        internal static int NextMsaa(int value, float direction)
        {
            int current = MsaaSamples(value);
            if (direction > 0f) return current >= 2 ? 4 : 2;
            return current <= 2 ? 1 : 2;
        }
        internal static float NextXrCap(float value, float direction)
        {
            if (float.IsNaN(value) || float.IsInfinity(value)) value = 1f;
            if (value <= 0f) return direction > 0f ? 0.5f : 0f;
            float next = value + direction * 0.05f;
            return next < 0.49f ? 0f : Math.Max(0.5f, Math.Min(1.5f, next));
        }

        // A quarter interval early still counts: frame jitter must not drop a
        // capture whose rate matches the display (72 Hz menus), while a 36 Hz
        // HUD on 72 Hz frames still skips every other frame.
        internal static bool CaptureDue(float now, float deadline, int rate)
        {
            return now >= deadline - 0.25f / Math.Max(1, rate);
        }

        internal static float NextCapture(float now, float previousDeadline, int rate)
        {
            float interval = 1f / Math.Max(1, rate);
            float next = previousDeadline + interval;
            return next > now ? next : now + interval;
        }
    }
}
