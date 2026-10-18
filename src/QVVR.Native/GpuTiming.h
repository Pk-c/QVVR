#pragma once
#include <atomic>
#include <d3d11.h>

namespace qvvr
{
// Nonblocking timestamp queries only; no texture readback or wait/flush.
class GpuTiming
{
    struct Slot
    {
        ID3D11Query *start = nullptr;
        ID3D11Query *end = nullptr;
        ID3D11Query *disjoint = nullptr;
        ID3D11Query *phase[16] = {};
        unsigned phaseMask = 0;
        bool pending = false;
    } slots[8];
    ID3D11DeviceContext *context = nullptr;
    unsigned index = 0;
    bool available = false, active = false;
    std::atomic<double> milliseconds{0};
    std::atomic<bool> detailed{false};
    std::atomic<double> phaseMilliseconds[8] = {};

  public:
    void ConfigureDetailed(bool value) { detailed.store(value); } // Before first render.
    void Mark(unsigned marker)
    {
        if (!active || marker >= 16 || !detailed.load()) return;
        auto &slot = slots[index];
        if (!slot.phase[marker] || (slot.phaseMask & (1u << marker))) return;
        context->End(slot.phase[marker]); slot.phaseMask |= 1u << marker;
    }
    double Phase(unsigned phase) { return phase < 8 ? phaseMilliseconds[phase].load() : 0; }
    void Initialize(ID3D11Texture2D *texture)
    {
        if (context)
            return;
        ID3D11Device *device = nullptr;
        texture->GetDevice(&device);
        device->GetImmediateContext(&context);
        available = true;
        for (auto &slot : slots)
        {
            D3D11_QUERY_DESC desc = {D3D11_QUERY_TIMESTAMP_DISJOINT, 0};
            if (FAILED(device->CreateQuery(&desc, &slot.disjoint)))
                available = false;
            desc.Query = D3D11_QUERY_TIMESTAMP;
            if (FAILED(device->CreateQuery(&desc, &slot.start)) || FAILED(device->CreateQuery(&desc, &slot.end)))
                available = false;
            if (detailed.load()) for (auto &query : slot.phase)
                if (FAILED(device->CreateQuery(&desc, &query))) detailed.store(false);
        }
        device->Release();
    }
    void Begin(ID3D11Texture2D *texture)
    {
        if (active)
            End();
        Initialize(texture);
        active = false;
        if (!available)
            return;
        auto &slot = slots[index];
        if (slot.pending)
        {
            D3D11_QUERY_DATA_TIMESTAMP_DISJOINT frequency = {};
            UINT64 start = 0, end = 0;
            if (context->GetData(slot.disjoint, &frequency, sizeof(frequency), D3D11_ASYNC_GETDATA_DONOTFLUSH) !=
                    S_OK ||
                context->GetData(slot.start, &start, sizeof(start), D3D11_ASYNC_GETDATA_DONOTFLUSH) != S_OK ||
                context->GetData(slot.end, &end, sizeof(end), D3D11_ASYNC_GETDATA_DONOTFLUSH) != S_OK)
                return;
            if (!frequency.Disjoint && frequency.Frequency && end >= start)
            {
                milliseconds.store((end - start) * 1000.0 / frequency.Frequency);
                for (unsigned phase = 0; phase < 8; ++phase)
                {
                    UINT64 a = 0, b = 0; unsigned mask = 3u << (phase * 2);
                    bool ready = (slot.phaseMask & mask) == mask &&
                        context->GetData(slot.phase[phase * 2], &a, sizeof(a), D3D11_ASYNC_GETDATA_DONOTFLUSH) == S_OK &&
                        context->GetData(slot.phase[phase * 2 + 1], &b, sizeof(b), D3D11_ASYNC_GETDATA_DONOTFLUSH) == S_OK;
                    phaseMilliseconds[phase].store(ready && b >= a ? (b - a) * 1000.0 / frequency.Frequency : 0);
                }
            }
            slot.pending = false;
        }
        context->Begin(slot.disjoint);
        slot.phaseMask = 0;
        context->End(slot.start);
        active = true;
    }
    void End()
    {
        if (!active)
            return;
        auto &slot = slots[index];
        context->End(slot.end);
        context->End(slot.disjoint);
        slot.pending = true;
        active = false;
        index = (index + 1) % 8;
    }
    double Latest()
    {
        return milliseconds.load();
    }
};
} // namespace qvvr
