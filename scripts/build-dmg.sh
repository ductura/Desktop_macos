#!/usr/bin/env bash
# Izrada Ductura.app i dist/Ductura-macOS.dmg (univerzalni binarni: Apple Silicon + Intel).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Ductura"

APP=build/Ductura.app
rm -rf build dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist
cp "$BIN" "$APP/Contents/MacOS/Ductura"
sed "s/__VERSION__/$VERSION/g" packaging/Info.plist > "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"   # ad-hoc potpis; za izdanje treba Developer ID i notarizacija

STAGE=build/dmg && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Ductura -srcfolder "$STAGE" -ov -format UDZO dist/Ductura-macOS.dmg
echo "dist/Ductura-macOS.dmg"
