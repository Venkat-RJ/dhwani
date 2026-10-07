# Verification record

These checks were completed on 7 October 2026.
Each entry describes what was checked and what the result establishes.
Live dictation and verified binary distribution remain open in the [release checklist](../PRODUCT.md#release-readiness).

The project was subsequently renamed from Lokaah Talky to Dhwani.
Historical checks below retain their original hashes and artifact identity.
They do not establish acceptance of a renamed installer.

## Dhwani rename checks

The renamed source has SHA-256 `d74d23bf031cba0f6ee571179054e6cc8ac596c4139a135683c5445fd43f983e` at `Dhwani/DhwaniApp.swift`.
The standalone optimized build and strict ad-hoc signature verification passed.
Its bundle name, display name, executable, and permission purpose strings use Dhwani.
The bundle identifier remains `com.lokaah.talky` for compatibility.

All 96 automated checks passed: lifecycle 10, product core 19, mocked scripts 18, benchmark evaluator 17, release tooling 12, beta tooling 12, and startup consumer 8.
The additional installer check verifies that an older named copy blocks installation before either app or any process is changed.
The full unsigned Xcode build on this Mac remained blocked by the unaccepted Xcode license, exit 69.

A fresh isolated startup probe passed on macOS 27.0.1 arm64 for the renamed executable.
The compact widget and setup screen were visually checked without recording or granting permissions.
Historical candidate archives were not rebuilt or renamed and retain their original identity and acceptance limits.

## Unnotarized beta preparation

Local source commit `c9c63b9254b13aeffd60c61b27fe5c5afbc7657b` was packaged as private candidate `v1.1.0-beta.3`, version 1.1.0, build 3.
All 95 automated checks passed: the six suites below plus 12 checks for the unnotarized beta workflow.
The 24 release-tooling checks were rerun after correcting the `codesign` certificate-extraction argument in both workflows.
The correction was also checked with the real macOS signing tool.

The optimized standalone CLT build passed.
The exact archive passed strict signature verification, signer-certificate matching, hardened-runtime and audio-input entitlement checks, bundle and source inspection, and extraction checks.
Its SHA-256 is `4e2f1d573f19f3b36430067a12c41c7182e309d969c7ee37ff78e468e6607569`.

Startup passed on macOS 27.0.1 arm64 using the extracted archive.
A normal Launch Services launch reported the existing Microphone and Speech Recognition grants, an available recognizer, and on-device support.
Accessibility was not granted.
The direct subprocess startup check reported Speech Recognition as unauthorized; the normal launch reported it as authorized.
Neither check requested permissions or recorded audio.

The candidate verifier correctly rejected its incomplete live acceptance record.
This is a private, locally signed candidate, not a published download or an Apple-notarized release.
Live capture, paste, permission recovery, privacy observations, macOS 14 acceptance, and clean-Mac installation remain pending.
The installed app was not replaced by these tests.

[Current interface screenshots](SCREENSHOTS.md) were captured separately without personal data or recording permissions.

## Build and automated checks

| Revision | Checks completed | Evidence |
| --- | --- | --- |
| `4be10fd` | Full Xcode 26.2 Release build for arm64 and the automated checks configured for that preview. | [CI run](https://github.com/Venkat-RJ/dhwani/actions/runs/37579865860) |
| `24709bd58a05f3116cc1e38a4ff3f1842bf446d4` | Full Xcode 26.2 arm64 Release build, all 83 checks, dependency audit with zero reported vulnerabilities, and actual startup on macOS 14.8.9 and 26.6.2. | [CI run](https://github.com/Venkat-RJ/dhwani/actions/runs/37583963398) |
| `3d62bd8c8d9de50d226b4d3336d131260bdf3bbf` | Full Xcode build, all 83 checks, dependency audit, and actual startup on macOS 14 and 26 after the History search fix. | [CI run](https://github.com/Venkat-RJ/dhwani/actions/runs/37586930290) |

The 83 checks cover:

| Suite | Checks |
| --- | ---: |
| Recognition lifecycle | 10 |
| Product core | 19 |
| Mocked scripts | 17 |
| Benchmark evaluator | 17 |
| Release tooling | 12 |
| Startup consumer | 8 |

The source-preview release links its final checked revision and CI run.
Current `main` can contain later work.

## Local builds and startup

Standalone Debug and Release builds passed with Swift 6.3.2 and the macOS 26.5 SDK.
The executables encoded macOS 14.0 as their minimum version.

Full Xcode on the review machine exited with code 69 because its license was not accepted.
That is an environmental build failure.
The complete Xcode build passed separately in CI.

The read-only startup build passed locally on macOS 27.0.1.
Its Swift source SHA-256 was `15d9bd5268f49773fbc4af35d2a648d3ed08f29276f7189208e7a7e308b7858b`.

CI for `24709bd` launched the exact compiled app on macOS 14.8.9 and 26.6.2.
The per-process probes matched the same source hash.
The packaging and extraction path also passed locally on macOS 27.0.1.

These checks establish compilation, packaging, and startup.
They do not establish recording, permission recovery, local-model accuracy, automatic paste, or dictation on the minimum OS.

## Interface checks

The following local checks used optimized ad-hoc builds.
The hashes refer to `Lokaah Talky/LokaahTalkyApp.swift`.

| Source SHA-256 | What was observed |
| --- | --- |
| `f10c149b4ad5d87c93ee7c59a3e3f6fc8f3e60b3da478034ae5a4c04afbdd848` | Setup, settings, and empty History screens, without granting recording permissions. |
| `89f05657cfd5d14785622d9ee662fd3d325aa95cb78cd4630a4b3545754fc377` | Setup and scrollable settings controls on macOS 27.0.1. |
| `15d9bd5268f49773fbc4af35d2a648d3ed08f29276f7189208e7a7e308b7858b` | Synthetic History search, multiline and legacy display, export, and deletion cancellation on macOS 27.0.1. |
| `b07707fd8b90c55fcd22fcd12cd98942e9295cd2fdfebd4a4e8c437f3e81dd1c` | The no-results message and accessible Clear search button. Clicking the button cleared the filter and restored all four entries. |

### Synthetic History test

The test used a private data directory and a separate bundle identity.
It contained three synthetic JSONL records and one legacy Markdown record.

Case-insensitive search, multiline display, and legacy display passed.
The export dialog produced a file containing each of the four records once, with multiline text intact.
The exported file had owner-only `0600` permissions and no extended ACL entries.

The deletion dialog explained what it would remove.
Cancelling left all four records available.
Deletion itself was not performed in this UI test.

A search with no matches initially left a blank panel.
The fix added a no-results message and Clear search button.
A fresh test build showed both, and Clear search restored the records.

These tests do not verify opt-in persistence, actual deletion, recording, clipboard insertion, permission recovery, or release installation.

## Apple privacy disclosure update

The disclosure update used Swift source SHA-256 `e558d7b98d757f61b275d7ee9f7f733c21c1351422deeb5c8d04b51d2db247c6` from the working tree.
The recognition lifecycle suite passed 10 checks, product core passed 19, and mocked scripts passed 17.
The benchmark fixtures passed 17 checks, startup consumer fixtures passed 8, and binary release mocks passed 12.
All 83 automated checks passed for this source.
The fixture and mocked checks do not establish live capture, actual notarization, or clean-machine installation.
The optimized standalone CLT build passed.
The full unsigned Xcode attempt remained blocked by the unaccepted license, with exit code 69.

The local app was signed with the existing development identity and passed strict signature verification.
It replaced the installed app only after a fresh probe reported no active capture.
The relaunched app's probe matched the new source hash and reported the existing Microphone and Speech Recognition grants as authorized.
This was a local development update, not a notarized binary release.

The installed app's Apple provider label and Settings privacy text were visually checked on macOS 27.0.1.
Settings displayed the engine disclosure, audit limitation, and Apple policy link.
The build's Speech Recognition purpose string also named Apple's engine and required on-device processing.
The system permission dialog was not requested again.

No recording or runtime network audit was performed for this wording update.
See [the privacy disclosure](PRIVACY.md) for what the source checks establish and what remains unverified.

## Source publication review

The local review checked 40 current text files and 29 historical text blobs.
None matched the credential patterns used in that check.
No private key, environment-secret file, or transcript-storage path was found among the files prepared for publication.

The app icon was visually inspected.
The historical local demo has silent audio and generated graphics in its source.
The old MP4 and GIF have not been rerendered and are not current product evidence.

The old remote DMG was not downloaded or inspected.
This review does not certify that binary.

## What remains

Live recording, permission recovery, destination delivery, repeated accuracy measurements, and clean-machine installation remain pending.
Mocked release tests do not establish real signing or notarization.
Startup does not establish that a local speech model works.

Use [TESTING.md](../TESTING.md) for the next runtime checks and [BINARY-RELEASE.md](BINARY-RELEASE.md) for a signed release candidate.
