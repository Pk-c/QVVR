#pragma once
#include <algorithm>
#include <cmath>

namespace qvvr
{
struct CapBounds { float minimum[3], maximum[3]; };
struct CapCullVolume { float center[3] = {}; float radius = 0, halfHeight = 0; };
inline bool ValidCapBounds(const CapBounds &b)
{
    for (int i = 0; i < 3; ++i)
        if (!std::isfinite(b.minimum[i]) || !std::isfinite(b.maximum[i]) || b.minimum[i] > b.maximum[i]) return false;
    return true;
}
inline bool CapMayIntersect(const CapBounds &b, const CapCullVolume &v)
{
    // Unknown volumes/bounds always retain the full stencil path.
    if (!ValidCapBounds(b) || !std::isfinite(v.radius) || !std::isfinite(v.halfHeight) || v.radius <= 0 || v.halfHeight <= 0) return true;
    float nearDistance[3], farDistance[3];
    for (int i = 0; i < 3; ++i)
    {
        if (!std::isfinite(v.center[i])) return true;
        float lo = b.minimum[i] - v.center[i], hi = b.maximum[i] - v.center[i];
        nearDistance[i] = (std::max)(0.f, (std::max)(lo, -hi));
        farDistance[i] = (std::max)(std::abs(lo), std::abs(hi));
    }
    float outer = v.radius + .05f, inner = (std::max)(0.f, v.radius - .05f);
    if (nearDistance[1] > v.halfHeight + .05f || nearDistance[0] * nearDistance[0] + nearDistance[2] * nearDistance[2] > outer * outer) return false;
    // A box entirely inside the cylinder cannot cut its boundary. A box
    // containing the cylinder MUST stay eligible (solid cliffs/buildings).
    return !(farDistance[1] < v.halfHeight - .05f && farDistance[0] * farDistance[0] + farDistance[2] * farDistance[2] < inner * inner);
}
}
