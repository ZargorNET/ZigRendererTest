Texture2D diffuseMap : register(t0, space2);
SamplerState sampler : register(s0, space2);

struct FragUBO {
    float3 lightPosition;
    float3 lightColor;
    float lightIntensity;
    float3 viewPosition;
};

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

    float3 dirToView = normalize(frag_ubo.viewPosition - input.position);

    // Normalize because the data from the vertex shader might interpolate which
    // will result in a vec that has a length > 1
    float3 surfaceNormal = normalize(input.surfaceNormal);

    float3 sampledDiffuseMap = diffuseMap.Sample(sampler, input.uv).rgb;

    // Ambient lighting
    float3 ambientIrradiance = float3(0.1);
    float3 reflectedRadiance = ambientIrradiance * sampledDiffuseMap;

    float incidenceAngleFactor = dot(dirToLight, surfaceNormal); // 1 direct incidence, 0 no incidence, -1 incidence from other side
    if (incidenceAngleFactor > 0) {
        float attenuationFactor = 1 / (pow(distToLight, 2)); // TODO: Control vars
        float3 incomingRadiance = frag_ubo.lightColor * frag_ubo.lightIntensity;
        float3 irradiance = incomingRadiance * incidenceAngleFactor * attenuationFactor;
        float3 brdf = blinnPhongBRDF(dirToLight, dirToView, surfaceNormal, sampledDiffuseMap);
        reflectedRadiance += irradiance * brdf;
    }

    float3 emittedRadiance = float3(0);
    float3 outRadiance = emittedRadiance + reflectedRadiance;

    return float4(outRadiance, 1);
}

float3 blinnPhongBRDF(float3 dirToLight, float3 dirToView, float3 surfaceNormal, float3 sampledDiffuseMap) {
    float3 materialDiffusionReflection = sampledDiffuseMap;

    float3 halfWayDir = normalize(dirToLight + dirToView); // Fancy Rhombus vector math!
    float specularDot = max(0, dot(halfWayDir, surfaceNormal)); // If θ is < 0, the light or view would come from the other side (more than 90° apart)
    float shininess = 100;
    float specularFactor = pow(specularDot, shininess);

    float3 specularReflection = float3(1) * specularFactor;

    return materialDiffusionReflection + specularFactor;
}
