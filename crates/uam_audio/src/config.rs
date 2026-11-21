//! Cross-platform configuration and status types for the audio engine.
//!
//! Nothing in this module depends on a platform API. It is the vocabulary the
//! engine, the FFI layer, and the tests share.

use serde::{Deserialize, Serialize};
use uam_domain::SampleFormat;
use uam_dsp::{BandConfig, DspConfig, FilterKind, LimiterConfig};

use crate::error::{AudioError, AudioErrorCode};

/// Default diagnostic test-tone frequency in hertz.
pub const DEFAULT_TONE_FREQUENCY_HZ: f64 = 1_000.0;
/// Default diagnostic test-tone level in dBFS (deliberately conservative).
pub const DEFAULT_TONE_LEVEL_DB: f64 = -20.0;
/// Lowest accepted test-tone frequency in hertz.
pub const MIN_TONE_FREQUENCY_HZ: f64 = 20.0;
/// Highest accepted test-tone frequency in hertz.
pub const MAX_TONE_FREQUENCY_HZ: f64 = 20_000.0;
/// Lowest accepted test-tone level in dBFS.
pub const MIN_TONE_LEVEL_DB: f64 = -60.0;
/// Highest accepted test-tone level in dBFS.
pub const MAX_TONE_LEVEL_DB: f64 = -3.0;

/// Sample encoding of an endpoint's interleaved buffer.
///
/// This is the *external boundary* encoding. The DSP host always processes
/// `f64`; the backend converts at the boundary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum SampleEncoding {
    /// 32-bit IEEE-754 floating point.
    F32,
    /// Signed 16-bit integer PCM.
    S16,
    /// Signed 24-bit integer PCM, packed into three bytes.
    S24,
    /// Signed 32-bit integer PCM.
    S32,
}

impl SampleEncoding {
    /// Stable identifier used in diagnostics.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::F32 => "f32",
            Self::S16 => "s16",
            Self::S24 => "s24",
            Self::S32 => "s32",
        }
    }

    /// Container size in bytes for this encoding.
    #[must_use]
    pub const fn bytes_per_sample(self) -> u32 {
        match self {
            Self::F32 => 4,
            Self::S16 => 2,
            Self::S24 => 3,
            Self::S32 => 4,
        }
    }

    /// Whether this encoding is an IEEE float encoding.
    #[must_use]
    pub const fn is_float(self) -> bool {
        matches!(self, Self::F32)
    }
}

/// A validated description of an endpoint's interleaved stream format.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StreamFormat {
    sample_rate_hz: u32,
    channels: u16,
    encoding: SampleEncoding,
    /// Bits occupied by one sample in the container (`8 * bytes_per_sample`
    /// unless the container is padded, e.g. 24 valid bits in a 32-bit word).
    container_bits: u16,
    /// Bits that carry the sample value.
    valid_bits: u16,
}

impl StreamFormat {
    /// Build and validate a stream format description.
    ///
    /// # Errors
    ///
    /// Returns [`AudioErrorCode::UnsupportedFormat`] for a zero sample rate, an
    /// implausible channel count, or container/valid-bit combinations this
    /// backend cannot encode.
    pub fn new(
        sample_rate_hz: u32,
        channels: u16,
        encoding: SampleEncoding,
        container_bits: u16,
        valid_bits: u16,
    ) -> Result<Self, AudioError> {
        if sample_rate_hz == 0 || channels == 0 || channels > 32 {
            return Err(AudioError::new(
                AudioErrorCode::UnsupportedFormat,
                format!(
                    "endpoint reported {sample_rate_hz} Hz and {channels} channels, \
                     which is not a usable stream format"
                ),
            ));
        }
        let valid_bits = if valid_bits == 0 {
            container_bits
        } else {
            valid_bits
        };
        if encoding.is_float() {
            if container_bits != 32 {
                return Err(AudioError::new(
                    AudioErrorCode::UnsupportedFormat,
                    format!("IEEE float containers must be 32 bits, got {container_bits}"),
                ));
            }
        } else {
            let supported = matches!(container_bits, 16 | 24 | 32);
            if !supported || valid_bits == 0 || valid_bits > container_bits {
                return Err(AudioError::new(
                    AudioErrorCode::UnsupportedFormat,
                    format!(
                        "integer containers must be 16, 24, or 32 bits with valid bits \
                         within the container, got {valid_bits} valid of {container_bits}"
                    ),
                ));
            }
        }
        Ok(Self {
            sample_rate_hz,
            channels,
            encoding,
            container_bits,
            valid_bits,
        })
    }

