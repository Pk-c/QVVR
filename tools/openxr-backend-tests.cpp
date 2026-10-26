// Fake OpenXR runtime + synthetic WARP textures. No real XR/OpenVR client.
#define XR_USE_PLATFORM_WIN32
#define XR_USE_GRAPHICS_API_D3D11
#include <windows.h>
#include <d3d11.h>
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include "OpenXrBackend.h"
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

static ID3D11Device *gpu;
static ID3D11DeviceContext *ctx;
static bool alpha = true, stageSupported = true, render = true, tracking = true, failWait = false;
static bool running = false, frameExtension = true;
static bool expectOpaqueScene = false, failMipSwapchain = false, failHudSwapchain = false;
static int expectedLayers = 1, mipSwapchainAttempts = 0, expectedQuadWidth = 32, expectedQuadHeight = 16;
static XrCompositionLayerQuad lastQuad = {};
static int phase = 0, waits = 0, begins = 0, ends = 0, sessions = 0, destroyed = 0, localSpaces = 0;
static int eventIndex = 0, eventCount = 2, swapIndex = 0, actionIndex = 0, handIndex = 0;
static int suggestions = 0, copies = 0;
static float gripValue = .9f;
static XrTime predicted = 100000;
static XrSessionState events[4] = {XR_SESSION_STATE_READY, XR_SESSION_STATE_FOCUSED};
static std::map<std::string, XrPath> paths;
static std::map<XrAction, std::string> actions;
struct Swap { ID3D11Texture2D *texture = nullptr; bool acquired = false, waited = false; UINT mips = 1; } swaps[3];
template<typename T> static T Handle(int value) { return reinterpret_cast<T>(static_cast<uintptr_t>(value)); }
static XrPosef Pose(float x, float y, float z) {
    XrPosef p = {}; p.orientation.y = p.orientation.w = sqrtf(.5f); p.position = {x,y,z}; return p;
}
static bool Near(float a, float b) { return fabsf(a-b) < .0001f; }
static XrResult XRAPI_CALL Requirements(XrInstance, XrSystemId, XrGraphicsRequirementsD3D11KHR *r) {
    IDXGIDevice *d = nullptr; IDXGIAdapter *a = nullptr; DXGI_ADAPTER_DESC desc = {};
    assert(SUCCEEDED(gpu->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&d))));
    assert(SUCCEEDED(d->GetAdapter(&a))); assert(SUCCEEDED(a->GetDesc(&desc)));
    r->adapterLuid = desc.AdapterLuid; r->minFeatureLevel = D3D_FEATURE_LEVEL_11_0;
    a->Release(); d->Release(); return XR_SUCCESS;
}
extern "C" {
XrResult XRAPI_CALL xrEnumerateInstanceExtensionProperties(const char*, uint32_t capacity, uint32_t *count, XrExtensionProperties *out) {
    *count = frameExtension ? 2 : 1;
    if (capacity) { strcpy_s(out[0].extensionName, XR_KHR_D3D11_ENABLE_EXTENSION_NAME);
        if (frameExtension) strcpy_s(out[1].extensionName, "XR_VALVE_frame_controller_interaction"); }
    return XR_SUCCESS;
}
XrResult XRAPI_CALL xrCreateInstance(const XrInstanceCreateInfo *c, XrInstance *out) {
    assert(c->enabledExtensionCount == (frameExtension ? 2u : 1u)); *out = Handle<XrInstance>(1); return XR_SUCCESS;
}
XrResult XRAPI_CALL xrDestroyInstance(XrInstance) { destroyed++; return XR_SUCCESS; }
XrResult XRAPI_CALL xrGetSystem(XrInstance, const XrSystemGetInfo*, XrSystemId *out) { *out = 1; return XR_SUCCESS; }
XrResult XRAPI_CALL xrEnumerateEnvironmentBlendModes(XrInstance, XrSystemId, XrViewConfigurationType, uint32_t capacity, uint32_t *count, XrEnvironmentBlendMode *out) {
    *count = alpha ? 2 : 1; if (capacity) { out[0] = XR_ENVIRONMENT_BLEND_MODE_OPAQUE; if (alpha) out[1] = XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND; } return XR_SUCCESS;
}
XrResult XRAPI_CALL xrGetInstanceProcAddr(XrInstance, const char *name, PFN_xrVoidFunction *out) {
    assert(!strcmp(name,"xrGetD3D11GraphicsRequirementsKHR")); *out = reinterpret_cast<PFN_xrVoidFunction>(Requirements); return XR_SUCCESS;
}
XrResult XRAPI_CALL xrCreateSession(XrInstance, const XrSessionCreateInfo *c, XrSession *out) {
    assert(reinterpret_cast<const XrGraphicsBindingD3D11KHR*>(c->next)->device == gpu);
    sessions++; swapIndex=actionIndex=handIndex=eventIndex=0; suggestions=0;
    *out = Handle<XrSession>(2); return XR_SUCCESS;
}
XrResult XRAPI_CALL xrDestroySession(XrSession) { assert(phase==0); running=false; return XR_SUCCESS; }
XrResult XRAPI_CALL xrCreateReferenceSpace(XrSession, const XrReferenceSpaceCreateInfo *c, XrSpace *out) {
    if (c->referenceSpaceType==XR_REFERENCE_SPACE_TYPE_STAGE && !stageSupported) return XR_ERROR_REFERENCE_SPACE_UNSUPPORTED;
    if (c->referenceSpaceType==XR_REFERENCE_SPACE_TYPE_LOCAL) localSpaces++;
    *out=Handle<XrSpace>(c->referenceSpaceType==XR_REFERENCE_SPACE_TYPE_VIEW ? 11 : 10); return XR_SUCCESS;
}
XrResult XRAPI_CALL xrDestroySpace(XrSpace) { return XR_SUCCESS; }
XrResult XRAPI_CALL xrStringToPath(XrInstance, const char *name, XrPath *out) {
    if (!paths.count(name)) paths[name]=paths.size()+1; *out=paths[name]; return XR_SUCCESS;
}
XrResult XRAPI_CALL xrCreateActionSet(XrInstance, const XrActionSetCreateInfo*, XrActionSet *out) { *out=Handle<XrActionSet>(30); actions.clear(); return XR_SUCCESS; }
XrResult XRAPI_CALL xrDestroyActionSet(XrActionSet) { return XR_SUCCESS; }
XrResult XRAPI_CALL xrCreateAction(XrActionSet, const XrActionCreateInfo *c, XrAction *out) {
    assert(c->countSubactionPaths==2); *out=Handle<XrAction>(40+actionIndex++); actions[*out]=c->actionName; return XR_SUCCESS;
}
XrResult XRAPI_CALL xrSuggestInteractionProfileBindings(XrInstance, const XrInteractionProfileSuggestedBinding *s) {
    assert(s->countSuggestedBindings==(s->interactionProfile==paths["/interaction_profiles/valve/frame_controller_valve"] ? 16u : 14u)); suggestions++; return XR_SUCCESS;
}
XrResult XRAPI_CALL xrAttachSessionActionSets(XrSession, const XrSessionActionSetsAttachInfo *a) { assert(a->countActionSets==1); return XR_SUCCESS; }
XrResult XRAPI_CALL xrCreateActionSpace(XrSession, const XrActionSpaceCreateInfo*, XrSpace *out) { *out=Handle<XrSpace>(12+handIndex++); return XR_SUCCESS; }
XrResult XRAPI_CALL xrEnumerateSwapchainFormats(XrSession, uint32_t capacity, uint32_t *count, int64_t *out) { *count=1; if(capacity) out[0]=DXGI_FORMAT_B8G8R8A8_UNORM_SRGB; return XR_SUCCESS; }
XrResult XRAPI_CALL xrEnumerateViewConfigurationViews(XrInstance, XrSystemId, XrViewConfigurationType, uint32_t capacity, uint32_t *count, XrViewConfigurationView *out) {
    *count=2; assert(capacity==2); for(int i=0;i<2;i++) { out[i].recommendedImageRectWidth=out[i].recommendedImageRectHeight=32;
        out[i].maxImageRectWidth=out[i].maxImageRectHeight=64; } return XR_SUCCESS;
}
XrResult XRAPI_CALL xrCreateSwapchain(XrSession, const XrSwapchainCreateInfo *c, XrSwapchain *out) {
    // Eyes are square (32x32 or 48x48); HUD swapchains are 2:1.
    if (c->width==2*c->height && failHudSwapchain) return XR_ERROR_RUNTIME_FAILURE;
    if (c->mipCount>1) { mipSwapchainAttempts++; if (failMipSwapchain) return XR_ERROR_SWAPCHAIN_FORMAT_UNSUPPORTED; }
    int free=0; while(free<3 && swaps[free].texture) free++;
    assert(free<3); swapIndex++; Swap &s=swaps[free];
    D3D11_TEXTURE2D_DESC d={}; d.Width=c->width; d.Height=c->height; d.Format=static_cast<DXGI_FORMAT>(c->format);
    d.MipLevels=c->mipCount; d.ArraySize=d.SampleDesc.Count=1; d.BindFlags=D3D11_BIND_RENDER_TARGET;
    assert(SUCCEEDED(gpu->CreateTexture2D(&d,nullptr,&s.texture))); s.acquired=s.waited=false; s.mips=c->mipCount;
    *out=reinterpret_cast<XrSwapchain>(&s); return XR_SUCCESS;
}
XrResult XRAPI_CALL xrDestroySwapchain(XrSwapchain handle) { auto s=reinterpret_cast<Swap*>(handle); assert(!s->acquired); s->texture->Release(); s->texture=nullptr; return XR_SUCCESS; }
XrResult XRAPI_CALL xrEnumerateSwapchainImages(XrSwapchain handle, uint32_t capacity, uint32_t *count, XrSwapchainImageBaseHeader *out) {
    *count=1; if(capacity) reinterpret_cast<XrSwapchainImageD3D11KHR*>(out)->texture=reinterpret_cast<Swap*>(handle)->texture; return XR_SUCCESS;
}
XrResult XRAPI_CALL xrAcquireSwapchainImage(XrSwapchain handle, const XrSwapchainImageAcquireInfo*, uint32_t *out) { auto s=reinterpret_cast<Swap*>(handle); assert(!s->acquired && phase==2); s->acquired=true; *out=0; return XR_SUCCESS; }
XrResult XRAPI_CALL xrWaitSwapchainImage(XrSwapchain handle, const XrSwapchainImageWaitInfo*) { auto s=reinterpret_cast<Swap*>(handle); assert(s->acquired); s->waited=true; return XR_SUCCESS; }
XrResult XRAPI_CALL xrReleaseSwapchainImage(XrSwapchain handle, const XrSwapchainImageReleaseInfo*) { auto s=reinterpret_cast<Swap*>(handle); assert(s->waited); s->acquired=s->waited=false; copies++; return XR_SUCCESS; }
XrResult XRAPI_CALL xrPollEvent(XrInstance, XrEventDataBuffer *out) {
    if(eventIndex==eventCount) return XR_EVENT_UNAVAILABLE;
    auto e=reinterpret_cast<XrEventDataSessionStateChanged*>(out); e->type=XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED;
    e->session=Handle<XrSession>(2); e->state=events[eventIndex++]; return XR_SUCCESS;
}
XrResult XRAPI_CALL xrBeginSession(XrSession, const XrSessionBeginInfo*) { assert(!running); running=true; return XR_SUCCESS; }
XrResult XRAPI_CALL xrEndSession(XrSession) { assert(running && phase==0); running=false; return XR_SUCCESS; }
XrResult XRAPI_CALL xrWaitFrame(XrSession, const XrFrameWaitInfo*, XrFrameState *out) {
    assert(running && phase==0); if(failWait) return XR_ERROR_RUNTIME_FAILURE;
    waits++; phase=1; predicted+=100; out->predictedDisplayTime=predicted; out->predictedDisplayPeriod=13888889; out->shouldRender=render; return XR_SUCCESS;
}
XrResult XRAPI_CALL xrBeginFrame(XrSession, const XrFrameBeginInfo*) { assert(phase==1); phase=2; begins++; return XR_SUCCESS; }
XrResult XRAPI_CALL xrLocateViews(XrSession, const XrViewLocateInfo *l, XrViewState *s, uint32_t capacity, uint32_t *count, XrView *out) {
    assert(phase==2 && l->displayTime==predicted && capacity==2); *count=2;
    s->viewStateFlags=tracking ? XR_VIEW_STATE_ORIENTATION_VALID_BIT|XR_VIEW_STATE_POSITION_VALID_BIT : 0;
    for(int i=0;i<2;i++) { out[i].pose=Pose(1.f,2.f,3.f+(i==0?.032f:-.032f)); out[i].fov={-.9f,.6f,.7f,-.8f}; } return XR_SUCCESS;
}
XrResult XRAPI_CALL xrLocateSpace(XrSpace space, XrSpace, XrTime time, XrSpaceLocation *out) {
    assert(phase==2 && time==predicted); out->locationFlags=XR_SPACE_LOCATION_ORIENTATION_VALID_BIT|XR_SPACE_LOCATION_POSITION_VALID_BIT;
    out->pose=space==Handle<XrSpace>(11) ? Pose(1,2,3) : Pose(space==Handle<XrSpace>(12)?-.2f:.2f,1,-.5f); return XR_SUCCESS;
}
XrResult XRAPI_CALL xrSyncActions(XrSession, const XrActionsSyncInfo *s) { assert(phase==2 && s->countActiveActionSets==1); return XR_SUCCESS; }
XrResult XRAPI_CALL xrGetActionStatePose(XrSession, const XrActionStateGetInfo*, XrActionStatePose *out) { out->isActive=true; return XR_SUCCESS; }
XrResult XRAPI_CALL xrGetActionStateBoolean(XrSession, const XrActionStateGetInfo *g, XrActionStateBoolean *out) { out->isActive=out->currentState=frameExtension || actions[g->action]!="grip_click"; return XR_SUCCESS; }
XrResult XRAPI_CALL xrGetActionStateFloat(XrSession, const XrActionStateGetInfo *g, XrActionStateFloat *out) { out->isActive=true; out->currentState=actions[g->action]=="grip"?gripValue:.7f; return XR_SUCCESS; }
XrResult XRAPI_CALL xrGetActionStateVector2f(XrSession, const XrActionStateGetInfo*, XrActionStateVector2f *out) { out->isActive=true; out->currentState={.3f,-.5f}; return XR_SUCCESS; }
XrResult XRAPI_CALL xrEndFrame(XrSession, const XrFrameEndInfo *e) {
    assert(phase==2 && e->displayTime==predicted && e->environmentBlendMode==XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND);
    assert(!swaps[0].acquired && !swaps[1].acquired && !swaps[2].acquired);
    if(e->layerCount) {
        assert(e->layerCount==static_cast<uint32_t>(expectedLayers)); auto p=reinterpret_cast<const XrCompositionLayerProjection*>(e->layers[0]);
        assert(p->type==XR_TYPE_COMPOSITION_LAYER_PROJECTION);
        if(e->layerCount==2) {
            auto q=reinterpret_cast<const XrCompositionLayerQuad*>(e->layers[1]);
            assert(q->type==XR_TYPE_COMPOSITION_LAYER_QUAD && q->space==Handle<XrSpace>(10));
            assert(q->layerFlags==XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT && q->eyeVisibility==XR_EYE_VISIBILITY_BOTH);
            assert(q->subImage.swapchain==reinterpret_cast<XrSwapchain>(&swaps[2]) && q->subImage.imageArrayIndex==0);
            assert(q->subImage.imageRect.offset.x==0 && q->subImage.imageRect.extent.width==expectedQuadWidth && q->subImage.imageRect.extent.height==expectedQuadHeight);
            lastQuad=*q;
        }
        assert(p->viewCount==2 && p->space==Handle<XrSpace>(10));
        assert(p->layerFlags==(expectOpaqueScene ? 0 : XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT));
        assert(Near(p->views[0].pose.position.z,3.032f) && Near(p->views[1].pose.position.z,2.968f));
        assert(Near(p->views[0].fov.angleLeft,-.9f));
    }
    phase=0; ends++; return XR_SUCCESS;
}
}
static ID3D11Texture2D *Source(bool opaqueColor = false) {
    // Entirely synthetic 32x32 image: lower half opaque, upper half transparent.
    uint32_t pixels[1024]; for(int y=0;y<32;y++) for(int x=0;x<32;x++) pixels[y*32+x]=y<16?(opaqueColor ? 0x00808080u : 0u):0xffffffffu;
    D3D11_TEXTURE2D_DESC d={}; d.Width=d.Height=32; d.MipLevels=d.ArraySize=d.SampleDesc.Count=1;
    d.Format=DXGI_FORMAT_B8G8R8A8_UNORM; d.BindFlags=D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA data={pixels,128,0}; ID3D11Texture2D *texture=nullptr;
    assert(SUCCEEDED(gpu->CreateTexture2D(&d,&data,&texture))); return texture;
}
// 32x16 HUD with a full mip chain: mip 0 top half opaque white, bottom half
// transparent (or additive gray with alpha 0); smaller mips distinct opaque grays
// so the trilinear resample's level selection is observable.
static ID3D11Texture2D *HudSource(bool additive = false) {
    D3D11_TEXTURE2D_DESC d={}; d.Width=32; d.Height=16; d.MipLevels=6; d.ArraySize=d.SampleDesc.Count=1;
    d.Format=DXGI_FORMAT_B8G8R8A8_UNORM; d.BindFlags=D3D11_BIND_SHADER_RESOURCE;
    static uint32_t pixels[6][512]; D3D11_SUBRESOURCE_DATA data[6]={};
    for(int m=0;m<6;m++) { UINT w=32u>>m, h=(std::max)(1u,16u>>m);
        for(UINT y=0;y<h;y++) for(UINT x=0;x<w;x++) { uint32_t g=(m+1)*30u;
            pixels[m][y*w+x]=m==0?(y<8?0xffffffffu:(additive?0x00808080u:0u)):(0xff000000u|(g<<16)|(g<<8)|g); }
        data[m]={pixels[m],w*4,0}; }
    ID3D11Texture2D *texture=nullptr; assert(SUCCEEDED(gpu->CreateTexture2D(&d,data,&texture))); return texture;
}
// Reads one pixel of one mip of the HUD swapchain texture.
static uint32_t HudPixel(UINT mip, UINT x, UINT y) {
    D3D11_TEXTURE2D_DESC d={}; swaps[2].texture->GetDesc(&d); d.Usage=D3D11_USAGE_STAGING; d.BindFlags=0; d.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
    ID3D11Texture2D *read=nullptr; assert(SUCCEEDED(gpu->CreateTexture2D(&d,nullptr,&read))); ctx->CopyResource(read,swaps[2].texture);
    D3D11_MAPPED_SUBRESOURCE data={}; UINT sub=D3D11CalcSubresource(mip,0,d.MipLevels);
    assert(SUCCEEDED(ctx->Map(read,sub,D3D11_MAP_READ,0,&data)));
    uint32_t value=*reinterpret_cast<uint32_t*>(static_cast<unsigned char*>(data.pData)+y*data.RowPitch+x*4);
    ctx->Unmap(read,sub); read->Release(); return value;
}
static bool NearByte(uint32_t pixel, int shift, int expected) { return abs(int((pixel>>shift)&255u)-expected)<=1; }
static void SubmitHud(ID3D11Texture2D *eyes, ID3D11Texture2D *hudTexture, const qvvr::HudLayer &hud, int layers, int expectedCopies) {
    qvvr::OpenXrFrame frame={}; vr::HmdMatrix34_t head={}; int before=copies; expectedLayers=layers;
    assert(qvvr::PrepareOpenXrFrame(frame)==1 && qvvr::BeginOpenXrFrame(eyes));
    assert(qvvr::SubmitOpenXrFrame(eyes,eyes,head,true,false,hudTexture,&hud) && copies==before+expectedCopies);
    expectedLayers=1;
}
static void CheckSyntheticAlpha(ID3D11Texture2D *source) {
    D3D11_TEXTURE2D_DESC d={}; source->GetDesc(&d); d.Usage=D3D11_USAGE_STAGING; d.BindFlags=0; d.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
    ID3D11Texture2D *read=nullptr; assert(SUCCEEDED(gpu->CreateTexture2D(&d,nullptr,&read))); ctx->CopyResource(read,source);
    D3D11_MAPPED_SUBRESOURCE data={}; assert(SUCCEEDED(ctx->Map(read,0,D3D11_MAP_READ,0,&data)));
    auto bytes=static_cast<unsigned char*>(data.pData); assert(bytes[3]==255 && bytes[31*data.RowPitch+3]==0);
    ctx->Unmap(read,0); read->Release();
}
int main() {
    D3D_FEATURE_LEVEL level; assert(SUCCEEDED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,nullptr,0,D3D11_SDK_VERSION,&gpu,&level,&ctx)));
    auto texture=Source(); uint32_t width=0,height=0; qvvr::OpenXrFrame frame={};
    qvvr::ConfigureOpenXr(true);
    assert(qvvr::InitializeExclusiveOpenXr(texture,1,width,height) && width==32 && height==32 && suggestions==2);
    assert(qvvr::PrepareOpenXrFrame(frame) && qvvr::OpenXrStatus()==3);
    assert(Near(frame.head.m[0][3],1) && Near(frame.head.m[2][0],-1) && Near(frame.leftEye.m[2][3],3.032f));
    assert(frame.leftHand.valid==3 && frame.rightHand.buttons==15 && Near(frame.rightHand.grip,.9f) && Near(frame.leftHand.stickX,.3f));
    int oldWaits=waits; qvvr::OpenXrFrame other={}; other.rightHand.buttons=123;
    assert(qvvr::PrepareOpenXrFrame(other)==2 && waits==oldWaits && other.rightHand.buttons==123);
    assert(qvvr::BeginOpenXrFrame(texture)); vr::HmdMatrix34_t unusedHead={}; unusedHead.m[0][3]=999;
    assert(qvvr::SubmitOpenXrFrame(texture,texture,unusedHead,true) && copies==2);
    CheckSyntheticAlpha(swaps[0].texture); CheckSyntheticAlpha(swaps[1].texture);
    assert(!qvvr::SubmitOpenXrFrame(texture,texture,unusedHead,true));
    // Opaque selection: original RGB may have unused zero alpha. Gamma copy
    // must decode that RGB normally, not divide by zero/premultiplied alpha.
    auto colored=Source(true); qvvr::SetOpenXrColorSpace(true,false);
    assert(qvvr::PrepareOpenXrFrame(frame)==1&&qvvr::BeginOpenXrFrame(colored));
    expectOpaqueScene=true;
    assert(qvvr::SubmitOpenXrFrame(colored,colored,unusedHead,true,true));
    expectOpaqueScene=false;
    D3D11_TEXTURE2D_DESC rd={}; swaps[0].texture->GetDesc(&rd);rd.Usage=D3D11_USAGE_STAGING;rd.BindFlags=0;rd.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
    ID3D11Texture2D *readOpaque=nullptr;assert(SUCCEEDED(gpu->CreateTexture2D(&rd,nullptr,&readOpaque)));
    ctx->CopyResource(readOpaque,swaps[0].texture);D3D11_MAPPED_SUBRESOURCE mapped={};
    assert(SUCCEEDED(ctx->Map(readOpaque,0,D3D11_MAP_READ,0,&mapped)));
    auto last=static_cast<unsigned char*>(mapped.pData)+31*mapped.RowPitch;
    // Linear shader output (~55/255) is stored through an sRGB RTV: encoded
    // bytes must round-trip to 128, NOT white from alpha division.
    assert(abs(int(last[0])-128)<=1&&abs(int(last[1])-128)<=1&&abs(int(last[2])-128)<=1&&last[3]==0);
    ctx->Unmap(readOpaque,0);
    // Visible additive emission on an empty eye background must be decoded
    // normally, not divided by zero; only emission gets coverage, black stays 0.
    for (int gamma=0;gamma<2;++gamma) {
        qvvr::SetOpenXrColorSpace(gamma!=0,false);
        // Color-space configuration is fixed at resource creation in production;
        // each test source must likewise get a newly classified SRV.
        auto emission=Source(true);
        assert(qvvr::PrepareOpenXrFrame(frame)==1&&qvvr::BeginOpenXrFrame(emission));
        assert(qvvr::SubmitOpenXrFrame(emission,emission,unusedHead,true));
        ctx->CopyResource(readOpaque,swaps[0].texture);
        assert(SUCCEEDED(ctx->Map(readOpaque,0,D3D11_MAP_READ,0,&mapped)));
        last=static_cast<unsigned char*>(mapped.pData)+31*mapped.RowPitch;
        int colorByte=gamma?128:188,alphaByte=gamma?55:128;
        assert(abs(int(last[0])-colorByte)<=1&&abs(int(last[1])-colorByte)<=1&&abs(int(last[2])-colorByte)<=1);
        assert(abs(int(last[3])-alphaByte)<=1); // not a solid alpha=255 rectangle
        ctx->Unmap(readOpaque,0);
        emission->Release();
    }
    readOpaque->Release();colored->Release();qvvr::SetOpenXrColorSpace(true,false);
    assert(qvvr::PrepareOpenXrFrame(frame)==1&&qvvr::BeginOpenXrFrame(texture));
    assert(qvvr::SubmitOpenXrFrame(texture,texture,unusedHead,true));
    CheckSyntheticAlpha(swaps[0].texture); // Back to gameplay: passthrough restored.
    // HUD compositor quad: created lazily as a single-level swapchain, resampled
    // from the mipmapped capture, copied only on a new content version.
    assert(qvvr::OpenXrHudStatus()==0);
    auto hudTexture=HudSource();
    qvvr::HudLayer hud={.25f,1.5f,-1.4f, 0,0,0,2, 1.8f,1.f, 1u,7u};
    SubmitHud(texture,hudTexture,hud,2,3);
    assert(qvvr::OpenXrHudStatus()==1 && swaps[2].mips==1 && mipSwapchainAttempts==0);
    assert(Near(lastQuad.pose.orientation.w,1) && Near(lastQuad.pose.orientation.x,0) && Near(lastQuad.size.width,1.8f) && Near(lastQuad.size.height,1));
    assert(Near(lastQuad.pose.position.x,.25f) && Near(lastQuad.pose.position.y,1.5f) && Near(lastQuad.pose.position.z,-1.4f));
    // Y flip like the eyes: source top rows (opaque white) land at the bottom.
    uint32_t top=HudPixel(0,3,0), bottom=HudPixel(0,3,15);
    assert(top==0 && NearByte(bottom,24,255) && NearByte(bottom,16,255) && NearByte(bottom,0,255));
    SubmitHud(texture,hudTexture,hud,2,2); // Unchanged HUD: quad reuses the released image, no copy.
    hud.version=8; SubmitHud(texture,hudTexture,hud,2,3);
    hud.visible=0; SubmitHud(texture,hudTexture,hud,1,2);
    hud.visible=1; hud.width=0; SubmitHud(texture,hudTexture,hud,1,2); hud.width=1.8f;
    hud.qw=0; SubmitHud(texture,hudTexture,hud,1,2); hud.qw=1;
    SubmitHud(texture,hudTexture,hud,2,2); // Valid again: no recopy needed.
    // Additive HUD pixels keep alpha 0 (pure added light), with decoded color.
    auto additiveHud=HudSource(true);
    SubmitHud(texture,additiveHud,hud,2,3);
    uint32_t glow=HudPixel(0,3,0);
    assert(NearByte(glow,24,0) && NearByte(glow,16,128) && NearByte(glow,0,128));
    // Width cap: half-size swapchain samples the next mip level (trilinear LOD 1).
    auto flatHud=HudSource(); qvvr::SetOpenXrHudMaxWidth(16); expectedQuadWidth=16; expectedQuadHeight=8;
    SubmitHud(texture,flatHud,hud,2,3); assert(swaps[2].mips==1 && qvvr::OpenXrHudStatus()==1);
    uint32_t mipOne=HudPixel(0,5,5); assert(NearByte(mipOne,24,255) && NearByte(mipOne,16,60) && NearByte(mipOne,0,60));
    qvvr::SetOpenXrHudMaxWidth(0); expectedQuadWidth=32; expectedQuadHeight=16;
    // A runtime refusing the HUD swapchain: projection continues, HUD stays in eyes.
    auto refusedHud=HudSource(); failHudSwapchain=true;
    SubmitHud(texture,refusedHud,hud,1,2); assert(qvvr::OpenXrHudStatus()==-1 && !swaps[2].texture); failHudSwapchain=false;
    SubmitHud(texture,refusedHud,hud,1,2); assert(qvvr::OpenXrHudStatus()==-1); // Sticky until session restart.
    additiveHud->Release();
    hudTexture->Release(); flatHud->Release(); refusedHud->Release();
    auto cadence=qvvr::ReadOpenXrPacing();
    assert(cadence.periodMs>13&&cadence.periodMs<15&&cadence.intervals>0);
    assert(cadence.maximumQueueAgeMs>=0&&cadence.maximumCopySubmitMs>=0);
    assert(qvvr::ReadOpenXrPacing().intervals==0); // Window read never mutates the latched XR frame.
    gripValue=0; assert(qvvr::PrepareOpenXrFrame(frame)==1 && (frame.rightHand.buttons&8)!=0 && frame.rightHand.grip==0);
    qvvr::CancelOpenXrFrame(); gripValue=.9f;
    render=false; assert(!qvvr::PrepareOpenXrFrame(frame) && phase==0); render=true;
    tracking=false; assert(!qvvr::PrepareOpenXrFrame(frame) && phase==0); tracking=true;
    assert(qvvr::PrepareOpenXrFrame(frame)); qvvr::CancelOpenXrFrame(); assert(phase==0);
    events[0]=XR_SESSION_STATE_STOPPING; eventIndex=0; eventCount=1;
    assert(!qvvr::PrepareOpenXrFrame(frame) && !running);
    qvvr::ShutdownOpenXr(); assert(!qvvr::OpenXrRequested() && qvvr::OpenXrStatus()==0 && qvvr::OpenXrHudStatus()==0);
    events[0]=XR_SESSION_STATE_READY; events[1]=XR_SESSION_STATE_FOCUSED; eventCount=2;
    stageSupported=false; frameExtension=false; qvvr::ConfigureOpenXr(true);
    assert(qvvr::InitializeExclusiveOpenXr(texture,1.5f,width,height) && width==48 && localSpaces==1 && suggestions==1);
    failWait=true; assert(!qvvr::PrepareOpenXrFrame(frame) && qvvr::OpenXrStatus()<0 && !qvvr::OpenXrSelected()); failWait=false;
    qvvr::ShutdownOpenXr(); alpha=false; qvvr::ConfigureOpenXr(true); int oldSessions=sessions;
    assert(!qvvr::InitializeExclusiveOpenXr(texture,1,width,height) && sessions==oldSessions && qvvr::OpenXrError()==XR_ERROR_ENVIRONMENT_BLEND_MODE_UNSUPPORTED);
    qvvr::ShutdownOpenXr(); assert(begins==ends && destroyed==3);
    texture->Release(); ctx->Release(); gpu->Release();
    puts("Exclusive XR fake-runtime/WARP passed: ABI, Frame/Touch actions, exact stereo poses/FOV, ALPHA_BLEND, GPU alpha/Y-copy, HUD quad layer (single-level resample, additive alpha, versioned copy, refusal), one-frame backpressure, cancel, no-render, tracking loss, STOPPING, LOCAL fallback, failure cleanup, unsupported alpha. No OpenVR linked or real XR session started.");
}
