#!/usr/bin/env bash
#
# Release pipeline: archive → sign → notarize → staple → DMG → notarize DMG
#
# Prereqs (one-time):
#   1. Developer ID Application certificate in your Keychain
#   2. xcrun notarytool store-credentials <profile> --apple-id ... --team-id ... --password ...
#   3. brew install xcodegen create-dmg
#
# Usage:
#   scripts/release.sh                       # defaults below
#   TEAM_ID=... KEYCHAIN_PROFILE=... scripts/release.sh
#
set -euo pipefail

# --- config (override via env) ---------------------------------------------
TEAM_ID="${TEAM_ID:-43THU6L26P}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-swordfish}"
VERSION="${VERSION:-1.1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJ_DIR="$REPO_ROOT/Swordfish"
BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Swordfish.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/Swordfish.app"
APP_ZIP="$BUILD_DIR/Swordfish-notarize.zip"
DMG_PATH="$BUILD_DIR/Swordfish-${VERSION}.dmg"

say()  { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m ✓\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m ✗\033[0m %s\n" "$*" >&2; exit 1; }

# --- sanity checks ----------------------------------------------------------
command -v xcodegen    >/dev/null || fail "xcodegen not installed (brew install xcodegen)"
command -v create-dmg  >/dev/null || fail "create-dmg not installed (brew install create-dmg)"
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || fail "Developer ID Application certificate missing from Keychain"
xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1 \
    || fail "notarytool keychain profile '$KEYCHAIN_PROFILE' not found — run 'xcrun notarytool store-credentials $KEYCHAIN_PROFILE ...' first"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- regenerate project -----------------------------------------------------
say "Regenerating Xcode project"
( cd "$PROJ_DIR" && xcodegen generate ) > /dev/null
ok "xcodegen"

# --- archive ----------------------------------------------------------------
say "Archiving (Release, signed with $SIGNING_IDENTITY)"
xcodebuild archive \
    -project "$PROJ_DIR/Swordfish.xcodeproj" \
    -scheme  Swordfish \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    > "$BUILD_DIR/archive.log" 2>&1 || {
        tail -30 "$BUILD_DIR/archive.log"
        fail "archive failed — see $BUILD_DIR/archive.log"
    }
ok "archive → $ARCHIVE_PATH"

# --- export .app ------------------------------------------------------------
say "Exporting .app"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$SCRIPT_DIR/exportOptions.plist" \
    > "$BUILD_DIR/export.log" 2>&1 || {
        tail -30 "$BUILD_DIR/export.log"
        fail "export failed — see $BUILD_DIR/export.log"
    }
ok "export → $APP_PATH"

# --- verify signature -------------------------------------------------------
say "Verifying local signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Sealed" | sed 's/^/  /'
ok "signature valid"

# --- notarize app -----------------------------------------------------------
say "Zipping app for notarization"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
ok "zipped → $APP_ZIP"

say "Submitting app to Apple Notary service (may take a few minutes)"
xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait \
    --output-format json > "$BUILD_DIR/notarize-app.json"
STATUS=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['status'])" "$BUILD_DIR/notarize-app.json")
[ "$STATUS" = "Accepted" ] || {
    cat "$BUILD_DIR/notarize-app.json"
    fail "notarization returned status: $STATUS"
}
ok "notarization: Accepted"

say "Stapling notarization ticket to app"
xcrun stapler staple "$APP_PATH"
ok "stapled"

say "Gatekeeper acceptance check"
spctl -a -vv "$APP_PATH" 2>&1 | sed 's/^/  /'

# --- package DMG ------------------------------------------------------------
say "Building DMG"
# Stage only the .app so xcodebuild's DistributionSummary.plist / ExportOptions.plist
# / Packaging.log don't leak into the DMG.
DMG_STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
/usr/bin/ditto "$APP_PATH" "$DMG_STAGE/Swordfish.app"

# create-dmg refuses to overwrite; we already cleaned build/
create-dmg \
    --volname "Swordfish ${VERSION}" \
    --window-pos 200 120 \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "Swordfish.app" 140 180 \
    --hide-extension "Swordfish.app" \
    --app-drop-link 400 180 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$DMG_STAGE" \
    > "$BUILD_DIR/create-dmg.log" 2>&1 || {
        tail -30 "$BUILD_DIR/create-dmg.log"
        fail "create-dmg failed"
    }
ok "DMG → $DMG_PATH"

# --- notarize DMG ----------------------------------------------------------
say "Signing DMG"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
ok "DMG signed"

say "Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait \
    --output-format json > "$BUILD_DIR/notarize-dmg.json"
STATUS=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['status'])" "$BUILD_DIR/notarize-dmg.json")
[ "$STATUS" = "Accepted" ] || {
    cat "$BUILD_DIR/notarize-dmg.json"
    fail "DMG notarization returned status: $STATUS"
}
ok "DMG notarization: Accepted"

say "Stapling DMG"
xcrun stapler staple "$DMG_PATH"
ok "DMG stapled"

say "Final Gatekeeper check on DMG"
spctl -a -vv --type open --context context:primary-signature "$DMG_PATH" 2>&1 | sed 's/^/  /' || true

printf "\n\033[1;32m🎣  Release ready:\033[0m  %s\n" "$DMG_PATH"
printf "   size: %s\n" "$(du -h "$DMG_PATH" | awk '{print $1}')"
printf "   next: gh release create v%s \"%s\" --title 'Swordfish %s' --notes-file RELEASE_NOTES.md\n" \
    "$VERSION" "$DMG_PATH" "$VERSION"
