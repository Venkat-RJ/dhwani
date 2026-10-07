# Changelog

## 1.1.0-beta.1 (source preview)

Prepared for an MIT public-source preview.
There is no verified signed and notarized binary for this version.
Runtime and distribution verification are tracked in [PRODUCT.md](PRODUCT.md).

- Require on-device recognition and explain unavailable local languages.
- Add settings for language and local vocabulary.
- Make history, latest-transcript persistence, and launch at login opt-in.
- Add searchable history with copy, export, deletion, and retention controls.
- Apply owner-only storage permissions and clear extended ACL access, including during migration.
- Export through a private temporary file whose ACL is cleared before writing transcript data.
- Add cancellation and check the original app and focused element before delivery.
- Preserve available text after system sleep or an audio-engine interruption and withhold automatic paste.
- Show the microphone used by the capture and explain missing or silent input.
- Keep isolated test captures separate from clipboard, paste, history, and automation output.
- Harden development signing and installation scripts, and add a standalone Command Line Tools build route.
- Upgrade the optional video toolchain to Remotion 4.0.533.
- Add MIT licensing, contributor guidance, security reporting guidance, and CI.
- Replace unverified coverage and clipboard claims with the actual behavior and test limits.
- Label the demo source as historical and remove its old download and quarantine-bypass instructions.

## 1.0.0

Historical internal release from 1 June 2026.
It introduced the floating dictation widget and local development distribution.
Its binary and demo predate the current hardening work.
