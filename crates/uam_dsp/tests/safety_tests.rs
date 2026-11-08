//! Phase 2.3D — numerical safety, denormal, and long-run stability tests.

use core::f64::consts::TAU;

use uam_domain::AudioConfig;
use uam_dsp::{
    linear_to_dbfs, BandConfig, DspConfig, DspError, DspPipeline, Equalizer, FilterKind, Limiter,
    LimiterConfig, PeakMeter,
};

fn stereo_48k() -> AudioConfig {
    AudioConfig::new(48_000, 2).expect("valid config")
}

fn band(kind: FilterKind, frequency_hz: f64, gain_db: f64, q: f64) -> BandConfig {
    BandConfig::new(kind, frequency_hz, gain_db, q).expect("valid band")
}

fn configured_pipeline() -> DspPipeline {
    let config = DspConfig::new(
        stereo_48k(),
        3.0,
        vec![
            band(FilterKind::LowShelf, 120.0, 4.0, 0.7),
            band(FilterKind::Peaking, 1_000.0, 6.0, 1.0),
        ],
    )
    .expect("config")
    .with_limiter(LimiterConfig::new(true, -3.0, 100.0).expect("limiter"));
    DspPipeline::from_config(&config).expect("pipeline")
}

#[test]
fn equalizer_contains_nan_and_infinity() {
    let mut equalizer = Equalizer::new(
        stereo_48k(),
        &[band(FilterKind::Peaking, 1_000.0, 6.0, 1.0)],
        0.0,
    )
    .expect("equalizer");
    let mut samples = vec![0.2; 512];
    samples[0] = f64::NAN;
    samples[1] = f64::INFINITY;
    samples[2] = f64::NEG_INFINITY;
    equalizer
        .process_interleaved(&mut samples)
        .expect("process");
    assert!(samples.iter().all(|sample| sample.is_finite()));
}

#[test]
fn limiter_contains_non_finite_input() {
    let mut limiter = Limiter::new(
        &LimiterConfig::new(true, -3.0, 100.0).expect("limiter"),
        stereo_48k(),
    )
    .expect("limiter");
    let mut samples = [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, 0.5];
    limiter.process_interleaved(&mut samples).expect("process");
    assert!(samples.iter().all(|sample| sample.is_finite()));
    assert!(limiter.gain().is_finite());
}

#[test]
fn pipeline_contains_non_finite_input() {
    let mut pipeline = configured_pipeline();
    let mut samples = vec![0.3; 512];
    samples[4] = f64::NAN;
    samples[5] = f64::INFINITY;
    samples[6] = f64::NEG_INFINITY;
    let report = pipeline.process_interleaved(&mut samples).expect("process");
    assert!(samples.iter().all(|sample| sample.is_finite()));
    assert!(report.output().overall_peak().is_finite());
    assert!(report.output().overall_peak_dbfs().is_finite());
}

#[test]
fn subnormal_input_is_processed_without_corruption() {
    // f64::MIN_POSITIVE is the smallest *normal* number; half of it and the
    // smallest positive subnormal are strictly subnormal.
    let smallest_subnormal = f64::from_bits(1);
    let inputs = [
        f64::MIN_POSITIVE,
        f64::MIN_POSITIVE / 4.0,
        smallest_subnormal,
        -smallest_subnormal,
    ];

    let mut equalizer = Equalizer::new(
        stereo_48k(),
        &[band(FilterKind::Peaking, 1_000.0, 6.0, 1.0)],
        0.0,
    )
    .expect("equalizer");
    for value in inputs {
        let mut samples = [value, -value];
        equalizer
            .process_interleaved(&mut samples)
            .expect("process");
        assert!(samples.iter().all(|sample| sample.is_finite()));
    }

    // The limiter does not flush subnormals to zero when they are below the
    // ceiling: no flush-to-zero policy is applied anywhere in the kernel.
    let mut limiter = Limiter::new(
        &LimiterConfig::new(true, 0.0, 100.0).expect("limiter"),
        stereo_48k(),
    )
    .expect("limiter");
    let mut samples = [smallest_subnormal, -smallest_subnormal];
    limiter.process_interleaved(&mut samples).expect("process");
    assert_eq!(samples, [smallest_subnormal, -smallest_subnormal]);

    // The meter reports a finite (floored) level for subnormal peaks.
    let mut meter = PeakMeter::new(2).expect("meter");
    let block = meter
        .process_interleaved(&[smallest_subnormal, 0.0])
        .expect("process");
    assert!(block.overall_peak().is_finite());
    assert!(block.overall_peak_dbfs().is_finite());
    assert_eq!(linear_to_dbfs(smallest_subnormal), linear_to_dbfs(0.0));
}

