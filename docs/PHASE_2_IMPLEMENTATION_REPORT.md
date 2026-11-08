# Phase 2 Implementation Report — DSP Configuration Foundation (2.1–2.2)

**Date:** 2026-11-08  
**Branch:** `feat/phase-2-dsp-foundation` (created from `main`, `22040fe`)  
**Status:** Phase 2.1–2.2 implemented and tested; Phase 2.3A–2.3D + 2.6 completed in `docs/PHASE_2_3_IMPLEMENTATION_REPORT.md`  

This report covers **Phase 2.1 (Audio Format Model)** and **Phase 2.2 (DSP
Configuration Engine)** only. It does not claim the limiter, FFI symbols, Flutter
DSP controller, benchmark suite, or audio backend, which are later milestones.

> **Follow-up:** Phase 2.3A–2.3D (preset adapter, peak metering, limiter,
> pipeline, numerical safety) and Phase 2.6 (benchmarking) are now implemented
> and tested. See `docs/PHASE_2_3_IMPLEMENTATION_REPORT.md` and
> `docs/PHASE_2_3_DESIGN.md`. The remaining blockers below are updated
> accordingly; the real-time hand-off and audio backend are still open.

## Executive summary

| Deliverable | Status |
|---|---|
| Audio format model (`SampleFormat`, boundary vs internal representation) | **Implemented + tested** |
| Existing `AudioConfig` callers remain compatible | **Verified** (`AudioConfig::new` unchanged) |
| `DspConfig` + `LimiterConfig` validated DTO | **Implemented + tested** |
| All parameter validation tested | **Implemented + tested** (each documented range has valid-boundary and rejected cases) |
| Equalizer control-thread configuration (`from_config`, `apply_config`) | **Implemented + tested** |
| Failed update preserves the existing chain | **Implemented + tested** |
| Real-time threading design documented | **Documented** (ADR-007); implementation deferred |
| Existing Rust tests still pass | **Verified** (63 total, was 41) |
| New tests pass | **Verified** (18 new integration + 5 new unit) |
| Flutter regression suite passes | **Verified** (68 tests) |
| Preset fixtures still validate | **Verified** (3 valid / 8 invalid) |
| Windows debug build still succeeds | **Verified** (local MSVC) |
| Reports and roadmap updated | **Done** |

## 1. What changed

### 1.1 `uam_domain` — audio boundary format model

`crates/uam_domain/src/audio_config.rs` gains an explicit **boundary** sample
format and separates it from the **internal** DSP representation.

- `SampleFormat` — `F32`, `F64`. Documents the format a future backend delivers
  or expects. Carries `as_str()`, `bytes_per_sample()` (`4`/`8`), and
  `is_internal_processing_format()`.
- `INTERNAL_PROCESSING_FORMAT` — the constant `SampleFormat::F64`. The kernel is
  `f64` only.
- `AudioConfig` gains a `boundary_format` field. `AudioConfig::new` is
  **unchanged** and defaults to `F64`; `AudioConfig::with_format` records an
  explicit boundary format. `boundary_format()` and
  `internal_processing_format()` expose both concepts.
- `ChannelLayout` (mono/stereo), sample-rate bounds, channel validation,
  Nyquist, and the 5 %-guard usable-frequency bound are unchanged.

**No native `f32` processing path exists or is claimed.** `f32` is metadata for a
future adapter that converts at the boundary; the DSP crate still stores,
processes, and returns `f64` only.

### 1.2 `uam_dsp` — DSP configuration DTO

New module `crates/uam_dsp/src/config.rs`:

- `DspConfig` — the single validated description of an equalizer chain:
  `audio` (`AudioConfig`), `preamp_db`, `bands` (`Vec<BandConfig>`), `bypassed`,
  and an optional `limiter` (`LimiterConfig`). Built with `DspConfig::new(...)`,
  adjusted with `with_bypassed()` / `with_limiter()`, validated with
  `validate()`.
