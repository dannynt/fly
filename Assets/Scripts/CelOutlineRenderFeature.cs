using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class CelOutlineRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public Material material;
        public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    public Settings settings = new Settings();

    class CelOutlinePass : ScriptableRenderPass
    {
        Material mat;
        const string passName = "CelOutlinePass";

        public CelOutlinePass(Material material, RenderPassEvent evt)
        {
            mat = material;
            renderPassEvent = evt;
            requiresIntermediateTexture = true;
            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        class CopyPassData { public TextureHandle src; }
        class EffectPassData { public TextureHandle src; public Material mat; }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();

            var descriptor = cameraData.cameraTargetDescriptor;
            descriptor.depthBufferBits = 0;
            descriptor.msaaSamples = 1;

            TextureHandle src = resourceData.activeColorTexture;
            TextureHandle tmp = UniversalRenderer.CreateRenderGraphTexture(renderGraph, descriptor, "_CelOutlineTmp", false);

            using (var builder = renderGraph.AddRasterRenderPass<EffectPassData>(passName + "_Effect", out var passData))
            {
                passData.src = src;
                passData.mat = mat;
                builder.UseTexture(src, AccessFlags.Read);
                builder.SetRenderAttachment(tmp, 0, AccessFlags.Write);
                builder.SetRenderFunc((EffectPassData data, RasterGraphContext ctx) =>
                {
                    Blitter.BlitTexture(ctx.cmd, data.src, new Vector4(1, 1, 0, 0), data.mat, 0);
                });
            }

            using (var builder = renderGraph.AddRasterRenderPass<CopyPassData>(passName + "_Copy", out var passData))
            {
                passData.src = tmp;
                builder.UseTexture(tmp, AccessFlags.Read);
                builder.SetRenderAttachment(src, 0, AccessFlags.Write);
                builder.SetRenderFunc((CopyPassData data, RasterGraphContext ctx) =>
                {
                    Blitter.BlitTexture(ctx.cmd, data.src, new Vector4(1, 1, 0, 0), 0, false);
                });
            }
        }
    }

    CelOutlinePass pass;

    public override void Create()
    {
        if (settings.material == null) return;
        pass = new CelOutlinePass(settings.material, settings.renderPassEvent);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.material == null) return;
        renderer.EnqueuePass(pass);
    }
}
