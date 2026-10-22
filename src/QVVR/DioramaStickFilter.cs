using System;
using UnityEngine;

namespace QVVR
{
    // Placement only: menu navigation and character locomotion are unchanged.
    internal sealed class DioramaStickFilter
    {
        private int axis;
        internal void Reset() { axis = 0; }
        internal Vector2 Update(float x, float y, float deadZone)
        {
            x = Finite(x) ? Math.Max(-1f, Math.Min(1f, x)) : 0f;
            y = Finite(y) ? Math.Max(-1f, Math.Min(1f, y)) : 0f;
            float dead = Finite(deadZone) ? Math.Max(0.1f, Math.Min(0.8f, deadZone)) : 0.4f;
            float ax = Math.Abs(x), ay = Math.Abs(y);
            if (Math.Max(ax, ay) <= dead) { Reset(); return new Vector2(0f, 0f); }
            if (axis == 0) axis = ax >= ay ? 1 : 2;
            // Require a deliberate change of direction to switch axes. A small
            // diagonal component during a turn must not translate the world.
            if (axis == 1 && ay > ax * 1.35f && ay > dead + 0.1f) axis = 2;
            else if (axis == 2 && ax > ay * 1.35f && ax > dead + 0.1f) axis = 1;
            float value = axis == 1 ? x : y;
            float amount = Math.Max(0f, (Math.Abs(value) - dead) / (1f - dead));
            if (value < 0f) amount = -amount;
            return axis == 1 ? new Vector2(amount, 0f) : new Vector2(0f, amount);
        }
        private static bool Finite(float value) { return !float.IsNaN(value) && !float.IsInfinity(value); }
    }
}