- `LimiterConfig` — validated **metadata only**: `enabled`, `ceiling_db`
  (−12.0 … 0.0 dBFS), `release_ms` (10 … 1000 ms), defaults disabled at
  −0.3 dBFS / 100 ms. `Default` is provided. No limiter algorithm exists; see
  §1.4.
- `crates/uam_dsp/src/validation.rs` gains the limiter bounds and three new
  `DspError` variants: `LimiterCeilingOutOfRange`, `LimiterReleaseOutOfRange`,
  `ReconfigurationRequired`.

### 1.3 `uam_dsp` — control-thread Equalizer reconfiguration

`crates/uam_dsp/src/equalizer/mod.rs` gains:

- `Equalizer::from_config(&DspConfig) -> Result<Self, DspError>` — validates,
  builds, and applies bypass/limiter metadata.
- `Equalizer::apply_config(&mut self, &DspConfig) -> Result<(), DspError>` — the
  control-thread replacement API.

`process_interleaved`, `set_bypassed`, `reset`, `frequency_response_db`, and
`latency_samples` are unchanged; Phase 0 processing behaviour is intact and its
tests are untouched.

### 1.4 No fake limiter

`LimiterConfig` is carried but never applied. A test
(`limiter_metadata_does_not_change_processing`) proves that enabling the limiter
metadata produces byte-identical output to a configuration without it. The
limiter's signal-processing algorithm belongs to a later milestone.

## 2. Documented value ranges

All bounds live in `crates/uam_dsp/src/validation.rs` and are enforced by
`DspConfig::validate` (bands are validated against the configured sample rate).

| Parameter | Range / rule |
|---|---|
| sample rate | `8_000 … 384_000` Hz |
| channels | mono (1) or stereo (2) only |
| band frequency | `10.0 … 20_000.0` Hz **and** `≤ 0.95 × Nyquist(sample rate)` |
| band gain | `−24.0 … +24.0` dB |
| band Q | `0.1 … 10.0` |
| band count | `0 … 32` (`MAX_BANDS`) |
| preamp | `−24.0 … +12.0` dB |
| limiter ceiling | `−12.0 … 0.0` dBFS |
| limiter release | `10.0 … 1_000.0` ms |

All numeric parameters must be finite; `NaN` and `±inf` are rejected.

## 3. Control-thread update guarantees

`apply_config` enforces, by construction and by test:

1. **Validate before apply.** `DspConfig::validate()` runs first. A configuration
   that fails validation cannot even be constructed, so it cannot reach the
   engine.
2. **Explicit reconfiguration for rate/channel changes.** A differing sample
   rate or channel count returns `DspError::ReconfigurationRequired` rather than
   updating in place.
3. **Failure cannot corrupt the chain.** The replacement filter state is built
   entirely into locals; `self` is mutated only after preparation succeeds. A
   rejected update leaves the active chain byte-for-byte intact.
4. **Preparation off the real-time path.** `apply_config` allocates; it is a
   control-thread method and must never be called from an audio callback. See
   §4.
5. **Phase 0 behaviour intact.** Bypass remains bit-exact; zero-band/zero-preamp
   remains bit-exact.

Applying a configuration resets filter memory because coefficients change.
Parameter smoothing and click-free bypass crossfades are **not** implemented in
this milestone.

## 4. Real-time thread safety

The full design record is `docs/adr/ADR-007-real-time-configuration-handoff.md`.
Summary of findings:

- The audio callback does not exist yet (the engine is `configuration_only`), so
  no hand-off is implemented. Implementing one now would be an unverifiable
  lock-free claim.
- **Selected model:** immutable prepared state transferred by a bounded SPSC
  channel (single-owner move), applied at a block boundary. Alternatives
  analysed: bounded SPSC command queue, triple-buffer ownership transfer,
  `Arc` double-buffer, per-field atomics, and seqlock.
- **Seqlock over non-atomic `f64` fields is rejected** as a data race in the
  Rust memory model, and cannot be expressed in a crate that is
  `#![forbid(unsafe_code)]`.
