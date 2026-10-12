# QVVR project guidance

QVVR is an experimental, non-destructive VR mod for the Windows x64 Unity Mono build of QV running locally on Steam Frame through Proton and FEX.

## Priorities

1. Keep the hot render path allocation-free.
2. Never read eye textures back to the CPU.
3. Keep original game files untouched; deployment is an overlay that can be removed.
4. Preserve a desktop-safe fallback if SteamVR/OpenVR is unavailable.
5. Measure on the Frame before adding features.

## Deployment workflow

- Deployment is deploy-only: do not launch or relaunch QV automatically.
- The user starts QV manually; injection still starts with the game.
- Confirm QV is closed before replacing its mod overlay. Do not terminate it automatically.

## Build and dependencies

- Target `netstandard2.0` and C# 7.3 for compatibility with the shipped Unity Mono runtime.
- Do not commit game assemblies, BepInEx, OpenVR binaries, or generated packages.
- Compile against assemblies under `.deps/unity-reference` and BepInEx/OpenVR under `.deps`.
- `tools/build.ps1` is the canonical build entry point.

## Testing

- Run `tools/build.ps1` after code changes.
- For render-path changes, verify that no per-frame managed allocations were introduced.
- Frame testing targets 72 Hz and records both CPU and GPU frame times.
