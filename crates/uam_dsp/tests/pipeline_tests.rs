//! Phase 2.3C — composed processing-pipeline tests.

use uam_domain::AudioConfig;
use uam_dsp::{BandConfig, DspConfig, DspPipeline, FilterKind, LimiterConfig};

fn stereo_48k() -> AudioConfig {
    AudioConfig::new(48_000, 2).expect("valid config")
}

#[test]
fn pipeline_reports_input_pre_limiter_and_output_peaks() {
    let config = DspConfig::new(stereo_48k(), 6.0, vec![])
        .expect("valid config")
        .with_limiter(LimiterConfig::new(true, -3.0, 100.0).expect("valid limiter"));
    let mut pipeline = DspPipeline::from_config(&config).expect("valid pipeline");
    let mut samples = [0.5, -0.5, 0.25, -0.25];

    let report = pipeline
        .process_interleaved(&mut samples)
        .expect("valid process");

    assert!((report.input().overall_peak() - 0.5).abs() < 1e-12);
    // +6dB turns 0.5 into approximately 0.9976, over -3dBFS ceiling.
    assert!(report.pre_limiter().overall_peak() > 0.9);
    assert!(!report.pre_limiter().clipping_detected());
    assert!(report.output().overall_peak() <= 10.0_f64.powf(-3.0 / 20.0) + 1e-12);
    assert!(report.gain_reduction_db() > 0.0);
    assert!(report.limiter_active());
}

#[test]
fn disabled_limiter_pipeline_matches_equalizer_output() {
    let band = BandConfig::new(FilterKind::Peaking, 1_000.0, 6.0, 1.0).expect("band");
    let config = DspConfig::new(stereo_48k(), -3.0, vec![band])
        .expect("config")
        .with_limiter(LimiterConfig::new(false, -0.3, 100.0).expect("limiter"));
    let mut pipeline = DspPipeline::from_config(&config).expect("pipeline");
    let mut direct = pipeline.equalizer().clone();
    let mut via_pipeline = [0.1, -0.2, 0.3, -0.4];
    let mut via_eq = via_pipeline;

    let report = pipeline
        .process_interleaved(&mut via_pipeline)
        .expect("process pipeline");
    direct.process_interleaved(&mut via_eq).expect("process eq");

    assert_eq!(via_pipeline, via_eq);
    assert!(!report.limiter_active());
    assert_eq!(report.gain_reduction_db(), 0.0);
}

#[test]
fn pre_limiter_meter_reports_clipping_when_limiter_is_disabled() {
    let config = DspConfig::new(stereo_48k(), 12.0, vec![]).expect("config");
    let mut pipeline = DspPipeline::from_config(&config).expect("pipeline");
    let mut samples = [0.5, -0.5];
    let report = pipeline.process_interleaved(&mut samples).expect("process");

    assert!(report.pre_limiter().clipping_detected());
    assert!(report.output().clipping_detected());
    assert!(!report.limiter_active());
}

#[test]
fn reset_resets_components_and_meters() {
    let config = DspConfig::new(stereo_48k(), 6.0, vec![])
        .expect("config")
        .with_limiter(LimiterConfig::new(true, -3.0, 100.0).expect("limiter"));
    let mut pipeline = DspPipeline::from_config(&config).expect("pipeline");
    let mut samples = [0.8, -0.8];
    pipeline.process_interleaved(&mut samples).expect("process");
    assert!(pipeline.output_meter().processed_frames() > 0);
    assert!(pipeline.limiter().gain() < 1.0);

    pipeline.reset();
    assert_eq!(pipeline.output_meter().processed_frames(), 0);
    assert_eq!(pipeline.output_meter().running_overall_peak(), 0.0);
    assert!((pipeline.limiter().gain() - 1.0).abs() < f64::EPSILON);
}

#[test]
fn pipeline_rejects_incomplete_frame_without_modification() {
    let config = DspConfig::new(stereo_48k(), 0.0, vec![]).expect("config");
    let mut pipeline = DspPipeline::from_config(&config).expect("pipeline");
    let mut samples = [0.1, 0.2, 0.3];
    let original = samples;
    assert!(pipeline.process_interleaved(&mut samples).is_err());
    assert_eq!(samples, original);
}