    /// Sample rate in hertz.
    #[must_use]
    pub const fn sample_rate_hz(&self) -> u32 {
        self.sample_rate_hz
    }

    /// Interleaved channel count.
    #[must_use]
    pub const fn channels(&self) -> u16 {
        self.channels
    }

    /// Boundary sample encoding.
    #[must_use]
    pub const fn encoding(&self) -> SampleEncoding {
        self.encoding
    }

    /// Container size in bits.
    #[must_use]
    pub const fn container_bits(&self) -> u16 {
        self.container_bits
    }

    /// Number of bits that carry the sample value.
    #[must_use]
    pub const fn valid_bits(&self) -> u16 {
        self.valid_bits
    }

    /// Bytes for one interleaved frame.
    #[must_use]
    pub const fn frame_bytes(&self) -> usize {
        self.encoding.bytes_per_sample() as usize * self.channels as usize
    }

    /// Bytes for `frames` interleaved frames.
    #[must_use]
    pub const fn buffer_bytes(&self, frames: usize) -> usize {
        self.frame_bytes() * frames
    }

    /// Bytes for one sample.
    #[must_use]
    pub const fn sample_bytes(&self) -> usize {
        self.encoding.bytes_per_sample() as usize
    }

    /// The domain boundary format recorded for this stream.
    #[must_use]
    pub const fn boundary_format(&self) -> SampleFormat {
        match self.encoding {
            SampleEncoding::F32 => SampleFormat::F32,
            _ => SampleFormat::F64,
        }
    }

    /// Short human-readable summary for diagnostics.
    #[must_use]
    pub fn summary(&self) -> String {
        format!(
            "{} Hz / {} ch / {} ({} valid of {} bits)",
            self.sample_rate_hz,
            self.channels,
            self.encoding.as_str(),
            self.valid_bits,
            self.container_bits,
        )
    }
}

/// Audio processing scope, mirrored from the architecture contract.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioScope {
    /// UAM processes audio that UAM itself generates.
    AppOwnedStream,
    /// UAM processes a supported selected stream.
    SelectedStream,
    /// UAM processes system output through a supported integration.
    SystemOutput,
    /// UAM edits configuration but is not attached to a processing path.
    ConfigurationOnly,
}

impl AudioScope {
    /// `app_owned_stream` when the backend is attached, otherwise
    /// `configuration_only`.
    #[must_use]
    pub const fn for_attachment(attached: bool) -> Self {
        if attached {
            Self::AppOwnedStream
        } else {
            Self::ConfigurationOnly
        }
    }

    /// Stable wire identifier.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::AppOwnedStream => "app_owned_stream",
            Self::SelectedStream => "selected_stream",
            Self::SystemOutput => "system_output",
            Self::ConfigurationOnly => "configuration_only",
        }
    }
}

/// Audio engine lifecycle state.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EngineState {
    /// Never initialized or explicitly shut down.
    Stopped,
    /// Resolving the selected endpoint and its format.
    Initializing,
    /// Endpoint and format resolved; a stream can be started.
    Ready,
    /// A stream is being opened.
    Starting,
    /// A stream is producing audio.
    Running,
    /// A stream is being stopped.
    Stopping,
    /// The active endpoint was lost and recovery is pending.
    Recovering,
    /// The engine hit an unrecoverable error.
    Failed,
}

impl EngineState {
    /// Stable wire identifier.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Stopped => "stopped",
            Self::Initializing => "initializing",
            Self::Ready => "ready",
            Self::Starting => "starting",
            Self::Running => "running",
            Self::Stopping => "stopping",
            Self::Recovering => "recovering",
            Self::Failed => "failed",
        }
    }
}

