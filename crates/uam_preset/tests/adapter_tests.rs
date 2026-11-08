//! Phase 2.3A — preset-to-DSP adapter tests.
//!
//! These cover filter-type mapping, order preservation, preamp conversion,
//! band-count limits, invalid data, and the sample-rate-dependent frequency
//! rule that only the DSP layer can enforce.

use std::fs;
use std::path::{Path, PathBuf};

use uam_domain::AudioConfig;
use uam_dsp::{
    DspError, FilterKind, MAX_BANDS, MAX_FREQUENCY_HZ, MAX_GAIN_DB, MAX_PREAMP_DB, MIN_Q,
};
use uam_preset::{
    from_json_str, AudioSettings, Compatibility, EqBand, EqualizerConfig, FilterType, Preset,
    PresetConversionError, PresetMetadata, CURRENT_SCHEMA_VERSION, FORMAT_ID,
};

fn stereo_48k() -> AudioConfig {
    AudioConfig::new(48_000, 2).expect("valid configuration")
}

fn mono_8k() -> AudioConfig {
    AudioConfig::new(8_000, 1).expect("valid configuration")
}

fn preset_with(bands: Vec<EqBand>, preamp_db: f64) -> Preset {
    Preset {
        format: FORMAT_ID.to_owned(),
        schema_version: CURRENT_SCHEMA_VERSION,
        metadata: PresetMetadata {
            name: "Adapter Test".to_owned(),
            author: None,
            description: None,
            created_at: None,
            tags: vec![],
        },
        compatibility: Compatibility {
            minimum_uam_version: "0.1.0".to_owned(),
            device_independent: true,
            required_capabilities: vec![],
        },
        audio: AudioSettings {
            preamp_db,
            equalizer: EqualizerConfig { bands },
        },
    }
}

fn band(filter_type: FilterType, frequency_hz: f64, gain_db: f64, q: f64) -> EqBand {
    EqBand {
        filter_type,
        frequency_hz,
        gain_db,
        q,
    }
}

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("database")
        .join("fixtures")
        .join("sample-presets")
}

#[test]
fn every_filter_type_maps_to_the_matching_kind() {
    let cases = [
        (FilterType::Peaking, FilterKind::Peaking),
        (FilterType::LowShelf, FilterKind::LowShelf),
        (FilterType::HighShelf, FilterKind::HighShelf),
    ];
    for (filter_type, expected) in cases {
        let preset = preset_with(vec![band(filter_type, 1_000.0, 3.0, 1.0)], 0.0);
        let config = preset
            .to_dsp_config(stereo_48k())
            .expect("valid conversion");
        assert_eq!(config.bands().len(), 1);
        assert_eq!(
            config.bands()[0].kind,
            expected,
            "wrong kind for {filter_type:?}"
        );
    }
}

#[test]
fn one_band_preset_preserves_parameters() {
    let preset = preset_with(vec![band(FilterType::Peaking, 1_234.0, -7.5, 2.25)], -4.0);
    let config = preset
        .to_dsp_config(stereo_48k())
        .expect("valid conversion");

    assert_eq!(config.band_count(), 1);
    let converted = config.bands()[0];
    assert_eq!(converted.kind, FilterKind::Peaking);
    assert_eq!(converted.frequency_hz, 1_234.0);
    assert_eq!(converted.gain_db, -7.5);
    assert_eq!(converted.q, 2.25);
    assert_eq!(config.preamp_db(), -4.0);
}

#[test]
fn multiple_bands_preserve_order_and_values() {
    let preset = preset_with(
        vec![
            band(FilterType::LowShelf, 90.0, 5.0, 0.7),
            band(FilterType::Peaking, 400.0, -3.0, 1.1),
            band(FilterType::Peaking, 2_000.0, 4.0, 1.4),
            band(FilterType::HighShelf, 8_000.0, -2.5, 0.6),
        ],
        1.5,
    );

    let config = preset
        .to_dsp_config(stereo_48k())
        .expect("valid conversion");

    let frequencies: Vec<f64> = config.bands().iter().map(|b| b.frequency_hz).collect();
    assert_eq!(frequencies, vec![90.0, 400.0, 2_000.0, 8_000.0]);
    let kinds: Vec<FilterKind> = config.bands().iter().map(|b| b.kind).collect();
    assert_eq!(
        kinds,
        vec![
            FilterKind::LowShelf,
            FilterKind::Peaking,
            FilterKind::Peaking,
            FilterKind::HighShelf
        ]
    );
    assert_eq!(config.preamp_db(), 1.5);
}

#[test]
fn preamp_is_converted_verbatim_and_bounds_are_enforced() {
    let at_max = preset_with(vec![], MAX_PREAMP_DB);
    assert_eq!(
        at_max
            .to_dsp_config(stereo_48k())
            .expect("valid")
            .preamp_db(),
        MAX_PREAMP_DB
    );

    let mut out_of_range = preset_with(vec![], 0.0);
    out_of_range.audio.preamp_db = MAX_PREAMP_DB + 1.0;
    assert!(matches!(
        out_of_range.to_dsp_config(stereo_48k()),
        Err(PresetConversionError::InvalidPreset(_))
    ));
}

