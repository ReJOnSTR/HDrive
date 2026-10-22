#!/bin/bash
set -euo pipefail
hdrive_repo_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$hdrive_repo_dir"
hdrive_output_dir="${HDRIVE_BUILD_OUTPUT:-$hdrive_repo_dir/build/macos}"
if [[ ! -x "$hdrive_output_dir/HDrive.app/Contents/MacOS/HDrive" ]]; then
  HDRIVE_BUILD_OUTPUT="$hdrive_output_dir" bash macOS/build-macos.sh
fi
open "$hdrive_output_dir/HDrive.app"
