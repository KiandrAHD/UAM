//! Shared parameter bounds and typed DSP errors.
//!
//! The same numeric bounds are mirrored by `database/schema/preset.schema.json`
//! and `uam_preset::validation`. Keeping the constants here gives the Rust
//! implementation a single source of truth for the DSP layer.

use core::fmt;

/// Lowest accepted EQ frequency in hertz.
pub const MIN_FREQUENCY_HZ: f64 = 10.0;
/// Highest accepted EQ frequency in hertz before sample-rate validation.
pub const MAX_FREQUENCY_HZ: f64 = 20_000.0;
/// Lowest accepted per-band gain in decibels.
pub const MIN_GAIN_DB: f64 = -24.0;
/// Highest accepted per-band gain in decibels.
pub const MAX_GAIN_DB: f64 = 24.0;
/// Lowest accepted Q factor (or shelf transition control).
pub const MIN_Q: f64 = 0.1;
/// Highest accepted Q factor (or shelf transition control).
pub const MAX_Q: f64 = 10.0;
/// Lowest accepted preamp gain in decibels.
pub const MIN_PREAMP_DB: f64 = -24.0;
/// Highest accepted preamp gain in decibels.
pub const MAX_PREAMP_DB: f64 = 12.0;
/// Maximum number of EQ bands allowed by the Phase 0 preset contract.
pub const MAX_BANDS: usize = 32;

/// A parameter or processing contract violation.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DspError {
    /// A numeric parameter was `NaN` or infinite.
    NonFiniteParameter(&'static str),
    /// Frequency below the accepted minimum.
    FrequencyTooLow {
        /// Supplied value in hertz.
        frequency_hz: f64,
        /// Minimum accepted value in hertz.
        minimum_hz: f64,
    },
    /// Frequency above the sample-rate-dependent usable maximum.
    FrequencyTooHigh {
        /// Supplied value in hertz.
        frequency_hz: f64,
        /// Maximum accepted value in hertz.
        maximum_hz: f64,
    },
    /// Per-band gain outside the accepted range.
    GainOutOfRange {
        /// Supplied value in decibels.
        gain_db: f64,
    },
    /// Preamp gain outside the accepted range.
    PreampOutOfRange {
        /// Supplied value in decibels.
        gain_db: f64,
    },
    /// Q factor outside the accepted range.
    QOutOfRange {
        /// Supplied value.
        q: f64,
    },
    /// More bands were supplied than the Phase 0 contract permits.
    TooManyBands {
        /// Supplied band count.
        supplied: usize,
        /// Maximum accepted count.
        maximum: usize,
    },
    /// The interleaved buffer length is not a whole number of frames.
    InvalidBlockLength {
        /// Supplied sample count.
        samples: usize,
        /// Channel count used to derive the frame size.
        channels: u16,
    },
    /// Computed biquad coefficients were not finite or had a zero denominator.
    UnstableCoefficients,
}

impl fmt::Display for DspError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NonFiniteParameter(name) => {
                write!(formatter, "parameter '{name}' must be finite")
            }
            Self::FrequencyTooLow {
                frequency_hz,
                minimum_hz,
            } => write!(
                formatter,
                "frequency {frequency_hz:.2} Hz is below the minimum {minimum_hz:.2} Hz"
            ),
            Self::FrequencyTooHigh {
                frequency_hz,
                maximum_hz,
            } => write!(
                formatter,
                "frequency {frequency_hz:.2} Hz exceeds the usable maximum {maximum_hz:.2} Hz for this sample rate"
            ),
            Self::GainOutOfRange { gain_db } => write!(
                formatter,
                "band gain {gain_db:.2} dB is outside {MIN_GAIN_DB:.2}..={MAX_GAIN_DB:.2} dB"
            ),
            Self::PreampOutOfRange { gain_db } => write!(
                formatter,
                "preamp gain {gain_db:.2} dB is outside {MIN_PREAMP_DB:.2}..={MAX_PREAMP_DB:.2} dB"
            ),
            Self::QOutOfRange { q } => {
                write!(formatter, "Q {q:.4} is outside {MIN_Q:.2}..={MAX_Q:.2}")
            }
            Self::TooManyBands { supplied, maximum } => write!(
                formatter,
                "{supplied} bands supplied; at most {maximum} are supported in Phase 0"
            ),
            Self::InvalidBlockLength { samples, channels } => write!(
                formatter,
                "interleaved buffer has {samples} samples, which is not divisible by {channels} channels"
            ),
            Self::UnstableCoefficients => {
                write!(formatter, "biquad coefficients were non-finite or unstable")
            }
        }
    }
}

impl std::error::Error for DspError {}
