#!/bin/bash
# HDrive - macOS Derle ve Yeniden Başlat
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "⏳ Varsa eski HDrive kapatılıyor..."
pkill -f "HDrive.app/Contents/MacOS/HDrive" 2>/dev/null || true
sleep 0.5

echo "🔨 HDrive derleniyor..."
mkdir -p macOS/HDrive.app/Contents/MacOS
mkdir -p macOS/HDrive.app/Contents/Resources
cp macOS/Info.plist macOS/HDrive.app/Contents/Info.plist 2>/dev/null || true
cp macOS/AppIcon.icns macOS/HDrive.app/Contents/Resources/AppIcon.icns 2>/dev/null || true

swiftc -parse-as-library \
  iOS/HDrive/Models/FileItem.swift \
  iOS/HDrive/Models/ServerConfig.swift \
  iOS/HDrive/Models/NetworkUtils.swift \
  iOS/HDrive/Models/KeychainHelper.swift \
  iOS/HDrive/Models/NetworkMonitor.swift \
  iOS/HDrive/Models/SyncLogManager.swift \
  iOS/HDrive/Server/BonjourPublisher.swift \
  iOS/HDrive/Server/WebDAVHandler.swift \
  iOS/HDrive/Server/WebDAVServer.swift \
  iOS/HDrive/Server/WebDashboardEmbeddedAssets.swift \
  macOS/HDriveMac/Services/WebDAVClient.swift \
  macOS/HDriveMac/Services/CloudreveManager.swift \
  macOS/HDriveMac/Services/DriveMounter.swift \
  macOS/HDriveMac/Services/FolderSyncEngine.swift \
  macOS/HDriveMac/Services/BonjourBrowser.swift \
  macOS/HDriveMac/Services/FileOpener.swift \
  macOS/HDriveMac/Services/FilePreviewManager.swift \
  macOS/HDriveMac/Services/FileIconProvider.swift \
  macOS/HDriveMac/Views/NativeExplorerView.swift \
  macOS/HDriveMac/HDriveMacApp.swift \
  -o "macOS/HDrive.app/Contents/MacOS/HDrive"

if [ $? -eq 0 ]; then
  echo "🚀 HDrive açılıyor..."
  open "$DIR/macOS/HDrive.app"
  echo "✅ Başarılı!"
else
  echo "❌ Derleme hatası oluştu!"
fi
