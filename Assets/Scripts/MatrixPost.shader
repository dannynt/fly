Shader "Custom/MatrixPost"
{
    Properties
    {
        [Header(Digital Rain)]
        [Toggle] _EnableRain ("Enable Digital Rain", Float) = 1
        _RainColumns ("Rain Columns", Range(20, 120)) = 60
        _RainSpeed ("Rain Speed", Range(1, 15)) = 5
        _RainLength ("Trail Length", Range(3, 20)) = 10
        _RainBrightness ("Rain Brightness", Range(0.3, 2)) = 1.0
        _RainColor ("Rain Color", Color) = (0, 1, 0.3, 1)

        [Header(World Tint)]
        _WorldTint ("World Tint Color", Color) = (0, 0.15, 0.05, 1)
        _WorldRetain ("World Visibility", Range(0, 0.6)) = 0.25
        _WorldEdgeBoost ("Edge Highlight", Range(0, 3)) = 1.5

        [Header(Edge Detection)]
        [Toggle] _EnableEdges ("Show World Edges", Float) = 1
        _EdgeThick ("Edge Thickness", Range(0.5, 4)) = 1.5
        _EdgeSens ("Edge Sensitivity", Range(0.02, 0.3)) = 0.08

        [Header(Glitch)]
        [Toggle] _EnableGlitch ("Enable Matrix Glitch", Float) = 1
        _GlitchRate ("Glitch Rate", Range(0.8, 0.99)) = 0.93
        _GlitchShift ("Glitch Shift", Range(0.005, 0.05)) = 0.02

        [Header(Bloom)]
        [Toggle] _EnableBloom ("Enable Green Bloom", Float) = 1
        _BloomSpread ("Bloom Spread", Range(1, 8)) = 4
        _BloomAmount ("Bloom Amount", Range(0, 1)) = 0.4

        [Header(Scanlines)]
        [Toggle] _EnableScan ("Enable Monitor Scanlines", Float) = 1
        _ScanAlpha ("Scanline Opacity", Range(0, 0.4)) = 0.15
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "MatrixPass"
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _EnableRain;
            float _RainColumns;
            float _RainSpeed;
            float _RainLength;
            float _RainBrightness;
            half4 _RainColor;
            half4 _WorldTint;
            float _WorldRetain;
            float _WorldEdgeBoost;
            float _EnableEdges;
            float _EdgeThick;
            float _EdgeSens;
            float _EnableGlitch;
            float _GlitchRate;
            float _GlitchShift;
            float _EnableBloom;
            float _BloomSpread;
            float _BloomAmount;
            float _EnableScan;
            float _ScanAlpha;

            float Hash(float n) { return frac(sin(n) * 43758.5453); }
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
                float2 texelSize = _BlitTexture_TexelSize.xy;
                float time = _Time.y;

                // --- Glitch ---
                if (_EnableGlitch > 0.5)
                {
                    float glitchBlock = floor(uv.y * 30.0);
                    float glitchTime = floor(time * 8.0);
                    float r = Hash(glitchBlock + glitchTime * 17.0);
                    if (r > _GlitchRate)
                        uv.x += (Hash(glitchBlock * 3.0 + glitchTime) - 0.5) * _GlitchShift;
                }

                half3 sceneCol = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                half sceneLum = Luminance3(sceneCol);

                // --- World as green-tinted wireframe ---
                half3 world = sceneLum * _WorldTint.rgb * 2.0 + sceneCol * _WorldRetain;

                // --- Edge detection for wireframe look ---
                if (_EnableEdges > 0.5)
                {
                    float2 off = texelSize * _EdgeThick;
                    half lL = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x, 0)).rgb);
                    half lR = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( off.x, 0)).rgb);
                    half lU = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0,  off.y)).rgb);
                    half lD = Luminance3(SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(0, -off.y)).rgb);
                    float edge = abs(lL - lR) + abs(lU - lD);
                    edge = smoothstep(_EdgeSens * 0.3, _EdgeSens, edge);
                    world += _RainColor.rgb * edge * _WorldEdgeBoost;
                }

                // --- Digital rain ---
                half3 rain = half3(0, 0, 0);
                if (_EnableRain > 0.5)
                {
                    float col_id = floor(uv.x * _RainColumns);
                    float colRand = Hash(col_id * 7.0 + 3.0);
                    float speed = (0.5 + colRand * 0.5) * _RainSpeed;

                    // Character grid
                    float charHeight = _RainColumns * (_ScreenParams.y / _ScreenParams.x);
                    float2 charUV = float2(col_id, floor(uv.y * charHeight));

                    // Rain drop head position
                    float headY = frac(time * speed * 0.1 + colRand * 10.0);
                    float distFromHead = frac(headY - uv.y);

                    // Trail fade
                    float trail = smoothstep(_RainLength / charHeight, 0.0, distFromHead);
                    trail *= step(0.0, distFromHead); // only behind head

                    // Character randomization
                    float charRand = Hash21(charUV + floor(time * speed));
                    float charBright = step(0.3, charRand); // some cells are "characters"

                    // Head is brightest (white-green)
                    float headGlow = smoothstep(0.02, 0.0, distFromHead);

                    half3 trailColor = _RainColor.rgb * trail * charBright * _RainBrightness;
                    half3 headColor = half3(0.7, 1.0, 0.7) * headGlow * _RainBrightness;

                    rain = trailColor + headColor;
                }

                half3 result = world + rain;

                // --- Green bloom ---
                if (_EnableBloom > 0.5)
                {
                    half3 bloom = half3(0, 0, 0);
                    float2 bOff = texelSize * _BloomSpread;
                    int samples = 0;
                    for (int x = -2; x <= 2; x++)
                    {
                        for (int y = -2; y <= 2; y++)
                        {
                            half3 s = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(x, y) * bOff).rgb;
                            half sL = Luminance3(s);
                            bloom += sL * _RainColor.rgb * step(0.4, sL);
                            samples++;
                        }
                    }
                    bloom /= (float)samples;
                    result += bloom * _BloomAmount;
                }

                // --- Monitor scanlines ---
                if (_EnableScan > 0.5)
                {
                    float scan = sin(uv.y * _ScreenParams.y * 1.5) * 0.5 + 0.5;
                    result *= 1.0 - scan * _ScanAlpha;
                }

                return half4(saturate(result), 1.0);
            }

            ENDHLSL
        }
    }
}
