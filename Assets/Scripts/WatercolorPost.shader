Shader "Custom/WatercolorPost"
{
    Properties
    {
        [Header(Wet Edge Bleed)]
        [Toggle] _EnableBleed ("Enable Color Bleed", Float) = 1
        _BleedRadius ("Bleed Radius", Range(1, 8)) = 3
        _BleedJitter ("Bleed Jitter", Range(0, 3)) = 1.5

        [Header(Pigment Separation)]
        [Toggle] _EnablePigment ("Enable Pigment Effect", Float) = 1
        _PigmentScale ("Pigment Noise Scale", Range(50, 500)) = 200
        _PigmentStrength ("Pigment Strength", Range(0, 0.3)) = 0.12

        [Header(Edge Darkening)]
        [Toggle] _EnableEdgeDarken ("Enable Wet Edges", Float) = 1
        _EdgeDarkenThickness ("Edge Thickness", Range(0.5, 4)) = 2.0
        _EdgeDarkenSensitivity ("Edge Sensitivity", Range(0.02, 0.4)) = 0.1
        _EdgeDarkenAmount ("Darken Amount", Range(0, 0.6)) = 0.3

        [Header(Color Softening)]
        _Desaturation ("Desaturation", Range(0, 0.5)) = 0.15
        _WarmShift ("Warm Tint", Range(0, 0.1)) = 0.03
        _Softness ("Color Softness (Posterize)", Range(3, 20)) = 10

        [Header(Paper)]
        [Toggle] _EnablePaper ("Enable Paper Texture", Float) = 1
        _PaperScale ("Paper Scale", Range(100, 800)) = 400
        _PaperStrength ("Paper Strength", Range(0, 0.3)) = 0.12
        _PaperColor ("Paper Tint", Color) = (0.98, 0.96, 0.9, 1)

        [Header(Wobble)]
        [Toggle] _EnableWobble ("Enable Paint Wobble", Float) = 1
        _WobbleAmount ("Wobble Amount", Range(0, 0.008)) = 0.002
        _WobbleScale ("Wobble Scale", Range(5, 50)) = 15
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "WatercolorPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _EnableBleed;
            float _BleedRadius;
            float _BleedJitter;
            float _EnablePigment;
            float _PigmentScale;
            float _PigmentStrength;
            float _EnableEdgeDarken;
            float _EdgeDarkenThickness;
            float _EdgeDarkenSensitivity;
            float _EdgeDarkenAmount;
            float _Desaturation;
            float _WarmShift;
            float _Softness;
            float _EnablePaper;
            float _PaperScale;
            float _PaperStrength;
            half4 _PaperColor;
            float _EnableWobble;
            float _WobbleAmount;
            float _WobbleScale;

            // Value noise
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
                f = f * f * (3.0 - 2.0 * f); // smoothstep

                float a = Hash21(i);
                float b = Hash21(i + float2(1, 0));
                float c = Hash21(i + float2(0, 1));
                float d = Hash21(i + float2(1, 1));

                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            half Luminance3(half3 c)
            {
                return dot(c, half3(0.2126, 0.7152, 0.0722));
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texelSize = _BlitTexture_TexelSize.xy;

                // --- Paint wobble distortion ---
                if (_EnableWobble > 0.5)
                {
                    float2 noiseUV = uv * _WobbleScale;
                    float nx = ValueNoise(noiseUV + float2(0, _Time.y * 0.5));
                    float ny = ValueNoise(noiseUV + float2(100, _Time.y * 0.5));
                    uv += (float2(nx, ny) - 0.5) * _WobbleAmount;
                }

                // --- Wet-edge color bleed (directional blur with jitter) ---
                half3 col;
                if (_EnableBleed > 0.5)
                {
                    half3 sum = half3(0, 0, 0);
                    float totalWeight = 0;

                    for (int x = -2; x <= 2; x++)
                    {
                        for (int y = -2; y <= 2; y++)
                        {
                            float2 off = float2(x, y) * texelSize * _BleedRadius;
                            // Add perlin-like jitter
                            float jitter = ValueNoise(uv * 300.0 + float2(x * 13.0, y * 7.0));
                            off += (jitter - 0.5) * texelSize * _BleedJitter;

                            half3 s = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + off).rgb;
                            float w = 1.0 / (1.0 + length(float2(x, y)));
                            sum += s * w;
                            totalWeight += w;
                        }
                    }
                    col = sum / totalWeight;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                }

                // --- Soft posterize (watercolor banding) ---
                col = floor(col * _Softness + 0.5) / _Softness;

                // --- Desaturate + warm shift ---
                half lum = Luminance3(col);
                col = lerp(col, half3(lum, lum, lum), _Desaturation);
                col.r += _WarmShift;
                col.b -= _WarmShift * 0.5;

                // --- Pigment noise (uneven color absorption) ---
                if (_EnablePigment > 0.5)
                {
                    float2 pigUV = uv * _PigmentScale;
                    float pigNoise = ValueNoise(pigUV);
                    float pigNoise2 = ValueNoise(pigUV * 2.0 + 100.0);
                    float pigment = (pigNoise * 0.6 + pigNoise2 * 0.4) * 2.0 - 1.0;

                    // Affect each channel slightly differently
                    col.r += pigment * _PigmentStrength * 1.1;
                    col.g += pigment * _PigmentStrength * 0.9;
                    col.b += pigment * _PigmentStrength * 1.0;
                }

                // --- Wet edge darkening ---
                if (_EnableEdgeDarken > 0.5)
                {
                    float2 edgeOffset = texelSize * _EdgeDarkenThickness;

                    half lumC = Luminance3(col);
                    half lumL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-edgeOffset.x, 0)).rgb);
                    half lumR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( edgeOffset.x, 0)).rgb);
                    half lumU = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,  edgeOffset.y)).rgb);
                    half lumD = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, -edgeOffset.y)).rgb);

                    float edge = abs(lumL - lumC) + abs(lumR - lumC) + abs(lumU - lumC) + abs(lumD - lumC);
                    edge = smoothstep(_EdgeDarkenSensitivity * 0.5, _EdgeDarkenSensitivity, edge);

                    // Darken edges with a brownish tint
                    col = lerp(col, col * (1.0 - _EdgeDarkenAmount) * half3(0.8, 0.7, 0.6), edge);
                }

                // --- Paper texture ---
                if (_EnablePaper > 0.5)
                {
                    float2 paperUV = uv * _PaperScale;
                    float paper = ValueNoise(paperUV);
                    float paperFine = ValueNoise(paperUV * 3.0);
                    float paperVal = paper * 0.6 + paperFine * 0.4;

                    // Blend towards paper color in lighter areas
                    half lumP = Luminance3(col);
                    float paperBlend = _PaperStrength * (0.5 + lumP * 0.5);
                    col = lerp(col, col * _PaperColor.rgb * (0.85 + paperVal * 0.3), paperBlend);
                }

                return half4(saturate(col), 1.0);
            }

            ENDHLSL
        }
    }
}
