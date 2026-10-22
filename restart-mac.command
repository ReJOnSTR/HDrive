#!/bin/bash
set -euo pipefail
hdrive_repo_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$hdrive_repo_dir"
hdrive_output_dir="${HDRIVE_BUILD_OUTPUT:-$hdrive_repo_dir/build/macos}"
# Build successfully before closing the running application.
HDRIVE_BUILD_OUTPUT="$hdrive_output_dir" bash macOS/build-macos.sh
if pgrep -x HDrive >/dev/null; then
  osascript -e 'tell application id "com.halilsak.HDriveMac" to quit'
  for hdrive_attempt in {1..50}; do
    if ! pgrep -x HDrive >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x HDrive >/dev/null; then
    echo "HDrive kapanmadı. Uygulamayı kapatıp yeniden deneyin." >&2
    exit 1
  fi
fi
open "$hdrive_output_dir/HDrive.app"
