using System;
using System.Globalization;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;

namespace QVVR
{
    internal sealed class VrSettingsMenu
    {
        private Plugin plugin;
        private OpenVrRenderer renderer;
        private GameObject root;
        private Material backgroundMaterial;
        private Material fontMaterial;
        private Text[] rows;
        private int selected;
        private bool anchorNeeded;
        private Vector3 trackingAnchorPosition;
        private Quaternion trackingAnchorRotation;
        private int lastDirection;
        private float nextRepeat;

        internal bool Visible { get { return root != null && root.activeSelf; } }

        internal void Initialize(Plugin owner, OpenVrRenderer vrRenderer, Transform parent, int layer, Shader panelShader)
        {
            plugin = owner;
            renderer = vrRenderer;
            try
            {
                Font font = Resources.GetBuiltinResource<Font>("Arial.ttf");
                if (font == null) throw new InvalidOperationException("Built-in menu font is unavailable.");
                fontMaterial = new Material(font.material);
                if (!fontMaterial.shader.isSupported) fontMaterial.shader = panelShader;
                fontMaterial.renderQueue = 4000;
                fontMaterial.SetInt("unity_GUIZTestMode", (int)CompareFunction.Always);
                fontMaterial.SetInt("_ZTest", (int)CompareFunction.Always);
                root = new GameObject("QVVR_Settings", typeof(RectTransform), typeof(Canvas));
                root.layer = layer;
                root.transform.SetParent(parent, false);
                RectTransform rect = (RectTransform)root.transform;
                rect.sizeDelta = new Vector2(960f, 1300f);
                Canvas canvas = root.GetComponent<Canvas>();
                canvas.renderMode = RenderMode.WorldSpace;
                canvas.sortingOrder = 4000;
                backgroundMaterial = new Material(panelShader);
                backgroundMaterial.renderQueue = 3990;
                backgroundMaterial.SetInt("unity_GUIZTestMode", (int)CompareFunction.Always);
                backgroundMaterial.SetInt("_ZTest", (int)CompareFunction.Always);
                GameObject background = Child("Background", layer);
                RectTransform bgRect = (RectTransform)background.transform;
                bgRect.sizeDelta = rect.sizeDelta;
                Image image = background.AddComponent<Image>();
                image.material = backgroundMaterial;
                image.color = new Color(0.035f, 0.05f, 0.09f, 0.96f);
                image.raycastTarget = false;
                CreateText("Title", font, layer, 610f, 50).text = "QVVR - SETTINGS";
                rows = new Text[22];
                for (int index = 0; index < rows.Length; index++)
                    rows[index] = CreateText("Row" + index, font, layer, 530f - index * 44f, 32);
                Text footer = CreateText("Help", font, layer, -520f, 25);
                footer.text = "Up/down: select   Left/right: adjust\nA: action   B or both sticks: close and save\nBoth grips: move / resize / rotate\nRender profile: next launch; game not paused";
                RefreshText();
                root.SetActive(false);
                Plugin.Log.LogInfo("QVVR world-anchored settings menu ready: click both sticks to toggle.");
            }
            catch (Exception exception)
            {
                Release();
                Plugin.Log.LogWarning("QVVR settings menu unavailable; game input preserved: " + exception);
            }
        }

        private GameObject Child(string name, int layer)
        {
            GameObject child = new GameObject(name, typeof(RectTransform));
            child.layer = layer;
            child.transform.SetParent(root.transform, false);
            return child;
        }

        private Text CreateText(string name, Font font, int layer, float y, int size)
        {
            GameObject child = Child(name, layer);
            RectTransform rect = (RectTransform)child.transform;
            rect.anchoredPosition = new Vector2(0f, y);
            rect.sizeDelta = new Vector2(890f, name == "Help" ? 130f : 55f);
            Text text = child.AddComponent<Text>();
            text.font = font;
            text.material = fontMaterial;
            text.fontSize = size;
            text.alignment = TextAnchor.MiddleLeft;
            text.horizontalOverflow = HorizontalWrapMode.Overflow;
            text.verticalOverflow = VerticalWrapMode.Overflow;
            text.raycastTarget = false;
            return text;
        }

        internal void Toggle()
        {
            if (root == null) return;
            if (Visible) { Close(); return; }
            renderer.CommitWorldGrabSettings(true);
            anchorNeeded = true;
            lastDirection = 0;
            RefreshText();
            root.SetActive(true);
        }

        internal void Close()
        {
            if (!Visible) return;
            root.SetActive(false);
            plugin.Config.Save();
            Plugin.Log.LogInfo("QVVR comfort settings saved.");
        }

        internal void ResetAnchor() { anchorNeeded = true; }

