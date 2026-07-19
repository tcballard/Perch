#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Perch.xcodeproj"
SCHEME="Perch"
TEAM_ID="R8HXTBY3NM"
APP_BUNDLE_ID="com.tcballard.perch"
WIDGET_BUNDLE_ID="com.tcballard.perch.widget"
SIGN_IDENTITY="Developer ID Application: Thomas Ballard ($TEAM_ID)"
EXPORT_OPTIONS="$ROOT_DIR/script/ExportOptions-DeveloperID.plist"
VERSION="0.1.0"
BUILD_NUMBER="7"
NOTARY_PROFILE="PerchNotary"
PREPARE_ONLY=false

usage() {
  cat <<'EOF'
usage: ./script/release.sh [options]

Options:
  --version VERSION          Release version (default: 0.1.0)
  --build NUMBER             Bundle build number (default: 7)
  --notary-profile NAME      notarytool Keychain profile (default: PerchNotary)
  --prepare-only             Build and verify the Developer ID artifact without
                             submitting it to Apple or producing a release ZIP
  -h, --help                 Show this help
EOF
}

while (($#)); do
  case "$1" in
    --version)
      VERSION="${2:?missing value for --version}"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="${2:?missing value for --build}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:?missing value for --notary-profile}"
      shift 2
      ;;
    --prepare-only)
      PREPARE_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "error: invalid version: $VERSION" >&2
  exit 2
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: build number must be a positive integer" >&2
  exit 2
fi

command -v xcodebuild >/dev/null
command -v xcrun >/dev/null
command -v ditto >/dev/null
command -v codesign >/dev/null
command -v spctl >/dev/null

if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
  echo "error: signing identity not found: $SIGN_IDENTITY" >&2
  exit 1
fi

WORK_DIR="$ROOT_DIR/.release/$VERSION-$BUILD_NUMBER"
ARCHIVE_PATH="$WORK_DIR/Perch.xcarchive"
EXPORT_DIR="$WORK_DIR/export"
UPLOAD_ZIP="$WORK_DIR/Perch-$VERSION-notary-upload.zip"
FINAL_ZIP="$ROOT_DIR/dist/Perch-$VERSION.zip"
CHECKSUM="$ROOT_DIR/dist/Perch-$VERSION.sha256"
VERIFY_ROOT="${TMPDIR%/}/PerchReleaseVerify-$VERSION-$BUILD_NUMBER"
UPLOAD_VERIFY_DIR="$VERIFY_ROOT/upload"
FINAL_STAGE_DIR="$VERIFY_ROOT/stage"
VERIFY_DIR="$VERIFY_ROOT/final"

rm -rf "$WORK_DIR" "$VERIFY_ROOT"
mkdir -p "$WORK_DIR" "$EXPORT_DIR" "$ROOT_DIR/dist"
trap 'rm -rf "$VERIFY_ROOT"' EXIT

echo "==> Archiving Perch $VERSION ($BUILD_NUMBER)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

echo "==> Exporting with Developer ID"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

APP="$EXPORT_DIR/Perch.app"
WIDGET="$APP/Contents/PlugIns/PerchWidget.appex"
if [[ ! -d "$APP" || ! -d "$WIDGET" ]]; then
  echo "error: exported host app or widget extension is missing" >&2
  exit 1
fi

assert_bundle_version() {
  local bundle="$1"
  local actual_version
  local actual_build
  actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")"
  actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Contents/Info.plist")"
  if [[ "$actual_version" != "$VERSION" || "$actual_build" != "$BUILD_NUMBER" ]]; then
    echo "error: bundle version mismatch in $bundle: expected $VERSION ($BUILD_NUMBER), got $actual_version ($actual_build)" >&2
    exit 1
  fi
}

assert_bundle_version "$APP"
assert_bundle_version "$WIDGET"

# Cloud-backed Documents folders can attach Finder/File Provider metadata to
# generated bundles. It is not executable content and strict codesign rejects
# it, so remove it before validating or packaging the exported app.
/usr/bin/xattr -cr "$APP"

assert_signature() {
  local bundle="$1"
  local expected_identifier="$2"
  local details
  details="$(codesign -dvvv "$bundle" 2>&1)"
  codesign --verify --deep --strict --verbose=2 "$bundle"
  grep -Fq "Identifier=$expected_identifier" <<<"$details"
  grep -Fq "Authority=$SIGN_IDENTITY" <<<"$details"
  grep -Eq 'flags=.*runtime' <<<"$details"
  grep -Fq 'Timestamp=' <<<"$details"
}

