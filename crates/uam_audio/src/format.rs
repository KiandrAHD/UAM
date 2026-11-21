//! Boundary sample-format conversion between interleaved `f64` and the byte
//! layout of an endpoint's stream.
//!
//! The DSP host always works in interleaved `f64`. A platform endpoint expects
//! its own container: IEEE float32, PCM16, packed PCM24, or PCM32. This module
//! converts at the boundary. It operates on plain byte slices, so it is fully
//! unit-testable without any audio device and contains no platform API.
//!
//! # Correctness rules
//!
//! - A sample is clamped to `[-1.0, 1.0]` before integer quantisation, so an
//!   overshoot saturates instead of wrapping around. Each clamped sample is
//!   counted in [`FormatReport::clamped_samples`].
//! - `NaN` and infinity are written as digital silence and counted in
//!   [`FormatReport::non_finite_samples`].
//! - Integer encodings scale to the *valid* bits and are left-shifted into the
//!   container when the container is wider (for example 24 valid bits in a
//!   32-bit word).
//! - Decoding is the exact inverse scaling, used by tests and by a future
//!   capture path. It is symmetric for every supported encoding.

use crate::config::{SampleEncoding, StreamFormat};

/// Outcome of one encode or decode pass.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct FormatReport {
    /// Frames converted.
    pub frames: usize,
    /// Samples clamped to full scale (encode only).
    pub clamped_samples: u64,
    /// Non-finite samples replaced with silence.
    pub non_finite_samples: u64,
}

impl FormatReport {
    /// A pass that converted nothing.
    #[must_use]
    pub const fn empty() -> Self {
        Self {
            frames: 0,
            clamped_samples: 0,
            non_finite_samples: 0,
        }
    }
}

/// Largest positive integer value for `valid_bits` two's-complement samples.
const fn integer_peak(valid_bits: u16) -> f64 {
    // 2^(valid_bits - 1) - 1, exact in f64 for all supported widths.
    ((1_u64 << (valid_bits - 1)) - 1) as f64
}

/// Encode interleaved `f64` samples into an endpoint buffer.
///
/// `out` must be at least `fmt.buffer_bytes(frames)` long; only that many bytes
/// are written. `samples` must contain at least `frames * channels` values.
///
/// # Panics
///
/// Panics when the two buffers are too small, which is a programming error in
/// the caller (the backend validates sizes before calling).
#[must_use]
pub fn encode(fmt: &StreamFormat, samples: &[f64], frames: usize, out: &mut [u8]) -> FormatReport {
    let channels = usize::from(fmt.channels());
    let sample_bytes = fmt.sample_bytes();
    let frame_bytes = fmt.frame_bytes();
    let needed_out = frame_bytes * frames;
    let needed_in = channels * frames;
    assert!(out.len() >= needed_out, "output buffer too small");
    assert!(samples.len() >= needed_in, "sample buffer too small");

    let mut report = FormatReport {
        frames,
        ..FormatReport::empty()
    };
    let valid_bits = fmt.valid_bits();
    let shift = u32::from(fmt.container_bits() - valid_bits);
    let peak = integer_peak(valid_bits);

    for frame in 0..frames {
        for channel in 0..channels {
            let index = frame * channels + channel;
            let mut value = samples[index];
            if !value.is_finite() {
                report.non_finite_samples += 1;
                value = 0.0;
            } else if value > 1.0 {
                value = 1.0;
                report.clamped_samples += 1;
            } else if value < -1.0 {
                value = -1.0;
                report.clamped_samples += 1;
            }
            let offset = frame * frame_bytes + channel * sample_bytes;
            write_sample(
                fmt.encoding(),
                value,
                peak,
                shift,
                &mut out[offset..offset + sample_bytes],
            );
        }
    }
    report
}

