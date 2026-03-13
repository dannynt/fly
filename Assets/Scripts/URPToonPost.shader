Shader "Custom/URPToonPost"
{
    Properties
    {
        [Header(Posterization)]
        _Steps ("Color Steps", Range(2, 16)) = 4

        [Header(Outlines)]
        [Toggle] _EnableOutlines ("Enable Outlines", Float) = 1
        _OutlineThickness ("Outline Thickness", Range(0.5, 5)) = 1.0
        _OutlineDepthThreshold ("Depth Threshold", Range(0.0001, 0.05)) = 0.002
        _OutlineNormalThreshold ("Normal Threshold", Range(0.01, 1)) = 0.3
        _OutlineColor ("Outline Color", Color) = (0, 0, 0, 1)

        [Header(Color)]
        _Saturation ("Saturation Boost", Range(0.5, 2.5)) = 1.3
        _Brightness ("Brightness", Range(0.8, 1.5)) = 1.05

        [Header(Halftone Dots)]
        [Toggle] _EnableHalftone ("Enable Halftone Dots", Float) = 1
        _HalftoneScale ("Dot Grid Size", Range(2, 30)) = 8
        _HalftoneStrength ("Dot Strength", Range(0, 1)) = 0.6
        _HalftoneShadowOnly ("Shadows Only", Range(0, 1)) = 0.5
        [Toggle] _HalftoneColor ("Colored Dots (vs Black)", Float) = 0

        [Header(Hatching)]
        [Toggle] _EnableHatching ("Enable Hatching in Shadows", Float) = 0
        _HatchThreshold ("Hatch Shadow Threshold", Range(0.0, 0.5)) = 0.2
        _HatchDensity ("Hatch Density", Range(20, 200)) = 80

        [Header(Vignette)]
        [Toggle] _EnableVignette ("Enable Vignette", Float) = 1
        _VignetteIntensity ("Vignette Intensity", Range(0, 2)) = 0.8
        _VignetteSmoothness ("Vignette Smoothness", Range(0.01, 1)) = 0.4
        _VignetteColor ("Vignette Color", Color) = (0, 0, 0, 1)

        [Header(Color Fringe)]
        [Toggle] _EnableFringe ("Enable Color Fringe", Float) = 0
        _FringeOffset ("Fringe Offset", Range(0.0005, 0.01)) = 0.003

        [Header(Paper Texture)]
        [Toggle] _EnablePaper ("Enable Paper Grain", Float) = 0
        _PaperStrength ("Paper Strength", Range(0, 0.5)) = 0.15
        _PaperScale ("Paper Scale", Range(50, 800)) = 300
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ToonPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Steps;
            float _EnableOutlines;
            float _OutlineThickness;
            float _OutlineDepthThreshold;
            float _OutlineNormalThreshold;
            half4 _OutlineColor;
            float _Saturation;
            float _Brightness;

            float _EnableHalftone;
            float _HalftoneScale;
            float _HalftoneStrength;
            float _HalftoneShadowOnly;
            float _HalftoneColor;

            float _EnableHatching;
            float _HatchThreshold;
            float _HatchDensity;

            float _EnableVignette;
            float _VignetteIntensity;
            float _VignetteSmoothness;
            half4 _VignetteColor;

            float _EnableFringe;
            float _FringeOffset;

            float _EnablePaper;
            float _PaperStrength;
            float _PaperScale;

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            float SampleDepth(float2 uv)
            {
                return SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
            }

            half Luminance3(half3 c)
            {
                return dot(c, half3(0.2126, 0.7152, 0.0722));
            }

            // Simple hash for procedural noise
            float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            half4 Frag (Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texelSize = _BlitTexture_TexelSize.xy;

                // --- Color fringe (chromatic aberration) ---
                half4 col;
                if (_EnableFringe > 0.5)
                {
                    float2 dir = uv - 0.5;
                    float dist = length(dir);
                    float2 offset = dir * dist * _FringeOffset;
                    col.r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + offset).r;
                    col.g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).g;
                    col.b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv - offset).b;
                    col.a = 1.0;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                }

                // --- Saturation & brightness ---
                half lum = Luminance3(col.rgb);
                col.rgb = lerp(half3(lum, lum, lum), col.rgb, _Saturation);
                col.rgb *= _Brightness;

                // --- Posterize ---
                col.rgb = floor(col.rgb * _Steps + 0.5) / _Steps;

                // --- Edge detection (depth + luminance Sobel) ---
                if (_EnableOutlines > 0.5)
                {
                    float2 offset = texelSize * _OutlineThickness;

                    float dC = SampleDepth(uv);
                    float dL = SampleDepth(uv + float2(-offset.x, 0));
                    float dR = SampleDepth(uv + float2( offset.x, 0));
                    float dU = SampleDepth(uv + float2(0,  offset.y));
                    float dD = SampleDepth(uv + float2(0, -offset.y));
                    float depthEdge = abs(dL - dC) + abs(dR - dC) + abs(dU - dC) + abs(dD - dC);
                    depthEdge = step(_OutlineDepthThreshold, depthEdge);

                    half lumTL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x,  offset.y)).rgb);
                    half lumT  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,          offset.y)).rgb);
                    half lumTR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x,  offset.y)).rgb);
                    half lumL  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x, 0)).rgb);
                    half lumR  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x, 0)).rgb);
                    half lumBL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x, -offset.y)).rgb);
                    half lumB  = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,         -offset.y)).rgb);
                    half lumBR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x, -offset.y)).rgb);

                    half sobelX = lumTL + 2.0 * lumL + lumBL - lumTR - 2.0 * lumR - lumBR;
                    half sobelY = lumTL + 2.0 * lumT + lumTR - lumBL - 2.0 * lumB - lumBR;
                    half normalEdge = sqrt(sobelX * sobelX + sobelY * sobelY);
                    normalEdge = step(_OutlineNormalThreshold, normalEdge);

                    half edge = saturate(depthEdge + normalEdge);
                    col.rgb = lerp(col.rgb, _OutlineColor.rgb, edge);
                }

                // --- Halftone dots ---
                if (_EnableHalftone > 0.5)
                {
                    float2 pixelPos = uv * _ScreenParams.xy;
                    float2 gridPos = pixelPos / _HalftoneScale;
                    float2 cellCenter = (floor(gridPos) + 0.5) * _HalftoneScale;
                    float distToCenter = length(pixelPos - cellCenter) / (_HalftoneScale * 0.5);

                    half lumH = Luminance3(col.rgb);
                    // Darker areas get bigger dots
                    float dotRadius = 1.0 - lumH;
                    // Blend between shadow-only and full-range
                    dotRadius = lerp(dotRadius, dotRadius * step(lumH, 0.5) * 2.0, _HalftoneShadowOnly);

                    float dotMask = smoothstep(dotRadius, dotRadius + 0.15, distToCenter);

                    if (_HalftoneColor > 0.5)
                    {
                        // Colored dots: darken with own color
                        half3 dotColor = col.rgb * 0.4;
                        col.rgb = lerp(dotColor, col.rgb, lerp(1.0, dotMask, _HalftoneStrength));
                    }
                    else
                    {
                        // Black dots
                        col.rgb = lerp(col.rgb * (1.0 - _HalftoneStrength), col.rgb, dotMask);
                    }
                }

                // --- Cross-hatching in dark areas ---
                if (_EnableHatching > 0.5)
                {
                    half lumFinal = Luminance3(col.rgb);
                    if (lumFinal < _HatchThreshold)
                    {
                        float2 pixelPos = uv * _ScreenParams.xy;
                        float hatch1 = step(0.5, frac((pixelPos.x + pixelPos.y) / _HatchDensity * 10.0));
                        float hatch2 = step(0.5, frac((pixelPos.x - pixelPos.y) / _HatchDensity * 10.0));
                        float hatchMask = min(hatch1, hatch2);
                        float darkness = 1.0 - smoothstep(0.0, _HatchThreshold, lumFinal);
                        col.rgb = lerp(col.rgb, col.rgb * (1.0 - 0.4 * darkness), 1.0 - hatchMask);
                    }
                }

                // --- Paper grain texture ---
                if (_EnablePaper > 0.5)
                {
                    float2 paperUV = uv * _PaperScale;
                    float noise = Hash21(floor(paperUV));
                    noise = noise * 2.0 - 1.0; // -1 to 1
                    col.rgb += noise * _PaperStrength;
                }

                // --- Vignette ---
                if (_EnableVignette > 0.5)
                {
                    float2 vigUV = uv - 0.5;
                    float vigDist = length(vigUV);
                    float vig = smoothstep(0.5, 0.5 - _VignetteSmoothness, vigDist) ;
                    vig = pow(vig, _VignetteIntensity);
                    col.rgb = lerp(_VignetteColor.rgb, col.rgb, vig);
                }

                return col;
            }

            ENDHLSL
        }
    }
}