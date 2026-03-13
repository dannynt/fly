Shader "Custom/NeonPost"
{
    Properties
    {
        [Header(Neon Edges)]
        [Toggle] _EnableNeonEdges ("Enable Neon Edges", Float) = 1
        _NeonThickness ("Edge Thickness", Range(0.5, 5)) = 1.5
        _NeonSensitivity ("Edge Sensitivity", Range(0.01, 0.5)) = 0.1
        _NeonGlow ("Glow Intensity", Range(0, 5)) = 2.5
        _NeonColor1 ("Neon Color 1", Color) = (0, 1, 1, 1)
        _NeonColor2 ("Neon Color 2", Color) = (1, 0, 1, 1)
        _NeonColorSpeed ("Color Cycle Speed", Range(0, 5)) = 1

        [Header(Contrast and Darken)]
        _DarkenAmount ("Background Darken", Range(0, 0.95)) = 0.6
        _ContrastBoost ("Contrast", Range(1, 3)) = 1.5

        [Header(Bloom Fake)]
        [Toggle] _EnableBloom ("Enable Glow Bloom", Float) = 1
        _BloomSpread ("Bloom Spread", Range(1, 8)) = 3
        _BloomIntensity ("Bloom Intensity", Range(0, 2)) = 0.8
        _BloomThreshold ("Bloom Threshold", Range(0, 1)) = 0.5

        [Header(Color Grading)]
        [Toggle] _EnableGrading ("Enable Cyberpunk Grading", Float) = 1
        _TintShadows ("Shadow Tint", Color) = (0.05, 0, 0.15, 1)
        _TintHighlights ("Highlight Tint", Color) = (0, 0.2, 0.3, 1)

        [Header(Scanlines)]
        [Toggle] _EnableScanlines ("Enable Scanlines", Float) = 0
        _ScanlineAlpha ("Scanline Opacity", Range(0, 0.5)) = 0.15
        _ScanlineDensity ("Scanline Density", Range(200, 2000)) = 800
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "NeonPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _EnableNeonEdges;
            float _NeonThickness;
            float _NeonSensitivity;
            float _NeonGlow;
            half4 _NeonColor1;
            half4 _NeonColor2;
            float _NeonColorSpeed;
            float _DarkenAmount;
            float _ContrastBoost;
            float _EnableBloom;
            float _BloomSpread;
            float _BloomIntensity;
            float _BloomThreshold;
            float _EnableGrading;
            half4 _TintShadows;
            half4 _TintHighlights;
            float _EnableScanlines;
            float _ScanlineAlpha;
            float _ScanlineDensity;

            half Luminance3(half3 c)
            {
                return dot(c, half3(0.2126, 0.7152, 0.0722));
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texelSize = _BlitTexture_TexelSize.xy;

                half4 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);

                // --- Contrast boost ---
                col.rgb = saturate((col.rgb - 0.5) * _ContrastBoost + 0.5);

                // --- Darken background ---
                col.rgb *= (1.0 - _DarkenAmount);

                // --- Color grading: tint shadows/highlights ---
                if (_EnableGrading > 0.5)
                {
                    half lum = Luminance3(col.rgb);
                    half3 shadowTint = lerp(col.rgb, col.rgb + _TintShadows.rgb, 1.0 - lum);
                    half3 highTint = lerp(shadowTint, shadowTint + _TintHighlights.rgb, lum);
                    col.rgb = highTint;
                }

                // --- Neon edges ---
                if (_EnableNeonEdges > 0.5)
                {
                    float2 offset = texelSize * _NeonThickness;

                    // Sobel on luminance
                    half lumTL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x,  offset.y)).rgb);
                    half lumT  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,          offset.y)).rgb);
                    half lumTR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x,  offset.y)).rgb);
                    half lumL  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x,  0)).rgb);
                    half lumR  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x,  0)).rgb);
                    half lumBL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x, -offset.y)).rgb);
                    half lumB  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,         -offset.y)).rgb);
                    half lumBR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x, -offset.y)).rgb);

                    half sobelX = lumTL + 2.0 * lumL + lumBL - lumTR - 2.0 * lumR - lumBR;
                    half sobelY = lumTL + 2.0 * lumT + lumTR - lumBL - 2.0 * lumB - lumBR;
                    half edgeStrength = sqrt(sobelX * sobelX + sobelY * sobelY);
                    edgeStrength = smoothstep(_NeonSensitivity * 0.5, _NeonSensitivity, edgeStrength);

                    // Color cycling between two neon colors
                    float t = sin(_Time.y * _NeonColorSpeed) * 0.5 + 0.5;
                    half3 neonCol = lerp(_NeonColor1.rgb, _NeonColor2.rgb, t);

                    // Also shift hue based on screen position for rainbow effect
                    float hueShift = uv.x + uv.y + _Time.y * _NeonColorSpeed * 0.3;
                    half3 rainbow = half3(
                        sin(hueShift * 6.28) * 0.5 + 0.5,
                        sin(hueShift * 6.28 + 2.09) * 0.5 + 0.5,
                        sin(hueShift * 6.28 + 4.19) * 0.5 + 0.5
                    );
                    neonCol = lerp(neonCol, rainbow, 0.3);

                    col.rgb += neonCol * edgeStrength * _NeonGlow;
                }

                // --- Fake bloom (box blur on bright areas) ---
                if (_EnableBloom > 0.5)
                {
                    half3 bloom = half3(0, 0, 0);
                    float2 bloomOffset = texelSize * _BloomSpread;
                    int samples = 0;

                    for (int x = -2; x <= 2; x++)
                    {
                        for (int y = -2; y <= 2; y++)
                        {
                            half3 s = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(x, y) * bloomOffset).rgb;
                            half sLum = Luminance3(s);
                            bloom += s * step(_BloomThreshold, sLum);
                            samples++;
                        }
                    }
                    bloom /= (float)samples;
                    col.rgb += bloom * _BloomIntensity;
                }

                // --- Scanlines ---
                if (_EnableScanlines > 0.5)
                {
                    float scanline = sin(uv.y * _ScanlineDensity) * 0.5 + 0.5;
                    col.rgb *= 1.0 - scanline * _ScanlineAlpha;
                }

                return col;
            }

            ENDHLSL
        }
    }
}
