//! Phase 2.1–2.2 configuration model and control-thread update tests.
//!
//! These tests exercise the audio format model in `uam_domain` and the
//! validated `DspConfig` / `LimiterConfig` DTO plus `Equalizer::apply_config`
//! in `uam_dsp`. They complement, and do not replace, the Phase 0 processing
//! regression tests in `dsp_tests.rs`.

use core::f64::consts::TAU;

use uam_domain::{AudioConfig, AudioConfigError, SampleFormat, INTERNAL_PROCESSING_FORMAT};
use uam_dsp::{
    BandConfig, DspConfig, DspError, Equalizer, FilterKind, LimiterConfig, MAX_BANDS,
    MAX_FREQUENCY_HZ, MAX_GAIN_DB, MAX_LIMITER_CEILING_DB, MAX_LIMITER_RELEASE_MS, MAX_PREAMP_DB,
    MAX_Q, MIN_FREQUENCY_HZ, MIN_GAIN_DB, MIN_LIMITER_CEILING_DB, MIN_LIMITER_RELEASE_MS,
    MIN_PREAMP_DB, MIN_Q,
};

fn stereo_48k() -> AudioConfig {
    AudioConfig::new(48_000, 2).expect("valid test configuration")
}

fn mono_48k() -> AudioConfig {
    AudioConfig::new(48_000, 1).expect("valid test configuration")
}

fn band(kind: FilterKind, frequency_hz: f64, gain_db: f64, q: f64) -> BandConfig {
    BandConfig::new(kind, frequency_hz, gain_db, q).expect("valid test band")
}

fn deterministic_sine(
    frequency_hz: f64,
    sample_rate_hz: u32,
    channels: u16,
    frames: usize,
    amplitude: f64,
) -> Vec<f64> {
    let mut samples = Vec::with_capacity(frames * usize::from(channels));
    for frame in 0..frames {
        let phase = TAU * frequency_hz * frame as f64 / f64::from(sample_rate_hz);
        let value = amplitude * phase.sin();
        for _ in 0..channels {
            samples.push(value);
        }
    }
    samples
}

fn rms(samples: &[f64]) -> f64 {
    let mut sum = 0.0;
    for sample in samples {
        sum += sample * sample;
    }
    (sum / samples.len() as f64).sqrt()
}

// ---------------------------------------------------------------------------
// Audio format model (Phase 2.1)
// ---------------------------------------------------------------------------

#[test]
fn accepts_valid_audio_configurations() {
    for sample_rate in [8_000, 44_100, 48_000, 96_000, 192_000, 384_000] {
        for channels in [1_u16, 2] {
            for format in [SampleFormat::F32, SampleFormat::F64] {
                let audio = AudioConfig::with_format(sample_rate, channels, format)
                    .expect("valid audio configuration");
                assert_eq!(audio.sample_rate_hz(), sample_rate);
                assert_eq!(audio.channels(), channels);
                assert_eq!(audio.boundary_format(), format);
                assert!(audio.nyquist_hz() > 0.0);
                assert!(audio.max_usable_frequency_hz() < audio.nyquist_hz());
            }
        }
    }
}

#[test]
fn rejects_invalid_sample_rates() {
    assert_eq!(
        AudioConfig::new(0, 2),
        Err(AudioConfigError::UnsupportedSampleRate(0))
    );
    assert_eq!(
        AudioConfig::new(7_999, 2),
        Err(AudioConfigError::UnsupportedSampleRate(7_999))
    );
    assert_eq!(
        AudioConfig::with_format(384_001, 2, SampleFormat::F32),
        Err(AudioConfigError::UnsupportedSampleRate(384_001))
    );
}

#[test]
fn rejects_invalid_channel_counts() {
    assert_eq!(
        AudioConfig::new(48_000, 0),
        Err(AudioConfigError::UnsupportedChannelCount(0))
    );
    assert_eq!(
        AudioConfig::new(48_000, 3),
        Err(AudioConfigError::UnsupportedChannelCount(3))
    );
    assert_eq!(
        AudioConfig::with_format(48_000, 6, SampleFormat::F32),
        Err(AudioConfigError::UnsupportedChannelCount(6))
    );
}

