# Phase 2 Readiness — DSP Audit and Proposed Design

**Date:** 2026-11-08  
**Branch:** `feat/phase-1-1-stabilization` (audit branch)  
**Status:** audit complete; Phase 2 design proposed; implementation not started  

## Executive summary

Phase 2 is **not yet ready to start from the current DSP state alone**. The Rust
DSP crate delivers a correct, well-tested biquad equalizer core, but it is still
the Phase 0 prototype: it has no audio format conversion, no limiter or clipping
protection, no real-time parameter hand-off, no audio backend, and no
benchmark suite. Four of the six Phase 2 exit criteria are unmet.

This document classifies every DSP capability as implemented or missing, audits
the gaps against `docs/PRD.md` (AUD-001…AUD-009) and `docs/Architecture.md`
(§5, §10), and proposes a concrete Phase 2 design that closes them.

**Verdict:** the DSP layer is a *Phase 0 prototype*, not a *Phase 2-ready
engine*. It is a sound foundation — the filter math, validation, and
allocation discipline are all reusable — but Phase 2 must add the format,
dynamics, parameter-hand-off, and benchmarking layers before the exit criteria
can be claimed.

## Phase 2 requirements recap

From `docs/Roadmap.md` §5 (Phase 2 — Rust Core and DSP Prototype):

- Define audio sample formats and channel layouts.
- Define DSP configuration models.
- Implement biquad filter primitives.
- Implement peaking, low-shelf, and high-shelf filters.
- Implement a configurable EQ chain.
- Implement preamp/gain with clipping awareness.
- Prototype limiter behavior.
- Add bypass and reset behavior.
- Benchmark CPU use and processing latency.
- Ensure real-time audio callbacks avoid locks, allocations, and blocking work.

From `docs/PRD.md` §7.3 (Audio Processing) and §8 (Non-Functional):

- AUD-001 configurable multi-band EQ (P0)
- AUD-002 preamp with safe limits and clipping warnings (P0)
- AUD-003 bass/treble shaping presets (P0)
- AUD-005 bypass and reset controls (P0)
- AUD-006 output peak monitoring and a limiter option (P1)
- Audio callbacks must avoid allocation, locks, unpredictable work.
- DSP must be benchmarked for CPU, latency, glitch-free operation.

From `docs/Architecture.md` §5 (DSP design requirements) and §10 (Threading):

- Sample-rate-aware coefficients; validated formats and layouts.
- No allocations or blocking locks in real-time callbacks.
- Separate parameter preparation from audio-thread application.
- Lock-free or bounded message passing for parameter updates.
- Define clipping behavior and safe gain defaults.
- Bypass without abrupt or unsafe transitions.
- Test for denormals, NaN, infinity, invalid parameters.
- Benchmark latency and CPU on reference hardware.
- DSP runs in the native audio processing context; callback work bounded.

## DSP capability audit

### Implemented (verified, reusable)

