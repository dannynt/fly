Shader "Custom/GlitchPost"
{
    Properties
    {
        [Header(Block Glitch)]
        [Toggle] _EnableBlockGlitch ("Enable Block Glitch", Float) = 1
        _BlockSize ("Block Size", Range(2, 60)) = 20
        _GlitchIntensity ("Glitch Intensity", Range(0, 0.1)) = 0.03
        _GlitchSpeed ("Glitch Speed", Range(1, 30)) = 8

        [Header(RGB Shift)]
        [Toggle] _EnableRGBShift ("Enable RGB Shift", Float) = 1
        _RGBShiftAmount ("RGB Shift Amount", Range(0, 0.02)) = 0.005

        [Header(Scanline Noise)]
        [Toggle] _EnableScanNoise ("Enable Scan Noise", Float) = 1
        _ScanNoiseIntensity ("Noise Intensity", Range(0, 0.3)) = 0.08
        _ScanNoiseSpeed ("Noise Speed", Range(1, 50)) = 20

        [Header(VHS Tracking)]
        [Toggle] _EnableTracking ("Enable VHS Tracking", Float) = 1
        _TrackingOffset ("Tracking Bar Height", Range(0.01, 0.15)) = 0.05
        _TrackingSpeed ("Tracking Speed", Range(0.1, 3)) = 0.7
        _TrackingDistort ("Tracking Distortion", Range(0, 0.05)) = 0.02

        [Header(Color Degradation)]
        [Toggle] _EnableDegradation ("Enable Color Degradation", Float) = 1
        _DegradeAmount ("Degradation Amount", Range(0, 1)) = 0.3

        [Header(Static Noise)]
        [Toggle] _EnableStatic ("Enable Static Overlay", Float) = 0
        _StaticIntensity ("Static Intensity", Range(0, 0.5)) = 0.1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "GlitchPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _EnableBlockGlitch;
            float _BlockSize;
            float _GlitchIntensity;
            float _GlitchSpeed;
            float _EnableRGBShift;
            float _RGBShiftAmount;
            float _EnableScanNoise;
            float _ScanNoiseIntensity;
            float _ScanNoiseSpeed;
            float _EnableTracking;
            float _TrackingOffset;
            float _TrackingSpeed;
            float _TrackingDistort;
            float _EnableDegradation;
            float _DegradeAmount;
            float _EnableStatic;
            float _StaticIntensity;

            float Hash(float n)
            {
                return frac(sin(n) * 43758.5453);
            }

            float Hash21(float2 p)
            {
                p = frac(p * float2(443.8975, 397.2973));
                p += dot(p, p.yx + 19.19);
                return frac(p.x * p.y);
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float time = _Time.y;

                // --- Block glitch: offset random horizontal strips ---
                if (_EnableBlockGlitch > 0.5)
                {
                    float blockY = floor(uv.y * _BlockSize);
                    float timeSlot = floor(time * _GlitchSpeed);
                    float rand = Hash(blockY + timeSlot * 100.0);

                    // Only glitch some blocks (sparse)
                    if (rand > 0.85)
                    {
                        float offsetX = (Hash(blockY * 3.0 + timeSlot) - 0.5) * 2.0 * _GlitchIntensity;
                        uv.x += offsetX;
                    }
                }

                // --- VHS tracking bar ---
                float trackingMask = 0.0;
                if (_EnableTracking > 0.5)
                {
                    float trackPos = frac(time * _TrackingSpeed);
                    float dist = abs(uv.y - trackPos);
                    dist = min(dist, 1.0 - dist); // wrap
                    trackingMask = smoothstep(_TrackingOffset, 0.0, dist);
                    uv.x += trackingMask * _TrackingDistort * sin(uv.y * 100.0);
                }

                // --- Sample with RGB shift ---
                half4 col;
                if (_EnableRGBShift > 0.5)
                {
                    float shift = _RGBShiftAmount;
                    // Randomize shift direction over time
                    float angle = Hash(floor(time * 4.0)) * 6.28;
                    float2 dir = float2(cos(angle), sin(angle)) * shift;

                    col.r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + dir).r;
                    col.g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).g;
                    col.b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv - dir).b;
                    col.a = 1.0;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                }

                // --- Scanline noise ---
                if (_EnableScanNoise > 0.5)
                {
                    float noise = Hash21(float2(uv.y * 500.0, floor(time * _ScanNoiseSpeed)));
                    float scanNoise = (noise - 0.5) * _ScanNoiseIntensity;
                    col.rgb += scanNoise;
                }

                // --- Color degradation (reduce to VHS palette) ---
                if (_EnableDegradation > 0.5)
                {
                    // Shift towards warmer, less saturated
                    half lum = dot(col.rgb, half3(0.2126, 0.7152, 0.0722));
                    half3 desat = half3(lum, lum, lum);
                    col.rgb = lerp(col.rgb, desat, _DegradeAmount * 0.4);

                    // Slight warm tint
                    col.r += _DegradeAmount * 0.03;
                    col.b -= _DegradeAmount * 0.03;

                    // Reduce precision
                    float vhsDepth = lerp(256.0, 16.0, _DegradeAmount);
                    col.rgb = floor(col.rgb * vhsDepth) / vhsDepth;
                }

                // --- Tracking bar brightness ---
                if (_EnableTracking > 0.5)
                {
                    col.rgb += trackingMask * 0.15;
                }

                // --- Static noise overlay ---
                if (_EnableStatic > 0.5)
                {
                    float2 staticUV = uv * _ScreenParams.xy;
                    float staticNoise = Hash21(staticUV + time * 1000.0);
                    col.rgb = lerp(col.rgb, half3(staticNoise, staticNoise, staticNoise), _StaticIntensity);
                }

                return col;
            }

            ENDHLSL
        }
    }
}
