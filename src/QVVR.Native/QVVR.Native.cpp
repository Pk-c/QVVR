#include "GpuTiming.h"
#include "OpenXrBackend.h"
#include "RenderPoseQueue.h"
#include "ShaderClip.h"
#include "openvr.h"
#include <atomic>
#include <cstdint>
#include <d3d11.h>

namespace
{
constexpr int CompositorUnavailable = -1000;
qvvr::RenderPoseQueue poseQueue;
vr::HmdMatrix34_t activeRenderPose = {}; // Graphics-thread-only frame snapshot.
int activeSlot = -1;

std::atomic<void *> leftTexture(nullptr);
std::atomic<void *> rightTexture(nullptr);
std::mutex textureMutex;
std::atomic<bool> shutdownComplete(true);
struct TextureFrameRefs
{
    ID3D11Texture2D *left = nullptr;
    ID3D11Texture2D *right = nullptr;
    TextureFrameRefs()
    {
        std::lock_guard<std::mutex> lock(textureMutex);
        left = static_cast<ID3D11Texture2D *>(leftTexture.load());
        right = static_cast<ID3D11Texture2D *>(rightTexture.load());
        if (left)
            left->AddRef();
        if (right)
            right->AddRef();
    }
    ~TextureFrameRefs()
    {
        if (left)
            left->Release();
        if (right)
            right->Release();
    }
};
std::atomic<bool> flipEyeTextureY(true);
std::atomic<std::uint64_t> submittedFrames(0);
std::atomic<int> leftSubmitResult(CompositorUnavailable);
std::atomic<int> rightSubmitResult(CompositorUnavailable);
vr::TrackedDevicePose_t renderPoses[vr::k_unMaxTrackedDeviceCount] = {};
bool frameReady = false; // Accessed only on Unity's graphics thread.
constexpr int ClipEventBase = 0x51566000;
constexpr int EndClipEvent = 0x51566200;
constexpr int CapCompositeEvent = 0x51566201;
constexpr int ShutdownEvent = 0x51566300;
constexpr int ProfileEventBase = 0x51566400;
struct ClipSlot
{
    qvvr::ClipParameters eye[2];
    qvvr::CapCullVolume cull[2];
    qvvr::CapSkipFrame skip;
    bool caps[2] = {}, reversed[2] = {}, transparent[2] = {};
} clipSlots[qvvr::PoseSlotCount] = {};
std::mutex clipMutex;
bool usingXrFrame = false;
bool activeOpaqueScene = false;
qvvr::GpuTiming gpuTiming;

void __stdcall OnRenderEvent(int eventId)
{
    if (eventId >= ProfileEventBase && eventId < ProfileEventBase + 16)
    { gpuTiming.Mark(static_cast<unsigned>(eventId - ProfileEventBase)); return; }
    if (eventId == ShutdownEvent)
    {
        qvvr::EndShaderClip();
        qvvr::SetShaderClipTargets(nullptr, nullptr);
        gpuTiming.End();
        qvvr::ShutdownOpenXr();
        frameReady = false;
        shutdownComplete.store(true);
        return;
    }
    if (eventId == EndClipEvent)
    {
        qvvr::EndShaderClip();
        return;
    }
    if (eventId == CapCompositeEvent)
    {
        qvvr::CompositeShaderCaps();
        return;
    }
    if (eventId >= ClipEventBase && eventId < ClipEventBase + qvvr::PoseSlotCount * 4)
    {
        int offset = eventId - ClipEventBase, eye = offset % 4, slot = offset / 4;
        if (eye > 1)
            return;
        qvvr::ClipParameters parameters;
        bool caps, reversed, transparent;
        qvvr::CapCullVolume cull;
        qvvr::CapSkipFrame skip;
        {
            std::lock_guard<std::mutex> lock(clipMutex);
            parameters = clipSlots[slot].eye[eye];
            caps = clipSlots[slot].caps[eye]; reversed = clipSlots[slot].reversed[eye];
            cull = clipSlots[slot].cull[eye];
            transparent = clipSlots[slot].transparent[eye];
            skip = clipSlots[slot].skip;
        }
        qvvr::BeginShaderClip(parameters, caps, reversed, transparent, &cull, &skip);
        return;
    }
    // Slot identity travels with the queued Unity command, not a shared
    // "latest pose" that the main thread could overwrite before execution.
    int slot = 0;
    bool beginFrame = false;
    if (!qvvr::DecodeRenderEvent(eventId, slot, beginFrame))
        return;

    TextureFrameRefs textures;
    void *left = textures.left;
    void *right = textures.right;
    if (left == nullptr || right == nullptr)
        return;

    // Never even request an OpenVR interface during an exclusive XR session.
    // Steam Frame's client crashes if both APIs coexist in this process.
    vr::IVRCompositor *compositor = nullptr;
    const bool xrRequested = qvvr::OpenXrRequested();
    if (!xrRequested) compositor = vr::VRCompositor();
    if (!xrRequested && compositor == nullptr)
    {
        leftSubmitResult.store(CompositorUnavailable, std::memory_order_relaxed);
        rightSubmitResult.store(CompositorUnavailable, std::memory_order_relaxed);
        return;
    }

    if (beginFrame)
    {
        frameReady = false;
        if (!poseQueue.TryRead(slot, activeRenderPose, &activeOpaqueScene))
            return;
        activeSlot = slot;
        usingXrFrame = xrRequested;
        if (xrRequested)
        {
            frameReady = qvvr::BeginOpenXrFrame(static_cast<ID3D11Texture2D *>(left));
            if (frameReady)
                gpuTiming.Begin(static_cast<ID3D11Texture2D *>(left));
            return;
        }
        // Wait BEFORE Unity's eye/UI draw commands, not after rendering.
        // Both events are serialized on the same graphics thread.
        const vr::EVRCompositorError poseError =
            compositor->WaitGetPoses(renderPoses, vr::k_unMaxTrackedDeviceCount, nullptr, 0);
        frameReady = poseError == vr::VRCompositorError_None;
        if (frameReady)
            gpuTiming.Begin(static_cast<ID3D11Texture2D *>(left));
        if (!frameReady)
        {
            leftSubmitResult.store(static_cast<int>(poseError), std::memory_order_relaxed);
            rightSubmitResult.store(static_cast<int>(poseError), std::memory_order_relaxed);
        }
        return;
    }
    if (!frameReady || activeSlot != slot)
        return;
    frameReady = false;
    if (usingXrFrame)
    {
        gpuTiming.Mark(10);
        bool result =
            qvvr::SubmitOpenXrFrame(static_cast<ID3D11Texture2D *>(left), static_cast<ID3D11Texture2D *>(right),
                                    activeRenderPose, flipEyeTextureY.load(), activeOpaqueScene);
        gpuTiming.Mark(11);
        gpuTiming.End();
        leftSubmitResult.store(result ? 0 : qvvr::OpenXrError());
        rightSubmitResult.store(result ? 0 : qvvr::OpenXrError());
        if (result)
            submittedFrames.fetch_add(1);
        return;
    }

    // Submit the D3D11 commands queued by Unity before Proton exports the
    gpuTiming.End();
    // textures and their synchronization objects to the Vulkan compositor.
    ID3D11Device *device = nullptr;
    ID3D11DeviceContext *context = nullptr;
    static_cast<ID3D11Texture2D *>(left)->GetDevice(&device);
    if (device != nullptr)
    {
        device->GetImmediateContext(&context);
        device->Release();
    }
    if (context != nullptr)
        context->Flush();

    // Unity D3D render targets have the opposite vertical orientation.
    // Correct it in the compositor, without a blit or CPU texture readback.
    const bool flipY = flipEyeTextureY.load(std::memory_order_relaxed);
    const vr::VRTextureBounds_t bounds = {0.0f, flipY ? 1.0f : 0.0f, 1.0f, flipY ? 0.0f : 1.0f};
    // Unity predicted its camera pose before this thread's WaitGetPoses.
    // Reprojection must use that exact pose, not WaitGetPoses' newer one.
    vr::VRTextureWithPose_t leftDescriptor = {};
    leftDescriptor.handle = left;
    leftDescriptor.eType = vr::TextureType_DirectX;
    leftDescriptor.eColorSpace = vr::ColorSpace_Auto;
    leftDescriptor.mDeviceToAbsoluteTracking = activeRenderPose;
    vr::VRTextureWithPose_t rightDescriptor = leftDescriptor;
    rightDescriptor.handle = right;

    const vr::EVRCompositorError leftError =
        compositor->Submit(vr::Eye_Left, &leftDescriptor, &bounds, vr::Submit_TextureWithPose);
    const vr::EVRCompositorError rightError =
        compositor->Submit(vr::Eye_Right, &rightDescriptor, &bounds, vr::Submit_TextureWithPose);

    leftSubmitResult.store(static_cast<int>(leftError), std::memory_order_relaxed);
    rightSubmitResult.store(static_cast<int>(rightError), std::memory_order_relaxed);
    if (leftError == vr::VRCompositorError_None && rightError == vr::VRCompositorError_None)
        submittedFrames.fetch_add(1, std::memory_order_relaxed);
    if (context != nullptr)
    {
        context->Flush();
        context->Release();
    }
    compositor->PostPresentHandoff();
}
} // namespace

