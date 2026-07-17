#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Perch"
BUNDLE_ID="com.tcballard.perch"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${PERCH_DERIVED_DATA:-${TMPDIR%/}/PerchDerivedData}"
BUILT_APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
BUILT_WIDGET_BUNDLE="$BUILT_APP_BUNDLE/Contents/PlugIns/PerchWidget.appex"
INSTALLED_APP_BUNDLE="${PERCH_INSTALL_APP:-/Applications/$APP_NAME.app}"
INSTALLED_WIDGET_BUNDLE="$INSTALLED_APP_BUNDLE/Contents/PlugIns/PerchWidget.appex"
APP_BINARY="$INSTALLED_APP_BUNDLE/Contents/MacOS/$APP_NAME"
APP_ENTITLEMENTS="$ROOT_DIR/Sources/Perch/Perch.entitlements"
WIDGET_ENTITLEMENTS="$ROOT_DIR/Sources/PerchWidget/PerchWidget.entitlements"
SIGN_IDENTITY="${PERCH_SIGN_IDENTITY:-Developer ID Application: Thomas Ballard (R8HXTBY3NM)}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x PerchWidget >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/Perch.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

# Cloud-backed Documents folders can attach Finder/File Provider metadata to
# generated bundles. It is not executable content and codesign rejects it.
/usr/bin/xattr -cr "$BUILT_APP_BUNDLE"

sign_mach_o_directory() {
  local directory="$1"
  local candidate
  for candidate in "$directory"/*.dylib; do
    [[ -e "$candidate" ]] || continue
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$candidate"
  done
}

# WidgetKit requires a signed host and extension even for local development.
# Signing the generated bundle directly avoids development-device provisioning
# while preserving the Team Identifier required by the macOS shared container.
sign_mach_o_directory "$BUILT_WIDGET_BUNDLE/Contents/MacOS"
/usr/bin/codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  --timestamp=none \
  --entitlements "$WIDGET_ENTITLEMENTS" \
  "$BUILT_WIDGET_BUNDLE"
sign_mach_o_directory "$BUILT_APP_BUNDLE/Contents/MacOS"
/usr/bin/codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  --timestamp=none \
  --entitlements "$APP_ENTITLEMENTS" \
  "$BUILT_APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$BUILT_APP_BUNDLE"

# WidgetKit may keep launching an older development copy when several bundles
# with the same identifier have been registered. Install and register one
# stable bundle so the host app and extension always share the same snapshot.
/usr/bin/ditto "$BUILT_APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
/usr/bin/xattr -cr "$INSTALLED_APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$INSTALLED_APP_BUNDLE"
"$LSREGISTER" -f -R -trusted "$INSTALLED_APP_BUNDLE"
/usr/bin/pluginkit -a "$INSTALLED_WIDGET_BUNDLE"

STALE_APP_BUNDLE="$ROOT_DIR/DerivedData/Build/Products/Debug/$APP_NAME.app"
if [[ -e "$STALE_APP_BUNDLE" && "$STALE_APP_BUNDLE" != "$INSTALLED_APP_BUNDLE" ]]; then
  "$LSREGISTER" -u "$STALE_APP_BUNDLE" >/dev/null 2>&1 || true
fi

open_app() {
  /usr/bin/open -n "$INSTALLED_APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
