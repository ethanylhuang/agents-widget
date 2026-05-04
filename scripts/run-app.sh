#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/Agents Widget.app"

"$ROOT_DIR/scripts/build-app.sh"
open "$APP_PATH"