| Capability | Status | Evidence |
|---|---|---|
| RBJ biquad coefficients (peaking) | Implemented | `crates/uam_dsp/src/filters/mod.rs:158-166` |
| RBJ biquad coefficients (low shelf) | Implemented | `crates/uam_dsp/src/filters/mod.rs:167-174` |
| RBJ biquad coefficients (high shelf) | Implemented | `crates/uam_dsp/src/filters/mod.rs:175-182` |
| Preamp gain (−24…+12 dB) | Implemented | `crates/uam_dsp/src/equalizer/mod.rs:50-52,141` |
| Cascaded EQ chain, per-channel state | Implemented | `crates/uam_dsp/src/equalizer/mod.rs:55-61,139-148` |
| Direct Form II Transposed processing | Implemented | `crates/uam_dsp/src/filters/mod.rs:272-285` |
| Allocation only in `new` | Implemented | `crates/uam_dsp/src/equalizer/mod.rs:55,63-71`; no alloc in `process_interleaved` |
| Sample-rate-aware coefficient derivation | Implemented | `crates/uam_dsp/src/filters/mod.rs:152` |
| Nyquist guard band (5 %) | Implemented | `crates/uam_domain/src/audio_config.rs:113-115` |
| Parameter validation (finite, range, band count) | Implemented | `crates/uam_dsp/src/validation.rs:10-26`; `filters/mod.rs:84-115` |
| Non-finite input containment | Implemented | `crates/uam_dsp/src/filters/mod.rs:273,279-284` |
| Poisoned-state recovery (reset on non-finite output) | Implemented | `crates/uam_dsp/src/filters/mod.rs:281-284` |
| Bypass (bit-exact) + state reset | Implemented | `crates/uam_dsp/src/equalizer/mod.rs:106-111,135-137`; tests `equalizer/mod.rs:220-231` |
| Zero-band / zero-preamp bit-exact | Implemented | `crates/uam_dsp/src/equalizer/mod.rs:135-137`; tests `equalizer/mod.rs:208-217` |
| Magnitude response analysis | Implemented | `crates/uam_dsp/src/filters/mod.rs:217-239`; `equalizer/mod.rs:156-173` |
| `latency_samples()` = 0 (IIR, no buffering) | Implemented | `crates/uam_dsp/src/equalizer/mod.rs:178-180` |
| Mono + stereo interleaved `f64` | Implemented | `crates/uam_domain/src/audio_config.rs:17-23` |
| Sample rate 8 kHz … 384 kHz | Implemented | `crates/uam_domain/src/audio_config.rs:10-12,74-82` |
| Deterministic tests (41 Rust) | Implemented | `crates/uam_dsp/tests/dsp_tests.rs` (10 tests); unit tests in `filters/mod.rs`, `equalizer/mod.rs`, `uam_domain`, `uam_preset`, `uam_ffi` |
| Block-length validation (whole frames) | Implemented | `crates/uam_dsp/src/equalizer/mod.rs:128-134` |
| `#![forbid(unsafe_code)]` in DSP/domain | Implemented | `crates/uam_dsp/src/lib.rs:1`; `crates/uam_domain/src/lib.rs:1` |

### Missing (Phase 2 work)

| Gap | Blocks | PRD / Architecture reference |
|---|---|---|
| Sample formats other than `f64` (no `f32`, no integer) | AUD-001; real audio backends deliver `f32`/`i16` | Architecture §5 "Support validated sample formats" |
| Channel layouts beyond mono/stereo (no 5.1, no 7.1) | Future multichannel; Phase 2 scope can stay stereo | Architecture §5 "validated channel layouts" |
| Limiter / ceiling / soft clipping | AUD-006 (P1); AUD-002 clipping warnings | Roadmap §5 "Prototype limiter behavior"; Architecture §5 "Define clipping behavior" |
| Peak / clipping metering | AUD-006; Architecture §5 `Meter[Peak / Clipping Meter]` | Roadmap §7 Phase 4 instrumentation |
| Denormal protection and test | Architecture §5 "Test for denormals" | — |
| Parameter smoothing / ramping | Click-free gain changes; Architecture §5 "bypass without abrupt transitions" | — |
| Click-free bypass crossfade | Architecture §5 "bypass that does not cause abrupt transitions" | — |
| Real-time parameter hand-off (lock-free) | Architecture §5 "Separate parameter preparation from audio-thread application"; §10 | Roadmap §5 "Parameter updates do not block the audio callback" |
| DSP configuration DTO validated at the boundary | Roadmap §5 "Define DSP configuration models" | — |
| FFI config/processing control symbols | Roadmap §5 "Flutter integration for editing DSP parameters" | — |
| Audio backend / stream abstraction and callback ownership | Phase 4; Phase 2 must define the seam | Architecture §10 "DSP runs in the native audio processing context" |
| Preset → DSP adapter in Rust | Roadmap §5; Phase 3 import path | — |
| CPU / latency / glitch benchmark suite | Roadmap §5 exit criteria "Performance is acceptable on the MVP reference machine" | Architecture §5 "Benchmark latency and CPU use on reference hardware" |
| Property / fuzz tests for parameter and preset inputs | Architecture §13 "Property/fuzz tests for imported JSON" | — |
| Long-run stability test (no drift, no denormal lock-up) | Roadmap §5 "glitch-free operation" | — |
| Multichannel downmix/upmix policy | Future; not Phase 2 | — |
| Documentation of parameter ranges (published) | Roadmap §5 deliverable "Documented parameter ranges" | exists in `validation.rs` but not published as a doc |

