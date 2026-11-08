# Phase 2.3 Design — Preset Adapter, Metering, Limiter, Pipeline, Benchmarking

**Date:** 2026-11-08
**Branch:** `feat/phase-2-3-complete-dsp`
**Status:** design of record; implemented in the same milestone (see `docs/PHASE_2_3_IMPLEMENTATION_REPORT.md`)
**Scope:** Phase 2.3A preset→DSP adapter, 2.3B peak metering, 2.3C limiter and
processing pipeline, 2.3D numerical safety, 2.6 DSP benchmarking

This document is the technical design record. It states what each component does,
what it guarantees, and — explicitly — what it does **not** guarantee.

---

## 1. Preset-to-DSP adapter (2.3A)

### 1.1 Problem

The portable `.uam-preset.json` schema (schema v1) stores metadata, a preamp
value, and an ordered EQ band list. The DSP engine consumes a validated
`DspConfig`. Two separate validators must not diverge: the preset validator owns
portable-schema rules, and the DSP layer owns numeric DSP rules, including the
sample-rate-dependent frequency limit.

### 1.2 API

```rust
impl Preset {
    pub fn to_dsp_config(
        &self,
        audio_config: AudioConfig,
    ) -> Result<DspConfig, PresetConversionError>;
}
```

`PresetConversionError` has two variants:

| Variant | Meaning |
|---|---|
| `InvalidPreset(PresetError)` | the preset itself fails portable validation |
| `Dsp(DspError)` | the converted configuration fails a DSP rule |

The preset does not carry a sample rate or channel count, so the caller supplies
the target `AudioConfig`.

### 1.3 Data-flow and rules

1. Validate the preset first (`Preset::validate`). Any portable failure is a
   `PresetConversionError::InvalidPreset`.
2. Map each `EqBand` in order to a `BandConfig`: `filter_type → FilterKind`
   (existing impl), frequency/gain/Q copied verbatim.
3. Build `DspConfig::new(audio_config, preamp_db, bands)`. This is the **final
   validation authority**; it re-checks every band against the sample rate.
4. The limiter is **not** invented: the schema has no limiter field, so the
   resulting configuration carries `limiter == None` and the DSP default
   (disabled) applies. Bypass is likewise not invented.

No second set of numeric bounds exists in the adapter.

---

## 2. Peak metering and clipping detection (2.3B)

### 2.1 What is measured

`PeakMeter` measures **sample peak**: the largest `|x|` in a block, per channel
and overall, plus a count of samples that reach or exceed an explicit clipping
threshold.

| Concept | Implemented | Notes |
|---|---|---|
| Sample peak | **Yes** | `max abs(sample)` per block and running (peak-hold) |
| Clipping detection | **Yes** | `abs(sample) >= CLIP_THRESHOLD_LINEAR` where threshold = `1.0` (`0 dBFS`) |
| True peak | **No** | requires over-sampling and reconstruction; not implemented and not claimed |

### 2.2 API

```rust
pub struct PeakMeter { /* fixed inline state */ }
impl PeakMeter {
    pub fn new(channels: u16) -> Result<Self, MeterError>;
    pub fn with_clip_threshold(channels: u16, clip_threshold: f64) -> Result<Self, MeterError>;
    pub fn process_interleaved(&mut self, samples: &[f64]) -> Result<BlockPeak, MeterError>;
    pub fn reset(&mut self);
    // running peak-hold accessors, clipped/non-finite counts, processed frames
}

pub struct BlockPeak { /* per-channel peaks, overall peak, counts */ }
```

`BlockPeak` exposes per-channel peaks, overall peak, `overall_peak_dbfs()`,
`clipped_samples()`, `clipping_detected()`, `non_finite_samples()`, and `frames()`.

### 2.3 Policies

- **Clipping threshold.** Full scale `1.0` linear (`0 dBFS`). A sample is clipped
  when `|x| >= 1.0`, so a signal that reaches full scale is reported as clipped.
- **dBFS floor.** `linear_to_dbfs` returns a finite value always: silence,
  non-finite, and subnormal magnitudes map to `DBFS_FLOOR = -200.0`. The meter
  never returns `NaN` or `-inf`.
- **Non-finite input.**
  - `NaN` is ignored for level and clipping (no level information) and counted in
    `non_finite_samples`.
  - `±inf` is counted in `non_finite_samples` and **also** as clipped (its
    magnitude provably exceeds the threshold), but is never folded into the
    finite reported peak.
- **State.** Running peaks are peak-hold: they keep the maximum since the last
  `reset()`.
- **Empty buffer** is valid and yields an empty `BlockPeak`. A partial frame is
  rejected with `MeterError::InvalidBlockLength`.
- **Allocation.** State is a fixed `[f64; 2]` plus scalars. Processing allocates
  nothing, takes no lock, and performs no I/O. The meter is independent of the
  equalizer and limiter.

---

## 3. Limiter processor (2.3C)

### 3.1 Selected algorithm

**Feed-forward, zero-look-ahead, peak limiter with instantaneous attack and
one-pole release**, channel-linked.

### 3.2 Signal flow

