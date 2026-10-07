# Contributing

Small, well-tested improvements are welcome.
Useful areas include permission recovery, destination safety, local language support, accessibility, and repeated long-capture testing.
Read [PRODUCT.md](PRODUCT.md) before proposing a larger feature.

## Development workflow

1. Fork or clone [the repository](https://github.com/Venkat-RJ/lokaah-talky).
2. Read `AGENTS.md`, `BUILD.md`, and `TESTING.md`.
3. Make a focused change with a concrete before-and-after example.
4. Run the unsigned build and the applicable tests.
5. Open a pull request describing the behavior, verification, and remaining limits.

Use Xcode 26 or newer on Apple Silicon.
The macOS deployment target is 14.
For logic changes, prefer deterministic tests that do not need microphone or Accessibility permission.
For live behavior, record the OS, locale, destination app, and test steps.
Explain when you could not perform a required runtime check.

## Protect user data

Do not include real dictations, screenshots of private apps, private keys, or keychain and permissions data in issues or patches.
Use synthetic sentences and redacted diagnostics.
Report security problems privately as described in [SECURITY.md](SECURITY.md).
Check that `build/`, `DerivedData/`, and `video/node_modules/` are absent from the patch.

The installer and live loopback test change the local machine.
Read their documentation and use the loopback's explicit flag only when you intend to make those changes.

## License and conduct

Contributions to the project source are made under its [MIT license](LICENSE).
Submit code and assets you have permission to contribute, and preserve required third-party notices.
Dependencies retain their own licenses.
Follow the [code of conduct](CODE_OF_CONDUCT.md).
Write for people: short paragraphs, useful new lines, no em dashes, and no unsupported performance claims.
