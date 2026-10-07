# Security policy

The `main` branch receives security fixes.
Version `1.1.0-beta.1` is a source preview.
Live dictation and binary distribution checks remain open in [PRODUCT.md](PRODUCT.md#release-readiness).

Historical `v1.0.0` binaries predate the current privacy and delivery changes and have not passed the current release checks.

## Report a vulnerability

Report vulnerabilities through [GitHub private vulnerability reporting](https://github.com/Venkat-RJ/dhwani/security/advisories/new).
It is enabled for this public repository.
If it is unavailable, use the contact details on [the maintainer's profile](https://github.com/Venkat-RJ).

Keep exploit details, transcripts, credentials, and private recordings out of public issues.
Include the affected commit or release, macOS version, prerequisites, impact, and a small reproduction using synthetic data.
Explain what you reproduced and what remains unconfirmed.
Identify dependency advisories and possible attack paths separately.

There is no guaranteed response time.

## Security boundaries

Dhwani's source requires on-device recognition for the selected language through Apple's Speech framework.
The recognition engine and models are supplied by Apple and are proprietary.
The source checks and Apple's documented API contract do not establish an independent audit of runtime network activity or Apple's broader data handling.
See [speech recognition and privacy](docs/PRIVACY.md).

Regular dictation replaces the clipboard.
Automatic paste requires Accessibility access and checks that the original app and focused text field still match.
When explicitly enabled, auto-send presses Return after paste and can submit a message or run a terminal command.
Cancellation and destination checks must apply to these paths.

The `talky_cmd` file lets processes running as your user control dictation.
Use it only with trusted scripts. It is not an authentication boundary.

Owner-only permissions restrict other local accounts' access to transcript storage.
Software running as your user can still access it.
Private storage and exports use owner-only file modes and clear extended ACL access grants.

History and exports are unencrypted.
Exporting to a shared or synchronized folder can create copies outside Dhwani's storage controls.

History and the latest-transcript file are off on a fresh installation.
Upgrades preserve saved choices.
Turning history off stops new saves and leaves existing records available for deletion.
Deleting history leaves exported files and clipboard contents in place.

## Signing and dependencies

Self-signed builds and signing identities are for local development.
Keep private signing keys out of reports and releases.
Public binaries require Developer ID signing, notarization, and checks of the exact release artifact.
See [the binary release workflow](docs/BINARY-RELEASE.md).

A dependency audit describes the versions checked at that time.
Update and audit the optional video toolchain before using its development server.
