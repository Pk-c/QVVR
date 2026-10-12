# Testing

Use PowerShell 7 and the local, ignored dependencies described in the README.
Run the canonical build after source changes:

```powershell
.\tools\build.ps1
.\tools\test-comfort.ps1
.\tools\test-diorama-view.ps1
.\tools\test-spatial-placement.ps1
.\tools\test-cloud-filter.ps1
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

An optional `-CapturedShader` argument exercises a locally captured shader;
captured bytecode is proprietary game data and must remain outside Git.
Offline tests do not validate headset comfort, runtime compatibility or performance.

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
