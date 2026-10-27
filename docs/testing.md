# Testing

Use PowerShell 7 and the local, ignored dependencies described in the README.
Run the canonical build after source changes:

For a complete local candidate check, `tools/verify-release.ps1` runs the build,
every test script in its own process, and the working-tree publication audit.
Private reports remain under ignored artifacts. This does not deploy or publish,
and hardware acceptance gates below remain mandatory.

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
.\tools\test-level-entry.ps1
.\tools\test-settings-menu.ps1
.\tools\test-openxr-math.ps1
.\tools\test-openvr-timing.ps1
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
8. **Black caps (reference profile enabled):** A/B the config flag, walk around cliffs and rotate/
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
   those values and upright lagged follow; their UI captures at the 72 Hz menu
   rate. Turn off stereo menus to restore independent 2D menu panel settings. Compare 2D/3D
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

11b. **HUD compositor layer (Frame):** with `VR.CompositorHudLayer=true`, check
    dialogue/counter text sharpness against `false`, HUD placement and follow lag,
    passthrough edges, the settings menu (in-eye HUD below it), screen fades and
    scene changes. Diagnostics log `HUD compositor layer: status=1, active=True`.
    Compare GPU HUD L/R (expected ~0 while active) and cadence at 72 Hz.
    `tools/test-openxr-backend.ps1` covers the quad, mip copy, versioned reuse and
    runtime refusal on a fake runtime only; legibility needs the headset.

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
HubPauseDistanceMeters default 1.2 m, adjusting 0.6-3 m through config, with hub
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

Additional sector/cadence checks: `tools/test-sector-cinema.ps1 -GameDir <QV>`
checks production movie lifecycle logic plus read-only installed hook metadata;
`tools/test-frame-pacing.ps1` checks interval/gap/percentile/queue/reset policies
and hot native allocations. Clear a sector, verify its movie is on a stationary
flat panel (also while turning/tilting the head), pause/skip/finish it, then
verify restoration of the original stereo hub/menu and normal subsequent levels.
Test late injection during a movie and toggling stereo selection menus off.
For jitter comparison, record separate idle/orbit and walking windows, at the
same scene/scale/caps settings, without grips or the settings menu. Compare
submission p95/max/long gaps and queue age to GPU time, and ungrabbed pivot vs
placement steps. Walking pivot motion is expected. Busy Unity iterations alone
are not displayed frame drops. Sector/movie and stability diagnostics still need
Frame visual/timing validation; no automatic launch is authorized by these tests.

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
getters is never queried, inactive or active. Inactive/disabled unknown graphics
no longer force continuous capture; active unsupported graphics retain normal
capture cadence. Dynamic test types in a separate Unity.TextMeshPro assembly
exercise the production cold delegate binding, including null shared materials,
shared material/shader replacements and time-driven full-SDF UV scrolling. Known
static TMP text can reuse its capture, while dirty callbacks and CanvasRenderer
color/alpha tweens invalidate it. With `-GameDir`, the performance test also
verifies both installed TMP shared getters are direct, non-cloning field reads.
A failed cache releases callbacks and stays disabled across
scans. A compiled catch guard prevents optional cache discovery from killing the
maintenance coroutine (which also refreshes the gameplay target and materials).

