#!/bin/zsh
# Build Vello, install to /Applications and launch it.
set -e
cd "$(dirname "$0")/.."
xcodegen -q
xcodebuild -project Vello.xcodeproj -scheme Vello -configuration Release -derivedDataPath build -quiet build
pkill -x Vello 2>/dev/null || true
rm -rf /Applications/Vello.app
ditto build/Build/Products/Release/Vello.app /Applications/Vello.app
open /Applications/Vello.app
echo "Vello is running (menu bar)."