/// One EQ band as sent by the control path.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EqBandDto {
    /// Filter shape.
    pub filter_type: EqFilterTypeDto,
    /// Centre or corner frequency in hertz.
    pub frequency_hz: f64,
    /// Gain in decibels.
    pub gain_db: f64,
    /// Quality factor.
    pub q: f64,
}

/// Editable filter shapes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EqFilterTypeDto {
    /// Peaking bell filter.
    Peaking,
    /// Low shelf.
    LowShelf,
    /// High shelf.
    HighShelf,
}

impl From<EqFilterTypeDto> for FilterKind {
    fn from(value: EqFilterTypeDto) -> Self {
        match value {
            EqFilterTypeDto::Peaking => Self::Peaking,
            EqFilterTypeDto::LowShelf => Self::LowShelf,
            EqFilterTypeDto::HighShelf => Self::HighShelf,
        }
    }
}

/// Limiter parameters as sent by the control path.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimiterDto {
    /// Whether the limiter is enabled.
    pub enabled: bool,
    /// Ceiling in dBFS.
    pub ceiling_db: f64,
    /// Release time in milliseconds.
    pub release_ms: f64,
}

/// A complete DSP configuration request from the control path.
///
/// The audio boundary configuration is deliberately absent: the engine owns the
/// active stream's sample rate and channel count, and rejects a request whose
/// bands cannot be realised at that rate.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DspRequest {
    /// Preamp gain in decibels.
    pub preamp_db: f64,
    /// Ordered EQ bands.
    pub bands: Vec<EqBandDto>,
    /// Whether processing is bypassed.
    #[serde(default)]
    pub bypassed: bool,
    /// Optional limiter parameters.
    #[serde(default)]
    pub limiter: Option<LimiterDto>,
}

impl DspRequest {
    /// A flat configuration with no processing.
    #[must_use]
    pub fn neutral() -> Self {
        Self {
            preamp_db: 0.0,
            bands: Vec::new(),
            bypassed: false,
            limiter: None,
        }
    }

    /// Resolve the request into a validated [`DspConfig`] for a stream.
    ///
    /// # Errors
    ///
    /// Returns [`AudioErrorCode::Configuration`] when any value is invalid or a
    /// band cannot be realised at the stream's sample rate.
    pub fn to_dsp_config(
        &self,
        sample_rate_hz: u32,
        channels: u16,
    ) -> Result<DspConfig, AudioError> {
        let audio = uam_domain::AudioConfig::with_format(
            sample_rate_hz,
            channels,
            uam_domain::INTERNAL_PROCESSING_FORMAT,
        )?;
        let mut bands = Vec::with_capacity(self.bands.len());
        for band in &self.bands {
            let resolved = BandConfig::new(
                band.filter_type.into(),
                band.frequency_hz,
                band.gain_db,
                band.q,
            )
            .map_err(|error| AudioError::new(AudioErrorCode::Configuration, error.to_string()))?;
            bands.push(resolved);
        }
        let mut config = DspConfig::new(audio, self.preamp_db, bands)
            .map_err(|error| AudioError::new(AudioErrorCode::Configuration, error.to_string()))?;
        if let Some(limiter) = self.limiter {
            let limiter =
                LimiterConfig::new(limiter.enabled, limiter.ceiling_db, limiter.release_ms)
                    .map_err(|error| {
                        AudioError::new(AudioErrorCode::Configuration, error.to_string())
                    })?;
            config = config.with_limiter(limiter);
        }
        config = config.with_bypassed(self.bypassed);
        config
            .validate()
            .map_err(|error| AudioError::new(AudioErrorCode::Configuration, error.to_string()))?;
        Ok(config)
    }
}

/// Diagnostic test-tone request. The tone is opt-in and never starts
/// automatically.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TestToneConfig {
    /// Sine frequency in hertz.
    pub frequency_hz: f64,
    /// Level in dBFS.
    pub level_db: f64,
}

impl Default for TestToneConfig {
    fn default() -> Self {
        Self {
            frequency_hz: DEFAULT_TONE_FREQUENCY_HZ,
            level_db: DEFAULT_TONE_LEVEL_DB,
        }
    }
}