Independent `[Performance]` rollback flags (default true):
`CullOutsideDiorama`, `AdaptiveUiCapture`, `DirectHudOverlay`.
`LiveCapBounds` independently controls the new ordinary-mesh cap pruning (requires
CullOutsideDiorama). `PostSubmitMaintenance` controls moving cold maintenance
after stereo enqueue. Both default true and can be compared independently.
Set a flag false in the config while QV is closed, then start QV manually for a
controlled comparison. `BlackCutSurfaces` remains the separate cap-effect switch.
`Diorama.CutSurfaceMode` (`Auto`, `Exact`, `BackFace`) chooses the cap method;
the `black caps mode` log line shows the effective mode, the setting and the
number of back-face eyes. Compare `Exact` and `BackFace` on the same level for
cut-edge visuals and GPU total (reference heavy level: about 10 ms vs 6.6 ms).
In a Debug build (`tools/build.ps1 -Configuration Debug`),
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
HUD captures/reuses and continuous-fallback reason (static/failed/material/Animator),
bounded static buffers, live skip-buffer count and cumulative pruned cap replays.
Live cap tests include moving/shared contributors, invalid bounds, enclosing
terrain, mesh replacement/recovery and clear/unpin lifecycle. WARP compares the
same cut pixels with live skips, empty skips and a stale registry generation,
checks that caller storage is copied, and verifies actual replay-count reductions.
Compiled IL checks cap snapshot ordering and the reused end-of-frame yield before
cold scans. No speedup follows from these correctness checks alone.

Use the previous Frame run as the baseline: HUD captures/reuses were 9243/0,
bounded static buffers and cap skips were zero. In steady gameplay, focused
submission windows had p95 buckets around 17-18.5 ms and maxima around 30-44 ms,
despite an idle ungrabbed diorama transform remaining stationary. These are
submission cadence observations, not compositor display drops. For the next
manual test, verify UI reuse/live cap skips actually increase, compare CPU/GPU
times and submission p95/maximum at 72 Hz, and record the post-submit maintenance
CPU maximum. Check idle/orbit separately from walking and scene transitions.
Shared or moving buffers may legitimately prevent cap pruning. Geometry
submission and UI snapshot checking add CPU work; keep only changes that improve
measured Frame timing. Do not claim a speedup from synthetic correctness tests.

## Portable input regression checks

OpenVR cadence checks: tools/test-openvr-timing.ps1 executes the production timing
policy and renderer query helpers with API doubles. It covers 60/72/80/90/120/144/
240 Hz, vsync subtraction, refresh changes, unavailable properties, invalid/stale
values, bounded/current-pose fallback, XR isolation and warmed zero allocations.
Compiled checks keep property reads off the per-frame/per-eye path and retain the
predicted pose in native submission. It also runs test-controller-input.ps1
-Backend OpenVR in a separate process, exercising the entire input fixture through
the OpenVR branch, including disconnect/focus/menu and both controller presets.
The default controller fixture still uses -Backend OpenXR for Frame regressions.

Pending PCVR hardware gate: Quest 3 through Virtual Desktop with SteamVR, then
Steam Link separately. Use Passthrough=false, FaceButtons, compositor pacing and
native Windows -force-d3d11. Verify both eye projections/IPD, orientation, scale,
head translation, two-hand placement, A/B/X/Y/triggers/stick clicks, right-stick
dead zone, menu/dialogue/pause/movie transitions, focus loss and reconnection.
Check black/green exterior, cylinder fade/caps and no-runtime desktop recovery.
Test a refresh change when supported, recording the selected runtime frequency
and actual CPU/GPU timings (e.g. 90 Hz has an 11.11 ms frame budget, 120 Hz 8.33 ms).
Neither the source audit nor passing API doubles proves wireless latency or
physical controller-role mapping. Do not mark either streaming route validated
until tested with the exact candidate; do not auto-start QV or change system
OpenXR/runtime settings as part of these tests.

Compact settings checks: run tools/test-settings-menu.ps1 after building. It
executes the production menu navigation/adjust/action/reset/text methods with API
doubles, verifies the exact 15-item whitelist/order, wraparound, toggles, actions,
absence of edits to hidden settings, and reset via ConfigEntry default metadata.
It compares Plugin bind defaults against the package sample and checks compiled
Adjust/RefreshText exclude removed controls. Existing user values must not be
changed on menu open/update. The reference profile is the last backed-up Frame
config from 2026-10-22; round float accumulation noise to 1.8 for panel/HUD size.
It contains numeric/boolean presentation values only, not personal data or saved
level placement. Verify a current device config before a later profile refresh.

