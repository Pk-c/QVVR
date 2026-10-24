QVVR - experimental VR mod for QV (Windows Unity Mono build, Steam app 1494110)
================================================================================

Extract this whole ZIP to a folder first. It contains:

  PC/          The mod overlay for the game folder (BepInEx loader + QVVR).
  SteamFrame/  Windows USB installer for Steam Frame (Install/update,
               Steam launch options, Uninstall).
  README.txt   This file.

Windows PC (native PCVR or desktop)
-----------------------------------
1. Close QV.
2. Copy the CONTENTS of PC/ directly beside QV.exe (not the PC folder itself).
   When updating, keep your BepInEx/config/dev.qvvr.prototype.cfg.
3. Start QV yourself. On native Windows add -force-d3d11 to the Steam launch
   options (no WINEDLLOVERRIDES prefix is needed there).
Uninstall: close QV, double-click uninstall.bat beside QV.exe.

Steam Frame (from a Windows PC over USB)
----------------------------------------
1. Close QV on the Frame. Enable Developer Mode / USB debugging, connect the
   Frame over USB and authorize this PC in the headset.
2. Put official Android SDK Platform Tools in SteamFrame/platform-tools/
   (SteamFrame/platform-tools/adb.exe), or have adb on PATH.
3. Double-click SteamFrame/QVVR-Frame-Setup.bat and choose 1 (Install/update).
   It installs PC/ on the Frame and sets the QV Steam launch options:
     WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11
   Setting launch options needs Steam running and CEF Remote Debugging enabled
   in the Frame developer settings; otherwise the tool tells you how to set
   them manually. Existing options are kept and completed, not replaced.
See SteamFrame/QVVR-Frame-Setup.txt for details, backups and recovery.

Nothing here starts or terminates QV. See PC/README.txt and
PC/RELEASE-NOTES.txt for features, known limits and licenses.
