using System;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace QVVR
{
    internal static class CameraSelector
    {
        private static Camera[] cameraCache = new Camera[16];
        internal static Camera FindBestCamera()
        {
            Camera main = Camera.main;
            if (IsUsable(main))
                return main;

            int needed = Camera.allCamerasCount;
            if (cameraCache.Length < needed) cameraCache = new Camera[needed + 8];
            int count = Camera.GetAllCameras(cameraCache);
            Camera[] cameras = cameraCache;
            Camera best = null;
            float bestScore = float.MinValue;

            for (int index = 0; index < count; index++)
            {
                Camera camera = cameras[index];
                if (!IsUsable(camera))
                    continue;

                float score = Score(camera);
                if (score > bestScore)
                {
                    best = camera;
                    bestScore = score;
                }
            }

            return best;
        }

        internal static bool IsGameplayScene()
        {
            return IsGameplayScene(SceneManager.GetActiveScene().name);
        }

        internal static bool IsGameplayScene(string sceneName)
        {
            return sceneName != null &&
                sceneName.Length >= 3 &&
                sceneName[0] >= '1' &&
                sceneName[0] <= '6' &&
                sceneName[1] == '_';
        }

        internal static string PathOf(Transform transform)
        {
            if (transform == null)
                return "<null>";

            string path = transform.name;
            while (transform.parent != null)
            {
                transform = transform.parent;
                path = transform.name + "/" + path;
            }

            return path;
        }

        private static bool IsUsable(Camera camera)
        {
            return camera != null &&
                camera.gameObject.activeInHierarchy &&
                camera.targetTexture == null &&
                !camera.name.StartsWith("QVVR_", StringComparison.Ordinal);
        }

        private static float Score(Camera camera)
        {
            float score = camera.depth;
            string name = camera.name ?? string.Empty;

            if (camera.enabled)
                score += 200f;
            if (camera.CompareTag("MainCamera"))
                score += 1000f;
            if (name.IndexOf("main", StringComparison.OrdinalIgnoreCase) >= 0)
                score += 150f;
            if (name.IndexOf("cinemachine", StringComparison.OrdinalIgnoreCase) >= 0)
                score += 100f;
            if (name.IndexOf("ui", StringComparison.OrdinalIgnoreCase) >= 0)
                score -= 500f;
            if (camera.orthographic)
                score -= 250f;
            if (camera.cullingMask == 0)
                score -= 1000f;

            return score;
        }
    }
}
