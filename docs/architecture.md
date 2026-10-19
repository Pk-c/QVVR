# Architecture

QVVR runs inside QV's Windows x64 Unity Mono process. BepInEx/Doorstop provides
a removable overlay. No original game files or individual shader assets are changed.

## Rendering and runtime ownership

Unity owns persistent D3D11 eye, flat-screen and UI render targets. Manual forward
stereo cameras render gameplay, optionally into multisampled targets followed by
GPU-only resolves. Native graphics events bracket rendering and submission.

OpenVR fallback predicts poses on the main thread, then pairs graphics-thread
WaitGetPoses and Submit. Each stereo pair carries its exact render pose through
a fixed native queue and uses pose-associated submissions.

Exclusive OpenXR waits/begins and captures headset/eye/controller poses before
game Update. Unity renders from that immutable snapshot; graphics events copy
eyes to XR swapchains and end the same frame using ALPHA_BLEND. One in-flight
frame prevents snapshot overwrite. No OpenVR tracking client is initialized
alongside XR. Initialization/session failures clean up XR before OpenVR fallback.

Full-scene selection menus latch an opaque-layer flag with the exact native pose
queue slot. The XR session still ends with ALPHA_BLEND, but that menu projection
layer omits BLEND_TEXTURE_SOURCE_ALPHA_BIT, treating unused original shader alpha
as opaque. Gamma RGB copy uses the existing non-premultiplied decode variant.
Gameplay immediately returns to source-alpha composition; no latest-global scene
flag, texture readback, shader rewriting or parallel XR/OpenVR client is needed.
See [OpenXR layer blending](https://registry.khronos.org/OpenXR/specs/1.0/man/html/XrCompositionLayerFlagBits.html).

## Cylindrical clipping

An early native D3D11 hook caches modified pixel-shader variants in memory.
A fragment's SV_Position is reconstructed through the inverse actual GPU
view-projection into original game cylinder coordinates. Exterior fragments are
discarded before depth/color writes, clipping terrain/buildings across boundaries.
Depth-only draws and opaque prepasses are handled as well.

Cached opaque, straight-alpha and premultiplied/additive variants provide a
smooth inward edge fade. Existing material arithmetic and depth ordering are
retained. UI/settings layers render separately. Unsupported shader cases are
diagnosed rather than silently accepted. No eye texture is read back to the CPU.

Optional black caps use a separate GPU winding/stencil pass. Cold maintenance
registers native index buffers from loaded opaque MeshRenderers, excluding known
liquids, skinned characters, particles and UI. Eligible opaque base/depth draws
are replayed **uncut** with both faces into a private depth/stencil surface whose
depth contains the analytical cylinder entry. Non-zero winding identifies solid
cross-sections, not empty space. A black pass writes actual boundary depth/alpha
at a cached BeforeForwardAlpha camera event or when leaving the eye target.
Opaque ForwardAdd blends must not prematurely finish the winding pass.
Indexed, instanced and
indexed-indirect draws are supported; renderer draws not using a registered
index buffer are deliberately not capped.

Targets are allocated at cold registration only and released on disable/scene
refresh; warmed hooks allocate no C++ memory. All modified graphics bindings are
explicitly restored. Context-state swaps are avoided here because they invalidate
intercepted D3D runtime dispatch entry points. The original inward geometry fade
remains; caps soften their own grazing silhouette. This opt-in prototype assumes
closed, consistently wound solids; open/non-manifold meshes and near-plane cuts
are not generally solved. Verify actual mesh/batch coverage and GPU costs on Frame.

References: [D3D11 depth/stencil](https://learn.microsoft.com/en-us/windows/win32/direct3d11/d3d10-graphics-programming-guide-depth-stencil),
[Unity native index buffers](https://docs.unity3d.com/2019.4/Documentation/ScriptReference/Mesh.GetNativeIndexBufferPtr.html).

## Physical placement

Placement state stores center P, rotation Q and size S in tracking-space meters.
For game cylinder center C and effective units U/S, the inverse view is:

`gameEye = C + inverse(Q) * (trackingEye - P) * U/S`

Both eyes share C, P, Q and S. C follows character translation while P is not
head-following. A two-hand similarity transform composes midpoint movement,
separation-based scaling and hand/wrist rotation. Release freezes the pose;
regrabs anchor at the current hand positions. Tracking/focus loss requires rearming.

Translation/rotation gains are latched at grab start (1.15/1.10 by default).
Rotation is amplified once after combining wrist/baseline estimates, around the
shared grab pivot. Resize and the independent physical head pose remain unchanged.

Level entry restores a heading-relative physical layout, fits current cylinder
bounds and ensures a visible front placement. Saved size is physical, not a
stale game-camera offset. Configuration writes occur outside rendering.
Entry depth clearance uses the actual physical cylinder bounding sphere + 0.08 m
(minimum 0.35 m), allowing a closer start even when the saved reach was below the
old, overly conservative diameter-based threshold. Saved X/Y, orientation, size
and deliberately farther Z values remain the saved base; the base first-entry offset is 1.2 m
forward and 0.45 m below the eyes. Only unsaved, untouched old default offsets
migrate; custom and saved base offsets remain intact. The lower visibility cone
allows this below-eye placement without pushing the new default upward.
EntrySizeMultiplier (default 0.85) and EntryDistanceMultiplier (default 0.8)
now reduce both existing and fresh base preferences at entry, before the same
visibility/clearance safeguards. Only forward depth is scaled, never height,
lateral offset or orientation. Gains latch at placement; saves divide by those
latched gains, so repeated level entry/recenter/save cannot compound reductions.
PreferredSizeMeters/PlacementOffsetMeters store the unscaled base preference.
Set both gains to 1 for the prior entry fit.

## Input and 2D presentation

VR values are bridged into Rewired without editing game assemblies. Viewer-relative
movement is scoped to CharacterMove movement/jump queries: walking compensates
QV's main-camera yaw; grid-based jumping does not apply that extra cancellation.
Other menu queries remain unrotated. Nested query scopes restore state on exceptions.

`ControllerInputConfiguration` resolves `[Input]` enum bindings on configuration
changes. A synchronized value snapshot/revision is copied once per poll; there
is no hot reflection, parsing, hardware-name discovery or array allocation.
FaceButtons uses normalized primary/secondary face roles (Frame XR maps the left
D-pad down/up onto X/Y roles). TrackpadWands avoids requiring A/X buttons and
uses trigger, application-menu and pad-click roles from OpenVR compatibility
input. Layout selection is explicit, not automatic hardware detection. Existing
OpenXR Frame/Touch suggestions and the 320-byte pose/action ABI remain unchanged;
other PCVR controllers still depend on their legacy SteamVR mapping.

Gameplay Fire1, Fire2, Pause, Swap, Dash, Cam and Load have distinct logical bits.
The game consumes semantic Dash/Cam/Load directly rather than also emitting the
gamepad-only L/R path, which would repeat commands and depends on gamepad
detection. Load owns its chord constituents while fully held. Grips and system
buttons cannot be assigned. Limited-button wand defaults leave the optional game
camera/page actions unbound; physical diorama gestures are unaffected.

Menu and gameplay button words are sampled separately. UI prefix/finalizer
scopes cover pause/options/achievements, dialogs, clear screens, skip handlers and
intro-world menus, including when the surrounding scene is stereoscopic gameplay.
Fire1/Fire2/Confirm then use menu bindings, independent of game remaps and chord
reservation. Menu stick axes stay unrotated and separate from left-only default
locomotion and right-only diorama axes. Game secondary camera axes are zeroed in
focused VR, including mirrored input in mixed mode. Diorama axes are applied once
in renderer LateUpdate after game UI queries: yaw about the cylinder center and
physical horizontal approach/retreat relative to the current viewer position.
Both eyes share the updated placement, with no HMD pose filtering or world-size
change. UI navigation reserves that frame, pause/settings/cinema/grips block
placement, and sparse settings persistence waits for stick release.
A UI down edge latches gameplay suppression
until neutral, so closing a dialog/pause cannot leak a held confirm into a game
action later in the same frame. Focus recovery, input-layout changes and VR
settings transitions likewise require neutral input. Nested scopes restore state
on exceptions; disconnect/release/disabled input retains original game input.
Already-delivered hold actions retain a pending ButtonUp until consumed, including
when a modal/jump temporarily stops game polling. All consumers in that input
frame see the same release. This prevents dash/camera/load from becoming stuck
when input ownership changes. Press-any-button screens observe normalized physical
buttons independently of configured menu bindings, still excluding grips/system.

`ExclusiveVrControls=true` replaces recognized Rewired actions/axes (including
zero values) only while focused VR controllers are available, preventing a second
Steam Input gamepad mapping from adding unrelated actions. Unknown actions and
desktop/no-controller fallback stay untouched outside modal/gesture suppression.
False restores mixed keyboard/gamepad merging. This is input routing only: no
Steam Input configuration or game assembly is modified. Binding edits are file
based; this does not add a VR rebinding editor or claim cross-headset hardware QA.

Title/menu cameras render to a flat target. Screen-space canvases are redirected
to an isolated transparent UI capture layer. Cached hierarchy/renderer lists are
built during scene maintenance. HUD and title/menu capture rates are independent.
Physical yaw-only panel orientation removes head pitch/roll before game-space
conversion. Settings panels retain a tracking-space anchor while open.

Exception: verified `IntroState.WorldState` / `IntroState.CostumeState` /
`IntroState.StageState` entries
inside `001_Intro` use the stereo eye cameras directly. State Enter postfixes and
cold initial-state recovery select presentation without per-frame reflection.
The World state is the 3D hub leading to costumes/maps; its manager exposes
the costume-access transition. Titles, exit/options/loading and unknown states
stay 2D. Selection rig uses the
original scripted camera with 1 game unit/meter head tracking; gameplay scale,
placement, tilt, cylinder, cloud suppression and grip gestures do not apply.
The hub alone dollies the VR rig forward toward the game manager's cached
`_worldTransform` anchor, retaining 35% of original forward depth and at least
one game unit of clearance. It does not edit the source camera, anchor, rotation
or head tracking. A missing/behind/invalid anchor retains original framing.
`VR.IntroHubDistanceScale=1` restores the original hub distance; this live
setting does not affect costume/map cameras or gameplay placement.
The source-camera StageUICanvas is isolated with overlay UI so labels/navigation
survive stereo capture; world-space and other-camera canvases stay unchanged.
Stereo hub/selections share gameplay HUD scale, physical distance and UI capture
cadence (36 Hz by default), using the existing upright lagged panel follow and
GPU mipmaps. A common allocation-free policy routes both layout and capture;
disabled stereo menus retain the independent 2D panel settings and 72 Hz capture.
`HudLayoutInset` caches root-child RectTransforms during canvas maintenance and
remaps anchors using `inset + originalAnchor * (1 - 2 * inset)`. It does not
change nested anchors, anchored positions, pivots or local font/widget scale.
Live game-side anchor writes become the new baseline; repeated scans never
compound the margin. Flat/title mode uses zero inset; reparenting/scene changes
and shutdown restore original anchors. No new per-frame layout traversal or
forced canvas rebuild is added.
The verified `IntroStageUIManager._dim` reference identifies the StageUICanvas
`LobbyDim` SpriteRenderer, without broad name matching. Its live enabled state
is sampled before our manual stage eye/UI capture, temporarily disabled, then
restored in a finally block. Other states, 2D recovery, game tweens and input are
untouched. Scene reset/shutdown also restore any outstanding suppression.
An explicit menu/config switch recovers captured 2D presentation. These scenes
contain actual static/skinned meshes; offline metadata verifies the hook sites,
but headset framing/performance validation remains required.
Stereo selections are therefore opt-in/off by default until the Frame test gate.

The verified first-level `1_1` opening uses a separate compatibility route.
GameManager SetDirector/OnEndDirector postfixes select flat/stereo presentation;
cold state/time/duration recovery handles late injection and timeline pauses.
The director's child camera is pinned during playback, overriding the general
camera scan only while flat. No game director/animation/scene state is changed.
The existing flat-screen render path captures that camera into one lazily created
RGB-only 1920x1080 target (RGB111110Float, RGB565 fallback) so unused original
alpha cannot erase the movie. There is no additional per-frame copy pass.
Flat UI uses original anchors/menu cadence; grips and viewer-relative movement
mapping are disabled until gameplay returns. Placement is fitted/restored only
after the intro ends/skips. Scene reset, shutdown and unavailable hooks/targets
retain desktop/normal VR fallback. Reflection and discovery stay outside render.
`FixedPanelAnchor` latches the entry head position/yaw in physical tracking space.
Cinematic eye rendering uses an independent stationary rig; calibration maps
the fixed panel and eyes consistently, without animated source-camera motion
or panel-follow interpolation. Entry/exit, recenter and scene change reset it.
The verified New Game `Opening`/`Opening2` scenes share this fixed-panel policy
without requiring first-level GameManager hooks. Their existing flat capture
continues animating independently. Other flat scenes retain regular follow.
The stereo World state alone overrides HUD scale to 4; this is not a distance
change and never changes saved/global gameplay HUD settings or flat recovery.

All stereo world paths exclude the mod panel layer, then render it last with
`CameraClearFlags.Depth`. This preserves scene color/passthrough alpha but removes
world depth that `Sprites/Default` would otherwise test (its depth test is fixed,
not controlled by the material's `_ZTest` property). No extra target/shader/copy
is needed. Cylinder mode already had a HUD pass; unclipped/menu stereo gains one
lightweight panel-only pass per eye. Resolve remains after the overlay.

The manual renderer uses execution order +10000, after QV's default-order
DynamicBone LateUpdate. Sampling bones before that step can expose transforms
reset in PreUpdate instead of the simulated pose. That ordering change alone
did not fix headset hair motion. Read-only scene metadata also shows Q's model
Animator uses CullUpdateTransforms and hair skins disable offscreen updates.
Manual camera rendering can leave these animated/skinned transforms stale while
DynamicBone continues integrating. `CharacterVisualCompatibility` overrides
only the cached active player's hierarchy to AlwaysAnimate/updateWhenOffscreen,
without enabling inactive renderers, changing animation timing or bone physics.
Cold maintenance handles costume/reparent changes and restores prior settings
on scene/player changes, tracking loss, intro entry and shutdown. No per-eye
component search or scene-wide animation override occurs. The attempted
DynamicBone CheckDistance camera rewrite was removed; CameraListener alone
retains its original compatibility hook. Hair correctness and player-only
animation/skinning cost remain unmeasured until the next manual Frame test.
Configurable gameplay triggers emit the semantic Dash/Cam/Load actions; the
original LB+RB command is exposed through Load (default both triggers). Menu
confirm/back/page bindings are separate. Grip, focus/menu suppression and
desktop fallback remain independent; no native OpenXR action/ABI change is needed.

Decorative cloud renderers are cached using verified signatures, temporarily
disabled around stereo gameplay rendering, then restored in a finally block.
Rain-cloud mechanics, unrelated particles and desktop rendering are preserved.

Known liquid shaders consume `_CameraDepthTexture`, verified through read-only
local shader metadata. A cold renderer cache requests `DepthTextureMode.Depth`
on each active gameplay eye while preserving the source's other depth flags.
The HUD-only pass disables depth generation. Depth is generated for that eye's
actual perspective/pose; Unity camera globals are never replaced with the flat
camera's position. Auxiliary depth passes retain original shaders and are not
cylinder-clipped, so outside geometry can still influence shoreline shading.
See [Unity depth textures](https://docs.unity3d.com/2019.4/Documentation/Manual/SL-CameraDepthTexture.html).

## Resource and performance rules

Hub Exit pause/options/achievements use an intro-only panel override: scale 2
at the dedicated live HubPauseDistanceMeters value (default 1.2 m, range 0.6-3).
The World hub keeps its scale 4; gameplay pause/other screens are unchanged.
One settings row exposes that distance independently of every other panel.

Physical gameplay eye mapping uses the exact absolute runtime eye snapshot:
`origin + inversePlacementRotation * (trackingEye - placementPosition) * units`.
Rotation is `inversePlacementRotation * trackingEyeRotation`. The previous
calibration/relative-head reconstruction cancels algebraically but adds float
round-trips at very small diorama scales. XR no longer extracts eye-to-head
matrices only to multiply them by head again. OpenVR derives absolute eyes from
that frame's exact head and static eye transforms. Panels/legacy views still
use their calibration mapping; stereo IPD, player follow and pose/submit pairing
remain unchanged. No HMD filtering or artificial world-follow lag is introduced.

Exclusive XR texture creation caps requested eye scale via XrResolutionCap,
default 1.0; 0 disables. It preserves the requested profile/config, applies only
on manual relaunch, and leaves OpenVR and HUD capture resolution untouched.
Final HUD eye sampling still uses that capped target. No live target resizing,
adaptive render allocation or extra blit is added. This addresses observed
missed GPU budgets, but cannot guarantee absence of every source of judder.

`VrScreenFade` replaces only a Cloud.FadeOut started in the stereo map state.
It samples the exact Cloud.Panel alpha once before eye rendering, temporarily
sets just its CanvasRenderer.cull (not Image.enabled, avoiding UI enable/layout
rebuilds), and restores it in finally. The original tween/color/raycast settings
and loading timeline are untouched. Loading can fade in and out; the replacement
persists until gameplay clears or a back/cancel/other scene aborts it.
One cached built-in premultiplied sprite material draws a black full-eye quad
after HUD and MSAA resolve with depth-only clear. Source-over alpha covers
passthrough as well as RGB; opaque black at alpha 1, original eye at alpha 0.
It uses no new render target, shader variant, game-shader change or GPU readback,
and draws nothing at zero alpha. Matrix/active-target state restores in finally;
missing/failed material falls back to the original game rectangle. Actual Unity
GPU composition, CanvasRenderer culling and CPU/GPU cost still require Frame QA.

The hot rendering/input paths must not introduce managed allocations. Shader
variants/resources are created cold; eye resolve/copy remains GPU-only.
Cold diagnostics can allocate and write logs. Scene changes/shutdown restore
camera, canvas, layer, renderer, shadow and frame-pacing state.

Maintain a desktop-safe fallback and measure CPU/GPU times on the actual Frame
at 72 Hz before claiming performance improvements.

## Conservative performance pass

Sector-clear movies are observed separately through the verified
IntroWorldManager.PlayClearDirection -> IntroEventManager.PlayCinema route in
001_Intro. The captured source is the active director child camera (the installed
scene's CINE_LOBBY/Main Camera (1) with CinemachineBrain, not its inactive virtual
camera rigs; the manager's unused _camera field is not serialized or assigned),
and the exact original camera argument is kept for return. EndCinema and cold
state recovery cover natural end, pause, skip, late injection and inactive
directors. This reuses the fixed RGB cinematic panel, overriding stereo-menu
routing and opaque full-scene composition only during the movie. No cylinder,
world-grab interaction, HUD hub scale override or game-camera animation is applied
to the panel. A scene change resets the observer. No timeline is driven or saved
game state modified. Head/eye pose tracking remains direct.

XR cadence diagnostics measure focused backend submission intervals over a
five-second window, with a fixed 0.5 ms histogram (p95 upper bucket), runtime
predicted period, long intervals (>1.5 period), maximum prepare-to-copy age and
copy/EndFrame span. They are not presentation times, display drop counts or
FPS, and must not be summed with GPU queries. Focus loss and window reads break
the interval baseline. A separate allocation-free sampler reports ungrabbed
player-follow and placement changes, excluding cinematic/grab/settings periods.
These observations distinguish scheduling gaps from unintended pivot/placement
motion; they do not filter tracking or claim a jitter fix without Frame QA.

`DioramaVisibility` caches loaded MeshRenderers on scene/config maintenance.
Once per stereo frame it tests live world AABBs against the original-game
cylinder, with a numerical guard band. Fully exterior enabled meshes are hidden
only while both manual eyes are prepared and restored in `finally`. Disabled
objects, mod/UI layers, prefab assets, particles and skinned characters are not
overridden. It does not replace clipping, alter game logic, or assume baked
occlusion is valid around the diorama. New uncached meshes retain normal rendering.
Invalid bounds fail open. Terrain not represented by MeshRenderers retains the
existing GPU clipping path.

`LiquidDepthPolicy.Visible` tests cached enabled liquids against the eye mask,
the cylinder and that eye's frustum, allocation-free. The mod adds its Depth bit
only when needed, after eye pose/projection setup. Source-camera depth modes are
never stripped. `CullOutsideDiorama=false` restores the previous active-liquid
policy as well as disabling exterior mesh/cap pruning.

Caps register unions of ALL mesh contributors sharing an index buffer, including
mixed-material contributors. Only immutable baked static batches receive bounded
registration; moving/unknown contributors make the entire buffer unbounded.
The original-world cylinder volume travels in the same 64-slot queue as the eye
clip parameters, so game-camera movement, physical placement, tilt and zoom cannot
race a queued eye. Bounds fully inside or disjoint from the cylinder need no
stencil replay. Enclosing/intersecting boxes retain it.

`LiveCapBounds` additionally samples current MeshRenderer bounds once per stereo
frame, including every cached contributor of a shared index buffer (also inactive
and mixed-material contributors). This covers QV's ordinary non-static-batched
meshes without freezing their transforms. A union wholly inside/disjoint from the
cylinder can omit its cap replay; invalid/destroyed contributors keep full replay.
Mesh replacements clear all skips and request cold rediscovery. The staging
pointer array is allocated/pinned only on cold refresh; native copies up to 256
skip keys into the exact pose slot, then into graphics-owned storage for each eye.
The registry generation invalidates snapshots across registration/scene changes;
unknown/unlisted buffers and capacity excess retain full replay. No per-frame
registry rebuild, shader mutation or GPU geometry readback. This adds live-bound
CPU work, so retain it only if Frame A/B measurements improve.

`UiCaptureCache` preserves the 3360x1890 target and mipmaps. Graphic vertex,
material and layout callbacks invalidate it; cached local transforms, enabled
graphics/canvases, and CanvasGroups (including ancestors) catch non-Graphic
changes. CanvasRenderer color snapshots also catch alpha/color tweens that do not
dirty Graphic geometry. Active Animators/custom materials conservatively keep the
old cadence; disabled/inactive graphics do not force continuous capture.
The 0.5-second maintenance scan forces a fresh capture and covers hierarchy
changes; global canvas discovery is cached for one second. Destroyed/hidden
objects and transitions invalidate reuse. List-based character discovery retains
inactive-costume and hair protections without allocating result arrays each scan;
fallback camera discovery reuses a bounded-growth array.

The ordinary HUD quad is explicitly drawn in a reused per-eye AfterEverything
command buffer. Native clipping ends BEFORE the material is bound; depth alone
is cleared, preserving world color/passthrough alpha, and drawing occurs before
MSAA resolve and the VR fade. No extra texture or blit. While the custom settings
Canvas is visible, or in flat scenes, the validated camera path remains. The
direct path does not attempt to replay CanvasRenderer geometry manually.

UI cache discovery never reads virtual material/defaultMaterial getters on
third-party Graphics (including TextMeshPro submeshes): these can instantiate
materials or throw before initialization, even on inactive widgets. Only exact
built-in Image/RawImage/Text types are inspected through those properties.
`UiMaterialWatch` binds the known TMP shared getters on cold discovery, without a
compile/runtime dependency on TMP in desktop fallback. The installed getters were
verified as direct field reads: TMP_Text.fontSharedMaterial and
TMP_SubMeshUI.sharedMaterial. Only exact TextMeshProUGUI/TMP_SubMeshUI types in
Unity.TextMeshPro and the stock Mobile/Distance Field or Distance Field shader
are eligible. Full SDF with face/outline UV scrolling, unknown shaders, missing or
replaced materials/shaders keep continuous capture. Hot checks use cached
delegates/property IDs, never reflection, shader-name strings or material clones.
Delegate observers survive routine scans and are reclassified only if their
material/shader changes; destroyed widgets are pruned cold, scene/session clear
releases all observers. Routine scans do not rebind every TMP getter.
Other Graphic types retain normal capture cadence. Discovery errors trip a session circuit breaker, unregister observers
and fall back to uncached captures without interrupting scene/controller
maintenance. Disabling AdaptiveUiCapture bypasses discovery as well as reuse.

`DetailedGpuTimings` optionally adds eight pairs of timestamp queries to the
existing eight-slot nonblocking query ring: UI, left/right world, left/right HUD,
XR copy span, and left/right depth. Missing passes report zero. Depth is part of
world, not an additive budget; spans can contain submission gaps and are delayed
samples, not FPS or percentiles. Profiling is off by default, created cold on the
graphics thread, and never reads an eye texture. Exterior mesh, liquid, cap and UI
reuse counters remain available without detailed timestamps.

`PostSubmitMaintenance` moves the existing cold coroutine work to a reused
WaitForEndOfFrame yield: canvas/hierarchy scans, registry discovery and diagnostic
formatting occur after stereo/Submit commands are queued, not while holding a new
XR pose ahead of eye enqueue. The coroutine rechecks initialization after its
yield. Its maximum CPU duration is logged with the scheduling flag for A/B tests.
This is not late latching: XR wait/begin, inputs, game Update, exact eye poses and
XR projection-layer poses keep their previous ordering and one-frame backpressure.
No HMD smoothing, additional GPU wait or second XR/OpenVR client is introduced.
