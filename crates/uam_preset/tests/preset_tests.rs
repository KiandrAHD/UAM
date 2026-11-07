use std::fs;
use std::path::{Path, PathBuf};

use uam_preset::{
    from_bytes, from_json_str, to_json_string, AudioSettings, Compatibility, EqBand,
    EqualizerConfig, FilterType, Preset, PresetError, PresetMetadata, CURRENT_SCHEMA_VERSION,
    FORMAT_ID, MAX_PRESET_BYTES,
};

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("database")
        .join("fixtures")
        .join("sample-presets")
}

fn fixture_files() -> Vec<PathBuf> {
    let mut files = fs::read_dir(fixture_dir())
        .expect("fixture directory is readable")
        .map(|entry| entry.expect("fixture entry is readable").path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "json")
        })
        .collect::<Vec<_>>();
    files.sort();
    files
}

fn valid_preset() -> Preset {
    Preset {
        format: FORMAT_ID.to_owned(),
        schema_version: CURRENT_SCHEMA_VERSION,
        metadata: PresetMetadata {
            name: "Test Preset".to_owned(),
            author: Some("Test Author".to_owned()),
            description: Some("Deterministic test fixture.".to_owned()),
            created_at: Some("2026-01-01T00:00:00Z".to_owned()),
            tags: vec!["test".to_owned()],
        },
        compatibility: Compatibility {
            minimum_uam_version: "0.1.0".to_owned(),
            device_independent: true,
            required_capabilities: vec![],
        },
        audio: AudioSettings {
            preamp_db: -2.0,
            equalizer: EqualizerConfig {
                bands: vec![EqBand {
                    filter_type: FilterType::Peaking,
                    frequency_hz: 1_000.0,
                    gain_db: 3.0,
                    q: 1.0,
                }],
            },
        },
    }
}

#[test]
fn all_valid_fixtures_parse_and_roundtrip() {
    let mut count = 0_usize;
    for path in fixture_files() {
        let name = path.file_name().expect("file name").to_string_lossy();
        if name.starts_with("invalid-") {
            continue;
        }
        let bytes = fs::read(&path).expect("fixture is readable");
        let preset = from_bytes(&bytes).unwrap_or_else(|error| {
            panic!("valid fixture {name} was rejected: {error}");
        });
        let exported = to_json_string(&preset).expect("valid preset exports");
        assert!(exported.ends_with('\n'));
        let reparsed = from_json_str(&exported).expect("exported preset re-imports");
        assert_eq!(reparsed, preset, "roundtrip changed {name}");
        count += 1;
    }
    assert!(
        count >= 3,
        "expected at least three valid fixtures, found {count}"
    );
}

#[test]
fn all_invalid_fixtures_are_rejected() {
    let mut count = 0_usize;
    for path in fixture_files() {
        let name = path.file_name().expect("file name").to_string_lossy();
        if !name.starts_with("invalid-") {
            continue;
        }
        let bytes = fs::read(&path).expect("fixture is readable");
        let result = from_bytes(&bytes);
        assert!(result.is_err(), "invalid fixture {name} was accepted");
        count += 1;
    }
    assert!(
        count >= 6,
        "expected at least six invalid fixtures, found {count}"
    );
}

#[test]
fn specific_invalid_fixtures_produce_typed_errors() {
    let cases = [
        ("invalid-format.uam-preset.json", "InvalidFormat"),
        (
            "invalid-schema-version.uam-preset.json",
            "UnsupportedSchemaVersion",
        ),
        ("invalid-gain.uam-preset.json", "InvalidField"),
        (
            "invalid-device-dependent.uam-preset.json",
            "UnsupportedCompatibility",
        ),
        ("invalid-executable-content.uam-preset.json", "InvalidJson"),
        ("invalid-q.uam-preset.json", "InvalidField"),
    ];

    for (name, expected) in cases {
        let bytes = fs::read(fixture_dir().join(name)).expect("fixture is readable");
        let error = from_bytes(&bytes).expect_err("fixture must be rejected");
        let actual = match error {
            PresetError::InvalidFormat { .. } => "InvalidFormat",
            PresetError::UnsupportedSchemaVersion { .. } => "UnsupportedSchemaVersion",
            PresetError::InvalidField { .. } => "InvalidField",
            PresetError::UnsupportedCompatibility(_) => "UnsupportedCompatibility",
            PresetError::InvalidJson(_) => "InvalidJson",
            other => panic!("unexpected error variant for {name}: {other:?}"),
        };
        assert_eq!(actual, expected, "wrong error for {name}");
    }
}

