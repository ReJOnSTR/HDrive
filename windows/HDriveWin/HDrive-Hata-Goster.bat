@echo off
chcp 65001 > nul
title HDrive Hata ve Teshis Konsolu
echo ======================================================================
echo                  HDRIVE BASLATMA VE TESHIS KONSOLU
echo ======================================================================
echo.
cd /d "%~dp0"
echo Uygulama Dizini: %cd%
echo.
echo HDrive.exe calistiriliyor... Lutfen bekleyin...
echo ----------------------------------------------------------------------

HDrive.exe

set EXITCODE=%ERRORLEVEL%
echo ----------------------------------------------------------------------
echo HDrive kapandi veya sonlandi. Cikis Kodu (Exit Code): %EXITCODE%
echo ======================================================================
echo.

if exist "%USERPROFILE%\Desktop\HDrive-Hata.txt" (
    echo [!] Masaustunde hata raporu bulundu (HDrive-Hata.txt):
    echo.
    type "%USERPROFILE%\Desktop\HDrive-Hata.txt"
) else if exist "HDrive-Hata.txt" (
    echo [!] Uygulama dizininde hata raporu bulundu:
    echo.
    type "HDrive-Hata.txt"
) else if exist "%LOCALAPPDATA%\HDrive\startup.log" (
    echo [!] Baslatma kayitlari (startup.log):
    echo.
    type "%LOCALAPPDATA%\HDrive\startup.log"
)
if exist "%LOCALAPPDATA%\HDrive\crash.log" (
    echo.
    echo [!] Cokme kayitlari (crash.log):
    echo.
    type "%LOCALAPPDATA%\HDrive\crash.log"
)

echo.
echo ======================================================================
echo COZUM SECENEKLERI:
if exist "WindowsAppRuntimeInstall-x64.exe" (
    echo [1] Windows App SDK 1.5 Runtime'i Yonetici Olarak Kur
)
if exist "vc_redist.x64.exe" (
    echo [2] Visual C++ 2015-2022 Runtime'i Yonetici Olarak Kur
)
echo [0] Konsoldan Cik
echo ======================================================================
set /p SECIM="Lutfen bir secim yapin [0-2]: "

if "%SECIM%"=="1" (
    if exist "WindowsAppRuntimeInstall-x64.exe" (
        echo Windows App SDK kuruluyor, yonetici izni onaylayin...
        powershell -Command "Start-Process 'WindowsAppRuntimeInstall-x64.exe' -ArgumentList '--quiet' -Verb RunAs -Wait"
        echo Kurulum tamamlandi. HDrive.exe tekrar calistiriliyor...
        start "" "HDrive.exe"
        exit /b 0
    )
)

if "%SECIM%"=="2" (
    if exist "vc_redist.x64.exe" (
        echo Visual C++ kuruluyor, yonetici izni onaylayin...
        powershell -Command "Start-Process 'vc_redist.x64.exe' -ArgumentList '/install /passive /norestart' -Verb RunAs -Wait"
        echo Kurulum tamamlandi. HDrive.exe tekrar calistiriliyor...
        start "" "HDrive.exe"
        exit /b 0
    )
)

exit /b 0

