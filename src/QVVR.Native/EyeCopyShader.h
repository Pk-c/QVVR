#pragma once
#include <string>
namespace qvvr
{
// Resource-creation helper only, never called on the hot render path.
inline std::string EyeCopySource(bool flip, int decode)
{
    return std::string("#define FLIP ") + (flip ? "1\n" : "0\n") + "#define DECODE " + std::to_string(decode) + "\n" +
           "Texture2D<float4> t:register(t0);float4 main(float4 p:SV_Position):SV_Target{uint w,h;t.GetDimensions(w,h);"
           "float4 c=t.Load(int3(p.x,FLIP?(h-1-(uint)p.y):(uint)p.y,0));\n"
           "bool emission=c.a==0;\n"
           "#if DECODE\n"
           "float a=DECODE==2&&!emission?max(c.a,0.00001):1;float3 v=max(c.rgb/a,0);"
           "c.rgb=(v<=0.04045?v/12.92:pow((v+0.055)/1.055,2.4))*a;\n"
           "#endif\n"
           // Empty additive pixels remain invisible. Visible emission on an
           // empty background receives only color-derived coverage, not a quad's
           // texture alpha. Do this in the existing GPU copy, no extra pass/PS.
           "#if DECODE!=1\n"
           "if(emission)c.a=saturate(max(c.r,max(c.g,c.b)));\n"
           "#endif\nreturn c;}";
}
} // namespace qvvr
