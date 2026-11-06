#!/bin/sh
# Builds build/DiskCleaner-<version>.dmg for distribution outside the App Store: an Apple
# silicon app signed with Developer ID and the hardened runtime, notarized by Apple and
# stapled, so it opens without Gatekeeper warnings. One-time setup is described in README › Releasing.
#
# Usage: NOTARY_PROFILE=<profile> scripts/release.sh
#        scripts/release.sh --skip-notarize   # local dry run, not for distribution
# TEAM_ID picks the team to sign for; DEVELOPER_ID overrides the signing identity.
set -eu

TEAM_ID="${TEAM_ID:-JKJ595QHBK}"

# SHA-1 of the first valid code-signing certificate of a kind, optionally of one team.
# Names are avoided because accented names may not match codesign's lookup.
find_identity() {
    security find-identity -v -p codesigning |
        awk -v kind="\"$1:" -v team="${2:+($2)\"}" 'index($0, kind) && index($0, team) { print $2; exit }'
}

cd "$(dirname "$0")/.."
SKIP_NOTARIZE=0
[ "${1:-}" = "--skip-notarize" ] && SKIP_NOTARIZE=1

IDENTITY="${DEVELOPER_ID:-$(find_identity "Developer ID Application" "$TEAM_ID")}"
if [ -z "$IDENTITY" ]; then
    if [ "$SKIP_NOTARIZE" = 1 ]; then
        IDENTITY="$(find_identity "Apple Development")"
        echo "warning: no Developer ID certificate, signing the dry run with an Apple Development one" >&2
    else
        echo "error: no \"Developer ID Application\" certificate of team $TEAM_ID in the keychain" >&2
        exit 1
    fi
fi
if [ "$SKIP_NOTARIZE" = 0 ] && [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "error: set NOTARY_PROFILE to a profile saved with 'xcrun notarytool store-credentials'" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
# Releases are tagged v<MAJOR.MINOR.PATCH>, which the in-app update check compares.
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: CFBundleShortVersionString must be MAJOR.MINOR.PATCH, got '$VERSION'" >&2
    exit 1
fi
APP="build/DiskCleaner.app"
DMG="build/DiskCleaner-$VERSION.dmg"

# Submits a file to Apple and waits; prints the log and stops if it is not accepted.
notarize() {
    result="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
    status="$(printf '%s' "$result" | plutil -extract status raw -o - -)"
    if [ "$status" != "Accepted" ]; then
        id="$(printf '%s' "$result" | plutil -extract id raw -o - -)"
        echo "error: notarization of $1 ended with status $status" >&2
        xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
        exit 1
    fi
    echo "Notarized $1"
}

ARCHS="arm64" SIGN_IDENTITY="$IDENTITY" CODESIGN_FLAGS="--options runtime --timestamp" ./scripts/build-app.sh
codesign --verify --strict --verbose=2 "$APP"
if [ "$SKIP_NOTARIZE" = 0 ]; then
    signed_team="$(codesign -dv "$APP" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2 }')"
    if [ "$signed_team" != "$TEAM_ID" ]; then
        echo "error: the app is signed for team $signed_team, expected $TEAM_ID" >&2
        exit 1
    fi
fi

# The app is notarized on its own first, so it stays trusted once copied out of the DMG
# even without a network connection.
if [ "$SKIP_NOTARIZE" = 0 ]; then
    ditto -c -k --keepParent "$APP" build/DiskCleaner.zip
    notarize build/DiskCleaner.zip
    rm build/DiskCleaner.zip
    xcrun stapler staple "$APP"
fi

STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/Disk Cleaner.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Disk Cleaner" -srcfolder "$STAGE" -format UDZO -ov "$DMG" > /dev/null
rm -rf "$STAGE"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

if [ "$SKIP_NOTARIZE" = 0 ]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
    spctl --assess --type exec --verbose "$APP"
fi

echo "Built $(pwd)/$DMG"
shasum -a 256 "$DMG"
