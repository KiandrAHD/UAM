//! Sample-peak metering and clipping detection.
//!
//! # What this measures
//!
//! [`PeakMeter`] measures the **sample peak** of an interleaved `f64` buffer:
//! the largest absolute value of any sample in a block, per channel and
//! overall. It also counts **clipped samples** — samples whose magnitude
//! reaches or exceeds an explicit linear threshold (default
//! [`CLIP_THRESHOLD_LINEAR`] = `1.0`, i.e. `0 dBFS`).
//!
//! This is deliberately **not** true-peak metering. True peak requires
//! over-sampling and reconstruction filtering to estimate the inter-sample
//! peak between samples. No over-sampling is implemented here, so the meter
//! reports sample peak only and never claims true peak.
//!
//! # Non-finite input policy
//!
//! The meter must never return `NaN` or infinity, so non-finite samples are
//! handled explicitly and counted in [`BlockPeak::non_finite_samples`]:
//!
//! - `NaN` is ignored for level and clipping: it carries no level information.
//! - `+inf` and `-inf` are impossible to represent as a level, so they are
//!   **not** folded into the reported peak (which stays finite), but they
//!   *are* counted as clipped because their magnitude provably exceeds the
//!   threshold. This keeps "clipped" truthful while keeping the meter output
//!   finite.
//!
//! # Allocation and real-time behaviour
//!
//! [`PeakMeter`] stores fixed-size inline state only. Block processing
//! ([`PeakMeter::process_interleaved`]) performs no allocation, no locking,
//! no I/O, and no logging, so it is safe to call from a future audio callback.
//! The meter is usable independently of the equalizer and the limiter.

use core::fmt;

use uam_domain::MAX_CHANNELS;

/// Linear magnitude at which a sample is treated as clipped (`0 dBFS`).
///
/// A sample is counted as clipped when its absolute value is greater than or
/// equal to this magnitude. It matches the definitions used by the limiter
/// ceiling, so a signal that reaches full scale is reported as clipped.
pub const CLIP_THRESHOLD_LINEAR: f64 = 1.0;

/// Lowest level returned by the dBFS helpers, used for silence and subnormal
/// peaks so the meter never returns negative infinity.
pub const DBFS_FLOOR: f64 = -200.0;

/// Linear magnitude that maps exactly to [`DBFS_FLOOR`] (`10^(floor/20)`).
const MIN_MEASURABLE_LINEAR: f64 = 1.0e-10;

/// Convert a linear magnitude to decibels relative to full scale.
///
/// The result is always finite: a magnitude that is non-finite, zero, or below
/// the meter floor maps to [`DBFS_FLOOR`]. This is used for both sample peaks
/// and meter reporting.
#[must_use]
pub fn linear_to_dbfs(linear: f64) -> f64 {
    let magnitude = linear.abs();
    if !magnitude.is_finite() || magnitude <= MIN_MEASURABLE_LINEAR {
        DBFS_FLOOR
    } else {
        (20.0 * magnitude.log10()).max(DBFS_FLOOR)
    }
}

/// Meter construction or processing failure.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MeterError {
    /// A channel count other than mono or stereo was requested.
    UnsupportedChannelCount(u16),
    /// The clipping threshold was non-finite or not strictly positive.
    InvalidClipThreshold(f64),
    /// The interleaved buffer length is not a whole number of frames.
    InvalidBlockLength {
        /// Supplied sample count.
        samples: usize,
        /// Channel count used to derive the frame size.
        channels: u16,
    },
}

impl fmt::Display for MeterError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnsupportedChannelCount(channels) => write!(
                formatter,
                "{channels} channels requested; the meter supports mono (1) or stereo (2)"
            ),
            Self::InvalidClipThreshold(threshold) => write!(
                formatter,
                "clipping threshold {threshold} must be finite and greater than zero"
            ),
            Self::InvalidBlockLength { samples, channels } => write!(
                formatter,
                "interleaved buffer has {samples} samples, which is not divisible by {channels} channels"
            ),
        }
    }
}

