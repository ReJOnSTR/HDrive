@echo off
chcp 65001 >nul
title HDrive - Windows Ag Surucusu Baglama Sihirbazi
cls
echo ================================================================
echo             HDRIVE - IPHONE AG SURUCUSU BAGLAMA ARACI           
echo ================================================================
echo.
echo Bu arac iPhone'unuzdaki HDrive uygulamasini dogrudan Windows
echo Dosya Gezgini icerisine 'Z:' surucusu olarak baglar.
echo.
echo [1] iPhone'unuzda HDrive uygulamasini acin ve 'Paylasimi Baslat'a basin.
echo [2] iPhone ekraninda gorunen IP adresini girin (Orn: 192.168.1.50)
echo.

set /p IPHONE_IP="iPhone IP Adresi: "

if "%IPHONE_IP%"=="" (
    echo.
    echo [HATA] IP adresi girmediniz! Islem iptal edildi.
    pause
    exit /b
)

set DRIVE_LETTER=Z:
set PORT=8080
set WEBDAV_URL=http://%IPHONE_IP%:%PORT%

echo.
echo [BILGI] Eski %DRIVE_LETTER% baglantisi kontrol ediliyor...
net use %DRIVE_LETTER% /delete /y >nul 2>&1

echo [BILGI] %WEBDAV_URL% adresi %DRIVE_LETTER% olarak baglaniyor...
net use %DRIVE_LETTER% %WEBDAV_URL% /persistent:no

if %ERRORLEVEL% equ 0 (
    echo.
    echo ================================================================
    echo [BASARILI] iPhone basariyla %DRIVE_LETTER% surucusu olarak baglandi!
    echo ================================================================
    echo.
    echo Dosya Gezgini aciliyor...
    explorer %DRIVE_LETTER%
) else (
    echo.
    echo [BILGI] Alternatif WebClient yontemi deneniyor...
    net use %DRIVE_LETTER% "\\%IPHONE_IP%@%PORT%\DavWWWRoot" /persistent:no
    if %ERRORLEVEL% equ 0 (
        echo [BASARILI] iPhone %DRIVE_LETTER% olarak baglandi!
        explorer %DRIVE_LETTER%
    ) else (
        echo.
        echo [DIKKAT] Dogrudan surucu baglanamadi.
        echo Tarayici ile web arayuzunu acmak icin bir tusa basin...
        pause >nul
        start %WEBDAV_URL%
    )
)

echo.
pause
