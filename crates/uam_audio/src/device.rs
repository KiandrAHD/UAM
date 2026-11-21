//! Platform-independent, normalized output-device model.
//!
//! The Windows adapter maps its endpoints into these types; no COM type ever
//! appears in this module. Every optional field is nullable because the
//! operating system does not always expose it, and *nothing* here is inferred
//! from a device name: an unknown field stays unknown.

use serde::Serialize;

/// Broad physical transport of an endpoint, when the OS exposes it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeviceTransport {
    /// On-board or otherwise internal audio hardware.
    BuiltIn,
    /// USB audio class device.
    Usb,
    /// Bluetooth audio endpoint.
    Bluetooth,
    /// HDMI or DisplayPort audio.
    Hdmi,
    /// Network or streaming endpoint.
    Network,
    /// Software or virtual endpoint.
    Virtual,
    /// Transport not exposed or not recognised.
    Unknown,
}

/// Endpoint lifecycle state as reported by the OS.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeviceState {
    /// Present and usable.
    Active,
    /// Present but disabled by the user.
    Disabled,
    /// Previously plugged in, currently absent.
    Unplugged,
    /// Present in the registry but not attached.
    NotPresent,
    /// State could not be read.
    Unknown,
}

impl DeviceState {
    /// Wire identifier.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Disabled => "disabled",
            Self::Unplugged => "unplugged",
            Self::NotPresent => "not_present",
            Self::Unknown => "unknown",
        }
    }
}

/// Stability of the endpoint identifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum IdStability {
    /// The OS guarantees the identifier is stable across reboots and re-plugs.
    StableAcrossSessions,
    /// The identifier is only valid for the current session.
    SessionScoped,
    /// Identifier stability is unknown.
    Unknown,
}

/// Provenance of an optional format summary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FormatProvenance {
    /// Read from the endpoint's mix format through `IAudioClient`.
    MixFormat,
    /// Not queried or not available.
    Unknown,
}

/// One normalized output endpoint.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OutputDevice {
    /// Application-level identifier (the OS endpoint id string).
    pub id: String,
    /// Human-readable endpoint name, when the OS exposes one.
    pub display_name: String,
    /// Platform identifier, identical to `id` on Windows, kept explicit so a
    /// future adapter can carry additional correlation data.
    pub platform_id: String,
    /// Transport, or [`DeviceTransport::Unknown`].
    pub transport: DeviceTransport,
    /// Current lifecycle state.
    pub connection_state: DeviceState,
    /// Whether this endpoint is the current default for its role.
    pub is_default: bool,
    /// Identifier stability classification.
    pub id_stability: IdStability,
    /// Short format summary, when a mix format was read.
    pub format_summary: Option<String>,
    /// Provenance of `format_summary`.
    pub format_provenance: FormatProvenance,
}

/// One enumeration result.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceListSnapshot {
    /// Active render endpoints, ordered as the OS returned them.
    pub devices: Vec<OutputDevice>,
    /// Identifier of the default render endpoint, when one exists.
    pub default_id: Option<String>,
    /// Whether enumeration reached the OS API.
    pub enumeration_succeeded: bool,
    /// Reason enumeration returned nothing or failed.
    pub reason: Option<String>,
}

impl DeviceListSnapshot {
    /// An empty snapshot explaining why nothing was returned.
    #[must_use]
    pub fn empty(reason: impl Into<String>) -> Self {
        Self {
            devices: Vec::new(),
            default_id: None,
            enumeration_succeeded: false,
            reason: Some(reason.into()),
        }
    }
}

/// Kinds of endpoint change the backend can report.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeviceEventKind {
    /// An endpoint was added.
    Added,
    /// An endpoint was removed.
    Removed,
    /// An endpoint's state changed (for example active to unplugged).
    StateChanged,
    /// The default endpoint for a role changed.
    DefaultChanged,
    /// A property of an endpoint changed.
    PropertyChanged,
}

/// One endpoint change notification.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceEvent {
    /// What changed.
    pub kind: DeviceEventKind,
    /// Identifier of the affected endpoint, when known.
    pub device_id: Option<String>,
    /// New connection state for [`DeviceEventKind::StateChanged`].
    pub state: Option<DeviceState>,
    /// New default identifier for [`DeviceEventKind::DefaultChanged`].
    pub default_id: Option<String>,
}

impl DeviceEvent {
    /// An event affecting one endpoint.
    #[must_use]
    pub fn for_device(kind: DeviceEventKind, device_id: impl Into<String>) -> Self {
        Self {
            kind,
            device_id: Some(device_id.into()),
            state: None,
            default_id: None,
        }
    }

    /// Whether this event invalidates a currently active endpoint.
    #[must_use]
    pub fn invalidates(&self, device_id: &str) -> bool {
        match self.kind {
            DeviceEventKind::Removed => self.device_id.as_deref() == Some(device_id),
            DeviceEventKind::StateChanged => {
                self.device_id.as_deref() == Some(device_id)
                    && !matches!(self.state, Some(DeviceState::Active) | None)
            }
            _ => false,
        }
    }
}
