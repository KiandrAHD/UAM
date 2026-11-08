# UAM DSP Benchmarks

**Date:** 2026-11-08
**Milestone:** Phase 2.6 — DSP performance benchmarking
**Status:** measured on the reference machine (not CI)

This document records the actual measured results of the `uam_dsp` benchmark
suite, the exact command used, and the methodology. No numbers here are
estimated or invented; they are the Criterion point estimates from the run
described below.

---

## 1. Environment

| Item | Value |
|---|---|
| OS | Microsoft Windows 11 Pro, 10.0.26200, Build 26200 (64-bit) |
| CPU | AMD Ryzen 5 6600H with Radeon Graphics |
| CPU cores / threads | 6 physical / 12 logical |
| CPU base clock | 3.30 GHz (nominal) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13), cargo 1.99.1 |
| Profile | Cargo `bench` profile (inherits `release`): `opt-level = 3`, `lto = "thin"`, `codegen-units = 1`, `panic = "abort"` |
| Criterion | 0.7.0 (default features disabled; `cargo_bench_support`) |
| Sample rate | 48 000 Hz |
| Channels | mono (1) and stereo (2) |
| Block sizes | 128, 256, 512, 1024, 2048, 4096 frames |
| Band counts | 0, 1, 5, 10, 32 |

These are **reference-machine** numbers, not CI numbers. CI runs on Ubuntu and
does not execute benchmarks.

---

## 2. Command

From `crates/`:

```powershell
cargo bench -p uam_dsp --bench dsp_processing --locked
```

Group timing is reduced for reproducibility (0.5 s warm-up, 1 s measurement,
30 samples per benchmark). The full matrix completes in a few minutes.

---

## 3. Methodology

- **Deterministic input.** A fixed analytic waveform
  `0.25·sin(0.013·n) + 0.05·cos(0.00481·n)` generated once per block size.
- **Buffer reuse.** Each benchmark allocates its input buffer once, outside the
  timed closure. The timed closure does not copy, allocate, or re-generate input.
- **Initialization excluded.** Configuration construction, coefficient
  derivation, and filter allocation happen before timing. Only the steady-state
  `process_interleaved` call is timed.
- **Reset per iteration.** Stateful engines are reset inside the loop so every
  iteration processes the same number of samples deterministically.
- **No I/O in timing.** No logging, file, or network access inside the closure.
- **`black_box`** wraps the buffer and result so the optimizer cannot elide work.
- **Throughput.** `Throughput::Elements(block_size)` (frames). Reported
  `fr/s` = frames processed per second.
- **ns/frame.** `mean time (ns) / block_size (frames)`.
- **% of one core.** `ns/frame ÷ 20 833.3 ns` (one frame at 48 kHz), i.e. the
  fraction of a single core needed to keep up with real time.

---

## 4. EQ-only results (ns/frame)

### 4.1 Stereo (2 channels)

| Bands \ Frames | 128 | 256 | 512 | 1024 | 2048 | 4096 |
|---|---|---|---|---|---|---|
| 0 | 0.059 | 0.029 | 0.016 | 0.009 | 0.004 | 0.002 |
| 1 | 21.28 | 19.21 | 18.66 | 18.05 | 18.46 | 19.91 |
| 5 | 90.89 | 88.62 | 91.39 | 86.99 | 84.20 | 74.43 |
| 10 | 188.49 | 201.32 | 202.09 | 172.20 | 152.51 | 151.41 |
| 32 | 615.31 | 671.57 | 541.02 | 471.91 | 460.39 | 481.00 |

### 4.2 Mono (1 channel)

| Bands \ Frames | 128 | 256 | 512 | 1024 | 2048 | 4096 |
|---|---|---|---|---|---|---|
| 0 | 0.068 | 0.033 | 0.016 | 0.008 | 0.004 | 0.002 |
| 1 | 12.73 | 11.21 | 10.51 | 10.32 | 9.90 | 10.35 |
| 5 | 50.84 | 46.95 | 50.35 | 46.30 | 49.85 | 44.19 |
| 10 | 101.26 | 107.89 | 107.70 | 97.18 | 88.45 | 79.44 |
| 32 | 334.69 | 332.95 | 306.70 | 255.79 | 242.46 | 232.38 |

