# Contributing to UAM

## Scope

Keep changes aligned with the universal-first, capability-based, local-first architecture. Phase boundaries matter: do not mark a platform or hardware feature as supported without an adapter test and evidence.

## Before opening a pull request

1. Read the relevant documentation and ADRs.
2. Keep generated build outputs and machine-specific paths out of Git.
3. Run Rust formatting, Clippy, and tests.
4. Run Dart formatting, Flutter analysis, and Flutter tests.
5. Update compatibility documentation when an API or platform claim changes.
6. Add tests for validation, DSP, bridge payloads, or platform adapter behavior.

## Code boundaries

- Keep DSP and domain logic independent of Flutter.
- Keep raw audio buffers out of ordinary Dart calls.
- Keep platform APIs behind adapters.
- Gate proprietary hardware controls by verified capabilities.
- Treat imported presets as untrusted input.

## Commit and review expectations

Use focused commits and descriptive pull requests. Explain verified behavior, blocked checks, platform assumptions, and remaining risks. Never include secrets, live databases, personal device inventories, logs with private paths, signing material, or Bluetooth pairing data.

## License

Contributions are accepted under the repository [MIT License](../LICENSE).
