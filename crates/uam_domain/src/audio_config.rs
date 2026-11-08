//! Validated audio stream configuration.
//!
//! Phase 0 supports mono and stereo interleaved `f64` sample buffers. These
//! are deliberately conservative: they cover the initial EQ prototype without
//! implying support for multichannel, integer, or planar formats.
//!
//! # Boundary format versus internal representation
//!
//! An audio stream has two distinct descriptions:
//!
//! - the **external boundary format** — the sample format a future platform
//!   audio backend delivers on input and expects on output. See
//!   [`SampleFormat`]. Phase 2 accepts `f32` (typical shared-mode backend
//!   boundary) and `f64` metadata, but only `f64` samples are ever stored,
//!   passed, or processed.
//! - the **internal DSP representation** — always `f64`
//!   ([`INTERNAL_PROCESSING_FORMAT`]). The Phase 0/2 processing kernel is
//!   `f64` only; there is no native `f32` kernel and none is claimed.
//!
//! When a backend exposes `f32`, the adapter converts to `f64` at the input
//! boundary and back to `f32` at the output boundary. That conversion is not
//! implemented in this crate: [`AudioConfig`] only records the intended
//! boundary format so a later adapter and the diagnostics layer agree on it.

use core::fmt;

/// Lowest sample rate accepted by the Phase 0 core.
pub const MIN_SAMPLE_RATE_HZ: u32 = 8_000;
/// Highest sample rate accepted by the Phase 0 core.
pub const MAX_SAMPLE_RATE_HZ: u32 = 384_000;
/// Phase 0 channels: mono or stereo.
pub const MAX_CHANNELS: u16 = 2;

/// Sample format at the external audio boundary.
///
/// This describes the format a platform audio backend delivers or expects.
/// It does **not** describe the internal DSP representation, which is always
/// [`SampleFormat::F64`] (see [`INTERNAL_PROCESSING_FORMAT`]). Integer and
/// planar formats are intentionally not modelled in Phase 2; a backend that
/// exposes them must convert to `f32` first and record that in diagnostics.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SampleFormat {
    /// 32-bit IEEE-754 floating point. The typical shared-mode backend
    /// boundary format. Requires conversion to `f64` for processing.
    F32,
    /// 64-bit IEEE-754 floating point. The internal DSP representation and
    /// the default boundary format for the Phase 0/2 prototype.
    F64,
}

impl SampleFormat {
    /// Stable identifier used in diagnostics and future preset metadata.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::F32 => "f32",
            Self::F64 => "f64",
        }
    }

    /// Size of one sample of this format in bytes.
    #[must_use]
    pub const fn bytes_per_sample(self) -> u32 {
        match self {
            Self::F32 => 4,
            Self::F64 => 8,
        }
    }

    /// Whether buffers in this format are the internal DSP representation.
    ///
    /// Only [`SampleFormat::F64`] is processed in place by the current DSP
    /// kernel; any other format must be converted at the boundary first.
    #[must_use]
    pub const fn is_internal_processing_format(self) -> bool {
        matches!(self, Self::F64)
    }
}

/// The internal DSP sample representation used by the Phase 0/2 kernel.
///
/// The kernel stores and processes `f64` only. This constant exists so callers
/// and tests can assert the invariant without hard-coding the variant.
pub const INTERNAL_PROCESSING_FORMAT: SampleFormat = SampleFormat::F64;

/// Explicit channel layout for an interleaved sample buffer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ChannelLayout {
    /// One channel.
    Mono,
    /// Two channels in left/right order.
    Stereo,
}

impl ChannelLayout {
    /// Number of channels represented by this layout.
    #[must_use]
    pub const fn channels(self) -> u16 {
        match self {
            Self::Mono => 1,
            Self::Stereo => 2,
        }
    }

