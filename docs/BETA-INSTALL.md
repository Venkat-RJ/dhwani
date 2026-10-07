# Install the unnotarized Dhwani beta

**No public beta installer has been released yet.**
A private **Dhwani** DMG has been prepared for coordinated testing.
It can be shared with a friend who understands that installation, dictation, and paste still need testing on another Mac.
Older private packages named **Lokaah Talky** retain their name and original checksums.
Use the exact filename, version, checksum, and test scope supplied by the maintainer.

This beta is signed with the project's local certificate and has not been notarized by Apple.
macOS may block the first launch because it cannot verify the developer.
The certificate is not a Developer ID certificate issued by Apple.

Use an Apple Silicon Mac with macOS 14 or newer.
Windows, Linux, and Intel Macs are not supported by this build.
The selected speech language needs an available on-device model.

For a private test, use the exact package supplied by the maintainer with its version, checksum, and test scope.
Public downloads, when available, belong on the [official Dhwani releases](https://github.com/Venkat-RJ/dhwani/releases).
If no app asset is listed, a public downloadable beta has not been published yet.
GitHub's automatic source archives are source code, not the app.

## Install

1. Finish any recording and quit an older Dhwani copy.
   When replacing Lokaah Talky with Dhwani, move the old app to Trash before installing the renamed copy. Keep your separate saved data if you want to preserve it.
2. Open the DMG in Finder, or expand the ZIP if that is the test package you received.
3. Drag the app into Applications. New builds use **Dhwani.app**; older private packages use **Lokaah Talky.app**. For a DMG, use the Applications shortcut and eject the disk after copying. Open the copy in Applications.
4. If macOS blocks it, review the warning. If you trust this exact download, open **System Settings > Privacy & Security** and use **Open Anyway** for Dhwani, if available. Confirm the app-specific prompt.

Some managed Macs do not allow this exception.
Do not disable Gatekeeper, remove quarantine attributes, install the signing certificate as a trusted root, or run an installation script with administrator privileges.
See [Apple's instructions](https://support.apple.com/en-us/102445) for the standard per-app approval flow.

The matching `SHA256SUMS` file lets technical users check that the download matches the published bytes.
An archive checksum does not provide Apple verification or establish that an app is safe.

## First use

Dhwani opens as a small floating widget.
Expand it to see the setup screen.
Read the [speech privacy disclosure](https://github.com/Venkat-RJ/dhwani/blob/main/docs/PRIVACY.md) before granting Speech Recognition access.
Microphone and Speech Recognition access are needed to dictate.
Accessibility is optional and enables automatic paste.

Focus the text field you want to write in.
Press **Option-Space**, speak, then press **Option-Space** again to finish.
Use **Command-V** if automatic paste is unavailable or blocked.
Press **Option-Escape** to cancel without delivery or storage.

Apple supplies the speech engine and models.
Dhwani requires on-device recognition and has no network-recognition fallback.
Regular dictation replaces the clipboard.
Automatic paste requires the original app and text field to remain focused.
Auto-send starts off and should stay off until you deliberately choose to send Return after pasting.

## Updates and removal

Updates are manual: finish recording, quit Dhwani, and replace the Applications copy with the new version.
Saved preferences survive upgrades.
macOS may ask for permissions again, particularly if the signing identity changes.
Do not run two Dhwani copies at the same time.

To uninstall, quit Dhwani and move the app from Applications to Trash.
Saved history and preferences are separate from the app.
See the [storage documentation](https://github.com/Venkat-RJ/dhwani#privacy-and-local-storage) before removing data you may want to keep.

Report reproducible problems through [GitHub issues](https://github.com/Venkat-RJ/dhwani/issues), with the version, macOS version, language, and steps.
Use synthetic text and remove private dictations from reports.
