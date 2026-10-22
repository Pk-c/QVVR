@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" -Interactive
set "qvvrExit=%errorlevel%"
echo.
pause
exit /b %qvvrExit%
