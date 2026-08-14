struct GlobalUbo {
    float4x4 viewProjectionMat;
};

struct LocalUbo {
    float4x4 modelMat;
    float4x4 normalMat;
};

ConstantBuffer<GlobalUbo> ubo : register(b0, space1);
ConstantBuffer<LocalUbo> local_ubo : register(b1, space1);

struct VertexInput {
    float3 position;
    float4 color;
    float2 uv;
    float3 normal;
};

struct VertexOutput {
    float4 clipPosition : SV_Position;
    float4 color;
    float2 uv;
    float3 position;
    float3 normal;
};

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
    float4 worldPosition = mul(local_ubo.modelMat, float4(input.position, 1));

    VertexOutput output;
    output.clipPosition = mul(ubo.viewProjectionMat, worldPosition);
    output.color = input.color;
    output.uv = input.uv;
    output.position = worldPosition.xzy;
    output.normal = normalize(mul(local_ubo.normalMat, float4(input.normal, 0)).xyz); // Calculate normal in world position from model space. Setting a zero
                                                                        // for 'w' eliminates the translation

    return output;
}

Texture2D tex : register(t0, space2);
SamplerState texSampler : register(s0, space2);

struct FragUBO {
    float3 lightPosition;
    float3 lightColor;
    float lightIntensity;
}
ConstantBuffer<FragUBO> frag_ubo : register(b0, space3);

struct FragmentInput {
    float4 color;
    float2 uv;
    float3 position;
    float3 surfaceNormal;
};

[shader("fragment")]
float4 fragmentMain(FragmentInput input) : SV_Target {
    float3 vecToLight = frag_ubo.lightPosition - input.position;
    float distToLight = length(vecToLight);
    float3 dirToLight = vecToLight / distToLight; // Normalized vector

    // Normalize because the data from the vertex shader might interpolate which
    // will result in a vec that has a length > 1
    float3 surfaceNormal = normalize(input.surfaceNormal);

    float incidenceAngleFactor = dot(dirToLight, surfaceNormal); // 1 direct incidence, 0 no incidence, -1 incidence from other side
    float3 reflectedRadiance;
    if (incidenceAngleFactor > 0) {
        float attenuationFactor = 1 / (pow(distToLight, 2)); // TODO: Control vars
        float3 incomingRadiance = frag_ubo.lightColor * frag_ubo.lightIntensity;
        float3 irradiance = incomingRadiance * incidenceAngleFactor * attenuationFactor;
        float3 brdf = 1;
        reflectedRadiance = irradiance * brdf;
    } else {
        reflectedRadiance = float3(0, 0, 0);
    }
    float3 emittedRadiance = float3(0, 0, 0);
    float3 outRadiance =  emittedRadiance + reflectedRadiance;

    return tex.Sample(texSampler, input.uv) * float4(outRadiance, 1);
    // return tex.Sample(texSampler, input.uv) * input.color;
}
