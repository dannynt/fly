Shader "Custom/PopArtPost"
{
    Properties
    {
        [Header(Color Palette)]
        [KeywordEnum(Classic, Warhol, Neon, Pastel)] _Palette ("Color Palette", Float) = 0
        _ColorCount ("Color Levels", Range(2, 6)) = 4
        _Saturation ("Saturation", Range(1, 4)) = 2.5
        _Contrast ("Contrast", Range(1, 3)) = 1.8

        [Header(Ben Day Dots)]
        [Toggle] _EnableDots ("Enable Ben-Day Dots", Float) = 1
        _DotScale ("Dot Scale", Range(3, 25)) = 10
        _DotStrength ("Dot Strength", Range(0, 1)) = 0.7
        [KeywordEnum(Round, Diamond, Square)] _DotShape ("Dot Shape", Float) = 0

        [Header(Bold Outlines)]
        [Toggle] _EnableOutlines ("Enable Bold Outlines", Float) = 1
        _OutlineThick ("Outline Thickness", Range(1, 6)) = 2.5
        _OutlineSens ("Outline Sensitivity", Range(0.02, 0.3)) = 0.1
        _OutlineCol ("Outline Color", Color) = (0, 0, 0, 1)

        [Header(Color Channel Split)]
        [Toggle] _EnableSplit ("Enable CMYK Split Look", Float) = 0
        _SplitOffset ("Split Offset", Range(0.001, 0.008)) = 0.003

        [Header(Speed Lines)]
        [Toggle] _EnableSpeedLines ("Enable Impact Lines", Float) = 0
        _SpeedLineCount ("Line Count", Range(8, 64)) = 24
        _SpeedLineWidth ("Line Width", Range(0.01, 0.1)) = 0.03
        _SpeedLineInner ("Inner Clear Radius", Range(0.1, 0.5)) = 0.3
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "PopArtPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Palette;
            float _ColorCount;
            float _Saturation;
            float _Contrast;
            float _EnableDots;
            float _DotScale;
            float _DotStrength;
            float _DotShape;
            float _EnableOutlines;
            float _OutlineThick;
            float _OutlineSens;
            half4 _OutlineCol;
            float _EnableSplit;
            float _SplitOffset;
            float _EnableSpeedLines;
            float _SpeedLineCount;
            float _SpeedLineWidth;
            float _SpeedLineInner;

            half Luminance3(half3 c)
            {
                return dot(c, half3(0.2126, 0.7152, 0.0722));
            }

            // Palette color remap
            half3 RemapPalette(half3 col, int palette)
            {
                // Quantize first
                col = floor(col * _ColorCount + 0.5) / _ColorCount;

                if (palette == 1) // Warhol: push towards primary/secondary colors
                {
                    half maxC = max(col.r, max(col.g, col.b));
                    half minC = min(col.r, min(col.g, col.b));
                    float range = maxC - minC + 0.001;
                    col = (col - minC) / range; // normalize
                    col = pow(col, 0.6); // push towards extremes
                    col *= half3(1.0, 0.85, 0.3); // warm warhol tint
                }
                else if (palette == 2) // Neon
                {
                    col = pow(col, 0.5);
                    col *= half3(1.2, 0.8, 1.3);
                }
                else if (palette == 3) // Pastel
                {
                    col = lerp(half3(0.5, 0.5, 0.5), col, 0.6);
                    col += 0.2;
                }

                return saturate(col);
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texelSize = _BlitTexture_TexelSize.xy;

                // --- CMYK-style offset sampling ---
                half3 col;
                if (_EnableSplit > 0.5)
                {
                    float off = _SplitOffset;
                    col.r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(off, 0)).r;
                    col.g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).g;
                    col.b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, off)).b;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                }

                // --- Boost saturation + contrast ---
                half lum = Luminance3(col);
                col = lerp(half3(lum, lum, lum), col, _Saturation);
                col = saturate((col - 0.5) * _Contrast + 0.5);

                // --- Apply palette remap ---
                int palette = (int)_Palette;
                col = RemapPalette(col, palette);

                // --- Ben-Day dots ---
                if (_EnableDots > 0.5)
                {
                    float2 pixelPos = uv * _ScreenParams.xy;
                    float2 gridPos = pixelPos / _DotScale;
                    float2 cellPos = frac(gridPos) - 0.5;

                    float dotDist;
                    int shape = (int)_DotShape;
                    if (shape == 0) // Round
                        dotDist = length(cellPos);
                    else if (shape == 1) // Diamond
                        dotDist = abs(cellPos.x) + abs(cellPos.y);
                    else // Square
                        dotDist = max(abs(cellPos.x), abs(cellPos.y));

                    // Dot size based on luminance (darker = bigger dots)
                    half lumD = Luminance3(col);
                    float dotRadius = (1.0 - lumD) * 0.5;
                    float dotMask = smoothstep(dotRadius, dotRadius + 0.05, dotDist);

                    // Apply dots: show paper color (white) through dots
                    half3 paperWhite = half3(1, 1, 0.97);
                    col = lerp(col, lerp(paperWhite, col, dotMask), _DotStrength);
                }

                // --- Bold outlines ---
                if (_EnableOutlines > 0.5)
                {
                    float2 off = texelSize * _OutlineThick;

                    half lumTL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x,  off.y)).rgb);
                    half lumT  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,       off.y)).rgb);
                    half lumTR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( off.x,  off.y)).rgb);
                    half lumL  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x,  0)).rgb);
                    half lumR  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( off.x,  0)).rgb);
                    half lumBL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x, -off.y)).rgb);
                    half lumB  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,      -off.y)).rgb);
                    half lumBR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( off.x, -off.y)).rgb);

                    half sx = lumTL + 2.0 * lumL + lumBL - lumTR - 2.0 * lumR - lumBR;
                    half sy = lumTL + 2.0 * lumT + lumTR - lumBL - 2.0 * lumB - lumBR;
                    half edge = sqrt(sx * sx + sy * sy);
                    edge = smoothstep(_OutlineSens * 0.3, _OutlineSens, edge);

                    col = lerp(col, _OutlineCol.rgb, edge);
                }

                // --- Impact / speed lines ---
                if (_EnableSpeedLines > 0.5)
                {
                    float2 center = uv - 0.5;
                    float angle = atan2(center.y, center.x);
                    float dist = length(center);

                    float lines = abs(sin(angle * _SpeedLineCount));
                    lines = step(1.0 - _SpeedLineWidth, lines);

                    float outerMask = step(_SpeedLineInner, dist);
                    lines *= outerMask;

                    col = lerp(col, _OutlineCol.rgb, lines * 0.6);
                }

                return half4(saturate(col), 1.0);
            }

            ENDHLSL
        }
    }
}
