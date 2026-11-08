# Phase 2.3 Implementation Report — Adapter, Metering, Limiter, Pipeline, Benchmarks

**Date:** 2026-11-08
**Branch:** `feat/phase-2-3-complete-dsp` (created from `main`, `35b9f65`)
**Status:** Phase 2.3A–2.3D and Phase 2.6 implemented and tested; no audio backend
**Scope:** preset→DSP adapter (2.3A), sample-peak metering and clipping detection
(2.3B), limiter and processing pipeline (2.3C), numerical safety / regression
(2.3D), and DSP benchmarking (2.6)

This report covers Phase 2.3 and Phase 2.6 only. It does not claim a real-time
audio backend, the real-time parameter hand-off, or the FFI/Flutter DSP
controller, which remain open (Phase 2.x + Phase 4). The design record is
`docs/PHASE_2_3_DESIGN.md`; the benchmark numbers are in
`docs/testing/BENCHMARKS.md`.

## Executive summary

| Deliverable | Status |
|---|---|
| Preset→DSP adapter (`Preset::to_dsp_config`) | **Implemented + tested** |
| Sample-peak meter + clipping detection | **Implemented + tested** |
| Feed-forward limiter (ceiling, release, channel-linked) | **Implemented + tested** |
| `DspPipeline` (preamp+EQ → limiter → metering) + `PipelineReport` | **Implemented + tested** |
| Numerical safety (non-finite, subnormal, invalid params, long-run) | **Implemented + tested** |
| Steady-state allocation-freedom test | **Implemented + tested** |
| Benchmark suite (Criterion) + measured results | **Implemented + run** |
| Performance target < 2 % of one core (stereo, 10 bands, 256 frames) | **Met** on reference machine |
| Existing tests preserved (no test weakened/removed) | **Verified** (127 total, was 64) |
| `uam_dsp`/`uam_domain`/`uam_preset` free of `unsafe` | **Verified** (`#![forbid(unsafe_code)]`) |
| Real-time parameter hand-off to a live callback | **Not implemented** — no callback exists (ADR-007) |
| Audio backend (WASAPI etc.) | **Not implemented** — Phase 4 |

## 1. What changed

### 1.1 `uam_preset` — preset→DSP adapter (2.3A)

New module `crates/uam_preset/src/adapter.rs`:

- `Preset::to_dsp_config(&self, audio_config: AudioConfig) -> Result<DspConfig,
  PresetConversionError>` — the single bridge from the portable schema to a
  validated DSP configuration.
- `PresetConversionError { InvalidPreset(PresetError), Dsp(DspError) }` with
  `Display`, `Error::source`, and `From` conversions for both inner errors.

Rules enforced:

1. The preset is validated first (`Preset::validate`); a portable failure is
   `InvalidPreset` and no DSP value is produced.
2. `filter_type → FilterKind` (existing `From` impl), frequency, gain, and Q are
   copied verbatim; band order is preserved.
3. `DspConfig::new(...)` is the **final validation authority**, so the
   sample-rate-dependent frequency bound is enforced exactly once, in the DSP
   layer — the adapter defines no second set of numeric bounds.
4. The limiter and bypass are **not invented**: the schema has no such fields, so
   the resulting configuration carries no limiter and is un-bypassed.
5. `uam_preset` gained a dependency on `uam_domain` (for `AudioConfig`).

### 1.2 `uam_dsp` — metering (2.3B)

New module `crates/uam_dsp/src/meter.rs`:

- `PeakMeter` — sample-peak meter with running (peak-hold) state.
  `new`, `with_clip_threshold`, `process_interleaved(&[f64]) -> BlockPeak`,
  `reset`, and running accessors (`running_peak`, `running_overall_peak`,
  `clipped_samples`, `clipping_detected`, `non_finite_samples`,
  `processed_frames`).
- `BlockPeak` — per-channel peaks, overall peak, `overall_peak_dbfs()`,
  `clipped_samples()`, `clipping_detected()`, `non_finite_samples()`, `frames()`.
