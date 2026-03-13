using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class DreamRendererFeature : ScriptableRendererFeature
{
    class DreamPass : ScriptableRenderPass
    {
        private Material material;

        public DreamPass(Material mat)
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
            desc.name = "_DreamTempTexture";
            desc.depthBufferBits = 0;
            TextureHandle tempTexture = renderGraph.CreateTexture(desc);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("DreamPass_Apply", out var passData))
            {
                passData.source = resourceData.activeColorTexture;
                builder.UseTexture(passData.source);
                builder.SetRenderAttachment(tempTexture, 0);

                builder.SetRenderFunc((PassData data, RasterGraphContext ctx) =>
                {
                    Blitter.BlitTexture(ctx.cmd, data.source, new Vector4(1, 1, 0, 0), material, 0);
                });
            }

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("DreamPass_CopyBack", out var passData))
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
    DreamPass pass;

    public override void Create()
    {
        pass = new DreamPass(material);
        pass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (material == null) return;
        renderer.EnqueuePass(pass);
    }
}
