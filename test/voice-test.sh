#!/bin/bash
# End-to-end dictation test with NO human needed.
#
# It feeds synthesized speech (`say`) into the app's microphone input through a
# virtual audio loopback (BlackHole), drives start/stop via the ~/.talky/talky_cmd
# hook, then measures how much was captured. Uses a numbered script so coverage is
# checkable ("sentence number 1..N").
#
# One-time prerequisites:
#   brew install switchaudio-osx
#   brew install --cask blackhole-2ch     # then once: sudo killall coreaudiod
#
# Usage:  ./test/voice-test.sh [sentence_count]    (default 40 ≈ ~80s of speech)
#
# Audio devices are saved and restored automatically, even on Ctrl-C.

set -uo pipefail
APP="/Applications/Lokaah Talky.app"
CMD="$HOME/.talky/talky_cmd"
N="${1:-40}"

command -v SwitchAudioSource >/dev/null 2>&1 || { echo "Missing: brew install switchaudio-osx"; exit 1; }
SwitchAudioSource -a 2>/dev/null | grep -q "BlackHole 2ch" || {
    echo "Missing BlackHole. Run: brew install --cask blackhole-2ch  (then: sudo killall coreaudiod)"; exit 1; }
[ -d "$APP" ] || { echo "Install the app first: ./reinstall.sh --build"; exit 1; }

# Numbered TTS script (numbering = coverage check); a pause every 6 sentences.
TXT="$(mktemp /tmp/talky-test-XXXX.txt)"
python3 - "$N" >"$TXT" <<'PY'
import sys
n = int(sys.argv[1])
print(" ".join(f"This is test sentence number {i}." + (" [[slnc 600]]" if i % 6 == 0 else "") for i in range(1, n + 1)))
PY

# Save current devices; restore on any exit.
ORIG_IN="$(SwitchAudioSource -c -t input)"
ORIG_OUT="$(SwitchAudioSource -c -t output)"
restore() { SwitchAudioSource -t input -s "$ORIG_IN" >/dev/null 2>&1; SwitchAudioSource -t output -s "$ORIG_OUT" >/dev/null 2>&1; echo "[restored audio: in=$ORIG_IN out=$ORIG_OUT]"; }
trap restore EXIT

# Route everything through BlackHole and relaunch so the app captures from it.
SwitchAudioSource -t input  -s "BlackHole 2ch" >/dev/null
SwitchAudioSource -t output -s "BlackHole 2ch" >/dev/null
pkill -9 -f "Lokaah Talky.app/Contents/MacOS" 2>/dev/null
sleep 1.5
: > "$CMD"
open "$APP"
sleep 6   # let the on-device model warm up

echo "▶ dictating $N sentences into BlackHole..."
echo "start" > "$CMD"; sleep 2
say -r 175 -f "$TXT"
sleep 1; echo "stop" > "$CMD"; sleep 4

echo "=== captured (~/.talky/voice_input.txt) ==="
cat "$HOME/.talky/voice_input.txt"; echo
python3 - "$N" <<'PY'
import re, sys, os
n = int(sys.argv[1])
t = open(os.path.expanduser("~/.talky/voice_input.txt")).read().lower()
spelled = {"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9}
got = set(int(x) for x in re.findall(r"number (\d+)", t))
for w, v in spelled.items():
    if f"number {w}" in t:
        got.add(v)          # recognizer spells single digits as words
print(f"coverage: {len(got)}/{n} sentences, {len(t.split())} words")
PY
