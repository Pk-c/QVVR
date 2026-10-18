using System;
using System.Collections.Generic;
using UnityEngine;

namespace QVVR
{
    internal static class HudLayoutMath
    {
        internal static float Percent(float value)
        { return float.IsNaN(value) || float.IsInfinity(value) ? 12f : Math.Max(0f, Math.Min(45f, value)); }
        internal static float Anchor(float value, float percent)
        {
            float inset = Percent(percent) * 0.01f;
            return inset + value * (1f - 2f * inset);
        }
    }

    // Cold canvas maintenance only: inset root layout anchors, NOT font/graphic
    // scale, nested anchors, game positions, material state or every frame's mesh.
    internal sealed class HudLayoutInset
    {
        private sealed class Entry
        {
            internal Canvas Canvas;
            internal Vector2 OriginalMin, OriginalMax, AppliedMin, AppliedMax;
            internal bool Applied;
        }
        private readonly Dictionary<RectTransform, Entry> entries = new Dictionary<RectTransform, Entry>();
        internal void Apply(Canvas canvas, float percent)
        {
            float amount = HudLayoutMath.Percent(percent);
            Transform root = canvas.transform;
            for (int i = 0; i < root.childCount; ++i)
            {
                RectTransform rect = root.GetChild(i) as RectTransform;
                if (rect == null) continue;
                Entry entry;
                if (!entries.TryGetValue(rect, out entry))
                {
                    if (amount == 0f) continue;
                    entry = new Entry { Canvas = canvas, OriginalMin = rect.anchorMin, OriginalMax = rect.anchorMax };
                    entries.Add(rect, entry);
                }
                entry.Canvas = canvas;
                // Respect game-side anchor changes/animations without compounding
                // our inset at each scan. Local position/size/pivot stay untouched.
                Observe(rect, entry);
                Vector2 min = Inset(entry.OriginalMin, amount), max = Inset(entry.OriginalMax, amount);
                if (rect.anchorMin != min) rect.anchorMin = min;
                if (rect.anchorMax != max) rect.anchorMax = max;
                entry.AppliedMin = min; entry.AppliedMax = max; entry.Applied = true;
            }
            // Restore children that the game reparented outside this canvas root.
            foreach (var pair in entries)
                if (pair.Key != null && pair.Value.Canvas == canvas && pair.Key.parent != root)
                    Restore(pair.Key, pair.Value);
        }
        private static Vector2 Inset(Vector2 anchor, float percent)
        { return new Vector2(HudLayoutMath.Anchor(anchor.x, percent), HudLayoutMath.Anchor(anchor.y, percent)); }
        private static void Observe(RectTransform rect, Entry entry)
        {
            if (!entry.Applied || rect.anchorMin != entry.AppliedMin) entry.OriginalMin = rect.anchorMin;
            if (!entry.Applied || rect.anchorMax != entry.AppliedMax) entry.OriginalMax = rect.anchorMax;
        }
        private static void Restore(RectTransform rect, Entry entry)
        {
            Observe(rect, entry);
            if (rect.anchorMin != entry.OriginalMin) rect.anchorMin = entry.OriginalMin;
            if (rect.anchorMax != entry.OriginalMax) rect.anchorMax = entry.OriginalMax;
            entry.Applied = false;
        }
        internal void Clear()
        {
            foreach (var pair in entries) if (pair.Key != null) Restore(pair.Key, pair.Value);
            entries.Clear();
        }
    }
}
