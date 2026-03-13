Shader "Custom/FilmNoirPost"
{
    Properties
    {
        [Header(Black and White)]
        _DesatAmount ("Desaturation", Range(0.7, 1)) = 1.0
        _Contrast ("Contrast", Range(1, 4)) = 2.2
        _Brightness ("Brightness", Range(0.6, 1.2)) = 0.85
        _Gamma ("Gamma", Range(0.5, 2)) = 1.3

        [Header(Shadow Crush)]
        _ShadowCrush ("Shadow Depth", Range(0, 0.3)) = 0.1
        _HighlightBoost ("Highlight Pop", Range(1, 2)) = 1.3

        [Header(Film Grain)]
        [Toggle] _EnableGrain ("Enable Film Grain", Float) = 1
        _GrainIntensity ("Grain Intensity", Range(0, 0.2)) = 0.1
        _GrainScale ("Grain Scale", Range(200, 1000)) = 500

        [Header(Vignette)]
        [Toggle] _EnableVignette ("Enable Dramatic Vignette", Float) = 1
        _VigIntensity ("Vignette Intensity", Range(0, 3)) = 1.5
        _VigSoftness ("Vignette Softness", Range(0.1, 0.5)) = 0.25
        _VigRoundness ("Vignette Roundness", Range(0.5, 1.5)) = 1.0

        [Header(Light Rays)]
        [Toggle] _EnableRays ("Enable Window Light", Float) = 1
        _RayAngle ("Light Angle", Range(0, 6.28)) = 0.78
        _RayWidth ("Ray Width", Range(0.05, 0.3)) = 0.12
        _RayIntensity ("Ray Intensity", Range(0, 0.4)) = 0.15
        _RayCount ("Ray Count", Range(2, 8)) = 4

        [Header(Venetian Blinds)]
        [Toggle] _EnableBlinds ("Enable Venetian Blinds", Float) = 0
        _BlindsCount ("Blinds Count", Range(5, 40)) = 15
        _BlindsAngle ("Blinds Angle", Range(-0.5, 0.5)) = 0.1
        _BlindsAlpha ("Blinds Darkness", Range(0, 0.7)) = 0.4

        [Header(Sepia Option)]
        [Toggle] _EnableSepia ("Enable Sepia Tint", Float) = 0
        _SepiaStrength ("Sepia Strength", Range(0, 0.5)) = 0.2

        [Header(Flicker)]
        [Toggle] _EnableFlicker ("Enable Projector Flicker", Float) = 1
        _FlickerSpeed ("Flicker Speed", Range(5, 40)) = 18
        _FlickerAmount ("Flicker Amount", Range(0, 0.08)) = 0.03

        [Header(Scratches)]
        [Toggle] _EnableScratches ("Enable Film Scratches", Float) = 1
        _ScratchDensity ("Scratch Density", Range(0.95, 0.999)) = 0.985
        _ScratchBrightness ("Scratch Brightness", Range(0.1, 0.5)) = 0.25
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "FilmNoirPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _DesatAmount;
            float _Contrast;
            float _Brightness;
            float _Gamma;
            float _ShadowCrush;
            float _HighlightBoost;
            float _EnableGrain;
            float _GrainIntensity;
            float _GrainScale;
            float _EnableVignette;
            float _VigIntensity;
            float _VigSoftness;
            float _VigRoundness;
            float _EnableRays;
            float _RayAngle;
            float _RayWidth;
            float _RayIntensity;
            float _RayCount;
            float _EnableBlinds;
            float _BlindsCount;
            float _BlindsAngle;
            float _BlindsAlpha;
            float _EnableSepia;
            float _SepiaStrength;
            float _EnableFlicker;
            float _FlickerSpeed;
            float _FlickerAmount;
            float _EnableScratches;
            float _ScratchDensity;
            float _ScratchBrightness;

            float Hash21(float2 p)
            {
                p = frac(p * float2(443.897, 397.297));
                p += dot(p, p.yx + 19.19);
                return frac(p.x * p.y);
            }

            half Luminance3(half3 c) { return dot(c, half3(0.2126, 0.7152, 0.0722)); }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float time = _Time.y;

                half3 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;

                // --- Black & white ---
                half lum = Luminance3(col);
                col = lerp(col, half3(lum, lum, lum), _DesatAmount);

                // --- Contrast + brightness + gamma ---
                col = saturate((col - 0.5) * _Contrast + 0.5);
                col *= _Brightness;
                col = pow(max(col, 0.001), _Gamma);

                // --- Shadow crush + highlight boost ---
                col = max(col - _ShadowCrush, 0.0);
                half lumF = Luminance3(col);
                col += col * smoothstep(0.6, 1.0, lumF) * (_HighlightBoost - 1.0);

                // --- Venetian blinds ---
                if (_EnableBlinds > 0.5)
                {
                    float blindUV = uv.y + uv.x * _BlindsAngle;
                    float blind = sin(blindUV * _BlindsCount * 6.28) * 0.5 + 0.5;
                    blind = smoothstep(0.3, 0.7, blind);
                    col *= 1.0 - blind * _BlindsAlpha;
                }

                // --- Light rays (diagonal streaks) ---
                if (_EnableRays > 0.5)
                {
                    float2 rayDir = float2(cos(_RayAngle), sin(_RayAngle));
                    float rayCoord = dot(uv - 0.5, rayDir);
                    for (int r = 0; r < 8; r++)
                    {
                        if (r >= (int)_RayCount) break;
                        float rayPos = (float)r / _RayCount - 0.5;
                        float dist = abs(rayCoord - rayPos * 0.8);
                        float ray = smoothstep(_RayWidth, 0.0, dist);
                        // Perpendicular fade
                        float perpCoord = dot(uv - 0.5, float2(-rayDir.y, rayDir.x));
                        ray *= smoothstep(0.6, 0.0, abs(perpCoord));
                        col += ray * _RayIntensity;
                    }
                }

                // --- Film grain ---
                if (_EnableGrain > 0.5)
                {
                    float grain = Hash21(uv * _GrainScale + time * 100.0);
                    col += (grain - 0.5) * _GrainIntensity;
                }

                // --- Film scratches ---
                if (_EnableScratches > 0.5)
                {
                    float scratchX = Hash21(float2(floor(time * 24.0), 0));
                    float dist = abs(uv.x - scratchX);
                    float scratch = smoothstep(0.001, 0.0, dist);
                    float scratchRand = Hash21(float2(scratchX, floor(time * 24.0)));
                    if (scratchRand > _ScratchDensity)
                        col += scratch * _ScratchBrightness;
                }

                // --- Projector flicker ---
                if (_EnableFlicker > 0.5)
                {
                    float flicker = 1.0 + sin(time * _FlickerSpeed) * sin(time * _FlickerSpeed * 2.3) * _FlickerAmount;
                    col *= flicker;
                }

                // --- Sepia ---
                if (_EnableSepia > 0.5)
                {
                    half3 sepia = half3(1.2, 1.0, 0.7) * Luminance3(col);
                    col = lerp(col, sepia, _SepiaStrength);
                }

                // --- Dramatic vignette ---
                if (_EnableVignette > 0.5)
                {
                    float2 vigUV = (uv - 0.5) * float2(1.0, _VigRoundness);
                    float vigDist = length(vigUV);
                    float vig = smoothstep(0.5, 0.5 - _VigSoftness, vigDist);
                    vig = pow(vig, _VigIntensity);
                    col *= vig;
                }

                return half4(saturate(col), 1.0);
            }

            ENDHLSL
        }
    }
}
