namespace QVVR
{
    // Modes: 0 idle, 1 right-hand translation, 2 two-hand size adjustment.
    // Immediate gestures; cached XR snapshots stay usable.
    internal sealed class GripGestureState
    {
        private bool armed;
        internal int Mode { get; private set; }
        internal bool Reserved { get { return Mode != 0; } }

        internal void Update(bool allowed, bool leftValid, bool rightValid,
            bool leftGrip, bool rightGrip, bool allowBoth, bool allowRight)
        {
            if (!allowed || !rightValid) { Reset(); return; }
            if (!rightGrip && (!leftValid || !leftGrip)) armed = true;
            if (!armed) return;
            if (allowBoth && leftValid && leftGrip && rightGrip)
            {
                Mode = 2; return;
            }
            if (!allowRight || !rightGrip || (leftValid && leftGrip))
            {
                Mode = 0; return;
            }
            Mode = 1;
        }

        internal void Reset() { armed = false; Mode = 0; }
    }
}
