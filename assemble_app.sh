#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building Echo in release configuration..."
swift build -c release

echo "==> Assembling Echo.app bundle..."
mkdir -p Echo.app/Contents/MacOS Echo.app/Contents/Resources

cp .build/release/Echo Echo.app/Contents/MacOS/Echo
chmod +x Echo.app/Contents/MacOS/Echo
cp Info.plist Echo.app/Contents/Info.plist
cp AppIcon.icns Echo.app/Contents/Resources/AppIcon.icns

echo "==> Ad-hoc code signing Echo.app..."
codesign --force --deep --sign - --identifier com.ragavij.echo Echo.app

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 Echo.app

echo "==> Running self-test..."
./Echo.app/Contents/MacOS/Echo --test

echo "==> Echo.app successfully assembled and verified!"
