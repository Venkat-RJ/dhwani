# Preparing a public binary

Talky is currently a public source preview.
Live dictation acceptance and a verified download remain separate release requirements.

Use this workflow to prepare a private candidate and verify the evidence for the exact archive you intend to publish.
The scripts do not upload a GitHub release, install or launch the app, grant permissions, or change audio routing.

Do not publish a binary until the runtime and artifact checks below pass for that exact artifact.
A startup probe shows that the app launched. Speech capture, permission recovery, and text delivery still need their own checks.

The acceptance JSON records outcomes from a human tester or automation.
Record evidence for each passing check.
Leave unfinished checks pending, and keep mocked regression results separate from runtime evidence.

Publication requires a maintainer-authorized action.
Authorization already given for the task remains valid; this workflow does not require a second confirmation.

## Prerequisites

Use a trusted macOS build machine with the supported standalone Command Line Tools compiler, Python 3.9 or newer, Git, and Apple's signing and notarization tools.
The local `setup-cert.sh` and `reinstall.sh` workflow is for development.
Its self-signed identity cannot prepare a public candidate through these scripts.

The release owner must configure these before preparing a candidate:

- A valid **Developer ID Application** certificate and private key in their Keychain.
- The expected Apple team ID and the certificate's SHA-1 fingerprint.
- A named `notarytool` Keychain profile with working notarization credentials.
- An explicit reviewed source tag already present locally.

Configure credentials using Apple's documented `notarytool store-credentials` flow or a separately reviewed secure process.
Do not pass private keys, keychain passwords, Apple ID passwords, or API key contents to these release scripts.

The scripts use the configured identity and profile.
They do not import or export private keys, create identities, unlock keychains, or accept Xcode licenses.
They provide no unsigned or ad-hoc fallback and no workflow for importing secrets into CI.

Developer ID signing, hardened runtime, a secure timestamp, and notarization are required for this distribution path.
See Apple's [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [Developer ID guidance](https://developer.apple.com/developer-id/).

## Prepare the candidate

Choose the numeric app version that matches the tag and a new positive bundle build number.
Also choose the current supported macOS major for acceptance testing.

The output directory must not exist. Its parent must exist.
The example below uses the macOS 27 host observed during this review.
Recheck the current supported version for a future release.

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

Replace the example tag with the actual reviewed local tag.
The example does not describe a published binary.

Use `--repo /absolute/repository/path` when preparing a different checkout.
`TALKY_DEVELOPER_DIR` can select a separately configured compatible toolchain.
By default, the script uses `/Library/Developer/CommandLineTools` and leaves the global developer selection unchanged.

Preparation proceeds in this order:

1. Verify the requested signing identity and read the existing notary profile.
2. Archive the tag's immutable commit into a private temporary directory and build that snapshot with `build-local.sh --release`.
   Uncommitted checkout changes cannot enter the build.
3. Set the supplied app version and build number before signing.
   Embed `ReleaseProvenance.json` with the tag object, commit, source hash, signing identity, and required platform major.
4. Check the bundle contents and executable.
   Reject unexpected files, symlinks, nested code, a non-arm64 executable, or a deployment target other than macOS 14.0.

Signing uses hardened runtime and a secure timestamp.
The only entitlement is `com.apple.security.device.audio-input=true`, required for microphone input under the hardened runtime.
After signing, the script reads back the entitlements and signer certificate.
It checks the exact team and certificate fingerprint.
See Apple's [Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input) and [hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime).

Adding helpers or frameworks requires a review of the allowed bundle contents and separate signing for the added code.
Do not use recursive signing to bypass those checks.

The script submits the first ZIP to Apple's notarization service and waits for `Accepted`.
The notarization log must identify that submission and archive checksum, with no issues or warnings.

It then staples the app, creates the final ZIP, and extracts it again.
Signature, entitlement, staple, and Gatekeeper checks are repeated on this final copy of the app.
ZIP files cannot be stapled directly.
Apple's [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) describes stapling the app and repackaging it.

Notarization may take time and sends the app to Apple's service.
If preparation is interrupted, the submission may continue at Apple even after the script removes the local partial candidate.

Successful preparation creates an owner-only directory (`0700`) with owner-only files (`0600`).
Inherited extended ACLs are removed before the script writes build or artifact data into the candidate directory.
The script verifies ownership, private permissions, and the absence of ACL entries on the final directory and metadata.
The directory contains:

- `Lokaah-Talky-<tag>-arm64.zip`: the stapled app archive.
- `SHA256SUMS`: its final SHA-256 checksum.
- `manifest.json`: immutable source and artifact identities and completed tool checks.
- `notarization-log.json`: the accepted submission's reviewed log.
- `acceptance-template.json`: acceptance fields left blank or false.

The app inside the archive uses normal distribution permissions, including an executable binary and readable signature resources.

Preparation errors and handled interruptions remove the partial output directory.
Tool failures stop preparation without printing raw credential-related output to the terminal.

Keep the manifest, log, and acceptance evidence private.
Publish only the reviewed ZIP and checksum, together with any release notes prepared for public sharing.

## Accept the exact binary

Extract and inspect the final ZIP in a clean test environment.
Run the exact signed candidate on Apple Silicon with macOS 14 and the configured current macOS major.
Do not substitute an unsigned Debug build, a differently signed app, an earlier source build, or a newer rebuild for these checks.
Check installation on a clean machine.
Check the original tagged artifact after download as well as after local extraction.

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
The tester can be a human or automation that exercised the relevant behavior.
Use a timezone-aware `testedAt`, identify the tester in `testedBy`, and include evidence for every passing field.

Live capture and delivery checks remain pending until they are completed.
Compilation, mocked tests, startup probes, and notarization do not complete them.

Do not reuse an acceptance record after rebuilding, resigning, restapling, or repackaging.
A changed artifact checksum invalidates that record.

```bash
./scripts/verify-binary-release.sh \
  --candidate-dir "$HOME/talky-release-candidate" \
  --acceptance "$HOME/talky-release-acceptance.json"
```

The verifier checks that the local source tag is unchanged.
It checks the source hash, final checksum, accepted notarization log, and complete acceptance evidence.
It also extracts and assesses a private snapshot of the archive again.

Use `--repo` if the candidate came from another checkout.
A passing result verifies the technical release requirements. It does not upload anything.
Publish through a maintainer-authorized action, using any authorization already present in the task.
The manifest retains `publicationApproved=false` because preparation never publishes or grants authorization.

## Regression checks without real credentials

```bash
DEVELOPER_DIR=/Library/Developer/CommandLineTools python3 -I test/test-release.py
```

These tests create isolated local Git fixtures and mock signing, Keychain inspection, notarization, Gatekeeper, and packaging tools.
They check preparation from the exact source and rejection of missing identities, wrong metadata, private payloads, signing failures, incorrect entitlements, mismatched notarization logs, incomplete acceptance, tampering, moved tags, and interruption.

They do not sign an app, contact Apple, import a key, install an app, or publish an artifact.
Real signing and runtime acceptance still require the checks above.