extern "C"
{
    __declspec(dllexport) void __cdecl QVVR_RequestShutdown()
    {
        shutdownComplete.store(false);
    }
    __declspec(dllexport) int __cdecl QVVR_IsShutdownComplete()
    {
        return shutdownComplete.load() ? 1 : 0;
    }
    __declspec(dllexport) void __cdecl QVVR_SetEyeColorSpace(int gammaGame, int sourceSrgb)
    {
        qvvr::SetOpenXrColorSpace(gammaGame != 0, sourceSrgb != 0);
    }
    __declspec(dllexport) void __cdecl QVVR_SetClipTargets(void *left, void *right)
    {
        qvvr::SetShaderClipTargets(static_cast<ID3D11Texture2D *>(left), static_cast<ID3D11Texture2D *>(right));
    }
    __declspec(dllexport) double __cdecl QVVR_GetGpuTime()
    {
        return gpuTiming.Latest();
    }
    __declspec(dllexport) void __cdecl QVVR_SetDetailedGpuTiming(int enabled) { gpuTiming.ConfigureDetailed(enabled != 0); }
    __declspec(dllexport) double __cdecl QVVR_GetGpuPhaseTime(int phase) { return gpuTiming.Phase(static_cast<unsigned>(phase)); }
    __declspec(dllexport) void __cdecl QVVR_ReadXrPacing(qvvr::FramePacingSnapshot *snapshot)
    { if (snapshot) *snapshot = qvvr::ReadOpenXrPacing(); }
    __declspec(dllexport) int __cdecl QVVR_InstallShaderClip(void *texture)
    {
        if (!texture)
            return 0;
        ID3D11Device *device = nullptr;
        static_cast<ID3D11Texture2D *>(texture)->GetDevice(&device);
        bool result = qvvr::InstallShaderClip(device);
        if (device)
            device->Release();
        return result ? 1 : 0;
    }
    __declspec(dllexport) int __cdecl QVVR_WriteClipDiagnostic(const wchar_t *path)
    {
        return qvvr::WriteShaderClipDiagnostic(path) ? 1 : 0;
    }
    __declspec(dllexport) void __cdecl QVVR_SetClipParameters(int slot, int eye, const qvvr::ClipParameters *parameters)
    {
        if (slot < 0 || slot >= qvvr::PoseSlotCount || eye < 0 || eye > 1 || !parameters)
            return;
        std::lock_guard<std::mutex> lock(clipMutex);
        clipSlots[slot].eye[eye] = *parameters;
        clipSlots[slot].caps[eye] = false;
        clipSlots[slot].cull[eye] = {};
    }
    __declspec(dllexport) void __cdecl QVVR_SetCylinderCapOptions(int slot, int eye, int enabled, int reversedZ, int transparent)
    {
        if (slot < 0 || slot >= qvvr::PoseSlotCount || eye < 0 || eye > 1) return;
        std::lock_guard<std::mutex> lock(clipMutex);
        clipSlots[slot].caps[eye] = enabled != 0;
        clipSlots[slot].reversed[eye] = reversedZ != 0;
        clipSlots[slot].transparent[eye] = transparent != 0;
    }
    __declspec(dllexport) void __cdecl QVVR_RegisterCapMesh(void *indices)
    {
        qvvr::RegisterCapMesh(static_cast<ID3D11Buffer *>(indices));
    }
    __declspec(dllexport) void __cdecl QVVR_RegisterCapMeshBounds(void *indices, const qvvr::CapBounds *bounds)
    {
        if (bounds) qvvr::RegisterCapMeshBounds(static_cast<ID3D11Buffer *>(indices), *bounds);
    }
    __declspec(dllexport) void __cdecl QVVR_SetCapCullVolume(int slot, int eye, float x, float y, float z, float radius, float halfHeight)
    {
        if (slot < 0 || slot >= qvvr::PoseSlotCount || eye < 0 || eye > 1) return;
        std::lock_guard<std::mutex> lock(clipMutex);
        auto &v = clipSlots[slot].cull[eye];
        v.center[0] = x; v.center[1] = y; v.center[2] = z; v.radius = radius; v.halfHeight = halfHeight;
    }
    __declspec(dllexport) void __cdecl QVVR_ClearCapMeshes()
    {
        qvvr::ClearCapMeshes();
    }
    __declspec(dllexport) void __cdecl QVVR_SetCapSkipMeshes(int slot, const uintptr_t *buffers, int count)
    {
        if (slot < 0 || slot >= qvvr::PoseSlotCount) return;
        std::lock_guard<std::mutex> lock(clipMutex);
        auto &skip = clipSlots[slot].skip;
        skip.generation = qvvr::GetCapRegistryGeneration();
        // Invalid/oversized snapshots disable pruning, never truncate silently.
        skip.count = buffers && count > 0 && count <= static_cast<int>(qvvr::CapSkipFrame::Capacity) ? static_cast<unsigned>(count) : 0;
        for (unsigned i = 0; i < skip.count; ++i) skip.buffers[i] = buffers[i];
    }
    __declspec(dllexport) void __cdecl QVVR_GetCapCullStats(unsigned *bounded, unsigned *skipped)
    {
        unsigned b = 0, s = 0; qvvr::GetCapCullStats(b, s);
        if (bounded) *bounded = b; if (skipped) *skipped = s;
    }
    __declspec(dllexport) void __cdecl QVVR_GetCapStats(unsigned *available, unsigned *registered, unsigned *replayed, unsigned *composed)
    {
        unsigned a=0,r=0,v=0,c=0;
        qvvr::GetCapStats(a,r,v,c);
        if(available)*available=a;if(registered)*registered=r;if(replayed)*replayed=v;if(composed)*composed=c;
    }
    __declspec(dllexport) void __cdecl QVVR_ConfigureOpenXr(int enabled)
    {
        qvvr::ConfigureOpenXr(enabled != 0);
    }
    __declspec(dllexport) int __cdecl QVVR_InitializeExclusiveOpenXr(void *texture, float scale, unsigned *width, unsigned *height)
    {
        if (!width || !height) return 0;
        return qvvr::InitializeExclusiveOpenXr(static_cast<ID3D11Texture2D *>(texture), scale, *width, *height) ? 1 : 0;
    }
    __declspec(dllexport) int __cdecl QVVR_PrepareOpenXrFrame(qvvr::OpenXrFrame *frame)
    {
        return frame ? qvvr::PrepareOpenXrFrame(*frame) : 0;
    }
    __declspec(dllexport) void __cdecl QVVR_CancelOpenXrFrame()
    {
        qvvr::CancelOpenXrFrame();
    }
    __declspec(dllexport) int __cdecl QVVR_GetOpenXrStatus(int *error)
    {
        if (error)
            *error = qvvr::OpenXrError();
        return qvvr::OpenXrStatus();
    }
    __declspec(dllexport) void __cdecl QVVR_GetClipStats(unsigned *patched, unsigned *rejected, unsigned *unknown,
                                                      unsigned *depthOnly)
    {
        unsigned p = 0, r = 0, u = 0, d = 0;
        qvvr::GetShaderClipStats(p, r, u, d);
        if (patched)
            *patched = p;
        if (rejected)
            *rejected = r;
        if (unknown)
            *unknown = u;
        if (depthOnly)
            *depthOnly = d;
    }
    __declspec(dllexport) void __cdecl QVVR_GetClipBindingStats(unsigned *materials, unsigned *otherContexts)
    {
        unsigned m = 0, o = 0;
        qvvr::GetShaderClipBindingStats(m, o);
        if (materials) *materials = m;
        if (otherContexts) *otherContexts = o;
    }
    __declspec(dllexport) int __cdecl QVVR_SetRenderPose(int slot, const vr::HmdMatrix34_t *pose)
    {
        return pose != nullptr && poseQueue.TryWrite(slot, *pose) ? 1 : 0;
    }
    __declspec(dllexport) int __cdecl QVVR_SetRenderPoseAndMode(int slot, const vr::HmdMatrix34_t *pose, int opaqueScene)
    {
        return pose != nullptr && poseQueue.TryWrite(slot, *pose, opaqueScene != 0) ? 1 : 0;
    }

    __declspec(dllexport) void __cdecl QVVR_SetFlipEyeTextureY(int enabled)
    {
        flipEyeTextureY.store(enabled != 0, std::memory_order_relaxed);
    }

    __declspec(dllexport) void *__cdecl QVVR_GetRenderEventFunc()
    {
        return reinterpret_cast<void *>(&OnRenderEvent);
    }

    __declspec(dllexport) void __cdecl QVVR_SetEyeTextures(void *left, void *right)
    {
        if (left)
            static_cast<ID3D11Texture2D *>(left)->AddRef();
        if (right)
            static_cast<ID3D11Texture2D *>(right)->AddRef();
        std::lock_guard<std::mutex> lock(textureMutex);
        void *oldLeft = leftTexture.exchange(left);
        void *oldRight = rightTexture.exchange(right);
        if (oldLeft)
            static_cast<ID3D11Texture2D *>(oldLeft)->Release();
        if (oldRight)
            static_cast<ID3D11Texture2D *>(oldRight)->Release();
    }

    __declspec(dllexport) void __cdecl QVVR_ClearEyeTextures()
    {
        QVVR_SetEyeTextures(nullptr, nullptr);
        poseQueue.Clear();
    }

    __declspec(dllexport) void __cdecl QVVR_GetSubmitState(std::uint64_t *frames, int *leftResult, int *rightResult)
    {
        if (frames != nullptr)
            *frames = submittedFrames.load(std::memory_order_relaxed);
        if (leftResult != nullptr)
            *leftResult = leftSubmitResult.load(std::memory_order_relaxed);
        if (rightResult != nullptr)
            *rightResult = rightSubmitResult.load(std::memory_order_relaxed);
    }
}
