#!/bin/bash
set -euo pipefail
hdrive_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$hdrive_repo_dir"
hdrive_output_dir="${HDRIVE_BUILD_OUTPUT:-build/macos}"
hdrive_app="$hdrive_output_dir/HDrive.app"
mkdir -p "$hdrive_app/Contents/MacOS" "$hdrive_app/Contents/Resources"
cp -X macOS/Info.plist "$hdrive_app/Contents/Info.plist"
cp -R Resources/Localization "$hdrive_app/Contents/Resources/"
cp -X macOS/AppIcon.icns "$hdrive_app/Contents/Resources/AppIcon.icns"
hdrive_sources=(
  iOS/HDrive/Models/FileItem.swift iOS/HDrive/Models/ServerConfig.swift
  iOS/HDrive/Models/NetworkUtils.swift iOS/HDrive/Models/KeychainHelper.swift
  iOS/HDrive/Models/NetworkMonitor.swift iOS/HDrive/Models/SyncLogManager.swift
  iOS/HDrive/Models/FolderSync.swift
  iOS/HDrive/Models/StorageSecurity.swift iOS/HDrive/Models/S3Storage.swift
  iOS/HDrive/Server/BonjourPublisher.swift iOS/HDrive/Server/WebDAVHandler.swift
  iOS/HDrive/Server/WebDAVServer.swift iOS/HDrive/Server/WebDashboardEmbeddedAssets.swift
  macOS/HDriveMac/Services/WebDAVClient.swift macOS/HDriveMac/Services/CloudreveManager.swift
  macOS/HDriveMac/Services/TransferManager.swift macOS/HDriveMac/Services/BonjourBrowser.swift
  macOS/HDriveMac/Services/AppUpdateService.swift macOS/HDriveMac/Views/AppUpdatesView.swift
  macOS/HDriveMac/Services/ExplorerSearch.swift macOS/HDriveMac/Views/FileDragSource.swift
  macOS/HDriveMac/Services/ResumableDownload.swift
  macOS/HDriveMac/Services/FileExportService.swift
  macOS/HDriveMac/Services/FileOpener.swift macOS/HDriveMac/Services/FilePreviewManager.swift
  macOS/HDriveMac/Services/FileIconProvider.swift macOS/HDriveMac/Views/TransferPopoverView.swift
  iOS/HDrive/Views/WorkspaceViews.swift
  macOS/HDriveMac/Views/FinderRenameField.swift
  macOS/HDriveMac/Views/NativeExplorerView.swift macOS/HDriveMac/HDriveMacApp.swift
)
for hdrive_arch in arm64 x86_64; do
  xcrun swiftc -parse-as-library -target "$hdrive_arch-apple-macos14.0" \
    -module-cache-path "$hdrive_output_dir/module-cache-$hdrive_arch" \
    "${hdrive_sources[@]}" -o "$hdrive_output_dir/HDrive-$hdrive_arch"
done
xcrun lipo -create "$hdrive_output_dir/HDrive-arm64" "$hdrive_output_dir/HDrive-x86_64" \
  -output "$hdrive_app/Contents/MacOS/HDrive"
xcrun lipo "$hdrive_app/Contents/MacOS/HDrive" -verify_arch arm64 x86_64
# Development builds use an explicit ad-hoc bundle signature. Distribution signing
# and notarization are enforced separately for public release tags.
hdrive_signing_stage="$(mktemp -d "${TMPDIR:-/tmp}/hdrive-build-sign.XXXXXX")"
trap 'rm -rf "$hdrive_signing_stage"' EXIT
ditto --norsrc --noextattr "$hdrive_app" "$hdrive_signing_stage/HDrive.app"
xattr -cr "$hdrive_signing_stage/HDrive.app"
codesign --force --sign - "$hdrive_signing_stage/HDrive.app"
codesign --verify --deep --strict "$hdrive_signing_stage/HDrive.app"
ditto --norsrc --noextattr "$hdrive_signing_stage/HDrive.app" "$hdrive_app"
printf 'Built Universal application: %s\n' "$hdrive_app"
