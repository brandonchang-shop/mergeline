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

# NOTE: do NOT codesign here. Santa runs in Lockdown with Transitive Allowlisting,
# so binaries written by the allowlisted `swiftc` compiler are auto-allowed by hash.
# Running `codesign` after swiftc rewrites the binary and changes its hash, which
# invalidates the transitive rule and gets the app blocked (AMFI -423 / Rule: None).

echo "Built $APP"