```text
per frame:
  peak      = max |x[c]| over channels c            (channel linking)
  target    = min(1, ceiling_linear / peak)          (0 if peak == 0)
  gain      = (target < gain) ? target               (instant attack)
                              : target + (gain-target) * release_coeff  (release)
  x[c]     *= gain                                   (all channels)
```

`release_coeff = exp(-1 / release_samples)`, `release_samples = release_ms * 1e-3 * sample_rate`.

### 3.3 Behaviour and guarantees

| Property | Design |
|---|---|
| Attack | Instantaneous. The gain applied to a frame is the gain computed from that frame. |
| Release | One-pole toward the target with a time constant derived from `release_ms` and the sample rate. |
| Ceiling | `ceiling_db` from `LimiterConfig`, converted to linear `10^(db/20)`. The **sample peak** of the output is bounded by this ceiling for every finite input. |
| Gain reduction | Reported as `gain_reduction_db()` (current) and `last_block_max_reduction_db()` / `peak_reduction_db()` (per block / since reset). |
| Channel linking | One gain from the frame's cross-channel peak, applied to all channels, so the stereo image cannot shift. |
| Latency | **Zero.** No look-ahead delay line, so `latency_samples() == 0`. |
| Memory | Scalar state only; no buffer allocated at construction or during processing. |
| Determinism | All state is scalars; `reset()` restores `gain = 1.0` and clears statistics. |
| Allocation / locking | None during processing. No `Mutex`/`RwLock`. |
| Invalid configuration | Rejected by `LimiterConfig::validate` before construction. |
| Non-finite input | Sanitized to `0.0` before detection, so state cannot be poisoned. |

### 3.4 Limitations and trade-offs (honest)

- **Not true-peak.** No over-sampling. Inter-sample peaks can exceed the ceiling
  even though every sample is bounded.
- **Not a brick-wall limiter in the analogue sense.** Only the sample peak is
  bounded.
- **No look-ahead.** Zero latency, but the gain can change abruptly on a
  transient, introducing harmonic distortion on fast material.
- **Single release time constant.** No program-dependent, multi-stage release.
  A look-ahead / program-dependent design is deferred to a later milestone and
  would need a pre-allocated delay line and a non-zero latency report.

### 3.5 Why the limiter is not embedded in `Equalizer`

`Equalizer` is the preamp + EQ cascade and its behaviour is frozen at the Phase 2.2
contract (including the test proving that limiter *metadata* does not change its
output). Embedding limiter processing into `Equalizer` would change that
contract. Instead the limiter is a separate component composed by
`DspPipeline`, so each component stays independently testable and the existing
`Equalizer` tests and ABI stay valid.

---

## 4. Processing pipeline (2.3C)

### 4.1 Order

```text
input (interleaved f64)
  → input validation (whole frames)
  → input peak meter        (input level)
  → preamp + EQ cascade     (Equalizer)
  → pre-limiter peak meter  (clipping before limiting)
  → limiter                 (gain reduction)
  → output peak meter       (output peak)
  → output
```

### 4.2 Reported quantities

`DspPipeline::process_interleaved` returns a `PipelineReport` distinguishing:

| Quantity | Field |
|---|---|
| Input level | `report.input()` (`BlockPeak`) |
| Clipping before limiting | `report.pre_limiter().clipping_detected()` |
| Gain reduction | `report.gain_reduction_db()`, `report.limiter_active()` |
| Output peak | `report.output()` (`BlockPeak`) |

### 4.3 Characteristics

- The equalizer includes the preamp, so preamp and EQ share one buffer traversal.
- Bypass applies to the equalizer only; the limiter is independent (a disabled
  limiter is bit-exact pass-through).
- `from_config`/`apply_config` allocate (control-thread). `process_interleaved`
  allocates nothing, takes no lock, does no I/O.
- The pipeline has no dependency on an audio backend. Every stage is public and
  independently testable.

---

## 5. Denormal and numerical policy (2.3D)

- **No flush-to-zero.** `uam_dsp` does not enable FTZ/DAZ and does not add
  arbitrary clamping. IEEE-754 subnormals are processed as subnormals. This
  preserves signal fidelity at very low levels.
- **Consequence (documented, measured):** subnormal inputs pass through the
  limiter unchanged when below the ceiling, and produce finite (floored) meter
  levels. On CPUs that penalise subnormals, extreme low-level content can be
  slower; there is no correctness impact.
- **Bounded state.** Filter sections reset on non-finite output
  (`filters::Biquad::process`); the limiter sanitizes non-finite input; the meter
  ignores non-finite level contributions. No non-finite value can persist in
  state.
- **Explicit rejection** of invalid frequency, Q, gain, limiter configuration,
  and block length.

---

## 6. Benchmark methodology (2.6)

See `docs/testing/BENCHMARKS.md` for the actual measured results and full matrix.
Summary of method:

- Framework: Criterion (`cargo bench -p uam_dsp --bench dsp_processing`).
- Sample rate 48 kHz; mono and stereo; block sizes 128/256/512/1024/2048/4096.
- Band counts 0/1/5/10/32; scenarios EQ only, EQ + meter, EQ + limiter,
  EQ + limiter + meter, limiter only, meter only, bypass.
- Deterministic generated input; buffers reused; initialization excluded from the
  timed closure; no logging or I/O inside timing.
- Reported metrics: mean time, ns/frame, and frames/second (throughput).
