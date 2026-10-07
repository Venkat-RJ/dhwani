# Product scope and release readiness

## Purpose

Make daily voice dictation useful across macOS apps while keeping recognition local and delivery deliberate.
The main uses are prose, technical notes, short code and terminal instructions, and longer spoken drafts.
The app should also remain usable through keyboard controls and accessible labels.

The widget should explain permission problems, unavailable local models, and blocked delivery in plain language.
Users should be able to cancel, retrieve a transcript, and choose whether anything is retained.

## Current scope

- Floating compact widget and expanded transcript view.
- Option-Space to start or finish, Option-Escape to cancel.
- On-device recognition for a supported selected locale and local contextual vocabulary.
- Clipboard delivery with automatic paste only to the unchanged original app and focused element.
- Optional auto-send, history, retention, latest-transcript automation output, and launch at login.
- Isolated command-driven test captures with per-run result files.

Cross-app accuracy and long-capture reliability require runtime evidence.
There is no claim of competitive superiority or a published recognition benchmark.
Historical marketing files are not proof of current behavior.

## Release readiness

The target is **1.1.0-beta.1, a source preview**.
It is not a verified downloadable app.
These checks were recorded on 7 October 2026 for the source-preview revision.
Unchecked items remain pending.

Source publication:

- [x] Review the privacy and delivery changes and resolve the identified source findings.
- [x] Pass the local lifecycle, product, and mocked-script suites: 10, 17, and 17 checks respectively.
- [x] Audit the locked video dependencies with no reported vulnerabilities in the current snapshot.
- [x] Build the complete app with standalone Command Line Tools and verify the optimized local bundle's source hash.
- [x] Review current source, reachable Git history, and app artwork for private data, secrets, and attribution.
- [x] Confirm MIT licensing and preserve applicable dependency licenses.
- [x] Update the README and historical video source to describe source builds and the current verification limits.
- [x] Publish the reviewed source and pass its required automated checks.
- [x] Retire the historical release from the public download path while preserving its tag and assets in a recoverable draft.
- [x] Enable private vulnerability reporting and verify the public repository settings after publication.
- [x] Pass the full Xcode build, logic checks, script checks, and dependency audit in CI.

The local source review included 40 current text files and 29 historical text blobs with no matches for the credential patterns checked.
No private key, environment-secret file, or transcript-storage path was found among the files prepared for publication.
The app icon was visually inspected. The historical local demo has silent audio and generated graphics in its source.
These checks do not certify the old remote DMG, which was not downloaded or inspected.
The legacy MP4 and GIF have not been rerendered and are not current product evidence.

Runtime and downloadable app:

- [x] Build the complete app with the documented Xcode toolchain in CI.
- [ ] Run the app on macOS 14 and a current macOS release on Apple Silicon.
- [ ] Check permission denial and recovery, microphone failure, cancellation, and unsupported local models.
- [ ] Verify delivery and explicit auto-send in TextEdit, a browser, a code editor, and Terminal.
- [ ] Verify changed app and changed focused element block automatic delivery.
- [ ] Verify opt-in storage, migration permissions, retention, and removal of test results.
- [ ] Run repeated short and long real recognition tests and review transcripts.
- [ ] Record a reproducible benchmark corpus, locale, hardware, duration, errors, and completion latency before publishing performance numbers.
- [ ] Review the exact release artifact and any replacement demo for private data, attribution, and current behavior.
- [ ] Produce a signed, notarized release artifact with checksums and test its installation on a clean machine.

Unsigned and ad-hoc local bundles are described in [BUILD.md](BUILD.md).
The initial preview commit `4be10fd` passed [CI](https://github.com/Venkat-RJ/lokaah-talky/actions/runs/37579865860), including the full Xcode 26.2 Release build for arm64.
The source-preview release links the final checked revision and its CI run.
The optimized ad-hoc bundle was launched and its setup, settings, and empty-history screens were observed without granting recording permissions.
Its Swift source SHA-256 is `f10c149b4ad5d87c93ee7c59a3e3f6fc8f3e60b3da478034ae5a4c04afbdd848`.
That UI check does not verify recognition, permission recovery, or cross-app delivery.
The full Xcode build remains blocked locally by an unaccepted Xcode license; CI validation is pending.
Source publication leaves the incomplete runtime and distribution checks visible.

## Benchmark plan

Use a small, reproducible corpus with ordinary prose, technical names, spoken punctuation, and longer passages with natural pauses.
Include at least one real microphone environment as well as the synthetic loopback test.
Measure word error rate against a reviewed reference, missing or duplicated segments, completion latency, and delivery success separately.
Keep sentence-marker coverage as a diagnostic rather than an accuracy metric.

Publish synthetic or consented samples, the exact commit and settings, and failed cases alongside successful ones.
Do not include private user dictations.
