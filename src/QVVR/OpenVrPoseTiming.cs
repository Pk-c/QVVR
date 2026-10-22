using System;

namespace QVVR
{
    internal sealed class OpenVrPoseTiming
    {
        private float frameSeconds, photonsSeconds;

        // Runtime properties are sampled cold, not per eye/frame. Do not assume
        // a Frame-specific refresh rate when SteamVR streams to another headset.
        internal void Configure(float displayHz, float vsyncToPhotons)
        {
            frameSeconds = Finite(displayHz) && displayHz >= 20f && displayHz <= 500f ? 1f / displayHz : 0f;
            photonsSeconds = Finite(vsyncToPhotons) && vsyncToPhotons >= 0f && vsyncToPhotons <= 0.1f ? vsyncToPhotons : 0f;
        }

        internal float Prediction(bool hasVsync, float sinceVsync)
        {
            if (frameSeconds == 0f) return 0f; // Unknown cadence: current pose, not a guessed 72/90 Hz.
            float prediction = frameSeconds + photonsSeconds;
            // Valve: frame duration - elapsed since vsync + display delay.
            // Missing/stale/invalid vsync falls back to one known runtime frame.
            if (hasVsync && Finite(sinceVsync) && sinceVsync >= 0f && sinceVsync <= frameSeconds)
                prediction -= sinceVsync;
            return Math.Max(0f, Math.Min(0.1f, prediction));
        }

        internal void Reset() { frameSeconds = photonsSeconds = 0f; }
        private static bool Finite(float value) { return !float.IsNaN(value) && !float.IsInfinity(value); }
    }
}
