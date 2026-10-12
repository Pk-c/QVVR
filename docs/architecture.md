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
Entry depth clearance uses the actual physical cylinder bounding sphere + 0.5 m
(minimum 1.25 m), allowing a closer start even when the saved reach was below the
old, overly conservative diameter-based threshold. Saved X/Y, orientation, size
and deliberately farther Z values are not reset; first-entry defaults to 1.6 m.

## Input and 2D presentation

VR values are bridged into Rewired without editing game assemblies. Viewer-relative
movement is scoped to CharacterMove movement/jump queries: walking compensates
QV's main-camera yaw; grid-based jumping does not apply that extra cancellation.
Other menu queries remain unrotated. Nested query scopes restore state on exceptions.

Title/menu cameras render to a flat target. Screen-space canvases are redirected
to an isolated transparent UI capture layer. Cached hierarchy/renderer lists are
built during scene maintenance. HUD and title/menu capture rates are independent.
Physical yaw-only panel orientation removes head pitch/roll before game-space
conversion. Settings panels retain a tracking-space anchor while open.

Exception: verified `IntroState.CostumeState` / `IntroState.StageState` entries
inside `001_Intro` use the stereo eye cameras directly. State Enter postfixes and
cold initial-state recovery select presentation without per-frame reflection.
Titles, hub, options/loading and unknown states stay 2D. Selection rig uses the
original scripted camera with 1 game unit/meter head tracking; gameplay scale,
placement, tilt, cylinder, cloud suppression and grip gestures do not apply.
The source-camera StageUICanvas is isolated with overlay UI so labels/navigation
survive stereo capture; world-space and other-camera canvases stay unchanged.
An explicit menu/config switch recovers captured 2D presentation. These scenes
contain actual static/skinned meshes; offline metadata verifies the hook sites,
but headset framing/performance validation remains required.
Stereo selections are therefore opt-in/off by default until the Frame test gate.

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

The hot rendering/input paths must not introduce managed allocations. Shader
variants/resources are created cold; eye resolve/copy remains GPU-only.
Cold diagnostics can allocate and write logs. Scene changes/shutdown restore
camera, canvas, layer, renderer, shadow and frame-pacing state.

Maintain a desktop-safe fallback and measure CPU/GPU times on the actual Frame
at 72 Hz before claiming performance improvements.
