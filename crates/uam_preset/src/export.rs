//! Portable preset export.
//!
//! Export validates the in-memory preset before serialization so UAM cannot
//! write a document that its own importer would reject.

use crate::schema::Preset;
use crate::validation::{validate_preset, PresetError, ValidationLimits};

/// Serialize a preset as pretty-printed JSON with a trailing newline.
///
/// # Errors
///
/// Returns [`PresetError`] when the preset is invalid or serialization fails.
pub fn to_json_string(preset: &Preset) -> Result<String, PresetError> {
    validate_preset(preset, &ValidationLimits::default())?;
    let mut json = serde_json::to_string_pretty(preset)
        .map_err(|error| PresetError::Serialization(error.to_string()))?;
    json.push('\n');
    Ok(json)
}
