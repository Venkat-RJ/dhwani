#!/usr/bin/env python3
"""Build a tagged Developer ID candidate and enforce exact-artifact test evidence."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import zipfile

APP_NAME = "Dhwani.app"
EXECUTABLE = "Dhwani"
BUNDLE_ID = "com.lokaah.talky"
ENTITLEMENTS = {"com.apple.security.device.audio-input": True}
RUNTIME_CHECKS = (
    "onDeviceShortCapture", "longCaptureWithSessionRenewal", "permissionDenialAndRecovery",
    "unavailableLocalModel", "microphoneFailure", "captureAndProcessingCancellation",
    "textEditDelivery", "browserDelivery", "editorDelivery", "terminalDelivery",
    "changedAppAndFieldPreventPaste", "autoSendOffAndExplicitOptIn",
    "privateStorageAndRetention", "testCaptureNoDeliveryOrNormalPersistence",
    "testResultRemoval", "cleanMachineInstallation",
)


class ReleaseError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    path.chmod(0o600)


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise ReleaseError(f"Cannot read valid JSON from {path.name}.") from error


def run(argv, *, cwd=None, env=None, output=None):
    # Never echo raw tool output: credentials belong in a preconfigured Keychain profile.
    try:
        result = subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, check=False)
    except OSError as error:
        raise ReleaseError(f"Could not run {Path(argv[0]).name}.") from error
    require(result.returncode == 0,
            f"{Path(argv[0]).name} failed (exit {result.returncode}). No candidate is approved.")
    if output:
        output.write_bytes(result.stdout)
        output.chmod(0o600)
    return result.stdout, result.stderr


def text_run(argv, **kwargs):
    stdout, stderr = run(argv, **kwargs)
    return (stdout + stderr).decode("utf-8", errors="replace")


def tooling_env():
    env = os.environ.copy()
    env["DEVELOPER_DIR"] = env.get("TALKY_DEVELOPER_DIR", "/Library/Developer/CommandLineTools")
    # Prevent a caller's optimization environment from bypassing checks in archived scripts.
    env.pop("PYTHONOPTIMIZE", None)
    return env


def git_value(repo, revision, env):
    return run(["git", "-C", str(repo), "rev-parse", "--verify", revision], env=env)[0].decode().strip()


def source_identity(repo, tag, env):
    require(re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?", tag),
            "Tag must be an explicit version tag, for example v1.1.0-beta.2.")
    ref = "refs/tags/" + tag
    return git_value(repo, ref + "^{object}", env), git_value(repo, ref + "^{commit}", env)


def verify_identity(fingerprint, team, env):
    identities = text_run(["security", "find-identity", "-v", "-p", "codesigning"], env=env)
    pattern = r'\b' + re.escape(fingerprint) + r'\s+"Developer ID Application: [^"\n]+ \(' + re.escape(team) + r'\)"'
    require(re.search(pattern, identities, flags=re.I),
            "A valid Developer ID Application identity with the requested fingerprint and team is required.")


def bundle_check(app, identity, *, signed, env):
    require(app.is_dir() and not app.is_symlink(), "Expected a real app bundle.")
    expected = {"Contents/Info.plist", f"Contents/MacOS/{EXECUTABLE}",
                "Contents/Resources/AppIcon.icns", "Contents/Resources/ReleaseProvenance.json"}
    if signed:
        expected.add("Contents/_CodeSignature/CodeResources")
    files = set()
    directories = set()
    for path in app.rglob("*"):
        require(not path.is_symlink(), "Release bundles must not contain symlinks.")
        require(path.is_file() or path.is_dir(), "Unexpected special file in release bundle.")
        if path.is_file():
            files.add(str(path.relative_to(app)))
        else:
            directories.add(str(path.relative_to(app)))
    require(files == expected, "Unexpected bundle payload; review nested code or private files before release.")
    require(directories == {"Contents", "Contents/MacOS", "Contents/Resources"}
            | ({"Contents/_CodeSignature"} if signed else set()), "Unexpected bundle directories.")
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    except (OSError, ValueError) as error:
        raise ReleaseError("Invalid bundle Info.plist.") from error
    expected_info = {
        "CFBundleIdentifier": BUNDLE_ID, "CFBundleExecutable": EXECUTABLE,
        "CFBundleShortVersionString": identity["version"], "CFBundleVersion": identity["buildNumber"],
        "LSMinimumSystemVersion": "14.0", "LSUIElement": True,
        "TalkyBuildConfiguration": "Release", "TalkySourceSHA256": identity["sourceSHA256"],
        "TalkyBuildMethod": "local-clt", "TalkyGitCommit": identity["sourceCommit"],
    }
    require(all(info.get(key) == value for key, value in expected_info.items()),
            "Bundle metadata does not match the release source, version, build, or platform.")
    require(info.get("NSMicrophoneUsageDescription") and info.get("NSSpeechRecognitionUsageDescription"),
            "Both privacy usage descriptions are required.")
    require(read_json(app / "Contents/Resources/ReleaseProvenance.json") == identity,
            "Signed source provenance does not match this release.")
    executable = app / "Contents/MacOS" / EXECUTABLE
    architectures = text_run(["lipo", "-archs", str(executable)], env=env).strip()
    require(architectures == "arm64", "Release executable must contain exactly the arm64 architecture.")
    load_commands = text_run(["otool", "-l", str(executable)], env=env)
    require(re.search(r"cmd LC_BUILD_VERSION\s+(?:(?!\n\s*cmd ).)*?platform (?:1|MACOS)\s+minos 14\.0(?:\.0)?\b",
                      load_commands, flags=re.S), "Executable must target macOS 14.0.")


def signed_check(app, identity, env):
    bundle_check(app, identity, signed=True, env=env)
    run(["codesign", "--verify", "--deep", "--strict", str(app)], env=env)
    details = text_run(["codesign", "--display", "--verbose=4", str(app)], env=env)
    require(re.search(r"^Identifier=" + re.escape(BUNDLE_ID) + r"$", details, re.M), "Wrong signed identifier.")
    require(re.search(r"^TeamIdentifier=" + re.escape(identity["teamID"]) + r"$", details, re.M), "Wrong signed team.")
    require(re.search(r"^Authority=Developer ID Application: .+ \(" + re.escape(identity["teamID"]) + r"\)$", details, re.M),
            "Signature is not Developer ID Application.")
    require("Authority=Developer ID Certification Authority" in details and "Authority=Apple Root CA" in details,
            "Expected Apple's Developer ID certificate chain.")
    require(re.search(r"^CodeDirectory .*flags=.*\bruntime\b", details, re.M), "Hardened runtime is required.")
    require(re.search(r"^Timestamp=.+$", details, re.M), "Secure signing timestamp is required.")
    raw_entitlements = run(["codesign", "--display", "--entitlements", "-", "--xml", str(app)], env=env)[0]
    try:
        entitlements = plistlib.loads(raw_entitlements)
    except ValueError as error:
        raise ReleaseError("Could not read signed entitlements.") from error
    require(entitlements == ENTITLEMENTS and entitlements.get("com.apple.security.device.audio-input") is True,
            "Signed entitlements must contain only the enabled audio-input entitlement.")
    with tempfile.TemporaryDirectory(prefix="talky-certificate-") as temp:
        prefix = str(Path(temp) / "signer")
        run(["codesign", "--display", "--extract-certificates=" + prefix, str(app)], env=env)
        certificate = Path(prefix + "0")
        require(certificate.is_file() and hashlib.sha1(certificate.read_bytes()).hexdigest().upper() == identity["signingFingerprint"],
                "The actual signing certificate fingerprint does not match the requested identity.")


def notarization_log_check(log, submission_id, submitted_sha, filename):
    require(isinstance(log, dict) and log.get("status") == "Accepted" and log.get("statusCode") == 0,
            "Notarization log must report Accepted with statusCode 0.")
    require(log.get("jobId") == submission_id and log.get("sha256", "").lower() == submitted_sha
            and log.get("archiveFilename") == filename,
            "Notarization log does not identify the submitted archive.")
    require(log.get("issues") in (None, []), "Review notarization warnings or errors before preparing a release.")


def archive_check(archive):
    try:
        with zipfile.ZipFile(archive) as zipped:
            require(zipped.namelist(), "Empty archive.")
            for entry in zipped.infolist():
                path = PurePosixPath(entry.filename)
                require(not path.is_absolute() and ".." not in path.parts and "\\" not in entry.filename,
                        "Unsafe archive path.")
                require(path.parts and (path.parts[0] == APP_NAME or
                        (path.parts[0] == "__MACOSX" and
                         ((len(path.parts) == 1 and entry.is_dir()) or
                          (len(path.parts) > 1 and path.parts[1] in (APP_NAME, "._" + APP_NAME))))),
                        "Archive contains files outside the app and its macOS metadata.")
                require((entry.external_attr >> 16) & 0o170000 != 0o120000, "Archive contains a symlink.")
            require(zipped.testzip() is None, "Damaged archive.")
    except (OSError, zipfile.BadZipFile) as error:
        raise ReleaseError("Invalid release ZIP archive.") from error


def inspect_archive(archive, destination, identity, env):
    archive_check(archive)
    run(["ditto", "-x", "-k", str(archive), str(destination)], env=env)
    children = {path.name for path in destination.iterdir()}
    require(children <= {APP_NAME, "__MACOSX"} and APP_NAME in children, "Unexpected extracted payload.")
    app = destination / APP_NAME
    signed_check(app, identity, env)
    run(["xcrun", "stapler", "validate", str(app)], env=env)
    assessment = text_run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], env=env)
    require("source=Notarized Developer ID" in assessment, "Gatekeeper must identify Notarized Developer ID.")


def distribution_permissions(app):
    for path in [app, *app.rglob("*")]:
        path.chmod(0o755 if path.is_dir() or path == app / "Contents/MacOS" / EXECUTABLE else 0o644)


def private_check(path, env):
    require(not path.is_symlink() and path.stat().st_uid == os.geteuid(), "Candidate paths must be owned by the current user.")
    require(path.stat().st_mode & 0o777 == (0o700 if path.is_dir() else 0o600), "Candidate paths must have owner-only permissions.")
    acl = text_run(["ls", "-lde", str(path)], env=env)
    require(not re.search(r"^\s*[0-9]+:", acl, re.M), "Candidate paths must not have extended ACL entries.")


def acceptance_template(identity, archive_sha, prepared):
    return {
        "schemaVersion": 1, "sourceCommit": identity["sourceCommit"], "artifactSHA256": archive_sha,
        "testedAt": "", "testedBy": "",
        "artifactInspection": {"passed": False, "evidence": ""},
        "platforms": {
            "minimumOS": {"osVersion": "14.x", "architecture": "arm64", "hardware": "", "passed": False, "evidence": ""},
            "currentOS": {"osVersion": "", "architecture": "arm64", "hardware": "", "passed": False, "evidence": ""},
        },
        "runtimeChecks": {key: {"passed": False, "evidence": ""} for key in RUNTIME_CHECKS},
        "candidatePreparedAt": prepared,
    }


def prepare(args):
    env = tooling_env()
    repo = args.repo.resolve()
    require(re.fullmatch(r"[0-9A-Fa-f]{40}", args.identity), "Identity must be a 40-character certificate SHA-1 fingerprint.")
    require(re.fullmatch(r"[A-Z0-9]{10}", args.team_id), "Expected a 10-character Apple team identifier.")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version), "Version must have three numeric components.")
    require(re.fullmatch(r"[1-9][0-9]{0,3}", args.build_number), "Build number must be an integer between 1 and 9999.")
    require(args.current_os_major >= 15, "Current macOS test target must be newer than macOS 14.")
    require(args.tag == "v" + args.version or args.tag.startswith("v" + args.version + "-"), "Version must match the tag.")
    require(args.notary_profile and not args.notary_profile.startswith("-"), "A preconfigured notarytool Keychain profile is required.")
    tag_object, commit = source_identity(repo, args.tag, env)
    verify_identity(args.identity.upper(), args.team_id, env)
    # A profile read check, no secret display, before building or signing.
    run(["xcrun", "notarytool", "history", "--keychain-profile", args.notary_profile, "--output-format", "json"], env=env)
    output = args.output_dir.absolute()
    require(not output.exists() and not output.is_symlink(), "Output directory must not already exist.")
    require(output.parent.is_dir(), "Output parent directory must already exist.")
    output.mkdir(mode=0o700)
    try:
        # POSIX modes do not remove inherited macOS ACL grants.
        run(["chmod", "-N", str(output)], env=env)
        output.chmod(0o700)
        private_check(output, env)
        with tempfile.TemporaryDirectory(prefix=".work-", dir=output) as temp:
            work = Path(temp)
            source = work / "source"
            source.mkdir(mode=0o700)
            # Extract git's immutable archive with tar, never the caller's working tree.
            archived = work / "source.tar"
            run(["git", "-C", str(repo), "archive", "--format=tar", commit], env=env, output=archived)
            run(["tar", "-xf", str(archived), "-C", str(source)], env=env)
            require((source / "build-local.sh").is_file(), "The tagged source has no standalone build script.")
            identity = {
                "tag": args.tag, "tagObject": tag_object, "sourceCommit": commit,
                "sourceSHA256": sha256(source / "Dhwani/DhwaniApp.swift"),
                "version": args.version, "buildNumber": args.build_number,
                "teamID": args.team_id, "signingFingerprint": args.identity.upper(),
                "currentOSMajor": args.current_os_major,
            }
            build = work / "build"
            run(["bash", str(source / "build-local.sh"), "--release", "--output-dir", str(build)], cwd=source, env=env)
            app = build / APP_NAME
            info_path = app / "Contents/Info.plist"
            info = plistlib.loads(info_path.read_bytes())
            info.update(CFBundleShortVersionString=args.version, CFBundleVersion=args.build_number, TalkyGitCommit=commit)
            info_path.write_bytes(plistlib.dumps(info))
            write_json(app / "Contents/Resources/ReleaseProvenance.json", identity)
            bundle_check(app, identity, signed=False, env=env)
            distribution_permissions(app)
            entitlement_path = work / "entitlements.plist"
            entitlement_path.write_bytes(plistlib.dumps(ENTITLEMENTS))
            run(["codesign", "--force", "--sign", identity["signingFingerprint"], "--options", "runtime",
                 "--timestamp", "--entitlements", str(entitlement_path), str(app)], env=env)
            # codesign creates its signature directory under the private preparation umask.
            distribution_permissions(app)
            signed_check(app, identity, env)
            filename = f"Dhwani-{args.tag}-arm64.zip"
            submitted = work / filename
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(submitted)], env=env)
            submitted_sha = sha256(submitted)
            raw = run(["xcrun", "notarytool", "submit", str(submitted), "--keychain-profile", args.notary_profile,
                       "--wait", "--output-format", "json"], env=env)[0]
            submission = json.loads(raw)
            require(submission.get("status") == "Accepted" and
                    re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", submission.get("id", "")),
                    "Notarization must finish with Accepted and a submission ID.")
            log_path = work / "notarization-log.json"
            run(["xcrun", "notarytool", "log", submission["id"], "--keychain-profile", args.notary_profile, str(log_path)], env=env)
            notarization_log_check(read_json(log_path), submission["id"], submitted_sha, filename)
            run(["xcrun", "stapler", "staple", str(app)], env=env)
            run(["xcrun", "stapler", "validate", str(app)], env=env)
            candidate = output / filename
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(candidate)], env=env)
            candidate.chmod(0o600)
            inspected = work / "inspection"
            inspected.mkdir(mode=0o700)
            inspect_archive(candidate, inspected, identity, env)
            require(source_identity(repo, args.tag, env) == (tag_object, commit), "Source tag changed while preparing the candidate.")
            prepared = now()
            archive_sha = sha256(candidate)
            shutil.copyfile(log_path, output / "notarization-log.json")
            (output / "notarization-log.json").chmod(0o600)
            manifest = {
                "schemaVersion": 1, "identity": identity, "artifact": filename, "artifactSHA256": archive_sha,
                "preparedAt": prepared, "submissionID": submission["id"], "submittedArchiveSHA256": submitted_sha,
                "notarizationLogSHA256": sha256(output / "notarization-log.json"),
                "verified": {"signature": True, "hardenedRuntime": True, "minimalEntitlements": True,
                             "notarization": True, "staple": True, "gatekeeper": True, "repackedArtifact": True},
                "publicationApproved": False,
            }
            write_json(output / "manifest.json", manifest)
            write_json(output / "acceptance-template.json", acceptance_template(identity, archive_sha, prepared))
            (output / "SHA256SUMS").write_text(f"{archive_sha}  {filename}\n")
            (output / "SHA256SUMS").chmod(0o600)
            for path in output.iterdir():
                if path != work:
                    private_check(path, env)
        print(f"Private signed and notarized candidate: {output}")
        print("Complete runtime and artifact acceptance evidence is still required.")
    except BaseException:
        shutil.rmtree(output)
        raise


def acceptance_check(acceptance, manifest):
    require(acceptance.get("schemaVersion") == 1 and acceptance.get("sourceCommit") == manifest["identity"]["sourceCommit"]
            and acceptance.get("artifactSHA256") == manifest["artifactSHA256"]
            and acceptance.get("candidatePreparedAt") == manifest["preparedAt"], "Acceptance belongs to a different candidate.")
    require(isinstance(acceptance.get("testedBy"), str) and acceptance["testedBy"].strip(), "Identify the human or automated tester.")
    try:
        accepted = dt.datetime.fromisoformat(acceptance.get("testedAt", ""))
        prepared = dt.datetime.fromisoformat(manifest["preparedAt"])
        require(accepted.tzinfo is not None and prepared.tzinfo is not None and prepared <= accepted
                <= dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=5), "Acceptance time must follow preparation and not be in the future.")
    except (ValueError, TypeError) as error:
        raise ReleaseError("Acceptance needs a timezone-aware timestamp.") from error

    def passed(record):
        return isinstance(record, dict) and record.get("passed") is True and isinstance(record.get("evidence"), str) and record["evidence"].strip()

    require(passed(acceptance.get("artifactInspection")), "Artifact inspection with evidence is required.")
    platforms = acceptance.get("platforms", {})
    require(isinstance(platforms, dict), "Platform acceptance is required.")
    for name in ("minimumOS", "currentOS"):
        record = platforms.get(name, {})
        require(passed(record) and isinstance(record.get("hardware"), str) and record["hardware"].strip()
                and record.get("architecture") == "arm64",
                "Both macOS platform checks require Apple Silicon hardware and evidence.")
        match = re.fullmatch(r"([0-9]+)\.[0-9]+(?:\.[0-9]+)?", record.get("osVersion", ""))
        require(match and int(match[1]) == (14 if name == "minimumOS" else manifest["identity"]["currentOSMajor"]),
                "Record actual macOS 14 and the configured current macOS version.")
    checks = acceptance.get("runtimeChecks", {})
    require(isinstance(checks, dict) and set(checks) == set(RUNTIME_CHECKS) and all(passed(checks[key]) for key in RUNTIME_CHECKS),
            "Every required runtime acceptance check must pass with evidence.")


def verify(args):
    env = tooling_env()
    candidate = args.candidate_dir.resolve()
    require(candidate.is_dir(), "Candidate directory is missing.")
    private_check(candidate, env)
    for name in ("manifest.json", "SHA256SUMS", "notarization-log.json", "acceptance-template.json"):
        private_check(candidate / name, env)
    manifest = read_json(candidate / "manifest.json")
    require(manifest.get("schemaVersion") == 1 and manifest.get("publicationApproved") is False, "Unexpected candidate manifest.")
    identity = manifest.get("identity", {})
    require(isinstance(identity, dict) and re.fullmatch(r"[0-9a-f]{40}", identity.get("sourceCommit", "")), "Invalid source identity.")
    require(source_identity(args.repo.resolve(), identity.get("tag", ""), env) == (identity.get("tagObject"), identity["sourceCommit"]),
            "Local release tag no longer identifies the prepared source.")
    source_bytes = run(["git", "-C", str(args.repo.resolve()), "show", identity["sourceCommit"] + ":Dhwani/DhwaniApp.swift"], env=env)[0]
    require(hashlib.sha256(source_bytes).hexdigest() == identity.get("sourceSHA256"), "Source hash does not match the tagged commit.")
    filename = manifest.get("artifact", "")
    require(filename == f"Dhwani-{identity.get('tag')}-arm64.zip" and Path(filename).name == filename, "Invalid artifact name.")
    archive = candidate / filename
    private_check(archive, env)
    require(archive.is_file() and not archive.is_symlink() and sha256(archive) == manifest.get("artifactSHA256"), "Candidate archive changed.")
    require((candidate / "SHA256SUMS").read_text() == f"{manifest['artifactSHA256']}  {filename}\n", "Checksum record differs from candidate.")
    log_path = candidate / "notarization-log.json"
    require(not log_path.is_symlink() and sha256(log_path) == manifest.get("notarizationLogSHA256"), "Notarization log changed.")
    notarization_log_check(read_json(log_path), manifest.get("submissionID"), manifest.get("submittedArchiveSHA256"), filename)
    acceptance = read_json(args.acceptance)
    acceptance_check(acceptance, manifest)
    with tempfile.TemporaryDirectory(prefix="talky-release-verification-") as temp:
        work = Path(temp)
        run(["chmod", "-N", str(work)], env=env)
        work.chmod(0o700)
        private_check(work, env)
        snapshot = work / filename
        shutil.copyfile(archive, snapshot)
        require(sha256(snapshot) == manifest["artifactSHA256"], "Candidate changed before verification.")
        inspection = work / "inspection"
        inspection.mkdir(mode=0o700)
        inspect_archive(snapshot, inspection, identity, env)
    require(sha256(archive) == manifest["artifactSHA256"], "Candidate changed during verification.")
    print(f"Verified exact candidate: {filename}")
    print(f"SHA256: {manifest['artifactSHA256']}")
    print("All recorded acceptance gates passed. No upload or publication was performed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare", help="Build and notarize a private candidate; never publish")
    prepare_parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    for option in ("tag", "version", "build-number", "identity", "team-id", "notary-profile"):
        prepare_parser.add_argument("--" + option, required=True)
    prepare_parser.add_argument("--output-dir", type=Path, required=True)
    prepare_parser.add_argument("--current-os-major", type=int, required=True,
                                help="Actual current macOS major required for runtime acceptance")
    prepare_parser.set_defaults(action=prepare)
    verify_parser = commands.add_parser("verify", help="Require exact-artifact acceptance evidence; never publish")
    verify_parser.add_argument("--candidate-dir", type=Path, required=True)
    verify_parser.add_argument("--acceptance", type=Path, required=True)
    verify_parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    verify_parser.set_defaults(action=verify)
    args = parser.parse_args()
    os.umask(0o077)
    def stop(signum, frame):
        raise ReleaseError(f"Interrupted by signal {signum}; no publication is approved.")
    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, stop)
    try:
        args.action(args)
    except (ReleaseError, OSError, ValueError, KeyError, TypeError) as error:
        # No raw subprocess output or supplied credential values on stdout/stderr.
        print(f"Release stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
