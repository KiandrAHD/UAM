#![deny(unsafe_op_in_unsafe_fn)]
#![deny(unsafe_code)]
//! Narrow C ABI facade for the Flutter application.
//!
//! Phase 0 exposes two control-path functions:
//!
//! - `uam_get_engine_info` returns a UTF-8 JSON object describing the compiled
//!   core.
//! - `uam_string_free` releases strings allocated by this library.
//!
//! Real-time audio buffers are intentionally not exposed. The Flutter side
//! must never shuttle individual frames through Dart FFI; a future audio
//! backend will own the callback inside the native layer.
//!
//! The FFI module is the only place where `unsafe` is permitted. It is limited
//! to pointer ownership transfer and freeing. Every `unsafe` block is preceded
//! by a safety comment and every exported pointer has an explicit owner.

use core::ffi::c_char;
use std::ffi::CString;

pub mod api;
pub mod error;

pub use api::{EngineInfo, SUPPORTED_PROTOTYPE_FUNCTIONALITY};

/// Returns the C ABI contract version.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_abi_version() -> u32 {
    uam_domain::BRIDGE_ABI_VERSION
}

/// Returns a newly allocated UTF-8 JSON string describing the engine.
///
/// The caller owns the returned pointer and must release it with
/// [`uam_string_free`]. The function returns a null pointer if the payload
/// cannot be serialized or contains an interior NUL byte. A null return is an
/// internal failure, not a valid response.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub extern "C" fn uam_get_engine_info() -> *mut c_char {
    api::engine_info_json()
        .ok()
        .and_then(|json| CString::new(json).ok())
        .map_or(std::ptr::null_mut(), CString::into_raw)
}

/// Frees a string previously returned by this library.
///
/// # Safety
///
/// `pointer` must be null or a pointer produced by
/// [`uam_get_engine_info`] that has not already been freed. Passing any other
/// pointer is undefined behaviour. Null is accepted and ignored.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn uam_string_free(pointer: *mut c_char) {
    if pointer.is_null() {
        return;
    }
    // SAFETY: the caller contract requires a pointer created by
    // `CString::into_raw` in this library and not previously freed.
    unsafe {
        drop(CString::from_raw(pointer));
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_is_exported() {
        assert_eq!(uam_abi_version(), uam_domain::BRIDGE_ABI_VERSION);
    }

    #[test]
    fn engine_info_pointer_can_be_freed() {
        let pointer = uam_get_engine_info();
        assert!(!pointer.is_null());
        // SAFETY: the pointer was allocated by `uam_get_engine_info` and is
        // freed exactly once here.
        unsafe {
            uam_string_free(pointer);
        }
    }

    #[test]
    fn freeing_null_is_a_noop() {
        // SAFETY: null is explicitly accepted by the contract.
        unsafe {
            uam_string_free(std::ptr::null_mut());
        }
    }
}
