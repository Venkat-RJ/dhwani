#!/usr/bin/env python3
"""Package or launch a CI test app without recording or changing TCC grants."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid
import zipfile


class SmokeError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise SmokeError(message)


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    require(result.returncode == 0, f"{Path(args[0]).name} failed (exit {result.returncode})")
    return result.stdout


def private_path(path, directory=False):
    info = path.lstat()
    require(info.st_uid == os.getuid(), "Smoke path has the wrong owner")
    require(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode),
            "Smoke path is not a regular private path")
    require(stat.S_IMODE(info.st_mode) == (0o700 if directory else 0o600),
            "Smoke path has non-private permissions")
    if not directory:
        require(info.st_nlink == 1 and info.st_size < 64 * 1024, "Unsafe smoke result file")
    acl = command("/bin/ls", "-lde", str(path))
    require(re.search(r"\n\s*\d+:", acl) is None, "Smoke path has an extended ACL")


def bundle_info(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(info.get("CFBundleIdentifier") == "com.lokaah.talky" and
            info.get("CFBundleExecutable") == "Lokaah Talky", "Unexpected app bundle identity")
    return info


def utc(value):
    require(isinstance(value, str) and value.endswith("Z"), "Probe timestamp must be UTC")
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def validate_probe(probe, *, run_id, process_id, started, now, source, commit, info, os_major=None):
    fields = {"schemaVersion", "kind", "runID", "createdAt", "processID", "sourceSHA256", "gitCommit",
              "buildMethod", "version", "build", "osMajor", "osMinor", "osPatch", "architecture", "phase",
              "busy", "microphoneAllowed", "speechAllowed", "accessibilityAllowed",
              "supportsOnDeviceRecognition", "recognizerAvailable"}
    require(isinstance(probe, dict) and set(probe) <= fields, "Probe contains unexpected information")
    require(type(probe.get("schemaVersion")) is int and probe["schemaVersion"] == 1 and
            probe.get("kind") == "readiness", "Wrong probe schema")
    require(probe.get("runID") == run_id, "Wrong probe UUID")
    require(type(probe.get("processID")) is int and probe["processID"] == process_id, "Wrong probe process")
    require(started <= utc(probe.get("createdAt")) <= now + 1, "Stale probe result")
    require(probe.get("sourceSHA256") == source, "Wrong probe source identity")
    require(probe.get("gitCommit") == commit, "Wrong probe commit identity")
    require(probe.get("buildMethod") == info.get("TalkyBuildMethod"), "Wrong probe build method")
    require(probe.get("version") == info["CFBundleShortVersionString"] and
            probe.get("build") == info["CFBundleVersion"], "Wrong probe bundle version")
    require(probe.get("architecture") == "arm64", "Probe did not run on Apple Silicon")
    for key in ("osMajor", "osMinor", "osPatch"):
        require(type(probe.get(key)) is int and probe[key] >= 0, "Invalid probe OS version")
    require(probe["osMajor"] >= 14, "Unsupported probe OS")
    if os_major is not None:
        require(probe["osMajor"] == os_major, "Probe ran on the wrong OS major")
    for key in ("busy", "microphoneAllowed", "speechAllowed", "accessibilityAllowed",
                "supportsOnDeviceRecognition", "recognizerAvailable"):
        require(type(probe.get(key)) is bool, "Invalid probe readiness flag")
    require(probe.get("phase") in ("idle", "denied", "unavailable") and not probe["busy"],
            "Startup probe unexpectedly reports an active capture")
    require(not any(key in probe for key in ("transcript", "microphone", "vocabulary", "statusMessage", "history")),
            "Probe contains private capture information")
    return probe


def package(args):
    source_hash = digest(args.source)
    require(re.fullmatch(r"[0-9a-f]{40}", args.commit) is not None, "Expected a full commit SHA")
    repo = Path(__file__).resolve().parents[1]
    source_path = args.source.resolve().relative_to(repo)
    require(str(source_path) == "Lokaah Talky/LokaahTalkyApp.swift", "Expected this checkout's app source")
    revision = subprocess.run(["git", "-C", str(repo), "show", args.commit + ":" + str(source_path)],
                              capture_output=True)
    require(revision.returncode == 0 and hashlib.sha256(revision.stdout).hexdigest() == source_hash,
            "Source does not match the supplied commit")
    output = args.output.resolve()
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    app = output / "Lokaah Talky.app"
    command("/usr/bin/ditto", str(args.app.resolve()), str(app))
    info_path = app / "Contents/Info.plist"
    info = bundle_info(app)
    info.update(TalkySourceSHA256=source_hash, TalkyGitCommit=args.commit, TalkyBuildMethod="ci-startup-test")
    with info_path.open("wb") as stream:
        plistlib.dump(info, stream)
    command("/usr/bin/codesign", "--force", "--sign", "-", str(app))
    command("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    archive = output / "startup-test.zip"
    command("/usr/bin/ditto", "-c", "-k", "--norsrc", "--keepParent", str(app), str(archive))
    manifest = {"schemaVersion": 1, "kind": "startup-test-only", "gitCommit": args.commit,
                "sourceSHA256": source_hash, "archiveSHA256": digest(archive),
                "executableSHA256": digest(app / "Contents/MacOS" / info["CFBundleExecutable"])}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.rmtree(app)
    print("Packaged ad-hoc CI startup app. It is not a notarized release.")


def artifact_app(directory, target, expected_commit, expected_source):
    manifest = json.loads((directory / "manifest.json").read_text())
    require(manifest.get("schemaVersion") == 1 and manifest.get("kind") == "startup-test-only", "Wrong artifact kind")
    require(manifest.get("gitCommit") == expected_commit and manifest.get("sourceSHA256") == expected_source,
            "Artifact identity does not match this checkout")
    archive = directory / "startup-test.zip"
    require(digest(archive) == manifest.get("archiveSHA256"), "Corrupt startup archive")
    with zipfile.ZipFile(archive) as stream:
        for item in stream.infolist():
            path = Path(item.filename)
            require(not path.is_absolute() and ".." not in path.parts and
                    path.parts and path.parts[0] == "Lokaah Talky.app", "Unsafe startup archive entry")
            require(not stat.S_ISLNK(item.external_attr >> 16), "Symlink in startup archive")
    command("/usr/bin/ditto", "-x", "-k", str(archive), str(target))
    app = target / "Lokaah Talky.app"
    info = bundle_info(app)
    require(digest(app / "Contents/MacOS" / info["CFBundleExecutable"]) == manifest.get("executableSHA256"),
            "Wrong startup executable")
    return app


def run(args):
    require(sys.platform == "darwin", "Startup smoke requires macOS")
    require(re.fullmatch(r"[0-9a-f]{64}", args.source_sha256) is not None, "Expected a source SHA256")
    require(args.commit is None or re.fullmatch(r"[0-9a-f]{40}", args.commit) is not None, "Expected a commit SHA")
    if args.artifact_dir:
        require(args.commit is not None, "Transferred CI artifact requires a commit SHA")
    with tempfile.TemporaryDirectory(prefix="talky-startup-") as scratch:
        root = Path(scratch)
        app = artifact_app(args.artifact_dir, root / "extracted", args.commit, args.source_sha256) if args.artifact_dir else args.app.resolve()
        info = bundle_info(app)
        require(info.get("TalkySourceSHA256") == args.source_sha256 and info.get("TalkyGitCommit") == args.commit,
                "App identity differs from the expected source")
        command("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
        data = root / "data"
        data.mkdir(mode=0o700)
        command("/bin/chmod", "-N", str(data))
        private_path(data, directory=True)
        run_id = str(uuid.uuid4()).upper()
        env = dict(os.environ, TALKY_DATA_DIR=str(data))
        started = time.time()
        process = subprocess.Popen([str(app / "Contents/MacOS" / info["CFBundleExecutable"])], env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + args.timeout
            command_file = data / "talky_cmd"
            while not command_file.exists():
                require(process.poll() is None, "App exited before command watcher started")
                require(time.monotonic() < deadline, "App command watcher did not start")
                time.sleep(0.1)
            private_path(command_file)
            with os.fdopen(os.open(command_file, os.O_RDWR | os.O_NOFOLLOW), "r+") as stream:
                require(stream.read() == "", "Unexpected command in isolated startup directory")
                stream.write("test-probe:" + run_id)
                stream.flush()
            result_path = data / "probe-results" / (run_id + ".json")
            while not result_path.exists():
                require(process.poll() is None, "App exited before readiness probe completed")
                require(time.monotonic() < deadline, "Readiness probe timed out")
                time.sleep(0.1)
            private_path(result_path.parent, directory=True)
            private_path(result_path)
            probe = json.loads(result_path.read_text())
            validate_probe(probe, run_id=run_id, process_id=process.pid, started=started, now=time.time(),
                           source=args.source_sha256, commit=args.commit, info=info, os_major=args.os_major)
            require(not (data / "voice_history").exists() and not (data / "voice_input.txt").exists() and
                    not (data / "test-results").exists(), "Startup probe created transcript storage")
            require(process.poll() is None, "App exited after readiness probe")
            evidence = {"schemaVersion": 1, "kind": "startup-smoke", "passed": True,
                        "scope": "Launch and read-only readiness. No recording or delivery acceptance.", "probe": probe}
            if args.result:
                require(not args.result.exists(), "Refusing to replace startup evidence")
                args.result.parent.mkdir(parents=True, exist_ok=True)
                with args.result.open("x") as stream:
                    command("/bin/chmod", "-N", str(args.result))
                    args.result.chmod(0o600)
                    private_path(args.result)
                    json.dump(evidence, stream, indent=2)
                    stream.write("\n")
            print(f"PASS: actual app startup on macOS {probe['osMajor']}.{probe['osMinor']}.{probe['osPatch']} arm64")
            print("Readiness only. No microphone, speech, or Accessibility permission was requested.")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def main():
    os.umask(0o077)
    def interrupted(signum, frame):
        # Let run()'s finally reap its own app before exiting, even on a second signal.
        for event in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(event, signal.SIG_IGN)
        raise SmokeError("Startup smoke interrupted")
    for event in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(event, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    prepared = subparsers.add_parser("package", help="Make a test-only ad-hoc artifact from a CI build")
    prepared.add_argument("--app", type=Path, required=True)
    prepared.add_argument("--source", type=Path, required=True)
    prepared.add_argument("--commit", required=True)
    prepared.add_argument("--output", type=Path, required=True)
    startup = subparsers.add_parser("run", help="Launch a test app and validate its read-only readiness result")
    chosen = startup.add_mutually_exclusive_group(required=True)
    chosen.add_argument("--app", type=Path)
    chosen.add_argument("--artifact-dir", type=Path)
    startup.add_argument("--source-sha256", required=True)
    startup.add_argument("--commit")
    startup.add_argument("--os-major", type=int)
    startup.add_argument("--timeout", type=int, choices=range(1, 61), default=20, metavar="1..60")
    startup.add_argument("--result", type=Path)
    args = parser.parse_args()
    try:
        package(args) if args.operation == "package" else run(args)
    except (SmokeError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
