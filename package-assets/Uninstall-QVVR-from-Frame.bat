@echo off
setlocal
title Uninstall QVVR from Steam Frame
echo Removing QVVR from your Steam Frame (settings are kept). Close QV on the Frame and connect it by USB.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0QVVR-Frame-Setup.ps1" -Action Uninstall %*
set "qvvrExit=%errorlevel%"
echo.
pause
exit /b %qvvrExit%