#[test]
fn very_small_and_max_finite_amplitudes_stay_bounded() {
    let mut limiter = Limiter::new(
        &LimiterConfig::new(true, 0.0, 50.0).expect("limiter"),
        stereo_48k(),
    )
    .expect("limiter");

    // Very small amplitude: passes through untouched.
    let mut tiny = [1.0e-30_f64, -1.0e-30];
    limiter.process_interleaved(&mut tiny).expect("process");
    assert!(tiny.iter().all(|sample| sample.is_finite()));

    // The largest finite magnitude: bounded to the ceiling, never infinite.
    let mut huge = [f64::MAX, f64::MIN];
    limiter.process_interleaved(&mut huge).expect("process");
    assert!(huge.iter().all(|sample| sample.is_finite()));
    assert!(huge[0].abs() <= 1.0 + 1.0e-12);
    assert!(huge[1].abs() <= 1.0 + 1.0e-12);
}

#[test]
fn invalid_parameters_are_rejected() {
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, f64::NAN, 0.0, 1.0),
        Err(DspError::NonFiniteParameter("frequencyHz"))
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, 1_000.0, 0.0, -1.0),
        Err(DspError::QOutOfRange { .. })
    ));
    assert!(matches!(
        BandConfig::new(FilterKind::Peaking, 1_000.0, f64::INFINITY, 1.0),
        Err(DspError::NonFiniteParameter("gainDb"))
    ));
    assert!(matches!(
        LimiterConfig::new(true, f64::NAN, 100.0),
        Err(DspError::NonFiniteParameter(_))
    ));
    assert!(matches!(
        LimiterConfig::new(true, -0.3, -5.0),
        Err(DspError::LimiterReleaseOutOfRange { .. })
    ));
}

#[test]
fn invalid_block_lengths_are_rejected_everywhere() {
    let mut equalizer = Equalizer::new(stereo_48k(), &[], 0.0).expect("equalizer");
    let mut limiter = Limiter::new(
        &LimiterConfig::new(true, -3.0, 100.0).expect("limiter"),
        stereo_48k(),
    )
    .expect("limiter");
    let mut meter = PeakMeter::new(2).expect("meter");
    let mut pipeline = configured_pipeline();

    let mut odd = [0.1, 0.2, 0.3];
    assert!(matches!(
        equalizer.process_interleaved(&mut odd),
        Err(DspError::InvalidBlockLength { .. })
    ));
    assert!(matches!(
        limiter.process_interleaved(&mut odd),
        Err(DspError::InvalidBlockLength { .. })
    ));
    assert!(meter.process_interleaved(&odd).is_err());
    assert!(matches!(
        pipeline.process_interleaved(&mut odd),
        Err(DspError::InvalidBlockLength { .. })
    ));
}

#[test]
fn long_run_equalizer_output_stays_finite_and_bounded() {
    let mut equalizer = Equalizer::new(
        stereo_48k(),
        &[band(FilterKind::Peaking, 1_000.0, 12.0, 5.0)],
        0.0,
    )
    .expect("equalizer");
    let mut block = vec![0.0_f64; 512 * 2];
    for step in 0..20_000_u64 {
        for (index, sample) in block.iter_mut().enumerate() {
            let phase = TAU * 1_000.0 * ((step * 256 + index as u64) as f64) / 48_000.0;
            *sample = 0.5 * phase.sin();
        }
        equalizer.process_interleaved(&mut block).expect("process");
        assert!(
            block.iter().all(|sample| sample.is_finite()),
            "non-finite output at step {step}"
        );
        assert!(
            block.iter().all(|sample| sample.abs() < 10.0),
            "state explosion at step {step}"
        );
    }
}

#[test]
fn long_run_pipeline_is_stable_and_deterministic_on_reset() {
    let mut pipeline = configured_pipeline();
    let mut block = vec![0.0_f64; 256 * 2];
    for step in 0..20_000_u64 {
        for (index, sample) in block.iter_mut().enumerate() {
            let phase = TAU * 440.0 * ((step * 128 + index as u64) as f64) / 48_000.0;
            *sample = 0.8 * phase.sin();
        }
        pipeline.process_interleaved(&mut block).expect("process");
        assert!(block.iter().all(|sample| sample.is_finite()));
        assert!(block.iter().all(|sample| sample.abs() <= 1.0 + 1.0e-9));
    }

    // Deterministic reset: identical input after reset yields identical output.
    pipeline.reset();
    let mut first = vec![0.0_f64; 512];
    for (index, sample) in first.iter_mut().enumerate() {
        *sample = (index as f64 * 0.05).sin() * 0.4;
    }
    let mut a = first.clone();
    let mut b = first.clone();
    pipeline.process_interleaved(&mut a).expect("process");
    pipeline.reset();
    pipeline.process_interleaved(&mut b).expect("process");
    assert_eq!(a, b);
}
