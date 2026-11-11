@echo off
REM build_windows.bat - 버전(패치) +1 후 Windows 릴리스 빌드. 옵션: -Minor / -NoBump
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_windows.ps1" %*
