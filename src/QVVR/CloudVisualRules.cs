using System;

namespace QVVR
{
    internal static class CloudVisualRules
    {
        // Exact signatures from QV scene metadata, not a broad "cloud" match.
        // Cloud save UI and SummonsCloud/RainCloud gameplay must survive.
        internal static bool Hide(string objectName, string materialName, string shaderName)
        {
            if (string.Equals(shaderName, "Hidden/ScreenSpaceCloudShadow", StringComparison.Ordinal)) return true;
            return Named(objectName, "Clouds") && Named(materialName, "Cloud") &&
                string.Equals(shaderName, "ERB/Particles/Add_CenterGlow", StringComparison.Ordinal);
        }

        private static bool Named(string value, string expected)
        {
            if (string.Equals(value, expected, StringComparison.OrdinalIgnoreCase)) return true;
            if (value == null || value.Length < expected.Length) return false;
            return string.Compare(value, 0, expected, 0, expected.Length, StringComparison.OrdinalIgnoreCase) == 0 &&
                ((value.Length == expected.Length + 7 && value.EndsWith("(Clone)", StringComparison.Ordinal)) ||
                 (value.Length == expected.Length + 11 && value.EndsWith(" (Instance)", StringComparison.Ordinal)));
        }
    }
}
