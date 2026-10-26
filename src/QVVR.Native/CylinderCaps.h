#pragma once
#include "ShaderClip.h"
#include <d3d11_1.h>
#include <d3dcompiler.h>
#include <cstring>
#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace qvvr
{
// Optional cross-section pass. Count uncut, opaque mesh front/back crossings
// before the cylinder ENTRY along each ray. Non-zero winding means that boundary
// intersects a solid. Composite black at that boundary with real eye depth,
// BEFORE transparent draws and outside clip. Never sample/read back a game eye;
// no original shader/mesh mutation.
//
// Inline mode (default when the eye depth has stencil and the game does not use
// stencil): count in the eye's OWN stencil with an analytic entry test, then
// composite through the stencil test. Nothing ever rebinds render targets, so
// tiled GPUs (Steam Frame via DXVK) keep the eye in tile memory; the private
// mode swapped targets twice per replayed draw (~7 ms on Frame). Private mode
// remains for stencil-less depth, game stencil use or the rollback switch.
class CylinderCaps
{
    template<class T> static void Drop(T *&p) { if (p) p->Release(); p = nullptr; }
    struct Constants { ClipParameters clip; float options[4]; } constants = {};
    ID3D11Device *device = nullptr;
    ID3D11DeviceContext *context = nullptr;
    ID3D11Buffer *buffer = nullptr;
    ID3D11VertexShader *vertex = nullptr;
    ID3D11PixelShader *entry = nullptr, *cap[2] = {};
    ID3D11DepthStencilState *initializeDepth = nullptr, *countDepth[2] = {}, *compositeDepth[2] = {};
    ID3D11RasterizerState *raster[2] = {};
    ID3D11BlendState *blend = nullptr;
    ID3D11PixelShader *countInline = nullptr, *capInline = nullptr;
    ID3D11DepthStencilState *countInlineState = nullptr, *compositeInline[2] = {};
    ID3D11BlendState *noColor = nullptr;
    ID3D11DepthStencilView *inlineDepth = nullptr; // Eye DSV holding this eye's count.
    ID3D11BlendState *savedBlend = nullptr; FLOAT savedFactors[4] = {}; UINT savedSampleMask = 0;
    ID3D11Buffer *savedPixelBuffer = nullptr;
    bool inlineAvailable = false, inlineMode = false;
    unsigned shaderVariants = 0; // Bit 0: early-reject count PS, bit 1: conservative-depth composite.
    // Back-face mode (capMode 1): ShaderClip marks the facing of each opaque
    // world surface in the eye stencil (front 0, back 1) while drawing it; a
    // trivial stencil-tested pass then paints visible interiors black. No
    // replay, no ray math, no depth output.
    std::atomic<int> capMode{0};
    ID3D11PixelShader *backFacePixel = nullptr;
    ID3D11DepthStencilState *backFaceComposite = nullptr;
    bool backFaceAvailable = false, backFaceMarked = false, backFaceComposited = false;
    ID3D11DepthStencilView *backFaceDepth = nullptr;
    D3D11_TEXTURE2D_DESC backFaceDesc = {};
    std::atomic<unsigned> backFaceEyes{0};
    // Graphics thread: set by the OMSetRenderTargets hook. While false, inline
    // replays skip OMGetRenderTargets (8 view AddRef/Release round trips each).
    bool targetsChanged = true;
    std::atomic<bool> inlineEnabled{true}, stencilConflict{false};
    std::atomic<unsigned> inlineEyes{0}, privateEyes{0};
    struct Target
    {
        ID3D11Texture2D *eye = nullptr, *depth = nullptr;
        ID3D11DepthStencilView *view = nullptr;
        ID3D11ShaderResourceView *stencil = nullptr;
        D3D11_TEXTURE2D_DESC desc = {};
    } targets[2], frameTarget;
    std::mutex targetMutex, meshMutex;
    struct Mesh { ID3D11Buffer *buffer; CapBounds bounds; bool bounded; };
    std::vector<Mesh> meshes; // Reserved/changed on cold registration only.
    CapCullVolume cullVolume;
    CapSkipFrame skipFrame;
    std::atomic<uint64_t> meshGeneration{1};
    Target *target = nullptr;
    bool initialized = false, rendered = false, dirty = false;
    std::atomic<unsigned> meshCount{0}, volumeDraws{0}, composites{0};
    std::atomic<unsigned> skippedVolumes{0};
    ID3D11RenderTargetView *savedTargets[8] = {};
    ID3D11DepthStencilView *savedDepthView = nullptr;
    ID3D11DepthStencilState *savedDepth = nullptr;
    ID3D11RasterizerState *savedRaster = nullptr;
    ID3D11PixelShader *savedPixel = nullptr;
    UINT savedStencilRef = 0;

    static constexpr const char *source =
        "cbuffer C:register(b0){float4x4 pixelToLocal;float4 limits;float4 options;}"
        "bool boundary(float2 pixel,out float depth,out float coverage){"
        "float zn=options.x>.5?1:0,zf=options.x>.5?.0001:.9999;"
        "float4 hn=mul(pixelToLocal,float4(pixel,zn,1));"
        "float4 hf=mul(pixelToLocal,float4(pixel,zf,1));"
        "if(abs(hn.w)<1e-12||abs(hf.w)<1e-12){depth=0;coverage=0;return false;}"
        "float3 n=hn.xyz/hn.w,d=hf.xyz/hf.w-n;"
        "float enter=-1e20,leave=1e20;"
        "float a=dot(d.xz,d.xz),b=dot(n.xz,d.xz),c=dot(n.xz,n.xz)-limits.x;"
        "if(a<1e-12){if(c>0){depth=0;coverage=0;return false;}}"
        "else{float h=b*b-a*c;if(h<0){depth=0;coverage=0;return false;}"
        "h=sqrt(h);enter=(-b-h)/a;leave=(-b+h)/a;}"
        "if(abs(d.y)<1e-12){if(abs(n.y)>limits.y){depth=0;coverage=0;return false;}}"
        "else{float t0=(-limits.y-n.y)/d.y,t1=(limits.y-n.y)/d.y;"
        "enter=max(enter,min(t0,t1));leave=min(leave,max(t0,t1));}"
        // No fake near-plane cap when the eye/near plane is already inside.
        "if(enter<=0||leave<enter||enter>=1){depth=0;coverage=0;return false;}"
        "float s=enter*hn.w/(hf.w*(1-enter)+enter*hn.w);depth=lerp(zn,zf,s);"
        // Retain a soft silhouette without changing the original geometry fade.
        "coverage=limits.z>0?smoothstep(0,limits.z,length(d)*(leave-enter)):1;"
        "return depth>=0&&depth<=1;}"
        "float main(float4 p:SV_Position):SV_Depth{float z,a;if(!boundary(p.xy,z,a))discard;return z;}";

    bool Pixel(const char *text, ID3D11PixelShader **result)
    {
        ID3DBlob *code = nullptr;
        if (FAILED(D3DCompile(text, strlen(text), nullptr, nullptr, nullptr, "main", "ps_5_0",
            D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, nullptr))) return false;
        HRESULT hr = device->CreatePixelShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, result);
        code->Release(); return SUCCEEDED(hr);
    }

    // bindTargets=false (inline mode): draw into the targets already bound, so
    // DXVK keeps the same render pass; color only selects the blend state.
    void Fullscreen(ID3D11RenderTargetView *color, ID3D11DepthStencilView *depth,
        ID3D11PixelShader *pixel, ID3D11DepthStencilState *state, ID3D11ShaderResourceView *stencil, bool bindTargets = true)
    {
        // Explicit save/restore: context-state swaps can replace the D3D runtime
        // dispatch table and invalidate Unity's intercepted method entry points.
        // All storage is on the stack, with no per-eye allocations.
        ID3D11VertexShader *vs = nullptr; ID3D11PixelShader *ps = nullptr;
        ID3D11GeometryShader *gs = nullptr; ID3D11HullShader *hs = nullptr; ID3D11DomainShader *ds = nullptr;
        ID3D11ClassInstance *vc[256] = {}, *pc[256] = {}, *gc[256] = {}, *hc[256] = {}, *dc[256] = {};
        UINT vn=256,pn=256,gn=256,hn=256,dn=256;
        context->VSGetShader(&vs,vc,&vn); context->PSGetShader(&ps,pc,&pn);
        context->GSGetShader(&gs,gc,&gn); context->HSGetShader(&hs,hc,&hn); context->DSGetShader(&ds,dc,&dn);
        ID3D11InputLayout *layout = nullptr; D3D11_PRIMITIVE_TOPOLOGY topology;
        context->IAGetInputLayout(&layout); context->IAGetPrimitiveTopology(&topology);
        ID3D11Buffer *cb = nullptr; ID3D11ShaderResourceView *srv = nullptr;
        context->PSGetConstantBuffers(0,1,&cb); context->PSGetShaderResources(0,1,&srv);
        ID3D11RenderTargetView *rt[8] = {}; ID3D11DepthStencilView *dsv = nullptr;
        if (bindTargets) context->OMGetRenderTargets(8,rt,&dsv);
        ID3D11DepthStencilState *depthState = nullptr; UINT ref;
        context->OMGetDepthStencilState(&depthState,&ref);
        ID3D11BlendState *blendState = nullptr; FLOAT factors[4]; UINT sampleMask;
        context->OMGetBlendState(&blendState,factors,&sampleMask);
        ID3D11RasterizerState *rs = nullptr; context->RSGetState(&rs);
        D3D11_VIEWPORT viewports[16] = {}; UINT viewportCount=16;
        context->RSGetViewports(&viewportCount,viewports);
        context->IASetInputLayout(nullptr);
        context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        context->GSSetShader(nullptr,nullptr,0); context->HSSetShader(nullptr,nullptr,0); context->DSSetShader(nullptr,nullptr,0);
        context->VSSetShader(vertex, nullptr, 0);
        context->PSSetShader(pixel, nullptr, 0);
        context->PSSetConstantBuffers(0, 1, &buffer);
        context->PSSetShaderResources(0, 1, &stencil);
        const D3D11_TEXTURE2D_DESC &size = target ? target->desc : backFaceDesc;
        D3D11_VIEWPORT viewport = {0, 0, float(size.Width), float(size.Height), 0, 1};
        context->RSSetViewports(1, &viewport);
        context->RSSetState(raster[0]);
        context->OMSetDepthStencilState(state, 0);
        context->OMSetBlendState(color ? blend : nullptr, nullptr, 0xffffffff);
        if (bindTargets) context->OMSetRenderTargets(color ? 1 : 0, color ? &color : nullptr, depth);
        context->Draw(3, 0);
        // Unbind mask before its next depth/stencil use (no DSV/SRV hazards).
        ID3D11ShaderResourceView *none = nullptr; context->PSSetShaderResources(0,1,&none);
        if (bindTargets) context->OMSetRenderTargets(8,rt,dsv);
        context->OMSetDepthStencilState(depthState,ref); context->OMSetBlendState(blendState,factors,sampleMask);
        context->RSSetState(rs); context->RSSetViewports(viewportCount,viewports);
        context->VSSetShader(vs,vc,vn); context->PSSetShader(ps,pc,pn);
        context->GSSetShader(gs,gc,gn); context->HSSetShader(hs,hc,hn); context->DSSetShader(ds,dc,dn);
        context->IASetInputLayout(layout); context->IASetPrimitiveTopology(topology);
        context->PSSetConstantBuffers(0,1,&cb); context->PSSetShaderResources(0,1,&srv);
        Drop(vs); Drop(ps); Drop(gs); Drop(hs); Drop(ds); Drop(layout); Drop(cb); Drop(srv);
        for (UINT i=0;i<vn;++i) Drop(vc[i]); for (UINT i=0;i<pn;++i) Drop(pc[i]);
        for (UINT i=0;i<gn;++i) Drop(gc[i]); for (UINT i=0;i<hn;++i) Drop(hc[i]); for (UINT i=0;i<dn;++i) Drop(dc[i]);
        for (auto &view:rt) Drop(view);
        Drop(dsv); Drop(depthState); Drop(blendState); Drop(rs);
    }

public:
    bool Initialize(ID3D11Device *owner)
    {
        device = owner;
        device->GetImmediateContext(&context);
        HRESULT hr;
        D3D11_BUFFER_DESC bd = {};
        bd.ByteWidth = sizeof(constants); bd.Usage = D3D11_USAGE_DEFAULT; bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
        if (FAILED(device->CreateBuffer(&bd, nullptr, &buffer))) return false;
        const char *vs = "float4 main(uint id:SV_VertexID):SV_Position{float2 p=float2((id<<1)&2,id&2);"
            "return float4(p*float2(2,-2)+float2(-1,1),0,1);}";
        ID3DBlob *code = nullptr;
        if (FAILED(D3DCompile(vs, strlen(vs), nullptr, nullptr, nullptr, "main", "vs_4_0", 0, 0, &code, nullptr))) return false;
        hr = device->CreateVertexShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, &vertex);
        code->Release();
        if (FAILED(hr) || !Pixel(source, &entry)) return false;
        // Two small cold compiled variants; use per-sample stencil for MSAA.
        std::string base(source, strstr(source, "float main(") - source);
        for (int ms = 0; ms < 2; ++ms)
        {
            std::string text = base + (ms ? "Texture2DMS<uint2> mask:register(t0);" : "Texture2D<uint2> mask:register(t0);");
            text += "struct Result{float4 color:SV_Target;float depth:SV_Depth;};"
                "Result main(float4 p:SV_Position";
            if (ms) text += ",uint sample:SV_SampleIndex";
            text += "){uint winding=";
            text += ms ? "mask.Load(int2(p.xy),sample).y;" : "mask.Load(int3(p.xy,0)).y;";
            text += "if(winding==0)discard;float z,a;if(!boundary(p.xy,z,a))discard;"
                "Result r;r.depth=z;r.color=options.y>.5?float4(0,0,0,a):float4(0,limits.w*(1-a),0,1);return r;}";
            if (!Pixel(text.c_str(), &cap[ms])) return false;
        }
        D3D11_DEPTH_STENCIL_DESC ds = {};
        ds.DepthEnable = TRUE; ds.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL; ds.DepthFunc = D3D11_COMPARISON_ALWAYS;
        if (FAILED(device->CreateDepthStencilState(&ds, &initializeDepth))) return false;
        for (int reverse = 0; reverse < 2; ++reverse)
        {
            ds.DepthFunc = reverse ? D3D11_COMPARISON_GREATER_EQUAL : D3D11_COMPARISON_LESS_EQUAL;
            if (FAILED(device->CreateDepthStencilState(&ds, &compositeDepth[reverse]))) return false;
            ds.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO;
            ds.StencilEnable = TRUE; ds.StencilReadMask = ds.StencilWriteMask = 0xff;
            ds.FrontFace.StencilFunc = ds.BackFace.StencilFunc = D3D11_COMPARISON_ALWAYS;
            ds.FrontFace.StencilPassOp = D3D11_STENCIL_OP_INCR;
            ds.BackFace.StencilPassOp = D3D11_STENCIL_OP_DECR;
            ds.FrontFace.StencilFailOp = ds.BackFace.StencilFailOp = D3D11_STENCIL_OP_KEEP;
            ds.FrontFace.StencilDepthFailOp = ds.BackFace.StencilDepthFailOp = D3D11_STENCIL_OP_KEEP;
            if (FAILED(device->CreateDepthStencilState(&ds, &countDepth[reverse]))) return false;
            ds = {}; ds.DepthEnable = TRUE; ds.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL;
        }
        for (int winding = 0; winding < 2; ++winding)
        {
            D3D11_RASTERIZER_DESC rs = {};
            rs.FillMode = D3D11_FILL_SOLID; rs.CullMode = D3D11_CULL_NONE;
            rs.FrontCounterClockwise = winding; rs.DepthClipEnable = TRUE; rs.MultisampleEnable = TRUE;
            if (FAILED(device->CreateRasterizerState(&rs, &raster[winding]))) return false;
        }
        D3D11_BLEND_DESC bs = {};
        auto &rt = bs.RenderTarget[0]; rt.BlendEnable = TRUE;
        rt.SrcBlend = rt.SrcBlendAlpha = D3D11_BLEND_ONE;
        rt.DestBlend = rt.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
        rt.BlendOp = rt.BlendOpAlpha = D3D11_BLEND_OP_ADD;
        rt.RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
        if (FAILED(device->CreateBlendState(&bs, &blend))) return false;
        meshes.reserve(256);
        inlineAvailable = InitializeInline(base);
        backFaceAvailable = InitializeBackFace();
        initialized = true; return true;
    }

    // Optional: any failure keeps the exact (winding) modes.
    bool InitializeBackFace()
    {
        if (!Pixel("float4 main(float4 p:SV_Position):SV_Target{return float4(0,0,0,1);}", &backFacePixel)) return false;
        D3D11_DEPTH_STENCIL_DESC ds = {};
        ds.DepthEnable = FALSE; ds.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO; ds.DepthFunc = D3D11_COMPARISON_ALWAYS;
        ds.StencilEnable = TRUE; ds.StencilReadMask = 0xff; ds.StencilWriteMask = 0;
        ds.StencilWriteMask = 0xff;
        // Interior (1) vs ref 0; passing pixels reset to 0, so the eye leaves
        // with a zero stencil without a second mid-pass clear.
        ds.FrontFace.StencilFunc = ds.BackFace.StencilFunc = D3D11_COMPARISON_NOT_EQUAL;
        ds.FrontFace.StencilPassOp = ds.BackFace.StencilPassOp = D3D11_STENCIL_OP_ZERO;
        ds.FrontFace.StencilFailOp = ds.BackFace.StencilFailOp = D3D11_STENCIL_OP_KEEP;
        ds.FrontFace.StencilDepthFailOp = ds.BackFace.StencilDepthFailOp = D3D11_STENCIL_OP_KEEP;
        return SUCCEEDED(device->CreateDepthStencilState(&ds, &backFaceComposite));
    }

    // Optional: any failure keeps the private-target path.
    bool InitializeInline(const std::string &base)
    {
        // Count only crossings nearer than the analytic cylinder entry (the
        // private mode's entry depth test), into stencil, without color.
        // Optimized variants first, then the plain ones: Proton's runtime HLSL
        // compiler (Steam Frame) accepts less than Windows d3dcompiler.
        // Most replayed fragments lie INSIDE the cylinder (always behind the
        // entry): one transform rejects them before the ray intersection.
        std::string countTail = "float z,a;if(!boundary(p.xy,z,a))discard;if(options.x>.5?p.z<z:p.z>z)discard;}";
        std::string count = base + "void main(float4 p:SV_Position){"
            "float4 h=mul(pixelToLocal,float4(p.xyz,1));"
            "if(abs(h.w)>1e-12){float3 l=h.xyz/h.w;if(dot(l.xz,l.xz)<limits.x&&abs(l.y)<limits.y)discard;}" + countTail;
        if (Pixel(count.c_str(), &countInline)) shaderVariants |= 1;
        else if (!Pixel((base + "void main(float4 p:SV_Position){" + countTail).c_str(), &countInline)) return false;
        // Conservative depth (>= the full-screen triangle's z=0) keeps the early
        // stencil test, so only winding!=0 pixels run the boundary shader.
        // (It requires centroid position; a full-screen triangle covers whole
        // pixels, so the centroid is the pixel center.)
        std::string compositeTail = "{float z,a;if(!boundary(p.xy,z,a))discard;"
            "Result r;r.depth=z;r.color=options.y>.5?float4(0,0,0,a):float4(0,limits.w*(1-a),0,1);return r;}";
        std::string composite = base + "struct Result{float4 color:SV_Target;float depth:SV_DepthGreaterEqual;};"
            "Result main(noperspective centroid float4 p:SV_Position)" + compositeTail;
        if (Pixel(composite.c_str(), &capInline)) shaderVariants |= 2;
        else if (!Pixel((base + "struct Result{float4 color:SV_Target;float depth:SV_Depth;};Result main(float4 p:SV_Position)" +
            compositeTail).c_str(), &capInline)) return false;
        D3D11_DEPTH_STENCIL_DESC ds = {};
        ds.DepthEnable = FALSE; ds.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO; ds.DepthFunc = D3D11_COMPARISON_ALWAYS;
        ds.StencilEnable = TRUE; ds.StencilReadMask = ds.StencilWriteMask = 0xff;
        ds.FrontFace.StencilFunc = ds.BackFace.StencilFunc = D3D11_COMPARISON_ALWAYS;
        ds.FrontFace.StencilPassOp = D3D11_STENCIL_OP_INCR;
        ds.BackFace.StencilPassOp = D3D11_STENCIL_OP_DECR;
        ds.FrontFace.StencilFailOp = ds.BackFace.StencilFailOp = D3D11_STENCIL_OP_KEEP;
        ds.FrontFace.StencilDepthFailOp = ds.BackFace.StencilDepthFailOp = D3D11_STENCIL_OP_KEEP;
        if (FAILED(device->CreateDepthStencilState(&ds, &countInlineState))) return false;
        for (int reverse = 0; reverse < 2; ++reverse)
        {
            ds.DepthEnable = TRUE; ds.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL;
            ds.DepthFunc = reverse ? D3D11_COMPARISON_GREATER_EQUAL : D3D11_COMPARISON_LESS_EQUAL;
            ds.StencilWriteMask = 0;
            ds.FrontFace.StencilFunc = ds.BackFace.StencilFunc = D3D11_COMPARISON_NOT_EQUAL; // winding != 0
            ds.FrontFace.StencilPassOp = ds.BackFace.StencilPassOp = D3D11_STENCIL_OP_KEEP;
            if (FAILED(device->CreateDepthStencilState(&ds, &compositeInline[reverse]))) return false;
        }
        D3D11_BLEND_DESC bs = {};
        bs.RenderTarget[0].RenderTargetWriteMask = 0;
        return SUCCEEDED(device->CreateBlendState(&bs, &noColor));
    }

    static bool HasStencil(ID3D11DepthStencilView *view)
    {
        if (!view) return false;
        D3D11_DEPTH_STENCIL_VIEW_DESC desc = {};
        view->GetDesc(&desc);
        return desc.Format == DXGI_FORMAT_D24_UNORM_S8_UINT || desc.Format == DXGI_FORMAT_D32_FLOAT_S8X24_UINT;
    }

    void SetTargets(ID3D11Texture2D *left, ID3D11Texture2D *right)
    {
        bool resourcesWanted;
        { std::lock_guard<std::mutex> lock(meshMutex); resourcesWanted = !meshes.empty(); }
        std::lock_guard<std::mutex> lock(targetMutex);
        ID3D11Texture2D *eyes[] = {left, right};
        for (int i = 0; i < 2; ++i)
        {
            auto &t = targets[i];
            if (t.eye == eyes[i]) continue;
            Drop(t.stencil); Drop(t.view); Drop(t.depth); Drop(t.eye);
            t.eye = eyes[i]; if (t.eye) t.eye->AddRef();
            if (resourcesWanted) Prepare(t);
        }
    }

    // Cold registration/target changes only, never allocate a GPU resource in
    // BeforeVolume/Composite. Disabling caps releases these extra eye-sized DSVs.
    void Prepare(Target &t)
    {
        if (!initialized || !t.eye || t.stencil) return;
        Drop(t.stencil); Drop(t.view); Drop(t.depth);
        t.eye->GetDesc(&t.desc);
        D3D11_TEXTURE2D_DESC td = t.desc;
        td.Format = DXGI_FORMAT_R24G8_TYPELESS; td.MipLevels = td.ArraySize = 1;
        td.Usage = D3D11_USAGE_DEFAULT; td.BindFlags = D3D11_BIND_DEPTH_STENCIL | D3D11_BIND_SHADER_RESOURCE;
        td.CPUAccessFlags = td.MiscFlags = 0;
        if (FAILED(device->CreateTexture2D(&td, nullptr, &t.depth))) return;
        D3D11_DEPTH_STENCIL_VIEW_DESC vd = {};
        vd.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
        vd.ViewDimension = td.SampleDesc.Count > 1 ? D3D11_DSV_DIMENSION_TEXTURE2DMS : D3D11_DSV_DIMENSION_TEXTURE2D;
        if (FAILED(device->CreateDepthStencilView(t.depth, &vd, &t.view))) return;
        D3D11_SHADER_RESOURCE_VIEW_DESC sd = {};
        sd.Format = DXGI_FORMAT_X24_TYPELESS_G8_UINT;
        sd.ViewDimension = td.SampleDesc.Count > 1 ? D3D11_SRV_DIMENSION_TEXTURE2DMS : D3D11_SRV_DIMENSION_TEXTURE2D;
        if (td.SampleDesc.Count == 1) sd.Texture2D.MipLevels = 1;
        device->CreateShaderResourceView(t.depth, &sd, &t.stencil);
    }

    void RegisterMesh(ID3D11Buffer *mesh, const CapBounds *bounds = nullptr)
    {
        if (!mesh) return;
        {
            std::lock_guard<std::mutex> lock(meshMutex);
            meshGeneration.fetch_add(1);
            for (auto &item : meshes) if (item.buffer == mesh)
            {
                // Static batching/shared index buffers: union ALL contributors.
                // A single moving/unbounded contributor disables pruning.
                item.bounded = item.bounded && bounds && ValidCapBounds(*bounds);
                if (item.bounded) for (int i = 0; i < 3; ++i)
                {
                    item.bounds.minimum[i] = (std::min)(item.bounds.minimum[i], bounds->minimum[i]);
                    item.bounds.maximum[i] = (std::max)(item.bounds.maximum[i], bounds->maximum[i]);
                }
                return;
            }
            mesh->AddRef(); meshes.push_back({mesh, bounds ? *bounds : CapBounds{}, bounds && ValidCapBounds(*bounds)});
            meshCount.store(static_cast<unsigned>(meshes.size()));
        }
        std::lock_guard<std::mutex> lock(targetMutex);
        for (auto &t : targets) Prepare(t);
    }
    void ClearMeshes()
    {
        {
            std::lock_guard<std::mutex> lock(meshMutex);
            meshGeneration.fetch_add(1);
            for (auto item : meshes) item.buffer->Release();
            meshes.clear();
            meshCount.store(0);
        }
        stencilConflict.store(false); // A new scene may not use stencil.
        std::lock_guard<std::mutex> lock(targetMutex);
        for (auto &t : targets) { Drop(t.stencil); Drop(t.view); Drop(t.depth); }
    }

    uint64_t Generation() const { return meshGeneration.load(); }
    void Begin(const ClipParameters &clip, bool enabled, bool reversed, bool transparent, const CapCullVolume *cull = nullptr, const CapSkipFrame *skip = nullptr)
    {
        constants.clip = clip;
        cullVolume = cull ? *cull : CapCullVolume{};
        skipFrame = skip ? *skip : CapSkipFrame{};
        constants.options[0] = reversed ? 1.f : 0.f;
        constants.options[1] = transparent ? 1.f : 0.f;
        constants.options[2] = enabled ? 1.f : 0.f;
        target = nullptr; rendered = dirty = inlineMode = false;
        targetsChanged = true;
        backFaceMarked = backFaceComposited = false;
        Drop(frameTarget.stencil); Drop(frameTarget.view); Drop(frameTarget.depth); Drop(frameTarget.eye);
        Drop(inlineDepth); Drop(backFaceDepth);
    }
    bool Active() const { return initialized && constants.options[2] > .5f; }
    void SetInlineEnabled(bool enabled) { inlineEnabled.store(enabled); }
    void TargetsChanged() { targetsChanged = true; }
    void SetMode(int mode) { capMode.store(mode); }
    // Graphics thread (ShaderClip state hooks).
    bool BackFaceWanted() const
    {
        return Active() && capMode.load() == 1 && backFaceAvailable && !stencilConflict.load() && !backFaceComposited;
    }
    void FlagStencilConflict() { stencilConflict.store(true); }
    // First marking draw of an eye: start from a zero stencil in that depth.
    void BackFaceMarked(ID3D11DepthStencilView *depth)
    {
        if (backFaceMarked || !depth) return;
        ID3D11Resource *resource = nullptr; depth->GetResource(&resource);
        ID3D11Texture2D *texture = nullptr;
        if (resource) resource->QueryInterface(__uuidof(ID3D11Texture2D), reinterpret_cast<void **>(&texture));
        Drop(resource);
        if (!texture) return;
        texture->GetDesc(&backFaceDesc); Drop(texture);
        context->ClearDepthStencilView(depth, D3D11_CLEAR_STENCIL, 0.f, 0);
        backFaceDepth = depth; backFaceDepth->AddRef();
        backFaceMarked = true; backFaceEyes.fetch_add(1);
    }
    unsigned BackFaceEyes() const { return backFaceEyes.load(); }
    // Bound index buffer is a registered solid that may reach the cut this
    // frame. Same selection as the exact replay, without the replay.
    bool BackFaceMesh()
    {
        ID3D11Buffer *indices = nullptr;
        DXGI_FORMAT format; UINT offset;
        context->IAGetIndexBuffer(&indices, &format, &offset);
        bool eligible = false;
        if (indices)
        {
            std::lock_guard<std::mutex> lock(meshMutex);
            for (const auto &mesh : meshes) if (mesh.buffer == indices)
            {
                eligible = (!mesh.bounded || CapMayIntersect(mesh.bounds, cullVolume)) &&
                    !skipFrame.Contains(reinterpret_cast<uintptr_t>(indices), meshGeneration.load());
                if (!eligible) skippedVolumes.fetch_add(1);
                break;
            }
        }
        Drop(indices);
        return eligible;
    }

    // Called only for eligible opaque indexed draws. Caller bypasses its own
    // hooks while replay/composite modifies graphics state.
    bool BeforeVolume(ID3D11PixelShader *original)
    {
        if (!Active() || rendered) return false;
        // Back-face mode marked this eye (the draw hook marks first): no replays.
        // Stencil-less depth or game stencil use keeps the exact path.
        if (backFaceMarked && !stencilConflict.load()) return false;
        ID3D11Buffer *indices = nullptr;
        DXGI_FORMAT format; UINT offset;
        context->IAGetIndexBuffer(&indices, &format, &offset);
        bool eligible = false;
        {
            std::lock_guard<std::mutex> lock(meshMutex);
            for (const auto &mesh : meshes) if (mesh.buffer == indices)
            {
                eligible = !mesh.bounded || CapMayIntersect(mesh.bounds, cullVolume);
                if (eligible && skipFrame.Contains(reinterpret_cast<uintptr_t>(indices), meshGeneration.load())) eligible = false;
                if (!eligible) skippedVolumes.fetch_add(1);
                break;
            }
        }
        Drop(indices);
        if (!eligible) return false;
        // Read once and keep as the state restored by AfterVolume.
        context->OMGetDepthStencilState(&savedDepth, &savedStencilRef);
        D3D11_DEPTH_STENCIL_DESC depthDesc = {};
        if (savedDepth) savedDepth->GetDesc(&depthDesc);
        else { depthDesc.DepthEnable = TRUE; depthDesc.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL; depthDesc.DepthFunc = D3D11_COMPARISON_LESS; }
        // The game owns the eye stencil if a cut solid's draw uses it: never
        // count there again this scene (an already counted eye may glitch once).
        if (depthDesc.StencilEnable) stencilConflict.store(true);
        // Skip additive/Equal repeats: each base/prepass surface counts once.
        if (!depthDesc.DepthEnable || depthDesc.DepthWriteMask != D3D11_DEPTH_WRITE_MASK_ALL ||
            (depthDesc.DepthFunc != D3D11_COMPARISON_LESS && depthDesc.DepthFunc != D3D11_COMPARISON_LESS_EQUAL &&
             depthDesc.DepthFunc != D3D11_COMPARISON_GREATER && depthDesc.DepthFunc != D3D11_COMPARISON_GREATER_EQUAL)) { ReleaseSaved(); return false; }
        // Inline replays keep the bound targets: re-read only after the game
        // changed them (or for the private path, which must restore them).
        if (!target || !inlineMode || targetsChanged)
        {
            context->OMGetRenderTargets(8, savedTargets, &savedDepthView);
            if (!savedTargets[0] || !savedDepthView) { ReleaseSaved(); return false; }
        }
        if (!target)
        {
            bool wantInline = inlineAvailable && inlineEnabled.load() && !stencilConflict.load() && HasStencil(savedDepthView);
            ID3D11Resource *resource = nullptr; savedTargets[0]->GetResource(&resource);
            {
                std::lock_guard<std::mutex> lock(targetMutex);
                for (auto &t : targets) if (resource == t.eye && (wantInline || (t.stencil && t.view)))
                {
                    frameTarget = t;
                    frameTarget.eye->AddRef();
                    if (frameTarget.depth) frameTarget.depth->AddRef();
                    if (frameTarget.view) frameTarget.view->AddRef();
                    if (frameTarget.stencil) frameTarget.stencil->AddRef();
                    target = &frameTarget; break;
                }
            }
            Drop(resource);
            if (!target) { ReleaseSaved(); return false; }
            context->UpdateSubresource(buffer, 0, nullptr, &constants, 0, 0);
            inlineMode = wantInline;
            if (inlineMode)
            {
                // Mid-pass stencil-only clear: no target rebind, no depth loss.
                inlineDepth = savedDepthView; inlineDepth->AddRef();
                context->ClearDepthStencilView(inlineDepth, D3D11_CLEAR_STENCIL, 0.f, 0);
                inlineEyes.fetch_add(1);
            }
            else
            {
                context->ClearDepthStencilView(target->view, D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL,
                    constants.options[0] > .5f ? 0.f : 1.f, 0);
                Fullscreen(nullptr, target->view, entry, initializeDepth, nullptr);
                privateEyes.fetch_add(1);
            }
        }
        else if (inlineMode && targetsChanged && savedDepthView != inlineDepth) { ReleaseSaved(); return false; } // Count stays in one stencil.
        if (inlineMode) targetsChanged = false; // Bound eye depth verified.
        context->RSGetState(&savedRaster);
        context->PSGetShader(&savedPixel, nullptr, nullptr);
        D3D11_RASTERIZER_DESC rs = {};
        if (savedRaster) savedRaster->GetDesc(&rs);
        context->RSSetState(raster[rs.FrontCounterClockwise ? 1 : 0]);
        if (inlineMode)
        {
            // Same targets: color writes masked, winding counted in eye stencil.
            context->OMGetBlendState(&savedBlend, savedFactors, &savedSampleMask);
            context->PSGetConstantBuffers(0, 1, &savedPixelBuffer);
            context->OMSetBlendState(noColor, nullptr, 0xffffffff);
            context->OMSetDepthStencilState(countInlineState, 0);
            context->PSSetShader(countInline, nullptr, 0);
            context->PSSetConstantBuffers(0, 1, &buffer);
        }
        else
        {
            // Empty color target prevents all writes to game eye colors.
            context->OMSetRenderTargets(0, nullptr, target->view);
            context->OMSetDepthStencilState(countDepth[constants.options[0] > .5f ? 1 : 0], 0);
            context->PSSetShader(original, nullptr, 0); // Original alpha-test/discard, no cylinder clip.
        }
        dirty = true; volumeDraws.fetch_add(1); return true;
    }
    void AfterVolume()
    {
        if (inlineMode)
        {
            context->OMSetBlendState(savedBlend, savedFactors, savedSampleMask);
            context->PSSetConstantBuffers(0, 1, &savedPixelBuffer);
        }
        else context->OMSetRenderTargets(8, savedTargets, savedDepthView);
        context->OMSetDepthStencilState(savedDepth, savedStencilRef);
        context->RSSetState(savedRaster);
        context->PSSetShader(savedPixel, nullptr, 0);
        ReleaseSaved();
    }
    void Composite()
    {
        if (!Active()) return;
        if (backFaceMarked && !stencilConflict.load())
        {
            if (backFaceComposited) return;
            ID3D11RenderTargetView *color = nullptr; ID3D11DepthStencilView *depth = nullptr;
            context->OMGetRenderTargets(1, &color, &depth);
            if (color && depth == backFaceDepth)
            {
                // Black where the nearest opaque surface is a back face. Early
                // stencil rejects everything else; the pass also re-zeroes it.
                Fullscreen(color, depth, backFacePixel, backFaceComposite, nullptr, false);
                backFaceComposited = true;
                composites.fetch_add(1);
            }
            Drop(color); Drop(depth);
            return;
        }
        if (!dirty || rendered || !target) return;
        ID3D11RenderTargetView *color = nullptr; ID3D11DepthStencilView *depth = nullptr;
        context->OMGetRenderTargets(1, &color, &depth);
        ID3D11Resource *resource = nullptr;
        if (color) color->GetResource(&resource);
        if (resource == target->eye && depth)
        {
            if (!inlineMode)
            {
                Fullscreen(color, depth, cap[target->desc.SampleDesc.Count > 1 ? 1 : 0],
                    compositeDepth[constants.options[0] > .5f ? 1 : 0], target->stencil);
                rendered = true;
                composites.fetch_add(1);
            }
            else if (depth == inlineDepth)
            {
                // Per-sample stencil test replaces the private mask read; then
                // hand Unity back a zero stencil for later passes.
                Fullscreen(color, depth, capInline, compositeInline[constants.options[0] > .5f ? 1 : 0], nullptr, false);
                context->ClearDepthStencilView(depth, D3D11_CLEAR_STENCIL, 0.f, 0);
                rendered = true;
                composites.fetch_add(1);
            }
        }
        Drop(resource); Drop(color); Drop(depth);
    }
    void ReleaseSaved()
    {
        for (auto &t : savedTargets) Drop(t);
        Drop(savedDepthView); Drop(savedDepth); Drop(savedRaster); Drop(savedPixel);
        Drop(savedBlend); Drop(savedPixelBuffer);
    }
    void End()
    {
        constants.options[2] = 0;
        target = nullptr; inlineMode = false;
        backFaceMarked = backFaceComposited = false;
        Drop(frameTarget.stencil); Drop(frameTarget.view); Drop(frameTarget.depth); Drop(frameTarget.eye);
        Drop(inlineDepth); Drop(backFaceDepth);
    }
    void ModeStats(unsigned &inlineCount, unsigned &privateCount, bool &conflict) const
    {
        inlineCount = inlineEyes.load(); privateCount = privateEyes.load(); conflict = stencilConflict.load();
    }
    // -1 = inline pipeline unavailable, else the optimized-variant bits.
    int InlineVariants() const { return inlineAvailable ? static_cast<int>(shaderVariants) : -1; }
    void Stats(unsigned &available, unsigned &registered, unsigned &replayed, unsigned &composed) const
    {
        available = initialized ? 1 : 0; registered = meshCount.load();
        replayed = volumeDraws.load(); composed = composites.load();
    }
    void CullStats(unsigned &bounded, unsigned &skipped)
    {
        std::lock_guard<std::mutex> lock(meshMutex);
        bounded = 0; for (const auto &mesh : meshes) if (mesh.bounded) ++bounded;
        skipped = skippedVolumes.load();
    }
};
} // namespace qvvr
