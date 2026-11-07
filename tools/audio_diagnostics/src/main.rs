//! Phase 0 read-only Windows audio endpoint diagnostics.
//!
//! This tool enumerates Windows audio endpoints through the MMDevice API, the
//! same device layer that a future UAM Windows audio backend builds on. It
//! opens **no** audio stream, captures **no** audio, and changes nothing. It
//! only proves that Rust can reach the Windows audio device enumeration API and
//! read device friendly names and states.
//!
//! Output contains real, machine-specific device names. Do not commit captured
//! output to the repository; see `README.md`.

use std::process::ExitCode;

use windows::core::GUID;
use windows::Win32::Foundation::PROPERTYKEY;
use windows::Win32::Media::Audio::{
    eCapture, eRender, IMMDevice, IMMDeviceCollection, IMMDeviceEnumerator, MMDeviceEnumerator,
    DEVICE_STATE_ACTIVE, DEVICE_STATE_DISABLED, DEVICE_STATE_NOTPRESENT, DEVICE_STATE_UNPLUGGED,
};
use windows::Win32::System::Com::StructuredStorage::PropVariantToStringAlloc;
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_ALL, COINIT_MULTITHREADED, STGM_READ,
};

/// `PKEY_Device_FriendlyName` = {a45c254e-df1c-4efd-8020-67d146a850e0}, 14.
/// Defined here directly so the tool does not depend on a shell-property crate.
const PKEY_DEVICE_FRIENDLY_NAME: PROPERTYKEY = PROPERTYKEY {
    fmtid: GUID::from_u128(0xa45c254e_df1c_4efd_8020_67d146a850e0),
    pid: 14,
};

fn device_state_label(state: u32) -> String {
    let mut labels = Vec::new();
    if state & DEVICE_STATE_ACTIVE.0 != 0 {
        labels.push("ACTIVE");
    }
    if state & DEVICE_STATE_DISABLED.0 != 0 {
        labels.push("DISABLED");
    }
    if state & DEVICE_STATE_NOTPRESENT.0 != 0 {
        labels.push("NOTPRESENT");
    }
    if state & DEVICE_STATE_UNPLUGGED.0 != 0 {
        labels.push("UNPLUGGED");
    }
    if labels.is_empty() {
        labels.push("UNKNOWN");
    }
    labels.join("|")
}

/// Read `PKEY_Device_FriendlyName` from an endpoint's property store.
///
/// # Safety
///
/// `device` must be a valid `IMMDevice` obtained from an enumerator in the same
/// COM apartment.
unsafe fn friendly_name(device: &IMMDevice) -> String {
    let Ok(store) = device.OpenPropertyStore(STGM_READ) else {
        return "<property store unavailable>".to_owned();
    };
    let Ok(value) = store.GetValue(&PKEY_DEVICE_FRIENDLY_NAME) else {
        return "<friendly name unavailable>".to_owned();
    };
    match PropVariantToStringAlloc(&value) {
        Ok(pwstr) => {
            let name = pwstr
                .to_string()
                .unwrap_or_else(|_| "<invalid UTF-16>".to_owned());
            // SAFETY: pwstr was allocated by PropVariantToStringAlloc and is
            // freed exactly once here.
            windows::Win32::System::Com::CoTaskMemFree(Some(pwstr.0.cast()));
            name
        }
        Err(_) => "<not a string property>".to_owned(),
    }
}

/// Enumerate one data-flow direction and return the endpoint count.
///
/// # Safety
///
/// `collection` must be a valid `IMMDeviceCollection`.
unsafe fn enumerate(collection: &IMMDeviceCollection, label: &str) -> u32 {
    let count = collection.GetCount().unwrap_or(0);
    println!("== {label}: {count} endpoint(s) ==");
    for index in 0..count {
        let Ok(device) = collection.Item(index) else {
            println!("  [{index}] <device unavailable>");
            continue;
        };
        let state = device.GetState().map(|s| s.0).unwrap_or(0);
        let name = friendly_name(&device);
        println!(
            "  [{index}] state={} name={name}",
            device_state_label(state)
        );
    }
    count
}

fn run() -> windows::core::Result<()> {
    // SAFETY: COM is initialized for the lifetime of this call and balanced by
    // CoUninitialize before return. All device objects are released before then.
    unsafe {
        // S_FALSE from a re-initialize is a success value, so `.ok()` is correct.
        CoInitializeEx(None, COINIT_MULTITHREADED).ok()?;
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;

        let render = enumerator.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)?;
        let render_active = enumerate(&render, "Render endpoints (ACTIVE)");

        let capture = enumerator.EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE)?;
        let capture_active = enumerate(&capture, "Capture endpoints (ACTIVE)");

        println!(
            "phase0_wasapi_probe_ok render_active={render_active} capture_active={capture_active}"
        );

        CoUninitialize();
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("phase0_wasapi_probe_failed: {error:?}");
            ExitCode::FAILURE
        }
    }
}
