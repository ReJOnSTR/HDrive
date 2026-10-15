#!/bin/bash
set -euo pipefail
hdrive_mode="$1"
hdrive_app="$2"
hdrive_required="${HDRIVE_REQUIRE_SIGNING:-false}"
hdrive_temp="$(mktemp -d "${TMPDIR:-/tmp}/hdrive-sign.XXXXXX")"
hdrive_keychain="$hdrive_temp/signing.keychain-db"
cleanup() {
  if [ -f "$hdrive_keychain" ]; then security delete-keychain "$hdrive_keychain" >/dev/null 2>&1 || true; fi
  # Only temporary credentials created by this script are removed.
  find "$hdrive_temp" -type f -exec rm -f {} +
  rmdir "$hdrive_temp" 2>/dev/null || true
}
trap cleanup EXIT
if [ "$hdrive_mode" = "sign" ]; then
  if [ -z "${MACOS_SIGNING_CERTIFICATE_BASE64:-}" ] || [ -z "${MACOS_SIGNING_CERTIFICATE_PASSWORD:-}" ]; then
    if [ "$hdrive_required" = "true" ]; then echo 'Developer ID release signing secrets are missing.' >&2; exit 1; fi
    echo 'Development build: Developer ID signing is not configured.'; exit 0
  fi
  printf '%s' "$MACOS_SIGNING_CERTIFICATE_BASE64" | base64 --decode > "$hdrive_temp/certificate.p12"
  hdrive_keychain_password="$(openssl rand -base64 32)"
  security create-keychain -p "$hdrive_keychain_password" "$hdrive_keychain"
  security set-keychain-settings -lut 21600 "$hdrive_keychain"
  security unlock-keychain -p "$hdrive_keychain_password" "$hdrive_keychain"
  security import "$hdrive_temp/certificate.p12" -k "$hdrive_keychain" -P "$MACOS_SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$hdrive_keychain_password" "$hdrive_keychain" >/dev/null
  hdrive_identity="$(security find-identity -v -p codesigning "$hdrive_keychain" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"
  if [ -z "$hdrive_identity" ]; then echo 'The certificate must be Developer ID Application.' >&2; exit 1; fi
  codesign --force --options runtime --timestamp --keychain "$hdrive_keychain" --sign "$hdrive_identity" "$hdrive_app"
  codesign --verify --deep --strict --verbose=2 "$hdrive_app"
elif [ "$hdrive_mode" = "notarize" ]; then
  hdrive_dmg="$3"
  if [ -z "${APPLE_NOTARY_KEY_BASE64:-}" ] || [ -z "${APPLE_NOTARY_KEY_ID:-}" ] || [ -z "${APPLE_NOTARY_ISSUER_ID:-}" ]; then
    if [ "$hdrive_required" = "true" ]; then echo 'Apple notarization API secrets are missing.' >&2; exit 1; fi
    echo 'Development build: Apple notarization is not configured.'; exit 0
  fi
  printf '%s' "$APPLE_NOTARY_KEY_BASE64" | base64 --decode > "$hdrive_temp/AuthKey.p8"
  xcrun notarytool submit "$hdrive_dmg" --key "$hdrive_temp/AuthKey.p8" --key-id "$APPLE_NOTARY_KEY_ID" \
    --issuer "$APPLE_NOTARY_ISSUER_ID" --wait --output-format json > "$hdrive_temp/notary.json"
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print("Notarization:", r.get("status")); sys.exit(0 if r.get("status")=="Accepted" else 1)' "$hdrive_temp/notary.json"
  xcrun stapler staple "$hdrive_dmg"
  xcrun stapler staple "$hdrive_app"
  xcrun stapler validate "$hdrive_dmg"
else
  echo 'Usage: sign-release.sh sign APP | notarize APP DMG' >&2; exit 2
fi
