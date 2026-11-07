# Phase 0 Report — Discovery and Technical Validation

**Product:** Universe Audio Management (UAM)
**Phase:** 0
**Date:** 2026-11-07
**Branch:** `feat/phase-0-technical-validation`
**Status:** Complete with documented blockers. No commit or push was performed.

---

## 1. Executive summary

Phase 0 built and validated a real technical foundation instead of a mock-up:

- A Rust workspace with a working DSP core (RBJ biquads + preamp), a strict
  portable preset format, and a narrow C ABI.
- A Flutter application shell that calls the compiled Rust library through
  `dart:ffi` and displays structured engine information.
- A validated `.uam-preset.json` schema with 3 valid and 8 invalid fixtures,
  checked by both JSON Schema and Rust semantic validation.
- A real Windows audio device enumeration probe using the MMDevice (WASAPI)
  API: 4 active render endpoints and 2 active capture endpoints observed.
- ADRs, a five-platform compatibility matrix, platform notes, a dependency and
  license audit, testing documentation, and CI workflows.

The project does **not** yet process audio. Phase 0 reports
`audio_processing_scope = "configuration_only"` and never claims system-wide
processing or vendor hardware control.

## 2. Scope and objectives

Planned Phase 0 work:

1. Audit the existing documentation and environment.
2. Normalize `.docs/` to `docs/` without losing content.
3. Create the repository foundation.
4. Demonstrate Flutter↔Rust interoperability.
5. Prototype a real, tested Rust DSP.
6. Define and validate the portable preset format.
7. Research five-platform audio/Bluetooth compatibility.
8. Investigate Windows audio integration.
9. Record architecture decisions.
10. Audit dependencies and licenses.
11. Establish testing and CI.
12. Report honestly on what works and what does not.

## 3. Repository and documentation structure

- `.docs/` was migrated to `docs/` with `git mv`, preserving the user's
  modification to `docs/Structure_File.md` (tree root changed to `UAM/`).
- The Phase 0 subset of the intended tree now exists: `app/flutter/`,
  `crates/`, `database/`, `presets/`, `scripts/`, `tools/`, `docs/`,
  `.github/workflows/`.
- Root files created: `README.md`, `CONTRIBUTING.md`, `SECURITY.md`,
  `.gitignore`, `.editorconfig`, `.gitattributes`.
- `LICENSE` (MIT) was preserved unchanged.
- `docs/` now includes `COMPATIBILITY.md`, `DEVELOPMENT.md`,
  `DEPENDENCY_AUDIT.md`, `PHASE_0_REPORT.md`, `adr/`, `platform/`, and
  `testing/`.

Deviation recorded: ADR-003/ADR-004 titles follow the Phase 0 task
(interop and local-first data), not the older Structure_File names. The mapping
is documented in `docs/adr/README.md`.

## 4. Environment audit

| Tool | Result |
|---|---|
| Flutter | `3.44.6` stable |
| Bundled Dart | `3.12.2` |
| Standalone PATH Dart | `3.10.2` (mismatch warning; not used) |
| rustc / cargo | `1.99.1` |
| Rust toolchains | GNU and MSVC installed |
| Git | `2.52.0` |
| Visual Studio Community 2022 | Installed without the C++ workload |
| Android SDK | `36`, missing `cmdline-tools`, licenses not accepted |
| Python / `jsonschema` | `3.11` / `4.26` |
| Node | `22.23.2` |
| CMake / Ninja | `4.4.4` / `1.13.2` |

Environment check script: `scripts/setup/check_environment.ps1`.

## 5. Architecture decisions

Six ADRs are recorded in `docs/adr/`:

| ADR | Decision | Status |
|---|---|---|
| ADR-001 | Flutter for the shared UI | Accepted |
| ADR-002 | Rust for the DSP and domain core | Accepted |
| ADR-003 | Narrow C ABI + Dart FFI (flutter_rust_bridge deferred) | Accepted (Phase 0) |
| ADR-004 | Local-first data + portable preset interchange | Accepted (Phase 0) |
| ADR-005 | Capability-based hardware controls | Accepted (principle) |
| ADR-006 | Windows-first audio integration | Proposed (not verified) |

`flutter_rust_bridge` `2.14.0-beta.2` (MIT) was evaluated and deferred: beta
status plus an extra codegen toolchain, with no benefit for a three-function
control surface.

## 6. Flutter↔Rust bridge proof

Exported C ABI (`crates/uam_ffi/src/lib.rs`):

| Function | Behavior |
|---|---|
| `uam_abi_version() -> u32` | Returns `1` |
| `uam_get_engine_info() -> *mut c_char` | Returns owned UTF-8 JSON |
| `uam_string_free(*mut c_char)` | Frees the returned pointer |

Dart side:

- `app/flutter/lib/bridge/generated/uam_ffi_bindings.dart` — low-level FFI.
- `app/flutter/lib/bridge/rust_api.dart` — typed facade; validates every field
  and rejects an ABI mismatch.
- `app/flutter/test/integration/rust_bridge_test.dart` — live proof.

