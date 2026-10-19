using System;
using BepInEx.Configuration;

namespace QVVR
{
    // Translate settings on change, not during input polling.
    internal sealed class ControllerInputConfiguration : IDisposable
    {
        private readonly ConfigFile file;
        private readonly object snapshotLock = new object();
        private ControllerBindings snapshot;
        private uint revision;
        private readonly ConfigEntry<ControllerLayout> layout;
        private readonly ConfigEntry<ControllerBinding> primary, secondary, pause, swap, dash, camera, load;
        private readonly ConfigEntry<ControllerBinding> confirm, back, previousPage, nextPage, vrMenu;
        private readonly ConfigEntry<ControllerStick> movementStick, dioramaStick, menuStick;
        private readonly ConfigEntry<float> dioramaTurnSpeed, dioramaMoveSpeed;
        private readonly ConfigEntry<bool> exclusive;
        internal ControllerBindings Bindings { get { lock (snapshotLock) return snapshot; } }
        internal ControllerBindings Read(out uint currentRevision)
        { lock (snapshotLock) { currentRevision = revision; return snapshot; } }
        internal ControllerInputConfiguration(ConfigFile config)
        {
            file = config;
            layout = file.Bind("Input", "Layout", ControllerLayout.FaceButtons,
                "FaceButtons: Frame/Touch-style face buttons. TrackpadWands: triggers, application-menu buttons and trackpad clicks. OpenVR uses its legacy compatibility layout; choose a preset then override logical roles if needed.");
            primary = Bind("PrimaryAction", "Gameplay Fire1. Default: right primary face button; wands: right trigger.");
            secondary = Bind("SecondaryAction", "Gameplay Fire2, separate from Pause. Default: right secondary face/application-menu button.");
            pause = Bind("Pause", "Game pause. Default: left secondary face/application-menu button.");
            swap = Bind("Swap", "Character swap. Default: left primary face button; wands: left trackpad click.");
            dash = Bind("Dash", "Hold to dash. Default: right trigger; wands: left trigger.");
            camera = Bind("Camera", "Hold for QV's camera mode. Default: left trigger; wands: None (diorama manipulation remains available).");
            load = Bind("Load", "Original LB+RB load command. Default: both triggers; owns constituent controls while held.");
            confirm = Bind("MenuConfirm", "Confirm in menus/dialogs/QVVR settings. Default: right primary face button; wands: right trigger.");
            back = Bind("MenuBack", "Back in menus/QVVR settings. Default: right secondary face/application-menu button.");
            previousPage = Bind("PreviousPage", "Menu L/page action. Default: left trigger; wands: None.");
            nextPage = Bind("NextPage", "Menu R/page action. Default: right trigger; wands: None.");
            vrMenu = Bind("VrSettings", "Toggle QVVR settings. Default: both stick clicks; wands: right trackpad click. Grips remain reserved for the diorama.");
            movementStick = file.Bind("Input", "MovementStick", ControllerStick.Left, "Character locomotion: Left, Right, Either or None. Default Left prevents camera input from moving the character too.");
            dioramaStick = file.Bind("Input", "DioramaStick", ControllerStick.Right, "Diorama placement: horizontal turns about its center; forward brings it closer, backward moves it away. Left, Right, Either or None. Game camera axes are disabled in VR.");
            dioramaTurnSpeed = file.Bind("Input", "DioramaStickTurnDegreesPerSecond", 60f, "Full-deflection diorama yaw speed in degrees per second (0-180).");
            dioramaMoveSpeed = file.Bind("Input", "DioramaStickMoveMetersPerSecond", 0.6f, "Full-deflection diorama approach/retreat speed in physical meters per second (0-3). Height and size are preserved.");
            menuStick = file.Bind("Input", "MenuStick", ControllerStick.Either, "Menu/settings navigation source, independent of locomotion.");
            exclusive = file.Bind("Input", "ExclusiveVrControls", true,
                "While VR controllers are available and focused, replace recognized QV actions instead of adding Steam Input's mirrored gamepad. Unknown actions and desktop/no-controller fallback stay untouched. False allows mixed keyboard/gamepad input.");
            Refresh(); file.SettingChanged += OnSettingChanged;
        }
        private ConfigEntry<ControllerBinding> Bind(string key, string description)
        { return file.Bind("Input", key, ControllerBinding.Default, description + " Default selects the preset; None disables the action. Values name logical roles, never grips or reserved system buttons."); }
        private void OnSettingChanged(object sender, SettingChangedEventArgs args)
        { if (args.ChangedSetting.Definition.Section == "Input") Refresh(); }
        private void Refresh()
        {
            ControllerBindings next = ControllerButtonPolicy.Defaults(new ControllerBindings {
                Layout = layout.Value, Primary = primary.Value, Secondary = secondary.Value, Pause = pause.Value,
                Swap = swap.Value, Dash = dash.Value, Camera = camera.Value, Load = load.Value,
                MenuConfirm = confirm.Value, MenuBack = back.Value, PreviousPage = previousPage.Value,
                NextPage = nextPage.Value, VrMenu = vrMenu.Value, MovementStick = movementStick.Value,
                DioramaStick = dioramaStick.Value, DioramaTurnSpeed = dioramaTurnSpeed.Value,
                DioramaMoveSpeed = dioramaMoveSpeed.Value, MenuStick = menuStick.Value, Exclusive = exclusive.Value });
            lock (snapshotLock) { snapshot = next; revision++; }
        }
        public void Dispose() { file.SettingChanged -= OnSettingChanged; }
    }
}
