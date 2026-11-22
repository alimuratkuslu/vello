#!/bin/zsh
# Build a notarized Vello-<version>.dmg, publish it with a Sparkle appcast on GitHub Releases,
# and bump the Homebrew cask.
# One-time: xcrun notarytool store-credentials vello --apple-id <apple-id> --team-id 5JMBLLG6WT
#           Sparkle's EdDSA private key in the login keychain (generate_keys).
# Usage: scripts/release.sh 0.2.0 notes.md
set -e
VERSION=${1:?usage: scripts/release.sh <version> <notes-file>}
NOTES=${2:?usage: scripts/release.sh <version> <notes-file>}
cd "$(dirname "$0")/.."
OUT=build/release
rm -rf $OUT && mkdir -p $OUT/dmg

xcodegen -q
xcodebuild -project Vello.xcodeproj -scheme Vello -configuration Release -derivedDataPath build/release-dd -quiet \
  CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$VERSION build
ditto build/release-dd/Build/Products/Release/Vello.app $OUT/dmg/Vello.app
codesign --verify --deep --strict $OUT/dmg/Vello.app

ln -s /Applications $OUT/dmg/Applications
hdiutil create -volname Vello -srcfolder $OUT/dmg -ov -format UDZO $OUT/Vello-$VERSION.dmg -quiet
codesign --sign "Developer ID Application" --timestamp $OUT/Vello-$VERSION.dmg

xcrun notarytool submit $OUT/Vello-$VERSION.dmg --keychain-profile vello --wait
xcrun stapler staple $OUT/Vello-$VERSION.dmg
spctl --assess --type open --context context:primary-signature -v $OUT/Vello-$VERSION.dmg

# Sparkle appcast, signed with the EdDSA key from the keychain. Served from the latest release's assets.
SPARKLE=build/SourcePackages/artifacts/sparkle/Sparkle/bin
[ -x $SPARKLE/generate_appcast ] || xcodebuild -resolvePackageDependencies -project Vello.xcodeproj -derivedDataPath build -quiet
mkdir -p $OUT/appcast && cp $OUT/Vello-$VERSION.dmg $OUT/appcast/
$SPARKLE/generate_appcast --download-url-prefix "https://github.com/alimuratkuslu/vello/releases/download/v$VERSION/" $OUT/appcast

gh release create v$VERSION $OUT/Vello-$VERSION.dmg $OUT/appcast/appcast.xml --title "Vello $VERSION" --notes-file "$NOTES"

# Homebrew cask in alimuratkuslu/homebrew-tap
SHA=$(shasum -a 256 $OUT/Vello-$VERSION.dmg | cut -d' ' -f1)
rm -rf build/homebrew-tap && gh repo clone alimuratkuslu/homebrew-tap build/homebrew-tap -- -q
mkdir -p build/homebrew-tap/Casks
cat > build/homebrew-tap/Casks/vello.rb <<CASK
cask "vello" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/alimuratkuslu/vello/releases/download/v#{version}/Vello-#{version}.dmg"
  name "Vello"
  desc "Free, private, on-device dictation"
  homepage "https://github.com/alimuratkuslu/vello"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Vello.app"

  zap trash: [
    "~/Library/Application Support/Vello",
    "~/Library/Caches/com.alimuratkuslu.vello",
    "~/Library/HTTPStorages/com.alimuratkuslu.vello",
    "~/Library/Preferences/com.alimuratkuslu.vello.plist",
  ]
end
CASK
git -C build/homebrew-tap add Casks/vello.rb
git -C build/homebrew-tap commit -q -m "vello $VERSION"
git -C build/homebrew-tap push -q
echo "Done: v$VERSION released, cask bumped"
