#!/usr/bin/env bash
set -e
set -u
set -o pipefail

app_path="$1"
codesign_identity="$2"
timestamp_signatures="${3:-1}"
sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"
sparkle_version="$sparkle_framework/Versions/B"

codesign_args=(--force --options runtime --sign "$codesign_identity")
if test "$timestamp_signatures" = 1; then
    codesign_args+=(--timestamp)
fi

codesign "${codesign_args[@]}" "$sparkle_version/XPCServices/Installer.xpc"
codesign "${codesign_args[@]}" --preserve-metadata=entitlements "$sparkle_version/XPCServices/Downloader.xpc"
codesign "${codesign_args[@]}" "$sparkle_version/Autoupdate"
codesign "${codesign_args[@]}" "$sparkle_version/Updater.app"
codesign "${codesign_args[@]}" "$sparkle_framework"
