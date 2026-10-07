#!/usr/bin/env python3
"""Failure cases for identity and privacy checks in the live startup consumer."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location("startup_smoke", Path(__file__).with_name("startup-smoke.py"))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class ProbeValidationTests(unittest.TestCase):
    def setUp(self):
        self.probe = {"schemaVersion": 1, "kind": "readiness", "runID": "12345678-1234-1234-1234-123456789ABC",
                      "createdAt": "2026-10-07T10:00:01.123Z", "processID": 1234,
                      "sourceSHA256": "a" * 64, "gitCommit": "b" * 40, "buildMethod": "ci-startup-test",
                      "version": "1.1.0", "build": "2", "osMajor": 14, "osMinor": 8, "osPatch": 9,
                      "architecture": "arm64", "phase": "denied", "busy": False,
                      "microphoneAllowed": False, "speechAllowed": False, "accessibilityAllowed": False,
                      "supportsOnDeviceRecognition": True, "recognizerAvailable": True}
        self.expected = {"run_id": self.probe["runID"], "process_id": 1234,
                         "started": smoke.utc("2026-10-07T10:00:00Z"), "now": smoke.utc("2026-10-07T10:00:02Z"),
                         "source": "a" * 64, "commit": "b" * 40, "os_major": 14,
                         "info": {"TalkyBuildMethod": "ci-startup-test", "CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "2"}}

    def validate(self, **changes):
        probe = copy.deepcopy(self.probe)
        probe.update(changes)
        return smoke.validate_probe(probe, **self.expected)

    def test_missing_permissions_are_valid_readiness_not_dictation_acceptance(self):
        self.assertEqual(self.validate(), self.probe)

    def test_wrong_uuid_process_or_identity_fails(self):
        for field, value in {"runID": "another", "processID": 9999, "sourceSHA256": "c" * 64,
                             "gitCommit": "c" * 40, "version": "1.0.0", "build": "1", "kind": "capture"}.items():
            with self.subTest(field=field), self.assertRaises(smoke.SmokeError):
                self.validate(**{field: value})

    def test_stale_future_or_non_utc_results_fail(self):
        for value in ("2026-10-07T09:59:59Z", "2026-10-07T10:00:05Z", "2026-10-07T10:00:01", None):
            with self.subTest(value=value), self.assertRaises(smoke.SmokeError):
                self.validate(createdAt=value)

    def test_transcripts_and_unknown_fields_fail(self):
        for field in ("transcript", "microphone", "vocabulary", "statusMessage", "accountName"):
            with self.subTest(field=field), self.assertRaises(smoke.SmokeError):
                self.validate(**{field: "Unexpected private data"})

    def test_active_capture_and_wrong_platform_fail(self):
        for change in ({"phase": "listening", "busy": True}, {"phase": "processing"},
                       {"osMajor": 26}, {"architecture": "x86_64"}, {"osMajor": True}):
            with self.subTest(change=change), self.assertRaises(smoke.SmokeError):
                self.validate(**change)

    def test_non_boolean_flags_fail(self):
        for field in ("busy", "microphoneAllowed", "speechAllowed", "accessibilityAllowed",
                      "supportsOnDeviceRecognition", "recognizerAvailable"):
            with self.subTest(field=field), self.assertRaises(smoke.SmokeError):
                self.validate(**{field: 0})

    def test_boolean_schema_is_not_an_integer_version(self):
        with self.assertRaises(smoke.SmokeError):
            self.validate(schemaVersion=True)


@unittest.skipUnless(sys.platform == "darwin", "macOS startup process cleanup")
class InterruptedHarnessTests(unittest.TestCase):
    def test_interruption_reaps_only_launched_child_and_cleans_private_directory(self):
        for interruption in (signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=interruption), tempfile.TemporaryDirectory(prefix="talky-smoke-interruption-") as name:
                fixture = Path(name)
                app = fixture / "Lokaah Talky.app"
                executable = app / "Contents/MacOS/Lokaah Talky"
                executable.parent.mkdir(parents=True)
                info = {"CFBundleIdentifier": "com.lokaah.talky", "CFBundleExecutable": "Lokaah Talky",
                        "TalkySourceSHA256": "a" * 64, "TalkyGitCommit": "b" * 40,
                        "CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "2"}
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
                marker = fixture / "launched-child.json"
                executable.write_text(
                    "#!" + sys.executable + "\n"
                    "import json,os,pathlib,time\n"
                    "data=pathlib.Path(os.environ['TALKY_DATA_DIR'])\n"
                    "(data/'talky_cmd').write_text('')\n"
                    "pathlib.Path(" + repr(str(marker)) + ").write_text(json.dumps({'pid':os.getpid(),'data':str(data)}))\n"
                    "while True: time.sleep(0.1)\n")
                executable.chmod(0o755)
                harness = fixture / "harness.py"
                harness.write_text(
                    "import importlib.util,sys\n"
                    "spec=importlib.util.spec_from_file_location('smoke'," + repr(str(Path(smoke.__file__))) + ")\n"
                    "module=importlib.util.module_from_spec(spec)\n"
                    "spec.loader.exec_module(module)\n"
                    "module.command=lambda *args: ''\n"
                    "sys.argv=['startup-smoke','run','--app'," + repr(str(app)) + ","
                    "'--source-sha256','" + "a" * 64 + "','--commit','" + "b" * 40 + "','--timeout','60']\n"
                    "sys.exit(module.main())\n")
                unrelated = subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(30)"],
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                runner = subprocess.Popen([sys.executable, "-I", str(harness)],
                                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                child = None
                try:
                    deadline = time.monotonic() + 5
                    while not marker.exists():
                        self.assertIsNone(runner.poll(), "Harness exited before launching its dummy child")
                        self.assertLess(time.monotonic(), deadline, "Dummy launch timed out")
                        time.sleep(0.05)
                    launched = json.loads(marker.read_text())
                    child = launched["pid"]
                    data = Path(launched["data"])
                    self.assertEqual(data.stat().st_mode & 0o777, 0o700)
                    runner.send_signal(interruption)
                    stdout, stderr = runner.communicate(timeout=10)
                    self.assertNotEqual(runner.returncode, 0, stdout + stderr)
                    with self.assertRaises(ProcessLookupError):
                        os.kill(child, 0)
                    self.assertFalse(data.parent.exists(), "Private smoke directory survived interruption")
                    self.assertIsNone(unrelated.poll(), "Cleanup terminated an unrelated process")
                finally:
                    if runner.poll() is None:
                        runner.kill()
                        runner.communicate(timeout=5)
                    if child is not None:
                        try:
                            os.kill(child, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                    if unrelated.poll() is None:
                        unrelated.terminate()
                    unrelated.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
