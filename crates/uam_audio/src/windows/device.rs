//! MMDevice enumeration, endpoint properties, and mix-format parsing.

use windows::core::{GUID, PCWSTR};
use windows::Win32::Foundation::PROPERTYKEY;
use windows::Win32::Media::Audio::{
    eConsole, eRender, IAudioClient, IMMDevice, IMMDeviceEnumerator, DEVICE_STATE,
    DEVICE_STATE_ACTIVE, DEVICE_STATE_DISABLED, DEVICE_STATE_NOTPRESENT, DEVICE_STATE_UNPLUGGED,
    WAVEFORMATEX, WAVEFORMATEXTENSIBLE,
};
use windows::Win32::System::Com::StructuredStorage::{
    PropVariantClear, PropVariantToStringAlloc, PropVariantToUInt32,
};
use windows::Win32::System::Com::{CoTaskMemFree, CLSCTX_ALL, STGM_READ};
use windows::Win32::UI::Shell::PropertiesSystem::IPropertyStore;

use crate::config::{SampleEncoding, StreamFormat};
use crate::device::{
    DeviceListSnapshot, DeviceState, DeviceTransport, FormatProvenance, IdStability, OutputDevice,
};
use crate::error::{AudioError, AudioErrorCode};

/// `PKEY_Device_FriendlyName` = {a45c254e-df1c-4efd-8020-67d146a850e0}, 14.
const PKEY_DEVICE_FRIENDLY_NAME: PROPERTYKEY = PROPERTYKEY {
    fmtid: GUID::from_u128(0xa45c254e_df1c_4efd_8020_67d146a850e0),
    pid: 14,
};

/// `PKEY_AudioEndpoint_FormFactor` = {1da5d803-d492-4edd-8c23-e0c0ffee7f0e}, 0.
const PKEY_AUDIOENDPOINT_FORMFACTOR: PROPERTYKEY = PROPERTYKEY {
    fmtid: GUID::from_u128(0x1da5d803_d492_4edd_8c23_e0c0ffee7f0e),
    pid: 0,
};

/// `WAVE_FORMAT_PCM`.
const WAVE_FORMAT_PCM: u16 = 0x0001;
/// `WAVE_FORMAT_IEEE_FLOAT`.
const WAVE_FORMAT_IEEE_FLOAT: u16 = 0x0003;
/// `WAVE_FORMAT_EXTENSIBLE`.
const WAVE_FORMAT_EXTENSIBLE: u16 = 0xFFFE;

/// `KSDATAFORMAT_SUBTYPE_PCM`.
const KSDATAFORMAT_SUBTYPE_PCM: GUID = GUID::from_u128(0x00000001_0000_0010_8000_00aa00389b71);
/// `KSDATAFORMAT_SUBTYPE_IEEE_FLOAT`.
const KSDATAFORMAT_SUBTYPE_IEEE_FLOAT: GUID =
    GUID::from_u128(0x00000003_0000_0010_8000_00aa00389b71);

/// Enumerate active render endpoints into a normalized snapshot.
///
/// # Errors
///
/// Returns [`AudioErrorCode::DeviceEnumeration`] when the collection cannot be
/// read. A default endpoint that cannot be resolved is reported as `None`, which
/// is not an error.
pub fn enumerate_endpoints(
    enumerator: &IMMDeviceEnumerator,
) -> Result<DeviceListSnapshot, AudioError> {
    let default_id = default_endpoint_id(enumerator).unwrap_or(None);
    // SAFETY: `enumerator` is a live interface from the caller's apartment.
    let collection = unsafe { enumerator.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE) }
        .map_err(|error| {
            AudioError::new(
                AudioErrorCode::DeviceEnumeration,
                format!("EnumAudioEndpoints failed: {error:?}"),
            )
        })?;
    // SAFETY: the collection is live.
    let count = unsafe { collection.GetCount() }.map_err(|error| {
        AudioError::new(
            AudioErrorCode::DeviceEnumeration,
            format!("IMMDeviceCollection::GetCount failed: {error:?}"),
        )
    })?;

    let mut devices = Vec::with_capacity(count as usize);
    for index in 0..count {
        // SAFETY: index is within [0, count).
        let Ok(device) = (unsafe { collection.Item(index) }) else {
            continue;
        };
        let Ok(id) = read_device_id(&device) else {
            continue;
        };
        let display_name = friendly_name(&device);
        // SAFETY: the device is live.
        let state = unsafe { device.GetState() }.map_or(DeviceState::Unknown, map_device_state);
        let transport = form_factor_transport(&device);
        let is_default = default_id.as_deref() == Some(id.as_str());
        devices.push(OutputDevice {
            platform_id: id.clone(),
            id,
            display_name,
            transport,
            connection_state: state,
            is_default,
            id_stability: IdStability::StableAcrossSessions,
            format_summary: None,
            format_provenance: FormatProvenance::Unknown,
        });
    }

    Ok(DeviceListSnapshot {
        devices,
        default_id,
        enumeration_succeeded: true,
        reason: None,
    })
}

