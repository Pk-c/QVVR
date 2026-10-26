#pragma once
#include "FramePacingStats.h"
#include "openvr.h"
#include <d3d11.h>
#include <cstdint>
namespace qvvr
{
FramePacingSnapshot ReadOpenXrPacing();
struct OpenXrHand
{
    vr::HmdMatrix34_t pose;
    uint32_t valid, buttons; // bits 0=confirm, 1=back, 2=stick click, 3=grip click
    float stickX, stickY, trigger, grip;
};
struct OpenXrFov { float left, right, up, down; };
struct OpenXrFrame
{
    vr::HmdMatrix34_t head, leftEye, rightEye;
    OpenXrFov leftFov, rightFov;
    OpenXrHand leftHand, rightHand;
};
static_assert(sizeof(OpenXrFrame) == 320, "Managed XR snapshot ABI");
// HUD compositor quad in XR base space (OpenXR right-handed). The runtime
// samples the HUD texture at display resolution instead of the eye images.
struct HudLayer
{
    float px, py, pz, qx, qy, qz, qw, width, height;
    uint32_t visible, version; // version changes whenever the HUD texture content changes.
};
static_assert(sizeof(HudLayer) == 44, "Managed HUD layer ABI");
// 0=not created yet, 1=ready (HUD omitted from eyes), -1=failed (HUD stays in eyes).
int OpenXrHudStatus();
// Fake-runtime tests only: HUD swapchain width cap applied at the next creation (0 = default 2048).
void SetOpenXrHudMaxWidth(uint32_t width);
void ConfigureOpenXr(bool requested);
bool InitializeExclusiveOpenXr(ID3D11Texture2D *bootstrap, float scale, uint32_t &width, uint32_t &height);
// Unity main thread: wait/begin + poses/actions before the game's Update.
// At most ONE in-flight XR frame; never replace poses for queued eye draws.
// 0=waiting/lost tracking, 1=fresh snapshot, 2=previous frame still queued.
int PrepareOpenXrFrame(OpenXrFrame &frame);
void CancelOpenXrFrame();
bool OpenXrRequested();
void SetOpenXrColorSpace(bool gammaGame, bool sourceSrgb);
bool BeginOpenXrFrame(ID3D11Texture2D *left);
bool SubmitOpenXrFrame(ID3D11Texture2D *left, ID3D11Texture2D *right, const vr::HmdMatrix34_t &head, bool flip, bool opaqueScene = false,
                       ID3D11Texture2D *hud = nullptr, const HudLayer *hudLayer = nullptr);
bool OpenXrSelected();
// 0=OpenVR, 1=XR waiting, 2=XR visible, 3=XR focused, negative=XR failure.
int OpenXrStatus();
int OpenXrError();
void ShutdownOpenXr();
} // namespace qvvr
