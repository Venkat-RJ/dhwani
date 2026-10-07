#!/bin/bash
# Audio-loopback test. Test commands never paste or save normal history.
# This restarts Dhwani and temporarily changes the system audio devices.
# Usage: ./test/voice-test.sh --allow-system-changes [sentence_count]
set -euo pipefail
umask 077

if [ "${1:-}" != "--allow-system-changes" ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 --allow-system-changes [sentence_count]" >&2
    echo "This restarts Dhwani and temporarily routes system audio through BlackHole." >&2
    exit 2
fi
N="${2:-40}"
APP="${TALKY_APP_PATH:-/Applications/Dhwani.app}"
DATA_DIR="${TALKY_DATA_DIR:-$HOME/.talky}"
MIN_COVERAGE="${TALKY_MIN_COVERAGE:-0.95}"
START_TIMEOUT="${TALKY_TEST_START_TIMEOUT:-30}"
FINISH_TIMEOUT="${TALKY_TEST_FINISH_TIMEOUT:-30}"
case "$DATA_DIR" in
    /*) ;;
    *) echo "TALKY_DATA_DIR must be an absolute path." >&2; exit 2 ;;
esac
python3 -I - "$N" "$MIN_COVERAGE" "$START_TIMEOUT" "$FINISH_TIMEOUT" <<'PY'
import sys
try:
    n, threshold, start, finish = int(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    assert 1 <= n <= 10000 and 0 < threshold <= 1 and 1 <= start <= 300 and 1 <= finish <= 300
except (ValueError, AssertionError):
    sys.exit("Invalid sentence count, coverage threshold or timeout.")
PY
OPEN_HELP="$(open -h 2>&1 || true)"
if [[ "$OPEN_HELP" != *"--env"* ]]; then
    echo "This test requires open with --env support to isolate app storage." >&2
    exit 1
fi
command -v SwitchAudioSource >/dev/null || { echo "Install switchaudio-osx first." >&2; exit 1; }
SwitchAudioSource -a | grep -Fx "BlackHole 2ch" >/dev/null || {
    echo "Install BlackHole 2ch first." >&2; exit 1;
}
[ -d "$APP" ] || { echo "App not found: $APP" >&2; exit 1; }
mkdir -p "$DATA_DIR"
python3 -I - "$DATA_DIR" <<'PY'
import os, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
try:
    info = root.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError("Test storage must be a directory owned by your user")
    command = root / "talky_cmd"
    if command.exists() or command.is_symlink():
        info = command.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError("Command file must be a regular file owned by your user")
        command.chmod(0o600)
    root.chmod(0o700)
except (OSError, ValueError) as error:
    sys.exit(f"Unsafe test storage: {error}")
PY
DATA_DIR="$(cd "$DATA_DIR" && pwd -P)"
CMD="$DATA_DIR/talky_cmd"
RUN_ID="$(python3 -I -c 'import uuid; print(str(uuid.uuid4()).upper())')"
REQUESTED_AT="$(python3 -I -c 'import time; print(int(time.time()))')"
RESULT="$DATA_DIR/test-results/$RUN_ID.json"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/talky-voice-test.XXXXXX")"
ORIG_IN=""
ORIG_OUT=""
TEST_ACTIVE=0

cleanup() {
    local status=$? restore_failed=0
    trap - EXIT INT TERM HUP
    set +e
    if [ "$TEST_ACTIVE" -eq 1 ]; then
        printf 'test-stop:%s\n' "$RUN_ID" > "$CMD"
    fi
    if [ -n "$ORIG_IN" ]; then
        SwitchAudioSource -t input -s "$ORIG_IN" >/dev/null 2>&1 || restore_failed=1
    fi
    if [ -n "$ORIG_OUT" ]; then
        SwitchAudioSource -t output -s "$ORIG_OUT" >/dev/null 2>&1 || restore_failed=1
    fi
    rm -rf "$WORK_DIR"
    if [ "$restore_failed" -ne 0 ]; then
        echo "Audio restoration failed. Restore your input and output in System Settings." >&2
        if [ "$status" -eq 0 ]; then status=1; fi
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

python3 -I - "$N" > "$WORK_DIR/speech.txt" <<'PY'
import sys
n = int(sys.argv[1])
print(" ".join(f"This is test sentence number {i}." + (" [[slnc 600]]" if i % 6 == 0 else "") for i in range(1, n + 1)))
PY
cat > "$WORK_DIR/check-result.py" <<'PY'
import datetime, json, pathlib, re, sys
path, run_id, earliest, wanted = pathlib.Path(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4]
if not path.exists():
    sys.exit(10)
try:
    result = json.loads(path.read_text())
    assert result["runID"].lower() == run_id.lower(), "Result belongs to another run"
    started = datetime.datetime.fromisoformat(result["startedAt"].replace("Z", "+00:00"))
    assert started.timestamp() >= earliest, "Result predates this test"
    assert "blackhole" in result["microphone"].lower(), "App is not recording from BlackHole"
    phase = result["phase"]
    if phase in ("failed", "cancelled"):
        raise AssertionError(result.get("error") or f"Test {phase}")
    if phase != wanted:
        assert phase == "listening", f"Unexpected test phase: {phase}"
        sys.exit(10)
    if wanted == "completed":
        finished = datetime.datetime.fromisoformat(result["finishedAt"].replace("Z", "+00:00"))
        assert finished >= started, "Invalid test completion time"
        n, threshold = int(sys.argv[5]), float(sys.argv[6])
        text = result["transcript"].lower()
        words = dict(zip("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split(), range(20)))
        words.update(dict(zip("twenty thirty forty fifty sixty seventy eighty ninety".split(), range(20, 100, 10))))
        got = set()
        for match in re.finditer(r"\bsentence\s+number\s+", text):
            tokens = re.findall(r"\b(?:[a-z]+|\d+)\b", text[match.end():])
            total = current = 0
            for token in tokens:
                if token.isdigit():
                    current = int(token)
                    break
                if token in words:
                    current += words[token]
                elif token == "hundred":
                    current *= 100
                elif token == "thousand":
                    total += current * 1000
                    current = 0
                elif token == "and":
                    continue
                else:
                    break
            value = total + current
            if 1 <= value <= n:
                got.add(value)
        ratio = len(got) / n
        print(f"Sentence coverage: {len(got)}/{n} ({ratio:.1%}); {len(text.split())} recognized words")
        assert ratio >= threshold, f"Coverage below required {threshold:.1%}"
except (AssertionError, KeyError, TypeError, ValueError, OSError) as error:
    print(f"Test failed: {error}", file=sys.stderr)
    sys.exit(1)
PY

wait_for_result() {
    local wanted=$1 timeout=$2 status
    for ((attempt=0; attempt<timeout; attempt++)); do
        if python3 -I "$WORK_DIR/check-result.py" "$RESULT" "$RUN_ID" "$REQUESTED_AT" "$wanted" "$N" "$MIN_COVERAGE"; then
            return 0
        else
            status=$?
            if [ "$status" -ne 10 ]; then return "$status"; fi
        fi
        sleep 1
    done
    echo "Timed out waiting for test phase '$wanted'." >&2
    return 1
}

ORIG_IN="$(SwitchAudioSource -c -t input)"
ORIG_OUT="$(SwitchAudioSource -c -t output)"
[ -n "$ORIG_IN" ] && [ -n "$ORIG_OUT" ] || { echo "Could not read current audio devices." >&2; exit 1; }
SwitchAudioSource -t input -s "BlackHole 2ch" >/dev/null
SwitchAudioSource -t output -s "BlackHole 2ch" >/dev/null
PROCESS_PATTERN='Dhwani[.]app/Contents/MacOS/'
if pgrep -f "$PROCESS_PATTERN" >/dev/null; then
    pkill -TERM -f "$PROCESS_PATTERN"
    for ((attempt=0; attempt<30; attempt++)); do
        if ! pgrep -f "$PROCESS_PATTERN" >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -f "$PROCESS_PATTERN" >/dev/null; then
        echo "Dhwani did not quit. Test cancelled." >&2
        exit 1
    fi
fi
: > "$CMD"
open -n --env "TALKY_DATA_DIR=$DATA_DIR" "$APP"
sleep 2
TEST_ACTIVE=1
printf 'test-start:%s\n' "$RUN_ID" > "$CMD"
wait_for_result listening "$START_TIMEOUT"
echo "Dictating $N sentences into BlackHole..."
say -r 175 -f "$WORK_DIR/speech.txt"
sleep 1
printf 'test-stop:%s\n' "$RUN_ID" > "$CMD"
wait_for_result completed "$FINISH_TIMEOUT"
TEST_ACTIVE=0
echo "Test passed. Result: $RESULT"
