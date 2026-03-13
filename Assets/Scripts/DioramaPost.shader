Shader "Hidden/DioramaPost"
{
    Properties
    {
        _Intensity ("Effect Intensity", Range(0,1)) = 1

        [Header(Miniature Scale)]
        _FocusBand ("Focus Band Center", Range(0,1)) = 0.5
        _FocusWidth ("Focus Band Width", Range(0.05,0.5)) = 0.15
        _BlurStrength ("Blur Strength", Range(0,5)) = 2.5
        _BlurSamples ("Blur Quality", Range(1,4)) = 2

        [Header(Toy Colors)]
        _Saturation ("Saturation Boost", Range(1,2)) = 1.35
        _Vibrance ("Vibrance", Range(0,1)) = 0.4
        _Contrast ("Contrast", Range(0.8,1.5)) = 1.15
        _ColorTemp ("Color Temperature", Range(-0.3,0.3)) = 0.05

        [Header(Edge Darkening)]
        _EdgeDarken ("Edge Darkening", Range(0,1)) = 0.4
        _EdgeThickness ("Edge Thickness", Range(0.5,3)) = 1.5
        _EdgeDepthSensitivity ("Depth Edge Sensitivity", Range(0,5)) = 2.5

        [Header(Shadow Enhancement)]
        _ShadowDeepen ("Shadow Deepen", Range(0,0.5)) = 0.15
        _ShadowColor ("Shadow Tint", Color) = (0.7, 0.72, 0.8, 1)
        _AO ("Fake AO", Range(0,1)) = 0.3

        [Header(Highlights)]
        _HighlightBoost ("Highlight Boost", Range(0,0.5)) = 0.15
        _Specular ("Plastic Specular", Range(0,1)) = 0.3

        [Header(Vignette)]
        _Vignette ("Vignette", Range(0,1)) = 0.35
        _VignetteRoundness ("Vignette Roundness", Range(0.5,2)) = 1.2
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "DioramaPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            float _Intensity;

            float _FocusBand;
            float _FocusWidth;
            float _BlurStrength;
            float _BlurSamples;

            float _Saturation;
            float _Vibrance;
            float _Contrast;
            float _ColorTemp;

            float _EdgeDarken;
            float _EdgeThickness;
            float _EdgeDepthSensitivity;

            float _ShadowDeepen;
            float4 _ShadowColor;
            float _AO;

            float _HighlightBoost;
            float _Specular;

            float _Vignette;
            float _VignetteRoundness;

            float sampleDepth01(float2 uv)
            {
                return Linear01Depth(SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r, _ZBufferParams);
            }

            float4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;
                float2 texel = 1.0 / _ScreenParams.xy;

                // ---- Focus band blur (tilt-shift miniature) ----
                float focusDist = abs(uv.y - _FocusBand);
                float blurAmount = smoothstep(0, _FocusWidth, focusDist) * _BlurStrength;

                float3 col = float3(0,0,0);
                float totalW = 0;
                int samples = (int)_BlurSamples;

                if (blurAmount > 0.05)
                {
                    // Hexagonal-ish blur pattern for bokeh feel
                    for (int bx = -samples; bx <= samples; bx++)
                    {
                        for (int by = -samples; by <= samples; by++)
                        {
                            float2 off = float2(bx, by) * texel * blurAmount;
                            // Circular mask
                            float d = length(float2(bx, by)) / (float)samples;
                            if (d > 1.2) continue;
                            float w = 1.0 - d * 0.5;
                            float3 s = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + off).rgb;

                            // Bokeh: bright spots get extra weight
                            float sl = dot(s, float3(0.299, 0.587, 0.114));
                            w *= 1.0 + smoothstep(0.6, 1.0, sl) * 2.0;

                            col += s * w;
                            totalW += w;
                        }
                    }
                    col = (totalW > 0) ? col / totalW : SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                }
                else
                {
                    col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                }
                float3 original = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;

                float lum = dot(col, float3(0.299, 0.587, 0.114));
                float depth = sampleDepth01(uv);

                // ---- Edge darkening (depth-based) ----
                if (_EdgeDarken > 0.01)
                {
                    float t = _EdgeThickness;
                    float dC = sampleDepth01(uv);
                    float dL = sampleDepth01(uv + float2(-t, 0) * texel);
                    float dR = sampleDepth01(uv + float2( t, 0) * texel);
                    float dU = sampleDepth01(uv + float2(0, -t) * texel);
                    float dD = sampleDepth01(uv + float2(0,  t) * texel);

                    float depthEdge = abs(dL - dR) + abs(dU - dD);
                    depthEdge = smoothstep(0, 0.001 * _EdgeDepthSensitivity, depthEdge);

                    // Also detect color edges for flat surfaces
                    float3 cL = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-t, 0) * texel).rgb;
                    float3 cR = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2( t, 0) * texel).rgb;
                    float colorEdge = length(cL - cR);
                    colorEdge = smoothstep(0, 0.15, colorEdge);

                    float edge = saturate(max(depthEdge, colorEdge * 0.5));
                    col *= 1.0 - edge * _EdgeDarken * 0.6;
                }

                // ---- Fake ambient occlusion ----
                if (_AO > 0.01)
                {
                    float ao = 0;
                    float aoRadius = 3.0;
                    float centerD = sampleDepth01(uv);
                    ao += max(0, sampleDepth01(uv + float2(-aoRadius, 0) * texel) - centerD);
                    ao += max(0, sampleDepth01(uv + float2( aoRadius, 0) * texel) - centerD);
                    ao += max(0, sampleDepth01(uv + float2(0, -aoRadius) * texel) - centerD);
                    ao += max(0, sampleDepth01(uv + float2(0,  aoRadius) * texel) - centerD);
                    ao = smoothstep(0, 0.005, ao);
                    col *= 1.0 - ao * _AO * 0.5;
                }

                // ---- Shadow enhancement ----
                float shadowMask = 1.0 - smoothstep(0, 0.35, lum);
                col = lerp(col, col * _ShadowColor.rgb, shadowMask * _ShadowDeepen);
                col *= 1.0 - shadowMask * _ShadowDeepen * 0.3;

                // ---- Toy color saturation ----
                float newLum = dot(col, float3(0.299, 0.587, 0.114));
                col = lerp(float3(newLum, newLum, newLum), col, _Saturation);

                // Vibrance (boost less saturated colors more)
                float maxC = max(col.r, max(col.g, col.b));
                float minC = min(col.r, min(col.g, col.b));
                float curSat = (maxC > 0.001) ? (maxC - minC) / maxC : 0;
                float vibBoost = (1.0 - curSat) * _Vibrance;
                col = lerp(float3(newLum, newLum, newLum), col, 1.0 + vibBoost);

                // ---- Contrast ----
                col = (col - 0.5) * _Contrast + 0.5;

                // ---- Color temperature ----
                col.r += _ColorTemp * 0.05;
                col.b -= _ColorTemp * 0.05;

                // ---- Highlight boost (plastic/toy look) ----
                float highlightMask = smoothstep(0.6, 0.9, lum);
                col += highlightMask * _HighlightBoost;

                // ---- Plastic specular (small bright spots) ----
                float specMask = smoothstep(0.85, 0.95, lum);
                col += specMask * _Specular * float3(1.0, 0.98, 0.95) * 0.3;

                // ---- Vignette (elliptical for diorama framing) ----
                float2 vc = (uv - 0.5) * float2(1.0, _VignetteRoundness);
                float vd = length(vc);
                float vig = 1.0 - smoothstep(0.3, 0.85, vd);
                col *= lerp(1.0, vig, _Vignette);

                col = saturate(col);
                col = lerp(original, col, _Intensity);

                return float4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