        // Remain world-anchored while open, rather than chasing head rotation.
        internal void UpdatePose(Vector3 headPosition, Quaternion headRotation, float units,
            Vector3 rigPosition, Quaternion rigRotation, Matrix4x4 trackingToCalibrated)
        {
            if (!Visible) return;
            if (anchorNeeded)
            {
                trackingAnchorPosition = headPosition + headRotation * Vector3.forward * 2.5f;
                trackingAnchorRotation = headRotation;
                anchorNeeded = false;
            }
            // Keep the menu anchored in physical space even if game-follow,
            // size, placement or tilt change the game's inverse view transform.
            root.transform.position = rigPosition + rigRotation * trackingToCalibrated.MultiplyPoint3x4(trackingAnchorPosition) * units;
            root.transform.rotation = rigRotation * trackingToCalibrated.rotation * trackingAnchorRotation;
            root.transform.localScale = Vector3.one * (2.1f * units / 960f);
        }

        internal void HandleInput(float x, float y, bool confirmDown, bool backDown)
        {
            if (!Visible) return;
            if (backDown) { Close(); return; }
            int direction = 0;
            if (Mathf.Abs(y) > 0.55f && Mathf.Abs(y) >= Mathf.Abs(x)) direction = y > 0f ? 1 : 2;
            else if (Mathf.Abs(x) > 0.55f) direction = x > 0f ? 3 : 4;
            if (direction != 0 && (direction != lastDirection || Time.unscaledTime >= nextRepeat))
            {
                nextRepeat = Time.unscaledTime + (direction != lastDirection ? 0.4f : 0.15f);
                if (direction <= 2) selected = (selected + (direction == 1 ? rows.Length - 1 : 1)) % rows.Length;
                else Adjust(direction == 3 ? 1f : -1f);
                RefreshText();
            }
            lastDirection = direction;
            if (confirmDown)
            {
                if (selected == 7) renderer.Recenter();
                else if (selected == 20) renderer.PlaceInFront();
                else if (selected == 8) ResetDefaults();
                else if (selected == 13 || selected == 14 || selected == 19) Adjust(1f);
                RefreshText();
            }
        }

        private void Adjust(float sign)
        {
            switch (selected)
            {
                case 0: renderer.AdjustPlacementDistance(sign * 0.1f); anchorNeeded = true; break;
                case 1: plugin.WorldUnitsPerMeter.Value = Mathf.Clamp(plugin.WorldUnitsPerMeter.Value + sign * 0.25f, 0.25f, 10f); anchorNeeded = true; break;
                case 2: plugin.ViewPitchDegrees.Value = ComfortMath.ClampPitch(plugin.ViewPitchDegrees.Value + sign * 2f); anchorNeeded = true; break;
                case 3: plugin.PanelWidth.Value = Mathf.Clamp(plugin.PanelWidth.Value + sign * 0.1f, 1f, 4f); break;
                case 4: plugin.PanelDistance.Value = Mathf.Clamp(plugin.PanelDistance.Value + sign * 0.1f, 1.5f, 5f); break;
                case 5: plugin.PanelFollowLag.Value = Mathf.Clamp(plugin.PanelFollowLag.Value + sign * 0.05f, 0f, 1.5f); break;
                case 6: plugin.SelectQualityPreset(plugin.QualityPreset.Value + (sign > 0f ? 1 : -1)); break;
                case 9: plugin.DioramaEnabled.Value = !plugin.DioramaEnabled.Value; break;
                case 10: plugin.DioramaRadius.Value = Mathf.Clamp(plugin.DioramaRadius.Value + sign, 0.5f, 200f); break;
                case 11: plugin.DioramaHeight.Value = Mathf.Clamp(plugin.DioramaHeight.Value + sign, 0.5f, 200f); break;
                case 12: plugin.DioramaCenterHeight.Value = Mathf.Clamp(plugin.DioramaCenterHeight.Value + sign * 0.5f, -200f, 200f); break;
                case 13: plugin.VoidBackground.Value = DioramaMath.GreenBackground(plugin.VoidBackground.Value) ? 0 : 1; break;
                case 14: plugin.PassthroughEnabled.Value = !plugin.PassthroughEnabled.Value; break;
                case 15: renderer.SetCylinderProbe((renderer.CylinderProbeMode + (sign > 0f ? 1 : 3)) % 4); break;
                case 16: plugin.DioramaFeatherWidth.Value = Mathf.Clamp(plugin.DioramaFeatherWidth.Value + sign * 0.05f, 0f, 5f); break;
                case 17: plugin.GameplayHudScale.Value = DioramaMath.HudScale(plugin.GameplayHudScale.Value + sign * 0.1f); break;
                case 18: plugin.GameplayHudDistance.Value = Mathf.Clamp(plugin.GameplayHudDistance.Value + sign * 0.1f, 1f, 5f); break;
                case 19: plugin.HideDecorativeClouds.Value = !plugin.HideDecorativeClouds.Value; break;
                case 20: renderer.PlaceInFront(); anchorNeeded = true; break;
                case 21: plugin.DioramaWorldScale.Value = DioramaScaleState.Clamp(plugin.DioramaWorldScale.Value * (sign > 0f ? 1.25f : 0.8f)); break;
            }
        }

