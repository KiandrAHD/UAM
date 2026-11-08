//! Feed-forward peak limiter.
//!
//! `LimiterConfig` was metadata only through Phase 2.2. This module turns it
//! into a real signal-processing component while keeping the equalizer and the
//! limiter independent and separately testable.
//!
//! # Algorithm
//!
//! A **feed-forward, zero-look-ahead, peak limiter with instantaneous attack
//! and one-pole release**:
//!
//! 1. For each frame, compute the peak magnitude of the frame across all
//!    channels (`max |x[c]|`). Using one peak for every channel is the
//!    **channel-linking** strategy: a single gain is applied to all channels,
//!    so the stereo image cannot shift because one channel is limited more
//!    than the other.
//! 2. Derive the *target gain* needed so the loudest sample of the frame sits
//!    at the ceiling: `target = min(1, ceiling_linear / peak)`.
//! 3. Update the running gain:
//!    - **Attack (instantaneous):** if `target < gain`, set `gain = target`
//!      immediately.
//!    - **Release (smoothed):** otherwise move `gain` toward `target` with a
//!      one-pole filter `gain = target + (gain - target) * release_coeff`,
//!      where `release_coeff = exp(-1 / release_samples)` and
//!      `release_samples = release_ms * 1e-3 * sample_rate`.
//! 4. Apply `gain` to every channel of the frame.
//!
//! Because the gain applied to a frame never exceeds that frame's target
//! (attack sets it equal; release keeps it `<=` target), the output magnitude
//! is bounded by the ceiling **for every finite input sample**. This is a
//! sample-peak guarantee, not a true-peak guarantee.
//!
//! # Signal flow
//!
//! ```text
//! input (interleaved f64)
//!   -> per-frame peak detection (channel-linked)
//!   -> target gain = min(1, ceiling / peak)
//!   -> attack (instant) / release (one-pole)
//!   -> multiply all channels
//!   -> output
//! ```
//!
//! # Documented limitations and trade-offs
//!
//! - **Not true peak.** There is no over-sampling or reconstruction, so
//!   inter-sample peaks can exceed the ceiling even though every sample is
//!   bounded. A DAC can therefore still overshoot between samples.
//! - **Not brick-wall in the analogue sense.** As above, only the sample peak
//!   is guaranteed.
//! - **No look-ahead.** Because the gain is derived from the same sample it is
//!   applied to, there is **zero added latency** (`latency_samples() == 0`),
//!   but the gain can change abruptly on a transient, which introduces
//!   harmonic distortion on fast material. A look-ahead design would need a
//!   delay line, non-zero reported latency, and a pre-allocated buffer; it is
//!   deferred to a later milestone.
//! - **Instantaneous attack.** Gain reduction reaches the required value on
//!   the exact sample that exceeds the ceiling; the cost is distortion, not
//!   overshoot.
//! - **Release is a single time constant.** No program-dependent or multi-stage
//!   release is modelled.
//!
//! # Real-time behaviour
//!
//! Processing is allocation-free, lock-free, I/O-free, and bounded: work is
//! `frames * channels` multiply-adds plus one `exp` pre-computed at
//! construction. State is a handful of scalars. When the limiter is disabled,
//! [`Limiter::process_interleaved`] returns without touching the buffer, which
//! preserves the pre-limiter output exactly.
//!
//! Non-finite input samples are replaced with silence before detection, so they
//! can neither raise a false peak nor poison the gain state.

use uam_domain::AudioConfig;

use crate::config::LimiterConfig;
use crate::validation::DspError;

/// Feed-forward peak limiter. See the module documentation for the algorithm,
/// guarantees, and limitations.
#[derive(Debug, Clone)]
pub struct Limiter {
    channels: u16,
    enabled: bool,
    ceiling_linear: f64,
    release_coeff: f64,
    gain: f64,
    last_block_max_reduction_db: f64,
    peak_reduction_db: f64,
    limited_samples: u64,
}

impl Limiter {
    /// Build a limiter from validated configuration and audio parameters.
    ///
    /// # Errors
    ///
    /// Returns [`DspError`] when [`LimiterConfig::validate`] fails. The audio
    /// configuration is assumed already validated by [`AudioConfig`].
    pub fn new(config: &LimiterConfig, audio: AudioConfig) -> Result<Self, DspError> {
        config.validate()?;

        let ceiling_linear = db_to_linear(config.ceiling_db());
        let sample_rate = f64::from(audio.sample_rate_hz());
        let release_samples = (config.release_ms() * 1.0e-3 * sample_rate).max(1.0);
        let release_coeff = (-1.0 / release_samples).exp();

        Ok(Self {
            channels: audio.channels(),
            enabled: config.enabled(),
            ceiling_linear,
            release_coeff,
            gain: 1.0,
            last_block_max_reduction_db: 0.0,
            peak_reduction_db: 0.0,
            limited_samples: 0,
        })
    }

