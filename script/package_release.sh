#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dayline"
DEFAULT_BUNDLE_ID="de.obermaier.dayline"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
ARTIFACT_DIR="$DIST_DIR/artifacts"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/DaylineIcon.icns"
ICON_FILE="DaylineIcon.icns"
DMG_ROOT="$DIST_DIR/dmg-root"

INSTALL_APP=false
NOTARIZE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL_APP=true
      shift
      ;;
    --notarize)
      NOTARIZE=true
      shift
      ;;
    --help|-h)
      cat <<USAGE
usage: $0 [--install] [--notarize]

Builds a release Dayline.app bundle plus GitHub-release-ready artifacts:
  dist/artifacts/Dayline-<version>.dmg
  dist/artifacts/Dayline-<version>.app.zip

Environment:
  BUNDLE_ID               Bundle identifier. Defaults to $DEFAULT_BUNDLE_ID.
  MARKETING_VERSION       App version. Defaults to latest git tag or 0.1.0.
  BUILD_NUMBER            Build number. Defaults to git commit count.
  CODESIGN_IDENTITY       Signing identity. Auto-detects Developer ID, then Apple Development.
  NOTARY_PROFILE          notarytool keychain profile, required with --notarize.
USAGE
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

# resolve_version prints a stable marketing version for the bundle and artifact names.
resolve_version() {
  if [[ -n "${MARKETING_VERSION:-}" ]]; then
    printf '%s\n' "$MARKETING_VERSION"
    return
  fi

  if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    git describe --tags --abbrev=0 | sed 's/^v//'
    return
  fi

  printf '0.1.0\n'
}

# resolve_build_number prints a monotonically increasing build number when git is available.
resolve_build_number() {
  if [[ -n "${BUILD_NUMBER:-}" ]]; then
    printf '%s\n' "$BUILD_NUMBER"
    return
  fi

  if git rev-list --count HEAD >/dev/null 2>&1; then
    git rev-list --count HEAD
    return
  fi

  date +%Y%m%d%H%M
}

# detect_codesign_identity prefers public distribution signing, then local development signing.
detect_codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODESIGN_IDENTITY"
    return
  fi

  local identities developer_id apple_development
  identities="$(security find-identity -p codesigning -v 2>/dev/null || true)"
  developer_id="$(printf '%s\n' "$identities" | awk -F '"' '/"Developer ID Application:/ { print $2; exit }')"
  apple_development="$(printf '%s\n' "$identities" | awk -F '"' '/"Apple Development:/ { print $2; exit }')"

  if [[ -n "$developer_id" ]]; then
    printf '%s\n' "$developer_id"
  elif [[ -n "$apple_development" ]]; then
    printf '%s\n' "$apple_development"
  else
    printf '%s\n' "-"
  fi
}

# write_info_plist creates the minimal menu-bar app metadata macOS expects.
write_info_plist() {
  /usr/bin/plutil -create xml1 "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleDevelopmentRegion -string "en" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleDisplayName -string "$APP_NAME" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleExecutable -string "$APP_NAME" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleIconFile -string "$ICON_FILE" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleName -string "$APP_NAME" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleVersion -string "$BUILD_NUMBER_RESOLVED" "$INFO_PLIST"
  /usr/bin/plutil -insert LSApplicationCategoryType -string "public.app-category.productivity" "$INFO_PLIST"
  /usr/bin/plutil -insert LSMinimumSystemVersion -string "$MIN_SYSTEM_VERSION" "$INFO_PLIST"
  /usr/bin/plutil -insert LSUIElement -bool YES "$INFO_PLIST"
  /usr/bin/plutil -insert NSPrincipalClass -string "NSApplication" "$INFO_PLIST"
}

# copy_app_icon places the generated icon inside the bundle before signing seals resources.
copy_app_icon() {
  if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing app icon: $ICON_SOURCE" >&2
    exit 2
  fi

  cp "$ICON_SOURCE" "$APP_RESOURCES/$ICON_FILE"
}

# sign_path applies hardened runtime signing when a certificate is available.
sign_path() {
  local path="$1"

  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --options runtime --sign - "$path"
  else
    /usr/bin/codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$path"
  fi
}

# create_dmg builds the drag-install disk image used for GitHub releases.
create_dmg() {
  rm -rf "$DMG_ROOT"
  mkdir -p "$DMG_ROOT"
  /usr/bin/ditto "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
  ln -s /Applications "$DMG_ROOT/Applications"
  rm -f "$DMG_PATH"
  /usr/sbin/diskutil image create from --format UDZO --volumeName "$APP_NAME" "$DMG_ROOT" "$DMG_PATH"
  rm -rf "$DMG_ROOT"

  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    /usr/bin/codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
  fi
}

# notarize_dmg submits and staples the DMG when Apple notary credentials exist.
notarize_dmg() {
  if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    echo "NOTARY_PROFILE is required when using --notarize." >&2
    echo "Create one with: xcrun notarytool store-credentials <profile-name>" >&2
    exit 2
  fi

  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
}

# install_app copies the signed app bundle into /Applications for normal LaunchServices use.
install_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "/Applications/$APP_NAME.app"
  /usr/bin/ditto "$APP_BUNDLE" "/Applications/$APP_NAME.app"
  /usr/bin/open -n "/Applications/$APP_NAME.app"
}

BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
VERSION="$(resolve_version)"
BUILD_NUMBER_RESOLVED="$(resolve_build_number)"
SIGNING_IDENTITY="$(detect_codesign_identity)"
ARTIFACT_BASE="$APP_NAME-$VERSION"
DMG_PATH="$ARTIFACT_DIR/$ARTIFACT_BASE.dmg"
ZIP_PATH="$ARTIFACT_DIR/$ARTIFACT_BASE.app.zip"

rm -rf "$RELEASE_DIR" "$ARTIFACT_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$ARTIFACT_DIR"

swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

write_info_plist
copy_app_icon
sign_path "$APP_BUNDLE"
/usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
create_dmg

if [[ "$NOTARIZE" == true ]]; then
  notarize_dmg
fi

if [[ "$INSTALL_APP" == true ]]; then
  install_app
fi

cat <<SUMMARY
Built $APP_BUNDLE
Signed with: $SIGNING_IDENTITY
Created $DMG_PATH
Created $ZIP_PATH
SUMMARY

if [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  cat <<WARNING

Warning: this is not signed with a Developer ID Application certificate.
It is fine for this Mac, but public GitHub releases should use Developer ID signing plus notarization.
WARNING
fi
