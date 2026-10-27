# QVVR

An experimental, non-destructive VR mod for the Windows x64 Unity Mono build of
**QV**. Steam Frame runs the game through Proton/FEX. PCVR uses the OpenVR
fallback; compatible Frame runtimes can use exclusive OpenXR passthrough.

## Features and status

- Stereo gameplay rendering with tracked eyes and GPU-only MSAA resolve.
- Cylindrical diorama clipping, including terrain and intersecting geometry,
  with a configurable edge fade and black/green PCVR background.
- Optional OpenXR ALPHA_BLEND composition for passthrough.
- Two-hand translation, physical size and rotation; walk around the placed world.
- Saved layout with visible level-entry placement and a manual recovery action.
- Viewer-relative character movement and separate walk/jump input mappings.
- Upright 2D title/menu panels and an independently sized gameplay HUD.
- Full stereo costume/map selections in the verified intro scene, without diorama clipping.
- Decorative cloud removal without disabling rain-cloud gameplay mechanics.
- Per-eye depth support for QV's known water/ink shaders.
- Optional experimental black cross-sections for clipped opaque mesh solids.
- Original game files remain untouched; desktop rendering remains available.

This is a prototype, not a finished VR port. Passthrough and earlier diorama
iterations have been tested on Steam Frame; the latest layout/input changes need
further headset testing. Offline tests do not establish a stable 72 Hz result.
Post-processing compatibility, depth submission and foveation remain future work.

## Release candidate

Version 0.1.0 is being prepared as an **experimental candidate**, not a stable
release. See [release preparation](docs/release.md) and the
[English release notes](package-assets/RELEASE-NOTES.txt) for pending headset
checks, installation, known limits and the publication checklist.
`tools/verify-release.ps1` builds and runs the automated suites/audits without
deploying, launching QV, staging files or publishing a release.

## Build from source

Requirements: Windows x64, PowerShell 7, a .NET SDK supporting netstandard2.0,
Visual Studio C++ x64 Build Tools, and a legally installed Windows Mono build of QV.

Obtain BepInEx **5.4.23.5** and OpenVR SDK **2.15.6** from their official projects,
extract them locally, then provide explicit paths:

```powershell
.\tools\setup-deps.ps1 `
  -GameDir 'D:\Games\SteamLibrary\steamapps\common\QV' `
  -BepInExSource 'D:\Dependencies\BepInEx-5.4.23.5' `
  -OpenVrSource 'D:\Dependencies\openvr-2.15.6'

