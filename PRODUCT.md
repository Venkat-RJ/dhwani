# Product plan

## Purpose

Make voice dictation useful in everyday macOS work.
Keep recognition on-device and make text delivery predictable.
Name the recognition provider and explain what the privacy checks establish.

People should be able to write prose, take technical notes, and speak longer drafts.
They should also be able to use the widget and controls with a keyboard.

When something fails, explain what happened and where the available text can be found.
Let people cancel a capture and decide what gets saved.

## What is available

- A compact floating widget and an expanded transcript view.
- Option-Space to start or finish, and Option-Escape to cancel.
- Apple's on-device recognition with a selected language and local vocabulary hints.
- Clipboard copy and automatic paste when the original app and text field still match.
- Optional auto-send, history, retention, latest-transcript output, and launch at login.
- Isolated recording tests and startup probes.

These features are present in source.
Live recognition, long captures, and cross-app delivery still need acceptance testing.
There is no published accuracy benchmark or evidence that Talky is better than other dictation apps.
The current engine remains Apple's Speech framework.
The [privacy disclosure](docs/PRIVACY.md) distinguishes source configuration, Apple's policies, and unverified runtime network behavior.
Distribution can use an [unnotarized beta](docs/UNNOTARIZED-BETA.md) with a local signing certificate, or the [Apple-notarized release path](docs/BINARY-RELEASE.md).
Both require runtime acceptance of the final archive.

## What users have reported

We checked the reports below on 7 October 2026.
They come from other open-source projects.
They are individual observations, not Talky bug reports or a survey.

Some reports are closed.
They still provide useful test cases, but do not establish how common a problem is or whether it remains in the other app.
The priorities here are our interpretation of those reports.

### Keep the whole draft

