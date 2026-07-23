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
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/DaylineIcon.icns"
ICON_FILE="DaylineIcon.icns"
WORDMARK_SOURCE="$ROOT_DIR/Resources/DaylineWordmark.pdf"
WORDMARK_FILE="DaylineWordmark.pdf"
SPARKLE_FRAMEWORK_NAME="Sparkle.framework"
SPARKLE_PUBLIC_KEY="b7IXyZXo7zqHoVUdwJeOTwxY6gbmJYP/e0NV4i3G/Hk="
SPARKLE_FEED_URL="https://dayline.robin.build/appcast.xml"
DMG_ROOT="$DIST_DIR/dmg-root"
NOTARY_ZIP="$DIST_DIR/$APP_NAME-notary.zip"

INSTALL_APP=false
NOTARIZE=false
PREPARE_NOTARIZATION=false
PACKAGE_EXISTING=false

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
    --prepare-notarization)
      PREPARE_NOTARIZATION=true
      shift
      ;;
    --package-existing)
      PACKAGE_EXISTING=true
      shift
      ;;
    --help|-h)
      cat <<USAGE
usage: $0 [--install] [--notarize] [--prepare-notarization | --package-existing]

Builds a release Dayline.app bundle plus GitHub-release-ready artifacts:
  dist/artifacts/Dayline-<version>.dmg
  dist/artifacts/Dayline-<version>.app.zip

Environment:
  BUNDLE_ID               Bundle identifier. Defaults to $DEFAULT_BUNDLE_ID.
  MARKETING_VERSION       App version. Defaults to the exact HEAD tag or 0.1.0-dev.
  BUILD_NUMBER            Build number. Defaults to git commit count.
  DAYLINE_GOOGLE_CLIENT_ID  Google OAuth client ID embedded in the app.
  DAYLINE_LINEAR_CLIENT_ID  Linear OAuth client ID embedded in the app.
  CODESIGN_IDENTITY       Signing identity. Auto-detects Developer ID, then Apple Development.
  NOTARY_PROFILE          Local notarytool keychain profile.
  NOTARY_KEY_PATH         App Store Connect API key (.p8) for CI notarization.
  NOTARY_KEY_ID           App Store Connect API key ID.
  NOTARY_ISSUER_ID        App Store Connect API issuer ID.

Internal CI stages:
  --prepare-notarization  Build and sign the app, then preserve its notarization ZIP.
  --package-existing      Package an already-notarized app without rebuilding it.
USAGE
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$PREPARE_NOTARIZATION" == true && ( "$NOTARIZE" == true || "$PACKAGE_EXISTING" == true || "$INSTALL_APP" == true ) ]]; then
  echo "--prepare-notarization cannot be combined with other packaging modes." >&2
  exit 2
fi

if [[ "$PACKAGE_EXISTING" == true && ( "$NOTARIZE" == true || "$INSTALL_APP" == true ) ]]; then
  echo "--package-existing cannot be combined with --notarize or --install." >&2
  exit 2
fi

cd "$ROOT_DIR"

# resolve_version prints a stable marketing version for the bundle and artifact names.
resolve_version() {
  if [[ -n "${MARKETING_VERSION:-}" ]]; then
    printf '%s\n' "$MARKETING_VERSION"
    return
  fi

  if git describe --tags --exact-match HEAD >/dev/null 2>&1; then
    git describe --tags --exact-match HEAD | sed 's/^v//'
    return
  fi

  printf '0.1.0-dev\n'
}