.\tools\build.ps1
```

An optional `-OpenVrSdkSource` selects an existing official SDK checkout; otherwise
setup fetches the pinned SDK. `setup-render-deps.ps1` obtains pinned OpenXR 1.1.47
and DirectX shader tooling inputs and verifies checksums. All dependencies and
Unity compilation references stay under ignored `.deps/`; never redistribute
game assemblies. The managed plugin targets **netstandard2.0 / C# 7.3**.

Generated packages are written to `build/release/`, which is excluded from Git.
No game files, dependency binaries or release ZIPs are stored in this repository.

## Install and deploy

The release is a single `QVVR-vX.Y.Z.zip`:

- `PC/`: the game overlay. Copy its **contents** directly beside `QV.exe`.
- `SteamFrame/`: the portable Windows USB manager for Steam Frame.
- `README.txt`: short PC/Frame installation guide.

For Frame, extract the whole ZIP and double-click
**SteamFrame/QVVR-Frame-Setup.bat**. Its menu installs/updates (then sets the
Steam launch options), sets launch options only, or uninstalls QVVR. It uploads
only the content of `PC/`. Put official Android SDK Platform Tools in
`SteamFrame/platform-tools/adb.exe`, or provide `-AdbPath`; an existing ADB on
PATH/Android SDK is also accepted. Authorize the PC in Frame Developer Mode first.
The tool checks that QV is closed, validates the package before upload, preserves
settings/other mods and backs up overwritten/removed overlay files in the game's
`.qvvr-backups`. It refuses conflicting shared loaders, linked paths and ambiguous
devices rather than guessing. Launch options are read and applied through the
running Steam client (USB-forwarded CEF DevTools, `SteamClient.Apps`), keeping
existing options; this needs CEF Remote Debugging enabled in the Frame developer
settings, otherwise the tool reports the manual value. See
[USB manager instructions](package-assets/QVVR-Frame-Setup.txt) for parameters,
custom library paths, preview and recovery. Neither install nor uninstall starts
or terminates QV. No ADB executable is redistributed with the mod.

Close QV before replacing the overlay. Never deploy while it is running.
Back up existing mod files. Copy the contents of the release `PC/` folder directly
beside `QV.exe` (not into a nested folder), or use the deploy-only helper (ADB mode
runs the same Frame setup script, including launch options):

```powershell
.\tools\deploy-frame.ps1 -Mode Adb -AdbPath 'D:\Tools\platform-tools\adb.exe' -AdbSerial '<device-serial>'
```

Authorize the PC in the headset first. On Windows, `-AdbUsbLegacy` can be used
when the USB interface is present but ADB finds no device.
SSH and custom-tool deployment are also supported; see the script parameters.
Deployment does **not** start or terminate QV.

Set these Steam launch options for the Windows build on Frame:

```text
WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11
```

Start QV manually with the appropriate VR runtime available. Set
`Diorama.Passthrough=true` or enable **OpenXR passthrough** in the settings menu,
then restart manually, to try passthrough. OpenXR and OpenVR never run concurrently
inside the mod: unsupported/failing XR is destroyed before OpenVR fallback.
Without a usable VR runtime, the original desktop view remains available.

USB/SSH updates preserve `BepInEx/config/dev.qvvr.prototype.cfg`. Keep this file
when updating manually. To uninstall, close QV and run the ownership-checked
`uninstall.bat` from the installed overlay and confirm removal. It moves QVVR into
a recoverable `.qvvr-backups` folder; settings are kept by default and shared
loader/other mods remain. Optional PowerShell: `./uninstall.ps1 -RemoveConfig`
also backs up/removes settings; `-WhatIf` previews without moving anything.
On SteamOS, remove only `BepInEx/plugins/QVVR` and the QVVR config manually;
the batch helper targets Windows. Review core/loader replacement if BepInEx is
shared with other mods. The ZIP is allowlisted and audited, with full license
texts, corresponding Doorstop source, per-file hashes and an adjacent SHA-256
checksum. Hashes detect changes but are not a digital publisher signature.

### PCVR: Steam Link or Virtual Desktop

The intended PCVR route is **QVVR OpenVR -> SteamVR -> streaming headset**.
Quest 3 + Virtual Desktop is a planned hardware acceptance test, not yet a
validated compatibility claim. Connect through the streaming app and have the
headset/controllers ready in SteamVR before starting QV manually.

- Use the Windows x64 Mono game and `-force-d3d11` on the Windows PC. The Frame's
  `WINEDLLOVERRIDES` option is for Proton, not native Windows.
- Keep `[Diorama] Passthrough=false`; PCVR uses opaque black/green, not the Frame
  alpha-blend path. A copied Frame config may already have passthrough enabled.
- Keep `[Input] Layout=FaceButtons` for normalized Touch-style controls. SteamVR
  legacy controller mapping still determines the physical button/axis roles.
- Keep compositor frame pacing enabled. OpenVR prediction now uses SteamVR's
  reported display frequency, display delay and elapsed vsync time, not 1/72 s.
  This does not force the headset refresh rate or promise a particular FPS.
- Virtual Desktop's direct VDXR/OpenXR path is not the intended backend for this
  candidate; use SteamVR. Do not substitute an OpenComposite DLL for the bundled
  `openvr_api.dll` during this acceptance test.

Check stereo/IPD, head movement, grips, menu buttons, focus/reconnect, black/green
background and frame times on the actual connection before calling it supported.
An OpenVR-only input fixture and simulated timing tests do not test streaming
latency, driver mappings or headset comfort.

## Controls

Controller bindings live in `[Input]` in `BepInEx/config/dev.qvvr.prototype.cfg`.
They name logical button roles rather than a headset. Default `Layout=FaceButtons`
targets the existing Frame/Touch-style normalized layout. Use `TrackpadWands`
for OpenVR controllers without face buttons. Other PCVR devices still depend on
their SteamVR legacy compatibility mapping; these presets are not a new runtime
backend or a claim of hardware validation on every headset.

| Action | FaceButtons default | TrackpadWands default |
| --- | --- | --- |
| Primary game action | Right primary (A) | Right trigger |
| Secondary game action / menu back | Right secondary (B) | Right application-menu button |
| Pause | Left secondary (Y; Frame left D-pad up in XR) | Left application-menu button |
| Character swap | Left primary (X; Frame left D-pad down in XR) | Left trackpad click |
| Dash (hold) | Right trigger | Left trigger |
| Game camera mode (hold) | Left trigger | Unbound; diorama gestures still work |
| Load (original LB+RB action) | Both triggers | Both triggers |
| Menu/dialog/VR settings confirm | Right primary (A) | Right trigger |
| Menu previous/next page | Left/right trigger | Unbound; configurable |
| QVVR settings | Both stick clicks | Right trackpad click |

- Left stick/pad: viewer-relative character movement. Right stick/pad: left/right
  rotates the diorama about its center; forward brings it closer, backward moves
  it away, at constant height and size. With **Cylindrical diorama: Off**, the right
  stick instead turns the normal-scale camera in place and moves it forward/back
  along the viewer's upright heading. `MovementStick`, `DioramaStick`, `MenuStick`
  select `Left`, `Right`, `Either` or `None`; menus default to either stick/pad.
  Game secondary camera axes are disabled in focused VR. The old `CameraStick`
  setting is no longer used. Do not assign locomotion and diorama to the same stick
  unless simultaneous movement is intended.
- `DioramaStickTurnDegreesPerSecond=60` and
  `DioramaStickMoveMetersPerSecond=0.6` set full-deflection speeds. Placement uses
  physical meters, preserves tilt, and is saved after release. UI navigation,
  pause, VR settings, cinematics and two-grip gestures block stick placement.
  `DioramaStickDeadZone=0.4` gives placement a 40% center dead zone and a smooth
  response outside it. Dominant-axis hysteresis separates turning from approach:
  a slight diagonal during rotation no longer also moves the diorama.
- Every button action accepts `Default` (preset), `None`, `LeftPrimary`,
  `LeftSecondary`, `RightPrimary`, `RightSecondary`, `LeftTrigger`, `RightTrigger`,
  `LeftStickClick`, `RightStickClick`, `BothTriggers`, `BothStickClicks` or
  `BothSecondaryButtons`. Grips and system buttons cannot be assigned.
- `PrimaryAction`, `SecondaryAction`, `Pause`, `Swap`, `Dash`, `Camera`, `Load`,
  `MenuConfirm`, `MenuBack`, `PreviousPage`, `NextPage`, `VrSettings` are independent.
  For example, `PrimaryAction=RightTrigger` and `Dash=None` moves the primary action
  onto the trigger; also set `NextPage=None` if using it for menu confirmation.
- Pause/dialog queries use menu bindings even inside a VR gameplay scene. B no
  longer also emits Pause. Menu trigger paging does not also confirm by default.
  Closed dialogue handlers cannot consume gameplay A. A consumed UI confirm
  clears on button release without requiring the walking stick to recenter;
  delayed game polling also retains pending releases for held actions.
- While Load is held its constituent controls cannot also dash, activate camera
  mode or perform the primary action. A constituent pressed earlier can still
  perform its ordinary action before the full chord is held. Custom overlapping
  bindings are possible; avoid assigning the same single button to several game
  actions. Settings, gestures and focus-return input suppression are preserved.
- `ExclusiveVrControls=true` avoids adding Steam Input's mirrored gamepad actions
  while focused VR controllers are available. Set false to restore mixed
  keyboard/gamepad input. Unknown actions and no-controller/desktop fallback are
  retained. Edit the file with QV closed; existing user configuration is preserved
  on deployment and missing keys receive defaults on manual launch.
- Both grips: move hands together to translate, spread/close to resize,
  and rotate the shared hand/wrist pose to rotate the diorama.
- Release either grip to retain placement. Right grip alone has no placement action.
- F7: recenter; F8: toggle VR/desktop rendering.

The settings menu uses up/down to select and left/right to adjust. Binding edits
are currently file-based, not an in-headset rebinding screen. Closing saves
settings. The game simulation is not paused while this menu is open.

The compact menu has 15 entries: view tilt, render profile, recenter, restore
comfort defaults, cylindrical diorama on/off, radius/height/center height, void color, passthrough,
edge fade, clouds, place in front, diorama size and XR eye-scale cap. Position
and scale remain available through controller gestures/stick placement. Removed
panel/HUD/debug switches are not silently disabled; their config keys remain.
Fresh defaults use the reference Frame profile: tilt -16 degrees, 2D panel width
1.8 m/distance 1.5 m/follow lag 0.6 s, HUD scale 1.8/distance 1.4 m/inset 29%,
hub pause distance 1.2 m, cylinder on, normal probe, black caps and stereo
selection menus on. Existing config values are preserved. Restore comfort
defaults uses the same bound defaults, including the config-only settings.

Disable **Cylindrical diorama** for experimental full-world VR: one game unit per
physical meter, full stereo/room-scale tracking, no cylinder clipping, caps or
outside-cylinder culling, and the game's original background. The camera starts
3 game units behind Q at 1.6 units above the player root, follows Q's translation,
and ignores scripted gameplay-camera motion and miniature scale/tilt. The right
stick adds yaw and horizontal forward/back movement; the left still controls Q
relative to the viewer. **Reset camera behind Q** or **Recenter view** restores
the starting framing. Two-grip diorama gestures are inactive in this mode.
Returning to the diorama preserves its placement and size. Cinematics/selection
menus retain their existing presentation. There is no camera collision handling;
navigation can enter geometry. Rendering the whole level may increase GPU cost.
This mode still needs Frame and Quest 3/Virtual Desktop headset acceptance.

Dialogue boxes are centered in the viewer-following HUD instead of following the
actor's original flat-screen projection. They open in front of the viewer and
retain the normal upright HUD-follow delay, text animation and portraits. This
uses the existing UI capture, not an additional render pass. Set
`[Comfort] CenterDialogs=false` to restore the original layout. Desktop and fixed
flat cinematics keep their original dialogue placement.

Independent diorama VR shortens the standard level-entry transition before
dialogue/controls from 5.5 to 1.5 seconds. `Comfort.LevelEntrySeconds` accepts
1.5-5.5; set 5.5 to restore the original duration. The lower limit preserves QV's
internal camera-focus timing. Only GameStart's verified entry fades are changed;
their original completion callbacks still start dialogue/tutorials and movement.
Story cinematics, desktop and non-independent VR retain their original timing.
Changes apply at the next entry, not to an already-running transition.

Some levels open with a camera tour of the level (a Timeline) that cannot be
followed from the independent VR view. `Comfort.SkipLevelTour=true` (default)
stops it one frame after it starts, through the same `PlayableDirector.Stop`
path as the game's own skip, so the level starts normally. Level 1-1's story
intro stays on its flat screen; desktop and non-independent VR keep the tour.

Two-hand translation defaults to **1.15x**, rotation to **1.10x**; head tracking
and separation-based resize are unchanged. `Controls.DioramaMoveSensitivity`
and `Controls.DioramaRotationSensitivity` allow 0.25-3x, sampled at grab start.

**Diorama size** supports 0.001-10 times the base world size, independently of FOV.
Level entry restores physical size/orientation/offset relative to the wearer's
upright heading, with front/visibility safeguards. First entry fits a reasonable
size unless an existing preference can be reused. **Place diorama in front of me**
provides recovery. The cylinder follows the character, not head movement or
subsequent game-camera turns.
Entry now uses `Diorama.EntrySizeMultiplier=0.85` and
`Diorama.EntryDistanceMultiplier=0.8`: 15% smaller, about 20% closer subject to
cylinder clearance, also for existing saved layouts. Height/rotation remain
unchanged. Saving inverses the latched entry gains, so subsequent levels/recenters
do not repeatedly shrink or move the diorama forward. Set both gains to 1 for
the previous framing. The default 1.6 m base becomes a 1.36 m diorama.

2D panels follow horizontal heading with lag, never head pitch/roll. The settings
panel remains physically anchored while open. Gameplay and stereo intro HUD
size/distance are independent of captured 2D title/menu panel settings.

**3D costume/map menus** renders the verified `001_Intro` hub/costume/stage states
directly in stereo. Title/loading/other states retain 2D capture. Selections use
QV's scripted camera plus VR head tracking, not saved gameplay placement/size,
cylinder clipping, grips, or passthrough. Camera-space map labels are captured
alongside overlay UI. The hub leading to costumes is also stereo. These screens
share the gameplay HUD size and physical distance, with upright lagged follow
and GPU-filtered UI textures; their UI refreshes at the 72 Hz menu capture rate
(`Performance.MenuCaptureRate`), not the 36 Hz gameplay HUD rate. Turn the option off to recover the
old flat presentation and its independent menu UI settings.
**HUD center inset** moves root UI layout anchors inward by 29% per edge by
default (0-45%, live). Staying below 50% avoids collapsed/inverted panels.
Local font/widget size, game references and offsets stay
unchanged; 0 restores original anchors. Applies to gameplay/stereo intro capture,
not titles or flat recovery. Layout is updated during cold canvas maintenance,
not on each frame, and restored on desktop/shutdown.
The verified `1_1` opening Timeline switches to a flat cinematic panel using
its own camera, then returns to stereo gameplay after completion/skip. Late
injection and paused intros are recovered during cold maintenance. Saved diorama
layout is fitted in front of the viewer only when gameplay resumes; grips cannot
move the world during the intro. Flat intro UI keeps original anchors, while VR
controller confirm/back remain available. Other levels/cutscenes are unchanged.
The cinematic screen stays anchored in physical space without head-follow lag;
Timeline camera animation moves only the captured image. Recenter places the
screen in front again. HUD/settings render after the world with a depth-only
clear, so scenery cannot cover them (including stereo selection screens).
New Game's separate `Opening`/`Opening2` scenes also use this stationary viewer
rig/anchor, not the animated capture camera. Title/regular menus keep their
upright lagged follow. Only the stereo costume-access hub overrides HUD scale
to 4; maps, costume selection and gameplay keep the user's normal HUD scale and
their panel distance settings remain unchanged.
Hub pause/options/achievements (the separate Exit state) use a local scale 2
panel with its own live `Comfort.HubPauseDistanceMeters` setting (default 1.2 m,
range 0.6-3 m), now available in the config file rather than the compact menu.
It does not move the gameplay HUD or VR settings window. Other menus and gameplay
pause remain unchanged. Selecting a map replaces the exact `Cloud.Panel` fade
rectangle with a full-eye stereo fade following the original tween's opacity.
It covers HUD and passthrough too, survives Loading fades and clears with gameplay
fade-in. The original UI image is hidden only during manual capture, then restored;
game timing, raycast settings and scene callbacks are not modified.
Manual eye rendering runs after the game's hair/character LateUpdate simulation;
only the current player's Animator culling and skinned offscreen updates are
overridden to keep animated bones current for hair physics. DynamicBone camera
distance/timing/weights are no longer patched. Scene changes, tracking loss,
cinematics and shutdown restore cached settings. Hair stability and the bounded
player-only animation/skinning cost still need Frame validation.
The costume-access hub uses a closer VR-only camera pose: `VR.IntroHubDistanceScale`
defaults to 0.35 of forward depth to its world anchor (1 restores original
framing). Costume and map cameras are unaffected. The map screen's specific
`LobbyDim` renderer is hidden only during VR eye/UI capture, then restored;
game-side fade tweens, navigation and desktop output remain intact.
Stereo selection menus are enabled in the reference profile; set
`VR.StereoSelectionMenus=false` for flat recovery. New hardware still needs
visual framing, state-transition and CPU/GPU checks.

The old 1 m entry floor is removed: entry now keeps an 8 cm bounding-sphere
margin, with a 0.35 m minimum for tiny dioramas. Manual distance adjustment allows
0.25-10 m; two-grip placement remains independent. Size-aware outside clearance
still applies on automatic entry, including tilted cylinders.

For missed-frame judder, `VR.XrResolutionCap=1` caps exclusive OpenXR eye
supersampling at the runtime's recommended size on the next manual launch.
The VR settings menu exposes **Render scale** (0.5-1.5 in 0.05 steps, showing the
scale actually rendered; it moves the OpenXR cap with it) and **Anti-aliasing
(MSAA)** Off/2x/4x; both apply on the next manual launch. `XrResolutionCap=0`
in the config disables the cap. OpenVR ignores the cap. Capping Sharp 1.15 at 1.0 draws
about 24.4% fewer eye pixels; it does not imply an equal GPU-time reduction.
HUD capture stays at its existing resolution, but final eye sampling follows
the capped eye target. Head tracking is never smoothed or delayed. Physical
diorama eyes now use the exact absolute runtime poses and a direct eye-minus-
placement mapping, avoiding redundant calibrated/head-relative reconstruction.
This mitigates identified budget/precision risks, not a proven headset jitter fix.

Initial diorama clearance uses its physical radius/height bounding sphere plus
0.08 m (minimum depth 0.35 m), rather than a hard 1 m floor. The base first-entry
center is 1.2 m forward and 0.45 m below the eyes; entry multipliers and size
clearance determine the effective placement.
Saved lateral/vertical offsets and intentionally distant layouts are preserved;
only too-close/behind/offscreen entries are adjusted for visibility and clearance.
Only untouched, unsaved old default offsets migrate to the new default; saved
or customized layouts are never overwritten.

## Quality and performance

**HUD compositor layer (Steam Frame / OpenXR):** `VR.CompositorHudLayer=true`
submits the captured HUD as an OpenXR quad layer. The GPU resamples the mipmapped
3360x1890 capture trilinearly into a single-level 2048-wide swapchain, close to
display density, which the runtime samples once instead of through the eye images
(1728x1728 on Frame), so HUD and dialogue text stay sharp. Mipmapped swapchains
are avoided: Proton's D3D11 interop showed stale/corrupt lower levels on Frame.
Additive HUD effects stay additive light. The quad is recopied only when the HUD
content changes. The settings menu and screen fades
temporarily return to the in-eye HUD; a runtime refusal falls back permanently
for the session. OpenVR/PC rendering is unchanged. Restart after changing it.

Profiles: **Performance** (0.85 eye resolution), **Balanced** (1.0), and
**Sharp** (1.15), relative to the runtime recommendation. All default to 2x MSAA;
profiles apply on the next manual launch. HUD capture defaults to 36 Hz, menus
to 72 Hz, and UI capture to 3360x1890 (1.75x) with GPU mipmaps. Realtime shadows are
disabled in VR by default and restored on desktop fallback.
The UI sharpness test adds 36.1% UI capture pixels compared with the previous
1.5x target, not 36.1% total GPU time. Eye/world resolution, 36 Hz HUD cadence,
trilinear filtering and panel shaders are unchanged for an isolated A/B test.
Only the old default UI scale migrates once; custom values are preserved.
After migration, set `VR.UiTextureScale=1.5` and manually restart for rollback;
`VR.UiQualityRevision=1` prevents reapplying the test scale. Compare Frame CPU/GPU
and text shimmer in the same level/view before keeping the new setting.

`Diorama.LiquidDepthFix=true` requests fresh per-eye depth when a cached, known
liquid renderer is active. This addresses missing/stale screen-space depth;
it does not freeze/fake camera position or guarantee every liquid artifact is fixed.
The extra opaque depth pass needs a headset performance comparison.

`Diorama.WaterFoamFix=true` is an experimental workaround for blue water appearing
white from above. It temporarily disables only the white foam of the inspected
`WaterBlockMat` material during gameplay stereo rendering; the game's surface and
depth colors remain unchanged. Live values are restored afterward, including on
render failure. Ink, fog, menus, flat cinematics and desktop rendering are not
changed. This reuses the cold liquid scan and adds no render pass or texture.
Set false for an A/B comparison; the visual result still needs Frame validation.

Passthrough compatibility temporarily changes only the verified
`FairyMaterial` / `Custom/2SideShader` material's opaque One/Zero blend to
SrcAlpha/OneMinusSrcAlpha during manual gameplay renders, then restores its live
original values. Its shader already outputs texture alpha; no game shader or
asset file is edited. Other materials and OpenVR framing remain unchanged.
Additive world draws retain original RGB blending but no longer stamp texture
alpha into passthrough coverage. Visible emission over empty background gets
color-derived coverage in the existing XR copy; black texels stay transparent.
This is an ALPHA_BLEND approximation of additive emission, not exact addition to
the runtime's inaccessible camera image. Zero-alpha SrcAlpha fragments cannot
occlude later geometry, even when their original material writes depth.
No extra passes/textures/readback or additional pixel-shader variants are added.
Test fairy silhouettes, additive effects, opaque interiors and black/green
fallback backgrounds on the Frame before claiming performance/correctness.

**Black cut surfaces (experimental)** enables GPU stencil cross-sections of
registered opaque mesh geometry, without a solid black cylinder hiding the scene.
It is enabled in the reference Frame profile (`Diorama.BlackCutSurfaces=false`
disables it through the config file). `Diorama.CutSurfaceMode` picks the method:
`Auto` (default) uses `BackFace` on the OpenXR/Steam Frame path and `Exact` on
OpenVR/PC. `Exact` replays cut meshes and places black exactly on the cylinder
wall. `BackFace` marks the faces solids normally cull in the eye stencil while
they draw, then paints them black in one stencil-tested pass: no replay, about
2 ms instead of about 6 ms GPU on the heavy Frame level, but objects inside a cut
solid stay visible and a solid whose far side is also cut away can stay open.
Both fall back to the private exact method when the game uses stencil.
Open/non-manifold meshes, camera-inside-solid views, dynamic geometry and batching
can limit coverage; this is not a general-purpose watertight mesh repair.

The target is 72 Hz: a 13.89 ms frame budget. Measure CPU and GPU frame times on
the actual device; sparse log samples are not averages or percentiles.

See [architecture](docs/architecture.md), [testing](docs/testing.md), and
[repository safety](docs/repository-safety.md).

The performance pass conservatively culls exterior scene meshes and unnecessary
liquid depth, prunes eligible static-batch cap replays, reuses unchanged HUD
captures and draws the ordinary HUD without another camera render. Independent
rollback switches and optional per-pass GPU timestamps are documented in
[testing](docs/testing.md#performance-pass-validation). Frame gains remain to be measured.

`Performance.LightweightUiMaintenance=true` retains unchanged HUD dirty
subscriptions instead of reinstalling them every scan. UI that requires continuous
capture temporarily drops snapshot/subscription tracking and retries caching every
two seconds; capture rate, mipmaps and text resolution stay unchanged. Set false
for the previous full-tracking A/B path.

The release package contains no measurement code: periodic logs, GPU timestamp
queries, XR cadence counters and their settings are compiled out, and the log holds
only a few startup lines (version, renderer, compositor) plus warnings and errors.
For Frame measurements, build a developer package with
`.\tools\build.ps1 -Configuration Debug` (marked `"diagnostics": true` in
`qvvr-package.json`) and deploy it the same way. There,
`Performance.DiagnosticsEnabled=true` enables five-second measurement logs on the
next manual launch: XR submission cadence, main-thread and enqueue CPU, delayed GPU
frame time, UI scan counts, cylinder coverage, cut-surface and HUD layer state.
`DetailedGpuTimings=true` adds per-phase GPU timestamps (UI, eyes, depth, copy).
Maintenance and logging wall-clock durations are reported separately. Event hooks
still handle menu/cinema transitions immediately; idle recovery polling is once
per second and active fixed-panel cinema recovery remains at 0.1 seconds.
These are overhead reductions to validate on Frame, not a measured FPS guarantee.

## Repository and licensing

- `src/`: managed plugin and native D3D11/OpenXR/OpenVR bridge.
- `tools/`: build, dependency setup, tests and optional diagnostics/deployment.
- `package-assets/`: default configuration, installation notes and removal helper.
- `docs/`: maintained technical documentation only.

QVVR source is covered by the existing [MIT license](LICENSE).
Third-party components retain their own licenses; see
[third-party notices](package-assets/QVVR-THIRD-PARTY-NOTICES.txt).
QV and its assets are not included. This project is not an official game update.
