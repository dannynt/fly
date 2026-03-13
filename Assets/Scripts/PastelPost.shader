Shader "Hidden/PastelPost"
{
    Properties
    {
        _Intensity ("Effect Intensity", Range(0,1)) = 1

        [Header(Pastel Colors)]
        _Desaturation ("Desaturation", Range(0,0.7)) = 0.3
        _Lightness ("Lightness Lift", Range(0,0.3)) = 0.12
        _PastelMix ("Pastel White Mix", Range(0,0.5)) = 0.2
        _HueShift ("Hue Shift", Range(-0.1,0.1)) = 0.0

        [Header(Palette Mode)]
        _PaletteMode ("Palette (0=Soft 1=Candy 2=Earth 3=Lavender)", Range(0,3)) = 0
        _PaletteStrength ("Palette Strength", Range(0,1)) = 0.3

        [Header(Soft Focus)]
        _SoftBlur ("Soft Bloom Radius", Range(0,3)) = 1.0
        _BloomStrength ("Bloom Strength", Range(0,0.5)) = 0.15
        _BloomThreshold ("Bloom Threshold", Range(0.3,1)) = 0.6

        [Header(Contrast)]
        _Contrast ("Contrast", Range(0.6,1.2)) = 0.85
        _ShadowLift ("Shadow Lift", Range(0,0.2)) = 0.08
        _HighlightSoften ("Highlight Softening", Range(0,0.3)) = 0.1

        [Header(Tone)]
        _Warmth ("Warmth", Range(-0.5,0.5)) = 0.15
        _ShadowHue ("Shadow Tint", Color) = (0.85, 0.85, 0.95, 1)
        _HighlightHue ("Highlight Tint", Color) = (1.0, 0.98, 0.92, 1)

        [Header(Finish)]
        _Grain ("Soft Grain", Range(0,0.08)) = 0.02
        _Vignette ("Vignette", Range(0,0.5)) = 0.15
        _VignetteColor ("Vignette Color", Color) = (0.9, 0.85, 0.92, 1)
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "PastelPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Intensity;

            float _Desaturation;
            float _Lightness;
            float _PastelMix;
            float _HueShift;

            float _PaletteMode;
            float _PaletteStrength;

            float _SoftBlur;
            float _BloomStrength;
            float _BloomThreshold;

            float _Contrast;
            float _ShadowLift;
            float _HighlightSoften;

            float _Warmth;
            float4 _ShadowHue;
            float4 _HighlightHue;

            float _Grain;
            float _Vignette;
            float4 _VignetteColor;

            float hash12(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            float3 RGBtoHSV(float3 c)
            {
                float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
                float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
                float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
                float d = q.x - min(q.w, q.y);
                float e = 1.0e-10;
                return float3(abs(q.z + (q.w - q.y) / (6.0*d+e)), d/(q.x+e), q.x);
            }

            float3 HSVtoRGB(float3 c)
            {
                float3 p = abs(frac(c.xxx + float3(1.0,2.0/3.0,1.0/3.0)) * 6.0 - 3.0);
                return c.z * lerp(float3(1,1,1), saturate(p - 1.0), c.y);
            }

            // Palette color mapping
            float3 applyPalette(float3 col, float lum, int mode)
            {
                float3 tint;
                if (mode == 0) // Soft Pastel
                {
                    float3 low  = float3(0.75, 0.82, 0.88);
                    float3 mid  = float3(0.92, 0.88, 0.82);
                    float3 high = float3(0.98, 0.95, 0.90);
                    tint = (lum < 0.5) ? lerp(low, mid, lum * 2.0) : lerp(mid, high, (lum - 0.5) * 2.0);
                }
                else if (mode == 1) // Candy
                {
                    float3 low  = float3(0.85, 0.70, 0.80);
                    float3 mid  = float3(0.90, 0.85, 0.70);
                    float3 high = float3(0.70, 0.90, 0.85);
                    tint = (lum < 0.5) ? lerp(low, mid, lum * 2.0) : lerp(mid, high, (lum - 0.5) * 2.0);
                }
                else if (mode == 2) // Earthy
                {
                    float3 low  = float3(0.55, 0.50, 0.45);
                    float3 mid  = float3(0.80, 0.75, 0.65);
                    float3 high = float3(0.95, 0.92, 0.85);
                    tint = (lum < 0.5) ? lerp(low, mid, lum * 2.0) : lerp(mid, high, (lum - 0.5) * 2.0);
                }
                else // Lavender
                {
                    float3 low  = float3(0.65, 0.60, 0.80);
                    float3 mid  = float3(0.85, 0.80, 0.90);
                    float3 high = float3(0.95, 0.92, 0.98);
                    tint = (lum < 0.5) ? lerp(low, mid, lum * 2.0) : lerp(mid, high, (lum - 0.5) * 2.0);
                }
                return lerp(col, col * tint, _PaletteStrength);
            }

            float4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texel = 1.0 / _ScreenParams.xy;
                float3 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float3 original = col;

                float lum = dot(col, float3(0.299, 0.587, 0.114));

                // ---- Soft bloom ----
                if (_BloomStrength > 0.001)
                {
                    float3 bloom = float3(0,0,0);
                    float tw = 0;
                    float rad = _SoftBlur;
                    for (int bx = -2; bx <= 2; bx++)
                    {
                        for (int by = -2; by <= 2; by++)
                        {
                            float2 off = float2(bx, by) * texel * rad * 2.0;
                            float3 s = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + off).rgb;
                            float sl = dot(s, float3(0.299, 0.587, 0.114));
                            float w = smoothstep(_BloomThreshold, 1.0, sl);
                            bloom += s * w;
                            tw += w;
                        }
                    }
                    bloom = (tw > 0) ? bloom / tw : float3(0,0,0);
                    col += bloom * _BloomStrength;
                }

                // ---- Desaturate toward pastel ----
                float newLum = dot(col, float3(0.299, 0.587, 0.114));
                col = lerp(col, float3(newLum, newLum, newLum), _Desaturation);

                // ---- Mix with white (pastel shift) ----
                col = lerp(col, float3(1,1,1), _PastelMix * 0.5);

                // ---- Lightness lift ----
                col += _Lightness;

                // ---- Hue shift ----
                if (abs(_HueShift) > 0.001)
                {
                    float3 hsv = RGBtoHSV(col);
                    hsv.x = frac(hsv.x + _HueShift);
                    col = HSVtoRGB(hsv);
                }

                // ---- Palette color mapping ----
                int mode = (int)round(_PaletteMode);
                col = applyPalette(col, lum, mode);

                // ---- Contrast reduction (softer look) ----
                col = (col - 0.5) * _Contrast + 0.5;

                // ---- Shadow lift ----
                col = max(col, _ShadowLift);

                // ---- Highlight softening ----
                col = min(col, 1.0 - _HighlightSoften);

                // ---- Shadow/Highlight tinting ----
                float shadowMask = 1.0 - smoothstep(0.0, 0.4, lum);
                float highlightMask = smoothstep(0.6, 1.0, lum);
                col = lerp(col, col * _ShadowHue.rgb, shadowMask * 0.4);
                col = lerp(col, col * _HighlightHue.rgb, highlightMask * 0.3);

                // ---- Warmth ----
                col.r += _Warmth * 0.04;
                col.b -= _Warmth * 0.04;

                // ---- Soft grain ----
                float grain = (hash12(uv * _ScreenParams.xy + _Time.y * 50.0) - 0.5) * _Grain;
                col += grain;

                // ---- Vignette ----
                float2 vc = uv - 0.5;
                float vd = length(vc);
                float vig = 1.0 - smoothstep(0.4, 0.95, vd);
                col = lerp(col, col * _VignetteColor.rgb, (1.0 - vig) * _Vignette);

                col = saturate(col);
                col = lerp(original, col, _Intensity);

                return float4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
