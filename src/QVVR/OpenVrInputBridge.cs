using System;
using System.Reflection;
using System.Runtime.InteropServices;
using HarmonyLib;
using UnityEngine;
using Valve.VR;

namespace QVVR
{
    // Poll before QV's Update methods. Patches add VR input to the existing
    // Rewired results; keyboard/gamepad input and original game files survive.
    [DefaultExecutionOrder(-10000)]
    internal sealed class OpenVrInputBridge : MonoBehaviour
    {
        private const uint Right = 1, Left = 2, Up = 4, Down = 8, Confirm = 16, Back = 32;
        private static OpenVrInputBridge active;
        private static readonly uint ControllerStateSize = (uint)Marshal.SizeOf(typeof(VRControllerState_t));
        private CVRSystem system;
        private CVRCompositor compositor;
        private Plugin plugin;
        private Harmony harmony;
        private uint held, previous;
        private float horizontal, vertical, cameraHorizontal, cameraVertical;
        private float previousHorizontal, previousVertical;
        private bool hadFocus;
        private bool loggedControllers;
        private bool loggedInput;
        private VrSettingsMenu settingsMenu;
        private bool previousStickChord;
        private bool suppressUntilNeutral;
        private readonly GripGestureState gripGesture = new GripGestureState();
        private OpenVrRenderer renderer;
        private static int movementQueryDepth;
        private static bool movementUsesCameraYaw = true;
        private struct MovementScope { internal int Depth; internal bool CameraYaw; }

        internal bool BothGripsHeld { get { return gripGesture.Mode == 2; } }
        internal bool RightGripGrabHeld { get { return gripGesture.Mode == 1; } }
        internal uint LeftDevice { get; private set; }
        internal uint RightDevice { get; private set; }

        private bool ConsumeGameInput { get { return suppressUntilNeutral || (settingsMenu != null && settingsMenu.Visible) ||
            (gripGesture.Reserved && renderer != null && renderer.CanGrabWorld); } }

        internal void Initialize(Plugin owner, CVRSystem vrSystem, CVRCompositor vrCompositor, VrSettingsMenu menu, OpenVrRenderer vrRenderer)
        {
            plugin = owner;
            renderer = vrRenderer;
            settingsMenu = menu;
            system = vrSystem;
            compositor = vrCompositor;
            try
            {
                Type player = AccessTools.TypeByName("Rewired.Player");
                if (player == null)
                    throw new InvalidOperationException("QV's Rewired.Player type was not found.");
                harmony = new Harmony(Plugin.Guid + ".input");
                Patch(player, "GetAxis", "Axis", typeof(string));
                Patch(player, "GetAxisRaw", "Axis", typeof(string));
                Patch(player, "GetButton", "Button", typeof(string));
                Patch(player, "GetButtonDown", "ButtonDown", typeof(string));
                Patch(player, "GetButtonUp", "ButtonUp", typeof(string));
                Patch(player, "GetNegativeButton", "NegativeButton", typeof(string));
                Patch(player, "GetNegativeButtonDown", "NegativeButtonDown", typeof(string));
                Patch(player, "GetNegativeButtonUp", "NegativeButtonUp", typeof(string));
                Patch(player, "GetAnyButton", "AnyButton");
                Patch(player, "GetAnyButtonDown", "AnyButtonDown");
                Patch(player, "GetAnyButtonUp", "AnyButtonUp");
                Type mover = AccessTools.TypeByName("CharacterMove");
                if (mover != null)
                {
                    foreach (Type nested in mover.GetNestedTypes(BindingFlags.NonPublic | BindingFlags.Public))
                    {
                        if (!nested.Name.StartsWith("<MoveJoystick>")) continue;
                        MethodInfo next = AccessTools.Method(nested, "MoveNext");
                        if (next != null) harmony.Patch(next,
                            prefix: new HarmonyMethod(typeof(OpenVrInputBridge), "BeginMovementQuery"),
                            finalizer: new HarmonyMethod(typeof(OpenVrInputBridge), "EndMovementQuery"));
                    }
                    MethodInfo jump = AccessTools.Method(mover, "CharacterJump");
                    if (jump != null) harmony.Patch(jump,
                        prefix: new HarmonyMethod(typeof(OpenVrInputBridge), "BeginJumpQuery"),
                        finalizer: new HarmonyMethod(typeof(OpenVrInputBridge), "EndMovementQuery"));
                }
                active = this;
                Plugin.Log.LogInfo("QVVR Rewired input bridge active: stick navigation, A/right trigger confirm, B back.");
            }
            catch (Exception exception)
            {
                Release();
                Plugin.Log.LogError("QVVR controller bridge unavailable; original input preserved: " + exception);
            }
        }

