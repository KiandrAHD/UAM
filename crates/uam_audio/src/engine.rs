//! Control-side audio engine.
//!
//! The engine is the single owner of a platform backend and of at most one
//! running render stream. It resolves endpoints, prepares DSP pipelines for the
//! active stream format, starts and stops the stream, applies bypass and test
//! tone requests, and recovers from an endpoint that disappears mid-stream.
//!
//! Everything here runs on the control thread. Nothing in this module is on the
//! audio callback path; the real-time work lives in [`crate::host`].
//!
//! # State ownership
//!
//! [`EngineState`] is always derived from what the engine actually did, never
//! from a UI toggle: a stream is only `Running` while the backend reports the
//! producer thread alive, and a stopped engine falls back to `Ready` or
//! `Stopped` depending on whether an endpoint is resolved.

use std::sync::atomic::Ordering;
use std::sync::mpsc::Receiver;

use serde::Serialize;
use uam_dsp::DspPipeline;

use crate::backend::{AudioBackend, DeviceSubscription, OpenRequest, RunningStream};
use crate::config::{AudioScope, DspRequest, EngineState, StreamFormat, TestToneConfig};
use crate::device::{DeviceEvent, DeviceListSnapshot};
use crate::error::{AudioError, AudioErrorCode};
use crate::host::StreamControl;
use crate::metrics::MetricsSnapshot;

/// Maximum recovery attempts before the engine gives up on a lost endpoint.
const MAX_RECOVERY_ATTEMPTS: u32 = 3;

/// A stream format summary exposed to the control path.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FormatSummary {
    /// Sample rate in hertz.
    pub sample_rate_hz: u32,
    /// Interleaved channels.
    pub channels: u16,
    /// Boundary encoding identifier.
    pub encoding: String,
    /// Container bits.
    pub container_bits: u16,
    /// Valid bits.
    pub valid_bits: u16,
    /// Human-readable single-line summary.
    pub summary: String,
}

impl From<StreamFormat> for FormatSummary {
    fn from(format: StreamFormat) -> Self {
        Self {
            sample_rate_hz: format.sample_rate_hz(),
            channels: format.channels(),
            encoding: format.encoding().as_str().to_owned(),
            container_bits: format.container_bits(),
            valid_bits: format.valid_bits(),
            summary: format.summary(),
        }
    }
}

/// A typed error as exposed to the control path.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ErrorDto {
    /// Stable error code.
    pub code: String,
    /// Safe human-readable message.
    pub message: String,
}

impl From<&AudioError> for ErrorDto {
    fn from(error: &AudioError) -> Self {
        Self {
            code: error.code.as_str().to_owned(),
            message: error.message.clone(),
        }
    }
}

/// A complete engine status snapshot.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EngineStatus {
    /// Lifecycle state.
    pub state: EngineState,
    /// Processing scope, derived from whether a stream is attached.
    pub scope: AudioScope,
    /// Backend identifier.
    pub backend: String,
    /// What the backend does and does not do.
    pub backend_description: String,
    /// Selected endpoint identifier, if any.
    pub device_id: Option<String>,
    /// Selected endpoint display name, if resolved.
    pub device_name: Option<String>,
    /// Selected endpoint stream format, if resolved.
    pub format: Option<FormatSummary>,
    /// Whether processing is bypassed.
    pub bypassed: bool,
    /// Whether the diagnostic tone is enabled.
    pub test_tone_enabled: bool,
    /// Runtime metrics.
    pub metrics: MetricsSnapshot,
    /// Last error, if any.
    pub last_error: Option<ErrorDto>,
}

/// Control-side audio engine.
pub struct AudioEngine {
    backend: Box<dyn AudioBackend>,
    device_id: Option<String>,
    device_name: Option<String>,
    format: Option<StreamFormat>,
    request: DspRequest,
    bypassed: bool,
    tone: Option<TestToneConfig>,
    pipeline: Option<Box<DspPipeline>>,
    control: Option<StreamControl>,
    retired_rx: Option<Receiver<Box<DspPipeline>>>,
    stream: Option<Box<dyn RunningStream>>,
    subscription: Option<Box<dyn DeviceSubscription>>,
    events: Option<Receiver<DeviceEvent>>,
    state: EngineState,
    last_error: Option<AudioError>,
    restarts: u64,
    disconnects: u64,
}

