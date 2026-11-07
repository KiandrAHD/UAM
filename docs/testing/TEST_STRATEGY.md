# UAM Test Strategy

**Phase:** 0
**Goal:** prove correctness at the boundaries where defects are expensive:
DSP math, untrusted preset input, and the Flutter↔Rust contract.

## 1. Test layers

| Layer | Tooling | What it proves |
|---|---|---|
| Rust unit tests | `cargo test` | Filter math, bounds, validation helpers |
| Rust integration tests | `cargo test` | DSP chains, preset fixtures, FFI contract |
| Dart unit tests | `flutter test` | Result/failure types, scope parsing, engine info parsing |
| Dart widget tests | `flutter test` | Shell renders and shows bridge state |
| Bridge integration test | `flutter test` | Real Dart FFI call into `uam_ffi.dll` |
| Preset schema validation | Python + `jsonschema` | Fixtures match the published JSON Schema |
| Static analysis | `cargo clippy`, `flutter analyze` | Suspicious code, unused/dead paths |
| Formatting | `cargo fmt`, `dart format` | Consistent style |
| Platform probes | Rust + OS APIs | Real device enumeration (Windows) |

There is no automated audio-hardware test yet. See `AUDIO_TESTING.md`.

## 2. Commands

All commands assume the repository root.

### Rust

```powershell
Set-Location crates
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
Set-Location ..
```

On a host without the MSVC linker, set the environment described in
`docs/DEVELOPMENT.md` §4 first.

### Flutter

```powershell
Set-Location app/flutter
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
Set-Location ../..
```

Build the Rust DLL first so the live bridge test is not skipped:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1
```

### Presets

```powershell
python scripts/test/validate_presets.py
```

### Windows diagnostics

```powershell
Set-Location tools/audio_diagnostics
cargo run
Set-Location ../..
```

## 3. Phase 0 baseline

| Suite | Result |
|---|---|
| `cargo test --workspace` | 41 tests pass |
| `cargo clippy` | clean, `-D warnings` |
| `cargo fmt --check` | clean |
| `flutter analyze` | `No issues found!` |
| `flutter test` | 10 tests pass |
| `dart format` | clean |
| `validate_presets.py` | 3 valid, 8 invalid, `PASSED` |

Test counts by crate: domain 4, dsp 17 (7 unit + 10 integration), ffi 7,
preset 13 (2 unit + 11 integration).

## 4. What each suite covers

### DSP (`crates/uam_dsp`)

- Peaking gain at the centre frequency matches the configured gain within
  `0.01 dB`.
- Low shelf boosts lows and leaves highs; high shelf does the inverse.
- Sine-wave RMS gain within `0.3 dB` after the startup transient.
- Preamp scaling within `0.001 dB`.
- Impulse response is finite and decays.
- Non-finite input (`NaN`, `±Infinity`) does not poison state.
- Both `44_100` and `48_000` Hz are accepted.
- Out-of-range and non-finite parameters are rejected with typed errors.
- A band above the sample-rate guard band is rejected.
- Bypass and zero-band/zero-preamp paths are bit-exact.

### Preset (`crates/uam_preset`)

- Every valid fixture parses, exports, and round-trips unchanged.
- Every `invalid-*` fixture is rejected.
- Specific fixtures produce the expected typed error.
- Oversized input is rejected before parsing.
- Invalid UTF-8 and unknown fields are rejected.
- Non-finite values are rejected even when constructed in memory.
- Band count, metadata limits, duplicate tags, semver shape, and capability
  identifier format are enforced.
- Export refuses an invalid in-memory preset.

### FFI (`crates/uam_ffi`)

- ABI version is exported and matches `uam_domain`.
- Engine info pointer is non-null and can be freed exactly once.
- Freeing null is a no-op.
- Advertised functionality matches implemented Phase 0 features.
- The preset crate is linked into the bridge build.

### Flutter

- `Result` and failure mapping.
- Engine info JSON parsing, including rejection of malformed payloads.
- Audio processing scope parsing rejects unknown wire values.
- Widget shell renders and reflects bridge state.
- Live bridge test loads the DLL and checks product name, core version, ABI.

## 5. Determinism rules

- No wall-clock, randomness, network, or device dependence in unit tests.
- DSP tests use generated deterministic sine/impulse signals.
- Preset fixtures are static files under version control.
- The bridge test skips with a clear message when the native library is absent;
  CI builds the library first so it runs.

## 6. CI

`.github/workflows/rust-ci.yml` and `.github/workflows/flutter-ci.yml` run the
checks above on push and pull request. The Flutter job builds the Rust library
first so the live bridge test executes.

## 7. Known gaps

- [ ] No `cargo audit` / `cargo deny` step (not installed locally).
- [ ] No property/fuzz testing of the preset parser yet
      (`cargo-fuzz`/`proptest`).
- [ ] No benchmark suite or latency measurement.
- [ ] No real audio loopback/measurement test.
- [ ] No mobile or cross-platform execution.
- [ ] No coverage reporting threshold.
- [ ] No hardware capability adapter tests (none implemented).

These are Phase 1+ items; they are listed rather than silently skipped.