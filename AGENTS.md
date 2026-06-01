# AGENTS.md — Lokaah Talky

Context for AI coding agents (Claude Code, Codex, Cursor, …) working in this repo.

**Internal & confidential — do not share this app, repo, or build outside Lokaah.**

## What this is
A macOS menubar-less **accessory app** (no Dock icon, no main window): a floating
widget that records speech **on-device** and types the transcript into whatever app
is focused. The **entire app is one file**: `Lokaah Talky/LokaahTalkyApp.swift`.

Bundle id `com.lokaah.talky` · installs to `/Applications/Lokaah Talky.app`.
Requirements: macOS 14+ (macOS 26 SDK), Apple Silicon, Xcode 16+.

## Build & run
- One-time per machine: `./setup-cert.sh` — creates the local `Talky Self-Signed`
  code-signing cert.
- Build + sign + install + launch: **`./reinstall.sh --build`**
  (re-run `./reinstall.sh` without `--build` to reinstall the last build).
- Or open `Lokaah Talky.xcodeproj` in Xcode and Run.
- `reinstall.sh` builds to a deterministic `build/` dir in the repo, so it never
  installs a stale same-named app from elsewhere.

## Architecture (`Lokaah Talky/LokaahTalkyApp.swift`)
- `AppDelegate` — `.accessory` policy, the floating `FloatingPanel` (borderless,
  non-activating, so it never steals focus), ⌥Space Carbon global hotkey, the
  `~/.talky/talky_cmd` command watcher, `SMAppService` launch-at-login, and a
  Combine observer that resizes the panel (compact ↔ full).
- `RootView` — compact "presence" widget vs. full panel; phosphor-terminal look.
- `SpeechManager` — on-device `SFSpeechRecognizer`; long captures survive by renewing
  the recognition session at natural pauses (+ on session end) and accumulating
  `committedText` across sessions; writes `~/.talky/voice_history/YYYY-MM-DD.md`.
- `Paster` — clipboard + synthesized ⌘V + Return.
- `Waveform` / `MiniWaveform` — audio-reactive bars.

Deeper detail: **BUILD.md**.

## Conventions & gotchas
- Edit the single Swift file; rebuild via `./reinstall.sh --build`.
- **Signing:** the app is re-signed with the stable self-signed cert so macOS
  permission grants (Microphone / Speech / Accessibility) persist across rebuilds.
  **Do NOT add `tccutil reset` to `reinstall.sh`** — that was the old ad-hoc workaround.
- **Text insertion:** dictation **always copies to the clipboard**, then pastes with
  **⌘V**. ⌘V works everywhere (incl. Terminal). Do not make AX `kAXSelectedText` the
  primary insertion path — Terminal rejects it.
- Data dir is `~/.talky/` (`voice_history/`, `voice_input.txt`, `talky_cmd`).
- Never commit `build/`, `DerivedData/`, `video/node_modules/`, `.DS_Store` (see `.gitignore`).
- The explainer video is Remotion source in `video/` (`cd video && npm run render`).

## Testing
End-to-end dictation is tested with a virtual-audio loopback (BlackHole) + `say`,
driven through the `~/.talky/talky_cmd` hook — no human needed. Run
`./test/voice-test.sh [sentence_count]`. Details and the coverage caveat are in
**TESTING.md**.
