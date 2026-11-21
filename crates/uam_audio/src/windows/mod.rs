#![allow(unsafe_code)]
//! Native Windows WASAPI backend (shared mode, event-driven render).
//!
//! # Scope
//!
//! UAM renders **its own** audio stream to the selected render endpoint through
//! the Windows Audio Session API. It never captures or processes the audio of
//! other applications; the processing scope is therefore `app_owned_stream`
//! only while a stream is attached and `configuration_only` otherwise.
//!
//! # Threading
//!
//! COM is initialized multi-threaded (MTA) for the duration of each call that
//! touches the MMDevice API. The audio client and its render client run on a
//! dedicated producer thread that waits on the endpoint's event handle. WASAPI
//! interfaces are agile, so the objects created here are safe to use from the
//! producer thread; the `unsafe impl Send` on the resource bundles encode that
//! documented contract.
//!
//! # Unsafe
//!
//! This module is the only place in the crate where `unsafe` is permitted. Every
//! COM call is wrapped in a `unsafe` block that documents the invariant it
//! relies on (a valid interface obtained from a live enumerator in the same
//! apartment).

mod com;
mod device;
mod notification;
mod render;

use std::sync::mpsc::Receiver;

use windows::Win32::Media::Audio::{IMMDeviceEnumerator, MMDeviceEnumerator};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_ALL};

use crate::backend::{AudioBackend, DeviceSubscription, OpenRequest, RunningStream};
use crate::config::StreamFormat;
use crate::device::{DeviceEvent, DeviceListSnapshot};
use crate::error::{AudioError, AudioErrorCode};

use com::ComApartment;
use device::{default_endpoint_id, enumerate_endpoints, query_format};

/// The Windows WASAPI backend.
pub struct WindowsBackend;

impl WindowsBackend {
    /// Create the backend. No COM object is created until a call is made.
    #[must_use]
    pub const fn new() -> Self {
        Self
    }
}

impl Default for WindowsBackend {
    fn default() -> Self {
        Self::new()
    }
}

/// Create an MMDevice enumerator inside a fresh MTA apartment and run `f` with
/// it. The apartment guard lives for the whole call.
fn with_enumerator<T>(
    f: impl FnOnce(&IMMDeviceEnumerator) -> Result<T, AudioError>,
) -> Result<T, AudioError> {
    let _apartment = ComApartment::initialize()?;
    // SAFETY: `_apartment` guarantees COM is initialized on this thread for the
    // duration of the call, which is the MMDevice API's precondition.
    let enumerator: IMMDeviceEnumerator =
        unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }.map_err(|error| {
            AudioError::new(
                AudioErrorCode::DeviceEnumeration,
                format!("failed to create the MMDevice enumerator: {error:?}"),
            )
        })?;
    f(&enumerator)
}

impl AudioBackend for WindowsBackend {
    fn name(&self) -> &'static str {
        "wasapi-shared"
    }

    fn describe(&self) -> String {
        "WASAPI shared-mode event-driven render backend. UAM renders its own test \
         stream to the selected endpoint; it does not capture or process the audio \
         of other applications."
            .to_owned()
    }

    fn enumerate(&self) -> Result<DeviceListSnapshot, AudioError> {
        with_enumerator(enumerate_endpoints)
    }

    fn query_format(&self, device_id: &str) -> Result<StreamFormat, AudioError> {
        with_enumerator(|enumerator| query_format(enumerator, device_id))
    }

    fn default_device_id(&self) -> Result<Option<String>, AudioError> {
        with_enumerator(default_endpoint_id)
    }

    fn open(&self, request: OpenRequest) -> Result<Box<dyn RunningStream>, AudioError> {
        let _apartment = ComApartment::initialize()?;
        // SAFETY: COM is initialized above for the duration of the call.
        let enumerator: IMMDeviceEnumerator =
            unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }.map_err(
                |error| {
                    AudioError::new(
                        AudioErrorCode::DeviceEnumeration,
                        format!("failed to create the MMDevice enumerator: {error:?}"),
                    )
                },
            )?;
        let stream = render::open(&enumerator, request)?;
        Ok(Box::new(stream))
    }

    fn subscribe(
        &self,
    ) -> Result<(Box<dyn DeviceSubscription>, Receiver<DeviceEvent>), AudioError> {
        let _apartment = ComApartment::initialize()?;
        // SAFETY: COM is initialized above for the duration of the call.
        let enumerator: IMMDeviceEnumerator =
            unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }.map_err(
                |error| {
                    AudioError::new(
                        AudioErrorCode::DeviceEnumeration,
                        format!("failed to create the MMDevice enumerator: {error:?}"),
                    )
                },
            )?;
        let (subscription, events) = notification::subscribe(enumerator)?;
        Ok((Box::new(subscription), events))
    }
}
