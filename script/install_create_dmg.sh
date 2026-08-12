#!/usr/bin/env bash
set -euo pipefail

VERSION="1.3.0"
ARCHIVE_SHA256="c50d2bc97c3d6292642bac55f530d247eaf4bf65ee605f26b4caf339383e381c"
INSTALL_DIR="${1:?usage: install_create_dmg.sh <install-directory>}"
ARCHIVE="$INSTALL_DIR/create-dmg.tar.gz"

mkdir -p "$INSTALL_DIR"
curl --fail --location --proto '=https' --tlsv1.2 \
  "https://github.com/create-dmg/create-dmg/archive/refs/tags/v$VERSION.tar.gz" \
  --output "$ARCHIVE"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$ARCHIVE" | shasum -a 256 --check >&2
tar -xzf "$ARCHIVE" --strip-components=1 --directory "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/create-dmg"
printf '%s\n' "$INSTALL_DIR/create-dmg"
