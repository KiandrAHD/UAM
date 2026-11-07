use core::f64::consts::TAU;

use uam_domain::AudioConfig;
use uam_dsp::{
    BandConfig, DspError, Equalizer, FilterKind, MAX_BANDS, MAX_FREQUENCY_HZ, MAX_GAIN_DB, MAX_Q,
    MIN_FREQUENCY_HZ, MIN_Q,
};

fn stereo_48k() -> AudioConfig {
    AudioConfig::new(48_000, 2).expect("valid test configuration")
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

fn rms(samples: &[f64], channels: u16) -> f64 {
    let channels = usize::from(channels);
    let mut sum = 0.0;
    let mut count = 0_usize;
    for frame in samples.chunks_exact(channels) {
        for sample in frame {
            sum += sample * sample;
            count += 1;
        }
    }
    (sum / count as f64).sqrt()
}

#[test]
fn peaking_band_produces_expected_sine_gain() {
    let config = stereo_48k();
    let band = BandConfig::new(FilterKind::Peaking, 1_000.0, 6.0, 1.0).expect("valid band");
    let mut equalizer = Equalizer::new(config, &[band], 0.0).expect("valid equalizer");

    let frames = 96_000;
    let mut samples = deterministic_sine(1_000.0, 48_000, 2, frames, 0.25);
    let reference = rms(&samples, 2);

    equalizer
        .process_interleaved(&mut samples)
        .expect("processing succeeds");

    // Discard the first second to avoid the filter's startup transient.
    let settled = &samples[48_000 * 2..];
    let processed = rms(settled, 2);
    let measured_gain_db = 20.0 * (processed / reference).log10();

    assert!(
        (measured_gain_db - 6.0).abs() < 0.3,
        "expected approximately +6 dB, measured {measured_gain_db:.3} dB"
    );
}

#[test]
fn preamp_scales_output_by_the_expected_amount() {
    let config = stereo_48k();
    let mut equalizer = Equalizer::new(config, &[], -6.0).expect("valid equalizer");
    let mut samples = deterministic_sine(1_000.0, 48_000, 2, 48_000, 0.5);
    let reference = rms(&samples, 2);
    equalizer
        .process_interleaved(&mut samples)
        .expect("processing succeeds");
    let processed = rms(&samples, 2);
    let measured_gain_db = 20.0 * (processed / reference).log10();
    assert!(
        (measured_gain_db + 6.0).abs() < 0.001,
        "expected approximately -6 dB, measured {measured_gain_db:.6} dB"
    );
}

#[test]
fn impulse_response_is_finite_and_decays() {
    let config = stereo_48k();
    let band = BandConfig::new(FilterKind::Peaking, 2_000.0, 12.0, 2.0).expect("valid band");
    let mut equalizer = Equalizer::new(config, &[band], 0.0).expect("valid equalizer");

    let mut samples = vec![0.0; 48_000 * 2];
    samples[0] = 1.0;
    samples[1] = 1.0;
    equalizer
        .process_interleaved(&mut samples)
        .expect("processing succeeds");

    assert!(samples.iter().all(|sample| sample.is_finite()));
    let tail = &samples[24_000 * 2..];
    let peak = tail
        .iter()
        .fold(0.0_f64, |maximum, sample| maximum.max(sample.abs()));
    assert!(peak < 1.0e-6, "impulse tail did not decay: peak {peak:e}");
}

#[test]
fn non_finite_input_samples_are_contained() {
    let config = stereo_48k();
    let band = BandConfig::new(FilterKind::Peaking, 1_000.0, 6.0, 1.0).expect("valid band");
    let mut equalizer = Equalizer::new(config, &[band], 0.0).expect("valid equalizer");

    let mut samples = deterministic_sine(1_000.0, 48_000, 2, 4_800, 0.25);
    samples[10] = f64::NAN;
    samples[11] = f64::INFINITY;
    samples[12] = f64::NEG_INFINITY;
    equalizer
        .process_interleaved(&mut samples)
        .expect("processing succeeds");
    assert!(samples.iter().all(|sample| sample.is_finite()));
}

#[test]
fn accepts_44100_and_48000_hz() {
    for sample_rate in [44_100, 48_000] {
        let config = AudioConfig::new(sample_rate, 2).expect("valid configuration");
        let band =
            BandConfig::new(FilterKind::HighShelf, 10_000.0, -3.0, 0.707).expect("valid band");
        let mut equalizer = Equalizer::new(config, &[band], -2.0).expect("valid equalizer");
        let mut samples = deterministic_sine(1_000.0, sample_rate, 2, 4_800, 0.1);
        equalizer
            .process_interleaved(&mut samples)
            .expect("processing succeeds");
        assert!(samples.iter().all(|sample| sample.is_finite()));
    }
}

#[test]
fn rejects_non_finite_band_parameters() {
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, f64::NAN, 0.0, 1.0),
        Err(DspError::NonFiniteParameter("frequencyHz"))
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, 1_000.0, f64::INFINITY, 1.0),
        Err(DspError::NonFiniteParameter("gainDb"))
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, 1_000.0, 0.0, f64::NAN),
        Err(DspError::NonFiniteParameter("q"))
    ));
}

#[test]
fn rejects_out_of_range_band_parameters() {
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
        BandConfig::new(FilterKind::Peaking, 1_000.0, 0.0, MIN_Q - 0.01),
        Err(DspError::QOutOfRange { .. })
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, 1_000.0, 0.0, MAX_Q + 0.01),
        Err(DspError::QOutOfRange { .. })
    ));
}

#[test]
fn rejects_band_above_sample_rate_guard_band() {
    let config = AudioConfig::new(8_000, 1).expect("valid configuration");
    let band = BandConfig::new(FilterKind::Peaking, 20_000.0, 0.0, 1.0).expect("valid band");
    assert!(matches!(
        Equalizer::new(config, &[band], 0.0),
        Err(DspError::FrequencyTooHigh { .. })
    ));
}

#[test]
fn rejects_invalid_preamp_and_band_count() {
    let config = stereo_48k();
    assert!(matches!(
        Equalizer::new(config, &[], f64::NAN),
        Err(DspError::NonFiniteParameter("preampDb"))
    ));
    assert!(matches!(
        Equalizer::new(config, &[], 13.0),
        Err(DspError::PreampOutOfRange { .. })
    ));

    let band = BandConfig::new(FilterKind::Peaking, 1_000.0, 0.0, 1.0).expect("valid band");
    let too_many = vec![band; MAX_BANDS + 1];
    assert!(matches!(
        Equalizer::new(config, &too_many, 0.0),
        Err(DspError::TooManyBands { .. })
    ));
}

#[test]
fn combined_frequency_response_includes_preamp_and_bands() {
    let config = stereo_48k();
    let low = BandConfig::new(FilterKind::LowShelf, 200.0, 3.0, 0.707).expect("valid band");
    let high = BandConfig::new(FilterKind::HighShelf, 4_000.0, -3.0, 0.707).expect("valid band");
    let equalizer = Equalizer::new(config, &[low, high], -2.0).expect("valid equalizer");

    let response = equalizer.frequency_response_db(1_000.0);
    assert!(response.is_finite());
    assert!(
        (-3.0..=1.0).contains(&response),
        "unexpected mid-band response: {response} dB"
    );
    assert!((equalizer.latency_samples() as f64) < f64::EPSILON);
    assert_eq!(equalizer.band_count(), 2);
    assert_eq!(equalizer.channels(), 2);
}