- `linear_to_dbfs(f64) -> f64` — always finite; floors at `DBFS_FLOOR = -200.0`.
- Constants `CLIP_THRESHOLD_LINEAR = 1.0` (`0 dBFS`), `DBFS_FLOOR`.

Policies (see design §2): sample peak only (never true peak); clipping at
`|x| >= threshold`; `NaN` ignored for level and counted non-finite; `±inf` counted
non-finite **and** clipped without polluting the finite peak; empty buffer valid;
partial frame rejected with `MeterError::InvalidBlockLength`; no allocation,
lock, I/O, or logging.

### 1.3 `uam_dsp` — limiter (2.3C)

New module `crates/uam_dsp/src/limiter.rs`:

- `Limiter` — feed-forward, zero-look-ahead peak limiter, channel-linked.
  Instantaneous attack, one-pole release toward the target gain.
- `new(&LimiterConfig, AudioConfig) -> Result<Self, DspError>`,
  `process_interleaved(&mut [f64]) -> Result<(), DspError>`, `set_enabled`,
  `reset`, `gain`, `gain_reduction_db`, `last_block_max_reduction_db`,
  `peak_reduction_db`, `limited_samples`, `latency_samples() == 0`.

The equalizer is **not** modified to embed the limiter: `Equalizer` stays
limiter-agnostic (its `limiter_metadata_does_not_change_processing` contract
still holds), and the limiter is composed by `DspPipeline`.

### 1.4 `uam_dsp` — processing pipeline (2.3C)

New module `crates/uam_dsp/src/pipeline.rs`:

- `DspPipeline` — owns `Equalizer` + `Limiter` + three `PeakMeter`s (input,
  pre-limiter, output).
- `from_config(&DspConfig)`, `apply_config(&DspConfig)` (control-thread,
  allocates), `process_interleaved(&mut [f64]) -> Result<PipelineReport,
  DspError>`, `reset`, and stage/meter accessors.
- `PipelineReport` — `input()`, `pre_limiter()`, `output()` (`BlockPeak`),
  `gain_reduction_db()`, `limiter_active()`, `frames()`.

Order: input meter → preamp + EQ → pre-limiter meter → limiter → output meter.
Bypass applies to the equalizer only; a disabled limiter is bit-exact
pass-through, so a limiter-less pipeline matches an equalizer-only chain.

### 1.5 Wiring and re-exports

- `crates/uam_dsp/src/lib.rs` — adds `limiter`, `meter`, `pipeline` modules and
  re-exports `Limiter`, `PeakMeter`, `BlockPeak`, `MeterError`, `linear_to_dbfs`,
  `CLIP_THRESHOLD_LINEAR`, `DBFS_FLOOR`, `DspPipeline`, `PipelineReport`.
- `crates/uam_preset/src/lib.rs` — adds `adapter` module and re-exports
  `PresetConversionError`.
- `crates/uam_dsp/src/config.rs` — limiter documentation updated from "metadata
  only" to the real processor (the `LimiterConfig` API and validation are
  unchanged; the field is now consumed by `Limiter`).

### 1.6 Benchmarks (2.6)

- `crates/uam_dsp/benches/dsp_processing.rs` — Criterion benchmark suite
  (`harness = false`).
- `crates/uam_dsp/Cargo.toml` — adds the `criterion 0.7.0` dev-dependency
  (`default-features = false`, `features = ["cargo_bench_support"]`) and the
  `[[bench]]` entry.
- `docs/testing/BENCHMARKS.md` — environment, methodology, measured matrix, and
  interpretation.

## 2. Milestone status

