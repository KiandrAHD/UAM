//! `IMMNotificationClient` bridge into a plain event channel.
//!
//! The COM callback never touches the engine directly: it converts each
//! notification into a plain [`DeviceEvent`] and pushes it into a channel. The
//! control path drains the channel on its own schedule, so a slow or blocked
//! consumer cannot stall the COM notification thread.

use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Mutex;

use windows::core::PCWSTR;
use windows::Win32::Media::Audio::{
    eRender, EDataFlow, ERole, IMMDeviceEnumerator, IMMNotificationClient,
    IMMNotificationClient_Impl, DEVICE_STATE,
};
use windows::Win32::Media::Audio::{
    DEVICE_STATE_ACTIVE, DEVICE_STATE_DISABLED, DEVICE_STATE_NOTPRESENT, DEVICE_STATE_UNPLUGGED,
};
use windows_core::implement;

use super::com::ComApartment;
use crate::backend::DeviceSubscription;
use crate::device::{DeviceEvent, DeviceEventKind, DeviceState};
use crate::error::{AudioError, AudioErrorCode};

/// COM sink forwarding endpoint notifications into a channel.
#[implement(IMMNotificationClient)]
struct NotificationSink {
    sender: Mutex<Sender<DeviceEvent>>,
}

impl NotificationSink {
    fn forward(&self, event: DeviceEvent) {
        if let Ok(sender) = self.sender.lock() {
            // A closed receiver is not an error here; the control path simply
            // stopped listening.
            let _ = sender.send(event);
        }
    }
}

impl IMMNotificationClient_Impl for NotificationSink_Impl {
    fn OnDeviceStateChanged(
        &self,
        device_id: &PCWSTR,
        new_state: DEVICE_STATE,
    ) -> windows::core::Result<()> {
        self.forward(DeviceEvent {
            kind: DeviceEventKind::StateChanged,
            device_id: Some(read_pcwstr(device_id)),
            state: Some(map_state(new_state)),
            default_id: None,
        });
        Ok(())
    }

    fn OnDeviceAdded(&self, device_id: &PCWSTR) -> windows::core::Result<()> {
        self.forward(DeviceEvent::for_device(
            DeviceEventKind::Added,
            read_pcwstr(device_id),
        ));
        Ok(())
    }

    fn OnDeviceRemoved(&self, device_id: &PCWSTR) -> windows::core::Result<()> {
        self.forward(DeviceEvent::for_device(
            DeviceEventKind::Removed,
            read_pcwstr(device_id),
        ));
        Ok(())
    }

    fn OnDefaultDeviceChanged(
        &self,
        flow: EDataFlow,
        _role: ERole,
        default_id: &PCWSTR,
    ) -> windows::core::Result<()> {
        if flow.0 == eRender.0 {
            self.forward(DeviceEvent {
                kind: DeviceEventKind::DefaultChanged,
                device_id: None,
                state: None,
                default_id: Some(read_pcwstr(default_id)),
            });
        }
        Ok(())
    }

    fn OnPropertyValueChanged(
        &self,
        device_id: &PCWSTR,
        _key: &windows::Win32::Foundation::PROPERTYKEY,
    ) -> windows::core::Result<()> {
        self.forward(DeviceEvent::for_device(
            DeviceEventKind::PropertyChanged,
            read_pcwstr(device_id),
        ));
        Ok(())
    }
}

/// A registered endpoint-notification subscription.
pub struct WindowsDeviceSubscription {
    enumerator: Option<IMMDeviceEnumerator>,
    client: Option<IMMNotificationClient>,
}

// SAFETY: WASAPI MMDevice interfaces are agile (free-threaded) and this object
// is only unregistered from the thread that owns the engine, which joins the MTA
// before calling into COM.
unsafe impl Send for WindowsDeviceSubscription {}

impl DeviceSubscription for WindowsDeviceSubscription {
    fn unsubscribe(&mut self) {
        let _apartment = ComApartment::initialize();
        if let (Some(enumerator), Some(client)) = (self.enumerator.take(), self.client.take()) {
            // SAFETY: both interfaces are live and were created in this
            // process; registration is balanced with the call in `subscribe`.
            unsafe {
                let _ = enumerator.UnregisterEndpointNotificationCallback(&client);
            }
        }
    }
}

/// Register an endpoint-notification callback.
///
/// # Errors
///
/// Returns [`AudioErrorCode::DeviceEnumeration`] when registration fails.
pub fn subscribe(
    enumerator: IMMDeviceEnumerator,
) -> Result<(WindowsDeviceSubscription, Receiver<DeviceEvent>), AudioError> {
    let (sender, receiver) = channel();
    let sink: IMMNotificationClient = NotificationSink {
        sender: Mutex::new(sender),
    }
    .into();
    // SAFETY: the enumerator is live and COM is initialized by the caller.
    unsafe { enumerator.RegisterEndpointNotificationCallback(&sink) }.map_err(|error| {
        AudioError::new(
            AudioErrorCode::DeviceEnumeration,
            format!("RegisterEndpointNotificationCallback failed: {error:?}"),
        )
    })?;
    let subscription = WindowsDeviceSubscription {
        enumerator: Some(enumerator),
        client: Some(sink),
    };
    Ok((subscription, receiver))
}

/// Read a COM callback string parameter.
fn read_pcwstr(value: &PCWSTR) -> String {
    // SAFETY: the COM callback guarantees a valid NUL-terminated UTF-16 string
    // for the duration of the call.
    unsafe { value.to_string() }.unwrap_or_default()
}

/// Map a `DEVICE_STATE` bitmask to the normalized state.
fn map_state(state: DEVICE_STATE) -> DeviceState {
    if state.0 & DEVICE_STATE_ACTIVE.0 != 0 {
        DeviceState::Active
    } else if state.0 & DEVICE_STATE_DISABLED.0 != 0 {
        DeviceState::Disabled
    } else if state.0 & DEVICE_STATE_UNPLUGGED.0 != 0 {
        DeviceState::Unplugged
    } else if state.0 & DEVICE_STATE_NOTPRESENT.0 != 0 {
        DeviceState::NotPresent
    } else {
        DeviceState::Unknown
    }
}
