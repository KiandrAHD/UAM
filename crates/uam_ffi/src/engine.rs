#![allow(unsafe_code)]
//! Audio engine bridge: opaque handles plus JSON envelopes.
//!
//! # Contract
//!
//! Every engine function crosses the ABI as one owned UTF-8 JSON string, which
//! the caller releases with [`crate::uam_string_free`]. The envelope is:
//!
//! ```json
//! { "ok": true,  "error": null, "data": <payload> }
//! { "ok": false, "error": { "code": "<stable code>", "message": "<text>" }, "data": null }
//! ```
//!
//! Engines are addressed by an opaque `u64` handle. Handles are only ever
//! produced by [`uam_audio_engine_create`] and must be released with
//! [`uam_audio_engine_destroy`].
//!
//! # Safety at the boundary
//!
//! Each exported function wraps its body in `catch_unwind`, so a panic cannot
//! unwind across the C ABI; it becomes an `internal` error envelope instead.
//! Input strings are borrowed for the duration of the call only.

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

use serde_json::{json, Value};

use uam_audio::config::{DspRequest, TestToneConfig};
use uam_audio::engine::AudioEngine;

/// A bridge failure that becomes an error envelope.
struct BridgeError {
    code: String,
    message: String,
}

impl BridgeError {
    fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }

    fn invalid_argument(message: impl Into<String>) -> Self {
        Self::new("invalid_argument", message)
    }

    fn invalid_handle() -> Self {
        Self::new(
            "handle_invalid",
            "the audio engine handle is not registered",
        )
    }

    fn internal(message: impl Into<String>) -> Self {
        Self::new("internal", message)
    }
}

impl From<uam_audio::AudioError> for BridgeError {
    fn from(error: uam_audio::AudioError) -> Self {
        Self::new(error.code.as_str(), error.message)
    }
}

/// Global registry of live engines, keyed by opaque handle.
fn registry() -> &'static Mutex<HashMap<u64, AudioEngine>> {
    static REGISTRY: OnceLock<Mutex<HashMap<u64, AudioEngine>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Next handle to hand out. Zero is reserved for "no engine".
fn next_handle() -> u64 {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

/// Run `operation` under a panic guard and encode its result as an envelope.
fn guard(operation: impl FnOnce() -> Result<Value, BridgeError>) -> *mut c_char {
    let outcome = catch_unwind(AssertUnwindSafe(operation));
    let envelope = match outcome {
        Ok(Ok(data)) => json!({ "ok": true, "error": Value::Null, "data": data }),
        Ok(Err(error)) => json!({
            "ok": false,
            "error": { "code": error.code, "message": error.message },
            "data": Value::Null,
        }),
        Err(_) => json!({
            "ok": false,
            "error": { "code": "internal", "message": "the audio bridge panicked" },
            "data": Value::Null,
        }),
    };
    into_c_string(envelope.to_string())
}

/// Convert a serialized envelope into an owned C string.
fn into_c_string(text: String) -> *mut c_char {
    CString::new(text).map_or(std::ptr::null_mut(), CString::into_raw)
}

/// Run `operation` with the engine registered under `handle`.
fn with_engine<R>(
    handle: u64,
    operation: impl FnOnce(&mut AudioEngine) -> R,
) -> Result<R, BridgeError> {
    let mut map = registry()
        .lock()
        .map_err(|_| BridgeError::internal("the engine registry lock is poisoned"))?;
    let engine = map
        .get_mut(&handle)
        .ok_or_else(BridgeError::invalid_handle)?;
    Ok(operation(engine))
}

/// Borrow a NUL-terminated UTF-8 input string.
///
/// # Safety
///
/// `pointer` must be null or point to a NUL-terminated byte string that is valid
/// for the duration of the call.
unsafe fn read_cstr(pointer: *const c_char) -> Result<String, BridgeError> {
    if pointer.is_null() {
        return Err(BridgeError::invalid_argument(
            "expected a UTF-8 string, got null",
        ));
    }
    // SAFETY: the caller guarantees a NUL-terminated, valid-for-this-call string.
    let cstr = unsafe { CStr::from_ptr(pointer) };
    cstr.to_str()
        .map(str::to_owned)
        .map_err(|_| BridgeError::invalid_argument("the string was not valid UTF-8"))
}

/// Create an audio engine and return its handle.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_create() -> *mut c_char {
    guard(|| {
        let engine = AudioEngine::new();
        let handle = next_handle();
        registry()
            .lock()
            .map_err(|_| BridgeError::internal("the engine registry lock is poisoned"))?
            .insert(handle, engine);
        Ok(json!({ "handle": handle }))
    })
}

