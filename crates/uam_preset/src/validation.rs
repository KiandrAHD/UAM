//! Import-boundary validation for portable presets.
//!
//! Validation is intentionally redundant with the JSON Schema: the schema
//! protects external tooling and documents the contract, while this module
//! protects the Rust core regardless of how a [`crate::Preset`] value was
//! constructed.

use core::fmt;
use std::collections::HashSet;

use uam_dsp::{
    BandConfig, DspError, MAX_BANDS, MAX_GAIN_DB, MAX_PREAMP_DB, MIN_GAIN_DB, MIN_PREAMP_DB,
};

use crate::schema::{Preset, CURRENT_SCHEMA_VERSION, FORMAT_ID, MAX_PRESET_BYTES};

/// Tunable string limits used by validation and tests.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ValidationLimits {
    /// Maximum characters in `metadata.name`.
    pub max_name_chars: usize,
    /// Maximum characters in `metadata.author`.
    pub max_author_chars: usize,
    /// Maximum characters in `metadata.description`.
    pub max_description_chars: usize,
    /// Maximum number of tags.
    pub max_tags: usize,
    /// Maximum characters per tag.
    pub max_tag_chars: usize,
    /// Maximum number of EQ bands.
    pub max_bands: usize,
    /// Maximum number of required capability identifiers.
    pub max_required_capabilities: usize,
    /// Maximum characters in `metadata.createdAt`.
    pub max_created_at_chars: usize,
    /// Maximum preset document size in bytes.
    pub max_preset_bytes: usize,
}

impl Default for ValidationLimits {
    fn default() -> Self {
        Self {
            max_name_chars: 80,
            max_author_chars: 80,
            max_description_chars: 1_000,
            max_tags: 10,
            max_tag_chars: 32,
            max_bands: MAX_BANDS,
            max_required_capabilities: 16,
            max_created_at_chars: 40,
            max_preset_bytes: MAX_PRESET_BYTES,
        }
    }
}

/// A preset validation or import failure.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PresetError {
    /// Input exceeded the configured byte limit before parsing.
    TooLarge {
        /// Supplied byte count.
        bytes: usize,
        /// Allowed byte count.
        maximum: usize,
    },
    /// Input was not valid UTF-8 or valid JSON.
    InvalidJson(String),
    /// Top-level `format` was not [`FORMAT_ID`].
    InvalidFormat {
        /// Supplied identifier.
        found: String,
    },
    /// Schema version is not implemented by this build.
    UnsupportedSchemaVersion {
        /// Supplied version.
        found: u32,
    },
    /// A field violated a documented constraint.
    InvalidField {
        /// JSON field or array element path.
        field: String,
        /// Human-readable reason with no sensitive values.
        reason: String,
    },
    /// Compatibility metadata requests behaviour this build cannot honour.
    UnsupportedCompatibility(String),
    /// Serialization failed after validation.
    Serialization(String),
}

impl fmt::Display for PresetError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::TooLarge { bytes, maximum } => {
                write!(formatter, "preset is {bytes} bytes; the maximum is {maximum}")
            }
            Self::InvalidJson(reason) => write!(formatter, "invalid preset JSON: {reason}"),
            Self::InvalidFormat { found } => write!(
                formatter,
                "format '{found}' is not the required '{FORMAT_ID}'"
            ),
            Self::UnsupportedSchemaVersion { found } => write!(
                formatter,
                "schema version {found} is not supported; this build implements {CURRENT_SCHEMA_VERSION}"
            ),
            Self::InvalidField { field, reason } => {
                write!(formatter, "invalid field '{field}': {reason}")
            }
            Self::UnsupportedCompatibility(reason) => {
                write!(formatter, "unsupported preset compatibility: {reason}")
            }
            Self::Serialization(reason) => {
                write!(formatter, "preset serialization failed: {reason}")
            }
        }
    }
}

impl std::error::Error for PresetError {}

