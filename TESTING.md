# Testing Lokaah Talky

## Checks without microphone or installation changes

```bash
./test/run-unit-tests.sh
./test/run-product-tests.sh
python3 test/test-scripts.py
```

The unit and product suites cover the deterministic logic and privacy boundaries they explicitly exercise.
The script suite uses mocked commands to check installer, signing, and loopback behavior.
These checks do not prove live transcription, Accessibility delivery, or permission dialogs.

CI is configured to build an unsigned app on macOS 15 using Xcode 26.2 and run these checks.
It also audits the locked video dependencies.
CI does not grant microphone access, register a login item, change audio devices, or install the app.
See [BUILD.md](BUILD.md) for both the standalone CLT and Xcode build commands.
The full Xcode build on the review machine remains blocked by its unaccepted license.
Standalone CLT Debug and Release bundles have compiled locally; those builds do not establish live dictation or macOS 14 runtime acceptance.

## Live loopback test

This test changes system audio routing and launches the chosen app.
Run it only on a machine where those changes are acceptable.
It requires BlackHole 2ch, `SwitchAudioSource`, and already granted Microphone and Speech Recognition access.
Install those prerequisites separately using their official instructions.

```bash
./test/voice-test.sh --allow-system-changes 40
```

To select a separately built app and private test directory:

```bash
./build-local.sh --release --adhoc
talky_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/talky-loopback.XXXXXX")"
TALKY_APP_PATH="$PWD/build/local/Lokaah Talky.app" \
TALKY_DATA_DIR="$talky_test_dir" \
./test/voice-test.sh --allow-system-changes 40
```

Grant the required permissions to that chosen build before running the test.
Ad-hoc rebuilds can require new permission grants.

The flag is required.
The script records the existing input and output devices, selects BlackHole, requests an isolated capture, plays numbered sentences using macOS `say`, then restores the devices on exit.
It checks the requested capture's token, timestamps, microphone identity, and final state before scoring.
A stale normal transcript is never evidence of a successful test.

Configuration:

| Variable | Default | Purpose |
| --- | --- | --- |
| `TALKY_APP_PATH` | `/Applications/Lokaah Talky.app` | App to launch |
| `TALKY_DATA_DIR` | `~/.talky` | Absolute data directory passed to the app |
| `TALKY_MIN_COVERAGE` | `0.95` | Required numbered-sentence coverage |
| `TALKY_TEST_START_TIMEOUT` | `30` | Seconds to wait for listening |
| `TALKY_TEST_FINISH_TIMEOUT` | `30` | Seconds to wait for completion |

Timeout values must be between 1 and 300 seconds.
The default sentence count is 40.
`TALKY_DATA_DIR` must be an absolute path.
The script validates the owned directory and command file, then passes the resolved path into a fresh app process through `open -n --env`.
The harness and the app therefore use the same command and result directory.
If the installed `open` command lacks environment support, the script fails before changing audio routing.

## Command interface and test isolation

The watcher consumes commands from `<data-directory>/talky_cmd`, using `~/.talky` by default.
Regular `start`, `stop`, `toggle`, and `cancel` commands control ordinary dictation.
Only trusted scripts running as your user should use this interface.

Tests use `test-start:<UUID>` and `test-stop:<UUID>`.
Each capture writes `<data-directory>/test-results/<UUID>.json` with a phase of `listening`, `completed`, `failed`, or `cancelled`.
Test captures must not change the clipboard, paste into an app, press Return, save normal history, or update `voice_input.txt`.
Result files can contain test transcripts and should be deleted when no longer needed.

Numbered-sentence coverage measures how many expected sentence markers appear.
It is not word accuracy, punctuation accuracy, code accuracy, or proof of a gapless recording.
Claims about long captures need repeated runs and review of the actual transcript.
Zero coverage, duplicated markers, wrong run tokens, stale timestamps, unexpected microphones, recognition errors, and missing terminal results fail the test.
Cleanup stops only the requested test capture before restoring the saved devices.

## Manual acceptance checks

- Dictate into TextEdit, a browser text box, a code editor, and an inactive terminal prompt.
- Move to another app and another field during processing. Check that automatic paste is withheld.
- Leave auto-send off and confirm no Return occurs. Test explicitly enabled auto-send with harmless text.
- Cancel during capture and processing. Check that no transcript is delivered or stored.
- Deny and later restore each permission. Check the explanation and recovery path.
- Check an unavailable local language model, microphone disconnection, and recognition failure.
- Enable each storage option separately, inspect permissions, and test history retention.
- Run a longer capture with pauses and confirm that early and late words survive session renewal.

Record the exact commit, hardware, OS, locale, duration, destination app, and outcome.
Use synthetic or redacted text in shared reports.
