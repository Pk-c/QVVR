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
.\tools\test-intro-visuals.ps1
.\tools\test-ui-effects.ps1
.\tools\test-level-intro.ps1
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
Intro visual tests execute the actual compatibility source with headless API
doubles: cached hub dolly, original-distance recovery, dimmer enabled-state
restoration, live fade alpha preservation, exception/reset/shutdown cleanup and
no object search from hot methods.

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
9. **Stereo selections:** title stays 2D; hub/costume/map Enter/Exit switches reliably
   even if injection occurs after initial Enter. No cylinder, saved world scale,
   grip placement or passthrough. Models and camera-space UI must stay visible;
   verify framing/comfort, confirm/back/navigation, UI panels, menu 2D recovery,
   transition into/out of levels, F7/F8 and unknown-scene fallback. Walk through
   the hub that opens costumes and return from costume/map selection: all three
   must stay stereo. Change gameplay HUD size/distance; these screens must share
   those values, upright lagged follow and HUD capture cadence. Turn off stereo
   menus to restore independent 2D menu panel settings and capture. Compare 2D/3D
   CPU/GPU samples at 72 Hz; sparse samples are not stable averages.
   The hub should appear closer without shifting costume/map framing; compare
   `VR.IntroHubDistanceScale=0.35` and `1`. Move the head: preserve stereo/IPD.
   On the map screen, only LobbyDim should disappear in VR; verify labels,
   confirm/back and level transitions. With stereo disabled, retain the dimmer.
10. **Closer entry:** short saved reach no longer expands to the old diameter
    threshold; preserve X/Y/orientation while applying the entry size/depth
    multipliers to the saved base. Test tall/rotated/very small dioramas for
    valid starting clearance.
    Base entry remains 1.2 m forward and 0.45 m below; default entry multipliers
    0.8 (distance) / 0.85 (size) make it closer and give a 1.36 m diorama. Stay
    outside the physical cylinder. This also applies to existing saved layouts.
    Test ten entry/recenter/save cycles: size/depth must not repeatedly reduce.
    Base height remains 0.45 m below eyes, unless physical bounds require more
    clearance. Verify old untouched defaults migrate; saved custom base layouts
    stay intact and restore prior framing when both multipliers are 1.

Before the hub/dimmer corrections, a Frame `3D-menu` sample recorded main-render
enqueue CPU 3.62 ms, eye/UI/copy GPU 7.45 ms and XR preparation/wait 19.86 ms.
These are sparse, partial-path samples, not whole-frame times or proof of steady
72 Hz; repeat CPU/GPU measurements after manual deployment/testing.

11. **UI sharpness A/B:** compare `VR.UiTextureScale=1.5` (2880x1620) and `1.75`
    (3360x1890), manually restarting each time. Keep `UiQualityRevision=1` after
    the initial migration so rollback is not overwritten. Retain the same saved
    HUD size/distance, level, viewpoint, eye scale/MSAA and 36 Hz capture. Test
    stationary glyph contours, small head-motion shimmer, transparency and
    confirm/back interactions. Log CPU and delayed GPU samples at 72 Hz; do not
    infer total frame cost from the 36.1% increase in UI capture pixels.
    This first test deliberately changes no alpha shader, anisotropy or global AA.
    Pre-test Frame gameplay samples at UI scale 1.5: enqueue CPU 5.21-7.73 ms,
    eye/UI/copy GPU 6.55-7.35 ms (five sparse samples). They are not averages,
    whole-game CPU timings, or proof that later 1.75 captures meet the budget.
    Metadata confirms the current Sprites/Default panel uses One / OneMinusSrcAlpha
    blending; capture/composition alpha behavior needs a separate controlled
    investigation if supersampling alone does not resolve the glyph contours.

## Performance

12. **HUD layout inset:** test 0/12/25/36/45% and repeated menu changes. Corner controls
    move inward; centered groups stay centered, text/widget local scale remains
    unchanged, nested anchors are not inset twice. Verify game-side layout updates,
    dynamic UI, pointer/controller navigation, flat/title recovery and shutdown.
13. **Passthrough sprite alpha:** check the common fairy/papillon body and wings
    against camera passthrough, opaque terrain and the cylinder fade edge. Verify
    collectible/game behavior, source-camera blend restoration and cached material
    count. Compare OpenVR black/green fallback. Test additive sparks/glows with
    black RGB but texture alpha=1: invisible pixels must not form opaque rectangles,
    while visible emission retains RGB and gains bounded coverage in the existing
    XR copy. Check linear/gamma color, Y flip, MSAA, clipping, depth occlusion and
    return to opaque selection menus. The synthetic zero-alpha depth fixture checks
    1024 pixels; additive/feather hooks have zero C++ allocations over 896 warmed
    synthetic frames. These do not replace headset CPU/GPU measurements.

