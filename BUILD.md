# Building Lokaah Talky

Build on Apple Silicon with Xcode 26 or newer, or standalone Command Line Tools that support the flags in `build-local.sh`.
The deployment target is macOS 14.
A newer SDK does not prove the app works on macOS 14.
When reporting compatibility, include the OS, toolchain version, and checks you ran.

## Build with standalone Command Line Tools

`build-local.sh` creates a separate app bundle without installing or launching it.
It uses `/Library/Developer/CommandLineTools` by default.
Set `TALKY_DEVELOPER_DIR` to use another configured toolchain.
The script uses that toolchain's macOS SDK, snapshots the Swift source, and packages the executable and icon.

```bash
# Debug, with an unsigned executable.
./build-local.sh

# Optimized Release, also unsigned.
./build-local.sh --release

# Optimized bundle signed ad-hoc for local launch testing.
./build-local.sh --release --adhoc --output-dir build/local
```

The default output is `build/local/Lokaah Talky.app`.
Use `--output-dir` for another directory, including a temporary build for testing.
Info.plist records the build method, Debug or Release configuration, and source SHA256.
The script finishes the new bundle before replacing a previous output.
If compilation or signing fails, it keeps the previous build and returns an error.

Apple Silicon executables need signing before launch.
`--adhoc` signs and verifies the bundle for local testing.
Ad-hoc rebuilds can require new permission grants.
Use a stable local signing identity to help preserve grants between development builds.

`reinstall.sh` installs only the Xcode Debug product described below.
Running it after a standalone build does not install the bundle from `build/local/`.

Standalone Debug and Release builds passed during the 7 October 2026 review using Swift 6.3.2 and the macOS 26.5 SDK.
Their executables specify macOS 14.0 as the minimum version.
Live dictation on macOS 14 still needs testing.

## Build with Xcode

```bash
xcodebuild -version
xcodebuild -project "Lokaah Talky.xcodeproj" \
  -scheme "Lokaah Talky" -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath build/verification \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

This creates an unsigned test build without replacing the installed app.
Public CI has passed the complete unsigned Xcode build and automated checks.

On the review machine, the full Xcode build exited with code 69 because its license was not accepted.
`xcodebuild -version` worked, but the app build remained blocked.
Configure Xcode separately, or use standalone CLT when that toolchain is already configured.
The CLT build does not accept the full Xcode license or change the system developer-directory selection.

## Install for local development

These commands change your login keychain, install the app, and launch it.

```bash
./setup-cert.sh
./reinstall.sh --build
```

`setup-cert.sh` creates the **Talky Self-Signed** certificate and private key in your login keychain.
Read the keychain prompt before granting access.
Keep the identity local and never commit or publish its private key.
Stable signing helps macOS recognize later development builds.
Changes to the identity, bundle, or system can still require new permission grants.

`reinstall.sh --build` builds and installs this checkout's `build/Build/Products/Debug/Lokaah Talky.app`.
Run `./reinstall.sh` without `--build` to install that existing build.
The installer copies and verifies the signed bundle before stopping or replacing the running app.
Copy, signing, or launch failures return a nonzero status.
Replacement and launch failures restore the previous app when one existed.

The default destination is `/Applications/Lokaah Talky.app`.
Set `TALKY_DEST_DIR` to another writable installation directory.
Check the installer output for the actual path.

Local self-signing does not establish Apple verification.
An Apple-notarized download needs Developer ID signing, notarization, and testing of the final artifact.
The [unnotarized beta workflow](docs/UNNOTARIZED-BETA.md) can reuse an existing local certificate without a paid Apple developer membership.
It requires live acceptance, clean-Mac installation testing, and clear disclosure of the macOS approval step.
The historical DMG has not been verified against those release requirements.

## Architecture

The app lives in `Lokaah Talky/LokaahTalkyApp.swift`, with bundle identifier `com.lokaah.talky`.

- `AppDelegate` creates the floating accessory panel and global hotkeys.
- `RootView` provides the compact widget, transcript, history, and settings controls.
- `SpeechManager` manages permissions, capture, recognition sessions, cancellation, and delivery.
- The audio-request holder synchronizes access between the audio tap and recognition-session changes.
- `Paster` checks Accessibility trust and synthesizes Command-V and optional Return.
- The waveform views display microphone levels.

Keep UI and capture state on the main actor.
Audio callbacks must synchronize request access and leave actor-isolated state to the main actor.
Bind recognition callbacks and delayed work to the capture that created them, so they cannot finalize a later one.

## Delivery and storage

Regular dictation replaces the clipboard with the completed transcript.
Automatic paste uses Command-V, including in Terminal.
Use Accessibility to check the original focused element; keep Command-V as the main insertion path.
Recheck the destination before paste and Return.
Cancel delivery if it changed. Do not activate a stale destination.

Save transcripts only when the matching storage option is enabled.
Data defaults to `~/.talky/`.
Set an absolute `TALKY_DATA_DIR` to use a separate directory for an isolated test process.
Keep private directories at `0700` and files at `0600`, including replaced or migrated files.
Isolated test captures write only their own results and must not deliver text to another app.

## What a build proves

A successful build checks compilation and packaging.
Permissions, local models, Accessibility delivery, cancellation, long captures, and dictation on macOS 14 need live tests.
See [TESTING.md](TESTING.md) for the test flow and [PRODUCT.md](PRODUCT.md#release-readiness) for passed and pending checks.

[The binary release workflow](docs/BINARY-RELEASE.md) requires a configured Developer ID identity and notary profile.
It builds the exact tagged commit, checks signing and notarization, and requires completed test evidence tied to the final archive checksum.
It prepares a private candidate without uploading or installing it.
Developer ID signing, notarization, and clean-machine installation remain pending release checks.

## Optional video tooling

The historical explainer source is in `video/`, with dependencies pinned to Remotion 4.0.533.
Run `npm audit --package-lock-only --ignore-scripts` there to check the locked public dependencies.
Remotion has its own license.
Review the old MP4 and GIF again before using them as a demo of the current app.
