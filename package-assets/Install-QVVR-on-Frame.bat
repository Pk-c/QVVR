@echo off
setlocal
title Install QVVR on Steam Frame
echo Installing QVVR on your Steam Frame. Close QV on the Frame and connect it by USB.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0QVVR-Frame-Setup.ps1" -Action Install %*
set "qvvrExit=%errorlevel%"
echo.
pause
exit /b %qvvrExit%
