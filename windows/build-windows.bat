@echo off
chcp 65001 >nul
echo ================================================================
echo           HDRIVE WINDOWS (WinUI 3) DERLEME ARACI
echo ================================================================
echo.

where dotnet >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [HATA] .NET SDK bulunamadi! Lutfen .NET 8 SDK yukleyin:
    echo https://dotnet.microsoft.com/download/dotnet/8.0
    pause
    exit /b 1
)

cd /d "%~dp0HDriveWin"
echo [.NET] WinUI 3 projesi Release modunda derleniyor...
dotnet build -c Release -r win-x64 --self-contained

if %ERRORLEVEL% equ 0 (
    echo.
    echo [BASARILI] HDrive WinUI 3 uygulamasi basariyla derlendi!
    echo Konum: windows\HDriveWin\bin\x64\Release\net8.0-windows10.0.19041.0\win-x64\HDrive.exe
) else (
    echo.
    echo [HATA] Derleme sirasinda hata olustu.
)

pause
