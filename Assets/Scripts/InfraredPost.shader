Shader "Hidden/InfraredPost"
{
    Properties
    {
        _Intensity ("Effect Intensity", Range(0,1)) = 1
        _Mode ("Mode (0=Infrared Photo, 1=False Color, 2=Thermal Art)", Range(0,2)) = 0

        [Header(Infrared Photography)]
        _VegetationHue ("Vegetation Hue Threshold", Range(0,1)) = 0.35
        _VegetationRange ("Vegetation Hue Range", Range(0,0.2)) = 0.12
        _WhiteShift ("White Shift Amount", Range(0,1)) = 0.85
        _SkinWarmth ("Skin Warmth Shift", Range(0,1)) = 0.5
        _SkyDarken ("Sky Darkening", Range(0,1)) = 0.6

        [Header(False Color)]
        _ColorScale ("Color Scale", Range(0.5,3)) = 1.5
        _Gradient1 ("Cool Color", Color) = (0.05, 0.0, 0.3, 1)
        _Gradient2 ("Mid Color", Color) = (0.0, 0.8, 0.2, 1)
        _Gradient3 ("Warm Color", Color) = (1.0, 0.3, 0.0, 1)
        _Gradient4 ("Hot Color", Color) = (1.0, 1.0, 0.2, 1)

        [Header(Film Characteristics)]
        _Grain ("Film Grain", Range(0,0.15)) = 0.04
        _Halation ("Halation (IR Bloom)", Range(0,1)) = 0.35
        _HalationColor ("Halation Tint", Color) = (1.0, 0.85, 0.9, 1)
        _Vignette ("Vignette", Range(0,1)) = 0.3
        _Contrast ("Contrast Boost", Range(0.8,2)) = 1.15
        _Hotspot ("Hotspot Glow", Range(0,1)) = 0.25
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "InfraredPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Intensity;
            float _Mode;

            float _VegetationHue;
            float _VegetationRange;
            float _WhiteShift;
            float _SkinWarmth;
            float _SkyDarken;

            float _ColorScale;
            float4 _Gradient1;
            float4 _Gradient2;
            float4 _Gradient3;
            float4 _Gradient4;

            float _Grain;
            float _Halation;
            float4 _HalationColor;
            float _Vignette;
            float _Contrast;
            float _Hotspot;

            // ---- helpers ----
            float3 RGBtoHSV(float3 c)
            {
                float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
                float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
                float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
                float d = q.x - min(q.w, q.y);
                float e = 1.0e-10;
                return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
            }

            float3 HSVtoRGB(float3 c)
            {
                float3 p = abs(frac(c.xxx + float3(1.0,2.0/3.0,1.0/3.0)) * 6.0 - 3.0);
                return c.z * lerp(float3(1,1,1), saturate(p - 1.0), c.y);
            }

            float hash12(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            float4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float4 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                float3 original = col.rgb;

                float3 hsv = RGBtoHSV(original);
                float lum = dot(original, float3(0.299, 0.587, 0.114));
                int mode = (int)round(_Mode);
                float3 result = original;

                // ------ MODE 0: Infrared Photography ------
                if (mode == 0)
                {
                    // Detect vegetation by hue (greens)
                    float hueDist = abs(hsv.x - _VegetationHue);
                    hueDist = min(hueDist, 1.0 - hueDist);
                    float vegMask = 1.0 - smoothstep(0.0, _VegetationRange, hueDist);
                    vegMask *= smoothstep(0.1, 0.3, hsv.y); // must be somewhat saturated

                    // Detect sky (blue, high brightness)
                    float skyHueDist = abs(hsv.x - 0.6);
                    skyHueDist = min(skyHueDist, 1.0 - skyHueDist);
                    float skyMask = 1.0 - smoothstep(0.0, 0.15, skyHueDist);
                    skyMask *= smoothstep(0.1, 0.3, hsv.y);
                    skyMask *= smoothstep(0.3, 0.6, hsv.z);

                    // Detect skin tones (orange-ish hue, moderate sat)
                    float skinHueDist = abs(hsv.x - 0.08);
                    skinHueDist = min(skinHueDist, 1.0 - skinHueDist);
                    float skinMask = 1.0 - smoothstep(0.0, 0.08, skinHueDist);
                    skinMask *= smoothstep(0.15, 0.4, hsv.y);

                    // Base: convert to luminance for IR film
                    float irLum = lum;

                    // Vegetation turns white/pink in infrared
                    float3 vegColor = lerp(float3(irLum, irLum, irLum),
                                          float3(1.0, 0.92, 0.95), _WhiteShift);
                    vegColor = vegColor * (0.7 + irLum * 0.6);

                    // Sky darkens dramatically in IR
                    float3 skyColor = float3(irLum, irLum, irLum) * (1.0 - _SkyDarken * 0.7);

                    // Skin gets warm reddish tone
                    float3 skinColor = float3(irLum * 1.1, irLum * 0.85, irLum * 0.75);
                    skinColor = lerp(float3(irLum, irLum, irLum), skinColor, _SkinWarmth);

                    // Compose
                    float3 irBase = float3(irLum, irLum, irLum);
                    result = irBase;
                    result = lerp(result, vegColor, vegMask);
                    result = lerp(result, skyColor, skyMask * 0.7);
                    result = lerp(result, skinColor, skinMask * 0.5);

                    // Slight warm tint overall (IR film characteristic)
                    result = lerp(result, result * float3(1.05, 0.98, 0.93), 0.4);
                }
                // ------ MODE 1: False Color IR ------
                else if (mode == 1)
                {
                    // Map luminance to false color gradient
                    float t = saturate(lum * _ColorScale);

                    float3 fc;
                    if (t < 0.33)
                    {
                        fc = lerp(_Gradient1.rgb, _Gradient2.rgb, t / 0.33);
                    }
                    else if (t < 0.66)
                    {
                        fc = lerp(_Gradient2.rgb, _Gradient3.rgb, (t - 0.33) / 0.33);
                    }
                    else
                    {
                        fc = lerp(_Gradient3.rgb, _Gradient4.rgb, (t - 0.66) / 0.34);
                    }

                    // Mix in some original hue for interest
                    float3 hsvFC = RGBtoHSV(fc);
                    hsvFC.x = lerp(hsvFC.x, hsv.x, 0.15);
                    result = HSVtoRGB(hsvFC);
                }
                // ------ MODE 2: Thermal Art ------
                else
                {
                    // Artistic thermal with more stylized palette
                    float heat = saturate(lum * _ColorScale);

                    // 5 color stops for artistic thermal
                    float3 c1 = float3(0.0, 0.0, 0.15);  // deep blue-black
                    float3 c2 = float3(0.1, 0.0, 0.5);    // purple
                    float3 c3 = float3(0.8, 0.1, 0.1);    // red
                    float3 c4 = float3(1.0, 0.7, 0.0);    // orange-yellow
                    float3 c5 = float3(1.0, 1.0, 0.9);    // white-hot

                    float3 tc;
                    if (heat < 0.25)
                        tc = lerp(c1, c2, heat / 0.25);
                    else if (heat < 0.5)
                        tc = lerp(c2, c3, (heat - 0.25) / 0.25);
                    else if (heat < 0.75)
                        tc = lerp(c3, c4, (heat - 0.5) / 0.25);
                    else
                        tc = lerp(c4, c5, (heat - 0.75) / 0.25);

                    // Add subtle contour lines for artistic effect
                    float contour = frac(heat * 12.0);
                    contour = smoothstep(0.0, 0.05, contour) * smoothstep(0.1, 0.05, contour);
                    tc = lerp(tc, tc * 0.7, contour * 0.4);

                    result = tc;
                }

                // ---- Halation (IR bloom) ----
                if (_Halation > 0.01)
                {
                    float3 bloom = float3(0,0,0);
                    float totalW = 0;
                    float2 texelSize = 1.0 / _ScreenParams.xy;
                    for (int x = -3; x <= 3; x++)
                    {
                        for (int y = -3; y <= 3; y++)
                        {
                            float2 off = float2(x, y) * texelSize * 4.0;
                            float3 s = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + off).rgb;
                            float sLum = dot(s, float3(0.299, 0.587, 0.114));
                            float bright = smoothstep(0.6, 1.0, sLum);
                            float w = bright / (1.0 + length(float2(x,y)));
                            bloom += s * w;
                            totalW += w;
                        }
                    }
                    bloom = (totalW > 0) ? bloom / totalW : float3(0,0,0);
                    result += bloom * _Halation * _HalationColor.rgb;
                }

                // ---- Hotspot glow (center brightness like IR sensor) ----
                float2 center = uv - 0.5;
                float centerDist = length(center);
                float hotspot = 1.0 + (1.0 - smoothstep(0.0, 0.4, centerDist)) * _Hotspot * 0.3;
                result *= hotspot;

                // ---- Contrast ----
                result = saturate((result - 0.5) * _Contrast + 0.5);

                // ---- Film grain ----
                float grain = (hash12(uv * _ScreenParams.xy + _Time.y * 100.0) - 0.5) * _Grain;
                result += grain;

                // ---- Vignette ----
                float vig = 1.0 - smoothstep(0.4, 1.0, centerDist * 1.4);
                result *= lerp(1.0, vig, _Vignette);

                result = saturate(result);
                result = lerp(original, result, _Intensity);

                return float4(result, col.a);
            }
            ENDHLSL
        }
    }
}
