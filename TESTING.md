# Testing Lokaah Talky

How we test dictation end-to-end **without a human speaking** — by feeding
synthesized speech into the app's mic input through a virtual audio loopback.

## Why a loopback
The app captures from the live microphone, so there's nothing to "mock" in code.
Instead we route audio with **BlackHole** (a virtual audio device): macOS `say`
plays TTS into BlackHole's output, BlackHole loops it to its input, and the app
captures it as if it were a real mic. We drive start/stop through the app's
`~/.talky/talky_cmd` hook (write `start` / `stop` / `toggle`), then read back what
was captured.

## One-time setup
```bash
brew install switchaudio-osx
brew install --cask blackhole-2ch      # then once, to load the driver:
sudo killall coreaudiod
```

## Run it
```bash
./test/voice-test.sh           # ~40 sentences (~80s)
./test/voice-test.sh 150       # longer run (~7 min) — stress-tests long capture
```
The script: saves your current audio devices → routes input+output to BlackHole →
relaunches the app → `start` → `say`s a numbered script → `stop` → prints the
captured text and a coverage number → **restores your devices** (even on Ctrl-C).

## What it checks
- **Capture works and doesn't cut off** — the script is numbered ("sentence number
  1…N"), so coverage = how many numbers came back. Long runs verify that capture
  survives the per-session limit (we renew at pauses + accumulate across sessions).
- **Clipboard** — after a run, `pbpaste` holds the transcript (it's always copied).

Typical result on a clean signal: ~99% word coverage over a 7-minute run.

### Coverage caveat
The recognizer spells single digits as words ("number one"…"number nine") but uses
digits for 10+. A digit-only regex under-counts the first nine, so the script counts
both spelled and numeric forms. Don't trust a naive `grep "number [0-9]"`.

## Manual quick test
1. Focus a text field (Terminal, TextEdit, a chat box).
2. **⌥Space**, say a sentence, **⌥Space** again.
3. The text should appear there, and it's also on your clipboard (⌘V to re-paste).
   Turn on the **⏎** toggle if you want it to press Return after pasting.