impl std::error::Error for MeterError {}

/// Peak measurement for a single block.
///
/// Every value is finite. Use the `_dbfs` accessors for decibel reporting.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BlockPeak {
    per_channel: [f64; MAX_CHANNELS as usize],
    channels: u16,
    overall: f64,
    clipped: u64,
    non_finite: u64,
    frames: usize,
}

impl BlockPeak {
    /// An empty measurement for `channels` channels.
    const fn empty(channels: u16) -> Self {
        Self {
            per_channel: [0.0; MAX_CHANNELS as usize],
            channels,
            overall: 0.0,
            clipped: 0,
            non_finite: 0,
            frames: 0,
        }
    }

    /// Number of channels measured.
    #[must_use]
    pub const fn channels(&self) -> u16 {
        self.channels
    }

    /// Number of frames processed in this block.
    #[must_use]
    pub const fn frames(&self) -> usize {
        self.frames
    }

    /// Sample peak of one channel as a linear magnitude, or `0.0` when the
    /// channel index is out of range.
    #[must_use]
    pub fn per_channel_peak(&self, channel: usize) -> f64 {
        self.per_channel.get(channel).copied().unwrap_or(0.0)
    }

    /// Sample peak of one channel in dBFS (finite, floored).
    #[must_use]
    pub fn per_channel_peak_dbfs(&self, channel: usize) -> f64 {
        linear_to_dbfs(self.per_channel_peak(channel))
    }

    /// Largest sample peak across all channels in this block.
    #[must_use]
    pub const fn overall_peak(&self) -> f64 {
        self.overall
    }

    /// Overall sample peak in dBFS (finite, floored).
    #[must_use]
    pub fn overall_peak_dbfs(&self) -> f64 {
        linear_to_dbfs(self.overall)
    }

    /// Number of samples at or above the clipping threshold in this block.
    #[must_use]
    pub const fn clipped_samples(&self) -> u64 {
        self.clipped
    }

    /// Whether any sample in this block was clipped.
    #[must_use]
    pub const fn clipping_detected(&self) -> bool {
        self.clipped > 0
    }

    /// Number of non-finite samples seen in this block.
    #[must_use]
    pub const fn non_finite_samples(&self) -> u64 {
        self.non_finite
    }
}

/// A sample-peak meter with running (peak-hold) state.
///
/// State persists across blocks until [`PeakMeter::reset`]. The meter is
/// allocation-free during processing and holds no locks.
#[derive(Debug, Clone)]
pub struct PeakMeter {
    channels: u16,
    clip_threshold: f64,
    per_channel_peak: [f64; MAX_CHANNELS as usize],
    clipped_samples: u64,
    non_finite_samples: u64,
    processed_frames: u64,
}

impl PeakMeter {
    /// Create a meter for mono or stereo input with the default clipping
    /// threshold.
    ///
    /// # Errors
    ///
    /// Returns [`MeterError::UnsupportedChannelCount`] for any count other
    /// than one or two.
    pub fn new(channels: u16) -> Result<Self, MeterError> {
        Self::with_clip_threshold(channels, CLIP_THRESHOLD_LINEAR)
    }

    /// Create a meter with an explicit linear clipping threshold.
    ///
    /// # Errors
    ///
    /// Returns [`MeterError::UnsupportedChannelCount`] or
    /// [`MeterError::InvalidClipThreshold`].
    pub fn with_clip_threshold(channels: u16, clip_threshold: f64) -> Result<Self, MeterError> {
        if channels == 0 || channels > MAX_CHANNELS {
            return Err(MeterError::UnsupportedChannelCount(channels));
        }
        if !clip_threshold.is_finite() || clip_threshold <= 0.0 {
            return Err(MeterError::InvalidClipThreshold(clip_threshold));
        }
        Ok(Self {
            channels,
            clip_threshold,
            per_channel_peak: [0.0; MAX_CHANNELS as usize],
            clipped_samples: 0,
            non_finite_samples: 0,
            processed_frames: 0,
        })
    }