#[test]
fn sample_format_compatibility_at_the_boundary() {
    // An f32 boundary format is accepted and recorded, but processing stays f64.
    let audio =
        AudioConfig::with_format(48_000, 2, SampleFormat::F32).expect("valid configuration");
    assert_eq!(audio.boundary_format(), SampleFormat::F32);
    assert_eq!(audio.internal_processing_format(), SampleFormat::F64);
    assert_eq!(INTERNAL_PROCESSING_FORMAT, SampleFormat::F64);
    assert!(!audio.boundary_format().is_internal_processing_format());

    let config = DspConfig::new(
        audio,
        0.0,
        vec![band(FilterKind::Peaking, 1_000.0, 3.0, 1.0)],
    )
    .expect("valid configuration");
    let mut equalizer = Equalizer::from_config(&config).expect("valid equalizer");
    let mut samples = deterministic_sine(1_000.0, 48_000, 2, 4_800, 0.1);
    equalizer
        .process_interleaved(&mut samples)
        .expect("processing succeeds");
    assert!(samples.iter().all(|sample| sample.is_finite()));
}

// ---------------------------------------------------------------------------
// DSP configuration DTO (Phase 2.2)
// ---------------------------------------------------------------------------

#[test]
fn dsp_config_round_trips_its_fields() {
    let limiter = LimiterConfig::new(true, -1.0, 200.0).expect("valid limiter");
    let config = DspConfig::new(
        stereo_48k(),
        -3.0,
        vec![band(FilterKind::LowShelf, 120.0, 4.0, 0.7)],
    )
    .expect("valid configuration")
    .with_bypassed(true)
    .with_limiter(limiter);

    assert_eq!(config.audio(), stereo_48k());
    assert_eq!(config.preamp_db(), -3.0);
    assert_eq!(config.band_count(), 1);
    assert_eq!(config.bands()[0].frequency_hz, 120.0);
    assert!(config.bypassed());
    assert_eq!(config.limiter(), Some(limiter));
    assert!(config.validate().is_ok());
}

#[test]
fn rejects_invalid_preamp() {
    assert!(matches!(
        DspConfig::new(stereo_48k(), f64::NAN, vec![]),
        Err(DspError::NonFiniteParameter("preampDb"))
    ));
    assert!(matches!(
        DspConfig::new(stereo_48k(), MAX_PREAMP_DB + 0.5, vec![]),
        Err(DspError::PreampOutOfRange { .. })
    ));
    assert!(matches!(
        DspConfig::new(stereo_48k(), MIN_PREAMP_DB - 0.5, vec![]),
        Err(DspError::PreampOutOfRange { .. })
    ));
    // The documented bounds themselves are accepted.
    assert!(DspConfig::new(stereo_48k(), MIN_PREAMP_DB, vec![]).is_ok());
    assert!(DspConfig::new(stereo_48k(), MAX_PREAMP_DB, vec![]).is_ok());
}

#[test]
fn rejects_invalid_eq_band_configuration() {
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, f64::NAN, 0.0, 1.0),
        Err(DspError::NonFiniteParameter("frequencyHz"))
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, MIN_FREQUENCY_HZ - 1.0, 0.0, 1.0),
        Err(DspError::FrequencyTooLow { .. })
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, MAX_FREQUENCY_HZ + 1.0, 0.0, 1.0),
        Err(DspError::FrequencyTooHigh { .. })
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, 1_000.0, MAX_GAIN_DB + 1.0, 1.0),
        Err(DspError::GainOutOfRange { .. })
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, 1_000.0, MIN_GAIN_DB - 1.0, 1.0),
        Err(DspError::GainOutOfRange { .. })
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, 1_000.0, 0.0, MIN_Q - 0.01),
        Err(DspError::QOutOfRange { .. })
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, 1_000.0, 0.0, MAX_Q + 0.01),
        Err(DspError::QOutOfRange { .. })
    ));

    // Documented boundary values are accepted.
    assert!(BandConfig::new(FilterKind::Peaking, MIN_FREQUENCY_HZ, MIN_GAIN_DB, MIN_Q).is_ok());
    assert!(BandConfig::new(FilterKind::Peaking, MAX_FREQUENCY_HZ, MAX_GAIN_DB, MAX_Q).is_ok());
}

