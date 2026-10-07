#!/usr/bin/env python3
"""Unnotarized beta packaging regressions with isolated signing and build fixtures."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_fixtures", Path(__file__).with_name("test-release.py"))
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class BetaReleaseTests(unittest.TestCase):
    git = fixtures.BinaryReleaseTests.git
    write_config = fixtures.BinaryReleaseTests.write_config
    calls = fixtures.BinaryReleaseTests.calls

    def setUp(self):
        fixtures.BinaryReleaseTests.setUp(self)
        self.config["identityType"] = "local"
        self.write_config()
        mock = fixtures.MOCK_TOOL.replace('"--timestamp" in args', '"--timestamp=none" in args')
        mock = mock.replace('print("Authority=Developer ID Application: Test Fixture (" + config["team"] + ")")',
                            'print("Authority=Talky Self-Signed")')
        mock = mock.replace('print("Authority=Developer ID Certification Authority\\nAuthority=Apple Root CA")', '')
        for path in self.mock.iterdir():
            path.write_text("#!" + sys.executable + "\n" + mock)
            path.chmod(0o755)
        (self.repo / "docs").mkdir()
        (self.repo / "docs/BETA-INSTALL.md").write_text("Unnotarized beta. Use per-app approval only.\n")
        (self.repo / "docs/PRIVACY.md").write_text("Apple speech engine. Requires on-device processing.\n")
        (self.repo / "LICENSE").write_text("MIT fixture\n")
        self.git("add", ".")
        self.git("-c", "user.name=Isolated Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-qm", "beta documentation fixture")
        self.git("-c", "user.name=Isolated Fixture", "-c", "user.email=fixture@example.invalid",
                 "tag", "-fa", "v1.1.0-beta.2", "-m", "beta fixture")
        self.commit = self.git("rev-parse", "HEAD").stdout.strip()

    def prepare(self, extra=()):
        self.write_config()
        return subprocess.run(["bash", str(self.repo / "scripts/prepare-beta.sh"),
                               "--tag", "v1.1.0-beta.2", "--version", "1.1.0", "--build-number", "3",
                               "--identity", fixtures.FINGERPRINT, "--current-os-major", "26",
                               "--output-dir", str(self.output), *extra], env=self.env, text=True, capture_output=True)

    def prepared(self):
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads((self.output / "manifest.json").read_text())

    def accepted(self):
        value = fixtures.BinaryReleaseTests.accepted(self)
        for record in [*value["privacyChecks"].values(), value["installationApproval"]]:
            record.update(passed=True, evidence="Isolated gate fixture, not actual runtime evidence.")
        return value

    def verify(self, value):
        path = self.base / "acceptance.json"
        path.write_text(json.dumps(value))
        self.write_config()
        return subprocess.run(["bash", str(self.repo / "scripts/verify-beta.sh"),
                               "--candidate-dir", str(self.output), "--acceptance", str(path)],
                              env=self.env, text=True, capture_output=True)

    def test_local_signature_tagged_source_and_private_candidate_without_apple_services(self):
        self.source.write_text("// uncommitted changes must not enter this beta\n")
        manifest = self.prepared()
        self.assertEqual(manifest["identity"]["sourceCommit"], self.commit)
        self.assertEqual(manifest["identity"]["sourceSHA256"], self.source_hash)
        self.assertEqual(manifest["distribution"], "unnotarized-beta")
        self.assertFalse(manifest["notarized"])
        self.assertFalse(manifest["publicationApproved"])
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        for path in self.output.iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        with zipfile.ZipFile(self.output / manifest["artifact"]) as zipped:
            info = json.loads(zipped.read("Lokaah Talky.app/Contents/Resources/ReleaseProvenance.json"))
            self.assertEqual(info, manifest["identity"])
            executable = zipped.getinfo("Lokaah Talky.app/Contents/MacOS/Lokaah Talky")
            self.assertEqual(executable.external_attr >> 16 & 0o777, 0o755)
        result = self.verify(self.accepted())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("not Apple notarization", result.stdout)
        self.assertFalse(any(call[0] in ("xcrun", "spctl", "open", "gh") for call in self.calls()))
        self.assertFalse(any("import" in call or "add-trusted-cert" in call or "--timestamp" in call for call in self.calls()))

    def test_missing_identity_stops_before_output(self):
        self.config["identityType"] = "missing"
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_invalid_tag_and_existing_output_are_rejected(self):
        self.assertNotEqual(self.prepare(("--tag", "v1.1.0")).returncode, 0)
        self.output.mkdir()
        marker = self.output / "keep"
        marker.write_text("keep this existing candidate")
        self.assertNotEqual(self.prepare().returncode, 0)
        self.assertEqual(marker.read_text(), "keep this existing candidate")

    def test_build_signing_and_payload_failures_remove_only_new_candidate(self):
        cases = [{"buildFailure": True}, {"wrongSourceHash": True}, {"extraPayload": True},
                 {"architecture": "x86_64"}, {"minOS": "15.0"}, {"noRuntime": True},
                 {"wrongCertificate": True}, {"entitlements": {"com.apple.security.get-task-allow": True}},
                 {"failure": "codesign:sign"}, {"failure": "codesign:verify"}, {"failure": "ditto:extract"}]
        original = copy.deepcopy(self.config)
        for change in cases:
            with self.subTest(change=change):
                self.config = {**original, **change}
                result = self.prepare()
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("SECRET-NOT-PRINT", result.stdout + result.stderr)
                self.assertFalse(self.output.exists())

    def test_unfinished_runtime_checks_are_not_accepted(self):
        self.prepared()
        template = json.loads((self.output / "acceptance-template.json").read_text())
        self.assertNotEqual(self.verify(template).returncode, 0)
        acceptance = self.accepted()
        acceptance["runtimeChecks"]["longCaptureWithSessionRenewal"]["passed"] = False
        self.assertNotEqual(self.verify(acceptance).returncode, 0)

    def test_privacy_and_install_approval_evidence_are_required(self):
        self.prepared()
        for key in ("offlineRecognition", "runtimeNetworkObservation", "installationApproval"):
            with self.subTest(key=key):
                acceptance = self.accepted()
                record = acceptance[key] if key == "installationApproval" else acceptance["privacyChecks"][key]
                record["evidence"] = ""
                self.assertNotEqual(self.verify(acceptance).returncode, 0)

    def test_wrong_candidate_or_platform_acceptance_is_rejected(self):
        self.prepared()
        for field in ("artifactSHA256", "sourceCommit", "candidatePreparedAt", "distribution"):
            with self.subTest(field=field):
                acceptance = self.accepted()
                acceptance[field] = "different candidate"
                self.assertNotEqual(self.verify(acceptance).returncode, 0)
        acceptance = self.accepted()
        acceptance["platforms"]["minimumOS"]["osVersion"] = "27.0"
        self.assertNotEqual(self.verify(acceptance).returncode, 0)

    def test_tampered_archive_or_checksum_record_is_rejected(self):
        manifest = self.prepared()
        archive = self.output / manifest["artifact"]
        original = archive.read_bytes()
        archive.write_bytes(original + b"tampered")
        self.assertNotEqual(self.verify(self.accepted()).returncode, 0)
        archive.write_bytes(original)
        (self.output / "SHA256SUMS").write_text("wrong checksum\n")
        self.assertNotEqual(self.verify(self.accepted()).returncode, 0)

    def test_changed_installation_document_rejected_even_with_recomputed_manifest(self):
        manifest = self.prepared()
        document = self.output / "INSTALL.md"
        document.write_text("unreviewed replacement instructions\n")
        manifest["publicFiles"]["INSTALL.md"] = hashlib.sha256(document.read_bytes()).hexdigest()
        (self.output / "manifest.json").write_text(json.dumps(manifest))
        (self.output / "SHA256SUMS").write_text("".join(f"{digest}  {name}\n" for name, digest in sorted(manifest["publicFiles"].items())))
        self.assertNotEqual(self.verify(self.accepted()).returncode, 0)

    def test_moved_source_tag_and_missing_certificate_are_rejected(self):
        self.prepared()
        self.config["wrongCertificate"] = True
        self.assertNotEqual(self.verify(self.accepted()).returncode, 0)
        self.config["wrongCertificate"] = False
        self.source.write_text("// changed after preparation\n")
        self.git("add", ".")
        self.git("-c", "user.name=Isolated Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "changed source")
        self.git("tag", "-f", "v1.1.0-beta.2")
        self.assertNotEqual(self.verify(self.accepted()).returncode, 0)

    def test_beta_cannot_be_relabelled_as_notarized(self):
        manifest = self.prepared()
        manifest["notarized"] = True
        (self.output / "manifest.json").write_text(json.dumps(manifest))
        self.assertNotEqual(self.verify(self.accepted()).returncode, 0)

    def test_notarized_verifier_rejects_beta_candidate(self):
        self.prepared()
        result = fixtures.BinaryReleaseTests.verify(self, self.accepted())
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