/// Destroy a previously created audio engine.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_destroy(handle: u64) -> *mut c_char {
    guard(|| {
        let removed = registry()
            .lock()
            .map_err(|_| BridgeError::internal("the engine registry lock is poisoned"))?
            .remove(&handle);
        if removed.is_none() {
            return Err(BridgeError::invalid_handle());
        }
        Ok(Value::Null)
    })
}

/// Return a complete status snapshot.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_status(handle: u64) -> *mut c_char {
    guard(|| {
        let status = with_engine(handle, |engine| engine.status())?;
        serde_json::to_value(status).map_err(|error| BridgeError::internal(error.to_string()))
    })
}

/// Enumerate active render endpoints.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_enumerate(handle: u64) -> *mut c_char {
    guard(|| {
        let snapshot = with_engine(handle, |engine| engine.devices())??;
        serde_json::to_value(snapshot).map_err(|error| BridgeError::internal(error.to_string()))
    })
}

/// Return the current default render endpoint identifier.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_default_device(handle: u64) -> *mut c_char {
    guard(|| {
        let default = with_engine(handle, |engine| engine.default_device_id())??;
        Ok(json!({ "defaultId": default }))
    })
}

/// Select a render endpoint and resolve its stream format.
///
/// # Safety
///
/// `device_id` must be null or a NUL-terminated UTF-8 string valid for the call.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn uam_audio_engine_select_device(
    handle: u64,
    device_id: *const c_char,
) -> *mut c_char {
    guard(move || {
        // SAFETY: the caller guarantees the string contract.
        let device_id = unsafe { read_cstr(device_id) }?;
        let format = with_engine(handle, |engine| engine.select_device(&device_id))??;
        let format = engine_format_summary(format)?;
        Ok(json!({ "format": format }))
    })
}

/// Apply a DSP configuration request (`DspRequest` JSON).
///
/// # Safety
///
/// `request_json` must be null or a NUL-terminated UTF-8 string valid for the
/// call.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn uam_audio_engine_configure(
    handle: u64,
    request_json: *const c_char,
) -> *mut c_char {
    guard(move || {
        // SAFETY: the caller guarantees the string contract.
        let text = unsafe { read_cstr(request_json) }?;
        let request: DspRequest = serde_json::from_str(&text)
            .map_err(|error| BridgeError::invalid_argument(error.to_string()))?;
        with_engine(handle, |engine| engine.configure(request))??;
        Ok(Value::Null)
    })
}

/// Start the render stream.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_start(handle: u64) -> *mut c_char {
    guard(|| {
        with_engine(handle, |engine| engine.start())??;
        Ok(Value::Null)
    })
}

/// Stop the render stream.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_stop(handle: u64) -> *mut c_char {
    guard(|| {
        with_engine(handle, |engine| engine.stop())?;
        Ok(Value::Null)
    })
}

/// Request a bypass change. `bypassed` is a C `uint8_t` treated as boolean.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_set_bypass(handle: u64, bypassed: u8) -> *mut c_char {
    guard(move || {
        with_engine(handle, |engine| engine.set_bypass(bypassed != 0))?;
        Ok(Value::Null)
    })
}

/// Enable or disable the diagnostic test tone.
///
/// # Safety
///
/// `tone_json` must be null (disable the tone) or a NUL-terminated UTF-8
/// `TestToneConfig` object valid for the call.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn uam_audio_engine_set_test_tone(
    handle: u64,
    tone_json: *const c_char,
) -> *mut c_char {
    guard(move || {
        let tone = if tone_json.is_null() {
            None
        } else {
            // SAFETY: the caller guarantees the string contract.
            let text = unsafe { read_cstr(tone_json) }?;
            let tone: TestToneConfig = serde_json::from_str(&text)
                .map_err(|error| BridgeError::invalid_argument(error.to_string()))?;
            Some(tone)
        };
        with_engine(handle, |engine| engine.set_test_tone(tone))??;
        Ok(Value::Null)
    })
}

