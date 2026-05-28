#!/bin/bash
# Archive, export, notarize, and staple CCLight for Developer ID distribution.
#
# Prereqs:
#   1. A "Developer ID Application: Jian Shuo Wang (97XBW2A43H)" certificate
#      must be installed in the login keychain.
#      Install via Xcode → Settings → Accounts → Manage Certificates → "+" →
#      Developer ID Application, or generate at
#      https://developer.apple.com/account/resources/certificates
#   2. App Store Connect API key (used for notarytool auth) — env vars:
#        ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_API_KEY_CONTENT
#
# Usage:
#   scripts/archive-and-export.sh             # archive → export → notarize → staple
#   scripts/archive-and-export.sh --dmg       # also build a CCLight.dmg for download
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARCHIVE="$ROOT/build/CCLight.xcarchive"
EXPORT_DIR="$ROOT/build/export"
EXPORT_OPTS="$ROOT/scripts/ExportOptions.plist"

mkdir -p "$ROOT/build"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

# Build number stamping so each archive is unique under the current
# marketing version (some downstream tools, e.g. Sparkle update feeds,
# rely on a monotonically increasing build number).
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
echo "==> Bumping CURRENT_PROJECT_VERSION → $BUILD_NUMBER"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" \
  cclight.xcodeproj/project.pbxproj

echo "==> Archive"
xcodebuild \
  -project cclight.xcodeproj \
  -scheme cclight \
  -configuration Release \
  -destination 'platform=macOS' \
  archive \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  | grep -E "(error:|warning:|ARCHIVE)" | tail -5

echo "==> Export for Developer ID"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -allowProvisioningUpdates

APP="$EXPORT_DIR/CCLight.app"
[ -d "$APP" ] || { echo "ERROR: $APP not found after export"; exit 1; }
echo "==> Exported app: $APP"

echo "==> Notarize"
# notarytool needs API key auth. Decode the base64 env var into a temp file.
: "${ASC_API_KEY_ID:?missing}"
: "${ASC_API_ISSUER_ID:?missing}"
: "${ASC_API_KEY_CONTENT:?missing}"
KEY_FILE="$(mktemp -t asc-key-XXXXXX.p8)"
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s' "$ASC_API_KEY_CONTENT" | base64 --decode > "$KEY_FILE"
chmod 600 "$KEY_FILE"

# notarytool only accepts .zip / .pkg / .dmg. Zip the app for submission.
ZIP="$EXPORT_DIR/CCLight.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
  --key "$KEY_FILE" \
  --key-id "$ASC_API_KEY_ID" \
  --issuer "$ASC_API_ISSUER_ID" \
  --wait

echo "==> Staple"
xcrun stapler staple "$APP"

if [ "${1:-}" = "--dmg" ]; then
  echo "==> Build DMG"
  DMG="$EXPORT_DIR/CCLight.dmg"
  rm -f "$DMG"
  STAGING="$(mktemp -d)"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "CCLight" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
  rm -rf "$STAGING"
  # Sign + notarize the DMG too so Gatekeeper trusts it at download time.
  codesign --sign "Developer ID Application: Jian Shuo Wang (97XBW2A43H)" \
    --timestamp "$DMG"
  xcrun notarytool submit "$DMG" \
    --key "$KEY_FILE" \
    --key-id "$ASC_API_KEY_ID" \
    --issuer "$ASC_API_ISSUER_ID" \
    --wait
  xcrun stapler staple "$DMG"
  echo "==> DMG: $DMG"
fi

echo "==> Done. Distributable artifact: $APP"
