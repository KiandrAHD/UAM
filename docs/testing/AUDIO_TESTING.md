# Audio Testing Guide

**Phase:** 0
**Scope:** how UAM verifies DSP correctness now, and how it must verify real
audio behavior once a backend exists.

## 1. Principles

- Test the DSP with **deterministic, synthetic signals**, not by ear.
- Separate **DSP correctness** (math) from **integration correctness** (stream,
  clock, device) from **perceptual quality** (manual listening).
- Never record or upload user audio during automated tests.
- State the processing scope explicitly in every result. Phase 0 is
  `configuration_only`.
- A green DSP test does not prove system audio works.

## 2. Current automated DSP tests

Implemented in `crates/uam_dsp/`:

### 2.1 Frequency response (coefficient level)

`BiquadCoefficients::magnitude_db_at` is evaluated at the filter's centre or
corner frequency:

- Peaking filter gain at `f0` must equal the configured gain within `0.01 dB`
  for gains from `-12` to `+12 dB`.
- Low shelf at `200 Hz / +6 dB` must boost `20 Hz` by more than `5 dB` and leave
  `10 kHz` within `1 dB`.
- High shelf at `4 kHz / -6 dB` must leave `100 Hz` within `1 dB` and cut
  `20 kHz` by more than `5 dB`.

### 2.2 Time-domain gain (signal level)

A deterministic sine is processed for two seconds; the first second is discarded
to skip the startup transient; RMS before and after is compared:

- A `+6 dB` peaking band at `1 kHz` must produce `6 ± 0.3 dB`.
- A `-6 dB` preamp must produce `-6 ± 0.001 dB`.

### 2.3 Stability and safety

- An impulse response must stay finite and decay below `1e-6` in the tail.
- `NaN`, `+Infinity`, and `-Infinity` input samples must not poison state or
  produce non-finite output.
- Coefficients must be finite; a zero denominator is rejected.

### 2.4 Parameter validation

- Non-finite and out-of-range frequency, gain, and Q are rejected.
- A frequency above the sample-rate guard band is rejected.
- More than `32` bands are rejected.
- Preamp outside `-24..=12 dB` is rejected.

### 2.5 Supported sample rates

`44_100` and `48_000` Hz are exercised. Coefficients are recomputed per sample
rate; there is no hard-coded `44.1 kHz` assumption.

## 3. Manual DSP verification (optional, local)

Use any signal generator and analyzer (REW, Room EQ Wizard; `sox`; or a DAW):

1. Play pink noise through the chain.
2. Compare the measured response with the predicted
   `Equalizer::frequency_response_db` curve.
3. Confirm the peak/cut is centred where configured.
4. Confirm bypass returns the signal to unity.

Do not commit recordings or machine-specific measurements.

## 4. Future real-time audio tests (Phase 4+)

These are **not implemented** and must be designed before the first backend
ships.

### 4.1 Loopback measurement

- Render a known test signal (sine sweep or pink noise).
- Capture the processed output through loopback.
- Compute the transfer function (`FFT` ratio) and compare against the predicted
  magnitude response.
- Tolerance should be documented per device class; clock drift and resampling
  will add error.

### 4.2 Glitch and dropout detection

- Run a long stream and count discontinuities beyond a threshold.
- Record buffer size, sample rate, and CPU load.
- Assert no dropouts over a defined duration on reference hardware.

### 4.3 Latency

- Measure round-trip latency with an impulse.
- Report the backend's buffer latency separately from DSP latency. The
  minimum-phase IIR chain adds `0` samples of algorithmic latency
  (`Equalizer::latency_samples` returns `0`), so total latency is dominated by
  the OS buffer.

### 4.4 Device lifecycle

- Default-device change.
- Device removal and reconnection.
- Sleep/wake.
- Exclusive-mode contention (Windows).
- Permission denial (mobile).

### 4.5 Real-time safety

- No allocation, locking, I/O, or logging on the audio thread.
- Parameter changes are handed off without blocking.
- Denormal and non-finite inputs are contained.

## 5. Measurement honesty

- Report the exact processing scope (`app_owned_stream`, `selected_stream`,
  `system_output`, `configuration_only`).
- Do not describe a configuration-only test as audio processing.
- Do not generalize one device's result to all devices.
- Record the OS, driver, device, sample rate, buffer size, and build hash with
  any performance claim.

## 6. What Phase 0 did not test

- No audio was played or captured by UAM.
- No loopback measurement was performed.
- No latency or CPU benchmark was run.
- No device hot-plug test was run.
- No mobile audio session was tested.

The only audio-API evidence in Phase 0 is **device enumeration** through the
Windows MMDevice API (`tools/audio_diagnostics/`). That is not a processing
test.