### Not in Phase 2 scope (explicitly deferred)

- Windows audio integration, endpoint enumeration integration, device change
  handling — Phase 4 (`docs/Roadmap.md` §7).
- Bluetooth discovery, ANC/transparency adapters — Phase 5.
- SQLite persistence, preset CRUD storage — Phase 3.
- Linux/macOS/Android/iOS adapters — Phases 6–8.
- Cloud, accounts, sync — out of scope.

## Phase 2 exit-criteria assessment

| Roadmap §5 exit criterion | Status | Evidence |
|---|---|---|
| DSP tests pass for supported sample rates and channel layouts | **Partial** — tests cover 44.1/48 kHz stereo and 8 kHz mono; not all supported rates | `dsp_tests.rs:124-136` |
| No unexpected NaN/infinite values for validated inputs | **Met** | `dsp_tests.rs:108-121`; `filters/mod.rs:279-284` |
| Parameter updates do not block the audio callback | **Not met** — no audio callback exists; no parameter hand-off | — |
| Performance is acceptable on the MVP reference machine | **Not met** — no benchmark suite exists | no `benches/` in `crates/` |

Two of four exit criteria are met, one partial, one unmet. **Phase 2 is not
ready to be declared complete from the current state.**

## Proposed Phase 2 design

### 1. Audio format and channel model

Extend `uam_domain::AudioConfig` without breaking the existing API.

```rust
// uam_domain/src/audio_config.rs (additive)
pub enum SampleFormat {
    F32,   // primary backend format on Windows/WASAPI
    F64,   // internal processing precision (unchanged)
}

pub enum ChannelLayout {
    Mono,
    Stereo,
    // Phase 2 stops here. Multichannel is a later, separately-validated addition.
}
```

Rules:
- Internal processing stays `f64` (existing precision, existing tests).
- `f32` is converted to `f64` at the stream boundary and back at output, with
  a single rounding step per direction. No mixed-precision chains.
- Integer formats (`i16`, `i24`) are **not** accepted in Phase 2; if a backend
  exposes them, the adapter converts to `f32` first and records that in
  diagnostics.
- `AudioConfig::new` gains a `SampleFormat` parameter via a new constructor
  `AudioConfig::with_format`; the existing `AudioConfig::new` keeps `F64`
  default so all current call sites and tests remain valid.
- Channel count stays 1 or 2. A request for more channels returns
  `AudioConfigError::UnsupportedChannelCount` (unchanged).

### 2. DSP configuration DTO

A single validated DTO crosses every boundary (Rust internal, FFI, preset import).

```rust
// uam_dsp/src/config.rs (new)
#[derive(Debug, Clone, PartialEq)]
pub struct DspConfig {
    pub sample_rate_hz: u32,
    pub channels: u16,
    pub format: SampleFormat,
    pub preamp_db: f64,          // −24.0 … +12.0
    pub bands: Vec<BandConfig>,  // ≤ MAX_BANDS (32)
    pub limiter: LimiterConfig,
    pub bypassed: bool,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LimiterConfig {
    pub enabled: bool,
    pub ceiling_db: f64,     // −12.0 … 0.0, default −0.3
    pub release_ms: f64,     // 10 … 1000, default 100
}
```

Rules:
- `DspConfig` is validated by one function
  `DspConfig::validate(&self) -> Result<(), DspError>` reusing the existing
  `MIN_*`/`MAX_*` constants in `crates/uam_dsp/src/validation.rs`. No new
  numeric bounds are introduced in Phase 2 beyond the limiter.
- `BandConfig` is reused unchanged (`crates/uam_dsp/src/filters/mod.rs:49-58`).
- Serde `camelCase` JSON representation is added for the FFI payload, mirroring
  `crates/uam_preset/src/schema.rs` naming conventions.
- The DTO is `Clone + PartialEq` so the UI can diff configurations.

### 3. Rust configuration API

`uam_dsp` gains a builder plus a parametric processing handle.

