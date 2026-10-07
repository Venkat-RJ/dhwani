# Speech recognition and privacy

Talky currently uses Apple's Speech framework and the speech models supplied by macOS.
Apple's recognition engine is proprietary.
Talky's MIT license covers the app source, not Apple's engine or models.

## What Talky requires

Before recording, Talky checks that the selected recognizer supports on-device processing and is available.
Every recognition request requires on-device processing, including renewed sessions during longer captures.
Talky has no network-recognition fallback.
Vocabulary hints are passed to the same on-device recognizer.

Apple documents that [`requiresOnDeviceRecognition`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition) prevents request audio from being sent over the network when [`supportsOnDeviceRecognition`](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition) is true.

These settings have been reviewed in source.
They rely on Apple's documented API behavior.
Runtime network activity and Apple's broader data handling have not been independently audited.
This project does not have independent evidence establishing that Apple collects zero speech data.

## Why the permission notice mentions Apple

Talky needs Microphone and Speech Recognition access.
Apple controls the system permission notice; Talky supplies a separate explanation of its purpose.
The Speech framework supports server processing as well as on-device processing.
Apple's [permission documentation](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition) describes the broader service, while Talky selects on-device processing for each request.

Read the system notice before deciding whether to grant access.
The current app uses Apple's engine; an independent local engine is not available in Talky.

## Apple's published data-use policies

Apple's [Siri, Dictation and Privacy policy](https://www.apple.com/legal/privacy/data/en/ask-siri-dictation/) says audio transcribed by third-party apps using Speech Recognition may be sent to Apple.
Its broader policy describes processing and using request data to improve Apple services.

The optional [Improve Siri and Dictation setting](https://www.apple.com/legal/privacy/data/en/improve-siri-dictation/) permits storage and review of samples, including audio and transcripts.
See [Apple's instructions](https://support.apple.com/en-ie/127070) to review that setting on a Mac.
Talky does not read or change this setting.

These policies describe Apple's services.
They do not establish which data this Talky build has actually sent.
There is no evidence here that free access to the framework is an exchange for speech data.

## Data handled by Talky

The current app source has no developer analytics or remote audio or transcript upload implementation.
Regular dictation replaces the clipboard and can paste into another app.
Other apps can read clipboard contents, and the destination app can handle pasted text under its own policies.

History and the latest-transcript file start off on a fresh installation.
Saved preferences survive upgrades.
Opt-in history, exports, and isolated test results can contain transcripts.
Local transcript files are unencrypted and use owner-only permissions.

See [the README](https://github.com/Venkat-RJ/lokaah-talky#privacy-and-local-storage) for storage, retention, export, and deletion behavior.
Network-isolated recognition and runtime traffic checks remain pending in [the release checklist](https://github.com/Venkat-RJ/lokaah-talky/blob/main/PRODUCT.md#release-readiness).
