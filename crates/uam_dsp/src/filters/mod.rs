//! Biquad filter primitives and validated band parameters.
//!
//! Coefficients are derived with the RBJ Audio EQ Cookbook equations. For
//! peaking filters `q` is the conventional quality factor. For shelving
//! filters `q` controls the transition width through
//! `alpha = sin(w0) / (2q)`; it is not the cookbook shelf-slope `S` parameter,
//! so the documented parameter is intentionally named `q` everywhere.

use core::f64::consts::PI;
use core::fmt;

use uam_domain::AudioConfig;

use crate::validation::{
    DspError, MAX_FREQUENCY_HZ, MAX_GAIN_DB, MAX_Q, MIN_FREQUENCY_HZ, MIN_GAIN_DB, MIN_Q,
};

/// Supported equalizer filter shapes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FilterKind {
    /// Symmetric peaking band centred on `frequency_hz`.
    Peaking,
    /// Low-frequency shelving filter.
    LowShelf,
    /// High-frequency shelving filter.
    HighShelf,
}

impl FilterKind {
    /// Stable snake-case identifier used by the preset format.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Peaking => "peaking",
            Self::LowShelf => "low_shelf",
            Self::HighShelf => "high_shelf",
        }
    }
}

impl fmt::Display for FilterKind {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// One validated EQ band.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BandConfig {
    /// Filter shape.
    pub kind: FilterKind,
    /// Centre or corner frequency in hertz.
    pub frequency_hz: f64,
    /// Linear gain in decibels.
    pub gain_db: f64,
    /// Quality factor, or shelf transition-width control.
    pub q: f64,
}

impl BandConfig {
    /// Validate a band against sample-rate-independent bounds.
    ///
    /// # Errors
    ///
    /// Returns [`DspError`] for non-finite, out-of-range, or unsupported
    /// parameters. The sample-rate-dependent upper frequency bound is checked
    /// when the band is added to an [`crate::Equalizer`].
    pub fn new(
        kind: FilterKind,
        frequency_hz: f64,
        gain_db: f64,
        q: f64,
    ) -> Result<Self, DspError> {
        let band = Self {
            kind,
            frequency_hz,
            gain_db,
            q,
        };
        band.validate_general()?;
        Ok(band)
    }

    fn validate_general(self) -> Result<(), DspError> {
        if !self.frequency_hz.is_finite() {
            return Err(DspError::NonFiniteParameter("frequencyHz"));
        }
        if !self.gain_db.is_finite() {
            return Err(DspError::NonFiniteParameter("gainDb"));
        }
        if !self.q.is_finite() {
            return Err(DspError::NonFiniteParameter("q"));
        }
        if self.frequency_hz < MIN_FREQUENCY_HZ {
            return Err(DspError::FrequencyTooLow {
                frequency_hz: self.frequency_hz,
                minimum_hz: MIN_FREQUENCY_HZ,
            });
        }
        if self.frequency_hz > MAX_FREQUENCY_HZ {
            return Err(DspError::FrequencyTooHigh {
                frequency_hz: self.frequency_hz,
                maximum_hz: MAX_FREQUENCY_HZ,
            });
        }
        if !(MIN_GAIN_DB..=MAX_GAIN_DB).contains(&self.gain_db) {
            return Err(DspError::GainOutOfRange {
                gain_db: self.gain_db,
            });
        }
        if !(MIN_Q..=MAX_Q).contains(&self.q) {
            return Err(DspError::QOutOfRange { q: self.q });
        }
        Ok(())
    }

    pub(crate) fn validate_for(self, config: AudioConfig) -> Result<(), DspError> {
        self.validate_general()?;
        let maximum_hz = config.max_usable_frequency_hz();
        if self.frequency_hz > maximum_hz {
            return Err(DspError::FrequencyTooHigh {
                frequency_hz: self.frequency_hz,
                maximum_hz,
            });
        }
        Ok(())
    }
}

/// Normalized biquad coefficients for `H(z) = (b0 + b1 z^-1 + b2 z^-2) /
/// (1 + a1 z^-1 + a2 z^-2)`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BiquadCoefficients {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

