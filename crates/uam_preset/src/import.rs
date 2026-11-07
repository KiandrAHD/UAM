//! Safe preset import boundary.
//!
//! Byte-size, UTF-8, JSON, schema-version, and value validation all happen
//! before a caller receives a [`Preset`]. Imported files are untrusted input.

use crate::schema::{Preset, MAX_PRESET_BYTES};
use crate::validation::{validate_preset, PresetError, ValidationLimits};

/// Parse and validate a UTF-8 JSON preset document.
///
/// # Errors
///
/// Returns [`PresetError`] when the document is too large, not valid JSON, uses
/// an unsupported schema version, or violates any field constraint.
pub fn from_json_str(input: &str) -> Result<Preset, PresetError> {
    if input.len() > MAX_PRESET_BYTES {
        return Err(PresetError::TooLarge {
            bytes: input.len(),
            maximum: MAX_PRESET_BYTES,
        });
    }

    let preset: Preset =
        serde_json::from_str(input).map_err(|error| PresetError::InvalidJson(error.to_string()))?;
    validate_preset(&preset, &ValidationLimits::default())?;
    Ok(preset)
}

/// Parse and validate a byte buffer as a UTF-8 JSON preset document.
///
/// # Errors
///
/// Returns [`PresetError::TooLarge`] before UTF-8 decoding when the input
/// exceeds the hard limit, and otherwise behaves like [`from_json_str`].
pub fn from_bytes(input: &[u8]) -> Result<Preset, PresetError> {
    if input.len() > MAX_PRESET_BYTES {
        return Err(PresetError::TooLarge {
            bytes: input.len(),
            maximum: MAX_PRESET_BYTES,
        });
    }
    let text = core::str::from_utf8(input)
        .map_err(|error| PresetError::InvalidJson(format!("input is not valid UTF-8: {error}")))?;
    from_json_str(text)
}
