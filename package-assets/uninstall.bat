@echo off
setlocal
cd /d "%~dp0" || exit /b 1
if not exist "QV.exe" (
  echo QV.exe not found beside this script. Refusing to remove files.
  exit /b 1
)
if not exist ".qvvr-loader-owner" (
  echo QVVR ownership marker not found. Refusing to remove shared loader files.
  exit /b 1
)

if exist "BepInEx\plugins\QVVR" rmdir /s /q "BepInEx\plugins\QVVR"
if exist "BepInEx\config\dev.qvvr.prototype.cfg" del /q "BepInEx\config\dev.qvvr.prototype.cfg"
del /q ".qvvr-loader-owner"

echo QVVR plugin and configuration removed.
echo BepInEx, winhttp.dll and doorstop_config.ini were preserved because other mods may use them.