Observed live test log:

```text
[UAM][INFO] Rust core 0.1.0 loaded via bridge ABI 1
```

Safety: `unsafe` is confined to `uam_ffi`; each block has a safety comment; no
audio samples cross the boundary.

## 7. Rust DSP prototype

Implemented in `crates/uam_dsp/`:

- RBJ cookbook coefficients for peaking, low-shelf, and high-shelf filters.
- Direct Form II Transposed biquad with per-section state.
- Sample-rate-aware coefficient computation (verified at 44.1 and 48 kHz).
- Preamp gain, then an ordered biquad cascade.
- Mono/stereo interleaved `f64` processing.
- Allocation-free `process_interleaved` after construction.
- Typed errors for non-finite/out-of-range parameters, unstable coefficients,
  too many bands, and invalid block length.
- Bypass and reset; non-finite input is contained.

Verified behavior:

- Peaking gain at the centre frequency matches the configured gain within
  `0.01 dB`.
- Low/high shelves boost/cut the correct band.
- `+6 dB` measured within `0.3 dB` on a sine; `-6 dB` preamp within `0.001 dB`.
- Impulse response is finite and decays.
- NaN/Infinity input does not poison state.

Real-time note: Phase 0 does not connect to an audio backend and does not yet
implement a lock-free parameter hand-off. Both are explicitly deferred.

## 8. Preset schema and validation

- Canonical schema: `database/schema/preset.schema.json`
  (JSON Schema draft 2020-12, unknown fields rejected).
- Format: `.uam-preset.json`, `"format": "uam-preset"`, `schemaVersion: 1`.
- Device-independent by definition; `deviceIndependent` must be `true`.
- Bounds: preamp `-24..=12 dB`; band gain `-24..=24 dB`; frequency
  `10..=20000 Hz`; Q `0.1..=10`; at most 32 bands, 10 tags, 16 capabilities.
- No executable content, commands, secrets, pairing material, or vendor frames.
- Rust semantic validation is redundant with the schema by design.
- Fixtures: `database/fixtures/sample-presets/` (3 valid, 8 invalid).
- Examples: `presets/examples/`.

Command result:

```text
Valid fixtures: 3
Invalid fixtures: 8
PASSED
```

## 9. Platform compatibility research

Full matrix: `docs/COMPATIBILITY.md`. Per-platform notes:
`docs/platform/{WINDOWS,MACOS,LINUX,ANDROID,IOS}.md`.

Summary:

- **Windows:** device enumeration verified through the MMDevice API; stream
  processing not implemented; desktop build blocked by missing VS C++ workload.
- **macOS:** Core Audio / AVAudioEngine documented; Core Audio taps may allow
  non-app-owned capture on macOS 14.2+; not executed.
- **Linux:** PipeWire primary, PulseAudio compatibility secondary, BlueZ for
  Bluetooth; not executed.
- **Android:** app-owned processing and `AudioPlaybackCapture` documented;
  unrestricted system-wide output is not supported; toolchain incomplete.
- **iOS:** `AVAudioEngine` app-owned processing only; other-app and system-wide
  processing are not supported; not executed.

Status labels used: `VERIFIED`, `PROTOTYPED`, `DOCUMENTED`, `UNVERIFIED`,
`BLOCKED`, `NOT SUPPORTED`.

## 10. Windows audio investigation

Two independent probes:

1. **OS inventory** (`scripts/test/windows_endpoint_inventory.ps1`):
   22 render entries (4 `Status OK`), 7 capture entries. Coarse, not WASAPI.
   Output is machine-specific and gitignored.
2. **Rust MMDevice probe** (`tools/audio_diagnostics/`): real WASAPI-family
   enumeration.

Observed probe result (names redacted here):

```text
== Render endpoints (ACTIVE): 4 endpoint(s) ==
== Capture endpoints (ACTIVE): 2 endpoint(s) ==
phase0_wasapi_probe_ok render_active=4 capture_active=2
```

Exit code `0`.

Interpretation:

- Rust can initialize COM, create `IMMDeviceEnumerator`, enumerate endpoints,
  read state, and read `PKEY_Device_FriendlyName`.
- No stream was opened; no audio was captured or rendered.
- The proposed first integration is selected-stream loopback (ADR-006), not a
  virtual device or APO. System-wide processing remains unproven and
  unaccepted.

## 11. Dependency and license audit

Full inventory: `docs/DEPENDENCY_AUDIT.md`.

- Rust direct dependencies: `serde` and `serde_json` only
  (`uam_domain`/`uam_dsp` have none).
- All transitive Rust crates are permissive (MIT / Apache-2.0 / Unlicense /
  Unicode-3.0).
- Windows diagnostics use `windows 0.62.2` (MIT OR Apache-2.0).
- Flutter third-party runtime dependency: `ffi 2.2.0` (BSD-3-Clause); dev-only
  `flutter_lints`.
- `flutter_rust_bridge` was evaluated (MIT) but is not a dependency.
- No copyleft is linked into shipped code. The project can remain MIT.
- Gap: `cargo audit` / `cargo deny` are not installed or run yet.

