$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pluginDirectory = Join-Path $root 'build\release\QVVR-v0.1.0\BepInEx\plugins\QVVR'
if (-not [Environment]::Is64BitProcess) { throw 'Run this smoke test in x64 PowerShell.' }

if (-not ('QVVRNativeLoadTest' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class QVVRNativeLoadTest {
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int InstallShaderClipDelegate(IntPtr texture);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)]
    public static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll")]
    public static extern bool FreeLibrary(IntPtr module);
    public static int CheckColdBootstrap(IntPtr module) {
        IntPtr function = GetProcAddress(module, "QVVR_InstallShaderClip");
        if (function == IntPtr.Zero) throw new EntryPointNotFoundException("QVVR_InstallShaderClip");
        var install = (InstallShaderClipDelegate)Marshal.GetDelegateForFunctionPointer(
            function, typeof(InstallShaderClipDelegate));
        return install(IntPtr.Zero); // Defined no-op: no device, hook or session.
    }
}
'@
}

# Resolve the packaged modules exactly as the managed bootstrap does. This
# loads DLLs and checks exports/null-texture bootstrap: no VR init or GPU access.
$modules = [Collections.Generic.List[IntPtr]]::new()
try {
    foreach ($name in @('openvr_api.dll', 'openxr_loader.dll', 'QVVR.Native.dll')) {
        $path = Join-Path $pluginDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing packaged native dependency: $path"
        }
        $module = [QVVRNativeLoadTest]::LoadLibraryW($path)
        if ($module -eq [IntPtr]::Zero) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Packaged DLL failed to load: $name (Win32 $errorCode)"
        }
        $modules.Add($module)
    }
    foreach ($export in @('QVVR_GetRenderEventFunc', 'QVVR_InstallShaderClip', 'QVVR_ConfigureOpenXr', 'QVVR_InitializeExclusiveOpenXr', 'QVVR_PrepareOpenXrFrame', 'QVVR_CancelOpenXrFrame', 'QVVR_GetClipBindingStats', 'QVVR_WriteClipDiagnostic', 'QVVR_SetCylinderCapOptions', 'QVVR_RegisterCapMesh', 'QVVR_ClearCapMeshes', 'QVVR_GetCapStats')) {
        if ([QVVRNativeLoadTest]::GetProcAddress($modules[2], $export) -eq [IntPtr]::Zero) {
            throw "Missing native bridge export: $export"
        }
    }
    if ([QVVRNativeLoadTest]::CheckColdBootstrap($modules[2]) -ne 0) {
        throw 'Null-texture bootstrap must return false without touching the GPU.'
    }
    if ([QVVRNativeLoadTest]::GetProcAddress($modules[2], 'QVVR_SetRenderPoseAndMode') -eq [IntPtr]::Zero) {
        throw 'Missing frame-latched opaque selection mode export.'
    }
    foreach ($export in @('QVVR_RegisterCapMeshBounds','QVVR_SetCapCullVolume','QVVR_SetDetailedGpuTiming','QVVR_GetGpuPhaseTime','QVVR_GetCapCullStats')) {
        if ([QVVRNativeLoadTest]::GetProcAddress($modules[2], $export) -eq [IntPtr]::Zero) { throw "Missing performance export: $export" }
    }
    $bootstrapSource = Get-Content -LiteralPath (Join-Path $root 'src\QVVR\OpenVrManager.cs') -Raw
    if ($bootstrapSource -match 'extern\s+int\s+QVVR_InstallShaderClip') {
        throw 'Early shader-hook bootstrap must not eagerly bind a Mono P/Invoke before loading the DLL.'
    }
    Write-Host 'Packaged native load passed: OpenVR, OpenXR loader, native bridge and required exports. No VR session started.'
} finally {
    for ($index = $modules.Count - 1; $index -ge 0; $index--) {
        [void][QVVRNativeLoadTest]::FreeLibrary($modules[$index])
    }
}