        private void ResetDefaults()
        {
            renderer.Recenter();
            plugin.CameraDistanceScale.Value = 0.4f;
            plugin.WorldUnitsPerMeter.Value = 1f;
            plugin.ViewPitchDegrees.Value = 0f;
            plugin.PanelWidth.Value = 2.4f;
            plugin.PanelDistance.Value = 2.8f;
            plugin.PanelFollowLag.Value = 0.35f;
            plugin.GameplayHudScale.Value = 2f;
            plugin.GameplayHudDistance.Value = 2.8f;
            plugin.RightGripTranslationGain.Value = 20f;
            plugin.DioramaWorldScale.Value = 1f;
            anchorNeeded = true;
        }

        // Text strings/meshes change only on menu events, never on each render.
        private void RefreshText()
        {
            rows[0].text = "Diorama distance: " + Format(renderer.PlacementDistance) + " m";
            rows[1].text = "World units: " + Format(plugin.WorldUnitsPerMeter.Value) + " units / meter";
            rows[2].text = "View tilt: " + Format(plugin.ViewPitchDegrees.Value) + " deg (+ = downward)";
            rows[3].text = "Panel width: " + Format(plugin.PanelWidth.Value) + " m";
            rows[4].text = "Panel distance: " + Format(plugin.PanelDistance.Value) + " m";
            rows[5].text = "Panel follow lag: " + Format(plugin.PanelFollowLag.Value) + " s";
            rows[6].text = "Render profile: " + (plugin.QualityPreset.Value == 0 ? "Performance" : plugin.QualityPreset.Value == 2 ? "Sharp" : "Balanced");
            rows[7].text = "Recenter view (A)";
            rows[8].text = "Restore comfort defaults (A)";
            rows[9].text = "Cylindrical diorama: " + (plugin.DioramaEnabled.Value ? "On" : "Off");
            rows[10].text = "Diorama radius: " + Format(plugin.DioramaRadius.Value) + " units";
            rows[11].text = "Diorama height: " + Format(plugin.DioramaHeight.Value) + " units";
            rows[12].text = "Center height: " + Format(plugin.DioramaCenterHeight.Value) + " units";
            rows[13].text = "Void color: " + (DioramaMath.GreenBackground(plugin.VoidBackground.Value) ? "Green" : "Black");
            rows[14].text = "OpenXR passthrough: " + (plugin.PassthroughEnabled.Value ? "On" : "Off") + " (restart)";
            rows[15].text = "Cylinder probe: " + renderer.CylinderProbeMode + " - " +
                (renderer.CylinderProbeMode == 1 ? "Unclipped passes" : renderer.CylinderProbeMode == 2 ? "Unlimited" :
                 renderer.CylinderProbeMode == 3 ? "Neutral matrix" : "Normal");
            rows[16].text = "Cylinder edge fade: " + Format(plugin.DioramaFeatherWidth.Value) + " units";
            rows[17].text = "Gameplay HUD size: " + Format(plugin.GameplayHudScale.Value) + " x";
            rows[18].text = "Gameplay HUD distance: " + Format(plugin.GameplayHudDistance.Value) + " m";
            rows[19].text = "Decorative clouds: " + (plugin.HideDecorativeClouds.Value ? "Hidden" : "Visible");
            rows[20].text = "Place diorama in front of me (A)";
            rows[21].text = "Diorama size: " + plugin.DioramaWorldScale.Value.ToString("0.000", CultureInfo.InvariantCulture) + " x";
            for (int index = 0; index < rows.Length; index++)
                rows[index].color = index == selected ? new Color(0.4f, 0.9f, 1f) : Color.white;
        }

        private static string Format(float value) { return value.ToString("0.00", CultureInfo.InvariantCulture); }

        internal void Release()
        {
            Close();
            if (root != null) UnityEngine.Object.Destroy(root);
            if (backgroundMaterial != null) UnityEngine.Object.Destroy(backgroundMaterial);
            if (fontMaterial != null) UnityEngine.Object.Destroy(fontMaterial);
            root = null;
            backgroundMaterial = null;
            fontMaterial = null;
        }
    }
}
