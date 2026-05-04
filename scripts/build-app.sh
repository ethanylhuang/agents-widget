#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Agents Widget.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c debug --product agents-widget

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/.build/debug/agents-widget" "$MACOS_DIR/agents-widget"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/agents-widget"

echo "$APP_DIR"
