<p align="center">
  <img src="assets/icon.png" width="120" alt="Lokaah Talky">
</p>

<h1 align="center">Lokaah Talky</h1>

<p align="center">Fast, private voice dictation for macOS. Speak anywhere — your words appear at the cursor.</p>

<p align="center"><em>Internal tool · Lokaah · not for public distribution</em></p>

---

A floating, always-on-top dictation widget. Press a hotkey, talk, and the transcript is typed into whatever app is focused — terminal, editor, chat, browser. Speech recognition runs **on-device**, so audio never leaves your Mac.

- **Talk anywhere** — direct text insertion at the cursor (no clipboard clobber).
- **Long-form** — captures a full conversation (10 min+) without cutting off; ~99% coverage.
- **On-device & private** — Apple's on-device recognition; offline, no servers.
- **Compact presence** — a small widget you dictate into in place; expand (⤢) for the full panel.
- **History** — every dictation saved to `~/.talky/voice_history/`, browsable in-app (🕑).
- **Launches at login** and stays out of your way.

## Install & use (for the team)

**Requirements:** macOS 14+ (built against the macOS 26 SDK), Apple Silicon, Xcode 16+.

```bash
git clone https://github.com/venkat-lokaah/lokaah-talky.git
cd lokaah-talky
./setup-cert.sh        # once: creates your local signing cert (keeps permissions stable)
./reinstall.sh --build # builds, signs, installs to /Applications, launches
```

Or just open `Lokaah Talky.xcodeproj` in Xcode and hit Run.

**First launch** prompts for three permissions — grant all:
- **Microphone** + **Speech Recognition** — to hear and transcribe you.
- **Accessibility** — to type the transcript into the focused app. (Without it, it only copies to the clipboard.)

With the cert from `setup-cert.sh`, you grant these **once** and they persist across rebuilds.

## Using it

- **⌥Space** anywhere (or click the widget) → start/stop dictation. It stays compact while you talk.
- Speak; on stop the text is typed into the focused app.
- **⤢** opens the full panel (live transcript, history, toggles); **⤡** minimizes back.
- **🕑** browse all past dictations. **⏎** toggle auto-send (press Return after typing — e.g. to run a terminal command).
- Scriptable: write `start` / `stop` / `toggle` to `~/.talky/talky_cmd` to drive it from any script.

## How it's built

See **[BUILD.md](BUILD.md)** for architecture, the signing setup, and build details.

---

<p align="center">© Lokaah — internal &amp; confidential.</p>
