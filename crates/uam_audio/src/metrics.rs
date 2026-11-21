//! Low-overhead runtime metrics shared between the audio thread and the control
//! path.
//!
//! The audio thread only ever performs atomic stores/`fetch_max` on plain
//! integers; there is no lock, allocation, or formatting on the callback thread.
//! The control path reads a consistent-enough snapshot at a low polling rate.
//!
//! # What is measured versus estimated
//!
//! - **Measured**: callback wall-clock duration (`Instant` around the render
//!   step), sample peaks (from the DSP pipeline reports), clipping counts,
//!   limiter gain reduction, frames rendered, glitch/underrun/error counters.
//! - **Estimated**: the callback-duration percentile, which is derived from a
//!   fixed 32 µs histogram rather than from a full sample of every callback.
//! - **Reported by the API**: the endpoint stream latency, read once from
//!   `IAudioClient::GetStreamLatency`.
//!
//! Nothing here fabricates a value: a metric that was never observed is
//! reported as absent.

use core::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use serde::Serialize;

use crate::config::StreamFormat;

/// Number of histogram buckets for callback durations.
const HISTOGRAM_BUCKETS: usize = 64;
/// Width of one histogram bucket in nanoseconds (32 µs).
const HISTOGRAM_BUCKET_NS: u64 = 32_000;

/// Encode a non-negative `f64` as its bit pattern for atomic `fetch_max`.
fn bits(value: f64) -> u64 {
    if value.is_finite() && value >= 0.0 {
        value.to_bits()
    } else {
        0
    }
}

/// Decode a bit pattern produced by [`bits`].
fn from_bits(value: u64) -> f64 {
    f64::from_bits(value)
}

/// Counters and levels updated by the audio thread.
#[derive(Debug)]
pub struct Metrics {
    /// Frames rendered since the stream started.
    pub frames_processed: AtomicU64,
    /// Render callbacks completed.
    pub callbacks: AtomicU64,
    /// Sum of callback durations in nanoseconds.
    pub callback_sum_ns: AtomicU64,
    /// Longest observed callback duration in nanoseconds.
    pub callback_max_ns: AtomicU64,
    histogram: [AtomicU64; HISTOGRAM_BUCKETS],
    histogram_overflow: AtomicU64,
    /// Buffer writes that failed or lost a device buffer.
    pub glitches: AtomicU64,
    /// Event waits that returned before a buffer was available.
    pub underruns: AtomicU64,
    /// Event waits that timed out (missed deadline).
    pub deadline_misses: AtomicU64,
    /// Stream restarts performed by the engine.
    pub stream_restarts: AtomicU64,
    /// Endpoint removal or invalidation events observed.
    pub device_disconnects: AtomicU64,
    /// Backend errors observed by the audio thread.
    pub backend_errors: AtomicU64,
    peak_input: AtomicU64,
    peak_output: AtomicU64,
    limiter_reduction: AtomicU64,
    clipped_output: AtomicU64,
    non_finite_output: AtomicU64,
    /// Stream sample rate in hertz (0 = unknown).
    pub sample_rate_hz: AtomicU64,
    /// Interleaved channels (0 = unknown).
    pub channels: AtomicU64,
    /// Device buffer size in frames (0 = unknown).
    pub buffer_frames: AtomicU64,
    /// API-reported stream latency in 100 ns units (0 = unknown).
    pub stream_latency_100ns: AtomicU64,
    /// Encoding tag: 0 unknown, 1 f32, 16 s16, 24 s24, 32 s32.
    pub encoding_tag: AtomicU64,
    /// Container bits (0 = unknown).
    pub container_bits: AtomicU64,
    /// Valid bits (0 = unknown).
    pub valid_bits: AtomicU64,
    /// Last error code raised by the audio thread (0 = none).
    pub error_code: AtomicU64,
}

impl Default for Metrics {
    fn default() -> Self {
        Self::new()
    }
}

impl Metrics {
    /// Create zeroed metrics.
    #[must_use]
    pub fn new() -> Self {
        Self {
            frames_processed: AtomicU64::new(0),
            callbacks: AtomicU64::new(0),
            callback_sum_ns: AtomicU64::new(0),
            callback_max_ns: AtomicU64::new(0),
            histogram: core::array::from_fn(|_| AtomicU64::new(0)),
            histogram_overflow: AtomicU64::new(0),
            glitches: AtomicU64::new(0),
            underruns: AtomicU64::new(0),
            deadline_misses: AtomicU64::new(0),
            stream_restarts: AtomicU64::new(0),
            device_disconnects: AtomicU64::new(0),
            backend_errors: AtomicU64::new(0),
            peak_input: AtomicU64::new(0),
            peak_output: AtomicU64::new(0),
            limiter_reduction: AtomicU64::new(0),
            clipped_output: AtomicU64::new(0),
            non_finite_output: AtomicU64::new(0),
            sample_rate_hz: AtomicU64::new(0),
            channels: AtomicU64::new(0),
            buffer_frames: AtomicU64::new(0),
            stream_latency_100ns: AtomicU64::new(0),
            encoding_tag: AtomicU64::new(0),
            container_bits: AtomicU64::new(0),
            valid_bits: AtomicU64::new(0),
            error_code: AtomicU64::new(0),
        }
    }