/// Drain endpoint change notifications collected since the last call.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_device_events(handle: u64) -> *mut c_char {
    guard(|| {
        let events = with_engine(handle, |engine| engine.drain_device_events())?;
        let events = serde_json::to_value(events)
            .map_err(|error| BridgeError::internal(error.to_string()))?;
        Ok(json!({ "events": events }))
    })
}

/// Ensure endpoint notifications are subscribed.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_audio_engine_subscribe(handle: u64) -> *mut c_char {
    guard(|| {
        with_engine(handle, |engine| engine.subscribe())??;
        Ok(Value::Null)
    })
}

/// Serialize an engine format summary through the bridge.
fn engine_format_summary(format: uam_audio::StreamFormat) -> Result<Value, BridgeError> {
    let summary = json!({
        "sampleRateHz": format.sample_rate_hz(),
        "channels": format.channels(),
        "encoding": format.encoding().as_str(),
        "containerBits": format.container_bits(),
        "validBits": format.valid_bits(),
        "summary": format.summary(),
    });
    Ok(summary)
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;

    /// Read an envelope JSON string from a raw pointer and free it.
    unsafe fn take(pointer: *mut c_char) -> Value {
        assert!(!pointer.is_null(), "bridge returned null");
        // SAFETY: the pointer is owned by the caller and freed once here.
        let text = unsafe { CStr::from_ptr(pointer) }
            .to_str()
            .expect("valid UTF-8")
            .to_owned();
        // SAFETY: matches the allocation made by the bridge.
        unsafe { crate::uam_string_free(pointer) };
        serde_json::from_str(&text).expect("valid envelope JSON")
    }

    #[test]
    fn create_and_destroy_round_trips_a_handle() {
        // SAFETY: create returns an owned envelope; destroy is balanced.
        let create = unsafe { take(uam_audio_engine_create()) };
        assert_eq!(create["ok"], true);
        let handle = create["data"]["handle"].as_u64().expect("handle");
        assert!(handle >= 1);
        let destroy = unsafe { take(uam_audio_engine_destroy(handle)) };
        assert_eq!(destroy["ok"], true);
        let again = unsafe { take(uam_audio_engine_destroy(handle)) };
        assert_eq!(again["ok"], false);
        assert_eq!(again["error"]["code"], "handle_invalid");
    }

    #[test]
    fn status_of_unknown_handle_is_an_error_envelope() {
        let value = unsafe { take(uam_audio_engine_status(9_999_999)) };
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "handle_invalid");
    }

    #[test]
    fn status_envelope_carries_state_and_scope() {
        let create = unsafe { take(uam_audio_engine_create()) };
        let handle = create["data"]["handle"].as_u64().expect("handle");
        let status = unsafe { take(uam_audio_engine_status(handle)) };
        assert_eq!(status["ok"], true);
        assert!(status["data"]["state"].is_string());
        assert!(status["data"]["scope"].is_string());
        assert!(status["data"]["metrics"].is_object());
        unsafe { take(uam_audio_engine_destroy(handle)) };
    }

    #[test]
    fn invalid_json_configuration_is_rejected() {
        let create = unsafe { take(uam_audio_engine_create()) };
        let handle = create["data"]["handle"].as_u64().expect("handle");
        let bad = CString::new("{ not json").unwrap();
        let value = unsafe { take(uam_audio_engine_configure(handle, bad.as_ptr())) };
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "invalid_argument");
        unsafe { take(uam_audio_engine_destroy(handle)) };
    }

    #[test]
    fn by_hand_engine_is_not_attached_until_started() {
        let create = unsafe { take(uam_audio_engine_create()) };
        let handle = create["data"]["handle"].as_u64().expect("handle");
        let status = unsafe { take(uam_audio_engine_status(handle)) };
        // Without a selected endpoint the engine reports configuration only.
        assert_eq!(status["data"]["scope"], "configuration_only");
        unsafe { take(uam_audio_engine_destroy(handle)) };
    }
}