/// Read the current default render endpoint identifier, if any.
///
/// # Errors
///
/// This reports `Ok(None)` when no default endpoint exists; only a live
/// enumerator is required.
pub fn default_endpoint_id(enumerator: &IMMDeviceEnumerator) -> Result<Option<String>, AudioError> {
    // SAFETY: `enumerator` is a live interface.
    match unsafe { enumerator.GetDefaultAudioEndpoint(eRender, eConsole) } {
        Ok(device) => Ok(read_device_id(&device).ok()),
        Err(_) => Ok(None),
    }
}

/// Read an endpoint's mix format.
///
/// # Errors
///
/// Returns [`AudioErrorCode::InvalidEndpoint`] for an unknown identifier,
/// [`AudioErrorCode::AudioClientInit`] when the audio client cannot be
/// activated, and [`AudioErrorCode::UnsupportedFormat`] for a mix format this
/// backend cannot represent.
pub fn query_format(
    enumerator: &IMMDeviceEnumerator,
    device_id: &str,
) -> Result<StreamFormat, AudioError> {
    let device = get_device(enumerator, device_id)?;
    // SAFETY: the device is live and COM is initialized by the caller.
    unsafe {
        let client: IAudioClient = device.Activate(CLSCTX_ALL, None).map_err(|error| {
            AudioError::new(
                AudioErrorCode::AudioClientInit,
                format!("IAudioClient activation failed: {error:?}"),
            )
        })?;
        let mix = client.GetMixFormat().map_err(|error| {
            AudioError::new(
                AudioErrorCode::AudioClientInit,
                format!("GetMixFormat failed: {error:?}"),
            )
        })?;
        let parsed = stream_format_from_mix(mix);
        CoTaskMemFree(Some(mix.cast()));
        parsed
    }
}

/// Resolve an `IMMDevice` from an endpoint identifier.
///
/// # Errors
///
/// Returns [`AudioErrorCode::InvalidEndpoint`] when the identifier is not an
/// active endpoint identifier.
pub fn get_device(
    enumerator: &IMMDeviceEnumerator,
    device_id: &str,
) -> Result<IMMDevice, AudioError> {
    let wide: Vec<u16> = device_id.encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: `wide` is a NUL-terminated UTF-16 buffer that outlives the call.
    unsafe { enumerator.GetDevice(PCWSTR(wide.as_ptr())) }.map_err(|_| {
        AudioError::new(
            AudioErrorCode::InvalidEndpoint,
            format!("no active render endpoint matches {device_id}"),
        )
    })
}

/// Translate a `WAVEFORMATEX` pointer into a validated [`StreamFormat`].
///
/// # Errors
///
/// Returns [`AudioErrorCode::UnsupportedFormat`] for a tag, bit depth, or
/// container this backend cannot encode.
///
/// # Safety
///
/// `format` must point to a live `WAVEFORMATEX` (or `WAVEFORMATEXTENSIBLE` with
/// a matching `cbSize`) as returned by `IAudioClient::GetMixFormat`.
pub unsafe fn stream_format_from_mix(
    format: *const WAVEFORMATEX,
) -> Result<StreamFormat, AudioError> {
    if format.is_null() {
        return Err(AudioError::new(
            AudioErrorCode::UnsupportedFormat,
            "the endpoint returned a null mix format",
        ));
    }
    // SAFETY: the caller guarantees a live, sufficiently sized structure. The
    // packed structs are copied by value.
    let header: WAVEFORMATEX = unsafe { *format };
    let channels = header.nChannels;
    let sample_rate_hz = header.nSamplesPerSec;
    let container_bits = header.wBitsPerSample;
    let tag = header.wFormatTag;

    let (encoding, valid_bits) = if tag == WAVE_FORMAT_EXTENSIBLE && header.cbSize >= 22 {
        // SAFETY: `cbSize` confirms a full WAVEFORMATEXTENSIBLE payload.
        let extended: WAVEFORMATEXTENSIBLE = unsafe { *(format as *const WAVEFORMATEXTENSIBLE) };
        // SAFETY: reading packed fields uses unaligned reads; the pointer is
        // live and `cbSize` confirms the full extensible payload.
        let declared_valid =
            unsafe { core::ptr::addr_of!(extended.Samples.wValidBitsPerSample).read_unaligned() };
        let subformat = unsafe { core::ptr::addr_of!(extended.SubFormat).read_unaligned() };
        let valid_bits = if declared_valid == 0 {
            container_bits
        } else {
            declared_valid
        };
        if subformat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT {
            (SampleEncoding::F32, 32)
        } else if subformat == KSDATAFORMAT_SUBTYPE_PCM {
            (integer_encoding(container_bits)?, valid_bits)
        } else {
            return Err(AudioError::new(
                AudioErrorCode::UnsupportedFormat,
                "the endpoint uses a subformat other than IEEE float or PCM",
            ));
        }
    } else if tag == WAVE_FORMAT_IEEE_FLOAT {
        (SampleEncoding::F32, 32)
    } else if tag == WAVE_FORMAT_PCM {
        (integer_encoding(container_bits)?, container_bits)
    } else {
        return Err(AudioError::new(
            AudioErrorCode::UnsupportedFormat,
            format!("the endpoint uses unsupported format tag 0x{tag:04X}"),
        ));
    };

    StreamFormat::new(
        sample_rate_hz,
        channels,
        encoding,
        container_bits,
        valid_bits,
    )
}

