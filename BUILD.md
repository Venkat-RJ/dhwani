# Building Lokaah Talky

## Toolchain and platform

Use Apple Silicon and either Xcode 26 or newer, or standalone Command Line Tools that support the flags in `build-local.sh`.
The app's deployment target is macOS 14.
Using a newer SDK does not prove runtime behavior on macOS 14.
Record the OS, Xcode version, and checks performed when reporting compatibility.

## Standalone CLT build

The local builder uses `/Library/Developer/CommandLineTools` by default.
Set `TALKY_DEVELOPER_DIR` to another configured toolchain directory when needed.
It uses the selected macOS SDK, snapshots the Swift source, creates the app icon, and packages the app without changing the installed application.

```bash
# Debug, with an unsigned executable.
./build-local.sh

# Optimized Release, also unsigned.
./build-local.sh --release

# Optimized bundle signed ad-hoc for local launch testing.
./build-local.sh --release --adhoc --output-dir build/local
```

The default output is `build/local/Lokaah Talky.app`.
Use `--output-dir` to choose a separate output directory, including a temporary directory for verification.
Each bundle records its build method, Debug or Release configuration, and source SHA256 in Info.plist.
The builder stages the complete bundle before replacing a previous output.
Compilation or signing errors return failure and preserve the previous build.

Unsigned Apple Silicon executables need signing before launch.
`--adhoc` signs and verifies the bundle with an ad-hoc identity.
Local ad-hoc builds can request permissions again after rebuilding.
Use a stable local identity when you need permission continuity.

The standalone bundle is separate from Xcode's products.
`reinstall.sh` consumes only the Xcode Debug product described below, so running it after a standalone build will not install that standalone bundle.

During the 7 October 2026 review, standalone Debug and Release bundle builds passed with Swift 6.3.2 and the macOS 26.5 SDK.
The executables encoded a minimum macOS version of 14.0.
Live operation on macOS 14 remains a separate acceptance check.

## Xcode build

```bash
xcodebuild -version
xcodebuild -project "Lokaah Talky.xcodeproj" \
  -scheme "Lokaah Talky" -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath build/verification \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

This builds an unsigned verification artifact without replacing the installed app.
The full Xcode build on the review machine exited with code 69 because its license was not accepted.
`xcodebuild -version` succeeding did not establish that an app could be built.
Configure that Xcode installation before treating its build as verified, or use the standalone CLT route when that toolchain is already configured.
The CLT build does not accept a full Xcode license or change the system developer-directory selection.

## Local installation

```bash
./setup-cert.sh
./reinstall.sh --build
```

The setup script creates the local **Talky Self-Signed** certificate and private key in your login keychain.
Read the keychain prompt before granting access.
Keep this identity local and never commit or publish its private key.
A stable signing identity helps macOS recognize successive development builds.
Permission grants can still require review after identity, bundle, or system changes.

The installer uses this checkout's `build/Build/Products/Debug/Lokaah Talky.app`.
Running `./reinstall.sh` without `--build` installs its existing build.
The installer stages and verifies the signed bundle before stopping the running app or replacing the local installation.
Copy, signing, or launch failure returns a nonzero status; replacement and launch failures restore the previous app when one existed.
Read its output for the actual installation path.
The default path is `/Applications/Lokaah Talky.app`.
`TALKY_DEST_DIR` can select another writable installation directory.

Local self-signing is for development.
It is separate from Developer ID signing, notarization, and a verified public download.
Do not present an old unsigned DMG as the hardened release.

## Architecture

The app source is `Lokaah Talky/LokaahTalkyApp.swift`.
The bundle identifier is `com.lokaah.talky`.

- `AppDelegate` creates the floating accessory panel and global hotkeys.
- `RootView` provides the compact widget, transcript, history, and settings controls.
- `SpeechManager` manages permissions, capture, recognition sessions, cancellation, and delivery.
- The audio-request holder synchronizes access between the audio tap and recognition-session changes.
- `Paster` checks Accessibility trust and synthesizes Command-V and optional Return.
- The waveform views display microphone levels.

Keep UI and capture state on the main actor.
Audio callbacks must use synchronized request access and must not modify actor-isolated state directly.
Recognition callbacks and delayed work must belong to a specific capture so they cannot finalize a later one.

## Delivery and storage

Regular dictation always replaces the clipboard with the completed transcript.
Automatic paste uses Command-V, including for Terminal.
Accessibility is used to validate the original focused element, not as the primary text-insertion path.
Recheck the destination before paste and before Return.
Cancel rather than activate a stale destination.

Persist transcripts only when the corresponding storage option is enabled.
The default data directory is `~/.talky/`.
An absolute `TALKY_DATA_DIR` environment value selects a separate data root for an isolated test process.
Use mode `0700` for private directories and `0600` for files, including replacements and migration of existing storage.
Isolated test captures write only their own result files and must not deliver to another app.

## Runtime and release checks

A successful bundle build verifies compilation and packaging.
Microphone and Speech Recognition permissions, local-model availability, Accessibility delivery, cancellation, long captures, and minimum-OS operation require live acceptance checks.
Developer ID signing, notarization, and clean-machine installation remain release gates tracked in [PRODUCT.md](PRODUCT.md#release-readiness).
Public CI has passed the complete unsigned Xcode build and automated checks.
Use [TESTING.md](TESTING.md) to record the checks actually performed.

## Optional video tooling

The historical explainer source is in `video/`.
Its dependencies are pinned together to Remotion 4.0.533.
Run `npm audit --package-lock-only --ignore-scripts` there to check the locked public dependencies.
Remotion has its own license.
The old MP4 and GIF are historical assets and require a new content review before being used as a current product demo.