| Milestone | Work item | Status | Evidence |
|---|---|---|---|
| 2.3A | Preset→DSP adapter | **Implemented + tested** | `uam_preset/src/adapter.rs`; `tests/adapter_tests.rs` (13) |
| 2.3B | Peak metering + clipping detection | **Implemented + tested** | `uam_dsp/src/meter.rs`; `tests/meter_tests.rs` (15) |
| 2.3C | Limiter | **Implemented + tested** | `uam_dsp/src/limiter.rs`; `tests/limiter_tests.rs` (20) |
| 2.3C | Processing pipeline | **Implemented + tested** | `uam_dsp/src/pipeline.rs`; `tests/pipeline_tests.rs` (5) |
| 2.3D | Numerical safety / regression | **Implemented + tested** | `tests/safety_tests.rs` (9) |
| 2.3D | Steady-state allocation-freedom | **Implemented + tested** | `tests/allocation_tests.rs` (1) |
| 2.6 | Benchmark suite + results | **Implemented + run** | `benches/dsp_processing.rs`; `docs/testing/BENCHMARKS.md` |
| — | Real-time parameter hand-off | **Not implemented** | needs a live callback; design in `docs/adr/ADR-007` |
| — | FFI DSP symbols + Flutter DSP controller | **Not implemented** | deferred (additive ABI work) |
| — | Audio backend (WASAPI) | **Not implemented** | Phase 4 |

## 3. Documented behaviour and guarantees

| Area | Guarantee | Note |
|---|---|---|
| Adapter | Invalid preset and invalid DSP config are distinguished by error variant | Two-authority model: preset schema + DSP numeric rules |
| Meter | Every reported level is finite | silent/subnormal/non-finite floor at `-200 dBFS` |
| Meter | Clipping is truthful | `±inf` counted as clipped; `NaN` counted non-finite only |
| Limiter | Output sample peak `<= ceiling` for every finite input | sample-peak, **not** true-peak |
| Limiter | Zero added latency | no look-ahead; `latency_samples() == 0` |
| Limiter | Channel-linked | one gain from the cross-channel peak; no stereo shift |
| Limiter | Disabled = bit-exact pass-through | gain reset to unity on disable |
| Pipeline | `process_interleaved` allocates nothing | proven by `allocation_tests` over 2000 blocks |
| Pipeline | No lock, no I/O in processing | fixed inline state; no `Mutex`/`RwLock` |
| Safety | Non-finite input cannot persist in state | equalizer resets poisoned sections; limiter/meter sanitize |

## 4. Test results (actual)

### Rust

```powershell
$ cargo fmt --all -- --check                                 # EXIT=0
$ cargo clippy --workspace --all-targets --locked -- -D warnings   # EXIT=0
$ cargo test --workspace --locked                            # EXIT=0
```

Test totals (127, was 64):

| Suite | Tests |
|---|---|
| `uam_domain` unit | 9 |
| `uam_dsp` unit (`lib`) | 7 |
| `uam_dsp` `allocation_tests` (new) | 1 |
| `uam_dsp` `config_tests` | 18 |
| `uam_dsp` `dsp_tests` | 10 |
| `uam_dsp` `limiter_tests` (new) | 20 |
| `uam_dsp` `meter_tests` (new) | 15 |
| `uam_dsp` `pipeline_tests` (new) | 5 |
| `uam_dsp` `safety_tests` (new) | 9 |
| `uam_ffi` unit | 7 |
| `uam_preset` unit | 2 |
| `uam_preset` `adapter_tests` (new) | 13 |
| `uam_preset` `preset_tests` | 11 |
| **Total** | **127** |

No existing test was weakened, skipped, or deleted. The Phase 2.2 contract test
`limiter_metadata_does_not_change_processing` still passes because the `Equalizer`
is unchanged; the real limiter is a separate `Limiter` composed by `DspPipeline`.

### Benchmark

```powershell
$ cd crates
$ cargo bench -p uam_dsp --bench dsp_processing --locked   # EXIT=0; 96 benchmarks
```

Reference-machine result against the Phase 2 target (stereo, 10 bands,
256-frame blocks, 48 kHz):

| Configuration | ns/frame | % of one core | Target |
|---|---|---|---|
| EQ + limiter | 254.70 | 1.223 % | < 2 % ✅ |
| EQ + limiter + meter | 271.12 | 1.301 % | — |
| EQ only | 201.32 | 0.966 % | — |

Full matrix, environment, and methodology: `docs/testing/BENCHMARKS.md`.

### Flutter

```powershell
$ dart format --output=none --set-exit-if-changed lib test   # EXIT=0; 0 changed
$ flutter analyze                                            # EXIT=0; No issues found
$ flutter test                                               # EXIT=0; 68 passed
```