        private void Patch(Type player, string name, string postfix, params Type[] arguments)
        {
            MethodInfo target = AccessTools.Method(player, name, arguments);
            if (target == null)
                throw new MissingMethodException(player.FullName, name);
            harmony.Patch(target, postfix: new HarmonyMethod(typeof(OpenVrInputBridge), postfix));
        }

        private void Update()
        {
            bool wasGripping = gripGesture.Reserved;
            LeftDevice = RightDevice = OpenVR.k_unTrackedDeviceIndexInvalid;
            previous = held;
            previousHorizontal = horizontal; previousVertical = vertical;
            held = 0;
            horizontal = vertical = cameraHorizontal = cameraVertical = 0f;
            if (active != this || !plugin.VrEnabled.Value || !plugin.VrControllerInput.Value)
            {
                gripGesture.Reset();
                return;
            }
            if (renderer != null && renderer.UsesOpenXr) renderer.PrepareTracking();
            bool focus = renderer != null && renderer.HasInputFocus;
            if (!focus)
            {
                hadFocus = false;
                gripGesture.Reset();
                previousStickChord = false;
                previous = 0;
                return;
            }

            bool xr = renderer != null && renderer.UsesOpenXr;
            uint left = xr ? 1u : system.GetTrackedDeviceIndexForControllerRole(ETrackedControllerRole.LeftHand);
            uint right = xr ? 2u : system.GetTrackedDeviceIndexForControllerRole(ETrackedControllerRole.RightHand);
            VRControllerState_t leftState = default(VRControllerState_t);
            VRControllerState_t rightState = default(VRControllerState_t);
            bool hasLeft = xr ? renderer.GetXrControllerState(true, ref leftState) :
                left != OpenVR.k_unTrackedDeviceIndexInvalid && system.GetControllerState(left, ref leftState, ControllerStateSize);
            bool hasRight = xr ? renderer.GetXrControllerState(false, ref rightState) :
                right != OpenVR.k_unTrackedDeviceIndexInvalid && system.GetControllerState(right, ref rightState, ControllerStateSize);
            LeftDevice = hasLeft ? left : OpenVR.k_unTrackedDeviceIndexInvalid;
            RightDevice = hasRight ? right : OpenVR.k_unTrackedDeviceIndexInvalid;
            bool leftGrip = hasLeft && ComfortMath.GripPressed(leftState.ulButtonPressed, leftState.rAxis2.x, leftState.rAxis2.y);
            bool rightGrip = hasRight && ComfortMath.GripPressed(rightState.ulButtonPressed, rightState.rAxis2.x, rightState.rAxis2.y);
            gripGesture.Update(hadFocus && renderer != null && renderer.CanGrabWorld &&
                (settingsMenu == null || !settingsMenu.Visible),
                hasLeft && (!xr || renderer.IsControllerTracked(left)),
                hasRight && (!xr || renderer.IsControllerTracked(right)),
                leftGrip, rightGrip, plugin.TwoGripWorldGrab.Value, false);
            if (wasGripping && !gripGesture.Reserved && renderer != null && renderer.CanGrabWorld)
                suppressUntilNeutral = true;
            if ((hasLeft || hasRight) && !loggedControllers)
            {
                loggedControllers = true;
                Plugin.Log.LogInfo("QVVR " + (xr ? "exclusive OpenXR" : "OpenVR") + " controller states received: left=" + hasLeft + ", right=" + hasRight);
            }

            // Frame's official legacy binding uses axis0 for both thumbsticks,
            // button7 for A, button1 for B and axis1/button33 for the trigger.
            horizontal = DeadZone(Stronger(leftState.rAxis0.x, rightState.rAxis0.x));
            vertical = DeadZone(Stronger(leftState.rAxis0.y, rightState.rAxis0.y));
            cameraHorizontal = DeadZone(rightState.rAxis0.x);
            cameraVertical = DeadZone(rightState.rAxis0.y);
            if (horizontal > 0.5f) held |= Right;
            if (horizontal < -0.5f) held |= Left;
            if (vertical > 0.5f) held |= Up;
            if (vertical < -0.5f) held |= Down;
            if ((rightState.ulButtonPressed & ((1UL << 7) | (1UL << 33))) != 0 || rightState.rAxis1.x > 0.55f)
                held |= Confirm;
            if ((rightState.ulButtonPressed & (1UL << 1)) != 0)
                held |= Back;

            // The A press used to dismiss Steam's overlay must not also choose
            // a game menu item when scene focus returns.
            bool stickChord = ComfortMath.BothSticksPressed(leftState.ulButtonPressed, rightState.ulButtonPressed);
            bool focusWasAvailable = hadFocus;
            if (!hadFocus)
                previous = held;
            hadFocus = true;
            bool menuWasVisible = settingsMenu != null && settingsMenu.Visible;
            if (focusWasAvailable && stickChord && !previousStickChord && settingsMenu != null)
            {
                settingsMenu.Toggle();
                suppressUntilNeutral = true;
            }
            previousStickChord = stickChord;
            if (suppressUntilNeutral && held == 0 && horizontal == 0f && vertical == 0f &&
                ((leftState.ulButtonPressed | rightState.ulButtonPressed) & (1UL << 32)) == 0)
                suppressUntilNeutral = false;
            if (settingsMenu != null && settingsMenu.Visible && !suppressUntilNeutral)
                settingsMenu.HandleInput(horizontal, vertical, (State(1) & Confirm) != 0, (State(1) & Back) != 0);
            if (menuWasVisible && !settingsMenu.Visible)
            {
                RequireGripRelease();
                suppressUntilNeutral = true;
            }
            if (held != 0 && !loggedInput)
            {
                loggedInput = true;
                Plugin.Log.LogInfo("QVVR first controller navigation/button input received.");
            }
        }

