//! Validated DSP configuration DTO.
//!
//! [`DspConfig`] is the single validated description of an equalizer chain. It
//! carries the audio boundary configuration, the preamp gain, the ordered EQ
//! band list, the bypass state, and optional limiter metadata. It is a
//! plain-in-memory description: it is not serialized and crosses no FFI
//! boundary in Phase 2, so adding serde to it is deferred with the FFI symbols.
//!
//! # Value ranges
//!
//! Every numeric bound lives in [`crate::validation`] and is enforced by
//! [`DspConfig::validate`] and the type-level constructors below.
//!
//! | Field | Range / rule | Constant |
//! |---|---|---|
//! | `preamp_db` | `-24.0 ..= +12.0` dB | `MIN_PREAMP_DB` / `MAX_PREAMP_DB` |
//! | `bands.len()` | `0 ..= 32` | `MAX_BANDS` |
//! | band `frequency_hz` | `10.0 ..= 20_000.0` Hz, and `<=` the sample rate's usable maximum (`0.95 × Nyquist`) | `MIN_FREQUENCY_HZ` / `MAX_FREQUENCY_HZ` |
//! | band `gain_db` | `-24.0 ..= +24.0` dB | `MIN_GAIN_DB` / `MAX_GAIN_DB` |
//! | band `q` | `0.1 ..= 10.0` | `MIN_Q` / `MAX_Q` |
//! | `limiter.ceiling_db` | `-12.0 ..= 0.0` dBFS | `MIN_LIMITER_CEILING_DB` / `MAX_LIMITER_CEILING_DB` |
//! | `limiter.release_ms` | `10.0 ..= 1_000.0` ms | `MIN_LIMITER_RELEASE_MS` / `MAX_LIMITER_RELEASE_MS` |
//!
//! All numeric parameters must be finite; `NaN` and infinity are rejected.
//!
//! # Limiter scope
//!
//! [`LimiterConfig`] is a **validated description** of a limiter. The
//! signal-processing implementation lives in [`crate::limiter::Limiter`] and is
//! composed into [`crate::pipeline::DspPipeline`]. The [`crate::Equalizer`]
//! itself stays limiter-agnostic: it is the preamp + EQ cascade, and changing
//! that would change its ABI-level behaviour. A configuration that carries no
//! limiter (or a disabled one) therefore produces equalizer-only output.

use uam_domain::AudioConfig;

use crate::filters::BandConfig;
use crate::validation::{
    DspError, MAX_BANDS, MAX_LIMITER_CEILING_DB, MAX_LIMITER_RELEASE_MS, MAX_PREAMP_DB,
    MIN_LIMITER_CEILING_DB, MIN_LIMITER_RELEASE_MS, MIN_PREAMP_DB,
};

/// Validated limiter configuration: enable flag, ceiling, and release time.
///
/// This is the configuration half of the limiter. The processing half is
/// [`crate::limiter::Limiter`], which is driven by a [`crate::pipeline::DspPipeline`].
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LimiterConfig {
    enabled: bool,
    ceiling_db: f64,
    release_ms: f64,
}

impl LimiterConfig {
    /// Create validated limiter metadata.
    ///
    /// # Errors
    ///
    /// Returns [`DspError::NonFiniteParameter`],
    /// [`DspError::LimiterCeilingOutOfRange`], or
    /// [`DspError::LimiterReleaseOutOfRange`] for invalid input.
    pub fn new(enabled: bool, ceiling_db: f64, release_ms: f64) -> Result<Self, DspError> {
        let config = Self {
            enabled,
            ceiling_db,
            release_ms,
        };
        config.validate()?;
        Ok(config)
    }

    /// Re-check the value ranges. Always `Ok` for a value built through
    /// [`LimiterConfig::new`]; provided so a caller can revalidate a
    /// deserialized value in a later milestone.
    ///
    /// # Errors
    ///
    /// Same as [`LimiterConfig::new`].
    pub fn validate(&self) -> Result<(), DspError> {
        if !self.ceiling_db.is_finite() {
            return Err(DspError::NonFiniteParameter("limiterCeilingDb"));
        }
        if !self.release_ms.is_finite() {
            return Err(DspError::NonFiniteParameter("limiterReleaseMs"));
        }
        if !(MIN_LIMITER_CEILING_DB..=MAX_LIMITER_CEILING_DB).contains(&self.ceiling_db) {
            return Err(DspError::LimiterCeilingOutOfRange {
                ceiling_db: self.ceiling_db,
            });
        }
        if !(MIN_LIMITER_RELEASE_MS..=MAX_LIMITER_RELEASE_MS).contains(&self.release_ms) {
            return Err(DspError::LimiterReleaseOutOfRange {
                release_ms: self.release_ms,
            });
        }
        Ok(())
    }

