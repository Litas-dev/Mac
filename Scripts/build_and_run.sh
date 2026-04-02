#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PersonalFinances"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
DERIVED="$PROJECT_DIR/build/DerivedData"

cd "$PROJECT_DIR"

if [ -f "$PROJECT_DIR/Package.swift" ]; then
  echo "› Building with Swift Package Manager"
  export SWIFTPM_DISABLE_SANDBOX=1
  swift build -c debug
  BIN="$PROJECT_DIR/.build/debug/$APP_NAME"
  if [ ! -f "$BIN" ]; then
    BIN="$PROJECT_DIR/.build/debug/PersonalFinancesApp"
  fi
  osascript -e 'tell application "PersonalFinances" to quit' >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  echo "› Creating app bundle at $APP_BUNDLE"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
  PLIST_SRC="$PROJECT_DIR/Sources/PersonalFinancesApp/Info.plist"
  PLIST_DST="$APP_BUNDLE/Contents/Info.plist"
  cp "$PLIST_SRC" "$PLIST_DST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$PLIST_DST" \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$PLIST_DST" || true
  cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  RES_SRC="$PROJECT_DIR/Sources/PersonalFinancesApp/Resources"
  if [ -d "$RES_SRC" ]; then
    cp -R "$RES_SRC/." "$APP_BUNDLE/Contents/Resources/"
  fi
  codesign --force --deep --sign - "$APP_BUNDLE" || true
  echo "› Launching"
  open "$APP_BUNDLE"
  echo "Done."
else
  echo "› Building with Xcode"
  xcodebuild -project "$PROJECT_DIR/PersonalFinances.xcodeproj" \
    -scheme "$APP_NAME" -configuration Debug \
    -derivedDataPath "$DERIVED" -destination 'platform=macOS' \
    build | grep -E '^\*\*|error:|warning:' || true

  PRODUCT="$DERIVED/Build/Products/Debug/$APP_NAME.app"
  if [ ! -d "$PRODUCT" ]; then
    echo "Build did not produce $PRODUCT" >&2
    exit 1
  fi

  osascript -e 'tell application "PersonalFinances" to quit' >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "$APP_BUNDLE"
  cp -R "$PRODUCT" "$APP_BUNDLE"
  echo "› Launching"
  open "$APP_BUNDLE"
  echo "Done."
fi
