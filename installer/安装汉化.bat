@echo off
cd /d "%~dp0"
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0silver_gui.ps1"
