//! Phase 2.3B — sample-peak meter and clipping-detection tests.

use uam_dsp::{linear_to_dbfs, MeterError, PeakMeter, CLIP_THRESHOLD_LINEAR, DBFS_FLOOR};

fn meter(channels: u16) -> PeakMeter {
    PeakMeter::new(channels).expect("valid meter")
}

#[test]
fn rejects_unsupported_channel_counts_and_thresholds() {
    assert!(matches!(
        PeakMeter::new(0),
        Err(MeterError::UnsupportedChannelCount(0))
    ));
    assert!(matches!(
        PeakMeter::new(3),
        Err(MeterError::UnsupportedChannelCount(3))
    ));
    assert!(matches!(
        PeakMeter::with_clip_threshold(2, 0.0),
        Err(MeterError::InvalidClipThreshold(_))
    ));
    assert!(matches!(
        PeakMeter::with_clip_threshold(2, f64::NAN),
        Err(MeterError::InvalidClipThreshold(_))
    ));
    assert_eq!(meter(2).clip_threshold(), CLIP_THRESHOLD_LINEAR);
}

#[test]
fn silence_reports_zero_peak_and_the_dbfs_floor() {
    let mut peak_meter = meter(2);
    let block = peak_meter
        .process_interleaved(&[0.0; 8])
        .expect("valid block");
    assert_eq!(block.overall_peak(), 0.0);
    assert_eq!(block.overall_peak_dbfs(), DBFS_FLOOR);
    assert!(!block.clipping_detected());
    assert_eq!(block.frames(), 4);
}

#[test]
fn low_amplitude_maps_to_expected_dbfs() {
    let mut peak_meter = meter(1);
    let block = peak_meter
        .process_interleaved(&[0.5, -0.5, 0.25])
        .expect("valid block");
    assert!((block.overall_peak() - 0.5).abs() < f64::EPSILON);
    let expected = 20.0 * 0.5_f64.log10();
    assert!((block.overall_peak_dbfs() - expected).abs() < 1.0e-9);
    assert!(!block.clipping_detected());
}

#[test]
fn positive_and_negative_peaks_are_symmetric() {
    let mut positive = meter(1);
    let mut negative = meter(1);
    let up = positive.process_interleaved(&[0.75]).expect("valid");
    let down = negative.process_interleaved(&[-0.75]).expect("valid");
    assert_eq!(up.overall_peak(), 0.75);
    assert_eq!(down.overall_peak(), 0.75);
}

#[test]
fn full_scale_signal_is_detected_as_clipped() {
    let mut peak_meter = meter(1);
    let block = peak_meter.process_interleaved(&[1.0, -1.0]).expect("valid");
    assert!((block.overall_peak() - 1.0).abs() < f64::EPSILON);
    assert!((block.overall_peak_dbfs() - 0.0).abs() < 1.0e-9);
    assert_eq!(block.clipped_samples(), 2);
    assert!(block.clipping_detected());
}

#[test]
fn above_full_scale_signal_is_clipped_and_counted() {
    let mut peak_meter = meter(2);
    let block = peak_meter
        .process_interleaved(&[1.5, -1.5, 2.0, -0.5])
        .expect("valid");
    assert!((block.overall_peak() - 2.0).abs() < f64::EPSILON);
    assert_eq!(block.clipped_samples(), 3);
    assert_eq!(peak_meter.clipped_samples(), 3);
    assert!(peak_meter.clipping_detected());
}

#[test]
fn stereo_channels_are_measured_independently() {
    let mut peak_meter = meter(2);
    let block = peak_meter
        .process_interleaved(&[0.2, 0.8, 0.3, -0.9])
        .expect("valid");
    assert!((block.per_channel_peak(0) - 0.3).abs() < 1.0e-9);
    assert!((block.per_channel_peak(1) - 0.9).abs() < 1.0e-9);
    assert!((block.overall_peak() - 0.9).abs() < 1.0e-9);
    // Out-of-range channels report zero rather than panicking.
    assert_eq!(block.per_channel_peak(5), 0.0);
}

#[test]
fn mono_channel_count_is_reported() {
    let block = meter(1).process_interleaved(&[0.1, 0.2]).expect("valid");
    assert_eq!(block.channels(), 1);
    assert_eq!(block.frames(), 2);
}

