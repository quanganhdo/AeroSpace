#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.20.3-Beta-cotton.2"
build_number="$(git rev-list --count HEAD)"
codesign_identity="Developer ID Application: Quang Anh Do (C7HHQ9A86J)"
keychain_profile="aerospace-notary"
prepare_only=0
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --build-number) build_number="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --keychain-profile) keychain_profile="$2"; shift 2;;
        --prepare-only) prepare_only=1; shift;;
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

./build-docs.sh
mise exec -- ./build-shell-completion.sh

build_dir="${AEROSPACE_RELEASE_BUILD_DIR:-.notarization-build}"
build_info_file="$PWD/.build-info.txt"
printf '%s\n%s\n%s\n' "$build_version" "$(git rev-parse HEAD)" "$(git rev-parse --short HEAD)" > "$build_info_file"
built_app_path="$build_dir/Build/Products/Release/AeroSpace.app"
app_path="$build_dir/AeroSpace.app"
release_dir=".release/AeroSpace-v$build_version"
release_zip=".release/AeroSpace-v$build_version.zip"
sparkle_zip=".release/AeroSpace-v$build_version-sparkle.zip"
submission_zip=".release/AeroSpace-v$build_version-notarization.zip"

rm -rf "$app_path" "$release_dir" "$release_zip" "$sparkle_zip" "$submission_zip"

build_options="ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MARKETING_VERSION=$build_version CURRENT_PROJECT_VERSION=$build_number AEROSPACE_CODE_SIGN_IDENTITY=\"$codesign_identity\" AEROSPACE_BUILD_INFO_LDFLAGS=\"-sectcreate __TEXT __aero_build $build_info_file\" OTHER_CODE_SIGN_FLAGS=--timestamp"
for scheme in AeroSpace AeroSpaceCli; do
    flowdeck build \
        -w "$PWD/xcode/AeroSpace.xcodeproj" \
        -s "$scheme" \
        -D "My Mac" \
        -C Release \
        -d "$build_dir" \
        --xcodebuild-options="$build_options"
done
cli_path="$build_dir/Build/Products/Release/aerospace"

# Disable APFS cloning so ditto actually thins prebuilt frameworks before signing.
/usr/bin/ditto --noclone --arch arm64 "$built_app_path" "$app_path"

./script/embed-release-support-files.sh "$app_path" "$cli_path"
./script/sign-sparkle-for-distribution.sh "$app_path" "$codesign_identity"
codesign --force --options runtime --timestamp --sign "$codesign_identity" "$app_path/Contents/Helpers/aerospace"
codesign --force --options runtime --timestamp --sign "$codesign_identity" "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
./script/check-arm64-binaries.sh "$app_path"

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

if test "$prepare_only" = 1; then
    echo "Prepared signed notarization archive: $submission_zip"
    exit 0
fi

if ! xcrun notarytool history --keychain-profile "$keychain_profile" --output-format json > /dev/null; then
    echo "Can't find notarytool Keychain profile: $keychain_profile" > /dev/stderr
    echo "Create it with: xcrun notarytool store-credentials $keychain_profile --apple-id YOUR_APPLE_ID --team-id C7HHQ9A86J --password YOUR_APP_SPECIFIC_PASSWORD" > /dev/stderr
    exit 1
fi

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
