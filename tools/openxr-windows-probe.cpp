#include <cstdio>
#include <cstring>
#include <openxr/openxr.h>
#include <vector>
#include <windows.h>
int main()
{
    FILE *report = nullptr;
    freopen_s(&report, "Z:\\tmp\\qvvr-openxr-capabilities.txt", "w", stdout);
    setvbuf(stdout, nullptr, _IONBF, 0);
    uint32_t n = 0;
    XrResult result = xrEnumerateInstanceExtensionProperties(nullptr, 0, &n, nullptr);
    printf("xrEnumerateInstanceExtensionProperties=%d count=%u\n", result, n);
    if (XR_FAILED(result))
        return 1;
    std::vector<XrExtensionProperties> extensions(n, {XR_TYPE_EXTENSION_PROPERTIES});
    xrEnumerateInstanceExtensionProperties(nullptr, n, &n, extensions.data());
    bool d3d = false;
    for (auto &e : extensions)
        if (!strcmp(e.extensionName, "XR_KHR_D3D11_enable"))
            d3d = true;
    printf("D3D11 extension=%d\n", d3d);
    const char *names[] = {"XR_KHR_D3D11_enable"};
    XrInstanceCreateInfo create = {XR_TYPE_INSTANCE_CREATE_INFO};
    strcpy_s(create.applicationInfo.applicationName, "QVVR capability probe (no session)");
    create.applicationInfo.apiVersion = XR_MAKE_VERSION(1, 0, 0);
    create.enabledExtensionCount = d3d ? 1 : 0;
    create.enabledExtensionNames = names;
    XrInstance instance = XR_NULL_HANDLE;
    result = xrCreateInstance(&create, &instance);
    printf("xrCreateInstance=%d\n", result);
    if (XR_FAILED(result))
        return 1;
    XrInstanceProperties properties = {XR_TYPE_INSTANCE_PROPERTIES};
    xrGetInstanceProperties(instance, &properties);
    printf("Runtime=%s\n", properties.runtimeName);
    XrSystemGetInfo get = {XR_TYPE_SYSTEM_GET_INFO};
    get.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    XrSystemId system = 0;
    result = xrGetSystem(instance, &get, &system);
    printf("xrGetSystem=%d\n", result);
    if (XR_SUCCEEDED(result))
    {
        xrEnumerateEnvironmentBlendModes(instance, system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 0, &n, nullptr);
        std::vector<XrEnvironmentBlendMode> modes(n);
        result = xrEnumerateEnvironmentBlendModes(instance, system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, n, &n,
                                                  modes.data());
        printf("xrEnumerateEnvironmentBlendModes=%d:", result);
        for (auto mode : modes)
            printf(" %d", mode);
        puts(" (1=OPAQUE,3=ALPHA_BLEND)");
    }
    xrDestroyInstance(instance);
    return XR_FAILED(result) ? 1 : 0;
}
