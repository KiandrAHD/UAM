//! Phase 2.3C — limiter signal-processing tests.

use core::f64::consts::TAU;
use uam_domain::AudioConfig;
use uam_dsp::{Limiter, LimiterConfig};

fn stereo_48k() -> AudioConfig {
    AudioConfig::new(48_000, 2).expect("valid configuration")
}
fn mono_48k() -> AudioConfig {
    AudioConfig::new(48_000, 1).expect("valid configuration")
}

fn limiter(enabled: bool, ceiling_db: f64, release_ms: f64, audio: AudioConfig) -> Limiter {
    let config = LimiterConfig::new(enabled, ceiling_db, release_ms).expect("valid limiter config");
    Limiter::new(&config, audio).expect("valid limiter")
}

fn make_samples(
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

#[test]
fn disabled_limiter_is_bit_exact_pass_through() {
    let mut limiter = limiter(false, -0.3, 100.0, stereo_48k());
    let mut samples = [0.1, -0.2, 0.3, -0.4];
    let original = samples;
    limiter
        .process_interleaved(&mut samples)
        .expect("valid buffer");
    assert_eq!(samples, original);
}

#[test]
fn signal_below_ceiling_is_not_reduced() {
    let mut limiter = limiter(true, 0.0, 100.0, stereo_48k());
    let mut samples = [0.1, 0.2, -0.1, -0.2];
    limiter
        .process_interleaved(&mut samples)
        .expect("valid buffer");
    assert_eq!(samples, [0.1, 0.2, -0.1, -0.2]);
    assert!((limiter.gain() - 1.0).abs() < 1.0e-12);
}

#[test]
fn signal_at_ceiling_is_bounded() {
    let mut limiter = limiter(true, 0.0, 100.0, stereo_48k());
    // A 1.0 sample is exactly at 0 dBFS.
    let mut samples = [1.0, -1.0];
    limiter.process_interleaved(&mut samples).expect("valid");
    // Gain should have attacked to 1.0/1.0 = 1.0; output = 1.0.
    assert!(samples[0].abs() <= 1.0);
}

#[test]
fn signal_above_ceiling_is_reduced() {
    let mut limiter = limiter(true, 0.0, 100.0, stereo_48k());
    let mut samples = [2.0, -2.0];
    limiter.process_interleaved(&mut samples).expect("valid");
    // Output magnitude must not exceed 1.0.
    assert!(samples[0].abs() <= 1.0 + 1.0e-12);
    assert!(samples[1].abs() <= 1.0 + 1.0e-12);
    assert!(limiter.gain() < 1.0);
    assert!(limiter.gain_reduction_db() > 0.0);
}

#[test]
fn ceiling_at_minus_03dbfs_reduces_unity_signal() {
    // -0.3 dBFS ≈ 0.966.
    let mut limiter = limiter(true, -0.3, 100.0, stereo_48k());
    let mut samples = [1.0, -1.0];
    limiter.process_interleaved(&mut samples).expect("valid");
    assert!(samples[0].abs() < 1.0);
    assert!(samples[0].abs() >= 0.95);
}

#[test]
fn positive_and_negative_peaks_are_both_bounded() {
    let mut limiter = limiter(true, -1.0, 100.0, stereo_48k());
    let ceiling = 10.0_f64.powf(-1.0 / 20.0); // -1 dBFS linear.
    let mut samples = [1.5, -1.8];
    limiter.process_interleaved(&mut samples).expect("valid");
    assert!(samples[0].abs() <= ceiling + 1e-12);
    assert!(samples[1].abs() <= ceiling + 1e-12);
}

#[test]
fn sine_wave_above_ceiling_is_limited() {
    let mut limiter = limiter(true, -3.0, 200.0, stereo_48k());
    let amplitude = 1.5; // +3.5 dBFS
    let samples = make_samples(1_000.0, 48_000, 1, 4_800, amplitude);
    let mut processed = samples.clone();
    limiter.process_interleaved(&mut processed).expect("valid");
    // No output sample should exceed the ceiling.
    let ceiling = 10.0_f64.powf(-3.0 / 20.0);
    for sample in &processed {
        assert!(
            sample.abs() <= ceiling + 1e-12,
            "output {} exceeded ceiling {}",
            sample,
            ceiling
        );
    }
}

#[test]
fn impulse_is_bounded() {
    let mut limiter = limiter(true, -6.0, 50.0, stereo_48k());
    let mut samples = vec![0.0; 20];
    samples[0] = 5.0; // impulse above ceiling
    limiter.process_interleaved(&mut samples).expect("valid");
    let ceiling = 10.0_f64.powf(-6.0 / 20.0);
    for sample in &samples {
        assert!(sample.abs() <= ceiling + 1e-12);
    }
}

#[test]
fn transient_burst_triggers_attack() {
    let mut limiter = limiter(true, -3.0, 200.0, stereo_48k());
    // A burst above the ceiling followed by silence, processed as two blocks so
    // attack and release can be observed separately.
    let mut burst = vec![0.0; 48 * 2];
    for frame in burst.chunks_exact_mut(2) {
        frame[0] = 1.0;
        frame[1] = -1.0;
    }
    limiter.process_interleaved(&mut burst).expect("valid");

    let ceiling = 10.0_f64.powf(-3.0 / 20.0);
    for sample in &burst {
        assert!(sample.abs() <= ceiling + 1e-12);
    }
    let gain_after_attack = limiter.gain();
    assert!(gain_after_attack < 1.0);

    // The silence block releases the gain toward unity without overshoot.
    limiter.process_interleaved(&mut [0.0; 96]).expect("valid");
    assert!(limiter.gain() > gain_after_attack);
    assert!(limiter.gain() <= 1.0);
}

#[test]
fn release_recovery_is_gradual() {
    let mut limiter = limiter(true, -1.0, 500.0, stereo_48k());
    // Drive gain down.
    limiter
        .process_interleaved(&mut [1.5_f64, -1.5])
        .expect("valid");
    let gain_after_attack = limiter.gain();
    assert!(gain_after_attack < 1.0);

    // Subsequent silent frames allow gain to release.
    let first_gain = limiter.gain();
    limiter
        .process_interleaved(&mut [0.0_f64, 0.0])
        .expect("valid");
    let second_gain = limiter.gain();
    assert!(second_gain > first_gain, "gain should release toward unity");
    assert!(second_gain <= 1.0);
}

#[test]
fn mono_processing_bounded() {
    let mut limiter = limiter(true, -6.0, 100.0, mono_48k());
    let mut samples = [0.5, 1.5, -0.5, 2.0, 0.1];
    limiter.process_interleaved(&mut samples).expect("valid");
    let ceiling = 10.0_f64.powf(-6.0 / 20.0);
    for sample in &samples {
        assert!(sample.abs() <= ceiling + 1e-12);
    }
}

#[test]
fn stereo_linking_applies_single_gain_to_both_channels() {
    let mut limiter = limiter(true, -3.0, 100.0, stereo_48k());
    let ceiling = 10.0_f64.powf(-3.0 / 20.0); // 0.7079
                                              // Channel 0 above the ceiling, channel 1 far below it.
    let input0 = 0.9_f64;
    let input1 = 0.1_f64;
    let mut samples = [input0, input1, -input0, -input1];
    limiter
        .process_interleaved(&mut samples)
        .expect("valid block");

    // One linked gain means both channels were scaled by the same factor.
    let gain_left = samples[0].abs() / input0;
    let gain_right = samples[1].abs() / input1;
    assert!(
        (gain_left - gain_right).abs() < 1.0e-12,
        "channel gains diverged: {gain_left} vs {gain_right}"
    );
    // And the loud channel is bounded by the ceiling.
    assert!(samples[0].abs() <= ceiling + 1e-12);
}

#[test]
fn consecutive_blocks_maintain_state() {
    let mut limiter = limiter(true, -6.0, 200.0, stereo_48k());
    // First block: quiet → gain stays 1.0.
    let _ = limiter.process_interleaved(&mut [0.1_f64, 0.1]);
    assert!((limiter.gain() - 1.0).abs() < 1.0e-12);

    // Second block: loud.
    limiter
        .process_interleaved(&mut [2.0_f64, -2.0])
        .expect("valid");
    let gain_after_loud = limiter.gain();
    assert!(gain_after_loud < 1.0);

    // Third block: quiet again; gain should be recovering.
    let _ = limiter.process_interleaved(&mut [0.1_f64, 0.1]);
    assert!(limiter.gain() > gain_after_loud);
    assert!(limiter.gain() <= 1.0);
}

#[test]
fn reset_restores_deterministic_state() {
    let mut limiter = limiter(true, -3.0, 100.0, stereo_48k());
    limiter
        .process_interleaved(&mut [2.0_f64, -2.0])
        .expect("valid");
    assert!(limiter.gain() < 1.0);
    limiter.reset();
    assert!((limiter.gain() - 1.0).abs() < f64::EPSILON);
    assert!(limiter.peak_reduction_db() < 0.01);
    assert_eq!(limiter.limited_samples(), 0);
}

#[test]
fn long_run_stability() {
    let mut limiter = limiter(true, -3.0, 100.0, stereo_48k());
    let amplitude = 1.5;
    for step in 0..10_000 {
        let phase = TAU * 1000.0 * (step as f64) / 48_000.0;
        let value = amplitude * phase.sin();
        let mut samples = [value, value];
        limiter
            .process_interleaved(&mut samples)
            .expect("valid block");
        assert!(samples[0].is_finite(), "step {step}: output NaN/inf");
        assert!(samples[0].abs() <= 1.0 + 1e-12);
    }
}

#[test]
fn non_finite_input_is_sanitized_and_state_preserved() {
    let mut limiter = limiter(true, -3.0, 100.0, stereo_48k());
    // Drive gain down first.
    limiter
        .process_interleaved(&mut [2.0_f64, -2.0])
        .expect("valid");
    let gain_before = limiter.gain();

    // Now inject non-finite samples.
    let mut samples = [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, 0.5_f64];
    limiter
        .process_interleaved(&mut samples)
        .expect("valid block");
    // Output must be finite.
    for sample in &samples {
        assert!(sample.is_finite(), "output was {sample}");
    }
    // Non-finite values are treated as zero; the finite 0.5 sample permits a
    // normal release step, but cannot contaminate the gain state.
    assert!(limiter.gain().is_finite());
    assert!(limiter.gain() >= gain_before);
    assert!(limiter.gain() <= 1.0);
}

#[test]
fn maximum_supported_signal_amplitude_is_bounded() {
    let mut limiter = limiter(true, 0.0, 50.0, stereo_48k());
    // f64::MAX is not realistic but the limiter must not panic or overflow.
    let mut samples = [f64::MAX / 1e100, f64::MIN_POSITIVE];
    limiter.process_interleaved(&mut samples).expect("valid");
    assert!(samples[0].is_finite());
    assert!(samples[1].is_finite());
}

#[test]
fn set_enabled_false_resets_gain() {
    let mut limiter = limiter(true, -3.0, 100.0, stereo_48k());
    limiter
        .process_interleaved(&mut [2.0_f64, -2.0])
        .expect("valid");
    assert!(limiter.gain() < 1.0);
    limiter.set_enabled(false);
    assert!((limiter.gain() - 1.0).abs() < f64::EPSILON);
    // Disabled limiter is pass-through.
    let mut samples = [0.5_f64, 0.5];
    limiter.process_interleaved(&mut samples).expect("valid");
    assert_eq!(samples, [0.5_f64, 0.5]);
}

#[test]
fn ceiling_0dbfs_guarantees_output_never_exceeds_one() {
    let mut limiter = limiter(true, 0.0, 50.0, stereo_48k());
    for amplitude in [1.0, 1.5, 2.0, 10.0, 100.0] {
        let mut samples = [amplitude, amplitude];
        limiter.process_interleaved(&mut samples).expect("valid");
        assert!(
            samples[0].abs() <= 1.0 + 1e-12,
            "amplitude {amplitude} produced {}",
            samples[0]
        );
    }
}

#[test]
fn release_coefficient_is_sample_rate_aware() {
    // A fast release (10 ms) should reach near-unity quickly.
    let mut fast = limiter(true, -6.0, 10.0, stereo_48k());
    // Drive gain down.
    fast.process_interleaved(&mut [3.0_f64, -3.0])
        .expect("valid");
    let gain_before = fast.gain();
    // One silent block allows some release.
    fast.process_interleaved(&mut [0.0_f64, 0.0])
        .expect("valid");
    let gain_after = fast.gain();
    assert!(gain_after > gain_before);

    // A slow release (1 s) should barely recover in the same time.
    let mut slow = limiter(true, -6.0, 1000.0, stereo_48k());
    slow.process_interleaved(&mut [3.0_f64, -3.0])
        .expect("valid");
    let slow_gain_before = slow.gain();
    slow.process_interleaved(&mut [0.0_f64, 0.0])
        .expect("valid");
    let slow_gain_after = slow.gain();
    // The fast limiter should have released more than the slow one.
    assert!(
        (gain_after - gain_before) > (slow_gain_after - slow_gain_before),
        "fast release did not recover faster than slow"
    );
}
