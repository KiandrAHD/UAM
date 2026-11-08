//! Fixed processing pipeline: preamp + equalizer -> limiter -> metering.
//!
//! # Processing order
//!
//! ```text
//! input (interleaved f64)
//!   -> input validation (whole frames)
//!   -> input peak meter        (pre-processing level)
//!   -> preamp + EQ cascade     (Equalizer)
//!   -> pre-limiter peak meter  (clipping before limiting)
//!   -> limiter                 (gain reduction)
//!   -> output peak meter       (post-limiter level)
//!   -> output
//! ```
//!
//! The pipeline owns the three components and drives them; each component is
//! also usable and testable on its own. Nothing here depends on a platform
//! audio backend, and the components hold no shared mutable state across
//! threads.
//!
//! The equalizer already includes the preamp stage, so preamp and EQ share one
//! traversal of the buffer. Bypass applies to the equalizer (preamp + bands)
//! only; the limiter is independent, so a caller can A/B the EQ with limiting
//! active or inactive.
//!
//! # Allocation
//!
//! [`DspPipeline::from_config`] and [`DspPipeline::apply_config`] allocate (the
//! equalizer builds per-band, per-channel state). Once built,
//! [`DspPipeline::process_interleaved`] allocates nothing, takes no lock, and
//! performs no I/O.

use uam_domain::AudioConfig;

use crate::config::DspConfig;
use crate::equalizer::Equalizer;
use crate::limiter::Limiter;
use crate::meter::{BlockPeak, PeakMeter};
use crate::validation::DspError;

/// Per-block measurement returned by [`DspPipeline::process_interleaved`].
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PipelineReport {
    input: BlockPeak,
    pre_limiter: BlockPeak,
    output: BlockPeak,
    gain_reduction_db: f64,
    limiter_active: bool,
}

impl PipelineReport {
    /// Peak measurement of the raw input before any processing.
    #[must_use]
    pub const fn input(&self) -> BlockPeak {
        self.input
    }

    /// Peak measurement after preamp/EQ and before the limiter.
    ///
    /// Use [`BlockPeak::clipping_detected`] on this value to see whether the
    /// signal would clip *without* the limiter.
    #[must_use]
    pub const fn pre_limiter(&self) -> BlockPeak {
        self.pre_limiter
    }

    /// Peak measurement after the limiter.
    #[must_use]
    pub const fn output(&self) -> BlockPeak {
        self.output
    }

    /// Maximum gain reduction the limiter applied in this block, in dB.
    #[must_use]
    pub const fn gain_reduction_db(&self) -> f64 {
        self.gain_reduction_db
    }

    /// Whether the limiter acted on this block.
    #[must_use]
    pub const fn limiter_active(&self) -> bool {
        self.limiter_active
    }

    /// Number of frames measured.
    #[must_use]
    pub const fn frames(&self) -> usize {
        self.output.frames()
    }
}

/// Preamp + equalizer + limiter + peak metering for one audio stream.
#[derive(Debug, Clone)]
pub struct DspPipeline {
    audio: AudioConfig,
    equalizer: Equalizer,
    limiter: Limiter,
    input_meter: PeakMeter,
    pre_limiter_meter: PeakMeter,
    output_meter: PeakMeter,
}

impl DspPipeline {
    /// Build a pipeline from a validated [`DspConfig`].
    ///
    /// When the configuration carries no limiter, a disabled limiter is used,
    /// so the pipeline output matches an equalizer-only chain bit for bit.
    ///
    /// # Errors
    ///
    /// Returns [`DspError`] when [`DspConfig::validate`] fails or a band cannot
    /// be realised at the configured sample rate.
    pub fn from_config(config: &DspConfig) -> Result<Self, DspError> {
        config.validate()?;
        let audio = config.audio();
        let equalizer = Equalizer::from_config(config)?;
        let limiter_config = config.limiter().unwrap_or_default();
        let limiter = Limiter::new(&limiter_config, audio)?;

        Ok(Self {
            audio,
            equalizer,
            limiter,
            input_meter: meter_for(audio),
            pre_limiter_meter: meter_for(audio),
            output_meter: meter_for(audio),
        })
    }

