#!/usr/bin/env python3
"""Isolated binary-release regression tests. Never uses real signing or networking."""
import copy
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CERTIFICATE = b"isolated-test-certificate-not-a-real-key"
FINGERPRINT = hashlib.sha1(CERTIFICATE).hexdigest().upper()
TEAM = "TESTTEAM01"
SUBMISSION = "11111111-2222-3333-4444-555555555555"

MOCK_TOOL = r'''
import hashlib, json, os, pathlib, plistlib, shutil, signal, subprocess, sys, time, zipfile
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
config = json.loads(pathlib.Path(os.environ["TALKY_RELEASE_MOCK_CONFIG"]).read_text())
with pathlib.Path(os.environ["TALKY_RELEASE_MOCK_LOG"]).open("a") as log:
    log.write(json.dumps([tool, *args]) + "\n")
operation = tool
if tool == "xcrun": operation += ":" + ":".join(args[:2])
if tool == "codesign":
    operation += ":" + ("sign" if "--sign" in args else "entitlements" if "--entitlements" in args
                         else "certificate" if "--extract-certificates" in args else "verify" if "--verify" in args else "display")
if tool == "ditto": operation += ":" + ("extract" if "-x" in args else "archive")
if config.get("failure") == operation:
    print("SECRET-NOT-PRINT", file=sys.stderr)
    sys.exit(9)
if config.get("signalAt") == operation:
    os.kill(os.getppid(), signal.SIGTERM)
    time.sleep(1)
if tool in ("chmod", "ls"):
    if sys.platform == "darwin": sys.exit(subprocess.call(["/bin/" + tool, *args]))
    if tool == "ls": print("private fixture without ACL entries")
elif tool == "security":
    if config.get("identityType") == "local":
        print('1) ' + config["fingerprint"] + ' "Talky Self-Signed"')
    elif config.get("identityType") != "missing":
        print('1) ' + config["fingerprint"] + ' "Developer ID Application: Test Fixture (' + config["team"] + ')"')
elif tool == "codesign":
    app = pathlib.Path(args[-1])
    if "--sign" in args:
        assert args.index("--sign") < args.index("--options")
        assert "--deep" not in args and "--timestamp" in args
        assert args[args.index("--options") + 1] == "runtime"
        assert plistlib.loads(pathlib.Path(args[args.index("--entitlements") + 1]).read_bytes()) == {"com.apple.security.device.audio-input": True}
        signature = app / "Contents/_CodeSignature"
        signature.mkdir()
        (signature / "CodeResources").write_text("signed")
    elif "--extract-certificates" in args:
        pathlib.Path(args[args.index("--extract-certificates") + 1] + "0").write_bytes(
            b"wrong-certificate" if config.get("wrongCertificate") else b"isolated-test-certificate-not-a-real-key")
    elif "--entitlements" in args:
        sys.stdout.buffer.write(plistlib.dumps(config.get("entitlements", {"com.apple.security.device.audio-input": True})))
    elif "--display" in args:
        print("Identifier=com.lokaah.talky")
        print("TeamIdentifier=" + config.get("signedTeam", config["team"]))
        print("Authority=Developer ID Application: Test Fixture (" + config["team"] + ")")
        print("Authority=Developer ID Certification Authority\nAuthority=Apple Root CA")
        print("CodeDirectory v=20500 flags=" + ("0x0(none)" if config.get("noRuntime") else "0x10000(runtime)"))
        if not config.get("noTimestamp"): print("Timestamp=Oct 7, 2026 at 12:00:00")
elif tool == "lipo": print(config.get("architecture", "arm64"))
elif tool == "otool":
    print("Load command 10\n      cmd LC_BUILD_VERSION\n  cmdsize 32\n platform 1\n    minos " + config.get("minOS", "14.0") + "\n      sdk 26.5\n   ntools 1\n     tool 3\n  version 1238.5")
elif tool == "ditto":
    if "-x" in args:
        with zipfile.ZipFile(args[-2]) as zipped: zipped.extractall(args[-1])
    else:
        app = pathlib.Path(args[-2])
        with zipfile.ZipFile(args[-1], "w", zipfile.ZIP_DEFLATED) as zipped:
            for path in sorted(app.rglob("*")):
                if path.is_file(): zipped.write(path, str(path.relative_to(app.parent)))
elif tool == "xcrun":
    if args[:2] == ["notarytool", "history"]: print('{"history": []}')
    elif args[:2] == ["notarytool", "submit"]:
        archive = pathlib.Path(args[2])
        pathlib.Path(os.environ["TALKY_RELEASE_MOCK_SUBMITTED"]).write_text(json.dumps({"sha": hashlib.sha256(archive.read_bytes()).hexdigest(), "name": archive.name}))
        print(json.dumps({"id": "11111111-2222-3333-4444-555555555555", "status": config.get("notaryStatus", "Accepted")}))
    elif args[:2] == ["notarytool", "log"]:
        submitted = json.loads(pathlib.Path(os.environ["TALKY_RELEASE_MOCK_SUBMITTED"]).read_text())
        value = {"jobId": "11111111-2222-3333-4444-555555555555", "status": "Accepted", "statusCode": 0,
                 "archiveFilename": submitted["name"], "sha256": submitted["sha"], "issues": None}
        value.update(config.get("notaryLog", {}))
        pathlib.Path(args[-1]).write_text(json.dumps(value))
    elif args[:2] == ["stapler", "staple"]:
        (pathlib.Path(args[-1]) / "Contents/_CodeSignature/CodeResources").write_text("signed+stapled")
    elif args[:2] != ["stapler", "validate"]: sys.exit(97)
elif tool == "spctl": print("accepted\nsource=" + config.get("gatekeeperSource", "Notarized Developer ID"))
else: sys.exit(96)
'''

