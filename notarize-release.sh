#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.20.3-Beta-cotton.2"
build_number="$(git rev-list --count HEAD)"
codesign_identity="Developer ID Application: Quang Anh Do (C7HHQ9A86J)"
keychain_profile="aerospace-notary"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --build-number) build_number="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --keychain-profile) keychain_profile="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1;;
    esac
done

if ! [[ "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid build number: $build_number" > /dev/stderr
    exit 1
fi
if ! test -s script/sparkle-public-key.txt; then
    echo "Missing Sparkle public key: script/sparkle-public-key.txt" > /dev/stderr
    exit 1
fi

if ! security find-identity -v -p codesigning | grep --fixed-string -q "\"$codesign_identity\""; then
    echo "Can't find codesign identity: $codesign_identity" > /dev/stderr
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$keychain_profile" --output-format json > /dev/null; then
    echo "Can't find notarytool Keychain profile: $keychain_profile" > /dev/stderr
    echo "Create it with: xcrun notarytool store-credentials $keychain_profile --apple-id YOUR_APPLE_ID --team-id C7HHQ9A86J --password YOUR_APP_SPECIFIC_PASSWORD" > /dev/stderr
    exit 1
fi

./build-docs.sh
mise exec -- ./build-shell-completion.sh

./generate.sh \
    --build-version "$build_version" \
    --build-number "$build_number" \
    --codesign-identity "$codesign_identity" \
    --generate-git-hash \
    --ignore-cmd-help

build_dir=".notarization-build"
app_path="$build_dir/Build/Products/Release/AeroSpace.app"
cli_path=".build/release/aerospace"
release_dir=".release/AeroSpace-v$build_version"
release_zip=".release/AeroSpace-v$build_version.zip"
sparkle_zip=".release/AeroSpace-v$build_version-sparkle.zip"
submission_zip=".release/AeroSpace-v$build_version-notarization.zip"

restore_development_generated_files() {
    ./generate.sh --ignore-cmd-help
}
trap restore_development_generated_files EXIT

rm -rf "$build_dir" "$release_dir" "$release_zip" "$sparkle_zip" "$submission_zip"

flowdeck build \
    -w "$PWD/xcode/AeroSpace.xcodeproj" \
    -s AeroSpace \
    -D "My Mac" \
    -C Release \
    -d "$build_dir" \
    --xcodebuild-options='ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO OTHER_CODE_SIGN_FLAGS=--timestamp'

swift build -c release --arch arm64 --arch x86_64 --product aerospace

./script/embed-release-support-files.sh "$app_path" "$cli_path"
./script/sign-sparkle-for-distribution.sh "$app_path" "$codesign_identity"
codesign --force --options runtime --timestamp --sign "$codesign_identity" "$app_path/Contents/Helpers/aerospace"
codesign --force --options runtime --timestamp --sign "$codesign_identity" "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
file "$app_path/Contents/MacOS/AeroSpace" | grep --fixed-string "Mach-O universal binary with 2 architectures"
file "$app_path/Contents/Helpers/aerospace" | grep --fixed-string "Mach-O universal binary with 2 architectures"

mkdir -p "$release_dir/bin" "$release_dir/manpage"
/usr/bin/ditto "$app_path" "$release_dir/AeroSpace.app"
codesign --verify --deep --strict --verbose=2 "$release_dir/AeroSpace.app"
cp "$app_path/Contents/Helpers/aerospace" "$release_dir/bin/aerospace"
codesign --force --options runtime --timestamp --sign "$codesign_identity" "$release_dir/bin/aerospace"
codesign --verify --strict --verbose=2 "$release_dir/bin/aerospace"
cp .man/*.1 "$release_dir/manpage"
cp -r .shell-completion "$release_dir/shell-completion"
cp -r legal "$release_dir/legal"
rm -f "$release_dir/legal/LICENSE.txt"
cp LICENSE.txt "$release_dir/legal/LICENSE.txt"
/usr/bin/ditto --norsrc -c -k --keepParent "$release_dir" "$submission_zip"

xcrun notarytool submit "$submission_zip" \
    --keychain-profile "$keychain_profile" \
    --wait

xcrun stapler staple "$release_dir/AeroSpace.app"
xcrun stapler validate "$release_dir/AeroSpace.app"
/usr/sbin/spctl --assess --type execute --verbose=4 "$release_dir/AeroSpace.app"
codesign --verify --strict --verbose=2 "$release_dir/bin/aerospace"

/usr/bin/ditto --norsrc -c -k --keepParent "$release_dir" "$release_zip"
/usr/bin/ditto --norsrc -c -k --keepParent "$release_dir/AeroSpace.app" "$sparkle_zip"
rm "$submission_zip"
