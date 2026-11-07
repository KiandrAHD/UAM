//! Control-path API surface exposed through the C ABI.
//!
//! Values reported here are derived from compile-time package metadata and
//! from the capabilities actually implemented in the workspace. They are not
//! user-configurable and must not claim hardware or platform support.

use serde::Serialize;

use crate::error::FfiError;

/// Capabilities implemented by the Phase 0 workspace and verified by tests.
pub const SUPPORTED_PROTOTYPE_FUNCTIONALITY: &[&str] = &[
    "bridge.engine_info",
    "dsp.eq.peaking",
    "dsp.eq.low_shelf",
    "dsp.eq.high_shelf",
    "dsp.preamp",
    "dsp.interleaved.f64.mono_stereo",
    "preset.uam-preset.schema_v1.validate",
    "preset.uam-preset.schema_v1.import_export",
];

/// Structured engine information returned to Flutter.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EngineInfo {
    /// Product name shared with the UI.
    pub product_name: &'static str,
    /// Rust core version from Cargo package metadata.
    pub core_engine_version: &'static str,
    /// C ABI contract version.
    pub bridge_abi_version: u32,
    /// Honest implementation stage label.
    pub rust_implementation_status: &'static str,
    /// Capabilities present in this build.
    pub supported_prototype_functionality: &'static [&'static str],
    /// Audio processing scope. Phase 0 does not attach to a system audio path.
    pub audio_processing_scope: &'static str,
}

/// Build the engine information payload.
#[must_use]
pub fn engine_info() -> EngineInfo {
    EngineInfo {
        product_name: uam_domain::PRODUCT_NAME,
        core_engine_version: uam_domain::CORE_ENGINE_VERSION,
        bridge_abi_version: uam_domain::BRIDGE_ABI_VERSION,
        rust_implementation_status: "prototype",
        supported_prototype_functionality: SUPPORTED_PROTOTYPE_FUNCTIONALITY,
        audio_processing_scope: "configuration_only",
    }
}

/// Serialize the engine information payload as compact UTF-8 JSON.
///
/// # Errors
///
/// Returns [`FfiError::Serialization`] if `serde_json` cannot encode the
/// payload. Static payloads are expected to serialize successfully.
pub fn engine_info_json() -> Result<String, FfiError> {
    serde_json::to_string(&engine_info()).map_err(FfiError::Serialization)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_info_uses_compile_time_values() {
        let info = engine_info();
        assert_eq!(info.product_name, uam_domain::PRODUCT_NAME);
        assert_eq!(info.core_engine_version, uam_domain::CORE_ENGINE_VERSION);
        assert_eq!(info.bridge_abi_version, uam_domain::BRIDGE_ABI_VERSION);
        assert_eq!(info.rust_implementation_status, "prototype");
        assert_eq!(info.audio_processing_scope, "configuration_only");
    }

    #[test]
    fn advertised_functionality_matches_phase_0_implementations() {
        for feature in [
            "dsp.eq.peaking",
            "dsp.eq.low_shelf",
            "dsp.eq.high_shelf",
            "dsp.preamp",
            "preset.uam-preset.schema_v1.validate",
        ] {
            assert!(
                SUPPORTED_PROTOTYPE_FUNCTIONALITY.contains(&feature),
                "missing advertised feature {feature}"
            );
        }
    }

    #[test]
    fn json_payload_contains_structured_fields() {
        let json = engine_info_json().expect("static payload serializes");
        let value: serde_json::Value = serde_json::from_str(&json).expect("valid JSON");
        assert_eq!(value["productName"], uam_domain::PRODUCT_NAME);
        assert_eq!(value["coreEngineVersion"], uam_domain::CORE_ENGINE_VERSION);
        assert_eq!(value["bridgeAbiVersion"], uam_domain::BRIDGE_ABI_VERSION);
        assert_eq!(value["audioProcessingScope"], "configuration_only");
        assert!(value["supportedPrototypeFunctionality"]
            .as_array()
            .expect("array")
            .iter()
            .any(|entry| entry == "dsp.eq.peaking"));
    }

    #[test]
    fn preset_validation_crate_is_linked_into_the_bridge_build() {
        let json = r#"{
          "format": "uam-preset",
          "schemaVersion": 1,
          "metadata": { "name": "Bridge Link Check" },
          "compatibility": { "minimumUamVersion": "0.1.0", "deviceIndependent": true },
          "audio": { "preampDb": 0.0, "equalizer": { "bands": [] } }
        }"#;
        assert!(uam_preset::from_json_str(json).is_ok());
    }
}
