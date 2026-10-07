<p align="center"><img src="assets/icon.png" width="100" alt="Lokaah Talky icon"></p>

# Lokaah Talky

Local voice dictation for macOS, with a small floating widget.

Press **Option-Space**, speak, then press it again to finish.
Talky copies the transcript to the clipboard and can paste it into the app and text field where you started.

This is an MIT-licensed source preview.
Build from source while the remaining runtime and distribution checks are completed.
The historical `v1.0.0` download and demo do not represent the current privacy and delivery behavior.
See [release readiness](PRODUCT.md#release-readiness).

## What it does

- Requires Apple's on-device speech recognition for the selected language.
- Keeps a compact widget available without a Dock icon.
- Shows live text and supports longer captures through recognition-session renewal.
- Copies regular dictation to the clipboard, replacing its previous contents.
- Pastes only when the original app and focused text element still match.
- Offers an explicit auto-send toggle, off by default, that presses Return after paste.
- Lets you cancel a capture with **Option-Escape**.

Accuracy and reliable capture length depend on the voice, language, microphone, and environment.
There is no published word-accuracy benchmark yet.

## Build and run

The deployment target is **macOS 14 on Apple Silicon**.
Build with **Xcode 26 or newer**, or use standalone Command Line Tools with the Swift compiler options supported by [build-local.sh](build-local.sh).
A local speech model must be available for your chosen language.
The release checklist tracks testing on the minimum macOS version separately from compilation.

```bash
git clone https://github.com/Venkat-RJ/lokaah-talky.git
cd lokaah-talky
./setup-cert.sh
./reinstall.sh --build
```

`setup-cert.sh` creates a local development signing identity.
`reinstall.sh --build` builds, signs, installs, and launches the app.
These scripts affect your keychain and installed application, so read [BUILD.md](BUILD.md) first.
You can also open `Lokaah Talky.xcodeproj` in Xcode.

To build a separate local app with standalone Command Line Tools:

```bash
./build-local.sh
./build-local.sh --release --adhoc --output-dir build/local
```

The first command creates an unsigned Debug bundle at `build/local/Lokaah Talky.app`.
The second creates an optimized bundle with ad-hoc signing for local testing.
This build route leaves installation and launch to you.
Ad-hoc signing does not provide a notarized public download or a stable development identity.
If full Xcode reports an unaccepted license, the standalone CLT route can be used when its own toolchain is already configured.
Current build evidence and the remaining live dictation, permission, delivery, and minimum-OS checks are described in [BUILD.md](BUILD.md) and [TESTING.md](TESTING.md).

## Permissions and everyday use

Allow **Microphone** and **Speech Recognition** to dictate.
Allow **Accessibility** if you want automatic paste.
Without Accessibility, use Command-V to paste the copied text yourself.

Use the widget or **Option-Space** to start and finish.
Expand the widget to see the transcript and controls.
Open Settings to select the language, add local vocabulary, and manage optional storage and startup behavior.
If you move to another app or text field before delivery, Talky keeps the transcript on the clipboard for manual paste.

Auto-send can submit a chat message or run a terminal command.
Turn it on only when that is what you want for the current destination.
It starts off on a fresh installation. Your chosen setting is saved.

## Privacy and local storage

Speech recognition is required to run locally.
Talky refuses a capture when the selected recognizer cannot support on-device processing.
Clipboard contents and text delivered to another app become available to that app and other software with clipboard access.

History, the latest-transcript automation file, and launch at login are **off on a fresh installation**.
Upgrades preserve saved preferences and any existing launch-at-login registration.
If you enable history, choose a retention period of 1, 7, or 30 days, or keep it until you delete it.
Retention is checked at startup, when history settings change, and after a saved dictation.
History is stored as unencrypted local files under `~/.talky/voice_history/` with owner-only permissions.

Turning history off stops new saves and leaves existing records available.
Use **History** to search, copy, export, or delete saved dictations.
Deleting history does not clear the clipboard or remove exported files.

The optional latest-transcript file is `~/.talky/voice_input.txt`.
Turning its setting off removes that file.

The command interface and isolated test results are documented in [TESTING.md](TESTING.md).
The command interface is available to processes running as your user account.
Treat those scripts as trusted software.

## Contribute

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and useful first contributions.
[BUILD.md](BUILD.md) describes the architecture.
[PRODUCT.md](PRODUCT.md) records the product scope and release gates.
Report security issues through [SECURITY.md](SECURITY.md).

The project source is [MIT licensed](LICENSE), copyright 2026 Lokaah.
Dependencies keep their own licenses.
The optional Remotion video toolchain uses [Remotion's license](https://www.remotion.dev/license).
