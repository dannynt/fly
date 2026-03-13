using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class OilPaintRendererFeature : ScriptableRendererFeature
{
    class OilPaintPass : ScriptableRenderPass
    {
        private Material material;

        public OilPaintPass(Material mat)
        {
            material = mat;
            requiresIntermediateTexture = true;
        }

        private class PassData
        {
            public TextureHandle source;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (material == null) return;
            var resourceData = frameData.Get<UniversalResourceData>();
            var desc = renderGraph.GetTextureDesc(resourceData.activeColorTexture);
            desc.name = "_OilPaintTempTexture";
            desc.depthBufferBits = 0;
            TextureHandle tempTexture = renderGraph.CreateTexture(desc);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("OilPaintPass_Apply", out var passData))
            {
                passData.source = resourceData.activeColorTexture;
                builder.UseTexture(passData.source);
                builder.SetRenderAttachment(tempTexture, 0);
                builder.SetRenderFunc((PassData data, RasterGraphContext ctx) =>
                {
                    Blitter.BlitTexture(ctx.cmd, data.source, new Vector4(1, 1, 0, 0), material, 0);
                });
            }

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("OilPaintPass_CopyBack", out var passData))
            {
                passData.source = tempTexture;
                builder.UseTexture(passData.source);
                builder.SetRenderAttachment(resourceData.activeColorTexture, 0);
                builder.SetRenderFunc((PassData data, RasterGraphContext ctx) =>
                {
                    Blitter.BlitTexture(ctx.cmd, data.source, new Vector4(1, 1, 0, 0), 0, false);
                });
            }
        }
    }

    public Material material;
    OilPaintPass pass;

    public override void Create()
    {
        pass = new OilPaintPass(material);
        pass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (material == null) return;
        renderer.EnqueuePass(pass);
    }
}
