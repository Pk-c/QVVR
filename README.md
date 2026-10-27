# QVVR

## What it does

QVVR is an experimental VR mod for the Windows version of **QV**. It plays the
game as a miniature diorama you can place, resize and walk around in your room,
on PC VR through SteamVR or on Steam Frame.

- Stereo 3D gameplay with head tracking.
- Diorama mode: the level is cut to a cylinder you move, scale and rotate with
  both grips. Can be turned off for full-size, room-scale VR.
- Passthrough on Steam Frame: the diorama sits in your real room.
- 3D hub, costume and map screens. Menus, HUD and dialogue are shown on readable
  panels that follow your view.
- In-headset settings menu (click both sticks).
- Original game files are never modified. Without a working VR runtime the game
  runs normally on the desktop.

This is an experimental release: expect rough edges and report issues.

## Installing

Download `QVVR-vX.Y.Z.zip` from the releases page and extract the whole ZIP. It
contains a `PC` folder (the mod files) and a `SteamFrame` folder (the USB
installer). Close QV before installing or updating.

### On PC

1. Copy the **contents** of the `PC` folder directly into the QV game folder,
   next to `QV.exe` (Steam > QV > Manage > Browse local files).
   When updating, keep your existing `BepInEx/config/dev.qvvr.prototype.cfg`.
2. Start SteamVR with your headset connected (Quest 3: Steam Link, or Virtual
   Desktop in SteamVR mode), then start QV.

If the game stays on the desktop and `BepInEx/LogOutput.log` says
`QVVR requires D3D11`, add `-force-d3d11` to Steam > QV > Properties > Launch
options.

### On Steam Frame

Nothing else needs to be installed: the installer runs on a Windows PC and
includes ADB.

1. On the Frame, enable Developer Mode / USB debugging and connect it to your PC
   with a USB cable. Keep Steam running on the Frame; to let the installer set
   the launch options, also enable CEF Remote Debugging in the developer settings.
2. Double-click `SteamFrame/Install-QVVR-on-Frame.bat`. The first time, put on
   the headset and accept the "Allow USB debugging" prompt.
3. The installer ends with a **SUCCESS** or **FAILED** screen that says what to
   do next. Your settings and other mods are kept, and replaced files are backed
   up in the game's `.qvvr-backups` folder. If it says the launch options still
   need setting, enter them in Steam > QV > Properties:

   ```text
   WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11
   ```

4. Start QV on the Frame.

## Uninstalling

Close QV first. Uninstalling moves QVVR into the game's `.qvvr-backups` folder,
so it can be restored. BepInEx, other mods and the game itself are left alone.

### On PC

Double-click `uninstall.bat` next to `QV.exe` and type `UNINSTALL` to confirm.
Settings are kept. To remove them too, run this from the game folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveConfig
```

### On Steam Frame

Connect the Frame by USB and double-click
`SteamFrame/Uninstall-QVVR-from-Frame.bat`. It ends with a **SUCCESS** or
**FAILED** screen. Settings are kept; to remove them too, run this from the
`SteamFrame` folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\QVVR-Frame-Setup.ps1 -Action Uninstall -RemoveConfig
```

Remove the QVVR launch options in Steam afterwards if you want.

## Controls

Bindings can be changed in the `[Input]` section of
`BepInEx/config/dev.qvvr.prototype.cfg` (edit it with QV closed).

### Quest 3

Through SteamVR, using the default `Layout=FaceButtons`.

| Action | Button |
| --- | --- |
| Move Q | Left stick |
| Rotate diorama / bring it closer or further | Right stick |
| Move, resize and rotate the diorama | Hold both grips and move your hands |
| Main game action / confirm | A |
| Secondary action / back | B |
| Pause | Y |
| Swap character | X |
| Dash (hold) | Right trigger |
| Game camera mode (hold) | Left trigger |
| Load | Both triggers |
| Previous / next menu page | Left / right trigger |
| QVVR settings menu | Click both sticks |

In the settings menu, up/down selects and left/right changes a value. With
diorama mode off, the right stick turns and moves the camera instead.

### Steam Frame

Same as Quest 3, except **Pause** is left D-pad up and **Swap character** is
left D-pad down.

On a PC keyboard: **F7** recenters the view and **F8** toggles VR on or off.

## Building

Requirements: Windows x64, PowerShell 7, the .NET SDK, Visual Studio C++ x64
Build Tools, and the Windows version of QV installed.

1. Download BepInEx **5.4.23.5** and OpenVR **2.15.6** from their official
   projects and extract them.
2. Set up the dependencies once (they stay in the ignored `.deps/` folder;
   `setup-release-deps.ps1` downloads the release licences and the ADB bundled
   with the Frame installer, checked against pinned SHA-256 hashes):

   ```powershell
   .\tools\setup-deps.ps1 -GameDir 'D:\SteamLibrary\steamapps\common\QV' `
     -BepInExSource 'D:\Dependencies\BepInEx-5.4.23.5' `
     -OpenVrSource 'D:\Dependencies\openvr-2.15.6'
   .\tools\setup-render-deps.ps1
   .\tools\setup-release-deps.ps1
   ```

3. Build:

   ```powershell
   .\tools\build.ps1
   ```

The release ZIP is written to `build/release/`. `.\tools\verify-release.ps1`
runs every automated test. `.\tools\build.ps1 -Configuration Debug` builds a
developer version with performance logging. Never commit or redistribute game
files. More detail is in [docs/](docs/).

## Licence

QVVR is released under the MIT License:

```text
MIT License

Copyright (c) 2026 Pk_c

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The release package also includes BepInEx, HarmonyX, MonoMod, Mono.Cecil,
Unity Doorstop, OpenVR, OpenXR and, for the Frame installer only, Android ADB
under their own licenses; see `QVVR-THIRD-PARTY-NOTICES.txt` in the package.
QV itself is not included.
