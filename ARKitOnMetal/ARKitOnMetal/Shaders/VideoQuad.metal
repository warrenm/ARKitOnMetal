
#include <metal_stdlib>
using namespace metal;

constant int AttributeIndexPosition = 0;
constant int AttributeIndexTexCoords = 1;

constant int BufferIndexTransform = 1;

constant int TextureIndexLuma = 0;
constant int TextureIndexChroma = 1;

struct VertexIn {
    float2 position  [[attribute(AttributeIndexPosition)]];
    float2 texCoords [[attribute(AttributeIndexTexCoords)]];
};

struct VertexOut {
    float4 clipPosition [[position]];
    float2 texCoords;
};

vertex VertexOut videoQuadVertex(VertexIn in [[stage_in]],
                                 constant float3x3 &transform [[buffer(BufferIndexTransform)]])
{
    VertexOut out;
    out.clipPosition = float4(in.position, 0, 1);
    out.texCoords = (transform * float3(in.texCoords, 1)).xy;
    return out;
}

typedef VertexOut FragmentIn;

fragment half4 videoQuadFragment(FragmentIn in [[stage_in]],
                                 texture2d<float, access::sample> yTexture [[texture(TextureIndexLuma)]],
                                 texture2d<float, access::sample> cbcrTexture [[texture(TextureIndexChroma)]])
{
    sampler sampler2d(coord::normalized, filter::linear);

    float y = yTexture.sample(sampler2d, in.texCoords).r;
    float2 cbcr = cbcrTexture.sample(sampler2d, in.texCoords).rg;
    float3 ycbcr(y, cbcr);

    float3 offset(-16 / 255.0, -0.5, -0.5);
    float3x3 colorMatrix(1.164,  1.164, 1.164,
                         0.000, -0.392, 2.017,
                         1.596, -0.813, 0.000);

    float4 color(colorMatrix * (ycbcr + offset), 1);

    return half4(color);
}
