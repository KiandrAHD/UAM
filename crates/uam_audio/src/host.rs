//! Real-time DSP host: the piece that runs inside the audio callback.
//!
//! The host owns the active [`uam_dsp::DspPipeline`], the diagnostic test tone,
//! scratch buffers, and the click-free transition state. It is created on the
//! control thread (where all allocation happens) and then moved onto the audio
//! thread, which only ever calls [`DspHost::render`].
//!
//! # Real-time safety
//!
//! `render` performs no allocation, no locking, no I/O, and no logging:
//!
//! - A replacement pipeline arrives through a bounded channel; the host swaps
//!   pointers and sends the *retired* pipeline back to the control thread
//!   through a second bounded channel so it is dropped off the audio thread.
//! - Bypass and test-tone state are plain atomics.
//! - Every scratch buffer is preallocated to the device buffer size at
//!   construction.
//!
//! # Click-free transitions
//!
//! - A new DSP configuration crossfades over a short window instead of
//!   replacing filter memory instantly.
//! - Bypass is a smoothed mix between the dry input and the processed signal,
//!   so toggling it never steps discontinuously and the stream keeps running.

use core::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{Receiver, SyncSender, TrySendError};
use std::sync::Arc;

use uam_dsp::DspPipeline;

use crate::config::{TestToneConfig, DEFAULT_TONE_FREQUENCY_HZ};
use crate::metrics::Metrics;
use crate::tone::ToneOscillator;

/// Crossfade window for a configuration change, in seconds.
const CONFIG_FADE_SECONDS: f64 = 0.010;
/// Smoothing time constant for the bypass mix, in seconds.
const BYPASS_SMOOTH_SECONDS: f64 = 0.005;
/// Smallest crossfade window in frames.
const MIN_FADE_FRAMES: usize = 16;
/// Capacity of the retired-pipeline return channel.
const RETIRED_CAPACITY: usize = 4;

/// Control-side handle to one running stream.
///
/// Cloned into the engine; the audio thread receives the matching receivers.
#[derive(Clone)]
pub struct StreamControl {
    /// Shared metrics.
    pub metrics: Arc<Metrics>,
    /// Requested bypass state (`true` = processing disabled).
    pub bypass: Arc<AtomicBool>,
    /// Whether the diagnostic tone is requested.
    pub tone_enabled: Arc<AtomicBool>,
    /// Requested tone frequency, as `f64` bits.
    pub tone_frequency_bits: Arc<AtomicU64>,
    /// Requested tone level in dBFS, as `f64` bits.
    pub tone_level_bits: Arc<AtomicU64>,
    config_tx: SyncSender<Box<DspPipeline>>,
}

/// Audio-thread half of the control channel.
pub struct HostChannels {
    /// Replacement pipelines from the control thread.
    pub config_rx: Receiver<Box<DspPipeline>>,
    /// Retired pipelines to be dropped by the control thread.
    pub retired_tx: SyncSender<Box<DspPipeline>>,
}

impl StreamControl {
    /// Create the shared control block plus both halves of the hand-off.
    ///
    /// The engine keeps the returned `retired_rx` and drains it on every poll
    /// so replaced pipelines are dropped off the audio thread.
    #[must_use]
    pub fn new() -> (Self, HostChannels, Receiver<Box<DspPipeline>>) {
        let (config_tx, config_rx) = std::sync::mpsc::sync_channel(1);
        let (retired_tx, retired_rx) = std::sync::mpsc::sync_channel(RETIRED_CAPACITY);
        let control = Self {
            metrics: Arc::new(Metrics::new()),
            bypass: Arc::new(AtomicBool::new(false)),
            tone_enabled: Arc::new(AtomicBool::new(false)),
            tone_frequency_bits: Arc::new(AtomicU64::new(
                TestToneConfig::default().frequency_hz.to_bits(),
            )),
            tone_level_bits: Arc::new(AtomicU64::new(TestToneConfig::default().level_db.to_bits())),
            config_tx,
        };
        let channels = HostChannels {
            config_rx,
            retired_tx,
        };
        (control, channels, retired_rx)
    }

    /// Request a bypass state change. The audio thread smooths the transition.
    pub fn set_bypass(&self, bypassed: bool) {
        self.bypass.store(bypassed, Ordering::Relaxed);
    }

