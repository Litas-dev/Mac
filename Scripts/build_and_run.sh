#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Kivana"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
DERIVED="$PROJECT_DIR/build/DerivedData"

cd "$PROJECT_DIR"

if [ -f "$PROJECT_DIR/Package.swift" ]; then
  echo "› Building with Swift Package Manager"
  export SWIFTPM_DISABLE_SANDBOX=1
  UNIVERSAL="${UNIVERSAL:-1}"
  if [ "$UNIVERSAL" = "1" ]; then
    echo "› Building universal (arm64 + x86_64)"
    swift build -c debug --arch arm64
    ARM_BIN_DIR="$(swift build -c debug --arch arm64 --show-bin-path)"
    swift build -c debug --arch x86_64
    X86_BIN_DIR="$(swift build -c debug --arch x86_64 --show-bin-path)"
    ARM_BIN="$ARM_BIN_DIR/$APP_NAME"
    X86_BIN="$X86_BIN_DIR/$APP_NAME"
    if [ ! -f "$ARM_BIN" ]; then ARM_BIN="$ARM_BIN_DIR/PersonalFinances"; fi
    if [ ! -f "$ARM_BIN" ]; then ARM_BIN="$ARM_BIN_DIR/PersonalFinancesApp"; fi
    if [ ! -f "$X86_BIN" ]; then X86_BIN="$X86_BIN_DIR/PersonalFinances"; fi
    if [ ! -f "$X86_BIN" ]; then X86_BIN="$X86_BIN_DIR/PersonalFinancesApp"; fi
    UNIVERSAL_BIN="$PROJECT_DIR/.build/debug/$APP_NAME"
    mkdir -p "$(dirname "$UNIVERSAL_BIN")"
    ARM_ARCHS="$(lipo -info "$ARM_BIN" 2>/dev/null | sed -E 's/.*are: //; s/.*architecture: //' | xargs || true)"
    X86_ARCHS="$(lipo -info "$X86_BIN" 2>/dev/null | sed -E 's/.*are: //; s/.*architecture: //' | xargs || true)"
    if [[ "$ARM_ARCHS" == *"arm64"* && "$ARM_ARCHS" == *"x86_64"* ]]; then
      BIN="$ARM_BIN"
    elif [[ "$X86_ARCHS" == *"arm64"* && "$X86_ARCHS" == *"x86_64"* ]]; then
      BIN="$X86_BIN"
    elif [ -n "$ARM_ARCHS" ] && [ -n "$X86_ARCHS" ] && [ "$ARM_ARCHS" != "$X86_ARCHS" ]; then
      ARM_INPUT="$ARM_BIN"
      X86_INPUT="$X86_BIN"
      TMP_DIR="$PROJECT_DIR/.build/tmp-universal"
      mkdir -p "$TMP_DIR"
      if [[ "$ARM_ARCHS" == *" "* ]]; then
        ARM_INPUT="$TMP_DIR/$APP_NAME-arm64"
        lipo -thin arm64 "$ARM_BIN" -output "$ARM_INPUT"
      fi
      if [[ "$X86_ARCHS" == *" "* ]]; then
        X86_INPUT="$TMP_DIR/$APP_NAME-x86_64"
        lipo -thin x86_64 "$X86_BIN" -output "$X86_INPUT"
      fi
      lipo -create "$ARM_INPUT" "$X86_INPUT" -output "$UNIVERSAL_BIN"
      BIN="$UNIVERSAL_BIN"
    else
      echo "› Universal build not available (falling back to single-arch: $ARM_ARCHS)"
      BIN="$ARM_BIN"
    fi
  else
    swift build -c debug
    BIN="$PROJECT_DIR/.build/debug/$APP_NAME"
    if [ ! -f "$BIN" ]; then
      BIN="$PROJECT_DIR/.build/debug/PersonalFinances"
    fi
    if [ ! -f "$BIN" ]; then
      BIN="$PROJECT_DIR/.build/debug/PersonalFinancesApp"
    fi
  fi
  osascript -e 'tell application "Kivana" to quit' >/dev/null 2>&1 || true
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
  SCHEME_NAME="${SCHEME_NAME:-Kivana}"
  XCODEPROJ="$PROJECT_DIR/Kivana.xcodeproj"
  if [ ! -d "$XCODEPROJ" ]; then
    XCODEPROJ="$PROJECT_DIR/PersonalFinances.xcodeproj"
  fi
  xcodebuild -project "$XCODEPROJ" \
    -scheme "$SCHEME_NAME" -configuration Debug \
    -derivedDataPath "$DERIVED" -destination 'platform=macOS' \
    build | grep -E '^\*\*|error:|warning:' || true

  PRODUCT="$DERIVED/Build/Products/Debug/$APP_NAME.app"
  if [ ! -d "$PRODUCT" ]; then
    PRODUCT="$DERIVED/Build/Products/Debug/$SCHEME_NAME.app"
  fi
  if [ ! -d "$PRODUCT" ]; then
    echo "Build did not produce $PRODUCT" >&2
    exit 1
  fi

  osascript -e 'tell application "Kivana" to quit' >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "$APP_BUNDLE"
  cp -R "$PRODUCT" "$APP_BUNDLE"
  echo "› Launching"
  open "$APP_BUNDLE"
  echo "Done."
fi
