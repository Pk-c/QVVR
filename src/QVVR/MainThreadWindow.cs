#if QVVR_DIAGNOSTICS
// Developer builds only: feeds the periodic main-thread timing log.
namespace QVVR
{
    // Per-log-window main-thread timings (wall-clock ms). Value type, updated in
    // place every frame: no allocation on the render path.
    internal struct MainThreadWindow
    {
        private double frameSum, gameSum, waitSum, renderSum;
        internal int Frames { get; private set; }
        private int renders;
        internal double FrameMax { get; private set; }
        internal double GameMax { get; private set; }
        internal double WaitMax { get; private set; }
        internal double RenderMax { get; private set; }
        internal double FrameAverage { get { return Frames > 0 ? frameSum / Frames : 0; } }
        internal double GameAverage { get { return Frames > 0 ? gameSum / Frames : 0; } }
        internal double WaitAverage { get { return Frames > 0 ? waitSum / Frames : 0; } }
        internal double RenderAverage { get { return renders > 0 ? renderSum / renders : 0; } }

        internal void AddGame(double gameMs, double waitMs, double frameMs)
        {
            if (!Valid(gameMs) || !Valid(waitMs) || !Valid(frameMs)) return;
            Frames++;
            gameSum += gameMs; waitSum += waitMs; frameSum += frameMs;
            if (gameMs > GameMax) GameMax = gameMs;
            if (waitMs > WaitMax) WaitMax = waitMs;
            if (frameMs > FrameMax) FrameMax = frameMs;
        }

        internal void AddRender(double renderMs)
        {
            if (!Valid(renderMs)) return;
            renders++;
            renderSum += renderMs;
            if (renderMs > RenderMax) RenderMax = renderMs;
        }

        internal void Reset() { this = new MainThreadWindow(); }

        private static bool Valid(double value) { return value >= 0 && value < 10000; }
    }
}
#endif
