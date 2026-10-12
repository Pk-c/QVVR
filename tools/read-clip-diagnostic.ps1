[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [float]$CenterX = 0, [float]$CenterY = 0, [float]$CenterZ = 0,
    [string]$ShaderOutputDirectory
)
$ErrorActionPreference = 'Stop'
if (-not ('QVVRClipDiagnosticReader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class QVVRClipDiagnosticReader {
    [DllImport("d3dcompiler_47.dll", CallingConvention=CallingConvention.StdCall)]
    private static extern int D3DDisassemble(byte[] data, UIntPtr size, uint flags, IntPtr comments, out IntPtr blob);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate IntPtr BlobPointer(IntPtr blob);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate UIntPtr BlobSize(IntPtr blob);
    private static void SaveShader(string directory, string name, byte[] bytes) {
        Directory.CreateDirectory(directory);
        File.WriteAllBytes(Path.Combine(directory,name+".dxbc"),bytes);
        IntPtr blob;
        int hr=D3DDisassemble(bytes,(UIntPtr)bytes.Length,0,IntPtr.Zero,out blob);
        if(hr<0) throw new Exception("Disassembly failed: "+hr.ToString("X8"));
        try {
            IntPtr table=Marshal.ReadIntPtr(blob);
            var pointer=(BlobPointer)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(table,3*IntPtr.Size),typeof(BlobPointer));
            var size=(BlobSize)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(table,4*IntPtr.Size),typeof(BlobSize));
            string text=Marshal.PtrToStringAnsi(pointer(blob),(int)size(blob).ToUInt64()-1);
            File.WriteAllText(Path.Combine(directory,name+".asm.txt"),text);
        } finally { Marshal.Release(blob); }
    }
    private static double[,] Matrix(float[] values, bool transpose) {
        var m = new double[4,4];
        for(int r=0;r<4;r++) for(int c=0;c<4;c++) m[r,c]=values[transpose ? r*4+c : c*4+r];
        return m;
    }
    private static double[,] Multiply(double[,] a, double[,] b) {
        var m = new double[4,4];
        for(int r=0;r<4;r++) for(int c=0;c<4;c++) for(int k=0;k<4;k++) m[r,c]+=a[r,k]*b[k,c];
        return m;
    }
    private static double[,] Inverse(double[,] a) {
        var t = new double[4,8];
        for(int r=0;r<4;r++) { for(int c=0;c<4;c++) t[r,c]=a[r,c]; t[r,r+4]=1; }
        for(int c=0;c<4;c++) {
            int pivot=c;
            for(int r=c+1;r<4;r++) if(Math.Abs(t[r,c])>Math.Abs(t[pivot,c])) pivot=r;
            if(Math.Abs(t[pivot,c])<1e-20) throw new Exception("Singular clip matrix.");
            for(int k=0;k<8;k++) { double v=t[c,k]; t[c,k]=t[pivot,k]; t[pivot,k]=v; }
            double divisor=t[c,c]; for(int k=0;k<8;k++) t[c,k]/=divisor;
            for(int r=0;r<4;r++) if(r!=c) { double scale=t[r,c]; for(int k=0;k<8;k++) t[r,k]-=scale*t[c,k]; }
        }
        var result=new double[4,4]; for(int r=0;r<4;r++) for(int c=0;c<4;c++) result[r,c]=t[r,c+4];
        return result;
    }
    private static void Print(double[,] m) {
        for(int r=0;r<4;r++) Console.WriteLine("  {0,14:G8} {1,14:G8} {2,14:G8} {3,14:G8}",m[r,0],m[r,1],m[r,2],m[r,3]);
    }
    private sealed class Candidate { public double Error; public int Slot, Offset; public bool Transpose; public double[,] Matrix; }
    public static void Read(string path, float x, float y, float z, string shaderDirectory) {
        using(var reader=new BinaryReader(File.OpenRead(path))) {
            if(reader.ReadUInt32()!=0x51564344 || reader.ReadUInt32()!=2) throw new Exception("Unknown diagnostic format.");
            var values=new float[16]; for(int i=0;i<16;i++) values[i]=reader.ReadSingle();
            var clip=Matrix(values,false);
            var submitted=(float[])values.Clone();
            var limits=new float[4]; for(int i=0;i<4;i++) limits[i]=reader.ReadSingle();
            var viewport=new float[6]; for(int i=0;i<6;i++) viewport[i]=reader.ReadSingle();
            var sizes=new uint[14]; for(int i=0;i<14;i++) sizes[i]=reader.ReadUInt32();
            var starts=new uint[14]; for(int i=0;i<14;i++) starts[i]=reader.ReadUInt32();
            Console.WriteLine("Viewport x/y={0}/{1}, size={2}x{3}, depth={4}..{5}; radius={6}, half height={7}",
                viewport[0],viewport[1],viewport[2],viewport[3],viewport[4],viewport[5],Math.Sqrt(limits[0]),limits[1]);
            // Managed reconstruction currently assumes a full-size eye viewport.
            // Compare viewport above with the logged pixelRect before interpreting.
            var pixelToClip=new double[4,4]; pixelToClip[0,0]=2/viewport[2]; pixelToClip[0,3]=-1;
            pixelToClip[1,1]=-2/viewport[3]; pixelToClip[1,3]=1; pixelToClip[2,2]=pixelToClip[3,3]=1;
            var translation=new double[4,4]; for(int i=0;i<4;i++) translation[i,i]=1;
            translation[0,3]=-x; translation[1,3]=-y; translation[2,3]=-z;
            var expected=Multiply(Multiply(pixelToClip,Inverse(clip)),translation);
            Console.WriteLine("Expected world view-projection from submitted clip matrix:"); Print(expected);
            double norm=0; foreach(double v in expected) norm+=v*v;
            var candidates=new List<Candidate>();
            for(int slot=0;slot<14;slot++) {
                var bytes=reader.ReadBytes(65536);
                if(bytes.Length!=65536 || sizes[slot]>65536) throw new Exception("Truncated/invalid capture.");
                Console.WriteLine("VS b{0}: {1} captured bytes, firstConstant={2}",slot,sizes[slot],starts[slot]);
                for(int offset=0;offset+64<=sizes[slot];offset+=16) {
                    bool finite=true;
                    for(int i=0;i<16;i++) { values[i]=BitConverter.ToSingle(bytes,offset+i*4); finite &= !float.IsNaN(values[i])&&!float.IsInfinity(values[i]); }
                    if(!finite) continue;
                    for(int trans=0;trans<2;trans++) {
                        var m=Matrix(values,trans!=0); double error=0;
                        for(int r=0;r<4;r++) for(int c=0;c<4;c++) { double d=m[r,c]-expected[r,c]; error+=d*d; }
                        candidates.Add(new Candidate { Error=Math.Sqrt(error/Math.Max(norm,1e-20)),Slot=slot,Offset=offset,Transpose=trans!=0,Matrix=m });
                    }
                }
            }
            candidates.Sort((a,b)=>a.Error.CompareTo(b.Error));
            for(int i=0;i<Math.Min(5,candidates.Count);i++) {
                var c=candidates[i];
                Console.WriteLine("Closest matrix candidate b{0}+{1} bytes, transposed={2}, relative error={3:G6} (heuristic, not reflection)",c.Slot,c.Offset,c.Transpose,c.Error);
                Print(c.Matrix);
            }
            if(reader.BaseStream.Length>reader.BaseStream.Position) {
                uint slot=reader.ReadUInt32(), first=reader.ReadUInt32(), bytes=reader.ReadUInt32(), binding=reader.ReadUInt32();
                var received=new float[16]; for(int i=0;i<16;i++) received[i]=reader.ReadSingle();
                var receivedLimits=new float[4]; for(int i=0;i<4;i++) receivedLimits[i]=reader.ReadSingle();
                double error=0; for(int i=0;i<16;i++) error=Math.Max(error,Math.Abs(received[i]-submitted[i]));
                for(int i=0;i<4;i++) error=Math.Max(error,Math.Abs(receivedLimits[i]-limits[i]));
                Console.WriteLine("Pixel clip constants: b{0}, firstConstant={1}, bytes={2}, expected shader bound={3}, max absolute difference={4:G8}",slot,first,bytes,binding,error);
                Print(Matrix(received,false));
                Console.WriteLine("Received limits: {0}, {1}, {2}, {3}",receivedLimits[0],receivedLimits[1],receivedLimits[2],receivedLimits[3]);
                uint originalSize=reader.ReadUInt32(), clippedSize=reader.ReadUInt32();
                var original=reader.ReadBytes(262144); var clipped=reader.ReadBytes(262144);
                if(originalSize>original.Length || clippedSize>clipped.Length) throw new Exception("Invalid shader capture.");
                Console.WriteLine("Captured pixel shader: original={0} bytes, clipped={1} bytes",originalSize,clippedSize);
                if(!string.IsNullOrEmpty(shaderDirectory) && originalSize>0 && clippedSize>0) {
                    Array.Resize(ref original,(int)originalSize); Array.Resize(ref clipped,(int)clippedSize);
                    SaveShader(shaderDirectory,"pixel-original",original); SaveShader(shaderDirectory,"pixel-clipped",clipped);
                }
            }
        }
    }
}
'@
}
[QVVRClipDiagnosticReader]::Read((Resolve-Path -LiteralPath $Path).Path, $CenterX, $CenterY, $CenterZ, $ShaderOutputDirectory)
