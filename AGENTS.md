# AGENTS.md

## Project and writing

Dhwani is an MIT-licensed macOS voice-dictation project.
The public repository includes source and an experimental beta download.
Verified binary distribution has separate release gates; beta publication does not establish that those gates passed.
Never use em dashes in new writing.
Use short paragraphs, clear new lines, and factual claims.

Read `README.md`, `BUILD.md`, `TESTING.md`, and `PRODUCT.md` before changing behavior.
App code lives in `Dhwani/DhwaniApp.swift`.
The bundle identifier is `com.lokaah.talky`.
Target macOS 14 on Apple Silicon with Xcode 26 or newer.

## Build and test

- Use an unsigned `xcodebuild` with a separate derived-data directory for verification.
- Run `./test/run-unit-tests.sh`, `./test/run-product-tests.sh`, and `python3 test/test-scripts.py`.
- `./setup-cert.sh` changes the login keychain.
- `./reinstall.sh --build` replaces and launches the installed app.
- `./test/voice-test.sh --allow-system-changes [sentence_count]` changes audio routing.

Do not run the last three commands merely to inspect the project.
Record environmental build failures without treating them as app defects.
Do not add `tccutil reset` to the installer.

## Boundaries to preserve

- Require supported on-device recognition before installing the microphone tap. Never fall back to network recognition.
- Keep capture state on the main actor and synchronize the request used by the audio callback.
- Scope callbacks, timeouts, and delivery work to the capture that created them.
- Regular dictation copies to the clipboard and uses Command-V for paste. Do not replace it with AX selected-text insertion.
- Require the original app and focused element to match before paste and Return. Do not reactivate a stale target.
- Auto-send, history, latest-transcript persistence, and launch at login start off.
- Cancellation and isolated test captures must not perform normal delivery or persistence.
- Store private directories with `0700` and private files with `0600`.
- Keep private keys, recordings, real transcripts, permissions databases, build outputs, and dependency directories out of Git.

The command interface is a same-user scripting capability, not an authentication boundary.
Treat changes to that interface, retention, signing, and text delivery as changes requiring meaningful verification.

## Claims and publication

Do not claim recognition accuracy or reliable capture length from a numbered-sentence coverage score.
Do not claim a full build, live test, minimum-OS test, signing, or notarization passed unless that exact check passed.
The files under `assets/demo.*` are historical marketing, not current runtime evidence.
Use the canonical repository URL `https://github.com/Venkat-RJ/dhwani`.
Verify GitHub authentication and effective Git author before commits or pushes.
Do not rewrite attribution in existing history.
