#!/usr/bin/env python3
"""Prepare a locally signed, unnotarized beta without an Apple developer account."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import sys
import tempfile

spec = importlib.util.spec_from_file_location("talky_release", Path(__file__).with_name("release_tool.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

CHANNEL = "unnotarized-beta"
PUBLIC_DOCS = {"INSTALL.md": "docs/BETA-INSTALL.md", "PRIVACY.md": "docs/PRIVACY.md", "LICENSE": "LICENSE"}
PRIVACY_CHECKS = ("offlineRecognition", "runtimeNetworkObservation")


def signature_check(app, identity, env):
    release.bundle_check(app, identity, signed=True, env=env)
    release.run(["codesign", "--verify", "--deep", "--strict", str(app)], env=env)
    details = release.text_run(["codesign", "--display", "--verbose=4", str(app)], env=env)
    release.require(re.search(r"^Identifier=com\.lokaah\.talky$", details, re.M), "Wrong signed app identifier.")
    release.require(re.search(r"^CodeDirectory .*flags=.*\bruntime\b", details, re.M), "Hardened runtime is required.")
    raw = release.run(["codesign", "--display", "--entitlements", "-", "--xml", str(app)], env=env)[0]
    release.require(plistlib.loads(raw) == release.ENTITLEMENTS, "Only the audio-input entitlement is permitted.")
    with tempfile.TemporaryDirectory(prefix="talky-beta-certificate-") as temporary:
        prefix = str(Path(temporary) / "signer")
        release.run(["codesign", "--display", "--extract-certificates=" + prefix, str(app)], env=env)
        certificate = Path(prefix + "0")
        release.require(certificate.is_file() and hashlib.sha1(certificate.read_bytes()).hexdigest().upper()
                        == identity["signingFingerprint"], "The actual signing identity does not match this beta.")


def inspect_archive(archive, destination, identity, env):
    release.archive_check(archive)
    release.run(["ditto", "-x", "-k", str(archive), str(destination)], env=env)
    children = {path.name for path in destination.iterdir()}
    release.require(children <= {release.APP_NAME, "__MACOSX"} and release.APP_NAME in children,
                    "Unexpected extracted payload.")
    signature_check(destination / release.APP_NAME, identity, env)


def prepare(args):
    env = release.tooling_env()
    repo = args.repo.resolve()
    release.require(re.fullmatch(r"[0-9A-Fa-f]{40}", args.identity), "Use the certificate's 40-character SHA-1 fingerprint.")
    release.require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version), "Version needs three numeric components.")
    release.require(re.fullmatch(r"[1-9][0-9]{0,3}", args.build_number), "Build number must be between 1 and 9999.")
    release.require(args.tag.startswith("v" + args.version + "-beta."), "Use an explicit beta tag matching the version.")
    release.require(args.current_os_major >= 15, "Specify the current macOS acceptance target.")
    tag_object, commit = release.source_identity(repo, args.tag, env)
    # Include locally trusted identities: a self-signed publisher certificate need not chain to Apple.
    identities = release.text_run(["security", "find-identity", "-p", "codesigning"], env=env)
    release.require(re.search(r"\b" + re.escape(args.identity) + r'\s+"', identities, re.I),
                    "The specified signing certificate and private key must already exist in Keychain.")
    output = args.output_dir.absolute()
    release.require(not output.exists() and not output.is_symlink(), "Output directory must not already exist.")
    release.require(output.parent.is_dir(), "Output parent directory must already exist.")
    output.mkdir(mode=0o700)
    try:
        release.run(["chmod", "-N", str(output)], env=env)
        output.chmod(0o700)
        release.private_check(output, env)
        with tempfile.TemporaryDirectory(prefix=".work-", dir=output) as temporary:
            work = Path(temporary)
            source = work / "source"
            source.mkdir(mode=0o700)
            snapshot = work / "source.tar"
            release.run(["git", "-C", str(repo), "archive", "--format=tar", commit], env=env, output=snapshot)
            release.run(["tar", "-xf", str(snapshot), "-C", str(source)], env=env)
            identity = {
                "distribution": CHANNEL, "tag": args.tag, "tagObject": tag_object, "sourceCommit": commit,
                "sourceSHA256": release.sha256(source / "Dhwani/DhwaniApp.swift"),
                "version": args.version, "buildNumber": args.build_number,
                "signingFingerprint": args.identity.upper(), "currentOSMajor": args.current_os_major,
            }
            for destination, relative in PUBLIC_DOCS.items():
                document = source / relative
                release.require(document.is_file() and not document.is_symlink(), "Beta installation and privacy documents are required.")
                shutil.copyfile(document, output / destination)
                (output / destination).chmod(0o600)
            build = work / "build"
            release.run(["bash", str(source / "build-local.sh"), "--release", "--output-dir", str(build)], cwd=source, env=env)
            app = build / release.APP_NAME
            info_path = app / "Contents/Info.plist"
            info = plistlib.loads(info_path.read_bytes())
            info.update(CFBundleShortVersionString=args.version, CFBundleVersion=args.build_number,
                        TalkyGitCommit=commit, TalkyDistribution=CHANNEL)
            info_path.write_bytes(plistlib.dumps(info))
            release.write_json(app / "Contents/Resources/ReleaseProvenance.json", identity)
            release.bundle_check(app, identity, signed=False, env=env)
            release.distribution_permissions(app)
            entitlements = work / "entitlements.plist"
            entitlements.write_bytes(plistlib.dumps(release.ENTITLEMENTS))
            release.run(["codesign", "--force", "--sign", identity["signingFingerprint"], "--options", "runtime",
                         "--timestamp=none", "--entitlements", str(entitlements), str(app)], env=env)
            release.distribution_permissions(app)
            signature_check(app, identity, env)
            filename = f"Dhwani-{args.tag}-unnotarized-arm64.zip"
            archive = output / filename
            release.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], env=env)
            archive.chmod(0o600)
            inspection = work / "inspection"
            inspection.mkdir(mode=0o700)
            inspect_archive(archive, inspection, identity, env)
            release.require(release.source_identity(repo, args.tag, env) == (tag_object, commit), "Beta tag changed during preparation.")
            prepared = release.now()
            checksums = {name: release.sha256(output / name) for name in [filename, *PUBLIC_DOCS]}
            manifest = {
                "schemaVersion": 1, "distribution": CHANNEL, "notarized": False,
                "identity": identity, "artifact": filename, "artifactSHA256": checksums[filename],
                "publicFiles": checksums, "preparedAt": prepared, "publicationApproved": False,
            }
            release.write_json(output / "manifest.json", manifest)
            template = release.acceptance_template(identity, checksums[filename], prepared)
            template["distribution"] = CHANNEL
            template["privacyChecks"] = {key: {"passed": False, "evidence": ""} for key in PRIVACY_CHECKS}
            template["installationApproval"] = {"passed": False, "evidence": ""}
            release.write_json(output / "acceptance-template.json", template)
            (output / "SHA256SUMS").write_text("".join(f"{digest}  {name}\n" for name, digest in sorted(checksums.items())))
            (output / "SHA256SUMS").chmod(0o600)
        for path in [output, *output.iterdir()]:
            release.private_check(path, env)
        print(f"Prepared private unnotarized beta: {output / filename}")
        print("Runtime and clean-Mac installation checks remain pending. Nothing was installed or published.")
    except BaseException:
        shutil.rmtree(output)
        raise


def verify(args):
    env = release.tooling_env()
    candidate = args.candidate_dir.resolve()
    release.private_check(candidate, env)
    for name in ("manifest.json", "SHA256SUMS", "acceptance-template.json"):
        release.private_check(candidate / name, env)
    manifest = release.read_json(candidate / "manifest.json")
    release.require(manifest.get("schemaVersion") == 1 and manifest.get("distribution") == CHANNEL
                    and manifest.get("notarized") is False and manifest.get("publicationApproved") is False,
                    "Expected an explicitly unnotarized beta manifest.")
    identity = manifest["identity"]
    release.require(identity.get("distribution") == CHANNEL, "Wrong signed distribution channel.")
    release.require(release.source_identity(args.repo.resolve(), identity["tag"], env)
                    == (identity["tagObject"], identity["sourceCommit"]), "The beta tag moved after preparation.")
    source = release.run(["git", "-C", str(args.repo.resolve()), "show",
                          identity["sourceCommit"] + ":Dhwani/DhwaniApp.swift"], env=env)[0]
    release.require(hashlib.sha256(source).hexdigest() == identity["sourceSHA256"], "Source identity mismatch.")
    filename = f"Dhwani-{identity['tag']}-unnotarized-arm64.zip"
    release.require(manifest.get("artifact") == filename and Path(filename).name == filename, "Unexpected beta filename.")
    checksums = manifest.get("publicFiles", {})
    release.require(isinstance(checksums, dict) and set(checksums) == {filename, *PUBLIC_DOCS}, "Unexpected public beta files.")
    for name, digest in checksums.items():
        path = candidate / name
        release.private_check(path, env)
        release.require(path.is_file() and release.sha256(path) == digest, "Beta payload changed after preparation.")
    for name, relative in PUBLIC_DOCS.items():
        document = release.run(["git", "-C", str(args.repo.resolve()), "show", identity["sourceCommit"] + ":" + relative], env=env)[0]
        release.require(hashlib.sha256(document).hexdigest() == checksums[name], "Beta documentation differs from the tagged source.")
    release.require(checksums[filename] == manifest.get("artifactSHA256"), "Archive identity mismatch.")
    expected_checksums = "".join(f"{digest}  {name}\n" for name, digest in sorted(checksums.items()))
    release.require((candidate / "SHA256SUMS").read_text() == expected_checksums, "Checksum record mismatch.")
    acceptance = release.read_json(args.acceptance)
    release.acceptance_check(acceptance, manifest)
    release.require(acceptance.get("distribution") == CHANNEL, "Wrong acceptance channel.")
    checks = acceptance.get("privacyChecks", {})
    release.require(isinstance(checks, dict) and set(checks) == set(PRIVACY_CHECKS), "Privacy observations are required.")
    for check in [*checks.values(), acceptance.get("installationApproval")]:
        release.require(isinstance(check, dict) and check.get("passed") is True
                        and isinstance(check.get("evidence"), str) and check["evidence"].strip(),
                        "Privacy observations and the per-app macOS approval flow need recorded evidence.")
    with tempfile.TemporaryDirectory(prefix="talky-beta-verification-") as temporary:
        work = Path(temporary)
        snapshot = work / filename
        shutil.copyfile(candidate / filename, snapshot)
        release.require(release.sha256(snapshot) == manifest["artifactSHA256"], "Candidate changed before inspection.")
        inspect_archive(snapshot, work / "inspection", identity, env)
    release.require(release.sha256(candidate / filename) == manifest["artifactSHA256"], "Candidate changed during inspection.")
    print(f"Verified unnotarized beta: {filename}")
    print("All recorded acceptance gates passed. This is not Apple notarization. No publication was performed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare", help="Prepare a private unnotarized beta using an existing local certificate")
    for option in ("tag", "version", "build-number", "identity"):
        prepare_parser.add_argument("--" + option, required=True)
    prepare_parser.add_argument("--current-os-major", type=int, required=True)
    prepare_parser.add_argument("--output-dir", type=Path, required=True)
    prepare_parser.set_defaults(action=prepare)
    verify_parser = commands.add_parser("verify", help="Verify the exact beta and its completed runtime acceptance")
    verify_parser.add_argument("--candidate-dir", type=Path, required=True)
    verify_parser.add_argument("--acceptance", type=Path, required=True)
    verify_parser.set_defaults(action=verify)
    for command in (prepare_parser, verify_parser):
        command.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    os.umask(0o077)
    def interrupted(signum, frame):
        raise release.ReleaseError(f"Interrupted by signal {signum}; no beta was published.")
    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    try:
        args.action(args)
    except (release.ReleaseError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"Beta stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
