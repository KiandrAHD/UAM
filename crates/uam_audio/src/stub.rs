//! Truthful fallback backend for platforms without a native UAM adapter.

use std::sync::mpsc::{self, Receiver};

use crate::backend::{AudioBackend, DeviceSubscription, OpenRequest, RunningStream};
use crate::config::StreamFormat;
use crate::device::{DeviceEvent, DeviceListSnapshot};
use crate::error::{AudioError, AudioErrorCode};

/// Backend used outside Windows until a native adapter exists.
pub struct UnsupportedBackend;

impl UnsupportedBackend {
    /// Create fallback backend.
    #[must_use]
    pub const fn new() -> Self {
        Self
    }

    fn error() -> AudioError {
        AudioError::platform_unsupported(std::env::consts::OS)
    }
}

impl Default for UnsupportedBackend {
    fn default() -> Self {
        Self::new()
    }
}

impl AudioBackend for UnsupportedBackend {
    fn name(&self) -> &'static str {
        "unsupported"
    }

    fn describe(&self) -> String {
        format!(
            "UAM has no native audio render backend on {}. Processing remains configuration-only.",
            std::env::consts::OS
        )
    }

    fn enumerate(&self) -> Result<DeviceListSnapshot, AudioError> {
        Ok(DeviceListSnapshot::empty(Self::error().message))
    }

    fn query_format(&self, _device_id: &str) -> Result<StreamFormat, AudioError> {
        Err(Self::error())
    }

    fn default_device_id(&self) -> Result<Option<String>, AudioError> {
        Ok(None)
    }

    fn open(&self, _request: OpenRequest) -> Result<Box<dyn RunningStream>, AudioError> {
        Err(AudioError::new(
            AudioErrorCode::PlatformUnsupported,
            Self::error().message,
        ))
    }

    fn subscribe(
        &self,
    ) -> Result<(Box<dyn DeviceSubscription>, Receiver<DeviceEvent>), AudioError> {
        let (_tx, rx) = mpsc::channel();
        Ok((Box::new(UnsupportedSubscription), rx))
    }
}

struct UnsupportedSubscription;

impl DeviceSubscription for UnsupportedSubscription {
    fn unsubscribe(&mut self) {}
}
