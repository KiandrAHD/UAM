//! Validated audio stream configuration.
//!
//! Phase 0 supports mono and stereo interleaved `f64` sample buffers. These
//! are deliberately conservative: they cover the initial EQ prototype without
//! implying support for multichannel, float32, integer, or planar formats.

use core::fmt;

/// Lowest sample rate accepted by the Phase 0 core.
pub const MIN_SAMPLE_RATE_HZ: u32 = 8_000;
/// Highest sample rate accepted by the Phase 0 core.
pub const MAX_SAMPLE_RATE_HZ: u32 = 384_000;
/// Phase 0 channels: mono or stereo.
pub const MAX_CHANNELS: u16 = 2;

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
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AudioConfig {
    sample_rate_hz: u32,
    channel_layout: ChannelLayout,
}

impl AudioConfig {
    /// Create a configuration after checking the Phase 0 bounds.
    ///
    /// # Errors
    ///
    /// Returns [`AudioConfigError`] when the sample rate is outside
    /// [`MIN_SAMPLE_RATE_HZ`]..=[`MAX_SAMPLE_RATE_HZ`] or the channel count is
    /// not one or two.
    pub fn new(sample_rate_hz: u32, channels: u16) -> Result<Self, AudioConfigError> {
        if !(MIN_SAMPLE_RATE_HZ..=MAX_SAMPLE_RATE_HZ).contains(&sample_rate_hz) {
            return Err(AudioConfigError::UnsupportedSampleRate(sample_rate_hz));
        }
        Ok(Self {
            sample_rate_hz,
            channel_layout: ChannelLayout::from_channels(channels)?,
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
}
