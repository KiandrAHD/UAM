# UAM Development Guide

**Phase:** 1
**Applies to:** the monorepo at `UAM/`

## 1. Repository layout

| Path | Purpose |
|---|---|
| `app/flutter/` | Flutter application, design system, bridge, tests |
| `crates/` | Rust workspace (`uam_domain`, `uam_dsp`, `uam_preset`, `uam_ffi`) |
| `database/` | Preset schema, fixtures, migration notes |
| `presets/` | Example presets and schema pointers |
| `scripts/` | Setup, build, test automation |
| `tools/audio_diagnostics/` | Read-only Windows MMDevice probe |
| `docs/` | PRD, architecture, ADRs, platform and testing docs |

See `docs/Structure_File.md` for the actual Phase 1 tree. Future feature folders
are created when their phase begins.

## 2. Toolchain versions (Phase 1)

| Tool | Version used |
|---|---|
| Flutter | `3.44.6` stable |
| Dart (bundled) | `3.12.2` |
| Rust | `1.99.1` |
| Cargo edition | `2021` |
| Rust MSRV declared | `1.85` |
| Python (preset validation) | `3.11` + `jsonschema 4.26` |

> Use the Dart bundled with Flutter. A separate PATH Dart (`3.10.2` on the
> Phase 0 host) conflicts with the Flutter SDK version floor and produces
> analyzer/test mismatches.

## 3. First-time setup

```powershell
# From the repository root
flutter --version
rustc --version
cargo --version
python --version

# Check the environment and Rust toolchains
powershell -ExecutionPolicy Bypass -File scripts/setup/check_environment.ps1

# Flutter dependencies
Set-Location app/flutter
flutter pub get
Set-Location ../..
```

## 4. Building the Rust core

### Standard (host with MSVC C++ workload)

```powershell
Set-Location crates
cargo build -p uam_ffi
Set-Location ..
```

### Phase 0 host (no MSVC linker)

The host has the GNU target and `rust-lld` but no `link.exe`. Use the provided
script, which sets the required environment:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1
# Release:
powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1 -Profile release
```

Equivalent manual environment:

```powershell
$env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
$env:RUSTFLAGS = '-C linker=rust-lld -C link-self-contained=yes'
Set-Location crates
cargo build -p uam_ffi
```

The script copies `uam_ffi.dll` to
`app/flutter/windows/runner/native/uam_ffi.dll` (gitignored). The Dart locator
also searches `crates/target/{debug,release}` for development.

## 5. Running the app

```powershell
Set-Location app/flutter
flutter run -d windows
```

> The Windows desktop build requires the Visual Studio **Desktop development
> with C++** workload. On the Phase 0 host it is missing, so `flutter run -d
> windows` / `flutter build windows` will fail at the CMake/link stage. See
> `docs/platform/WINDOWS.md` for the exact missing components.

If the native library is elsewhere, point the app at it:

```powershell
$env:UAM_FFI_LIBRARY_PATH = 'D:\path\to\uam_ffi.dll'
```

## 6. Formatting, linting, tests

### Rust

```powershell
Set-Location crates
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
Set-Location ..
```

On the Phase 0 host, prepend the GNU/rust-lld environment from §4.

### Flutter

```powershell
Set-Location app/flutter
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
Set-Location ../..
```

The live bridge test (`test/integration/rust_bridge_test.dart`) loads the
compiled DLL if present; build the Rust library first to exercise it. Phase 1
also tests the responsive shell at compact/mobile/tablet/desktop widths and
covers module navigation, capability-safe controls, preset import validation,
and appearance preferences.

### Preset fixtures

```powershell
python scripts/test/validate_presets.py
```

Expected: `Valid fixtures: 3`, `Invalid fixtures: 8`, `PASSED`.

### Windows audio diagnostics

```powershell
Set-Location tools/audio_diagnostics
cargo run
```

On the Phase 0 host, set the GNU/rust-lld environment first. Output contains
machine-specific device names; do not commit it.

## 7. Bridge contract

The C ABI is intentionally tiny and versioned:

| Function | Contract |
|---|---|
| `uam_abi_version() -> u32` | `1` for Phase 0 |
| `uam_get_engine_info() -> *mut c_char` | Owned UTF-8 JSON; caller frees |
| `uam_string_free(*mut c_char)` | Frees a pointer from the function above |

Rules:

- Returned strings are owned by the caller and must be freed exactly once with
  `uam_string_free`.
- A `NULL` return is an internal failure, not a valid payload.
- Dart validates every JSON field and rejects an ABI mismatch.
- Never expose per-sample audio through this boundary.

When changing the ABI:

1. Increment `uam_domain::BRIDGE_ABI_VERSION`.
2. Update `AppConstants.expectedBridgeAbiVersion`.
3. Update this table and `docs/adr/ADR-003-flutter-rust-interop.md`.
4. Add a bridge test.

`flutter_rust_bridge` codegen is deferred; see `scripts/codegen/README.md`.

- Phase 1 uses `ChangeNotifier` plus `InheritedNotifier` (`UamAppController` and
  `UamAppScope`) and adds no state-management dependency.
- `UamShell` uses named routes and the required desktop/tablet/mobile breakpoints.
- Preset imports are validated locally by a Dart mirror of schema v1 because no
  preset-validation FFI symbol exists in the current ABI. The UI does not claim
  Rust validation.
- No device discovery, live audio backend, Bluetooth scanner, SQLite persistence,
  or cloud/auth service is included in Phase 1.

## 8. Adding a Rust crate

1. Add it under `crates/` and to `crates/Cargo.toml` `members`.
2. Keep dependency direction from `docs/Structure_File.md` §3.
3. `#![forbid(unsafe_code)]` unless it is a platform/FFI crate.
4. Add tests and run the full workspace checks.

## 9. Adding a platform adapter

1. Define the capability in the normalized model first (ADR-005).
2. Keep OS code out of `uam_domain`, `uam_dsp`, and `uam_preset`.
3. Isolate the adapter behind a trait; test with a fake.
4. Document the real observed behavior in `docs/platform/<OS>.md` and update
   `docs/COMPATIBILITY.md`.
5. Mark status honestly (`VERIFIED` only when executed).

## 10. What not to commit

- Build outputs (`**/target/`, `app/flutter/build/`).
- The copied native library (`app/flutter/windows/runner/native/`).
- Machine-specific diagnostics (`docs/platform/windows-endpoint-inventory.txt`).
- SQLite databases, logs, `.env` files, signing keys, or certificates.

`Cargo.lock` and `pubspec.lock` **are** committed for reproducibility.

## 11. Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `link.exe not found` | MSVC workload missing | Use the GNU/rust-lld environment or install the C++ workload |
| `flutter build windows` fails at CMake | VS C++ / Windows SDK missing | Install "Desktop development with C++" |
| `Dart SDK version` mismatch | PATH Dart differs from Flutter Dart | Use `flutter`-provided Dart |
| Bridge library not found | FFI library not built/copied | Run `scripts/build/build_rust.ps1` |
| ABI mismatch error | Rust and Dart versions diverged | Rebuild the DLL and update the ABI constant consistently |

## 12. Branch and commit policy

- Phase 0 work is on `feat/phase-0-technical-validation`.
- Phase 1 work is on `feat/phase-1-foundation-ux`.
- Do not force-push or rewrite shared history.
- Keep commits scoped; do not commit artifacts or secrets.
- Do not merge or push without explicit approval.