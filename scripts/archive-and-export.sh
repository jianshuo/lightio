#!/bin/bash
# Archive CCLight for App Store distribution.
# Prereq: an app record for bundle id com.wangjianshuo.cclight must exist
# in App Store Connect (https://appstoreconnect.apple.com/apps) and the team's
# Apple Distribution cert + provisioning profile must be available.
#
# Usage:
#   scripts/archive-and-export.sh           # archive + export to .pkg under build/
#   scripts/archive-and-export.sh upload    # also upload to App Store Connect
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARCHIVE="$ROOT/build/CCLight.xcarchive"
EXPORT_DIR="$ROOT/build/export"
EXPORT_OPTS="$ROOT/scripts/ExportOptions.plist"

mkdir -p "$ROOT/build"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

echo "==> Archive"
xcodebuild \
  -project cclight.xcodeproj \
  -scheme cclight \
  -configuration Release \
  -destination 'platform=macOS' \
  archive \
  -archivePath "$ARCHIVE" \
  | grep -E "(error:|warning:|ARCHIVE)" | tail -5

echo "==> Export for App Store Connect"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS"

PKG="$(find "$EXPORT_DIR" -name '*.pkg' | head -1)"
echo "==> Output package: $PKG"

if [ "${1:-}" = "upload" ]; then
  echo "==> Upload to App Store Connect"
  # Requires App Store Connect API key or xcrun altool credentials in the keychain.
  # Generate an API key at https://appstoreconnect.apple.com/access/api and add to
  # ~/.appstoreconnect/private_keys/ as AuthKey_XXXXXXXXXX.p8, then set:
  #   export ASC_KEY_ID=XXXXXXXXXX
  #   export ASC_ISSUER_ID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
  xcrun altool --upload-app \
    --type macos \
    --file "$PKG" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"
fi

echo "==> Done."