#[test]
fn band_frequency_boundary_matches_usable_maximum() {
    // At 8 kHz the usable maximum (0.95 x 4 kHz = 3.8 kHz) is below the general
    // 20 kHz cap, so the sample-rate guard is the binding constraint.
    let audio = AudioConfig::new(8_000, 1).expect("valid configuration");
    let usable = audio.max_usable_frequency_hz();
    assert!((usable - 3_800.0).abs() < f64::EPSILON);

    let at_limit = band(FilterKind::Peaking, usable, 0.0, 1.0);
    assert!(DspConfig::new(audio, 0.0, vec![at_limit]).is_ok());

    let above_limit = band(FilterKind::HighShelf, usable + 1.0, 0.0, 1.0);
    assert!(matches!(
        DspConfig::new(audio, 0.0, vec![above_limit]),
        Err(DspError::FrequencyTooHigh { .. })
    ));
}

#[test]
fn enforces_maximum_band_count() {
    let one = band(FilterKind::Peaking, 1_000.0, 0.0, 1.0);
    let at_limit = vec![one; MAX_BANDS];
    assert!(DspConfig::new(stereo_48k(), 0.0, at_limit).is_ok());

    let over_limit = vec![one; MAX_BANDS + 1];
    assert!(matches!(
        DspConfig::new(stereo_48k(), 0.0, over_limit),
        Err(DspError::TooManyBands {
            maximum: MAX_BANDS,
            ..
        })
    ));
}

#[test]
fn band_validation_is_sample_rate_aware() {
    let audio = AudioConfig::new(8_000, 1).expect("valid configuration");
    // 20 kHz is inside the general band range but far above the usable maximum
    // (0.95 x 4 kHz Nyquist = 3.8 kHz) for an 8 kHz stream.
    let high = band(FilterKind::Peaking, 20_000.0, 0.0, 1.0);
    assert!(matches!(
        DspConfig::new(audio, 0.0, vec![high]),
        Err(DspError::FrequencyTooHigh { .. })
    ));

    // The same band is fine at 48 kHz.
    assert!(DspConfig::new(stereo_48k(), 0.0, vec![high]).is_ok());
}

#[test]
fn validates_limiter_parameters() {
    assert!(LimiterConfig::new(false, -0.3, 100.0).is_ok());
    assert!(LimiterConfig::new(true, MIN_LIMITER_CEILING_DB, MIN_LIMITER_RELEASE_MS).is_ok());
    assert!(LimiterConfig::new(true, MAX_LIMITER_CEILING_DB, MAX_LIMITER_RELEASE_MS).is_ok());

    assert!(matches!(
        LimiterConfig::new(true, f64::NAN, 100.0),
        Err(DspError::NonFiniteParameter("limiterCeilingDb"))
    ));
    assert!(matches!(
        LimiterConfig::new(true, -0.3, f64::INFINITY),
        Err(DspError::NonFiniteParameter("limiterReleaseMs"))
    ));
    assert!(matches!(
        LimiterConfig::new(true, MIN_LIMITER_CEILING_DB - 0.1, 100.0),
        Err(DspError::LimiterCeilingOutOfRange { .. })
    ));
    assert!(matches!(
        LimiterConfig::new(true, MAX_LIMITER_CEILING_DB + 0.1, 100.0),
        Err(DspError::LimiterCeilingOutOfRange { .. })
    ));
    assert!(matches!(
        LimiterConfig::new(true, -0.3, MIN_LIMITER_RELEASE_MS - 0.1),
        Err(DspError::LimiterReleaseOutOfRange { .. })
    ));
    assert!(matches!(
        LimiterConfig::new(true, -0.3, MAX_LIMITER_RELEASE_MS + 0.1),
        Err(DspError::LimiterReleaseOutOfRange { .. })
    ));
}