```rust
// uam_dsp/src/lib.rs (additive exports)
pub use config::{DspConfig, LimiterConfig};

impl Equalizer {
    /// Build from a validated DTO. Equivalent to `new` plus limiter state.
    pub fn from_config(config: &DspConfig) -> Result<Self, DspError>;

    /// Apply a new configuration without reallocating when the band count
    /// and channel count are unchanged.
    pub fn apply_config(&mut self, config: &DspConfig) -> Result<(), DspError>;
}
```

Rules:
- `apply_config` reuses existing `Vec<Biquad>` capacity when `bands.len() *
  channels` is unchanged; otherwise it reallocates **off the audio thread**.
- Coefficient recomputation happens in `apply_config`, never in
  `process_interleaved`.
- `uam_preset` gains `Preset::to_dsp_config(&self) -> Result<DspConfig,
  PresetError>` so preset import and DSP construction share one validation
  path. `FilterType → FilterKind` already exists
  (`crates/uam_preset/src/schema.rs:29-47`).

### 4. Flutter → Rust flow

Phase 2 keeps the existing three-symbol control ABI and adds additive symbols
only. No audio buffers cross Dart FFI (Architecture §4).

```text
Flutter (Dart)                          Rust (native)
────────────────                        ──────────────
EqualizerController                     uam_dsp::DspConfig
   │  debounce 30 ms                        ▲
   ├─ serialize DspConfig JSON ────────────►│ uam_dsp_config_validate
   │                                        │   → Result<DspValidationReport>
   ├─ if valid, commit ────────────────────►│ uam_dsp_engine_apply_config
   │                                        │   (off-thread; hand-off to DSP)
   └─ read status ◄─────────────────────────│ uam_dsp_engine_status
                                            │   → DspStatus JSON
```

New Dart side:
- `lib/bridge/dsp_api.dart` — `DspGateway` interface + `RustDspApi`
  implementation, mirroring `EngineInfoGateway`/`RustApi` structure
  (`lib/bridge/rust_api.dart:15-19,101`).
- `EngineController` unchanged; a new `DspController` owns the config hand-off
  and status, so the Phase 1 controller's read-only contract is preserved.
- `processingVerified` stays `false` in Phase 2. The DSP engine is constructed
  and configurable, but no OS audio stream is attached — scope remains
  `configuration_only` until Phase 4.
- Debouncing: 30 ms after the last slider movement, then one commit. This keeps
  the UI responsive and avoids a commit per slider tick.

### 5. ABI versioning

`BRIDGE_ABI_VERSION` stays `1` in Phase 2. Policy:

| Change | ABI version |
|---|---|
| Add a new exported symbol | **no bump** (additive) |
| Add a field to an existing JSON payload | **no bump** if the field is optional and additive; bump if a required field is added |
| Change an existing function signature | **bump** |
| Change the meaning of an existing field | **bump** |
| Remove a symbol | **bump** |

Phase 2 adds these symbols, all additive:

```rust
#[unsafe(no_mangle)] pub extern "C" fn uam_dsp_api_version() -> u32;
#[unsafe(no_mangle)] pub unsafe extern "C" fn uam_dsp_config_validate(cfg_json: *const c_char) -> *mut c_char;
#[unsafe(no_mangle)] pub unsafe extern "C" fn uam_dsp_engine_create(cfg_json: *const c_char) -> u32;      // handle, 0 = failure
#[unsafe(no_mangle)] pub unsafe extern "C" fn uam_dsp_engine_apply_config(handle: u32, cfg_json: *const c_char) -> i32;
#[unsafe(no_mangle)] pub unsafe extern "C" fn uam_dsp_engine_status(handle: u32) -> *mut c_char;
#[unsafe(no_mangle)] pub unsafe extern "C" fn uam_dsp_engine_destroy(handle: u32);
```

Rules:
- `uam_abi_version()` continues to return `1`. `uam_dsp_api_version()` returns
  the DSP-specific contract version, starting at `1`, so DSP evolution does not
  force a bridge bump.
- All new functions follow the existing `uam_ffi` rules: only `uam_ffi` may
  contain `unsafe`, every `unsafe` block has a safety comment, every exported
  pointer has an explicit owner and a matching `_free`/`_destroy`
  (`crates/uam_ffi/src/lib.rs:1-18`).
