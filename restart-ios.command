#!/bin/bash
# HDrive - iOS Simülatöründe Derle ve Çalıştır
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "📱 iOS Simülatörü açılıyor..."
open -a Simulator

# Booted cihaz var mı kontrol et, yoksa ilk uygun iPhone'u başlat
BOOTED_ID=$(xcrun simctl list devices | grep -E "iPhone.*\(Booted\)" | head -n 1 | sed -E 's/.*\(([0-9A-F\-]+)\).*/\1/')

if [ -z "$BOOTED_ID" ]; then
    DEVICE_ID=$(xcrun simctl list devices available | grep -E "iPhone" | head -n 1 | sed -E 's/.*\(([0-9A-F\-]+)\).*/\1/')
    if [ -n "$DEVICE_ID" ]; then
        echo "⏳ Simülatör başlatılıyor ($DEVICE_ID)..."
        xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
        BOOTED_ID="$DEVICE_ID"
    else
        BOOTED_ID="booted"
    fi
fi

echo "🧹 Genişletilmiş öznitelikler temizleniyor..."
xattr -cr iOS 2>/dev/null || true

echo "🔨 HDrive iOS uygulaması derleniyor..."
xcodebuild -project iOS/HDrive.xcodeproj \
  -scheme HDrive \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath build/iOS \
  CODE_SIGNING_ALLOWED=NO \
  build

if [ $? -eq 0 ]; then
  APP_PATH="$DIR/build/iOS/Build/Products/Debug-iphonesimulator/HDrive.app"
  echo "📲 Simülatöre yükleniyor..."
  xcrun simctl install booted "$APP_PATH"
  echo "🚀 HDrive başlatılıyor..."
  xcrun simctl launch booted com.halilsak.HDrive
  echo "✅ HDrive iOS simülatöründe başarıyla çalıştırıldı!"
else
  echo "❌ Derleme hatası oluştu!"
fi