impl BiquadCoefficients {
    /// Compute coefficients for a validated band at a specific sample rate.
    ///
    /// # Errors
    ///
    /// Returns [`DspError`] when the band exceeds the usable band for the
    /// sample rate or when the resulting coefficients are not finite.
    pub fn from_band(band: BandConfig, config: AudioConfig) -> Result<Self, DspError> {
        band.validate_for(config)?;

        let a = 10.0_f64.powf(band.gain_db / 40.0);
        let omega = 2.0 * PI * band.frequency_hz / f64::from(config.sample_rate_hz());
        let (sin_omega, cos_omega) = omega.sin_cos();
        let alpha = sin_omega / (2.0 * band.q);
        let sqrt_a = a.sqrt();
        let two_sqrt_a_alpha = 2.0 * sqrt_a * alpha;

        let (b0, b1, b2, a0, a1, a2) = match band.kind {
            FilterKind::Peaking => (
                1.0 + alpha * a,
                -2.0 * cos_omega,
                1.0 - alpha * a,
                1.0 + alpha / a,
                -2.0 * cos_omega,
                1.0 - alpha / a,
            ),
            FilterKind::LowShelf => (
                a * ((a + 1.0) - (a - 1.0) * cos_omega + two_sqrt_a_alpha),
                2.0 * a * ((a - 1.0) - (a + 1.0) * cos_omega),
                a * ((a + 1.0) - (a - 1.0) * cos_omega - two_sqrt_a_alpha),
                (a + 1.0) + (a - 1.0) * cos_omega + two_sqrt_a_alpha,
                -2.0 * ((a - 1.0) + (a + 1.0) * cos_omega),
                (a + 1.0) + (a - 1.0) * cos_omega - two_sqrt_a_alpha,
            ),
            FilterKind::HighShelf => (
                a * ((a + 1.0) + (a - 1.0) * cos_omega + two_sqrt_a_alpha),
                -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_omega),
                a * ((a + 1.0) + (a - 1.0) * cos_omega - two_sqrt_a_alpha),
                (a + 1.0) - (a - 1.0) * cos_omega + two_sqrt_a_alpha,
                2.0 * ((a - 1.0) - (a + 1.0) * cos_omega),
                (a + 1.0) - (a - 1.0) * cos_omega - two_sqrt_a_alpha,
            ),
        };

        if a0.abs() < f64::EPSILON || !a0.is_finite() {
            return Err(DspError::UnstableCoefficients);
        }

        let coefficients = Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        };

        if coefficients.is_finite() {
            Ok(coefficients)
        } else {
            Err(DspError::UnstableCoefficients)
        }
    }

    fn is_finite(self) -> bool {
        self.b0.is_finite()
            && self.b1.is_finite()
            && self.b2.is_finite()
            && self.a1.is_finite()
            && self.a2.is_finite()
    }

    /// Magnitude response in decibels at `frequency_hz`.
    ///
    /// Returns [`f64::NEG_INFINITY`] when the denominator is numerically zero,
    /// which indicates a pole on the unit circle at that frequency.
    #[must_use]
    pub fn magnitude_db_at(self, frequency_hz: f64, sample_rate_hz: u32) -> f64 {
        if !frequency_hz.is_finite() || frequency_hz <= 0.0 || sample_rate_hz == 0 {
            return f64::NEG_INFINITY;
        }

        let omega = 2.0 * PI * frequency_hz / f64::from(sample_rate_hz);
        let (sin_1, cos_1) = omega.sin_cos();
        let (sin_2, cos_2) = (2.0 * omega).sin_cos();

        let numerator_real = self.b0 + self.b1 * cos_1 + self.b2 * cos_2;
        let numerator_imag = -(self.b1 * sin_1 + self.b2 * sin_2);
        let denominator_real = 1.0 + self.a1 * cos_1 + self.a2 * cos_2;
        let denominator_imag = -(self.a1 * sin_1 + self.a2 * sin_2);

        let numerator_magnitude = numerator_real.hypot(numerator_imag);
        let denominator_magnitude = denominator_real.hypot(denominator_imag);

        if denominator_magnitude <= f64::MIN_POSITIVE {
            f64::NEG_INFINITY
        } else {
            20.0 * (numerator_magnitude / denominator_magnitude).log10()
        }
    }
}