Frame acceptance: verify all 15 rows fit the panel, stick selection
wraps without invisible rows, A invokes recenter/restore/place and toggles only
void color/passthrough/clouds, and B/both stick clicks still close and save.
Confirm two-hand and stick placement still work with the menu closed. Hidden
config values must survive deployment/open/close, while explicit restore uses
the new reference defaults (-16 degree tilt, 1.8/1.5/0.6 flat panel, 1.8/1.4 HUD,
29% inset, 1.2 m hub pause, caps/stereo selections/cylinder on, normal probe).
Other headset framing and cap GPU cost remain hardware QA; no extra render pass
or per-frame layout work is introduced by this menu cleanup.

Standard level-entry checks: run tools/test-level-entry.ps1 after the canonical
build; optional -GameDir verifies both native 5.5-second fade branches and their
dialog/control callbacks in the installed assembly, read-only. The fixture runs
the production policy and transpiler with API doubles, executes emitted helper IL,
and checks callback/instruction preservation, both branches, exact fade selection,
layout rejection, live rollback, cleanup and failure fallback. Compiled guards
require enabled/initialized independent gameplay VR outside fixed cinema; comfort
tests audit the helper for managed allocations. This is not a Unity Mono test.

Frame acceptance: enter several levels, including one with tutorial and one
without, retry and return from a genuine first-level intro. Confirm the usual
blank pre-dialogue interval is about 1.5 s after GameStart, dialogue appears once,
movement is enabled normally, tutorials/save flow survive, and movie playback is
not skipped. Compare Comfort.LevelEntrySeconds=5.5 and F8 desktop fallback on a
subsequent level entry. Test normal cinematic completion and skip separately.
Do not shorten an already-running tween or manually invoke its callback. Record
CPU/GPU frame times at 72 Hz; the headless test does not establish hardware timing.

Run `tools/test-controller-input.ps1` (optionally `-GameDir` for read-only installed
QV metadata checks), `tools/test-render-corrections.ps1`, and `tools/test-comfort.ps1`
after the canonical build. The controller fixture compiles the actual bridge,
configuration and policies with API doubles. It checks both presets through real
polling/query code, press/hold/release edges, UI scope nesting, custom gameplay vs
menu remaps, held-confirm suppression after resume/dialogs, trigger-chord ownership,
stick separation, Steam Input mirror replacement, mixed-mode/unknown-action
fallback, focus/controller loss/reconnect, VR settings, grips and release. It
measures zero warmed managed allocations for 512 polling/button/axis iterations;
this .NET test is not a Unity/Mono or headset timing benchmark. IL allocation
guards cover the new policy/query/snapshot helpers. Installed metadata guards
verify the game's semantic actions and known UI query methods.

Regression cases also cover closed-dialog confirm polling without a gameplay
input latch, open-dialog consumption, recovery while walking without recentering,
delayed natural ButtonUp delivery, and bool/ObscuredBool getter IL emission.
Installed metadata checks verify both dialogue getters. Placement tests cover
40% dead-zone neutrality, smooth onset, full deflection, axis switching hysteresis
and invalid samples; navigation axes remain independent. These API-double tests
do not execute the patched game under Unity Mono.

Frame manual acceptance: verify right A primary/confirm, B secondary/back without
pausing, left D-pad up pause, left D-pad down swap, right trigger dash, left trigger
camera and both triggers Load. Confirm the trigger chord does not also keep dash
or camera active. Use either stick in pause/options/dialogs; outside UI, only the
configured locomotion stick should move the character. Enter/exit dialogs, pause,
cinematics and QVVR settings with controls held; release/repress must recover input
without a leaked action. Test the interactive 3D intro hub and page triggers too.
Keep grips reserved for placement and verify desktop/focus-loss fallback. Change
individual bindings with QV closed and relaunch manually; preserve saved comfort
and placement settings.

