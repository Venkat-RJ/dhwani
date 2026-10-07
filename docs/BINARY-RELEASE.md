# Preparing a public binary

The public source preview does not establish live dictation acceptance or a verified download.
The tooling here prepares a private candidate, then checks completed acceptance evidence for its exact bytes.
Neither script uploads a GitHub release, installs the app, launches it, grants permissions, or changes audio routing.

Do not publish a binary until the runtime and artifact checks below pass for that exact artifact.
An automated startup probe is useful evidence of launch behavior, but cannot accept speech capture, permissions, or text delivery.
An acceptance JSON file records test outcomes from a human or automation. It cannot establish those outcomes without the linked evidence.
Do not mark pending checks as passed or use mocked regression results as real runtime evidence.
A separate publication action must be covered by maintainer task authorization. Honor authorization already given for the task without adding a new confirmation flow.

## Prerequisites

Use a trusted macOS build machine with the supported standalone Command Line Tools compiler, Python 3.9 or newer, Git, and Apple's signing and notarization tools.
The existing local `setup-cert.sh` and `reinstall.sh` workflow remains separate.
Its self-signed identity cannot prepare a public candidate with these scripts.

Before preparing a release, the release owner must configure:

- A valid **Developer ID Application** certificate and private key in their Keychain.
- The expected Apple team ID and the certificate's SHA-1 fingerprint.
- A named `notarytool` Keychain profile with working notarization credentials.
- An explicit reviewed source tag already present locally.

Configure credentials using Apple's documented `notarytool store-credentials` flow or a separately reviewed secure process.
Do not pass private keys, keychain passwords, Apple ID passwords, or API key contents to these release scripts.
They do not import or export private keys, create identities, unlock keychains, or accept Xcode licenses.
There is no unsigned or ad-hoc fallback and no CI secret import workflow.

Developer ID signing, hardened runtime, a secure timestamp, and notarization are required for this distribution path.
See Apple's [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [Developer ID guidance](https://developer.apple.com/developer-id/).

## Prepare the candidate

Choose the numeric app version matching the tag, a new positive bundle build number, and the current supported macOS major to test.
The output directory must not exist; its parent must exist.
The example uses the currently observed macOS 27 host. Recheck the current supported version when preparing a future release.

```bash
./scripts/prepare-binary-release.sh \
  --tag v1.1.0-beta.2 \
  --version 1.1.0 \
  --build-number 3 \
  --identity YOUR_40_CHARACTER_CERTIFICATE_SHA1 \
  --team-id YOURTEAMID \
  --notary-profile talky-notary \
  --current-os-major 27 \
  --output-dir "$HOME/talky-release-candidate"
```

The example tag is illustrative, not evidence of a published binary.
Select the actual reviewed local tag.
Use `--repo /absolute/repository/path` when preparing a different checkout.
`TALKY_DEVELOPER_DIR` can select a separately configured compatible toolchain.
The default uses `/Library/Developer/CommandLineTools` without changing the global developer selection.

The script first verifies the requested signing identity and reads the existing notary profile.
It archives the tag's immutable commit into a private temporary directory and builds that snapshot with `build-local.sh --release`.
Uncommitted checkout changes cannot enter the build.
It sets the supplied app version and build number before signing and embeds `ReleaseProvenance.json` containing the tag object, commit, source hash, signing identity, and required platform major.
It rejects unexpected bundle files, symlinks, nested code, a non-arm64 executable, or a deployment target other than macOS 14.0.

Signing uses hardened runtime and a secure timestamp.
The only entitlement is `com.apple.security.device.audio-input=true`, required for microphone input under the hardened runtime.
The script reads back the signed entitlements and signer certificate, then checks the exact team and certificate fingerprint.
See Apple's [Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input) and [hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime).
Adding helpers or frameworks requires a reviewed extension to this explicit bundle contract and separate appropriate signing. Do not enable recursive signing to bypass it.

