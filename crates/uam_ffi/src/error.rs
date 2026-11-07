//! Errors internal to the FFI facade.
//!
//! Errors are converted to a null pointer at the C boundary in Phase 0. They
//! never cross the ABI as Rust types.

use core::fmt;

/// Internal bridge failure.
#[derive(Debug)]
pub enum FfiError {
    /// JSON serialization failed.
    Serialization(serde_json::Error),
}

impl fmt::Display for FfiError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Serialization(error) => write!(formatter, "serialization failed: {error}"),
        }
    }
}

impl std::error::Error for FfiError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Serialization(error) => Some(error),
        }
    }
}
