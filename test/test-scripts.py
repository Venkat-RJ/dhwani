#!/usr/bin/env python3
"""Regression tests using copied scripts, private fixtures and mocked macOS tools."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MOCK_TOOL = r'''#!/usr/bin/env python3
import datetime, json, os, pathlib, re, shutil, subprocess, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
base = pathlib.Path(os.environ["MOCK_ROOT"])
case = os.environ.get("MOCK_CASE", "success")
with (base / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"tool": name, "args": args}) + "\n")
if name == "security":
    if args[0] == "find-certificate":
        sys.exit(1 if case.startswith("cert-new") else 0)
    if args[0] == "find-identity":
        if case not in ("no-identity", "cert-orphan"):
            print('  1) FAKEHASH "Talky Self-Signed"')
        sys.exit(0)
    sys.exit(1 if case == "cert-new-import-fails" else 0)
if name == "openssl":
    if args[0] == "rand":
        print("f" * 64)
    for flag in ("-keyout", "-out"):
        if flag in args:
            pathlib.Path(args[args.index(flag) + 1]).write_text("fixture")
    sys.exit(1 if case == "cert-new-key-fails" and args[0] == "req" else 0)
if name == "xcodebuild":
    print("BUILD SUCCEEDED")
    sys.exit(7 if case == "build-fails" else 0)
if name == "ditto":
    if case == "copy-fails":
        pathlib.Path(args[1]).mkdir()
        sys.exit(1)
    shutil.copytree(args[0], args[1])
    sys.exit(0)
if name == "codesign":
    sys.exit(1 if case == "sign-fails" or (case == "verify-fails" and "--verify" in args) else 0)
if name == "mv":
    source = pathlib.Path(args[0])
    if case == "replace-fails" and source.parent.name.startswith(".talky-install.") and source.name == "Dhwani.app":
        sys.exit(1)
    sys.exit(subprocess.call(["/bin/mv", *args]))
if name == "open":
    if "-h" in args:
        print("Usage: open" if case == "no-open-env" else "Usage: open --env VAR")
        sys.exit(0)
    if case == "launch-fails":
        sys.exit(1)
    if case != "app-crashes":
        (base / "running").write_text("running")
    sys.exit(0)
if name == "pgrep":
    if (base / "running").exists():
        print("1234")
        sys.exit(0)
    sys.exit(1)
if name == "pkill":
    (base / "running").unlink(missing_ok=True)
    sys.exit(0)
if name == "SwitchAudioSource":
    if "-a" in args:
        print("Built-in Input\nBuilt-in Output\nBlackHole 2ch")
    elif "-c" in args:
        print("Built-in Input" if "input" in args else "Built-in Output")
    elif case == "route-fails" and "output" in args and "BlackHole 2ch" in args:
        sys.exit(1)
    elif case == "restore-fails" and "Built-in Output" in args:
        sys.exit(1)
    sys.exit(0)
if name == "say":
    if case == "interrupted":
        import signal
        os.kill(os.getppid(), signal.SIGINT)
        sys.exit(130)
    if case == "tts-fails":
        sys.exit(1)
    script = pathlib.Path(args[args.index("-f") + 1]).read_text()
    (base / "spoken").write_text(re.sub(r"\[\[.*?\]\]", "", script))
    sys.exit(0)
if name == "sleep":
    data = pathlib.Path(os.environ["TALKY_DATA_DIR"])
    command_path = data / "talky_cmd"
    if not command_path.exists():
        sys.exit(0)
    command = command_path.read_text().strip()
    if not command.startswith(("test-start:", "test-stop:")):
        sys.exit(0)
    operation, run_id = command.split(":", 1)
    results = data / "test-results"
    results.mkdir(exist_ok=True)
    path = results / (run_id + ".json")
    stamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    if operation == "test-start":
        result = {"runID": run_id, "phase": "listening", "transcript": "", "error": None,
                  "startedAt": stamp, "finishedAt": None, "microphone": "BlackHole 2ch"}
        if case == "wrong-run":
            result["runID"] = "00000000-0000-0000-0000-000000000000"
        if case == "stale-result":
            result["startedAt"] = "2000-01-01T00:00:00Z"
        if case == "wrong-mic":
            result["microphone"] = "Built-in Input"
        if case == "recognition-fails":
            result["phase"], result["error"] = "failed", "Recognizer unavailable"
        if case == "no-result":
            sys.exit(0)
    else:
        result = json.loads(path.read_text())
        result["phase"], result["finishedAt"] = "completed", stamp
        result["transcript"] = os.environ.get("MOCK_TRANSCRIPT", (base / "spoken").read_text() if (base / "spoken").exists() else "")
    path.write_text(json.dumps(result))
    command_path.write_text("")
    sys.exit(0)
sys.exit("Unexpected mock tool: " + name)
'''


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="talky-script-tests-")
        self.base = Path(self.temp.name)
        self.project = self.base / "project"
        self.project.mkdir()
        for name in ("reinstall.sh", "setup-cert.sh"):
            shutil.copy2(ROOT / name, self.project / name)
        shutil.copy2(ROOT / "test/voice-test.sh", self.project / "voice-test.sh")
        self.destination = self.base / "Applications"
        self.destination.mkdir()
        self.app = self.destination / "Dhwani.app"
        self.app.mkdir()
        (self.app / "old-marker").write_text("previous")
        source = self.project / "build/Build/Products/Debug/Dhwani.app/Contents"
        (source / "MacOS").mkdir(parents=True)
        (source / "Info.plist").write_text("fixture")
        binary = source / "MacOS/Dhwani"
        binary.write_text("fixture")
        binary.chmod(0o755)
        (source.parent / "new-marker").write_text("new")
        self.data = self.base / "data"
        self.data.mkdir()
        self.tmp = self.base / "temporary"
        self.tmp.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        runner = self.bin / "mock-tool.py"
        runner.write_text(MOCK_TOOL)
        runner.chmod(0o755)
        for name in ("security", "openssl", "xcodebuild", "ditto", "codesign", "mv", "open", "pgrep", "pkill", "SwitchAudioSource", "say", "sleep"):
            (self.bin / name).symlink_to(runner)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        MOCK_ROOT=str(self.base), TALKY_DEST_DIR=str(self.destination),
                        TALKY_APP_PATH=str(self.app), TALKY_DATA_DIR=str(self.data),
                        TALKY_TEST_START_TIMEOUT="3", TALKY_TEST_FINISH_TIMEOUT="3", TMPDIR=str(self.tmp))

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, script, *args, case="success", transcript=None):
        (self.base / "calls.jsonl").write_text("")
        env = dict(self.env, MOCK_CASE=case)
        if transcript is not None:
            env["MOCK_TRANSCRIPT"] = transcript
        return subprocess.run(["/bin/bash", str(self.project / script), *args],
                              env=env, text=True, capture_output=True, timeout=20)

    def calls(self):
        path = self.base / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def assert_preserved(self):
        self.assertTrue((self.app / "old-marker").exists())
        self.assertFalse((self.app / "new-marker").exists())
        self.assertEqual(list(self.destination.glob(".talky-install.*")), [])

    def assert_audio_restored(self):
        calls = self.calls()
        for kind, device in (("input", "Built-in Input"), ("output", "Built-in Output")):
            self.assertTrue(any(call["tool"] == "SwitchAudioSource" and call["args"] == ["-t", kind, "-s", device] for call in calls))

    def test_install_success_and_verification_before_replacement(self):
        result = self.run_script("reinstall.sh", "--build")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.app / "new-marker").exists())
        self.assertFalse((self.app / "old-marker").exists())
        calls = self.calls()
        verify = next(i for i, call in enumerate(calls) if call["tool"] == "codesign" and "--verify" in call["args"])
        replace = next(i for i, call in enumerate(calls) if call["tool"] == "mv")
        self.assertLess(verify, replace)
        self.assertEqual(list(self.destination.glob(".talky-install.*")), [])
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_build_failure_ignores_success_text_and_preserves_app(self):
        result = self.run_script("reinstall.sh", "--build", case="build-fails")
        self.assertNotEqual(result.returncode, 0)
        self.assert_preserved()
        self.assertNotIn("OK Installed", result.stdout)

    def test_rename_refuses_a_second_copy_without_changing_either_app(self):
        legacy = self.destination / "Lokaah Talky.app"
        legacy.mkdir()
        (legacy / "old-marker").write_text("previous brand")
        result = self.run_script("reinstall.sh", "--build")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("before installing Dhwani", result.stderr)
        self.assert_preserved()
        self.assertEqual((legacy / "old-marker").read_text(), "previous brand")
        self.assertEqual(self.calls(), [])
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_install_preparation_failures_preserve_app(self):
        for case in ("no-identity", "copy-fails", "sign-fails", "verify-fails"):
            with self.subTest(case=case):
                result = self.run_script("reinstall.sh", case=case)
                self.assertNotEqual(result.returncode, 0)
                self.assert_preserved()
                self.assertFalse(any(call["tool"] == "pkill" for call in self.calls()))

    def test_install_move_and_launch_failures_restore_previous_app(self):
        for case in ("replace-fails", "launch-fails", "app-crashes"):
            with self.subTest(case=case):
                result = self.run_script("reinstall.sh", case=case)
                self.assertNotEqual(result.returncode, 0)
                self.assert_preserved()
                self.assertNotIn("OK Installed", result.stdout)
                (self.base / "running").unlink(missing_ok=True)

    def test_certificate_import_restricts_key_and_cleans_files(self):
        result = self.run_script("setup-cert.sh", case="cert-new")
        self.assertEqual(result.returncode, 0, result.stderr)
        imported = next(call["args"] for call in self.calls() if call["tool"] == "security" and call["args"][0] == "import")
        self.assertNotIn("-A", imported)
        self.assertIn("-x", imported)
        self.assertEqual(imported[imported.index("-T") + 1], "/usr/bin/codesign")
        self.assertFalse(Path(imported[1]).exists())
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_certificate_failures_clean_private_files(self):
        for case in ("cert-new-key-fails", "cert-new-import-fails", "cert-orphan"):
            with self.subTest(case=case):
                self.assertNotEqual(self.run_script("setup-cert.sh", case=case).returncode, 0)
                self.assertEqual(list(self.tmp.iterdir()), [])

    def test_existing_certificate_identity_is_preserved(self):
        result = self.run_script("setup-cert.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call["tool"] == "openssl" or (call["tool"] == "security" and call["args"][0] == "import") for call in self.calls()))

    def test_voice_requires_explicit_system_change_option(self):
        result = self.run_script("voice-test.sh", "40")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_voice_success_uses_private_result_and_preserves_latest(self):
        latest = self.data / "voice_input.txt"
        latest.write_text("existing private transcript")
        result = self.run_script("voice-test.sh", "--allow-system-changes", "40")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("40/40", result.stdout)
        self.assertEqual(latest.read_text(), "existing private transcript")
        launch = next(call["args"] for call in self.calls() if call["tool"] == "open" and "-h" not in call["args"])
        self.assertEqual(launch, ["-n", "--env", "TALKY_DATA_DIR=" + str(self.data.resolve()), str(self.app)])
        self.assert_audio_restored()
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_voice_rejects_relative_storage_before_any_system_changes(self):
        self.env["TALKY_DATA_DIR"] = "relative-data"
        result = self.run_script("voice-test.sh", "--allow-system-changes", "40")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_voice_requires_launch_environment_support(self):
        result = self.run_script("voice-test.sh", "--allow-system-changes", "40", case="no-open-env")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call["tool"] == "SwitchAudioSource" for call in self.calls()))

    def test_voice_rejects_symlinked_command_without_touching_target(self):
        target = self.base / "private-target"
        target.write_text("preserve me")
        (self.data / "talky_cmd").symlink_to(target)
        result = self.run_script("voice-test.sh", "--allow-system-changes", "40")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "preserve me")
        self.assertFalse(any(call["tool"] == "SwitchAudioSource" and "-s" in call["args"] for call in self.calls()))

    def test_python_optimization_cannot_disable_coverage_check(self):
        self.env["PYTHONOPTIMIZE"] = "1"
        result = self.run_script("voice-test.sh", "--allow-system-changes", "40", transcript="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Coverage below required", result.stderr)

    def test_voice_launch_route_tts_and_recognition_failures_restore_audio(self):
        for case in ("launch-fails", "route-fails", "tts-fails", "recognition-fails", "no-result", "restore-fails", "interrupted"):
            with self.subTest(case=case):
                result = self.run_script("voice-test.sh", "--allow-system-changes", "40", case=case)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assert_audio_restored()
                self.assertEqual(list(self.tmp.iterdir()), [])

    def test_voice_rejects_stale_wrong_token_and_wrong_microphone(self):
        for case in ("stale-result", "wrong-run", "wrong-mic"):
            with self.subTest(case=case):
                result = self.run_script("voice-test.sh", "--allow-system-changes", "40", case=case)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assert_audio_restored()

    def test_voice_coverage_empty_duplicates_and_out_of_range_fail(self):
        for transcript in ("", "This is test sentence number one. " * 40,
                           "sentence number 1000. sentence number one hundred."):
            with self.subTest(transcript=transcript[:30]):
                result = self.run_script("voice-test.sh", "--allow-system-changes", "40", transcript=transcript)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("Coverage below required", result.stderr)

    def test_voice_counts_spelled_numbers_without_prefix_matches(self):
        result = self.run_script("voice-test.sh", "--allow-system-changes", "3",
                                 transcript="Sentence number one. Sentence number two. Sentence number three. Sentence number one hundred.")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("3/3", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
