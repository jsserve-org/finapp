#!/bin/sh
# Builds an ad-hoc signed arm64 IPA at build/Ledgerly-v<version>.ipa.
# Ad-hoc signing lets installers that don't re-sign everything (unlike SideStore) launch the app.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Ledgerly.xcodeproj -scheme Ledgerly -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/IPADerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
app=build/IPADerivedData/Build/Products/Release-iphoneos/Ledgerly.app
codesign --force --sign - --timestamp=none "$app"
version=$(plutil -extract CFBundleShortVersionString raw "$app/Info.plist")
package=build/IPAPackage
rm -rf "$package" && mkdir -p "$package/Payload" && cp -R "$app" "$package/Payload/"
rm -f "build/Ledgerly-v$version.ipa"
(cd "$package" && zip -qry "../Ledgerly-v$version.ipa" Payload)
echo "build/Ledgerly-v$version.ipa"
