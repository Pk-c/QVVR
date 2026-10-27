using System;
using System.Globalization;
using BepInEx.Configuration;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;

namespace QVVR
{
    internal sealed class VrSettingsMenu
    {
        private enum Item
        {
            ViewTilt, RenderScale, Msaa, Recenter, RestoreDefaults, CylindricalDiorama, Radius, Height, CenterHeight,
            VoidColor, Passthrough, EdgeFade, Clouds, PlaceInFront, Size, Count
        }
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
                rect.sizeDelta = new Vector2(960f, 940f);
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
                CreateText("Title", font, layer, 370f, 50).text = "QVVR - SETTINGS";
                rows = new Text[(int)Item.Count];
                for (int index = 0; index < rows.Length; index++)
                    rows[index] = CreateText("Row" + index, font, layer, 290f - index * 40f, 32);
                Text footer = CreateText("Help", font, layer, -382f, 25);
                footer.text = "Up/down: select   Left/right: adjust\nA: action   B or both sticks: close and save\nDiorama: both grips; full VR: right stick camera\nRender scale and MSAA: next launch; game not paused";
                RefreshText();
                root.SetActive(false);
                Plugin.Trace("QVVR world-anchored settings menu ready: click both sticks to toggle.");
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
            Plugin.Trace("QVVR comfort settings saved.");
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
                switch ((Item)selected)
                {
                    case Item.Recenter: renderer.Recenter(); break;
                    case Item.PlaceInFront: renderer.PlaceInFront(); anchorNeeded = true; break;
                    case Item.RestoreDefaults: ResetDefaults(); break;
                    case Item.CylindricalDiorama: case Item.VoidColor: case Item.Passthrough: case Item.Clouds: Adjust(1f); break;
                }
                RefreshText();
            }
        }

        private void Adjust(float sign)
        {
            switch ((Item)selected)
            {
                case Item.ViewTilt: plugin.ViewPitchDegrees.Value = ComfortMath.ClampPitch(plugin.ViewPitchDegrees.Value + sign * 2f); anchorNeeded = true; break;
                case Item.RenderScale:
                {
                    // Steps the scale actually rendered. The OpenXR stability cap
                    // follows it, so the chosen value is never silently capped.
                    float scale = RenderBudget.NextRenderScale(EffectiveRenderScale(), sign);
                    plugin.EyeTextureResolutionScale.Value = scale;
                    if (plugin.XrResolutionCap.Value > 0f) plugin.XrResolutionCap.Value = scale;
                    break;
                }
                case Item.Msaa: plugin.EyeMsaaSamples.Value = RenderBudget.NextMsaa(plugin.EyeMsaaSamples.Value, sign); break;
                case Item.CylindricalDiorama: plugin.DioramaEnabled.Value = !plugin.DioramaEnabled.Value; anchorNeeded = true; break;
                case Item.Radius: plugin.DioramaRadius.Value = Mathf.Clamp(plugin.DioramaRadius.Value + sign, 0.5f, 200f); break;
                case Item.Height: plugin.DioramaHeight.Value = Mathf.Clamp(plugin.DioramaHeight.Value + sign, 0.5f, 200f); break;
                case Item.CenterHeight: plugin.DioramaCenterHeight.Value = Mathf.Clamp(plugin.DioramaCenterHeight.Value + sign * 0.5f, -200f, 200f); break;
                case Item.VoidColor: plugin.VoidBackground.Value = DioramaMath.GreenBackground(plugin.VoidBackground.Value) ? 0 : 1; break;
                case Item.Passthrough: plugin.PassthroughEnabled.Value = !plugin.PassthroughEnabled.Value; break;
                case Item.EdgeFade: plugin.DioramaFeatherWidth.Value = Mathf.Clamp(plugin.DioramaFeatherWidth.Value + sign * 0.05f, 0f, 5f); break;
                case Item.Clouds: plugin.HideDecorativeClouds.Value = !plugin.HideDecorativeClouds.Value; break;
                case Item.PlaceInFront: renderer.PlaceInFront(); anchorNeeded = true; break;
                case Item.Size: plugin.DioramaWorldScale.Value = DioramaScaleState.Clamp(plugin.DioramaWorldScale.Value * (sign > 0f ? 1.25f : 0.8f)); break;
            }
        }

        private void ResetDefaults()
        {
            renderer.Recenter();
            Reset(plugin.CameraDistanceScale);
            Reset(plugin.WorldUnitsPerMeter);
            Reset(plugin.ViewPitchDegrees);
            Reset(plugin.PanelWidth);
            Reset(plugin.PanelDistance);
            Reset(plugin.PanelFollowLag);
            Reset(plugin.GameplayHudScale);
            Reset(plugin.GameplayHudDistance);
            Reset(plugin.HubPauseDistance);
            Reset(plugin.XrResolutionCap);
            Reset(plugin.GameplayHudInset);
            Reset(plugin.RightGripTranslationGain);
            Reset(plugin.DioramaWorldScale);
            Reset(plugin.DioramaMoveSensitivity);
            Reset(plugin.DioramaRotationSensitivity);
            Reset(plugin.DioramaEnabled);
            Reset(plugin.BlackCutSurfaces);
            Reset(plugin.StereoSelectionMenus);
            anchorNeeded = true;
        }

        // Exclusive OpenXR (passthrough path) applies the stability cap.
        private float EffectiveRenderScale()
        {
            return RenderBudget.SceneScale(plugin.EyeTextureResolutionScale.Value, plugin.PassthroughEnabled.Value, plugin.XrResolutionCap.Value);
        }

        // Use the same shipped defaults as Config.Bind, including config-only
        // settings. Never replace a user's saved values merely by opening a menu.
        private static void Reset<T>(ConfigEntry<T> entry) { entry.Value = (T)entry.DefaultValue; }

        // Text strings/meshes change only on menu events, never on each render.
        private void RefreshText()
        {
            rows[(int)Item.ViewTilt].text = "View tilt: " + Format(plugin.ViewPitchDegrees.Value) + " deg (+ = downward)";
            rows[(int)Item.RenderScale].text = "Render scale: " + Format(EffectiveRenderScale()) + " (restart)";
            int samples = RenderBudget.MsaaSamples(plugin.EyeMsaaSamples.Value);
            rows[(int)Item.Msaa].text = "Anti-aliasing (MSAA): " + (samples > 1 ? samples + "x" : "Off") + " (restart)";
            rows[(int)Item.Recenter].text = "Recenter view (A)";
            rows[(int)Item.RestoreDefaults].text = "Restore comfort defaults (A)";
            rows[(int)Item.CylindricalDiorama].text = "Cylindrical diorama: " + (plugin.DioramaEnabled.Value ? "On" : "Off - full-scale VR");
            rows[(int)Item.Radius].text = "Diorama radius: " + Format(plugin.DioramaRadius.Value) + " units";
            rows[(int)Item.Height].text = "Diorama height: " + Format(plugin.DioramaHeight.Value) + " units";
            rows[(int)Item.CenterHeight].text = "Center height: " + Format(plugin.DioramaCenterHeight.Value) + " units";
            rows[(int)Item.VoidColor].text = "Void color: " + (DioramaMath.GreenBackground(plugin.VoidBackground.Value) ? "Green" : "Black");
            rows[(int)Item.Passthrough].text = "OpenXR passthrough: " + (plugin.PassthroughEnabled.Value ? "On" : "Off") + " (restart)";
            rows[(int)Item.EdgeFade].text = "Cylinder edge fade: " + Format(plugin.DioramaFeatherWidth.Value) + " units";
            rows[(int)Item.Clouds].text = "Decorative clouds: " + (plugin.HideDecorativeClouds.Value ? "Hidden" : "Visible");
            rows[(int)Item.PlaceInFront].text = plugin.DioramaEnabled.Value ? "Place diorama in front of me (A)" : "Reset camera behind Q (A)";
            rows[(int)Item.Size].text = "Diorama size: " + plugin.DioramaWorldScale.Value.ToString("0.000", CultureInfo.InvariantCulture) + " x";
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
