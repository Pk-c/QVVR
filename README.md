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
- Decorative cloud removal without disabling rain-cloud gameplay mechanics.
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

- Right A/right trigger: confirm; right B: back.
- Thumbsticks: menu navigation; character movement is viewer-relative.
- Both thumbstick clicks: open/close the QVVR settings panel.
- Both grips: move hands together to translate, spread/close to resize,
  and rotate the shared hand/wrist pose to rotate the diorama.
- Release either grip to retain placement. Right grip alone has no placement action.
- F7: recenter; F8: toggle VR/desktop rendering.

The settings menu uses up/down to select and left/right to adjust. Closing saves
settings. The game simulation is not paused while this menu is open.

**Diorama size** supports 0.001-10 times the base world size, independently of FOV.
Level entry restores physical size/orientation/offset relative to the wearer's
upright heading, with front/visibility safeguards. First entry fits a reasonable
size unless an existing preference can be reused. **Place diorama in front of me**
provides recovery. The cylinder follows the character, not head movement or
subsequent game-camera turns.

2D panels follow horizontal heading with lag, never head pitch/roll. The settings
panel remains physically anchored while open. HUD size/distance are independent
of title/menu panel settings.

## Quality and performance

Profiles: **Performance** (0.85 eye resolution), **Balanced** (1.0), and
**Sharp** (1.15), relative to the runtime recommendation. All default to 2x MSAA;
profiles apply on the next manual launch. HUD capture defaults to 36 Hz, menus
to 72 Hz, and UI capture to 2880x1620 with GPU mipmaps. Realtime shadows are
disabled in VR by default and restored on desktop fallback.

The target is 72 Hz: a 13.89 ms frame budget. Measure CPU and GPU frame times on
the actual device; sparse log samples are not averages or percentiles.

See [architecture](docs/architecture.md), [testing](docs/testing.md), and
[repository safety](docs/repository-safety.md).

## Repository and licensing

- `src/`: managed plugin and native D3D11/OpenXR/OpenVR bridge.
- `tools/`: build, dependency setup, tests and optional diagnostics/deployment.
- `package-assets/`: default configuration, installation notes and removal helper.
- `docs/`: maintained technical documentation only.

QVVR source is covered by the existing [MIT license](LICENSE).
Third-party components retain their own licenses; see
[third-party notices](package-assets/QVVR-THIRD-PARTY-NOTICES.txt).
QV and its assets are not included. This project is not an official game update.
