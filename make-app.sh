#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds Oopsie.app into ./build. Usage: ./make-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

echo "🔨 Building Oopsie…"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Oopsie"

APP="build/Oopsie.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Oopsie"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "🎨 Making the icon…"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP" >/dev/null
echo "💥 Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Oopsie.app
  cp -R "$APP" /Applications/
  echo "📦 Installed to /Applications/Oopsie.app"
  open /Applications/Oopsie.app
fi
