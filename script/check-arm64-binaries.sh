#!/usr/bin/env bash
set -e
set -u
set -o pipefail

if test $# -eq 0; then
    echo "Usage: $0 APP_OR_BINARY_PATH..." >&2
    exit 1
fi

checked_binaries=0
check_binary() {
    local binary="$1"
    local description
    description="$(file -b "$binary")"
    case "$description" in
        Mach-O*)
            if [[ "$description" != *" arm64"* || "$description" == *"universal binary"* ]]; then
                echo "Expected an Apple Silicon only binary: $binary ($description)" >&2
                exit 1
            fi
            checked_binaries=$((checked_binaries + 1))
            ;;
    esac
}

for path in "$@"; do
    if test -d "$path"; then
        while IFS= read -r -d '' binary; do
            check_binary "$binary"
        done < <(find "$path" -type f -print0)
    elif test -f "$path"; then
        check_binary "$path"
    else
        echo "Path not found: $path" >&2
        exit 1
    fi
done

if test "$checked_binaries" -eq 0; then
    echo "No Mach-O binaries found" >&2
    exit 1
fi
echo "Verified $checked_binaries Apple Silicon only binaries"
