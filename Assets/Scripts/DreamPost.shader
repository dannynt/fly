Shader "Custom/DreamPost"
{
    Properties
    {
        [Header(Wave Distortion)]
        [Toggle] _EnableWaves ("Enable Wave Distortion", Float) = 1
        _WaveAmplitude ("Wave Amplitude", Range(0, 0.02)) = 0.005
        _WaveFrequency ("Wave Frequency", Range(1, 30)) = 10
        _WaveSpeed ("Wave Speed", Range(0.1, 5)) = 1.5

        [Header(Radial Blur)]
        [Toggle] _EnableRadialBlur ("Enable Dreamy Blur", Float) = 1
        _BlurAmount ("Blur Amount", Range(0, 0.03)) = 0.008
        _BlurCenter ("Blur Center Focus", Range(0, 1)) = 0.3

        [Header(Color Shift)]
        [Toggle] _EnableColorShift ("Enable Color Drift", Float) = 1
        _HueShiftSpeed ("Hue Shift Speed", Range(0, 2)) = 0.3
        _HueShiftAmount ("Hue Shift Amount", Range(0, 0.3)) = 0.08
        _ChromaBoost ("Chroma Boost", Range(1, 2)) = 1.3

        [Header(Ethereal Glow)]
        [Toggle] _EnableGlow ("Enable Soft Glow", Float) = 1
        _GlowSpread ("Glow Spread", Range(1, 10)) = 4
        _GlowIntensity ("Glow Intensity", Range(0, 1)) = 0.35

        [Header(Vignette)]
        [Toggle] _EnableVignette ("Enable Soft Vignette", Float) = 1
        _VigIntensity ("Vignette Intensity", Range(0, 2)) = 0.6
        _VigSoftness ("Vignette Softness", Range(0.1, 0.8)) = 0.4
        _VigColor ("Vignette Color", Color) = (0.1, 0.05, 0.2, 1)

        [Header(Film Grain)]
        [Toggle] _EnableGrain ("Enable Film Grain", Float) = 0
        _GrainIntensity ("Grain Intensity", Range(0, 0.15)) = 0.05

        [Header(Breathing)]
        [Toggle] _EnableBreathe ("Enable Breathing Effect", Float) = 1
        _BreatheSpeed ("Breathe Speed", Range(0.1, 3)) = 0.8
        _BreatheAmount ("Breathe Amount", Range(0, 0.05)) = 0.015
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "DreamPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _EnableWaves;
            float _WaveAmplitude;
            float _WaveFrequency;
            float _WaveSpeed;
            float _EnableRadialBlur;
            float _BlurAmount;
            float _BlurCenter;
            float _EnableColorShift;
            float _HueShiftSpeed;
            float _HueShiftAmount;
            float _ChromaBoost;
            float _EnableGlow;
            float _GlowSpread;
            float _GlowIntensity;
            float _EnableVignette;
            float _VigIntensity;
            float _VigSoftness;
            half4 _VigColor;
            float _EnableGrain;
            float _GrainIntensity;
            float _EnableBreathe;
            float _BreatheSpeed;
            float _BreatheAmount;

            float Hash21(float2 p)
            {
                p = frac(p * float2(443.897, 397.297));
                p += dot(p, p.yx + 19.19);
                return frac(p.x * p.y);
            }

            // RGB to HSV
            half3 RGBtoHSV(half3 c)
            {
                half4 K = half4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
                half4 p = lerp(half4(c.bg, K.wz), half4(c.gb, K.xy), step(c.b, c.g));
                half4 q = lerp(half4(p.xyw, c.r), half4(c.r, p.yzx), step(p.x, c.r));
                half d = q.x - min(q.w, q.y);
                half e = 1.0e-10;
                return half3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
            }

            // HSV to RGB
            half3 HSVtoRGB(half3 c)
            {
                half4 K = half4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
                half3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
                return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texelSize = _BlitTexture_TexelSize.xy;
                float time = _Time.y;

                // --- Breathing (slow zoom pulse) ---
                if (_EnableBreathe > 0.5)
                {
                    float breathe = sin(time * _BreatheSpeed) * _BreatheAmount;
                    uv = (uv - 0.5) * (1.0 + breathe) + 0.5;
                }

                // --- Wave distortion ---
                if (_EnableWaves > 0.5)
                {
                    float waveX = sin(uv.y * _WaveFrequency + time * _WaveSpeed) * _WaveAmplitude;
                    float waveY = cos(uv.x * _WaveFrequency * 0.7 + time * _WaveSpeed * 1.3) * _WaveAmplitude * 0.5;
                    uv += float2(waveX, waveY);
                }

                // --- Radial blur (dreamy soft) ---
                half3 col;
                if (_EnableRadialBlur > 0.5)
                {
                    half3 sum = half3(0, 0, 0);
                    float2 center = float2(0.5, 0.5);
                    float2 dir = uv - center;
                    float dist = length(dir);
                    // Blur increases away from center
                    float blurStrength = smoothstep(_BlurCenter, 1.0, dist) * _BlurAmount;

                    int blurSamples = 8;
                    for (int s = 0; s < blurSamples; s++)
                    {
                        float t = (float)s / (float)(blurSamples - 1);
                        float2 sampleUV = uv - dir * blurStrength * t;
                        sum += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, sampleUV).rgb;
                    }
                    col = sum / (float)blurSamples;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                }

                // --- Soft glow (additive blur) ---
                if (_EnableGlow > 0.5)
                {
                    half3 glow = half3(0, 0, 0);
                    float2 glowOff = texelSize * _GlowSpread;
                    int gs = 0;

                    for (int x = -2; x <= 2; x++)
                    {
                        for (int y = -2; y <= 2; y++)
                        {
                            glow += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(x, y) * glowOff).rgb;
                            gs++;
                        }
                    }
                    glow /= (float)gs;
                    col = lerp(col, col + glow, _GlowIntensity);
                }

                // --- Color shift / hue drift ---
                if (_EnableColorShift > 0.5)
                {
                    half3 hsv = RGBtoHSV(col);
                    hsv.x += sin(time * _HueShiftSpeed + uv.x * 3.0 + uv.y * 2.0) * _HueShiftAmount;
                    hsv.y *= _ChromaBoost;
                    col = HSVtoRGB(hsv);
                }

                // --- Film grain ---
                if (_EnableGrain > 0.5)
                {
                    float grain = Hash21(uv * _ScreenParams.xy + time * 1000.0);
                    col += (grain - 0.5) * _GrainIntensity;
                }

                // --- Vignette ---
                if (_EnableVignette > 0.5)
                {
                    float2 vigUV = uv - 0.5;
                    float vigDist = length(vigUV);
                    float vig = smoothstep(0.5, 0.5 - _VigSoftness, vigDist);
                    vig = pow(vig, _VigIntensity);
                    col = lerp(_VigColor.rgb, col, vig);
                }

                return half4(saturate(col), 1.0);
            }

            ENDHLSL
        }
    }
}
