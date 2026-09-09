@echo off
chcp 65001 >nul
cd /d "%~dp0HDriveWin"
dotnet run -r win-x64