#[test]
fn limiter_metadata_does_not_change_processing() {
    let bands = vec![band(FilterKind::Peaking, 1_000.0, 6.0, 1.0)];
    let without = DspConfig::new(stereo_48k(), -2.0, bands.clone()).expect("valid configuration");
    let with = DspConfig::new(stereo_48k(), -2.0, bands)
        .expect("valid configuration")
        .with_limiter(LimiterConfig::new(true, 0.0, 50.0).expect("valid limiter"));

    let signal = deterministic_sine(1_000.0, 48_000, 2, 4_800, 0.5);
    let mut a = signal.clone();
    Equalizer::from_config(&without)
        .expect("valid equalizer")
        .process_interleaved(&mut a)
        .expect("processing succeeds");
    let mut b = signal.clone();
    Equalizer::from_config(&with)
        .expect("valid equalizer")
        .process_interleaved(&mut b)
        .expect("processing succeeds");

    // No limiter processor exists yet, so enabling the metadata is a no-op.
    assert_eq!(a, b);
}

// ---------------------------------------------------------------------------
// Equalizer control-thread configuration (Phase 2.2)
// ---------------------------------------------------------------------------

#[test]
fn from_config_matches_new() {
    let bands = vec![
        band(FilterKind::LowShelf, 120.0, 3.0, 0.7),
        band(FilterKind::Peaking, 1_000.0, -4.0, 1.2),
    ];
    let config = DspConfig::new(stereo_48k(), -2.0, bands.clone()).expect("valid configuration");

    let from_config = Equalizer::from_config(&config).expect("valid equalizer");
    let from_new = Equalizer::new(stereo_48k(), &bands, -2.0).expect("valid equalizer");

    assert_eq!(from_config.band_count(), from_new.band_count());
    assert_eq!(from_config.preamp_db(), from_new.preamp_db());
    assert_eq!(
        from_config.frequency_response_db(1_000.0),
        from_new.frequency_response_db(1_000.0)
    );
}

#[test]
fn apply_config_replaces_the_chain() {
    let mut equalizer = Equalizer::new(stereo_48k(), &[], 0.0).expect("valid equalizer");
    assert_eq!(equalizer.band_count(), 0);
    assert_eq!(equalizer.preamp_db(), 0.0);

    let replacement = DspConfig::new(
        stereo_48k(),
        -6.0,
        vec![
            band(FilterKind::LowShelf, 150.0, 5.0, 0.7),
            band(FilterKind::HighShelf, 6_000.0, -4.0, 0.7),
        ],
    )
    .expect("valid configuration")
    .with_bypassed(false);

    equalizer
        .apply_config(&replacement)
        .expect("valid replacement");

    assert_eq!(equalizer.band_count(), 2);
    assert_eq!(equalizer.preamp_db(), -6.0);
    assert_eq!(equalizer.channels(), 2);
    assert!(!equalizer.is_bypassed());

    let mut samples = deterministic_sine(150.0, 48_000, 2, 48_000, 0.1);
    equalizer
        .process_interleaved(&mut samples)
        .expect("processing succeeds");
    assert!(samples.iter().all(|sample| sample.is_finite()));
    assert!(rms(&samples) > 0.0);
}

