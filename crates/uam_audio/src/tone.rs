//! Diagnostic test-tone source.
//!
//! A deterministic sine oscillator used to demonstrate the vertical slice. It
//! is opt-in, never starts automatically, defaults to a conservative level, and
//! ramps its amplitude up and down so enabling or disabling it cannot click.
//!
//! The oscillator owns a handful of scalars and renders into a caller-provided
//! buffer. It allocates nothing while rendering.

/// Time constant for the amplitude ramp, in seconds.
const RAMP_TIME_CONSTANT_S: f64 = 0.005;
/// Amplitude below which a disabled tone is treated as fully faded out.
const SILENCE_FLOOR: f64 = 1.0e-4;

/// Sine test-tone oscillator with a click-free amplitude ramp.
#[derive(Debug, Clone)]
pub struct ToneOscillator {
    phase: f64,
    amplitude: f64,
    ramp_coefficient: f64,
    active: bool,
}

impl Default for ToneOscillator {
    fn default() -> Self {
        Self::new()
    }
}

impl ToneOscillator {
    /// Create a silent oscillator.
    #[must_use]
    pub fn new() -> Self {
        Self {
            phase: 0.0,
            amplitude: 0.0,
            ramp_coefficient: 0.0,
            active: false,
        }
    }

    /// Whether the oscillator has any non-silent output.
    #[must_use]
    pub const fn is_active(&self) -> bool {
        self.active
    }

    /// Reset phase and amplitude to silence.
    pub fn reset(&mut self) {
        self.phase = 0.0;
        self.amplitude = 0.0;
        self.active = false;
    }

    /// Render `frames` interleaved frames into `out`.
    ///
    /// `target_amplitude` is the linear target level (0 when the tone is
    /// disabled). The oscillator ramps toward it with a short one-pole so it
    /// never steps discontinuously. Returns the peak magnitude written.
    pub fn render(
        &mut self,
        sample_rate_hz: u32,
        channels: usize,
        frames: usize,
        frequency_hz: f64,
        target_amplitude: f64,
        out: &mut [f64],
    ) -> f64 {
        let needed = frames * channels;
        if out.len() < needed || channels == 0 || sample_rate_hz == 0 {
            return 0.0;
        }
        if self.ramp_coefficient == 0.0 {
            let samples = RAMP_TIME_CONSTANT_S * f64::from(sample_rate_hz);
            self.ramp_coefficient = (-1.0 / samples.max(1.0)).exp();
        }

        let target = if target_amplitude.is_finite() && target_amplitude > 0.0 {
            target_amplitude
        } else {
            0.0
        };
        let omega = 2.0 * core::f64::consts::PI * frequency_hz / f64::from(sample_rate_hz);
        let mut peak = 0.0_f64;

        for frame in 0..frames {
            self.amplitude = target + (self.amplitude - target) * self.ramp_coefficient;
            let value = self.amplitude * self.phase.sin();
            self.phase += omega;
            if self.phase > core::f64::consts::TAU {
                self.phase -= core::f64::consts::TAU;
            }
            let magnitude = value.abs();
            if magnitude > peak {
                peak = magnitude;
            }
            for channel in 0..channels {
                out[frame * channels + channel] = value;
            }
        }

        self.active = self.amplitude > SILENCE_FLOOR;
        if !self.active && target == 0.0 {
            self.amplitude = 0.0;
            self.phase = 0.0;
        }
        peak
    }

    /// Fill a buffer with silence without advancing the oscillator.
    pub fn render_silence(out: &mut [f64], needed: usize) {
        let count = needed.min(out.len());
        for sample in &mut out[..count] {
            *sample = 0.0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ramps_up_without_a_step() {
        let mut oscillator = ToneOscillator::new();
        let mut out = vec![0.0_f64; 2 * 48];
        oscillator.render(48_000, 2, 48, 1_000.0, 0.5, &mut out);
        // The very first sample must be tiny: the ramp starts at zero.
        assert!(out[0].abs() < 1e-6, "first sample was {}", out[0]);
        // After ~1 ms (48 frames) the envelope has grown meaningfully.
        let late = out[2 * 47].abs();
        assert!(late > 0.01, "envelope did not grow, sample {late}");
    }

    #[test]
    fn produces_a_sine_at_the_requested_frequency() {
        let mut oscillator = ToneOscillator::new();
        let sample_rate = 48_000_u32;
        let frequency = 1_000.0;
        // Warm the ramp up to full amplitude first.
        for _ in 0..20 {
            let mut warm = vec![0.0_f64; 480];
            oscillator.render(sample_rate, 1, 480, frequency, 1.0, &mut warm);
        }
        let mut out = vec![0.0_f64; 480];
        oscillator.render(sample_rate, 1, 480, frequency, 1.0, &mut out);
        // Zoom on a quiet stretch: 10 samples covering one period.
        let peak = out[100..128].iter().fold(0.0_f64, |m, s| m.max(s.abs()));
        assert!(peak > 0.5, "tone amplitude too low: {peak}");
    }

    #[test]
    fn fades_out_to_silence_when_disabled() {
        let mut oscillator = ToneOscillator::new();
        let mut out = vec![0.0_f64; 2 * 4800];
        // Ramp up to full level, then down.
        for _ in 0..5 {
            oscillator.render(48_000, 2, 4800, 440.0, 0.5, &mut out);
        }
        oscillator.render(48_000, 2, 4800, 440.0, 0.0, &mut out);
        oscillator.render(48_000, 2, 4800, 440.0, 0.0, &mut out);
        assert!(!oscillator.is_active());
        assert!(out[out.len() - 1].abs() < 1e-3, "tail was not silent");
    }

    #[test]
    fn non_finite_target_is_treated_as_silence() {
        let mut oscillator = ToneOscillator::new();
        let mut out = vec![1.0_f64; 2 * 480];
        let peak = oscillator.render(48_000, 2, 480, 1_000.0, f64::NAN, &mut out);
        assert_eq!(peak, 0.0);
        for sample in &out[..960] {
            assert!(sample.is_finite());
        }
    }

    #[test]
    fn render_silence_zeroes_the_requested_span() {
        let mut out = vec![1.0_f64; 32];
        ToneOscillator::render_silence(&mut out, 16);
        for sample in &out[..16] {
            assert_eq!(*sample, 0.0);
        }
        for sample in &out[16..] {
            assert_eq!(*sample, 1.0);
        }
    }
}
