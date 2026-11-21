//! Platform audio backends behind one interface.
//!
//! The engine talks only to [`AudioBackend`]. A backend owns endpoint discovery,
//! stream opening, and device notifications for one operating system. Only
//! Windows has a real implementation in this phase; other platforms use
//! [`crate::stub::UnsupportedBackend`], which reports the truth instead of
//! pretending.

use std::sync::mpsc::Receiver;

use uam_dsp::DspPipeline;

use crate::config::StreamFormat;
use crate::device::{DeviceEvent, DeviceListSnapshot};
use crate::error::AudioError;
use crate::host::{HostChannels, StreamControl};

/// Everything a backend needs to open one render stream.
///
/// The audio-thread host is built by the backend once it knows the device buffer
/// size, so the pipeline travels prepared and the control channel travels
/// before the stream exists.
pub struct OpenRequest {
    /// Endpoint identifier to render to.
    pub device_id: String,
    /// Format the engine validated for this endpoint.
    pub format: StreamFormat,
    /// Initial DSP pipeline, already built for `format`.
    pub pipeline: Box<DspPipeline>,
    /// Control handle for bypass, tone, and configuration hand-off.
    pub control: StreamControl,
    /// Audio-thread half of the control channel.
    pub channels: HostChannels,
}

/// A stream that is running on its own thread.
pub trait RunningStream: Send {
    /// Whether the producer thread is still alive and rendering.
    fn is_running(&self) -> bool;
    /// Stop the stream, join its thread, and release all native resources.
    fn terminate(self: Box<Self>);
}

/// A live device-notification subscription.
pub trait DeviceSubscription: Send {
    /// Remove the OS callback registration and release it.
    fn unsubscribe(&mut self);
}

/// One platform audio backend.
pub trait AudioBackend: Send {
    /// Short backend name used in diagnostics.
    fn name(&self) -> &'static str;

    /// Human-readable description of what this backend does and does not do.
    fn describe(&self) -> String;

    /// Enumerate active render endpoints.
    ///
    /// # Errors
    ///
    /// Returns a typed error when the OS audio API cannot be reached. An empty
    /// but successful result is reported as an empty snapshot, never as an
    /// error.
    fn enumerate(&self) -> Result<DeviceListSnapshot, AudioError>;

    /// Read an endpoint's current mix format.
    ///
    /// # Errors
    ///
    /// Returns [`crate::error::AudioErrorCode::InvalidEndpoint`] for an unknown
    /// identifier and a typed error when the format cannot be read.
    fn query_format(&self, device_id: &str) -> Result<StreamFormat, AudioError>;

    /// Identifier of the current default render endpoint, if any.
    ///
    /// # Errors
    ///
    /// Returns a typed error when the OS API cannot be reached.
    fn default_device_id(&self) -> Result<Option<String>, AudioError>;

    /// Open and start a render stream.
    ///
    /// # Errors
    ///
    /// Returns a typed error when the endpoint or stream cannot be opened. On
    /// failure the request's pipeline, control, and buffers are dropped cleanly.
    fn open(&self, request: OpenRequest) -> Result<Box<dyn RunningStream>, AudioError>;

    /// Subscribe to endpoint change notifications.
    ///
    /// # Errors
    ///
    /// Returns a typed error when the OS notification API cannot be reached.
    fn subscribe(&self)
        -> Result<(Box<dyn DeviceSubscription>, Receiver<DeviceEvent>), AudioError>;
}

/// Build the backend for the current platform.
#[must_use]
pub fn create_backend() -> Box<dyn AudioBackend> {
    #[cfg(windows)]
    {
        Box::new(crate::windows::WindowsBackend::new())
    }
    #[cfg(not(windows))]
    {
        Box::new(crate::stub::UnsupportedBackend::new())
    }
}
