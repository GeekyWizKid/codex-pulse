#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodexPulse"
BUNDLE_ID="com.codexpulse.monitor"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf -- "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
# File Provider may restore an empty FinderInfo xattr as soon as the .app
# directory appears. It is not executable content, but strict code-signing
# validation rejects it, so remove that metadata once more after signing.
/usr/bin/xattr -d com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build|build)
    ;;
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
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not remain running" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [--build|run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
