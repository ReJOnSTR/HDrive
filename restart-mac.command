#!/bin/bash
# HDrive - Yeniden Başlatıcı (Kapat ve Yeniden Aç)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "HDrive kapatılıyor..."
pkill -f "HDrive.app/Contents/MacOS/HDrive" || true
sleep 0.5

echo "HDrive yeniden açılıyor..."
open "$DIR/macOS/HDrive.app"
echo "Başarılı!"