    /// Stable identifier used in diagnostics and future preset metadata.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Mono => "mono",
            Self::Stereo => "stereo",
        }
    }

    /// Resolve a layout from an explicit channel count.
    ///
    /// # Errors
    ///
    /// Returns [`AudioConfigError::UnsupportedChannelCount`] for any count
    /// other than one or two.
    pub const fn from_channels(channels: u16) -> Result<Self, AudioConfigError> {
        match channels {
            1 => Ok(Self::Mono),
            2 => Ok(Self::Stereo),
            other => Err(AudioConfigError::UnsupportedChannelCount(other)),
        }
    }
}

/// A validated audio stream configuration.
///
/// The configuration records the sample rate, channel layout, and external
/// boundary sample format. It never changes the internal DSP representation,
/// which is always [`INTERNAL_PROCESSING_FORMAT`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AudioConfig {
    sample_rate_hz: u32,
    channel_layout: ChannelLayout,
    boundary_format: SampleFormat,
}

impl AudioConfig {
    /// Create a configuration after checking the Phase 0 bounds.
    ///
    /// The external boundary format defaults to [`SampleFormat::F64`] so every
    /// pre-Phase-2 caller and test keeps its existing behaviour. Use
    /// [`AudioConfig::with_format`] to record a different boundary format.
    ///
    /// # Errors
    ///
    /// Returns [`AudioConfigError`] when the sample rate is outside
    /// [`MIN_SAMPLE_RATE_HZ`]..=[`MAX_SAMPLE_RATE_HZ`] or the channel count is
    /// not one or two.
    pub fn new(sample_rate_hz: u32, channels: u16) -> Result<Self, AudioConfigError> {
        Self::with_format(sample_rate_hz, channels, SampleFormat::F64)
    }

    /// Create a configuration with an explicit external boundary format.
    ///
    /// # Errors
    ///
    /// Same as [`AudioConfig::new`]. The boundary format is descriptive only
    /// and is never rejected here.
    pub fn with_format(
        sample_rate_hz: u32,
        channels: u16,
        boundary_format: SampleFormat,
    ) -> Result<Self, AudioConfigError> {
        if !(MIN_SAMPLE_RATE_HZ..=MAX_SAMPLE_RATE_HZ).contains(&sample_rate_hz) {
            return Err(AudioConfigError::UnsupportedSampleRate(sample_rate_hz));
        }
        Ok(Self {
            sample_rate_hz,
            channel_layout: ChannelLayout::from_channels(channels)?,
            boundary_format,
        })
    }

    /// Configured sample rate in hertz.
    #[must_use]
    pub const fn sample_rate_hz(self) -> u32 {
        self.sample_rate_hz
    }

    /// Configured channel layout.
    #[must_use]
    pub const fn channel_layout(self) -> ChannelLayout {
        self.channel_layout
    }

    /// Number of interleaved channels.
    #[must_use]
    pub const fn channels(self) -> u16 {
        self.channel_layout.channels()
    }

    /// External boundary sample format recorded for this stream.
    ///
    /// This is the format a future backend delivers or expects. It never
    /// changes the internal `f64` processing representation.
    #[must_use]
    pub const fn boundary_format(self) -> SampleFormat {
        self.boundary_format
    }

    /// Sample format the DSP kernel stores and processes. Always
    /// [`SampleFormat::F64`].
    #[must_use]
    pub const fn internal_processing_format(self) -> SampleFormat {
        INTERNAL_PROCESSING_FORMAT
    }

    /// Nyquist frequency in hertz.
    #[must_use]
    pub fn nyquist_hz(self) -> f64 {
        f64::from(self.sample_rate_hz) / 2.0
    }

    /// Highest frequency that the DSP chain may process without aliasing.
    ///
    /// A five-percent guard band keeps filters away from the Nyquist edge,
    /// where bilinear-transform warping becomes numerically unreliable.
    #[must_use]
    pub fn max_usable_frequency_hz(self) -> f64 {
        self.nyquist_hz() * 0.95
    }
}

/// Configuration validation failure.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioConfigError {
    /// Sample rate outside the supported range.
    UnsupportedSampleRate(u32),
    /// Channel count other than mono or stereo.
    UnsupportedChannelCount(u16),
}

