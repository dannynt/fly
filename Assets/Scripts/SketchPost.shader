Shader "Custom/SketchPost"
{
    Properties
    {
        [Header(Sketch Lines)]
        _LinesDensity ("Lines Density", Range(50, 600)) = 200
        _LinesThickness ("Lines Thickness", Range(0.1, 0.9)) = 0.45
        _DarkThreshold ("Dark Threshold (more lines)", Range(0.1, 0.9)) = 0.6
        _MidThreshold ("Mid Threshold (fewer lines)", Range(0.0, 0.5)) = 0.3

        [Header(Edge Ink)]
        [Toggle] _EnableEdgeInk ("Enable Edge Ink", Float) = 1
        _EdgeThickness ("Edge Thickness", Range(0.5, 4)) = 1.5
        _EdgeThreshold ("Edge Sensitivity", Range(0.01, 0.5)) = 0.15

        [Header(Paper)]
        _PaperColor ("Paper Color", Color) = (0.95, 0.93, 0.88, 1)
        _InkColor ("Ink Color", Color) = (0.15, 0.12, 0.1, 1)

        [Header(Wobble)]
        [Toggle] _EnableWobble ("Enable Hand-Drawn Wobble", Float) = 1
        _WobbleAmount ("Wobble Amount", Range(0, 0.005)) = 0.001
        _WobbleSpeed ("Wobble Speed", Range(0, 10)) = 3

        [Header(Color Wash)]
        [Toggle] _EnableColorWash ("Keep Subtle Color", Float) = 1
        _ColorWashStrength ("Color Strength", Range(0, 0.6)) = 0.25
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "SketchPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _LinesDensity;
            float _LinesThickness;
            float _DarkThreshold;
            float _MidThreshold;
            float _EnableEdgeInk;
            float _EdgeThickness;
            float _EdgeThreshold;
            half4 _PaperColor;
            half4 _InkColor;
            float _EnableWobble;
            float _WobbleAmount;
            float _WobbleSpeed;
            float _EnableColorWash;
            float _ColorWashStrength;

            float Hash21(float2 p)
            {
                p = frac(p * float2(443.8975, 397.2973));
                p += dot(p, p.yx + 19.19);
                return frac(p.x * p.y);
            }

            half Luminance3(half3 c)
            {
                return dot(c, half3(0.2126, 0.7152, 0.0722));
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texelSize = _BlitTexture_TexelSize.xy;

                // --- Hand-drawn wobble ---
                if (_EnableWobble > 0.5)
                {
                    float noiseX = Hash21(floor(uv * 80.0) + floor(_Time.y * _WobbleSpeed));
                    float noiseY = Hash21(floor(uv * 80.0) + floor(_Time.y * _WobbleSpeed) + 100.0);
                    uv += (float2(noiseX, noiseY) - 0.5) * _WobbleAmount;
                }

                half4 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                half lum = Luminance3(col.rgb);

                // --- Sketch hatching lines ---
                float2 pixelPos = uv * _ScreenParams.xy;

                // Layer 1: diagonal lines (dark areas)
                float line1 = step(_LinesThickness, frac((pixelPos.x + pixelPos.y) / _LinesDensity * 10.0));
                float hatch1 = lerp(1.0, line1, step(lum, _DarkThreshold));

                // Layer 2: opposite diagonal (very dark areas)
                float line2 = step(_LinesThickness, frac((pixelPos.x - pixelPos.y) / _LinesDensity * 10.0));
                float hatch2 = lerp(1.0, line2, step(lum, _MidThreshold));

                // Layer 3: horizontal lines for deepest shadows
                float line3 = step(_LinesThickness + 0.1, frac(pixelPos.y / _LinesDensity * 10.0));
                float hatch3 = lerp(1.0, line3, step(lum, _MidThreshold * 0.5));

                float hatchFinal = min(hatch1, min(hatch2, hatch3));

                // --- Edge ink ---
                float edgeMask = 0.0;
                if (_EnableEdgeInk > 0.5)
                {
                    float2 offset = texelSize * _EdgeThickness;

                    half lumL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x, 0)).rgb);
                    half lumR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x, 0)).rgb);
                    half lumU = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,  offset.y)).rgb);
                    half lumD = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, -offset.y)).rgb);

                    float edgeX = abs(lumL - lumR);
                    float edgeY = abs(lumU - lumD);
                    edgeMask = step(_EdgeThreshold, edgeX + edgeY);
                }

                // --- Compose: paper + ink ---
                half3 sketchColor = lerp(_InkColor.rgb, _PaperColor.rgb, hatchFinal);
                sketchColor = lerp(sketchColor, _InkColor.rgb, edgeMask);

                // --- Optional color wash ---
                if (_EnableColorWash > 0.5)
                {
                    half3 tinted = lerp(sketchColor, col.rgb, _ColorWashStrength);
                    sketchColor = tinted;
                }

                // --- Paper grain noise ---
                float grain = Hash21(floor(uv * 500.0));
                sketchColor += (grain - 0.5) * 0.04;

                return half4(sketchColor, 1.0);
            }

            ENDHLSL
        }
    }
}
