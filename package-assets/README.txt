QVVR 0.1.0 - Experimental release candidate
================================

Hub/costume/map screens in 001_Intro can render in full stereo without diorama
clipping or passthrough. Title/loading/other states remain 2D. Use 3D costume/map
menus in settings to test it or recover flat capture if framing/transitions fail.
Their UI shares gameplay HUD size, distance, upright follow and capture rate.
Exception: only the stereo costume-access hub uses HUD scale 4. Distances and
the saved normal HUD scale for maps/costume selection/gameplay stay unchanged.
Stereo selections are enabled in the reference Frame profile; config false
restores flat recovery. Other hardware still needs framing/performance checks.
Costume-access hub VR distance retains 35% of original forward depth; set
VR.IntroHubDistanceScale=1 to restore it. Costume/map cameras stay unchanged.
The map LobbyDim is hidden only during stereo eye/UI capture; other fades remain.
Entry base: 1.2 m forward, 0.45 m below eyes. EntryDistanceMultiplier=0.8 and
EntrySizeMultiplier=0.85 make existing/fresh layouts closer and 15% smaller,
subject to size-aware clearance. Base 1.6 m size becomes 1.36 m physically.
Saving inverts entry gains, preventing cumulative shrink/forward drift. Set
both multipliers to 1 to restore previous framing; height/rotation are retained.
Only untouched unsaved old defaults migrate. Saved/custom layouts stay intact.
Saved X/Y, size, rotation and intentionally distant placement are preserved.

Two-hand placement sensitivity: translation 1.15x, rotation 1.10x. Resize and
head tracking are unchanged. LiquidDepthFix adds fresh per-eye depth only for
known active liquid shaders; verify water/ink on the headset.
WaterFoamFix=true experimentally removes the common blue-water material's white
foam during gameplay stereo only, retaining its surface/depth colors and restoring
the live material afterward. Ink/fog/desktop are unchanged. Set false for A/B.
No extra render pass or texture; the visual result needs Frame validation.
Black cut surfaces (experimental) is enabled in the reference Frame profile.
Set Diorama.BlackCutSurfaces=false in the config to disable it. Open meshes
and incomplete native batch registration can limit coverage; extra GPU work.

Copy the CONTENTS of the release PC folder beside QV.exe. Close QV before deployment;
start it manually afterward. Preserve BepInEx/config/dev.qvvr.prototype.cfg
when updating manually. USB/SSH deployment preserves it automatically.
Back up the overlay first; review loader/core files if other mods share BepInEx.
See RELEASE-NOTES.txt for known limits, candidate status and pending Frame checks.
LICENSE.txt and BepInEx/plugins/QVVR/licenses contain the full license texts.
qvvr-files.sha256 lists payload hashes; the adjacent ZIP.sha256 verifies download
integrity, not publisher identity. No game assemblies/assets or user logs/config
are bundled; the supplied config is a clean fresh-install reference template.

Steam launch options for the Windows build on Steam Frame (the SteamFrame USB
installer sets them automatically when Steam CEF Remote Debugging is enabled):
  WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11

Native Windows PCVR (Steam Link / Virtual Desktop): use -force-d3d11, not the
Proton WINEDLLOVERRIDES prefix. Connect the headset/controllers in SteamVR first,
keep Diorama.Passthrough=false and Input.Layout=FaceButtons for Touch-style roles,
then start QV manually. This candidate uses OpenVR through SteamVR, not direct
VDXR or an OpenComposite replacement DLL. Opaque black/green exterior is expected.
Prediction follows the runtime cadence/display delay/vsync instead of assuming
72 Hz. Quest 3 + Virtual Desktop and Steam Link hardware validation is pending.

