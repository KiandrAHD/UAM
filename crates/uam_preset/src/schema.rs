//! Serde data model for the portable preset format.
//!
//! Field names are camelCase in JSON to match the published schema. Numeric
//! values carry their unit in the field name; no implicit units are permitted.

use serde::{Deserialize, Serialize};

use crate::validation::ValidationLimits;

/// Stable top-level format identifier.
pub const FORMAT_ID: &str = "uam-preset";
/// Schema version implemented by this crate.
pub const CURRENT_SCHEMA_VERSION: u32 = 1;
/// Hard byte limit applied before JSON parsing.
pub const MAX_PRESET_BYTES: usize = 256 * 1024;

/// Supported portable filter shapes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FilterType {
    /// Symmetric peaking band.
    Peaking,
    /// Low-frequency shelf.
    LowShelf,
    /// High-frequency shelf.
    HighShelf,
}

impl From<FilterType> for uam_dsp::FilterKind {
    fn from(value: FilterType) -> Self {
        match value {
            FilterType::Peaking => Self::Peaking,
            FilterType::LowShelf => Self::LowShelf,
            FilterType::HighShelf => Self::HighShelf,
        }
    }
}

impl From<uam_dsp::FilterKind> for FilterType {
    fn from(value: uam_dsp::FilterKind) -> Self {
        match value {
            uam_dsp::FilterKind::Peaking => Self::Peaking,
            uam_dsp::FilterKind::LowShelf => Self::LowShelf,
            uam_dsp::FilterKind::HighShelf => Self::HighShelf,
        }
    }
}

/// One equalizer band in a portable preset.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EqBand {
    /// Filter shape.
    pub filter_type: FilterType,
    /// Centre or corner frequency in hertz.
    pub frequency_hz: f64,
    /// Band gain in decibels.
    pub gain_db: f64,
    /// Quality factor, or shelf transition-width control.
    pub q: f64,
}

/// Equalizer section of a preset.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EqualizerConfig {
    /// Ordered filter cascade. Order affects only floating-point rounding for
    /// linear filters, but is preserved for deterministic reproduction.
    pub bands: Vec<EqBand>,
}

/// Audio settings in a device-independent preset.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AudioSettings {
    /// Preamp gain in decibels.
    pub preamp_db: f64,
    /// Equalizer configuration.
    pub equalizer: EqualizerConfig,
}

/// Non-sensitive author-provided metadata.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PresetMetadata {
    /// Display name.
    pub name: String,
    /// Author label chosen by the user. Not an account identity.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    /// Free-text description.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// RFC 3339 creation timestamp. Schema validation is authoritative for the
    /// format; the Rust validator enforces length and control characters.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    /// Search/description tags.
    #[serde(default)]
    pub tags: Vec<String>,
}

/// Compatibility information used before importing a preset.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Compatibility {
    /// Oldest UAM version expected to understand the preset.
    pub minimum_uam_version: String,
    /// Portable presets must remain device-independent in schema version 1.
    pub device_independent: bool,
    /// Feature identifiers the preset expects the target to support.
    #[serde(default)]
    pub required_capabilities: Vec<String>,
}

/// One portable preset document.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Preset {
    /// Must equal [`FORMAT_ID`].
    pub format: String,
    /// Must equal [`CURRENT_SCHEMA_VERSION`] for this implementation.
    pub schema_version: u32,
    /// Author-facing metadata.
    pub metadata: PresetMetadata,
    /// Compatibility contract.
    pub compatibility: Compatibility,
    /// Audio settings.
    pub audio: AudioSettings,
}

impl Preset {
    /// Validate this preset against the Phase 0 contract.
    ///
    /// # Errors
    ///
    /// Returns [`crate::PresetError`] with the first violated rule. Import
    /// callers must treat any error as a rejection.
    pub fn validate(&self) -> Result<(), crate::PresetError> {
        crate::validation::validate_preset(self, &ValidationLimits::default())
    }
}
