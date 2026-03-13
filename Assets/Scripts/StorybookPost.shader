Shader "Hidden/StorybookPost"
{
    Properties
    {
        _Intensity ("Effect Intensity", Range(0,1)) = 1

        [Header(Ink Outlines)]
        _OutlineThickness ("Outline Thickness", Range(0.5,4)) = 1.5
        _OutlineStrength ("Outline Strength", Range(0,1)) = 0.7
        _InkColor ("Ink Color", Color) = (0.15, 0.1, 0.08, 1)
        _DepthSensitivity ("Depth Sensitivity", Range(0,5)) = 2.0
        _NormalSensitivity ("Normal Sensitivity", Range(0,3)) = 1.2

        [Header(Color Palette)]
        _Warmth ("Warmth", Range(0,1)) = 0.4
        _Saturation ("Saturation", Range(0.3,1.5)) = 0.85
        _Brightness ("Brightness Lift", Range(-0.1,0.2)) = 0.05
        _ColorSteps ("Color Quantization Steps", Range(4,32)) = 12
        _StepSoftness ("Step Softness", Range(0,1)) = 0.6

        [Header(Paper and Texture)]
        _PaperGrain ("Paper Grain", Range(0,0.15)) = 0.06
        _PaperTint ("Paper Tint", Color) = (0.98, 0.95, 0.88, 1)
        _PaperBlend ("Paper Blend", Range(0,0.3)) = 0.1
        _EdgeWobble ("Edge Wobble", Range(0,0.005)) = 0.001

        [Header(Soft Edges)]
        _SoftBlur ("Soft Blur", Range(0,1)) = 0.25
        _Vignette ("Vignette", Range(0,1)) = 0.25
        _VignetteColor ("Vignette Color", Color) = (0.3, 0.2, 0.1, 1)
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "StorybookPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            float _Intensity;

            float _OutlineThickness;
            float _OutlineStrength;
            float4 _InkColor;
            float _DepthSensitivity;
            float _NormalSensitivity;

            float _Warmth;
            float _Saturation;
            float _Brightness;
            float _ColorSteps;
            float _StepSoftness;

            float _PaperGrain;
            float4 _PaperTint;
            float _PaperBlend;
            float _EdgeWobble;

            float _SoftBlur;
            float _Vignette;
            float4 _VignetteColor;

            float hash12(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                float a = hash12(i);
                float b = hash12(i + float2(1,0));
                float c = hash12(i + float2(0,1));
                float d = hash12(i + float2(1,1));
                return lerp(lerp(a,b,f.x), lerp(c,d,f.x), f.y);
            }

            float sampleDepth(float2 uv)
            {
                return Linear01Depth(SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r, _ZBufferParams);
            }

            float4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texel = 1.0 / _ScreenParams.xy;

                // Edge wobble for hand-drawn feel
                float wobble = (valueNoise(uv * 300.0 + _Time.y * 2.0) - 0.5) * _EdgeWobble;
                float2 wuv = uv + wobble;

                // ---- Soft blur (watercolor-ish softness) ----
                float3 col = float3(0,0,0);
                if (_SoftBlur > 0.01)
                {
                    float radius = _SoftBlur * 2.0;
                    col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, wuv + float2(-radius, -radius) * texel).rgb;
                    col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, wuv + float2( radius, -radius) * texel).rgb;
                    col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, wuv + float2(-radius,  radius) * texel).rgb;
                    col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, wuv + float2( radius,  radius) * texel).rgb;
                    col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, wuv).rgb * 2.0;
                    col /= 6.0;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, wuv).rgb;
                }
                float3 original = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;

                // ---- Depth-based outline ----
                float depthC = sampleDepth(uv);
                float depthL = sampleDepth(uv + float2(-_OutlineThickness, 0) * texel);
                float depthR = sampleDepth(uv + float2( _OutlineThickness, 0) * texel);
                float depthU = sampleDepth(uv + float2(0, -_OutlineThickness) * texel);
                float depthD = sampleDepth(uv + float2(0,  _OutlineThickness) * texel);

                float depthEdge = abs(depthL - depthR) + abs(depthU - depthD);
                depthEdge = smoothstep(0.0, 0.001 * _DepthSensitivity, depthEdge);

                // Normal-based outline (reconstruct from color difference as fallback)
                float3 colL = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-_OutlineThickness, 0) * texel).rgb;
                float3 colR = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( _OutlineThickness, 0) * texel).rgb;
                float3 colU = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, -_OutlineThickness) * texel).rgb;
                float3 colD = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,  _OutlineThickness) * texel).rgb;
                float colorEdge = length(colL - colR) + length(colU - colD);
                colorEdge = smoothstep(0.0, 0.3 / _NormalSensitivity, colorEdge);

                float outline = saturate(max(depthEdge, colorEdge));

                // ---- Color quantization (gentle) ----
                float3 quantized = floor(col * _ColorSteps + 0.5) / _ColorSteps;
                col = lerp(col, quantized, 1.0 - _StepSoftness);

                // ---- Warmth and saturation ----
                float lum = dot(col, float3(0.299, 0.587, 0.114));
                // Saturation
                col = lerp(float3(lum, lum, lum), col, _Saturation);
                // Warmth: shift toward warm tones
                col.r += _Warmth * 0.06;
                col.g += _Warmth * 0.02;
                col.b -= _Warmth * 0.04;
                // Brightness
                col += _Brightness;

                // ---- Paper texture ----
                float paper = valueNoise(uv * _ScreenParams.xy * 0.5) * _PaperGrain;
                col += paper - _PaperGrain * 0.5;
                // Paper tint blend
                col = lerp(col, col * _PaperTint.rgb, _PaperBlend);

                // ---- Apply ink outlines ----
                // Vary ink opacity slightly for hand-drawn feel
                float inkVar = 0.85 + valueNoise(uv * 200.0) * 0.15;
                col = lerp(col, _InkColor.rgb, outline * _OutlineStrength * inkVar);

                // ---- Vignette ----
                float2 vc = uv - 0.5;
                float vd = length(vc);
                float vig = 1.0 - smoothstep(0.35, 0.85, vd);
                col = lerp(col, col * _VignetteColor.rgb, (1.0 - vig) * _Vignette);

                col = saturate(col);
                col = lerp(original, col, _Intensity);

                return float4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