    /// Whether the limiter is requested to act on the signal.
    #[must_use]
    pub const fn enabled(&self) -> bool {
        self.enabled
    }

    /// Requested ceiling in decibels relative to full scale.
    #[must_use]
    pub const fn ceiling_db(&self) -> f64 {
        self.ceiling_db
    }

    /// Requested release time in milliseconds.
    #[must_use]
    pub const fn release_ms(&self) -> f64 {
        self.release_ms
    }
}

impl Default for LimiterConfig {
    /// Disabled limiter at the documented default ceiling and release time.
    fn default() -> Self {
        Self {
            enabled: false,
            ceiling_db: crate::validation::DEFAULT_LIMITER_CEILING_DB,
            release_ms: crate::validation::DEFAULT_LIMITER_RELEASE_MS,
        }
    }
}

/// One validated DSP configuration for a single audio stream.
#[derive(Debug, Clone, PartialEq)]
pub struct DspConfig {
    audio: AudioConfig,
    preamp_db: f64,
    bands: Vec<BandConfig>,
    bypassed: bool,
    limiter: Option<LimiterConfig>,
}

impl DspConfig {
    /// Create a validated configuration.
    ///
    /// The chain starts un-bypassed with no limiter configured. Use
    /// [`DspConfig::with_bypassed`] and [`DspConfig::with_limiter`] to adjust
    /// those before handing the configuration to the engine.
    ///
    /// # Errors
    ///
    /// Returns the first violated rule: too many bands, non-finite or
    /// out-of-range preamp, or an invalid band for the audio configuration.
    pub fn new(
        audio: AudioConfig,
        preamp_db: f64,
        bands: Vec<BandConfig>,
    ) -> Result<Self, DspError> {
        let config = Self {
            audio,
            preamp_db,
            bands,
            bypassed: false,
            limiter: None,
        };
        config.validate()?;
        Ok(config)
    }

    /// Set the bypass state.
    #[must_use]
    pub fn with_bypassed(mut self, bypassed: bool) -> Self {
        self.bypassed = bypassed;
        self
    }

    /// Attach validated limiter metadata.
    #[must_use]
    pub fn with_limiter(mut self, limiter: LimiterConfig) -> Self {
        self.limiter = Some(limiter);
        self
    }

    /// Audio boundary configuration this DSP configuration targets.
    #[must_use]
    pub const fn audio(&self) -> AudioConfig {
        self.audio
    }

    /// Preamp gain in decibels.
    #[must_use]
    pub const fn preamp_db(&self) -> f64 {
        self.preamp_db
    }

    /// Ordered EQ bands.
    #[must_use]
    pub fn bands(&self) -> &[BandConfig] {
        &self.bands
    }

    /// Number of configured EQ bands.
    #[must_use]
    pub fn band_count(&self) -> usize {
        self.bands.len()
    }

    /// Whether processing is bypassed.
    #[must_use]
    pub const fn bypassed(&self) -> bool {
        self.bypassed
    }

    /// Limiter metadata, when configured.
    #[must_use]
    pub const fn limiter(&self) -> Option<LimiterConfig> {
        self.limiter
    }

    /// Validate every field against the documented ranges.
    ///
    /// Bands are validated against the configured sample rate, so this is the
    /// single validation gate for both a fresh configuration and a replacement
    /// applied to a running engine.
    ///
    /// # Errors
    ///
    /// Returns the first violated rule.
    pub fn validate(&self) -> Result<(), DspError> {
        if self.bands.len() > MAX_BANDS {
            return Err(DspError::TooManyBands {
                supplied: self.bands.len(),
                maximum: MAX_BANDS,
            });
        }
        if !self.preamp_db.is_finite() {
            return Err(DspError::NonFiniteParameter("preampDb"));
        }
        if !(MIN_PREAMP_DB..=MAX_PREAMP_DB).contains(&self.preamp_db) {
            return Err(DspError::PreampOutOfRange {
                gain_db: self.preamp_db,
            });
        }
        for band in &self.bands {
            band.validate_for(self.audio)?;
        }
        if let Some(limiter) = self.limiter {
            limiter.validate()?;
        }
        Ok(())
    }
}