    /// Publish the stream format details once the stream is open.
    pub fn set_format(&self, format: &StreamFormat, buffer_frames: u32) {
        self.sample_rate_hz
            .store(u64::from(format.sample_rate_hz()), Ordering::Relaxed);
        self.channels
            .store(u64::from(format.channels()), Ordering::Relaxed);
        self.buffer_frames
            .store(u64::from(buffer_frames), Ordering::Relaxed);
        self.encoding_tag.store(
            u64::from(format.encoding().bytes_per_sample() * 8),
            Ordering::Relaxed,
        );
        self.container_bits
            .store(u64::from(format.container_bits()), Ordering::Relaxed);
        self.valid_bits
            .store(u64::from(format.valid_bits()), Ordering::Relaxed);
    }

    /// Record one completed callback.
    pub fn record_callback(&self, duration: Duration) {
        let nanos = duration.as_nanos().min(u128::from(u64::MAX)) as u64;
        self.callbacks.fetch_add(1, Ordering::Relaxed);
        self.callback_sum_ns.fetch_add(nanos, Ordering::Relaxed);
        self.callback_max_ns.fetch_max(nanos, Ordering::Relaxed);
        let bucket = (nanos / HISTOGRAM_BUCKET_NS) as usize;
        if bucket < HISTOGRAM_BUCKETS {
            self.histogram[bucket].fetch_add(1, Ordering::Relaxed);
        } else {
            self.histogram_overflow.fetch_add(1, Ordering::Relaxed);
        }
    }

    /// Fold one block's peaks, gain reduction, and clipping into the running
    /// maximum.
    pub fn observe_block(
        &self,
        peak_input: f64,
        peak_output: f64,
        limiter_reduction_db: f64,
        clipped: u64,
        non_finite: u64,
    ) {
        self.peak_input
            .fetch_max(bits(peak_input), Ordering::Relaxed);
        self.peak_output
            .fetch_max(bits(peak_output), Ordering::Relaxed);
        self.limiter_reduction
            .fetch_max(bits(limiter_reduction_db), Ordering::Relaxed);
        if clipped > 0 {
            self.clipped_output.fetch_add(clipped, Ordering::Relaxed);
        }
        if non_finite > 0 {
            self.non_finite_output
                .fetch_add(non_finite, Ordering::Relaxed);
        }
    }

    /// Fold the boundary-encoder's clamping and non-finite replacements into
    /// the running counters.
    pub fn observe_boundary(&self, clamped: u64, non_finite: u64) {
        if clamped > 0 {
            self.clipped_output.fetch_add(clamped, Ordering::Relaxed);
        }
        if non_finite > 0 {
            self.non_finite_output
                .fetch_add(non_finite, Ordering::Relaxed);
        }
    }

    /// Record the API-reported stream latency, in 100 ns units.
    pub fn set_stream_latency_100ns(&self, latency: u64) {
        self.stream_latency_100ns.store(latency, Ordering::Relaxed);
    }

    /// Clear peaks and error state so a fresh stream starts clean.
    pub fn reset_levels(&self) {
        self.peak_input.store(0, Ordering::Relaxed);
        self.peak_output.store(0, Ordering::Relaxed);
        self.limiter_reduction.store(0, Ordering::Relaxed);
        self.clipped_output.store(0, Ordering::Relaxed);
        self.non_finite_output.store(0, Ordering::Relaxed);
    }

