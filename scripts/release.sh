#!/bin/zsh
# Build a notarized Vello-<version>.dmg for GitHub Releases.
# One-time: xcrun notarytool store-credentials vello --apple-id <apple-id> --team-id 5JMBLLG6WT
# Usage: scripts/release.sh 0.1.0
set -e
VERSION=${1:?usage: scripts/release.sh <version>}
cd "$(dirname "$0")/.."
OUT=build/release
rm -rf $OUT && mkdir -p $OUT/dmg

xcodegen -q
xcodebuild -project Vello.xcodeproj -scheme Vello -configuration Release -derivedDataPath build/release-dd -quiet \
  CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS=--timestamp \
  MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$VERSION build
ditto build/release-dd/Build/Products/Release/Vello.app $OUT/dmg/Vello.app
codesign --verify --deep --strict $OUT/dmg/Vello.app

ln -s /Applications $OUT/dmg/Applications
hdiutil create -volname Vello -srcfolder $OUT/dmg -ov -format UDZO $OUT/Vello-$VERSION.dmg -quiet
codesign --sign "Developer ID Application" --timestamp $OUT/Vello-$VERSION.dmg

xcrun notarytool submit $OUT/Vello-$VERSION.dmg --keychain-profile vello --wait
xcrun stapler staple $OUT/Vello-$VERSION.dmg
spctl --assess --type open --context context:primary-signature -v $OUT/Vello-$VERSION.dmg
echo "Done: $OUT/Vello-$VERSION.dmg"
