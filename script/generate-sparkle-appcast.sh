#!/usr/bin/env bash
set -e
set -u
set -o pipefail

if test $# -ne 3; then
    echo "Usage: $0 RELEASE_ZIP GITHUB_REPO TAG" > /dev/stderr
    exit 1
fi

release_zip="$1"
github_repo="$2"
tag="$3"
sparkle_tools_dir="${SPARKLE_TOOLS_DIR:-.notarization-build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
sparkle_key_account="do.anh.Aerospace"
generate_appcast="$sparkle_tools_dir/generate_appcast"
input_dir=".release/sparkle-appcast-input"
output_path=".release/appcast.xml"

if ! test -f "$release_zip"; then
    echo "Release ZIP not found: $release_zip" > /dev/stderr
    exit 1
fi
if ! test -x "$generate_appcast"; then
    echo "Sparkle generate_appcast tool not found: $generate_appcast" > /dev/stderr
    exit 1
fi

rm -rf "$input_dir"
mkdir -p "$input_dir"
cp "$release_zip" "$input_dir"

"$generate_appcast" \
    --account "$sparkle_key_account" \
    --download-url-prefix "https://github.com/$github_repo/releases/download/$tag/" \
    "$input_dir"

if ! test -f "$input_dir/appcast.xml"; then
    echo "Sparkle did not generate appcast.xml" > /dev/stderr
    exit 1
fi
cp "$input_dir/appcast.xml" "$output_path"