> **0-band note.** With 0 bands and 0 dB preamp the equalizer takes its
> bit-exact short-circuit path, so the ~0.002–0.07 ns/frame figure is call
> overhead only, not filter work.

### 4.3 EQ-only as % of one core at 48 kHz (stereo, 256-frame blocks)

| Bands | ns/frame | % of one core |
|---|---|---|
| 1 | 19.21 | 0.092 % |
| 5 | 88.62 | 0.425 % |
| 10 | 201.32 | 0.966 % |
| 32 | 671.57 | 3.223 % |

At 4096-frame blocks the 10-band and 32-band figures drop to `151.41` and
`481.00` ns/frame (`0.727 %` and `2.309 %`): larger blocks amortise the
per-call overhead.

---

## 5. Scenario overhead (stereo, 10 bands, ns/frame)

| Scenario \ Frames | 128 | 256 | 512 | 1024 | 2048 | 4096 |
|---|---|---|---|---|---|---|
| Bypass (equalizer early-out) | 0.058 | 0.029 | 0.015 | 0.007 | 0.004 | 0.002 |
| EQ only | 188.49 | 201.32 | 202.09 | 172.20 | 152.51 | 151.41 |
| EQ + peak meter | 199.36 | 192.85 | 187.76 | 174.86 | 170.38 | 163.51 |
| EQ + limiter | 265.26 | 254.70 | 245.57 | 199.86 | 167.61 | 169.54 |
| EQ + limiter + peak meter | 272.60 | 271.12 | 276.46 | 221.63 | 178.97 | 178.42 |

### 5.1 Isolated components (stereo, ns/frame)

| Component \ Frames | 128 | 256 | 512 | 1024 | 2048 | 4096 |
|---|---|---|---|---|---|---|
| Limiter only (10-band config, disabled EQ path) | 17.43 | 17.31 | 17.24 | 16.84 | 17.27 | 17.22 |
| Peak meter only | 4.32 | 4.22 | 4.18 | 4.28 | 4.51 | 4.06 |

### 5.2 Derived overheads (stereo, 10 bands)

| Metric | Value |
|---|---|
| Peak-meter overhead | ≈ 4–11 ns/frame per meter pass |
| Limiter overhead | ≈ 17 ns/frame |
| Marginal cost per stereo EQ band | ≈ 15–21 ns/frame (from 1→32 bands) |

---

## 6. Interpretation against the Phase 2 readiness target

`docs/PHASE_2_READINESS.md` proposed a target of **< 2 % of one core at 48 kHz
stereo, 10 bands, 256-frame blocks** for EQ + limiter.

| Configuration (stereo, 10 bands, 256 frames) | ns/frame | % of one core | Target |
|---|---|---|---|
| EQ + limiter | 254.70 | 1.223 % | < 2 % ✅ |
| EQ + limiter + peak meter | 271.12 | 1.301 % | — |
| EQ only | 201.32 | 0.966 % | — |

The target is met on the reference machine. The 32-band worst case
(`3.223 %` at 256 frames) is recorded for transparency; 32 bands is the Phase 0
maximum, not the expected default.

---

## 7. Limitations of these measurements

- Single reference machine (AMD Ryzen 5 6600H). Results are not a cross-platform
  or cross-CPU claim.
- No SIMD or multi-threading is used; the DSP is scalar `f64`, so per-frame cost
  is deterministic.
- Criterion `default-features = false` means no HTML/plot reports are produced;
  the console output and `target/criterion/**/estimates.json` are authoritative.
- Benchmarks measure the DSP kernel only. They contain no platform audio backend,
  because none exists yet (Phase 4).
