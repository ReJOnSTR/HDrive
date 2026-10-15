#!/bin/bash
set -euo pipefail
hdrive_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$hdrive_repo_dir"
hdrive_test_dir="build/apple-regression"
mkdir -p "$hdrive_test_dir"
# Compile the production storage client and models directly.
xcrun swiftc -parse-as-library -module-cache-path "$hdrive_test_dir/module-cache" \
  macOS/HDriveMac/Services/WebDAVClient.swift iOS/HDrive/Models/FolderSync.swift iOS/HDrive/Models/StorageSecurity.swift iOS/HDrive/Models/S3Storage.swift \
  iOS/HDrive/Models/KeychainHelper.swift macOS/HDriveMac/Services/CloudreveManager.swift \
  iOS/HDrive/Models/FileItem.swift iOS/HDrive/Models/ServerConfig.swift iOS/HDrive/Models/NetworkUtils.swift \
  iOS/HDrive/Server/WebDAVHandler.swift iOS/HDrive/Server/WebDashboardEmbeddedAssets.swift \
  macOS/tests/CoreRegression.swift -o "$hdrive_test_dir/CoreRegression"
"$hdrive_test_dir/CoreRegression"
