#!/usr/bin/env bash
set -e
set -u
set -o pipefail

if test $# -ne 2; then
    echo "Usage: $0 APP_PATH CLI_PATH" > /dev/stderr
    exit 1
fi

app_path="$1"
cli_path="$2"
helpers_dir="$app_path/Contents/Helpers"
resources_dir="$app_path/Contents/Resources"

mkdir -p \
    "$helpers_dir" \
    "$resources_dir/legal" \
    "$resources_dir/manpage" \
    "$resources_dir/shell-completion"

cp "$cli_path" "$helpers_dir/aerospace"
cp .man/*.1 "$resources_dir/manpage"
cp -R .shell-completion/. "$resources_dir/shell-completion"
cp -R legal/. "$resources_dir/legal"
rm -f "$resources_dir/legal/LICENSE.txt"
cp LICENSE.txt "$resources_dir/legal/LICENSE.txt"
