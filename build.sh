#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="build/Mergeline.app"
BIN_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$BIN_DIR" "$RES_DIR"

echo "Compiling…"
swiftc -O -swift-version 5 \
  -o "$BIN_DIR/Mergeline" \
  Sources/Model.swift Sources/ContentView.swift Sources/main.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mergeline</string>
  <key>CFBundleDisplayName</key><string>Mergeline</string>
  <key>CFBundleIdentifier</key><string>io.local.mergeline</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Mergeline</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# ad-hoc codesign so macOS is happy launching it
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
