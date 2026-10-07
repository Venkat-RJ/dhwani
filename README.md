<p align="center"><img src="assets/icon.png" width="72" alt="Dhwani icon"></p>

# Dhwani

**Voice typing for your Mac.**

[Visit the website](https://venkat-rj.github.io/dhwani/)

Press **Option-Space**, speak, then press it again to finish.
Dhwani turns your speech into text, copies it, and can paste it into the text field where you started.
It uses Apple's speech engine and requires an available on-device language model.

## Download and install

**There is no public download link yet. Dhwani is in early testing.**

A private DMG test package has been prepared. [Volunteer for a coordinated test](docs/EARLY-TESTING.md) to request access.
Once a maintainer provides the file, open it and drag **Dhwani** into **Applications**.
Then open Dhwani and allow Microphone and Speech Recognition access.
No Xcode or terminal commands are needed to install that package.
It is not Apple-notarized, so macOS may also require **Open Anyway** in Privacy & Security.

**[Volunteer to try the early beta](docs/EARLY-TESTING.md)**

For Apple Silicon Macs, M1 or newer. The build targets macOS 14 or newer; live dictation on macOS 14 still needs testing.
Windows, Linux, and Intel Macs are not supported by this build.

## How you use it

1. Click the text field you want to write in.
2. Press **Option-Space** to start speaking, then again to finish.
3. Dhwani copies the text. With Accessibility permission, it can also paste for you.

Without Accessibility, press **Command-V** yourself.
If you switch apps or text fields during dictation, automatic paste is withheld.
Press **Option-Escape** to cancel.

Dhwani stays in a small floating widget. Expand it for the transcript and settings.
You can choose a speech language, add vocabulary hints, and enable local history.
Auto-send starts off; turning it on can submit a message or run a terminal command.

<p><img src="assets/widget-current.jpg" width="230" alt="Current compact Dhwani widget before setup"></p>

<details>
<summary>See the setup screen</summary>

<p><img src="assets/setup-current.jpg" width="380" alt="Dhwani setup with the Apple speech disclosure and separate Microphone, Speech Recognition, and Accessibility permissions"></p>

Actual interface captured on 7 October 2026 from an isolated app copy, before recording permissions were granted.
[Capture details](docs/SCREENSHOTS.md).

</details>

## Privacy and local storage

Apple supplies the recognition engine and language models.
Dhwani's source requires on-device recognition and has no network-recognition fallback.
This relies on Apple's API behavior; runtime network activity has not been independently audited.
Read the [Apple speech and privacy disclosure](docs/PRIVACY.md) before granting access.

Regular dictation replaces your clipboard. Other apps can read that text.
History, the latest-transcript file, and launch at login start off on a fresh installation.
Upgrades keep your saved preferences. [Storage, retention, and deletion details](docs/LOCAL-STORAGE.md).

## Build and run

**For developers:** [BUILD.md](BUILD.md) covers building from source with Xcode or Command Line Tools.
GitHub's **Source code** archives contain developer files, not an installable app.

## Help improve Dhwani

[Test the app](docs/EARLY-TESTING.md), [report a bug](https://github.com/Venkat-RJ/dhwani/issues/new?template=bug_report.yml), or [contribute a fix](CONTRIBUTING.md).
We need help with installation, permission recovery, dictation, and pasting into everyday apps.

Live dictation, cross-app paste, privacy observations, and installation on a fresh Mac still need acceptance testing.
No recognition-accuracy or reliable capture-length claim has been established.
See [completed checks](docs/VERIFICATION.md), the [release checklist](PRODUCT.md#release-readiness), and [test instructions](TESTING.md).
Report vulnerabilities [privately](SECURITY.md).

[![Build and checks](https://github.com/Venkat-RJ/dhwani/actions/workflows/ci.yml/badge.svg)](https://github.com/Venkat-RJ/dhwani/actions/workflows/ci.yml)

[MIT licensed](LICENSE). Dependencies retain their own licenses, including the optional [Remotion video toolchain](https://www.remotion.dev/license).
The old `v1.0.0` build and `assets/demo.*` are historical material.
