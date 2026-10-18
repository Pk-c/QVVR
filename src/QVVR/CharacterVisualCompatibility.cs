using System.Collections.Generic;
using UnityEngine;

namespace QVVR
{
    // Only the current player's hierarchy. Unity's manual eye cameras are not
    // reliable animation-culling witnesses: keep Q's animation and skinning
    // current so DynamicBone never integrates against stale animated bones.
    // Discovery/cache allocation occurs in cold maintenance, never per eye.
    internal sealed class CharacterVisualCompatibility
    {
        private struct AnimatorState
        {
            internal Animator Animator;
            internal AnimatorCullingMode Original;
            internal int Scan;
        }
        private struct SkinState
        {
            internal SkinnedMeshRenderer Renderer;
            internal bool Original;
            internal int Scan;
        }
        private readonly List<AnimatorState> animators = new List<AnimatorState>(4);
        private readonly List<SkinState> skins = new List<SkinState>(24);
        private readonly List<Animator> foundAnimators = new List<Animator>(4);
        private readonly List<SkinnedMeshRenderer> foundSkins = new List<SkinnedMeshRenderer>(24);
        private Transform target;
        private int scan;

        internal void Refresh(Transform player)
        {
            if (player != target) { Clear(); target = player; }
            if (player == null) { Clear(); return; }
            scan++;
            foundAnimators.Clear();
            player.GetComponentsInChildren<Animator>(true, foundAnimators);
            for (int index = 0; index < foundAnimators.Count; index++)
            {
                Animator animator = foundAnimators[index];
                if (animator == null) continue;
                int entry = 0;
                while (entry < animators.Count && animators[entry].Animator != animator) entry++;
                AnimatorState state;
                if (entry == animators.Count)
                {
                    state = new AnimatorState { Animator = animator, Original = animator.cullingMode };
                    animators.Add(state);
                }
                else state = animators[entry];
                if (animator.cullingMode != AnimatorCullingMode.AlwaysAnimate) state.Original = animator.cullingMode;
                state.Scan = scan; animators[entry] = state;
                if (animator.cullingMode != AnimatorCullingMode.AlwaysAnimate) animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;
            }
            foundSkins.Clear();
            player.GetComponentsInChildren<SkinnedMeshRenderer>(true, foundSkins);
            for (int index = 0; index < foundSkins.Count; index++)
            {
                SkinnedMeshRenderer renderer = foundSkins[index];
                if (renderer == null) continue;
                int entry = 0;
                while (entry < skins.Count && skins[entry].Renderer != renderer) entry++;
                SkinState state;
                if (entry == skins.Count)
                {
                    state = new SkinState { Renderer = renderer, Original = renderer.updateWhenOffscreen };
                    skins.Add(state);
                }
                else state = skins[entry];
                if (!renderer.updateWhenOffscreen) state.Original = false;
                state.Scan = scan; skins[entry] = state;
                if (!renderer.updateWhenOffscreen) renderer.updateWhenOffscreen = true;
            }
            // Reparented/replaced models must not keep our override elsewhere.
            for (int index = animators.Count - 1; index >= 0; index--)
            {
                AnimatorState state = animators[index];
                if (state.Scan == scan && state.Animator != null) continue;
                if (state.Animator != null) state.Animator.cullingMode = state.Original;
                animators.RemoveAt(index);
            }
            for (int index = skins.Count - 1; index >= 0; index--)
            {
                SkinState state = skins[index];
                if (state.Scan == scan && state.Renderer != null) continue;
                if (state.Renderer != null) state.Renderer.updateWhenOffscreen = state.Original;
                skins.RemoveAt(index);
            }
        }

        internal void Clear()
        {
            for (int index = 0; index < animators.Count; index++)
                if (animators[index].Animator != null) animators[index].Animator.cullingMode = animators[index].Original;
            for (int index = 0; index < skins.Count; index++)
                if (skins[index].Renderer != null) skins[index].Renderer.updateWhenOffscreen = skins[index].Original;
            animators.Clear(); skins.Clear(); foundAnimators.Clear(); foundSkins.Clear(); target = null; scan = 0;
        }
    }
}