    /// Replace the pipeline's parameters from a validated [`DspConfig`].
    ///
    /// This is a **control-thread** operation and allocates for the equalizer
    /// replacement. It must not be called from a real-time audio callback.
    ///
    /// # Errors
    ///
    /// Returns [`DspError`] when validation fails, when the audio
    /// configuration does not match this pipeline, or when a band cannot be
    /// realised. A rejected update leaves the pipeline untouched.
    pub fn apply_config(&mut self, config: &DspConfig) -> Result<(), DspError> {
        config.validate()?;
        // The equalizer enforces the sample-rate / channel guard and prepares
        // its replacement before committing, so a rejection here leaves both
        // the equalizer and the limiter unchanged.
        self.equalizer.apply_config(config)?;
        let limiter_config = config.limiter().unwrap_or_default();
        self.limiter = Limiter::new(&limiter_config, self.audio)?;
        Ok(())
    }

    /// Audio boundary configuration this pipeline targets.
    #[must_use]
    pub const fn audio(&self) -> AudioConfig {
        self.audio
    }

    /// Number of interleaved channels.
    #[must_use]
    pub const fn channels(&self) -> u16 {
        self.audio.channels()
    }

    /// Sample rate in hertz.
    #[must_use]
    pub const fn sample_rate_hz(&self) -> u32 {
        self.audio.sample_rate_hz()
    }

    /// The equalizer stage.
    #[must_use]
    pub const fn equalizer(&self) -> &Equalizer {
        &self.equalizer
    }

    /// Mutable access to the equalizer stage.
    pub fn equalizer_mut(&mut self) -> &mut Equalizer {
        &mut self.equalizer
    }

    /// The limiter stage.
    #[must_use]
    pub const fn limiter(&self) -> &Limiter {
        &self.limiter
    }

    /// Mutable access to the limiter stage.
    pub fn limiter_mut(&mut self) -> &mut Limiter {
        &mut self.limiter
    }

    /// Meter measuring the raw input.
    #[must_use]
    pub const fn input_meter(&self) -> &PeakMeter {
        &self.input_meter
    }

    /// Meter measuring the signal after preamp/EQ, before the limiter.
    #[must_use]
    pub const fn pre_limiter_meter(&self) -> &PeakMeter {
        &self.pre_limiter_meter
    }

    /// Meter measuring the final output.
    #[must_use]
    pub const fn output_meter(&self) -> &PeakMeter {
        &self.output_meter
    }

    /// Mutable access to the final output meter.
    pub fn output_meter_mut(&mut self) -> &mut PeakMeter {
        &mut self.output_meter
    }

    /// Clear equalizer memory, limiter gain, and all meter state.
    pub fn reset(&mut self) {
        self.equalizer.reset();
        self.limiter.reset();
        self.input_meter.reset();
        self.pre_limiter_meter.reset();
        self.output_meter.reset();
    }

    /// Process an interleaved `f64` buffer in place and return the block report.
    ///
    /// # Errors
    ///
    /// Returns [`DspError::InvalidBlockLength`] when the buffer is not a whole
    /// number of frames. No samples are modified in that case.
    pub fn process_interleaved(&mut self, samples: &mut [f64]) -> Result<PipelineReport, DspError> {
        let channels = usize::from(self.channels());
        if samples.len() % channels != 0 {
            return Err(DspError::InvalidBlockLength {
                samples: samples.len(),
                channels: self.channels(),
            });
        }

        let input = measure(&mut self.input_meter, samples);
        self.equalizer.process_interleaved(samples)?;
        let pre_limiter = measure(&mut self.pre_limiter_meter, samples);
        self.limiter.process_interleaved(samples)?;
        let output = measure(&mut self.output_meter, samples);

        Ok(PipelineReport {
            input,
            pre_limiter,
            output,
            gain_reduction_db: self.limiter.last_block_max_reduction_db(),
            limiter_active: self.limiter.is_enabled(),
        })
    }
}

/// Build a meter for a validated audio configuration.
fn meter_for(audio: AudioConfig) -> PeakMeter {
    PeakMeter::new(audio.channels()).expect("validated audio configuration has 1 or 2 channels")
}

/// Measure a block, treating an impossible meter error as an invariant break.
fn measure(meter: &mut PeakMeter, samples: &[f64]) -> BlockPeak {
    meter
        .process_interleaved(samples)
        .expect("block length was validated before processing")
}
