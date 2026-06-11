#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [version]" >&2
  exit 1
fi

if [[ -n "$VERSION" ]]; then
  DIST_DIR="$ROOT_DIR/dist/$VERSION"
else
  DIST_DIR="$ROOT_DIR/dist"
fi

APP_DIR="$DIST_DIR/Token Meter.app"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/TokenMeter" "$APP_DIR/Contents/MacOS/TokenMeter"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/TokenMeter"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
