# Testing

Use PowerShell 7 and the local, ignored dependencies described in the README.
Run the canonical build after source changes:

```powershell
.\tools\build.ps1
.\tools\test-comfort.ps1
.\tools\test-diorama-view.ps1
.\tools\test-spatial-placement.ps1
.\tools\test-cloud-filter.ps1
.\tools\test-liquid-depth.ps1
.\tools\test-intro-menus.ps1
.\tools\test-openxr-math.ps1
.\tools\test-native-load.ps1
.\tools\test-native-pose.ps1
.\tools\test-openxr-backend.ps1
.\tools\test-shader-clip.ps1
```

Tests cover comfort/input helpers, compiled render-event ordering, hot-method
allocation checks, physical layout/movement math, cloud restoration, XR ABI,
pose-queue threading, fake-runtime XR lifecycle and synthetic D3D11/WARP clipping.
The spatial tests execute production math/state with headless Unity math doubles.
Synthetic GPU fixtures may read their own results, never game eye textures.
Cap fixtures exercise perspective/orthographic entry depth, side/height surfaces,
1x/2x MSAA, alpha/opaque-green exterior, enabled/disabled mode, indexed/instanced
draws, target restoration and warmed hook allocations. Closed synthetic solids
do not prove that actual QV terrain is watertight or batch buffers are registered.

An optional `-CapturedShader` argument exercises a locally captured shader;
captured bytecode is proprietary game data and must remain outside Git.
Offline tests do not validate headset comfort, runtime compatibility or performance.
Optional `test-intro-menus.ps1 -GameDir <local-QV-directory>` verifies game state
hook metadata read-only, without loading/executing game code or exporting its IL.

## Manual headset gates

Deploy only with QV closed. Do not launch or terminate it through deployment;
the tester starts QV manually.

1. **Startup/fallback:** injection with normal launch, VR unavailable, F8 desktop
   recovery, cleanup and unchanged original game files.
2. **Stereo:** correct eye orientation, IPD, asymmetric FOV, head rotation/translation,
   level transitions and recentering. No CPU eye-texture readback.
3. **Diorama:** terrain/building boundary clipping, transparent exterior with XR,
   black/green OpenVR fallback, edge fade and independent HUD rendering.
4. **Placement:** first-level visible fit, saved layout reuse, walking around,
   two-hand xyz movement, physical size, wrist/baseline rotation, release/regrab,
   tracking/focus loss and front-placement recovery.
5. **Input/UI:** viewer-relative movement and jumps from every side and after
   diorama rotation; unchanged menus; upright 2D panels; anchored settings panel;
   no input leakage during manipulation/menu use.
6. **Clouds:** decorative clouds/shadows hidden only in VR gameplay; rain-cloud
   puzzles, unrelated effects and desktop rendering preserved.
7. **Liquids:** water, ink/pots, fog and RainCore from multiple viewpoints, both
   eyes, following level transitions and desktop/VR toggles. A/B LiquidDepthFix;
   compare CPU/GPU times in water-heavy rooms and scenes with no active liquid.
8. **Black caps (off by default):** enable in menu, walk around cliffs and rotate/
   resize the diorama; check sides/top/bottom, fade, depth, and empty passthrough
   regions. Buildings inside the cylinder must stay unchanged. Check indexed
   batch registration and cumulative replay/composite counters in sparse logs.
   Open meshes and camera-inside-solid cases are experimental limitations.
   Compare caps off/on at 72 Hz before making them the default.
9. **Stereo selections:** title stays 2D; costume/map Enter/Exit switches reliably
   even if injection occurs after initial Enter. No cylinder, saved world scale,
   grip placement or passthrough. Models and camera-space UI must stay visible;
   verify framing/comfort, confirm/back/navigation, UI panels, menu 2D recovery,
   transition into/out of levels, F7/F8 and unknown-scene fallback. Compare 2D/3D
   CPU/GPU samples at 72 Hz; sparse samples are not stable averages.
10. **Closer entry:** short saved reach no longer expands to the old diameter
    threshold; preserve X/Y, physical size/orientation and deliberately farther
    depth. Test tall/rotated/very small dioramas for valid starting clearance.

## Performance

Target 72 Hz: 13.89 ms. Record CPU and GPU frame times, actual eye dimensions,
reprojection/drops and artifacts for title/menu, typical gameplay, the heaviest
visible room, transitions and a sustained thermal session. Compare identical
settings and scenes with the menu open/closed and features enabled/disabled.
Record averages and representative peaks/percentiles where available. Five-second
log samples are isolated diagnostics, not statistical performance summaries.

## Reporting safely

Report software versions, generic hardware model, settings and summarized timings.
Do not publish raw logs, runtime configurations, crash dumps, game assets or shader
captures. These can contain personal paths, account/device identifiers or
proprietary data. Redact before sharing any minimal excerpt.