- `Mutex`/`RwLock` around configuration is rejected (can block the audio thread).
- The DSP and domain crates remain `#![forbid(unsafe_code)]`; any synchronization
  primitive belongs in the future backend crate.

## 5. Test results (actual output)

### Rust (documented GNU + rust-lld environment)

```powershell
$ $env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
$ $env:RUSTFLAGS = '-C linker=rust-lld -C link-self-contained=yes'
$ cargo fmt --all -- --check                              # EXIT=0
$ cargo clippy --workspace --all-targets -- -D warnings   # EXIT=0
$ cargo test --workspace                                  # EXIT=0
```

Test totals:

| Suite | Tests |
|---|---|
| `uam_domain` unit (5 new) | 9 |
| `uam_dsp` unit | 7 |
| `uam_dsp` `config_tests` (new) | 18 |
| `uam_dsp` `dsp_tests` | 10 |
| `uam_ffi` unit | 7 |
| `uam_preset` unit | 2 |
| `uam_preset` `preset_tests` | 11 |
| **Total** | **64** (was 41) |

New tests added:

- `uam_domain`: `new_defaults_to_f64_boundary_format`,
  `explicit_boundary_format_is_recorded`,
  `internal_processing_format_is_always_f64`, `sample_format_metadata_is_stable`,
  `with_format_still_validates_rate_and_channels`.
- `uam_dsp` `config_tests.rs` (18): valid audio configurations; invalid sample
  rates; invalid channels; sample-format compatibility; invalid preamp; invalid
  EQ band configuration; maximum band count; sample-rate-aware band validation;
  limiter parameter validation; limiter-metadata no-op; `from_config` vs `new`
  equivalence; `apply_config` replacement; failed replacement preserves state;
  invalid DTO rejected before the engine; mono and stereo processing; bypass
  bit-exactness through `from_config`; DTO field round-trip.

### Flutter (Windows host)

```powershell
$ dart format --output=none --set-exit-if-changed lib test   # EXIT=0; 0 changed
$ flutter analyze                                          # EXIT=0; No issues found
$ flutter test                                             # EXIT=0; 68 tests passed
```

No Dart source changed in this milestone.

### Preset fixtures

```powershell
$ python scripts/test/validate_presets.py
  VALID: balanced-warm.uam-preset.json
  VALID: neutral-reference.uam-preset.json
  VALID: shelf-bass-boost.uam-preset.json
  REJECTED: 8 invalid fixtures (all as expected)
  # EXIT=0; PASSED
```

## 6. Windows build result

Local Windows verification (not CI, not a release build):

```powershell
$ powershell -File scripts/build/build_rust.ps1
  # Built Rust FFI library: crates\target\debug\uam_ffi.dll
  # Copied Flutter runtime library: app\flutter\windows\runner\native\uam_ffi.dll

$ flutter build windows --debug        # EXIT=0
  # √ Built build\windows\x64\runner\Debug\uam.exe
```

Verified artifact paths (Git-ignored, not committed):

```
crates/target/debug/uam_ffi.dll
app/flutter/windows/runner/native/uam_ffi.dll
app/flutter/build/windows/x64/runner/Debug/uam.exe
```

- Rust is built with the documented GNU + rust-lld toolchain; the Flutter Windows
  build uses MSVC (Visual Studio Community 2022 17.14.11, Windows SDK
  10.0.26100.0).
- GitHub Actions CI runs on Ubuntu and does not build the Windows binary.
- **No release build, installer, or signed package was produced.**

## 7. Remaining blockers

Updated after Phase 2.3A–2.3D + 2.6 (see `docs/PHASE_2_3_IMPLEMENTATION_REPORT.md`):

