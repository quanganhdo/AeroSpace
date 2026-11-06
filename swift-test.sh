#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

swift build --build-tests

test_frameworks_dir=".build/debug/AppBundleTests.xctest/Contents/Frameworks"
mkdir -p "$test_frameworks_dir"
rm -rf "$test_frameworks_dir/Sparkle.framework"
cp -R .build/debug/Sparkle.framework "$test_frameworks_dir"

events=.swift-testing-events.jsonl
rm -f "$events"

if swift test --skip-build --event-stream-output-path "$events" --event-stream-version 0 |
    sed -E '/^[^[:space:]]+ +(Test|Suite) [^[:space:]]+ (started|passed after)/d' |
    # Replace colons with semicolons in dates to avoid treating these lines as files in vim
    sed -E 's/:/;/g'
then
    echo "✅ Swift tests have passed successfully"
else
    # Swift Testing console output only prints file names. Print full paths for vim
    jq -r '
        .payload
        | select(.kind == "issueRecorded" and (.issue.isKnown | not))
        | .issue.sourceLocation as $loc
        | "\($loc._filePath):\($loc.line):\($loc.column): error: \(.testID | split("/")[0:2] | join("/")): \(.messages | map(.text) | join("\n"))"
    ' "$events"
    echo "❌ Swift tests have failed"
    exit 1
fi
