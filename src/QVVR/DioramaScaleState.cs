using System;

namespace QVVR
{
    // Physical size, not camera distance/FOV. Saved sparsely after release.
    internal sealed class DioramaScaleState
    {
        private float startSeparation, startScale;
        internal bool Active { get; private set; }
        internal bool HasOverride { get; private set; }
        internal float Scale { get; private set; }

        internal void Update(bool held, bool valid, float separation, float configured)
        {
            if (!held || !valid || float.IsNaN(separation) || float.IsInfinity(separation) || separation < 0.08f)
            { Stop(); return; }
            if (!Active)
            {
                startScale = Resolve(configured);
                startSeparation = separation;
                Scale = startScale;
                HasOverride = Active = true;
                return;
            }
            Scale = Clamp(startScale * separation / startSeparation);
        }

        internal float Resolve(float configured) { return HasOverride ? Scale : Clamp(configured); }
        internal void Stop() { Active = false; }
        internal void ClearOverride() { if (!Active) HasOverride = false; }
        internal static float Clamp(float scale)
        {
            return float.IsNaN(scale) || float.IsInfinity(scale) ? 1f : Math.Max(0.001f, Math.Min(10f, scale));
        }
    }
}