    /// Request a test-tone change. `None` fades the tone out.
    pub fn set_tone(&self, tone: Option<TestToneConfig>) {
        match tone {
            Some(tone) => {
                self.tone_frequency_bits
                    .store(tone.frequency_hz.to_bits(), Ordering::Relaxed);
                self.tone_level_bits
                    .store(tone.level_db.to_bits(), Ordering::Relaxed);
                self.tone_enabled.store(true, Ordering::Relaxed);
            }
            None => self.tone_enabled.store(false, Ordering::Relaxed),
        }
    }

    /// Hand a prepared pipeline to the audio thread.
    ///
    /// Returns `false` when the stream is not draining configurations (it was
    /// stopped), in which case the caller keeps the pipeline.
    pub fn try_send_pipeline(&self, pipeline: Box<DspPipeline>) -> bool {
        self.config_tx.try_send(pipeline).is_ok()
    }

    /// Hand a prepared pipeline to the audio thread, waiting briefly for the
    /// queue to drain if the audio thread is holding the previous one.
    ///
    /// Bounded: the audio thread drains every callback, so this returns within
    /// one buffer period. Returns `false` if the stream is gone.
    pub fn send_pipeline_waiting(&self, mut pipeline: Box<DspPipeline>) -> bool {
        for _ in 0..64 {
            match self.config_tx.try_send(pipeline) {
                Ok(()) => return true,
                Err(TrySendError::Full(returned)) => {
                    pipeline = returned;
                    std::thread::sleep(std::time::Duration::from_millis(2));
                }
                Err(TrySendError::Disconnected(_)) => return false,
            }
        }
        false
    }
}

/// In-flight crossfade between the previous and current pipelines.
struct CrossFade {
    pipeline: Box<DspPipeline>,
    position: usize,
    length: usize,
}

/// The audio-thread DSP host.
pub struct DspHost {
    channels: usize,
    sample_rate_hz: u32,
    max_frames: usize,
    pipeline: Box<DspPipeline>,
    config_rx: Receiver<Box<DspPipeline>>,
    retired_tx: SyncSender<Box<DspPipeline>>,
    fade: Option<CrossFade>,
    fade_length: usize,
    bypass_mix: f64,
    bypass_coefficient: f64,
    tone: ToneOscillator,
    metrics: Arc<Metrics>,
    bypass_requested: Arc<AtomicBool>,
    tone_enabled: Arc<AtomicBool>,
    tone_frequency_bits: Arc<AtomicU64>,
    tone_level_bits: Arc<AtomicU64>,
    scratch_main: Vec<f64>,
    scratch_fade: Vec<f64>,
    scratch_dry: Vec<f64>,
    output: Vec<f64>,
}

impl DspHost {
    /// Build a host for a validated audio configuration and initial pipeline.
    ///
    /// `max_frames` must be at least the device buffer size; every buffer is
    /// allocated here, on the control thread.
    #[must_use]
    pub fn new(
        channel_count: u16,
        sample_rate_hz: u32,
        max_frames: usize,
        pipeline: Box<DspPipeline>,
        control: StreamControl,
        channels: HostChannels,
    ) -> Self {
        let channel_count = usize::from(channel_count);
        let capacity = max_frames.max(1) * channel_count;
        let max_frames = max_frames.max(1);
        let fade_length = ((CONFIG_FADE_SECONDS * f64::from(sample_rate_hz)) as usize)
            .clamp(MIN_FADE_FRAMES, max_frames);
        let bypass_coefficient =
            (-1.0 / (BYPASS_SMOOTH_SECONDS * f64::from(sample_rate_hz)).max(1.0)).exp();
        Self {
            channels: channel_count,
            sample_rate_hz,
            max_frames,
            pipeline,
            config_rx: channels.config_rx,
            retired_tx: channels.retired_tx,
            fade: None,
            fade_length,
            bypass_mix: 1.0,
            bypass_coefficient,
            tone: ToneOscillator::new(),
            metrics: control.metrics,
            bypass_requested: control.bypass,
            tone_enabled: control.tone_enabled,
            tone_frequency_bits: control.tone_frequency_bits,
            tone_level_bits: control.tone_level_bits,
            scratch_main: vec![0.0; capacity],
            scratch_fade: vec![0.0; capacity],
            scratch_dry: vec![0.0; capacity],
            output: vec![0.0; capacity],
        }
    }

    /// Maximum frames the host can render in one call.
    #[must_use]
    pub const fn max_frames(&self) -> usize {
        self.max_frames
    }

    /// Interleaved channel count.
    #[must_use]
    pub const fn channels(&self) -> usize {
        self.channels
    }