- `AppConstants.expectedBridgeAbiVersion` stays `1`; a new
  `expectedDspApiVersion = 1` is added and checked the same way
  (`lib/core/constants/app_constants.dart:9`).
- A migration path is documented **before** any bump: `docs/adr/ADR-008` would
  record the reason, the old/new payloads, and a compatibility window.
- Rust tests assert that the three Phase 0 symbols are unchanged and that each
  new symbol is present and callable (a "surface contract" test).

### 6. Safe parameter updates

Parameter updates must never block or reallocate on the audio thread.

```text
UI thread                     control thread                DSP thread
─────────                     ──────────────                ──────────
slider change                 ┌──────────────┐              ┌────────────────┐
  │ debounce 30 ms            │ validate DTO │              │ audio callback │
  ▼                           │ (no alloc)   │              │  reads slot    │
serialize DspConfig ─────────►│              │              │  (lock-free)   │
                              │ commit       │──seqlock───► │                │
                              └──────────────┘  or triple   └────────────────┘
                                                buffer
```

Mechanism (Phase 2, no backend yet):
- `DspParameterSlot` — a fixed-size, allocation-free slot holding the
  coefficients and limiter state for the next block.
- Writers (control side) build the next slot, validate it, then publish with a
  sequence counter (seqlock) or swap a triple-buffer index.
- Readers (audio side) read the current slot once per block, never partially.
- On mismatch (writer mid-publish), the reader reuses the previous slot for
  that block and retries on the next block. No lock is taken.
- Coefficient interpolation: Phase 2 applies the new coefficients at a block
  boundary and resets filter state only if the sample rate or channel count
  changed. Gain/preamp changes do not reset state; a 5 ms linear ramp on the
  preamp linear gain avoids clicks.
- Bypass transitions use a 5 ms equal-power crossfade rather than an abrupt
  switch, closing the gap noted in `equalizer/mod.rs:104-105`.

### 7. Real-time thread safety

Invariant enforced by construction, verified by test:

| Rule | Enforcement |
|---|---|
| No allocation in `process_interleaved` | Already true (`equalizer/mod.rs:139-148`); add a test that runs the callback with a custom allocator counting allocations |
| No locks in `process_interleaved` | Seqlock/triple-buffer read is lock-free; add a test asserting no `Mutex`/`RwLock` is touched (compile-time by type, runtime by allocation/lock counters) |
| No I/O, no logging in `process_interleaved` | Already true; add a lint-level guard (`#![deny(clippy::print_stdout)]` in the DSP crate is not applicable — it is a library; instead the audit relies on the allocation/lock test) |
| Bounded work per block | Fixed iteration count `bands × channels × frames`; no early exits that depend on input values |
| Denormal protection | Flush-to-zero on subnormal outputs; tested with `1e-308` inputs |
| Panics | `process_interleaved` contains no `unwrap`/`expect`/index-out-of-bounds paths on validated input; a `catch_unwind` boundary is added in the future backend, not in the DSP crate |

New tests in `crates/uam_dsp/tests/rt_safety_tests.rs`:
- allocation-count test using a custom `GlobalAlloc` that asserts zero
  allocations during a 1000-block run after warm-up;
- lock-free read/write concurrency test using multiple threads hammering
  `apply_config` while another thread runs `process_interleaved`;
- denormal input test (`f64::MIN_POSITIVE / 4`);
- long-run drift test (10 s of audio, assert output stays finite and the RMS
  of a constant input stays within tolerance).

### 8. Limiter and clipping

Phase 2 prototypes the limiter per Roadmap §5 and AUD-006; the peak meter is
Phase 4 instrumentation, but the limiter must expose the data the meter needs.

```text
Preamp → EQ cascade → Limiter → (output)
```

Design:
- Look-ahead: none in Phase 2 (adds latency and a delay line). A simple
  feed-forward gain-reduction limiter is used.
- Detection: peak of the absolute sample value, per channel, smoothed with a
  one-pole envelope follower; release from `LimiterConfig::release_ms`.
