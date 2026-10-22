namespace QVVR
{
    internal enum ControllerLayout { FaceButtons, TrackpadWands }
    internal enum ControllerBinding
    {
        Default, None, LeftPrimary, LeftSecondary, RightPrimary, RightSecondary,
        LeftTrigger, RightTrigger, LeftStickClick, RightStickClick,
        BothTriggers, BothStickClicks, BothSecondaryButtons
    }
    internal enum ControllerStick { Left, Right, Either, None }
    internal struct ControllerBindings
    {
        internal ControllerLayout Layout;
        internal ControllerBinding Primary, Secondary, Pause, Swap, Dash, Camera, Load;
        internal ControllerBinding MenuConfirm, MenuBack, PreviousPage, NextPage, VrMenu;
        internal ControllerStick MovementStick, DioramaStick, MenuStick;
        internal float DioramaTurnSpeed, DioramaMoveSpeed, DioramaDeadZone;
        internal bool Exclusive;
    }
    internal static class ControllerButtonPolicy
    {
        internal const uint Confirm = 16, Back = 32, LeftShoulder = 64, RightShoulder = 128;
        internal const uint Primary = 256, Secondary = 512, Pause = 1024, Swap = 2048, Dash = 4096, Camera = 8192, Load = 16384;
        private const uint LP = 1, LS = 2, RP = 4, RS = 8, LT = 16, RT = 32, LC = 64, RC = 128;

        internal static bool Trigger(ulong buttons, float value)
        { return (buttons & (1UL << 33)) != 0 || (!float.IsNaN(value) && !float.IsInfinity(value) && value > 0.55f); }

        // Physical roles, not headset names. OpenXR and OpenVR compatibility
        // input share this policy. Grips/system buttons are never game bindings.
        internal static uint Physical(ulong left, float leftTrigger, ulong right, float rightTrigger)
        {
            uint result = 0;
            if ((left & (1UL << 7)) != 0) result |= LP;
            if ((left & (1UL << 1)) != 0) result |= LS;
            if ((right & (1UL << 7)) != 0) result |= RP;
            if ((right & (1UL << 1)) != 0) result |= RS;
            if (Trigger(left, leftTrigger)) result |= LT;
            if (Trigger(right, rightTrigger)) result |= RT;
            if ((left & (1UL << 32)) != 0) result |= LC;
            if ((right & (1UL << 32)) != 0) result |= RC;
            return result;
        }
        internal static uint Sources(ControllerBinding binding)
        {
            switch (binding)
            {
                case ControllerBinding.LeftPrimary: return LP;
                case ControllerBinding.LeftSecondary: return LS;
                case ControllerBinding.RightPrimary: return RP;
                case ControllerBinding.RightSecondary: return RS;
                case ControllerBinding.LeftTrigger: return LT;
                case ControllerBinding.RightTrigger: return RT;
                case ControllerBinding.LeftStickClick: return LC;
                case ControllerBinding.RightStickClick: return RC;
                case ControllerBinding.BothTriggers: return LT | RT;
                case ControllerBinding.BothStickClicks: return LC | RC;
                case ControllerBinding.BothSecondaryButtons: return LS | RS;
                default: return 0;
            }
        }
        internal static bool Pressed(uint physical, ControllerBinding binding)
        { uint mask = Sources(binding); return mask != 0 && (physical & mask) == mask; }
        internal static ControllerBinding Resolve(ControllerBinding binding, ControllerBinding fallback)
        { return binding == ControllerBinding.Default ? fallback : binding; }
        // Resolve on configuration changes, never parse strings while polling.
        internal static ControllerBindings Defaults(ControllerBindings b)
        {
            bool wands = b.Layout == ControllerLayout.TrackpadWands;
            b.Primary = Resolve(b.Primary, wands ? ControllerBinding.RightTrigger : ControllerBinding.RightPrimary);
            b.Secondary = Resolve(b.Secondary, ControllerBinding.RightSecondary);
            b.Pause = Resolve(b.Pause, ControllerBinding.LeftSecondary);
            b.Swap = Resolve(b.Swap, wands ? ControllerBinding.LeftStickClick : ControllerBinding.LeftPrimary);
            b.Dash = Resolve(b.Dash, wands ? ControllerBinding.LeftTrigger : ControllerBinding.RightTrigger);
            b.Camera = Resolve(b.Camera, wands ? ControllerBinding.None : ControllerBinding.LeftTrigger);
            b.Load = Resolve(b.Load, ControllerBinding.BothTriggers);
            b.MenuConfirm = Resolve(b.MenuConfirm, wands ? ControllerBinding.RightTrigger : ControllerBinding.RightPrimary);
            b.MenuBack = Resolve(b.MenuBack, ControllerBinding.RightSecondary);
            b.PreviousPage = Resolve(b.PreviousPage, wands ? ControllerBinding.None : ControllerBinding.LeftTrigger);
            b.NextPage = Resolve(b.NextPage, wands ? ControllerBinding.None : ControllerBinding.RightTrigger);
            b.VrMenu = Resolve(b.VrMenu, wands ? ControllerBinding.RightStickClick : ControllerBinding.BothStickClicks);
            return b;
        }
        private static bool Available(uint physical, ControllerBinding binding, uint reserved)
        { return (Sources(binding) & reserved) == 0 && Pressed(physical, binding); }
        internal static uint Buttons(uint physical, ControllerBindings b, bool gameplay)
        {
            uint result = 0, reserved = 0;
            // Chords own their constituents: Load must not leak a dash/camera/
            // primary action; a wand swap must not also open pause/back.
            if (gameplay && Pressed(physical, b.Load)) { result |= Load; reserved |= Sources(b.Load); }
            if (gameplay && Available(physical, b.Swap, reserved)) { result |= Swap; reserved |= Sources(b.Swap); }
            if (Available(physical, b.Pause, reserved)) result |= Pause;
            if (Available(physical, b.MenuConfirm, reserved)) result |= Confirm;
            if (Available(physical, b.MenuBack, reserved)) result |= Back;
            if (Available(physical, b.PreviousPage, reserved)) result |= LeftShoulder;
            if (Available(physical, b.NextPage, reserved)) result |= RightShoulder;
            if (gameplay)
            {
                if (Available(physical, b.Primary, reserved)) result |= Primary;
                if (Available(physical, b.Secondary, reserved)) result |= Secondary;
                if (Available(physical, b.Dash, reserved)) result |= Dash;
                if (Available(physical, b.Camera, reserved)) result |= Camera;
            }
            return result;
        }
        internal static uint ActionMask(string action, bool negative, bool menu)
        {
            switch (action)
            {
                case "Horizontal": return negative ? 2u : 1u;
                case "Vertical": return negative ? 8u : 4u;
                case "Right": return negative ? 0 : 1u;
                case "Left": return negative ? 0 : 2u;
                case "Up": return negative ? 0 : 4u;
                case "Down": return negative ? 0 : 8u;
                case "Confirm": return negative ? 0 : menu ? Confirm : Primary;
                case "Fire1": return negative ? 0 : menu ? Confirm : Primary;
                case "Fire2": return negative ? 0 : menu ? Back : Secondary;
                case "Pause": return negative ? 0 : Pause;
                case "Swap": return negative || menu ? 0 : Swap;
                case "Dash": return negative || menu ? 0 : Dash;
                case "Cam": return negative || menu ? 0 : Camera;
                case "Load": return negative || menu ? 0 : Load;
                // Gameplay uses semantic actions, not the additional desktop
                // gamepad-only L/R path (which would repeat Dash/Cam/Load).
                case "L": return negative || !menu ? 0 : LeftShoulder;
                case "R": return negative || !menu ? 0 : RightShoulder;
                default: return 0;
            }
        }
        internal static bool Known(string action)
        { return ActionMask(action, false, true) != 0 || ActionMask(action, false, false) != 0 || action == "ZL"; }
        internal static float Stick(ControllerStick source, float left, float right)
        {
            if (float.IsNaN(left) || float.IsInfinity(left)) left = 0;
            if (float.IsNaN(right) || float.IsInfinity(right)) right = 0;
            switch (source)
            {
                case ControllerStick.Left: return left;
                case ControllerStick.Right: return right;
                case ControllerStick.Either: return System.Math.Abs(left) >= System.Math.Abs(right) ? left : right;
                default: return 0f;
            }
        }
        internal static uint Directions(uint buttons, float x, float y)
        {
            uint result = buttons & ~15u;
            if (x > .5f) result |= 1;
            if (x < -.5f) result |= 2;
            if (y > .5f) result |= 4;
            if (y < -.5f) result |= 8;
            return result;
        }
    }
}
