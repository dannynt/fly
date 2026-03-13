Shader "Custom/RetroPost"
{
    Properties
    {
        [Header(Pixelation)]
        [Toggle] _EnablePixelation ("Enable Pixelation", Float) = 1
        _PixelSize ("Pixel Size", Range(1, 20)) = 4
        _ColorDepth ("Color Depth", Range(2, 64)) = 16

        [Header(CRT Scanlines)]
        [Toggle] _EnableScanlines ("Enable Scanlines", Float) = 1
        _ScanlineIntensity ("Scanline Intensity", Range(0, 1)) = 0.3
        _ScanlineFrequency ("Scanline Density", Range(100, 2000)) = 800
        _ScanlineSpeed ("Scanline Scroll Speed", Range(0, 10)) = 1.5

        [Header(CRT Curvature)]
        [Toggle] _EnableCurvature ("Enable CRT Curvature", Float) = 1
        _CurvatureAmount ("Curvature Amount", Range(0, 0.1)) = 0.02

        [Header(Color Bleed)]
        [Toggle] _EnableBleed ("Enable Color Bleed", Float) = 1
        _BleedAmount ("Bleed Amount", Range(0, 0.01)) = 0.003

        [Header(Flicker)]
        [Toggle] _EnableFlicker ("Enable Screen Flicker", Float) = 0
        _FlickerStrength ("Flicker Strength", Range(0, 0.1)) = 0.03
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "RetroPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _EnablePixelation;
            float _PixelSize;
            float _ColorDepth;
            float _EnableScanlines;
            float _ScanlineIntensity;
            float _ScanlineFrequency;
            float _ScanlineSpeed;
            float _EnableCurvature;
            float _CurvatureAmount;
            float _EnableBleed;
            float _BleedAmount;
            float _EnableFlicker;
            float _FlickerStrength;

            float2 CurvUV(float2 uv, float amount)
            {
                uv = uv * 2.0 - 1.0;
                float2 offset = abs(uv.yx) * amount;
                uv = uv + uv * offset * offset;
                uv = uv * 0.5 + 0.5;
                return uv;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;

                // --- CRT curvature ---
                if (_EnableCurvature > 0.5)
                {
                    uv = CurvUV(uv, _CurvatureAmount);
                    // Black outside screen bounds
                    if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1)
                        return half4(0, 0, 0, 1);
                }

                // --- Pixelation ---
                if (_EnablePixelation > 0.5)
                {
                    float2 pixelCount = _ScreenParams.xy / _PixelSize;
                    uv = floor(uv * pixelCount) / pixelCount;
                }

                // --- Sample with color bleed ---
                half4 col;
                if (_EnableBleed > 0.5)
                {
                    col.r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(_BleedAmount, 0)).r;
                    col.g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).g;
                    col.b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv - float2(_BleedAmount, 0)).b;
                    col.a = 1.0;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
                }

                // --- Reduce color depth ---
                if (_EnablePixelation > 0.5)
                {
                    col.rgb = floor(col.rgb * _ColorDepth) / _ColorDepth;
                }

                // --- Scanlines ---
                if (_EnableScanlines > 0.5)
                {
                    float scanline = sin((uv.y + _Time.y * _ScanlineSpeed * 0.01) * _ScanlineFrequency) * 0.5 + 0.5;
                    scanline = pow(scanline, 1.5);
                    col.rgb *= 1.0 - scanline * _ScanlineIntensity;

                    // Subtle horizontal line shimmer
                    float shimmer = sin(uv.y * _ScanlineFrequency * 2.0 + _Time.y * 30.0) * 0.5 + 0.5;
                    col.rgb += shimmer * 0.01;
                }

                // --- Flicker ---
                if (_EnableFlicker > 0.5)
                {
                    float flicker = 1.0 + sin(_Time.y * 15.7) * sin(_Time.y * 23.3) * _FlickerStrength;
                    col.rgb *= flicker;
                }

                // --- Slight green-ish CRT tint ---
                if (_EnableScanlines > 0.5)
                {
                    col.rgb *= half3(0.95, 1.0, 0.95);
                }

                return col;
            }

            ENDHLSL
        }
    }
}
