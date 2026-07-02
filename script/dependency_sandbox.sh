#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dayline"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="${1:-unauthenticated}"
TMP_DIR="$(mktemp -d -t dayline-deps.XXXXXX)"

usage() {
  cat >&2 <<USAGE
usage: $0 <scenario>

Scenarios:
  missing          Both CLI paths point to missing files.
  unauthenticated Both fake CLIs exist but auth probes fail.
  ready           Both fake CLIs exist, auth probes pass, and data is empty.
  gws-missing     gws is missing; linear is ready.
  linear-missing  linear is missing; gws is ready.
USAGE
}

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

cd "$ROOT_DIR"

make_fake_gws() {
  local path="$1"
  local mode="$2"

  cat >"$path" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

MODE="${DAYLINE_FAKE_MODE:-ready}"
COMMAND="${1:-} ${2:-}"

if [[ "$COMMAND" == "auth status" ]]; then
  if [[ "$MODE" == "ready" ]]; then
    echo '{"user":"fake@example.com","token_valid":true}'
    exit 0
  fi
  echo "Fake gws is not authenticated." >&2
  exit 2
fi

if [[ "$COMMAND" == "auth login" ]]; then
  echo "Fake gws auth login. No real credentials were touched."
  exit 0
fi

if [[ "$1" == "calendar" ]]; then
  if [[ "$MODE" == "ready" ]]; then
    echo '{"items":[]}'
    exit 0
  fi
  echo "Fake gws calendar call blocked because auth is missing." >&2
  exit 2
fi

echo "Fake gws received: $*" >&2
exit 0
SCRIPT

  chmod +x "$path"
  DAYLINE_FAKE_MODE="$mode" "$path" auth status >/dev/null 2>&1 || true
}

make_fake_linear() {
  local path="$1"
  local mode="$2"

  cat >"$path" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

MODE="${DAYLINE_FAKE_MODE:-ready}"
COMMAND="${1:-} ${2:-}"

if [[ "$COMMAND" == "auth whoami" ]]; then
  if [[ "$MODE" == "ready" ]]; then
    echo "User: Fake User"
    exit 0
  fi
  echo "Fake linear is not authenticated." >&2
  exit 1
fi

if [[ "$COMMAND" == "auth login" ]]; then
  echo "Fake linear auth login. No real credentials were touched."
  exit 0
fi

if [[ "$1" == "api" ]]; then
  if [[ "$MODE" == "ready" ]]; then
    echo '{"data":{"viewer":{"assignedIssues":{"nodes":[]}}}}'
    exit 0
  fi
  echo "Fake linear API call blocked because auth is missing." >&2
  exit 1
fi

echo "Fake linear received: $*" >&2
exit 0
SCRIPT

  chmod +x "$path"
  DAYLINE_FAKE_MODE="$mode" "$path" auth whoami >/dev/null 2>&1 || true
}

GWS_PATH="$TMP_DIR/gws"
LINEAR_PATH="$TMP_DIR/linear"
GWS_MODE="ready"
LINEAR_MODE="ready"

case "$SCENARIO" in
  missing)
    GWS_PATH="$TMP_DIR/missing-gws"
    LINEAR_PATH="$TMP_DIR/missing-linear"
    ;;
  unauthenticated)
    GWS_MODE="unauthenticated"
    LINEAR_MODE="unauthenticated"
    make_fake_gws "$GWS_PATH" "$GWS_MODE"
    make_fake_linear "$LINEAR_PATH" "$LINEAR_MODE"
    ;;
  ready)
    make_fake_gws "$GWS_PATH" "$GWS_MODE"
    make_fake_linear "$LINEAR_PATH" "$LINEAR_MODE"
    ;;
  gws-missing)
    GWS_PATH="$TMP_DIR/missing-gws"
    make_fake_linear "$LINEAR_PATH" "$LINEAR_MODE"
    ;;
  linear-missing)
    LINEAR_PATH="$TMP_DIR/missing-linear"
    make_fake_gws "$GWS_PATH" "$GWS_MODE"
    ;;
  *)
    usage
    exit 2
    ;;
esac

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

echo "Launching $APP_NAME with fake dependency scenario: $SCENARIO"
echo "DAYLINE_GWS_PATH=$GWS_PATH"
echo "DAYLINE_LINEAR_PATH=$LINEAR_PATH"
echo
echo "Quit $APP_NAME or press Ctrl-C here to end the sandbox run."

DAYLINE_GWS_PATH="$GWS_PATH" \
DAYLINE_LINEAR_PATH="$LINEAR_PATH" \
DAYLINE_GWS_INSTALL_COMMAND="echo Fake gws install. No real packages were installed." \
DAYLINE_LINEAR_INSTALL_COMMAND="echo Fake linear install. No real packages were installed." \
DAYLINE_FAKE_MODE="$GWS_MODE" \
"$BUILD_BINARY"
