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
// HUD compositor quad: fullscreen triangle with UVs; the pixel shader resamples
// the mipmapped HUD capture trilinearly into a single-level swapchain image.
inline const char *HudResampleVertexSource()
{
    return "void main(uint id:SV_VertexID,out float4 pos:SV_Position,out float2 uv:TEXCOORD0){"
           "float2 p=float2((id<<1)&2,id&2);pos=float4(p*float2(2,-2)+float2(-1,1),0,1);uv=p;}";
}
// Same color decode as the eyes, but additive HUD pixels (alpha 0) stay
// additive light in the premultiplied quad instead of gaining coverage.
inline std::string HudResampleSource(bool flip, int decode)
{
    return std::string("#define FLIP ") + (flip ? "1\n" : "0\n") + "#define DECODE " + std::to_string(decode) + "\n" +
           "Texture2D<float4> t:register(t0);SamplerState s:register(s0);"
           "float4 main(float4 p:SV_Position,float2 uv:TEXCOORD0):SV_Target{"
           "float4 c=t.Sample(s,float2(uv.x,FLIP?1-uv.y:uv.y));\n"
           "#if DECODE\n"
           "float a=DECODE==2&&c.a>0?c.a:1;float3 v=saturate(c.rgb/a);"
           "c.rgb=(v<=0.04045?v/12.92:pow((v+0.055)/1.055,2.4))*a;\n"
           "#endif\nreturn c;}";
}
} // namespace qvvr