        private static float Stronger(float first, float second)
        {
            return Mathf.Abs(first) >= Mathf.Abs(second) ? first : second;
        }

        private static float DeadZone(float value)
        {
            return Mathf.Abs(value) < 0.25f ? 0f : value;
        }

        private static uint Mask(string action, bool negative)
        {
            switch (action)
            {
                case "Horizontal": return negative ? Left : Right;
                case "Vertical": return negative ? Down : Up;
                case "Right": return negative ? 0 : Right;
                case "Left": return negative ? 0 : Left;
                case "Up": return negative ? 0 : Up;
                case "Down": return negative ? 0 : Down;
                case "Confirm":
                case "Fire1": return negative ? 0 : Confirm;
                case "Pause":
                case "Fire2": return negative ? 0 : Back;
                default: return 0;
            }
        }

        private static void Axis(string __0, ref float __result)
        {
            OpenVrInputBridge input = active;
            if (input == null) return;
            if (input.ConsumeGameInput) { __result = 0f; return; }
            float value;
            bool vrMovement = false;
            switch (__0)
            {
                case "Horizontal":
                case "Vertical":
                    Vector2 move = new Vector2(input.horizontal, input.vertical);
                    vrMovement = movementQueryDepth > 0 && move.sqrMagnitude > 0f && input.renderer != null;
                    if (vrMovement) move = input.renderer.MapPlayerMovement(move, movementUsesCameraYaw);
                    value = __0 == "Horizontal" ? move.x : move.y;
                    break;
                case "Horizontal2":
                case "Vertical2":
                    Vector2 second = new Vector2(input.cameraHorizontal, input.cameraVertical);
                    vrMovement = movementQueryDepth > 0 && second.sqrMagnitude > 0f && input.renderer != null;
                    if (vrMovement) second = input.renderer.MapPlayerMovement(second, movementUsesCameraYaw);
                    value = __0 == "Horizontal2" ? second.x : second.y;
                    break;
                default: return;
            }
            // Steam Input may also expose the same stick as a flat gamepad.
            // While a VR stick is active, do not mix its unmapped component back
            // in. With idle VR sticks, original keyboard/gamepad input survives.
            __result = vrMovement ? value : Stronger(__result, value);
        }

