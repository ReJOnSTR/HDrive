#!/bin/bash
set -euo pipefail
hdrive_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$hdrive_repo_dir"
hdrive_test_dir="${HDRIVE_TEST_OUTPUT:-build/apple-regression}"
mkdir -p "$hdrive_test_dir"
# Compile each platform client against the same behavioral regressions.
hdrive_client="${HDRIVE_TEST_CLIENT:-macOS/HDriveMac/Services/WebDAVClient.swift}"
hdrive_client_flags=(-D HDRIVE_APPLE_CLIENT)
if [[ "$hdrive_client" == "macOS/HDriveMac/Services/WebDAVClient.swift" ]]; then hdrive_client_flags=(-D HDRIVE_MAC_CLIENT); fi
xcrun swiftc -parse-as-library -module-cache-path "$hdrive_test_dir/module-cache" \
  "${hdrive_client_flags[@]}" \
  "$hdrive_client" iOS/HDrive/Models/FolderSync.swift iOS/HDrive/Models/StorageSecurity.swift iOS/HDrive/Models/S3Storage.swift \
  iOS/HDrive/Models/KeychainHelper.swift macOS/HDriveMac/Services/CloudreveManager.swift \
  macOS/HDriveMac/Services/AppUpdateService.swift \
  macOS/HDriveMac/Services/ExplorerSearch.swift macOS/HDriveMac/Views/FileDragSource.swift \
  macOS/HDriveMac/Services/ResumableDownload.swift \
  macOS/HDriveMac/Services/FileExportService.swift macOS/HDriveMac/Services/FileOpener.swift iOS/HDrive/Models/SyncLogManager.swift \
  iOS/HDrive/Models/FileItem.swift iOS/HDrive/Models/ServerConfig.swift iOS/HDrive/Models/NetworkUtils.swift \
  iOS/HDrive/Server/WebDAVHandler.swift iOS/HDrive/Server/WebDashboardEmbeddedAssets.swift \
  macOS/tests/ParityRegression.swift macOS/tests/CoreRegression.swift -o "$hdrive_test_dir/CoreRegression"
"$hdrive_test_dir/CoreRegression"
