using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using BepInEx;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using Valve.VR;

namespace QVVR
{
    internal static class NativeBridge
    {
        internal const int SubmitEventId = 0x51565652;
        internal const int BeginFrameEventId = 0x51565651;
        internal const int PoseSlotCount = 64;
        internal const int ClipEventBase = 0x51566000;
        internal const int EndClipEvent = 0x51566200;
        internal const int CapCompositeEvent = 0x51566201;
        internal const int ShutdownEvent = 0x51566300;
        internal const int ProfileEventBase = 0x51566400;
        internal static bool ShaderClipReady;

        [StructLayout(LayoutKind.Sequential)]
        internal struct ClipParameters
        {
            internal Matrix4x4 ScreenToCylinder;
            internal Vector4 Limits;
        }
        [StructLayout(LayoutKind.Sequential)]
        internal struct CapMeshBounds { internal Vector3 Minimum, Maximum; }
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_RegisterCapMeshBounds(IntPtr indexBuffer, ref CapMeshBounds bounds);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_SetCapCullVolume(int slot, int eye, float x, float y, float z, float radius, float halfHeight);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_SetCapSkipMeshes(int slot, IntPtr buffers, int count);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_SetDetailedGpuTiming(int enabled);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern double QVVR_GetGpuPhaseTime(int phase);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_GetCapCullStats(ref uint bounded, ref uint skipped);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_ReadXrPacing(ref OpenXrPacing snapshot);

        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_SetClipTargets(IntPtr left, IntPtr right);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_SetClipParameters(int slot, int eye, ref ClipParameters parameters);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_SetCylinderCapOptions(int slot, int eye, int enabled, int reversedZ, int transparent);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_RegisterCapMesh(IntPtr indexBuffer);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_ClearCapMeshes();
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_GetCapStats(ref uint available, ref uint registered, ref uint replayed, ref uint composed);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_ConfigureOpenXr(int enabled);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int QVVR_InitializeExclusiveOpenXr(IntPtr texture, float scale, ref uint width, ref uint height);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int QVVR_PrepareOpenXrFrame(ref OpenXrFrame frame);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_CancelOpenXrFrame();
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_SetEyeColorSpace(int gammaGame, int sourceSrgb);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int QVVR_GetOpenXrStatus(ref int error);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_GetClipStats(ref uint patched, ref uint rejected, ref uint unknown, ref uint depthOnly);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_GetClipBindingStats(ref uint materialBindings, ref uint otherContextBindings);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        internal static extern int QVVR_WriteClipDiagnostic(string path);
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern double QVVR_GetGpuTime();
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_RequestShutdown();
        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int QVVR_IsShutdownComplete();

        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int QVVR_SetRenderPoseAndMode(int slot, ref HmdMatrix34_t pose, int opaqueScene);

        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr QVVR_GetRenderEventFunc();

        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_SetEyeTextures(IntPtr left, IntPtr right);

        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_SetFlipEyeTextureY(int enabled);

        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_ClearEyeTextures();

        [DllImport("QVVR.Native", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void QVVR_GetSubmitState(
            ref ulong frames,
            ref int leftResult,
            ref int rightResult);
    }

    internal sealed class OpenVrManager : MonoBehaviour
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryW(string path);

        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)]
        private static extern IntPtr GetProcAddress(IntPtr module, string name);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int InstallShaderClipDelegate(IntPtr texture);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void ConfigureDiagnosticsDelegate(int enabled);

        private Plugin plugin;
        private OpenVrRenderer renderer;
        private IntPtr openVrModule;
        private IntPtr openXrLoaderModule;
        private IntPtr bridgeModule;
        private float nextInitAttempt;
        private string lastStatus;
        private Thread initThread;
        private volatile int initState;
        private CVRSystem initializedSystem;
        private CVRCompositor initializedCompositor;
        private EVRInitError initializationError;
        private Exception initializationException;
        private bool nativeShutdownPending;
        private bool openXrFailedForLaunch;
        private volatile bool openVrClientActive;

        internal void Initialize(Plugin owner)
        {
            plugin = owner;
            // Install before the first game scene submits shaders to D3D11.
            // Only transient mod-owned storage is touched; no game asset edits.
            if (SystemInfo.graphicsDeviceType == GraphicsDeviceType.Direct3D11 && EnsureNativeLibraries())
            {
                RenderTexture bootstrap = new RenderTexture(16, 16, 0, RenderTextureFormat.ARGB32);
                try
                {
                    bootstrap.Create();
                    NativeBridge.ShaderClipReady = InstallCylinderHook(bootstrap.GetNativeTexturePtr());
                    Plugin.Log.LogInfo("QVVR early GPU cylinder hook installed=" + NativeBridge.ShaderClipReady);
                }
                catch (Exception exception) { Plugin.Log.LogWarning("Cylinder GPU hook unavailable: " + exception); }
                finally { bootstrap.Release(); Destroy(bootstrap); }
            }
            StartCoroutine(RuntimeLoop());
        }

        private bool InstallCylinderHook(IntPtr texture)
        {
            // Mono may resolve P/Invokes while compiling Initialize, before its
            // EnsureNativeLibraries call executes. Resolve this startup-only call
            // from the successfully loaded handle instead of caching a failed bind.
            IntPtr configureAddress = GetProcAddress(bridgeModule, "QVVR_ConfigureDiagnostics");
            if (configureAddress == IntPtr.Zero) throw new EntryPointNotFoundException("QVVR_ConfigureDiagnostics");
            ConfigureDiagnosticsDelegate configure = (ConfigureDiagnosticsDelegate)Marshal.GetDelegateForFunctionPointer(
                configureAddress, typeof(ConfigureDiagnosticsDelegate));
            configure(plugin.DiagnosticsEnabled.Value ? 1 : 0);
            IntPtr function = GetProcAddress(bridgeModule, "QVVR_InstallShaderClip");
            if (function == IntPtr.Zero)
                throw new EntryPointNotFoundException("QVVR_InstallShaderClip in loaded QVVR.Native.dll");
            InstallShaderClipDelegate install = (InstallShaderClipDelegate)Marshal.GetDelegateForFunctionPointer(
                function, typeof(InstallShaderClipDelegate));
            return install(texture) != 0;
        }

        internal void Recenter()
        {
            if (renderer == null)
            {
                Plugin.Log.LogInfo("Recenter queued until OpenVR becomes active.");
                return;
            }
            renderer.Recenter();
        }

        private IEnumerator RuntimeLoop()
        {
            yield return null;
            SetStatus("Render-thread OpenVR bootstrap started at game launch.");

            while (true)
            {
                // Graphics-thread XR cleanup must finish before OpenVR tracking
                // is shut down or another renderer can begin initialization.
                if (nativeShutdownPending)
                {
                    if (NativeBridge.QVVR_IsShutdownComplete() == 0) { yield return null; continue; }
                    nativeShutdownPending = false;
                    ShutdownOpenVrClient();
                    ResetInitialization();
                }
                if (!plugin.VrEnabled.Value)
                {
                    ShutdownRenderer();
                    SetStatus("VR disabled; original desktop camera restored.");
                    yield return new WaitForSecondsRealtime(1f);
                    continue;
                }

                if (renderer != null)
                {
                    if (renderer.NeedsOpenVrSceneFallback)
                    {
                        openXrFailedForLaunch = true;
                        ShutdownRenderer();
                        SetStatus("OpenXR unavailable/lost; switching the existing running game back to the OpenVR scene renderer.");
                        continue;
                    }
                    Camera candidate = renderer.LevelIntroCamera != null ? renderer.LevelIntroCamera : CameraSelector.FindBestCamera();
                    if (candidate != null && renderer.SourceCamera != candidate)
                        renderer.SetSourceCamera(candidate);
                    yield return new WaitForSecondsRealtime(1f);
                    continue;
                }

                if (initState == 1)
                {
                    yield return null;
                    continue;
                }

                if (initState == 3)
                {
                    string detail = initializationException != null
                        ? initializationException.ToString()
                        : initializationError == EVRInitError.None
                            ? "compositor unavailable"
                            : OpenVR.GetStringForHmdError(initializationError);
                    SetStatus("Waiting for SteamVR: " + initializationError + " (" + detail + ").");
                    ShutdownOpenVrClient();
                    ResetInitialization();
                    yield return new WaitForSecondsRealtime(2f);
                    continue;
                }

                if (initState == 2)
                {
                    CVRSystem system = initializedSystem;
                    CVRCompositor compositor = initializedCompositor;
                    ResetInitialization();

                    Camera source = CameraSelector.FindBestCamera();
                    if (source == null)
                    {
                        SetStatus("OpenVR active; waiting for the QV camera.");
                        ShutdownOpenVrClient();
                        yield return new WaitForSecondsRealtime(1f);
                        continue;
                    }

                    GameObject host = new GameObject("QVVR_OpenVR");
                    host.hideFlags = HideFlags.HideAndDontSave;
                    host.transform.SetParent(transform, false);
                    OpenVrRenderer candidateRenderer = host.AddComponent<OpenVrRenderer>();
                    try
                    {
                        Plugin.Log.LogInfo("OpenVR initialization completed; creating GPU targets and panels.");
                        candidateRenderer.Initialize(plugin, system, compositor, source, false);
                        renderer = candidateRenderer;
                        SetStatus("Render-thread OpenVR compositor active from startup.");
                    }
                    catch (Exception exception)
                    {
                        Plugin.Log.LogError("QVVR renderer setup failed; restoring flat mode: " + exception);
                        candidateRenderer.ReleaseResources();
                        Destroy(host);
                        nativeShutdownPending = true;
                        nextInitAttempt = Time.unscaledTime + 5f;
                    }
                    continue;
                }

                if (Time.unscaledTime < nextInitAttempt)
                {
                    yield return null;
                    continue;
                }
                nextInitAttempt = Time.unscaledTime + 5f;

                if (!EnsureNativeLibraries())
                {
                    SetStatus("QVVR native libraries unavailable; desktop mode remains active.");
                    yield return new WaitForSecondsRealtime(2f);
                    continue;
                }

                if (SystemInfo.graphicsDeviceType != GraphicsDeviceType.Direct3D11)
                {
                    SetStatus("QVVR requires D3D11; current renderer is " + SystemInfo.graphicsDeviceType + ".");
                    yield return new WaitForSecondsRealtime(5f);
                    continue;
                }

                if (!openXrFailedForLaunch && plugin.PassthroughEnabled.Value && NativeBridge.ShaderClipReady)
                {
                    Camera source = CameraSelector.FindBestCamera();
                    if (source == null) { yield return null; continue; }
                    GameObject host = new GameObject("QVVR_OpenXR");
                    host.hideFlags = HideFlags.HideAndDontSave;
                    host.transform.SetParent(transform, false);
                    OpenVrRenderer candidateRenderer = host.AddComponent<OpenVrRenderer>();
                    try
                    {
                        candidateRenderer.Initialize(plugin, null, null, source, true);
                        renderer = candidateRenderer;
                        SetStatus("Exclusive OpenXR selected: XR tracking, controllers and ALPHA_BLEND; no OpenVR client initialized.");
                    }
                    catch (Exception exception)
                    {
                        openXrFailedForLaunch = true;
                        Plugin.Log.LogWarning("Exclusive OpenXR setup failed; falling back to the validated OpenVR diorama: " + exception);
                        candidateRenderer.ReleaseResources();
                        Destroy(host);
                        nativeShutdownPending = true;
                    }
                    continue;
                }
                BeginOpenVrInitialization();
                SetStatus("OpenVR initialization running asynchronously; flat rendering remains active.");
            }
        }

        private void BeginOpenVrInitialization()
        {
            initializationError = EVRInitError.None;
            initializationException = null;
            initializedSystem = null;
            initializedCompositor = null;
            initState = 1;

            initThread = new Thread(InitializeOpenVrWorker);
            initThread.Name = "QVVR OpenVR initialization";
            initThread.IsBackground = true;
            initThread.Start();
        }

        private void InitializeOpenVrWorker()
        {
            EVRInitError error = EVRInitError.None;
            CVRSystem system = null;
            CVRCompositor compositor = null;
            Exception exception = null;

            try
            {
                // Only called when passthrough is off, or AFTER XR destruction.
                // Never initialize an OpenVR Background/tracking client for XR.
                openVrClientActive = true;
                system = OpenVR.Init(ref error, EVRApplicationType.VRApplication_Scene);
                if (error == EVRInitError.None && system != null)
                {
                    compositor = OpenVR.Compositor;
                }
            }
            catch (Exception caught)
            {
                exception = caught;
            }

            initializationError = error;
            initializationException = exception;
            initializedSystem = system;
            initializedCompositor = compositor;
            initState = exception == null && error == EVRInitError.None &&
                system != null && compositor != null ? 2 : 3;
        }

        private void ResetInitialization()
        {
            initThread = null;
            initializedSystem = null;
            initializedCompositor = null;
            initializationException = null;
            initializationError = EVRInitError.None;
            initState = 0;
        }
        private void ShutdownOpenVrClient()
        {
            if (!openVrClientActive) return;
            try { OpenVR.Shutdown(); } catch { }
            openVrClientActive = false;
        }

        private bool EnsureNativeLibraries()
        {
            string directory = Path.Combine(Paths.PluginPath, "QVVR");
            if (openVrModule == IntPtr.Zero)
                openVrModule = LoadLibrary(Path.Combine(directory, "openvr_api.dll"));
            if (openVrModule == IntPtr.Zero)
                return false;

            // The SDK .lib is an import library, not a static loader. Load the
            // packaged DLL by absolute path before resolving the bridge's imports;
            // LoadLibraryW does not search this private plugin directory by default.
            if (openXrLoaderModule == IntPtr.Zero)
                openXrLoaderModule = LoadLibrary(Path.Combine(directory, "openxr_loader.dll"));
            if (openXrLoaderModule == IntPtr.Zero)
                return false;

            if (bridgeModule == IntPtr.Zero)
                bridgeModule = LoadLibrary(Path.Combine(directory, "QVVR.Native.dll"));
            return bridgeModule != IntPtr.Zero;
        }

        private static IntPtr LoadLibrary(string path)
        {
            if (!File.Exists(path))
            {
                Plugin.Log.LogError("Missing native library: " + path);
                return IntPtr.Zero;
            }

            IntPtr module = LoadLibraryW(path);
            if (module == IntPtr.Zero)
                Plugin.Log.LogError("LoadLibrary failed for " + path + ": Win32 " + Marshal.GetLastWin32Error());
            else
                Plugin.Log.LogInfo("Loaded native library: " + path);
            return module;
        }

        private void SetStatus(string status)
        {
            if (string.Equals(lastStatus, status, StringComparison.Ordinal))
                return;
            lastStatus = status;
            Plugin.Log.LogInfo(status);
        }

        private void ShutdownRenderer()
        {
            if (renderer != null)
            {
                renderer.ReleaseResources();
                Destroy(renderer.gameObject);
                renderer = null;
                nativeShutdownPending = true;
            }
            if (initState != 1 && !nativeShutdownPending)
            {
                ShutdownOpenVrClient();
                ResetInitialization();
            }
        }

