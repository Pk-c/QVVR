using System;
using System.Collections.Generic;
using HarmonyLib;
using UnityEngine;

namespace QVVR
{
    // QV Dialog projects its actor through the original camera. Keep those
    // game-owned coordinates intact and override only the captured VR layout.
    internal sealed class DialogHudLayout
    {
        private struct Entry
        {
            internal RectTransform Rect, Canvas;
            internal Canvas Owner;
            internal CanvasGroup Group;
            internal Vector3 Position;
            internal bool Applied;
        }
        private Type dialogType;
        private readonly List<Entry> entries = new List<Entry>(4);

        internal void Initialize() { dialogType = AccessTools.TypeByName("Dialog"); }
        internal void BeginScan() { Restore(); entries.Clear(); }
        internal void Watch(Canvas canvas)
        {
            if (dialogType == null || canvas == null) return;
            RectTransform root = canvas.transform as RectTransform;
            if (root == null) return;
            // Discovery/arrays are cold, alongside the existing canvas scan.
            Component[] dialogs = canvas.GetComponentsInChildren(dialogType, true);
            for (int i = 0; i < dialogs.Length; i++)
            {
                RectTransform rect = dialogs[i].transform as RectTransform;
                if (rect == null || rect == root) continue;
                entries.Add(new Entry { Rect = rect, Canvas = root, Owner = canvas,
                    Group = dialogs[i].GetComponent<CanvasGroup>() });
            }
        }
        private static bool Visible(Entry entry)
        {
            return entry.Rect != null && entry.Canvas != null && entry.Owner != null && entry.Owner.enabled &&
                entry.Rect.gameObject.activeInHierarchy && entry.Rect.IsChildOf(entry.Canvas) &&
                (entry.Group == null || !entry.Group.enabled || entry.Group.alpha > 0.001f);
        }
        internal bool HasVisibleDialog
        {
            get
            {
                for (int i = 0; i < entries.Count; i++) if (Visible(entries[i])) return true;
                return false;
            }
        }
        internal void Prepare()
        {
            for (int i = 0; i < entries.Count; i++)
            {
                Entry entry = entries[i];
                if (entry.Applied || !Visible(entry)) continue;
                Transform parent = entry.Rect.parent;
                if (parent == null) continue;
                // Center the actual rectangle, not its pivot/anchors or actor.
                // Works through nested/scaled parents and noncentral pivots.
                Vector3 offset = parent.InverseTransformVector(
                    entry.Canvas.TransformPoint(entry.Canvas.rect.center) -
                    entry.Rect.TransformPoint(entry.Rect.rect.center));
                if (!Finite(offset.x) || !Finite(offset.y) || !Finite(offset.z)) continue;
                entry.Position = entry.Rect.anchoredPosition3D;
                entry.Applied = true;
                entries[i] = entry; // Save before a possible Unity setter error.
                entry.Rect.anchoredPosition3D = entry.Position + offset;
            }
        }
        private static bool Finite(float value) { return !float.IsNaN(value) && !float.IsInfinity(value); }
        internal void Restore()
        {
            for (int i = 0; i < entries.Count; i++)
            {
                Entry entry = entries[i];
                if (!entry.Applied) continue;
                if (entry.Rect != null) entry.Rect.anchoredPosition3D = entry.Position;
                entry.Applied = false; entries[i] = entry;
            }
        }
        internal void Clear() { BeginScan(); }
    }
}