    /// Read a snapshot suitable for the control path.
    #[must_use]
    pub fn snapshot(&self) -> MetricsSnapshot {
        let callbacks = self.callbacks.load(Ordering::Relaxed);
        let sum_ns = self.callback_sum_ns.load(Ordering::Relaxed);
        let average_ns = sum_ns.checked_div(callbacks).unwrap_or(0);
        MetricsSnapshot {
            frames_processed: self.frames_processed.load(Ordering::Relaxed),
            callbacks,
            callback_average_us: nanos_to_us(average_ns),
            callback_max_us: nanos_to_us(self.callback_max_ns.load(Ordering::Relaxed)),
            callback_p95_us: self.percentile_us(0.95),
            callback_p99_us: self.percentile_us(0.99),
            percentile_kind: "histogram32us".to_owned(),
            peak_input_dbfs: uam_dsp::linear_to_dbfs(from_bits(
                self.peak_input.load(Ordering::Relaxed),
            )),
            peak_output_dbfs: uam_dsp::linear_to_dbfs(from_bits(
                self.peak_output.load(Ordering::Relaxed),
            )),
            limiter_reduction_db: from_bits(self.limiter_reduction.load(Ordering::Relaxed)),
            clipped_output_samples: self.clipped_output.load(Ordering::Relaxed),
            non_finite_output_samples: self.non_finite_output.load(Ordering::Relaxed),
            glitches: self.glitches.load(Ordering::Relaxed),
            underruns: self.underruns.load(Ordering::Relaxed),
            deadline_misses: self.deadline_misses.load(Ordering::Relaxed),
            stream_restarts: self.stream_restarts.load(Ordering::Relaxed),
            device_disconnects: self.device_disconnects.load(Ordering::Relaxed),
            backend_errors: self.backend_errors.load(Ordering::Relaxed),
            sample_rate_hz: self.sample_rate_hz.load(Ordering::Relaxed),
            channels: u32_from_u64(self.channels.load(Ordering::Relaxed)),
            buffer_frames: u32_from_u64(self.buffer_frames.load(Ordering::Relaxed)),
            stream_latency_ms: latency_100ns_to_ms(
                self.stream_latency_100ns.load(Ordering::Relaxed),
            ),
            encoding_tag: u32_from_u64(self.encoding_tag.load(Ordering::Relaxed)) as u16,
            container_bits: u32_from_u64(self.container_bits.load(Ordering::Relaxed)) as u16,
            valid_bits: u32_from_u64(self.valid_bits.load(Ordering::Relaxed)) as u16,
            error_code: self.error_code.load(Ordering::Relaxed),
        }
    }

    fn percentile_us(&self, quantile: f64) -> f64 {
        let mut total = self.callbacks.load(Ordering::Relaxed);
        let overflow = self.histogram_overflow.load(Ordering::Relaxed);
        if total == 0 {
            return 0.0;
        }
        total += overflow;
        let target = (quantile * total as f64).ceil() as u64;
        let mut cumulative = 0_u64;
        for (index, bucket) in self.histogram.iter().enumerate() {
            cumulative += bucket.load(Ordering::Relaxed);
            if cumulative >= target {
                // Report the upper bound of the bucket in microseconds.
                return nanos_to_us((index as u64 + 1) * HISTOGRAM_BUCKET_NS);
            }
        }
        // Everything landed in the overflow bucket; report its lower bound.
        nanos_to_us(HISTOGRAM_BUCKETS as u64 * HISTOGRAM_BUCKET_NS)
    }
}

fn nanos_to_us(nanos: u64) -> f64 {
    nanos as f64 / 1_000.0
}

fn u32_from_u64(value: u64) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

fn latency_100ns_to_ms(value: u64) -> f64 {
    // 100 ns units to milliseconds.
    value as f64 / 10_000.0
}

/// Immutable metrics snapshot exposed to the control path.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricsSnapshot {
    /// Frames rendered since the stream started.
    pub frames_processed: u64,
    /// Render callbacks completed.
    pub callbacks: u64,
    /// Average callback duration in microseconds.
    pub callback_average_us: f64,
    /// Longest callback duration in microseconds.
    pub callback_max_us: f64,
    /// Estimated 95th-percentile callback duration in microseconds.
    pub callback_p95_us: f64,
    /// Estimated 99th-percentile callback duration in microseconds.
    pub callback_p99_us: f64,
    /// How the percentile was derived (never a full sample of callbacks).
    pub percentile_kind: String,
    /// Highest observed input sample peak, dBFS.
    pub peak_input_dbfs: f64,
    /// Highest observed output sample peak, dBFS.
    pub peak_output_dbfs: f64,
    /// Highest observed limiter gain reduction, dB.
    pub limiter_reduction_db: f64,
    /// Output samples at or above full scale.
    pub clipped_output_samples: u64,
    /// Output samples that were non-finite before sanitising.
    pub non_finite_output_samples: u64,
    /// Failed buffer writes.
    pub glitches: u64,
    /// Buffer waits that produced no writable frames.
    pub underruns: u64,
    /// Event waits that timed out.
    pub deadline_misses: u64,
    /// Stream restarts performed by the engine.
    pub stream_restarts: u64,
    /// Endpoint disconnections observed.
    pub device_disconnects: u64,
    /// Backend errors observed by the audio thread.
    pub backend_errors: u64,
    /// Stream sample rate in hertz.
    pub sample_rate_hz: u64,
    /// Interleaved channels.
    pub channels: u32,
    /// Device buffer size in frames.
    pub buffer_frames: u32,
    /// API-reported stream latency in milliseconds.
    pub stream_latency_ms: f64,
    /// Encoding tag: 0 unknown, 32 f32, 16 s16, 24 s24, 32 s32.
    pub encoding_tag: u16,
    /// Container bits.
    pub container_bits: u16,
    /// Valid bits.
    pub valid_bits: u16,
    /// Last audio-thread error code, or 0.
    pub error_code: u64,
}

