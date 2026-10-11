@echo off
chcp 65001 >nul
setlocal
set "PSEXE=powershell"
where pwsh >nul 2>nul && set "PSEXE=pwsh"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" uninstall %*
echo.
pause