It submits the first ZIP to Apple's notarization service and waits for `Accepted`.
It requires the notarization log to identify that submission and archive checksum, with no issues or warnings.
It staples the app, creates the final ZIP, extracts it again, and repeats signature, entitlement, staple, and Gatekeeper checks on the app that will actually ship.
ZIP files cannot be stapled directly; Apple's [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) describes stapling the app and repackaging it.
Notarization may take time and sends the app to Apple's service.
An interrupted submission may continue at Apple even though this script removes the local partial candidate.

Successful preparation creates an owner-only directory (`0700`) with owner-only files (`0600`).
Inherited extended ACLs are removed from the candidate directory before any build or artifact bytes enter it.
The script verifies ownership, restrictive modes, and absence of ACL entries on the final directory and metadata.
The directory contains:

- `Lokaah-Talky-<tag>-arm64.zip`: the stapled app archive.
- `SHA256SUMS`: its final SHA-256 checksum.
- `manifest.json`: immutable source and artifact identities and completed tool checks.
- `notarization-log.json`: the accepted submission's reviewed log.
- `acceptance-template.json`: acceptance fields left blank or false.

The app inside the archive uses normal distribution permissions, including an executable binary and readable signature resources.
Preparation errors and handled interruption remove the partial output directory.
Tool failures stop the release without dumping raw credential-related output to the terminal.
Keep the private manifest, log, and acceptance evidence private. Public distribution needs only the reviewed ZIP and checksum, plus any deliberately prepared public release notes.

## Accept the exact binary

Extract and inspect the final ZIP in a clean test environment.
Run the exact signed candidate on Apple Silicon with macOS 14 and the configured current macOS major.
Do not substitute an unsigned Debug build, a differently signed app, an earlier source build, or a newer rebuild for these checks.
Check clean-machine installation and the original tagged artifact after download as well as local extraction.

Review the artifact for private data, transcripts, recordings, keys, unrelated files, attribution, correct version, and current behavior.
Record synthetic or redacted evidence and actual hardware and OS versions.
Complete every runtime field in the generated template, including:

- Short and long on-device capture, with recognition-session renewal.
- Permission denial and recovery, unavailable local models, and microphone failure.
- Cancellation during capture and processing without delivery or persistence.
- Delivery into TextEdit, a browser, an editor, and a harmless terminal prompt.
- Moving to another app or field preventing automatic paste.
- Auto-send off by default and explicit opt-in behavior using harmless text.
- Private storage permissions, retention, and isolated test capture without normal delivery or persistence.
- Test result removal and clean-machine installation.

Copy `acceptance-template.json` to a separate private acceptance file.
The tester can be a human or automation that actually exercised the relevant behavior.
Use a timezone-aware `testedAt`, identify the tester in `testedBy`, and include evidence for every passing field.
Missing live capture or delivery checks remain pending even if compilation, mocked tests, startup probes, or notarization succeeded.
Do not reuse a record after rebuilding, resigning, restapling, or repackaging, because any changed artifact checksum invalidates acceptance.

```bash
./scripts/verify-binary-release.sh \
  --candidate-dir "$HOME/talky-release-candidate" \
  --acceptance "$HOME/talky-release-acceptance.json"
```

The verifier requires the local source tag to remain unchanged, checks the source hash, final checksum, and accepted notarization log, validates complete acceptance evidence, and re-extracts and assesses a private snapshot of the archive again.
Use `--repo` if the candidate came from another checkout.
A passing result verifies the technical release gates; it performs no upload itself.
Publish only through a maintainer-authorized action, including authorization already present in the task.
The manifest retains `publicationApproved=false` because preparation never publishes or grants authorization.

## Regression checks without real credentials

```bash
DEVELOPER_DIR=/Library/Developer/CommandLineTools python3 -I test/test-release.py
```

These tests create isolated local Git fixtures and mock signing, Keychain inspection, notarization, Gatekeeper, and packaging tools.
They exercise successful exact-source preparation and rejection of missing identities, wrong metadata, private payloads, signing failures, incorrect entitlements, mismatched notarization logs, partial acceptance, tampering, moved tags, and interruption.
They do not sign an app, contact Apple, import a key, install an app, publish an artifact, or provide runtime acceptance.
