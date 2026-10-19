#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <mutex>

namespace qvvr
{
// Blittable diagnostic window. Submission gaps are NOT compositor drop counts.
struct FramePacingSnapshot
{
    uint64_t intervals = 0, longGaps = 0;
    double averageMs = 0, maximumMs = 0, p95UpperMs = 0;
    double periodMs = 0, maximumQueueAgeMs = 0, maximumCopySubmitMs = 0;
};
class FramePacingStats
{
    std::mutex mutex;
    FramePacingSnapshot snapshot;
    uint64_t histogram[256] = {};
    double lastEnd = 0, sum = 0;
public:
    void Record(double completed, double prepared, double copyStarted, double period, bool focused)
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!focused || !std::isfinite(completed) || !std::isfinite(period) || period <= 0)
        { lastEnd = 0; return; }
        snapshot.periodMs = period;
        if (std::isfinite(prepared) && std::isfinite(copyStarted) && prepared > 0 && copyStarted >= prepared && completed >= copyStarted)
        {
            snapshot.maximumQueueAgeMs = (std::max)(snapshot.maximumQueueAgeMs, copyStarted - prepared);
            snapshot.maximumCopySubmitMs = (std::max)(snapshot.maximumCopySubmitMs, completed - copyStarted);
        }
        if (lastEnd > 0 && completed > lastEnd)
        {
            double interval = completed - lastEnd;
            ++snapshot.intervals; sum += interval;
            snapshot.maximumMs = (std::max)(snapshot.maximumMs, interval);
            if (interval > period * 1.5) ++snapshot.longGaps;
            unsigned bucket = interval >= 127.5 ? 255 : static_cast<unsigned>(std::ceil(interval * 2));
            ++histogram[bucket];
        }
        lastEnd = completed;
    }
    FramePacingSnapshot ReadAndReset()
    {
        // Copy/reset only under the lock; formatting/logging is outside it.
        std::lock_guard<std::mutex> lock(mutex);
        FramePacingSnapshot result = snapshot;
        if (result.intervals)
        {
            result.averageMs = sum / static_cast<double>(result.intervals);
            uint64_t target = result.intervals - result.intervals / 20, count = 0;
            for (unsigned i = 0; i < 256; ++i)
            {
                count += histogram[i];
                if (count >= target) { result.p95UpperMs = i == 255 ? result.maximumMs : i * .5; break; }
            }
        }
        snapshot = {}; sum = lastEnd = 0;
        for (auto &bucket : histogram) bucket = 0;
        return result;
    }
};
static_assert(sizeof(FramePacingSnapshot) == 64, "Pacing snapshot ABI");
}