    /// Channel count this meter was built for.
    #[must_use]
    pub const fn channels(&self) -> u16 {
        self.channels
    }

    /// Linear clipping threshold in use.
    #[must_use]
    pub const fn clip_threshold(&self) -> f64 {
        self.clip_threshold
    }

    /// Measure one interleaved block and fold it into the running state.
    ///
    /// No allocation, locking, I/O, or logging occurs. An empty buffer is
    /// valid and produces an empty [`BlockPeak`].
    ///
    /// # Errors
    ///
    /// Returns [`MeterError::InvalidBlockLength`] when the buffer is not a
    /// whole number of frames. No state is modified in that case.
    pub fn process_interleaved(&mut self, samples: &[f64]) -> Result<BlockPeak, MeterError> {
        let channels = usize::from(self.channels);
        if samples.len() % channels != 0 {
            return Err(MeterError::InvalidBlockLength {
                samples: samples.len(),
                channels: self.channels,
            });
        }

        let mut block = BlockPeak::empty(self.channels);
        block.frames = samples.len() / channels;

        for frame in samples.chunks_exact(channels) {
            for (channel, sample) in frame.iter().enumerate() {
                if !sample.is_finite() {
                    block.non_finite += 1;
                    if sample.is_infinite() {
                        // Infinite magnitude provably exceeds any finite
                        // threshold, so it is clipped, but it is not folded
                        // into the (finite) reported peak.
                        block.clipped += 1;
                    }
                    continue;
                }
                let magnitude = sample.abs();
                if magnitude > block.per_channel[channel] {
                    block.per_channel[channel] = magnitude;
                }
                if magnitude > block.overall {
                    block.overall = magnitude;
                }
                if magnitude >= self.clip_threshold {
                    block.clipped += 1;
                }
            }
        }

        for (channel, peak) in block.per_channel.iter().enumerate() {
            if *peak > self.per_channel_peak[channel] {
                self.per_channel_peak[channel] = *peak;
            }
        }
        self.clipped_samples += block.clipped;
        self.non_finite_samples += block.non_finite;
        self.processed_frames += u64::try_from(block.frames).unwrap_or(u64::MAX);

        Ok(block)
    }

    /// Clear all running state. Deterministic: the meter behaves exactly as a
    /// freshly constructed instance afterwards.
    pub fn reset(&mut self) {
        self.per_channel_peak = [0.0; MAX_CHANNELS as usize];
        self.clipped_samples = 0;
        self.non_finite_samples = 0;
        self.processed_frames = 0;
    }

    /// Running (peak-hold) sample peak of one channel since the last reset.
    #[must_use]
    pub fn running_peak(&self, channel: usize) -> f64 {
        self.per_channel_peak.get(channel).copied().unwrap_or(0.0)
    }

    /// Running sample peak of one channel in dBFS.
    #[must_use]
    pub fn running_peak_dbfs(&self, channel: usize) -> f64 {
        linear_to_dbfs(self.running_peak(channel))
    }

    /// Largest running sample peak across all channels.
    #[must_use]
    pub fn running_overall_peak(&self) -> f64 {
        self.per_channel_peak
            .iter()
            .take(usize::from(self.channels))
            .copied()
            .fold(0.0_f64, f64::max)
    }

    /// Overall running sample peak in dBFS.
    #[must_use]
    pub fn running_overall_peak_dbfs(&self) -> f64 {
        linear_to_dbfs(self.running_overall_peak())
    }

    /// Running count of clipped samples since the last reset.
    #[must_use]
    pub const fn clipped_samples(&self) -> u64 {
        self.clipped_samples
    }

    /// Whether any sample has been clipped since the last reset.
    #[must_use]
    pub const fn clipping_detected(&self) -> bool {
        self.clipped_samples > 0
    }

    /// Running count of non-finite samples since the last reset.
    #[must_use]
    pub const fn non_finite_samples(&self) -> u64 {
        self.non_finite_samples
    }

    /// Total frames processed since the last reset.
    #[must_use]
    pub const fn processed_frames(&self) -> u64 {
        self.processed_frames
    }
}
