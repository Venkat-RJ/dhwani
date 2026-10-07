# Contributing

Talky is an MIT-licensed source preview.
Useful contributions include permission recovery, safe text delivery, local language support, accessibility, and long-capture testing.
Read [PRODUCT.md](PRODUCT.md) for the scope and remaining checks before proposing a larger feature.

## Choose a focused task

- Test a short dictation session and report exact results through [early testing](docs/EARLY-TESTING.md).
- Reproduce one permission, focus, or delivery problem with synthetic text and a minimal sequence of steps.
- Check keyboard navigation and VoiceOver labels on setup, history, and settings.
- Test an available local language and record the locale, microphone type, and recognition errors without sharing private speech.
- Improve a build or setup instruction after trying it on your own Mac.

Check existing issues first and describe the task you intend to take on.
For changes to capture, storage, signing, or delivery, discuss the approach before a larger patch.

## Find the relevant code

| Area | Starting point |
| --- | --- |
| Floating panel, views, recognition, delivery, and storage | `Lokaah Talky/LokaahTalkyApp.swift`; see the architecture map in [BUILD.md](BUILD.md#architecture) |
| Deterministic recognition and product checks | `test/RecognitionLifecycleTests.swift` and `test/ProductCoreTests.swift` |
| Build, installation, and command tests | Root shell scripts and `test/test-scripts.py` |
| Candidate packaging and acceptance | `scripts/` and the release tests in `test/` |
| Recognition benchmark inputs and evaluator | `test/benchmarks/` |
| Historical marketing video | `video/`; not a current runtime demonstration |

The app currently uses one Swift source file.
A future split should preserve behavior and update both Xcode and standalone builds, along with the tests that extract source sections.

## Development workflow

1. Fork or clone [the repository](https://github.com/Venkat-RJ/lokaah-talky).
2. Read [AGENTS.md](AGENTS.md), [BUILD.md](BUILD.md), and [TESTING.md](TESTING.md).
3. Make a focused change and show what happens before and after it.
4. Build an unsigned app and run the checks relevant to your change.
5. Open a pull request explaining what changed, how you checked it, and what remains unverified.

Use Apple Silicon and target macOS 14.
Build with Xcode 26 or newer, or use the supported standalone Command Line Tools route in [BUILD.md](BUILD.md).

Test logic changes without microphone or Accessibility permission where possible.
For live app checks, record the OS, locale, destination app, steps, and outcome.
Say which runtime checks you could not complete.

## Protect user data

Use synthetic sentences and redact private details from diagnostics.
Keep real dictations, screenshots of private apps, private keys, and keychain or permissions data out of issues and patches.
Report vulnerabilities privately through [SECURITY.md](SECURITY.md).

Check that your patch contains no `build/`, `DerivedData/`, or `video/node_modules/` files.

The installer replaces and launches the local app.
The live loopback test changes audio routing.
Read their documentation before running them, and pass `--allow-system-changes` only when you intend to run the loopback test.

## License and conduct

Contribute project source under the [MIT license](LICENSE).
Submit only code and assets you have permission to contribute.
Keep attribution and required third-party notices. Dependencies retain their own licenses.
Follow the [code of conduct](CODE_OF_CONDUCT.md).

Use short paragraphs, clear new lines, and plain language.
Avoid em dashes and unsupported performance claims.
