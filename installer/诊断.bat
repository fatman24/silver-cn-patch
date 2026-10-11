@echo off
cd /d "%~dp0"
echo === 诊断：直接运行安装器（窗口不隐藏）===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0silver_gui.ps1"
echo === 退出码: %ERRORLEVEL% ===
pause
