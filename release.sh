#!/bin/bash
set -e
set -u
set -o pipefail

cd "$(dirname "$0")"

build_version=""
tap_dir="../homebrew-tap"
brew_tap="quanganhdo/tap"
github_repo="quanganhdo/AeroSpace"
codesign_identity="Developer ID Application: Quang Anh Do (C7HHQ9A86J)"
keychain_profile="aerospace-notary"
release_notes=""
skip_tests=0
skip_build=0

usage() {
    cat <<EOF
Usage: ./release.sh --build-version VERSION [options]

Builds and notarizes the release, publishes it to GitHub, and updates the
Homebrew tap.

Options:
  --build-version VERSION       Required, for example 0.20.3-Beta-cotton.3
  --tap-dir PATH                Homebrew tap checkout (default: ../homebrew-tap)
  --brew-tap USER/TAP           Homebrew tap name (default: $brew_tap)
  --github-repo OWNER/REPO      GitHub repository (default: $github_repo)
  --codesign-identity IDENTITY  Developer ID Application identity
  --keychain-profile PROFILE    notarytool Keychain profile
  --notes TEXT                  GitHub release notes (default: generated notes)
  --skip-tests                  Skip the test/lint suite
  --skip-build                  Reuse the existing release ZIP
  -h, --help                    Show this help
EOF
}

while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --tap-dir) tap_dir="$2"; shift 2;;
        --brew-tap) brew_tap="$2"; shift 2;;
        --github-repo) github_repo="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --keychain-profile) keychain_profile="$2"; shift 2;;
        --notes) release_notes="$2"; shift 2;;
        --skip-tests) skip_tests=1; shift;;
        --skip-build) skip_build=1; shift;;
        -h|--help) usage; exit 0;;
        *) echo "Unknown option $1" > /dev/stderr; usage > /dev/stderr; exit 1;;
    esac
done

if test -z "$build_version"; then
    echo "--build-version is mandatory" > /dev/stderr
    usage > /dev/stderr
    exit 1
fi

case "$build_version" in
    *[!A-Za-z0-9._-]*)
        echo "Invalid build version: $build_version" > /dev/stderr
        exit 1
        ;;
esac

tap_dir="$(cd "$tap_dir" 2> /dev/null && pwd)" || {
    echo "Homebrew tap directory doesn't exist: $tap_dir" > /dev/stderr
    exit 1
}

tag="v$build_version"
release_zip="$PWD/.release/AeroSpace-v$build_version.zip"
cask_path="$tap_dir/Casks/aerospace.rb"

for command in brew gh git mise shasum; do
    if ! command -v "$command" > /dev/null; then
        echo "Required command not found: $command" > /dev/stderr
        exit 1
    fi
done
mise exec -- ruby --version > /dev/null

if ! test -f "$cask_path"; then
    echo "Cask not found: $cask_path" > /dev/stderr
    exit 1
fi

if test "$(git branch --show-current)" != main; then
    echo "AeroSpace releases must be created from main" > /dev/stderr
    exit 1
fi

if test "$(git -C "$tap_dir" branch --show-current)" != main; then
    echo "Homebrew tap releases must be created from main" > /dev/stderr
    exit 1
fi

if test -n "$(git status --porcelain)"; then
    echo "AeroSpace working tree must be clean" > /dev/stderr
    git status --short > /dev/stderr
    exit 1
fi

if test -n "$(git -C "$tap_dir" status --porcelain)"; then
    echo "Homebrew tap working tree must be clean" > /dev/stderr
    git -C "$tap_dir" status --short > /dev/stderr
    exit 1
fi

gh auth status > /dev/null
git fetch origin main
git -C "$tap_dir" fetch origin main

if ! git merge-base --is-ancestor origin/main HEAD; then
    echo "AeroSpace main is behind or diverged from origin/main" > /dev/stderr
    exit 1
fi

if test "$(git -C "$tap_dir" rev-parse HEAD)" != "$(git -C "$tap_dir" rev-parse origin/main)"; then
    echo "Homebrew tap main must match origin/main before release" > /dev/stderr
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
    if test "$(git rev-list -n 1 "$tag")" != "$(git rev-parse HEAD)"; then
        echo "Tag $tag already points to a different commit" > /dev/stderr
        exit 1
    fi
fi

if test "$skip_tests" = 0; then
    ./test.sh
fi

if test "$skip_build" = 0; then
    ./notarize-release.sh \
        --build-version "$build_version" \
        --codesign-identity "$codesign_identity" \
        --keychain-profile "$keychain_profile"
fi

if ! test -f "$release_zip"; then
    echo "Release ZIP not found: $release_zip" > /dev/stderr
    exit 1
fi

if test -n "$(git status --porcelain)"; then
    echo "Release build left tracked or untracked source changes" > /dev/stderr
    git status --short > /dev/stderr
    exit 1
fi

sha="$(shasum -a 256 "$release_zip" | awk '{print $1}')"

git push origin main
if ! git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
    git tag -a "$tag" -m "AeroSpace $build_version"
fi
git push origin "$tag"

asset_name="$(basename "$release_zip")"
if gh release view "$tag" --repo "$github_repo" > /dev/null 2>&1; then
    published_digest="$(
        gh release view "$tag" \
            --repo "$github_repo" \
            --json assets \
            --jq ".assets[] | select(.name == \"$asset_name\") | .digest"
    )"
    if test -z "$published_digest"; then
        gh release upload "$tag" "$release_zip" --repo "$github_repo"
    elif test "$published_digest" != "sha256:$sha"; then
        echo "Published asset checksum differs for $asset_name" > /dev/stderr
        echo "Use a new build version instead of replacing a release asset" > /dev/stderr
        exit 1
    fi
else
    create_args=(
        "$tag"
        "$release_zip"
        --repo "$github_repo"
        --title "AeroSpace $build_version"
        --verify-tag
    )
    if test -n "$release_notes"; then
        create_args+=(--notes "$release_notes")
    else
        create_args+=(--generate-notes)
    fi
    gh release create "${create_args[@]}"
fi

mise exec -- ruby ./script/update-brew-cask.rb \
    "$cask_path" \
    "$build_version" \
    "$sha"

git -C "$tap_dir" diff --check
HOMEBREW_NO_AUTO_UPDATE=1 brew style "$cask_path"

if test -n "$(git -C "$tap_dir" status --porcelain)"; then
    git -C "$tap_dir" add Casks/aerospace.rb
    git -C "$tap_dir" commit -m "Update aerospace to $build_version"
    git -C "$tap_dir" push origin main
fi

brew update
HOMEBREW_NO_AUTO_UPDATE=1 brew audit --cask --strict --online "$brew_tap/aerospace"

echo
echo "Published AeroSpace $build_version"
echo "Release: https://github.com/$github_repo/releases/tag/$tag"
echo "SHA-256: $sha"
