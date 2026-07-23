#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Rebuilds and launches the mock app with a meeting alert firing immediately,
# so the full-screen meeting overlay can be tested on demand.
exec "$ROOT_DIR/script/build_mock_and_run.sh" --mock-meeting-alert
