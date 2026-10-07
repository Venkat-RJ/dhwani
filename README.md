<p align="center"><img src="assets/icon.png" width="88" alt="Lokaah Talky icon"></p>

# Lokaah Talky

**Speak from a floating widget. Paste into the text field where you started.**

Talky is a voice-dictation app for Apple Silicon Macs.
Press **Option-Space**, speak, then press it again to finish.
Talky copies the transcript to your clipboard and can paste it into the original app and text field.

[![Build and checks](https://github.com/Venkat-RJ/lokaah-talky/actions/workflows/ci.yml/badge.svg)](https://github.com/Venkat-RJ/lokaah-talky/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Early source preview. Looking for testers and contributors.**
There is no public app download yet.
You can [build from source](#build-and-run) or [help with early testing](docs/EARLY-TESTING.md).

Talky uses Apple's speech engine and requires an available on-device language model.
Read the [Apple dependency and privacy disclosure](docs/PRIVACY.md) before granting Speech Recognition access.

## A look at Talky

<p><img src="assets/widget-current.jpg" width="230" alt="Compact Talky widget showing Set up Talky and the expand control"></p>
<p><img src="assets/setup-current.jpg" width="380" alt="Expanded Talky setup showing the Apple speech disclosure and separate Microphone, Speech Recognition, and Accessibility permissions"></p>

Current widget and setup screen, captured on 7 October 2026 from an isolated app copy.
No recording permissions were granted for these screenshots.
They show the interface, not a live transcription test. [Capture details](docs/SCREENSHOTS.md).

## What it does

- A small floating widget with no Dock icon.
- **Option-Space** to start or finish, and **Option-Escape** to cancel.
- Live transcript text and recognition-session renewal during longer captures.
- Clipboard copy and optional paste into the original app and text field.
- Language selection and local vocabulary hints.
- Optional history with search, copy, export, deletion, and retention controls.

History, auto-send, the latest-transcript file, and launch at login start off.
Regular dictation replaces the clipboard.
Automatic paste is withheld if you change the original app or focused text field.

## Try it or help test

| Your next step | Where to go |
| --- | --- |
| Build and run the source | [Build instructions](BUILD.md) |
| Volunteer to test or share a test result | [Early testing guide](docs/EARLY-TESTING.md) |
| Understand the Apple speech dependency | [Privacy disclosure](docs/PRIVACY.md) |
| Fix a bug or contribute | [Contributor guide](CONTRIBUTING.md) |
| See completed and pending checks | [Verification record](docs/VERIFICATION.md) and [release checklist](PRODUCT.md#release-readiness) |

A locally signed, unnotarized beta candidate has been prepared and startup-tested on one Mac.
Its live dictation, delivery, privacy, and fresh-install acceptance remain incomplete.
The candidate is private; GitHub's source archives are not an installable app.

A future unnotarized beta may require macOS's per-app approval step.
See [beta installation](docs/BETA-INSTALL.md) and [the maintainer workflow](docs/UNNOTARIZED-BETA.md).
Accuracy and reliable capture length still need testing with real voices, languages, microphones, and environments.
No recognition-accuracy benchmark has been published.

## Build and run

Use **Apple Silicon** with **Xcode 26 or newer**, or compatible standalone Command Line Tools.
The deployment target is **macOS 14**.
Earlier compiled revisions passed startup checks on macOS 14; live dictation on that version is still pending.

```bash
git clone https://github.com/Venkat-RJ/lokaah-talky.git
cd lokaah-talky
./build-local.sh --release --adhoc --output-dir build/local
```

This creates `build/local/Lokaah Talky.app` without installing or launching it.
Open that app in Finder to try your local build.
Ad-hoc rebuilds may need new permission grants.
For Xcode builds or installation with a stable local identity, follow [BUILD.md](BUILD.md).
Stable-identity setup changes the login keychain.
The development installer replaces the installed app and launches it.

## Permissions and everyday use

Allow **Microphone** and **Speech Recognition** to dictate.
Allow **Accessibility** if you want automatic paste.
Without Accessibility, use **Command-V** to paste the copied text yourself.

1. Focus the app and text field where you want the text.
2. Press **Option-Space**, or use the widget, to start.
3. Speak, then press **Option-Space** again to finish.
4. Use **Command-V** if automatic paste is unavailable or blocked.

If you change the destination app or field, the transcript stays on the clipboard for manual paste.
Expand the widget for the transcript, history, and settings.

Auto-send can submit a chat message or run a terminal command.
It starts off on a fresh installation, and your choice is saved.
Enable it only when you want Return sent to the current destination.

## Privacy and local storage

Talky's source requires local processing for every recognition request and has no network-recognition fallback.
It refuses to record if the selected recognizer cannot process speech on-device.
These checks rely on Apple's documented API behavior.
Runtime network activity and Apple's broader data handling have not been independently audited.
Talky's source is MIT licensed; Apple's recognition engine is proprietary.
Read [the privacy disclosure](docs/PRIVACY.md) and linked Apple policies.

Other apps can read clipboard contents, and the receiving app can use pasted text.
History, the latest-transcript file, and launch at login are **off on a fresh installation**.
Upgrades preserve saved preferences and existing launch-at-login registration.

If enabled, history can be kept for 1, 7, or 30 days, or until you delete it.
Retention is checked at startup, when history settings change, and after saving a dictation.
History lives in `~/.talky/voice_history/` as unencrypted files with owner-only permissions.
Turning history off stops new saves and leaves existing records available.
History deletion does not clear the clipboard or remove exported files.

The optional latest-transcript file is `~/.talky/voice_input.txt`.
Turning that setting off removes the file.
Scripts running as your user can control Talky through its command file.
Use trusted scripts and read [TESTING.md](TESTING.md) for the interface and isolated test results.

## Contribute

Useful work includes permission recovery, safe text delivery, accessibility, local languages, and live testing.
Start with [CONTRIBUTING.md](CONTRIBUTING.md) for focused tasks and the development workflow.

- [BUILD.md](BUILD.md): build, installation, and architecture.
- [TESTING.md](TESTING.md): automated checks and live tests.
- [PRODUCT.md](PRODUCT.md): user needs, priorities, and release checklist.
- [SECURITY.md](SECURITY.md): private vulnerability reporting.

The project source is [MIT licensed](LICENSE), copyright 2026 Lokaah.
Dependencies retain their licenses, including the optional [Remotion video toolchain](https://www.remotion.dev/license).
The old `v1.0.0` build and `assets/demo.*` are historical material, not evidence of today's behavior.
