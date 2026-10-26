[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Core') {
    # Unity 2019's reference assemblies use the .NET Framework/Mono ABI.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    if ($LASTEXITCODE -ne 0) { throw 'OpenXR math test failed in Windows PowerShell.' }
    return
}
$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $root 'src/QVVR/OpenXrFrame.cs') -Raw
$tests = @'
namespace Valve.VR {
    // Same 12-float ABI as the SDK; no OpenVR runtime loaded for this test.
    public struct HmdMatrix34_t { public float m0,m1,m2,m3,m4,m5,m6,m7,m8,m9,m10,m11; }
}
namespace QVVR {
    public static class XrMathTests {
        private static int checks;
        private static void Assert(bool value, string message) { checks++; if (!value) throw new System.Exception(message); }
        private static bool Near(float a, float b) { return System.Math.Abs(a-b)<0.0001f; }
        public static int Run() {
            Assert(System.Runtime.InteropServices.Marshal.SizeOf(typeof(OpenXrHand))==72, "Hand ABI");
            Assert(System.Runtime.InteropServices.Marshal.SizeOf(typeof(OpenXrFrame))==320, "Frame ABI");
            Assert(System.Runtime.InteropServices.Marshal.OffsetOf(typeof(OpenXrFrame), "LeftHand").ToInt32()==176, "Hand offset ABI");
            OpenXrFov fov = new OpenXrFov();
            fov.Left=-0.9f; fov.Right=0.6f; fov.Up=0.7f; fov.Down=-0.8f;
            UnityEngine.Matrix4x4 p = fov.Projection(0.1f, 100f);
            float l=(float)System.Math.Tan(fov.Left), r=(float)System.Math.Tan(fov.Right);
            float u=(float)System.Math.Tan(fov.Up), d=(float)System.Math.Tan(fov.Down);
            Assert(Near(p.m00*l-p.m02,-1f), "Left asymmetric FOV boundary");
            Assert(Near(p.m00*r-p.m02,1f), "Right asymmetric FOV boundary");
            Assert(Near(p.m11*u-p.m12,1f), "Upper FOV boundary");
            Assert(Near(p.m11*d-p.m12,-1f), "Lower FOV boundary");
            Assert(Near((p.m22*(-0.1f)+p.m23)/0.1f,-1f), "Unity near plane depth -1");
            Assert(Near((p.m22*(-100f)+p.m23)/100f,1f), "Unity far plane depth +1");
            Assert(Near(p.m32,-1f) && Near(p.m33,0f), "Perspective divide must use RH negative Z");
            HudLayerChecks();
            return checks;
        }
        // Managed-only math: Unity's native Quaternion/Matrix entry points are unavailable here.
        private static UnityEngine.Quaternion Yaw(float degrees) {
            float half = degrees * 0.5f * (float)System.Math.PI / 180f;
            return new UnityEngine.Quaternion(0f, (float)System.Math.Sin(half), 0f, (float)System.Math.Cos(half));
        }
        private static UnityEngine.Quaternion Conj(UnityEngine.Quaternion q) { return new UnityEngine.Quaternion(-q.x, -q.y, -q.z, q.w); }
        private static UnityEngine.Matrix4x4 Pose(UnityEngine.Vector3 t, UnityEngine.Quaternion q) {
            UnityEngine.Matrix4x4 m = new UnityEngine.Matrix4x4();
            UnityEngine.Vector3 x = q * UnityEngine.Vector3.right, y = q * UnityEngine.Vector3.up, z = q * UnityEngine.Vector3.forward;
            m.SetColumn(0, new UnityEngine.Vector4(x.x, x.y, x.z, 0f)); m.SetColumn(1, new UnityEngine.Vector4(y.x, y.y, y.z, 0f));
            m.SetColumn(2, new UnityEngine.Vector4(z.x, z.y, z.z, 0f)); m.SetColumn(3, new UnityEngine.Vector4(t.x, t.y, t.z, 1f));
            return m;
        }
        private static void HudLayerChecks() {
            Assert(System.Runtime.InteropServices.Marshal.SizeOf(typeof(OpenXrHudLayer))==44, "HUD layer ABI");
            // Panel straight ahead in Unity tracking space (+Z forward) must be in
            // front in OpenXR (-Z) with identity orientation, i.e. facing the viewer.
            OpenXrHudLayer layer = new OpenXrHudLayer();
            UnityEngine.Matrix4x4 identity = Pose(UnityEngine.Vector3.zero, UnityEngine.Quaternion.identity);
            layer.SetFromWorld(new UnityEngine.Vector3(0f, 1.5f, 1.4f), UnityEngine.Quaternion.identity, new UnityEngine.Vector3(3.24f, 1.82f, 1f),
                UnityEngine.Vector3.zero, UnityEngine.Quaternion.identity, 1f, identity, UnityEngine.Quaternion.identity, 5u);
            Assert(layer.Visible==1 && layer.Version==5 && Near(layer.PositionY,1.5f) && Near(layer.PositionZ,-1.4f), "HUD ahead maps to OpenXR -Z");
            Assert(Near(layer.RotationW,1f) && Near(layer.Width,3.24f) && Near(layer.Height,1.82f), "HUD identity facing and size");
            // Round trip through the eye rig mapping with recenter, rig yaw and world scale.
            UnityEngine.Vector3 calibrationPosition = new UnityEngine.Vector3(0.3f, 1.6f, -0.2f);
            UnityEngine.Quaternion calibrationRotation = Yaw(35f), rigRotation = Yaw(-120f), trackingRotation = Yaw(20f);
            UnityEngine.Vector3 rigPosition = new UnityEngine.Vector3(12f, 4f, -7f), tracking = new UnityEngine.Vector3(0.6f, 1.4f, 1.1f);
            float units = 0.05f;
            UnityEngine.Vector3 world = rigPosition + rigRotation * (Conj(calibrationRotation) * (tracking - calibrationPosition)) * units;
            UnityEngine.Quaternion worldRotation = rigRotation * Conj(calibrationRotation) * trackingRotation;
            layer.SetFromWorld(world, worldRotation, new UnityEngine.Vector3(0.09f, 0.05f, 1f), rigPosition, rigRotation, units,
                Pose(calibrationPosition, calibrationRotation), calibrationRotation, 6u);
            Assert(layer.Visible==1 && Near(layer.PositionX,tracking.x) && Near(layer.PositionY,tracking.y) && Near(layer.PositionZ,-tracking.z), "HUD position inverts the rig mapping");
            Assert(Near(layer.RotationX,-trackingRotation.x) && Near(layer.RotationY,-trackingRotation.y) &&
                Near(layer.RotationZ,trackingRotation.z) && Near(layer.RotationW,trackingRotation.w), "HUD rotation mirrors Unity LH to OpenXR RH");
            Assert(Near(layer.Width,1.8f) && Near(layer.Height,1f), "World units convert back to meters");
            layer.SetFromWorld(world, worldRotation, UnityEngine.Vector3.one, rigPosition, rigRotation, 0f, identity, UnityEngine.Quaternion.identity, 7u);
            Assert(layer.Visible==0, "Invalid world scale never submits a quad");
            layer.SetFromWorld(new UnityEngine.Vector3(float.NaN, 0f, 0f), worldRotation, UnityEngine.Vector3.one, rigPosition, rigRotation, 1f, identity, UnityEngine.Quaternion.identity, 8u);
            Assert(layer.Visible==0, "Non-finite pose never submits a quad");
        }
    }
}
'@
$unityAssembly = Join-Path $root '.deps/unity-reference/UnityEngine.CoreModule.dll'
[Reflection.Assembly]::LoadFrom($unityAssembly) | Out-Null
Add-Type -TypeDefinition ($source + $tests) -ReferencedAssemblies $unityAssembly
$count = [QVVR.XrMathTests]::Run()
Write-Host "OpenXR snapshot/projection: $count assertions passed; no runtime session started."