        private void OnDestroy()
        {
            StopAllCoroutines();
            ShutdownRenderer();
        }
    }

    // Unity normally renders after every LateUpdate. Manual stereo rendering
    // must also wait for QV's default-order DynamicBone/character simulation.
    [DefaultExecutionOrder(10000)]
    internal sealed class OpenVrRenderer : MonoBehaviour
    {
        private static readonly string[] PanelShaderCandidates =
        {
            "Sprites/Default",
            "UI/Default",
            "Unlit/Transparent",
            "UI/Unlit/Transparent",
            "UI/Default-SoftMask"
        };

        private const int PanelLayer = 31;
        private const int PanelMask = 1 << PanelLayer;
        private const int UiCaptureLayer = 30;
        private const int UiCaptureMask = 1 << UiCaptureLayer;
        private const float CanvasPlane = 1f;
        private const float CanvasSlab = 0.5f;

        private sealed class CanvasState
        {
            internal Canvas Canvas;
            internal RenderMode RenderMode;
            internal Camera WorldCamera;
            internal float PlaneDistance;
        }

        private struct UiLayerState
        {
            internal GameObject Object;
            internal int OriginalLayer;
        }

        private Plugin plugin;
        private CVRSystem system;
        private CVRCompositor compositor;
        private Camera sourceCamera;
        private bool sourceWasEnabled;
        private RenderTexture sourceTarget;
        private StereoTargetEyeMask sourceStereo;
        private int sourceMask;

        private Camera leftCamera;
        private Camera rightCamera;
        private Camera uiCaptureCamera;
        private CommandBuffer capCompositeCommands;
        private CommandBuffer leftHudCommands, rightHudCommands;
        private CommandBuffer leftDepthBegin, leftDepthEnd, rightDepthBegin, rightDepthEnd;
        private Mesh hudMesh;
        private readonly UiCaptureCache uiCaptureCache = new UiCaptureCache();
        private readonly DioramaVisibility visibility = new DioramaVisibility();
        private bool detailedGpuTimings;
        private bool lastLeftLiquidDepth, lastRightLiquidDepth;
        private ulong leftDepthFrames, rightDepthFrames;
        private bool capCommandsAttached;
        private readonly HudLayoutInset hudLayoutInset = new HudLayoutInset();
        private readonly DialogHudLayout dialogHudLayout = new DialogHudLayout();
        private bool centeredDialogVisible;
        private readonly TransparentEffectCompatibility transparentEffects = new TransparentEffectCompatibility();
        private RenderTexture leftTexture;
        private RenderTexture rightTexture;
        private RenderTexture leftMsaaTexture;
        private RenderTexture rightMsaaTexture;
        private RenderTexture flatTexture;
        private RenderTexture cinemaTexture;
        private RenderTexture uiTexture;
        private GameObject flatPanel;
        private GameObject uiPanel;
        private Material flatMaterial;
        private Material uiMaterial;

        private TrackedDevicePose_t[] renderPoses;
        private readonly OpenVrPoseTiming openVrTiming = new OpenVrPoseTiming();
        private float nextOpenVrTimingRefresh;
        private Matrix4x4 leftEyeToHead;
        private Matrix4x4 rightEyeToHead;
        private Matrix4x4 calibrationInverse = Matrix4x4.identity;
        private bool needsRecenter = true;
        private bool initialized;
        private bool resourcesReleased;
        private bool gameplayScene;
        private bool introScene, stereoMenuScene, stereoMenuDiagnosticPending;
        private IntroPresentation introPresentation;
        private IntroMenuCompatibility introMenus;
        private FirstLevelIntroCompatibility levelIntro;
        private LevelEntryCompatibility levelEntry;
        private SectorCinemaCompatibility sectorCinema;
        private CharacterSwapCompatibility characterSwap;
        private bool firstLevelScene, levelIntroFlat, cinemaCaptureFailed, openingScene;
        private Camera levelIntroCamera;
        private readonly FixedPanelAnchor cinemaPanelAnchor = new FixedPanelAnchor();
        private readonly CharacterVisualCompatibility characterVisuals = new CharacterVisualCompatibility();
        private readonly VrScreenFade screenFade = new VrScreenFade();
        private float entrySizeGain = 1f, entryDistanceGain = 1f;
        private OpenVrInputBridge inputBridge;
        private QvCameraCompatibility cameraCompatibility;
        private VrSettingsMenu settingsMenu;
        private Transform gameplayTarget;
        private Type gameManagerType;
        private UnityEngine.Object gameManager;
        private Type playerType;
        private FieldInfo playerField;
        private Vector3 rigPosition;
        private Quaternion rigRotation;
        private float rigUnitsPerMeter = 1f;
        private Vector3 followedPanelPosition;
        private Quaternion followedPanelRotation;
        private bool panelPoseValid;
        private IntPtr renderEvent;
        private float nextCanvasScan;
        private float nextSubmitCheck;
        private int poseSlot;
        private int currentPoseSlot;
        private Vector3 dioramaAnchor;
        private Vector3 dioramaCameraAnchor;
        private bool dioramaAnchorValid;
        // Temporary A/B probes are session-only: never overwrite saved diorama
        // dimensions or silently claim that a diagnostic is real clipping.
        internal int CylinderProbeMode { get; private set; } = 0;
        private Vector3 lastCylinderCenter;
        private Vector3 lastCylinderPivotLocal;
        private float lastCylinderDeterminant;
        private bool cylinderDiagnosticPrepared, cylinderDiagnosticWritten;
        private Matrix4x4 diagnosticView, diagnosticProjection;
        private Vector3 diagnosticCenter;
        private Rect diagnosticRect;

        internal void SetCylinderProbe(int mode)
        {
            CylinderProbeMode = Mathf.Clamp(mode, 0, 3);
            Plugin.Log.LogInfo("QVVR cylinder diagnostic probe=" + CylinderProbeMode +
                " (0=normal, 1=two passes without clipping, 2=unlimited cylinder, 3=neutral screen matrix).");
        }
        private bool passthroughRequested;
        private OpenXrFrame xrFrame;
        private int xrPreparedUnityFrame = -1;
        private bool xrTrackingReady, xrFrameQueued;
        private ulong xrBusyUnityFrames, xrTrackingMisses, xrQueuedFrames;
        private readonly XrInputLatch xrInput = new XrInputLatch();
        internal bool UsesOpenXr { get { return passthroughRequested; } }
        private int lastXrStatus = int.MinValue;
        private uint lastRejectedShaders;
        private uint lastUnknownShaders;
        private double lastMainRenderMilliseconds;
        private bool stabilitySampleValid;
        private Vector3 stabilityPivot, stabilityPlacement;
        private Quaternion stabilityRotation;
        private double maxPivotStepMm, maxPlacementStepMm, maxPlacementTurnDegrees;
        private uint stabilitySamples;
        private double lastXrPrepareMilliseconds;
        private float nextTimingLog;
        private float sceneChangedAt;
        private Compositor_FrameTiming frameTiming;
        private ulong lastSubmittedFrames;
        private float nextUiCapture;
        private float nextFlatCapture;
        private bool uiTextureHasContent;
        private bool performanceSettingsApplied;
        private int originalTargetFrameRate;
        private ShadowQuality originalShadows;
        private readonly List<CanvasState> canvasStates = new List<CanvasState>();
        private readonly Dictionary<int, UiLayerState> uiLayers = new Dictionary<int, UiLayerState>();
        private readonly List<Transform> canvasTransforms = new List<Transform>(128);
        private Canvas[] discoveredCanvases;
        private float nextCanvasDiscovery;
        private readonly WorldGrabState worldGrab = new WorldGrabState();
        private readonly DioramaScaleState dioramaScale = new DioramaScaleState();
        private readonly DioramaPlacementState placement = new DioramaPlacementState();
        private readonly FullVrViewState fullVrView = new FullVrViewState();
        private Vector3 trackingHeadPosition;
        private Quaternion trackingHeadRotation = Quaternion.identity, trackingYaw = Quaternion.identity;
        private bool trackingHeadValid, placeFrontRequested;
        private float lastScaleSetting, lastPitchSetting, lastUnitsSetting, lastExtentSetting;
        private float rigWorldScale = 1f;
        private readonly DioramaViewState dioramaView = new DioramaViewState();
        private bool viewHasPlayer;
        private Vector3 frameDioramaOrigin, frameCylinderCenter;
        private Quaternion trackingToWorldRotation = Quaternion.identity;
        private readonly CloudRendererFilter cloudFilter = new CloudRendererFilter();
        private readonly LiquidDepthPolicy liquidDepth = new LiquidDepthPolicy();
        private readonly CutSurfaceRegistry cutSurfaces = new CutSurfaceRegistry();
        private bool renderMaterialsDirty = true;
        private bool lastCapPreference;
        private bool cloudsDirty = true;
        private bool lastCloudPreference;
        private double maximumMaintenanceMilliseconds;
        private double lastDiagnosticLogMilliseconds;
        private bool diagnosticsEnabled;
        private float nextPresentationRecovery;

        internal Camera SourceCamera { get { return sourceCamera; } }
        internal bool ShortenLevelEntry { get { return initialized && !resourcesReleased && plugin.VrEnabled.Value &&
            plugin.IndependentDioramaView.Value && gameplayScene && !FixedCinemaPanel; } }
        internal bool IsFirstLevelScene { get { return firstLevelScene; } }
        internal bool IsSectorCinemaScene { get { return introScene; } }
        internal Camera LevelIntroCamera { get { return levelIntroFlat ? levelIntroCamera : null; } }
        internal bool UseGameShoulders { get { return initialized && !levelIntroFlat &&
            (gameplayScene || (introScene && introPresentation == IntroPresentation.World)); } }
        private bool FixedCinemaPanel { get { return MenuScenePolicy.FixedCinemaPanel(levelIntroFlat, openingScene); } }
        internal bool CanGrabWorld { get { return initialized && gameplayScene && !levelIntroFlat &&
            plugin.DioramaEnabled.Value && plugin.TwoGripWorldGrab.Value; } }
        internal bool IsControllerTracked(uint device)
        {
            return device < renderPoses.Length && renderPoses[device].bDeviceIsConnected && renderPoses[device].bPoseIsValid;
        }
        internal bool NeedsOpenVrSceneFallback
        {
            get
            {
                if (!UsesOpenXr) return false;
                int error = 0;
                return NativeBridge.QVVR_GetOpenXrStatus(ref error) < 0;
            }
        }
        internal bool HasInputFocus
        {
            get
            {
                int error = 0;
                int xr = NativeBridge.QVVR_GetOpenXrStatus(ref error);
                return UsesOpenXr ? xr == 3 : system != null && compositor != null && system.IsInputAvailable() && compositor.CanRenderScene();
            }
        }

        internal void Initialize(
            Plugin owner,
            CVRSystem vrSystem,
            CVRCompositor vrCompositor,
            Camera source,
            bool allowOpenXr)
        {
            plugin = owner;
            gameManagerType = HarmonyLib.AccessTools.TypeByName("GameManager");
            playerType = HarmonyLib.AccessTools.TypeByName("NewPlayer");
            if (gameManagerType != null)
                playerField = gameManagerType.GetField("newPlayerClass", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            system = vrSystem;
            compositor = vrCompositor;
            renderPoses = new TrackedDevicePose_t[OpenVR.k_unMaxTrackedDeviceCount];
            frameTiming.m_nSize = (uint)Marshal.SizeOf(typeof(Compositor_FrameTiming));
            renderEvent = NativeBridge.QVVR_GetRenderEventFunc();
            if (renderEvent == IntPtr.Zero)
                throw new InvalidOperationException("QVVR native render callback is unavailable.");

            uint width = 0;
            uint height = 0;
            float scale = RenderBudget.SceneScale(plugin.EyeTextureResolutionScale.Value, allowOpenXr, plugin.XrResolutionCap.Value);
            passthroughRequested = allowOpenXr;
            NativeBridge.QVVR_ConfigureOpenXr(passthroughRequested ? 1 : 0);
            if (UsesOpenXr)
            {
                if (system != null || compositor != null) throw new InvalidOperationException("XR requires exclusive API ownership.");
                if (Marshal.SizeOf(typeof(OpenXrFrame)) != 320 || Marshal.SizeOf(typeof(OpenXrPacing)) != 64) throw new InvalidOperationException("XR snapshot ABI mismatch.");
                RenderTexture bootstrap = new RenderTexture(16, 16, 0, RenderTextureFormat.ARGB32);
                try
                {
                    bootstrap.Create();
                    if (NativeBridge.QVVR_InitializeExclusiveOpenXr(bootstrap.GetNativeTexturePtr(), scale, ref width, ref height) == 0)
                    {
                        int error = 0;
                        NativeBridge.QVVR_GetOpenXrStatus(ref error);
                        throw new InvalidOperationException("OpenXR ALPHA_BLEND initialization failed, XrResult=" + error);
                    }
                }
                finally { bootstrap.Release(); Destroy(bootstrap); }
            }
            else
            {
                system.GetRecommendedRenderTargetSize(ref width, ref height);
                width = (uint)Mathf.Max(256, Mathf.RoundToInt(width * scale));
                height = (uint)Mathf.Max(256, Mathf.RoundToInt(height * scale));
                leftEyeToHead = ToUnityMatrix(system.GetEyeToHeadTransform(EVREye.Eye_Left));
                rightEyeToHead = ToUnityMatrix(system.GetEyeToHeadTransform(EVREye.Eye_Right));
                RefreshOpenVrTiming();
            }
            int eyeWidth = (int)width;
            int eyeHeight = (int)height;
            detailedGpuTimings = plugin.DetailedGpuTimings.Value;
            diagnosticsEnabled = plugin.DiagnosticsEnabled.Value;
            NativeBridge.QVVR_SetDetailedGpuTiming(detailedGpuTimings ? 1 : 0);
            CreateResources(eyeWidth, eyeHeight);
            NativeBridge.QVVR_SetEyeColorSpace(QualitySettings.activeColorSpace == ColorSpace.Gamma ? 1 : 0, leftTexture.sRGB ? 1 : 0);
            originalTargetFrameRate = Application.targetFrameRate;
            originalShadows = QualitySettings.shadows;
            performanceSettingsApplied = true;
            if (plugin.CompositorFramePacing.Value) Application.targetFrameRate = -1;
            if (plugin.DisableRealtimeShadows.Value) QualitySettings.shadows = ShadowQuality.Disable;
            SetSourceCamera(source);
            if (!UsesOpenXr) compositor.SetTrackingSpace(ETrackingUniverseOrigin.TrackingUniverseStanding);
            SceneManager.activeSceneChanged += OnActiveSceneChanged;
            gameplayScene = CameraSelector.IsGameplayScene();
            introScene = MenuScenePolicy.IsIntroScene(SceneManager.GetActiveScene().name);
            introMenus = new IntroMenuCompatibility();
            introMenus.Initialize(this);
            firstLevelScene = LevelIntroPolicy.Scene(SceneManager.GetActiveScene().name);
            openingScene = MenuScenePolicy.IsOpeningScene(SceneManager.GetActiveScene().name);
            levelIntro = new FirstLevelIntroCompatibility();
            levelIntro.Initialize(this);
            sectorCinema = new SectorCinemaCompatibility();
            sectorCinema.Initialize(this);
            characterSwap = new CharacterSwapCompatibility();
            characterSwap.Initialize(this);
            initialized = true;
            levelEntry = new LevelEntryCompatibility();
            levelEntry.Initialize(this, plugin);
            dialogHudLayout.Initialize();
            StartCoroutine(CanvasMaintenance());
            settingsMenu = new VrSettingsMenu();
            settingsMenu.Initialize(plugin, this, transform, PanelLayer, flatMaterial.shader);
            cameraCompatibility = new QvCameraCompatibility();
            cameraCompatibility.Initialize(this);
            screenFade.Initialize();
            if (plugin.VrControllerInput.Value)
            {
                inputBridge = gameObject.AddComponent<OpenVrInputBridge>();
                inputBridge.Initialize(plugin, system, compositor, settingsMenu, this);
            }

            Plugin.Log.LogInfo(string.Format(
                "QVVR renderer: {0}x{1} per eye, {2}; 2D target 1920x1080.",
                eyeWidth,
                eyeHeight,
                SystemInfo.graphicsDeviceType));
            Plugin.Log.LogInfo(UsesOpenXr ? "Exclusive XR order: WaitFrame/BeginFrame -> poses/actions -> QV Update -> Unity stereo -> GPU-only copy -> EndFrame ALPHA_BLEND." : "OpenVR graphics-thread order: WaitGetPoses -> GPU rendering/resolve -> Submit; compositor pacing=" + plugin.CompositorFramePacing.Value);
            Plugin.Log.LogInfo("QVVR quality: gameplay MSAA=" + RenderBudget.MsaaSamples(plugin.EyeMsaaSamples.Value) + ", HUD Hz=" + plugin.UiCaptureRate.Value + ", menu Hz=" + plugin.MenuCaptureRate.Value + ", UI=" + uiTexture.width + "x" + uiTexture.height + " trilinear mipmaps, realtime shadows disabled=" + plugin.DisableRealtimeShadows.Value);
            Plugin.Log.LogInfo("QVVR pose-associated submissions enabled; 2D eyes skip scene depth and MSAA resolves.");
            Plugin.Log.LogInfo("QVVR scene scale: requested=" + plugin.EyeTextureResolutionScale.Value +
                ", effective=" + scale + ", XR cap=" + plugin.XrResolutionCap.Value + "; HUD capture resolution is independent.");
            Plugin.Log.LogInfo("OpenVR eye texture vertical correction: " + plugin.FlipEyeTextureY.Value);
            Plugin.Log.LogInfo("QVVR placement: both grips naturally translate/resize/rotate in tracking space; right grip alone has no action. Level entry restores a saved visible layout or fits 1.6 m in front. Movement queries follow viewer heading; panels remain upright.");
        }

        internal void SetSourceCamera(Camera camera)
        {
            if (camera == null || camera == leftCamera || camera == rightCamera || camera == uiCaptureCamera)
                return;

            RestoreSourceCamera();
            worldGrab.Stop();
            dioramaScale.Stop();
            placement.Stop();
            dioramaView.Reset();
            sourceCamera = camera;
            dioramaAnchorValid = false;
            panelPoseValid = false;
            sourceWasEnabled = camera.enabled;
            sourceTarget = camera.targetTexture;
            sourceStereo = camera.stereoTargetEye;
            sourceMask = camera.cullingMask;
            camera.enabled = false;
            nextFlatCapture = 0f;
            Plugin.Log.LogInfo("QVVR source camera: " + CameraSelector.PathOf(camera.transform));
        }

        // Called by state-entry hooks/cold maintenance, never scene/reflection
        // discovery in LateUpdate. Gameplay ownership and placement stay separate.
        internal void SetIntroPresentation(IntroPresentation state)
        {
            if (!introScene) return;
            if (introPresentation == IntroPresentation.Stage && state != IntroPresentation.Stage)
                screenFade.SceneChanged(false, false); // Back/cancel without loading a scene.
            introPresentation = state;
            bool stereo = MenuScenePolicy.StereoSelection(plugin.StereoSelectionMenus.Value, introScene, state);
            if (stereoMenuScene == stereo) return;
            stereoMenuScene = stereo;
            stereoMenuDiagnosticPending = stereo;
            needsRecenter = true; panelPoseValid = false;
            nextFlatCapture = nextUiCapture = 0f;
            RedirectOverlayCanvases();
            if (inputBridge != null) inputBridge.RequireGripRelease();
            if (settingsMenu != null) settingsMenu.ResetAnchor();
            Plugin.Log.LogInfo("QVVR intro presentation: " + state + (stereo ? " - full stereo menu, no diorama/cylinder." : " - captured 2D menu."));
        }

        internal void BeginStageFade(UnityEngine.UI.Image panel)
        {
            if (introScene && stereoMenuScene && introPresentation == IntroPresentation.Stage)
            {
                screenFade.Begin(panel);
                nextUiCapture = 0f;
            }
        }

        internal void SetLevelIntro(bool playing, Camera captureCamera)
        {
            // Shared fixed-panel route for the verified first-level intro and
            // sector-clear movie. Only their scoped compatibility hooks call it.
            if ((!firstLevelScene || !gameplayScene) && !introScene) return;
            if (playing && captureCamera == null) return; // Do not switch to an unverified capture source.
            if (playing && cinemaCaptureFailed) return;
            bool changed = levelIntroFlat != playing;
            if (!changed && !playing) return; // Do not override normal gameplay camera selection.
            if (changed)
            {
                nextPresentationRecovery = 0f;
                if (playing && cinemaTexture == null)
                {
                    // RGB-only capture samples alpha=1, even when original movie
                    // shaders/post effects write unused alpha=0. Cold creation,
                    // no extra copy pass and no change to validated menu targets.
                    RenderTextureFormat format = SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.RGB111110Float)
                        ? RenderTextureFormat.RGB111110Float : RenderTextureFormat.RGB565;
                    cinemaTexture = CreateTexture("QVVR_CinemaCapture", 1920, 1080, 24, 1, true, format);
                    if (!cinemaTexture.IsCreated())
                    {
                        DestroyTexture(cinemaTexture); cinemaTexture = null; cinemaCaptureFailed = true;
                        Plugin.Log.LogWarning("QVVR cinematic capture unavailable; normal VR rendering retained.");
                        return;
                    }
                }
                flatMaterial.mainTexture = playing ? cinemaTexture : flatTexture;
                placement.Stop(); SavePlacementSettings(); placement.Reset();
                if (playing) characterVisuals.Clear();
                cinemaPanelAnchor.Reset();
                panelPoseValid = false; nextFlatCapture = nextUiCapture = 0f;
                if (inputBridge != null) inputBridge.RequireGripRelease();
                if (settingsMenu != null) settingsMenu.ResetAnchor();
                Plugin.Log.LogInfo(playing ? "QVVR cinematic: fixed flat panel (first intro or sector clear)." : "QVVR cinematic: original stereo gameplay/menu restored.");
            }
            levelIntroFlat = playing; levelIntroCamera = playing ? captureCamera : null;
            if (captureCamera != null && sourceCamera != captureCamera) SetSourceCamera(captureCamera);
            if (changed) RedirectOverlayCanvases();
        }

        internal void Recenter()
        {
            placement.Stop();
            SavePlacementSettings();
            if (plugin.DioramaEnabled.Value) { placement.Reset(); placeFrontRequested = true; }
            fullVrView.Reset();
            worldGrab.ResetOffset();
            dioramaScale.Stop();
            dioramaView.Reset();
            if (inputBridge != null) inputBridge.RequireGripRelease();
            needsRecenter = true;
            panelPoseValid = false;
            cinemaPanelAnchor.Reset();
            if (settingsMenu != null) settingsMenu.ResetAnchor();
            Plugin.Log.LogInfo("OpenVR recenter requested.");
        }

        private void CreateResources(int width, int height)
        {
            leftTexture = CreateTexture("QVVR_LeftEye", width, height, 24);
            rightTexture = CreateTexture("QVVR_RightEye", width, height, 24);
            int samples = RenderBudget.MsaaSamples(plugin.EyeMsaaSamples.Value);
            if (samples > 1)
            {
                leftMsaaTexture = CreateTexture("QVVR_LeftEyeMsaa", width, height, 24, samples);
                rightMsaaTexture = CreateTexture("QVVR_RightEyeMsaa", width, height, 24, samples);
            }
            flatTexture = CreateTexture("QVVR_FlatScreen", 1920, 1080, 24, 1, true);
            float uiScale = RenderBudget.UiScale(plugin.UiTextureScale.Value);
            uiTexture = CreateTexture("QVVR_UiCapture", Mathf.RoundToInt(1920 * uiScale), Mathf.RoundToInt(1080 * uiScale), 0, 1, true);
            ClearTexture(uiTexture, new Color(0f, 0f, 0f, 0f));
            uiTexture.GenerateMips();

            leftCamera = CreateCamera("QVVR_LeftEyeCamera", leftTexture);
            rightCamera = CreateCamera("QVVR_RightEyeCamera", rightTexture);
            uiCaptureCamera = CreateCamera("QVVR_UiCaptureCamera", uiTexture);
            capCompositeCommands = new CommandBuffer { name = "QVVR black cross-sections before transparent geometry" };
            capCompositeCommands.IssuePluginEvent(renderEvent, NativeBridge.CapCompositeEvent);
            leftHudCommands = new CommandBuffer { name = "QVVR direct HUD left" };
            rightHudCommands = new CommandBuffer { name = "QVVR direct HUD right" };
            leftCamera.AddCommandBuffer(CameraEvent.AfterEverything, leftHudCommands);
            rightCamera.AddCommandBuffer(CameraEvent.AfterEverything, rightHudCommands);
            if (detailedGpuTimings)
            {
                leftDepthBegin = ProfileCommands("QVVR depth left begin", 12);
                leftDepthEnd = ProfileCommands("QVVR depth left end", 13);
                rightDepthBegin = ProfileCommands("QVVR depth right begin", 14);
                rightDepthEnd = ProfileCommands("QVVR depth right end", 15);
                leftCamera.AddCommandBuffer(CameraEvent.BeforeDepthTexture, leftDepthBegin);
                leftCamera.AddCommandBuffer(CameraEvent.AfterDepthTexture, leftDepthEnd);
                rightCamera.AddCommandBuffer(CameraEvent.BeforeDepthTexture, rightDepthBegin);
                rightCamera.AddCommandBuffer(CameraEvent.AfterDepthTexture, rightDepthEnd);
            }
            uiCaptureCamera.clearFlags = CameraClearFlags.SolidColor;
            uiCaptureCamera.backgroundColor = new Color(0f, 0f, 0f, 0f);
            uiCaptureCamera.cullingMask = UiCaptureMask;
            uiCaptureCamera.allowHDR = false;
            uiCaptureCamera.allowMSAA = false;
            uiCaptureCamera.useOcclusionCulling = false;
            uiCaptureCamera.renderingPath = RenderingPath.Forward;
            uiCaptureCamera.transform.position = new Vector3(0f, -1000f, 0f);
            uiCaptureCamera.transform.rotation = Quaternion.identity;
            uiCaptureCamera.nearClipPlane = CanvasPlane - CanvasSlab;
            uiCaptureCamera.farClipPlane = CanvasPlane + CanvasSlab;

            flatMaterial = CreateMaterial("QVVR_FlatScreenMaterial", flatTexture, false);
            uiMaterial = CreateMaterial("QVVR_UiMaterial", uiTexture, true);
            flatPanel = CreatePanel("QVVR_FlatScreenPanel", flatMaterial);
            uiPanel = CreatePanel("QVVR_UiPanel", uiMaterial);
            hudMesh = uiPanel.GetComponent<MeshFilter>().sharedMesh;
            flatPanel.transform.SetParent(transform, true);
            uiPanel.transform.SetParent(transform, true);

            NativeBridge.QVVR_SetFlipEyeTextureY(plugin.FlipEyeTextureY.Value ? 1 : 0);
            NativeBridge.QVVR_SetEyeTextures(
                leftTexture.GetNativeTexturePtr(),
                rightTexture.GetNativeTexturePtr());
            NativeBridge.QVVR_SetClipTargets(
                (leftMsaaTexture != null ? leftMsaaTexture : leftTexture).GetNativeTexturePtr(),
                (rightMsaaTexture != null ? rightMsaaTexture : rightTexture).GetNativeTexturePtr());
        }

        private static RenderTexture CreateTexture(string name, int width, int height, int depth, int samples = 1, bool mipmaps = false, RenderTextureFormat format = RenderTextureFormat.ARGB32)
        {
            RenderTexture texture = new RenderTexture(
                width,
                height,
                depth,
                format,
                RenderTextureReadWrite.Default);
            texture.name = name;
            texture.antiAliasing = samples;
            texture.bindTextureMS = samples > 1;
            texture.filterMode = mipmaps ? FilterMode.Trilinear : FilterMode.Bilinear;
            texture.useMipMap = mipmaps;
            texture.autoGenerateMips = false;
            texture.hideFlags = HideFlags.HideAndDontSave;
            texture.Create();
            return texture;
        }

        private Camera CreateCamera(string name, RenderTexture target)
        {
            GameObject cameraObject = new GameObject(name);
            cameraObject.hideFlags = HideFlags.HideAndDontSave;
            cameraObject.transform.SetParent(transform, false);
            Camera camera = cameraObject.AddComponent<Camera>();
            camera.enabled = false;
            camera.stereoTargetEye = StereoTargetEyeMask.None;
            camera.targetTexture = target;
            return camera;
        }

        private static Material CreateMaterial(string name, Texture texture, bool transparent)
        {
            Shader shader = transparent ? null : Shader.Find("Unlit/Texture");
            if (shader != null && !shader.isSupported)
                shader = null;
            for (int index = 0; shader == null && index < PanelShaderCandidates.Length; index++)
            {
                Shader candidate = Shader.Find(PanelShaderCandidates[index]);
                if (candidate != null && candidate.isSupported)
                    shader = candidate;
            }
            if (shader == null)
            {
                Material canvasDefault = Canvas.GetDefaultCanvasMaterial();
                if (canvasDefault != null && canvasDefault.shader != null && canvasDefault.shader.isSupported)
                    shader = canvasDefault.shader;
            }
            if (shader == null)
                throw new InvalidOperationException("No supported alpha-blended panel shader is loaded for " + name + ".");

            Plugin.Log.LogInfo("QVVR panel shader for " + name + ": " + shader.name);

            Material material = new Material(shader);
            material.name = name;
            material.mainTexture = texture;
            if (transparent)
            {
                material.renderQueue = 3950;
                material.SetInt("unity_GUIZTestMode", (int)CompareFunction.Always);
                material.SetInt("_ZTest", (int)CompareFunction.Always);
            }
            return material;
        }

        private static GameObject CreatePanel(string name, Material material)
        {
            GameObject panel = GameObject.CreatePrimitive(PrimitiveType.Quad);
            panel.name = name;
            panel.hideFlags = HideFlags.HideAndDontSave;
            panel.layer = PanelLayer;
            Collider collider = panel.GetComponent<Collider>();
            if (collider != null)
                Destroy(collider);
            MeshRenderer renderer = panel.GetComponent<MeshRenderer>();
            renderer.material = material;
            renderer.shadowCastingMode = ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            return panel;
        }

        internal bool PrepareTracking()
        {
            if (!UsesOpenXr) return true;
            if (xrPreparedUnityFrame == Time.frameCount) return xrTrackingReady;
            // A camera disappearance/failed pose-queue write may have prevented
            // submission. Only cancel frames that never queued GPU commands.
            if (xrTrackingReady && !xrFrameQueued) NativeBridge.QVVR_CancelOpenXrFrame();
            xrPreparedUnityFrame = Time.frameCount;
            xrFrameQueued = false;
            long started = System.Diagnostics.Stopwatch.GetTimestamp();
            int result = initialized && sourceCamera != null ? NativeBridge.QVVR_PrepareOpenXrFrame(ref xrFrame) : 0;
            xrInput.Update(result);
            if (result == 2) xrBusyUnityFrames++;
            else if (!xrInput.RenderReady) xrTrackingMisses++;
            xrTrackingReady = xrInput.RenderReady;
            lastXrPrepareMilliseconds = (System.Diagnostics.Stopwatch.GetTimestamp() - started) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
            if (!xrTrackingReady)
            {
                if (!xrInput.Busy) { worldGrab.Stop(); dioramaScale.Stop(); placement.Stop(); trackingHeadValid = false; }
                return false;
            }
            renderPoses[0] = XrTrackedPose(xrFrame.Head, true, true);
            CacheHeadPose(ToUnityMatrix(xrFrame.Head));
            renderPoses[1] = XrTrackedPose(xrFrame.LeftHand.Pose, (xrFrame.LeftHand.Valid & 1) != 0, xrFrame.LeftHand.Valid != 0);
            renderPoses[2] = XrTrackedPose(xrFrame.RightHand.Pose, (xrFrame.RightHand.Valid & 1) != 0, xrFrame.RightHand.Valid != 0);
            return true;
        }

        private static TrackedDevicePose_t XrTrackedPose(HmdMatrix34_t pose, bool valid, bool connected)
        {
            TrackedDevicePose_t result = new TrackedDevicePose_t();
            result.mDeviceToAbsoluteTracking = pose;
            result.bPoseIsValid = valid;
            result.bDeviceIsConnected = connected;
            result.eTrackingResult = valid ? ETrackingResult.Running_OK : ETrackingResult.Uninitialized;
            return result;
        }

        internal bool GetXrControllerState(bool left, ref VRControllerState_t state)
        {
            state = new VRControllerState_t();
            if (!xrInput.InputReady) return false;
            OpenXrHand hand = left ? xrFrame.LeftHand : xrFrame.RightHand;
            if (hand.Valid == 0) return false;
            // Reuse only the legacy data layout, never the OpenVR runtime.
            state.rAxis0.x = hand.StickX; state.rAxis0.y = hand.StickY;
            state.rAxis1.x = hand.Trigger;
            state.rAxis2.x = hand.Grip;
            if ((hand.Buttons & 1) != 0) state.ulButtonPressed |= 1UL << 7;
            if ((hand.Buttons & 2) != 0) state.ulButtonPressed |= 1UL << 1;
            if ((hand.Buttons & 4) != 0) state.ulButtonPressed |= 1UL << 32;
            if ((hand.Buttons & 8) != 0) state.ulButtonPressed |= 1UL << 2;
            return true;
        }

        // Cold startup/maintenance: frequency can change while a wireless PCVR
        // runtime is connected. OpenXR must never call the OpenVR tracking API.
        private void RefreshOpenVrTiming()
        {
            if (UsesOpenXr || system == null) return;
            ETrackedPropertyError error = ETrackedPropertyError.TrackedProp_Success;
            float hz = system.GetFloatTrackedDeviceProperty(OpenVR.k_unTrackedDeviceIndex_Hmd,
                ETrackedDeviceProperty.Prop_DisplayFrequency_Float, ref error);
            if (error != ETrackedPropertyError.TrackedProp_Success) hz = 0f;
            error = ETrackedPropertyError.TrackedProp_Success;
            float photons = system.GetFloatTrackedDeviceProperty(OpenVR.k_unTrackedDeviceIndex_Hmd,
                ETrackedDeviceProperty.Prop_SecondsFromVsyncToPhotons_Float, ref error);
            if (error != ETrackedPropertyError.TrackedProp_Success) photons = 0f;
            openVrTiming.Configure(hz, photons);
            nextOpenVrTimingRefresh = Time.unscaledTime + 1f;
        }

        private void PredictOpenVrTracking()
        {
            if (UsesOpenXr || system == null) return;
            float sinceVsync = 0f;
            ulong frameCounter = 0;
            bool hasVsync = system.GetTimeSinceLastVsync(ref sinceVsync, ref frameCounter);
            system.GetDeviceToAbsoluteTrackingPose(ETrackingUniverseOrigin.TrackingUniverseStanding,
                openVrTiming.Prediction(hasVsync, sinceVsync), renderPoses);
        }

        private void LateUpdate()
        {
            if (!initialized || sourceCamera == null || (!UsesOpenXr && compositor == null))
                return;

            // Non-blocking prediction for the Unity cameras. The compositor's
            // blocking WaitGetPoses is paired with Submit on the graphics thread.
            if (UsesOpenXr)
            {
                if (!PrepareTracking()) return;
            }
            else PredictOpenVrTracking();

            TrackedDevicePose_t hmdPose = renderPoses[OpenVR.k_unTrackedDeviceIndex_Hmd];
            if (!hmdPose.bDeviceIsConnected || !hmdPose.bPoseIsValid)
            {
                worldGrab.Stop();
                dioramaScale.Stop();
                placement.Stop();
                trackingHeadValid = false;
                sourceCamera.enabled = sourceWasEnabled;
                if (plugin.CompositorFramePacing.Value) Application.targetFrameRate = originalTargetFrameRate;
                return;
            }

            sourceCamera.enabled = false;
            // QV's options code may reset its limiter after our initialization.
            if (plugin.CompositorFramePacing.Value && Application.targetFrameRate != -1)
                Application.targetFrameRate = -1;
            if (plugin.DisableRealtimeShadows.Value && QualitySettings.shadows != ShadowQuality.Disable)
            {
                // Preserve a later game-options change for desktop fallback.
                originalShadows = QualitySettings.shadows;
                QualitySettings.shadows = ShadowQuality.Disable;
            }

            Matrix4x4 absoluteHead = ToUnityMatrix(hmdPose.mDeviceToAbsoluteTracking);
            CacheHeadPose(absoluteHead);
            if (needsRecenter)
            {
                calibrationInverse = absoluteHead.inverse;
                needsRecenter = false;
                if (stereoMenuScene) stereoMenuDiagnosticPending = true;
                Plugin.Log.LogInfo("OpenVR view recentered.");
            }
            Matrix4x4 relativeHead = calibrationInverse * absoluteHead;

            if (NativeBridge.QVVR_SetRenderPoseAndMode(poseSlot, ref hmdPose.mDeviceToAbsoluteTracking, MenuScenePolicy.RenderStereoMenu(stereoMenuScene, levelIntroFlat) ? 1 : 0) == 0) return;
            currentPoseSlot = poseSlot;
            long renderStarted = System.Diagnostics.Stopwatch.GetTimestamp();
            int eventOffset = poseSlot * 4;
            poseSlot = (poseSlot + 1) % NativeBridge.PoseSlotCount;
            UpdateRig();
            UpdateWorldGrab();
            UpdateDioramaStick();
            // Apply placement input in this same stereo frame for both eyes.
            UpdateRig();
            if (diagnosticsEnabled) SampleDioramaStability();
            if (gameplayScene && !levelIntroFlat && plugin.BlackCutSurfaces.Value && plugin.CullOutsideDiorama.Value && plugin.LiveCapBounds.Value &&
                plugin.DioramaEnabled.Value && CylinderProbeMode == 0 && NativeBridge.ShaderClipReady)
                cutSurfaces.PrepareFrame(currentPoseSlot, frameCylinderCenter,
                    SafeValue(plugin.DioramaRadius.Value, 12f, 0.5f, 200f), SafeValue(plugin.DioramaHeight.Value, 12f, 0.5f, 200f) * 0.5f);
            else if (NativeBridge.ShaderClipReady) cutSurfaces.ClearFrame(currentPoseSlot);
            GL.IssuePluginEvent(renderEvent, NativeBridge.BeginFrameEventId + eventOffset);
            xrFrameQueued = UsesOpenXr;
            try
            {
                if (introMenus != null && MenuScenePolicy.HideStageDim(MenuScenePolicy.RenderStereoMenu(stereoMenuScene, levelIntroFlat), introPresentation)) introMenus.HideStageDim();
                screenFade.Prepare();
                CaptureUi();
                PositionPanels(relativeHead);
                if (settingsMenu != null)
                    settingsMenu.UpdatePose(trackingHeadPosition, trackingYaw, rigUnitsPerMeter,
                        rigPosition, rigRotation, calibrationInverse);

                if (gameplayScene && !levelIntroFlat)
                {
                    try
                    {
                        if (plugin.HideDecorativeClouds.Value) cloudFilter.HideForStereo();
                        if (UsesOpenXr && lastXrStatus > 0) transparentEffects.Prepare();
                        if (plugin.WaterFoamFix.Value) liquidDepth.PrepareWater();
                        if (plugin.CullOutsideDiorama.Value && plugin.DioramaEnabled.Value && CylinderProbeMode == 0 && NativeBridge.ShaderClipReady)
                            visibility.HideOutside(frameCylinderCenter, SafeValue(plugin.DioramaRadius.Value, 12f, 0.5f, 200f),
                                SafeValue(plugin.DioramaHeight.Value, 12f, 0.5f, 200f) * 0.5f);
                        RenderStereoGameplay();
                    }
                    finally { visibility.Restore(); liquidDepth.RestoreWater(); transparentEffects.Restore(); cloudFilter.Restore(); }
                }
                else if (MenuScenePolicy.RenderStereoMenu(stereoMenuScene, levelIntroFlat))
                    RenderStereoGameplay();
                else
                    RenderFlatScreen();
            }
            finally { screenFade.Restore(); if (introMenus != null) introMenus.RestoreStageDim(); }

            GL.IssuePluginEvent(renderEvent, NativeBridge.SubmitEventId + eventOffset);
            if (UsesOpenXr) xrQueuedFrames++;
            lastMainRenderMilliseconds = (System.Diagnostics.Stopwatch.GetTimestamp() - renderStarted) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
            CheckSubmitState();
        }

        private IEnumerator CanvasMaintenance()
        {
            WaitForSecondsRealtime interval = new WaitForSecondsRealtime(0.1f);
            WaitForEndOfFrame afterRender = new WaitForEndOfFrame();
            while (initialized)
            {
                // Do not hold a freshly predicted XR pose while scanning UI,
                // refreshing render registries or formatting diagnostic logs.
                // Queue the stereo frame/Submit first; changes affect the next
                // frame. Reuse both yield objects, no per-tick allocation.
                if (plugin.PostSubmitMaintenance.Value) yield return afterRender;
                if (!initialized) yield break;
                long maintenanceStarted = System.Diagnostics.Stopwatch.GetTimestamp();
                CommitWorldGrabSettings(false);
                if (!UsesOpenXr && Time.unscaledTime >= nextOpenVrTimingRefresh) RefreshOpenVrTiming();
                // Event hooks still react immediately. Slow only the defensive
                // recovery polling while idle; active/paused movies stay fast.
                if (Time.unscaledTime >= nextPresentationRecovery)
                {
                    nextPresentationRecovery = Time.unscaledTime + (levelIntroFlat ? 0.1f : 1f);
                    if (firstLevelScene && levelIntro != null) levelIntro.Refresh();
                    if (introScene && sectorCinema != null) sectorCinema.Refresh();
                    if (introScene && introMenus != null) introMenus.Refresh();
                }
                if (introScene) SetIntroPresentation(introPresentation); // Live 2D recovery switch.
                if (plugin.BlackCutSurfaces.Value != lastCapPreference) renderMaterialsDirty = true;
                if (cutSurfaces.NeedsRefresh) renderMaterialsDirty = true;
                if (renderMaterialsDirty)
                {
                    liquidDepth.Clear(); cutSurfaces.Clear(); transparentEffects.Clear();
                    visibility.Clear();
                    lastCapPreference = plugin.BlackCutSurfaces.Value;
                    if (lastCapPreference != capCommandsAttached)
                    {
                        // Cold attachment only. Do not mistake opaque ForwardAdd
                        // blending for the start of transparent geometry.
                        if (lastCapPreference)
                        {
                            leftCamera.AddCommandBuffer(CameraEvent.BeforeForwardAlpha, capCompositeCommands);
                            rightCamera.AddCommandBuffer(CameraEvent.BeforeForwardAlpha, capCompositeCommands);
                        }
                        else
                        {
                            leftCamera.RemoveCommandBuffer(CameraEvent.BeforeForwardAlpha, capCompositeCommands);
                            rightCamera.RemoveCommandBuffer(CameraEvent.BeforeForwardAlpha, capCompositeCommands);
                        }
                        capCommandsAttached = lastCapPreference;
                    }
                    if (gameplayScene || introScene)
                    {
                        liquidDepth.Refresh();
                        if (gameplayScene) transparentEffects.Refresh();
                        if (gameplayScene && lastCapPreference) cutSurfaces.Refresh();
                        if (gameplayScene) visibility.Refresh(sourceMask & ~(UiCaptureMask | PanelMask));
                    }
                    renderMaterialsDirty = false;
                    Plugin.Log.LogInfo("QVVR liquid depth renderers=" + liquidDepth.Count + ", cap meshes=" + cutSurfaces.Count);
                    Plugin.Log.LogInfo("QVVR cached passthrough fairy materials=" + transparentEffects.Count);
                }
                if (plugin.HideDecorativeClouds.Value != lastCloudPreference) cloudsDirty = true;
                if (cloudsDirty)
                {
                    lastCloudPreference = plugin.HideDecorativeClouds.Value;
                    cloudFilter.Clear();
                    if (gameplayScene && lastCloudPreference) cloudFilter.Refresh();
                    cloudsDirty = false;
                    Plugin.Log.LogInfo("QVVR decorative clouds: hide=" + lastCloudPreference + ", cached renderers=" + cloudFilter.Count);
                }
                if (Time.unscaledTime >= nextCanvasScan)
                {
                    nextCanvasScan = Time.unscaledTime + 0.5f;
                    RedirectOverlayCanvases();
                    RefreshGameplayTarget();
                }
                maximumMaintenanceMilliseconds = Math.Max(maximumMaintenanceMilliseconds,
                    (System.Diagnostics.Stopwatch.GetTimestamp() - maintenanceStarted) * 1000.0 / System.Diagnostics.Stopwatch.Frequency);
                if (Time.unscaledTime >= nextTimingLog)
                {
                    nextTimingLog = Time.unscaledTime + (diagnosticsEnabled || detailedGpuTimings ? 5f : 30f);
                    long logStarted = System.Diagnostics.Stopwatch.GetTimestamp();
                    LogFrameTiming();
                    lastDiagnosticLogMilliseconds = (System.Diagnostics.Stopwatch.GetTimestamp() - logStarted) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
                    maximumMaintenanceMilliseconds = 0;
                }
                yield return interval;
            }
        }

        private void CaptureUi()
        {
            bool centerDialog = plugin.CenterDialogs.Value && !FixedCinemaPanel &&
                MenuScenePolicy.UseGameplayHud(gameplayScene && !levelIntroFlat, MenuScenePolicy.RenderStereoMenu(stereoMenuScene, levelIntroFlat)) &&
                dialogHudLayout.HasVisibleDialog;
            if (centerDialog != centeredDialogVisible)
            {
                centeredDialogVisible = centerDialog;
                uiCaptureCache.Invalidate(); nextUiCapture = 0f;
                // A newly opened dialogue starts in front immediately, then
                // resumes the normal comfortable upright panel-follow lag.
                if (centerDialog) panelPoseValid = false;
            }
            bool visible = false;
            for (int index = 0; index < canvasStates.Count; index++)
            {
                Canvas canvas = canvasStates[index].Canvas;
                if (canvas != null && canvas.enabled && canvas.gameObject.activeInHierarchy) { visible = true; break; }
            }
            if (!visible)
            {
                if (uiTextureHasContent) { ClearTexture(uiTexture, Color.clear); uiTexture.GenerateMips(); }
                uiCaptureCache.Invalidate();
                uiTextureHasContent = false;
                if (uiPanel.activeSelf) uiPanel.SetActive(false);
                return;
            }
            if (!uiPanel.activeSelf) uiPanel.SetActive(true);
            if (Time.unscaledTime + 0.0001f < nextUiCapture) return;
            bool gameplayHud = MenuScenePolicy.UseGameplayHud(gameplayScene && !levelIntroFlat, MenuScenePolicy.RenderStereoMenu(stereoMenuScene, levelIntroFlat));
            nextUiCapture = RenderBudget.NextCapture(Time.unscaledTime, nextUiCapture, Mathf.Clamp(gameplayHud ? plugin.UiCaptureRate.Value : plugin.MenuCaptureRate.Value, 1, 72));
            if (plugin.AdaptiveUiCapture.Value && uiTextureHasContent && !uiCaptureCache.NeedsCapture()) return;
            ProfileMark(0);
            try
            {
                if (centerDialog) dialogHudLayout.Prepare();
                uiCaptureCamera.Render();
            }
            finally { dialogHudLayout.Restore(); }
            uiTexture.GenerateMips();
            ProfileMark(1);
            // Snapshot original game layout, AFTER temporary VR centering is
            // restored. Otherwise the cache would invalidate itself every frame.
            uiCaptureCache.Captured();
            uiTextureHasContent = true;
        }

        private void PositionPanels(Matrix4x4 relativeHead)
        {
            Vector3 headPosition = rigPosition + rigRotation * ((Vector3)relativeHead.GetColumn(3) * rigUnitsPerMeter);
            Quaternion headRotation = UprightHeadRotation();
            float weight = ComfortMath.FollowWeight(Time.unscaledDeltaTime, Mathf.Clamp(plugin.PanelFollowLag.Value, 0f, 1.5f));
            if (FixedCinemaPanel)
            {
                // Physical-space anchor: neither Timeline camera animation nor
                // HMD movement makes the screen chase the viewer. Calibration
                // maps this fixed anchor and the eyes through the same space.
                cinemaPanelAnchor.Latch(trackingHeadPosition, trackingYaw);
                followedPanelPosition = rigPosition + rigRotation *
                    (calibrationInverse.MultiplyPoint3x4(cinemaPanelAnchor.Position) * rigUnitsPerMeter);
                followedPanelRotation = rigRotation * calibrationInverse.rotation * cinemaPanelAnchor.Rotation;
            }
            else if (!panelPoseValid)
            {
                followedPanelPosition = headPosition;
                followedPanelRotation = headRotation;
                panelPoseValid = true;
            }
            else
            {
                followedPanelPosition = Vector3.Lerp(followedPanelPosition, headPosition, weight);
                followedPanelRotation = Quaternion.Slerp(followedPanelRotation, headRotation, weight);
            }
            float width = Mathf.Clamp(plugin.PanelWidth.Value, 1f, 4f) * rigUnitsPerMeter;
            float height = width * 1080f / 1920f;
            float distance = Mathf.Clamp(plugin.PanelDistance.Value, 1.5f, 5f) * rigUnitsPerMeter;

            flatPanel.transform.position = followedPanelPosition + followedPanelRotation * Vector3.forward * distance;
            flatPanel.transform.rotation = followedPanelRotation;
            flatPanel.transform.localScale = new Vector3(width, height, 1f);

            bool gameplayHud = MenuScenePolicy.UseGameplayHud(gameplayScene && !levelIntroFlat, MenuScenePolicy.RenderStereoMenu(stereoMenuScene, levelIntroFlat));
            float hudScale = gameplayHud ? DioramaMath.HudScale(plugin.GameplayHudScale.Value) : 1f;
            hudScale = MenuScenePolicy.HubHudScale(MenuScenePolicy.RenderStereoMenu(stereoMenuScene, levelIntroFlat), introPresentation, hudScale);
            float hudDistance = gameplayHud ? SafeValue(plugin.GameplayHudDistance.Value, 2.8f, 1f, 5f) * rigUnitsPerMeter : distance;
            if (!levelIntroFlat && MenuScenePolicy.HubPauseOverlay(introScene, introPresentation))
            {
                hudScale = 2f;
                hudDistance = MenuScenePolicy.PauseDistance(plugin.HubPauseDistance.Value) * rigUnitsPerMeter;
            }
            uiPanel.transform.position = followedPanelPosition + followedPanelRotation * Vector3.forward * (hudDistance - 0.01f * rigUnitsPerMeter);
            uiPanel.transform.rotation = followedPanelRotation;
            uiPanel.transform.localScale = new Vector3(width * hudScale, height * hudScale, 1f);
        }

        // Cold maintenance and GameManager swap callbacks only. The game's
        // newPlayerClass changes on character swap: always re-read it rather
        // than keeping the first character for the whole level.
        internal void RefreshGameplayTarget()
        {
            if (!gameplayScene) return;
            Component player = null;
            if (gameManagerType != null && playerField != null)
            {
                if (gameManager == null) gameManager = FindObjectOfType(gameManagerType);
                if (gameManager != null) player = playerField.GetValue(gameManager) as Component;
            }
            if (player == null && gameplayTarget == null && playerType != null)
                player = FindObjectOfType(playerType) as Component;
            if (player != null && player.transform != gameplayTarget)
            {
                bool swapped = gameplayTarget != null;
                gameplayTarget = player.transform;
                Plugin.Log.LogInfo((swapped ? "QVVR character swap; camera pivot: " : "QVVR camera distance pivot: ") +
                    CameraSelector.PathOf(gameplayTarget));
            }
            if (gameplayTarget != null) RefreshCharacterVisuals();
        }

        private void CacheHeadPose(Matrix4x4 absoluteHead)
        {
            trackingHeadPosition = (Vector3)absoluteHead.GetColumn(3);
            trackingHeadRotation = absoluteHead.rotation;
            trackingYaw = SpatialMath.Upright(trackingHeadRotation, trackingYaw);
            trackingHeadValid = true;
        }

        private void RefreshCharacterVisuals()
        {
            // Cold maintenance also releases the override on tracking loss or
            // while Q's gameplay actor is hidden by a cinematic.
            if (trackingHeadValid && !levelIntroFlat) characterVisuals.Refresh(gameplayTarget);
            else characterVisuals.Clear();
        }

        private Quaternion UprightHeadRotation()
        {
            // Strip pitch/roll in physical tracking space BEFORE game rotation.
            return rigRotation * calibrationInverse.rotation * trackingYaw;
        }

        internal Vector2 MapPlayerMovement(Vector2 stick, bool cancelSourceYaw)
        {
            if (!gameplayScene || levelIntroFlat || !trackingHeadValid || sourceCamera == null) return stick;
            bool diorama = plugin.DioramaEnabled.Value;
            if (diorama ? !placement.Valid : !fullVrView.Valid) return stick;
            Quaternion sourceYaw = cancelSourceYaw ? Quaternion.AngleAxis(sourceCamera.transform.eulerAngles.y, Vector3.up) : Quaternion.identity;
            return SpatialMath.Movement(stick, diorama ? placement.Rotation : Quaternion.Inverse(fullVrView.Rotation), trackingYaw, sourceYaw);
        }

        private void UpdateRig()
        {
            // Switching back restores the untouched miniature placement. A new
            // full-world session starts beside Q, never at miniature scale.
            if (plugin.DioramaEnabled.Value || FixedCinemaPanel || !gameplayScene) fullVrView.Reset();
            if (FixedCinemaPanel)
            {
                // The animated source camera belongs only to the captured movie.
                // Panel-only eyes use an independent, stationary viewing space.
                rigPosition = Vector3.zero; rigRotation = Quaternion.identity;
                rigUnitsPerMeter = rigWorldScale = 1f;
                return;
            }
            if (stereoMenuScene)
            {
                // Follow only QV's scripted selection-camera framing, then add
                // unsmoothed stereo head tracking. Never apply gameplay tilt,
                // stored diorama size/offset, player-follow or grip transforms.
                rigPosition = sourceCamera.transform.position;
                rigRotation = sourceCamera.transform.rotation;
                if (introPresentation == IntroPresentation.World && introMenus != null)
                    rigPosition = introMenus.HubPosition(rigPosition, rigRotation, plugin.IntroHubDistanceScale.Value);
                rigUnitsPerMeter = rigWorldScale = 1f;
                return;
            }
            if (gameplayScene && !plugin.DioramaEnabled.Value)
            { UpdateFullVrRig(); return; }
            if (!gameplayScene || gameplayTarget == null || !trackingHeadValid || (!placement.Valid && !HasInputFocus))
            { UpdateLegacyRig(); return; }
            frameDioramaOrigin = gameplayTarget.position;
            frameCylinderCenter = frameDioramaOrigin + Vector3.up * SafeValue(plugin.DioramaCenterHeight.Value, 3f, -200f, 200f);
            float units = SafeValue(plugin.WorldUnitsPerMeter.Value, 1f, 0.25f, 10f);
            float extent = Mathf.Max(2f * SafeValue(plugin.DioramaRadius.Value, 12f, 0.5f, 200f),
                SafeValue(plugin.DioramaHeight.Value, 12f, 0.5f, 200f));
            if (!placement.Valid)
            {
                float preferred = plugin.PreferredSizeMeters.Value;
                float previousSize = extent * DioramaScaleState.Clamp(plugin.DioramaWorldScale.Value) / units;
                if (!plugin.PlacementSaved.Value && previousSize >= 0.05f && previousSize <= 4f) preferred = previousSize;
                entrySizeGain = SpatialMath.EntryGain(plugin.EntrySizeMultiplier.Value, 0.85f);
                entryDistanceGain = SpatialMath.EntryGain(plugin.EntryDistanceMultiplier.Value, 0.8f);
                preferred *= entrySizeGain;
                float size = SpatialMath.EntryScale(extent, preferred, units);
                Vector3 offset = plugin.PlacementOffset.Value;
                offset.z *= entryDistanceGain;
                if (placeFrontRequested) offset.x = 0f;
                offset = SpatialMath.VisibleOffset(offset,
                    SafeValue(plugin.DioramaRadius.Value, 12f, 0.5f, 200f) * size / units,
                    SafeValue(plugin.DioramaHeight.Value, 12f, 0.5f, 200f) * size / units);
                Quaternion orientation = plugin.PlacementSaved.Value && SpatialMath.Finite(plugin.PlacementEuler.Value) ?
                    trackingYaw * Quaternion.Euler(plugin.PlacementEuler.Value) :
                    trackingYaw * Quaternion.Inverse(sourceCamera.transform.rotation *
                        Quaternion.AngleAxis(ComfortMath.ClampPitch(plugin.ViewPitchDegrees.Value), Vector3.right));
                placement.Place(trackingHeadPosition + trackingYaw * offset, orientation, size);
                lastScaleSetting = plugin.DioramaWorldScale.Value;
                lastPitchSetting = plugin.ViewPitchDegrees.Value;
                lastUnitsSetting = units;
                lastExtentSetting = extent;
                placeFrontRequested = false;
                panelPoseValid = false;
            }
            if (!placement.Active && !Mathf.Approximately(lastScaleSetting, plugin.DioramaWorldScale.Value))
            {
                lastScaleSetting = plugin.DioramaWorldScale.Value;
                placement.SetScale(lastScaleSetting);
            }
            if (!Mathf.Approximately(lastPitchSetting, plugin.ViewPitchDegrees.Value))
            {
                placement.Tilt(ComfortMath.ClampPitch(plugin.ViewPitchDegrees.Value) - ComfortMath.ClampPitch(lastPitchSetting));
                lastPitchSetting = plugin.ViewPitchDegrees.Value;
            }
            if (!Mathf.Approximately(lastUnitsSetting, units))
            { lastUnitsSetting = units; placement.SetScale(placement.Scale); }
            if (!Mathf.Approximately(lastExtentSetting, extent))
            { lastExtentSetting = extent; placement.SetScale(placement.Scale); }
            rigWorldScale = placement.Scale;
            rigUnitsPerMeter = DioramaMath.ViewUnits(units, rigWorldScale);
            Quaternion inverse = Quaternion.Inverse(placement.Rotation);
            trackingToWorldRotation = inverse;
            Matrix4x4 calibration = calibrationInverse.inverse;
            rigRotation = inverse * calibration.rotation;
            rigPosition = frameCylinderCenter + inverse * ((Vector3)calibration.GetColumn(3) - placement.Position) * rigUnitsPerMeter;
            if (placement.Dirty) panelPoseValid = false;
        }

        private void UpdateFullVrRig()
        {
            rigUnitsPerMeter = rigWorldScale = 1f;
            if (!fullVrView.Valid && gameplayTarget != null && trackingHeadValid && HasInputFocus)
            {
                fullVrView.Place(gameplayTarget.position,
                    Quaternion.AngleAxis(sourceCamera.transform.eulerAngles.y, Vector3.up), trackingHeadPosition, trackingYaw);
                panelPoseValid = false;
            }
            if (fullVrView.Valid)
            {
                if (gameplayTarget != null) fullVrView.FollowPlayer(gameplayTarget.position);
                Matrix4x4 calibration = calibrationInverse.inverse;
                trackingToWorldRotation = fullVrView.Rotation;
                rigRotation = fullVrView.Rotation * calibration.rotation;
                rigPosition = fullVrView.EyePosition((Vector3)calibration.GetColumn(3));
            }
            else
            {
                // Safe normal-scale fallback until the player/tracking exists.
                rigPosition = sourceCamera.transform.position;
                rigRotation = Quaternion.AngleAxis(sourceCamera.transform.eulerAngles.y, Vector3.up);
            }
        }

        private void UpdateLegacyRig()
        {
            rigPosition = sourceCamera.transform.position;
            rigRotation = sourceCamera.transform.rotation;
            frameDioramaOrigin = gameplayTarget != null ? gameplayTarget.position : rigPosition;
            frameCylinderCenter = ResolveCylinderCenter(frameDioramaOrigin);
            if (gameplayScene && plugin.IndependentDioramaView.Value)
            {
                bool hasPlayer = gameplayTarget != null;
                Vector3 pivot = frameDioramaOrigin + Vector3.up * 0.6f;
                if (!dioramaView.Valid || hasPlayer != viewHasPlayer)
                {
                    dioramaView.Latch(pivot.x, pivot.y, pivot.z, rigPosition.x, rigPosition.y, rigPosition.z,
                        rigRotation.x, rigRotation.y, rigRotation.z, rigRotation.w);
                    viewHasPlayer = hasPlayer;
                }
                dioramaView.Update(pivot.x, pivot.y, pivot.z, worldGrab.ResolveCameraScale(plugin.CameraDistanceScale.Value),
                    worldGrab.OffsetX, worldGrab.OffsetY, worldGrab.OffsetZ);
                rigPosition = new Vector3(dioramaView.PositionX, dioramaView.PositionY, dioramaView.PositionZ);
                rigRotation = new Quaternion(dioramaView.RotationX, dioramaView.RotationY, dioramaView.RotationZ, dioramaView.RotationW);
            }
            if (gameplayScene)
                rigRotation = rigRotation * Quaternion.AngleAxis(ComfortMath.ClampPitch(plugin.ViewPitchDegrees.Value), Vector3.right);
            rigUnitsPerMeter = gameplayScene ? Mathf.Clamp(plugin.WorldUnitsPerMeter.Value, 0.25f, 10f) : 1f;
            if (gameplayScene && !plugin.IndependentDioramaView.Value && gameplayTarget != null)
            {
                Vector3 pivot = gameplayTarget.position + Vector3.up * 0.6f;
                rigPosition = pivot + (rigPosition - pivot) * worldGrab.ResolveCameraScale(plugin.CameraDistanceScale.Value);
            }
            if (gameplayScene && !plugin.IndependentDioramaView.Value)
                rigPosition += new Vector3(worldGrab.OffsetX, worldGrab.OffsetY, worldGrab.OffsetZ);
            float size = gameplayScene ? dioramaScale.Resolve(plugin.DioramaWorldScale.Value) : 1f;
            if (!Mathf.Approximately(size, rigWorldScale)) panelPoseValid = false;
            rigWorldScale = size;
            if (gameplayScene)
            {
                // Inverse of a uniform world-size transform about the cylinder
                // center. Its physical placement is invariant under size changes;
                // eye/IPD translation stays 1:1, never attached to the diorama.
                rigPosition = new Vector3(
                    DioramaMath.ScaleViewAxis(frameCylinderCenter.x, rigPosition.x, size),
                    DioramaMath.ScaleViewAxis(frameCylinderCenter.y, rigPosition.y, size),
                    DioramaMath.ScaleViewAxis(frameCylinderCenter.z, rigPosition.z, size));
                rigUnitsPerMeter = DioramaMath.ViewUnits(plugin.WorldUnitsPerMeter.Value, size);
            }
        }

        private Vector3 ResolveCylinderCenter(Vector3 origin)
        {
            Vector3 center = origin;
            if (!plugin.IndependentDioramaView.Value)
            {
                Vector3 gameCameraPosition = sourceCamera.transform.position;
                if (!dioramaAnchorValid)
                {
                    dioramaAnchor = origin;
                    dioramaCameraAnchor = gameCameraPosition;
                    dioramaAnchorValid = gameplayTarget != null;
                }
                center = dioramaAnchor;
                if (plugin.DioramaFollowCamera.Value)
                    center += gameCameraPosition - dioramaCameraAnchor;
                else if (plugin.DioramaFollowPlayer.Value && gameplayTarget != null)
                    center = origin;
            }
            return center + Vector3.up * SafeValue(plugin.DioramaCenterHeight.Value, 3f, -200f, 200f);
        }

        private void UpdateWorldGrab()
        {
            bool held = CanGrabWorld && inputBridge != null && inputBridge.BothGripsHeld &&
                placement.Valid && (settingsMenu == null || !settingsMenu.Visible);
            if (!held) { placement.Stop(); return; }
            uint left = inputBridge.LeftDevice;
            uint right = inputBridge.RightDevice;
            if (!IsControllerTracked(right) || !IsControllerTracked(left)) { placement.Stop(); return; }
            Matrix4x4 l = ToUnityMatrix(renderPoses[left].mDeviceToAbsoluteTracking);
            Matrix4x4 r = ToUnityMatrix(renderPoses[right].mDeviceToAbsoluteTracking);
            placement.Update(true, true, (Vector3)l.GetColumn(3), l.rotation, (Vector3)r.GetColumn(3), r.rotation,
                plugin.DioramaMoveSensitivity.Value, plugin.DioramaRotationSensitivity.Value);
        }

        private void SavePlacementSettings()
        {
            if (!plugin.DioramaEnabled.Value) return;
            if (!placement.Valid || placement.Active || !placement.Dirty || !trackingHeadValid) return;
            // ConfigEntry changes allocate; persist only after placement input
            // is released, never continuously while the stick is held.
            if (inputBridge != null && inputBridge.DioramaStick.sqrMagnitude > 0f) return;
            float units = SafeValue(plugin.WorldUnitsPerMeter.Value, 1f, 0.25f, 10f);
            float extent = Mathf.Max(2f * SafeValue(plugin.DioramaRadius.Value, 12f, 0.5f, 200f), SafeValue(plugin.DioramaHeight.Value, 12f, 0.5f, 200f));
            Vector3 offset = Quaternion.Inverse(trackingYaw) * (placement.Position - trackingHeadPosition);
            offset.z = SpatialMath.EntryBase(offset.z, entryDistanceGain);
            plugin.PlacementOffset.Value = offset;
            plugin.PlacementEuler.Value = (Quaternion.Inverse(trackingYaw) * placement.Rotation).eulerAngles;
            plugin.PreferredSizeMeters.Value = SpatialMath.EntryBase(extent * placement.Scale / units, entrySizeGain);
            plugin.DioramaWorldScale.Value = placement.Scale;
            lastScaleSetting = placement.Scale;
            plugin.PlacementSaved.Value = true;
            plugin.Config.Save();
            placement.Saved();
        }

        private void UpdateDioramaStick()
        {
            if (!initialized || !gameplayScene || levelIntroFlat || !HasInputFocus || !trackingHeadValid || inputBridge == null) return;
            if (!plugin.DioramaEnabled.Value)
            {
                fullVrView.MoveStick(inputBridge.DioramaStick, trackingHeadPosition, trackingYaw, Time.unscaledDeltaTime,
                    inputBridge.DioramaTurnSpeed, inputBridge.DioramaMoveSpeed);
                return;
            }
            placement.MoveStick(inputBridge.DioramaStick, trackingHeadPosition, Time.unscaledDeltaTime,
                inputBridge.DioramaTurnSpeed, inputBridge.DioramaMoveSpeed);
        }

        internal void PlaceInFront()
        {
            if (plugin.DioramaEnabled.Value)
            { placement.Stop(); SavePlacementSettings(); placement.Reset(); placeFrontRequested = true; }
            fullVrView.Reset();
            if (inputBridge != null) inputBridge.RequireGripRelease();
            panelPoseValid = false;
            if (settingsMenu != null) settingsMenu.ResetAnchor();
        }

        internal float PlacementDistance { get { return placement.Valid ? Vector3.Distance(placement.Position, trackingHeadPosition) : 2f; } }
        internal void AdjustPlacementDistance(float delta)
        {
            if (!placement.Valid) return;
            Vector3 direction = placement.Position - trackingHeadPosition;
            float distance = direction.magnitude;
            if (distance < 0.0001f) direction = trackingYaw * Vector3.forward;
            else direction /= distance;
            placement.Place(trackingHeadPosition + direction * Mathf.Clamp(distance + delta, 0.25f, 10f), placement.Rotation, placement.Scale);
        }

        // Called by sparse maintenance or a menu event, not on every rendered
        // frame. BepInEx ConfigEntry setters allocate notification objects.
        internal void CommitWorldGrabSettings(bool stop)
        {
            if (stop) placement.Stop();
            SavePlacementSettings();
            if (stop) { worldGrab.Stop(); dioramaScale.Stop(); }
            if (!dioramaScale.Active && dioramaScale.HasOverride)
            {
                if (!Mathf.Approximately(plugin.DioramaWorldScale.Value, dioramaScale.Scale))
                {
                    plugin.DioramaWorldScale.Value = dioramaScale.Scale;
                    plugin.Config.Save();
                }
                dioramaScale.ClearOverride();
            }
            if (worldGrab.Active || !worldGrab.HasCameraOverride) return;
            if (!Mathf.Approximately(plugin.CameraDistanceScale.Value, worldGrab.CameraScale))
            {
                plugin.CameraDistanceScale.Value = worldGrab.CameraScale;
                plugin.Config.Save();
            }
            worldGrab.ClearCameraOverride();
        }

        private void RenderFlatScreen()
        {
            if (!flatPanel.activeSelf)
                flatPanel.SetActive(true);

            if (Time.unscaledTime + 0.0001f >= nextFlatCapture)
            {
                RenderTexture capture = levelIntroFlat ? cinemaTexture : flatTexture;
                nextFlatCapture = RenderBudget.NextCapture(Time.unscaledTime, nextFlatCapture, Mathf.Clamp(plugin.MenuCaptureRate.Value, 1, 72));
                sourceCamera.targetTexture = capture;
                sourceCamera.stereoTargetEye = StereoTargetEyeMask.None;
                sourceCamera.cullingMask = sourceMask & ~(PanelMask | UiCaptureMask);
                try { sourceCamera.Render(); capture.GenerateMips(); }
                finally { RestoreSourceRenderSettings(); }
            }

            RenderEye(EVREye.Eye_Left, leftCamera, TrackingEye(EVREye.Eye_Left), true);
            RenderEye(EVREye.Eye_Right, rightCamera, TrackingEye(EVREye.Eye_Right), true);
        }

        private void RenderStereoGameplay()
        {
            if (flatPanel.activeSelf)
                flatPanel.SetActive(false);
            RenderEye(EVREye.Eye_Left, leftCamera, TrackingEye(EVREye.Eye_Left), false);
            RenderEye(EVREye.Eye_Right, rightCamera, TrackingEye(EVREye.Eye_Right), false);
        }

        private Matrix4x4 TrackingEye(EVREye eye)
        {
            // Use the runtime's exact absolute eye from this submitted snapshot.
            // XR no longer does head^-1 * eye followed by head * that result.
            if (UsesOpenXr) return ToUnityMatrix(eye == EVREye.Eye_Left ? xrFrame.LeftEye : xrFrame.RightEye);
            Matrix4x4 head = ToUnityMatrix(renderPoses[OpenVR.k_unTrackedDeviceIndex_Hmd].mDeviceToAbsoluteTracking);
            return head * (eye == EVREye.Eye_Left ? leftEyeToHead : rightEyeToHead);
        }

        private void RenderEye(EVREye eye, Camera camera, Matrix4x4 trackingEye, bool panelOnly)
        {
            // A 2D panel does not need the game's scene depth/occlusion passes.
            // CopyFrom would inherit those settings even with a panel-only mask.
            if (!panelOnly) camera.CopyFrom(sourceCamera);
            camera.enabled = false;
            camera.stereoTargetEye = StereoTargetEyeMask.None;
            RenderTexture resolved = eye == EVREye.Eye_Left ? leftTexture : rightTexture;
            RenderTexture multisampled = eye == EVREye.Eye_Left ? leftMsaaTexture : rightMsaaTexture;
            if (panelOnly) multisampled = null;
            camera.targetTexture = multisampled != null ? multisampled : resolved;
            camera.allowHDR = false;
            camera.allowMSAA = multisampled != null;
            camera.renderingPath = RenderingPath.Forward;
            camera.orthographic = false;
            bool originalBackground = !panelOnly && (stereoMenuScene || (gameplayScene && !plugin.DioramaEnabled.Value));
            camera.clearFlags = originalBackground ? sourceCamera.clearFlags : CameraClearFlags.SolidColor;
            camera.backgroundColor = originalBackground ? sourceCamera.backgroundColor : passthroughRequested ? Color.clear :
                DioramaMath.GreenBackground(plugin.VoidBackground.Value) ? Color.green : Color.black;
            camera.cullingMask = panelOnly ? PanelMask : (sourceMask & ~(UiCaptureMask | PanelMask));
            if (stereoMenuScene) camera.useOcclusionCulling = false;
            if (panelOnly)
            {
                camera.depthTextureMode = DepthTextureMode.None;
                camera.useOcclusionCulling = false;
            }

            if (gameplayScene && !levelIntroFlat && !plugin.DioramaEnabled.Value && fullVrView.Valid)
            {
                camera.transform.position = fullVrView.EyePosition((Vector3)trackingEye.GetColumn(3));
                camera.transform.rotation = fullVrView.Rotation * trackingEye.rotation;
            }
            else if (gameplayScene && !levelIntroFlat && plugin.DioramaEnabled.Value && placement.Valid && gameplayTarget != null)
            {
                camera.transform.position = SpatialMath.EyePosition(frameCylinderCenter, placement.Position,
                    trackingToWorldRotation, (Vector3)trackingEye.GetColumn(3), rigUnitsPerMeter);
                camera.transform.rotation = trackingToWorldRotation * trackingEye.rotation;
            }
            else
            {
                Matrix4x4 relativeEye = calibrationInverse * trackingEye;
                camera.transform.position = rigPosition + rigRotation * ((Vector3)relativeEye.GetColumn(3) * rigUnitsPerMeter);
                camera.transform.rotation = rigRotation * relativeEye.rotation;
            }
            float near = Mathf.Max(0.005f, Mathf.Min(sourceCamera.nearClipPlane / rigWorldScale, 0.03f * rigUnitsPerMeter));
            float far = Mathf.Max(near + 0.1f, sourceCamera.farClipPlane / Mathf.Min(rigWorldScale, 1f));
            camera.nearClipPlane = near;
            camera.farClipPlane = far;
            camera.projectionMatrix = UsesOpenXr ?
                (eye == EVREye.Eye_Left ? xrFrame.LeftFov : xrFrame.RightFov).Projection(near, far) :
                ToUnityProjection(system.GetProjectionMatrix(eye, near, far));
            if (diagnosticsEnabled && stereoMenuDiagnosticPending && stereoMenuScene && !panelOnly && eye == EVREye.Eye_Left)
            {
                // Diagnostics only: one line per stereo-menu entry/recenter, never per frame.
                stereoMenuDiagnosticPending = false;
                LogStereoMenuDiagnostic(camera, trackingEye);
            }
            bool cylinder =FullVrViewState.ClipWorld(gameplayScene, panelOnly, NativeBridge.ShaderClipReady, plugin.DioramaEnabled.Value);
            bool liquidVisible = !panelOnly && plugin.LiquidDepthFix.Value &&
                (!plugin.CullOutsideDiorama.Value ? liquidDepth.NeedsDepth : liquidDepth.Visible(camera,
                    cylinder && plugin.DioramaEnabled.Value && CylinderProbeMode == 0, frameCylinderCenter,
                    SafeValue(plugin.DioramaRadius.Value, 12f, 0.5f, 200f), SafeValue(plugin.DioramaHeight.Value, 12f, 0.5f, 200f) * 0.5f));
            // CopyFrom restored the game's own depth requirements: only our
            // extra depth bit is conditional. Never strip game-requested modes.
            if (liquidVisible) camera.depthTextureMode |= DepthTextureMode.Depth;
            if (eye == EVREye.Eye_Left) { lastLeftLiquidDepth = liquidVisible; if (liquidVisible) leftDepthFrames++; }
            else { lastRightLiquidDepth = liquidVisible; if (liquidVisible) rightDepthFrames++; }
            bool directHud = !panelOnly && plugin.DirectHudOverlay.Value && hudMesh != null &&
                (settingsMenu == null || !settingsMenu.Visible);
            ConfigureHudCommands(eye, directHud, cylinder);
            if (!panelOnly) ProfileMark(eye == EVREye.Eye_Left ? 2 : 4);
            if (cylinder)
            {
                // The inverse actual GPU view-projection includes all existing
                // world translation, rotation, pitch, zoom and VR unit scale.
                // Reconstruct directly into original-game cylinder coordinates.
                Vector3 origin = frameDioramaOrigin;
                Vector3 center = frameCylinderCenter;
                Matrix4x4 pixelToClip = Matrix4x4.identity;
                pixelToClip.m00 = 2f / resolved.width;
                pixelToClip.m03 = -1f;
                pixelToClip.m11 = -2f / resolved.height;
                pixelToClip.m13 = 1f;
                Matrix4x4 viewProjection = GL.GetGPUProjectionMatrix(camera.projectionMatrix, true) * camera.worldToCameraMatrix;
                NativeBridge.ClipParameters parameters = new NativeBridge.ClipParameters();
                parameters.ScreenToCylinder = Matrix4x4.Translate(-center) * viewProjection.inverse * pixelToClip;
                if (diagnosticsEnabled && CylinderProbeMode == 0 && plugin.DioramaEnabled.Value && !cylinderDiagnosticPrepared)
                {
                    diagnosticView = camera.worldToCameraMatrix;
                    diagnosticProjection = GL.GetGPUProjectionMatrix(camera.projectionMatrix, true);
                    diagnosticCenter = center;
                    diagnosticRect = camera.pixelRect;
                    cylinderDiagnosticPrepared = true;
                }
                if (diagnosticsEnabled)
                {
                    lastCylinderCenter = center;
                    lastCylinderDeterminant = viewProjection.determinant;
                    Vector4 pivotClip = viewProjection * new Vector4(origin.x, origin.y, origin.z, 1f);
                    Vector4 pivotPixel = new Vector4(.5f * resolved.width * (pivotClip.x + pivotClip.w),
                        .5f * resolved.height * (pivotClip.w - pivotClip.y), pivotClip.z, pivotClip.w);
                    Vector4 pivotLocal = parameters.ScreenToCylinder * pivotPixel;
                    lastCylinderPivotLocal = new Vector3(pivotLocal.x, pivotLocal.y, pivotLocal.z) / pivotLocal.w;
                }
                float radius = SafeValue(plugin.DioramaRadius.Value, 12f, 0.5f, 200f);
                float cylinderHeight = SafeValue(plugin.DioramaHeight.Value, 12f, 0.5f, 200f);
                float feather = DioramaMath.FeatherWidth(plugin.DioramaFeatherWidth.Value, radius, cylinderHeight);
                parameters.Limits = new Vector4(radius * radius, cylinderHeight * 0.5f, feather,
                    !UsesOpenXr && DioramaMath.GreenBackground(plugin.VoidBackground.Value) ? 1f : 0f);
                if (CylinderProbeMode == 2)
                    parameters.Limits = new Vector4(float.MaxValue, float.MaxValue, 0f, 0f);
                if (CylinderProbeMode == 3)
                {
                    // Every rasterized eye pixel is inside this known-finite
                    // screen-space cylinder. No inverse projection/anchor involved.
                    parameters.ScreenToCylinder = pixelToClip;
                    parameters.Limits = new Vector4(4f, 4f, 0f, 0f);
                }
                camera.cullingMask = sourceMask & ~(UiCaptureMask | PanelMask);
                // Arbitrary views around the diorama must not use QV's baked
                // isometric occlusion assumptions. Depth generation stays per-eye.
                camera.useOcclusionCulling = false;
                if (CylinderProbeMode == 1) camera.Render();
                else
                {
                    NativeBridge.QVVR_SetClipParameters(currentPoseSlot, (int)eye, ref parameters);
                    NativeBridge.QVVR_SetCylinderCapOptions(currentPoseSlot, (int)eye,
                        plugin.BlackCutSurfaces.Value && CylinderProbeMode == 0 && plugin.DioramaEnabled.Value ? 1 : 0,
                        SystemInfo.usesReversedZBuffer ? 1 : 0, UsesOpenXr ? 1 : 0);
                    if (plugin.CullOutsideDiorama.Value)
                        NativeBridge.QVVR_SetCapCullVolume(currentPoseSlot, (int)eye, center.x, center.y, center.z, radius, cylinderHeight * 0.5f);
                    GL.IssuePluginEvent(renderEvent, NativeBridge.ClipEventBase + currentPoseSlot * 4 + (int)eye);
                    try { camera.Render(); }
                    finally { GL.IssuePluginEvent(renderEvent, NativeBridge.EndClipEvent); }
                }
            }
            else camera.Render();
            if (!panelOnly && !directHud)
            {
                ProfileMark(eye == EVREye.Eye_Left ? 3 : 5);
                ProfileMark(eye == EVREye.Eye_Left ? 6 : 8);
                RenderPanelOverlay(camera);
                ProfileMark(eye == EVREye.Eye_Left ? 7 : 9);
            }
            if (multisampled != null) multisampled.ResolveAntiAliasedSurface(resolved);
            screenFade.Render(resolved);
        }

        private void LogStereoMenuDiagnostic(Camera camera, Matrix4x4 trackingEye)
        {
            Vector3 hub = Vector3.zero;
            bool hasHub = introMenus != null && introMenus.TryGetHubAnchor(out hub);
            Matrix4x4 p = camera.projectionMatrix;
            Vector3 relative = (Vector3)(calibrationInverse * trackingEye).GetColumn(3);
            Plugin.Log.LogInfo(string.Format(System.Globalization.CultureInfo.InvariantCulture,
                "QVVR stereo menu diagnostic: backend={0} state={1} | source {2} pos={3} rot={4} ortho={5} size={6:F2} fov={7:F1} near={8:F3} far={9:F1} clear={10} bg={11} mask=0x{12:X8} depth={13} | hub={14} {15} scale={16:F2} | rig pos={17} rot={18} units={19:F2} | eye pos={20} fwd={21} rel={22} near={23:F3} far={24:F1} clear={25} mask=0x{26:X8} msaa={27} target={28}x{29} | proj m00={30:F3} m11={31:F3} m22={32:F4} m23={33:F4} m32={34:F1} reversedZ={35}",
                UsesOpenXr ? "OpenXR" : "OpenVR", introPresentation,
                CameraSelector.PathOf(sourceCamera.transform), sourceCamera.transform.position.ToString("F2"), sourceCamera.transform.eulerAngles.ToString("F1"),
                sourceCamera.orthographic, sourceCamera.orthographicSize, sourceCamera.fieldOfView, sourceCamera.nearClipPlane, sourceCamera.farClipPlane,
                sourceCamera.clearFlags, sourceCamera.backgroundColor, sourceMask, sourceCamera.depth,
                hasHub, hub.ToString("F2"), plugin.IntroHubDistanceScale.Value,
                rigPosition.ToString("F2"), rigRotation.eulerAngles.ToString("F1"), rigUnitsPerMeter,
                camera.transform.position.ToString("F2"), camera.transform.forward.ToString("F2"), relative.ToString("F2"),
                camera.nearClipPlane, camera.farClipPlane, camera.clearFlags, camera.cullingMask,
                camera.allowMSAA, camera.targetTexture != null ? camera.targetTexture.width : 0, camera.targetTexture != null ? camera.targetTexture.height : 0,
                p.m00, p.m11, p.m22, p.m23, p.m32, SystemInfo.usesReversedZBuffer));
        }

        private static void RenderPanelOverlay(Camera camera)
        {
            // Sprites/Default has a fixed depth test, so setting _ZTest on its
            // material cannot guarantee visibility. Keep world color/alpha,
            // clear only depth, then draw HUD/settings last (also without clip).
            camera.clearFlags = CameraClearFlags.Depth;
            camera.cullingMask = PanelMask;
            camera.depthTextureMode = DepthTextureMode.None;
            camera.useOcclusionCulling = false;
            camera.Render();
        }

        private void ProfileMark(int marker)
        {
            if (detailedGpuTimings) GL.IssuePluginEvent(renderEvent, NativeBridge.ProfileEventBase + marker);
        }

        private void SampleDioramaStability()
        {
            if (!gameplayScene || !plugin.DioramaEnabled.Value || levelIntroFlat || gameplayTarget == null || !placement.Valid || placement.Active ||
                (inputBridge != null && inputBridge.DioramaStick.sqrMagnitude > 0f) ||
                (settingsMenu != null && settingsMenu.Visible))
            { stabilitySampleValid = false; return; }
            Vector3 pivot = gameplayTarget.position;
            if (stabilitySampleValid)
            {
                double step = (pivot - stabilityPivot).magnitude * 1000.0 / rigUnitsPerMeter;
                maxPivotStepMm = Math.Max(maxPivotStepMm, step);
                maxPlacementStepMm = Math.Max(maxPlacementStepMm, (placement.Position - stabilityPlacement).magnitude * 1000.0);
                maxPlacementTurnDegrees = Math.Max(maxPlacementTurnDegrees, Quaternion.Angle(placement.Rotation, stabilityRotation));
                stabilitySamples++;
            }
            stabilityPivot = pivot; stabilityPlacement = placement.Position; stabilityRotation = placement.Rotation;
            stabilitySampleValid = true;
        }
        private CommandBuffer ProfileCommands(string name, int marker)
        {
            CommandBuffer commands = new CommandBuffer { name = name };
            commands.IssuePluginEvent(renderEvent, NativeBridge.ProfileEventBase + marker);
            return commands;
        }
        private void ConfigureHudCommands(EVREye eye, bool direct, bool cylinder)
        {
            CommandBuffer commands = eye == EVREye.Eye_Left ? leftHudCommands : rightHudCommands;
            commands.Clear();
            if (!direct) return;
            if (detailedGpuTimings) commands.IssuePluginEvent(renderEvent, NativeBridge.ProfileEventBase + (eye == EVREye.Eye_Left ? 3 : 5));
            // Stop native cylinder shader interception BEFORE binding the HUD
            // material, including when the camera has no world geometry.
            if (cylinder) commands.IssuePluginEvent(renderEvent, NativeBridge.EndClipEvent);
            if (detailedGpuTimings) commands.IssuePluginEvent(renderEvent, NativeBridge.ProfileEventBase + (eye == EVREye.Eye_Left ? 6 : 8));
            if (uiPanel.activeSelf)
            {
                commands.ClearRenderTarget(true, false, Color.clear);
                commands.DrawMesh(hudMesh, uiPanel.transform.localToWorldMatrix, uiMaterial, 0, -1);
            }
            if (detailedGpuTimings) commands.IssuePluginEvent(renderEvent, NativeBridge.ProfileEventBase + (eye == EVREye.Eye_Left ? 7 : 9));
        }

        private static float SafeValue(float value, float fallback, float min, float max)
        {
            return float.IsNaN(value) || float.IsInfinity(value) ? fallback : Mathf.Clamp(value, min, max);
        }

        private void RestoreSourceRenderSettings()
        {
            if (sourceCamera == null)
                return;
            sourceCamera.targetTexture = sourceTarget;
            sourceCamera.stereoTargetEye = sourceStereo;
            sourceCamera.cullingMask = sourceMask;
            sourceCamera.enabled = false;
        }

        private void RedirectOverlayCanvases()
        {
            if (discoveredCanvases == null || Time.unscaledTime >= nextCanvasDiscovery)
            {
                discoveredCanvases = FindObjectsOfType<Canvas>();
                nextCanvasDiscovery = Time.unscaledTime + 1f;
            }
            Canvas[] found = discoveredCanvases;
            bool cacheScan = uiCaptureCache.BeginMaintenance(Time.unscaledTime, plugin.AdaptiveUiCapture.Value, plugin.LightweightUiMaintenance.Value);
            dialogHudLayout.BeginScan();
            for (int index = 0; index < found.Length; index++)
            {
                Canvas canvas = found[index];
                if (canvas == null || canvas.rootCanvas != canvas)
                    continue;

                CanvasState state = FindCanvasState(canvas);
                if (MenuScenePolicy.CaptureCanvas(introScene, (int)canvas.renderMode, canvas.worldCamera == sourceCamera))
                {
                    if (state == null)
                    {
                        state = new CanvasState
                        {
                            Canvas = canvas,
                            RenderMode = canvas.renderMode,
                            WorldCamera = canvas.worldCamera,
                            PlaneDistance = canvas.planeDistance
                        };
                        canvasStates.Add(state);
                    }
                    if (canvas.renderMode != RenderMode.ScreenSpaceCamera) canvas.renderMode = RenderMode.ScreenSpaceCamera;
                }

                if (state != null)
                {
                    IsolateCanvasLayers(canvas);
                    hudLayoutInset.Apply(canvas, MenuScenePolicy.UseGameplayHud(gameplayScene && !levelIntroFlat, MenuScenePolicy.RenderStereoMenu(stereoMenuScene, levelIntroFlat)) ? plugin.GameplayHudInset.Value : 0f);
                    if (canvas.worldCamera != uiCaptureCamera) canvas.worldCamera = uiCaptureCamera;
                    if (canvas.planeDistance != CanvasPlane) canvas.planeDistance = CanvasPlane;
                    dialogHudLayout.Watch(canvas);
                    if (cacheScan && !uiCaptureCache.Failed)
                    {
                        try { uiCaptureCache.Watch(canvas); }
                        catch (Exception exception)
                        {
                            uiCaptureCache.DisableReuse();
                            Plugin.Log.LogWarning("QVVR optional UI cache disabled for this session; normal capture and scene maintenance preserved: " + exception);
                        }
                    }
                }
            }
            if (cacheScan && !uiCaptureCache.Failed)
            {
                try { uiCaptureCache.EndMaintenance(Time.unscaledTime, plugin.LightweightUiMaintenance.Value); }
                catch (Exception exception)
                {
                    uiCaptureCache.DisableReuse();
                    Plugin.Log.LogWarning("QVVR optional UI cache disabled; normal capture retained: " + exception);
                }
            }
        }

        private void IsolateCanvasLayers(Canvas canvas)
        {
            canvasTransforms.Clear();
            canvas.GetComponentsInChildren<Transform>(true, canvasTransforms);
            for (int index = 0; index < canvasTransforms.Count; index++)
            {
                GameObject obj = canvasTransforms[index].gameObject;
                int id = obj.GetInstanceID();
                UiLayerState existing;
                if (!uiLayers.TryGetValue(id, out existing) || existing.Object == null)
                    uiLayers[id] = new UiLayerState { Object = obj, OriginalLayer = obj.layer };
                if (obj.layer != UiCaptureLayer) obj.layer = UiCaptureLayer;
            }
        }

        private CanvasState FindCanvasState(Canvas canvas)
        {
            for (int index = 0; index < canvasStates.Count; index++)
            {
                if (canvasStates[index].Canvas == canvas)
                    return canvasStates[index];
            }
            return null;
        }

        private void RestoreCanvases()
        {
            uiCaptureCache.Clear();
            discoveredCanvases = null;
            dialogHudLayout.Clear(); centeredDialogVisible = false;
            hudLayoutInset.Clear();
            for (int index = 0; index < canvasStates.Count; index++)
            {
                CanvasState state = canvasStates[index];
                if (state.Canvas == null)
                    continue;
                state.Canvas.renderMode = state.RenderMode;
                state.Canvas.worldCamera = state.WorldCamera;
                state.Canvas.planeDistance = state.PlaneDistance;
            }
            canvasStates.Clear();
            foreach (UiLayerState state in uiLayers.Values)
                if (state.Object != null) state.Object.layer = state.OriginalLayer;
            uiLayers.Clear();
            canvasTransforms.Clear();
            nextUiCapture = nextFlatCapture = 0f;
        }

        private void CheckSubmitState()
        {
            if (Time.unscaledTime < nextSubmitCheck)
                return;
            nextSubmitCheck = Time.unscaledTime + 1f;

            int xrError = 0;
            int xrStatus = NativeBridge.QVVR_GetOpenXrStatus(ref xrError);
            if (xrStatus != lastXrStatus)
            {
                lastXrStatus = xrStatus;
                Plugin.Log.LogInfo("QVVR compositor: " + (xrStatus > 0 ? "Exclusive OpenXR ALPHA_BLEND status=" + xrStatus : "OpenVR opaque-background fallback") + "; XR result=" + xrError);
            }
            uint patched = 0, rejected = 0, unknown = 0, depthOnly = 0;
            NativeBridge.QVVR_GetClipStats(ref patched, ref rejected, ref unknown, ref depthOnly);
            if (rejected != lastRejectedShaders || unknown != lastUnknownShaders)
            {
                lastRejectedShaders = rejected; lastUnknownShaders = unknown;
                Plugin.Log.LogWarning("QVVR cylinder shaders: patched=" + patched + ", rejected=" + rejected + ", uncaptured non-null binds=" + unknown + ", clipped depth-only binds=" + depthOnly + ". Unsupported material draws are hidden; legitimate depth-only passes are preserved inside the cylinder.");
            }

            ulong frames = 0;
            int leftResult = 0;
            int rightResult = 0;
            NativeBridge.QVVR_GetSubmitState(ref frames, ref leftResult, ref rightResult);
            if (frames != lastSubmittedFrames)
            {
                if (lastSubmittedFrames == 0)
                    Plugin.Log.LogInfo("First frame submitted from Unity's graphics thread.");
                lastSubmittedFrames = frames;
            }
            if ((leftResult != 0 || rightResult != 0) && (leftResult != -1000 || rightResult != -1000))
                Plugin.Log.LogWarning("OpenVR native submit result: left=" + leftResult + ", right=" + rightResult);
        }

        // Sparse diagnostics outside LateUpdate: single-frame samples, NOT
        // session means/percentiles. Skip transition frames to label mode safely.
        private void LogFrameTiming()
        {
            bool verbose = diagnosticsEnabled || detailedGpuTimings;
            if (diagnosticsEnabled && cylinderDiagnosticPrepared && !cylinderDiagnosticWritten)
            {
                string path = Path.Combine(Paths.PluginPath, "QVVR", "cylinder-diagnostic.bin");
                if (NativeBridge.QVVR_WriteClipDiagnostic(path) == 1)
                {
                    cylinderDiagnosticWritten = true;
                    Plugin.Log.LogInfo("QVVR one-shot GPU constant-buffer diagnostic saved: " + path +
                        "; center=" + diagnosticCenter + "; pixel rect=" + diagnosticRect +
                        "; expected view:\n" + diagnosticView.ToString("R") +
                        "; expected GPU projection:\n" + diagnosticProjection.ToString("R"));
                    Renderer targetRenderer = gameplayTarget != null ? gameplayTarget.GetComponentInChildren<Renderer>() : null;
                    if (targetRenderer != null)
                        Plugin.Log.LogInfo("QVVR target renderer world bounds: center=" + targetRenderer.bounds.center + ", size=" + targetRenderer.bounds.size);
                }
            }
            if (verbose && gameplayScene && plugin.DioramaEnabled.Value && NativeBridge.ShaderClipReady)
            {
                uint patched = 0, rejected = 0, unknown = 0, depthOnly = 0;
                NativeBridge.QVVR_GetClipStats(ref patched, ref rejected, ref unknown, ref depthOnly);
                uint materials = 0, otherContexts = 0;
                NativeBridge.QVVR_GetClipBindingStats(ref materials, ref otherContexts);
                Plugin.Log.LogInfo("QVVR cylinder coverage: patched=" + patched + ", rejected=" + rejected +
                    ", uncaptured non-null binds=" + unknown + ", clipped depth-only binds=" + depthOnly +
                    ", material binds=" + materials + ", other context binds=" + otherContexts);
                Plugin.Log.LogInfo("QVVR cylinder probe=" + CylinderProbeMode + ", center=" + lastCylinderCenter +
                    ", reconstructed pivot local=" + lastCylinderPivotLocal + ", projection determinant=" + lastCylinderDeterminant);
                Plugin.Log.LogInfo("QVVR liquid depth: enabled=" + plugin.LiquidDepthFix.Value +
                    ", cached=" + liquidDepth.Count + ", active=" + liquidDepth.NeedsDepth);
                Plugin.Log.LogInfo("QVVR optimization counters: outside meshes=" + visibility.LastHidden + "/" + visibility.Count +
                    ", liquid depth needed L/R=" + lastLeftLiquidDepth + "/" + lastRightLiquidDepth +
                    ", cumulative depth eyes=" + leftDepthFrames + "/" + rightDepthFrames +
                    ", UI captures/reuses=" + uiCaptureCache.Captures + "/" + uiCaptureCache.Reuses);
                Plugin.Log.LogInfo("QVVR UI cache continuous reason=" + uiCaptureCache.ContinuousReason +
                    " (0=static, 1=failed, 2=custom/unknown/time-driven material, 3=active Animator); adaptive=" + plugin.AdaptiveUiCapture.Value);
                if (detailedGpuTimings)
                    Plugin.Log.LogInfo(string.Format("QVVR GPU phases (delayed sample, ms): UI={0:F2}, world L/R={1:F2}/{2:F2}, HUD L/R={3:F2}/{4:F2}, XR copy span={5:F2}, depth L/R={6:F2}/{7:F2}. Depth is included in world; zero means absent/unavailable. Do not sum with CPU.",
                        NativeBridge.QVVR_GetGpuPhaseTime(0), NativeBridge.QVVR_GetGpuPhaseTime(1), NativeBridge.QVVR_GetGpuPhaseTime(2),
                        NativeBridge.QVVR_GetGpuPhaseTime(3), NativeBridge.QVVR_GetGpuPhaseTime(4), NativeBridge.QVVR_GetGpuPhaseTime(5),
                        NativeBridge.QVVR_GetGpuPhaseTime(6), NativeBridge.QVVR_GetGpuPhaseTime(7)));
                if (plugin.BlackCutSurfaces.Value)
                {
                    uint available = 0, registered = 0, replayed = 0, composed = 0;
                    NativeBridge.QVVR_GetCapStats(ref available, ref registered, ref replayed, ref composed);
                    uint bounded = 0, skipped = 0;
                    NativeBridge.QVVR_GetCapCullStats(ref bounded, ref skipped);
                    Plugin.Log.LogInfo("QVVR black caps: available=" + available + ", registered buffers=" + registered +
                        ", total volume draws=" + replayed + ", total eye composites=" + composed +
                        ", bounded static buffers=" + bounded + ", live skip buffers this stereo frame=" + cutSurfaces.LastSkipped +
                        ", cumulative pruned replays=" + skipped);
                }
                Plugin.Log.LogInfo("QVVR placement: physical layout=" + placement.Valid +
                    ", player=" + (gameplayTarget != null) + ", right drag=" + (inputBridge != null && inputBridge.RightGripGrabHeld) +
                    ", both=" + (inputBridge != null && inputBridge.BothGripsHeld) + ", active=" + placement.Active +
                    ", right tracked=" + (inputBridge != null && IsControllerTracked(inputBridge.RightDevice)) +
                    ", physical scale=" + rigWorldScale + ", position=" + placement.Position +
                    ", rotation=" + placement.Rotation.eulerAngles + ", saved=" + plugin.PlacementSaved.Value);
            }
            int error = 0;
            if (NativeBridge.QVVR_GetOpenXrStatus(ref error) > 0)
            {
                OpenXrPacing pacing = new OpenXrPacing();
                NativeBridge.QVVR_ReadXrPacing(ref pacing);
                Plugin.Log.LogInfo(string.Format("QVVR XR submission cadence window: intervals={0}, average={1:F2} ms, p95 bucket upper={2:F2} ms, max={3:F2} ms, runtime period={4:F2} ms, long gaps (>1.5 period)={5}, max prepare-to-copy={6:F2} ms, max copy/EndFrame={7:F2} ms. Submission timing, NOT display drops/FPS or pure GPU time.",
                    pacing.Intervals, pacing.AverageMs, pacing.P95UpperMs, pacing.MaximumMs, pacing.PeriodMs, pacing.LongGaps, pacing.MaximumQueueAgeMs, pacing.MaximumCopySubmitMs));
                if (stabilitySamples != 0)
                    Plugin.Log.LogInfo(string.Format("QVVR ungrabbed diorama stability window: samples={0}, max raw player-follow step={1:F4} physical mm, max placement step={2:F4} mm, max placement turn={3:F6} deg. Player movement is expected; compare while idle. HMD poses are not filtered.",
                        stabilitySamples, maxPivotStepMm, maxPlacementStepMm, maxPlacementTurnDegrees));
                stabilitySamples = 0; maxPivotStepMm = maxPlacementStepMm = maxPlacementTurnDegrees = 0;
                if (verbose) Plugin.Log.LogInfo("QVVR XR pacing counters (cumulative): queued stereo frames=" + xrQueuedFrames +
                    ", busy/skipped Unity frames=" + xrBusyUnityFrames + ", no-render/tracking misses=" + xrTrackingMisses);
                Plugin.Log.LogInfo(string.Format("QVVR maintenance window: max CPU={0:F2} ms, post-submit={1}, previous log batch={2:F2} ms. Maintenance excludes logging; elapsed wall-clock times, not profiler CPU usage.", maximumMaintenanceMilliseconds, plugin.PostSubmitMaintenance.Value, lastDiagnosticLogMilliseconds));
                if (!verbose) Plugin.Log.LogInfo("QVVR performance summary: outside meshes=" + visibility.LastHidden + "/" + visibility.Count +
                    ", UI captures/reuses=" + uiCaptureCache.Captures + "/" + uiCaptureCache.Reuses +
                    ", cache suspended=" + uiCaptureCache.Suspended + ", continuous reason=" + uiCaptureCache.ContinuousReason +
                    ", live cap skips=" + cutSurfaces.LastSkipped);
                Plugin.Log.LogInfo(string.Format("QVVR OpenXR timing sample mode={0}: main render enqueue CPU={1:F2} ms, eye/UI/copy GPU={2:F2} ms, XR wait/pose/input preparation={3:F2} ms; budget=13.89 ms at 72 Hz. Enqueue CPU excludes the game's earlier Update and XR pacing wait; GPU query is delayed/nonblocking, zero means unavailable.",
                    levelIntroFlat ? "flat-cinema" : gameplayScene ? (plugin.DioramaEnabled.Value ? "diorama" : "full-vr") : stereoMenuScene ? "3D-menu" : "2D-menu", lastMainRenderMilliseconds, NativeBridge.QVVR_GetGpuTime(), lastXrPrepareMilliseconds));
                return;
            }
            if (UsesOpenXr || compositor == null || Time.unscaledTime - sceneChangedAt < 2f || !compositor.GetFrameTiming(ref frameTiming, 0)) return;
            Plugin.Log.LogInfo(string.Format(
                "QVVR timing sample mode={0}: CPU interval={1:F2} ms, application GPU={2:F2} ms, frame interval={3:F2} ms, presents={4}, drops={5}; budget=13.89 ms at 72 Hz.",
                levelIntroFlat ? "flat-intro" : gameplayScene ? (plugin.DioramaEnabled.Value ? "diorama" : "full-vr") : stereoMenuScene ? "3D-menu" : "2D-menu",
                Mathf.Max(0f, frameTiming.m_flNewFrameReadyMs - frameTiming.m_flNewPosesReadyMs),
                frameTiming.m_flPreSubmitGpuMs + frameTiming.m_flPostSubmitGpuMs,
                frameTiming.m_flClientFrameIntervalMs,
                frameTiming.m_nNumFramePresents, frameTiming.m_nNumDroppedFrames));
        }

        private void OnActiveSceneChanged(Scene previous, Scene current)
        {
            fullVrView.Reset();
            stabilitySampleValid = false; stabilitySamples = 0;
            maxPivotStepMm = maxPlacementStepMm = maxPlacementTurnDegrees = 0;
            placement.Stop(); SavePlacementSettings(); placement.Reset();
            cloudFilter.Clear();
            visibility.Clear();
            cloudsDirty = true;
            characterVisuals.Clear();
            transparentEffects.Clear();
            liquidDepth.Clear(); cutSurfaces.Clear(); renderMaterialsDirty = true;
            worldGrab.ResetOffset();
            dioramaScale.Stop();
            dioramaView.Reset();
            if (inputBridge != null) inputBridge.RequireGripRelease();
            RestoreCanvases();
            gameplayScene = CameraSelector.IsGameplayScene(current.name);
            screenFade.SceneChanged(gameplayScene, current.name == "Loading");
            firstLevelScene = LevelIntroPolicy.Scene(current.name);
            openingScene = MenuScenePolicy.IsOpeningScene(current.name);
            levelIntroFlat = false; levelIntroCamera = null; cinemaCaptureFailed = false;
            cinemaPanelAnchor.Reset();
            flatMaterial.mainTexture = flatTexture;
            if (levelIntro != null) levelIntro.Reset();
            if (sectorCinema != null) sectorCinema.Reset();
            introScene = MenuScenePolicy.IsIntroScene(current.name);
            introPresentation = IntroPresentation.Unknown; stereoMenuScene = false;
            if (introMenus != null) introMenus.Reset();
            sceneChangedAt = Time.unscaledTime;
            gameplayTarget = null; gameManager = null;
            dioramaAnchorValid = false;
            panelPoseValid = false;
            if (settingsMenu != null) settingsMenu.Close();
            nextCanvasScan = 0f;
            nextPresentationRecovery = 0f;
            Plugin.Log.LogInfo(gameplayScene
                ? "QVVR scene mode: stereoscopic gameplay."
                : "QVVR scene mode: captured 2D render target.");
        }

        private void RestoreSourceCamera()
        {
            if (sourceCamera == null)
                return;
            sourceCamera.targetTexture = sourceTarget;
            sourceCamera.stereoTargetEye = sourceStereo;
            sourceCamera.cullingMask = sourceMask;
            sourceCamera.enabled = sourceWasEnabled;
            sourceCamera = null;
        }

        private static void ClearTexture(RenderTexture texture, Color color)
        {
            RenderTexture previous = RenderTexture.active;
            RenderTexture.active = texture;
            GL.Clear(true, true, color);
            RenderTexture.active = previous;
        }

        private static Matrix4x4 ToUnityMatrix(HmdMatrix34_t matrix)
        {
            Matrix4x4 result = Matrix4x4.identity;
            result.SetColumn(0, new Vector4(matrix.m0, matrix.m4, -matrix.m8, 0f));
            result.SetColumn(1, new Vector4(matrix.m1, matrix.m5, -matrix.m9, 0f));
            result.SetColumn(2, new Vector4(-matrix.m2, -matrix.m6, matrix.m10, 0f));
            result.SetColumn(3, new Vector4(matrix.m3, matrix.m7, -matrix.m11, 1f));
            return result;
        }

        private static Matrix4x4 ToUnityProjection(HmdMatrix44_t matrix)
        {
            Matrix4x4 result = new Matrix4x4();
            result.SetRow(0, new Vector4(matrix.m0, matrix.m1, matrix.m2, matrix.m3));
            result.SetRow(1, new Vector4(matrix.m4, matrix.m5, matrix.m6, matrix.m7));
            // OpenVR returns D3D clip depth (0..w): m22=-f/(f-n), m23=-fn/(f-n).
            // Unity camera projections are OpenGL-style (-w..w); passing D3D
            // depth halves clip z, which pushes Unity fog to ~far/2 (fully
            // fogged stereo menus) and wastes half the depth range.
            result.SetRow(2, new Vector4(2f * matrix.m8 - matrix.m12, 2f * matrix.m9 - matrix.m13,
                2f * matrix.m10 - matrix.m14, 2f * matrix.m11 - matrix.m15));
            result.SetRow(3, new Vector4(matrix.m12, matrix.m13, matrix.m14, matrix.m15));
            return result;
        }

        private void OnDestroy()
        {
            ReleaseResources();
        }

        internal void ReleaseResources()
        {
            if (resourcesReleased)
                return;
            resourcesReleased = true;
            openVrTiming.Reset();
            if (levelEntry != null) levelEntry.Release();
            if (levelIntro != null) levelIntro.Release();
            if (sectorCinema != null) sectorCinema.Release();
            if (characterSwap != null) characterSwap.Release();
            screenFade.Release();
            uiCaptureCache.Clear();
            visibility.Clear();
            characterVisuals.Clear();
            cloudFilter.Clear();
            liquidDepth.Clear(); cutSurfaces.Clear();
            transparentEffects.Clear();
            CommitWorldGrabSettings(true);
            initialized = false;
            if (UsesOpenXr && xrTrackingReady && !xrFrameQueued) NativeBridge.QVVR_CancelOpenXrFrame();
            xrTrackingReady = false;
            xrInput.Update(0);
            if (performanceSettingsApplied)
            {
                Application.targetFrameRate = originalTargetFrameRate;
                QualitySettings.shadows = originalShadows;
                performanceSettingsApplied = false;
            }
            if (settingsMenu != null) settingsMenu.Release();
            if (cameraCompatibility != null)
                cameraCompatibility.Release(this);
            if (introMenus != null) introMenus.Release();
            if (inputBridge != null)
            {
                inputBridge.Release();
                Destroy(inputBridge);
            }
            SceneManager.activeSceneChanged -= OnActiveSceneChanged;
            NativeBridge.QVVR_ClearEyeTextures();
            if (renderEvent != IntPtr.Zero)
            {
                NativeBridge.QVVR_RequestShutdown();
                GL.IssuePluginEvent(renderEvent, NativeBridge.ShutdownEvent);
            }
            RestoreCanvases();
            RestoreSourceCamera();
            ReleaseCommands(leftCamera, CameraEvent.AfterEverything, ref leftHudCommands);
            ReleaseCommands(rightCamera, CameraEvent.AfterEverything, ref rightHudCommands);
            ReleaseCommands(leftCamera, CameraEvent.BeforeDepthTexture, ref leftDepthBegin);
            ReleaseCommands(leftCamera, CameraEvent.AfterDepthTexture, ref leftDepthEnd);
            ReleaseCommands(rightCamera, CameraEvent.BeforeDepthTexture, ref rightDepthBegin);
            ReleaseCommands(rightCamera, CameraEvent.AfterDepthTexture, ref rightDepthEnd);
            if (capCompositeCommands != null)
            {
                if (leftCamera != null) leftCamera.RemoveCommandBuffer(CameraEvent.BeforeForwardAlpha, capCompositeCommands);
                if (rightCamera != null) rightCamera.RemoveCommandBuffer(CameraEvent.BeforeForwardAlpha, capCompositeCommands);
                capCompositeCommands.Release(); capCompositeCommands = null; capCommandsAttached = false;
            }
            DestroyCamera(leftCamera);
            DestroyCamera(rightCamera);
            DestroyCamera(uiCaptureCamera);
            DestroyPanel(flatPanel, flatMaterial);
            DestroyPanel(uiPanel, uiMaterial);
            DestroyTexture(leftTexture);
            DestroyTexture(rightTexture);
            DestroyTexture(leftMsaaTexture);
            DestroyTexture(rightMsaaTexture);
            DestroyTexture(flatTexture);
            DestroyTexture(cinemaTexture);
            DestroyTexture(uiTexture);
        }

        private static void DestroyCamera(Camera camera)
        {
            if (camera != null)
                Destroy(camera.gameObject);
        }
        private static void ReleaseCommands(Camera camera, CameraEvent where, ref CommandBuffer commands)
        {
            if (commands == null) return;
            if (camera != null) camera.RemoveCommandBuffer(where, commands);
            commands.Release(); commands = null;
        }

        private static void DestroyPanel(GameObject panel, Material material)
        {
            if (panel != null)
                Destroy(panel);
            if (material != null)
                Destroy(material);
        }

        private static void DestroyTexture(RenderTexture texture)
        {
            if (texture == null)
                return;
            texture.Release();
            Destroy(texture);
        }
    }
}
