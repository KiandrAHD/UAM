//! Typed audio backend errors.
//!
//! Every error carries a stable, machine-readable code ([`AudioErrorCode`]) and
//! a safe human-readable message. The code is what crosses the FFI boundary; the
//! message is for diagnostics and never contains device identifiers, pointers,
//! or audio content.

use core::fmt;

/// Stable error classification shared with the Flutter control path.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AudioErrorCode {
    /// COM could not be initialized on the calling thread.
    ComInitialization,
    /// Enumerating audio endpoints failed.
    DeviceEnumeration,
    /// No active render endpoint exists.
    NoOutputEndpoint,
    /// The requested endpoint identifier is unknown or malformed.
    InvalidEndpoint,
    /// The endpoint format is not supported by this backend.
    UnsupportedFormat,
    /// The endpoint exposes a channel layout this build cannot process.
    UnsupportedChannelCount,
    /// `IAudioClient::Initialize` or service activation failed.
    AudioClientInit,
    /// Acquiring the render buffer failed.
    BufferAcquisition,
    /// Releasing the render buffer failed.
    BufferRelease,
    /// The endpoint was invalidated (format change, driver reset, removal).
    DeviceInvalidated,
    /// The endpoint disappeared while the stream was active.
    DeviceRemoved,
    /// Starting the stream failed.
    StreamStart,
    /// Stopping the stream failed.
    StreamStop,
    /// A DSP configuration was rejected.
    Configuration,
    /// An engine handle or stream handle was invalid.
    HandleInvalid,
    /// A backend wait timed out.
    Timeout,
    /// The operating system reported an unexpected backend error.
    BackendError,
    /// The current platform has no implemented audio backend.
    PlatformUnsupported,
    /// An internal invariant was violated.
    Internal,
}

impl AudioErrorCode {
    /// Stable wire identifier used by FFI payloads and diagnostics.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::ComInitialization => "com_initialization",
            Self::DeviceEnumeration => "device_enumeration",
            Self::NoOutputEndpoint => "no_output_endpoint",
            Self::InvalidEndpoint => "invalid_endpoint",
            Self::UnsupportedFormat => "unsupported_format",
            Self::UnsupportedChannelCount => "unsupported_channel_count",
            Self::AudioClientInit => "audio_client_init",
            Self::BufferAcquisition => "buffer_acquisition",
            Self::BufferRelease => "buffer_release",
            Self::DeviceInvalidated => "device_invalidated",
            Self::DeviceRemoved => "device_removed",
            Self::StreamStart => "stream_start",
            Self::StreamStop => "stream_stop",
            Self::Configuration => "configuration",
            Self::HandleInvalid => "handle_invalid",
            Self::Timeout => "timeout",
            Self::BackendError => "backend_error",
            Self::PlatformUnsupported => "platform_unsupported",
            Self::Internal => "internal",
        }
    }
    /// Stable numeric identifier used by cross-thread metrics.
    #[must_use]
    pub const fn as_u64(self) -> u64 {
        match self {
            Self::ComInitialization => 1,
            Self::DeviceEnumeration => 2,
            Self::NoOutputEndpoint => 3,
            Self::InvalidEndpoint => 4,
            Self::UnsupportedFormat => 5,
            Self::UnsupportedChannelCount => 6,
            Self::AudioClientInit => 7,
            Self::BufferAcquisition => 8,
            Self::BufferRelease => 9,
            Self::DeviceInvalidated => 10,
            Self::DeviceRemoved => 11,
            Self::StreamStart => 12,
            Self::StreamStop => 13,
            Self::Configuration => 14,
            Self::HandleInvalid => 15,
            Self::Timeout => 16,
            Self::BackendError => 17,
            Self::PlatformUnsupported => 18,
            Self::Internal => 19,
        }
    }

    /// Resolve a numeric identifier produced by [`AudioErrorCode::as_u64`].
    /// Returns `None` for `0` (no error) and for unknown values.
    #[must_use]
    pub const fn from_u64(value: u64) -> Option<Self> {
        match value {
            1 => Some(Self::ComInitialization),
            2 => Some(Self::DeviceEnumeration),
            3 => Some(Self::NoOutputEndpoint),
            4 => Some(Self::InvalidEndpoint),
            5 => Some(Self::UnsupportedFormat),
            6 => Some(Self::UnsupportedChannelCount),
            7 => Some(Self::AudioClientInit),
            8 => Some(Self::BufferAcquisition),
            9 => Some(Self::BufferRelease),
            10 => Some(Self::DeviceInvalidated),
            11 => Some(Self::DeviceRemoved),
            12 => Some(Self::StreamStart),
            13 => Some(Self::StreamStop),
            14 => Some(Self::Configuration),
            15 => Some(Self::HandleInvalid),
            16 => Some(Self::Timeout),
            17 => Some(Self::BackendError),
            18 => Some(Self::PlatformUnsupported),
            19 => Some(Self::Internal),
            _ => None,
        }
    }
}

impl fmt::Display for AudioErrorCode {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// A typed backend or engine failure.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioError {
    /// Stable classification.
    pub code: AudioErrorCode,
    /// Safe human-readable detail.
    pub message: String,
}

impl AudioError {
    /// Build an error from a code and a message.
    #[must_use]
    pub fn new(code: AudioErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    /// Convenience constructor for the platform-unsupported case.
    #[must_use]
    pub fn platform_unsupported(platform: &str) -> Self {
        Self::new(
            AudioErrorCode::PlatformUnsupported,
            format!("No UAM audio backend is implemented for {platform}."),
        )
    }
}

impl fmt::Display for AudioError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for AudioError {}

impl From<uam_dsp::DspError> for AudioError {
    fn from(error: uam_dsp::DspError) -> Self {
        Self::new(AudioErrorCode::Configuration, error.to_string())
    }
}

impl From<uam_domain::AudioConfigError> for AudioError {
    fn from(error: uam_domain::AudioConfigError) -> Self {
        Self::new(AudioErrorCode::Configuration, error.to_string())
    }
}
