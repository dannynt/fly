Shader "Custom/OilPaintPost"
{
    Properties
    {
        [Header(Oil Paint Brush)]
        _BrushRadius ("Brush Radius", Range(1, 8)) = 3
        _Sharpness ("Paint Sharpness", Range(0.5, 5)) = 2.0

        [Header(Color Richness)]
        _Saturation ("Saturation Boost", Range(1, 2.5)) = 1.4
        _Contrast ("Contrast", Range(0.8, 2)) = 1.2
        _Steps ("Color Quantize", Range(8, 64)) = 24

        [Header(Brush Texture)]
        [Toggle] _EnableBrushStroke ("Enable Brush Strokes", Float) = 1
        _StrokeScale ("Stroke Scale", Range(20, 200)) = 80
        _StrokeStrength ("Stroke Visibility", Range(0, 0.15)) = 0.06

        [Header(Canvas)]
        [Toggle] _EnableCanvas ("Enable Canvas Texture", Float) = 1
        _CanvasScale ("Canvas Scale", Range(100, 600)) = 300
        _CanvasStrength ("Canvas Strength", Range(0, 0.12)) = 0.05

        [Header(Edge Paint)]
        [Toggle] _EnablePaintEdge ("Enable Thick Paint Edges", Float) = 1
        _PaintEdgeThickness ("Edge Thickness", Range(0.5, 4)) = 1.5
        _PaintEdgeSensitivity ("Edge Sensitivity", Range(0.02, 0.3)) = 0.08
        _PaintEdgeDarken ("Edge Darken", Range(0, 0.5)) = 0.2

        [Header(Impasto Highlight)]
        [Toggle] _EnableImpasto ("Enable Impasto (Thick Paint Shine)", Float) = 1
        _ImpastoThreshold ("Brightness Threshold", Range(0.5, 0.95)) = 0.75
        _ImpastoStrength ("Highlight Strength", Range(0, 0.3)) = 0.12
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "OilPaintPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _BrushRadius;
            float _Sharpness;
            float _Saturation;
            float _Contrast;
            float _Steps;
            float _EnableBrushStroke;
            float _StrokeScale;
            float _StrokeStrength;
            float _EnableCanvas;
            float _CanvasScale;
            float _CanvasStrength;
            float _EnablePaintEdge;
            float _PaintEdgeThickness;
            float _PaintEdgeSensitivity;
            float _PaintEdgeDarken;
            float _EnableImpasto;
            float _ImpastoThreshold;
            float _ImpastoStrength;

            float Hash21(float2 p)
            {
                p = frac(p * float2(443.897, 397.297));
                p += dot(p, p.yx + 19.19);
                return frac(p.x * p.y);
            }

            float ValueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                float a = Hash21(i);
                float b = Hash21(i + float2(1, 0));
                float c = Hash21(i + float2(0, 1));
                float d = Hash21(i + float2(1, 1));
                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            half Luminance3(half3 c)
            {
                return dot(c, half3(0.2126, 0.7152, 0.0722));
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texelSize = _BlitTexture_TexelSize.xy;
                int radius = (int)_BrushRadius;

                // --- Kuwahara filter (oil paint look) ---
                // Divide neighborhood into 4 quadrants, pick the one with lowest variance
                half3 mean[4];
                half3 variance[4];
                int count[4];

                for (int q = 0; q < 4; q++)
                {
                    mean[q] = half3(0, 0, 0);
                    variance[q] = half3(0, 0, 0);
                    count[q] = 0;
                }

                for (int ox = -radius; ox <= radius; ox++)
                {
                    for (int oy = -radius; oy <= radius; oy++)
                    {
                        half3 s = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(ox, oy) * texelSize).rgb;

                        // Determine quadrant
                        int qIdx = (ox >= 0 ? 1 : 0) + (oy >= 0 ? 2 : 0);
                        mean[qIdx] += s;
                        variance[qIdx] += s * s;
                        count[qIdx]++;
                    }
                }

                half minVar = 1e10;
                half3 result = half3(0, 0, 0);

                for (int q2 = 0; q2 < 4; q2++)
                {
                    float n = (float)count[q2];
                    mean[q2] /= n;
                    variance[q2] = variance[q2] / n - mean[q2] * mean[q2];
                    half totalVar = dot(variance[q2], half3(1, 1, 1));

                    if (totalVar < minVar)
                    {
                        minVar = totalVar;
                        result = mean[q2];
                    }
                }

                // --- Saturation & contrast ---
                half lum = Luminance3(result);
                result = lerp(half3(lum, lum, lum), result, _Saturation);
                result = saturate((result - 0.5) * _Contrast + 0.5);

                // --- Soft color quantize ---
                result = floor(result * _Steps + 0.5) / _Steps;

                // --- Brush stroke texture ---
                if (_EnableBrushStroke > 0.5)
                {
                    float2 strokeUV = uv * _StrokeScale;
                    // Directional streaks based on local luminance gradient
                    float angle = lum * 6.28;
                    float2 rotUV = float2(
                        strokeUV.x * cos(angle) - strokeUV.y * sin(angle),
                        strokeUV.x * sin(angle) + strokeUV.y * cos(angle)
                    );
                    float stroke = ValueNoise(float2(rotUV.x * 3.0, rotUV.y * 0.3));
                    result += (stroke - 0.5) * _StrokeStrength;
                }

                // --- Thick paint edges ---
                if (_EnablePaintEdge > 0.5)
                {
                    float2 off = texelSize * _PaintEdgeThickness;
                    half lumL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x, 0)).rgb);
                    half lumR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( off.x, 0)).rgb);
                    half lumU = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,  off.y)).rgb);
                    half lumD = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, -off.y)).rgb);
                    float edge = abs(lumL - lumR) + abs(lumU - lumD);
                    edge = smoothstep(_PaintEdgeSensitivity * 0.5, _PaintEdgeSensitivity, edge);
                    result *= (1.0 - edge * _PaintEdgeDarken);
                }

                // --- Impasto highlights (thick paint sheen on bright areas) ---
                if (_EnableImpasto > 0.5)
                {
                    half lumFinal = Luminance3(result);
                    float impasto = smoothstep(_ImpastoThreshold, 1.0, lumFinal);
                    float noiseImp = ValueNoise(uv * 150.0);
                    result += impasto * noiseImp * _ImpastoStrength;
                }

                // --- Canvas texture ---
                if (_EnableCanvas > 0.5)
                {
                    float2 canvasUV = uv * _CanvasScale;
                    float canvasX = sin(canvasUV.x * 6.28) * 0.5 + 0.5;
                    float canvasY = sin(canvasUV.y * 6.28) * 0.5 + 0.5;
                    float canvas = canvasX * canvasY;
                    result += (canvas - 0.5) * _CanvasStrength;
                }

                return half4(saturate(result), 1.0);
            }

            ENDHLSL
        }
    }
}
