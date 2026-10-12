#pragma once
#include <cstdint>
#include <mutex>
#include "openvr.h"

namespace qvvr
{
    constexpr int BeginFrameEventId = 0x51565651;
    constexpr int SubmitEventId = 0x51565652;
    constexpr int PoseSlotCount = 64;

    inline bool DecodeRenderEvent(int eventId, int& slot, bool& beginFrame)
    {
        const std::uint32_t offset = static_cast<std::uint32_t>(eventId) -
            static_cast<std::uint32_t>(BeginFrameEventId);
        if (offset >= PoseSlotCount * 4 || offset % 4 > SubmitEventId - BeginFrameEventId) return false;
        slot = static_cast<int>(offset / 4);
        beginFrame = offset % 4 == 0;
        return true;
    }

    // Fixed storage, no pointers into managed memory, no queued-frame overwrite.
    class RenderPoseQueue
    {
        struct Slot
        {
            vr::HmdMatrix34_t pose = {};
            bool pending = false;
            bool opaqueScene = false;
        };
        Slot slots[PoseSlotCount];
        std::mutex mutex;
    public:
        bool TryWrite(int slot, const vr::HmdMatrix34_t& pose, bool opaqueScene = false)
        {
            if (slot < 0 || slot >= PoseSlotCount) return false;
            std::lock_guard<std::mutex> lock(mutex);
            if (slots[slot].pending) return false;
            slots[slot].pose = pose;
            slots[slot].opaqueScene = opaqueScene;
            slots[slot].pending = true;
            return true;
        }

        bool TryRead(int slot, vr::HmdMatrix34_t& pose, bool *opaqueScene = nullptr)
        {
            if (slot < 0 || slot >= PoseSlotCount) return false;
            std::lock_guard<std::mutex> lock(mutex);
            if (!slots[slot].pending) return false;
            pose = slots[slot].pose;
            if (opaqueScene) *opaqueScene = slots[slot].opaqueScene;
            slots[slot].pending = false;
            return true;
        }

        void Clear()
        {
            std::lock_guard<std::mutex> lock(mutex);
            for (auto& slot : slots) slot.pending = false;
        }
    };
}
