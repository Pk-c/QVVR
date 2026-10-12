"""Read OpenXR capabilities only: no session, swapchain, frame or camera access.

Linux ARM64 Steam Frame usage:
XR_RUNTIME_JSON=/opt/steamvr/steamxr_linuxarm64.json python3 probe-openxr.py
ABI subset follows Khronos OpenXR-SDK/include/openxr/openxr.h (OpenXR 1.0).
"""
import ctypes as c
import json
import os


class Extension(c.Structure):
    _fields_ = [("type", c.c_int32), ("next", c.c_void_p),
                ("name", c.c_char * 128), ("version", c.c_uint32)]


class Application(c.Structure):
    _fields_ = [("name", c.c_char * 128), ("version", c.c_uint32),
                ("engine", c.c_char * 128), ("engine_version", c.c_uint32),
                ("api_version", c.c_uint64)]


class InstanceInfo(c.Structure):
    _fields_ = [("type", c.c_int32), ("next", c.c_void_p), ("flags", c.c_uint64),
                ("app", Application), ("layer_count", c.c_uint32),
                ("layers", c.POINTER(c.c_char_p)), ("extension_count", c.c_uint32),
                ("extensions", c.POINTER(c.c_char_p))]


class SystemInfo(c.Structure):
    _fields_ = [("type", c.c_int32), ("next", c.c_void_p), ("form_factor", c.c_int32)]


def checked(result, operation):
    if result < 0:
        raise RuntimeError(operation + " returned XrResult " + str(result))


loader = c.CDLL("/opt/steamvr/bin/linuxarm64/libopenxr_loader.so")
loader.xrEnumerateInstanceExtensionProperties.argtypes = [c.c_char_p, c.c_uint32,
    c.POINTER(c.c_uint32), c.POINTER(Extension)]
loader.xrCreateInstance.argtypes = [c.POINTER(InstanceInfo), c.POINTER(c.c_void_p)]
loader.xrDestroyInstance.argtypes = [c.c_void_p]
loader.xrGetSystem.argtypes = [c.c_void_p, c.POINTER(SystemInfo), c.POINTER(c.c_uint64)]
loader.xrEnumerateEnvironmentBlendModes.argtypes = [c.c_void_p, c.c_uint64,
    c.c_int32, c.c_uint32, c.POINTER(c.c_uint32), c.POINTER(c.c_int32)]

count = c.c_uint32()
checked(loader.xrEnumerateInstanceExtensionProperties(None, 0, c.byref(count), None), "extensions/count")
extensions = (Extension * count.value)()
for extension in extensions:
    extension.type = 2
checked(loader.xrEnumerateInstanceExtensionProperties(None, count, c.byref(count), extensions), "extensions/list")
report = {"runtime_manifest": os.environ.get("XR_RUNTIME_JSON"),
          "session_created": False,
          "extensions": [extension.name.decode() for extension in extensions]}
info = InstanceInfo()
info.type = 3
info.app.name = b"QVVR capability probe"
info.app.version = 1
info.app.engine = b"QVVR diagnostics"
info.app.engine_version = 1
info.app.api_version = 1 << 48
instance = c.c_void_p()
checked(loader.xrCreateInstance(c.byref(info), c.byref(instance)), "xrCreateInstance")
try:
    system_info = SystemInfo(4, None, 1)
    system = c.c_uint64()
    checked(loader.xrGetSystem(instance, c.byref(system_info), c.byref(system)), "xrGetSystem")
    count = c.c_uint32()
    checked(loader.xrEnumerateEnvironmentBlendModes(instance, system, 2, 0, c.byref(count), None), "blend/count")
    modes = (c.c_int32 * count.value)()
    checked(loader.xrEnumerateEnvironmentBlendModes(instance, system, 2, count, c.byref(count), modes), "blend/list")
    names = {1: "OPAQUE", 2: "ADDITIVE", 3: "ALPHA_BLEND"}
    report["stereo_environment_blend_modes"] = [names.get(mode, str(mode)) for mode in modes]
    report["passthrough_extensions"] = [name for name in report["extensions"] if "passthrough" in name.lower()]
    print(json.dumps(report, indent=2))
finally:
    checked(loader.xrDestroyInstance(instance), "xrDestroyInstance")