A user compared the same long recording under two settings and received very different amounts of text.
See [VoiceInk #853](https://github.com/Beingpax/VoiceInk/issues/853).

Talky waits for recognition sessions to finish and retains available text after an interruption.
We have not verified complete long drafts in live tests.

Next check: repeat the four-minute corpus three times.
Inspect the beginning, middle, and end for missing or repeated words, and record the time to final text.

### Paste the right text and keep it recoverable

One macOS user reported older clipboard text being pasted instead of speech.
Another wanted the previous clipboard contents preserved.
See [Handy #502](https://github.com/cjpais/Handy/issues/502) and [#921](https://github.com/cjpais/Handy/issues/921).

Talky replaces the clipboard with regular dictation and uses Command-V after checking the destination.
It does not restore the previous clipboard contents.

Next check: inspect the actual receiving text in several apps, under load and after changing focus.
Ask users whether clipboard restoration would help before adding it.
A timed restore can run before a slow app reads the transcript.

### Recognize names without changing ordinary words

A Portuguese-language user requested contextual vocabulary and cautioned against unconditional replacement.
See [VoiceInk #862](https://github.com/Beingpax/VoiceInk/issues/862).

Talky supplies local vocabulary hints to the recognizer.
We have not measured their effect on accuracy.

Next check: compare the same utterances with hints on and off.
Score exact names and technical terms, with ordinary words as controls.
Record the locale and both lexical and locale-normalized scores.

### Make language choice predictable

A multilingual user preferred explicit language choice and wanted faster workflow switching.
See [Handy discussion #1534](https://github.com/cjpais/Handy/discussions/1534).

Talky shows the selected locale.
Frequent switching, Indian English, and code-switching still need testing.

Next check: alternate three captures between two locally available languages.
Record the selected language, output language, vocabulary behavior, and steps needed to switch.

### Make setup and upgrades understandable

A macOS user reported hidden setup after a microphone prompt and ineffective old Accessibility entries.
See [Handy #1618](https://github.com/cjpais/Handy/issues/1618).

Talky shows permission rows, checks permissions again, links to System Settings, and supports manual clipboard paste.
A stable local signing identity is available for development.
Live permission denial and recovery are still unverified.

Next check: fresh setup, return from System Settings, denial and regrant, and a signed upgrade.
Check that dictation remains usable without Accessibility.
Do not reset permissions automatically.

### Make activation usable

One user requested single-key double-tap activation because simultaneous keys were difficult.
Another reported a foreground app interfering with global shortcuts.
See [VoiceInk #516](https://github.com/Beingpax/VoiceInk/issues/516) and [Cline #14148](https://github.com/cline/cline/issues/14148).

Talky has fixed Option-Space and Option-Escape shortcuts, plus labeled controls.
Successful shortcut registration does not prove that everyone can use them in every app.

Next check: keyboard-only and VoiceOver tasks, different keyboard layouts, and activation in each supported destination.
Include feedback from people with limited dexterity before choosing another shortcut scheme.

### Help people find preserved work

A user found that recovery existed, but the failure message did not explain how to reach it.
See [TypeWhisper #1267](https://github.com/TypeWhisper/typewhisper-mac/issues/1267).

Talky exposes available transcript text, Copy, and interruption status.
It does not save raw audio for recovery.

Next check: ask a first-time tester to recover a synthetic partial result without instructions.
Check whether the app explains what was preserved and what was discarded.

### Make corrections practical

A discussion requested spoken punctuation and local corrections.
Participants also noted that command words can occur in ordinary text.
See [Handy discussion #1805](https://github.com/cjpais/Handy/discussions/1805).

Talky supports selecting and copying the transcript.
It has no correction editor or spoken-command parser.

Next check: eight synthetic examples with punctuation, corrections, and literal command words.
Measure the time and steps needed to finish the text.
Use those results to decide whether a small review-and-edit flow would help.

## Priorities

First, verify capture, recovery, and delivery.
Then measure vocabulary, language switching, correction, and activation friction.

The reports above do not justify adding cloud processing, saved raw audio, telemetry, automatic updates, or unconditional replacements by default.

## Feedback from real tasks

No Talky user interviews or observed external-user sessions have been completed.
Automated checks do not tell us whether people find the app useful or accessible.
Get permission before contacting participants or publishing their data.

Use synthetic text in a test environment the participant has agreed to use.
Include prose, technical notes, a long draft, and a keyboard-only task.
Use more than one locale where local models are available.

Before giving instructions, ask the tester to:

1. Start and stop a capture.
2. Find information about a missing permission or local model.
3. Recover text after automatic delivery is blocked.
4. Explain what history saves and what happens to the clipboard.

Record whether each task succeeds without help.
Note the steps, time, correction effort, unexpected behavior, and preferred recovery path.

Collect the input method, broad microphone type, OS, locale, and destination app.
Omit personal dictations and device or account names.

Keep observed results separate from preferences and proposed changes.
Include failed tasks.
Fix lost work, unintended insertion, blocked activation, and unclear recovery before adding more options.

## Release readiness

**1.1.0-beta.1 is a source preview.**
The checklist covers that preview and the work on `main` toward a verified downloadable app.
It was updated on 7 October 2026.
See [verification details](docs/VERIFICATION.md) for exact commits, hashes, CI runs, and limits.

### Source and development checks

- [x] Review and fix the identified privacy and delivery issues in source.
- [x] Review current source, reachable history, and artwork for private data, secrets, and attribution.
- [x] Apply MIT licensing and preserve dependency licenses.
- [x] Publish the source, contributor guidance, and private vulnerability reporting.
- [x] Keep the old binary release in a recoverable draft, outside the public download path.
- [x] Update the README and historical video source to describe the source preview and test limits.
- [x] Build with standalone Command Line Tools and verify the optimized bundle's source hash.
- [x] Pass the full Xcode build and all 83 automated checks in CI.
- [x] Audit the locked video dependencies with no reported vulnerabilities in the checked snapshot.
- [x] Add a synthetic corpus, evaluator, and tests for scoring and result provenance.
- [x] Add release tooling that requires signing, notarization, and completed acceptance of the exact final archive.
- [x] Disclose Apple's recognition engine, permission notice, and the limits of source-only privacy checks.

### App and distribution checks

- [x] Launch the optimized ad-hoc app on macOS 27.0.1 and validate a private startup probe.
- [x] Launch the compiled app on macOS 14 and 26 in CI.
- [x] Check synthetic History display, search, export, deletion cancellation, and Clear search on macOS 27.0.1.
- [ ] Complete live dictation acceptance on macOS 14 and a current macOS release on Apple Silicon.
- [ ] Check permission denial and recovery, microphone failure, cancellation, and unavailable local models.
- [ ] Test recognition with network access unavailable and inspect runtime network activity from the app and relevant speech services using synthetic audio. Record the environment, process attribution, and limits of the observations.
- [ ] Check delivery and explicit auto-send in TextEdit, a browser, a code editor, and Terminal.
- [ ] Check that changing the app or focused field blocks automatic delivery.
- [ ] Check opt-in storage, migration permissions, retention, and removal of test results in the live app.
- [ ] Repeat short and long recognition tests and review the transcripts.
- [ ] Publish benchmark inputs, locale, hardware, duration, errors, and completion latency before making performance claims.
- [ ] Review the final release archive and any new demo for private data, attribution, and current behavior.
- [ ] For an unnotarized beta, verify the local signature and checksums and test the app-specific approval flow on a clean Mac.
- [ ] For an Apple-notarized release, sign with Developer ID, notarize, checksum, and test installation on a clean Mac.

Startup and synthetic History checks do not establish live dictation or reliable cross-app paste.
Local signing does not establish a verified public download.
The remaining checks need approved app permissions and configured release-signing credentials.

## Benchmark plan

The [versioned synthetic corpus](test/benchmarks/README.md) has ten cases for `en-US` and `en-IN`.
It covers prose, technical names, numbers, spoken punctuation, and longer passages with pauses.
Its tests verify the evaluator, not recognition accuracy.

Use repeated loopback runs and at least one real microphone environment.
Measure word error rate against a reviewed reference.
Report missing or repeated segments, completion latency, and delivery success separately.
Use sentence-marker coverage only as a diagnostic.

Publish synthetic or consented samples, exact commits and settings, and failed cases alongside successes.
Keep private dictations out of shared results.
