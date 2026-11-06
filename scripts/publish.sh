#!/bin/sh
# Publishes the DMG made by scripts/release.sh: uploads it as a GitHub release of
# <owner>/disk-cleaner and points the cask in <owner>/homebrew-tap at it, so that
# `brew install --cask <owner>/tap/disk-cleaner` installs it.
#
# Usage: scripts/publish.sh [--dry-run]   # --dry-run only prints the cask
# GITHUB_USER picks the gh account (default thai1108) without switching the active one.
set -eu

cd "$(dirname "$0")/.."
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

OWNER="${GITHUB_USER:-thai1108}"
APP_REPO="$OWNER/disk-cleaner"
TAP_REPO="$OWNER/homebrew-tap"
CASK_PATH="Casks/disk-cleaner.rb"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
DMG="build/DiskCleaner-$VERSION.dmg"

if [ ! -f "$DMG" ]; then
    echo "error: $DMG not found; run scripts/release.sh first" >&2
    exit 1
fi
# Homebrew installs the DMG with Gatekeeper checks, so only a notarized one may go out.
if [ "$DRY_RUN" = 0 ] && ! spctl --assess --type open --context context:primary-signature "$DMG" 2> /dev/null; then
    echo "error: $DMG is not notarized; build it with scripts/release.sh without --skip-notarize" >&2
    exit 1
fi

# The release tag must point at the commit the DMG was built from.
if [ "$DRY_RUN" = 0 ]; then
    if ! git diff --quiet HEAD; then
        echo "error: commit your changes before publishing" >&2
        exit 1
    fi
    git fetch --quiet origin
    if [ -z "$(git branch --remotes --contains HEAD)" ]; then
        echo "error: push $(git rev-parse --short HEAD) before publishing" >&2
        exit 1
    fi
fi

SHA256="$(shasum -a 256 "$DMG" | awk '{ print $1 }')"
CASK="$(cat <<RUBY
cask "disk-cleaner" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$APP_REPO/releases/download/v#{version}/DiskCleaner-#{version}.dmg"
  name "Disk Cleaner"
  desc "Disk space analyzer and cleaner"
  homepage "https://github.com/$APP_REPO"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Disk Cleaner.app"

  zap trash: [
    "~/Library/Preferences/$BUNDLE_ID.plist",
    "~/Library/Saved Application State/$BUNDLE_ID.savedState",
  ]
end
RUBY
)"

if [ "$DRY_RUN" = 1 ]; then
    printf '%s\n' "$CASK"
    exit 0
fi

GH_TOKEN="$(gh auth token --user "$OWNER")"
export GH_TOKEN

gh release create "v$VERSION" "$DMG" --repo "$APP_REPO" --target "$(git rev-parse HEAD)" --title "Disk Cleaner $VERSION" \
    --notes "Install with Homebrew: \`brew install --cask $OWNER/tap/disk-cleaner\`, or download the DMG below. SHA-256: \`$SHA256\`"

# Updating through the API needs the current file's blob SHA, unless the cask is new.
current_sha="$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq .sha 2> /dev/null || true)"
content="$(printf '%s\n' "$CASK" | base64)"
if printf '%s' "$current_sha" | grep -Eq '^[0-9a-f]{40}$'; then
    gh api -X PUT "repos/$TAP_REPO/contents/$CASK_PATH" -f message="Update disk-cleaner to $VERSION" \
        -f content="$content" -f sha="$current_sha" > /dev/null
else
    gh api -X PUT "repos/$TAP_REPO/contents/$CASK_PATH" -f message="Add disk-cleaner $VERSION" \
        -f content="$content" > /dev/null
fi

echo "Published Disk Cleaner $VERSION; install with: brew install --cask $OWNER/tap/disk-cleaner"
