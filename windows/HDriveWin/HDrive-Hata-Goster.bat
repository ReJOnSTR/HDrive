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
) else (
    echo Herhangi bir hata dosyasi olusmadi. Cikis Kodu: %EXITCODE%
)

echo.
echo ======================================================================
echo Konsolu kapatmak icin klavyeden herhangi bir tusa basin...
pause > nul