No Dart source changed in this milestone.

### Preset fixtures

```powershell
$ python scripts/test/validate_presets.py                    # EXIT=0; PASSED
  # 3 valid fixtures accepted; 8 invalid fixtures rejected as expected
```

### Windows build

```powershell
$ powershell -File scripts/build/build_rust.ps1              # produced uam_ffi.dll
$ flutter build windows --debug                              # EXIT=0; uam.exe
```

Local Windows verification only (not CI, not a release build).

## 5. Dependencies added

| Crate | Dependency | Scope | Reason |
|---|---|---|---|
| `uam_preset` | `uam_domain` (path) | normal | `AudioConfig` for `to_dsp_config` |
| `uam_dsp` | `criterion 0.7.0` | dev | benchmark suite (`default-features = false`, `cargo_bench_support`) |

`crates/Cargo.lock` is updated accordingly; `--locked` builds and tests succeed.
No runtime dependency was added to `uam_dsp`, `uam_domain`, or the FFI crate.

## 6. Files changed

Added:

- `crates/uam_dsp/src/meter.rs`
- `crates/uam_dsp/src/limiter.rs`
- `crates/uam_dsp/src/pipeline.rs`
- `crates/uam_dsp/tests/meter_tests.rs`
- `crates/uam_dsp/tests/limiter_tests.rs`
- `crates/uam_dsp/tests/pipeline_tests.rs`
- `crates/uam_dsp/tests/safety_tests.rs`
- `crates/uam_dsp/tests/allocation_tests.rs`
- `crates/uam_dsp/benches/dsp_processing.rs`
- `crates/uam_preset/src/adapter.rs`
- `crates/uam_preset/tests/adapter_tests.rs`
- `docs/PHASE_2_3_DESIGN.md`
- `docs/PHASE_2_3_IMPLEMENTATION_REPORT.md` (this file)
- `docs/testing/BENCHMARKS.md`

Modified:

- `crates/uam_dsp/Cargo.toml` (criterion dev-dependency, `[[bench]]`)
- `crates/uam_dsp/src/lib.rs` (modules + re-exports)
- `crates/uam_dsp/src/config.rs` (limiter docs)
- `crates/uam_preset/Cargo.toml` (`uam_domain` dependency)
- `crates/uam_preset/src/lib.rs` (adapter module + re-export)
- `crates/Cargo.lock`
- `docs/PHASE_2_READINESS.md`, `docs/PHASE_2_IMPLEMENTATION_REPORT.md`,
  `docs/Roadmap.md`, `docs/Architecture.md`, `docs/Structure_File.md`,
  `docs/README.md`

## 7. Limitations (honest)

- **No real-time backend.** No audio callback exists, so the "parameter updates do
  not block the callback" exit criterion remains **unmet**; the hand-off design is
  in `docs/adr/ADR-007`, not implemented.
- **Sample peak, not true peak.** Neither the meter nor the limiter over-samples;
  inter-sample peaks can exceed the ceiling. Documented in every relevant module.
- **No look-ahead.** The limiter has zero latency but can distort transients.
- **Single release time constant.** No program-dependent release.
- **No `f32` kernel.** Internal processing remains `f64`; `f32` is a boundary
  format only.
- **Benchmarks are single-machine.** AMD Ryzen 5 6600H on Windows; not a
  cross-platform or CI claim. CI does not run benchmarks.
- **FFI/Flutter DSP surface not added.** Preset import and live DSP construction
  share the adapter in Rust, but no new C symbols or Flutter controller exist yet.

## 8. Remaining work

| Item | Owner milestone |
|---|---|
| Real-time parameter hand-off (prepared state, bounded transfer) | Phase 2.x / Phase 4 |
| FFI DSP config symbols + Flutter `DspController` | Phase 2.x (additive ABI) |
| WASAPI backend, endpoint handling, device change | Phase 4 |
| Look-ahead / true-peak limiter, parameter smoothing | later, with ADR |
| SQLite persistence, preset CRUD | Phase 3 |

See `docs/PHASE_2_READINESS.md` for the updated gap list and
`docs/Roadmap.md` §5 for the progress note.
