# Disk Cleaner

A disk space analyzer and cleaner for macOS: scan a disk or folder, see what takes up space as size bars, queue what you no longer need, and remove it.

## Features

- Fast parallel scanner built on `getattrlistbulk(2)`; reports on-disk (allocated) sizes, counts hard links once, never follows symlinks or crosses into other volumes.
- Sidebar with every disk and scanned folder; results stay available for the session, so switching locations never loses a scan.
- Size bar of the focused folder split into its largest items, and a list where each folder's bar shows what is inside it. Hover to highlight, click to open a folder.
- Open a subfolder with double-click, Return or the › button; hover a row for Quick Look (Space) and Open/Reveal in Finder; right-click for Copy Path and more.
- Cleanup list: drag items onto the bottom bar (or press ⌫ / the + button), then **Move to Trash** or **Delete Immediately**. ⌘⌫ or *Move to Trash* in the context menu trashes items right away.
- After a cleanup a banner confirms it, with **Undo** for items moved to the Trash and **Empty Trash…** (also ⇧⌘⌫).
- **Largest Files**: the 200 biggest files and packages under the current folder, filterable by videos, archives, disk images, installers and apps.
- **Quick Clean** (sidebar → Tools): sizes of caches, logs, Xcode build data, Homebrew/npm/Gradle caches and the Trash, cleaned in one go.
- Disk overview with used, purgeable and free space, plus *System & Other* (space the scan can't see: macOS, snapshots, other users' files, skipped folders).
- System folders and top-level home folders are protected from deletion.
- Settings (⌘,): pick a color theme — Teal (default), Indigo, Violet, Coral or Graphite; it applies immediately.
- Automatic updates with [Sparkle](https://sparkle-project.org): a daily check of the appcast attached
  to the latest GitHub release, downloading and installing new versions in the background (both can be
  turned off in Settings), plus *Check for Updates…* in the app menu. The version is in Settings and
  *About*.

## Install

```sh
brew install --cask thai1108/tap/disk-cleaner
```

Or download the DMG from [the releases](https://github.com/thai1108/disk-cleaner/releases).

## Requirements

A Mac with Apple silicon and macOS 14+ (the Liquid Glass look needs macOS 26); Xcode 26+
(Swift 6.2) to build.

## Build & run

```sh
./scripts/build-app.sh          # builds and signs build/DiskCleaner.app
open build/DiskCleaner.app
open -a build/DiskCleaner.app ~/Downloads   # scan a folder directly
```

Tests: `swift test`.

Secret scanning: run `lefthook install` once per clone (needs `lefthook` and `gitleaks`, both
in Homebrew). gitleaks then checks staged changes before each commit and the history before
each push (`lefthook.yml`).

## Releasing

The app is distributed outside the Mac App Store as a notarized DMG: the App Store sandbox
would block whole-disk scans, Quick Clean and the Trash.

One-time setup:

1. Join the Apple Developer Program.
2. Create a **Developer ID Application** certificate for team `JKJ595QHBK`: Xcode › Settings ›
   Accounts › Manage Certificates › + (only the team's Account Holder can). It is stored in the
   login keychain.
3. Create an app-specific password at account.apple.com, then store the notarization
   credentials in the keychain. Run this in Terminal; it asks for the password:

   ```sh
   xcrun notarytool store-credentials disk-cleaner-notary --apple-id <your-apple-id> --team-id JKJ595QHBK
   ```

4. Updates are signed with a Sparkle EdDSA key whose public half is `SUPublicEDKey` in
   `Resources/Info.plist`. The private key lives only in the login keychain of the release Mac; back
   it up somewhere safe (never in git), or installed copies can no longer be updated:

   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x <backup-file>
   ```

Releases are signed for team `JKJ595QHBK`; `scripts/release.sh` refuses to sign with another
team's certificate (set `TEAM_ID` to change it).

Each release:

1. In `Resources/Info.plist`, set `CFBundleShortVersionString` to the new semantic version
   `MAJOR.MINOR.PATCH` (patch for fixes, minor for features, major for breaking changes) and
   increase the `CFBundleVersion` build number by one. Releases are tagged `v<version>`.
2. Run `NOTARY_PROFILE=disk-cleaner-notary ./scripts/release.sh`. It builds an Apple silicon app,
   signs it with Developer ID and the hardened runtime, notarizes and staples the app and
   the DMG, and checks both with Gatekeeper.
3. Run `RELEASE_NOTES="<what changed>" ./scripts/publish.sh`. It signs the DMG for Sparkle, uploads
   it with `appcast.xml` as release `v<version>` of this repo (installed apps update from it) and
   updates the cask in [thai1108/homebrew-tap](https://github.com/thai1108/homebrew-tap), using
   the `thai1108` gh account without switching the active one. `--dry-run` prints the cask.

`./scripts/release.sh --skip-notarize` makes a local dry run that is not fit for distribution.

## Full Disk Access

Grant it once in System Settings → Privacy & Security → Full Disk Access. Without it, macOS asks separately for Desktop, Documents, Downloads, Photos and Music; the app explains this once, then skips those folders (shown with a lock) instead of letting macOS interrupt the scan.

`build-app.sh` signs with your Apple Development (or Developer ID) certificate when one is installed, so the grant survives rebuilds. Set `SIGN_IDENTITY` to choose another; with no certificate it falls back to ad-hoc signing, and macOS forgets the grant after every rebuild.

## Layout

- `Sources/DiskCleanerCore` — scanner, file tree, size breakdown, cleanup list, path rules (unit-tested).
- `Sources/DiskCleaner` — SwiftUI app.
- `scripts/` — app bundling and icon generation.
