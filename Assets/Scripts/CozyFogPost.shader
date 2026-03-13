Shader "Hidden/CozyFogPost"
{
    Properties
    {
        _Intensity ("Effect Intensity", Range(0,1)) = 1

        [Header(Height Fog)]
        _FogDensity ("Fog Density", Range(0,1)) = 0.5
        _FogStart ("Fog Start Height (screen Y)", Range(0,1)) = 0.3
        _FogEnd ("Fog End Height", Range(0,1)) = 0.8
        _FogColorLow ("Fog Color (Low)", Color) = (0.75, 0.8, 0.85, 1)
        _FogColorHigh ("Fog Color (High)", Color) = (0.9, 0.85, 0.75, 1)

        [Header(Distance Fog)]
        _DistFog ("Distance Fog", Range(0,1)) = 0.4
        _DistFogStart ("Dist Fog Near", Range(0,0.1)) = 0.01
        _DistFogEnd ("Dist Fog Far", Range(0.05,0.5)) = 0.15
        _DistFogColor ("Distance Fog Color", Color) = (0.82, 0.85, 0.9, 1)

        [Header(Sun and Sky)]
        _SunGlow ("Sun Glow", Range(0,1)) = 0.6
        _SunPosition ("Sun Position XY", Vector) = (0.7, 0.8, 0, 0)
        _SunColor ("Sun Color", Color) = (1.0, 0.9, 0.7, 1)
        _SunSize ("Sun Glow Size", Range(0.1,0.8)) = 0.35
        _SkyGradient ("Sky Gradient Blend", Range(0,1)) = 0.2
        _SkyTop ("Sky Top Color", Color) = (0.5, 0.65, 0.9, 1)
        _SkyHorizon ("Sky Horizon Color", Color) = (0.9, 0.85, 0.75, 1)

        [Header(Golden Hour)]
        _GoldenHour ("Golden Hour", Range(0,1)) = 0.3
        _ShadowWarmth ("Shadow Warmth", Range(0,1)) = 0.3
        _AmbientWarmth ("Ambient Warmth", Range(0,1)) = 0.2

        [Header(Light Rays)]
        _LightRays ("Light Ray Strength", Range(0,1)) = 0.2
        _RayCount ("Ray Count", Range(3,12)) = 6
        _RayWidth ("Ray Width", Range(0.01,0.1)) = 0.04

        [Header(Atmosphere)]
        _Scatter ("Light Scatter", Range(0,1)) = 0.2
        _Softness ("Overall Softness", Range(0,1)) = 0.15
        _Vignette ("Vignette", Range(0,0.5)) = 0.2
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "CozyFogPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            float _Intensity;

            float _FogDensity;
            float _FogStart;
            float _FogEnd;
            float4 _FogColorLow;
            float4 _FogColorHigh;

            float _DistFog;
            float _DistFogStart;
            float _DistFogEnd;
            float4 _DistFogColor;

            float _SunGlow;
            float4 _SunPosition;
            float4 _SunColor;
            float _SunSize;
            float _SkyGradient;
            float4 _SkyTop;
            float4 _SkyHorizon;

            float _GoldenHour;
            float _ShadowWarmth;
            float _AmbientWarmth;

            float _LightRays;
            float _RayCount;
            float _RayWidth;

            float _Scatter;
            float _Softness;
            float _Vignette;

            float hash12(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            float sampleDepth01(float2 uv)
            {
                return Linear01Depth(SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r, _ZBufferParams);
            }

            float4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texel = 1.0 / _ScreenParams.xy;

                // ---- Soft blur ----
                float3 col;
                if (_Softness > 0.01)
                {
                    float r = _Softness * 1.5;
                    col  = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb * 2.0;
                    col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-r, 0) * texel).rgb;
                    col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( r, 0) * texel).rgb;
                    col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, -r) * texel).rgb;
                    col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,  r) * texel).rgb;
                    col /= 6.0;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                }
                float3 original = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;

                float depth = sampleDepth01(uv);
                float lum = dot(col, float3(0.299, 0.587, 0.114));

                // ---- Height fog ----
                float heightFog = smoothstep(_FogStart, _FogEnd, 1.0 - uv.y) * _FogDensity;
                float3 fogColor = lerp(_FogColorLow.rgb, _FogColorHigh.rgb, uv.y);
                col = lerp(col, fogColor, heightFog * 0.6);

                // ---- Distance fog ----
                float distFog = smoothstep(_DistFogStart, _DistFogEnd, depth) * _DistFog;
                col = lerp(col, _DistFogColor.rgb, distFog);

                // ---- Sky gradient blend (for skybox areas at max depth) ----
                float skyMask = smoothstep(0.95, 1.0, depth);
                float3 skyColor = lerp(_SkyHorizon.rgb, _SkyTop.rgb, uv.y);
                col = lerp(col, skyColor, skyMask * _SkyGradient);

                // ---- Sun glow ----
                float2 sunUV = _SunPosition.xy;
                float sunDist = length(uv - sunUV);
                float sunGlow = exp(-sunDist * sunDist / (_SunSize * _SunSize * 0.1)) * _SunGlow;
                col += _SunColor.rgb * sunGlow * 0.4;

                // ---- Light rays ----
                if (_LightRays > 0.01)
                {
                    float2 toSun = uv - sunUV;
                    float angle = atan2(toSun.y, toSun.x);
                    float rayPattern = sin(angle * _RayCount) * 0.5 + 0.5;
                    rayPattern = smoothstep(0.5 - _RayWidth, 0.5, rayPattern);
                    float rayFade = exp(-sunDist * 2.0);
                    float rays = rayPattern * rayFade * _LightRays;
                    col += _SunColor.rgb * rays * 0.15;
                }

                // ---- Golden hour color grading ----
                // Warm up overall
                col.r += _AmbientWarmth * 0.05;
                col.g += _AmbientWarmth * 0.02;
                col.b -= _AmbientWarmth * 0.03;

                // Warm shadows
                float shadowMask = 1.0 - smoothstep(0, 0.4, lum);
                col = lerp(col, col * float3(1.1, 0.9, 0.75), shadowMask * _ShadowWarmth * 0.4);

                // Golden hour overall shift
                float3 goldenTint = float3(1.05, 0.95, 0.8);
                col *= lerp(float3(1,1,1), goldenTint, _GoldenHour);

                // ---- Light scatter (fake atmospheric scattering) ----
                if (_Scatter > 0.01)
                {
                    float3 scatter = float3(0,0,0);
                    float tw = 0;
                    for (int sx = -2; sx <= 2; sx++)
                    {
                        for (int sy = -2; sy <= 2; sy++)
                        {
                            float2 off = float2(sx, sy) * texel * 6.0;
                            float3 s = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + off).rgb;
                            float sl = dot(s, float3(0.299, 0.587, 0.114));
                            float w = smoothstep(0.5, 1.0, sl);
                            scatter += s * w;
                            tw += w;
                        }
                    }
                    scatter = (tw > 0) ? scatter / tw : float3(0,0,0);
                    col += scatter * _Scatter * 0.3 * _SunColor.rgb;
                }

                // ---- Vignette ----
                float2 vc = uv - 0.5;
                float vd = length(vc);
                float vig = 1.0 - smoothstep(0.4, 0.9, vd);
                col *= lerp(1.0, vig, _Vignette);

                col = saturate(col);
                col = lerp(original, col, _Intensity);

                return float4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
