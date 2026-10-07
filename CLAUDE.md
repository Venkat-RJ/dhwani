# Lokaah Talky

Read **@AGENTS.md** for project instructions, then `BUILD.md`, `TESTING.md`, and `PRODUCT.md`.

The app source is `Lokaah Talky/LokaahTalkyApp.swift`.
Use Xcode 26 or newer; the deployment target is macOS 14 on Apple Silicon.
Preserve local-only recognition, destination checks, cancellation, private storage, and isolated test captures.

Use unsigned builds and deterministic test suites for routine verification.
Signing setup, reinstallation, and live loopback tests affect the user's machine.
Do not run them simply to inspect the project.
Never use em dashes or make unverified accuracy or release claims.