    /// Render `frames` interleaved frames and return the output slice.
    ///
    /// # Panics
    ///
    /// Panics when `frames` exceeds the preallocated capacity, which the backend
    /// validates against the device buffer size before calling.
    pub fn render(&mut self, frames: usize) -> &[f64] {
        assert!(frames <= self.max_frames, "render block exceeds capacity");
        let samples = frames * self.channels;
        if samples == 0 {
            return &self.output[..0];
        }

        self.apply_config_changes();

        // Source: diagnostic tone, or silence.
        let tone_enabled = self.tone_enabled.load(Ordering::Relaxed);
        let (frequency_hz, amplitude) = if tone_enabled {
            let frequency_hz = f64::from_bits(self.tone_frequency_bits.load(Ordering::Relaxed));
            let level_db = f64::from_bits(self.tone_level_bits.load(Ordering::Relaxed));
            (
                frequency_hz,
                TestToneConfig {
                    frequency_hz,
                    level_db,
                }
                .amplitude(),
            )
        } else {
            (DEFAULT_TONE_FREQUENCY_HZ, 0.0)
        };
        let input_peak = self.tone.render(
            self.sample_rate_hz,
            self.channels,
            frames,
            frequency_hz,
            amplitude,
            &mut self.scratch_main,
        );

        let bypass_requested = self.bypass_requested.load(Ordering::Relaxed);
        let bypass_target = if bypass_requested { 0.0 } else { 1.0 };
        let needs_dry = self.bypass_mix < 1.0 || bypass_target < 1.0;
        if needs_dry {
            self.scratch_dry[..samples].copy_from_slice(&self.scratch_main[..samples]);
        }

        let report = self.process_pipeline(frames, samples);

        // Blend dry and processed according to the smoothed bypass mix.
        let mut output_peak = 0.0_f64;
        for frame in 0..frames {
            self.bypass_mix =
                bypass_target + (self.bypass_mix - bypass_target) * self.bypass_coefficient;
            for channel in 0..self.channels {
                let index = frame * self.channels + channel;
                let processed = self.output[index];
                let value = if needs_dry {
                    let dry = self.scratch_dry[index];
                    dry + self.bypass_mix * (processed - dry)
                } else {
                    processed
                };
                let value = if value.is_finite() { value } else { 0.0 };
                self.output[index] = value;
                let magnitude = value.abs();
                if magnitude > output_peak {
                    output_peak = magnitude;
                }
            }
        }

        self.metrics
            .frames_processed
            .fetch_add(u64::try_from(frames).unwrap_or(u64::MAX), Ordering::Relaxed);
        self.metrics.observe_block(
            input_peak,
            output_peak,
            report.gain_reduction_db,
            report.clipped,
            report.non_finite,
        );

        &self.output[..samples]
    }

    /// Drain configuration updates and run the pipeline into `self.output`.
    fn process_pipeline(&mut self, _frames: usize, samples: usize) -> BlockOutcome {
        if let Some(mut fade) = self.fade.take() {
            self.scratch_fade[..samples].copy_from_slice(&self.scratch_main[..samples]);
            let outcome = run_pipeline(&mut self.pipeline, &mut self.scratch_main[..samples]);
            let _ = fade
                .pipeline
                .process_interleaved(&mut self.scratch_fade[..samples]);
            let length = fade.length.max(1);
            let mut position = fade.position;
            for index in 0..samples {
                let t = (position / length).min(1) as f64;
                let active = self.scratch_main[index];
                let previous = self.scratch_fade[index];
                self.output[index] = previous + t * (active - previous);
                if index % self.channels == 0 {
                    position += 1;
                }
            }
            fade.position = position;
            if fade.position >= length {
                self.retire(fade.pipeline);
            } else {
                self.fade = Some(fade);
            }
            outcome
        } else {
            let outcome = run_pipeline(&mut self.pipeline, &mut self.scratch_main[..samples]);
            self.output[..samples].copy_from_slice(&self.scratch_main[..samples]);
            outcome
        }
    }

    /// Consume queued pipeline replacements, archiving the old ones safely.
    fn apply_config_changes(&mut self) {
        let mut newest: Option<Box<DspPipeline>> = None;
        while let Ok(incoming) = self.config_rx.try_recv() {
            if let Some(previous) = newest.replace(incoming) {
                self.retire(previous);
            }
        }
        let Some(incoming) = newest else {
            return;
        };
        if let Some(fade) = self.fade.take() {
            self.retire(fade.pipeline);
        }
        let previous = core::mem::replace(&mut self.pipeline, incoming);
        self.fade = Some(CrossFade {
            pipeline: previous,
            position: 0,
            length: self.fade_length.max(1),
        });
    }

