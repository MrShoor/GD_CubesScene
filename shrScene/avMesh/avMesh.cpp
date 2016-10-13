#include "hlsl.h"
#include "matrices.h"
#include "..\lighting.h"

struct VS_Input {
    float3 vsCoord         : vsCoord;
    float3 vsNormal        : vsNormal;
    float2 vsTex           : vsTex;
    float4 aiTranslateTexID: aiTranslateTexID; //xyz - translate, w - diffuse texture ID
};

struct VS_Output {
    float4 Pos                 : SV_Position;
    float2 vTex                : vTex;
    float4 addColor            : addColor;
};

float MapXStep;

float4 vertPhongColor(float3 Normal, float3 ViewDir, float3 LightDir, float4 Specular, float4 Ambient, float SpecPower)
{
   float3 Reflect = reflect(LightDir, Normal);
   float DiffuseK = max(0, dot(Normal, LightDir));
   float3 SpecularColor = Specular.rgb * (pow(max(0.0, -dot(LightDir, Reflect)), SpecPower));
   return float4(Ambient.rgb + SpecularColor, DiffuseK);
}

VS_Output VS(VS_Input In) {
    VS_Output Out;
    float3 vCoord = mul(float4(In.vsCoord+In.aiTranslateTexID.xyz, 1.0), V_Matrix).xyz;
    float3 viewNorm = mul(In.vsNormal, (float3x3)V_Matrix);
    
    float3 viewDir = normalize(vCoord);
    Out.addColor = vertPhongColor(-viewNorm, viewDir, viewDir, 1.0, 0.1, 128.0);
    
    Out.vTex.xy = In.vsTex;
    Out.vTex.x += In.aiTranslateTexID.w;
    Out.vTex.x *= MapXStep;
    Out.Pos = mul(float4(vCoord, 1.0), P_Matrix);
    return Out;
}

///////////////////////////////////////////////////////////////////////////////

Texture2D Maps; SamplerState MapsSampler;

struct PS_Output {
    float4 Color : SV_Target0;
};

PS_Output PS(VS_Output In) {
    PS_Output Out;
    
    float4 diff = Maps.Sample(MapsSampler, In.vTex);
    
    Out.Color = diff.bgra;
    Out.Color.xyz *= In.addColor.a;
    Out.Color.xyz += In.addColor.xyz;
    return Out;
}