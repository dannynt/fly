Shader "Custom/ThermalPost"
{
    Properties
    {
        [Header(Thermal Mode)]
        [KeywordEnum(Heat, Predator, XRay, Night)] _Mode ("Vision Mode", Float) = 0

        [Header(Heat Vision)]
        _HeatContrast ("Heat Contrast", Range(1, 5)) = 2.5
        [Toggle] _InvertHeat ("Invert Heat Map", Float) = 0

        [Header(Scan Effect)]
        [Toggle] _EnableScan ("Enable Scan Line", Float) = 1
        _ScanSpeed ("Scan Speed", Range(0.1, 3)) = 0.5
        _ScanWidth ("Scan Width", Range(0.01, 0.1)) = 0.03
        _ScanBrightness ("Scan Brightness", Range(0, 1)) = 0.4

        [Header(Noise)]
        [Toggle] _EnableNoise ("Enable Sensor Noise", Float) = 1
        _NoiseIntensity ("Noise Intensity", Range(0, 0.2)) = 0.06

        [Header(Edge Highlight)]
        [Toggle] _EnableEdge ("Enable Edge Highlight", Float) = 1
        _EdgeThickness ("Edge Thickness", Range(0.5, 4)) = 1.5
        _EdgeSensitivity ("Edge Sensitivity", Range(0.01, 0.3)) = 0.08

        [Header(UI Overlay)]
        [Toggle] _EnableGrid ("Enable Grid Overlay", Float) = 0
        _GridSize ("Grid Size", Range(10, 100)) = 40
        _GridAlpha ("Grid Opacity", Range(0, 0.3)) = 0.1

        [Header(Vignette)]
        [Toggle] _EnableVignette ("Enable Scope Vignette", Float) = 1
        _VigRadius ("Vignette Radius", Range(0.2, 0.8)) = 0.5
        _VigSoftness ("Vignette Softness", Range(0.05, 0.5)) = 0.2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ThermalPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Mode;
            float _HeatContrast;
            float _InvertHeat;
            float _EnableScan;
            float _ScanSpeed;
            float _ScanWidth;
            float _ScanBrightness;
            float _EnableNoise;
            float _NoiseIntensity;
            float _EnableEdge;
            float _EdgeThickness;
            float _EdgeSensitivity;
            float _EnableGrid;
            float _GridSize;
            float _GridAlpha;
            float _EnableVignette;
            float _VigRadius;
            float _VigSoftness;

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

            // Heat map: blue -> cyan -> green -> yellow -> red -> white
            half3 HeatPalette(float t)
            {
                t = saturate(t);
                half3 c;
                if (t < 0.2)
                    c = lerp(half3(0, 0, 0.3), half3(0, 0, 1), t / 0.2);
                else if (t < 0.4)
                    c = lerp(half3(0, 0, 1), half3(0, 1, 0.5), (t - 0.2) / 0.2);
                else if (t < 0.6)
                    c = lerp(half3(0, 1, 0.5), half3(1, 1, 0), (t - 0.4) / 0.2);
                else if (t < 0.8)
                    c = lerp(half3(1, 1, 0), half3(1, 0.3, 0), (t - 0.6) / 0.2);
                else
                    c = lerp(half3(1, 0.3, 0), half3(1, 1, 1), (t - 0.8) / 0.2);
                return c;
            }

            // Predator vision: mostly green/yellow thermal
            half3 PredatorPalette(float t)
            {
                t = saturate(t);
                half3 cold = half3(0.05, 0.05, 0.15);
                half3 mid = half3(0.1, 0.4, 0.1);
                half3 warm = half3(0.8, 0.8, 0.0);
                half3 hot = half3(1.0, 0.2, 0.0);

                if (t < 0.33)
                    return lerp(cold, mid, t / 0.33);
                else if (t < 0.66)
                    return lerp(mid, warm, (t - 0.33) / 0.33);
                else
                    return lerp(warm, hot, (t - 0.66) / 0.34);
            }

            // X-Ray: inverted blue-ish look
            half3 XRayPalette(float t)
            {
                t = 1.0 - saturate(t); // invert
                half3 dark = half3(0, 0, 0.05);
                half3 bone = half3(0.7, 0.8, 1.0);
                return lerp(dark, bone, t * t);
            }

            // Night vision: green monochrome
            half3 NightPalette(float t)
            {
                t = saturate(t);
                return half3(t * 0.1, t * 0.9, t * 0.15);
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texelSize = _BlitTexture_TexelSize.xy;
                float time = _Time.y;

                half4 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                half lum = Luminance3(col.rgb);

                // Apply contrast
                lum = saturate(pow(lum, 1.0 / _HeatContrast));
                if (_InvertHeat > 0.5) lum = 1.0 - lum;

                // --- Pick palette based on mode ---
                half3 result;
                int mode = (int)_Mode;
                if (mode == 0)
                    result = HeatPalette(lum);
                else if (mode == 1)
                    result = PredatorPalette(lum);
                else if (mode == 2)
                    result = XRayPalette(lum);
                else
                    result = NightPalette(lum);

                // --- Edge highlight ---
                if (_EnableEdge > 0.5)
                {
                    float2 off = texelSize * _EdgeThickness;
                    half lumL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x, 0)).rgb);
                    half lumR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( off.x, 0)).rgb);
                    half lumU = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,  off.y)).rgb);
                    half lumD = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, -off.y)).rgb);

                    float edge = abs(lumL - lumR) + abs(lumU - lumD);
                    edge = smoothstep(_EdgeSensitivity * 0.5, _EdgeSensitivity, edge);

                    // Bright edge in palette's highlight color
                    result += edge * 0.5;
                }

                // --- sensor noise ---
                if (_EnableNoise > 0.5)
                {
                    float noise = Hash21(uv * _ScreenParams.xy + time * 500.0);
                    result += (noise - 0.5) * _NoiseIntensity;
                }

                // --- Scan line ---
                if (_EnableScan > 0.5)
                {
                    float scanPos = frac(time * _ScanSpeed);
                    float dist = abs(uv.y - scanPos);
                    dist = min(dist, 1.0 - dist);
                    float scanMask = smoothstep(_ScanWidth, 0.0, dist);
                    result += scanMask * _ScanBrightness;
                }

                // --- Grid overlay ---
                if (_EnableGrid > 0.5)
                {
                    float2 gridUV = uv * _ScreenParams.xy;
                    float gridX = step(0.95, frac(gridUV.x / _GridSize));
                    float gridY = step(0.95, frac(gridUV.y / _GridSize));
                    float grid = max(gridX, gridY);
                    result = lerp(result, result + 0.3, grid * _GridAlpha);
                }

                // --- Scope vignette ---
                if (_EnableVignette > 0.5)
                {
                    float2 vigUV = uv - 0.5;
                    float vigDist = length(vigUV);
                    float vig = 1.0 - smoothstep(_VigRadius - _VigSoftness, _VigRadius, vigDist);
                    result *= vig;

                    // Circle edge
                    float ring = smoothstep(_VigRadius, _VigRadius - 0.005, vigDist) - smoothstep(_VigRadius - 0.005, _VigRadius - 0.01, vigDist);
                    if (mode == 3) // night vision green ring
                        result += ring * half3(0, 0.5, 0);
                    else
                        result += ring * 0.3;
                }

                return half4(saturate(result), 1.0);
            }

            ENDHLSL
        }
    }
}
