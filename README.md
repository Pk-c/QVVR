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

Close QV before replacing the overlay. Never deploy while it is running.
Copy a locally built ZIP beside `QV.exe`, or use the deploy-only helper:

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
`uninstall.bat` from the installed overlay; shared loader files are preserved.

## Controls

- Right A: confirm/jump; right B: back.
- Gameplay index triggers: left = LB (`L`), right = RB (`R`), both = LB+RB.
  Grips remain reserved for diorama manipulation. Right trigger still confirms
  in menus, cinematic panels and VR settings.
- Thumbsticks: menu navigation; character movement is viewer-relative.
- Both thumbstick clicks: open/close the QVVR settings panel.
- Both grips: move hands together to translate, spread/close to resize,
  and rotate the shared hand/wrist pose to rotate the diorama.
- Release either grip to retain placement. Right grip alone has no placement action.
- F7: recenter; F8: toggle VR/desktop rendering.

The settings menu uses up/down to select and left/right to adjust. Closing saves
settings. The game simulation is not paused while this menu is open.

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
share the gameplay HUD size, physical distance and capture rate, with upright
lagged follow and GPU-filtered UI textures. Turn the option off to recover the
old flat presentation and its independent menu UI settings.
**HUD center inset** moves root UI layout anchors inward by 12% per edge by
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
range 0.6-3 m), exposed as **Hub pause/achievements distance** in VR settings.
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
This experimental option is off by default: visual framing, state transitions
and CPU/GPU costs still need Frame testing.

The old 1 m entry floor is removed: entry now keeps an 8 cm bounding-sphere
margin, with a 0.35 m minimum for tiny dioramas. Manual distance adjustment allows
0.25-10 m; two-grip placement remains independent. Size-aware outside clearance
still applies on automatic entry, including tilted cylinders.

For missed-frame judder, `VR.XrResolutionCap=1` caps exclusive OpenXR eye
supersampling at the runtime's recommended size on the next manual launch.
The requested profile is preserved; **XR eye scale cap** in settings can raise
the cap or disable it (0). OpenVR is unchanged. Capping Sharp 1.15 at 1.0 draws
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
It is **off by default** until Frame correctness/performance testing. It costs an
extra geometry pass and private GPU depth/stencil targets when enabled.
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

## Repository and licensing

- `src/`: managed plugin and native D3D11/OpenXR/OpenVR bridge.
- `tools/`: build, dependency setup, tests and optional diagnostics/deployment.
- `package-assets/`: default configuration, installation notes and removal helper.
- `docs/`: maintained technical documentation only.

QVVR source is covered by the existing [MIT license](LICENSE).
Third-party components retain their own licenses; see
[third-party notices](package-assets/QVVR-THIRD-PARTY-NOTICES.txt).
QV and its assets are not included. This project is not an official game update.
