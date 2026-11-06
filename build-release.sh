#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
build_number="$(git rev-list --count HEAD)"
codesign_identity="aerospace-codesign-certificate"
timestamp_signatures=0
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --build-number) build_number="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --timestamp-signatures) timestamp_signatures=1; shift;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

if ! [[ "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid build number: $build_number" > /dev/stderr
    exit 1
fi

#############
### BUILD ###
#############

./build-docs.sh --release
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh

build_info_file="$PWD/.build-info.txt"
printf '%s\n%s\n%s\n' "$build_version" "$(git rev-parse HEAD)" "$(git rev-parse --short HEAD)" > "$build_info_file"

swift_build_cli=(build -c release --arch arm64 --product aerospace)
swift "${swift_build_cli[@]}" -Xswiftc -warnings-as-errors \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __aero_build \
    -Xlinker "$build_info_file"
cli_bin_path="$(swift "${swift_build_cli[@]}" --show-bin-path)"

rm -rf .release && mkdir .release

cd ./xcode
    xcode_configuration="Release"
    xcodebuild -version
    extra_xcodebuild_args=()
    if test "$timestamp_signatures" = 1; then
        extra_xcodebuild_args+=("OTHER_CODE_SIGN_FLAGS=--timestamp")
    fi
    xcodebuild-pretty ../.release/xcodebuild.log clean build \
        -scheme AeroSpace \
        -destination "generic/platform=macOS" \
        -configuration "$xcode_configuration" \
        -derivedDataPath .xcode-build \
        ARCHS=arm64 \
        MARKETING_VERSION="$build_version" \
        CURRENT_PROJECT_VERSION="$build_number" \
        AEROSPACE_CODE_SIGN_IDENTITY="$codesign_identity" \
        AEROSPACE_BUILD_INFO_LDFLAGS="-sectcreate __TEXT __aero_build $build_info_file" \
        "${extra_xcodebuild_args[@]}"
cd -

/usr/bin/ditto --noclone --arch arm64 \
    "xcode/.xcode-build/Build/Products/$xcode_configuration/AeroSpace.app" \
    .release/AeroSpace.app
cp "$cli_bin_path/aerospace" .release

# Binary reproducibility: strip non-portable rpaths
# https://github.com/swiftlang/swift-package-manager/issues/10760
xcrun objdump --macho --rpaths --no-leading-headers --arch all .release/aerospace | grep -vE '^(@|/usr/lib/swift$)' | sort -u |
    while IFS= read -r rpath; do
        install_name_tool -delete_rpath "$rpath" .release/aerospace
    done

################
### SIGN CLI ###
################

codesign_args=(--force --options runtime --sign "$codesign_identity")
if test "$timestamp_signatures" = 1; then
    codesign_args+=(--timestamp)
fi
codesign "${codesign_args[@]}" .release/aerospace
./script/embed-release-support-files.sh .release/AeroSpace.app .release/aerospace
./script/sign-sparkle-for-distribution.sh \
    .release/AeroSpace.app \
    "$codesign_identity" \
    "$timestamp_signatures"
codesign "${codesign_args[@]}" .release/AeroSpace.app

################
### VALIDATE ###
################

./script/validate-release-binaries.sh

############
### PACK ###
############

mkdir -p ".release/AeroSpace-v$build_version/manpage" && cp .man/*.1 ".release/AeroSpace-v$build_version/manpage"
cp -r ./legal ".release/AeroSpace-v$build_version/legal"
rm -f ".release/AeroSpace-v$build_version/legal/LICENSE.txt"
cp LICENSE.txt ".release/AeroSpace-v$build_version/legal/LICENSE.txt"
cp -r .shell-completion ".release/AeroSpace-v$build_version/shell-completion"
cd .release
    mkdir -p "AeroSpace-v$build_version/bin" && cp -r aerospace "AeroSpace-v$build_version/bin"
    /usr/bin/ditto AeroSpace.app "AeroSpace-v$build_version/AeroSpace.app"
    codesign --verify --deep --strict --verbose=2 "AeroSpace-v$build_version/AeroSpace.app"
    /usr/bin/ditto --norsrc -c -k --keepParent \
        "AeroSpace-v$build_version" \
        "AeroSpace-v$build_version.zip"
    /usr/bin/ditto --norsrc -c -k --keepParent \
        "AeroSpace-v$build_version/AeroSpace.app" \
        "AeroSpace-v$build_version-sparkle.zip"
cd -

#################
### Brew Cask ###
#################
for cask_name in aerospace aerospace-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/AeroSpace-v$build_version.zip" \
        --build-version "$build_version"
done
