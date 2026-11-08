//! Conversion from a validated portable preset to a validated DSP configuration.
//!
//! The adapter is the single bridge between the portable `.uam-preset.json`
//! schema and the DSP configuration engine. It exists so preset import and live
//! DSP construction share one code path and one authority for validation:
//! [`DspConfig::new`] (which runs [`DspConfig::validate`]).
//!
//! Guarantees:
//!
//! - The preset is validated first, so invalid portable data is rejected with a
//!   [`PresetError`] before any DSP value exists.
//! - Band order, frequency, gain, Q, and filter type are preserved exactly.
//! - [`Preset::audio`]`preamp_db` becomes the configuration preamp unchanged.
//! - The limiter is **not** invented: the preset schema has no limiter field,
//!   so the resulting configuration carries no limiter and the DSP default
//!   (disabled) applies downstream.
//! - Bypass is not invented either: the schema has no bypass field, so the
//!   configuration is un-bypassed.
//! - No second set of numeric bounds is defined here; the DSP layer is the
//!   final authority, including the sample-rate-dependent frequency limit.
//!
//! The adapter is independent of Flutter and the C ABI.

use core::fmt;

use uam_domain::AudioConfig;
use uam_dsp::{BandConfig, DspConfig, DspError};

use crate::schema::Preset;
use crate::validation::PresetError;

/// Failure converting a portable preset into a DSP configuration.
#[derive(Debug, Clone, PartialEq)]
pub enum PresetConversionError {
    /// The preset failed portable-schema validation before conversion.
    InvalidPreset(PresetError),
    /// The converted configuration was rejected by the DSP layer.
    ///
    /// This is where sample-rate-dependent rules (for example a band above the
    /// usable maximum for the supplied [`AudioConfig`]) are enforced.
    Dsp(DspError),
}

impl fmt::Display for PresetConversionError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPreset(error) => write!(formatter, "preset is invalid: {error}"),
            Self::Dsp(error) => write!(
                formatter,
                "preset produces an invalid DSP configuration: {error}"
            ),
        }
    }
}

impl std::error::Error for PresetConversionError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::InvalidPreset(error) => Some(error),
            Self::Dsp(error) => Some(error),
        }
    }
}

impl From<PresetError> for PresetConversionError {
    fn from(error: PresetError) -> Self {
        Self::InvalidPreset(error)
    }
}

impl From<DspError> for PresetConversionError {
    fn from(error: DspError) -> Self {
        Self::Dsp(error)
    }
}

impl Preset {
    /// Convert this preset into a validated [`DspConfig`] for `audio_config`.
    ///
    /// The preset does not carry a sample rate or channel layout, so the target
    /// [`AudioConfig`] is supplied by the caller. The DSP configuration is
    /// validated by [`DspConfig::new`], which is the single numeric authority
    /// for the DSP layer.
    ///
    /// # Errors
    ///
    /// Returns [`PresetConversionError::InvalidPreset`] when the preset itself
    /// is invalid, or [`PresetConversionError::Dsp`] when the converted
    /// configuration violates a DSP rule (for example a band frequency above
    /// the usable maximum for `audio_config`).
    pub fn to_dsp_config(
        &self,
        audio_config: AudioConfig,
    ) -> Result<DspConfig, PresetConversionError> {
        self.validate()?;

        let bands: Vec<BandConfig> = self
            .audio
            .equalizer
            .bands
            .iter()
            .map(|band| BandConfig {
                kind: band.filter_type.into(),
                frequency_hz: band.frequency_hz,
                gain_db: band.gain_db,
                q: band.q,
            })
            .collect();

        // `DspConfig::new` validates every field, including the
        // sample-rate-dependent band frequency bound, so this is the final
        // authority. No limiter or bypass is attached because the schema has
        // no such fields.
        let config = DspConfig::new(audio_config, self.audio.preamp_db, bands)?;
        Ok(config)
    }
}