Right-stick placement: verify left/right rotates about the diorama center (not
the viewer), forward approaches and backward retreats at unchanged height/size.
Walk around the placed world and repeat; direction must remain relative to the
current viewer. Check UI navigation, pause, focus return, cinema and two-grip
priority without accidental placement or mirrored game camera input. Speeds are
configured in physical meters/second and degrees/second in [Input]. Release the
stick and reload a level to verify sparse saved placement. Compare idle and
continuous-stick CPU/GPU timings at 72 Hz on Frame; automated tests are not
hardware validation. The spatial fixture checks actual placement math including
distance limits, existing out-of-range grab positions, scale independence and
stall/invalid-input safety; comfort IL guards cover the new hot methods.

For the A-lock regression, hold the walking stick and repeatedly tap/release A
with no dialogue open, then repeat after opening/closing dialogue and pause.
Movement must recover without releasing the stick; a held confirm must not leak
into gameplay. Temporarily inactive dash/camera/load polling must still receive up.
For placement, rotate with a small diagonal and verify no approach/retreat occurs;
deliberately switch toward the vertical axis and verify smooth translation.

Water color trial: run tools/test-liquid-depth.ps1 and tools/test-comfort.ps1.
The fixture checks exact material selection, shared-material deduplication, live
foam restoration, failure cleanup and exclusions; compiled IL checks verify the
override surrounds gameplay stereo rendering. Inspect a local scene read-only
with tools/inspect-water-shading.py if further shader diagnosis is needed (local
UnityPy dependency required; do not commit extracted game assets/disassembly).
Compare WaterFoamFix=true/false in the same water level from above and the side,
with LiquidDepthFix unchanged. Verify original blue/depth shading, acceptable foam
removal, ink/fog/effects, both eyes, transitions and desktop fallback. Record CPU
and GPU times at 72 Hz; tests alone establish neither water correctness nor cost.

For another headset/controller, first verify the runtime's normalized role mapping
and select FaceButtons or TrackpadWands. Test every configured action, tap/hold/up,
trackpad/stick axes, grip gestures and settings access on physical hardware.
Wand defaults deliberately leave optional game camera/menu page buttons unbound;
confirm navigation remains usable or assign explicit page buttons for the game
screen in question. Preset tests alone do not establish device compatibility,
OpenXR passthrough support or acceptable Frame CPU/GPU timing.

## Dialogue HUD validation

Dialogue HUD checks: after the canonical build, run `tools/test-dialog-hud.ps1`
(optional `-GameDir` verifies installed QV dialogue projection metadata) and
`tools/test-comfort.ps1`. The fixture executes production layout code through
nested/rotated/scaled parents with off-center pivots, actor motion, hidden,
disabled, reparented and destroyed UI, repeated prepare/restore, setter/render
failure cleanup and zero warmed managed allocations. Compiled IL verifies
centering around the single existing UI capture, finally restoration, original
layout cache snapshot order, cold discovery and cinema/flat gating.

Frame visual acceptance: open dialogue while facing away from the original game
camera, then walk around and rotate/resize/translate the diorama. The box should
open centered in front, remain on the upright viewer-following HUD with its usual
lag, preserve text/portrait/popup/advance animations, and draw above the world.
Check both speakers, intro-hub dialogue, repeated open/close, pause/scene changes,
flat cinematics and desktop fallback. Compare UI capture/reuse and CPU/GPU timing
at 72 Hz with `Comfort.CenterDialogs` on/off. Correctness tests do not establish
headset readability or a measured performance gain.

## Low-overhead maintenance validation

Run the canonical build, `tools/test-performance.ps1`, `tools/test-comfort.ps1`,
`tools/test-native-load.ps1`, `tools/test-shader-clip.ps1`, and the dialogue,
controller, intro-menu and first-level/sector cinema regressions. The UI fixture
checks unchanged subscription retention, removed/new widget lifecycle, continuous
capture without tracking, recovery probes, immediate rollback, disable/scene
cleanup and zero warmed managed allocations on the suspended path. The WARP shader
test runs in separate processes with diagnostics enabled and disabled. It verifies
identical cylinder/alpha/feather/cap correctness and zero hot C++ allocations in
both modes; the disabled mode also asserts zero diagnostic staging buffers and
zero cached diagnostic shader bytecodes. No real eye textures are read back.

