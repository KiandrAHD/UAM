#![forbid(unsafe_code)]
//! Portable `.uam-preset.json` schema, validation, import, and export.
//!
//! Portable presets are device-independent by default. They contain metadata,
//! a preamp value, and an ordered EQ band list. They never contain executable
//! content, shell commands, credentials, vendor protocol frames, or Bluetooth
//! pairing material. Unknown fields are rejected so future additions require an
//! explicit schema-version decision.

pub mod adapter;
pub mod export;
pub mod import;
pub mod schema;
pub mod validation;

pub use adapter::PresetConversionError;
pub use export::to_json_string;
pub use import::{from_bytes, from_json_str};
pub use schema::{
    AudioSettings, Compatibility, EqBand, EqualizerConfig, FilterType, Preset, PresetMetadata,
    CURRENT_SCHEMA_VERSION, FORMAT_ID, MAX_PRESET_BYTES,
};
pub use validation::{PresetError, ValidationLimits};
