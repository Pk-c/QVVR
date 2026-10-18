using UnityEngine;
using UnityEngine.UI;

namespace QVVR
{
    // Mirrors the verified Cloud.Panel tween without changing its color, input,
    // callbacks or scene timing. One cached material, no extra render target.
    internal sealed class VrScreenFade
    {
        private Material material;
        private Image source;
        private bool active, hidden, wasCulled, finishWhenClear;
        internal float Opacity { get; private set; }

        internal void Initialize()
        {
            Shader shader = Shader.Find("Sprites/Default");
            if (shader == null || !shader.isSupported) return;
            // Built-in premultiplied One/OneMinusSrcAlpha blending also composes
            // alpha correctly over empty passthrough pixels, not just game RGB.
            material = new Material(shader) { name = "QVVR_ComfortFade", hideFlags = HideFlags.HideAndDontSave };
            material.mainTexture = Texture2D.whiteTexture;
            material.color = Color.white;
        }

        internal void Begin(Image panel)
        {
            if (material == null || panel == null) return; // Original rectangle remains as fallback.
            Restore(); source = panel; active = true; finishWhenClear = false; Opacity = 0f;
        }

        internal void SceneChanged(bool gameplay, bool loading)
        {
            if (!active) return;
            if (gameplay) finishWhenClear = true;
            else if (!loading) { Restore(); active = false; Opacity = 0f; }
        }

        // Called once per stereo frame, before UI capture; same opacity in eyes.
        internal void Prepare()
        {
            Restore(); // Preserve baseline even if a caller retries preparation.
            if (!active || source == null) { Opacity = 0f; active = false; return; }
            float alpha = source.gameObject.activeInHierarchy && source.enabled ? source.color.a : 0f;
            Opacity = float.IsNaN(alpha) || float.IsInfinity(alpha) ? 0f : Mathf.Clamp01(alpha);
            // Loading may itself fade in/out. Keep mirroring until the final
            // gameplay fade-in completes, rather than releasing at Loading's 0.
            if (finishWhenClear && Opacity == 0f) { active = false; return; }
            // Cull just this graphic; toggling Image.enabled every capture
            // would unregister/rebuild UI and run unnecessary enable callbacks.
            wasCulled = source.canvasRenderer.cull; hidden = true;
            source.canvasRenderer.cull = true;
        }

        internal void Restore()
        {
            if (hidden && source != null) source.canvasRenderer.cull = wasCulled;
            hidden = false;
        }

        internal void Render(RenderTexture target)
        {
            if (Opacity <= 0f || material == null || target == null) return;
            RenderTexture previous = RenderTexture.active;
            RenderTexture.active = target;
            GL.PushMatrix();
            try
            {
                GL.LoadOrtho();
                if (!material.SetPass(0)) { Release(); return; }
                // Full-eye clip-independent overlay, after world + HUD + resolve.
                // Keep color, clear only depth. Stereo/head pose cannot expose edges.
                GL.Clear(true, false, Color.clear);
                GL.Begin(GL.QUADS);
                GL.Color(new Color(0f, 0f, 0f, Opacity));
                GL.Vertex3(0f, 0f, 0f); GL.Vertex3(0f, 1f, 0f);
                GL.Vertex3(1f, 1f, 0f); GL.Vertex3(1f, 0f, 0f);
                GL.End();
            }
            finally { GL.PopMatrix(); RenderTexture.active = previous; }
        }

        internal void Release()
        {
            Restore(); active = false; source = null; Opacity = 0f;
            if (material != null) Object.Destroy(material);
            material = null;
        }
    }
}