    /// Hand a retired pipeline back to the control thread for disposal.
    fn retire(&self, pipeline: Box<DspPipeline>) {
        if let Err(TrySendError::Full(pipeline)) = self.retired_tx.try_send(pipeline) {
            // The control thread has not drained yet. Dropping here is the only
            // available option and is extremely rare.
            drop(pipeline);
        }
    }
}

/// Outcome of one block, used to update metrics.
struct BlockOutcome {
    gain_reduction_db: f64,
    clipped: u64,
    non_finite: u64,
}

/// Run one pipeline over a block, returning a safe outcome on the impossible
/// error path (a whole-frame block can never be rejected).
fn run_pipeline(pipeline: &mut DspPipeline, block: &mut [f64]) -> BlockOutcome {
    match pipeline.process_interleaved(block) {
        Ok(report) => BlockOutcome {
            gain_reduction_db: report.gain_reduction_db(),
            clipped: report.output().clipped_samples(),
            non_finite: report.output().non_finite_samples(),
        },
        Err(_) => BlockOutcome {
            gain_reduction_db: 0.0,
            clipped: 0,
            non_finite: 0,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{DspRequest, EqBandDto, EqFilterTypeDto};
    use uam_dsp::DspPipeline;

    fn pipeline(preamp_db: f64, gain_db: f64) -> Box<DspPipeline> {
        let request = DspRequest {
            preamp_db,
            bands: if gain_db == 0.0 {
                Vec::new()
            } else {
                vec![EqBandDto {
                    filter_type: EqFilterTypeDto::Peaking,
                    frequency_hz: 1_000.0,
                    gain_db,
                    q: 1.0,
                }]
            },
            bypassed: false,
            limiter: None,
        };
        let config = request.to_dsp_config(48_000, 2).expect("valid config");
        Box::new(DspPipeline::from_config(&config).expect("valid pipeline"))
    }

    struct Rig {
        host: DspHost,
        control: StreamControl,
        retired: Receiver<Box<DspPipeline>>,
    }

    fn rig(max_frames: usize) -> Rig {
        let (control, channels, retired) = StreamControl::new();
        let host = DspHost::new(
            2,
            48_000,
            max_frames,
            pipeline(0.0, 0.0),
            control.clone(),
            channels,
        );
        Rig {
            host,
            control,
            retired,
        }
    }

    #[test]
    fn silence_when_tone_is_off() {
        let mut rig = rig(256);
        let output = rig.host.render(128);
        assert!(output.iter().all(|sample| *sample == 0.0));
    }

    #[test]
    fn tone_is_generated_when_enabled() {
        let mut rig = rig(256);
        rig.control.tone_enabled.store(true, Ordering::Relaxed);
        let mut peak = 0.0_f64;
        for _ in 0..32 {
            let output = rig.host.render(256);
            for sample in output {
                peak = peak.max(sample.abs());
            }
        }
        assert!(peak > 0.01, "expected audible tone, got peak {peak}");
    }

    #[test]
    fn bypass_returns_the_dry_signal() {
        let mut rig = rig(256);
        rig.control.tone_enabled.store(true, Ordering::Relaxed);
        rig.control.bypass.store(true, Ordering::Relaxed);
        for _ in 0..64 {
            rig.host.render(256);
        }
        let output = rig.host.render(256).to_vec();
        let snapshot = rig.control.metrics.snapshot();
        assert!(snapshot.peak_output_dbfs <= snapshot.peak_input_dbfs + 1e-9);
        assert!(output.iter().all(|sample| sample.is_finite()));
    }

    #[test]
    fn config_swap_is_applied_and_retires_the_old() {
        let mut rig = rig(256);
        rig.control.tone_enabled.store(true, Ordering::Relaxed);
        for _ in 0..8 {
            rig.host.render(256);
        }
        assert!(rig.control.try_send_pipeline(pipeline(6.0, 12.0)));
        rig.host.render(256);
        assert!(rig.retired.try_recv().is_ok());
    }

    #[test]
    fn non_finite_never_escapes_the_host() {
        let mut rig = rig(256);
        rig.control.tone_enabled.store(true, Ordering::Relaxed);
        for _ in 0..8 {
            let output = rig.host.render(256);
            assert!(output.iter().all(|sample| sample.is_finite()));
        }
    }

    #[test]
    fn buffer_size_validation_rejects_oversized_requests() {
        let mut rig = rig(64);
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            rig.host.render(128);
        }));
        assert!(result.is_err());
    }
}