BUILD_FIXTURE = r'''#!/bin/bash
set -euo pipefail
"$TALKY_RELEASE_TEST_PYTHON" -I - "$@" <<'PY'
import hashlib, json, os, pathlib, plistlib, sys
args = sys.argv[1:]
assert "--release" in args and "--adhoc" not in args
config = json.loads(pathlib.Path(os.environ["TALKY_RELEASE_MOCK_CONFIG"]).read_text())
if config.get("buildFailure"): sys.exit(11)
root = pathlib.Path.cwd()
app = pathlib.Path(args[args.index("--output-dir") + 1]) / "Lokaah Talky.app"
(app / "Contents/MacOS").mkdir(parents=True)
(app / "Contents/Resources").mkdir()
(app / "Contents/MacOS/Lokaah Talky").write_bytes(b"fixture executable")
(app / "Contents/Resources/AppIcon.icns").write_bytes(b"fixture icon")
info = {"CFBundleIdentifier": "com.lokaah.talky", "CFBundleExecutable": "Lokaah Talky",
        "CFBundleShortVersionString": "0.0.0", "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0",
        "LSUIElement": True, "NSMicrophoneUsageDescription": "Mic", "NSSpeechRecognitionUsageDescription": "Speech",
        "TalkyBuildConfiguration": "Release", "TalkyBuildMethod": "local-clt", "TalkySourceSHA256": hashlib.sha256((root / "Lokaah Talky/LokaahTalkyApp.swift").read_bytes()).hexdigest()}
if config.get("wrongSourceHash"): info["TalkySourceSHA256"] = "0" * 64
(app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
if config.get("extraPayload"): (app / "Contents/Resources/voice_input.txt").write_text("synthetic private transcript")
PY
'''


class BinaryReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="talky-release-tests-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        self.repo.mkdir()
        shutil.copytree(ROOT / "scripts", self.repo / "scripts")
        (self.repo / "build-local.sh").write_text(BUILD_FIXTURE)
        (self.repo / "Lokaah Talky").mkdir()
        self.source = self.repo / "Lokaah Talky/LokaahTalkyApp.swift"
        self.source.write_text("// exact tagged source fixture\n")
        self.source_hash = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.mock = self.base / "bin"
        self.mock.mkdir()
        for name in ("security", "codesign", "xcrun", "ditto", "spctl", "lipo", "otool", "chmod", "ls"):
            path = self.mock / name
            path.write_text("#!" + sys.executable + "\n" + MOCK_TOOL)
            path.chmod(0o755)
        self.config_path = self.base / "config.json"
        self.log = self.base / "calls.jsonl"
        self.config = {"fingerprint": FINGERPRINT, "team": TEAM}
        self.env = os.environ.copy()
        self.env.update(DEVELOPER_DIR="/Library/Developer/CommandLineTools",
                        PATH=str(self.mock) + os.pathsep + self.env["PATH"],
                        TALKY_RELEASE_MOCK_CONFIG=str(self.config_path), TALKY_RELEASE_MOCK_LOG=str(self.log),
                        TALKY_RELEASE_MOCK_SUBMITTED=str(self.base / "submitted.json"), TALKY_RELEASE_TEST_PYTHON=sys.executable,
                        PYTHONOPTIMIZE="2")
        self.write_config()
        self.git("init", "-q")
        self.git("-c", "user.name=Isolated Fixture", "-c", "user.email=fixture@example.invalid", "add", ".")
        self.git("-c", "user.name=Isolated Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")
        self.git("-c", "user.name=Isolated Fixture", "-c", "user.email=fixture@example.invalid", "tag", "-a", "v1.1.0-beta.2", "-m", "fixture tag")
        self.commit = self.git("rev-parse", "HEAD").stdout.strip()
        self.output = self.base / "candidate"

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], env=self.env,
                              text=True, capture_output=True, check=True)

    def write_config(self):
        self.config_path.write_text(json.dumps(self.config))

    def prepare(self, extra=()):
        self.write_config()
        return subprocess.run(["bash", str(self.repo / "scripts/prepare-binary-release.sh"),
                               "--tag", "v1.1.0-beta.2", "--version", "1.1.0", "--build-number", "3",
                               "--identity", FINGERPRINT, "--team-id", TEAM, "--notary-profile", "fixture-notary",
                               "--current-os-major", "26", "--output-dir", str(self.output), *extra], env=self.env, text=True, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def prepared(self):
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads((self.output / "manifest.json").read_text())

    def accepted(self):
        value = json.loads((self.output / "acceptance-template.json").read_text())
        value.update(testedAt=dt.datetime.now(dt.timezone.utc).isoformat(), testedBy="Automated isolated fixture")
        value["artifactInspection"].update(passed=True, evidence="Inspected exact ZIP, synthetic fixture only.")
        for name, os_version in (("minimumOS", "14.8"), ("currentOS", "26.0")):
            value["platforms"][name].update(osVersion=os_version, hardware="Apple Silicon fixture",
                                           passed=True, evidence="Isolated gate fixture, not real runtime evidence.")
        for record in value["runtimeChecks"].values():
            record.update(passed=True, evidence="Isolated gate fixture, not real runtime evidence.")
        return value

    def verify(self, value):
        path = self.base / "acceptance.json"
        path.write_text(json.dumps(value))
        self.write_config()
        return subprocess.run(["bash", str(self.repo / "scripts/verify-binary-release.sh"),
                               "--candidate-dir", str(self.output), "--acceptance", str(path)], env=self.env,
                              text=True, capture_output=True)

    def test_success_exact_tag_private_output_minimal_signature_and_stapled_checksum(self):
        self.source.write_text("// uncommitted source must not be built\n")
        manifest = self.prepared()
        self.assertEqual(manifest["identity"]["sourceCommit"], self.commit)
        self.assertEqual(manifest["identity"]["sourceSHA256"], self.source_hash)
        self.assertNotEqual(manifest["identity"]["tagObject"], self.commit)
        self.assertEqual(manifest["identity"]["buildNumber"], "3")
        self.assertFalse(manifest["publicationApproved"])
        self.assertNotEqual(manifest["artifactSHA256"], manifest["submittedArchiveSHA256"])
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        for path in self.output.iterdir(): self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        with zipfile.ZipFile(self.output / manifest["artifact"]) as zipped:
            info = plistlib.loads(zipped.read("Lokaah Talky.app/Contents/Info.plist"))
            self.assertEqual(info["CFBundleVersion"], "3")
            self.assertEqual(info["CFBundleShortVersionString"], "1.1.0")
            self.assertEqual(zipped.getinfo("Lokaah Talky.app/Contents/_CodeSignature/CodeResources").external_attr >> 16 & 0o777, 0o644)
            self.assertEqual(zipped.getinfo("Lokaah Talky.app/Contents/MacOS/Lokaah Talky").external_attr >> 16 & 0o777, 0o755)
        self.assertFalse(any("import" in call or "store-credentials" in call for call in self.calls()))
        self.assertFalse(any(call[0] in ("open", "gh") for call in self.calls()))
        self.assertNotIn("fixture-notary", (self.output / "manifest.json").read_text())
        result = self.verify(self.accepted())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No upload or publication", result.stdout)

    def test_missing_or_local_identity_fails_before_build_and_output(self):
        for kind in ("missing", "local"):
            with self.subTest(kind=kind):
                self.config["identityType"] = kind
                self.assertNotEqual(self.prepare().returncode, 0)
                self.assertFalse(self.output.exists())
        self.assertFalse(any(call[0] == "codesign" for call in self.calls()))

    def test_invalid_tag_version_or_existing_output_fails(self):
        for options in (("--tag", "HEAD"), ("--version", "1.0.0"), ("--tag", "v9.9.9", "--version", "9.9.9")):
            with self.subTest(options=options):
                self.assertNotEqual(self.prepare(options).returncode, 0)
                self.assertFalse(self.output.exists())
        self.output.mkdir()
        marker = self.output / "keep"
        marker.write_text("existing candidate")
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertEqual(marker.read_text(), "existing candidate")

    def test_tool_failures_remove_partial_candidate_without_leaking_tool_output(self):
        for operation in ("xcrun:notarytool:history", "codesign:sign", "codesign:verify", "codesign:certificate",
                          "xcrun:notarytool:submit", "xcrun:notarytool:log", "xcrun:stapler:staple",
                          "xcrun:stapler:validate", "spctl", "ditto:extract", "chmod"):
            with self.subTest(operation=operation):
                self.config = {"fingerprint": FINGERPRINT, "team": TEAM, "failure": operation}
                result = self.prepare()
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("SECRET-NOT-PRINT", result.stdout + result.stderr)
                self.assertFalse(self.output.exists())

    def test_build_failure_wrong_platform_source_and_private_payload_fail(self):
        for option, value in (("buildFailure", True), ("wrongSourceHash", True), ("architecture", "arm64 x86_64"),
                              ("minOS", "26.2"), ("extraPayload", True)):
            with self.subTest(option=option):
                self.config = {"fingerprint": FINGERPRINT, "team": TEAM, option: value}
                self.assertNotEqual(self.prepare().returncode, 0)
                self.assertFalse(self.output.exists())

    def test_signature_team_fingerprint_timestamp_runtime_and_entitlements_fail_closed(self):
        for option, value in (("signedTeam", "WRONGTEAM0"), ("wrongCertificate", True), ("noTimestamp", True),
                              ("noRuntime", True), ("entitlements", {}),
                              ("entitlements", {"com.apple.security.device.audio-input": True, "com.apple.security.get-task-allow": True})):
            with self.subTest(option=option, value=value):
                self.config = {"fingerprint": FINGERPRINT, "team": TEAM, option: value}
                self.assertNotEqual(self.prepare().returncode, 0)
                self.assertFalse(self.output.exists())

    def test_notarization_rejects_nonaccepted_warnings_or_wrong_archive_identity(self):
        for change in ({"notaryStatus": "Invalid"}, {"notaryStatus": "In Progress"},
                       {"notaryLog": {"issues": [{"severity": "warning"}]}},
                       {"notaryLog": {"sha256": "0" * 64}}, {"notaryLog": {"jobId": "wrong"}},
                       {"notaryLog": {"archiveFilename": "wrong.zip"}}, {"gatekeeperSource": "Developer ID"}):
            with self.subTest(change=change):
                self.config = {"fingerprint": FINGERPRINT, "team": TEAM, **change}
                self.assertNotEqual(self.prepare().returncode, 0)
                self.assertFalse(self.output.exists())

    def test_pending_partial_stale_or_wrong_platform_acceptance_fails(self):
        self.prepared()
        template = json.loads((self.output / "acceptance-template.json").read_text())
        self.assertNotEqual(self.verify(template).returncode, 0)
        baseline = self.accepted()
        changes = (
            lambda v: v.update(testedBy=""),
            lambda v: v.update(sourceCommit="0" * 40),
            lambda v: v.update(artifactSHA256="0" * 64),
            lambda v: v.update(testedAt="2020-01-01T00:00:00+00:00"),
            lambda v: v.update(testedAt="2099-01-01T00:00:00+00:00"),
            lambda v: v["artifactInspection"].update(evidence=""),
            lambda v: v["platforms"]["minimumOS"].update(osVersion="15.0"),
            lambda v: v["platforms"]["currentOS"].update(osVersion="15.0"),
            lambda v: v["platforms"]["minimumOS"].update(architecture="x86_64"),
            lambda v: v["runtimeChecks"].pop("terminalDelivery"),
            lambda v: v["runtimeChecks"]["longCaptureWithSessionRenewal"].update(passed=False),
        )
        for change in changes:
            value = copy.deepcopy(baseline)
            change(value)
            with self.subTest(value=value): self.assertNotEqual(self.verify(value).returncode, 0)

    def test_changed_archive_or_notary_log_invalidates_prior_acceptance(self):
        manifest = self.prepared()
        accepted = self.accepted()
        archive = self.output / manifest["artifact"]
        original = archive.read_bytes()
        archive.write_bytes(original + b"changed after tests")
        self.assertNotEqual(self.verify(accepted).returncode, 0)
        archive.write_bytes(original)
        log = self.output / "notarization-log.json"
        log.write_text(log.read_text() + " ")
        self.assertNotEqual(self.verify(accepted).returncode, 0)

    def test_signal_cleans_candidate_and_moved_tag_invalidates_acceptance(self):
        self.config["signalAt"] = "xcrun:notarytool:submit"
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.config.pop("signalAt")
        self.prepared()
        acceptance = self.accepted()
        self.git("tag", "-d", "v1.1.0-beta.2")
        self.git("tag", "v1.1.0-beta.2")
        self.assertNotEqual(self.verify(acceptance).returncode, 0)

    @unittest.skipUnless(sys.platform == "darwin", "macOS ACL inheritance regression")
    def test_inherited_acl_removed_before_candidate_bytes(self):
        # Only synthetic fixture bytes receive this grant; no real keys or app data exist here.
        subprocess.run(["/bin/chmod", "+a", "everyone allow read,execute,file_inherit,directory_inherit",
                        str(self.base)], check=True)
        manifest = self.prepared()
        for path in [self.output, *self.output.iterdir()]:
            listing = subprocess.run(["/bin/ls", "-lde", str(path)], text=True, capture_output=True, check=True).stdout
            self.assertNotRegex(listing, r"(?m)^\s*[0-9]+:")
        calls = self.calls()
        clear = next(index for index, call in enumerate(calls) if call[:2] == ["chmod", "-N"])
        sign = next(index for index, call in enumerate(calls) if call[0] == "codesign" and "--sign" in call)
        self.assertLess(clear, sign)
        self.assertEqual(manifest["identity"]["sourceCommit"], self.commit)

    @unittest.skipUnless(sys.platform == "darwin", "actual macOS ditto metadata layout")
    def test_actual_ditto_metadata_layout_and_reject_unsafe_archive_paths(self):
        spec = importlib.util.spec_from_file_location("talky_release_fixture", ROOT / "scripts/release_tool.py")
        release = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(release)
        app = self.base / "archive-fixture/Lokaah Talky.app"
        resource = app / "Contents/Resources/AppIcon.icns"
        resource.parent.mkdir(parents=True)
        resource.write_bytes(b"synthetic resource")
        subprocess.run(["/usr/bin/xattr", "-w", "com.apple.talky-test", "synthetic", str(resource)], check=True)
        archive = self.base / "actual-ditto.zip"
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)
        with zipfile.ZipFile(archive) as zipped: self.assertIn("__MACOSX/", zipped.namelist())
        release.archive_check(archive)
        for filename in ("../outside", "__MACOSX/../../outside", "/absolute", "unrelated.txt", "Lokaah Talky.app/link"):
            with self.subTest(filename=filename):
                entry = zipfile.ZipInfo(filename)
                if filename.endswith("/link"): entry.external_attr = 0o120777 << 16
                with zipfile.ZipFile(archive, "w") as zipped: zipped.writestr(entry, b"synthetic")
                with self.assertRaises(release.ReleaseError): release.archive_check(archive)


if __name__ == "__main__":
    unittest.main(verbosity=2)