- Gain reduction: `target_gain = min(1.0, ceiling_linear / detected_peak)`;
  the gain is ramped (not stepped) across the block.
- Ceiling default `-0.3 dBFS`, range `−12.0 … 0.0`.
- Clipping awareness (AUD-002):
  - the limiter reports `clipping_detected: bool` and
    `peak_dbfs: f64` per block in `DspStatus`;
  - when the limiter is disabled and the post-EQ peak exceeds `0 dBFS`, the
    status reports `clipping_detected = true` but **does not hard-clip the
    signal** — the value is left as-is and the UI shows a warning. Hard
    clipping is opt-in via `LimiterConfig::ceiling_db` (the limiter's job).
- Safe defaults: preamp `0.0 dB`, all bands `0.0 dB`, limiter enabled with
  `-0.3 dB` ceiling. This guarantees a valid configuration cannot produce
  sustained clipping.
- Bypass of the limiter is independent of EQ bypass, so users can A/B the EQ
  with and without limiting.

### 9. Latency and CPU benchmark methodology

No `benches/` directory exists today. Phase 2 adds one.

```text
crates/
└── uam_dsp/
    └── benches/
        ├── eq_cpu.rs        # criterion: per-block CPU cost
        └── eq_latency.rs    # measured algorithmic latency + block latency
```

Method:
- **CPU cost.** `criterion` with `throughput = frames`, measuring
  `process_interleaved` on 128-, 256-, 512-, 1024-, 4096-frame blocks at
  48 kHz stereo, for 0 / 1 / 5 / 10 / 32 bands. Report `ns/frame` and derived
  `% of one core at real-time`. Release profile with `lto = "thin"`,
  `codegen-units = 1` (already set in `crates/Cargo.toml`).
- **Algorithmic latency.** Assert `latency_samples() == 0` and verify by
  cross-correlating input and output impulses; report the measured offset.
- **End-to-end latency.** Not measurable in Phase 2 (no backend). Documented
  as: `algorithmic latency (0) + backend buffer latency (Phase 4)`. Phase 4
  adds the measurement harness.
- **Glitch-free operation.** A 60-second run with parameter changes applied
  every 500 ms; assert every output sample is finite and no NaN appears.
- **Reference hardware.** The MVP reference machine is the current host
  (Windows 11, x86_64). Results are recorded with the host CPU model, Rust
  version, and profile in `docs/testing/BENCHMARKS.md` (new).
- **Reproducibility.** `cargo bench` runs are recorded with `--save-baseline
  phase2`; the baseline is committed as a text file so regressions are
  diffable.
- **Acceptance target (proposed, subject to confirmation).** 10-band stereo
  EQ + limiter at 48 kHz must consume < 2 % of one core on the reference
  machine at 256-frame blocks. If the target is not met, Phase 2 records the
  measurement and the optimization is scheduled before Phase 4.

### 10. Error handling and bypass

| Condition | Behavior |
|---|---|
| Invalid DTO at the FFI boundary | `uam_dsp_config_validate` returns a structured report (error kind + field path + bounds); the engine is not created and no state changes |
| Engine handle invalid | `uam_dsp_engine_*` return a non-zero error code; no panic, no abort |
| Coefficient computation failure (`UnstableCoefficients`) | `apply_config` fails; the previous valid configuration stays active; status reports the failure |
| Non-finite input sample | Replaced with silence; filter state reset if poisoned (existing behaviour, `filters/mod.rs:273-284`) |
| Sample-rate or channel change | New `DspConfig` requires a new engine handle; `apply_config` returns an error rather than reallocating on the audio thread |
| Bypass on | Bit-exact passthrough (existing behaviour, `equalizer/mod.rs:135-137`) with a 5 ms crossfade on the transition |
| Bypass off | Coefficients resume from a reset state if the bypass lasted more than one block; crossfade in |
| Limiter bypass | Independent of EQ bypass; gain reduction resets to unity |
| Panic in DSP | Cannot happen from validated input; `uam_ffi` catches nothing — the backend (Phase 4) owns a `catch_unwind` boundary |
| Preset that fails validation | `Preset::to_dsp_config` returns `PresetError`; UI shows the existing local-validation message; no partial application |

## Implementation plan

Ordered so that each step is independently testable:

| # | Work item | Crate | Tests |
|---|---|---|---|
| 1 | `SampleFormat` in `AudioConfig` (additive constructor) | `uam_domain` | sample-rate/format matrix |
| 2 | `DspConfig` + `LimiterConfig` + `validate` | `uam_dsp` | valid/invalid DTO table tests |
| 3 | `Equalizer::from_config` / `apply_config` | `uam_dsp` | config-equivalence to `new`; capacity reuse |
| 4 | Denormal + allocation + lock-free tests | `uam_dsp` | `rt_safety_tests.rs` |
| 5 | Limiter prototype + clipping reporting | `uam_dsp` | gain-reduction envelope; ceiling bounds; bypass independence |
| 6 | Crossfade bypass + preamp ramp | `uam_dsp` | no-click test (energy delta at transition) |
| 7 | `Preset::to_dsp_config` | `uam_preset` | preset→config round-trip; invalid preset rejection |
| 8 | New FFI symbols + surface-contract test | `uam_ffi` | symbol presence; validation report shape; handle lifecycle |
| 9 | `DspGateway` / `RustDspApi` + `DspController` | Flutter | unit + widget tests with a fake gateway |
| 10 | Debounced commit + status wiring in EQ page | Flutter | widget test asserting one commit per debounce window |
| 11 | `benches/eq_cpu.rs`, `benches/eq_latency.rs` | `uam_dsp` | `cargo bench` runs; baseline committed |
| 12 | `docs/testing/BENCHMARKS.md` + `docs/adr/ADR-007` (RT safety) | docs | — |

Dependencies: 1 → 2 → 3; 4 and 5 depend on 3; 6 depends on 5; 7 depends on 2;
8 depends on 3 and 7; 9 depends on 8; 10 depends on 9; 11 depends on 5; 12
depends on 11.

## Open decisions

1. **Limiter look-ahead.** None in Phase 2. Look-ahead adds a delay line and
   `latency_samples() > 0`, which changes the latency contract. Deferred to a
   later phase with an explicit ADR if a transparent limiter is required.
2. **`f32` processing path.** Phase 2 converts at the boundary rather than
   adding a second `f32` chain. A native `f32` path halves memory traffic but
   doubles the test matrix; revisit only if the CPU benchmark misses the
   acceptance target.
3. **Multichannel.** Out of Phase 2 scope. `ChannelLayout` stays mono/stereo;
   adding 5.1/7.1 requires a downmix policy and a new preset compatibility
   field.
4. **Parameter smoothing detail.** 5 ms linear preamp ramp is proposed; an
   exponential ramp is audibly smoother but harder to test deterministically.
   Decision deferred to implementation review.
5. **Benchmark acceptance threshold.** < 2 % of one core at 48 kHz stereo,
   10 bands, 256-frame blocks is proposed. Confirm against the MVP reference
   machine before Phase 4.

## Readiness verdict

| Area | Phase 2 ready? |
|---|---|
| Biquad filter math, EQ chain, preamp | **Yes** — correct, tested, allocation-disciplined |
| Parameter validation and error types | **Yes** — reusable as-is |
| Bypass and reset semantics | **Yes** — bit-exact; crossfade is a Phase 2 addition |
| Sample format beyond `f64` | **No** — Phase 2 work |
| Limiter / clipping protection | **No** — Phase 2 work |
| Real-time parameter hand-off | **No** — Phase 2 work |
| Audio backend seam | **No** — Phase 2 defines the interface; Phase 4 implements |
| Benchmark suite | **No** — Phase 2 work |
| FFI config surface | **No** — Phase 2 work (additive to ABI 1) |
| Flutter DSP controller | **No** — Phase 2 work |

**Overall:** the DSP core is a *Phase 0 prototype* that Phase 2 can build on,
not a Phase 2-ready engine. Two of four Phase 2 exit criteria are unmet. The
proposed design above closes every gap while preserving the existing ABI, the
existing 41 Rust tests, the existing 68 Flutter tests, and the existing honest
`configuration_only` reporting.