Controls:
  F7: recenter. F8: toggle VR/desktop.
  [Input] Layout=FaceButtons: A primary/confirm, B secondary/back, Y pause,
  X character swap. Frame XR left D-pad down/up supplies X/Y roles.
  Right trigger: dash. Left trigger: game camera. Both: load (LB+RB action).
  Menu triggers: previous/next page, not confirm. A confirms menus/dialogs.
  Left stick: viewer-relative movement. Right stick: horizontal rotates the
  diorama about its center; forward brings it closer, backward moves it away.
  Cylinder Off: right stick turns the full-scale camera in place and moves it
  forward/back along your upright viewing direction. Left stick still moves Q.
  Height and size stay unchanged. Menus retain stick navigation.
  [Input] DioramaStick selects the placement stick (default Right);
  DioramaStickTurnDegreesPerSecond=60, DioramaStickMoveMetersPerSecond=0.6.
  DioramaStickDeadZone=0.4: 40% placement dead zone with smooth onset. Dominant-axis
  hysteresis prevents small diagonal turn input from also moving the diorama.
  Closed dialogue queries no longer consume gameplay A. UI-confirm suppression
  ends on button release without recentering the walking stick; delayed held-action
  releases remain available when the game resumes polling.
  The old CameraStick setting is ignored; game secondary camera axes are disabled.
  Dialogue boxes are centered in the viewer-following VR HUD; portraits and text
  animation are preserved. [Comfort] CenterDialogs=false restores the original
  layout. Desktop and fixed flat cinematics are unaffected. No extra render pass.
  Comfort.LevelEntrySeconds=1.5 shortens the ordinary pre-dialogue entry fade in
  independent diorama VR (range 1.5-5.5; 5.5 restores native timing). Original
  callbacks still start dialogue/tutorials/controls. Story movies and desktop
  retain their timing; applies at the next entry, not to an active transition.
  Performance.LightweightUiMaintenance=true avoids repeated HUD subscriptions;
  continuous UI keeps full capture rate with a cache recovery probe every 2 s.
  Performance.DiagnosticsEnabled=false uses concise 30 s performance summaries
  without shader dumps. True restores developer diagnostics after manual restart.
  Both stick clicks: open/close QVVR settings.
  Layout=TrackpadWands: right trigger primary/confirm, right application-menu
  secondary/back, left application-menu pause, left pad click swap, left trigger
  dash, right pad click VR settings. Both triggers load. Optional camera/page
  bindings are unbound in this limited-button preset; individual overrides work.
  All actions and stick sources can be rebound in [Input]; Default follows the
  preset, None disables. Existing OpenVR legacy mapping must expose these roles.
  Presets have synthetic tests; other-headset hardware QA is still required.
  ExclusiveVrControls=true prevents Steam Input mirror actions while focused
  VR controllers are available. False restores mixed keyboard/gamepad input.
  Original desktop/no-controller input remains. Grips/system buttons are reserved.
  Menu up/down: select. Left/right: adjust. Closing saves settings.
  Both grips: natural translation, hand-separation size, hand/wrist rotation.
  Release either grip to retain the pose. Right grip alone does not manipulate.
  The settings menu does not pause game simulation.
  Compact menu: tilt, render profile, recenter, restore comfort defaults, cylinder on/off,
  radius/height/center height, void color, passthrough, edge fade, clouds, place in
  front, diorama size, XR eye-scale cap (15 rows). Other settings remain in config.
  Reference defaults: tilt -16 degrees, flat panel 1.8 m wide / 1.5 m away /
  0.6 s follow lag. Existing saved config is preserved; defaults apply to fresh
  configs and the explicit restore-comfort action, never merely opening the menu.

