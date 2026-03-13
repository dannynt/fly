Shader "Custom/HologramPost"
{
    Properties
    {
        [Header(Hologram Base)]
        _HoloColor ("Primary Holo Color", Color) = (0, 0.8, 1, 1)
        _HoloColor2 ("Secondary Holo Color", Color) = (0, 1, 0.5, 1)
        _SceneRetain ("Scene Color Retain", Range(0, 0.5)) = 0.15
        _WireframeAlpha ("Wireframe Transparency", Range(0.3, 1)) = 0.85

        [Header(Scan Lines)]
        [Toggle] _EnableScanLines ("Enable Scan Lines", Float) = 1
        _ScanDensity ("Scan Line Density", Range(100, 3000)) = 800
        _ScanSpeed ("Scan Scroll Speed", Range(0, 10)) = 3
        _ScanAlpha ("Scan Line Alpha", Range(0, 0.5)) = 0.2

        [Header(Horizontal Glitch)]
        [Toggle] _EnableGlitch ("Enable Holo Glitch", Float) = 1
        _GlitchIntensity ("Glitch Intensity", Range(0, 0.05)) = 0.015
        _GlitchSpeed ("Glitch Speed", Range(1, 30)) = 10
        _GlitchBlockSize ("Glitch Block Size", Range(5, 50)) = 20

        [Header(Fresnel Edge Glow)]
        [Toggle] _EnableEdgeGlow ("Enable Edge Glow", Float) = 1
        _EdgeGlowThickness ("Edge Thickness", Range(0.5, 4)) = 1.5
        _EdgeGlowSens ("Edge Sensitivity", Range(0.02, 0.3)) = 0.08
        _EdgeGlowPower ("Glow Power", Range(1, 5)) = 2.5

        [Header(Flicker)]
        [Toggle] _EnableFlicker ("Enable Projection Flicker", Float) = 1
        _FlickerSpeed ("Flicker Speed", Range(5, 60)) = 20
        _FlickerAmount ("Flicker Amount", Range(0, 0.15)) = 0.05

        [Header(Data Stream)]
        [Toggle] _EnableData ("Enable Data Overlay", Float) = 0
        _DataScale ("Data Scale", Range(5, 30)) = 12
        _DataSpeed ("Data Scroll Speed", Range(1, 20)) = 8
        _DataAlpha ("Data Opacity", Range(0, 0.3)) = 0.1

        [Header(Chromatic Aberration)]
        [Toggle] _EnableChroma ("Enable Chromatic Split", Float) = 1
        _ChromaOffset ("Chroma Offset", Range(0.001, 0.008)) = 0.003

        [Header(Triangle Grid)]
        [Toggle] _EnableGrid ("Enable Holo Grid", Float) = 0
        _GridScale ("Grid Scale", Range(10, 80)) = 30
        _GridAlpha ("Grid Opacity", Range(0, 0.3)) = 0.08
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "HologramPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            half4 _HoloColor;
            half4 _HoloColor2;
            float _SceneRetain;
            float _WireframeAlpha;
            float _EnableScanLines;
            float _ScanDensity;
            float _ScanSpeed;
            float _ScanAlpha;
            float _EnableGlitch;
            float _GlitchIntensity;
            float _GlitchSpeed;
            float _GlitchBlockSize;
            float _EnableEdgeGlow;
            float _EdgeGlowThickness;
            float _EdgeGlowSens;
            float _EdgeGlowPower;
            float _EnableFlicker;
            float _FlickerSpeed;
            float _FlickerAmount;
            float _EnableData;
            float _DataScale;
            float _DataSpeed;
            float _DataAlpha;
            float _EnableChroma;
            float _ChromaOffset;
            float _EnableGrid;
            float _GridScale;
            float _GridAlpha;

            float Hash(float n) { return frac(sin(n) * 43758.5453); }
            float Hash21(float2 p)
            {
                p = frac(p * float2(443.897, 397.297));
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
                float time = _Time.y;

                // --- Glitch offset ---
                if (_EnableGlitch > 0.5)
                {
                    float blockY = floor(uv.y * _GlitchBlockSize);
                    float timeSlot = floor(time * _GlitchSpeed);
                    float r = Hash(blockY + timeSlot * 37.0);
                    if (r > 0.88)
                    {
                        float shift = (Hash(blockY * 3.0 + timeSlot) - 0.5) * 2.0 * _GlitchIntensity;
                        uv.x += shift;
                    }
                }

                // --- Chromatic aberration ---
                half3 col;
                if (_EnableChroma > 0.5)
                {
                    col.r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(_ChromaOffset, 0)).r;
                    col.g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).g;
                    col.b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv - float2(_ChromaOffset, 0)).b;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                }

                // --- Convert to hologram ---
                half lum = Luminance3(col);

                // Mix between two holo colors based on height
                float colorMix = sin(uv.y * 6.28 + time * 0.5) * 0.5 + 0.5;
                half3 holoBase = lerp(_HoloColor.rgb, _HoloColor2.rgb, colorMix);

                // Hologram color = luminance * holo tint + slight original color
                half3 holo = lum * holoBase + col * _SceneRetain;

                // --- Edge glow (Sobel) ---
                if (_EnableEdgeGlow > 0.5)
                {
                    float2 off = texelSize * _EdgeGlowThickness;
                    half lumL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x, 0)).rgb);
                    half lumR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( off.x, 0)).rgb);
                    half lumU = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,  off.y)).rgb);
                    half lumD = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, -off.y)).rgb);
                    float edge = abs(lumL - lumR) + abs(lumU - lumD);
                    edge = smoothstep(_EdgeGlowSens * 0.3, _EdgeGlowSens, edge);
                    holo += holoBase * pow(edge, 1.0 / _EdgeGlowPower) * 2.0;
                }

                // --- Scan lines ---
                if (_EnableScanLines > 0.5)
                {
                    float scanLine = sin((uv.y + time * _ScanSpeed * 0.01) * _ScanDensity);
                    holo *= 1.0 - step(0.5, scanLine) * _ScanAlpha;

                    // Big slow scan bar
                    float bigScan = frac(time * _ScanSpeed * 0.05);
                    float barDist = abs(uv.y - bigScan);
                    barDist = min(barDist, 1.0 - barDist);
                    float bar = smoothstep(0.02, 0.0, barDist);
                    holo += holoBase * bar * 0.3;
                }

                // --- Projection flicker ---
                if (_EnableFlicker > 0.5)
                {
                    float flicker = 1.0 + sin(time * _FlickerSpeed) * sin(time * _FlickerSpeed * 1.7) * _FlickerAmount;
                    holo *= flicker;
                }

                // --- Data stream overlay (falling characters) ---
                if (_EnableData > 0.5)
                {
                    float2 dataUV = float2(floor(uv.x * _DataScale * 3.0), floor((uv.y - time * _DataSpeed * 0.05) * _DataScale));
                    float dataChar = Hash21(dataUV);
                    float dataBright = step(0.6, dataChar);
                    // Fade based on position
                    float dataFade = frac((uv.y - time * _DataSpeed * 0.05) * 2.0);
                    holo += holoBase * dataBright * dataFade * _DataAlpha;
                }

                // --- Triangle / hex grid ---
                if (_EnableGrid > 0.5)
                {
                    float2 gridUV = uv * _ScreenParams.xy / _GridScale;
                    float gridX = abs(frac(gridUV.x) - 0.5);
                    float gridY = abs(frac(gridUV.y) - 0.5);
                    float grid = step(0.48, gridX) + step(0.48, gridY);
                    // Diagonal lines for triangles
                    float diag = abs(frac(gridUV.x + gridUV.y) - 0.5);
                    grid += step(0.48, diag);
                    grid = saturate(grid);
                    holo += holoBase * grid * _GridAlpha;
                }

                // --- Transparency / wireframe alpha ---
                holo *= _WireframeAlpha;

                return half4(saturate(holo), 1.0);
            }

            ENDHLSL
        }
    }
}
