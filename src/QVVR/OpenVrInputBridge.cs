using System;
using System.Reflection;
using System.Runtime.InteropServices;
using HarmonyLib;
using UnityEngine;
using Valve.VR;

namespace QVVR
{
    // Poll before QV's Update methods. Route recognized Rewired actions through
    // configurable VR bindings; desktop/no-controller input and game files survive.
    [DefaultExecutionOrder(-10000)]
    internal sealed class OpenVrInputBridge : MonoBehaviour
    {
        private const uint Right = 1, Left = 2, Up = 4, Down = 8, Confirm = 16, Back = 32;
        private const uint LeftShoulder = ControllerButtonPolicy.LeftShoulder, RightShoulder = ControllerButtonPolicy.RightShoulder;
        private static OpenVrInputBridge active;
        private static readonly uint ControllerStateSize = (uint)Marshal.SizeOf(typeof(VRControllerState_t));
        private CVRSystem system;
        private CVRCompositor compositor;
        private Plugin plugin;
        private Harmony harmony;
        private uint held, previous;
        private uint menuHeld, previousMenuHeld;
        private uint deliveredActions, pendingReleases, acknowledgedReleases;
        private uint physicalHeld, previousPhysicalHeld;
        private float horizontal, vertical, dioramaHorizontal, dioramaVertical;
        private int menuNavigationFrame = -1;
        private float previousHorizontal, previousVertical;
        private float menuHorizontal, menuVertical, previousMenuHorizontal, previousMenuVertical;
        private ControllerBindings bindings;
        private uint bindingRevision;
        private bool controllerInputAvailable, gameplayControls;
        private bool hadFocus;
        private bool loggedControllers;
        private bool loggedInput;
        private VrSettingsMenu settingsMenu;
        private bool previousStickChord;
        private bool suppressUntilNeutral;
        private bool uiActionLatch;
        private bool previousShoulderMode;
        private readonly GripGestureState gripGesture = new GripGestureState();
        private OpenVrRenderer renderer;
        private static int movementQueryDepth;
        private static int uiQueryDepth;
        private static bool movementUsesCameraYaw = true;
        private struct MovementScope { internal int Depth; internal bool CameraYaw; }
        private bool IsMenuContext { get { return uiQueryDepth > 0 || !gameplayControls; } }

        internal bool BothGripsHeld { get { return gripGesture.Mode == 2; } }
        internal bool RightGripGrabHeld { get { return gripGesture.Mode == 1; } }
        internal uint LeftDevice { get; private set; }
        internal uint RightDevice { get; private set; }
        // Read in renderer LateUpdate, after QV's UI handlers had a chance to
        // consume navigation this frame. Never mutate placement during polling.
        internal Vector2 DioramaStick { get { return controllerInputAvailable && gameplayControls &&
            !ConsumeGameInput && !gripGesture.Reserved && menuNavigationFrame != Time.frameCount && Time.timeScale > 0f ?
            new Vector2(dioramaHorizontal, dioramaVertical) : new Vector2(0f, 0f); } }
        internal float DioramaTurnSpeed { get { return bindings.DioramaTurnSpeed; } }
        internal float DioramaMoveSpeed { get { return bindings.DioramaMoveSpeed; } }

