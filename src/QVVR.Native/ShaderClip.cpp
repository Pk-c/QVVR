#include "ShaderClip.h"
#include "CylinderCaps.h"
#include <D3D12TokenizedProgramFormat.hpp>
#include <DxilHash.cpp>
#include <atomic>
#include <cstring>
#include <cstdio>
#include <d3dcompiler.h>
#include <d3d11_1.h>
#include <mutex>
#include <unordered_map>
#include <windows.h>
#ifdef QVVR_CLIP_TEST
#include <cstdio>
#define FAIL_CLIP()                                                                                                    \
    do                                                                                                                 \
    {                                                                                                                  \
        printf("Clip parser failed at %d\n", __LINE__);                                                                \
        return false;                                                                                                  \
    } while (0)
#else
#define FAIL_CLIP() return false
#endif

namespace qvvr
{
namespace
{
using Words = std::vector<unsigned>;
constexpr unsigned Tag(char a, char b, char c, char d)
{
    return a | (b << 8) | (c << 16) | (d << 24);
}
struct Chunk
{
    unsigned tag;
    Words data;
};
unsigned InstructionLength(const Words &code, size_t at)
{
    if (at >= code.size())
        return 0;
    unsigned op = code[at] & 0x7ff;
    if (op == D3D10_SB_OPCODE_CUSTOMDATA)
        return at + 1 < code.size() ? code[at + 1] : 0;
    return (code[at] >> 24) & 127;
}
bool Declaration(unsigned op)
{
    return (op >= D3D10_SB_OPCODE_DCL_RESOURCE && op <= D3D10_SB_OPCODE_DCL_GLOBAL_FLAGS) ||
           op == D3D10_SB_OPCODE_CUSTOMDATA || op == D3D11_SB_OPCODE_DCL_UNORDERED_ACCESS_VIEW_TYPED ||
           op == D3D11_SB_OPCODE_DCL_UNORDERED_ACCESS_VIEW_RAW ||
           op == D3D11_SB_OPCODE_DCL_UNORDERED_ACCESS_VIEW_STRUCTURED || op == D3D11_SB_OPCODE_DCL_RESOURCE_RAW ||
           op == D3D11_SB_OPCODE_DCL_RESOURCE_STRUCTURED;
}
bool ReadChunks(const void *bytes, size_t length, std::vector<Chunk> &chunks)
{
    if (!bytes || length < 32 || length % 4)
        FAIL_CLIP();
    auto w = static_cast<const unsigned *>(bytes);
    if (w[0] != Tag('D', 'X', 'B', 'C') || w[6] != length || w[7] > (length - 32) / 4)
        FAIL_CLIP();
    for (unsigned i = 0; i < w[7]; ++i)
    {
        unsigned offset = w[8 + i];
        if (offset % 4 || offset > length - 8)
            return false;
        auto c = w + offset / 4;
        if (c[1] % 4 || c[1] > length - offset - 8)
            FAIL_CLIP();
        chunks.push_back({c[0], Words(c + 2, c + 2 + c[1] / 4)});
    }
    return true;
}
// Compiler-generated clip prefix is remapped into reserved registers.
bool RemapOperand(Words &w, size_t &at, size_t end, unsigned temps, unsigned input, unsigned cb)
{
    if (at >= end)
        return false;
    unsigned token = w[at++], type = DECODE_D3D10_SB_OPERAND_TYPE(token);
    unsigned extended = token;
    while (extended & 0x80000000u)
    {
        if (at >= end)
            return false;
        extended = w[at++];
    }
    if (type == D3D10_SB_OPERAND_TYPE_IMMEDIATE32 || type == D3D10_SB_OPERAND_TYPE_IMMEDIATE64)
    {
        unsigned components = (token & 3) == 1 ? 1 : 4;
        at += components * (type == D3D10_SB_OPERAND_TYPE_IMMEDIATE64 ? 2 : 1);
        return at <= end;
    }
    unsigned dimensions = DECODE_D3D10_SB_OPERAND_INDEX_DIMENSION(token);
    for (unsigned i = 0; i < dimensions; ++i)
    {
        if (DECODE_D3D10_SB_OPERAND_INDEX_REPRESENTATION(i, token) != D3D10_SB_OPERAND_INDEX_IMMEDIATE32 || at >= end)
            return false;
        if (i == 0)
        {
            if (type == D3D10_SB_OPERAND_TYPE_TEMP)
                w[at] += temps;
            else if (type == D3D10_SB_OPERAND_TYPE_INPUT)
                w[at] = input;
            else if (type == D3D10_SB_OPERAND_TYPE_CONSTANT_BUFFER)
                w[at] = cb;
        }
        ++at;
    }
    return true;
}
const char *PrefixSource = "cbuffer Cylinder:register(b13){float4x4 pixelToLocal;float4 limits;}"
                           "float4 main(float4 p:SV_Position):SV_Target{"
                           "float4 h=mul(pixelToLocal,float4(p.xyz,1));float3 q=h.xyz/h.w;"
                           "clip(min(limits.x-dot(q.xz,q.xz),limits.y-abs(q.y)));"
                           "float fade=1;[branch]if(limits.z>0){"
                           "float d=min(sqrt(limits.x)-length(q.xz),limits.y-abs(q.y));"
                           "float t=saturate(d/limits.z);fade=t*t*(3-2*t);}return fade.xxxx;}";
// Redirect only SV_Target0 operands to a reserved temporary. Outputs are
// write-only in DXBC: fading by reading o0 itself would be invalid. Original
// material arithmetic/resources/control flow stay unchanged, including MRTs.
bool RedirectColorOperand(Words &w, size_t &at, size_t end, unsigned colorTemp)
{
    if (at >= end) return false;
    size_t start = at;
    unsigned token = w[at++], type = DECODE_D3D10_SB_OPERAND_TYPE(token), extended = token;
    while (extended & 0x80000000u)
    {
        if (at >= end) return false;
        extended = w[at++];
    }
    if (type == D3D10_SB_OPERAND_TYPE_IMMEDIATE32 || type == D3D10_SB_OPERAND_TYPE_IMMEDIATE64)
    {
        unsigned components = token & 3;
        if (components != 1 && components != 2) return false;
        at += (components == 1 ? 1 : 4) * (type == D3D10_SB_OPERAND_TYPE_IMMEDIATE64 ? 2 : 1);
        return at <= end;
    }
    unsigned dimensions = DECODE_D3D10_SB_OPERAND_INDEX_DIMENSION(token);
    for (unsigned i = 0; i < dimensions; ++i)
    {
        unsigned representation = DECODE_D3D10_SB_OPERAND_INDEX_REPRESENTATION(i, token);
        bool immediate32 = representation == D3D10_SB_OPERAND_INDEX_IMMEDIATE32 ||
            representation == D3D10_SB_OPERAND_INDEX_IMMEDIATE32_PLUS_RELATIVE;
        bool immediate64 = representation == D3D10_SB_OPERAND_INDEX_IMMEDIATE64 ||
            representation == D3D10_SB_OPERAND_INDEX_IMMEDIATE64_PLUS_RELATIVE;
        if (immediate32 || immediate64)
        {
            if (at + (immediate64 ? 2 : 1) > end) return false;
            if (i == 0 && type == D3D10_SB_OPERAND_TYPE_OUTPUT && dimensions == 1 && immediate32 && w[at] == 0)
            {
                w[start] = (token & ~(0xffu << 12)) | (D3D10_SB_OPERAND_TYPE_TEMP << 12);
                w[at] = colorTemp;
            }
            at += immediate64 ? 2 : 1;
        }
        if (representation == D3D10_SB_OPERAND_INDEX_RELATIVE ||
            representation == D3D10_SB_OPERAND_INDEX_IMMEDIATE32_PLUS_RELATIVE ||
            representation == D3D10_SB_OPERAND_INDEX_IMMEDIATE64_PLUS_RELATIVE)
            if (!RedirectColorOperand(w, at, end, colorTemp)) return false;
    }
    return at <= end;
}
void Emit(Words &code, unsigned op, std::initializer_list<Words> operands)
{
    size_t start = code.size();
    code.push_back(op);
    for (const auto &operand : operands) code.insert(code.end(), operand.begin(), operand.end());
    code[start] |= static_cast<unsigned>(code.size() - start) << 24;
}
Words donorCode;
std::once_flag donorOnce;
void CompileDonor()
{
    ID3DBlob *blob = nullptr;
    ID3DBlob *errors = nullptr;
    HRESULT result = D3DCompile(PrefixSource, strlen(PrefixSource), nullptr, nullptr, nullptr, "main", "ps_4_0",
                                D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &blob, &errors);
    if (errors)
        errors->Release();
    if (FAILED(result))
        return;
#ifdef QVVR_CLIP_TEST
    ID3DBlob *dis = nullptr;
    D3DDisassemble(blob->GetBufferPointer(), blob->GetBufferSize(), 0, nullptr, &dis);
    if (dis)
    {
        printf("Donor:\n%s\n", static_cast<const char *>(dis->GetBufferPointer()));
        dis->Release();
    }
#endif
    std::vector<Chunk> chunks;
    if (ReadChunks(blob->GetBufferPointer(), blob->GetBufferSize(), chunks))
        for (auto &c : chunks)
            if (c.tag == Tag('S', 'H', 'D', 'R') || c.tag == Tag('S', 'H', 'E', 'X'))
                donorCode = c.data;
    blob->Release();
}
} // namespace

bool PatchCylinderShader(const void *bytes, size_t length, std::vector<std::uint8_t> &output, unsigned &bufferSlot,
                         bool opaque, bool premultiplied)
{
    std::call_once(donorOnce, CompileDonor);
    if (donorCode.empty())
        return false;
    std::vector<Chunk> chunks;
    if (!ReadChunks(bytes, length, chunks))
        return false;
    Chunk *code = nullptr;
    Chunk *sig = nullptr;
    for (auto &c : chunks)
    {
        if (c.tag == Tag('S', 'H', 'D', 'R') || c.tag == Tag('S', 'H', 'E', 'X'))
            code = &c;
        if (c.tag == Tag('I', 'S', 'G', 'N'))
            sig = &c;
    }
    // Unity 2019 D3D11 uses ISGN. Unsupported signatures fail closed.
    if (!code || !sig || sig->data.size() < 2 || code->data.size() < 2 || (code->data[0] >> 16) != 0)
        FAIL_CLIP();
    unsigned count = sig->data[0];
    if (2 + count * 6 > sig->data.size())
        return false;
    unsigned occupied = 0, position = 32, originalTemps = 0, occupiedCb = 0;
    for (unsigned i = 0; i < count; ++i)
    {
        auto entry = &sig->data[2 + i * 6];
        if (entry[4] < 32)
            occupied |= 1u << entry[4];
        if (entry[2] == D3D_NAME_POSITION)
            position = entry[4];
    }
    bool addPosition = position == 32;
    if (addPosition)
    {
        for (position = 0; position < 32 && (occupied & (1u << position)); ++position)
        {
        }
        if (position == 32)
            return false;
    }
    Words declarations, instructions;
    bool positionDeclared = false;
    for (size_t at = 2; at < code->data.size();)
    {
        unsigned token = code->data[at], op = token & 0x7ff, len = InstructionLength(code->data, at);
        if (!len || at + len > code->data.size())
            return false;
        if (op == D3D10_SB_OPCODE_DCL_TEMPS)
            originalTemps = code->data[at + 1];
        if (op == D3D10_SB_OPCODE_DCL_CONSTANT_BUFFER)
            occupiedCb |= 1u << code->data[at + 2];
        if (op == D3D10_SB_OPCODE_DCL_INPUT_PS_SIV && len >= 4 &&
            code->data[at + 2] == position && code->data[at + 3] == D3D_NAME_POSITION)
            positionDeclared = true;
        at += len;
    }
    for (bufferSlot = 13; bufferSlot > 0 && (occupiedCb & (1u << bufferSlot)); --bufferSlot)
    {
    }
    if (occupiedCb & (1u << bufferSlot))
        return false;
    unsigned donorTemps = 0;
    Words fadeSource;
    for (size_t at = 2; at < donorCode.size();)
    {
        unsigned token = donorCode[at], op = token & 0x7ff, len = (token >> 24) & 127;
        if (!len || at + len > donorCode.size())
            return false;
        if (op == D3D10_SB_OPCODE_DCL_TEMPS)
            donorTemps = donorCode[at + 1];
        // Unity retains unused SV_Position in ISGN but removes its declaration
        // from the optimized shader body. Signature presence is not sufficient:
        // the injected reads must also have an actual system-value declaration.
        else if (op == D3D10_SB_OPCODE_DCL_CONSTANT_BUFFER ||
                 (op == D3D10_SB_OPCODE_DCL_INPUT_PS_SIV && !positionDeclared))
        {
            Words ins(donorCode.begin() + at, donorCode.begin() + at + len);
            size_t operand = 1;
            if (!RemapOperand(ins, operand, ins.size(), originalTemps, position, bufferSlot))
                FAIL_CLIP();
            declarations.insert(declarations.end(), ins.begin(), ins.end());
        }
        else if (op < D3D10_SB_OPCODE_DCL_RESOURCE && op != D3D10_SB_OPCODE_RET)
        {
            // Donor's final constant-color output is not part of clipping.
            bool outputOperand =
                len > 1 && DECODE_D3D10_SB_OPERAND_TYPE(donorCode[at + 1]) == D3D10_SB_OPERAND_TYPE_OUTPUT;
            if (outputOperand && op == D3D10_SB_OPCODE_MOV && len == 5)
            {
                fadeSource.assign(donorCode.begin() + at + 3, donorCode.begin() + at + len);
                size_t operand = 0;
                if (!RemapOperand(fadeSource, operand, fadeSource.size(), originalTemps, position, bufferSlot)) return false;
            }
            if (!outputOperand)
            {
                Words ins(donorCode.begin() + at, donorCode.begin() + at + len);
                size_t operand = 1;
                while (operand < ins.size())
                    if (!RemapOperand(ins, operand, ins.size(), originalTemps, position, bufferSlot))
                        FAIL_CLIP();
                instructions.insert(instructions.end(), ins.begin(), ins.end());
            }
        }
        at += len;
    }
    if (fadeSource.empty()) return false;
    const unsigned colorTemp = originalTemps + donorTemps, scratchTemp = colorTemp + 1;
    Words combined = {code->data[0], 0};
    size_t firstBody = 2;
    bool hadTemps = false;
    while (firstBody < code->data.size())
    {
        unsigned token = code->data[firstBody], op = token & 0x7ff, len = InstructionLength(code->data, firstBody);
        if (!Declaration(op))
            break;
        Words ins(code->data.begin() + firstBody, code->data.begin() + firstBody + len);
        if (op == D3D10_SB_OPCODE_DCL_TEMPS)
        {
            ins[1] = originalTemps + donorTemps + 2;
            hadTemps = true;
        }
        if (op == D3D10_SB_OPCODE_DCL_GLOBAL_FLAGS)
            ins[0] &= ~D3D11_SB_GLOBAL_FLAG_FORCE_EARLY_DEPTH_STENCIL;
        if (op == D3D10_SB_OPCODE_DCL_OUTPUT && ins.size() >= 3 && ins[2] == 0)
            ins[1] = (ins[1] & ~0xf0u) | 0xf0u;
        // Existing SV_Position may declare only z/w. Prefix needs all xyz.
        if (op == D3D10_SB_OPCODE_DCL_INPUT_PS_SIV && ins.size() >= 4 && ins[2] == position &&
            ins[3] == D3D_NAME_POSITION)
            ins[1] = (ins[1] & ~0xf0u) | 0xf0u;
        combined.insert(combined.end(), ins.begin(), ins.end());
        firstBody += len;
    }
    if (!hadTemps)
    {
        combined.push_back((2u << 24) | D3D10_SB_OPCODE_DCL_TEMPS);
        combined.push_back(donorTemps + 2);
    }
    combined.insert(combined.end(), declarations.begin(), declarations.end());
    combined.insert(combined.end(), instructions.begin(), instructions.end());
    bool target0 = false;
    for (auto &c : chunks)
        if (c.tag == Tag('O', 'S', 'G', 'N'))
            for (unsigned i = 0; i < c.data[0]; ++i)
                if (c.data[2 + i * 6 + 4] == 0)
                    target0 = true;
    for (size_t at = firstBody; at < code->data.size();)
    {
        unsigned op = code->data[at] & 0x7ff, len = InstructionLength(code->data, at);
        if (!len || at + len > code->data.size())
            return false;
        if (target0 && (op == D3D10_SB_OPCODE_RET || op == D3D10_SB_OPCODE_RETC))
        {
            Words color = {0x00100e46, colorTemp}, alpha = {0x00100ff6, colorTemp};
            if (opaque)
            {
                // Premultiplied coverage, preserving depth/opaque ordering.
                // In opaque green fallback only, fade RGB into that void color.
                Emit(combined, D3D10_SB_OPCODE_MUL, {{0x00100072, scratchTemp}, color, fadeSource});
                Emit(combined, D3D10_SB_OPCODE_MOV, {{0x00102072, 0}, {0x00100e46, scratchTemp}});
                Emit(combined, D3D10_SB_OPCODE_MAD, {{0x00100082, scratchTemp}, fadeSource,
                    {0x00004001, 0xbf800000}, {0x00004001, 0x3f800000}});
                Emit(combined, D3D10_SB_OPCODE_MAD, {{0x00102022, 0}, {0x00100ff6, scratchTemp},
                    {0x00208ff6, bufferSlot, 4}, {0x00100556, scratchTemp}});
                Emit(combined, D3D10_SB_OPCODE_MOV, {{0x00102082, 0}, fadeSource});
            }
            else
            {
                // Straight-alpha blend multiplies RGB itself; ONE/premultiplied
                // blend needs shader RGB attenuation. Never apply fade twice.
                if (premultiplied) Emit(combined, D3D10_SB_OPCODE_MUL, {{0x00102072, 0}, color, fadeSource});
                else Emit(combined, D3D10_SB_OPCODE_MOV, {{0x00102072, 0}, color});
                Emit(combined, D3D10_SB_OPCODE_MUL, {{0x00102082, 0}, alpha, fadeSource});
            }
        }
        Words ins(code->data.begin() + at, code->data.begin() + at + len);
        if (target0 && op != D3D10_SB_OPCODE_CUSTOMDATA)
        {
            size_t operand = 1;
            unsigned extended = ins[0];
            while (extended & 0x80000000u)
            {
                if (operand >= ins.size()) return false;
                extended = ins[operand++];
            }
            while (operand < ins.size())
                if (!RedirectColorOperand(ins, operand, ins.size(), colorTemp)) return false;
        }
        combined.insert(combined.end(), ins.begin(), ins.end());
        at += len;
    }
    combined[1] = static_cast<unsigned>(combined.size());
    code->data = std::move(combined);
    if (addPosition)
    {
        // Entries precede string storage. Relocate all existing name offsets.
        Words signature = {count + 1, sig->data[1]};
        for (unsigned i = 0; i < count; ++i)
        {
            for (unsigned j = 0; j < 6; ++j)
                signature.push_back(sig->data[2 + i * 6 + j] + (j == 0 ? 24 : 0));
        }
        unsigned nameOffset = static_cast<unsigned>((sig->data.size() + 6) * 4);
        unsigned entry[] = {nameOffset, 0, D3D_NAME_POSITION, D3D_REGISTER_COMPONENT_FLOAT32, position, 0x00000f0f};
        signature.insert(signature.end(), entry, entry + 6);
        signature.insert(signature.end(), sig->data.begin() + 2 + count * 6, sig->data.end());
        const char name[12] = "SV_Position";
        auto nameWords = reinterpret_cast<const unsigned *>(name);
        signature.insert(signature.end(), nameWords, nameWords + 3);
        sig->data = std::move(signature);
    }
    else
    {
        for (unsigned i = 0; i < count; ++i)
            if (sig->data[2 + i * 6 + 2] == D3D_NAME_POSITION)
                sig->data[2 + i * 6 + 5] = 0x00000f0f;
    }
    if (target0)
        for (auto &c : chunks)
            if (c.tag == Tag('O', 'S', 'G', 'N'))
                for (unsigned i = 0; i < c.data[0]; ++i)
                    if (c.data[2 + i * 6 + 4] == 0)
                        c.data[2 + i * 6 + 5] = 0x0000000f;
    Words container = {Tag('D', 'X', 'B', 'C'), 0, 0, 0, 0, 1, 0, static_cast<unsigned>(chunks.size())};
    container.resize(8 + chunks.size());
    for (size_t i = 0; i < chunks.size(); ++i)
    {
        container[8 + i] = static_cast<unsigned>(container.size() * 4);
        container.push_back(chunks[i].tag);
        container.push_back(static_cast<unsigned>(chunks[i].data.size() * 4));
        container.insert(container.end(), chunks[i].data.begin(), chunks[i].data.end());
    }
    container[6] = static_cast<unsigned>(container.size() * 4);
    auto start = reinterpret_cast<const std::uint8_t *>(container.data());
    ComputeHashRetail(start + 20, static_cast<UINT>(container.size() * 4 - 20),
                      reinterpret_cast<BYTE *>(container.data() + 1));
    output.assign(start, start + container.size() * 4);
    return true;
}

namespace
{
using CreatePS = HRESULT(STDMETHODCALLTYPE *)(ID3D11Device *, const void *, SIZE_T, ID3D11ClassLinkage *,
                                              ID3D11PixelShader **);
using SetPS = void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, ID3D11PixelShader *, ID3D11ClassInstance *const *, UINT);
using SetCB = void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, UINT, UINT, ID3D11Buffer *const *);
using SetBlend = void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, ID3D11BlendState *, const FLOAT[4], UINT);
using CreateBlend = HRESULT(STDMETHODCALLTYPE *)(ID3D11Device *, const D3D11_BLEND_DESC *, ID3D11BlendState **);
using Draw = void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, UINT, UINT);
using DrawIndexed = void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, UINT, UINT, INT);
using DrawIndexedInstanced = void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, UINT, UINT, UINT, INT, UINT);
using DrawIndexedIndirect = void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, ID3D11Buffer *, UINT);
using SetTargets = void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, UINT, ID3D11RenderTargetView *const *,
                                             ID3D11DepthStencilView *);
