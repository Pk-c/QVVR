namespace QVVR
{
    internal static class ControllerButtonPolicy
    {
        internal const uint Confirm = 16, Back = 32, LeftShoulder = 64, RightShoulder = 128;

        internal static bool Trigger(ulong buttons, float value)
        { return (buttons & (1UL << 33)) != 0 || value > 0.55f; }

        internal static uint Buttons(ulong left, float leftTrigger, ulong right, float rightTrigger, bool gameShoulders)
        {
            uint result = (right & (1UL << 7)) != 0 ? Confirm : 0;
            if ((right & (1UL << 1)) != 0) result |= Back;
            if (gameShoulders)
            {
                // Use index triggers, not grips: two-hand diorama gestures keep
                // ownership of squeeze input. No jump/confirm leaks from LB+RB.
                if (Trigger(left, leftTrigger)) result |= LeftShoulder;
                if (Trigger(right, rightTrigger)) result |= RightShoulder;
            }
            else if (Trigger(right, rightTrigger)) result |= Confirm;
            return result;
        }
    }
}
