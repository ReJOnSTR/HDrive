@echo off
chcp 65001 >nul
title HDrive - Windows Ag Surucusu Baglantisini Kes
cls
echo ================================================================
echo             HDRIVE - AG SURUCUSU BAGLANTISINI KESME             
echo ================================================================
echo.
echo Z: surucusunun baglantisi kesiliyor...
net use Z: /delete /y

if %ERRORLEVEL% equ 0 (
    echo.
    echo [BASARILI] Z: ag surucusu guvenle kaldirildi.
) else (
    echo.
    echo [BILGI] Z: surucusu zaten bagli degil veya kaldirilamadi.
)

echo.
pause