using SetTargetsUav = void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, UINT, ID3D11RenderTargetView *const *,
                                                ID3D11DepthStencilView *, UINT, UINT,
                                                ID3D11UnorderedAccessView *const *, const UINT *);
CreatePS originalCreate = nullptr;
SetPS originalSet = nullptr;
SetCB originalCB = nullptr;
SetBlend originalBlend = nullptr;
CreateBlend originalCreateBlend = nullptr;
Draw originalDraw = nullptr;
DrawIndexed originalDrawIndexed = nullptr;
DrawIndexedInstanced originalDrawIndexedInstanced = nullptr;
DrawIndexedIndirect originalDrawIndexedIndirect = nullptr;
qvvr::CylinderCaps cylinderCaps;
bool internalCapDraw = false;
bool capShaderSupported = false;
SetTargets originalTargets = nullptr;
SetTargetsUav originalTargetsUav = nullptr;
ID3D11Texture2D *clipTargets[2] = {};
std::mutex targetMutex;
bool worldTarget = false;
struct Variant
{
    ID3D11PixelShader *shader;
    ID3D11PixelShader *opaque;
    ID3D11PixelShader *premultiplied;
    unsigned slot;
};
std::unordered_map<ID3D11PixelShader *, Variant> variants;
std::unordered_map<ID3D11BlendState *, ID3D11BlendState *> blends;
std::mutex variantMutex;
std::mutex blendMutex;
struct DiagnosticBytecode { std::vector<std::uint8_t> original, clipped, opaque, premultiplied; };
// Cold resource-creation cache, deliberately separate from the small Variant
// copied in HookSet. Never copy a vector in the per-draw render path.
std::unordered_map<ID3D11PixelShader *, DiagnosticBytecode> diagnosticShaders;
ID3D11DeviceContext *context = nullptr;
ID3D11DeviceContext1 *diagnosticContext = nullptr;
ID3D11Buffer *clipBuffer = nullptr;
ID3D11PixelShader *discardShader = nullptr;
ID3D11PixelShader *depthClipShader = nullptr;
ID3D11PixelShader *savedShader = nullptr;
ID3D11ClassInstance *savedClasses[256] = {};
UINT savedClassCount = 0;
ID3D11Buffer *savedBuffers[14] = {};
std::atomic<bool> clipping(false);
bool opaqueDraw = true;
bool premultipliedDraw = false;
ID3D11PixelShader *requestedShader = nullptr;
ID3D11BlendState *savedBlend = nullptr;
FLOAT savedFactors[4] = {};
UINT savedSampleMask = 0;
unsigned activeBuffer = 13;
std::atomic<unsigned> patchedCount(0), rejectedCount(0), unknownCount(0);
std::atomic<unsigned> depthOnlyCount(0);
std::atomic<unsigned> materialBindCount(0), otherContextBindCount(0);
// All memory and staging resources are reserved at installation. Capture a
// single real world draw, not a frame loop; read only GPU constant buffers.
constexpr unsigned DiagnosticSlots = 14, DiagnosticBytes = 65536;
ID3D11Buffer *diagnosticStaging[DiagnosticSlots] = {};
ID3D11Query *diagnosticQuery = nullptr;
ID3D11Buffer *diagnosticPixelStaging = nullptr;
struct ClipDiagnostic
{
    unsigned magic = 0x51564344, version = 2;
    ClipParameters parameters = {};
    D3D11_VIEWPORT viewport = {};
    unsigned sizes[DiagnosticSlots] = {};
    unsigned firstConstants[DiagnosticSlots] = {};
    unsigned char data[DiagnosticSlots][DiagnosticBytes] = {};
} diagnostic;
constexpr unsigned DiagnosticShaderBytes = 262144;
struct PixelDiagnostic
{
    unsigned slot = 0, firstConstant = 0, bytes = 0, expectedBinding = 0;
    ClipParameters gpuParameters = {};
    unsigned originalSize = 0, clippedSize = 0;
    unsigned char original[DiagnosticShaderBytes] = {}, clipped[DiagnosticShaderBytes] = {};
} pixelDiagnostic;
std::atomic<bool> diagnosticReady(false);
bool diagnosticArmed = false, diagnosticPending = false, diagnosticCaptured = false;
void RestoreDiagnosticDrawHooks();
void CaptureWorldConstants(ID3D11DeviceContext *ctx)
{
    if (ctx != context || !clipping || !worldTarget || !diagnosticArmed || diagnosticCaptured || !requestedShader)
        return;
    ID3D11Buffer *buffers[DiagnosticSlots] = {};
    unsigned constantCounts[DiagnosticSlots] = {};
    if (diagnosticContext)
        diagnosticContext->VSGetConstantBuffers1(0, DiagnosticSlots, buffers, diagnostic.firstConstants, constantCounts);
    else ctx->VSGetConstantBuffers(0, DiagnosticSlots, buffers);
    unsigned viewportCount = 1;
    ctx->RSGetViewports(&viewportCount, &diagnostic.viewport);
    for (unsigned i = 0; i < DiagnosticSlots; ++i)
    {
        if (!buffers[i]) continue;
        D3D11_BUFFER_DESC desc = {};
        buffers[i]->GetDesc(&desc);
        unsigned offset = diagnostic.firstConstants[i] * 16;
        if (offset < desc.ByteWidth)
        {
            unsigned size = desc.ByteWidth - offset;
            if (size > DiagnosticBytes) size = DiagnosticBytes;
            if (diagnosticContext && size > constantCounts[i] * 16) size = constantCounts[i] * 16;
            diagnostic.sizes[i] = size;
            D3D11_BOX box = {offset, 0, 0, offset + size, 1, 1};
            ctx->CopySubresourceRegion(diagnosticStaging[i], 0, 0, 0, 0, buffers[i], 0, &box);
        }
        buffers[i]->Release();
    }
    pixelDiagnostic.slot = activeBuffer;
    ID3D11Buffer *pixelBuffer = nullptr;
    unsigned pixelCount = 0;
    if (diagnosticContext)
        diagnosticContext->PSGetConstantBuffers1(activeBuffer, 1, &pixelBuffer, &pixelDiagnostic.firstConstant, &pixelCount);
    else ctx->PSGetConstantBuffers(activeBuffer, 1, &pixelBuffer);
    if (pixelBuffer)
    {
        D3D11_BUFFER_DESC desc = {};
        pixelBuffer->GetDesc(&desc);
        unsigned offset = pixelDiagnostic.firstConstant * 16;
        if (offset < desc.ByteWidth)
        {
            unsigned size = desc.ByteWidth - offset;
            if (size > sizeof(ClipParameters)) size = sizeof(ClipParameters);
            if (diagnosticContext && size > pixelCount * 16) size = pixelCount * 16;
            pixelDiagnostic.bytes = size;
            D3D11_BOX box = {offset, 0, 0, offset + size, 1, 1};
            if (size) ctx->CopySubresourceRegion(diagnosticPixelStaging, 0, 0, 0, 0, pixelBuffer, 0, &box);
        }
        pixelBuffer->Release();
    }
    ID3D11PixelShader *bound = nullptr;
    ctx->PSGetShader(&bound, nullptr, nullptr);
    {
        std::lock_guard<std::mutex> lock(variantMutex);
        auto variant = variants.find(requestedShader);
        if (variant != variants.end())
            pixelDiagnostic.expectedBinding = bound == (opaqueDraw ? variant->second.opaque :
                premultipliedDraw ? variant->second.premultiplied : variant->second.shader);
        auto code = diagnosticShaders.find(requestedShader);
        if (code != diagnosticShaders.end())
        {
            const auto &selected = opaqueDraw ? code->second.opaque :
                premultipliedDraw ? code->second.premultiplied : code->second.clipped;
            if (code->second.original.size() <= DiagnosticShaderBytes && selected.size() <= DiagnosticShaderBytes)
            {
                pixelDiagnostic.originalSize = static_cast<unsigned>(code->second.original.size());
                pixelDiagnostic.clippedSize = static_cast<unsigned>(selected.size());
                memcpy(pixelDiagnostic.original, code->second.original.data(), pixelDiagnostic.originalSize);
                memcpy(pixelDiagnostic.clipped, selected.data(), pixelDiagnostic.clippedSize);
            }
        }
    }
    if (bound) bound->Release();
    ctx->End(diagnosticQuery);
    diagnosticCaptured = diagnosticPending = true;
    RestoreDiagnosticDrawHooks();
}
void CollectWorldConstants()
{
    if (!diagnosticPending || context->GetData(diagnosticQuery, nullptr, 0, D3D11_ASYNC_GETDATA_DONOTFLUSH) != S_OK)
        return;
    for (unsigned i = 0; i < DiagnosticSlots; ++i)
    {
        if (!diagnostic.sizes[i]) continue;
        D3D11_MAPPED_SUBRESOURCE mapped = {};
        HRESULT hr = context->Map(diagnosticStaging[i], 0, D3D11_MAP_READ, D3D11_MAP_FLAG_DO_NOT_WAIT, &mapped);
        if (hr != S_OK)
        {
#ifdef QVVR_CLIP_TEST
            printf("Diagnostic Map failed: %08x\n", static_cast<unsigned>(hr));
#endif
            return;
        }
        memcpy(diagnostic.data[i], mapped.pData, diagnostic.sizes[i]);
        context->Unmap(diagnosticStaging[i], 0);
    }
    if (pixelDiagnostic.bytes)
    {
        D3D11_MAPPED_SUBRESOURCE mapped = {};
        if (context->Map(diagnosticPixelStaging, 0, D3D11_MAP_READ, D3D11_MAP_FLAG_DO_NOT_WAIT, &mapped) != S_OK) return;
        memcpy(&pixelDiagnostic.gpuParameters, mapped.pData, pixelDiagnostic.bytes);
        context->Unmap(diagnosticPixelStaging, 0);
    }
    diagnosticPending = false;
    diagnosticReady.store(true, std::memory_order_release);
}
void STDMETHODCALLTYPE HookDraw(ID3D11DeviceContext *ctx, UINT count, UINT start)
{
    if (internalCapDraw) { originalDraw(ctx, count, start); return; }
    CaptureWorldConstants(ctx);
    originalDraw(ctx, count, start);
}
bool BeginCapVolume(ID3D11DeviceContext *ctx)
{
    if (ctx != context || !clipping || !worldTarget || !cylinderCaps.Active()) return false;
    internalCapDraw = true;
    bool volume = opaqueDraw && capShaderSupported && cylinderCaps.BeforeVolume(requestedShader);
    if (!volume) internalCapDraw = false;
    return volume;
}
void EndCapVolume()
{
    cylinderCaps.AfterVolume(); internalCapDraw = false;
}
void STDMETHODCALLTYPE HookDrawIndexed(ID3D11DeviceContext *ctx, UINT count, UINT start, INT base)
{
    if (internalCapDraw) { originalDrawIndexed(ctx, count, start, base); return; }
    CaptureWorldConstants(ctx);
    if (BeginCapVolume(ctx)) { originalDrawIndexed(ctx, count, start, base); EndCapVolume(); }
    originalDrawIndexed(ctx, count, start, base);
}
void STDMETHODCALLTYPE HookDrawIndexedInstanced(ID3D11DeviceContext *ctx, UINT count, UINT instances, UINT start, INT base, UINT first)
{
    if (internalCapDraw) { originalDrawIndexedInstanced(ctx, count, instances, start, base, first); return; }
    CaptureWorldConstants(ctx);
    if (BeginCapVolume(ctx)) { originalDrawIndexedInstanced(ctx, count, instances, start, base, first); EndCapVolume(); }
    originalDrawIndexedInstanced(ctx, count, instances, start, base, first);
}
void STDMETHODCALLTYPE HookDrawIndexedIndirect(ID3D11DeviceContext *ctx, ID3D11Buffer *args, UINT offset)
{
    if (internalCapDraw) { originalDrawIndexedIndirect(ctx, args, offset); return; }
    CaptureWorldConstants(ctx);
    if (BeginCapVolume(ctx)) { originalDrawIndexedIndirect(ctx, args, offset); EndCapVolume(); }
    originalDrawIndexedIndirect(ctx, args, offset);
}
bool Replace(void **table, unsigned index, void *function, void **original);
void RestoreDiagnosticDrawHooks()
{
    if (cylinderCaps.Active()) return;
    auto table = *reinterpret_cast<void ***>(context);
    void *ignored = nullptr;
    if (table[12] == reinterpret_cast<void *>(&HookDrawIndexed))
        Replace(table, 12, reinterpret_cast<void *>(originalDrawIndexed), &ignored);
    if (table[13] == reinterpret_cast<void *>(&HookDraw))
        Replace(table, 13, reinterpret_cast<void *>(originalDraw), &ignored);
    if (table[20] == reinterpret_cast<void *>(&HookDrawIndexedInstanced))
        Replace(table, 20, reinterpret_cast<void *>(originalDrawIndexedInstanced), &ignored);
    if (table[39] == reinterpret_cast<void *>(&HookDrawIndexedIndirect))
        Replace(table, 39, reinterpret_cast<void *>(originalDrawIndexedIndirect), &ignored);
}
void ArmDiagnosticDrawHooks()
{
    if (internalCapDraw || ((!diagnosticArmed || diagnosticCaptured) && !cylinderCaps.Active())) return;
    // The D3D11 runtime specializes its Draw entry points when shaders/states
    // change. Refresh only while this single snapshot is waiting for a draw.
    auto table = *reinterpret_cast<void ***>(context);
    if (table[12] != reinterpret_cast<void *>(&HookDrawIndexed))
        Replace(table, 12, reinterpret_cast<void *>(&HookDrawIndexed), reinterpret_cast<void **>(&originalDrawIndexed));
    if (table[13] != reinterpret_cast<void *>(&HookDraw))
        Replace(table, 13, reinterpret_cast<void *>(&HookDraw), reinterpret_cast<void **>(&originalDraw));
    if (cylinderCaps.Active())
    {
        if (table[20] != reinterpret_cast<void *>(&HookDrawIndexedInstanced))
            Replace(table, 20, reinterpret_cast<void *>(&HookDrawIndexedInstanced), reinterpret_cast<void **>(&originalDrawIndexedInstanced));
        if (table[39] != reinterpret_cast<void *>(&HookDrawIndexedIndirect))
            Replace(table, 39, reinterpret_cast<void *>(&HookDrawIndexedIndirect), reinterpret_cast<void **>(&originalDrawIndexedIndirect));
    }
}
HRESULT STDMETHODCALLTYPE HookCreate(ID3D11Device *device, const void *bytes, SIZE_T size, ID3D11ClassLinkage *linkage,
                                     ID3D11PixelShader **shader)
{
    HRESULT hr = originalCreate(device, bytes, size, linkage, shader);
    if (SUCCEEDED(hr) && shader && *shader)
    {
        Variant v = {discardShader, discardShader, discardShader, 13};
        std::vector<std::uint8_t> code;
        DiagnosticBytecode capture;
        bool supported = !linkage && PatchCylinderShader(bytes, size, code, v.slot) &&
            SUCCEEDED(originalCreate(device, code.data(), code.size(), nullptr, &v.shader));
        if (supported) capture.clipped = code;
        supported = supported && PatchCylinderShader(bytes, size, code, v.slot, true) &&
            SUCCEEDED(originalCreate(device, code.data(), code.size(), nullptr, &v.opaque));
        if (supported) capture.opaque = code;
        supported = supported && PatchCylinderShader(bytes, size, code, v.slot, false, true) &&
            SUCCEEDED(originalCreate(device, code.data(), code.size(), nullptr, &v.premultiplied));
        if (supported)
        {
            capture.premultiplied = std::move(code);
            auto start = static_cast<const std::uint8_t *>(bytes);
            capture.original.assign(start, start + size);
            ++patchedCount;
        }
        else
        {
            if (v.shader != discardShader)
                v.shader->Release();
            if (v.opaque != discardShader) v.opaque->Release();
            if (v.premultiplied != discardShader) v.premultiplied->Release();
            v.shader = v.opaque = v.premultiplied = discardShader;
            ++rejectedCount;
        }
        // Keep original alive until process shutdown, preventing pointer reuse.
        std::lock_guard<std::mutex> lock(variantMutex);
        if (supported) diagnosticShaders.emplace(*shader, std::move(capture));
        if (variants.emplace(*shader, v).second)
            (*shader)->AddRef();
        else
        {
            if (v.shader != discardShader)
                v.shader->Release();
            if (v.opaque != discardShader)
                v.opaque->Release();
            if (v.premultiplied != discardShader) v.premultiplied->Release();
        }
    }
    return hr;
}
HRESULT STDMETHODCALLTYPE HookCreateBlend(ID3D11Device *device, const D3D11_BLEND_DESC *desc, ID3D11BlendState **state)
{
    HRESULT hr = originalCreateBlend(device, desc, state);
    if (SUCCEEDED(hr) && desc && state && *state)
    {
        D3D11_BLEND_DESC fixed = *desc;
        auto &rt = fixed.RenderTarget[0];
        if (rt.RenderTargetWriteMask & 7)
            rt.RenderTargetWriteMask |= D3D11_COLOR_WRITE_ENABLE_ALPHA;
        if (rt.BlendEnable)
        {
            rt.SrcBlendAlpha = D3D11_BLEND_ONE;
            rt.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
            rt.BlendOpAlpha = D3D11_BLEND_OP_ADD;
        }
        ID3D11BlendState *variant = nullptr;
        if (SUCCEEDED(originalCreateBlend(device, &fixed, &variant)))
        {
            std::lock_guard<std::mutex> lock(blendMutex);
            if (blends.emplace(*state, variant).second)
                (*state)->AddRef();
            else
                variant->Release();
        }
    }
    return hr;
}
void STDMETHODCALLTYPE HookSet(ID3D11DeviceContext *ctx, ID3D11PixelShader *shader, ID3D11ClassInstance *const *classes,
                               UINT count)
{
    if (internalCapDraw) { originalSet(ctx, shader, classes, count); return; }
    if (clipping && ctx != context)
        ++otherContextBindCount;
    if (ctx == context)
        requestedShader = shader;
    if (ctx == context && clipping && worldTarget)
    {
        Variant v = {discardShader, discardShader, discardShader, 13};
        if (!shader)
        {
            // A null PS is a valid depth-only pass, not an unknown material.
            // Preserve interior depth (and no color output) so later Equal
            // passes render, but still discard exterior occluders.
            v.shader = v.opaque = v.premultiplied = depthClipShader;
            ++depthOnlyCount;
        }
        else
        {
            std::lock_guard<std::mutex> lock(variantMutex);
            auto it = variants.find(shader);
            if (it != variants.end())
            {
                v = it->second;
                ++materialBindCount;
            }
            else
                ++unknownCount;
        }
        if (activeBuffer != v.slot)
            originalCB(ctx, activeBuffer, 1, &savedBuffers[activeBuffer]);
        activeBuffer = v.slot;
        originalCB(ctx, activeBuffer, 1, &clipBuffer);
        originalSet(ctx, opaqueDraw ? v.opaque : premultipliedDraw ? v.premultiplied : v.shader, nullptr, 0);
        capShaderSupported = !shader || v.shader != discardShader;
    }
    else
    {
        if (ctx == context && clipping)
            originalCB(ctx, activeBuffer, 1, &savedBuffers[activeBuffer]);
        originalSet(ctx, shader, classes, count);
    }
    if (ctx == context) ArmDiagnosticDrawHooks();
}
void STDMETHODCALLTYPE HookBlend(ID3D11DeviceContext *ctx, ID3D11BlendState *state, const FLOAT factors[4], UINT mask);
bool IsWorldTarget(ID3D11RenderTargetView *view)
{
    if (!view)
        return false;
    ID3D11Resource *resource = nullptr;
    view->GetResource(&resource);
    bool result;
    {
        std::lock_guard<std::mutex> lock(targetMutex);
        result = resource == clipTargets[0] || resource == clipTargets[1];
    }
    if (resource)
        resource->Release();
    return result;
}
void UpdateTarget(ID3D11DeviceContext *ctx, UINT count, ID3D11RenderTargetView *const *views)
{
    if (ctx != context || !clipping)
        return;
    worldTarget = count > 0 && views && IsWorldTarget(views[0]);
    // Corrected variants apply only to the eye color target, not shadow maps
    // and auxiliary targets created inside Camera.Render.
    HookBlend(ctx, savedBlend, savedFactors, savedSampleMask);
}
void STDMETHODCALLTYPE HookTargets(ID3D11DeviceContext *ctx, UINT count, ID3D11RenderTargetView *const *views,
                                   ID3D11DepthStencilView *depth)
{
    if (!internalCapDraw && ctx == context && clipping && worldTarget && cylinderCaps.Active() &&
        (!depth || !count || !views || !IsWorldTarget(views[0])))
    { internalCapDraw = true; cylinderCaps.Composite(); internalCapDraw = false; }
    originalTargets(ctx, count, views, depth);
    if (!internalCapDraw) UpdateTarget(ctx, count, views);
}
void STDMETHODCALLTYPE HookTargetsUav(ID3D11DeviceContext *ctx, UINT count, ID3D11RenderTargetView *const *views,
                                      ID3D11DepthStencilView *depth, UINT start, UINT uavs,
                                      ID3D11UnorderedAccessView *const *unordered, const UINT *counts)
{
    if (!internalCapDraw && ctx == context && clipping && worldTarget && cylinderCaps.Active() &&
        count != D3D11_KEEP_RENDER_TARGETS_AND_DEPTH_STENCIL &&
        (!depth || !count || !views || !IsWorldTarget(views[0])))
    { internalCapDraw = true; cylinderCaps.Composite(); internalCapDraw = false; }
    originalTargetsUav(ctx, count, views, depth, start, uavs, unordered, counts);
    if (!internalCapDraw && count != D3D11_KEEP_RENDER_TARGETS_AND_DEPTH_STENCIL)
        UpdateTarget(ctx, count, views);
}
void STDMETHODCALLTYPE HookBlend(ID3D11DeviceContext *ctx, ID3D11BlendState *state, const FLOAT factors[4], UINT mask)
{
    if (internalCapDraw) { originalBlend(ctx, state, factors, mask); return; }
    if (ctx != context || !clipping)
    {
        originalBlend(ctx, state, factors, mask);
        return;
    }
    if (savedBlend != state)
    {
        if (savedBlend)
            savedBlend->Release();
        savedBlend = state;
        if (savedBlend)
            savedBlend->AddRef();
    }
    for (int i = 0; i < 4; ++i)
        savedFactors[i] = factors ? factors[i] : 1.f;
    savedSampleMask = mask;
    D3D11_BLEND_DESC desc = {};
    if (state)
        state->GetDesc(&desc);
    opaqueDraw = !state || !desc.RenderTarget[0].BlendEnable;
    premultipliedDraw = state && desc.RenderTarget[0].SrcBlend != D3D11_BLEND_SRC_ALPHA &&
        desc.RenderTarget[0].SrcBlend != D3D11_BLEND_SRC_ALPHA_SAT;
    ID3D11BlendState *use = state;
    {
        std::lock_guard<std::mutex> lock(blendMutex);
        auto it = blends.find(state);
        if (worldTarget && it != blends.end())
            use = it->second;
    }
    originalBlend(ctx, use, factors, mask);
    HookSet(ctx, requestedShader, nullptr, 0);
}
void STDMETHODCALLTYPE HookBuffers(ID3D11DeviceContext *ctx, UINT start, UINT count, ID3D11Buffer *const *buffers)
{
    if (internalCapDraw) { originalCB(ctx, start, count, buffers); return; }
    if (ctx == context && clipping)
        for (UINT i = 0; i < count && start + i < 14; ++i)
        {
            auto &saved = savedBuffers[start + i];
            if (saved != buffers[i])
            {
                if (saved)
                    saved->Release();
                saved = buffers[i];
                if (saved)
                    saved->AddRef();
            }
        }
    originalCB(ctx, start, count, buffers);
    if (ctx == context && clipping && worldTarget && start <= activeBuffer && start + count > activeBuffer)
        originalCB(ctx, activeBuffer, 1, &clipBuffer);
    if (ctx == context) ArmDiagnosticDrawHooks();
}
bool Replace(void **table, unsigned index, void *function, void **original)
{
    DWORD protection;
    if (!VirtualProtect(table + index, sizeof(void *), PAGE_READWRITE, &protection))
        return false;
    *original = InterlockedExchangePointer(reinterpret_cast<void *volatile *>(table + index), function);
    DWORD ignored;
    VirtualProtect(table + index, sizeof(void *), protection, &ignored);
    return true;
}
} // namespace
bool InstallShaderClip(ID3D11Device *device)
{
    if (context)
        return true;
    if (!device)
        return false;
    // Optional pipeline: failure never disables clipping/VR. Its own shaders
    // are created before shader interception and never enter game variants.
    cylinderCaps.Initialize(device);
    device->GetImmediateContext(&context);
    context->QueryInterface(__uuidof(ID3D11DeviceContext1), reinterpret_cast<void **>(&diagnosticContext));
    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = sizeof(ClipParameters);
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    if (FAILED(device->CreateBuffer(&desc, nullptr, &clipBuffer)))
        return false;
    // Diagnostic resources are optional: failure must not disable VR/clipping.
    D3D11_BUFFER_DESC staging = {};
    staging.ByteWidth = DiagnosticBytes;
    staging.Usage = D3D11_USAGE_STAGING;
    staging.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    bool diagnosticAvailable = true;
    for (auto &buffer : diagnosticStaging)
        if (FAILED(device->CreateBuffer(&staging, nullptr, &buffer))) diagnosticAvailable = false;
    if (FAILED(device->CreateBuffer(&staging, nullptr, &diagnosticPixelStaging))) diagnosticAvailable = false;
    D3D11_QUERY_DESC query = {D3D11_QUERY_EVENT, 0};
    if (diagnosticAvailable) device->CreateQuery(&query, &diagnosticQuery);
    const char *source = "float4 main():SV_Target{clip(-1);return 0;}";
    ID3DBlob *b = nullptr;
    if (FAILED(D3DCompile(source, strlen(source), nullptr, nullptr, nullptr, "main", "ps_4_0", 0, 0, &b, nullptr)))
        return false;
    HRESULT hr = device->CreatePixelShader(b->GetBufferPointer(), b->GetBufferSize(), nullptr, &discardShader);
    b->Release();
    if (FAILED(hr))
        return false;
    const char *depthSource =
        "cbuffer Cylinder:register(b13){float4x4 pixelToLocal;float4 limits;}"
        "void main(float4 p:SV_Position){float4 h=mul(pixelToLocal,float4(p.xyz,1));"
        "float3 q=h.xyz/h.w;clip(min(limits.x-dot(q.xz,q.xz),limits.y-abs(q.y)));}";
    b = nullptr;
    if (FAILED(D3DCompile(depthSource, strlen(depthSource), nullptr, nullptr, nullptr, "main", "ps_4_0",
                          D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &b, nullptr)))
        return false;
    hr = device->CreatePixelShader(b->GetBufferPointer(), b->GetBufferSize(), nullptr, &depthClipShader);
    b->Release();
    if (FAILED(hr))
        return false;
    auto deviceTable = *reinterpret_cast<void ***>(device);
    auto contextTable = *reinterpret_cast<void ***>(context);
    return Replace(deviceTable, 15, reinterpret_cast<void *>(&HookCreate),
                   reinterpret_cast<void **>(&originalCreate)) &&
           Replace(deviceTable, 20, reinterpret_cast<void *>(&HookCreateBlend),
                   reinterpret_cast<void **>(&originalCreateBlend)) &&
           Replace(contextTable, 9, reinterpret_cast<void *>(&HookSet), reinterpret_cast<void **>(&originalSet)) &&
           Replace(contextTable, 16, reinterpret_cast<void *>(&HookBuffers), reinterpret_cast<void **>(&originalCB)) &&
           Replace(contextTable, 35, reinterpret_cast<void *>(&HookBlend), reinterpret_cast<void **>(&originalBlend)) &&
           Replace(contextTable, 33, reinterpret_cast<void *>(&HookTargets),
                   reinterpret_cast<void **>(&originalTargets)) &&
           Replace(contextTable, 34, reinterpret_cast<void *>(&HookTargetsUav),
                   reinterpret_cast<void **>(&originalTargetsUav));
}
void SetShaderClipTargets(ID3D11Texture2D *left, ID3D11Texture2D *right)
{
    cylinderCaps.SetTargets(left, right);
    if (left)
        left->AddRef();
    if (right)
        right->AddRef();
    std::lock_guard<std::mutex> lock(targetMutex);
    for (auto target : clipTargets)
        if (target)
            target->Release();
    clipTargets[0] = left;
    clipTargets[1] = right;
}
void RegisterCapMesh(ID3D11Buffer *indices) { cylinderCaps.RegisterMesh(indices); }
void ClearCapMeshes() { cylinderCaps.ClearMeshes(); }
void CompositeShaderCaps()
{
    if (!context || !clipping || !worldTarget || !cylinderCaps.Active()) return;
    internalCapDraw = true; cylinderCaps.Composite(); internalCapDraw = false;
}
void GetCapStats(unsigned &available, unsigned &registered, unsigned &replayed, unsigned &composed)
{ cylinderCaps.Stats(available, registered, replayed, composed); }
void BeginShaderClip(const ClipParameters &parameters, bool caps, bool reversedZ, bool transparent)
{
    if (!context || clipping)
        return;
    cylinderCaps.Begin(parameters, caps, reversedZ, transparent);
    CollectWorldConstants();
    diagnosticArmed = diagnosticQuery && !diagnosticCaptured && parameters.limits[0] > 4.f && parameters.limits[0] < 1e20f;
    if (diagnosticArmed) diagnostic.parameters = parameters;
    savedClassCount = 256;
    context->PSGetShader(&savedShader, savedClasses, &savedClassCount);
    context->PSGetConstantBuffers(0, 14, savedBuffers);
    context->OMGetBlendState(&savedBlend, savedFactors, &savedSampleMask);
    context->UpdateSubresource(clipBuffer, 0, nullptr, &parameters, 0, 0);
    clipping = true;
    requestedShader = savedShader;
    ID3D11RenderTargetView *target = nullptr;
    context->OMGetRenderTargets(1, &target, nullptr);
    worldTarget = IsWorldTarget(target);
    if (target)
        target->Release();
    HookBlend(context, savedBlend, savedFactors, savedSampleMask);
}
bool WriteShaderClipDiagnostic(const wchar_t *path)
{
    if (!path || !diagnosticReady.load(std::memory_order_acquire)) return false;
    FILE *file = nullptr;
    if (_wfopen_s(&file, path, L"wb") != 0 || !file) return false;
    bool success = fwrite(&diagnostic, sizeof(diagnostic), 1, file) == 1;
    success = success && fwrite(&pixelDiagnostic, sizeof(pixelDiagnostic), 1, file) == 1;
    fclose(file);
    return success;
}
void EndShaderClip()
{
    if (!context || !clipping)
        return;
    internalCapDraw = true; cylinderCaps.Composite(); internalCapDraw = false;
    cylinderCaps.End();
    RestoreDiagnosticDrawHooks();
    clipping = false;
    // Restore Unity's latest requested bindings, matching its state cache.
    originalSet(context, requestedShader, nullptr, 0);
    originalCB(context, 0, 14, savedBuffers);
    originalBlend(context, savedBlend, savedFactors, savedSampleMask);
    if (savedBlend)
    {
        savedBlend->Release();
        savedBlend = nullptr;
    }
    if (savedShader)
    {
        savedShader->Release();
        savedShader = nullptr;
    }
    for (UINT i = 0; i < savedClassCount; ++i)
        if (savedClasses[i])
            savedClasses[i]->Release();
    for (auto &b : savedBuffers)
        if (b)
        {
            b->Release();
            b = nullptr;
        }
}
void GetShaderClipStats(unsigned &p, unsigned &r, unsigned &u, unsigned &d)
{
    p = patchedCount.load();
    r = rejectedCount.load();
    u = unknownCount.load();
    d = depthOnlyCount.load();
}
void GetShaderClipBindingStats(unsigned &materials, unsigned &otherContexts)
{
    materials = materialBindCount.load();
    otherContexts = otherContextBindCount.load();
}
} // namespace qvvr