#[test]
fn empty_block_is_safe() {
    let mut peak_meter = meter(2);
    let block = peak_meter.process_interleaved(&[]).expect("valid");
    assert_eq!(block.frames(), 0);
    assert_eq!(block.overall_peak(), 0.0);
    assert_eq!(block.overall_peak_dbfs(), DBFS_FLOOR);
    assert_eq!(peak_meter.processed_frames(), 0);
}

#[test]
fn incomplete_frame_is_rejected() {
    let mut peak_meter = meter(2);
    assert_eq!(
        peak_meter.process_interleaved(&[0.0, 0.0, 0.0]),
        Err(MeterError::InvalidBlockLength {
            samples: 3,
            channels: 2
        })
    );
}

#[test]
fn non_finite_input_never_produces_non_finite_output() {
    let mut peak_meter = meter(2);
    let block = peak_meter
        .process_interleaved(&[f64::NAN, 0.5, f64::INFINITY, f64::NEG_INFINITY, 0.5, 0.5])
        .expect("valid");
    assert!(block.overall_peak().is_finite());
    assert!(block.overall_peak_dbfs().is_finite());
    assert!(block.per_channel_peak_dbfs(0).is_finite());
    // NaN + two infinities are non-finite; the infinities are clipped too.
    assert_eq!(block.non_finite_samples(), 3);
    assert_eq!(block.clipped_samples(), 2);
    assert_eq!(peak_meter.non_finite_samples(), 3);
}

#[test]
fn reset_restores_deterministic_state() {
    let mut peak_meter = meter(2);
    peak_meter
        .process_interleaved(&[0.9, 0.9, 1.2, 1.2])
        .expect("valid");
    assert!(peak_meter.running_overall_peak() > 0.0);
    assert!(peak_meter.clipping_detected());

    peak_meter.reset();
    assert_eq!(peak_meter.running_overall_peak(), 0.0);
    assert_eq!(peak_meter.running_peak_dbfs(0), DBFS_FLOOR);
    assert_eq!(peak_meter.clipped_samples(), 0);
    assert_eq!(peak_meter.non_finite_samples(), 0);
    assert_eq!(peak_meter.processed_frames(), 0);
}

#[test]
fn repeated_blocks_hold_the_running_peak() {
    let mut peak_meter = meter(1);
    peak_meter.process_interleaved(&[0.2, 0.3]).expect("valid");
    peak_meter.process_interleaved(&[0.1]).expect("valid");
    assert!((peak_meter.running_overall_peak() - 0.3).abs() < 1.0e-9);

    let quiet = peak_meter.process_interleaved(&[0.05]).expect("valid");
    // The block peak reflects only this block, the running peak holds the max.
    assert!((quiet.overall_peak() - 0.05).abs() < 1.0e-9);
    assert!((peak_meter.running_overall_peak() - 0.3).abs() < 1.0e-9);
}

#[test]
fn long_sequence_of_blocks_stays_finite_and_monotone() {
    let mut peak_meter = meter(2);
    let mut expected_frames = 0_u64;
    for step in 0..2_000_u32 {
        let amplitude = ((step % 50) as f64) / 50.0;
        let samples = [amplitude, -amplitude];
        let block = peak_meter.process_interleaved(&samples).expect("valid");
        assert!(block.overall_peak().is_finite());
        expected_frames += 1;
    }
    assert_eq!(peak_meter.processed_frames(), expected_frames);
    assert!((peak_meter.running_overall_peak() - 0.98).abs() < 1.0e-9);
    assert!(!peak_meter.clipping_detected());
}

#[test]
fn linear_to_dbfs_is_finite_for_extremes() {
    assert_eq!(linear_to_dbfs(0.0), DBFS_FLOOR);
    assert_eq!(linear_to_dbfs(-0.0), DBFS_FLOOR);
    assert_eq!(linear_to_dbfs(f64::NAN), DBFS_FLOOR);
    assert_eq!(linear_to_dbfs(f64::INFINITY), DBFS_FLOOR);
    assert_eq!(linear_to_dbfs(f64::MIN_POSITIVE / 4.0), DBFS_FLOOR);
    assert!(linear_to_dbfs(f64::MAX).is_finite());
    assert!(linear_to_dbfs(1.0).abs() < 1.0e-12);
}
