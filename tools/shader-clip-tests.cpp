#include "EyeCopyShader.h"
#include "ShaderClip.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <atomic>
#include <new>
#include <windows.h>
#include <d3dcompiler.h>
static std::atomic<bool> trackAllocations(false);
static bool enableDiagnosticCapture = true;
static std::atomic<unsigned> hotAllocations(0);
void *operator new(std::size_t size) {
    if (trackAllocations.load()) hotAllocations.fetch_add(1);
    void *p = std::malloc(size ? size : 1); if (!p) throw std::bad_alloc(); return p;
}
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *p) noexcept { std::free(p); }
void operator delete[](void *p) noexcept { std::free(p); }
void operator delete(void *p, std::size_t) noexcept { std::free(p); }
void operator delete[](void *p, std::size_t) noexcept { std::free(p); }
static ID3DBlob *Compile(const char *source, const char *target)
{
    ID3DBlob *blob = nullptr;
    ID3DBlob *errors = nullptr;
    HRESULT hr = D3DCompile(source, strlen(source), nullptr, nullptr, nullptr, "main", target, 0, 0, &blob, &errors);
    if (errors)
    {
        printf("%s\n", static_cast<const char *>(errors->GetBufferPointer()));
        errors->Release();
    }
    assert(SUCCEEDED(hr));
    return blob;
}
static void DrawTriangle(ID3D11DeviceContext *context)
{
    // Do not let the optimizing test compiler hoist a COM method address
    // across the installation of an in-place vtable hook.
    auto table = *reinterpret_cast<void *volatile **>(context);
    auto draw = reinterpret_cast<void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *, UINT, UINT)>(table[13]);
    draw(context, 3, 0);
}
static void CheckUnusedPositionSignature(ID3DBlob *original)
{
    ID3DBlob *text = nullptr;
    assert(SUCCEEDED(D3DDisassemble(original->GetBufferPointer(), original->GetBufferSize(), 0, nullptr, &text)));
    const char *before = static_cast<const char *>(text->GetBufferPointer());
    // Matches the real QV material: signature includes position, but the
    // optimized instruction stream has no position declaration or reads.
    assert((strstr(before, "SV_Position") || strstr(before, "SV_POSITION")) && !strstr(before, "dcl_input_ps_siv"));
    text->Release();
    std::vector<std::uint8_t> code;
    unsigned slot = 0;
    assert(qvvr::PatchCylinderShader(original->GetBufferPointer(), original->GetBufferSize(), code, slot));
    assert(SUCCEEDED(D3DDisassemble(code.data(), code.size(), 0, nullptr, &text)));
    const char *after = static_cast<const char *>(text->GetBufferPointer());
    bool declared = strstr(after, "dcl_input_ps_siv") != nullptr;
    text->Release();
    if (!declared)
    {
        puts("Unused SV_Position signature regression failed: injected input has no declaration.");
        std::exit(3);
    }
    puts("Unused SV_Position signature regression: injected input declaration present.");
}
static void RenderTest(ID3D11Device *device, ID3D11DeviceContext *context)
{
    // Synthetic WARP test targets only, never headset/game eye textures.
    qvvr::ConfigureShaderDiagnostics(enableDiagnosticCapture);
    assert(qvvr::InstallShaderClip(device));
    D3D11_TEXTURE2D_DESC td = {};
    td.Width = td.Height = 32;
    td.MipLevels = td.ArraySize = 1;
    td.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    td.SampleDesc.Count = 1;
    td.BindFlags = D3D11_BIND_RENDER_TARGET;
    ID3D11Texture2D *color = nullptr;
    assert(SUCCEEDED(device->CreateTexture2D(&td, nullptr, &color)));
    qvvr::SetShaderClipTargets(color, color);
    ID3D11RenderTargetView *target = nullptr;
    assert(SUCCEEDED(device->CreateRenderTargetView(color, nullptr, &target)));
    td.Format = DXGI_FORMAT_D32_FLOAT;
    td.BindFlags = D3D11_BIND_DEPTH_STENCIL;
    ID3D11Texture2D *depth = nullptr;
    assert(SUCCEEDED(device->CreateTexture2D(&td, nullptr, &depth)));
    ID3D11DepthStencilView *depthTarget = nullptr;
    assert(SUCCEEDED(device->CreateDepthStencilView(depth, nullptr, &depthTarget)));
    td.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    td.BindFlags = 0;
    td.Usage = D3D11_USAGE_STAGING;
    td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    ID3D11Texture2D *readback = nullptr;
    assert(SUCCEEDED(device->CreateTexture2D(&td, nullptr, &readback)));
    auto vsCode = Compile("float4 main(uint id:SV_VertexID):SV_Position{float2 p=float2((id<<1)&2,id&2);return "
                          "float4(p*float2(2,-2)+float2(-1,1),.25+.5*p.y,1);}",
                          "vs_4_0");
    auto frontCode = Compile("float4 main(uint id:SV_VertexID):SV_Position{float2 p=float2((id<<1)&2,id&2);return "
                             "float4(p*float2(2,-2)+float2(-1,1),.01,1);}",
                             "vs_4_0");
    ID3D11VertexShader *vs = nullptr;
    ID3D11VertexShader *front = nullptr;
    assert(SUCCEEDED(device->CreateVertexShader(vsCode->GetBufferPointer(), vsCode->GetBufferSize(), nullptr, &vs)));
    assert(SUCCEEDED(
        device->CreateVertexShader(frontCode->GetBufferPointer(), frontCode->GetBufferSize(), nullptr, &front)));
    auto greenCode = Compile("float4 main():SV_Target{return float4(0,1,0,0);}", "ps_4_0");
    auto redCode = Compile("float4 main():SV_Target{return float4(1,0,0,0);}", "ps_4_0");
    ID3D11PixelShader *green = nullptr;
    ID3D11PixelShader *red = nullptr;
    assert(SUCCEEDED(
        device->CreatePixelShader(greenCode->GetBufferPointer(), greenCode->GetBufferSize(), nullptr, &green)));
    assert(SUCCEEDED(device->CreatePixelShader(redCode->GetBufferPointer(), redCode->GetBufferSize(), nullptr, &red)));
    D3D11_VIEWPORT viewport = {0, 0, 32, 32, 0, 1};
    context->RSSetViewports(1, &viewport);
    context->IASetInputLayout(nullptr);
    context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    qvvr::ClipParameters parameters = {};
    parameters.screenToCylinder[0] = 1.f / 16;
    parameters.screenToCylinder[12] = -1;
    parameters.screenToCylinder[10] = 4;
    parameters.screenToCylinder[14] = -2;
    parameters.screenToCylinder[15] = 1;
    parameters.limits[0] = .36f;
    parameters.limits[1] = 10;
    unsigned checked = 0;
    for (int test = 0; test < 3; ++test)
    {
        // Second case includes the top/bottom planes. Third shifts and scales
        // the cylinder matrix, as the VR world transform does.
        if (test == 1)
        {
            parameters.screenToCylinder[5] = 1.f / 16;
            parameters.screenToCylinder[13] = -1;
            parameters.limits[1] = .25f;
        }
        if (test == 2)
        {
            parameters.screenToCylinder[0] = 1.f / 32;
            parameters.screenToCylinder[12] = -.7f;
        }
        float clear[4] = {0, 0, 0, 0};
        context->ClearRenderTargetView(target, clear);
        context->ClearDepthStencilView(depthTarget, D3D11_CLEAR_DEPTH, 1, 0);
        context->OMSetRenderTargets(1, &target, depthTarget);
        context->OMSetBlendState(nullptr, nullptr, 0xffffffff);
        qvvr::BeginShaderClip(parameters);
        context->VSSetShader(front, nullptr, 0);
        context->PSSetShader(red, nullptr, 0);
        DrawTriangle(context);
        context->VSSetShader(vs, nullptr, 0);
        context->PSSetShader(green, nullptr, 0);
        context->Draw(3, 0);
        qvvr::EndShaderClip();
        ID3D11PixelShader *bound = nullptr;
        context->PSGetShader(&bound, nullptr, nullptr);
        assert(bound == green);
        bound->Release();
        context->CopyResource(readback, color);
        D3D11_MAPPED_SUBRESOURCE pixels = {};
        assert(SUCCEEDED(context->Map(readback, 0, D3D11_MAP_READ, 0, &pixels)));
        for (unsigned y = 0; y < 32; ++y)
            for (unsigned x = 0; x < 32; ++x)
            {
                float px = x + .5f, py = y + .5f;
                float localX = parameters.screenToCylinder[0] * px + parameters.screenToCylinder[12];
                float localZ = py / 16 - 1,
                      localY = parameters.screenToCylinder[5] * py + parameters.screenToCylinder[13];
                bool inside = localX * localX + localZ * localZ <= .36f && fabsf(localY) <= parameters.limits[1];
                auto pixel = static_cast<unsigned char *>(pixels.pData) + y * pixels.RowPitch + x * 4;
                assert(pixel[0] == 0 && pixel[2] == 0);
                assert(pixel[1] == (inside ? 255 : 0));
                assert(pixel[3] == (inside ? 255 : 0));
                ++checked;
            }
        context->Unmap(readback, 0);
    }
    // Switching to a shader that really owns b13 must restore the game's b13
    // contents before moving the clip constants to another free slot.
    auto blueCode = Compile("cbuffer C:register(b13){float4 color;}float4 main():SV_Target{return color;}", "ps_4_0");
    ID3D11PixelShader *blue = nullptr;
    assert(
        SUCCEEDED(device->CreatePixelShader(blueCode->GetBufferPointer(), blueCode->GetBufferSize(), nullptr, &blue)));
    D3D11_BUFFER_DESC bd = {};
    bd.ByteWidth = 16;
    bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    const float blueValue[] = {0, 0, 1, 0};
    D3D11_SUBRESOURCE_DATA initial = {blueValue, 0, 0};
    ID3D11Buffer *blueBuffer = nullptr;
    assert(SUCCEEDED(device->CreateBuffer(&bd, &initial, &blueBuffer)));
    float empty[4] = {};
    context->ClearRenderTargetView(target, empty);
    context->ClearDepthStencilView(depthTarget, D3D11_CLEAR_DEPTH, 1, 0);
    unsigned beforePatched = 0, beforeRejected = 0, beforeUnknown = 0, beforeDepthOnly = 0;
    qvvr::GetShaderClipStats(beforePatched, beforeRejected, beforeUnknown, beforeDepthOnly);
    qvvr::BeginShaderClip(parameters);
    context->VSSetShader(vs, nullptr, 0);
    context->PSSetShader(green, nullptr, 0);
    context->Draw(3, 0);
    context->PSSetConstantBuffers(13, 1, &blueBuffer);
    context->PSSetShader(blue, nullptr, 0);
    context->ClearDepthStencilView(depthTarget, D3D11_CLEAR_DEPTH, 1, 0);
    context->Draw(3, 0);
    qvvr::EndShaderClip();
    context->CopyResource(readback, color);
    D3D11_MAPPED_SUBRESOURCE bluePixels = {};
    assert(SUCCEEDED(context->Map(readback, 0, D3D11_MAP_READ, 0, &bluePixels)));
    for (unsigned y = 0; y < 32; ++y)
        for (unsigned x = 0; x < 32; ++x)
        {
            float localX = parameters.screenToCylinder[0] * (x + .5f) + parameters.screenToCylinder[12];
            float localZ = (y + .5f) / 16 - 1;
            bool inside = localX * localX + localZ * localZ <= .36f && fabsf(localZ) <= .25f;
            auto pixel = static_cast<unsigned char *>(bluePixels.pData) + y * bluePixels.RowPitch + x * 4;
            assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == (inside ? 255 : 0) && pixel[3] == (inside ? 255 : 0));
            ++checked;
        }
    context->Unmap(readback, 0);
    blueBuffer->Release();
    blue->Release();
    blueCode->Release();
    // Unity can intentionally bind a null PS for a depth-only prepass. Its
    // interior depth must survive clipping for a subsequent ZTest Equal pass.
    // Treating null as an unknown material and discarding every fragment makes
    // the entire opaque world vanish while the independently rendered UI works.
    D3D11_DEPTH_STENCIL_DESC equalDesc = {};
    equalDesc.DepthEnable = TRUE;
    equalDesc.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO;
    equalDesc.DepthFunc = D3D11_COMPARISON_EQUAL;
    ID3D11DepthStencilState *equalDepth = nullptr;
    assert(SUCCEEDED(device->CreateDepthStencilState(&equalDesc, &equalDepth)));
    context->OMSetRenderTargets(1, &target, depthTarget);
    context->OMSetDepthStencilState(nullptr, 0);
    context->ClearRenderTargetView(target, empty);
    context->ClearDepthStencilView(depthTarget, D3D11_CLEAR_DEPTH, 1, 0);
    qvvr::BeginShaderClip(parameters);
    context->VSSetShader(front, nullptr, 0);
    context->PSSetShader(nullptr, nullptr, 0);
    context->Draw(3, 0); // Exterior foreground must not occlude the interior.
    context->VSSetShader(vs, nullptr, 0);
    context->PSSetShader(nullptr, nullptr, 0);
    context->Draw(3, 0);
    context->OMSetDepthStencilState(equalDepth, 0);
    context->PSSetShader(green, nullptr, 0);
    context->Draw(3, 0);
    qvvr::EndShaderClip();
    context->CopyResource(readback, color);
    D3D11_MAPPED_SUBRESOURCE depthOnlyPixels = {};
    assert(SUCCEEDED(context->Map(readback, 0, D3D11_MAP_READ, 0, &depthOnlyPixels)));
    unsigned depthOnlyFailures = 0;
    for (unsigned y = 0; y < 32; ++y)
        for (unsigned x = 0; x < 32; ++x)
        {
            float localX = parameters.screenToCylinder[0] * (x + .5f) + parameters.screenToCylinder[12];
            float localZ = (y + .5f) / 16 - 1;
            bool inside = localX * localX + localZ * localZ <= .36f && fabsf(localZ) <= .25f;
            auto pixel = static_cast<unsigned char *>(depthOnlyPixels.pData) + y * depthOnlyPixels.RowPitch + x * 4;
            if (pixel[0] != 0 || pixel[1] != (inside ? 255 : 0) || pixel[2] != 0 ||
                pixel[3] != (inside ? 255 : 0)) ++depthOnlyFailures;
            ++checked;
        }
    context->Unmap(readback, 0);
    printf("Depth-only prepass + ZTest Equal: %u mismatched pixels\n", depthOnlyFailures);
    assert(depthOnlyFailures == 0);
    unsigned afterPatched = 0, afterRejected = 0, afterUnknown = 0, afterDepthOnly = 0;
    qvvr::GetShaderClipStats(afterPatched, afterRejected, afterUnknown, afterDepthOnly);
    assert(afterUnknown == beforeUnknown && afterDepthOnly >= beforeDepthOnly + 2);
    context->OMSetDepthStencilState(nullptr, 0);
    equalDepth->Release();
    // Auxiliary/shadow targets inside the scope must not use the eye matrix.
    D3D11_TEXTURE2D_DESC auxiliaryDesc = {};
    color->GetDesc(&auxiliaryDesc);
    ID3D11Texture2D *auxiliary = nullptr;
    assert(SUCCEEDED(device->CreateTexture2D(&auxiliaryDesc, nullptr, &auxiliary)));
    ID3D11RenderTargetView *auxiliaryTarget = nullptr;
    assert(SUCCEEDED(device->CreateRenderTargetView(auxiliary, nullptr, &auxiliaryTarget)));
    context->ClearRenderTargetView(auxiliaryTarget, empty);
    context->ClearDepthStencilView(depthTarget, D3D11_CLEAR_DEPTH, 1, 0);
    qvvr::BeginShaderClip(parameters);
    context->OMSetRenderTargets(1, &auxiliaryTarget, depthTarget);
    context->VSSetShader(front, nullptr, 0);
    context->PSSetShader(red, nullptr, 0);
    context->Draw(3, 0);
    qvvr::EndShaderClip();
    context->CopyResource(readback, auxiliary);
    D3D11_MAPPED_SUBRESOURCE auxiliaryPixels = {};
    assert(SUCCEEDED(context->Map(readback, 0, D3D11_MAP_READ, 0, &auxiliaryPixels)));
    for (unsigned y = 0; y < 32; ++y)
        for (unsigned x = 0; x < 32; ++x)
        {
            auto pixel = static_cast<unsigned char *>(auxiliaryPixels.pData) + y * auxiliaryPixels.RowPitch + x * 4;
            assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 0);
            ++checked;
        }
    context->Unmap(readback, 0);
    auxiliaryTarget->Release();
    auxiliary->Release();
    // Real perspective depth: translated camera/anchor, small near plane,
    // and both D3D forward and reversed Z. Earlier tests had homogeneous w=1
    // and could not validate the inverse projection used by gameplay.
    // Bind a recognizable VS buffer to verify the one-shot diagnostic uses
    // the active GPU contents, not a CPU-side copy of the expected projection.
    const float diagnosticValue[4] = {17.f, 23.f, 41.f, 59.f};
    D3D11_SUBRESOURCE_DATA diagnosticInitial = {diagnosticValue, 0, 0};
    ID3D11Buffer *diagnosticBuffer = nullptr;
    assert(SUCCEEDED(device->CreateBuffer(&bd, &diagnosticInitial, &diagnosticBuffer)));
    context->VSSetConstantBuffers(0, 1, &diagnosticBuffer);
    auto positionCode = Compile("float4 main(float4 p:SV_Position):SV_Target{return float4(0,p.w>0?1:0,0,0);}", "ps_4_0");
    ID3D11PixelShader *positionGreen = nullptr;
    assert(SUCCEEDED(device->CreatePixelShader(positionCode->GetBufferPointer(), positionCode->GetBufferSize(), nullptr, &positionGreen)));
    auto unusedPositionCode = Compile("float4 main(float4 p:SV_Position):SV_Target{return float4(0,1,0,0);}", "ps_4_0");
    CheckUnusedPositionSignature(unusedPositionCode);
    ID3D11PixelShader *unusedPositionGreen = nullptr;
    assert(SUCCEEDED(device->CreatePixelShader(unusedPositionCode->GetBufferPointer(), unusedPositionCode->GetBufferSize(), nullptr, &unusedPositionGreen)));
    for (int test = 0; test < 3; ++test)
    {
        bool reversed = test != 0;
        const float nearPlane = .015f, farPlane = 1000.f, distance = 20.f;
        float a = reversed ? -nearPlane / (farPlane - nearPlane) : farPlane / (farPlane - nearPlane);
        float b = reversed ? nearPlane * farPlane / (farPlane - nearPlane) : -nearPlane * farPlane / (farPlane - nearPlane);
        char source[512];
        sprintf_s(source, "float4 main(uint id:SV_VertexID):SV_Position{float2 p=float2((id<<1)&2,id&2);return "
                  "float4((p*float2(2,-2)+float2(-1,1))*20,%0.9g,20);}", (a + b / distance) * distance);
        auto code = Compile(source, "vs_4_0");
        ID3D11VertexShader *perspectiveVs = nullptr;
        assert(SUCCEEDED(device->CreateVertexShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, &perspectiveVs)));
        qvvr::ClipParameters perspective = {};
        perspective.screenToCylinder[0] = b / 16;
        perspective.screenToCylinder[5] = -b / 16;
        perspective.screenToCylinder[10] = distance;
        perspective.screenToCylinder[11] = 1;
        perspective.screenToCylinder[12] = -b;
        perspective.screenToCylinder[13] = b;
        perspective.screenToCylinder[14] = -distance * a - b;
        perspective.screenToCylinder[15] = -a;
        perspective.limits[0] = 14.5f * 14.5f;
        perspective.limits[1] = 5.25f;
        context->OMSetRenderTargets(1, &target, depthTarget);
        context->OMSetDepthStencilState(nullptr, 0);
        context->ClearRenderTargetView(target, empty);
        context->ClearDepthStencilView(depthTarget, D3D11_CLEAR_DEPTH, 1, 0);
        qvvr::BeginShaderClip(perspective);
        context->VSSetShader(perspectiveVs, nullptr, 0);
        // Cover an existing SV_Position.w-only declaration, not just the
        // newly-added position input in the constant-color shader.
        context->PSSetShader(test == 2 ? unusedPositionGreen : reversed ? positionGreen : green, nullptr, 0);
        DrawTriangle(context);
        qvvr::EndShaderClip();
        context->CopyResource(readback, color);
        D3D11_MAPPED_SUBRESOURCE result = {};
        assert(SUCCEEDED(context->Map(readback, 0, D3D11_MAP_READ, 0, &result)));
        unsigned failed = 0;
        for (unsigned y = 0; y < 32; ++y)
            for (unsigned x = 0; x < 32; ++x)
            {
                bool inside = fabsf(distance * ((x + .5f) / 16 - 1)) <= 14.5f &&
                              fabsf(distance * (1 - (y + .5f) / 16)) <= 5.25f;
                auto pixel = static_cast<unsigned char *>(result.pData) + y * result.RowPitch + x * 4;
                if (pixel[0] != 0 || pixel[1] != (inside ? 255 : 0) || pixel[2] != 0 || pixel[3] != (inside ? 255 : 0)) ++failed;
                ++checked;
            }
        context->Unmap(readback, 0);
        printf("Perspective clipping (%s): %u mismatched pixels\n", test == 2 ? "unused position signature, reversed Z" : reversed ? "reversed Z" : "forward Z", failed);
        assert(failed == 0);
        perspectiveVs->Release();
        code->Release();
    }
    context->Flush();
    if (enableDiagnosticCapture)
    {
    bool diagnosticWritten = false;
    for (int attempt = 0; attempt < 1000 && !diagnosticWritten; ++attempt)
    {
        qvvr::BeginShaderClip(parameters); // Production uses the next frames.
        qvvr::EndShaderClip();
        diagnosticWritten = qvvr::WriteShaderClipDiagnostic(L"artifacts/shader-clip-tests/cylinder-diagnostic.bin");
        if (!diagnosticWritten) Sleep(1); // Test only: at most one second.
    }
    assert(diagnosticWritten);
    FILE *diagnosticFile = nullptr;
    assert(_wfopen_s(&diagnosticFile, L"artifacts/shader-clip-tests/cylinder-diagnostic.bin", L"rb") == 0);
    // Header: magic/version + ClipParameters + viewport + sizes + firstConstants.
    assert(fseek(diagnosticFile, 8 + 80 + 24 + 14 * 4 * 2, SEEK_SET) == 0);
    float actualDiagnostic[4] = {};
    assert(fread(actualDiagnostic, sizeof(actualDiagnostic), 1, diagnosticFile) == 1);
    assert(memcmp(actualDiagnostic, diagnosticValue, sizeof(diagnosticValue)) == 0);
    assert(fseek(diagnosticFile, 8 + 80 + 24 + 14 * 4 * 2 + 14 * 65536, SEEK_SET) == 0);
    unsigned pixelHeader[4] = {};
    assert(fread(pixelHeader, sizeof(pixelHeader), 1, diagnosticFile) == 1);
    assert(pixelHeader[0] == 13 && pixelHeader[1] == 0 && pixelHeader[2] == 80 && pixelHeader[3] == 1);
    qvvr::ClipParameters actualPixelParameters = {};
    assert(fread(&actualPixelParameters, sizeof(actualPixelParameters), 1, diagnosticFile) == 1);
    assert(actualPixelParameters.limits[0] == 14.5f * 14.5f && actualPixelParameters.limits[1] == 5.25f);
    fclose(diagnosticFile);
    puts("GPU constant-buffer diagnostic: active VS data captured; no eye texture readback.");
    }
    else
    {
        unsigned buffers = 0, shaders = 0;
        qvvr::ShaderDiagnosticTestStats(buffers, shaders);
        assert(buffers == 0 && shaders == 0);
        assert(!qvvr::WriteShaderClipDiagnostic(L"artifacts/shader-clip-tests/disabled.bin"));
        puts("Diagnostic disabled: zero staging buffers, zero retained diagnostic shader bytecodes; clipping unchanged.");
    }
    ID3D11Buffer *noBuffer = nullptr;
    context->VSSetConstantBuffers(0, 1, &noBuffer);
    diagnosticBuffer->Release();
    positionGreen->Release();
    positionCode->Release();
    unusedPositionGreen->Release();
    unusedPositionCode->Release();
    printf("GPU clipping: %u pixels passed; outside foreground does not hide inside geometry, alpha 0/1, "
           "radial/height/transform checks.\n",
           checked);
    // A depth-writing SrcAlpha quad with alpha=0 must not hide a later solid.
    D3D11_BLEND_DESC transparentBlend = {};
    auto &rt = transparentBlend.RenderTarget[0];
    rt.BlendEnable = TRUE; rt.SrcBlend = D3D11_BLEND_SRC_ALPHA; rt.DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
    rt.BlendOp = rt.BlendOpAlpha = D3D11_BLEND_OP_ADD;
    rt.SrcBlendAlpha = D3D11_BLEND_ONE; rt.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
    rt.RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    ID3D11BlendState *transparentState = nullptr;
    assert(SUCCEEDED(device->CreateBlendState(&transparentBlend, &transparentState)));
    const float transparentEmpty[4] = {};
    context->ClearRenderTargetView(target, transparentEmpty); context->ClearDepthStencilView(depthTarget, D3D11_CLEAR_DEPTH, 1, 0);
    context->OMSetRenderTargets(1, &target, depthTarget);
    context->OMSetDepthStencilState(nullptr, 0);
    qvvr::ClipParameters interior = {}; interior.screenToCylinder[15] = 1; interior.limits[0] = interior.limits[1] = 1;
    qvvr::BeginShaderClip(interior);
    context->OMSetBlendState(transparentState, nullptr, 0xffffffff);
    context->VSSetShader(front, nullptr, 0); context->PSSetShader(red, nullptr, 0); DrawTriangle(context);
    context->OMSetBlendState(nullptr, nullptr, 0xffffffff);
    context->VSSetShader(vs, nullptr, 0); context->PSSetShader(green, nullptr, 0); DrawTriangle(context);
    qvvr::EndShaderClip();
    context->CopyResource(readback, color);
    D3D11_MAPPED_SUBRESOURCE transparentRead = {};
    assert(SUCCEEDED(context->Map(readback, 0, D3D11_MAP_READ, 0, &transparentRead)));
    for (int y = 0; y < 32; ++y) for (int x = 0; x < 32; ++x)
    {
        auto pixel = static_cast<unsigned char *>(transparentRead.pData) + y * transparentRead.RowPitch + x * 4;
        assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255);
    }
    context->Unmap(readback, 0); transparentState->Release();
    puts("GPU clipping: 1024 zero-alpha depth-writing quad pixels preserve geometry behind them.");
    red->Release();
    green->Release();
    front->Release();
    vs->Release();
    redCode->Release();
    greenCode->Release();
    frontCode->Release();
    vsCode->Release();
    readback->Release();
    depthTarget->Release();
    depth->Release();
    target->Release();
    qvvr::SetShaderClipTargets(nullptr, nullptr);
    color->Release();
}
static void FeatherTest(ID3D11Device *device, ID3D11DeviceContext *context)
{
    // Synthetic WARP targets only. Test REAL hooked variants/blend selection,
    // not a stand-alone approximation of the game's patched shader.
    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = desc.Height = 32; desc.MipLevels = desc.ArraySize = desc.SampleDesc.Count = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM; desc.BindFlags = D3D11_BIND_RENDER_TARGET;
    ID3D11Texture2D *color = nullptr, *read = nullptr;
    assert(SUCCEEDED(device->CreateTexture2D(&desc, nullptr, &color)));
    desc.Usage = D3D11_USAGE_STAGING; desc.BindFlags = 0; desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    assert(SUCCEEDED(device->CreateTexture2D(&desc, nullptr, &read)));
    ID3D11RenderTargetView *target = nullptr;
    assert(SUCCEEDED(device->CreateRenderTargetView(color, nullptr, &target)));
    auto vertex = Compile("float4 main(uint id:SV_VertexID):SV_Position{float2 p=float2((id<<1)&2,id&2);return float4(p*float2(2,-2)+float2(-1,1),.5,1);}", "vs_4_0");
    ID3D11VertexShader *vs = nullptr;
    assert(SUCCEEDED(device->CreateVertexShader(vertex->GetBufferPointer(), vertex->GetBufferSize(), nullptr, &vs)));
    D3D11_VIEWPORT viewport = {0,0,32,32,0,1}; context->RSSetViewports(1, &viewport);
    context->IASetInputLayout(nullptr); context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    qvvr::SetShaderClipTargets(color, color);
    unsigned checks = 0;
    for (int mode = 0; mode < 7; ++mode)
    {
        const char *material = mode == 0 ? "float4 main():SV_Target{return float4(1,0,0,0);}" :
            mode == 1 ? "float4 main():SV_Target{return float4(1,0,0,.5);}" :
            mode == 2 ? "float4 main():SV_Target{return float4(.5,0,0,.5);}" :
            mode == 3 ? "float3 main():SV_Target{return float3(1,0,0);}" :
            mode == 4 ? "float4 main(float4 p:SV_Position):SV_Target{if(p.x<16)return float4(1,0,0,0);float r=0;[loop]for(int i=0;i<3;i++)r+=.333333333;return float4(r,0,0,0);}" :
            "float4 main(float4 p:SV_Position):SV_Target{return float4(p.x<16?0:.5,0,0,1);}";
        auto pixelCode = Compile(material, mode == 4 ? "ps_5_0" : "ps_4_0");
        ID3D11PixelShader *ps = nullptr;
        assert(SUCCEEDED(device->CreatePixelShader(pixelCode->GetBufferPointer(), pixelCode->GetBufferSize(), nullptr, &ps)));
        D3D11_BLEND_DESC blend = {};
        auto &rt = blend.RenderTarget[0]; rt.RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
        rt.BlendEnable = mode == 1 || mode == 2 || mode >= 5;
        rt.SrcBlend = mode == 1 || mode == 5 ? D3D11_BLEND_SRC_ALPHA : D3D11_BLEND_ONE;
        rt.DestBlend = mode >= 5 ? D3D11_BLEND_ONE : D3D11_BLEND_INV_SRC_ALPHA; rt.BlendOp = D3D11_BLEND_OP_ADD;
        rt.SrcBlendAlpha = D3D11_BLEND_ONE; rt.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA; rt.BlendOpAlpha = D3D11_BLEND_OP_ADD;
        ID3D11BlendState *state = nullptr;
        assert(SUCCEEDED(device->CreateBlendState(&blend, &state)));
        qvvr::ClipParameters warm = {};
        warm.screenToCylinder[15] = 1; warm.limits[0] = 1; warm.limits[1] = 1; warm.limits[2] = .2f;
        context->OMSetRenderTargets(1, &target, nullptr);
        context->OMSetBlendState(state, nullptr, 0xffffffff);
        // Resources/shader variants are already created. Only warmed per-frame
        // Begin/target/blend/shader/draw/End hooks are counted here.
        hotAllocations.store(0); trackAllocations.store(true);
        for (int frame = 0; frame < 128; ++frame)
        {
            qvvr::BeginShaderClip(warm);
            context->OMSetRenderTargets(1, &target, nullptr);
            context->OMSetBlendState(state, nullptr, 0xffffffff);
            context->VSSetShader(vs, nullptr, 0); context->PSSetShader(ps, nullptr, 0);
            context->Draw(3,0); qvvr::EndShaderClip();
        }
        trackAllocations.store(false);
        assert(hotAllocations.load() == 0);
        for (int caps = 0; caps < 2; ++caps)
            for (int green = 0; green < 2; ++green)
                for (int disabled = 0; disabled < 2; ++disabled)
                {
                    float clear[4] = {0, static_cast<float>(green), 0, static_cast<float>(green)};
                    context->ClearRenderTargetView(target, clear);
                    context->OMSetRenderTargets(1, &target, nullptr);
                    context->OMSetBlendState(state, nullptr, 0xffffffff);
                    qvvr::ClipParameters p = {};
                    p.screenToCylinder[0] = 1.f/16; p.screenToCylinder[12] = -1;
                    if (caps) { p.screenToCylinder[5] = 1.f/16; p.screenToCylinder[13] = -1; }
                    else { p.screenToCylinder[6] = 1.f/16; p.screenToCylinder[14] = -1; }
                    p.screenToCylinder[15] = 1;
                    p.limits[0] = .64f; p.limits[1] = .6f;
                    p.limits[2] = disabled ? 0.f : .2f; p.limits[3] = static_cast<float>(green);
                    qvvr::BeginShaderClip(p);
                    context->VSSetShader(vs, nullptr, 0); context->PSSetShader(ps, nullptr, 0); context->Draw(3,0);
                    qvvr::EndShaderClip();
                    ID3D11BlendState *restored = nullptr; context->OMGetBlendState(&restored, nullptr, nullptr);
                    assert(restored == state); restored->Release();
                    context->CopyResource(read, color);
                    D3D11_MAPPED_SUBRESOURCE mapped = {}; assert(SUCCEEDED(context->Map(read,0,D3D11_MAP_READ,0,&mapped)));
                    for (int y=0;y<32;++y) for (int x=0;x<32;++x)
                    {
                        float qx=(x+.5f)/16-1, vertical=(y+.5f)/16-1;
                        float radial=sqrtf(qx*qx+(caps?0.f:vertical*vertical));
                        float distance=(std::min)(.8f-radial, .6f-(caps?fabsf(vertical):0.f));
                        float fade=0;
                        bool inside=distance>=0;
                        if (inside) { float t=disabled?1.f:(std::max)(0.f,(std::min)(1.f,distance/.2f)); fade=t*t*(3-2*t); }
                        bool transparent=mode==1 || mode==2;
                        float red=fade*(transparent?.5f:mode>=5?(x<16?0.f:.5f):1.f);
                        float g=green ? (mode>=5?1.f:(1-red)) : 0.f;
                        float a=mode>=5?static_cast<float>(green):!inside ? static_cast<float>(green) : transparent ? (green?1.f:red) : fade;
                        auto pixel=static_cast<unsigned char*>(mapped.pData)+y*mapped.RowPitch+x*4;
                        assert(abs(static_cast<int>(pixel[0])-static_cast<int>(roundf(red*255)))<=2);
                        assert(abs(static_cast<int>(pixel[1])-static_cast<int>(roundf(g*255)))<=2);
                        assert(pixel[2]==0);
                        assert(abs(static_cast<int>(pixel[3])-static_cast<int>(roundf(a*255)))<=2);
                        ++checks;
                    }
                    context->Unmap(read,0);
                }
        state->Release(); ps->Release(); pixelCode->Release();
    }
    qvvr::SetShaderClipTargets(nullptr,nullptr);
    target->Release(); color->Release(); read->Release(); vs->Release(); vertex->Release();
    printf("GPU feather: %u pixels passed; radial/caps, opaque/straight/premultiplied alpha, partial outputs, branch/loop returns, black/green fallback, zero-width, blend restoration.\n", checks);
    puts("GPU feather/additive hot hooks: zero C++ allocations across 896 warmed synthetic frames; black additive texels never add quad coverage.");
}
static void CylinderCapTest(ID3D11Device *device, ID3D11DeviceContext *context)
{
    qvvr::CapCullVolume testVolume = {{0,0,0},2,2};
    assert(!qvvr::CapMayIntersect({{-.1f,-.1f,-.1f},{.1f,.1f,.1f}}, testVolume));
    assert(!qvvr::CapMayIntersect({{4,-1,-1},{5,1,1}}, testVolume));
    assert(qvvr::CapMayIntersect({{-5,-5,-5},{5,5,5}}, testVolume));
    assert(qvvr::CapMayIntersect({{1.99f,-1,-.1f},{2.1f,1,.1f}}, testVolume));
    assert(qvvr::CapMayIntersect({{1,1,1},{-1,-1,-1}}, testVolume));
    unsigned available=0,registered=0,replayed=0,composed=0;
    qvvr::GetCapStats(available,registered,replayed,composed);
    assert(available==1); // Optional pipeline must really compile, not silently skip.
    // Synthetic closed meshes only. Actual production hooks + stencil entry
    // pass/composition. Readback here is test-owned, NEVER a game eye texture.
    const unsigned indices[] = {0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,
        3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5};
    D3D11_BUFFER_DESC ibd = {};
    ibd.ByteWidth = sizeof(indices); ibd.Usage = D3D11_USAGE_IMMUTABLE; ibd.BindFlags = D3D11_BIND_INDEX_BUFFER;
    D3D11_SUBRESOURCE_DATA data = {indices,0,0}; ID3D11Buffer *indexBuffers[3] = {};
    for (auto &ib : indexBuffers) assert(SUCCEEDED(device->CreateBuffer(&ibd,&data,&ib)));
    auto psCode = Compile("float4 main():SV_Target{return float4(1,0,0,1);}","ps_4_0");
    ID3D11PixelShader *ps = nullptr;
    assert(SUCCEEDED(device->CreatePixelShader(psCode->GetBufferPointer(),psCode->GetBufferSize(),nullptr,&ps)));
    unsigned checks = 0;
    for (int perspective=0;perspective<2;++perspective) for (int reverse=0;reverse<2;++reverse) for (int plane=0;plane<2;++plane)
        for (int ms=1;ms<=2;++ms) for (int transparent=0;transparent<2;++transparent)
    {
        context->ClearState();
        D3D11_TEXTURE2D_DESC td = {};
        td.Width=td.Height=32;td.MipLevels=td.ArraySize=1;td.SampleDesc.Count=ms;
        td.Format=DXGI_FORMAT_R8G8B8A8_UNORM;td.BindFlags=D3D11_BIND_RENDER_TARGET;
        ID3D11Texture2D *color=nullptr,*depth=nullptr,*resolved=nullptr,*read=nullptr;
        assert(SUCCEEDED(device->CreateTexture2D(&td,nullptr,&color)));
        ID3D11RenderTargetView *target=nullptr;
        assert(SUCCEEDED(device->CreateRenderTargetView(color,nullptr,&target)));
        td.Format=DXGI_FORMAT_D32_FLOAT;td.BindFlags=D3D11_BIND_DEPTH_STENCIL;
        assert(SUCCEEDED(device->CreateTexture2D(&td,nullptr,&depth)));
        ID3D11DepthStencilView *dsv=nullptr;
        assert(SUCCEEDED(device->CreateDepthStencilView(depth,nullptr,&dsv)));
        td.SampleDesc.Count=1;td.Format=DXGI_FORMAT_R8G8B8A8_UNORM;td.BindFlags=0;
        assert(SUCCEEDED(device->CreateTexture2D(&td,nullptr,&resolved)));
        td.Usage=D3D11_USAGE_STAGING;td.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        assert(SUCCEEDED(device->CreateTexture2D(&td,nullptr,&read)));
        char vsSource[512];
        float pa=reverse?-.05f/(50-.05f):50/(50-.05f),pb=reverse?.05f*50/(50-.05f):-.05f*50/(50-.05f);
        if(perspective)sprintf_s(vsSource,"float4 main(float3 v:POSITION):SV_Position{return float4(v.xy,%0.9g*(v.z+2)+%0.9g,v.z+2);}",pa,pb);
        else sprintf_s(vsSource,"float4 main(float3 v:POSITION):SV_Position{return float4(v.x,v.y,%s,1);}",
            reverse ? "1-(v.z+2)/4" : "(v.z+2)/4");
        auto vsCode=Compile(vsSource,"vs_4_0"); ID3D11VertexShader *vs=nullptr;
        assert(SUCCEEDED(device->CreateVertexShader(vsCode->GetBufferPointer(),vsCode->GetBufferSize(),nullptr,&vs)));
        D3D11_INPUT_ELEMENT_DESC layoutDesc = {"POSITION",0,DXGI_FORMAT_R32G32B32_FLOAT,0,0,D3D11_INPUT_PER_VERTEX_DATA,0};
        ID3D11InputLayout *layout=nullptr;
        assert(SUCCEEDED(device->CreateInputLayout(&layoutDesc,1,vsCode->GetBufferPointer(),vsCode->GetBufferSize(),&layout)));
        // A cliff crossing entry, a wholly inside building, and an exterior
        // solid that MUST NOT fill empty space. In plane mode, Z maps to Y.
        ID3D11Buffer *vertices[3]={};
        const float bounds[3][6]={{-.35f,.35f,-.4f,.4f,-1.8f,.6f},
            {.45f,.65f,-.2f,.2f,-.25f,.2f},{-.7f,-.5f,-.4f,.4f,-1.8f,-1.5f}};
        for(int box=0;box<3;++box)
        {
            const auto &b=bounds[box];
            float v[8][3]={{b[0],b[2],b[4]},{b[1],b[2],b[4]},{b[1],b[3],b[4]},{b[0],b[3],b[4]},
                {b[0],b[2],b[5]},{b[1],b[2],b[5]},{b[1],b[3],b[5]},{b[0],b[3],b[5]}};
            D3D11_BUFFER_DESC vb={};vb.ByteWidth=sizeof(v);vb.Usage=D3D11_USAGE_IMMUTABLE;vb.BindFlags=D3D11_BIND_VERTEX_BUFFER;
            D3D11_SUBRESOURCE_DATA vd={v,0,0}; assert(SUCCEEDED(device->CreateBuffer(&vb,&vd,&vertices[box])));
        }
        D3D11_DEPTH_STENCIL_DESC ds={};ds.DepthEnable=TRUE;ds.DepthWriteMask=D3D11_DEPTH_WRITE_MASK_ALL;
        ds.DepthFunc=reverse?D3D11_COMPARISON_GREATER_EQUAL:D3D11_COMPARISON_LESS_EQUAL;
        ID3D11DepthStencilState *depthState=nullptr;
        assert(SUCCEEDED(device->CreateDepthStencilState(&ds,&depthState)));
        qvvr::ClipParameters p={};
        p.screenToCylinder[0]=1.f/16;p.screenToCylinder[12]=-1;
        if(plane){p.screenToCylinder[9]=reverse?-4.f:4.f;p.screenToCylinder[13]=reverse?2.f:-2.f;
            p.screenToCylinder[6]=-1.f/16;p.screenToCylinder[14]=1;}
        else{p.screenToCylinder[5]=-1.f/16;p.screenToCylinder[13]=1;
            p.screenToCylinder[10]=reverse?-4.f:4.f;p.screenToCylinder[14]=reverse?2.f:-2.f;}
        p.screenToCylinder[15]=1;p.limits[0]=.64f;p.limits[1]=.8f;p.limits[3]=transparent?0.f:1.f;
        if(perspective)
        {
            p.screenToCylinder[0]=pb/16;p.screenToCylinder[12]=-pb;
            p.screenToCylinder[5]=plane?0.f:-pb/16;p.screenToCylinder[6]=plane?-pb/16:0.f;
            p.screenToCylinder[9]=plane?-2.f:0.f;p.screenToCylinder[10]=plane?0.f:-2.f;
            p.screenToCylinder[13]=plane?2*pa+pb:pb;p.screenToCylinder[14]=plane?pb:2*pa+pb;
            p.screenToCylinder[11]=1;p.screenToCylinder[15]=-pa;
        }
        qvvr::SetShaderClipTargets(color,color);
        qvvr::CapCullVolume cull = {{0,0,0},.8f,.8f};
        for (int box = 0; box < 3; ++box)
        {
            qvvr::CapBounds b = {{bounds[box][0],bounds[box][2],bounds[box][4]}, {bounds[box][1],bounds[box][3],bounds[box][5]}};
            if (!plane) qvvr::RegisterCapMeshBounds(indexBuffers[box], b);
            else qvvr::RegisterCapMesh(indexBuffers[box]); // Moving/unbounded fallback.
        }
        qvvr::CapSkipFrame skip, stale;
        skip.generation = qvvr::GetCapRegistryGeneration();
        // Mirrors the managed live-bounds union: only interior/exterior meshes.
        skip.count = 2; skip.buffers[0] = reinterpret_cast<uintptr_t>(indexBuffers[1]);
        skip.buffers[1] = reinterpret_cast<uintptr_t>(indexBuffers[2]);
        stale = skip; --stale.generation;
        stale.count = 3; stale.buffers[2] = reinterpret_cast<uintptr_t>(indexBuffers[0]);
        assert(skip.Contains(skip.buffers[0], skip.generation));
        assert(!stale.Contains(stale.buffers[2], skip.generation));
        auto frame=[&](bool enable,bool instanced,bool unbind,const qvvr::CapSkipFrame *snapshot=nullptr) {
            context->OMSetRenderTargets(1,&target,dsv);
            context->OMSetDepthStencilState(depthState,23);
            context->OMSetBlendState(nullptr,nullptr,0xffffffff);
            context->RSSetState(nullptr);
            D3D11_VIEWPORT viewport={0,0,32,32,0,1};context->RSSetViewports(1,&viewport);
            const float empty[]={0,transparent?0.f:1.f,0,transparent?0.f:1.f};
            context->ClearRenderTargetView(target,empty);
            context->ClearDepthStencilView(dsv,D3D11_CLEAR_DEPTH,reverse?0.f:1.f,0);
            context->IASetInputLayout(layout);context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            context->VSSetShader(vs,nullptr,0);
            qvvr::CapSkipFrame payload = snapshot ? *snapshot : qvvr::CapSkipFrame{};
            qvvr::BeginShaderClip(p,enable,reverse!=0,transparent!=0,plane?nullptr:&cull,&payload);
            payload = {}; // Caller storage may change; the graphics snapshot must not.
            context->PSSetShader(ps,nullptr,0);
            for(int box=0;box<3;++box){int mesh=instanced?2-box:box;auto vb=vertices[mesh];UINT stride=12,offset=0;context->IASetVertexBuffers(0,1,&vb,&stride,&offset);
                context->IASetIndexBuffer(indexBuffers[mesh],DXGI_FORMAT_R32_UINT,0);
                auto table=*reinterpret_cast<void *volatile **>(context);
                if(instanced)reinterpret_cast<void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *,UINT,UINT,UINT,INT,UINT)>(table[20])(context,36,1,0,0,0);
                else reinterpret_cast<void(STDMETHODCALLTYPE *)(ID3D11DeviceContext *,UINT,UINT,INT)>(table[12])(context,36,0,0);}
            if(instanced)qvvr::CompositeShaderCaps(); // Actual BeforeForwardAlpha event.
            if(unbind)context->OMSetRenderTargets(0,nullptr,nullptr); // Camera.Render target restoration regression.
            qvvr::EndShaderClip();
            if(!unbind){ID3D11PixelShader *actual=nullptr;context->PSGetShader(&actual,nullptr,nullptr);
                if(actual!=ps)printf("GPU caps state failed enabled=%d instanced=%d reverse=%d plane=%d ms=%d alpha=%d actual=%p expected=%p\n",enable,instanced,reverse,plane,ms,transparent,actual,ps);
                assert(actual==ps);actual->Release();
                UINT ref;ID3D11DepthStencilState *actualDepth=nullptr;context->OMGetDepthStencilState(&actualDepth,&ref);
                assert(actualDepth==depthState&&ref==23);actualDepth->Release();}
        };
        for(int mode=0;mode<7;++mode)
        {
            unsigned beforeDraws=0; qvvr::GetCapStats(available,registered,beforeDraws,composed);
            frame(mode!=0,mode==2,mode==3,mode==4?&skip:mode==5?&stale:nullptr);
            qvvr::GetCapStats(available,registered,replayed,composed);
            assert(replayed-beforeDraws == (mode==0?0u:!plane||mode==4?1u:3u));
            if(ms>1)context->ResolveSubresource(resolved,0,color,0,DXGI_FORMAT_R8G8B8A8_UNORM);
            else context->CopyResource(resolved,color);
            context->CopyResource(read,resolved);
            D3D11_MAPPED_SUBRESOURCE mapped={};assert(SUCCEEDED(context->Map(read,0,D3D11_MAP_READ,0,&mapped)));
            for(unsigned y=0;y<32;++y)for(unsigned x=0;x<32;++x)
            {
                auto expected=[&](float sx,float sy) {
                    float qx=sx/16-1,qy=1-sy/16;
                    float origin[]={perspective?0.f:qx,perspective?0.f:qy,-2.f};
                    float ray[]={perspective?qx:0.f,perspective?qy:0.f,perspective?1.f:4.f};
                    float n[]={origin[0],plane?origin[2]:origin[1],plane?origin[1]:origin[2]};
                    float d[]={ray[0],plane?ray[2]:ray[1],plane?ray[1]:ray[2]};
                    float a=d[0]*d[0]+d[2]*d[2],b=n[0]*d[0]+n[2]*d[2],c=n[0]*n[0]+n[2]*n[2]-.64f;
                    float enter=-1e20f,leave=1e20f;
                    if(a<1e-12f){if(c>0)return 0;}else{
                        float h=b*b-a*c;if(h<0)return 0;h=sqrtf(h);enter=(-b-h)/a;leave=(-b+h)/a;}
                    if(fabsf(d[1])<1e-12f){if(fabsf(n[1])>.8f)return 0;}else{
                        float t0=(-.8f-n[1])/d[1],t1=(.8f-n[1])/d[1];
                        enter=fmaxf(enter,fminf(t0,t1));leave=fminf(leave,fmaxf(t0,t1));}
                    if(leave<enter||leave<0)return 0;
                    bool cut=false,inside=false;
                    for(const auto &box:bounds){float begin=-1e20f,end=1e20f;
                        for(int axis=0;axis<3;++axis){if(fabsf(ray[axis])<1e-12f){if(origin[axis]<box[axis*2]||origin[axis]>box[axis*2+1])end=-1e20f;}
                            else{float t0=(box[axis*2]-origin[axis])/ray[axis],t1=(box[axis*2+1]-origin[axis])/ray[axis];
                                begin=fmaxf(begin,fminf(t0,t1));end=fminf(end,fmaxf(t0,t1));}}
                        if(end<begin||end<0)continue;
                        if(begin<enter&&end>enter&&enter>0)cut=true;
                        if(begin>=enter&&begin<=leave)inside=true;}
                    return cut&&mode!=0?1:inside?2:0;
                };
                int expect=expected(x+.5f,y+.5f);
                // Exclude only raster edges whose subsamples have different results.
                if(expected(x+.2f,y+.2f)!=expect||expected(x+.8f,y+.8f)!=expect||
                    expected(x+.2f,y+.8f)!=expect||expected(x+.8f,y+.2f)!=expect)continue;
                auto pixel=static_cast<unsigned char*>(mapped.pData)+y*mapped.RowPitch+x*4;
                unsigned r=expect==2?255:0,g=expect==0&&!transparent?255:0,a=expect!=0||!transparent?255:0;
                if(pixel[0]!=r||pixel[1]!=g||pixel[2]!=0||pixel[3]!=a)
                {printf("GPU caps failed perspective=%d reverse=%d plane=%d ms=%d alpha=%d mode=%d pixel=%u,%u got=%u,%u,%u,%u expected=%u,%u,0,%u\n",
                    perspective,reverse,plane,ms,transparent,mode,x,y,pixel[0],pixel[1],pixel[2],pixel[3],r,g,a);std::exit(5);}
                ++checks;
            }
            context->Unmap(read,0);
        }
        // No managed path here; no C++ allocation in warmed production hooks.
        hotAllocations.store(0);trackAllocations.store(true);
        for(int i=0;i<8;++i)frame(true,false,false,&skip);
        trackAllocations.store(false);assert(hotAllocations.load()==0);
        qvvr::ClearCapMeshes();qvvr::SetShaderClipTargets(nullptr,nullptr);
        context->ClearState();
        for(auto vb:vertices)vb->Release();
        depthState->Release();layout->Release();vs->Release();vsCode->Release();
        target->Release();dsv->Release();color->Release();depth->Release();resolved->Release();read->Release();
    }
    ps->Release();psCode->Release();for(auto ib:indexBuffers)ib->Release();
    qvvr::GetCapStats(available,registered,replayed,composed);
    assert(registered==0&&replayed==16*(24+14)&&composed==32*14);
    printf("GPU caps: %u pixels passed; perspective/orthographic, side/height cuts, empty exterior, untouched interior, forward/reversed Z, 1x/2x MSAA, alpha/green, disabled mode, indexed/instanced, target unbind, state restoration.\n",checks);
    puts("GPU caps hot hooks: zero C++ allocations across 256 warmed synthetic frames.");
    puts("GPU caps bounds: identical cut pixels with static/live interior/exterior replay omitted; stale-generation/empty snapshots fail open, caller storage is copied, moving/unbounded fallback preserved.");
}
int main(int argc, char **argv)
{
    enableDiagnosticCapture = !(argc > 1 && strcmp(argv[1], "--no-diagnostics") == 0);
    setvbuf(stdout, nullptr, _IONBF, 0);
    ID3D11Device *device = nullptr;
    ID3D11DeviceContext *context = nullptr;
    assert(SUCCEEDED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0, nullptr, 0, D3D11_SDK_VERSION,
                                       &device, nullptr, &context)));
    if (argc > 1 && enableDiagnosticCapture)
    {
        // Optional uncommitted artifact from the real Frame diagnostic. Never
        // ship or commit captured game shader binaries as test fixtures.
        FILE *file = nullptr;
        assert(fopen_s(&file, argv[1], "rb") == 0);
        assert(fseek(file, 0, SEEK_END) == 0);
        long size = ftell(file);
        assert(size > 0 && size < 1048576);
        rewind(file);
        ID3DBlob *original = nullptr;
        assert(SUCCEEDED(D3DCreateBlob(static_cast<SIZE_T>(size), &original)));
        assert(fread(original->GetBufferPointer(), static_cast<size_t>(size), 1, file) == 1);
        fclose(file);
        CheckUnusedPositionSignature(original);
        for (int variant = 0; variant < 3; ++variant)
        {
            std::vector<std::uint8_t> code;
            unsigned slot = 0;
            assert(qvvr::PatchCylinderShader(original->GetBufferPointer(), original->GetBufferSize(), code, slot, variant == 1, variant == 2));
            ID3D11PixelShader *shader = nullptr;
            assert(SUCCEEDED(device->CreatePixelShader(code.data(), code.size(), nullptr, &shader)));
            shader->Release();
        }
        original->Release();
        puts("Captured QV shader regression: position declaration restored; all three variants accepted by D3D11.");
    }
    const char *sources[] = {
        "float4 main(float2 uv:TEXCOORD):SV_Target{return float4(uv,0,1);}",
        "float4 main(float4 p:SV_Position):SV_Target{return float4(p.zzz,1);}",
        "Texture2D t;SamplerState s;float4 main(float2 uv:TEXCOORD):SV_Target{return t.Sample(s,uv);}",
        "cbuffer C:register(b13){float4 color;}float4 main(float2 uv:TEXCOORD):SV_Target{clip(uv.x-.5);return color;}"};
    for (auto source : sources)
    {
        ID3DBlob *original = nullptr;
        assert(SUCCEEDED(
            D3DCompile(source, strlen(source), nullptr, nullptr, nullptr, "main", "ps_4_0", 0, 0, &original, nullptr)));
        std::vector<std::uint8_t> patched;
        unsigned slot = 0;
        assert(qvvr::PatchCylinderShader(original->GetBufferPointer(), original->GetBufferSize(), patched, slot));
        ID3DBlob *disassembly = nullptr;
        D3DDisassemble(patched.data(), patched.size(), 0, nullptr, &disassembly);
        if (disassembly)
        {
            printf("%s\n", static_cast<const char *>(disassembly->GetBufferPointer()));
            disassembly->Release();
        }
        ID3D11PixelShader *shader = nullptr;
        HRESULT hr = device->CreatePixelShader(patched.data(), patched.size(), nullptr, &shader);
        printf("Create shader=%08x, slot=%u\n", static_cast<unsigned>(hr), slot);
        assert(SUCCEEDED(hr));
        shader->Release();
        original->Release();
    }
    for (int i = 0; i < 6; ++i)
    {
        auto source = qvvr::EyeCopySource(i % 2 != 0, i / 2);
        auto code = Compile(source.c_str(), "ps_4_0");
        ID3D11PixelShader *shader = nullptr;
        assert(SUCCEEDED(device->CreatePixelShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, &shader)));
        shader->Release();
        code->Release();
    }
    puts("OpenXR GPU-copy variants: 6 compiled and validated (Y flip, Gamma/Linear, alpha preserved).");
    RenderTest(device, context);
    FeatherTest(device, context);
    CylinderCapTest(device, context);
    context->Release();
    device->Release();
    puts("Shader clipping bytecode and GPU validation passed.");
}
