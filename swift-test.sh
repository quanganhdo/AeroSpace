#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

swift build --build-tests

test_frameworks_dir=".build/debug/AppBundleTests.xctest/Contents/Frameworks"
mkdir -p "$test_frameworks_dir"
rm -rf "$test_frameworks_dir/Sparkle.framework"
cp -R .build/debug/Sparkle.framework "$test_frameworks_dir"

if swift test --skip-build \
    | sed -E '/^Test (Suite|Case).*(started|passed)/d' \
    | sed -E '/^[[:space:]]+Executed.*with 0 failures/d' \
    | sed -E '/ [[:digit:]]+(:[[:digit:]]+)+/s/:/;/g' # Replace colons with semicolons in dates to avoid treating these lines as files in vim
then
    echo "✅ Swift tests have passed successfully"
else
    echo "❌ Swift tests have failed"
    exit 1
fi
