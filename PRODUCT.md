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
- Read-only readiness probes for automated app startup checks.

Cross-app accuracy and long-capture reliability require runtime evidence.
There is no claim of competitive superiority or a published recognition benchmark.
Historical marketing files are not proof of current behavior.

## Evidence from dictation users

The following primary reports were checked on 7 October 2026.
They are a small sample from other open-source projects, not Talky bug reports, a survey, or evidence of how common a problem is.
Some reports are now closed. Their historical observations still define useful validation cases; closure alone does not prove a current defect or fix.
The priorities below are our interpretation of those reports.

| Need and source | Talky today | Next evidence needed |
| --- | --- | --- |
| Keep complete long drafts and identify incomplete output. A reporter compared the same long recording under two settings and obtained very different output lengths. [VoiceInk #853](https://github.com/Beingpax/VoiceInk/issues/853) | Capture-scoped sessions drain before finalization; interruptions retain available text. Full-length live results remain unverified. | Repeat the four-minute corpus three times. Inspect early, middle, and final text, deletion/duplication diagnostics, and completion latency. |
| Insert the right text while keeping it recoverable. A macOS user reported older clipboard contents appearing instead of speech. A separate user wanted their prior clipboard preserved. [Handy #502](https://github.com/cjpais/Handy/issues/502), [#921](https://github.com/cjpais/Handy/issues/921) | Regular dictation deliberately replaces the clipboard and pastes with Command-V after destination checks. Prior clipboard restoration is not implemented. | Verify actual receiving-app contents under load and changed focus. Validate the clipboard tradeoff with users before adding restoration; a timed restore can race a slow receiver. |
| Recognize names and technical terms without changing ordinary words indiscriminately. A Portuguese-language user requested contextual vocabulary and cautioned against unconditional replacement. [VoiceInk #862](https://github.com/Beingpax/VoiceInk/issues/862) | Local vocabulary hints are supplied to recognition. Their accuracy benefit has not been measured. | Paired vocabulary-on/off utterances with exact-name scoring and ordinary-word controls. Keep locale and lexical scores visible. |
| Make language choice predictable. A multilingual user preferred explicit language choice and requested faster workflow switching. [Handy discussion #1534](https://github.com/cjpais/Handy/discussions/1534) | The selected locale is explicit. Frequent switching, Indian English, and code-switching have not been accepted. | Alternate three captures between two locally available languages and record selection steps, output language, and vocabulary behavior. |
| Explain incomplete setup and recover after an upgrade. A macOS report described hidden onboarding after a microphone prompt and ineffective old Accessibility entries. [Handy #1618](https://github.com/cjpais/Handy/issues/1618) | Explicit permission rows, polling, settings links, stable local signing, and clipboard-only delivery are available. Runtime denial/recovery remains pending. | Fresh setup, returning from System Settings, deny/regrant, and one signed upgrade. Verify the user can continue without granting Accessibility. Do not reset permissions automatically. |
| Support activation that fits the user and foreground app. One user requested single-key double-tap activation because simultaneous keys were difficult; another report described app-specific global-shortcut interference. [VoiceInk #516](https://github.com/Beingpax/VoiceInk/issues/516), [Cline #14148](https://github.com/cline/cline/issues/14148) | Fixed Option-Space/Option-Escape shortcuts and labeled clickable controls exist. Registration checks do not prove universal usability. | Keyboard-only and VoiceOver tasks, limited-dexterity feedback, multiple keyboard layouts, and activation in each supported destination. Choose any new shortcut scheme from observed needs. |
| Find preserved work when something fails. A user found recovery existed but the failure banner did not explain how to reach it. [TypeWhisper #1267](https://github.com/TypeWhisper/typewhisper-mac/issues/1267) | Available transcript text, Copy, and interruption status are exposed. Raw recordings are not saved for recovery. | Ask a first-time tester to recover a synthetic partial result without telling them where to look. Explain precisely what was preserved and what was discarded. |
| Correct speech into usable text without ambiguous command behavior. A discussion requested spoken punctuation and local correction, while participants noted that command words can also be ordinary text. [Handy discussion #1805](https://github.com/cjpais/Handy/discussions/1805) | The transcript can be selected and copied. It has no correction editor or spoken-command parser. | Eight synthetic correction and literal-command examples; measure time and steps to finish. Evaluate a small review/edit flow before a broader command system. |

First priority is dependable capture, recovery, and destination delivery.
Then measure vocabulary, locale, correction, and activation friction.
These observations do not justify adding cloud processing, raw-audio persistence, telemetry, automatic updates, or unconditional text replacements by default.

## Task-based feedback

No Talky user interviews or observed external-user sessions have been completed.
The source preview and automated checks cannot establish that real users find the app useful or accessible.
Do not contact participants or publish their data without separate authorization.

Use synthetic text in a separately permitted test environment.
Include a prose-writing task, technical notes, a long draft, and a keyboard-only task, with more than one locale where local models are available.
Before instructions, ask the tester to start and stop, find missing permission or local-model information, recover text after blocked delivery, and explain history/clipboard behavior.
Record whether each task succeeds unaided, the steps and time required, correction effort, unexpected behavior, and the tester's preferred recovery path.
Collect input method, broad microphone type, OS, locale, and destination app; omit personal dictated content and device/account names.

Keep observed task outcomes separate from reported preferences and proposed fixes.
Include failed tasks alongside successful ones.
Prioritize issues that lose work, insert unintended text, prevent activation, or make recovery unclear before adding options.

## Release readiness

The published **1.1.0-beta.1 release is a source preview**.
This checklist also tracks current `main` changes needed before a verified downloadable app.
These checks were recorded on 7 October 2026 for the source-preview revision.
Unchecked items remain pending.

Source publication:

- [x] Review the privacy and delivery changes and resolve the identified source findings.
- [x] Pass the local lifecycle, product, and mocked-script suites: 10, 19, and 17 checks respectively.
- [x] Audit the locked video dependencies with no reported vulnerabilities in the current snapshot.
- [x] Build the complete app with standalone Command Line Tools and verify the optimized local bundle's source hash.
- [x] Review current source, reachable Git history, and app artwork for private data, secrets, and attribution.
- [x] Confirm MIT licensing and preserve applicable dependency licenses.
- [x] Update the README and historical video source to describe source builds and the current verification limits.
- [x] Publish the reviewed source and pass its required automated checks.
- [x] Retire the historical release from the public download path while preserving its tag and assets in a recoverable draft.
- [x] Enable private vulnerability reporting and verify the public repository settings after publication.
- [x] Pass the full Xcode build, logic checks, script checks, and dependency audit in CI.
- [x] Add a synthetic recognition corpus, evaluator, and scoring/evidence fixture tests without claiming measured accuracy.
- [x] Add a signed/notarized candidate workflow and tests that reject incomplete exact-artifact acceptance.
- [x] Pass benchmark evaluator, release-tool, and startup-consumer regression suites: 17, 12, and 8 checks respectively.

The local source review included 40 current text files and 29 historical text blobs with no matches for the credential patterns checked.
No private key, environment-secret file, or transcript-storage path was found among the files prepared for publication.
The app icon was visually inspected. The historical local demo has silent audio and generated graphics in its source.
These checks do not certify the old remote DMG, which was not downloaded or inspected.
The legacy MP4 and GIF have not been rerendered and are not current product evidence.

Runtime and downloadable app:

- [x] Build the complete app with the documented Xcode toolchain in CI.
- [x] Launch the optimized ad-hoc test app on macOS 27.0.1 and validate a private read-only readiness result.
- [x] Pass actual startup checks of the compiled app on macOS 14 and macOS 26 in CI.
- [x] Check synthetic History display, case-insensitive search, export, and deletion cancellation in an isolated app on macOS 27.0.1.
- [ ] Complete live dictation acceptance on macOS 14 and a current macOS release on Apple Silicon.
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
An earlier optimized preview bundle was launched and its setup, settings, and empty-history screens were observed without granting recording permissions.
Its Swift source SHA-256 is `f10c149b4ad5d87c93ee7c59a3e3f6fc8f3e60b3da478034ae5a4c04afbdd848`.
That UI check does not verify recognition, permission recovery, or cross-app delivery.
The responsive panel build was subsequently launched on macOS 27.0.1 and its setup and scrollable settings controls were observed.
That UI build's source SHA-256 is `89f05657cfd5d14785622d9ee662fd3d325aa95cb78cd4630a4b3545754fc377`.
The later read-only startup-probe build also passed an isolated launch check, with source SHA-256 `15d9bd5268f49773fbc4af35d2a648d3ed08f29276f7189208e7a7e308b7858b`.
Commit `24709bd58a05f3116cc1e38a4ff3f1842bf446d4` passed [CI](https://github.com/Venkat-RJ/lokaah-talky/actions/runs/37583963398): the full Xcode 26.2 arm64 Release build, all 83 automated checks, and the locked dependency audit with zero reported vulnerabilities.
That workflow launched its exact compiled app on macOS 14.8.9 and 26.6.2, validating per-process read-only probes with the same source hash.
The same packaging and extraction path was also exercised locally on macOS 27.0.1.
These checks do not accept recording, permission recovery, automatic delivery, or minimum-OS dictation.
The History UI was separately exercised with three synthetic JSONL records and one legacy Markdown record in a private data directory and a distinct test bundle identity.
The tested source hash was `15d9bd5268f49773fbc4af35d2a648d3ed08f29276f7189208e7a7e308b7858b`.
Case-insensitive search, multiline display, and legacy display passed.
The actual export dialog produced a file containing each of the four records once, preserving multiline text, with owner-only `0600` permissions and no extended ACL entries.
The deletion dialog explained its scope; cancelling left all four records available.
An unmatched search exposed a blank-panel usability defect, addressed by a no-results message and a Clear search button.
The fixed optimized app was launched with a fresh test identity and the same synthetic records, using source SHA-256 `b07707fd8b90c55fcd22fcd12cd98942e9295cd2fdfebd4a4e8c437f3e81dd1c`.
The no-results message and accessible Clear search control were observed; clicking it cleared the filter and restored all four entries.
These isolated UI checks do not verify opt-in persistence, actual deletion, recording, clipboard insertion, permission recovery, or release installation.
The full Xcode build remains blocked locally by an unaccepted Xcode license. CI has verified the complete Xcode build separately.
Source publication leaves the incomplete runtime and distribution checks visible.

## Benchmark plan

Use a small, reproducible corpus with ordinary prose, technical names, spoken punctuation, and longer passages with natural pauses.
[The versioned synthetic corpus and evaluator](test/benchmarks/README.md) provide ten cases for `en-US` and `en-IN`.
Their fixture tests validate scoring and result provenance checks. Live measurements remain pending.
Include at least one real microphone environment as well as the synthetic loopback test.
Measure word error rate against a reviewed reference, missing or duplicated segments, completion latency, and delivery success separately.
Keep sentence-marker coverage as a diagnostic rather than an accuracy metric.

Publish synthetic or consented samples, the exact commit and settings, and failed cases alongside successful ones.
Do not include private user dictations.