On Frame, keep the same scene/view/resolution and compare
`LightweightUiMaintenance=true/false`. Check dynamic dialogue, hidden/reopened UI,
animated materials, pause/options, new widgets and scene changes; suspension must
retain full capture cadence, never freeze text/fades. Summaries report suspension
and continuous reason alongside capture/reuse counts. Compare maintenance elapsed
time, separately reported log batch time, cadence p95/maximum and GPU samples.
Measure with a Debug package (`tools/build.ps1 -Configuration Debug`, then deploy):
enable `DiagnosticsEnabled=true` (manual restart). The Release package has these
settings and their code compiled out and writes no periodic logs. `DetailedGpuTimings=true` adds per-phase
GPU timestamps to the same five-second output. Test menu/cinema event hooks,
late injection, paused/skipped movies and delayed camera activation with the idle
one-second recovery fallback. Preserve original game files and deploy-only policy.
No performance gain is established until physical Frame A/B measurements pass.

## Full-world VR mode

`tools/test-full-vr.ps1` executes production `FullVrViewState` and `SpatialMath`
using the shared Unity math doubles. It checks normal-scale spawn, physical head
translation and stereo IPD, yaw about the head after room-scale walking, upright
forward/back travel, player-follow without double translation, viewer-relative
character input/source-camera yaw cancellation, invalid inputs/stalls, refresh-rate
independence and separate diorama/free-camera lifetime. Warmed state updates and
eye mapping must allocate zero managed bytes. Compiled renderer guards verify
eye/rig/input/reset wiring and mode guards, while `test-comfort.ps1` includes all
new hot methods in its allocation IL audit. The clipping truth table excludes
panels and disabled dioramas regardless of passthrough composition.

Hardware acceptance remains pending: switch modes repeatedly on Frame OpenXR
alpha blend and Quest 3/Virtual Desktop SteamVR/OpenVR, verify both eyes, restored
miniature pose/size, HUD/menu anchors, cinematics, focus loss, recenter and scene
entry. Walk around physically before turning with the right stick (no orbit or
scale change), then combine player follow with camera navigation. Confirm pause,
dialogues, two-grip gestures and no-runtime desktop fallback remain correct.
There is no collision avoidance in free-camera mode. Compare CPU/GPU times at
72 Hz in the same scene; summaries label `full-vr` and `diorama` separately.
Automated checks do not establish normal-scale comfort or whole-level GPU cost.

## Installer safety fixtures

`tools/test-installers.ps1` exercises the actual archive validator, PC uninstaller
and Frame orchestration with an ADB double. It covers package allowlist parity,
hash corruption, traversal/case/unexpected/symlink ZIP entries, Windows junction
rejection, running-game refusal, WhatIf, backup/settings/other-mod preservation,
idempotent uninstall, optional config removal and check/upload/install ordering.
Run in Windows PowerShell 5.1 with process-scoped ExecutionPolicy Bypass and in
PowerShell 7. No administrator rights or permanent policy change are needed for
the distributed scripts. Sandbox restrictions may require an unsandboxed fixture
run to create test junctions or start Git Bash; all fixtures stay under artifacts.

`tools/test-frame-overlay.ps1` executes the production POSIX helper in Git Bash
against fake QV folders. Only the allowed storage-prefix gate is translated to
the fixture root; ADB, pgrep and bsdtar are boundary doubles. It tests fresh/update
installs, CRLF checksum manifests, preflight conflicts before overlay writes,
process-query errors/running QV, linked content, backups and uninstall/reinstall
settings behavior. No real Frame or game is changed. USB authorization/transfer,
on-device tools, permissions and interruption recovery still need Frame acceptance.

## Reporting safely

Report software versions, generic hardware model, settings and summarized timings.
Do not publish raw logs, runtime configurations, crash dumps, game assets or shader
captures. These can contain personal paths, account/device identifiers or
proprietary data. Redact before sharing any minimal excerpt.
