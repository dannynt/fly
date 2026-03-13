Shader "Custom/FrozenPost"
{
    Properties
    {
        [Header(Ice Color)]
        _IceTint ("Ice Tint", Color) = (0.7, 0.85, 1.0, 1)
        _TintStrength ("Tint Strength", Range(0, 0.8)) = 0.35
        _Desaturation ("Desaturation", Range(0, 0.7)) = 0.4
        _BrightnessShift ("Brightness Shift", Range(0.9, 1.3)) = 1.1

        [Header(Frost Crystals)]
        [Toggle] _EnableFrost ("Enable Frost Overlay", Float) = 1
        _FrostScale ("Crystal Scale", Range(50, 400)) = 150
        _FrostIntensity ("Frost Intensity", Range(0, 0.6)) = 0.3
        _FrostEdge ("Frost Edge Size (Vignette)", Range(0.1, 0.8)) = 0.4
        _FrostSharpness ("Frost Edge Sharpness", Range(0.05, 0.5)) = 0.2

        [Header(Ice Shimmer)]
        [Toggle] _EnableShimmer ("Enable Ice Sparkle", Float) = 1
        _ShimmerScale ("Sparkle Scale", Range(200, 1000)) = 500
        _ShimmerSpeed ("Sparkle Speed", Range(1, 20)) = 8
        _ShimmerIntensity ("Sparkle Intensity", Range(0, 0.5)) = 0.2
        _ShimmerThreshold ("Sparkle Threshold", Range(0.9, 0.99)) = 0.95

        [Header(Frozen Distortion)]
        [Toggle] _EnableDistort ("Enable Ice Refraction", Float) = 1
        _DistortAmount ("Refraction Amount", Range(0, 0.01)) = 0.003
        _DistortScale ("Refraction Scale", Range(5, 40)) = 15

        [Header(Fog Breath)]
        [Toggle] _EnableFog ("Enable Cold Fog", Float) = 1
        _FogDensity ("Fog Density", Range(0, 0.5)) = 0.15
        _FogHeight ("Fog Position", Range(0, 0.5)) = 0.2
        _FogColor ("Fog Color", Color) = (0.85, 0.9, 1.0, 1)

        [Header(Icicle Vignette)]
        [Toggle] _EnableIceVig ("Enable Ice Vignette", Float) = 1
        _IceVigIntensity ("Ice Vignette Intensity", Range(0, 2)) = 1.0
        _IceVigColor ("Ice Vignette Color", Color) = (0.6, 0.75, 0.95, 1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "FrozenPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            half4 _IceTint;
            float _TintStrength;
            float _Desaturation;
            float _BrightnessShift;
            float _EnableFrost;
            float _FrostScale;
            float _FrostIntensity;
            float _FrostEdge;
            float _FrostSharpness;
            float _EnableShimmer;
            float _ShimmerScale;
            float _ShimmerSpeed;
            float _ShimmerIntensity;
            float _ShimmerThreshold;
            float _EnableDistort;
            float _DistortAmount;
            float _DistortScale;
            float _EnableFog;
            float _FogDensity;
            float _FogHeight;
            half4 _FogColor;
            float _EnableIceVig;
            float _IceVigIntensity;
            half4 _IceVigColor;

            float Hash21(float2 p)
            {
                p = frac(p * float2(443.897, 397.297));
                p += dot(p, p.yx + 19.19);
                return frac(p.x * p.y);
            }

            float ValueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                float a = Hash21(i);
                float b = Hash21(i + float2(1, 0));
                float c = Hash21(i + float2(0, 1));
                float d = Hash21(i + float2(1, 1));
                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            // Voronoi for crystal pattern
            float Voronoi(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float minDist = 1.0;

                for (int x = -1; x <= 1; x++)
                {
                    for (int y = -1; y <= 1; y++)
                    {
                        float2 neighbor = float2(x, y);
                        float2 point = Hash21(i + neighbor).xx;
                        point = 0.5 + 0.5 * sin(6.28 * point + _Time.y * 0.3);
                        float2 diff = neighbor + point - f;
                        float dist = length(diff);
                        minDist = min(minDist, dist);
                    }
                }
                return minDist;
            }

            half Luminance3(half3 c)
            {
                return dot(c, half3(0.2126, 0.7152, 0.0722));
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float time = _Time.y;

                // --- Ice refraction distortion ---
                if (_EnableDistort > 0.5)
                {
                    float2 noiseUV = uv * _DistortScale;
                    float nx = ValueNoise(noiseUV + time * 0.2);
                    float ny = ValueNoise(noiseUV + 50.0 + time * 0.15);
                    uv += (float2(nx, ny) - 0.5) * _DistortAmount;
                }

                half3 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;

                // --- Desaturate + ice tint ---
                half lum = Luminance3(col);
                col = lerp(col, half3(lum, lum, lum), _Desaturation);
                col = lerp(col, col * _IceTint.rgb, _TintStrength);
                col *= _BrightnessShift;

                // --- Frost crystal overlay (Voronoi on edges) ---
                if (_EnableFrost > 0.5)
                {
                    float2 vigUV = uv - 0.5;
                    float edgeDist = length(vigUV);
                    float edgeMask = smoothstep(_FrostEdge - _FrostSharpness, _FrostEdge, edgeDist);

                    float frost = Voronoi(uv * _FrostScale * 0.1);
                    float frostDetail = ValueNoise(uv * _FrostScale);
                    float frostPattern = frost * 0.7 + frostDetail * 0.3;

                    // Frost is white-blue
                    half3 frostColor = half3(0.85, 0.92, 1.0) * (0.7 + frostPattern * 0.6);
                    col = lerp(col, frostColor, edgeMask * _FrostIntensity);
                }

                // --- Ice sparkle / shimmer ---
                if (_EnableShimmer > 0.5)
                {
                    float2 sparkleUV = uv * _ShimmerScale;
                    float sparkle = Hash21(floor(sparkleUV) + floor(time * _ShimmerSpeed));
                    if (sparkle > _ShimmerThreshold)
                    {
                        float2 cellPos = frac(sparkleUV) - 0.5;
                        float sparkleRadius = (1.0 - (sparkle - _ShimmerThreshold) / (1.0 - _ShimmerThreshold));
                        float sparkleDot = 1.0 - smoothstep(0.0, 0.15 * sparkleRadius, length(cellPos));
                        col += sparkleDot * _ShimmerIntensity * half3(0.9, 0.95, 1.0);
                    }
                }

                // --- Cold fog at bottom ---
                if (_EnableFog > 0.5)
                {
                    float fogMask = smoothstep(_FogHeight + 0.1, 0.0, uv.y);
                    float fogNoise = ValueNoise(uv * 30.0 + time * 0.5);
                    fogMask *= (0.7 + fogNoise * 0.3);
                    col = lerp(col, _FogColor.rgb, fogMask * _FogDensity);
                }

                // --- Ice vignette ---
                if (_EnableIceVig > 0.5)
                {
                    float2 vigUV2 = uv - 0.5;
                    float vigDist = length(vigUV2);
                    float vig = smoothstep(0.3, 0.7, vigDist);
                    vig = pow(vig, _IceVigIntensity);
                    col = lerp(col, _IceVigColor.rgb * 0.4, vig * 0.5);
                }

                return half4(saturate(col), 1.0);
            }

            ENDHLSL
        }
    }
}
