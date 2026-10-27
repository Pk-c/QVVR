# Release preparation: 0.1.0 experimental candidate

This document prepares a release; it does not authorize a push, tag, GitHub
release, deployment, game launch or game termination. No stable 72 Hz claim.

## Local candidate

Use PowerShell 7 and the ignored dependencies from the README. Obtain pinned
release license/source inputs once, then build offline:

```powershell
.\tools\setup-release-deps.ps1
.\tools\build.ps1
.\tools\test-package.ps1
.\tools\check-publication.ps1 -Mode WorkingTree
git diff --check
```

The normal package build validates pinned license inputs offline, then copies
only the exact inventory in `tools/package-layout.ps1`. No recursive loader-tree
copy, game files, custom device config, logs, shader dumps, symbols or SDKs.
Mono.Cecil.Pdb.dll is a runtime library, not a .pdb debug-symbol file.
Unmodified Unity Doorstop source is included alongside its full license.
Release managed builds omit debug symbols. Full third-party license texts are
retained; dependency binaries/source ZIPs stay outside Git history.

Artifacts under ignored `build/release/`:

- `QVVR-v0.1.0.zip`: the single release archive.
  - `PC/`: game overlay; copy its contents directly beside QV.exe.
  - `SteamFrame/`: QVVR-Frame-Setup .bat/.ps1/.txt USB installer (uploads `PC/`).
  - `README.txt`: short PC/Frame installation guide.
- `QVVR-v0.1.0.zip.sha256`: download integrity checksum, not a signature.
- `PC/qvvr-files.sha256` inside the archive: every other overlay file's hash.
- `PC/qvvr-package.json` inside the archive: version, architecture, source HEAD,
  dirty-source flag and candidate status; no private local paths or identity.
- `PC/RELEASE-NOTES.txt` inside the archive: English notes ready for review.

Packaging audits exact ZIP paths (including dotfiles), duplicate/case collisions,
path traversal, payload/input checksums, runtime version, ownership marker,
clean fresh-install configuration and checksums. A dirty candidate is not an
exact tagged source build; rebuild from the chosen clean commit before publishing.

## Automated verification

The Frame USB installer ships in the same ZIP under `SteamFrame/`, outside the
game overlay; it rebuilds and validates the exact overlay from `PC/` before upload.
`PC/` includes uninstall.bat/uninstall.ps1 for local PC removal. The Frame tools
bundle unmodified official ADB (Android SDK Platform Tools r37.0.1: adb.exe,
AdbWinApi.dll, AdbWinUsbApi.dll, NOTICE.txt) under `SteamFrame/platform-tools/`,
pinned by SHA-256 in `tools/setup-release-deps.ps1`; it is never uploaded.
Run installer fixtures on Windows PowerShell 5.1 and PowerShell 7, including the
Git Bash POSIX fixture. Device USB acceptance (install/update/remove/reinstall,
custom config preservation, backups, game-open refusal and disconnect recovery)
is still pending; scripts never auto-launch/terminate QV. Steam launch options are
only changed through the running Steam client API, never by editing localconfig.vdf.

Run all `tools/test-*.ps1` suites from individual PowerShell processes after the
canonical build. See testing.md. In particular include controller, menu,
dialogue, level-entry, first-level/sector cinema, render/allocation/performance,
native load/pose/pacing, fake-runtime OpenXR and synthetic WARP shader/cap tests.
These do not substitute for physical-headset checks or prove absence of secrets.
Only audit public working-tree text; never stage dependencies or diagnostics.

## Required Frame acceptance before publication

- Deploy the exact candidate only after QV is confirmed closed; user launches it.
- Verify the compact 15-row menu, navigation/actions, persistence, restored
  defaults and unchanged gesture/stick controls. Preserve existing user config.
- Enter/retry several levels: shorter ordinary transition, one dialogue trigger,
  normal movement/tutorial/save state. Genuine first-level and sector movies
  remain flat and retain skip/natural-completion behavior.
- Retest A while holding locomotion, modal transitions and missed release polling.
- Compare water foam workaround on/off from above/side; do not call it solved
  without this test. Check ink, transparent effects and both eyes.
- Check caps, feathered cylinder, passthrough and black/green opaque fallback.
- Toggle cylindrical diorama Off/On with OpenVR and exclusive OpenXR. Off must
  show the full level at normal scale, no cylinder/caps/culling; head translation
  and IPD stay 1:1. Right stick turns about the head and moves forward/back along
  upright heading; left stick remains viewer-relative Q movement. Check player
  follow, recenter, camera reset, room-scale walking, menu/cinema transitions and
  preserved diorama size/placement when switching back. Record whole-level CPU/GPU
  timings separately; this camera has no collision handling. Gate remains pending.
- Record CPU/GPU frame times at 72 Hz in a representative level and heavy menu;
  keep raw logs/device config private. Scene-dependent stutter remains a limit.
- Test no-runtime/F8 desktop recovery and removal without touching original game
  files or other mods. Other PCVR controller presets still need hardware testing.

Do not mark these gates passed based on an earlier build or offline fixtures.

## Pending PCVR acceptance

Quest 3 + Virtual Desktop is planned for a later manual test by the maintainer;
Steam Link must be tested separately. Use the Windows game with -force-d3d11,
SteamVR/OpenVR, passthrough disabled and normalized FaceButtons controls. Direct
VDXR and third-party OpenVR-to-OpenXR wrappers are outside this candidate's test
scope. The OpenVR cadence fix removes the fixed 72 Hz prediction assumption;
test-openvr-timing.ps1 and both input backend fixtures cover it offline, not on
a physical streaming headset. See testing.md for the full acceptance checklist.

## Publication, only after explicit approval

1. Review English release notes, notices and public diff; confirm version/title
   and experimental/pre-release status with the maintainer.
2. Stage an explicit reviewed file list. Run the default staged publication audit
   and inspect the staged diff. Do not stage the entire workspace blindly.
3. Commit using the maintainer's chosen non-personal identity. Do not rewrite
   existing history. No automation here creates a commit, tag or public release.
4. Rebuild the exact clean source revision, rerun tests/audits and archive the
   matching headset results. Revalidate any changed binary on the Frame.
5. If authorized, publish the reviewed ZIP/checksum as release assets, not Git
   source files. Attach the English notes and clearly list known limits.

Updates: back up the overlay and preserve `BepInEx/config/dev.qvvr.prototype.cfg`.
Fresh templates have unsaved placement and passthrough disabled; never distribute
the maintainer's whole headset configuration. Shared BepInEx installations require
review before replacing core/loader files. On SteamOS remove only QVVR's plugin
directory/config manually; the Windows helper preserves shared loader files.
