#!/usr/bin/env bash
# Builds TrustMe.app (the demo) into ./build. A real .app bundle is required: the
# drag-to-authorize flow drags this bundle into System Settings.
#
#   Scripts/build-demo.sh            # build
#   Scripts/build-demo.sh --open     # build and launch
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Named after the display name: System Settings lists apps by bundle file name,
# and the guide band must match what the user sees in the list.
APP="$ROOT/build/TrustMe.app"
BUNDLE_ID="com.trustme.demo"

cd "$ROOT"
swift build -c release --product TrustMeDemo
BIN="$(swift build -c release --show-bin-path)/TrustMeDemo"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TrustMeDemo"

ICONSET="$ROOT/build/AppIcon.iconset"
if [[ ! -f "$ROOT/build/AppIcon.icns" ]]; then
  swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"
  rm -rf "$ICONSET"
fi
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>TrustMe</string>
  <key>CFBundleDisplayName</key><string>TrustMe</string>
  <key>CFBundleExecutable</key><string>TrustMeDemo</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSCameraUsageDescription</key><string>TrustMe shows your camera in recordings and calls.</string>
  <key>NSMicrophoneUsageDescription</key><string>TrustMe records your voice in recordings and calls.</string>
</dict>
</plist>
PLIST

# TCC ties grants to the code signature. An ad-hoc signature changes on every
# build, so a grant made for one build silently stops matching the next. Prefer
# a real identity (override with CODESIGN_IDENTITY); fall back to ad-hoc.
# (`|| true`: with no identities grep fails, which pipefail would turn fatal.)
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)}"
codesign --force --deep --sign "${IDENTITY:--}" --identifier "$BUNDLE_ID" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc (grants reset on every rebuild)}"

echo "Built $APP"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