| Item | Status |
|---|---|
| Parameter updates do not block the audio callback | **Unmet** — no callback exists; design recorded in ADR-007 |
| Performance acceptable on the reference machine | **Met** — Criterion suite; EQ + limiter 1.223 % of one core (`docs/testing/BENCHMARKS.md`) |
| Limiter signal processing | **Implemented + tested** (`uam_dsp::Limiter`) |
| Preset → DSP adapter (`Preset::to_dsp_config`) | **Implemented + tested** (`uam_preset::adapter`) |
| Peak metering + clipping detection | **Implemented + tested** (`uam_dsp::PeakMeter`) |
| Processing pipeline | **Implemented + tested** (`uam_dsp::DspPipeline`) |
| Denormal + allocation-safety tests | **Implemented + tested** (`safety_tests.rs`, `allocation_tests.rs`) |
| Concurrent-update (lock-free) test | Not implemented (needs prepared-state hand-off) |
| DSP FFI symbols / Flutter DSP controller | Not implemented (additive ABI work, deferred) |
| Audio backend seam (Windows WASAPI) | Not implemented (Phase 4) |

## 8. Phase 2.3 implementation proposal

Proposed next milestone, in dependency order. Items 1, 4, and 5 are now
**completed** (see `docs/PHASE_2_3_IMPLEMENTATION_REPORT.md`); items 2, 3
(concurrent-update test), and 6 remain open.

1. **`Preset::to_dsp_config`** in `uam_preset` — one validation path from a
   portable preset to a `DspConfig`, reusing `FilterType → FilterKind`.
   **Done** (`uam_preset::adapter`).
2. **Prepared-state hand-off** per ADR-007 — a `PreparedState` type in the DSP
   crate plus a bounded single-owner transfer owned by a future `uam_audio`
   crate; no `unsafe` in the DSP crate.
3. **Real-time safety tests** — allocation-count test (custom `GlobalAlloc`),
   concurrent `apply_config` + processing test, denormal input test
   (`f64::MIN_POSITIVE / 4`), long-run drift test. **Mostly done** — allocation,
   denormal, and long-run tests are implemented; the concurrent-update test
   remains open pending a hand-off implementation.
4. **Simplified dynamics** — peak/clipping detection and the limiter algorithm
   (feed-forward gain reduction at the configured ceiling) with tests; then
   enable `LimiterConfig` in the processing path. **Done** (`Limiter`,
   `PeakMeter`, `DspPipeline`).
5. **Benchmark suite** — `criterion` CPU cost (`ns/frame` at 48 kHz stereo,
   0/1/5/10/32 bands, 128…4096-frame blocks) and latency; record a committed
   baseline in `docs/testing/BENCHMARKS.md`. **Done.**
6. **Additive FFI + Flutter controller** — only after the above, and only with a
   documented ABI policy (`uam_dsp_api_version`), mirroring the readiness plan.

Each step stays independently testable and preserves the ABI, the 64 Rust tests,
and the 68 Flutter tests. Phase 2.3 preserves them and expands the Rust suite to
127 tests; the Flutter suite remains 68 tests.

## 9. Files changed in this milestone

Added:

- `crates/uam_dsp/src/config.rs`
- `crates/uam_dsp/tests/config_tests.rs`
- `docs/adr/ADR-007-real-time-configuration-handoff.md`
- `docs/PHASE_2_IMPLEMENTATION_REPORT.md` (this file)

Modified:

- `crates/uam_domain/src/audio_config.rs` (boundary format model + tests)
- `crates/uam_domain/src/lib.rs` (re-exports)
- `crates/uam_dsp/src/validation.rs` (limiter bounds, new error variants)
- `crates/uam_dsp/src/equalizer/mod.rs` (`from_config`, `apply_config`)
- `crates/uam_dsp/src/lib.rs` (module + re-exports)
- `docs/PHASE_1_1_REPORT.md` (Phase 1.1 closure)
- `docs/PHASE_2_READINESS.md`, `docs/Roadmap.md`, `docs/Architecture.md`,
  `docs/Structure_File.md`, `docs/README.md`, `docs/adr/README.md`