/// One Direct Form II Transposed biquad section with independent state.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Biquad {
    coefficients: BiquadCoefficients,
    state_1: f64,
    state_2: f64,
}

impl Biquad {
    /// Create a filter section with zeroed state.
    #[must_use]
    pub const fn new(coefficients: BiquadCoefficients) -> Self {
        Self {
            coefficients,
            state_1: 0.0,
            state_2: 0.0,
        }
    }

    /// Coefficients currently in use.
    #[must_use]
    pub const fn coefficients(self) -> BiquadCoefficients {
        self.coefficients
    }

    /// Process one sample.
    ///
    /// Non-finite input is treated as silence. If state or output becomes
    /// non-finite the section resets and emits silence, preventing `NaN`
    /// propagation into the rest of the chain.
    pub fn process(&mut self, input: f64) -> f64 {
        let input = if input.is_finite() { input } else { 0.0 };
        let output = self.coefficients.b0.mul_add(input, self.state_1);
        self.state_1 =
            self.coefficients.b1.mul_add(input, self.state_2) - self.coefficients.a1 * output;
        self.state_2 = self.coefficients.b2 * input - self.coefficients.a2 * output;

        if output.is_finite() && self.state_1.is_finite() && self.state_2.is_finite() {
            output
        } else {
            self.reset();
            0.0
        }
    }

    /// Clear filter memory without changing coefficients.
    pub fn reset(&mut self) {
        self.state_1 = 0.0;
        self.state_2 = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> AudioConfig {
        AudioConfig::new(48_000, 2).expect("valid test configuration")
    }

    #[test]
    fn peaking_response_at_centre_matches_gain() {
        for gain_db in [-12.0, -6.0, 0.0, 3.0, 6.0, 12.0] {
            let band =
                BandConfig::new(FilterKind::Peaking, 1_000.0, gain_db, 1.0).expect("valid band");
            let coefficients =
                BiquadCoefficients::from_band(band, config()).expect("valid coefficients");
            let response = coefficients.magnitude_db_at(1_000.0, 48_000);
            assert!(
                (response - gain_db).abs() < 0.01,
                "gain {gain_db} dB produced {response} dB"
            );
        }
    }

    #[test]
    fn low_shelf_boosts_low_frequencies_not_high() {
        let band = BandConfig::new(FilterKind::LowShelf, 200.0, 6.0, 0.707).expect("valid band");
        let coefficients =
            BiquadCoefficients::from_band(band, config()).expect("valid coefficients");
        let low = coefficients.magnitude_db_at(20.0, 48_000);
        let high = coefficients.magnitude_db_at(10_000.0, 48_000);
        assert!(low > 5.0, "low shelf response at 20 Hz was {low} dB");
        assert!(
            high.abs() < 1.0,
            "low shelf response at 10 kHz was {high} dB"
        );
    }

    #[test]
    fn high_shelf_boosts_high_frequencies_not_low() {
        let band =
            BandConfig::new(FilterKind::HighShelf, 4_000.0, -6.0, 0.707).expect("valid band");
        let coefficients =
            BiquadCoefficients::from_band(band, config()).expect("valid coefficients");
        let low = coefficients.magnitude_db_at(100.0, 48_000);
        let high = coefficients.magnitude_db_at(20_000.0, 48_000);
        assert!(
            low.abs() < 1.0,
            "high shelf response at 100 Hz was {low} dB"
        );
        assert!(high < -5.0, "high shelf response at 20 kHz was {high} dB");
    }

    #[test]
    fn non_finite_input_does_not_poison_state() {
        let band = BandConfig::new(FilterKind::Peaking, 1_000.0, 6.0, 1.0).expect("valid band");
        let coefficients =
            BiquadCoefficients::from_band(band, config()).expect("valid coefficients");
        let mut filter = Biquad::new(coefficients);
        assert_eq!(filter.process(f64::NAN), 0.0);
        for sample in [0.0, 0.1, -0.1, 0.0] {
            assert!(filter.process(sample).is_finite());
        }
    }
}