Before these corrections, four sparse Frame gameplay samples recorded enqueue
CPU 3.88-9.96 ms and eye/UI/copy GPU 6.27-6.74 ms; not averages or full-game CPU
frame times. Compare equivalent views/settings after manual deployment.

## Performance measurement

14. **First-level opening:** enter `1_1` with the intro not already watched.
    Verify flat cinematic camera framing, letterboxing/dialog/skip UI, pause and
    skip, then automatic stereo gameplay and saved front placement. Grips must
    not manipulate the diorama while flat; normal confirm/back remain available.
    Already-watched/retry and other scenes must remain unaffected. Test injection
    during the timeline, source-camera changes, scene exit and desktop recovery.
    RGB-only capture avoids original unused alpha=0 erasing the movie. It creates
    one cold 1920x1080 mipmapped target on first use, not another render/copy pass;
    RGB111110Float is preferred, RGB565 is the lower-precision fallback. If capture
    fails, normal VR remains active. Record `flat-intro` CPU/GPU samples at 72 Hz.

## Performance target

Run `tools/test-vr-screen-fade.ps1 -GameDir <local-QV>` for actual production
fade state/source culling/target+matrix cleanup and synthetic premultiplied alpha
math, plus compiled post-HUD/resolve ordering and read-only Cloud/Exit metadata.
These API doubles are not a GPU or headset image test. Placement tests cover
entry multipliers, gain bounds and 100 non-compounding save/entry round-trips.

On Frame, test hub pause/options/achievements at scale 2 and its dedicated
HubPauseDistanceMeters default 1.2 m, adjusting 0.6-3 m live in VR settings, with hub
World, map/costume and gameplay pause unchanged. Select a level: no rectangular
fade edges should appear when looking around; both eyes/HUD/passthrough fade
together, including Loading fade-in/out and final gameplay fade-in. Check back/
cancel, repeated loads, overlay focus loss and VR/desktop toggle. Confirm source
UI culling restores, original game input works and no opaque black remains.
Compare CPU/GPU timings at 72 Hz during fade and steady state. At opacity 0 there
is no extra draw; during fade there is one full-eye quad per eye, no new target.

## Stationary-world judder and near-entry regression

Before these fixes, ten sparse Frame gameplay samples at Sharp eye scale 1.15
and 2x MSAA recorded eye/UI/copy GPU 7.89-17.02 ms; six exceeded the 13.89 ms
budget. Main-render enqueue CPU was 4.74-7.60 ms, excluding earlier game Update.
These are isolated delayed query samples, not averages, complete frame times
or proof that missed frames are the only cause of the reported stationary-world
shake. User reported stable passthrough while the diorama trembled at rest.

Test exclusive XR cap 1.0 versus off (0), with manual relaunch, identical scenes
and slow physical head translation/rotation around an idle character without
grips. Record actual dimensions, GPU/CPU timings and queued/busy/miss counter
deltas, plus perceived jitter; do not infer FPS from cumulative counters alone.
HUD capture dimensions must stay unchanged; final eye sampling can be less
supersampled. OpenVR profile sizes must remain unaffected. Verify physical
stereo/IPD, canted eyes, recenter, tilt and player-follow after direct eye mapping.

Small cylinders must no longer be pushed to a 1 m entry: expect bounding-sphere
radius + 8 cm, minimum 0.35 m, retaining valid saved depth outside that bound.
Check a rotated 0.6 m cylinder and tiny/large cylinders, manual distance down to
0.25 m, both-grip placement and non-compounding saved entry gains. Production
math tests cover raw tracking/world round-trips at units 1, 70 and 1000; compiled
guards verify exact runtime eye snapshots and dedicated pause-distance routing.

Run `tools/test-render-corrections.ps1` (optional `-GameDir`) for actual production
anchor/button/overlay behavior and compiled render order/lifecycle/game-hook
checks. These API-double/IL checks do not prove on-headset depth, hair stability
or controller bindings. The allocation audit covers all new hot helpers.
`tools/test-character-visuals.ps1` exercises the production player-only culling
cache, preserving disabled/inactive models, live game changes, costume reparent
and root replacement, with restore/cold-only IL guards. AnimationModule is a
compile-only ignored Unity dependency, never packaged or committed.