impl fmt::Display for AudioConfigError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnsupportedSampleRate(rate) => write!(
                formatter,
                "sample rate {rate} Hz is outside the supported {MIN_SAMPLE_RATE_HZ}..={MAX_SAMPLE_RATE_HZ} Hz range"
            ),
            Self::UnsupportedChannelCount(channels) => write!(
                formatter,
                "{channels} channels requested; Phase 0 supports mono (1) or stereo (2)"
            ),
        }
    }
}

impl std::error::Error for AudioConfigError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_common_sample_rates() {
        for rate in [8_000, 44_100, 48_000, 96_000, 192_000, 384_000] {
            let config = AudioConfig::new(rate, 2).expect("valid configuration");
            assert_eq!(config.sample_rate_hz(), rate);
            assert_eq!(config.channels(), 2);
        }
    }

    #[test]
    fn accepts_mono_and_stereo_only() {
        assert_eq!(ChannelLayout::from_channels(1), Ok(ChannelLayout::Mono));
        assert_eq!(ChannelLayout::from_channels(2), Ok(ChannelLayout::Stereo));
        assert_eq!(
            ChannelLayout::from_channels(6),
            Err(AudioConfigError::UnsupportedChannelCount(6))
        );
    }

    #[test]
    fn rejects_out_of_range_sample_rates() {
        assert_eq!(
            AudioConfig::new(0, 2),
            Err(AudioConfigError::UnsupportedSampleRate(0))
        );
        assert_eq!(
            AudioConfig::new(7_999, 2),
            Err(AudioConfigError::UnsupportedSampleRate(7_999))
        );
        assert_eq!(
            AudioConfig::new(384_001, 2),
            Err(AudioConfigError::UnsupportedSampleRate(384_001))
        );
    }

    #[test]
    fn reports_nyquist_and_guard_band() {
        let config = AudioConfig::new(48_000, 2).expect("valid configuration");
        assert!((config.nyquist_hz() - 24_000.0).abs() < f64::EPSILON);
        assert!((config.max_usable_frequency_hz() - 22_800.0).abs() < f64::EPSILON);
    }

    #[test]
    fn new_defaults_to_f64_boundary_format() {
        let config = AudioConfig::new(48_000, 2).expect("valid configuration");
        assert_eq!(config.boundary_format(), SampleFormat::F64);
    }

    #[test]
    fn explicit_boundary_format_is_recorded() {
        let config =
            AudioConfig::with_format(48_000, 2, SampleFormat::F32).expect("valid configuration");
        assert_eq!(config.boundary_format(), SampleFormat::F32);
        assert_eq!(config.sample_rate_hz(), 48_000);
        assert_eq!(config.channels(), 2);
    }

    #[test]
    fn internal_processing_format_is_always_f64() {
        assert_eq!(INTERNAL_PROCESSING_FORMAT, SampleFormat::F64);
        for boundary in [SampleFormat::F32, SampleFormat::F64] {
            let config =
                AudioConfig::with_format(44_100, 1, boundary).expect("valid configuration");
            assert_eq!(config.internal_processing_format(), SampleFormat::F64);
        }
    }

    #[test]
    fn sample_format_metadata_is_stable() {
        assert_eq!(SampleFormat::F32.as_str(), "f32");
        assert_eq!(SampleFormat::F64.as_str(), "f64");
        assert_eq!(SampleFormat::F32.bytes_per_sample(), 4);
        assert_eq!(SampleFormat::F64.bytes_per_sample(), 8);
        assert!(!SampleFormat::F32.is_internal_processing_format());
        assert!(SampleFormat::F64.is_internal_processing_format());
    }

    #[test]
    fn with_format_still_validates_rate_and_channels() {
        assert_eq!(
            AudioConfig::with_format(0, 2, SampleFormat::F32),
            Err(AudioConfigError::UnsupportedSampleRate(0))
        );
        assert_eq!(
            AudioConfig::with_format(48_000, 4, SampleFormat::F32),
            Err(AudioConfigError::UnsupportedChannelCount(4))
        );
    }
}
