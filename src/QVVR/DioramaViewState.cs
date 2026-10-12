namespace QVVR
{
    // A game-following anchor, NOT a head-following camera. Source camera pose
    // is sampled only on entry/recenter; subsequent game rotations are ignored.
    internal sealed class DioramaViewState
    {
        private float cameraX, cameraY, cameraZ;
        internal bool Valid { get; private set; }
        internal float RotationX, RotationY, RotationZ, RotationW;
        internal float PositionX, PositionY, PositionZ;

        internal void Latch(float x, float y, float z, float cx, float cy, float cz,
            float qx, float qy, float qz, float qw)
        {
            cameraX = cx - x; cameraY = cy - y; cameraZ = cz - z;
            RotationX = qx; RotationY = qy; RotationZ = qz; RotationW = qw;
            Valid = true;
        }

        internal void Update(float x, float y, float z, float scale, float ox, float oy, float oz)
        {
            PositionX = x + cameraX * scale + ox;
            PositionY = y + cameraY * scale + oy;
            PositionZ = z + cameraZ * scale + oz;
        }

        internal void Reset() { Valid = false; }
    }
}
