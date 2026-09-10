@echo off
chcp 65001 >nul
cd /d "%~dp0HDriveWin"
dotnet run -p:Platform=x64 -r win-x64