pub(crate) fn validate_preset(
    preset: &Preset,
    limits: &ValidationLimits,
) -> Result<(), PresetError> {
    if preset.format != FORMAT_ID {
        return Err(PresetError::InvalidFormat {
            found: preset.format.clone(),
        });
    }
    if preset.schema_version != CURRENT_SCHEMA_VERSION {
        return Err(PresetError::UnsupportedSchemaVersion {
            found: preset.schema_version,
        });
    }

    validate_text(
        "metadata.name",
        &preset.metadata.name,
        true,
        1,
        limits.max_name_chars,
    )?;
    if let Some(author) = &preset.metadata.author {
        validate_text("metadata.author", author, false, 1, limits.max_author_chars)?;
    }
    if let Some(description) = &preset.metadata.description {
        validate_text(
            "metadata.description",
            description,
            true,
            0,
            limits.max_description_chars,
        )?;
    }
    if let Some(created_at) = &preset.metadata.created_at {
        validate_text(
            "metadata.createdAt",
            created_at,
            false,
            1,
            limits.max_created_at_chars,
        )?;
    }

    if preset.metadata.tags.len() > limits.max_tags {
        return Err(PresetError::InvalidField {
            field: "metadata.tags".to_owned(),
            reason: format!(
                "{} tags supplied; at most {} are allowed",
                preset.metadata.tags.len(),
                limits.max_tags
            ),
        });
    }
    let mut seen_tags = HashSet::new();
    for (index, tag) in preset.metadata.tags.iter().enumerate() {
        validate_text(
            &format!("metadata.tags[{index}]"),
            tag,
            false,
            1,
            limits.max_tag_chars,
        )?;
        if !seen_tags.insert(tag) {
            return Err(PresetError::InvalidField {
                field: format!("metadata.tags[{index}]"),
                reason: "duplicate tag".to_owned(),
            });
        }
    }

    if !is_semver(&preset.compatibility.minimum_uam_version) {
        return Err(PresetError::InvalidField {
            field: "compatibility.minimumUamVersion".to_owned(),
            reason: "expected a three-component numeric version such as 0.1.0".to_owned(),
        });
    }
    if !preset.compatibility.device_independent {
        return Err(PresetError::UnsupportedCompatibility(
            "schema version 1 portable presets must set deviceIndependent to true".to_owned(),
        ));
    }
    if preset.compatibility.required_capabilities.len() > limits.max_required_capabilities {
        return Err(PresetError::InvalidField {
            field: "compatibility.requiredCapabilities".to_owned(),
            reason: format!(
                "{} entries supplied; at most {} are allowed",
                preset.compatibility.required_capabilities.len(),
                limits.max_required_capabilities
            ),
        });
    }
    let mut seen_capabilities = HashSet::new();
    for (index, capability) in preset
        .compatibility
        .required_capabilities
        .iter()
        .enumerate()
    {
        if capability.is_empty()
            || capability.len() > 64
            || !capability.chars().all(|character| {
                character.is_ascii_lowercase()
                    || character.is_ascii_digit()
                    || matches!(character, '.' | '_' | ':' | '-')
            })
        {
            return Err(PresetError::InvalidField {
                field: format!("compatibility.requiredCapabilities[{index}]"),
                reason: "expected 1..=64 characters from [a-z0-9._:-]".to_owned(),
            });
        }
        if !seen_capabilities.insert(capability) {
            return Err(PresetError::InvalidField {
                field: format!("compatibility.requiredCapabilities[{index}]"),
                reason: "duplicate capability identifier".to_owned(),
            });
        }
    }

    if !preset.audio.preamp_db.is_finite() {
        return Err(PresetError::InvalidField {
            field: "audio.preampDb".to_owned(),
            reason: "must be finite".to_owned(),
        });
    }
    if !(MIN_PREAMP_DB..=MAX_PREAMP_DB).contains(&preset.audio.preamp_db) {
        return Err(PresetError::InvalidField {
            field: "audio.preampDb".to_owned(),
            reason: format!("must be within {MIN_PREAMP_DB}..={MAX_PREAMP_DB} dB"),
        });
    }

    if preset.audio.equalizer.bands.len() > limits.max_bands {
        return Err(PresetError::InvalidField {
            field: "audio.equalizer.bands".to_owned(),
            reason: format!(
                "{} bands supplied; at most {} are allowed",
                preset.audio.equalizer.bands.len(),
                limits.max_bands
            ),
        });
    }

    for (index, band) in preset.audio.equalizer.bands.iter().enumerate() {
        let field = format!("audio.equalizer.bands[{index}]");
        BandConfig::new(
            band.filter_type.into(),
            band.frequency_hz,
            band.gain_db,
            band.q,
        )
        .map_err(|error| map_band_error(&field, error))?;
    }

    Ok(())
}

fn map_band_error(field: &str, error: DspError) -> PresetError {
    let reason = match error {
        DspError::FrequencyTooHigh {
            frequency_hz,
            maximum_hz,
        } if frequency_hz > uam_dsp::MAX_FREQUENCY_HZ => {
            format!("frequency {frequency_hz} Hz exceeds the portable maximum {maximum_hz} Hz")
        }
        DspError::GainOutOfRange { gain_db } => {
            format!("gain {gain_db} dB must be within {MIN_GAIN_DB}..={MAX_GAIN_DB} dB")
        }
        other => other.to_string(),
    };
    PresetError::InvalidField {
        field: field.to_owned(),
        reason,
    }
}

fn validate_text(
    field: &str,
    value: &str,
    allow_newlines: bool,
    minimum_chars: usize,
    maximum_chars: usize,
) -> Result<(), PresetError> {
    let character_count = value.chars().count();
    if character_count < minimum_chars {
        return Err(PresetError::InvalidField {
            field: field.to_owned(),
            reason: "must not be empty".to_owned(),
        });
    }
    if character_count > maximum_chars {
        return Err(PresetError::InvalidField {
            field: field.to_owned(),
            reason: format!("must contain at most {maximum_chars} characters"),
        });
    }
    if value.trim().is_empty() && minimum_chars > 0 {
        return Err(PresetError::InvalidField {
            field: field.to_owned(),
            reason: "must not contain only whitespace".to_owned(),
        });
    }
    let has_forbidden_control = value.chars().any(|character| {
        character.is_control() && !(allow_newlines && matches!(character, '\n' | '\r' | '\t'))
    });
    if has_forbidden_control {
        return Err(PresetError::InvalidField {
            field: field.to_owned(),
            reason: "must not contain control characters".to_owned(),
        });
    }
    Ok(())
}

fn is_semver(value: &str) -> bool {
    let mut components = 0_usize;
    for component in value.split('.') {
        components += 1;
        if component.is_empty()
            || !component.bytes().all(|byte| byte.is_ascii_digit())
            || (component.len() > 1 && component.starts_with('0'))
            || component.parse::<u32>().is_err()
        {
            return false;
        }
    }
    components == 3
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn semver_requires_three_numeric_components() {
        for valid in ["0.1.0", "1.0.0", "10.20.30"] {
            assert!(is_semver(valid), "{valid} should be valid");
        }
        for invalid in ["1", "1.0", "1.0.0.0", "v1.0.0", "01.0.0", "1.0.x", ""] {
            assert!(!is_semver(invalid), "{invalid} should be invalid");
        }
    }

    #[test]
    fn text_limits_count_characters_not_bytes() {
        assert!(validate_text("field", "éé", false, 1, 2).is_ok());
        assert!(validate_text("field", "ééé", false, 1, 2).is_err());
    }
}