Frame acceptance after manual deployment: start New Game and walk/look around
in both Opening/Opening2 and the first-level intro
and confirm the screen stays fixed while the movie animates; recenter and skip.
Only the stereo costume-access hub should have HUD scale 4, with unchanged
distance; maps, actual costume selection and gameplay retain saved HUD scale.
Walk/jump with each costume and check hair is smooth without freezing. Test
looking away/returning, tilt/scale changes, tracking loss and VR/desktop toggle;
the previous camera-distance hair hook is removed. Put the
diorama in front of the HUD and verify HUD/settings draw above terrain, caps and
selection scenery with passthrough alpha intact. Test either/both index triggers,
release edges, A/B, menu/cinema confirm, grip suppression and focus recovery.
Compare CPU/GPU times at 72 Hz, especially unclipped and stereo selection modes
which now have a panel-only overlay pass; no eye texture CPU readback is added.

Target 72 Hz: 13.89 ms. Record CPU and GPU frame times, actual eye dimensions,
reprojection/drops and artifacts for title/menu, typical gameplay, the heaviest
visible room, transitions and a sustained thermal session. Compare identical
settings and scenes with the menu open/closed and features enabled/disabled.
Record averages and representative peaks/percentiles where available. Five-second
log samples are isolated diagnostics, not statistical performance summaries.

## Performance pass validation

Run `tools/build.ps1`, `tools/test-performance.ps1`, `tools/test-comfort.ps1`,
`tools/test-liquid-depth.ps1`, `tools/test-character-visuals.ps1`,
`tools/test-render-corrections.ps1`, and `tools/test-shader-clip.ps1`.
The performance fixture executes production bounds/visibility, liquid, shared
cap-buffer unions and UI invalidation policies using API doubles. The D3D11 WARP
cap test verifies identical expected pixels with bounded pruning, plus the
unbounded fallback, forward/reversed Z, MSAA, instancing and hot C++ allocations.
Managed IL guards include all new hot methods, direct HUD depth clear/draw,
clip-volume integration and finally-based state restoration. These are NOT
Unity/headset rendering or throughput benchmarks.

Regression: a TMP-like Graphic with throwing virtual material/defaultMaterial
getters is never queried, inactive or active. Unsupported graphics retain normal
capture cadence; a failed cache releases callbacks and stays disabled across
scans. A compiled catch guard prevents optional cache discovery from killing the
maintenance coroutine (which also refreshes the gameplay target and materials).

Independent `[Performance]` rollback flags (default true):
`CullOutsideDiorama`, `AdaptiveUiCapture`, `DirectHudOverlay`.
Set a flag false in the config while QV is closed, then start QV manually for a
controlled comparison. `BlackCutSurfaces` remains the separate cap-effect switch.
`DetailedGpuTimings=false` is the default; enable it before a manual launch to
log delayed per-pass GPU samples every five seconds. Keep it identical in A/B
comparisons. Preserve eye resolution, HUD resolution/cadence, cylinder size,
viewpoint, scene and thermal state. CPU enqueue time is partial, not full-game
CPU time; never add it to GPU time. Record CPU and GPU times at 72 Hz.

Frame acceptance: compare a heavy room and a water/ink scene with each flag
disabled/enabled independently, then together. Walk, jump, orbit, move/rotate/
resize/tilt the cylinder, cross its boundaries, recenter, change levels, toggle
VR/desktop and check fallback/tracking loss. No missing cliffs, buildings or
caps; boundary fade unchanged; water/paint correct in each eye. Watch objects
entering from outside and moving platforms. Verify UI text changes, counters,
animated icons, custom materials, nested canvas visibility, popup creation,
pause/achievements, ancestor CanvasGroup fades and cinematic skips. Confirm HUD
and settings always cover terrain, correct Y orientation, alpha/passthrough and
VR transition fades. No frozen UI or hair regression. If any scene fails, keep
its corresponding switch off pending a targeted fix.

Counters report exterior meshes omitted, liquid depth requirements/eye counts,
HUD captures/reuses, bounded static buffers and cumulative pruned cap replays.
Shared or moving buffers may legitimately prevent cap pruning. Geometry
submission and UI snapshot checking add CPU work; keep only changes that improve
measured Frame timing. Do not claim a speedup from synthetic correctness tests.

## Reporting safely

Report software versions, generic hardware model, settings and summarized timings.
Do not publish raw logs, runtime configurations, crash dumps, game assets or shader
captures. These can contain personal paths, account/device identifiers or
proprietary data. Redact before sharing any minimal excerpt.
