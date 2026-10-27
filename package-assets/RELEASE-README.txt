QVVR - experimental VR mod for QV (Windows Unity Mono build, Steam app 1494110)
================================================================================

Extract this whole ZIP to a folder first. It contains:

  PC/          The mod overlay for the game folder (BepInEx loader + QVVR).
  SteamFrame/  Windows USB installer for Steam Frame (ADB included).
  README.txt   This file.

Windows PC (native PCVR or desktop)
-----------------------------------
1. Close QV.
2. Copy the CONTENTS of PC/ directly beside QV.exe (not the PC folder itself).
   When updating, keep your BepInEx/config/dev.qvvr.prototype.cfg.
3. Start QV yourself. No launch options are needed on Windows. Only if the game
   stays on the desktop and BepInEx/LogOutput.log says "QVVR requires D3D11",
   add -force-d3d11 to the Steam launch options.
Uninstall: close QV, double-click uninstall.bat beside QV.exe.

Steam Frame (from a Windows PC over USB)
----------------------------------------
1. Close QV on the Frame. Enable Developer Mode / USB debugging on the Frame
   and connect it to this PC with a USB cable. Nothing else to install.
2. Double-click SteamFrame/Install-QVVR-on-Frame.bat. The first time, accept
   the "Allow USB debugging" prompt in the headset. It ends with a clear
   SUCCESS or FAILED screen telling you what to do next.
3. It installs PC/ on the Frame and sets the QV Steam launch options:
     WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11
   Setting launch options needs Steam running and CEF Remote Debugging enabled
   in the Frame developer settings; otherwise the tool tells you how to set
   them manually. Existing options are kept and completed, not replaced.
   A first Frame install starts from SteamFrame/QVVR-Frame-Defaults.cfg (the
   Steam Frame reference profile); an existing Frame config is kept.
Uninstall: double-click SteamFrame/Uninstall-QVVR-from-Frame.bat (keeps settings).
See SteamFrame/QVVR-Frame-Setup.txt for details, backups and recovery.

Nothing here starts or terminates QV. See PC/README.txt and
PC/RELEASE-NOTES.txt for features, known limits and licenses.