/// Map a container bit depth to an integer encoding.
fn integer_encoding(bits: u16) -> Result<SampleEncoding, AudioError> {
    match bits {
        16 => Ok(SampleEncoding::S16),
        24 => Ok(SampleEncoding::S24),
        32 => Ok(SampleEncoding::S32),
        other => Err(AudioError::new(
            AudioErrorCode::UnsupportedFormat,
            format!("the endpoint uses an unsupported bit depth of {other} bits"),
        )),
    }
}

/// Read the endpoint identifier string.
fn read_device_id(device: &IMMDevice) -> Result<String, AudioError> {
    // SAFETY: the device is live; the returned string is owned by COM.
    let pwstr = unsafe { device.GetId() }.map_err(|error| {
        AudioError::new(
            AudioErrorCode::DeviceEnumeration,
            format!("IMMDevice::GetId failed: {error:?}"),
        )
    })?;
    // SAFETY: the pointer is a valid NUL-terminated UTF-16 string.
    let id = unsafe { pwstr.to_string() }.unwrap_or_default();
    // SAFETY: the string was allocated by COM and is freed exactly once here.
    unsafe { CoTaskMemFree(Some(pwstr.0.cast())) };
    if id.is_empty() {
        return Err(AudioError::new(
            AudioErrorCode::DeviceEnumeration,
            "an endpoint reported an empty identifier",
        ));
    }
    Ok(id)
}

/// Read `PKEY_Device_FriendlyName`, returning a placeholder on failure.
fn friendly_name(device: &IMMDevice) -> String {
    // SAFETY: the device is live and COM is initialized by the caller.
    unsafe {
        let Ok(store) = device.OpenPropertyStore(STGM_READ) else {
            return "<name unavailable>".to_owned();
        };
        let Ok(value) = store.GetValue(&PKEY_DEVICE_FRIENDLY_NAME) else {
            return "<name unavailable>".to_owned();
        };
        let name = match PropVariantToStringAlloc(&value) {
            Ok(pwstr) => {
                let text = pwstr
                    .to_string()
                    .unwrap_or_else(|_| "<invalid UTF-16>".to_owned());
                CoTaskMemFree(Some(pwstr.0.cast()));
                text
            }
            Err(_) => "<name unavailable>".to_owned(),
        };
        let mut value = value;
        let _ = PropVariantClear(&mut value);
        if name.is_empty() {
            "<unnamed endpoint>".to_owned()
        } else {
            name
        }
    }
}

/// Map `PKEY_AudioEndpoint_FormFactor` to a transport when it is meaningful.
fn form_factor_transport(device: &IMMDevice) -> DeviceTransport {
    // SAFETY: the device is live and COM is initialized by the caller.
    unsafe {
        let Ok(store): Result<IPropertyStore, _> = device.OpenPropertyStore(STGM_READ) else {
            return DeviceTransport::Unknown;
        };
        let Ok(value) = store.GetValue(&PKEY_AUDIOENDPOINT_FORMFACTOR) else {
            return DeviceTransport::Unknown;
        };
        let form_factor = PropVariantToUInt32(&value).unwrap_or(u32::MAX);
        let mut value = value;
        let _ = PropVariantClear(&mut value);
        match form_factor {
            // RemoteNetworkDevice
            0 => DeviceTransport::Network,
            // DigitalAudioDisplayDevice (HDMI/DisplayPort)
            9 => DeviceTransport::Hdmi,
            _ => DeviceTransport::Unknown,
        }
    }
}

/// Map a `DEVICE_STATE` bitmask to the normalized state.
fn map_device_state(state: DEVICE_STATE) -> DeviceState {
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
