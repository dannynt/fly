using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class FilmNoirRendererFeature : ScriptableRendererFeature
{
    class FilmNoirPass : ScriptableRenderPass
    {
        private Material material;
        public FilmNoirPass(Material mat) { material = mat; requiresIntermediateTexture = true; }
        private class PassData { public TextureHandle source; }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (material == null) return;
            var resourceData = frameData.Get<UniversalResourceData>();
            var desc = renderGraph.GetTextureDesc(resourceData.activeColorTexture);
            desc.name = "_FilmNoirTemp"; desc.depthBufferBits = 0;
            TextureHandle temp = renderGraph.CreateTexture(desc);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("FilmNoirPass_Apply", out var passData))
            {
                passData.source = resourceData.activeColorTexture;
                builder.UseTexture(passData.source);
                builder.SetRenderAttachment(temp, 0);
                builder.SetRenderFunc((PassData d, RasterGraphContext ctx) =>
                    Blitter.BlitTexture(ctx.cmd, d.source, new Vector4(1, 1, 0, 0), material, 0));
            }
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("FilmNoirPass_Copy", out var passData))
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
    FilmNoirPass pass;
    public override void Create() { pass = new FilmNoirPass(material); pass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing; }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    { if (material == null) return; renderer.EnqueuePass(pass); }
}
