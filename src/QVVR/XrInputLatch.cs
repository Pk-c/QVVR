namespace QVVR
{
    // A queued XR frame is backpressure, not lost tracking/released grips.
    internal sealed class XrInputLatch
    {
        internal bool RenderReady { get; private set; }
        internal bool InputReady { get; private set; }
        internal bool Busy { get; private set; }
        internal void Update(int result)
        {
            RenderReady = result == 1;
            Busy = result == 2;
            if (!Busy) InputReady = RenderReady;
        }
    }
}