# require_distribution_source ensures public artifacts map to one clean tagged commit.
require_distribution_source() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Refusing to notarize from a dirty working tree." >&2
    echo "Commit all release changes first." >&2
    exit 2
  fi

  local exact_tag
  exact_tag="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
  if [[ -z "$exact_tag" ]]; then
    echo "Refusing to notarize an untagged commit." >&2
    echo "Create and push a version tag such as v0.1.4 first." >&2
    exit 2
  fi

  if [[ "$exact_tag" != "v$VERSION" ]]; then
    echo "MARKETING_VERSION ($VERSION) does not match HEAD tag ($exact_tag)." >&2
    exit 2
  fi
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
  # Keep these in sync with AuthConfig / AuthProvider callback schemes.
  local google_client_id="$GOOGLE_CLIENT_ID"
  local google_url_scheme="com.googleusercontent.apps.${google_client_id%.apps.googleusercontent.com}"
  local linear_url_scheme="dayline"

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
  /usr/bin/plutil -insert DaylineGoogleClientID -string "$google_client_id" "$INFO_PLIST"
  /usr/bin/plutil -insert DaylineLinearClientID -string "$LINEAR_CLIENT_ID" "$INFO_PLIST"
  /usr/bin/plutil -insert DaylineLinearCallbackScheme -string "$linear_url_scheme" "$INFO_PLIST"
  /usr/bin/plutil -insert CFBundleURLTypes -json "[{\"CFBundleURLName\":\"$BUNDLE_ID.oauth.linear\",\"CFBundleURLSchemes\":[\"$linear_url_scheme\"]},{\"CFBundleURLName\":\"$BUNDLE_ID.oauth.google\",\"CFBundleURLSchemes\":[\"$google_url_scheme\"]}]" "$INFO_PLIST"
  /usr/bin/plutil -insert LSApplicationCategoryType -string "public.app-category.productivity" "$INFO_PLIST"
  /usr/bin/plutil -insert LSMinimumSystemVersion -string "$MIN_SYSTEM_VERSION" "$INFO_PLIST"
  /usr/bin/plutil -insert LSMultipleInstancesProhibited -bool YES "$INFO_PLIST"
  /usr/bin/plutil -insert LSUIElement -bool YES "$INFO_PLIST"
  /usr/bin/plutil -insert NSPrincipalClass -string "NSApplication" "$INFO_PLIST"
  /usr/bin/plutil -insert SUFeedURL -string "$SPARKLE_FEED_URL" "$INFO_PLIST"
  /usr/bin/plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$INFO_PLIST"
  /usr/bin/plutil -insert SUEnableAutomaticChecks -bool YES "$INFO_PLIST"
  /usr/bin/plutil -insert SUAutomaticallyUpdate -bool YES "$INFO_PLIST"
  /usr/bin/plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$INFO_PLIST"
  /usr/bin/plutil -insert SURequireSignedFeed -bool YES "$INFO_PLIST"
}

# copy_app_icon places the generated icon inside the bundle before signing seals resources.
copy_app_icon() {
  if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing app icon: $ICON_SOURCE" >&2
    exit 2
  fi

  cp "$ICON_SOURCE" "$APP_RESOURCES/$ICON_FILE"
}

# copy_wordmark places the outlined display wordmark inside the bundle.
copy_wordmark() {
  if [[ ! -f "$WORDMARK_SOURCE" ]]; then
    echo "Missing wordmark: $WORDMARK_SOURCE" >&2
    exit 2
  fi

  cp "$WORDMARK_SOURCE" "$APP_RESOURCES/$WORDMARK_FILE"
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

# embed_and_sign_sparkle copies Sparkle's framework without flattening its symlinks,
# removes sandbox-only XPC services, and signs the remaining nested code inside-out.
embed_and_sign_sparkle() {
  local build_dir="$1"
  local source_framework="$build_dir/$SPARKLE_FRAMEWORK_NAME"
  local destination_framework="$APP_FRAMEWORKS/$SPARKLE_FRAMEWORK_NAME"
  local framework_version="$destination_framework/Versions/B"

  if [[ ! -d "$source_framework" ]]; then
    echo "Missing Sparkle framework in SwiftPM build products: $source_framework" >&2
    exit 2
  fi

  mkdir -p "$APP_FRAMEWORKS"
  /usr/bin/ditto "$source_framework" "$destination_framework"

  # Dayline is not sandboxed, so Sparkle documents these XPC services as optional.
  # Keeping only the in-process downloader and installer reduces nested signing surface.
  /bin/rm -rf "$framework_version/XPCServices"
  /bin/rm -rf "$destination_framework/XPCServices"

  sign_path "$framework_version/Autoupdate"
  sign_path "$framework_version/Updater.app"
  sign_path "$destination_framework"

  /usr/bin/codesign --verify --strict --verbose=2 "$framework_version/Autoupdate"
  /usr/bin/codesign --verify --strict --verbose=2 "$framework_version/Updater.app"
  /usr/bin/codesign --verify --strict --verbose=2 "$destination_framework"
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

# Runs notarytool with local or CI credentials.
notarytool_with_credentials() {
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool "$@" --keychain-profile "$NOTARY_PROFILE"
    return
  fi

  if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    xcrun notarytool "$@" \
      --key "$NOTARY_KEY_PATH" \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID"
    return
  fi

  echo "Notarization credentials are required with --notarize." >&2
  echo "Use NOTARY_PROFILE locally, or NOTARY_KEY_PATH/NOTARY_KEY_ID/NOTARY_ISSUER_ID in CI." >&2
  exit 2
}

# Submits once, then polls by ID so temporary status-check outages are retryable.
submit_for_notarization() {
  local path="$1"
  local submission submission_id info status

  if ! submission="$(notarytool_with_credentials submit "$path" --output-format json)"; then
    echo "Notarization submission failed: $submission" >&2
    return 1
  fi
  submission_id="$(/usr/bin/plutil -extract id raw -o - - <<< "$submission" 2>/dev/null || true)"
  if [[ -z "$submission_id" ]]; then
    echo "Could not read notarization submission ID: $submission" >&2
    return 1
  fi
  echo "Notary submission: $submission_id"

  while true; do
    if info="$(notarytool_with_credentials info "$submission_id" --output-format json)"; then
      status="$(/usr/bin/plutil -extract status raw -o - - <<< "$info" 2>/dev/null || true)"
      if [[ -z "$status" ]]; then
        echo "Could not parse notarization status: $info" >&2
        status="Unknown"
      fi
      case "$status" in
        Accepted)
          echo "Notary submission accepted: $submission_id"
          return
          ;;
        Invalid|Rejected)
          echo "Notary submission failed: $submission_id ($status)" >&2
          notarytool_with_credentials log "$submission_id" || true
          return 1
          ;;
        *)
          echo "Notary submission $submission_id: $status"
          ;;
      esac
    else
      echo "Could not check notarization status; retrying in 60 seconds: $info" >&2
    fi
    sleep 60
  done
}

