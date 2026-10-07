# Testing Lokaah Talky

## Start with automated checks

These suites run without recording audio or changing the installed app.

```bash
./test/run-unit-tests.sh
./test/run-product-tests.sh
python3 test/test-scripts.py
python3 -I test/benchmarks/test_benchmark.py
python3 -I test/test-startup-smoke.py
python3 -I test/test-release.py
```

The unit and product suites check deterministic logic and privacy boundaries.
The script suite mocks installer, signing, and loopback commands.
Passing these checks does not verify live transcription, Accessibility delivery, or permission dialogs.

CI builds an unsigned app on macOS 15 with Xcode 26.2, runs these suites, and audits the locked video dependencies.
It sends an ad-hoc test copy to macOS 14 and macOS 26 runners for startup checks.
The receiving jobs check the copy against the same workflow's commit, source hash, executable hash, and archive checksum.
These temporary test copies are not notarized downloads.
CI does not grant microphone access, register a login item, change audio devices, or install the app.

Local CLT Debug and Release builds have passed.
The review machine's full Xcode build remains blocked by its unaccepted license; CI has verified Xcode separately.
Builds alone do not verify live dictation or macOS 14 runtime behavior.
See [BUILD.md](BUILD.md) for build commands and [PRODUCT.md](PRODUCT.md#release-readiness) for passed and pending checks.

## Startup without recording

This harness launches the selected app with a fresh private data directory, sends `test-probe:<UUID>`, then terminates only that process.
It checks the result's UUID, process ID, source and build identity, timestamp, actual OS, file modes, and ACLs.
It requests no permissions and records no audio.
App startup creates an isolated command file; the harness checks that no normal transcript storage was created.

```bash
./build-local.sh --release --adhoc --output-dir build/startup-local
talky_source_hash=$(shasum -a 256 "Lokaah Talky/LokaahTalkyApp.swift" | awk '{print $1}')
DEVELOPER_DIR=/Library/Developer/CommandLineTools python3 -I test/startup-smoke.py run \
  --app "$PWD/build/startup-local/Lokaah Talky.app" \
  --source-sha256 "$talky_source_hash" --result build/startup-local/result.json
```

The result destination must not already exist.
A CI artifact also requires `--commit`, matching the transferred manifest and app.
A successful launch does not verify permission recovery, recording, local model accuracy, Accessibility delivery, or installation.

The macOS 14 hosted image is [scheduled to retire on 2 November 2026](https://github.com/actions/runner-images/blob/main/images/macos/macos-14-arm64-Readme.md).
When that runner is unavailable, continue macOS 14 checks on a separately maintained machine.

## Live loopback test

This test launches the chosen app and changes system audio routing.
Use a machine where those changes are acceptable.
It requires BlackHole 2ch, `SwitchAudioSource`, and Microphone and Speech Recognition access already granted to the chosen build.
Install the tools separately using their official instructions.
Ad-hoc rebuilds can require new permission grants.

```bash
./test/voice-test.sh --allow-system-changes 40
```

To use a separate build and private test directory:

```bash
./build-local.sh --release --adhoc
talky_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/talky-loopback.XXXXXX")"
TALKY_APP_PATH="$PWD/build/local/Lokaah Talky.app" \
TALKY_DATA_DIR="$talky_test_dir" \
./test/voice-test.sh --allow-system-changes 40
```

`--allow-system-changes` is required.
The script saves the current input and output devices, selects BlackHole, starts an isolated capture, and plays numbered sentences with macOS `say`.
On exit, it stops only the requested test capture and restores the saved devices.
Before scoring, it checks the capture's token, timestamps, microphone identity, and final state.
A stale normal transcript cannot pass the test.

| Variable | Default | Purpose |
| --- | --- | --- |
| `TALKY_APP_PATH` | `/Applications/Lokaah Talky.app` | App to launch |
| `TALKY_DATA_DIR` | `~/.talky` | Absolute data directory passed to the app |
| `TALKY_MIN_COVERAGE` | `0.95` | Required numbered-sentence coverage |
| `TALKY_TEST_START_TIMEOUT` | `30` | Seconds to wait for listening |
| `TALKY_TEST_FINISH_TIMEOUT` | `30` | Seconds to wait for completion |

The default sentence count is 40; timeouts must be between 1 and 300 seconds.
`TALKY_DATA_DIR` must be absolute.
The script checks directory and command-file ownership, resolves the path, and passes it to a fresh app process through `open -n --env`.
The app and harness use the same directory for commands and results.
If `open` lacks environment support, the script fails before changing audio routing.

Coverage counts unique expected sentence markers. Repeated markers count once.
It does not measure word, punctuation, or code accuracy, or prove that a recording has no gaps.
Long-capture claims need repeated runs and review of the actual transcript.
The test fails on insufficient unique coverage, wrong run tokens, stale timestamps, unexpected microphones, recognition errors, or missing terminal results.

## Command interface and test isolation

The app reads commands from `<data-directory>/talky_cmd`, under `~/.talky` by default.
`start`, `stop`, `toggle`, and `cancel` control ordinary dictation.
Use this interface only with trusted scripts running as your user.

Isolated captures use `test-start:<UUID>` and `test-stop:<UUID>`.
Each writes `<data-directory>/test-results/<UUID>.json`, with phase `listening`, `completed`, `failed`, or `cancelled`.
Test captures must not change the clipboard, paste, press Return, save normal history, or update `voice_input.txt`.
Results can contain test transcripts. Delete them when no longer needed.

`test-probe:<UUID>` writes `<data-directory>/probe-results/<UUID>.json`.
It reports permission and recognizer flags, build identity, OS version, and process identity.
It contains no transcript, microphone name, vocabulary, history, or user-facing status text.
The probe leaves any active capture unchanged: it cannot start, stop, or cancel one.

## Recognition accuracy benchmark

[The synthetic benchmark](test/benchmarks/README.md) supplies ten cases for `en-US` and `en-IN`, including prose, technical terms, numbers, spoken punctuation, and four-minute passages.
Preparation creates text and an incomplete metadata template without playing or recording audio.
The evaluator scores actual isolated results, including failed captures, using lexical and documented locale-normalized word error rates.
It reports missing or duplicated segments, punctuation errors, and completion-latency bounds separately.
The fixture tests check scoring, not recognition quality.

Run repeated loopback and real-microphone tests before making performance claims.
Keep failed cases and their runtime details alongside successful ones.
Check delivery accuracy and exact executable terminal syntax separately.

## Binary release checks

[The binary release workflow](docs/BINARY-RELEASE.md) prepares a private Developer ID candidate from an exact source tag, notarizes and staples it, and verifies the repackaged archive.
Its mocked tests do not use real credentials.
The exact final artifact still needs live tests and a clean-machine installation check.

## Check live behavior

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
