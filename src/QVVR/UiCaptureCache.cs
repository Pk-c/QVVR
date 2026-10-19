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
        private readonly Dictionary<Graphic, UiMaterialWatch> cachedMaterialWatches = new Dictionary<Graphic, UiMaterialWatch>();
        private readonly List<Graphic> expiredMaterialWatches = new List<Graphic>(16);
        private readonly List<Color> graphicColors = new List<Color>(128);
        private readonly List<Canvas> canvases = new List<Canvas>(16);
        private readonly List<bool> canvasEnabled = new List<bool>(16);
        private readonly List<Pose> poses = new List<Pose>(128);
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
        internal UiCaptureCache() { invalidate = Invalidate; }
        internal void Invalidate() { dirty = true; }
        internal void BeginScan()
        {
            Unwatch();
            // Retain cold-bound TMP delegates across the regular maintenance
            // scan. Destroyed popup widgets must not retain their bound targets.
            expiredMaterialWatches.Clear();
            foreach (KeyValuePair<Graphic, UiMaterialWatch> pair in cachedMaterialWatches)
                if (pair.Key == null) expiredMaterialWatches.Add(pair.Key);
            for (int i = 0; i < expiredMaterialWatches.Count; i++) cachedMaterialWatches.Remove(expiredMaterialWatches[i]);
            expiredMaterialWatches.Clear();
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
                if (graphic == null || graphics.Contains(graphic)) continue;
                graphics.Add(graphic);
                graphicEnabled.Add(graphic.enabled);
                graphicColors.Add(graphic.canvasRenderer.GetColor());
                graphic.RegisterDirtyVerticesCallback(invalidate);
                graphic.RegisterDirtyMaterialCallback(invalidate);
                graphic.RegisterDirtyLayoutCallback(invalidate);
                // Graphic.material is VIRTUAL. TMP_SubMeshUI's getter can
                // instantiate a material (or throw while an inactive submesh
                // has no source). Never call third-party material getters.
                // Only exact built-in uGUI types have the shared, non-cloning
                // getters we support. Unknown graphics keep normal cadence.
                System.Type type = graphic.GetType();
                bool builtIn = type == typeof(Image) || type == typeof(RawImage) || type == typeof(Text);
                graphicBuiltIn.Add(builtIn);
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
            for (int i = 0; i < foundRects.Count; i++)
            {
                RectTransform t = foundRects[i];
                poses.Add(new Pose { Transform = t, Position = t.localPosition, Rotation = t.localRotation,
                    Scale = t.localScale, Rect = t.rect, Active = t.gameObject.activeInHierarchy });
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
            if (dirty || Continuous()) return true;
            for (int i = 0; i < graphics.Count; i++)
                if (graphics[i] == null || graphics[i].enabled != graphicEnabled[i] || graphics[i].canvasRenderer.GetColor() != graphicColors[i]) return true;
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
            Reuses++;
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
                if (graphicBuiltIn[i])
                {
                    if (graphic.material != graphic.defaultMaterial) { ContinuousReason = 2; return true; }
                    continue;
                }
                UiMaterialWatch watch = materialWatches[i];
                if (watch == null || watch.Continuous()) { ContinuousReason = 2; return true; }
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
            if (Continuous()) { dirty = true; return; }
            for (int i = 0; i < graphics.Count; i++) if (graphics[i] != null)
            {
                graphicEnabled[i] = graphics[i].enabled;
                graphicColors[i] = graphics[i].canvasRenderer.GetColor();
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
            for (int i = 0; i < graphics.Count; i++)
            {
                Graphic graphic = graphics[i];
                if (graphic == null) continue;
                graphic.UnregisterDirtyVerticesCallback(invalidate);
                graphic.UnregisterDirtyMaterialCallback(invalidate);
                graphic.UnregisterDirtyLayoutCallback(invalidate);
            }
            graphics.Clear(); graphicEnabled.Clear(); graphicBuiltIn.Clear(); materialWatches.Clear(); graphicColors.Clear();
            canvases.Clear(); canvasEnabled.Clear(); poses.Clear(); groups.Clear(); animators.Clear(); dirty = true;
        }
        internal void Clear() { Unwatch(); cachedMaterialWatches.Clear(); expiredMaterialWatches.Clear(); }
        // A cache is optional, scene/controller preparation is not. Keep this
        // circuit breaker for the session, including across maintenance scans.
        internal void DisableReuse() { Failed = true; Clear(); }
    }
}