## 12. Testing and CI

Documentation: `docs/testing/TEST_STRATEGY.md`,
`docs/testing/AUDIO_TESTING.md`, `docs/testing/HARDWARE_MATRIX.md`.

Phase 0 results:

| Check | Result |
|---|---|
| `cargo test --workspace` | 41 tests pass |
| `cargo clippy --workspace --all-targets -- -D warnings` | clean |
| `cargo fmt --check` | clean |
| `flutter analyze` | `No issues found!` |
| `flutter test` | 10 tests pass |
| `dart format --set-exit-if-changed` | clean |
| `python scripts/test/validate_presets.py` | `PASSED` |
| Windows MMDevice probe | 4 render + 2 capture, exit `0` |

Test counts: domain 4, dsp 17, ffi 7, preset 13.

CI workflows:

- `.github/workflows/rust-ci.yml` — fmt, clippy (`-D warnings`), tests in
  `crates/`.
- `.github/workflows/flutter-ci.yml` — builds `uam_ffi` on Linux first, then
  format, analyze, and test in `app/flutter/` with the `.so` path exported.

## 13. Blockers and risks

### Blockers

1. **Flutter Windows desktop build** — Visual Studio Community 2022 lacks:
   - MSVC v142 VS 2019 C++ x64/x86 build tools
   - C++ CMake tools for Windows
   - Windows 10 SDK

   Fix: install the **Desktop development with C++** workload, then
   `flutter build windows`.
2. **MSVC Rust linking** — `link.exe` not found without the C++ workload.
   Workaround for local validation:
   `RUSTUP_TOOLCHAIN=stable-x86_64-pc-windows-gnu` and
   `RUSTFLAGS=-C linker=rust-lld -C link-self-contained=yes`.
3. **Android toolchain** — `cmdline-tools` missing, licenses not accepted; no
   mobile build attempted.
4. **macOS/Linux/iOS execution** — no host available; research is
   documentation-only.

### Risks

- Windows system-wide processing may require a signed virtual audio device or
  an APO; effort and install complexity are high.
- Mobile platforms restrict other-app and system-wide audio; product claims must
  stay narrow.
- Per-process loopback has Windows-version constraints.
- Cross-platform DSP/preset behavior is inferred, not executed off-Windows.
- The narrow C ABI requires hand-written Rust and Dart changes for every new
  capability; this will need review as the surface grows.
- No vulnerability scan or fuzzing yet.

## 14. Acceptance checklist and next steps

### Acceptance checklist

| Item | Status |
|---|---|
| `.docs/` migrated to `docs/` without content loss | Done |
| `docs/Structure_File.md` modification preserved | Done |
| Repository foundation created | Done |
| Flutter UI shell | Done (not built as a desktop binary) |
| Rust workspace (domain, dsp, preset, ffi) | Done |
| Real Flutter↔Rust call demonstrated | Done |
| Real DSP (no fake processing) | Done |
| Sample-rate-aware biquads | Done |
| DSP deterministic tests | Done |
| Preset schema + valid/invalid fixtures | Done |
| Dual validation (schema + Rust) | Done |
| Five-platform compatibility report | Done |
| Platform docs (5) | Done |
| ADR-001…006 | Done |
| Dependency/license audit | Done |
| Testing docs | Done |
| Rust CI | Done |
| Flutter CI | Done |
| Phase 0 report | This document |
| No artifacts/secrets committed | Verified (pre-commit) |
| `LICENSE` preserved | Done |
| No commit/push/merge/history rewrite | Done |
| Desktop app binary built | Blocked (VS C++ missing) |
| Live system audio processing | Not claimed; deferred |
| Cross-platform execution | Blocked (no hosts) |

### Exact next steps

1. Install the Visual Studio **Desktop development with C++** workload
   (including Windows 10/11 SDK and CMake tools), then run:
   ```powershell
   Set-Location app/flutter
   flutter build windows
   ```
2. Add a WASAPI shared-mode render stream that plays a deterministic test tone.
3. Add loopback capture and measure the transfer function against
   `Equalizer::frequency_response_db`.
4. Implement `IMMNotificationClient` handling for default-device and removal
   events.
5. Add `cargo audit` (or `cargo deny check`) to `rust-ci.yml`.
6. Add property/fuzz tests for the preset parser.
7. Configure the Android SDK (`cmdline-tools`, licenses) and attempt a mobile
   bridge build.
8. Obtain macOS/Linux hosts to execute the documented platform paths.
9. Keep Phase 0 commits scoped; do not push or merge without approval.

### Reproduce the Phase 0 checks

```powershell
# Rust (Phase 0 host)
$env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
$env:RUSTFLAGS = '-C linker=rust-lld -C link-self-contained=yes'
Set-Location crates
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
Set-Location ..

# Flutter
Set-Location app/flutter
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
Set-Location ../..

# Presets
python scripts/test/validate_presets.py

# Windows endpoint probe
Set-Location tools/audio_diagnostics
cargo run
Set-Location ../..
```