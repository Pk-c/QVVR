QVVR 0.1.0 - Experimental VR mod
================================

Costume/map selections in 001_Intro can render in full stereo without diorama
clipping or passthrough. Title/loading/other states remain 2D. Use 3D costume/map
menus in settings to test it or recover flat capture if framing/transitions fail.
The stereo selection option is off by default until Frame measurement/testing.
First-entry default depth is 1.6 m; closer clearance uses actual cylinder bounds.
Saved X/Y, size, rotation and intentionally distant placement are preserved.

Two-hand placement sensitivity: translation 1.15x, rotation 1.10x. Resize and
head tracking are unchanged. LiquidDepthFix adds fresh per-eye depth only for
known active liquid shaders; verify water/ink on the headset.
Black cut surfaces (experimental) is an opt-in settings-menu stencil cap mode.
It is off by default until Frame correctness/performance testing. Open meshes
and incomplete native batch registration can limit coverage; extra GPU work.

Install the locally built archive beside QV.exe. Close QV before deployment;
start it manually afterward. Preserve BepInEx/config/dev.qvvr.prototype.cfg
when updating manually. USB/SSH deployment preserves it automatically.

Steam launch options for the Windows build on Steam Frame:
  WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11

Controls:
  F7: recenter. F8: toggle VR/desktop.
  Right A/right trigger: confirm. Right B: back.
  Both stick clicks: open/close QVVR settings.
  Menu up/down: select. Left/right: adjust. Closing saves settings.
  Both grips: natural translation, hand-separation size, hand/wrist rotation.
  Release either grip to retain the pose. Right grip alone does not manipulate.
  The settings menu does not pause game simulation.

Diorama:
  Game fragments are clipped to a cylinder; HUD/menu panels are separate.
  Default radius/height: 12 original game units.
  Diorama size supports 0.001-10 times base size.
  Saved physical size, orientation and offset are reused at level entry,
  with visibility safeguards and a reasonable first-entry fit.
  Use Place diorama in front of me for recovery.
  Character-follow is retained; head movement changes only the viewpoint.
  Character movement/jump inputs follow viewer heading and diorama rotation.
  2D panels remain upright. The open settings panel stays physically anchored.
  Cylinder edge fade defaults to 1 game unit; zero restores hard clipping.
  Gameplay HUD size defaults to 2x, distance to 2.8 m.
  Decorative clouds are hidden only during VR gameplay renders. Rain-cloud
  puzzles, cloud-save UI, other effects and desktop rendering remain intact.

Passthrough and fallback:
  Diorama.Passthrough=false: OpenVR, black or green opaque exterior.
  Diorama.Passthrough=true: exclusive OpenXR ALPHA_BLEND, after manual restart.
  XR tracking/actions and composition replace OpenVR entirely in this mode.
  Failing/unsupported XR is destroyed before OpenVR fallback.
  Without a usable VR runtime, original desktop rendering remains available.

Quality:
  Profiles Performance / Balanced / Sharp use 0.85 / 1.0 / 1.15 resolution.
  Profiles take effect on the next manual launch; MSAA defaults to 2x.
  HUD capture: 36 Hz. Menus: 72 Hz. UI: 2880x1620 with GPU mipmaps.
  Realtime shadows are disabled in VR and restored in desktop fallback.
  Target: 72 Hz (13.89 ms), requiring actual device CPU/GPU measurements.
  Experimental features may still have rendering, input or performance issues.

Diagnostics:
  Runtime log: BepInEx/LogOutput.log.
  Cylinder probe 0: Normal; 1: Unclipped passes; 2: Unlimited; 3: Neutral matrix.
  Probe choices are temporary. Diagnostic shader/constant dumps are not eye images.
  Logs and dumps may contain private paths or proprietary game data.
  Do not publish raw diagnostics, saved configurations or game assets.

Uninstall:
  Close QV, then run uninstall.bat from the installed overlay.
  It removes only the owned QVVR plugin/configuration, not shared loader files.