assert_no_debug_entitlement() {
  local bundle="$1"
  local entitlements="$WORK_DIR/$(basename "$bundle").entitlements.plist"
  codesign -d --entitlements :- "$bundle" >"$entitlements" 2>/dev/null
  if [[ -s "$entitlements" ]] && \
     [[ "$(plutil -extract com.apple.security.get-task-allow raw -o - "$entitlements" 2>/dev/null || true)" == "true" ]]; then
    echo "error: release bundle contains com.apple.security.get-task-allow=true: $bundle" >&2
    exit 1
  fi
}

echo "==> Verifying exported signatures and entitlements"
assert_signature "$APP" "$APP_BUNDLE_ID"
assert_signature "$WIDGET" "$WIDGET_BUNDLE_ID"
assert_no_debug_entitlement "$APP"
assert_no_debug_entitlement "$WIDGET"

/usr/bin/ditto -c -k --keepParent "$APP" "$UPLOAD_ZIP"

echo "==> Verifying packaged notarization upload"
rm -rf "$UPLOAD_VERIFY_DIR"
mkdir -p "$UPLOAD_VERIFY_DIR"
/usr/bin/ditto -x -k "$UPLOAD_ZIP" "$UPLOAD_VERIFY_DIR"
PACKAGED_APP="$UPLOAD_VERIFY_DIR/Perch.app"
PACKAGED_WIDGET="$PACKAGED_APP/Contents/PlugIns/PerchWidget.appex"
assert_signature "$PACKAGED_APP" "$APP_BUNDLE_ID"
assert_signature "$PACKAGED_WIDGET" "$WIDGET_BUNDLE_ID"
assert_no_debug_entitlement "$PACKAGED_APP"
assert_no_debug_entitlement "$PACKAGED_WIDGET"

if $PREPARE_ONLY; then
  echo
  echo "Prepared and verified Developer ID artifact:"
  echo "  $UPLOAD_ZIP"
  echo "Notarization was intentionally skipped; this is not a release artifact."
  exit 0
fi

echo "==> Submitting to Apple notarization"
xcrun notarytool submit "$UPLOAD_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling and validating notarization ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

echo "==> Creating final release ZIP"
rm -f "$FINAL_ZIP" "$CHECKSUM"

# The repository lives in a File Provider-backed Documents folder, which can
# reattach Finder metadata after stapling. Stage the accepted app on the local
# volume, remove only extended attributes there, and prove that its signature
# and notarization ticket remain valid before creating the public archive.
rm -rf "$FINAL_STAGE_DIR"
mkdir -p "$FINAL_STAGE_DIR"
/usr/bin/ditto "$APP" "$FINAL_STAGE_DIR/Perch.app"
/usr/bin/xattr -cr "$FINAL_STAGE_DIR/Perch.app"
assert_signature "$FINAL_STAGE_DIR/Perch.app" "$APP_BUNDLE_ID"
xcrun stapler validate "$FINAL_STAGE_DIR/Perch.app"
spctl --assess --type execute --verbose=4 "$FINAL_STAGE_DIR/Perch.app"
/usr/bin/ditto -c -k --keepParent "$FINAL_STAGE_DIR/Perch.app" "$FINAL_ZIP"

rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
/usr/bin/ditto -x -k "$FINAL_ZIP" "$VERIFY_DIR"
EXTRACTED_APP="$VERIFY_DIR/Perch.app"
EXTRACTED_WIDGET="$EXTRACTED_APP/Contents/PlugIns/PerchWidget.appex"
assert_signature "$EXTRACTED_APP" "$APP_BUNDLE_ID"
assert_signature "$EXTRACTED_WIDGET" "$WIDGET_BUNDLE_ID"
assert_no_debug_entitlement "$EXTRACTED_APP"
assert_no_debug_entitlement "$EXTRACTED_WIDGET"
xcrun stapler validate "$EXTRACTED_APP"
spctl --assess --type execute --verbose=4 "$EXTRACTED_APP"

(
  cd "$ROOT_DIR/dist"
  shasum -a 256 "$(basename "$FINAL_ZIP")" >"$(basename "$CHECKSUM")"
)

echo
echo "Release artifacts ready:"
echo "  $FINAL_ZIP"
echo "  $CHECKSUM"
echo "No tag or GitHub release was created."
