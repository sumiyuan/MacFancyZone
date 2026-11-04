#!/bin/bash
# Builds build/MacPowertools.app and signs it with the local signing identity.
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="MacPowertools Local Signing"
BUNDLE_ID="com.sumiyuan.MacPowertools"
APP="build/MacPowertools.app"

if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "error: signing identity \"$IDENTITY\" not found." >&2
    echo "Run scripts/create-signing-cert.sh once to create it." >&2
    exit 1
fi

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/MacPowertools" "$APP/Contents/MacOS/MacPowertools"
cp packaging/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
