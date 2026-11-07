# UAM

Universe Audio Management (UAM) is a local-first, universal-first audio management application built around a Flutter UI, a shared Rust core, and capability-gated native platform adapters.

Phase 1 establishes the responsive UI foundation on top of Phase 0 technical evidence. The repository contains:

- A Flutter application at [`app/flutter/`](app/flutter/) with a reusable design system, responsive shell, and seven configuration modules.
- A Rust workspace at [`crates/`](crates/) with domain validation, real biquad DSP, preset validation, and a narrow C ABI.
- Versioned `.uam-preset.json` schema and fixtures at [`database/`](database/).
- Compatibility, platform, ADR, testing, and phase reports under [`docs/`](docs/).

The Flutter application reports structured metadata from the compiled Rust core. It explicitly reports `configuration_only`; it does not claim system-wide equalization, live device discovery, or hardware control. Device and hardware UI stays unavailable until a verified platform adapter reports capability evidence.

## Requirements

- Flutter stable and Dart compatible with `app/flutter/pubspec.yaml`.
- Rust stable with Cargo.
- Windows development requires the Flutter Windows C++ workload; Phase 0 validation used Rust's GNU target with `rust-lld` because the host's MSVC linker components were incomplete.
- For mobile targets, install the relevant Android or Apple toolchains. Phase 1 does not build or verify mobile targets.

Verified environment and setup commands are in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Quick validation

From the repository root on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1
cd app/flutter
flutter pub get
flutter analyze
flutter test
```

Rust checks use the stable GNU toolchain and self-contained LLVM linker on this validation host:

```powershell
$env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
$env:RUSTFLAGS = '-C linker=rust-lld -C link-self-contained=yes'
cd crates
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

The generated native library is copied to `app/flutter/windows/runner/native/uam_ffi.dll` for local development. This is a build artifact and is ignored by Git.

## Scope policy

UAM reports a feature only after the relevant operating-system API and hardware adapter have been tested. Bluetooth pairing does not prove ANC, transparency, battery, touch, or firmware control. iOS is limited to supported app-owned audio paths; Android effects are session/device dependent; desktop system-wide processing requires an explicit backend architecture.

## Documentation

- [Documentation index](docs/README.md)
- [Phase 0 report](docs/PHASE_0_REPORT.md)
- [Phase 1 report](docs/PHASE_1_REPORT.md)
- [Compatibility matrix](docs/COMPATIBILITY.md)
- [Development setup](docs/DEVELOPMENT.md)
- [Architecture](docs/Architecture.md)
- [Repository structure](docs/Structure_File.md)
- [Security policy](SECURITY.md)
- [Contribution guide](CONTRIBUTING.md)

## License

UAM is distributed under the [MIT License](LICENSE).