impl MetricsSnapshot {
    /// A zeroed snapshot used when no stream is attached. Every level is zero
    /// (full-scale floors), and every format field is unknown.
    #[must_use]
    pub fn empty() -> Self {
        Self {
            frames_processed: 0,
            callbacks: 0,
            callback_average_us: 0.0,
            callback_max_us: 0.0,
            callback_p95_us: 0.0,
            callback_p99_us: 0.0,
            percentile_kind: "histogram32us".to_owned(),
            peak_input_dbfs: uam_dsp::DBFS_FLOOR,
            peak_output_dbfs: uam_dsp::DBFS_FLOOR,
            limiter_reduction_db: 0.0,
            clipped_output_samples: 0,
            non_finite_output_samples: 0,
            glitches: 0,
            underruns: 0,
            deadline_misses: 0,
            stream_restarts: 0,
            device_disconnects: 0,
            backend_errors: 0,
            sample_rate_hz: 0,
            channels: 0,
            buffer_frames: 0,
            stream_latency_ms: 0.0,
            encoding_tag: 0,
            container_bits: 0,
            valid_bits: 0,
            error_code: 0,
        }
    }

    /// Estimated buffer duration in milliseconds, derived from the buffer size
    /// and sample rate. Returns 0 when unknown.
    #[must_use]
    pub fn buffer_duration_ms(&self) -> f64 {
        if self.sample_rate_hz == 0 {
            return 0.0;
        }
        f64::from(self.buffer_frames) / self.sample_rate_hz as f64 * 1_000.0
    }

    /// Processing load as a fraction of the buffer period, from the average
    /// callback time. Returns 0 when unknown.
    #[must_use]
    pub fn average_load(&self) -> f64 {
        let period_us = self.buffer_duration_ms() * 1_000.0;
        if period_us <= 0.0 {
            return 0.0;
        }
        self.callback_average_us / period_us
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percentile_tracks_a_uniform_histogram() {
        let metrics = Metrics::new();
        for _ in 0..100 {
            metrics.record_callback(Duration::from_micros(64));
        }
        let snapshot = metrics.snapshot();
        assert_eq!(snapshot.callbacks, 100);
        assert!((snapshot.callback_average_us - 64.0).abs() < 1.0);
        assert!((snapshot.callback_max_us - 64.0).abs() < 1.0);
        // 64 µs lands in bucket 2, upper bound 96 µs.
        assert!(snapshot.callback_p95_us >= 64.0);
        assert!(snapshot.callback_p95_us <= 96.0);
    }

    #[test]
    fn peaks_use_running_maximum() {
        use uam_dsp::linear_to_dbfs;
        let metrics = Metrics::new();
        metrics.observe_block(0.25, 0.5, 1.0, 0, 0);
        metrics.observe_block(0.1, 0.2, 0.5, 3, 1);
        let snapshot = metrics.snapshot();
        assert!((snapshot.peak_input_dbfs - linear_to_dbfs(0.25)).abs() < 1e-12);
        assert!((snapshot.peak_output_dbfs - linear_to_dbfs(0.5)).abs() < 1e-12);
        assert!((snapshot.limiter_reduction_db - 1.0).abs() < 1e-12);
        assert_eq!(snapshot.clipped_output_samples, 3);
        assert_eq!(snapshot.non_finite_output_samples, 1);
    }

    #[test]
    fn buffer_duration_and_load_are_derived() {
        let metrics = Metrics::new();
        let format =
            StreamFormat::new(48_000, 2, crate::config::SampleEncoding::F32, 32, 32).unwrap();
        metrics.set_format(&format, 480);
        for _ in 0..10 {
            metrics.record_callback(Duration::from_micros(48));
        }
        let snapshot = metrics.snapshot();
        assert!((snapshot.buffer_duration_ms() - 10.0).abs() < 1e-9);
        assert!((snapshot.average_load() - 0.0048).abs() < 1e-6);
    }
}
