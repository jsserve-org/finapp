#!/bin/sh
# Builds an ad-hoc signed arm64 IPA at build/Ledgerly-v<version>.ipa.
# AppDrop re-signs the IPA for each installer, so no Apple certificates are needed.
set -eu
cd "$(dirname "$0")/.."

bun install
bunx expo prebuild --platform ios --clean

cd ios
xcodebuild -workspace Ledgerly.xcworkspace -scheme Ledgerly -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

app=build/Build/Products/Release-iphoneos/Ledgerly.app
[ -d "$app" ] || { echo "Build did not produce $app" >&2; exit 1; }

codesign --force --sign - --timestamp=none "$app"
version=$(plutil -extract CFBundleShortVersionString raw "$app/Info.plist")
package=build/IPAPackage
rm -rf "$package" && mkdir -p "$package/Payload" && cp -R "$app" "$package/Payload/"
rm -f "build/Ledgerly-v$version.ipa"
(cd "$package" && zip -qry "../Ledgerly-v$version.ipa" Payload)
echo "ios/build/Ledgerly-v$version.ipa"
