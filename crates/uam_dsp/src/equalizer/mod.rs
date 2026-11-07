//! Equalizer chain: preamp followed by a cascade of biquad sections.
//!
//! The chain owns one independent filter state per band and channel. All
//! allocation happens in [`Equalizer::new`]. The processing method performs
//! bounded arithmetic only and is suitable for a future real-time callback,
//! although Phase 0 does not connect it to an operating-system audio device.
//!
//! Phase 0 parameter changes are applied by constructing a replacement chain
//! off the audio thread. A lock-free parameter hand-off is deferred to the
//! phase that introduces a real audio backend.

use uam_domain::AudioConfig;

use crate::filters::{BandConfig, Biquad, BiquadCoefficients};
use crate::validation::{DspError, MAX_BANDS, MAX_PREAMP_DB, MIN_PREAMP_DB};

/// Preamp plus cascaded biquad equalizer with per-channel state.
#[derive(Debug, Clone)]
pub struct Equalizer {
    sample_rate_hz: u32,
    channels: u16,
    bands: Vec<BandConfig>,
    filters: Vec<Biquad>,
    preamp_db: f64,
    preamp_linear: f64,
    bypassed: bool,
}

impl Equalizer {
    /// Build a processing chain for a validated configuration.
    ///
    /// # Errors
    ///
    /// Returns [`DspError`] when the band count or any parameter is invalid, or
    /// when a band cannot be realised at the configured sample rate.
    pub fn new(
        config: AudioConfig,
        bands: &[BandConfig],
        preamp_db: f64,
    ) -> Result<Self, DspError> {
        if bands.len() > MAX_BANDS {
            return Err(DspError::TooManyBands {
                supplied: bands.len(),
                maximum: MAX_BANDS,
            });
        }
        if !preamp_db.is_finite() {
            return Err(DspError::NonFiniteParameter("preampDb"));
        }
        if !(MIN_PREAMP_DB..=MAX_PREAMP_DB).contains(&preamp_db) {
            return Err(DspError::PreampOutOfRange { gain_db: preamp_db });
        }

        let channels = config.channels();
        let mut filters = Vec::with_capacity(bands.len() * usize::from(channels));
        for band in bands {
            let coefficients = BiquadCoefficients::from_band(*band, config)?;
            for _ in 0..channels {
                filters.push(Biquad::new(coefficients));
            }
        }

        Ok(Self {
            sample_rate_hz: config.sample_rate_hz(),
            channels,
            bands: bands.to_vec(),
            filters,
            preamp_db,
            preamp_linear: 10.0_f64.powf(preamp_db / 20.0),
            bypassed: false,
        })
    }

    /// Sample rate used to derive the current coefficients.
    #[must_use]
    pub const fn sample_rate_hz(&self) -> u32 {
        self.sample_rate_hz
    }

    /// Number of interleaved channels expected by [`Self::process_interleaved`].
    #[must_use]
    pub const fn channels(&self) -> u16 {
        self.channels
    }

    /// Number of configured EQ bands.
    #[must_use]
    pub fn band_count(&self) -> usize {
        self.bands.len()
    }

    /// Configured preamp gain in decibels.
    #[must_use]
    pub const fn preamp_db(&self) -> f64 {
        self.preamp_db
    }

    /// Whether the chain is currently bypassed.
    #[must_use]
    pub const fn is_bypassed(&self) -> bool {
        self.bypassed
    }

    /// Set bypass. Filter memory is cleared on every transition to avoid
    /// replaying stale state; Phase 0 does not perform a click-free crossfade.
    pub fn set_bypassed(&mut self, bypassed: bool) {
        if self.bypassed != bypassed {
            self.reset();
        }
        self.bypassed = bypassed;
    }

    /// Clear all filter memory.
    pub fn reset(&mut self) {
        for filter in &mut self.filters {
            filter.reset();
        }
    }

    /// Process an interleaved `f64` buffer in place.
    ///
    /// # Errors
    ///
    /// Returns [`DspError::InvalidBlockLength`] when the buffer is not a whole
    /// number of frames for the configured channel count. No samples are
    /// modified in that case.
    pub fn process_interleaved(&mut self, samples: &mut [f64]) -> Result<(), DspError> {
        let channels = usize::from(self.channels);
        if samples.len() % channels != 0 {
            return Err(DspError::InvalidBlockLength {
                samples: samples.len(),
                channels: self.channels,
            });
        }
        if self.bypassed || (self.bands.is_empty() && self.preamp_db == 0.0) {
            return Ok(());
        }

        for frame in samples.chunks_exact_mut(channels) {
            for (channel, sample) in frame.iter_mut().enumerate() {
                let mut value = *sample * self.preamp_linear;
                for (band_index, _) in self.bands.iter().enumerate() {
                    let filter_index = band_index * channels + channel;
                    value = self.filters[filter_index].process(value);
                }
                *sample = value;
            }
        }
        Ok(())
    }

    /// Combined magnitude response in decibels at one frequency.
    ///
    /// This includes preamp gain unless the chain is bypassed.
    #[must_use]
    pub fn frequency_response_db(&self, frequency_hz: f64) -> f64 {
        if self.bypassed {
            return 0.0;
        }
        self.preamp_db
            + self
                .bands
                .iter()
                .map(|band| {
                    BiquadCoefficients::from_band(*band, self.audio_config()).map_or(
                        f64::NEG_INFINITY,
                        |coefficients| {
                            coefficients.magnitude_db_at(frequency_hz, self.sample_rate_hz)
                        },
                    )
                })
                .sum::<f64>()
    }

    /// Fixed processing latency in samples. A minimum-phase IIR cascade has no
    /// added buffering latency; the audio backend's buffer latency is separate.
    #[must_use]
    pub const fn latency_samples(&self) -> u32 {
        0
    }

    fn audio_config(&self) -> AudioConfig {
        AudioConfig::new(self.sample_rate_hz, self.channels)
            .expect("Equalizer only stores a previously validated configuration")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::FilterKind;

    #[test]
    fn rejects_incomplete_stereo_frame() {
        let config = AudioConfig::new(48_000, 2).expect("valid configuration");
        let mut equalizer = Equalizer::new(config, &[], 0.0).expect("valid chain");
        let mut samples = [0.0; 3];
        assert_eq!(
            equalizer.process_interleaved(&mut samples),
            Err(DspError::InvalidBlockLength {
                samples: 3,
                channels: 2
            })
        );
    }

    #[test]
    fn zero_band_zero_preamp_is_bit_exact() {
        let config = AudioConfig::new(48_000, 2).expect("valid configuration");
        let mut equalizer = Equalizer::new(config, &[], 0.0).expect("valid chain");
        let mut samples = [0.1, -0.2, 0.3, -0.4];
        let original = samples;
        equalizer
            .process_interleaved(&mut samples)
            .expect("valid buffer");
        assert_eq!(samples, original);
    }

    #[test]
    fn bypass_is_bit_exact_even_with_active_bands() {
        let config = AudioConfig::new(48_000, 2).expect("valid configuration");
        let band = BandConfig::new(FilterKind::Peaking, 1_000.0, 6.0, 1.0).expect("valid band");
        let mut equalizer = Equalizer::new(config, &[band], 3.0).expect("valid equalizer");
        equalizer.set_bypassed(true);
        let mut samples = [0.1, -0.2, 0.3, -0.4];
        let original = samples;
        equalizer
            .process_interleaved(&mut samples)
            .expect("valid buffer");
        assert_eq!(samples, original);
    }
}
