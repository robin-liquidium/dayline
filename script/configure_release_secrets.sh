#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_KEY_ACCOUNT="dayline"
SPARKLE_KEY_TOOL="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
SPARKLE_KEY_TEMP_DIR=""

cleanup() {
  if [[ -n "$SPARKLE_KEY_TEMP_DIR" && -d "$SPARKLE_KEY_TEMP_DIR" ]]; then
    /bin/rm -rf "$SPARKLE_KEY_TEMP_DIR"
  fi
}

trap cleanup EXIT

cd "$ROOT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required." >&2
  exit 2
fi

gh auth status >/dev/null
REPOSITORY="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

read -r -p "Path to Developer ID Application .p12: " certificate_path
if [[ ! -f "$certificate_path" ]]; then
  echo "Certificate not found: $certificate_path" >&2
  exit 2
fi

read -r -s -p "Password for the .p12: " certificate_password
printf '\n'

read -r -p "Path to App Store Connect API key .p8: " api_key_path
if [[ ! -f "$api_key_path" ]]; then
  echo "API key not found: $api_key_path" >&2
  exit 2
fi

read -r -p "App Store Connect API key ID: " api_key_id
read -r -p "App Store Connect issuer ID: " issuer_id

if [[ -z "$certificate_password" || -z "$api_key_id" || -z "$issuer_id" ]]; then
  echo "Certificate password, key ID, and issuer ID are required." >&2
  exit 2
fi

if [[ ! -x "$SPARKLE_KEY_TOOL" ]]; then
  echo "Resolving Sparkle's signing tools..."
  swift build >/dev/null
fi

if ! "$SPARKLE_KEY_TOOL" --account "$SPARKLE_KEY_ACCOUNT" -p >/dev/null 2>&1; then
  echo "No Sparkle key exists in the macOS Keychain for account $SPARKLE_KEY_ACCOUNT." >&2
  echo "Generate or import it with:" >&2
  echo "  $SPARKLE_KEY_TOOL --account $SPARKLE_KEY_ACCOUNT" >&2
  exit 2
fi

SPARKLE_KEY_TEMP_DIR="$(mktemp -d /tmp/dayline-sparkle-secret.XXXXXX)"
sparkle_private_key_path="$SPARKLE_KEY_TEMP_DIR/private-key"
"$SPARKLE_KEY_TOOL" --account "$SPARKLE_KEY_ACCOUNT" -x "$sparkle_private_key_path"
chmod 600 "$sparkle_private_key_path"

echo "Uploading encrypted repository secrets..."
/usr/bin/base64 < "$certificate_path" | tr -d '\n\r' | gh secret set MACOS_CERTIFICATE_P12_BASE64 --repo "$REPOSITORY"
printf '%s' "$certificate_password" | gh secret set MACOS_CERTIFICATE_PASSWORD --repo "$REPOSITORY"
/usr/bin/base64 < "$api_key_path" | tr -d '\n\r' | gh secret set APP_STORE_CONNECT_KEY_P8_BASE64 --repo "$REPOSITORY"
printf '%s' "$api_key_id" | gh secret set APP_STORE_CONNECT_KEY_ID --repo "$REPOSITORY"
printf '%s' "$issuer_id" | gh secret set APP_STORE_CONNECT_ISSUER_ID --repo "$REPOSITORY"
gh secret set DAYLINE_SPARKLE_PRIVATE_KEY --repo "$REPOSITORY" < "$sparkle_private_key_path"

echo
echo "Release secrets configured for $REPOSITORY."
echo "They are stored by GitHub Actions and were not written into this repository."
