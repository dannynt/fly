Shader "Hidden/CelOutlinePost"
{
    Properties
    {
        _Intensity ("Effect Intensity", Range(0,1)) = 1

        [Header(Outlines)]
        _OutlineThickness ("Outline Thickness", Range(0.5,5)) = 2.0
        _OutlineColor ("Outline Color", Color) = (0.08, 0.06, 0.05, 1)
        _OutlineStrength ("Outline Strength", Range(0,1)) = 0.85
        _DepthThreshold ("Depth Threshold", Range(0.0001,0.01)) = 0.002
        _ColorThreshold ("Color Edge Threshold", Range(0.05,0.8)) = 0.2
        _DistanceFade ("Distance Fade", Range(0,1)) = 0.5

        [Header(Cel Shading)]
        _ShadowSteps ("Shadow Steps", Range(2,8)) = 3
        _ShadowSoftness ("Step Softness", Range(0,1)) = 0.15
        _ShadowColor ("Shadow Tint", Color) = (0.6, 0.65, 0.8, 1)
        _HighlightColor ("Highlight Tint", Color) = (1.0, 0.98, 0.9, 1)
        _ShadowThreshold ("Shadow Threshold", Range(0,1)) = 0.45

        [Header(Color)]
        _Saturation ("Saturation", Range(0.5,1.5)) = 1.05
        _ColorBoost ("Color Vibrance", Range(0,1)) = 0.3
        _Warmth ("Warmth", Range(-0.5,0.5)) = 0.1

        [Header(Specular Highlight)]
        _SpecularSize ("Specular Band Size", Range(0,0.3)) = 0.08
        _SpecularBrightness ("Specular Brightness", Range(0,1)) = 0.4

        [Header(Ambient)]
        _AmbientLight ("Ambient Lift", Range(0,0.2)) = 0.05
        _Vignette ("Vignette", Range(0,0.5)) = 0.15
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "CelOutlinePass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            float _Intensity;

            float _OutlineThickness;
            float4 _OutlineColor;
            float _OutlineStrength;
            float _DepthThreshold;
            float _ColorThreshold;
            float _DistanceFade;

            float _ShadowSteps;
            float _ShadowSoftness;
            float4 _ShadowColor;
            float4 _HighlightColor;
            float _ShadowThreshold;

            float _Saturation;
            float _ColorBoost;
            float _Warmth;

            float _SpecularSize;
            float _SpecularBrightness;

            float _AmbientLight;
            float _Vignette;

            float sampleDepth01(float2 uv)
            {
                return Linear01Depth(SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r, _ZBufferParams);
            }

            float4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texel = 1.0 / _ScreenParams.xy;
                float3 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float3 original = col;

                // ---- Roberts cross depth edge detection (cleaner for low-poly) ----
                float t = _OutlineThickness;
                float d00 = sampleDepth01(uv + float2(-t, -t) * texel);
                float d11 = sampleDepth01(uv + float2( t,  t) * texel);
                float d01 = sampleDepth01(uv + float2(-t,  t) * texel);
                float d10 = sampleDepth01(uv + float2( t, -t) * texel);
                float depthEdge = abs(d00 - d11) + abs(d01 - d10);
                depthEdge = smoothstep(0, _DepthThreshold, depthEdge);

                // Distance-based outline fade (thin outlines far away)
                float centerDepth = sampleDepth01(uv);
                float distFade = 1.0 - smoothstep(0.05, 0.5, centerDepth) * _DistanceFade;
                depthEdge *= distFade;

                // ---- Color-based edge detection (catches flat-shaded polygon edges) ----
                float3 cL = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-t, 0) * texel).rgb;
                float3 cR = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( t, 0) * texel).rgb;
                float3 cU = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, -t) * texel).rgb;
                float3 cD = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,  t) * texel).rgb;
                float colorEdge = length(cL - cR) + length(cU - cD);
                colorEdge = smoothstep(0, _ColorThreshold, colorEdge);
                colorEdge *= distFade;

                float edge = saturate(max(depthEdge, colorEdge * 0.7));

                // ---- Cel shading: quantize luminance into steps ----
                float lum = dot(col, float3(0.299, 0.587, 0.114));

                // Quantize
                float steps = _ShadowSteps;
                float quantLum = floor(lum * steps + 0.5) / steps;
                // Smooth the step transition
                float smoothLum = lerp(quantLum, lum, _ShadowSoftness);

                // Remap color using quantized luminance
                float lumRatio = (lum > 0.001) ? smoothLum / lum : 1.0;
                col *= lumRatio;

                // Shadow and highlight tinting
                float shadowMask = 1.0 - smoothstep(0, _ShadowThreshold, smoothLum);
                float highlightMask = smoothstep(_ShadowThreshold + 0.3, 1.0, smoothLum);
                col = lerp(col, col * _ShadowColor.rgb, shadowMask * 0.5);
                col = lerp(col, col * _HighlightColor.rgb, highlightMask * 0.3);

                // ---- Specular highlight band ----
                float specBand = smoothstep(1.0 - _SpecularSize, 1.0 - _SpecularSize * 0.3, lum);
                col += specBand * _SpecularBrightness * float3(1, 0.98, 0.95);

                // ---- Color adjustments ----
                // Saturation
                float newLum = dot(col, float3(0.299, 0.587, 0.114));
                col = lerp(float3(newLum, newLum, newLum), col, _Saturation);

                // Vibrance (boost low-saturation colors more)
                float maxC = max(col.r, max(col.g, col.b));
                float minC = min(col.r, min(col.g, col.b));
                float curSat = (maxC > 0.001) ? (maxC - minC) / maxC : 0;
                float vibBoost = (1.0 - curSat) * _ColorBoost;
                col = lerp(float3(newLum, newLum, newLum), col, 1.0 + vibBoost);

                // Warmth
                col.r += _Warmth * 0.04;
                col.b -= _Warmth * 0.04;

                // Ambient lift
                col += _AmbientLight;

                // ---- Apply outline ----
                col = lerp(col, _OutlineColor.rgb, edge * _OutlineStrength);

                // ---- Vignette ----
                float2 vc = uv - 0.5;
                float vd = length(vc);
                float vig = 1.0 - smoothstep(0.5, 1.0, vd * 1.2);
                col *= lerp(1.0, vig, _Vignette);

                col = saturate(col);
                col = lerp(original, col, _Intensity);

                return float4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
