Shader "Hidden/BladeRunnerPost"
{
    Properties
    {
        _Intensity ("Effect Intensity", Range(0,1)) = 1

        [Header(Rain)]
        _RainAmount ("Rain Amount", Range(0,1)) = 0.7
        _RainSpeed ("Rain Speed", Range(0.5,5)) = 2.0
        _RainLength ("Rain Streak Length", Range(0.02,0.15)) = 0.06
        _RainWidth ("Rain Width", Range(0.001,0.005)) = 0.002
        _RainBrightness ("Rain Brightness", Range(0,1)) = 0.5
        _RainAngle ("Rain Angle", Range(-0.3,0.3)) = 0.05

        [Header(Wet Surface)]
        _WetReflection ("Wet Reflection", Range(0,1)) = 0.4
        _PuddleAmount ("Puddle Amount", Range(0,1)) = 0.3
        _ReflectionBlur ("Reflection Blur", Range(0,1)) = 0.5

        [Header(Neon  Atmosphere)]
        _NeonGlow ("Neon Glow Boost", Range(0,2)) = 0.8
        _NeonColor1 ("Neon Color 1", Color) = (0.0, 0.5, 1.0, 1)
        _NeonColor2 ("Neon Color 2", Color) = (1.0, 0.1, 0.6, 1)
        _FogAmount ("Atmospheric Fog", Range(0,1)) = 0.35
        _FogColor ("Fog Color", Color) = (0.02, 0.03, 0.06, 1)
        _FogHeight ("Fog Height", Range(0,1)) = 0.5

        [Header(Mood)]
        _Teal ("Teal Shift", Range(0,1)) = 0.4
        _Orange ("Orange Shift", Range(0,1)) = 0.3
        _Darkness ("Darkness", Range(0,1)) = 0.25
        _Bloom ("Fake Bloom", Range(0,1)) = 0.3
        _ChromAb ("Chromatic Aberration", Range(0,0.01)) = 0.002
        _FilmGrain ("Film Grain", Range(0,0.1)) = 0.03
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "BladeRunnerPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Intensity;

            float _RainAmount;
            float _RainSpeed;
            float _RainLength;
            float _RainWidth;
            float _RainBrightness;
            float _RainAngle;

            float _WetReflection;
            float _PuddleAmount;
            float _ReflectionBlur;

            float _NeonGlow;
            float4 _NeonColor1;
            float4 _NeonColor2;
            float _FogAmount;
            float4 _FogColor;
            float _FogHeight;

            float _Teal;
            float _Orange;
            float _Darkness;
            float _Bloom;
            float _ChromAb;
            float _FilmGrain;

            // ---- noise helpers ----
            float hash11(float p)
            {
                p = frac(p * 0.1031);
                p *= p + 33.33;
                p *= p + p;
                return frac(p);
            }

            float hash12(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            float hash21(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);

                float a = hash21(i);
                float b = hash21(i + float2(1,0));
                float c = hash21(i + float2(0,1));
                float d = hash21(i + float2(1,1));

                return lerp(lerp(a,b,f.x), lerp(c,d,f.x), f.y);
            }

            // ---- rain layer ----
            float rainLayer(float2 uv, float seed, float scale)
            {
                float2 rainUV = uv * float2(scale, 1.0);
                rainUV.x += _RainAngle * rainUV.y;

                // Column ID
                float colId = floor(rainUV.x);
                float colRand = hash11(colId + seed);

                // Only some columns have rain
                if (colRand > _RainAmount) return 0;

                // Each drop has its own timing
                float dropSpeed = _RainSpeed * (0.7 + colRand * 0.6);
                float t = _Time.y * dropSpeed + colRand * 100.0;

                // Vertical position within column
                float dropY = frac(t * 0.3 + hash11(colId * 7.13 + seed));

                // Drop shape
                float dx = abs(frac(rainUV.x) - 0.5);
                float dy = frac(rainUV.y * 0.5) - dropY;

                // Streak
                float streak = smoothstep(_RainWidth * scale, 0.0, dx);
                streak *= smoothstep(_RainLength, 0.0, dy) * smoothstep(-0.005, 0.0, dy);

                // Brightness variation
                streak *= 0.5 + colRand * 0.5;

                return streak;
            }

            float4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;

                // ---- Chromatic aberration ----
                float2 dir = uv - 0.5;
                float dist = length(dir);
                float2 offset = dir * _ChromAb * dist;
                float r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + offset).r;
                float g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).g;
                float b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv - offset).b;
                float3 col = float3(r, g, b);
                float3 original = col;

                float lum = dot(col, float3(0.299, 0.587, 0.114));

                // ---- Darken scene ----
                col *= 1.0 - _Darkness * 0.5;

                // ---- Teal-orange color grading ----
                // Shadows -> teal, highlights -> orange
                float3 tealTint = float3(0.0, 0.6, 0.7);
                float3 orangeTint = float3(1.0, 0.6, 0.2);
                float shadowMask = 1.0 - smoothstep(0.0, 0.5, lum);
                float highlightMask = smoothstep(0.5, 1.0, lum);
                col = lerp(col, col * tealTint, shadowMask * _Teal * 0.4);
                col = lerp(col, col + orangeTint * 0.1, highlightMask * _Orange * 0.4);

                // ---- Neon glow boost ----
                // Amplify bright saturated pixels
                float sat = 1.0 - (min(min(col.r, col.g), col.b) / (max(max(col.r, col.g), col.b) + 0.001));
                float neonMask = sat * smoothstep(0.3, 0.8, lum);
                float3 neonMix = lerp(_NeonColor1.rgb, _NeonColor2.rgb, sin(_Time.y * 0.5) * 0.5 + 0.5);
                col += neonMix * neonMask * _NeonGlow * 0.15;

                // ---- Fake bloom on bright areas ----
                if (_Bloom > 0.01)
                {
                    float3 bloom = float3(0,0,0);
                    float tw = 0;
                    float2 texel = 1.0 / _ScreenParams.xy;
                    for (int bx = -2; bx <= 2; bx++)
                    {
                        for (int by = -2; by <= 2; by++)
                        {
                            float2 off = float2(bx, by) * texel * 5.0;
                            float3 s = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + off).rgb;
                            float sl = dot(s, float3(0.299, 0.587, 0.114));
                            float w = smoothstep(0.5, 1.0, sl);
                            bloom += s * w;
                            tw += w;
                        }
                    }
                    bloom = (tw > 0) ? bloom / tw : float3(0,0,0);
                    col += bloom * _Bloom * 0.5;
                }

                // ---- Rain ----
                float rain = 0;
                rain += rainLayer(uv, 0.0, 80.0) * 0.7;
                rain += rainLayer(uv, 13.7, 120.0) * 0.5;
                rain += rainLayer(uv, 27.3, 200.0) * 0.3;
                rain = saturate(rain);

                // Rain picks up nearby neon color
                float3 rainColor = lerp(float3(0.7, 0.8, 0.9), col * 1.5 + 0.2, 0.3);
                col += rainColor * rain * _RainBrightness;

                // ---- Wet surface / puddle reflections ----
                // Lower portion of screen simulates ground reflection
                float groundMask = smoothstep(0.55, 0.4, uv.y) * _PuddleAmount;

                // Wavy reflection using noise
                float2 reflUV = float2(uv.x, 1.0 - uv.y);
                float wave = valueNoise(uv * 30.0 + _Time.y * 0.5) * 0.01;
                reflUV += wave;

                // Blur the reflection
                float3 refl = float3(0,0,0);
                float2 texelR = 1.0 / _ScreenParams.xy;
                float blurR = _ReflectionBlur * 3.0;
                refl += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, reflUV + float2(-blurR, 0) * texelR).rgb;
                refl += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, reflUV).rgb;
                refl += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, reflUV + float2(blurR, 0) * texelR).rgb;
                refl += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, reflUV + float2(0, blurR) * texelR).rgb;
                refl /= 4.0;

                // Puddle mask with noise for irregular shapes
                float puddleNoise = valueNoise(uv * 15.0);
                float puddleMask = groundMask * smoothstep(0.3, 0.6, puddleNoise);

                col = lerp(col, refl * 0.8, puddleMask * _WetReflection);

                // Wet surface sheen on non-puddle areas
                float wetSheen = groundMask * (1.0 - puddleMask) * _WetReflection * 0.3;
                col += wetSheen * 0.1;

                // ---- Atmospheric fog ----
                float fogMask = smoothstep(1.0 - _FogHeight, 1.0, uv.y) * _FogAmount;
                // Also add distance-like fog in middle
                float centerFog = (1.0 - abs(uv.y - 0.5) * 2.0) * 0.3 * _FogAmount;
                float totalFog = saturate(fogMask + centerFog);
                col = lerp(col, _FogColor.rgb + neonMix * 0.03, totalFog);

                // ---- Film grain ----
                float grain = (hash12(uv * _ScreenParams.xy + _Time.y * 137.0) - 0.5) * _FilmGrain;
                col += grain;

                // ---- Vignette ----
                float vig = 1.0 - smoothstep(0.3, 0.9, dist * 1.3);
                col *= vig;

                col = saturate(col);
                col = lerp(original, col, _Intensity);

                return float4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
