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
            return checks;
        }
    }
}
'@
$unityAssembly = Join-Path $root '.deps/unity-reference/UnityEngine.CoreModule.dll'
[Reflection.Assembly]::LoadFrom($unityAssembly) | Out-Null
Add-Type -TypeDefinition ($source + $tests) -ReferencedAssemblies $unityAssembly
$count = [QVVR.XrMathTests]::Run()
Write-Host "OpenXR snapshot/projection: $count assertions passed; no runtime session started."