#[test]
fn empty_band_preset_produces_empty_configuration() {
    let preset = preset_with(vec![], -2.0);
    let config = preset
        .to_dsp_config(stereo_48k())
        .expect("valid conversion");
    assert_eq!(config.band_count(), 0);
    assert_eq!(config.preamp_db(), -2.0);
    assert_eq!(config.audio(), stereo_48k());
    assert!(config.limiter().is_none());
    assert!(!config.bypassed());
}

#[test]
fn maximum_band_count_is_accepted() {
    let band = band(FilterType::Peaking, 1_000.0, 0.0, 1.0);
    let preset = preset_with(vec![band; MAX_BANDS], 0.0);
    let config = preset
        .to_dsp_config(stereo_48k())
        .expect("valid conversion");
    assert_eq!(config.band_count(), MAX_BANDS);
}

#[test]
fn too_many_bands_are_rejected() {
    let band = band(FilterType::Peaking, 1_000.0, 0.0, 1.0);
    let preset = preset_with(vec![band; MAX_BANDS + 1], 0.0);
    assert!(matches!(
        preset.to_dsp_config(stereo_48k()),
        Err(PresetConversionError::InvalidPreset(_))
    ));
}

#[test]
fn invalid_frequency_is_rejected() {
    let preset = preset_with(vec![band(FilterType::Peaking, 5.0, 0.0, 1.0)], 0.0);
    assert!(matches!(
        preset.to_dsp_config(stereo_48k()),
        Err(PresetConversionError::InvalidPreset(_))
    ));
}

#[test]
fn invalid_gain_is_rejected() {
    let preset = preset_with(
        vec![band(FilterType::Peaking, 1_000.0, MAX_GAIN_DB + 1.0, 1.0)],
        0.0,
    );
    assert!(matches!(
        preset.to_dsp_config(stereo_48k()),
        Err(PresetConversionError::InvalidPreset(_))
    ));
}

#[test]
fn invalid_q_is_rejected() {
    let preset = preset_with(
        vec![band(FilterType::Peaking, 1_000.0, 0.0, MIN_Q - 0.01)],
        0.0,
    );
    assert!(matches!(
        preset.to_dsp_config(stereo_48k()),
        Err(PresetConversionError::InvalidPreset(_))
    ));
}

#[test]
fn sample_rate_dependent_frequency_validation_uses_the_dsp_layer() {
    // 20 kHz is inside the portable maximum (MAX_FREQUENCY_HZ) so it passes
    // preset validation, but it is far above the usable maximum for an 8 kHz
    // stream, so the DSP layer must reject it.
    let preset = preset_with(
        vec![band(FilterType::Peaking, MAX_FREQUENCY_HZ, 0.0, 1.0)],
        0.0,
    );

    // The preset itself is portable-valid.
    assert!(preset.validate().is_ok());

    // The same preset is valid at 48 kHz...
    assert!(preset.to_dsp_config(stereo_48k()).is_ok());

    // ...but the DSP layer rejects it for an 8 kHz stream.
    assert!(matches!(
        preset.to_dsp_config(mono_8k()),
        Err(PresetConversionError::Dsp(
            DspError::FrequencyTooHigh { .. }
        ))
    ));
}

#[test]
fn invalid_preset_data_is_rejected_before_conversion() {
    let mut wrong_format = preset_with(vec![], 0.0);
    wrong_format.format = "not-a-uam-preset".to_owned();
    assert!(matches!(
        wrong_format.to_dsp_config(stereo_48k()),
        Err(PresetConversionError::InvalidPreset(_))
    ));

    let mut non_finite = preset_with(vec![], 0.0);
    non_finite.audio.preamp_db = f64::NAN;
    assert!(matches!(
        non_finite.to_dsp_config(stereo_48k()),
        Err(PresetConversionError::InvalidPreset(_))
    ));
}

#[test]
fn all_valid_fixtures_convert_to_dsp_configurations() {
    let mut converted = 0_usize;
    for entry in fs::read_dir(fixture_dir()).expect("fixture directory readable") {
        let path = entry.expect("fixture entry").path();
        if path.extension().is_none_or(|extension| extension != "json") {
            continue;
        }
        let name = path.file_name().expect("file name").to_string_lossy();
        if name.starts_with("invalid-") {
            continue;
        }
        let text = fs::read_to_string(&path).expect("fixture readable");
        let preset = from_json_str(&text).unwrap_or_else(|error| {
            panic!("valid fixture {name} did not parse: {error}");
        });
        let config = preset
            .to_dsp_config(stereo_48k())
            .unwrap_or_else(|error| panic!("valid fixture {name} did not convert: {error}"));
        assert_eq!(config.band_count(), preset.audio.equalizer.bands.len());
        assert_eq!(config.preamp_db(), preset.audio.preamp_db);
        assert!(config.validate().is_ok());
        converted += 1;
    }
    assert!(
        converted >= 3,
        "expected at least 3 valid fixtures, found {converted}"
    );
}
