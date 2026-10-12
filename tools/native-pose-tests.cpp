#include <atomic>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include "RenderPoseQueue.h"

static void Check(bool condition, const char* message)
{
    if (!condition) { std::fprintf(stderr, "%s\n", message); std::exit(1); }
}

int main()
{
    qvvr::RenderPoseQueue queue;
    vr::HmdMatrix34_t read = {};
    for (int round = 0; round < 3; ++round)
    {
        for (int slot = 0; slot < qvvr::PoseSlotCount; ++slot)
        {
            vr::HmdMatrix34_t pose = {};
            for (int row = 0; row < 3; ++row)
                for (int column = 0; column < 4; ++column)
                    pose.m[row][column] = static_cast<float>(round * 1000 + slot * 12 + row * 4 + column);
            Check(queue.TryWrite(slot, pose, slot % 2 != 0), "Empty slot must accept a pose.");
            vr::HmdMatrix34_t wrong = {};
            Check(!queue.TryWrite(slot, wrong), "Queued pose must not be overwritten.");
        }
        for (int slot = qvvr::PoseSlotCount - 1; slot >= 0; --slot)
        {
            bool opaque = false;
            Check(queue.TryRead(slot, read, &opaque), "Queued pose must remain readable in arbitrary order.");
            Check(opaque == (slot % 2 != 0), "Opaque menu mode must travel with its exact frame pose, not a latest global.");
            for (int row = 0; row < 3; ++row)
                for (int column = 0; column < 4; ++column)
                    Check(read.m[row][column] == round * 1000 + slot * 12 + row * 4 + column, "Pose was mixed with a different frame.");
            Check(!queue.TryRead(slot, read), "Pose must be consumed once.");
            int decoded = -1;
            bool begin = false;
            Check(qvvr::DecodeRenderEvent(qvvr::BeginFrameEventId + slot * 4, decoded, begin) && decoded == slot && begin, "Wrong begin event identity.");
            Check(qvvr::DecodeRenderEvent(qvvr::SubmitEventId + slot * 4, decoded, begin) && decoded == slot && !begin, "Wrong submit event identity.");
        }
    }
    int slot = -1;
    bool begin = false;
    Check(!qvvr::DecodeRenderEvent(qvvr::BeginFrameEventId - 1, slot, begin), "Out-of-range event accepted.");
    Check(!qvvr::DecodeRenderEvent(qvvr::BeginFrameEventId + 2, slot, begin), "Unused event accepted.");
    Check(!qvvr::DecodeRenderEvent(qvvr::BeginFrameEventId + qvvr::PoseSlotCount * 4, slot, begin), "Out-of-range slot accepted.");
    Check(!qvvr::DecodeRenderEvent(INT_MIN, slot, begin), "Invalid signed event accepted.");
    Check(!queue.TryRead(-1, read) && !queue.TryWrite(qvvr::PoseSlotCount, read), "Invalid pose slot accepted.");
    Check(queue.TryWrite(0, read), "Write before clear failed.");
    queue.Clear();
    Check(!queue.TryRead(0, read) && queue.TryWrite(0, read), "Fallback must clear queued poses.");
    queue.Clear();

    // The production queue is shared by Unity's main and graphics threads.
    std::thread producer([&queue]() {
        for (int index = 1; index <= 10000; ++index)
        {
            vr::HmdMatrix34_t pose = {};
            for (auto& row : pose.m) for (auto& value : row) value = static_cast<float>(index);
            while (!queue.TryWrite(index % qvvr::PoseSlotCount, pose, index % 3 == 0)) std::this_thread::yield();
        }
    });
    for (int index = 1; index <= 10000; ++index)
    {
        bool opaque = false;
        while (!queue.TryRead(index % qvvr::PoseSlotCount, read, &opaque)) std::this_thread::yield();
        Check(opaque == (index % 3 == 0), "Cross-thread scene mode was mixed with another pose.");
        for (const auto& row : read.m) for (auto value : row)
            Check(value == index, "Cross-thread frame pose was overwritten or torn.");
    }
    producer.join();
    std::puts("Native pose tests passed: 64 slots, wraparound, exact frame identity, fallback clear, 10000 cross-thread frames.");
    return 0;
}
