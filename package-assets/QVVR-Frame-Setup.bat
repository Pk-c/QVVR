@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0QVVR-Frame-Setup.ps1" %*
set "qvvrExit=%errorlevel%"
echo.
pause
exit /b %qvvrExit%