/// Decode an endpoint buffer into interleaved `f64` samples.
///
/// `input` must contain at least `frames * frame_bytes` bytes; `out` must hold
/// at least `frames * channels` values.
///
/// # Panics
///
/// Panics when the two buffers are too small.
#[must_use]
pub fn decode(fmt: &StreamFormat, input: &[u8], frames: usize, out: &mut [f64]) -> FormatReport {
    let channels = usize::from(fmt.channels());
    let sample_bytes = fmt.sample_bytes();
    let frame_bytes = fmt.frame_bytes();
    assert!(
        input.len() >= frame_bytes * frames,
        "input buffer too small"
    );
    assert!(out.len() >= channels * frames, "output buffer too small");

    let mut report = FormatReport {
        frames,
        ..FormatReport::empty()
    };
    let valid_bits = fmt.valid_bits();
    let shift = u32::from(fmt.container_bits() - valid_bits);
    let inv_peak = 1.0 / integer_peak(valid_bits);

    for frame in 0..frames {
        for channel in 0..channels {
            let offset = frame * frame_bytes + channel * sample_bytes;
            let value = read_sample(
                fmt.encoding(),
                shift,
                inv_peak,
                &input[offset..offset + sample_bytes],
            );
            if value.is_finite() {
                out[frame * channels + channel] = value;
            } else {
                report.non_finite_samples += 1;
                out[frame * channels + channel] = 0.0;
            }
        }
    }
    report
}

/// Write one clamped sample into a `sample_bytes`-wide little-endian slot.
fn write_sample(encoding: SampleEncoding, value: f64, peak: f64, shift: u32, slot: &mut [u8]) {
    match encoding {
        SampleEncoding::F32 => {
            let bytes = (value as f32).to_le_bytes();
            slot.copy_from_slice(&bytes);
        }
        SampleEncoding::S16 | SampleEncoding::S24 | SampleEncoding::S32 => {
            let quantized = (value * peak).round() as i64;
            let scaled = (quantized << shift) as u32;
            let bytes = scaled.to_le_bytes();
            slot.copy_from_slice(&bytes[..slot.len()]);
        }
    }
}

