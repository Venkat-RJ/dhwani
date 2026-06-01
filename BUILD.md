# Building Lokaah Talky

How the app is structured, signed, and built. For install/use, see [README.md](README.md).

## Requirements

- macOS 14+ (project targets the macOS 26 SDK), Apple Silicon
- Xcode 16+ (command-line tools installed)

## Quick build

```bash
./setup-cert.sh         # once per machine
./reinstall.sh --build  # build + sign + install + launch
```

`./reinstall.sh` (no `--build`) re-signs and reinstalls the most recent build.
You can also open `Lokaah Talky.xcodeproj` in Xcode and Run.

## Project layout

```
Lokaah Talky.xcodeproj      # Xcode project (target/scheme: "Lokaah Talky")
Lokaah Talky/
  LokaahTalkyApp.swift      # the entire app — one file
  Assets.xcassets/          # app icon (green waveform mark)
assets/icon.png             # repo/logo copy of the icon
setup-cert.sh               # generates the local signing cert
reinstall.sh                # build → sign → install → launch
```

Bundle id: `com.lokaah.talky` · App: `/Applications/Lokaah Talky.app`.

## Architecture (LokaahTalkyApp.swift)

It's a SwiftUI menubar-less accessory app — no Dock icon, no main window. Everything is in one file:

- **`LokaahTalkyApp` / `AppDelegate`** — sets `.accessory` activation policy, creates the floating panel, registers the ⌥Space global hotkey (Carbon `RegisterEventHotKey`), the `~/.talky/talky_cmd` command watcher, and the login-at-launch item (`SMAppService`). A Combine observer resizes the panel between compact and full.
- **`FloatingPanel`** — a borderless, non-activating `NSPanel` at `.floating` level. Non-activating is what lets it never steal focus, so synthesized typing lands in the app you were using.
- **`RootView`** — the UI. Compact "presence" widget vs. full panel (waveform, transcript, history, toggles). Phosphor-terminal aesthetic.
- **`Waveform` / `MiniWaveform`** — audio-reactive green bars driven by the live mic level.
- **`SpeechManager`** — the engine. On-device `SFSpeechRecognizer`; long captures survive by renewing the recognition session at natural pauses and on session-end, accumulating committed text across sessions (a request "box" keeps the mic tap alive across renewals). Writes history to `~/.talky/voice_history/YYYY-MM-DD.md` and the latest line to `~/.talky/voice_input.txt`.
- **`TextInserter`** — inserts the transcript via the Accessibility API (`kAXSelectedText` on the focused element), with a CGEvent Unicode-keystroke fallback for apps that reject AX. Never touches the clipboard on the happy path.
- **`Paster`** — Accessibility-trust check/prompt and the synthetic Return key for auto-send.

## Signing (important)

Xcode signs the app **ad-hoc**, so its code hash changes on every build. macOS ties
permission grants (Microphone / Speech / Accessibility) to the code identity, so an
ad-hoc rebuild silently invalidates them — you'd re-grant every build.

`setup-cert.sh` creates a local self-signed code-signing cert **"Talky Self-Signed"**
in your login keychain. `reinstall.sh` re-signs each build with it:

```
codesign --force --deep --sign "Talky Self-Signed" "/Applications/Lokaah Talky.app"
```

That gives a **stable designated requirement** (`identifier "com.lokaah.talky" and
certificate leaf = <your cert>`), so grants persist across rebuilds. The cert does not
need to be trusted by Gatekeeper — codesign uses it locally and macOS only needs the
stable identity. Each developer generates their own cert; nothing secret is shared.

Without the cert, `reinstall.sh` falls back to ad-hoc and warns you (grants reset per build).

## Permissions

Declared in the build settings (auto-generated Info.plist keys):
`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`. Accessibility is
requested at runtime the first time the app needs to type.

Data lives in `~/.talky/` (`voice_history/`, `voice_input.txt`, `talky_cmd`).