Diorama:
  Cylindrical diorama Off enables experimental full-world VR at 1 game unit/m.
  The camera starts 3 units behind Q, 1.6 units above the player root; follows Q
  but not the animated game camera. Right stick: turn / move forward or back.
  Recenter or Reset camera behind Q restores the starting framing. No camera
  collisions: you can move into geometry. Whole-level rendering may cost more GPU.
  No cylinder/caps/outside-cylinder culling, including with OpenXR passthrough
  enabled. Original game background is restored. Two-grip gestures are inactive.
  Diorama size/placement are preserved for switching back. Cinemas/menus unchanged.
  This new mode still needs headset acceptance on Frame and PCVR.
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
  Gameplay/stereo intro HUD size defaults to 1.8x, distance to 1.4 m (config-only).
  HUD center inset: 29% per edge, config range 0-45% without scaling text.
  Zero restores original anchors; title/flat recovery remains unchanged.
  First-level opening Timeline: flat panel, then automatic stereo restoration
  after completion/skip. Grips are disabled during intro; game controls remain.
  The movie screen stays fixed in physical space; recenter places it in front.
  New Game Opening/Opening2 use the same fixed screen, not their animated camera.
  Hub pause/options/achievements UI alone uses scale 2 and its own live distance:
  Comfort.HubPauseDistanceMeters defaults to 1.2 m, config range 0.6-3 m.
  Map selection: Cloud.Panel's original fade tween drives a full-eye VR fade,
  including HUD and passthrough, through Loading and gameplay fade-in. The 2D
  rectangle is hidden only for capture, with original game state restored.
  HUD/settings draw above scenery using a final depth-only-clear panel pass.
  Manual rendering waits for hair/character LateUpdate; physics stays enabled.
  Only Q's animation/skinning culling is bypassed during VR gameplay. Original
  settings restore on tracking loss/scene change/shutdown; bone physics and
  camera-distance rules stay untouched. Headset hair/performance test required.
  Decorative clouds are hidden only during VR gameplay renders. Rain-cloud
  puzzles, cloud-save UI, other effects and desktop rendering remain intact.

Passthrough and fallback:
  Diorama.Passthrough=false: OpenVR, black or green opaque exterior.
  Diorama.Passthrough=true: exclusive OpenXR ALPHA_BLEND, after manual restart.
  XR tracking/actions and composition replace OpenVR entirely in this mode.
  Fairy texture alpha is enabled only for manual passthrough renders; original
  material blending is restored afterward. Additive black texels no longer add
  opaque quad coverage. Existing GPU copy handles visible emission; no new pass.
  Failing/unsupported XR is destroyed before OpenVR fallback.
  Without a usable VR runtime, original desktop rendering remains available.

Quality:
  Profiles Performance / Balanced / Sharp use 0.85 / 1.0 / 1.15 resolution.
  Profiles take effect on the next manual launch; MSAA defaults to 2x.
  Gameplay/stereo intro HUD: 36 Hz. Flat menus: 72 Hz.
  UI: 3360x1890 (1.75x) with GPU mipmaps; scene resolution is unchanged.
  UI-only sharpness test: +36.1% capture pixels, not total GPU time.
  Old default 1.5 migrates once; custom values are preserved.
  Rollback: VR.UiTextureScale=1.5, keep UiQualityRevision=1, manually restart.
  Realtime shadows are disabled in VR and restored in desktop fallback.
  Target: 72 Hz (13.89 ms), requiring actual device CPU/GPU measurements.
  XR eye scale cap: default 1.0, adjustable/off (0) in settings; manual restart.
  Caps Sharp supersampling to reduce missed-frame judder, preserving the chosen
  profile, OpenVR and HUD capture size (final eye sampling follows the cap).
  Exact absolute runtime eye poses avoid redundant head/calibration round-trips;
  no head smoothing or artificial world lag. Headset jitter fix needs validation.
  Auto entry clearance: cylinder bounding sphere + 8 cm, minimum 0.35 m, no 1 m
  floor for tiny dioramas. Manual distance supports 0.25-10 m.
  Experimental features may still have rendering, input or performance issues.

Diagnostics:
  Runtime log: BepInEx/LogOutput.log.
  Cylinder probe 0: Normal; 1: Unclipped passes; 2: Unlimited; 3: Neutral matrix.
  Probe choices are temporary. Diagnostic shader/constant dumps are not eye images.
  Logs and dumps may contain private paths or proprietary game data.
  Do not publish raw diagnostics, saved configurations or game assets.

Uninstall:
  PC: close QV, double-click uninstall.bat beside QV.exe and type UNINSTALL.
  QVVR is moved into .qvvr-backups for recovery; settings are kept by default.
  BepInEx, winhttp.dll, doorstop_config.ini, game files and other mods are kept.
  Optional: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveConfig
  also backs up/removes settings. Add -WhatIf for a non-mutating preview.
  Frame from PC: run SteamFrame/QVVR-Frame-Setup.bat from the extracted release
  ZIP and choose install/update, launch options or uninstall.
  Needs authorized USB debugging and Android SDK Platform Tools (not bundled).
  Existing settings are preserved; incompatible shared loader files are refused.
