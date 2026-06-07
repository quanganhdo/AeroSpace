#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.20.3-Beta-cotton.1"
codesign_identity="Developer ID Application: Quang Anh Do (C7HHQ9A86J)"
keychain_profile="aerospace-notary"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --keychain-profile) keychain_profile="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1;;
    esac
done

if ! security find-identity -v -p codesigning | grep --fixed-string -q "\"$codesign_identity\""; then
    echo "Can't find codesign identity: $codesign_identity" > /dev/stderr
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$keychain_profile" --output-format json > /dev/null; then
    echo "Can't find notarytool Keychain profile: $keychain_profile" > /dev/stderr
    echo "Create it with: xcrun notarytool store-credentials $keychain_profile --apple-id YOUR_APPLE_ID --team-id C7HHQ9A86J --password YOUR_APP_SPECIFIC_PASSWORD" > /dev/stderr
    exit 1
fi

./generate.sh \
    --build-version "$build_version" \
    --codesign-identity "$codesign_identity" \
    --ignore-cmd-help \
    --ignore-shell-parser

build_dir=".notarization-build"
app_path="$build_dir/Build/Products/Release/AeroSpace.app"
release_dir=".release/AeroSpace-v$build_version"
release_zip=".release/AeroSpace-v$build_version.zip"
submission_zip=".release/AeroSpace-v$build_version-notarization.zip"

restore_development_generated_files() {
    ./generate.sh --ignore-cmd-help --ignore-shell-parser
}
trap restore_development_generated_files EXIT

rm -rf "$build_dir" "$release_dir" "$release_zip" "$submission_zip"

flowdeck build \
    -w "$PWD/AeroSpace.xcodeproj" \
    -s AeroSpace \
    -D "My Mac" \
    -C Release \
    -d "$build_dir" \
    --xcodebuild-options='OTHER_CODE_SIGN_FLAGS=--timestamp'

codesign --verify --deep --strict --verbose=2 "$app_path"
mkdir -p "$release_dir"
cp -r "$app_path" "$release_dir"
/usr/bin/ditto -c -k --keepParent "$app_path" "$submission_zip"

xcrun notarytool submit "$submission_zip" \
    --keychain-profile "$keychain_profile" \
    --wait

xcrun stapler staple "$release_dir/AeroSpace.app"
xcrun stapler validate "$release_dir/AeroSpace.app"
/usr/sbin/spctl --assess --type execute --verbose=4 "$release_dir/AeroSpace.app"

/usr/bin/ditto -c -k --keepParent "$release_dir" "$release_zip"
rm "$submission_zip"