        // Scope only actual character movement/jump queries, never 2D menu axes.
        // Finalizer restores nested state even if a game coroutine throws.
        private static void BeginMovementQuery(out MovementScope __state)
        {
            __state = new MovementScope { Depth = movementQueryDepth, CameraYaw = movementUsesCameraYaw };
            movementQueryDepth++; movementUsesCameraYaw = true;
        }
        private static void BeginJumpQuery(out MovementScope __state)
        {
            __state = new MovementScope { Depth = movementQueryDepth, CameraYaw = movementUsesCameraYaw };
            movementQueryDepth++; movementUsesCameraYaw = false;
        }
        private static void EndMovementQuery(MovementScope __state)
        { movementQueryDepth = __state.Depth; movementUsesCameraYaw = __state.CameraYaw; }

        private static void Button(string __0, ref bool __result) { Add(__0, false, 0, ref __result); }
        private static void ButtonDown(string __0, ref bool __result) { Add(__0, false, 1, ref __result); }
        private static void ButtonUp(string __0, ref bool __result) { Add(__0, false, 2, ref __result); }
        private static void NegativeButton(string __0, ref bool __result) { Add(__0, true, 0, ref __result); }
        private static void NegativeButtonDown(string __0, ref bool __result) { Add(__0, true, 1, ref __result); }
        private static void NegativeButtonUp(string __0, ref bool __result) { Add(__0, true, 2, ref __result); }
        private static void AnyButton(ref bool __result) { AddAny(0, ref __result); }
        private static void AnyButtonDown(ref bool __result) { AddAny(1, ref __result); }
        private static void AnyButtonUp(ref bool __result) { AddAny(2, ref __result); }

        private static void Add(string action, bool negative, int edge, ref bool result)
        {
            OpenVrInputBridge input = active;
            if (input != null && input.ConsumeGameInput) result = false;
            else if (input != null)
            {
                uint mask = Mask(action, negative);
                bool value = (input.State(edge) & mask) != 0;
                if (movementQueryDepth > 0 && mask != 0 && (mask & ~(Right | Left | Up | Down)) == 0 &&
                    (input.horizontal != 0f || input.vertical != 0f || input.previousHorizontal != 0f || input.previousVertical != 0f))
                    result = value;
                else result |= value;
            }
        }

        private static void AddAny(int edge, ref bool result)
        {
            OpenVrInputBridge input = active;
            if (input != null && input.ConsumeGameInput) result = false;
            else if (input != null) result |= input.State(edge) != 0;
        }

        private uint State(int edge)
        {
            if (movementQueryDepth > 0 && renderer != null &&
                (horizontal != 0f || vertical != 0f || previousHorizontal != 0f || previousVertical != 0f))
            {
                uint current = MovementMask(held, horizontal, vertical);
                uint before = MovementMask(previous, previousHorizontal, previousVertical);
                return edge == 1 ? current & ~before : edge == 2 ? before & ~current : current;
            }
            return edge == 1 ? held & ~previous : edge == 2 ? previous & ~held : held;
        }

        private uint MovementMask(uint buttons, float x, float y)
        {
            Vector2 move = renderer.MapPlayerMovement(new Vector2(x, y), movementUsesCameraYaw);
            uint result = buttons & ~(Right | Left | Up | Down);
            if (move.x > 0.5f) result |= Right;
            if (move.x < -0.5f) result |= Left;
            if (move.y > 0.5f) result |= Up;
            if (move.y < -0.5f) result |= Down;
            return result;
        }

        internal void Release()
        {
            if (active == this) active = null;
            held = previous = 0;
            movementQueryDepth = 0;
            movementUsesCameraYaw = true;
            RequireGripRelease();
            if (harmony != null)
            {
                harmony.UnpatchSelf();
                harmony = null;
            }
        }

        private void OnDestroy() { Release(); }

        internal void RequireGripRelease()
        {
            gripGesture.Reset();
        }
    }
}