impl Default for AudioEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl AudioEngine {
    /// Create an engine with the platform backend and no selected endpoint.
    #[must_use]
    pub fn new() -> Self {
        Self {
            backend: crate::backend::create_backend(),
            device_id: None,
            device_name: None,
            format: None,
            request: DspRequest::neutral(),
            bypassed: false,
            tone: None,
            pipeline: None,
            control: None,
            retired_rx: None,
            stream: None,
            subscription: None,
            events: None,
            state: EngineState::Stopped,
            last_error: None,
            restarts: 0,
            disconnects: 0,
        }
    }

    /// Backend identifier.
    #[must_use]
    pub fn backend_name(&self) -> &'static str {
        self.backend.name()
    }

    /// What the backend does and does not do.
    #[must_use]
    pub fn backend_description(&self) -> String {
        self.backend.describe()
    }

    /// Enumerate active render endpoints.
    ///
    /// # Errors
    ///
    /// Returns a typed backend error when the OS API cannot be reached.
    pub fn devices(&self) -> Result<DeviceListSnapshot, AudioError> {
        self.backend.enumerate()
    }

    /// Subscribe to endpoint change notifications.
    ///
    /// # Errors
    ///
    /// Returns a typed backend error when the notification API cannot be
    /// reached. Calling this twice replaces the previous subscription.
    pub fn subscribe(&mut self) -> Result<(), AudioError> {
        let (subscription, events) = self.backend.subscribe()?;
        if let Some(mut previous) = self.subscription.take() {
            previous.unsubscribe();
        }
        self.subscription = Some(subscription);
        self.events = Some(events);
        Ok(())
    }

    /// Drain pending endpoint change notifications without blocking.
    ///
    /// Returns the events collected since the previous call.
    #[must_use]
    pub fn drain_device_events(&mut self) -> Vec<DeviceEvent> {
        let mut events = Vec::new();
        if let Some(receiver) = &self.events {
            while let Ok(event) = receiver.try_recv() {
                events.push(event);
            }
        }
        events
    }

    /// Select a render endpoint and resolve its stream format.
    ///
    /// The engine refuses endpoints that expose more than two channels: the DSP
    /// chain processes mono and stereo only, and the engine reports that
    /// limitation instead of down-mixing silently.
    ///
    /// # Errors
    ///
    /// Returns [`AudioErrorCode::InvalidEndpoint`] for an unknown identifier,
    /// [`AudioErrorCode::UnsupportedChannelCount`] for a multichannel endpoint,
    /// and any backend error raised while reading the format.
    pub fn select_device(&mut self, device_id: &str) -> Result<StreamFormat, AudioError> {
        let format = self.backend.query_format(device_id)?;
        if format.channels() > 2 {
            return Err(AudioError::new(
                AudioErrorCode::UnsupportedChannelCount,
                format!(
                    "endpoint {device_id} exposes {} channels; UAM processes mono or stereo only",
                    format.channels()
                ),
            ));
        }
        let pipeline = self.build_pipeline(format)?;
        self.device_id = Some(device_id.to_owned());
        self.device_name = self.resolve_name(device_id);
        self.format = Some(format);
        self.pipeline = Some(pipeline);
        self.last_error = None;
        if self.stream.is_none() {
            self.state = EngineState::Ready;
        }
        Ok(format)
    }

    /// Identifier of the current default render endpoint.
    ///
    /// # Errors
    ///
    /// Returns a typed backend error when the OS API cannot be reached.
    pub fn default_device_id(&self) -> Result<Option<String>, AudioError> {
        self.backend.default_device_id()
    }

    /// Apply a DSP configuration request.
    ///
    /// When an endpoint format is known, the configuration is validated against
    /// it, built into a new pipeline, and handed to the running stream (or held
    /// for the next start). When no endpoint is selected, the request is stored
    /// and validated later, at selection or start time.
    ///
    /// # Errors
    ///
    /// Returns [`AudioErrorCode::Configuration`] when a value is invalid or a
    /// band cannot be realised at the active sample rate.
    pub fn configure(&mut self, request: DspRequest) -> Result<(), AudioError> {
        if let Some(format) = self.format {
            let config = request.to_dsp_config(format.sample_rate_hz(), format.channels())?;
            let pipeline = Box::new(DspPipeline::from_config(&config)?);
            match &self.control {
                Some(control) => {
                    if !control.send_pipeline_waiting(pipeline) {
                        // The stream stopped concurrently; rebuild for the next
                        // start so the request is not lost.
                        let config =
                            request.to_dsp_config(format.sample_rate_hz(), format.channels())?;
                        self.pipeline = Some(Box::new(DspPipeline::from_config(&config)?));
                    }
                }
                None => self.pipeline = Some(pipeline),
            }
        }
        self.request = request;
        self.last_error = None;
        Ok(())
    }

    /// Request a bypass state change.
    pub fn set_bypass(&mut self, bypassed: bool) {
        self.bypassed = bypassed;
        if let Some(control) = &self.control {
            control.set_bypass(bypassed);
        }
    }

    /// Request a diagnostic test-tone change.
    ///
    /// # Errors
    ///
    /// Returns [`AudioErrorCode::Configuration`] for an out-of-range frequency
    /// or level.
    pub fn set_test_tone(&mut self, tone: Option<TestToneConfig>) -> Result<(), AudioError> {
        if let Some(tone) = tone {
            tone.validate()?;
        }
        self.tone = tone;
        if let Some(control) = &self.control {
            control.set_tone(tone);
        }
        Ok(())
    }

    /// Open and start the render stream on the selected endpoint.
    ///
    /// # Errors
    ///
    /// Returns [`AudioErrorCode::InvalidEndpoint`] when no endpoint is selected
    /// and any backend error raised while opening the stream.
    pub fn start(&mut self) -> Result<(), AudioError> {
        if self
            .stream
            .as_ref()
            .is_some_and(|stream| stream.is_running())
        {
            return Ok(());
        }
        let device_id = self.device_id.clone().ok_or_else(|| {
            AudioError::new(
                AudioErrorCode::InvalidEndpoint,
                "no output endpoint is selected",
            )
        })?;
        let format = self.format.ok_or_else(|| {
            AudioError::new(
                AudioErrorCode::InvalidEndpoint,
                "no stream format is resolved",
            )
        })?;
        let pipeline = match self.pipeline.take() {
            Some(pipeline) => pipeline,
            None => self.build_pipeline(format)?,
        };

        self.state = EngineState::Starting;
        let (control, channels, retired_rx) = StreamControl::new();
        control.set_bypass(self.bypassed);
        control.set_tone(self.tone);
        let request = OpenRequest {
            device_id,
            format,
            pipeline,
            control: control.clone(),
            channels,
        };
        match self.backend.open(request) {
            Ok(stream) => {
                self.retired_rx = Some(retired_rx);
                self.control = Some(control);
                self.stream = Some(stream);
                self.state = EngineState::Running;
                self.last_error = None;
                Ok(())
            }
            Err(error) => {
                self.state = EngineState::Failed;
                self.last_error = Some(error.clone());
                Err(error)
            }
        }
    }

    /// Stop the render stream, if one is running.
    pub fn stop(&mut self) {
        if let Some(stream) = self.stream.take() {
            stream.terminate();
        }
        self.control = None;
        self.retired_rx = None;
        self.state = if self.format.is_some() {
            EngineState::Ready
        } else {
            EngineState::Stopped
        };
    }

    /// Poll the engine: drop retired pipelines, detect a dead stream, and
    /// attempt recovery from a lost endpoint.
    ///
    /// This is the engine's periodic heartbeat; the control path calls it before
    /// reading status.
    pub fn poll(&mut self) {
        if let Some(receiver) = &self.retired_rx {
            while receiver.try_recv().is_ok() {
                // Retired pipelines are dropped here, off the audio thread.
            }
        }

        let died = self
            .stream
            .as_ref()
            .is_some_and(|stream| !stream.is_running());
        if !died {
            return;
        }

        let error_code = self
            .control
            .as_ref()
            .map(|control| control.metrics.snapshot().error_code)
            .unwrap_or(0);
        let code = AudioErrorCode::from_u64(error_code);

        if matches!(
            code,
            Some(AudioErrorCode::DeviceInvalidated) | Some(AudioErrorCode::DeviceRemoved)
        ) {
            self.disconnects += 1;
            self.recover();
        } else {
            self.state = EngineState::Failed;
            self.last_error = Some(AudioError::new(
                code.unwrap_or(AudioErrorCode::BackendError),
                "the render stream stopped unexpectedly",
            ));
        }
    }

    /// Build a status snapshot. Also drains retired pipelines and device events.
    pub fn status(&mut self) -> EngineStatus {
        self.poll();
        let mut metrics = self
            .control
            .as_ref()
            .map(|control| control.metrics.snapshot())
            .unwrap_or_else(MetricsSnapshot::empty);
        metrics.stream_restarts += self.restarts;
        metrics.device_disconnects += self.disconnects;
        if metrics.sample_rate_hz == 0 {
            if let Some(format) = self.format {
                metrics.sample_rate_hz = u64::from(format.sample_rate_hz());
                metrics.channels = u32::from(format.channels());
                metrics.encoding_tag = format.encoding().bytes_per_sample() as u16 * 8;
                metrics.container_bits = format.container_bits();
                metrics.valid_bits = format.valid_bits();
            }
        }
        let bypassed = self.control.as_ref().map_or(self.bypassed, |control| {
            control.bypass.load(Ordering::Relaxed)
        });
        let tone_enabled = self
            .control
            .as_ref()
            .map_or(self.tone.is_some(), |control| {
                control.tone_enabled.load(Ordering::Relaxed)
            });
        let attached = matches!(self.state, EngineState::Running);
        EngineStatus {
            state: self.state,
            scope: AudioScope::for_attachment(attached),
            backend: self.backend.name().to_owned(),
            backend_description: self.backend.describe(),
            device_id: self.device_id.clone(),
            device_name: self.device_name.clone(),
            format: self.format.map(FormatSummary::from),
            bypassed,
            test_tone_enabled: tone_enabled,
            metrics,
            last_error: self.last_error.as_ref().map(ErrorDto::from),
        }
    }

    /// Build a pipeline for a concrete stream format.
    fn build_pipeline(&self, format: StreamFormat) -> Result<Box<DspPipeline>, AudioError> {
        let config = self
            .request
            .to_dsp_config(format.sample_rate_hz(), format.channels())?;
        Ok(Box::new(DspPipeline::from_config(&config)?))
    }

    /// Resolve a display name for an endpoint by enumerating and matching ids.
    fn resolve_name(&self, device_id: &str) -> Option<String> {
        self.backend
            .enumerate()
            .ok()
            .and_then(|snapshot| {
                snapshot
                    .devices
                    .into_iter()
                    .find(|device| device.id == device_id)
            })
            .map(|device| device.display_name)
    }

    /// Attempt to recover a stream whose endpoint disappeared.
    fn recover(&mut self) {
        self.state = EngineState::Recovering;
        if let Some(stream) = self.stream.take() {
            stream.terminate();
        }
        self.control = None;
        self.retired_rx = None;

        if self.restarts >= u64::from(MAX_RECOVERY_ATTEMPTS) {
            self.state = EngineState::Failed;
            self.last_error = Some(AudioError::new(
                AudioErrorCode::DeviceRemoved,
                "the output endpoint was lost and recovery attempts were exhausted",
            ));
            return;
        }

        // Prefer the same endpoint; fall back to the current default.
        let mut resolved = self.device_id.clone().and_then(|id| {
            self.backend
                .query_format(&id)
                .ok()
                .map(|format| (id, format))
        });
        if resolved.is_none() {
            resolved = self
                .backend
                .default_device_id()
                .ok()
                .flatten()
                .and_then(|id| {
                    self.backend
                        .query_format(&id)
                        .ok()
                        .map(|format| (id, format))
                });
        }
        let Some((device_id, format)) = resolved else {
            self.state = EngineState::Failed;
            self.last_error = Some(AudioError::new(
                AudioErrorCode::NoOutputEndpoint,
                "no render endpoint is available for recovery",
            ));
            return;
        };

        self.device_id = Some(device_id.clone());
        self.device_name = self.resolve_name(&device_id);
        self.format = Some(format);
        self.pipeline = None;
        self.restarts += 1;
        if let Err(error) = self.start() {
            self.last_error = Some(error);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::{AudioBackend, DeviceSubscription, OpenRequest, RunningStream};
    use crate::config::{EqBandDto, EqFilterTypeDto, SampleEncoding};
    use crate::device::DeviceListSnapshot;
    use crate::metrics::Metrics;
    use std::sync::atomic::AtomicBool;
    use std::sync::mpsc::{channel, Receiver};
    use std::sync::{Arc, Mutex};

    const TEST_DEVICE: &str = "test-device";

    struct FakeShared {
        running: AtomicBool,
        channels: u16,
        query_fail: AtomicBool,
        open_fail: AtomicBool,
        opens: std::sync::atomic::AtomicU64,
        metrics: Mutex<Option<Arc<Metrics>>>,
    }

    impl FakeShared {
        fn new(channels: u16) -> Arc<Self> {
            Arc::new(Self {
                running: AtomicBool::new(false),
                channels,
                query_fail: AtomicBool::new(false),
                open_fail: AtomicBool::new(false),
                opens: std::sync::atomic::AtomicU64::new(0),
                metrics: Mutex::new(None),
            })
        }
    }

    struct FakeBackend {
        shared: Arc<FakeShared>,
    }

    struct FakeStream {
        shared: Arc<FakeShared>,
    }

    impl RunningStream for FakeStream {
        fn is_running(&self) -> bool {
            self.shared.running.load(Ordering::Relaxed)
        }

        fn terminate(self: Box<Self>) {
            self.shared.running.store(false, Ordering::Relaxed);
        }
    }

    struct FakeSubscription;

    impl DeviceSubscription for FakeSubscription {
        fn unsubscribe(&mut self) {}
    }

    impl AudioBackend for FakeBackend {
        fn name(&self) -> &'static str {
            "fake"
        }

        fn describe(&self) -> String {
            "fake backend for engine tests".to_owned()
        }

        fn enumerate(&self) -> Result<DeviceListSnapshot, AudioError> {
            let device = crate::device::OutputDevice {
                id: TEST_DEVICE.to_owned(),
                display_name: "Fake Output".to_owned(),
                platform_id: TEST_DEVICE.to_owned(),
                transport: crate::device::DeviceTransport::Unknown,
                connection_state: crate::device::DeviceState::Active,
                is_default: true,
                id_stability: crate::device::IdStability::SessionScoped,
                format_summary: None,
                format_provenance: crate::device::FormatProvenance::Unknown,
            };
            Ok(DeviceListSnapshot {
                devices: vec![device],
                default_id: Some(TEST_DEVICE.to_owned()),
                enumeration_succeeded: true,
                reason: None,
            })
        }

        fn query_format(&self, device_id: &str) -> Result<StreamFormat, AudioError> {
            if device_id != TEST_DEVICE || self.shared.query_fail.load(Ordering::Relaxed) {
                return Err(AudioError::new(
                    AudioErrorCode::InvalidEndpoint,
                    "unknown endpoint",
                ));
            }
            StreamFormat::new(48_000, self.shared.channels, SampleEncoding::F32, 32, 32)
        }

        fn default_device_id(&self) -> Result<Option<String>, AudioError> {
            if self.shared.query_fail.load(Ordering::Relaxed) {
                Ok(None)
            } else {
                Ok(Some(TEST_DEVICE.to_owned()))
            }
        }

        fn open(&self, request: OpenRequest) -> Result<Box<dyn RunningStream>, AudioError> {
            self.shared.opens.fetch_add(1, Ordering::Relaxed);
            if self.shared.open_fail.load(Ordering::Relaxed) {
                return Err(AudioError::new(AudioErrorCode::StreamStart, "open failed"));
            }
            *self.shared.metrics.lock().unwrap() = Some(request.control.metrics.clone());
            self.shared.running.store(true, Ordering::Relaxed);
            Ok(Box::new(FakeStream {
                shared: self.shared.clone(),
            }))
        }

        fn subscribe(
            &self,
        ) -> Result<(Box<dyn DeviceSubscription>, Receiver<DeviceEvent>), AudioError> {
            let (_tx, rx) = channel();
            Ok((Box::new(FakeSubscription), rx))
        }
    }

    fn engine_with(shared: Arc<FakeShared>) -> AudioEngine {
        let mut engine = AudioEngine::new();
        engine.backend = Box::new(FakeBackend { shared });
        engine
    }

    #[test]
    fn start_reaches_running_and_reports_app_owned_stream() {
        let shared = FakeShared::new(2);
        let mut engine = engine_with(shared.clone());
        engine.select_device(TEST_DEVICE).expect("select succeeds");
        engine.start().expect("start succeeds");
        let status = engine.status();
        assert_eq!(status.state, EngineState::Running);
        assert_eq!(status.scope, AudioScope::AppOwnedStream);
        assert_eq!(status.metrics.sample_rate_hz, 48_000);
        assert_eq!(status.metrics.channels, 2);
        assert_eq!(status.device_name.as_deref(), Some("Fake Output"));
        assert_eq!(shared.opens.load(Ordering::Relaxed), 1);
        engine.stop();
        assert_eq!(engine.status().state, EngineState::Ready);
    }

    #[test]
    fn select_rejects_multichannel_endpoint() {
        let shared = FakeShared::new(6);
        let mut engine = engine_with(shared);
        let error = engine.select_device(TEST_DEVICE).unwrap_err();
        assert_eq!(error.code, AudioErrorCode::UnsupportedChannelCount);
    }

    #[test]
    fn configure_before_selection_is_applied_at_start() {
        let shared = FakeShared::new(2);
        let mut engine = engine_with(shared);
        let request = DspRequest {
            preamp_db: -3.0,
            bands: vec![EqBandDto {
                filter_type: EqFilterTypeDto::HighShelf,
                frequency_hz: 6_000.0,
                gain_db: 4.0,
                q: 0.7,
            }],
            bypassed: false,
            limiter: None,
        };
        engine.configure(request).expect("configure is stored");
        engine.select_device(TEST_DEVICE).expect("select succeeds");
        engine.start().expect("start succeeds");
        assert_eq!(engine.status().state, EngineState::Running);
    }

    #[test]
    fn start_without_selection_fails_with_invalid_endpoint() {
        let shared = FakeShared::new(2);
        let mut engine = engine_with(shared);
        let error = engine.start().unwrap_err();
        assert_eq!(error.code, AudioErrorCode::InvalidEndpoint);
    }

    #[test]
    fn unexpected_stream_death_marks_failed() {
        let shared = FakeShared::new(2);
        let mut engine = engine_with(shared.clone());
        engine.select_device(TEST_DEVICE).expect("select succeeds");
        engine.start().expect("start succeeds");
        // The stream dies without a device-invalidation code.
        shared.running.store(false, Ordering::Relaxed);
        let status = engine.status();
        assert_eq!(status.state, EngineState::Failed);
    }

    #[test]
    fn device_invalidation_recovers_and_counts_a_restart() {
        let shared = FakeShared::new(2);
        let mut engine = engine_with(shared.clone());
        engine.select_device(TEST_DEVICE).expect("select succeeds");
        engine.start().expect("start succeeds");
        let metrics = shared.metrics.lock().unwrap().clone().unwrap();
        metrics.error_code.store(
            AudioErrorCode::DeviceInvalidated.as_u64(),
            Ordering::Relaxed,
        );
        shared.running.store(false, Ordering::Relaxed);
        let status = engine.status();
        assert_eq!(status.state, EngineState::Running);
        assert_eq!(status.metrics.stream_restarts, 1);
        assert_eq!(status.metrics.device_disconnects, 1);
        assert_eq!(shared.opens.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn recovery_exhaustion_marks_failed() {
        let shared = FakeShared::new(2);
        let mut engine = engine_with(shared.clone());
        engine.select_device(TEST_DEVICE).expect("select succeeds");
        engine.start().expect("start succeeds");
        // Every reopen fails and no endpoint can be resolved for recovery.
        shared.open_fail.store(true, Ordering::Relaxed);
        shared.query_fail.store(true, Ordering::Relaxed);
        let metrics = shared.metrics.lock().unwrap().clone().unwrap();
        metrics.error_code.store(
            AudioErrorCode::DeviceInvalidated.as_u64(),
            Ordering::Relaxed,
        );
        shared.running.store(false, Ordering::Relaxed);
        let status = engine.status();
        assert_eq!(status.state, EngineState::Failed);
        assert!(status.last_error.is_some());
    }

    #[test]
    fn tone_request_is_validated() {
        let shared = FakeShared::new(2);
        let mut engine = engine_with(shared);
        assert!(engine
            .set_test_tone(Some(TestToneConfig {
                frequency_hz: 1_000.0,
                level_db: -20.0,
            }))
            .is_ok());
        let error = engine
            .set_test_tone(Some(TestToneConfig {
                frequency_hz: 1.0,
                level_db: -20.0,
            }))
            .unwrap_err();
        assert_eq!(error.code, AudioErrorCode::Configuration);
    }
}
