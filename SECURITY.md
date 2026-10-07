# Security policy

The development branch receives security fixes.
Version `1.1.0-beta.1` is a source preview with runtime and distribution checks still open.
Historical `v1.0.0` binaries predate the current privacy and delivery changes.
They are not a verified distribution of the hardened app.

## Report a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/Venkat-RJ/lokaah-talky/security/advisories/new), enabled for this public repository.
If that route is unavailable, use the contact details published by [the maintainer](https://github.com/Venkat-RJ).
Do not put exploit details, transcripts, credentials, or private recordings in a public issue.

Include the affected commit or release, macOS version, prerequisites, impact, and a minimal reproduction using synthetic data.
Separate a demonstrated exploit from a dependency advisory or a possible attack path.
There is no guaranteed response time at this stage.

## Security boundaries

Talky requires on-device recognition.
Regular dictation replaces the clipboard and can paste into a validated original destination.
Auto-send can execute or submit that text when explicitly enabled.
Those paths must preserve cancellation and destination checks.

The command file is intentionally available to trusted processes running as the same user.
Owner-only file permissions help protect local transcript storage from other accounts.
They do not isolate it from software already running as its owner.
Private storage and exports clear extended ACL grants as well as applying owner-only file modes.
Local history and exports are unencrypted.
Exporting to a shared or synchronized folder can create copies outside Talky's storage controls.

History and latest-transcript persistence start off on a fresh installation.
Upgrades preserve saved choices. Disabling history stops new saves and leaves existing records available for explicit deletion.
Deleting history does not remove exported files or clear the clipboard.

Local self-signed builds and signing identities are for development.
Never attach a private signing key to a report or release.
Published binaries require separate signing, notarization, and artifact checks.

Dependency audit results are a snapshot.
The optional video toolchain should be updated and audited before using its development server.
