using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class HologramRendererFeature : ScriptableRendererFeature
{
    class HologramPass : ScriptableRenderPass
    {
        private Material material;
        public HologramPass(Material mat) { material = mat; requiresIntermediateTexture = true; }

        private class PassData { public TextureHandle source; }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (material == null) return;
            var resourceData = frameData.Get<UniversalResourceData>();
            var desc = renderGraph.GetTextureDesc(resourceData.activeColorTexture);
            desc.name = "_HologramTemp"; desc.depthBufferBits = 0;
            TextureHandle temp = renderGraph.CreateTexture(desc);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("HologramPass_Apply", out var passData))
            {
                passData.source = resourceData.activeColorTexture;
                builder.UseTexture(passData.source);
                builder.SetRenderAttachment(temp, 0);
                builder.SetRenderFunc((PassData d, RasterGraphContext ctx) =>
                    Blitter.BlitTexture(ctx.cmd, d.source, new Vector4(1, 1, 0, 0), material, 0));
            }
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("HologramPass_Copy", out var passData))
            {
                passData.source = temp;
                builder.UseTexture(passData.source);
                builder.SetRenderAttachment(resourceData.activeColorTexture, 0);
                builder.SetRenderFunc((PassData d, RasterGraphContext ctx) =>
                    Blitter.BlitTexture(ctx.cmd, d.source, new Vector4(1, 1, 0, 0), 0, false));
            }
        }
    }

    public Material material;
    HologramPass pass;
    public override void Create() { pass = new HologramPass(material); pass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing; }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    { if (material == null) return; renderer.EnqueuePass(pass); }
}
