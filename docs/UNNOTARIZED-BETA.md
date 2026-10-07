# Prepare a beta without an Apple developer membership

This is an explicit distribution option for an unnotarized beta.
It uses a stable local signing certificate, a versioned source snapshot, an app ZIP, installation notes, and checksums.
It does not use Apple's notarization service or require a paid Developer ID certificate.
It does not grant trust to the certificate on anyone's Mac.
The [notarized release workflow](BINARY-RELEASE.md) remains a separate option.

The maintainer requested public distribution of `v1.1.0-beta.4` as an experimental beta before full runtime acceptance.
The website links its DMG directly. [Release notes](https://github.com/Venkat-RJ/dhwani/releases/tag/v1.1.0-beta.4) and the [verification record](VERIFICATION.md) describe completed and pending checks.
This publication does not satisfy the verification workflow below or change its acceptance requirements.

The app still uses Apple's Speech framework.
Read [the privacy disclosure](PRIVACY.md).

## Prepare a private candidate

Use an existing code-signing identity whose private key stays in your login Keychain.
Reusing the same certificate helps macOS recognize later versions.
Changing it can require fresh app permissions.
`setup-cert.sh` can create a local identity, but it changes the Keychain and is a separate setup step.

Review and commit the intended source and create an explicit beta tag before building.
The packager builds the tagged source, so uncommitted changes cannot enter the app.
The output directory must not already exist.

```bash
./scripts/prepare-beta.sh \
  --tag v1.1.0-beta.2 --version 1.1.0 --build-number 3 \
  --identity YOUR_40_CHARACTER_CERTIFICATE_SHA1 \
  --current-os-major 27 \
  --output-dir "$HOME/talky-unnotarized-beta"
```

The version and tag above are examples, not a promise that a download exists.
Use the actual current macOS major when preparing a later candidate.
The script builds an optimized arm64 app targeting macOS 14.
It signs with hardened runtime and only the audio-input entitlement, with no secure timestamp or notarization request.
It validates the exact certificate, bundle contents, source identity, and extracted archive.
It copies only the tagged installation guide, privacy disclosure, and MIT license alongside the app ZIP.

Candidate files use owner-only permissions.
The app inside the ZIP has normal distribution permissions.
No private key, recording, transcript, Keychain contents, or user preferences are packaged.
No app is installed or launched and nothing is published by this command.

## Test the exact archive

Copy `acceptance-template.json` to a private acceptance record.
Every test needs an actual result and evidence tied to this candidate's checksum.
Use [TESTING.md](../TESTING.md) for capture, delivery, permissions, cancellation, and storage checks.
Run the app on macOS 14 and a current macOS release on Apple Silicon.
Check the downloaded archive's installation on a clean Mac, including the normal app-specific approval flow in [BETA-INSTALL.md](BETA-INSTALL.md).
An already approved development copy cannot establish that first-install behavior.

Also record offline recognition and runtime network observations from the app and relevant speech services.
Describe the environment and the limits of those observations.
A traffic observation is not proof about every Apple service or future version.
Keep failures and unfinished checks marked as pending.

```bash
./scripts/verify-beta.sh \
  --candidate-dir "$HOME/talky-unnotarized-beta" \
  --acceptance "$HOME/talky-beta-acceptance.json"
```

Verification rejects missing evidence, changed archives, changed public documents, moved tags, incorrect signatures, and unexpected bundled files.
It never treats the lack of notarization as a successful Gatekeeper assessment.
The notarized verifier continues to reject this candidate.
Rebuilding, resigning, or repackaging requires new acceptance evidence.

## Publish after acceptance

Create a GitHub prerelease with **Unnotarized beta** in its title and first paragraph.
Publish only the app ZIP, `INSTALL.md`, `PRIVACY.md`, `LICENSE`, and `SHA256SUMS` from the verified directory.
Keep the manifest and detailed acceptance evidence private; summarize actual results and limitations in release notes.
Link the immutable source tag and make the supported hardware and macOS versions clear.

Do not tell people to disable Gatekeeper, strip quarantine attributes, trust a new root certificate, or run privileged shell commands to install the app.
Some managed Macs will not permit this beta.
An unsigned installer, another hosting service, or a package-manager listing does not create an Apple-verified identity.

The tooling prepares and verifies the candidate locally.
Publication is a separate maintainer action.