#[test]
fn failed_replacement_preserves_previous_chain() {
    let mut equalizer = Equalizer::new(
        stereo_48k(),
        &[band(FilterKind::Peaking, 2_000.0, 6.0, 1.0)],
        -3.0,
    )
    .expect("valid equalizer");

    let before_response = equalizer.frequency_response_db(2_000.0);
    let before_preamp = equalizer.preamp_db();

    // A DTO can only be built if it is valid, so the reachable failure modes at
    // `apply_config` are a sample-rate change and a channel-count change. Both
    // must be rejected and must leave the active chain untouched.
    let rate_mismatch = DspConfig::new(
        AudioConfig::new(44_100, 2).expect("valid configuration"),
        -6.0,
        vec![],
    )
    .expect("valid configuration");
    assert!(matches!(
        equalizer.apply_config(&rate_mismatch),
        Err(DspError::ReconfigurationRequired {
            active_sample_rate_hz: 48_000,
            active_channels: 2,
            target_sample_rate_hz: 44_100,
            target_channels: 2,
        })
    ));

    let channel_mismatch = DspConfig::new(mono_48k(), -6.0, vec![]).expect("valid configuration");
    assert!(matches!(
        equalizer.apply_config(&channel_mismatch),
        Err(DspError::ReconfigurationRequired {
            active_channels: 2,
            target_channels: 1,
            ..
        })
    ));

    // The two rejected attempts left the chain byte-for-byte intact.
    assert_eq!(equalizer.band_count(), 1);
    assert_eq!(equalizer.preamp_db(), before_preamp);
    assert_eq!(equalizer.frequency_response_db(2_000.0), before_response);
    assert_eq!(equalizer.channels(), 2);
    assert_eq!(equalizer.sample_rate_hz(), 48_000);
}

#[test]
fn invalid_dto_is_rejected_before_reaching_the_engine() {
    // A DTO that fails validation cannot be constructed, so it can never be
    // applied. Confirm the constructor rejects the value and the engine state
    // is unchanged.
    let engine = AudioConfig::new(8_000, 1).expect("valid configuration");
    let equalizer = Equalizer::new(engine, &[], 0.0).expect("valid equalizer");
    let invalid = DspConfig::new(
        engine,
        0.0,
        vec![band(FilterKind::Peaking, 20_000.0, 0.0, 1.0)],
    );
    assert!(matches!(invalid, Err(DspError::FrequencyTooHigh { .. })));
    assert_eq!(equalizer.band_count(), 0);
    assert_eq!(equalizer.preamp_db(), 0.0);
}

#[test]
fn mono_and_stereo_processing_both_work() {
    for (audio, channels) in [(mono_48k(), 1_u16), (stereo_48k(), 2)] {
        let config = DspConfig::new(
            audio,
            0.0,
            vec![band(FilterKind::Peaking, 1_000.0, 6.0, 1.0)],
        )
        .expect("valid configuration");
        let mut equalizer = Equalizer::from_config(&config).expect("valid equalizer");
        assert_eq!(equalizer.channels(), channels);

        let frames = 48_000;
        let mut samples = deterministic_sine(1_000.0, 48_000, channels, frames, 0.25);
        let original = rms(&samples);
        equalizer
            .process_interleaved(&mut samples)
            .expect("processing succeeds");

        let settled = &samples[24_000 * usize::from(channels)..];
        let processed = rms(settled);
        let measured_gain_db = 20.0 * (processed / original).log10();
        assert!(
            (measured_gain_db - 6.0).abs() < 0.4,
            "{channels}-channel expected ~+6 dB, measured {measured_gain_db:.3} dB"
        );
    }
}

#[test]
fn bypass_from_config_is_bit_exact() {
    let config = DspConfig::new(
        stereo_48k(),
        3.0,
        vec![band(FilterKind::Peaking, 1_000.0, 6.0, 1.0)],
    )
    .expect("valid configuration")
    .with_bypassed(true);
    let mut equalizer = Equalizer::from_config(&config).expect("valid equalizer");
    assert!(equalizer.is_bypassed());

    let mut samples = [0.1, -0.2, 0.3, -0.4];
    let original = samples;
    equalizer
        .process_interleaved(&mut samples)
        .expect("valid buffer");
    assert_eq!(samples, original);
}
