# Local storage and clipboard

Regular dictation replaces the previous clipboard contents.
Other apps can read the clipboard, and the destination app handles pasted text under its own policies.
Deleting Dhwani history does not clear the clipboard.

## What starts off

History, the latest-transcript file, and launch at login start off on a fresh installation.
Upgrades preserve saved preferences and existing launch-at-login registration.
Auto-send also starts off. Enable it only when you intend to send Return after pasting.

## History

If you enable history, Dhwani stores transcripts under `~/.talky/voice_history/`.
The files are unencrypted and use owner-only permissions.
You can keep entries for 1, 7, or 30 days, or until you delete them.
Retention is checked at startup, when history settings change, and after saving a dictation.

Turning history off stops new saves and leaves existing entries available.
Use the History screen to search, copy, export, or delete entries.
Deleting history does not remove exported copies or clear the clipboard.

## Latest-transcript file

The optional latest-transcript file is `~/.talky/voice_input.txt`.
Turning that setting off removes the file.
Scripts running as your user can control Dhwani through its command file.
Use trusted scripts and read [TESTING.md](../TESTING.md) for the interface and isolated test results.

## Removing the app

Quitting Dhwani and moving it to Trash removes the app, not its saved history and preferences.
Export anything you want to keep before deleting local records.
Use the app's History controls to delete saved dictations and turn off the latest-transcript setting to remove its output file.
Exported copies must be managed separately.

For Apple's role in speech processing, read [the privacy disclosure](PRIVACY.md).
