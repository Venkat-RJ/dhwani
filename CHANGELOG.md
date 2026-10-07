# Changelog

## Unreleased

Changes on `main` after the source-preview tag:

- Add a no-results message and Clear search button to History.
- Add a synthetic recognition corpus, evaluator, and tests for scoring and result provenance.
- Add private startup probes and CI startup checks on macOS 14 and 26.
- Add tooling for a signed, notarized release candidate, with acceptance tied to the final archive.
- Record user reports, test priorities, and completed verification separately.

## 1.1.0-beta.1 (source preview)

The first MIT-licensed public source preview.
A verified signed and notarized binary is still pending.
See the [release checklist](PRODUCT.md#release-readiness).

### Dictation and controls

- Require on-device recognition and explain when a local language is unavailable.
- Add language selection and local vocabulary settings.
- Keep the expanded panel within the display's usable area.
- Add cancellation and check the original app and focused field before delivery.
- Preserve available text after sleep or an audio-engine interruption, without automatic paste.
- Show the active microphone and explain missing or silent input.

### Privacy and history

- Make history, latest-transcript output, and launch at login opt-in.
- Add history search, copy, export, deletion, and retention controls.
- Apply owner-only permissions and remove extended ACL access, including during migration.
- Clear the export temporary file's ACL before writing transcript text.
- Keep isolated test captures separate from clipboard, paste, history, and automation output.

### Development and publication

- Harden the development signing and installation scripts.
- Add a standalone Command Line Tools build route.
- Upgrade the optional video toolchain to Remotion 4.0.533.
- Add MIT licensing, contributor and security guides, and CI.
- Describe actual clipboard behavior and test limits in place of unverified claims.
- Mark the old demo as historical and remove its download and quarantine-bypass instructions.

## 1.0.0

Historical internal release from 1 June 2026.
Introduced the floating dictation widget and local development distribution.
The binary and demo predate the current privacy and delivery changes.
