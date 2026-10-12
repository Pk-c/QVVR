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

## Physical placement

Placement state stores center P, rotation Q and size S in tracking-space meters.
For game cylinder center C and effective units U/S, the inverse view is:

`gameEye = C + inverse(Q) * (trackingEye - P) * U/S`

Both eyes share C, P, Q and S. C follows character translation while P is not
head-following. A two-hand similarity transform composes midpoint movement,
separation-based scaling and hand/wrist rotation. Release freezes the pose;
regrabs anchor at the current hand positions. Tracking/focus loss requires rearming.

Level entry restores a heading-relative physical layout, fits current cylinder
bounds and ensures a visible front placement. Saved size is physical, not a
stale game-camera offset. Configuration writes occur outside rendering.

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

Decorative cloud renderers are cached using verified signatures, temporarily
disabled around stereo gameplay rendering, then restored in a finally block.
Rain-cloud mechanics, unrelated particles and desktop rendering are preserved.

## Resource and performance rules

The hot rendering/input paths must not introduce managed allocations. Shader
variants/resources are created cold; eye resolve/copy remains GPU-only.
Cold diagnostics can allocate and write logs. Scene changes/shutdown restore
camera, canvas, layer, renderer, shadow and frame-pacing state.

Maintain a desktop-safe fallback and measure CPU/GPU times on the actual Frame
at 72 Hz before claiming performance improvements.
