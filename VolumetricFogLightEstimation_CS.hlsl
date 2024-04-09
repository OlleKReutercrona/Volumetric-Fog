#include "common.hlsli"
#include "ShadowCommons.hlsli"

RWTexture3D<float4> volTexture : register(u1);

Texture2D<float4> dirShadowMap : register(t14);

cbuffer volumeBuffer : register(b6)
{
    float3 minBounds;
    float padding1;
    float3 maxBounds;
    float padding2;
}

struct DirectionalLightData
{
    float3 directionalLightDirection;
    float directionalLightIntensity;
    float3 directionalLightColour;
    float ambientLightIntensity;
    float4x4 transform;
    uint shadowMapInfo;
    float3 padding;
};

struct SpotLightData
{
    float3 position;
    float intensity;
    float3 direction;
    float range;
    float3 colour;
    float innerAngle;
    float outerAngle;
    bool active;
    uint shadowMapInfo;
    float padding;
    float4x4 transform;
};

cbuffer lightData : register(b4)
{
    DirectionalLightData dLData;
    SpotLightData sLData[8];
    uint numberOfSL;
    float padding[3];
}

float phase(const float g, const float cos_theta)
{
    float denom = 1 + g * g - 2 * g * cos_theta;
    return 1.0f / (4.0f * PI) * (1.0f - g * g) / (denom * sqrt(denom));
}

[numthreads(8, 8, 8)]
void main( uint3 DTid : SV_DispatchThreadID )
{
    float4 result;

    const float3 volumeSize = maxBounds - minBounds;
    
    float3 texDimensions;
    volTexture.GetDimensions(texDimensions.x, texDimensions.y, texDimensions.z);
    
    int3 flippedDTID = DTid;
    flippedDTID.x = 255 - DTid.x;
    flippedDTID.y = 255 - DTid.y;
    flippedDTID.z = 255 - DTid.z;
    
    const float3 relativeTexturePosition = texDimensions / float3(flippedDTID);
    
    const float3 texturePosition = volumeSize / float3(relativeTexturePosition.xyz);
    
    const float3 worldPosition = texturePosition + minBounds;

    int numberOfShadows = 0;
    float shadowFactor = 0.0f;
    const float bias = 0.0000005f;
    const float g = 0.8f;
    
    const float3 toEye = normalize(float3(worldPosition - cameraPosition.xyz));
    
    shadowFactor = CalculateShadowNoBlurring(dLData.shadowMapInfo, dLData.transform, worldPosition, bias);
    float3 colour = dLData.directionalLightColour * shadowFactor * dLData.directionalLightIntensity;
    
    for (int i = 0; i < numberOfSL; i++)
    {
        SpotLightData light = sLData[i];
        
        const float3 toCamera = float3(light.transform._14_24_34 - worldPosition);
        
        shadowFactor = CalculateShadowNoBlurring(light.shadowMapInfo, light.transform, worldPosition, bias);
        
        const float3 spotlightColour = EvaluateSpotLight(light.colour, light.intensity, light.range, 
                                                         light.position, -light.direction, light.outerAngle, 
                                                         light.innerAngle, toCamera, worldPosition.xyz);
        
        const float shadow = shadowFactor * (clamp(1 - length(worldPosition - light.position) / light.range, 0.0f, 1.0f) * light.intensity);
        
        colour += shadow * spotlightColour;
       
    }
    
    result.rgb = colour;
    
    result.a = 1.0f;
    
    volTexture[DTid].rgba = result;
}