        private bool ConsumeGameInput { get { return suppressUntilNeutral || (uiActionLatch && !IsMenuContext) || (settingsMenu != null && settingsMenu.Visible) ||
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
                // UI remains UI even while the scene is stereoscopic gameplay.
                // Fire1/Fire2 and navigation must use menu bindings in pause,
                // dialogs and intro hub handlers, not the player's action keys.
                string[] menus = { "Pause:Update", "AchievementDisplay:Update", "OptionManager:Update",
                    "ClearUI:Update", "DialogManager:DialogUpdate", "PrevDialogManager:Update",
                    "NarrativeManager:Update", "SkipManager:Update", "IntroWorldManager:Excute", "NewIntroWorldManager:Excute" };
                for (int i = 0; i < menus.Length; i++)
                {
                    string[] name = menus[i].Split(':'); Type type = AccessTools.TypeByName(name[0]);
                    MethodInfo method = type == null ? null : AccessTools.Method(type, name[1], Type.EmptyTypes);
                    if (method != null) harmony.Patch(method,
                        prefix: new HarmonyMethod(typeof(OpenVrInputBridge), "BeginUiQuery"),
                        finalizer: new HarmonyMethod(typeof(OpenVrInputBridge), "EndUiQuery"));
                }
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
                Plugin.Log.LogInfo("QVVR configurable controller bridge active: [Input] logical roles, separate gameplay/menu actions, layout=" + plugin.InputControls.Bindings.Layout +
                    ", exclusive VR controls=" + plugin.InputControls.Bindings.Exclusive + ". OpenXR actions / OpenVR legacy compatibility; original desktop fallback retained.");
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
            pendingReleases &= ~acknowledgedReleases; acknowledgedReleases = 0;
            controllerInputAvailable = false;
            bool wasGripping = gripGesture.Reserved;
            LeftDevice = RightDevice = OpenVR.k_unTrackedDeviceIndexInvalid;
            previous = held;
            previousPhysicalHeld = physicalHeld; physicalHeld = 0;
            previousMenuHeld = menuHeld;
            previousHorizontal = horizontal; previousVertical = vertical;
            previousMenuHorizontal = menuHorizontal; previousMenuVertical = menuVertical;
            held = 0;
            menuHeld = 0;
            horizontal = vertical = dioramaHorizontal = dioramaVertical = 0f;
            menuHorizontal = menuVertical = 0f;
            if (active != this || !plugin.VrEnabled.Value || !plugin.VrControllerInput.Value)
            {
                gripGesture.Reset();
                hadFocus = false; previousStickChord = false;
                ReleaseDeliveredActions();
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
                ReleaseDeliveredActions();
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
            controllerInputAvailable = hasLeft || hasRight;
            if (!controllerInputAvailable)
            {
                hadFocus = false; previous = 0; previousStickChord = false;
                gripGesture.Reset(); ReleaseDeliveredActions(); return;
            }
            uint currentBindingRevision;
            bindings = plugin.InputControls.Read(out currentBindingRevision);
            if (bindingRevision != currentBindingRevision) suppressUntilNeutral = true;
            bindingRevision = currentBindingRevision;
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

            // OpenXR is already normalized into this compatibility state. On
            // PCVR these roles come from SteamVR's legacy controller mapping.
            horizontal = DeadZone(ControllerButtonPolicy.Stick(bindings.MovementStick, leftState.rAxis0.x, rightState.rAxis0.x));
            vertical = DeadZone(ControllerButtonPolicy.Stick(bindings.MovementStick, leftState.rAxis0.y, rightState.rAxis0.y));
            menuHorizontal = DeadZone(ControllerButtonPolicy.Stick(bindings.MenuStick, leftState.rAxis0.x, rightState.rAxis0.x));
            menuVertical = DeadZone(ControllerButtonPolicy.Stick(bindings.MenuStick, leftState.rAxis0.y, rightState.rAxis0.y));
            dioramaHorizontal = DeadZone(ControllerButtonPolicy.Stick(bindings.DioramaStick, leftState.rAxis0.x, rightState.rAxis0.x));
            dioramaVertical = DeadZone(ControllerButtonPolicy.Stick(bindings.DioramaStick, leftState.rAxis0.y, rightState.rAxis0.y));
            if (horizontal > 0.5f) held |= Right;
            if (horizontal < -0.5f) held |= Left;
            if (vertical > 0.5f) held |= Up;
            if (vertical < -0.5f) held |= Down;
            bool shoulders = renderer != null && renderer.UseGameShoulders;
            // Do not reinterpret a held control when presentation changes.
            if (shoulders != previousShoulderMode) suppressUntilNeutral = true;
            previousShoulderMode = shoulders;
            gameplayControls = shoulders;
            uint physical = ControllerButtonPolicy.Physical(hasLeft ? leftState.ulButtonPressed : 0,
                hasLeft ? leftState.rAxis1.x : 0f, hasRight ? rightState.ulButtonPressed : 0,
                hasRight ? rightState.rAxis1.x : 0f);
            physicalHeld = physical;
            held |= ControllerButtonPolicy.Buttons(physical, bindings, gameplayControls);
            menuHeld = ControllerButtonPolicy.Buttons(physical, bindings, false);

            // The A press used to dismiss Steam's overlay must not also choose
            // a game menu item when scene focus returns.
            bool stickChord = ControllerButtonPolicy.Pressed(physical, bindings.VrMenu);
            bool focusWasAvailable = hadFocus;
            if (!hadFocus)
            {
                previous = held;
                previousPhysicalHeld = physicalHeld;
                previousMenuHeld = menuHeld;
                previousHorizontal = horizontal; previousVertical = vertical;
                previousMenuHorizontal = menuHorizontal; previousMenuVertical = menuVertical;
                if (physical != 0 || dioramaHorizontal != 0f || dioramaVertical != 0f) suppressUntilNeutral = true;
            }
            hadFocus = true;
            bool menuWasVisible = settingsMenu != null && settingsMenu.Visible;
            if (focusWasAvailable && stickChord && !previousStickChord && settingsMenu != null)
            {
                settingsMenu.Toggle();
                suppressUntilNeutral = true;
            }
            previousStickChord = stickChord;
            if (suppressUntilNeutral && physical == 0 && horizontal == 0f && vertical == 0f &&
                menuHorizontal == 0f && menuVertical == 0f && dioramaHorizontal == 0f && dioramaVertical == 0f)
                suppressUntilNeutral = false;
            if (physical == 0 && horizontal == 0f && vertical == 0f && menuHorizontal == 0f && menuVertical == 0f &&
                dioramaHorizontal == 0f && dioramaVertical == 0f) uiActionLatch = false;
            if (settingsMenu != null && settingsMenu.Visible && !suppressUntilNeutral)
                settingsMenu.HandleInput(menuHorizontal, menuVertical, (MenuState(1) & Confirm) != 0, (MenuState(1) & Back) != 0);
            if (menuWasVisible && !settingsMenu.Visible)
            {
                RequireGripRelease();
                suppressUntilNeutral = true;
            }
            if (ConsumeGameInput) ReleaseDeliveredActions();
            else deliveredActions &= held;
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
            return float.IsNaN(value) || float.IsInfinity(value) || Mathf.Abs(value) < 0.25f ? 0f : value;
        }

        private static uint Mask(string action, bool negative)
        {
            return ControllerButtonPolicy.ActionMask(action, negative, active == null || active.IsMenuContext);
        }

        private static void Axis(string __0, ref float __result)
        {
            OpenVrInputBridge input = active;
            if (input == null || !input.controllerInputAvailable) return;
            if (input.ConsumeGameInput) { __result = 0f; return; }
            float value;
            bool vrMovement = false;
            switch (__0)
            {
                case "Horizontal":
                case "Vertical":
                    if (input.IsMenuContext) input.menuNavigationFrame = Time.frameCount;
                    Vector2 move = input.IsMenuContext ? new Vector2(input.menuHorizontal, input.menuVertical) : new Vector2(input.horizontal, input.vertical);
                    vrMovement = !input.IsMenuContext && movementQueryDepth > 0 && move.sqrMagnitude > 0f && input.renderer != null;
                    if (vrMovement) move = input.renderer.MapPlayerMovement(move, movementUsesCameraYaw);
                    value = __0 == "Horizontal" ? move.x : move.y;
                    break;
                case "Horizontal2":
                case "Vertical2":
                    // Also erase Steam Input's mirrored secondary axes, even in
                    // mixed mode: this stick now belongs to diorama placement.
                    __result = 0f;
                    return;
                default: return;
            }
            // Exclusive mode prevents a second, unmapped Steam Input action.
            // Mixed mode retains the old keyboard/gamepad merge policy.
            __result = input.bindings.Exclusive || vrMovement ? value : Stronger(__result, value);
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
        private static void BeginUiQuery(out int __state) { __state = uiQueryDepth; uiQueryDepth++; }
        private static void EndUiQuery(int __state) { uiQueryDepth = __state; }

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
            if (input == null) return;
            uint mask = Mask(action, negative);
            if (input.IsMenuContext && (mask & 15u) != 0) input.menuNavigationFrame = Time.frameCount;
            if (!input.controllerInputAvailable)
            {
                if (edge == 2) result |= input.Released(mask);
                return;
            }
            if (input.ConsumeGameInput)
            {
                input.ReleaseDeliveredActions();
                result = edge == 2 && input.Released(mask);
            }
            else
            {
                if (!ControllerButtonPolicy.Known(action)) return;
                bool value = (input.State(edge) & mask) != 0;
                if (edge == 2) value |= input.Released(mask);
                // A dialog/resume button must not become a held game action in
                // a later Update on this or the next frame. UI queries still
                // see the same edge; only gameplay waits for neutral input.
                if (value && edge == 1 && input.IsMenuContext && input.gameplayControls && (mask & ~15u) != 0)
                { input.uiActionLatch = true; input.ReleaseDeliveredActions(); }
                if (!input.IsMenuContext && value)
                {
                    if (edge == 2) input.deliveredActions &= ~mask;
                    else
                    {
                        input.deliveredActions |= mask;
                        input.pendingReleases &= ~mask;
                    }
                }
                if (input.bindings.Exclusive || (movementQueryDepth > 0 && mask != 0 && (mask & ~(Right | Left | Up | Down)) == 0 &&
                    (input.horizontal != 0f || input.vertical != 0f || input.previousHorizontal != 0f || input.previousVertical != 0f)))
                    result = value;
                else result |= value;
            }
        }

        private static void AddAny(int edge, ref bool result)
        {
            OpenVrInputBridge input = active;
            if (input == null || !input.controllerInputAvailable) return;
            if (input.ConsumeGameInput) result = false;
            else
            {
                // "Press any button" must still accept an otherwise unbound
                // face button. Grips and system buttons remain reserved.
                uint physical = edge == 1 ? input.physicalHeld & ~input.previousPhysicalHeld :
                    edge == 2 ? input.previousPhysicalHeld & ~input.physicalHeld : input.physicalHeld;
                bool value = physical != 0 || (input.State(edge) & 15u) != 0;
                result = input.bindings.Exclusive ? value : result || value;
            }
        }

        private uint State(int edge)
        {
            if (IsMenuContext) return MenuState(edge);
            if (movementQueryDepth > 0 && renderer != null &&
                (horizontal != 0f || vertical != 0f || previousHorizontal != 0f || previousVertical != 0f))
            {
                uint current = MovementMask(held, horizontal, vertical);
                uint before = MovementMask(previous, previousHorizontal, previousVertical);
                return edge == 1 ? current & ~before : edge == 2 ? before & ~current : current;
            }
            return edge == 1 ? held & ~previous : edge == 2 ? previous & ~held : held;
        }
        private uint MenuState(int edge)
        {
            uint current = ControllerButtonPolicy.Directions(menuHeld, menuHorizontal, menuVertical);
            uint before = ControllerButtonPolicy.Directions(previousMenuHeld, previousMenuHorizontal, previousMenuVertical);
            return edge == 1 ? current & ~before : edge == 2 ? before & ~current : current;
        }
        private void ReleaseDeliveredActions()
        {
            // Retain releases until the game actually asks for ButtonUp (it may
            // stop polling while paused/in a jump). Every consumer in that frame
            // sees the same edge; acknowledge only on the next input poll.
            pendingReleases |= deliveredActions; deliveredActions = 0;
        }
        private bool Released(uint mask)
        {
            uint released = pendingReleases & mask;
            acknowledgedReleases |= released;
            return released != 0;
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
            menuHeld = previousMenuHeld = 0; uiActionLatch = false;
            deliveredActions = pendingReleases = acknowledgedReleases = 0;
            physicalHeld = previousPhysicalHeld = 0;
            controllerInputAvailable = false;
            movementQueryDepth = 0;
            uiQueryDepth = 0;
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