# notarize_app submits a temporary ZIP, then staples the ticket to the app.
notarize_app() {
  rm -f "$NOTARY_ZIP"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
  submit_for_notarization "$NOTARY_ZIP"
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  rm -f "$NOTARY_ZIP"
}

# notarize_dmg submits and staples the final disk image.
notarize_dmg() {
  submit_for_notarization "$DMG_PATH"
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
GOOGLE_CLIENT_ID="${DAYLINE_GOOGLE_CLIENT_ID:-551177930544-9sl0govp6ok205csb939j4p2dhckrgbk.apps.googleusercontent.com}"
LINEAR_CLIENT_ID="${DAYLINE_LINEAR_CLIENT_ID:-00c88957100199ecb91362294a3f6e55}"
VERSION="$(resolve_version)"
BUILD_NUMBER_RESOLVED="$(resolve_build_number)"
SIGNING_IDENTITY="$(detect_codesign_identity)"
ARTIFACT_BASE="$APP_NAME-$VERSION"
DMG_PATH="$ARTIFACT_DIR/$ARTIFACT_BASE.dmg"
ZIP_PATH="$ARTIFACT_DIR/$ARTIFACT_BASE.app.zip"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && ! ( "$NOTARIZE" == false && "$VERSION" == "0.1.0-dev" ) ]]; then
  echo "Invalid MARKETING_VERSION: $VERSION" >&2
  exit 2
fi

if [[ "$NOTARIZE" == true || "$PREPARE_NOTARIZATION" == true ]]; then
  require_distribution_source
  if [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
    echo "Notarization requires a Developer ID Application certificate." >&2
    exit 2
  fi
fi

if [[ "$PACKAGE_EXISTING" == true ]]; then
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Missing preserved app bundle: $APP_BUNDLE" >&2
    exit 2
  fi
  if [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
    echo "Packaging the notarized app requires a Developer ID Application certificate for the DMG." >&2
    exit 2
  fi

  app_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$app_version" != "$VERSION" ]]; then
    echo "Preserved app version ($app_version) does not match MARKETING_VERSION ($VERSION)." >&2
    exit 2
  fi

  /usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  rm -rf "$ARTIFACT_DIR"
  mkdir -p "$ARTIFACT_DIR"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  create_dmg

  cat <<SUMMARY
Packaged preserved $APP_BUNDLE
Created $DMG_PATH
Created $ZIP_PATH
SUMMARY
  exit 0
fi

rm -rf "$RELEASE_DIR" "$ARTIFACT_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS" "$ARTIFACT_DIR"

swift build -c release
BUILD_PRODUCTS="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BUILD_PRODUCTS/$APP_NAME"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

write_info_plist
copy_app_icon
copy_wordmark
embed_and_sign_sparkle "$BUILD_PRODUCTS"
sign_path "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$PREPARE_NOTARIZATION" == true ]]; then
  rm -f "$NOTARY_ZIP"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
  echo "Prepared signed app for asynchronous notarization: $NOTARY_ZIP"
  exit 0
fi

if [[ "$NOTARIZE" == true ]]; then
  notarize_app
fi

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
