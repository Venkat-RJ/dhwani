# Help test Talky

Talky is an MIT-licensed source preview for Apple Silicon Macs.
We are looking for help with installation, permissions, dictation, and pasting into everyday apps.
You do not need to write code to report a useful result.

## Get started

There is no public app download yet.
Developers can [build from source](../BUILD.md).
If you would like to help test a packaged beta, [register your interest](https://github.com/Venkat-RJ/lokaah-talky/issues/new?template=early_testing.yml).
A maintainer can then coordinate an appropriate candidate and test scope with you.
Submitting the form does not install anything or guarantee a download.

The build targets macOS 14 or newer on Apple Silicon.
Live dictation on macOS 14 is still unverified.
Apple's on-device model must be available for the language you select.
Read [the speech privacy disclosure](PRIVACY.md) before granting access.
An unnotarized beta can require [manual per-app approval in macOS](BETA-INSTALL.md).

GitHub issues are public.
Share your macOS version, M-series chip, and intended speech language.
Do not include serial numbers, email addresses, recordings, personal dictations, or screenshots of private work.
Use [SECURITY.md](../SECURITY.md) for vulnerabilities.

## A first session

Use a blank TextEdit document and synthetic text.
Keep auto-send off. History and the latest-transcript file can stay off too.

1. Record the app version or source commit, macOS version, and selected language.
2. Note whether installation and setup make sense without help. Record repeated permission prompts or unclear messages.
3. Speak a short sentence, such as: "This is a test note. Please keep the meeting at ten tomorrow."
4. Stop and compare the visible transcript with what you said. Copy it manually if automatic paste is unavailable.
5. If you choose to grant Accessibility, repeat in the same blank document and check the actual pasted text.
6. Cancel a capture and check that it does not deliver text.
7. Change to another empty text field during a capture and check that Talky withholds automatic paste into the changed destination.

If anything behaves unexpectedly, stop and report what happened.
Keep available text before restarting or replacing the app.
A successful short session does not establish long-capture reliability or recognition accuracy.

## Share the result

Use the [early testing form](https://github.com/Venkat-RJ/lokaah-talky/issues/new?template=early_testing.yml) for an overall session report, or the [bug report form](https://github.com/Venkat-RJ/lokaah-talky/issues/new?template=bug_report.yml) for a reproducible problem.
Include:

- Version or commit, macOS version, chip family, and speech language.
- What you tried and whether it succeeded, failed, or was not tested.
- Destination app, permission choices, and broad microphone type when relevant.
- Expected behavior, actual behavior, and synthetic reproduction steps.

Leave unfinished checks marked as not tested.
A useful report can describe a failure or confusing interaction.

## Further testing

Long captures, permission denial and recovery, unavailable models, storage retention, and delivery across apps need separate sessions.
Network-isolated recognition and runtime traffic observations are also pending.
Follow [TESTING.md](../TESTING.md) and the [release checklist](../PRODUCT.md#release-readiness) for those checks.
A test report is evidence for its specific environment, not certification of every supported Mac.
