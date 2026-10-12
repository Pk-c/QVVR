#pragma once
#include "openvr.h"
#include <d3d11.h>
#include <cstdint>
namespace qvvr
{
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
bool SubmitOpenXrFrame(ID3D11Texture2D *left, ID3D11Texture2D *right, const vr::HmdMatrix34_t &head, bool flip);
bool OpenXrSelected();
// 0=OpenVR, 1=XR waiting, 2=XR visible, 3=XR focused, negative=XR failure.
int OpenXrStatus();
int OpenXrError();
void ShutdownOpenXr();
} // namespace qvvr