impl TestToneConfig {
    /// Validate frequency and level bounds.
    ///
    /// # Errors
    ///
    /// Returns [`AudioErrorCode::Configuration`] for a non-finite or
    /// out-of-range value.
    pub fn validate(&self) -> Result<(), AudioError> {
        if !self.frequency_hz.is_finite()
            || !(MIN_TONE_FREQUENCY_HZ..=MAX_TONE_FREQUENCY_HZ).contains(&self.frequency_hz)
        {
            return Err(AudioError::new(
                AudioErrorCode::Configuration,
                format!(
                    "test-tone frequency must be within {MIN_TONE_FREQUENCY_HZ}..={MAX_TONE_FREQUENCY_HZ} Hz"
                ),
            ));
        }
        if !self.level_db.is_finite()
            || !(MIN_TONE_LEVEL_DB..=MAX_TONE_LEVEL_DB).contains(&self.level_db)
        {
            return Err(AudioError::new(
                AudioErrorCode::Configuration,
                format!(
                    "test-tone level must be within {MIN_TONE_LEVEL_DB}..={MAX_TONE_LEVEL_DB} dBFS"
                ),
            ));
        }
        Ok(())
    }

    /// Linear amplitude for [`TestToneConfig::level_db`].
    #[must_use]
    pub fn amplitude(&self) -> f64 {
        10.0_f64.powf(self.level_db / 20.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stream_format_validates_float_and_integer_containers() {
        assert!(StreamFormat::new(48_000, 2, SampleEncoding::F32, 32, 32).is_ok());
        assert!(StreamFormat::new(48_000, 2, SampleEncoding::S16, 16, 16).is_ok());
        assert!(StreamFormat::new(48_000, 2, SampleEncoding::S24, 24, 24).is_ok());
        assert!(StreamFormat::new(48_000, 2, SampleEncoding::S32, 32, 24).is_ok());
        assert!(StreamFormat::new(48_000, 2, SampleEncoding::F32, 16, 16).is_err());
        assert!(StreamFormat::new(48_000, 2, SampleEncoding::S16, 20, 20).is_err());
        assert!(StreamFormat::new(0, 2, SampleEncoding::F32, 32, 32).is_err());
        assert!(StreamFormat::new(48_000, 0, SampleEncoding::F32, 32, 32).is_err());
    }

    #[test]
    fn stream_format_reports_frame_sizes() {
        let format = StreamFormat::new(48_000, 2, SampleEncoding::S24, 24, 24).unwrap();
        assert_eq!(format.frame_bytes(), 6);
        assert_eq!(format.buffer_bytes(128), 768);
        assert_eq!(format.sample_bytes(), 3);
    }

    #[test]
    fn dsp_request_builds_a_validated_config() {
        let request = DspRequest {
            preamp_db: 3.0,
            bands: vec![EqBandDto {
                filter_type: EqFilterTypeDto::Peaking,
                frequency_hz: 1_000.0,
                gain_db: 6.0,
                q: 1.0,
            }],
            bypassed: false,
            limiter: Some(LimiterDto {
                enabled: true,
                ceiling_db: -1.0,
                release_ms: 100.0,
            }),
        };
        let config = request.to_dsp_config(48_000, 2).expect("valid config");
        assert_eq!(config.band_count(), 1);
        assert!(config.limiter().is_some());
        assert!(!config.bypassed());
    }

    #[test]
    fn dsp_request_rejects_out_of_range_band() {
        let request = DspRequest {
            preamp_db: 0.0,
            bands: vec![EqBandDto {
                filter_type: EqFilterTypeDto::Peaking,
                frequency_hz: 1_000.0,
                gain_db: 99.0,
                q: 1.0,
            }],
            bypassed: false,
            limiter: None,
        };
        let error = request.to_dsp_config(48_000, 2).unwrap_err();
        assert_eq!(error.code, AudioErrorCode::Configuration);
    }

    #[test]
    fn test_tone_bounds_are_enforced() {
        assert!(TestToneConfig::default().validate().is_ok());
        assert!(TestToneConfig {
            frequency_hz: 5.0,
            level_db: -20.0,
        }
        .validate()
        .is_err());
        assert!(TestToneConfig {
            frequency_hz: 1_000.0,
            level_db: 0.0,
        }
        .validate()
        .is_err());
    }
}