/// Read one sample from a `sample_bytes`-wide little-endian slot.
fn read_sample(encoding: SampleEncoding, shift: u32, inv_peak: f64, slot: &[u8]) -> f64 {
    match encoding {
        SampleEncoding::F32 => {
            let mut bytes = [0_u8; 4];
            bytes.copy_from_slice(slot);
            f64::from(f32::from_le_bytes(bytes))
        }
        SampleEncoding::S16 | SampleEncoding::S24 | SampleEncoding::S32 => {
            let mut padded = [0_u8; 4];
            padded[..slot.len()].copy_from_slice(slot);
            let container_bits = 8 * slot.len() as u32;
            let raw = u32::from_le_bytes(padded);
            // Sign-extend from the container width.
            let signed = if container_bits == 32 {
                raw as i32 as i64
            } else {
                let shift_in = 32 - container_bits;
                ((raw << shift_in) as i32 >> shift_in) as i64
            };
            let value = signed >> shift;
            value as f64 * inv_peak
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fmt(encoding: SampleEncoding, container: u16, valid: u16) -> StreamFormat {
        StreamFormat::new(48_000, 2, encoding, container, valid).expect("valid format")
    }

    fn round_trip(encoding: SampleEncoding, container: u16, valid: u16, tolerance: f64) {
        let format = fmt(encoding, container, valid);
        let frames = 64;
        let channels = 2;
        let mut samples = Vec::with_capacity(frames * channels);
        for frame in 0..frames {
            let t = frame as f64 / frames as f64;
            samples.push((t * 2.0 - 1.0) * 0.9);
            samples.push(-(t * 2.0 - 1.0) * 0.9);
        }
        let mut bytes = vec![0_u8; format.buffer_bytes(frames)];
        let encode_report = encode(&format, &samples, frames, &mut bytes);
        assert_eq!(encode_report.frames, frames);
        assert_eq!(encode_report.clamped_samples, 0);
        assert_eq!(encode_report.non_finite_samples, 0);

        let mut decoded = vec![0.0_f64; frames * channels];
        let decode_report = decode(&format, &bytes, frames, &mut decoded);
        assert_eq!(decode_report.frames, frames);
        for (original, restored) in samples.iter().zip(decoded.iter()) {
            assert!(
                (original - restored).abs() <= tolerance,
                "{} vs {} for {:?}",
                original,
                restored,
                encoding
            );
        }
    }

    #[test]
    fn float32_round_trip() {
        round_trip(SampleEncoding::F32, 32, 32, 1e-6);
    }

    #[test]
    fn pcm16_round_trip() {
        round_trip(SampleEncoding::S16, 16, 16, 1.0 / 32767.0 + 1e-6);
    }

    #[test]
    fn pcm24_round_trip() {
        round_trip(SampleEncoding::S24, 24, 24, 1.0 / 8_388_607.0 + 1e-7);
    }

    #[test]
    fn pcm32_round_trip() {
        round_trip(SampleEncoding::S32, 32, 32, 1.0 / 2_147_483_647.0 + 1e-9);
    }

    #[test]
    fn pcm24_in_32_container_round_trip() {
        round_trip(SampleEncoding::S32, 32, 24, 2.0 / 8_388_607.0);
    }

    #[test]
    fn encodes_expected_pcm16_values() {
        let format = fmt(SampleEncoding::S16, 16, 16);
        let samples = [0.0, 1.0, -1.0, 0.5];
        let mut bytes = [0_u8; 8];
        let report = encode(&format, &samples, 2, &mut bytes);
        assert_eq!(report.clamped_samples, 0);
        assert_eq!(i16::from_le_bytes([bytes[0], bytes[1]]), 0);
        assert_eq!(i16::from_le_bytes([bytes[2], bytes[3]]), i16::MAX);
        assert_eq!(i16::from_le_bytes([bytes[4], bytes[5]]), -i16::MAX);
        assert_eq!(i16::from_le_bytes([bytes[6], bytes[7]]), 16_384);
    }

    #[test]
    fn non_finite_samples_become_silence() {
        let format = fmt(SampleEncoding::F32, 32, 32);
        let samples = [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, 0.25];
        let mut bytes = [0_u8; 16];
        let report = encode(&format, &samples, 2, &mut bytes);
        assert_eq!(report.non_finite_samples, 3);
        assert_eq!(
            f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]),
            0.0
        );
        assert_eq!(
            f32::from_le_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]),
            0.0
        );
        assert_eq!(
            f32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]),
            0.0
        );
        assert_eq!(
            f32::from_le_bytes([bytes[12], bytes[13], bytes[14], bytes[15]]),
            0.25
        );
    }

    #[test]
    fn out_of_range_samples_clamp_without_wrapping() {
        let format = fmt(SampleEncoding::S16, 16, 16);
        let samples = [4.0, -4.0];
        let mut bytes = [0_u8; 4];
        let report = encode(&format, &samples, 1, &mut bytes);
        assert_eq!(report.clamped_samples, 2);
        assert_eq!(i16::from_le_bytes([bytes[0], bytes[1]]), i16::MAX);
        assert_eq!(i16::from_le_bytes([bytes[2], bytes[3]]), -i16::MAX);
    }

    #[test]
    fn encode_writes_exactly_the_requested_frame_count() {
        let format = fmt(SampleEncoding::S24, 24, 24);
        let frames = 3;
        let samples = vec![0.1_f64; frames * 2];
        let mut bytes = vec![0xAA_u8; format.buffer_bytes(frames) + 8];
        let tail = bytes.len();
        let _ = encode(&format, &samples, frames, &mut bytes);
        // Bytes past the requested frame count are untouched.
        assert_eq!(bytes[format.buffer_bytes(frames)], 0xAA);
        assert_eq!(bytes[tail - 1], 0xAA);
    }

    #[test]
    fn decode_rejects_and_counts_non_finite_float() {
        let format = fmt(SampleEncoding::F32, 32, 32);
        let mut bytes = [0_u8; 8];
        bytes[..4].copy_from_slice(&f32::NAN.to_le_bytes());
        bytes[4..].copy_from_slice(&0.5_f32.to_le_bytes());
        let mut out = [0.0_f64; 2];
        let report = decode(&format, &bytes, 1, &mut out);
        assert_eq!(report.non_finite_samples, 1);
        assert_eq!(out[0], 0.0);
        assert!((out[1] - 0.5).abs() < 1e-6);
    }
}
