#!/bin/bash

# HDrive - macOS Finder Bağlantı Betiği
clear
echo "================================================================"
echo "             HDRIVE - MACOS FINDER BAĞLANTI ARACI               "
echo "================================================================"
echo ""
echo "iPhone ekranında görünen IP adresini girin (Örn: 192.168.1.50):"
read -p "iPhone IP Adresi: " IPHONE_IP

if [ -z "$IPHONE_IP" ]; then
    echo "[HATA] IP adresi girmediniz!"
    exit 1
fi

PORT=8080
WEBDAV_URL="http://$IPHONE_IP:$PORT"

echo ""
echo "[BİLGİ] macOS Finder ile $WEBDAV_URL adresine bağlanılıyor..."

# macOS Finder'da doğrudan Sunucuya Bağlan penceresini açar
osascript -e "tell application \"Finder\" to open location \"$WEBDAV_URL\""

echo ""
echo "[BAŞARILI] Finder bağlantı isteği gönderildi."
echo "Eğer Finder doğrudan açılmazsa tarayıcı ile açmak için bir tuşa basın..."
read -n 1 -s
open "$WEBDAV_URL"