    /// Number of interleaved channels expected by [`Self::process_interleaved`].
    #[must_use]
    pub const fn channels(&self) -> u16 {
        self.channels
    }

    /// Whether the limiter will act on the signal.
    #[must_use]
    pub const fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Enable or disable the limiter. Disabling resets the gain immediately so
    /// a disabled limiter is a bit-exact pass-through.
    pub fn set_enabled(&mut self, enabled: bool) {
        if self.enabled && !enabled {
            self.reset();
        }
        self.enabled = enabled;
    }

    /// Linear ceiling the output sample peak is bounded to.
    #[must_use]
    pub const fn ceiling_linear(&self) -> f64 {
        self.ceiling_linear
    }

    /// Current gain as a linear multiplier (`1.0` means no reduction).
    #[must_use]
    pub const fn gain(&self) -> f64 {
        self.gain
    }

    /// Current gain reduction in dB (non-negative).
    #[must_use]
    pub fn gain_reduction_db(&self) -> f64 {
        -linear_to_db(self.gain)
    }

    /// Maximum gain reduction observed in the most recent block, in dB.
    #[must_use]
    pub const fn last_block_max_reduction_db(&self) -> f64 {
        self.last_block_max_reduction_db
    }

    /// Maximum gain reduction observed since the last reset, in dB.
    #[must_use]
    pub const fn peak_reduction_db(&self) -> f64 {
        self.peak_reduction_db
    }

    /// Number of samples that were scaled down since the last reset.
    #[must_use]
    pub const fn limited_samples(&self) -> u64 {
        self.limited_samples
    }

    /// Added algorithmic latency in samples. The chosen design has no
    /// look-ahead, so this is always zero.
    #[must_use]
    pub const fn latency_samples(&self) -> u32 {
        0
    }

    /// Reset gain and statistics to the deterministic initial state.
    pub fn reset(&mut self) {
        self.gain = 1.0;
        self.last_block_max_reduction_db = 0.0;
        self.peak_reduction_db = 0.0;
        self.limited_samples = 0;
    }

    /// Apply limiting to an interleaved `f64` buffer in place.
    ///
    /// A disabled limiter returns without modifying the buffer. An enabled
    /// limiter bounds every finite output sample to `|x| <= ceiling_linear`.
    ///
    /// # Errors
    ///
    /// Returns [`DspError::InvalidBlockLength`] when the buffer is not a whole
    /// number of frames. No samples are modified in that case.
    pub fn process_interleaved(&mut self, samples: &mut [f64]) -> Result<(), DspError> {
        let channels = usize::from(self.channels);
        if samples.len() % channels != 0 {
            return Err(DspError::InvalidBlockLength {
                samples: samples.len(),
                channels: self.channels,
            });
        }
        if !self.enabled {
            return Ok(());
        }

        let mut block_max_reduction = 0.0_f64;

        for frame in samples.chunks_exact_mut(channels) {
            // Sanitize and detect the frame peak. Channel linking: one peak
            // for the whole frame drives one gain for every channel.
            let mut peak = 0.0_f64;
            for sample in frame.iter_mut() {
                if !sample.is_finite() {
                    *sample = 0.0;
                }
                let magnitude = sample.abs();
                if magnitude > peak {
                    peak = magnitude;
                }
            }

            let target_gain = if peak > self.ceiling_linear {
                self.ceiling_linear / peak
            } else {
                1.0
            };

            if target_gain < self.gain {
                // Instantaneous attack.
                self.gain = target_gain;
            } else {
                // One-pole release toward the target.
                self.gain = target_gain + (self.gain - target_gain) * self.release_coeff;
            }

            let reduction_db = -linear_to_db(self.gain);
            if reduction_db > block_max_reduction {
                block_max_reduction = reduction_db;
            }
            if reduction_db > self.peak_reduction_db {
                self.peak_reduction_db = reduction_db;
            }

            for sample in frame.iter_mut() {
                *sample *= self.gain;
                self.limited_samples += 1;
            }
        }

        self.last_block_max_reduction_db = block_max_reduction;
        Ok(())
    }
}

/// Convert decibels to a linear multiplier: `10^(db / 20)`.
fn db_to_linear(db: f64) -> f64 {
    10.0_f64.powf(db / 20.0)
}

/// Convert a linear multiplier to decibels. `0.0` maps to [`f64::NEG_INFINITY`];
/// callers only use this on strictly positive gains.
fn linear_to_db(linear: f64) -> f64 {
    20.0 * linear.log10()
}
