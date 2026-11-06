#!/bin/sh
# Builds a release binary and wraps it in build/DiskCleaner.app.
# ARCHS="arm64 x86_64" builds a universal binary; CODESIGN_FLAGS adds codesign options
# (scripts/release.sh uses both).
set -eu

cd "$(dirname "$0")/.."
APP="build/DiskCleaner.app"
ICON="Resources/AppIcon.icns"

ARCH_FLAGS=""
for arch in ${ARCHS:-}; do
    ARCH_FLAGS="$ARCH_FLAGS --arch $arch"
done
# shellcheck disable=SC2086 # ARCH_FLAGS is a list of flags.
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)/DiskCleaner"

if [ ! -f "$ICON" ]; then
    swift scripts/make-icon.swift "$ICON"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DiskCleaner"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Compiles the accent color (NSAccentColorName in Info.plist) into Assets.car.
xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 \
    --output-partial-info-plist build/assets-info.plist > /dev/null

# A certificate keeps the app's identity stable across rebuilds, so macOS remembers the Full
# Disk Access grant; an ad-hoc signature changes on every build and loses it.
# Override with SIGN_IDENTITY; falls back to ad-hoc when no certificate is installed.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"(Apple Development|Developer ID Application):/ { print $2; exit }')}"
# shellcheck disable=SC2086 # CODESIGN_FLAGS is a list of flags.
codesign --force ${CODESIGN_FLAGS:-} --sign "${IDENTITY:--}" "$APP"
echo "Built $(pwd)/$APP"
