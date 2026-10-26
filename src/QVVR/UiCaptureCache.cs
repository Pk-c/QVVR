using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;
using UnityEngine.UI;

namespace QVVR
{
    // Retain the full-resolution texture while ordinary UI is unchanged.
    // Unknown/custom materials and active Animators retain the original cadence.
    // Transform and CanvasGroup changes do not always dirty a Graphic, so they
    // are also observed, without clearing game-owned Transform.hasChanged flags.
    internal sealed class UiCaptureCache
    {
        private struct Pose
        {
            internal RectTransform Transform;
            internal Vector3 Position, Scale;
            internal Quaternion Rotation;
            internal Rect Rect;
            internal bool Active;
        }
        private struct Group { internal CanvasGroup Component; internal float Alpha; internal bool Enabled, IgnoreParents; }
        private readonly List<Graphic> graphics = new List<Graphic>(128);
        private readonly List<bool> graphicEnabled = new List<bool>(128);
        private readonly List<bool> graphicBuiltIn = new List<bool>(128);
        private readonly List<UiMaterialWatch> materialWatches = new List<UiMaterialWatch>(128);
        // Built-in graphics whose custom material is a known static shader
        // (resolved in cold Watch): compared by reference in Continuous().
        private readonly List<Material> graphicStaticMaterials = new List<Material>(128);
        // Looping decorative UI particles disabled while VR captures the HUD;
        // re-enabled by Clear() (VR off, scene change, cache failure).
        private readonly List<Graphic> hiddenParticles = new List<Graphic>(16);
        private readonly Dictionary<Graphic, UiMaterialWatch> cachedMaterialWatches = new Dictionary<Graphic, UiMaterialWatch>();
        private readonly List<Graphic> expiredMaterialWatches = new List<Graphic>(16);
        private readonly Dictionary<Graphic, int> subscriptions = new Dictionary<Graphic, int>();
        private readonly List<Graphic> expiredSubscriptions = new List<Graphic>(16);
        private int scan;
        private bool suspended;
        private float nextProbe;
        private readonly List<Color> graphicColors = new List<Color>(128);
        private readonly List<float> graphicAlphas = new List<float>(128); // CanvasRenderer alpha (CrossFadeAlpha).
        private readonly List<Canvas> canvases = new List<Canvas>(16);
        private readonly List<bool> canvasEnabled = new List<bool>(16);
        private readonly List<Pose> poses = new List<Pose>(128);
        // Only ACTIVE widgets are snapshotted. Hidden panels are watched through
        // the top of each inactive subtree: when one activates, the cache keeps
        // the original capture cadence until the next scan snapshots it.
        private readonly List<Transform> inactiveRoots = new List<Transform>(32);
        private bool stale;
        private readonly List<Group> groups = new List<Group>(16);
        private readonly List<Animator> animators = new List<Animator>(8);
        private readonly List<Graphic> foundGraphics = new List<Graphic>(128);
        private readonly List<RectTransform> foundRects = new List<RectTransform>(128);
        private readonly List<CanvasGroup> foundGroups = new List<CanvasGroup>(16);
        private readonly List<Animator> foundAnimators = new List<Animator>(8);
        private readonly List<Canvas> foundCanvases = new List<Canvas>(16);
        private readonly UnityAction invalidate;
        private bool dirty = true;
        internal bool Failed { get; private set; }
        internal ulong Captures { get; private set; }
        internal ulong Reuses { get; private set; }
        internal int ContinuousReason { get; private set; } // 0=static, 1=failed, 2=material, 3=Animator.
        internal bool Suspended { get { return suspended; } }
        internal bool HideParticles
        {
            get { return hideParticles; }
            set { hideParticles = value; if (!value) RestoreParticles(); }
        }
        private bool hideParticles;
        internal int HiddenParticles { get { return hiddenParticles.Count; } }
        internal int WatchedGraphics { get { return graphics.Count; } }
        internal int WatchedRects { get { return poses.Count; } }
        internal int InactiveRoots { get { return inactiveRoots.Count; } }
        internal bool Stale { get { return stale; } } // An opened hidden panel awaits a snapshot scan.
        internal UiCaptureCache() { invalidate = Invalidate; }
        internal void Invalidate() { dirty = true; }
        internal void BeginScan()
        { BeginScan(false); }
        private void BeginScan(bool incremental)
        {
            if (incremental)
            {
                // A rescan alone must not force a HUD re-render: keep the texture
                // unless the old snapshot already differs from the live UI.
                bool changed = dirty || stale || Changed();
                ClearSnapshots();
                dirty = changed;
            }
            else Unwatch();
            stale = false;
            scan++;
            // Retain cold-bound TMP delegates across the regular maintenance
            // scan. Destroyed popup widgets must not retain their bound targets.
            expiredMaterialWatches.Clear();
            foreach (KeyValuePair<Graphic, UiMaterialWatch> pair in cachedMaterialWatches)
                if (pair.Key == null) expiredMaterialWatches.Add(pair.Key);
            for (int i = 0; i < expiredMaterialWatches.Count; i++) cachedMaterialWatches.Remove(expiredMaterialWatches[i]);
            expiredMaterialWatches.Clear();
        }
        // Cold maintenance only. Continuous/unknown UI must still render at the
        // original cadence, but does not need snapshots or dirty subscriptions.
        internal bool BeginMaintenance(float now, bool enabled, bool lightweight)
        {
            if (!enabled || Failed)
            {
                Unwatch(); suspended = true; nextProbe = 0f;
                ContinuousReason = Failed ? 1 : 0;
                return false;
            }
            if (lightweight && suspended && now < nextProbe) return false;
            suspended = false;
            BeginScan(lightweight);
            return true;
        }
        internal void EndMaintenance(float now, bool lightweight)
        {
            expiredSubscriptions.Clear();
            foreach (KeyValuePair<Graphic, int> pair in subscriptions)
                if (pair.Key == null || pair.Value != scan) expiredSubscriptions.Add(pair.Key);
            for (int i = 0; i < expiredSubscriptions.Count; i++)
            {
                Graphic graphic = expiredSubscriptions[i]; Unsubscribe(graphic); subscriptions.Remove(graphic);
            }
            expiredSubscriptions.Clear();
            if (lightweight && Continuous())
            {
                Unwatch(); suspended = true; nextProbe = now + 2f;
            }
        }
        internal void Watch(Canvas canvas)
        {
            if (Failed) return;
            foundGraphics.Clear(); foundRects.Clear(); foundGroups.Clear(); foundAnimators.Clear();
            canvas.GetComponentsInChildren<Graphic>(true, foundGraphics);
            canvas.GetComponentsInChildren<RectTransform>(true, foundRects);
            canvas.GetComponentsInChildren<CanvasGroup>(true, foundGroups);
            canvas.GetComponentsInChildren<Animator>(true, foundAnimators);
            foundCanvases.Clear(); canvas.GetComponentsInChildren<Canvas>(true, foundCanvases);
            // CanvasGroups outside the root canvas can still fade its children.
            for (Transform parent = canvas.transform.parent; parent != null; parent = parent.parent)
            {
                CanvasGroup group = parent.GetComponent<CanvasGroup>();
                if (group != null && !foundGroups.Contains(group)) foundGroups.Add(group);
                Animator animator = parent.GetComponent<Animator>();
                if (animator != null && !foundAnimators.Contains(animator)) foundAnimators.Add(animator);
            }
            for (int i = 0; i < foundGraphics.Count; i++)
            {
                Graphic graphic = foundGraphics[i];
                if (graphic == null) continue;
                if (HideParticles && graphic.enabled && IsDecorativeParticle(graphic.GetType()))
                {
                    // Looping sparkles would force a full HUD re-render every
                    // frame. Disabling the Graphic also stops its mesh baking.
                    graphic.enabled = false;
                    hiddenParticles.Add(graphic);
                    continue;
                }
                int seen;
                bool subscribed = subscriptions.TryGetValue(graphic, out seen);
                if (subscribed && seen == scan) continue;
                bool active = graphic.gameObject.activeInHierarchy;
                // New visible widgets (instantiated popups) were never captured:
                // their OnEnable dirty event fired before this subscription.
                if (!subscribed && active) dirty = true;
                if (!subscribed)
                {
                    graphic.RegisterDirtyVerticesCallback(invalidate);
                    graphic.RegisterDirtyMaterialCallback(invalidate);
                    graphic.RegisterDirtyLayoutCallback(invalidate);
                }
                subscriptions[graphic] = scan;
                if (!active) continue; // Covered by its inactive subtree root.
                graphics.Add(graphic);
                graphicEnabled.Add(graphic.enabled);
                graphicColors.Add(graphic.canvasRenderer.GetColor());
                graphicAlphas.Add(graphic.canvasRenderer.GetAlpha());
                // Graphic.material is VIRTUAL. TMP_SubMeshUI's getter can
                // instantiate a material (or throw while an inactive submesh
                // has no source). Never call third-party material getters.
                // Only exact built-in uGUI types have the shared, non-cloning
                // getters we support. Unknown graphics keep normal cadence.
                System.Type type = graphic.GetType();
                bool builtIn = type == typeof(Image) || type == typeof(RawImage) || type == typeof(Text);
                graphicBuiltIn.Add(builtIn);
                Material custom = builtIn ? graphic.material : null;
                graphicStaticMaterials.Add(custom != null && custom != graphic.defaultMaterial && custom.shader != null &&
                    StaticCustomShader(custom.shader.name) ? custom : null); // Shader.name allocates: cold scan only.
                UiMaterialWatch watch = null;
                if (!builtIn)
                {
                    if (!cachedMaterialWatches.TryGetValue(graphic, out watch))
                    {
                        watch = new UiMaterialWatch(graphic);
                        cachedMaterialWatches.Add(graphic, watch);
                    }
                    else watch.Refresh();
                }
                materialWatches.Add(watch);
            }
            Transform root = canvas.transform;
            for (int i = 0; i < foundRects.Count; i++)
            {
                RectTransform t = foundRects[i];
                if (!t.gameObject.activeInHierarchy)
                {
                    // Topmost inactive object only; its descendants follow it.
                    if (t == root || t.parent == null || t.parent.gameObject.activeInHierarchy) inactiveRoots.Add(t);
                    continue;
                }
                poses.Add(new Pose { Transform = t, Position = t.localPosition, Rotation = t.localRotation,
                    Scale = t.localScale, Rect = t.rect, Active = true });
            }
            for (int i = 0; i < foundGroups.Count; i++)
            {
                CanvasGroup group = foundGroups[i];
                groups.Add(new Group { Component = group, Alpha = group.alpha, Enabled = group.enabled, IgnoreParents = group.ignoreParentGroups });
            }
            for (int i = 0; i < foundCanvases.Count; i++) { canvases.Add(foundCanvases[i]); canvasEnabled.Add(foundCanvases[i].enabled); }
            for (int i = 0; i < foundAnimators.Count; i++) animators.Add(foundAnimators[i]);
        }
        internal bool NeedsCapture()
        {
            if (suspended || dirty || stale || Continuous()) return true;
            if (Changed()) return true;
            Reuses++;
            return false;
        }
        // Live UI differs from the snapshot of the last capture.
        private bool Changed()
        {
            for (int i = 0; i < graphics.Count; i++)
                if (graphics[i] == null || graphics[i].enabled != graphicEnabled[i] || graphics[i].canvasRenderer.GetColor() != graphicColors[i] ||
                    graphics[i].canvasRenderer.GetAlpha() != graphicAlphas[i]) return true;
            for (int i = 0; i < canvases.Count; i++) if (canvases[i] == null || canvases[i].enabled != canvasEnabled[i]) return true;
            for (int i = 0; i < groups.Count; i++)
            {
                Group state = groups[i];
                if (state.Component == null || state.Component.alpha != state.Alpha || state.Component.enabled != state.Enabled || state.Component.ignoreParentGroups != state.IgnoreParents) return true;
            }
            for (int i = 0; i < poses.Count; i++)
            {
                Pose state = poses[i]; RectTransform t = state.Transform;
                if (t == null || t.gameObject.activeInHierarchy != state.Active || t.localPosition != state.Position ||
                    t.localRotation != state.Rotation || t.localScale != state.Scale || t.rect != state.Rect) return true;
            }
            for (int i = 0; i < inactiveRoots.Count; i++)
            {
                Transform t = inactiveRoots[i];
                if (t == null || t.gameObject.activeInHierarchy) { stale = true; return true; }
            }
            return false;
        }
        private bool Continuous()
        {
            ContinuousReason = 0;
            if (Failed) { ContinuousReason = 1; return true; }
            for (int i = 0; i < graphics.Count; i++)
            {
                Graphic graphic = graphics[i];
                if (graphic == null || !graphic.enabled || !graphic.gameObject.activeInHierarchy) continue;
                bool blocks;
                if (graphicBuiltIn[i])
                {
                    Material material = graphic.material;
                    blocks = material != graphic.defaultMaterial && material != graphicStaticMaterials[i];
                }
                else
                {
                    UiMaterialWatch watch = materialWatches[i];
                    blocks = watch == null || watch.Continuous();
                }
                // Visibility is checked only for would-be blockers (two engine calls).
                if (blocks && Visible(graphic)) { ContinuousReason = 2; return true; }
            }
            for (int i = 0; i < animators.Count; i++)
            {
                Animator animator = animators[i];
                if (animator != null && animator.enabled && animator.gameObject.activeInHierarchy && animator.speed != 0f) { ContinuousReason = 3; return true; }
            }
            return false;
        }
        internal void Captured()
        {
            Captures++;
            // Animated/custom UI already keeps its original refresh rate. Do
            // not also walk every widget to build an unused static snapshot.
            if (suspended || Continuous()) { dirty = true; return; }
            for (int i = 0; i < graphics.Count; i++) if (graphics[i] != null)
            {
                graphicEnabled[i] = graphics[i].enabled;
                graphicColors[i] = graphics[i].canvasRenderer.GetColor();
                graphicAlphas[i] = graphics[i].canvasRenderer.GetAlpha();
            }
            for (int i = 0; i < canvases.Count; i++) if (canvases[i] != null) canvasEnabled[i] = canvases[i].enabled;
            for (int i = 0; i < groups.Count; i++)
            {
                Group state = groups[i];
                if (state.Component != null) { state.Alpha = state.Component.alpha; state.Enabled = state.Component.enabled; state.IgnoreParents = state.Component.ignoreParentGroups; groups[i] = state; }
            }
            for (int i = 0; i < poses.Count; i++)
            {
                Pose state = poses[i]; RectTransform t = state.Transform;
                if (t == null) continue;
                state.Position = t.localPosition; state.Rotation = t.localRotation; state.Scale = t.localScale;
                state.Rect = t.rect; state.Active = t.gameObject.activeInHierarchy; poses[i] = state;
            }
            dirty = false;
        }
        private void Unwatch()
        {
            foreach (KeyValuePair<Graphic, int> pair in subscriptions) Unsubscribe(pair.Key);
            subscriptions.Clear();
            ClearSnapshots();
        }
        private void Unsubscribe(Graphic graphic)
        {
            if (graphic == null) return;
            graphic.UnregisterDirtyVerticesCallback(invalidate);
            graphic.UnregisterDirtyMaterialCallback(invalidate);
            graphic.UnregisterDirtyLayoutCallback(invalidate);
        }
        private void ClearSnapshots()
        {
            graphics.Clear(); graphicEnabled.Clear(); graphicBuiltIn.Clear(); graphicStaticMaterials.Clear(); materialWatches.Clear(); graphicColors.Clear(); graphicAlphas.Clear();
            canvases.Clear(); canvasEnabled.Clear(); poses.Clear(); inactiveRoots.Clear(); groups.Clear(); animators.Clear(); dirty = true; stale = false;
        }
        internal void Clear() { Unwatch(); stale = false; RestoreParticles(); cachedMaterialWatches.Clear(); expiredMaterialWatches.Clear(); expiredSubscriptions.Clear(); suspended = false; nextProbe = 0f; }
        private void RestoreParticles()
        {
            for (int i = 0; i < hiddenParticles.Count; i++) if (hiddenParticles[i] != null) hiddenParticles[i].enabled = true;
            hiddenParticles.Clear();
        }
        // QV keeps hidden panels (loading image, achievement gauges) enabled with
        // zero alpha. Their materials cannot change the capture while invisible;
        // becoming visible changes a snapshotted color, alpha or CanvasGroup.
        private static bool Visible(Graphic graphic)
        {
            if (graphic.color.a <= 0f) return false;
            CanvasRenderer renderer = graphic.canvasRenderer;
            return !renderer.cull && renderer.GetInheritedAlpha() > 0f;
        }
        // QV's HUD sparkles (fairy acquire/clear effects) use Coffee UIParticle.
        private static bool IsDecorativeParticle(System.Type type)
        {
            return type.FullName == "Coffee.UIExtensions.UIParticle";
        }
        // Custom built-in Image materials without time-driven animation.
        private static bool StaticCustomShader(string name)
        {
            return name == "ERB/Particles/Add_CenterGlow" || name == "UI/Default-SoftMask";
        }
        // A cache is optional, scene/controller preparation is not. Keep this
        // circuit breaker for the session, including across maintenance scans.
        internal void DisableReuse() { Failed = true; Clear(); }
    }
}
