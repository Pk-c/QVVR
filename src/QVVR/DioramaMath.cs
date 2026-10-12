using System;

namespace QVVR
{
    internal static class DioramaMath
    {
        internal const float DefaultFeatherWidth = 1f;
        internal static float ScaleViewAxis(float center, float unscaledView, float scale)
        {
            return center + (unscaledView - center) / DioramaScaleState.Clamp(scale);
        }
        internal static float ViewUnits(float units, float scale)
        {
            float safeUnits = float.IsNaN(units) || float.IsInfinity(units) ? 1f : Math.Max(0.25f, Math.Min(10f, units));
            return safeUnits / DioramaScaleState.Clamp(scale);
        }
        internal static float UpgradeFeatherWidth(float requested)
        {
            // Upgrade the old shipped width once, never zero or custom widths.
            return Math.Abs(requested - 0.35f) < 0.00001f ? DefaultFeatherWidth : requested;
        }
        internal static bool GreenBackground(int choice) { return choice == 1; }
        internal static float FeatherWidth(float requested, float radius, float height)
        {
            if (float.IsNaN(requested) || float.IsInfinity(requested)) requested = DefaultFeatherWidth;
            return Math.Max(0f, Math.Min(requested, Math.Min(radius * 0.5f, height * 0.25f)));
        }
        internal static float HudScale(float requested)
        {
            return float.IsNaN(requested) || float.IsInfinity(requested) ? 2f : Math.Max(0.5f, Math.Min(3f, requested));
        }
        // Only the original game-camera displacement moves the clip volume.
        // HMD, zoom and grip offsets belong to the viewing rig, not this anchor.
        internal static float FollowCameraAxis(float anchor, float camera, float cameraAtEntry)
        {
            return anchor + (camera - cameraAtEntry);
        }
    }
}
