#pragma once
#include <cstdint>
#include <d3d11.h>
#include <vector>
#include "DioramaBounds.h"

namespace qvvr
{
// Column-major screen-pixel/depth -> cylinder-local homogeneous coordinates.
struct ClipParameters
{
    float screenToCylinder[16];
    float limits[4]; // radius squared, half height, inward feather width, opaque void green
};
bool PatchCylinderShader(const void *bytes, size_t length, std::vector<std::uint8_t> &output, unsigned &bufferSlot,
                         bool opaque = false, bool premultiplied = false);
bool InstallShaderClip(ID3D11Device *device);
void SetShaderClipTargets(ID3D11Texture2D *left, ID3D11Texture2D *right);
void BeginShaderClip(const ClipParameters &parameters, bool caps = false, bool reversedZ = false, bool transparent = false, const CapCullVolume *cull = nullptr);
void EndShaderClip();
void CompositeShaderCaps();
void RegisterCapMesh(ID3D11Buffer *indices);
void RegisterCapMeshBounds(ID3D11Buffer *indices, const CapBounds &bounds);
void ClearCapMeshes();
void GetCapStats(unsigned &available, unsigned &registered, unsigned &replayed, unsigned &composed);
void GetCapCullStats(unsigned &bounded, unsigned &skipped);
void GetShaderClipStats(unsigned &patched, unsigned &rejected, unsigned &unknown, unsigned &depthOnly);
void GetShaderClipBindingStats(unsigned &materials, unsigned &otherContexts);
// One-shot buffer/state diagnostic. Never reads an eye/color/depth texture.
bool WriteShaderClipDiagnostic(const wchar_t *path);
} // namespace qvvr
