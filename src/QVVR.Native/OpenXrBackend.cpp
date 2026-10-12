#define XR_USE_PLATFORM_WIN32
#define XR_USE_GRAPHICS_API_D3D11
#include "OpenXrBackend.h"
#include "EyeCopyShader.h"
#include <atomic>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <d3d11_1.h>
#include <d3dcompiler.h>
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include <vector>
#include <windows.h>

namespace qvvr
{
namespace
{
std::atomic<bool> requested(false);
std::atomic<int> status(0), lastError(0);
std::atomic<bool> selected(false), frameBegun(false);
bool running = false, shouldRender = false;
XrInstance instance = XR_NULL_HANDLE;
XrSession session = XR_NULL_HANDLE;
XrSystemId system = XR_NULL_SYSTEM_ID;
XrSpace stage = XR_NULL_HANDLE;
XrSpace viewSpace = XR_NULL_HANDLE, handSpaces[2] = {};
XrActionSet actionSet = XR_NULL_HANDLE;
XrAction handPose = XR_NULL_HANDLE, stick = XR_NULL_HANDLE, stickClick = XR_NULL_HANDLE;
XrAction grip = XR_NULL_HANDLE, trigger = XR_NULL_HANDLE, confirm = XR_NULL_HANDLE, back = XR_NULL_HANDLE;
XrAction gripClick = XR_NULL_HANDLE;
XrPath handPaths[2] = {};
bool frameControllerProfile = false;
XrView locatedViews[2] = {{XR_TYPE_VIEW}, {XR_TYPE_VIEW}};
XrTime displayTime = 0;
XrSessionState state = XR_SESSION_STATE_UNKNOWN;
ID3D11Device *device = nullptr;
ID3D11DeviceContext1 *context = nullptr;
ID3DDeviceContextState *copyState = nullptr;
ID3D11VertexShader *copyVs = nullptr;
ID3D11PixelShader *copyPs[6] = {};
int colorDecodeMode = 0;
ID3D11ShaderResourceView *sources[2] = {};
ID3D11Texture2D *sourceTextures[2] = {};
int sourceDecodeMode[2] = {};
struct Eye
{
    XrSwapchain swapchain = XR_NULL_HANDLE;
    std::vector<XrSwapchainImageD3D11KHR> images;
    std::vector<ID3D11RenderTargetView *> targets;
    uint32_t width = 0, height = 0;
    bool acquired = false, waited = false;
    uint32_t index = 0;
} eyes[2];
bool Check(XrResult result)
{
    if (XR_FAILED(result))
    {
        lastError.store(result);
        return false;
    }
    return true;
}
template <typename T> void Release(T *&pointer)
{
    if (pointer)
    {
        pointer->Release();
        pointer = nullptr;
    }
}
void Destroy()
{
    selected.store(false);
    for (auto &eye : eyes)
    {
        if (eye.acquired && eye.swapchain)
        {
            if (!eye.waited)
            {
                XrSwapchainImageWaitInfo wait = {XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};
                wait.timeout = 1000000000;
                eye.waited = xrWaitSwapchainImage(eye.swapchain, &wait) == XR_SUCCESS;
            }
            if (eye.waited)
            {
                XrSwapchainImageReleaseInfo release = {XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
                xrReleaseSwapchainImage(eye.swapchain, &release);
            }
            eye.acquired = eye.waited = false;
        }
    }
    if (frameBegun && session)
    {
        XrFrameEndInfo end = {XR_TYPE_FRAME_END_INFO};
        end.displayTime = displayTime;
        end.environmentBlendMode = XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND;
        xrEndFrame(session, &end);
        frameBegun = false;
    }
    for (auto &eye : eyes)
    {
        for (auto target : eye.targets)
            if (target)
                target->Release();
        eye.targets.clear();
        eye.images.clear();
        if (eye.swapchain)
            xrDestroySwapchain(eye.swapchain);
        eye.swapchain = XR_NULL_HANDLE;
        eye.acquired = eye.waited = false;
    }
    Release(copyState);
    Release(copyVs);
    for (auto &shader : copyPs)
        Release(shader);
    for (int i = 0; i < 2; ++i)
    {
        Release(sources[i]);
        Release(sourceTextures[i]);
    }
    Release(context);
    Release(device);
    for (auto &space : handSpaces)
    {
        if (space) xrDestroySpace(space);
        space = XR_NULL_HANDLE;
    }
    if (viewSpace) xrDestroySpace(viewSpace);
    viewSpace = XR_NULL_HANDLE;
    if (stage)
        xrDestroySpace(stage);
    stage = XR_NULL_HANDLE;
    if (session)
        xrDestroySession(session);
    session = XR_NULL_HANDLE;
    if (actionSet) xrDestroyActionSet(actionSet);
    actionSet = XR_NULL_HANDLE;
    handPose = stick = stickClick = grip = trigger = confirm = back = XR_NULL_HANDLE;
    gripClick = XR_NULL_HANDLE;
    if (instance)
        xrDestroyInstance(instance);
    instance = XR_NULL_HANDLE;
    running = false;
    selected.store(false);
    state = XR_SESSION_STATE_UNKNOWN;
}
bool CreateCopyPipeline()
{
    ID3D11Device1 *device1 = nullptr;
    ID3D11DeviceContext *immediate = nullptr;
    if (FAILED(device->QueryInterface(__uuidof(ID3D11Device1), reinterpret_cast<void **>(&device1))))
        return false;
    device->GetImmediateContext(&immediate);
    HRESULT hr = immediate->QueryInterface(__uuidof(ID3D11DeviceContext1), reinterpret_cast<void **>(&context));
    immediate->Release();
    if (FAILED(hr))
    {
        device1->Release();
        return false;
    }
    D3D_FEATURE_LEVEL levels[] = {device->GetFeatureLevel()};
    hr =
        device1->CreateDeviceContextState(0, levels, 1, D3D11_SDK_VERSION, __uuidof(ID3D11Device), nullptr, &copyState);
    device1->Release();
    if (FAILED(hr))
        return false;
    const char *vs = "float4 main(uint id:SV_VertexID):SV_Position{float2 p=float2((id<<1)&2,id&2);return "
                     "float4(p*float2(2,-2)+float2(-1,1),0,1);}";
    ID3DBlob *blob = nullptr;
    if (FAILED(D3DCompile(vs, strlen(vs), nullptr, nullptr, nullptr, "main", "vs_4_0", D3DCOMPILE_OPTIMIZATION_LEVEL3,
                          0, &blob, nullptr)))
        return false;
    hr = device->CreateVertexShader(blob->GetBufferPointer(), blob->GetBufferSize(), nullptr, &copyVs);
    blob->Release();
    if (FAILED(hr))
        return false;
    for (int i = 0; i < 6; ++i)
    {
        std::string source = EyeCopySource(i % 2 != 0, i / 2);
        blob = nullptr;
        if (FAILED(D3DCompile(source.data(), source.size(), nullptr, nullptr, nullptr, "main", "ps_4_0",
                              D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &blob, nullptr)))
            return false;
        hr = device->CreatePixelShader(blob->GetBufferPointer(), blob->GetBufferSize(), nullptr, &copyPs[i]);
        blob->Release();
        if (FAILED(hr))
            return false;
    }
    return true;
}
bool MakeAction(XrAction &action, const char *name, XrActionType type)
{
    XrActionCreateInfo info = {XR_TYPE_ACTION_CREATE_INFO};
    strcpy_s(info.actionName, name);
    strcpy_s(info.localizedActionName, name);
    info.actionType = type;
    info.countSubactionPaths = 2;
    info.subactionPaths = handPaths;
    return Check(xrCreateAction(actionSet, &info, &action));
}
bool SuggestBindings(const char *profile, bool frame)
{
    XrPath profilePath = XR_NULL_PATH;
    if (!Check(xrStringToPath(instance, profile, &profilePath))) return false;
    std::vector<XrActionSuggestedBinding> bindings;
    for (int hand = 0; hand < 2; ++hand)
    {
        const char *base = hand == 0 ? "/user/hand/left" : "/user/hand/right";
        const XrAction actions[] = {handPose, stick, stickClick, grip, trigger, confirm, back, gripClick};
        const char *suffixes[] = {"/input/grip/pose", "/input/thumbstick", "/input/thumbstick/click",
            "/input/squeeze/value", "/input/trigger/value",
            hand == 0 ? (frame ? "/input/dpad_down/click" : "/input/x/click") : "/input/a/click",
            hand == 0 ? (frame ? "/input/dpad_up/click" : "/input/y/click") : "/input/b/click",
            "/input/squeeze/click"};
        for (int i = 0; i < (frame ? 8 : 7); ++i)
        {
            char path[128];
            sprintf_s(path, "%s%s", base, suffixes[i]);
            XrPath binding = XR_NULL_PATH;
            if (!Check(xrStringToPath(instance, path, &binding))) return false;
            bindings.push_back({actions[i], binding});
        }
    }
    XrInteractionProfileSuggestedBinding suggest = {XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    suggest.interactionProfile = profilePath;
    suggest.countSuggestedBindings = static_cast<uint32_t>(bindings.size());
    suggest.suggestedBindings = bindings.data();
    return Check(xrSuggestInteractionProfileBindings(instance, &suggest));
}
bool CreateActions()
{
    if (!Check(xrStringToPath(instance, "/user/hand/left", &handPaths[0])) ||
        !Check(xrStringToPath(instance, "/user/hand/right", &handPaths[1]))) return false;
    XrActionSetCreateInfo info = {XR_TYPE_ACTION_SET_CREATE_INFO};
    strcpy_s(info.actionSetName, "qvvr");
    strcpy_s(info.localizedActionSetName, "QVVR");
    if (!Check(xrCreateActionSet(instance, &info, &actionSet)) ||
        !MakeAction(handPose, "hand_pose", XR_ACTION_TYPE_POSE_INPUT) ||
        !MakeAction(stick, "stick", XR_ACTION_TYPE_VECTOR2F_INPUT) ||
        !MakeAction(stickClick, "stick_click", XR_ACTION_TYPE_BOOLEAN_INPUT) ||
        !MakeAction(grip, "grip", XR_ACTION_TYPE_FLOAT_INPUT) ||
        !MakeAction(gripClick, "grip_click", XR_ACTION_TYPE_BOOLEAN_INPUT) ||
        !MakeAction(trigger, "trigger", XR_ACTION_TYPE_FLOAT_INPUT) ||
        !MakeAction(confirm, "confirm", XR_ACTION_TYPE_BOOLEAN_INPUT) ||
        !MakeAction(back, "back", XR_ACTION_TYPE_BOOLEAN_INPUT)) return false;
    if (!SuggestBindings("/interaction_profiles/oculus/touch_controller", false)) return false;
    if (frameControllerProfile && !SuggestBindings("/interaction_profiles/valve/frame_controller_valve", true)) return false;
    XrSessionActionSetsAttachInfo attach = {XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};
    attach.countActionSets = 1;
    attach.actionSets = &actionSet;
    if (!Check(xrAttachSessionActionSets(session, &attach))) return false;
    for (int i = 0; i < 2; ++i)
    {
        XrActionSpaceCreateInfo space = {XR_TYPE_ACTION_SPACE_CREATE_INFO};
        space.action = handPose;
        space.subactionPath = handPaths[i];
        space.poseInActionSpace.orientation.w = 1;
        if (!Check(xrCreateActionSpace(session, &space, &handSpaces[i]))) return false;
    }
    return true;
}
bool Initialize(ID3D11Texture2D *left, float scale)
{
    uint32_t count = 0;
    if (!Check(xrEnumerateInstanceExtensionProperties(nullptr, 0, &count, nullptr)))
        return false;
    std::vector<XrExtensionProperties> extensions(count, {XR_TYPE_EXTENSION_PROPERTIES});
    if (!Check(xrEnumerateInstanceExtensionProperties(nullptr, count, &count, extensions.data())))
        return false;
    bool d3d = false;
    frameControllerProfile = false;
    for (auto &e : extensions)
    {
        if (!strcmp(e.extensionName, XR_KHR_D3D11_ENABLE_EXTENSION_NAME)) d3d = true;
        if (!strcmp(e.extensionName, "XR_VALVE_frame_controller_interaction")) frameControllerProfile = true;
    }
    if (!d3d)
    {
        lastError.store(XR_ERROR_EXTENSION_NOT_PRESENT);
        return false;
    }
    const char *names[] = {XR_KHR_D3D11_ENABLE_EXTENSION_NAME, "XR_VALVE_frame_controller_interaction"};
    XrInstanceCreateInfo create = {XR_TYPE_INSTANCE_CREATE_INFO};
    strcpy_s(create.applicationInfo.applicationName, "QVVR");
    create.applicationInfo.applicationVersion = 1;
    strcpy_s(create.applicationInfo.engineName, "Unity custom QVVR renderer");
    create.applicationInfo.apiVersion = XR_MAKE_VERSION(1, 0, 0);
    create.enabledExtensionCount = frameControllerProfile ? 2 : 1;
    create.enabledExtensionNames = names;
    if (!Check(xrCreateInstance(&create, &instance)))
        return false;
    XrSystemGetInfo get = {XR_TYPE_SYSTEM_GET_INFO};
    get.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    if (!Check(xrGetSystem(instance, &get, &system)))
        return false;
    if (!Check(xrEnumerateEnvironmentBlendModes(instance, system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 0, &count,
                                                nullptr)))
        return false;
    std::vector<XrEnvironmentBlendMode> modes(count);
    if (!Check(xrEnumerateEnvironmentBlendModes(instance, system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, count,
                                                &count, modes.data())))
        return false;
    bool alpha = false;
    for (auto mode : modes)
        if (mode == XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND)
            alpha = true;
    if (!alpha)
    {
        lastError.store(XR_ERROR_ENVIRONMENT_BLEND_MODE_UNSUPPORTED);
        return false;
    }
    PFN_xrGetD3D11GraphicsRequirementsKHR getRequirements = nullptr;
    if (!Check(xrGetInstanceProcAddr(instance, "xrGetD3D11GraphicsRequirementsKHR",
                                     reinterpret_cast<PFN_xrVoidFunction *>(&getRequirements))))
        return false;
    XrGraphicsRequirementsD3D11KHR requirements = {XR_TYPE_GRAPHICS_REQUIREMENTS_D3D11_KHR};
    if (!Check(getRequirements(instance, system, &requirements)))
        return false;
    left->GetDevice(&device);
    IDXGIDevice *dxgi = nullptr;
    IDXGIAdapter *adapter = nullptr;
    DXGI_ADAPTER_DESC desc = {};
    HRESULT hr = device->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void **>(&dxgi));
    if (FAILED(hr))
        return false;
    hr = dxgi->GetAdapter(&adapter);
    dxgi->Release();
    if (FAILED(hr))
        return false;
    hr = adapter->GetDesc(&desc);
    adapter->Release();
    if (FAILED(hr))
        return false;
    if (memcmp(&desc.AdapterLuid, &requirements.adapterLuid, sizeof(LUID)) ||
        device->GetFeatureLevel() < requirements.minFeatureLevel)
    {
        lastError.store(XR_ERROR_GRAPHICS_DEVICE_INVALID);
        return false;
    }
    XrGraphicsBindingD3D11KHR binding = {XR_TYPE_GRAPHICS_BINDING_D3D11_KHR};
    binding.device = device;
    XrSessionCreateInfo sessionCreate = {XR_TYPE_SESSION_CREATE_INFO};
    sessionCreate.next = &binding;
    sessionCreate.systemId = system;
    if (!Check(xrCreateSession(instance, &sessionCreate, &session)))
        return false;
    XrReferenceSpaceCreateInfo spaceCreate = {XR_TYPE_REFERENCE_SPACE_CREATE_INFO};
    spaceCreate.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_STAGE;
    spaceCreate.poseInReferenceSpace.orientation.w = 1;
    XrResult spaceResult = xrCreateReferenceSpace(session, &spaceCreate, &stage);
    // Exclusive XR uses the same base space for head, eyes, hands and layers.
    // LOCAL is safe here: there is no OpenVR Standing space to match anymore.
    if (spaceResult == XR_ERROR_REFERENCE_SPACE_UNSUPPORTED)
    {
        spaceCreate.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_LOCAL;
        spaceResult = xrCreateReferenceSpace(session, &spaceCreate, &stage);
    }
    if (!Check(spaceResult)) return false;
    spaceCreate.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_VIEW;
    if (!Check(xrCreateReferenceSpace(session, &spaceCreate, &viewSpace)) || !CreateActions()) return false;
    if (!Check(xrEnumerateSwapchainFormats(session, 0, &count, nullptr)))
        return false;
    std::vector<int64_t> formats(count);
    if (!Check(xrEnumerateSwapchainFormats(session, count, &count, formats.data())))
        return false;
    int64_t format = 0;
    for (auto f : formats)
        if (f == DXGI_FORMAT_R8G8B8A8_UNORM) format = f;
    for (auto f : formats)
        if (f == DXGI_FORMAT_B8G8R8A8_UNORM)
            format = f;
    for (auto f : formats)
        if (f == DXGI_FORMAT_R8G8B8A8_UNORM_SRGB) format = f;
    for (auto f : formats)
        if (f == DXGI_FORMAT_B8G8R8A8_UNORM_SRGB)
            format = f;
    if (!format)
    {
        lastError.store(XR_ERROR_SWAPCHAIN_FORMAT_UNSUPPORTED);
        return false;
    }
    XrViewConfigurationView recommendations[2] = {{XR_TYPE_VIEW_CONFIGURATION_VIEW}, {XR_TYPE_VIEW_CONFIGURATION_VIEW}};
    if (!Check(xrEnumerateViewConfigurationViews(instance, system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
        2, &count, recommendations)) || count != 2) return false;
    scale = std::isfinite(scale) ? fmaxf(.25f, fminf(1.5f, scale)) : 1.f;
    // Both existing Unity eyes use the same dimensions, bounded by BOTH maxima.
    uint32_t maxWidth = (std::min)(recommendations[0].maxImageRectWidth, recommendations[1].maxImageRectWidth);
    uint32_t maxHeight = (std::min)(recommendations[0].maxImageRectHeight, recommendations[1].maxImageRectHeight);
    uint32_t width = (std::min)(maxWidth, static_cast<uint32_t>(ceilf((std::max)(recommendations[0].recommendedImageRectWidth,
        recommendations[1].recommendedImageRectWidth) * scale)));
    uint32_t height = (std::min)(maxHeight, static_cast<uint32_t>(ceilf((std::max)(recommendations[0].recommendedImageRectHeight,
        recommendations[1].recommendedImageRectHeight) * scale)));
    for (int i = 0; i < 2; ++i)
    {
        auto &eye = eyes[i];
        eye.width = width;
        eye.height = height;
        XrSwapchainCreateInfo swap = {XR_TYPE_SWAPCHAIN_CREATE_INFO};
        swap.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT;
        swap.format = format;
        swap.sampleCount = 1;
        swap.width = eye.width;
        swap.height = eye.height;
        swap.faceCount = swap.arraySize = swap.mipCount = 1;
        if (!Check(xrCreateSwapchain(session, &swap, &eye.swapchain)))
            return false;
        if (!Check(xrEnumerateSwapchainImages(eye.swapchain, 0, &count, nullptr)))
            return false;
        eye.images.resize(count, {XR_TYPE_SWAPCHAIN_IMAGE_D3D11_KHR});
        eye.targets.resize(count, nullptr);
        if (!Check(xrEnumerateSwapchainImages(eye.swapchain, count, &count,
                                              reinterpret_cast<XrSwapchainImageBaseHeader *>(eye.images.data()))))
            return false;
        for (unsigned j = 0; j < count; ++j)
            if (FAILED(device->CreateRenderTargetView(eye.images[j].texture, nullptr, &eye.targets[j])))
                return false;
    }
    if (!CreateCopyPipeline())
        return false;
    selected.store(true);
    status.store(1);
    lastError.store(0);
    return true;
}
vr::HmdMatrix34_t Matrix(const XrPosef &pose)
{
    const auto &q = pose.orientation;
    vr::HmdMatrix34_t result = {};
    result.m[0][0] = 1 - 2 * (q.y * q.y + q.z * q.z);
    result.m[0][1] = 2 * (q.x * q.y - q.z * q.w);
    result.m[0][2] = 2 * (q.x * q.z + q.y * q.w);
    result.m[1][0] = 2 * (q.x * q.y + q.z * q.w);
    result.m[1][1] = 1 - 2 * (q.x * q.x + q.z * q.z);
    result.m[1][2] = 2 * (q.y * q.z - q.x * q.w);
    result.m[2][0] = 2 * (q.x * q.z - q.y * q.w);
    result.m[2][1] = 2 * (q.y * q.z + q.x * q.w);
    result.m[2][2] = 1 - 2 * (q.x * q.x + q.y * q.y);
    result.m[0][3] = pose.position.x;
    result.m[1][3] = pose.position.y;
    result.m[2][3] = pose.position.z;
    return result;
}
bool BoolAction(XrAction action, XrPath path)
{
    XrActionStateGetInfo get = {XR_TYPE_ACTION_STATE_GET_INFO};
    get.action = action;
    get.subactionPath = path;
    XrActionStateBoolean value = {XR_TYPE_ACTION_STATE_BOOLEAN};
    return XR_SUCCEEDED(xrGetActionStateBoolean(session, &get, &value)) && value.isActive && value.currentState;
}
float FloatAction(XrAction action, XrPath path)
{
    XrActionStateGetInfo get = {XR_TYPE_ACTION_STATE_GET_INFO};
    get.action = action;
    get.subactionPath = path;
    XrActionStateFloat value = {XR_TYPE_ACTION_STATE_FLOAT};
    return XR_SUCCEEDED(xrGetActionStateFloat(session, &get, &value)) && value.isActive ? value.currentState : 0.f;
}
void SampleHand(int index, OpenXrHand &hand)
{
    hand = {};
    XrActionStateGetInfo get = {XR_TYPE_ACTION_STATE_GET_INFO};
    get.action = handPose;
    get.subactionPath = handPaths[index];
    XrActionStatePose poseState = {XR_TYPE_ACTION_STATE_POSE};
    XrSpaceLocation location = {XR_TYPE_SPACE_LOCATION};
    constexpr XrSpaceLocationFlags valid = XR_SPACE_LOCATION_ORIENTATION_VALID_BIT | XR_SPACE_LOCATION_POSITION_VALID_BIT;
    bool active = XR_SUCCEEDED(xrGetActionStatePose(session, &get, &poseState)) && poseState.isActive;
    if (active) hand.valid = 2;
    if (active &&
        XR_SUCCEEDED(xrLocateSpace(handSpaces[index], stage, displayTime, &location)) &&
        (location.locationFlags & valid) == valid)
    {
        hand.pose = Matrix(location.pose);
        hand.valid |= 1;
    }
    get.action = stick;
    XrActionStateVector2f axes = {XR_TYPE_ACTION_STATE_VECTOR2F};
    if (XR_SUCCEEDED(xrGetActionStateVector2f(session, &get, &axes)) && axes.isActive)
    {
        hand.stickX = axes.currentState.x;
        hand.stickY = axes.currentState.y;
    }
    hand.grip = FloatAction(grip, handPaths[index]);
    hand.trigger = FloatAction(trigger, handPaths[index]);
    hand.buttons = (BoolAction(confirm, handPaths[index]) ? 1u : 0u) |
        (BoolAction(back, handPaths[index]) ? 2u : 0u) | (BoolAction(stickClick, handPaths[index]) ? 4u : 0u) |
        (BoolAction(gripClick, handPaths[index]) ? 8u : 0u);
}
bool CopyEye(int index, ID3D11Texture2D *source, bool flip)
{
    auto &eye = eyes[index];
    if (sourceTextures[index] != source)
    {
        Release(sources[index]);
        Release(sourceTextures[index]);
        D3D11_TEXTURE2D_DESC desc = {};
        source->GetDesc(&desc);
        D3D11_SHADER_RESOURCE_VIEW_DESC view = {};
        view.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
        view.Texture2D.MipLevels = 1;
        // Read encoded bytes; the copy shader handles Gamma/Linear Unity
        // correctly for linear XR composition and premultiplied alpha.
        view.Format = desc.Format;
        if (view.Format == DXGI_FORMAT_B8G8R8A8_TYPELESS)
            view.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        if (view.Format == DXGI_FORMAT_R8G8B8A8_TYPELESS)
            view.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        sourceDecodeMode[index] =
            (view.Format == DXGI_FORMAT_B8G8R8A8_UNORM_SRGB || view.Format == DXGI_FORMAT_R8G8B8A8_UNORM_SRGB)
                ? 0
                : colorDecodeMode;
        if (FAILED(device->CreateShaderResourceView(source, &view, &sources[index])))
        {
            lastError.store(XR_ERROR_RUNTIME_FAILURE);
            return false;
        }
        source->AddRef();
        sourceTextures[index] = source;
    }
    XrSwapchainImageAcquireInfo acquire = {XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
    if (!Check(xrAcquireSwapchainImage(eye.swapchain, &acquire, &eye.index)))
        return false;
    eye.acquired = true;
    XrSwapchainImageWaitInfo wait = {XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};
    wait.timeout = XR_INFINITE_DURATION;
    if (!Check(xrWaitSwapchainImage(eye.swapchain, &wait)))
        return false;
    eye.waited = true;
    ID3DDeviceContextState *unity = nullptr;
    context->SwapDeviceContextState(copyState, &unity);
    context->OMSetRenderTargets(1, &eye.targets[eye.index], nullptr);
    D3D11_VIEWPORT viewport = {0, 0, static_cast<float>(eye.width), static_cast<float>(eye.height), 0, 1};
    context->RSSetViewports(1, &viewport);
    context->IASetInputLayout(nullptr);
    context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context->VSSetShader(copyVs, nullptr, 0);
    context->PSSetShader(copyPs[sourceDecodeMode[index] * 2 + (flip ? 1 : 0)], nullptr, 0);
    context->PSSetShaderResources(0, 1, &sources[index]);
    context->Draw(3, 0);
    context->Flush();
    context->SwapDeviceContextState(unity, nullptr);
    unity->Release();
    XrSwapchainImageReleaseInfo release = {XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
    if (!Check(xrReleaseSwapchainImage(eye.swapchain, &release)))
        return false;
    eye.acquired = eye.waited = false;
    return true;
}
} // namespace
void ConfigureOpenXr(bool value)
{
    requested.store(value);
}
void SetOpenXrColorSpace(bool gammaGame, bool sourceSrgb)
{
    colorDecodeMode = gammaGame ? 2 : sourceSrgb ? 1 : 0;
}
bool OpenXrSelected()
{
    return selected.load();
}
bool OpenXrRequested() { return requested.load(); }
bool InitializeExclusiveOpenXr(ID3D11Texture2D *bootstrap, float scale, uint32_t &width, uint32_t &height)
{
    width = height = 0;
    if (!requested.load() || !bootstrap || selected.load()) return false;
    lastError.store(0);
    if (!Initialize(bootstrap, scale))
    {
        if (lastError.load() == 0) lastError.store(XR_ERROR_RUNTIME_FAILURE);
        Destroy();
        status.store(-1);
        return false;
    }
    width = eyes[0].width;
    height = eyes[0].height;
    return true;
}
int OpenXrStatus()
{
    return status.load();
}
int OpenXrError()
{
    return lastError.load();
}
bool BeginOpenXrFrame(ID3D11Texture2D *left)
{
    // Graphics thread: all XR timing/poses were latched before Unity Update.
    // No late WaitFrame/pose update can invalidate the already queued cameras.
    return left && selected.load() && frameBegun.load(std::memory_order_acquire);
}
void CancelOpenXrFrame()
{
    if (!frameBegun.load()) return;
    XrFrameEndInfo end = {XR_TYPE_FRAME_END_INFO};
    end.displayTime = displayTime;
    end.environmentBlendMode = XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND;
    if (!Check(xrEndFrame(session, &end)))
    {
        frameBegun.store(false);
        Destroy();
        status.store(-4);
        return;
    }
    frameBegun.store(false, std::memory_order_release);
}
int PrepareOpenXrFrame(OpenXrFrame &snapshot)
{
    // Back pressure is nonblocking: skip this Unity frame if its predecessor
    // is still queued/executing. Never call BeginFrame over an unfinished frame.
    if (!requested.load() || !selected.load()) return 0;
    if (frameBegun.load(std::memory_order_acquire)) return 2;
    snapshot = {};
    XrEventDataBuffer event = {XR_TYPE_EVENT_DATA_BUFFER};
    while (xrPollEvent(instance, &event) == XR_SUCCESS)
    {
        if (event.type == XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED)
        {
            auto changed = reinterpret_cast<XrEventDataSessionStateChanged *>(&event);
            if (changed->session != session) { event = {XR_TYPE_EVENT_DATA_BUFFER}; continue; }
            state = changed->state;
            if (state == XR_SESSION_STATE_READY && !running)
            {
                XrSessionBeginInfo begin = {XR_TYPE_SESSION_BEGIN_INFO};
                begin.primaryViewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
                if (!Check(xrBeginSession(session, &begin)))
                {
                    Destroy();
                    status.store(-2);
                    return false;
                }
                running = true;
            }
            if (state == XR_SESSION_STATE_STOPPING && running)
            {
                if (!Check(xrEndSession(session)))
                {
                    Destroy();
                    status.store(-3);
                    return false;
                }
                running = false;
            }
            if (state == XR_SESSION_STATE_EXITING || state == XR_SESSION_STATE_LOSS_PENDING)
            {
                Destroy();
                status.store(-3);
                return false;
            }
            status.store(state == XR_SESSION_STATE_FOCUSED ? 3 : state == XR_SESSION_STATE_VISIBLE ? 2 : 1);
        }
        else if (event.type == XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING)
        {
            Destroy();
            status.store(-3);
            return false;
        }
        event = {XR_TYPE_EVENT_DATA_BUFFER};
    }
    if (!running)
        return false;
    XrFrameWaitInfo wait = {XR_TYPE_FRAME_WAIT_INFO};
    XrFrameState frame = {XR_TYPE_FRAME_STATE};
    if (!Check(xrWaitFrame(session, &wait, &frame)))
    {
        Destroy();
        status.store(-4);
        return false;
    }
    XrFrameBeginInfo begin = {XR_TYPE_FRAME_BEGIN_INFO};
    if (!Check(xrBeginFrame(session, &begin)))
    {
        Destroy();
        status.store(-4);
        return false;
    }
    displayTime = frame.predictedDisplayTime;
    shouldRender = frame.shouldRender == XR_TRUE;
    frameBegun.store(true);
    if (!shouldRender) { CancelOpenXrFrame(); return false; }
    XrViewLocateInfo locate = {XR_TYPE_VIEW_LOCATE_INFO};
    locate.viewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
    locate.displayTime = displayTime;
    locate.space = stage;
    XrViewState viewState = {XR_TYPE_VIEW_STATE};
    uint32_t count = 0;
    XrSpaceLocation head = {XR_TYPE_SPACE_LOCATION};
    if (!Check(xrLocateViews(session, &locate, &viewState, 2, &count, locatedViews)) || count != 2 ||
        !Check(xrLocateSpace(viewSpace, stage, displayTime, &head)))
    {
        Destroy();
        status.store(-4);
        return false;
    }
    constexpr XrViewStateFlags validViews = XR_VIEW_STATE_ORIENTATION_VALID_BIT | XR_VIEW_STATE_POSITION_VALID_BIT;
    constexpr XrSpaceLocationFlags validHead = XR_SPACE_LOCATION_ORIENTATION_VALID_BIT | XR_SPACE_LOCATION_POSITION_VALID_BIT;
    if ((viewState.viewStateFlags & validViews) != validViews || (head.locationFlags & validHead) != validHead)
    {
        CancelOpenXrFrame();
        return false;
    }
    XrActiveActionSet active = {actionSet, XR_NULL_PATH};
    XrActionsSyncInfo sync = {XR_TYPE_ACTIONS_SYNC_INFO};
    sync.countActiveActionSets = 1;
    sync.activeActionSets = &active;
    if (!Check(xrSyncActions(session, &sync)))
    {
        Destroy();
        status.store(-4);
        return false;
    }
    snapshot.head = Matrix(head.pose);
    snapshot.leftEye = Matrix(locatedViews[0].pose);
    snapshot.rightEye = Matrix(locatedViews[1].pose);
    const auto &l = locatedViews[0].fov;
    const auto &r = locatedViews[1].fov;
    snapshot.leftFov = {l.angleLeft, l.angleRight, l.angleUp, l.angleDown};
    snapshot.rightFov = {r.angleLeft, r.angleRight, r.angleUp, r.angleDown};
    SampleHand(0, snapshot.leftHand);
    SampleHand(1, snapshot.rightHand);
    return true;
}
bool SubmitOpenXrFrame(ID3D11Texture2D *left, ID3D11Texture2D *right, const vr::HmdMatrix34_t &, bool flip)
{
    if (!frameBegun)
        return false;
    bool copied = shouldRender && CopyEye(0, left, flip) && CopyEye(1, right, flip);
    XrCompositionLayerProjectionView views[2] = {{XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW},
                                                 {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW}};
    for (int i = 0; i < 2; ++i)
    {
        views[i].pose = locatedViews[i].pose;
        views[i].fov = locatedViews[i].fov;
        views[i].subImage.swapchain = eyes[i].swapchain;
        views[i].subImage.imageRect.extent = {static_cast<int32_t>(eyes[i].width),
                                              static_cast<int32_t>(eyes[i].height)};
    }
    XrCompositionLayerProjection projection = {XR_TYPE_COMPOSITION_LAYER_PROJECTION};
    projection.space = stage;
    projection.viewCount = 2;
    projection.views = views;
    projection.layerFlags = XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
    const XrCompositionLayerBaseHeader *layers[] = {
        reinterpret_cast<const XrCompositionLayerBaseHeader *>(&projection)};
    XrFrameEndInfo end = {XR_TYPE_FRAME_END_INFO};
    end.displayTime = displayTime;
    end.environmentBlendMode = XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND;
    end.layerCount = copied ? 1 : 0;
    end.layers = copied ? layers : nullptr;
    bool ended = Check(xrEndFrame(session, &end));
    // Release the snapshot only AFTER the runtime consumes these exact views.
    frameBegun.store(false, std::memory_order_release);
    if (!ended || (shouldRender && !copied))
    {
        Destroy();
        status.store(-4);
        return false;
    }
    return true;
}
void ShutdownOpenXr()
{
    Destroy();
    requested.store(false);
    status.store(0);
    lastError.store(0);
}
} // namespace qvvr
