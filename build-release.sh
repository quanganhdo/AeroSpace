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
./generate.sh \
    --build-version "$build_version" \
    --build-number "$build_number" \
    --codesign-identity "$codesign_identity" \
    --generate-git-hash

swift build -c release --arch arm64 --arch x86_64 --product aerospace -Xswiftc -warnings-as-errors # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

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
        "${extra_xcodebuild_args[@]}"
cd -

git checkout .

/usr/bin/ditto \
    "xcode/.xcode-build/Build/Products/$xcode_configuration/AeroSpace.app" \
    .release/AeroSpace.app
cp .build/release/aerospace .release

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

required_app_files=(
    .release/AeroSpace.app/Contents/MacOS/AeroSpace
    .release/AeroSpace.app/Contents/Helpers/aerospace
    .release/AeroSpace.app/Contents/Resources/default-config.toml
    .release/AeroSpace.app/Contents/Resources/AppIcon.icns
    .release/AeroSpace.app/Contents/Resources/Assets.car
    .release/AeroSpace.app/Contents/Info.plist
)
for required_file in "${required_app_files[@]}"; do
    if ! test -e "$required_file"; then
        echo "Missing required app file: $required_file" > /dev/stderr
        exit 1
    fi
done

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary .release/AeroSpace.app/Contents/MacOS/AeroSpace
check-universal-binary .release/AeroSpace.app/Contents/Helpers/aerospace
check-universal-binary .release/aerospace

check-contains-hash .release/AeroSpace.app/Contents/MacOS/AeroSpace
check-contains-hash .release/AeroSpace.app/Contents/Helpers/aerospace
check-contains-hash .release/aerospace

codesign --verify --deep --strict --verbose=2 .release/AeroSpace.app
codesign --verify --strict --verbose=2 .release/aerospace

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
