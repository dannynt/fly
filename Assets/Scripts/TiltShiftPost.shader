Shader "Custom/TiltShiftPost"
{
    Properties
    {
        [Header(Focus Band)]
        _FocusCenter ("Focus Center Y", Range(0, 1)) = 0.5
        _FocusWidth ("Focus Width", Range(0.02, 0.4)) = 0.15
        _FocusFalloff ("Focus Falloff", Range(0.01, 0.3)) = 0.1

        [Header(Blur)]
        _BlurSize ("Blur Size", Range(1, 12)) = 5
        _BlurQuality ("Blur Quality (Samples)", Range(1, 4)) = 2

        [Header(Miniature Colors)]
        [Toggle] _EnableColorBoost ("Enable Toy Colors", Float) = 1
        _SatBoost ("Saturation Boost", Range(1, 3)) = 1.8
        _ContrastBoost ("Contrast Boost", Range(1, 2.5)) = 1.4
        _Warmth ("Warm Tint", Range(0, 0.1)) = 0.03
        _BrightnessBoost ("Brightness Boost", Range(0.9, 1.3)) = 1.1

        [Header(Vignette)]
        [Toggle] _EnableVignette ("Enable Vignette", Float) = 1
        _VigAmount ("Vignette Amount", Range(0, 1.5)) = 0.7
        _VigSoftness ("Vignette Softness", Range(0.1, 0.6)) = 0.35

        [Header(Bokeh Sparkle)]
        [Toggle] _EnableBokeh ("Enable Bokeh Highlights", Float) = 1
        _BokehThreshold ("Bokeh Brightness Threshold", Range(0.6, 0.98)) = 0.8
        _BokehSize ("Bokeh Size", Range(0.5, 4)) = 2.0
        _BokehIntensity ("Bokeh Intensity", Range(0, 1)) = 0.4
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "TiltShiftPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _FocusCenter;
            float _FocusWidth;
            float _FocusFalloff;
            float _BlurSize;
            float _BlurQuality;
            float _EnableColorBoost;
            float _SatBoost;
            float _ContrastBoost;
            float _Warmth;
            float _BrightnessBoost;
            float _EnableVignette;
            float _VigAmount;
            float _VigSoftness;
            float _EnableBokeh;
            float _BokehThreshold;
            float _BokehSize;
            float _BokehIntensity;

            half Luminance3(half3 c)
            {
                return dot(c, half3(0.2126, 0.7152, 0.0722));
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texelSize = _BlitTexture_TexelSize.xy;

                // --- Calculate blur amount based on distance from focus band ---
                float distFromFocus = abs(uv.y - _FocusCenter);
                float blurMask = smoothstep(_FocusWidth, _FocusWidth + _FocusFalloff, distFromFocus);
                float blurRadius = blurMask * _BlurSize;

                // --- Directional (horizontal-heavy) blur for tilt-shift look ---
                half3 col = half3(0, 0, 0);
                int quality = (int)_BlurQuality;
                int totalSamples = 0;

                if (blurRadius > 0.1)
                {
                    for (int x = -3 * quality; x <= 3 * quality; x++)
                    {
                        for (int y = -1 * quality; y <= 1 * quality; y++)
                        {
                            float2 off = float2(x, y) * texelSize * blurRadius * 0.4;
                            // Weight: horizontal samples more (elliptical bokeh)
                            float weight = 1.0 / (1.0 + abs(x) * 0.3 + abs(y) * 0.5);
                            col += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + off).rgb * weight;
                            totalSamples++;
                        }
                    }
                    col /= (float)totalSamples;

                    // Blend between sharp and blurred
                    half3 sharp = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                    col = lerp(sharp, col, blurMask);
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                }

                // --- Bokeh sparkle on bright spots in blurred areas ---
                if (_EnableBokeh > 0.5 && blurMask > 0.1)
                {
                    half lumC = Luminance3(col);
                    if (lumC > _BokehThreshold)
                    {
                        // Check neighboring pixels for similar brightness (cluster detection)
                        float2 bokehOff = texelSize * _BokehSize;
                        half lumAvg = 0;
                        lumAvg += Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(bokehOff.x, 0)).rgb);
                        lumAvg += Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv - float2(bokehOff.x, 0)).rgb);
                        lumAvg += Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, bokehOff.y)).rgb);
                        lumAvg += Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv - float2(0, bokehOff.y)).rgb);
                        lumAvg *= 0.25;

                        float bokehStrength = smoothstep(_BokehThreshold, 1.0, lumC) * blurMask;
                        col += col * bokehStrength * _BokehIntensity;
                    }
                }

                // --- Miniature color boost ---
                if (_EnableColorBoost > 0.5)
                {
                    half lum = Luminance3(col);
                    col = lerp(half3(lum, lum, lum), col, _SatBoost);
                    col = saturate((col - 0.5) * _ContrastBoost + 0.5);
                    col.r += _Warmth;
                    col.b -= _Warmth * 0.5;
                    col *= _BrightnessBoost;
                }

                // --- Vignette ---
                if (_EnableVignette > 0.5)
                {
                    float2 vigUV = uv - 0.5;
                    float vigDist = length(vigUV);
                    float vig = smoothstep(0.5, 0.5 - _VigSoftness, vigDist);
                    vig = pow(vig, _VigAmount);
                    col *= vig;
                }

                return half4(saturate(col), 1.0);
            }

            ENDHLSL
        }
    }
}