#[test]
fn oversized_input_is_rejected_before_parsing() {
    let oversized = vec![b' '; MAX_PRESET_BYTES + 1];
    assert!(matches!(
        from_bytes(&oversized),
        Err(PresetError::TooLarge { .. })
    ));
}

#[test]
fn invalid_utf8_is_rejected() {
    assert!(matches!(
        from_bytes(&[0xff, 0xfe, 0xfd]),
        Err(PresetError::InvalidJson(_))
    ));
}

#[test]
fn unknown_fields_are_rejected() {
    let json = r#"{
      "format": "uam-preset",
      "schemaVersion": 1,
      "metadata": { "name": "Unknown Field" },
      "compatibility": { "minimumUamVersion": "0.1.0", "deviceIndependent": true },
      "audio": { "preampDb": 0.0, "equalizer": { "bands": [] } },
      "vendorCommand": "unsafe"
    }"#;
    assert!(matches!(
        from_json_str(json),
        Err(PresetError::InvalidJson(_))
    ));
}

#[test]
fn non_finite_values_are_rejected_even_if_constructed_in_memory() {
    let mut preset = valid_preset();
    preset.audio.preamp_db = f64::NAN;
    assert!(matches!(
        preset.validate(),
        Err(PresetError::InvalidField { .. })
    ));

    let mut preset = valid_preset();
    preset.audio.equalizer.bands[0].frequency_hz = f64::INFINITY;
    assert!(matches!(
        preset.validate(),
        Err(PresetError::InvalidField { .. })
    ));
}

#[test]
fn too_many_bands_are_rejected() {
    let mut preset = valid_preset();
    let band = preset.audio.equalizer.bands[0];
    preset.audio.equalizer.bands = vec![band; uam_dsp::MAX_BANDS + 1];
    assert!(matches!(
        preset.validate(),
        Err(PresetError::InvalidField { field, .. }) if field == "audio.equalizer.bands"
    ));
}

#[test]
fn metadata_limits_and_duplicates_are_enforced() {
    let mut preset = valid_preset();
    preset.metadata.name = "  ".to_owned();
    assert!(preset.validate().is_err());

    let mut preset = valid_preset();
    preset.metadata.tags = vec!["duplicate".to_owned(), "duplicate".to_owned()];
    assert!(preset.validate().is_err());

    let mut preset = valid_preset();
    preset.metadata.description = Some("x".repeat(1_001));
    assert!(preset.validate().is_err());
}

#[test]
fn minimum_version_and_capability_identifiers_are_validated() {
    let mut preset = valid_preset();
    preset.compatibility.minimum_uam_version = "1.0".to_owned();
    assert!(preset.validate().is_err());

    let mut preset = valid_preset();
    preset.compatibility.required_capabilities = vec!["Invalid Capability".to_owned()];
    assert!(preset.validate().is_err());

    let mut preset = valid_preset();
    preset.compatibility.device_independent = false;
    assert!(matches!(
        preset.validate(),
        Err(PresetError::UnsupportedCompatibility(_))
    ));
}

#[test]
fn export_rejects_invalid_in_memory_preset() {
    let mut preset = valid_preset();
    preset.audio.preamp_db = 100.0;
    assert!(to_json_string(&preset).is_err());
}
