//! Shared-mode, event-driven WASAPI render stream.
//!
//! # Lifecycle
//!
//! 1. The control thread activates the endpoint's `IAudioClient`, reads its mix
//!    format, and initializes a shared-mode event-driven stream.
//! 2. It reads the device buffer size, the API-reported latency, and attaches an
//!    auto-reset event handle that WASAPI signals when a new buffer is due.
//! 3. It builds the [`DspHost`] on the control thread (allocation happens here)
//!    and moves it, with the audio client, onto a dedicated producer thread.
//! 4. The producer thread waits on `{audio_event, stop_event}`, renders the
//!    available frames into the device buffer, and releases it. It never locks,
//!    allocates, or formats on that path.
//! 5. A stop request sets `stop_event`; the thread drains, stops the client, and
//!    exits, releasing every handle.
//!
//! # Failure handling
//!
//! A device invalidation (`AUDCLNT_E_DEVICE_INVALIDATED`) is recorded as a
//! disconnect and ends the producer thread. The control-side engine observes the
//! dead thread and attempts recovery; this module never silently restarts a
//! stream on its own.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::Instant;

use windows::Win32::Foundation::{CloseHandle, HANDLE, WAIT_EVENT, WAIT_OBJECT_0, WAIT_TIMEOUT};
use windows::Win32::Media::Audio::{
    IAudioClient, IAudioRenderClient, IMMDeviceEnumerator, AUDCLNT_E_DEVICE_INVALIDATED,
    AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK, WAVEFORMATEX,
};
use windows::Win32::System::Com::{CoTaskMemFree, CLSCTX_ALL};
use windows::Win32::System::Threading::{CreateEventW, SetEvent, WaitForMultipleObjects};

use super::com::ComApartment;
use super::device::{get_device, stream_format_from_mix};
use crate::backend::{OpenRequest, RunningStream};
use crate::config::StreamFormat;
use crate::error::{AudioError, AudioErrorCode};
use crate::format::encode;
use crate::host::DspHost;
use crate::metrics::Metrics;

/// Longest wait for a buffer before the producer re-checks its stop flag, in
/// milliseconds. This is a safety net, not the normal cadence.
const MAX_WAIT_MS: u32 = 200;

/// Reason the producer loop should end.
enum LoopExit {
    /// A stop was requested.
    Stopped,
    /// WASAPI signalled a device invalidation.
    Invalidated,
    /// Another backend failure occurred.
    Failed(AudioErrorCode),
}

/// Shared control state between the engine and the producer thread.
struct StreamShared {
    running: AtomicBool,
    /// `stop_event` HANDLE stored as an integer; HANDLE is `!Send`.
    stop_handle: usize,
}

/// Everything the producer thread owns.
struct ProducerResources {
    client: IAudioClient,
    render_client: IAudioRenderClient,
    audio_event: HANDLE,
    stop_event: HANDLE,
    host: DspHost,
    format: StreamFormat,
    buffer_frames: u32,
    metrics: Arc<Metrics>,
    shared: Arc<StreamShared>,
}

// SAFETY: WASAPI `IAudioClient` and `IAudioRenderClient` are agile, free-threaded
// interfaces; the docs permit calling them from any thread. The host and metrics
// are plain `Send` data. The two HANDLEs are kernel objects safe to use from a
// different thread.
unsafe impl Send for ProducerResources {}

impl ProducerResources {
    fn run(mut self) {
        let _apartment = ComApartment::initialize();
        // SAFETY: the client is live and this is the producer thread.
        if let Err(error) = unsafe { self.client.Start() } {
            self.record_failure(AudioErrorCode::StreamStart);
            let _ = error;
            return;
        }

        let exit = loop {
            if !self.shared.running.load(Ordering::Relaxed) {
                break LoopExit::Stopped;
            }
            // SAFETY: both handles are valid auto/manual-reset events owned by
            // this thread or shared with the controller.
            let wait = unsafe {
                WaitForMultipleObjects(&[self.audio_event, self.stop_event], false, MAX_WAIT_MS)
            };
            if wait == WAIT_OBJECT_0 {
                match self.render_one() {
                    Ok(()) => {}
                    Err(LoopExit::Invalidated) => break LoopExit::Invalidated,
                    Err(LoopExit::Failed(code)) => break LoopExit::Failed(code),
                    Err(LoopExit::Stopped) => break LoopExit::Stopped,
                }
            } else if wait == WAIT_EVENT(WAIT_OBJECT_0.0 + 1) {
                break LoopExit::Stopped;
            } else if wait == WAIT_TIMEOUT {
                self.metrics.deadline_misses.fetch_add(1, Ordering::Relaxed);
            } else {
                break LoopExit::Failed(AudioErrorCode::BackendError);
            }
        };

        match exit {
            LoopExit::Stopped => {}
            LoopExit::Invalidated => self.record_failure(AudioErrorCode::DeviceInvalidated),
            LoopExit::Failed(code) => self.record_failure(code),
        }
        // SAFETY: the client is live.
        unsafe {
            let _ = self.client.Stop();
        }
        self.shared.running.store(false, Ordering::Relaxed);
    }

    /// Render one available buffer.
    fn render_one(&mut self) -> Result<(), LoopExit> {
        let started = Instant::now();
        // SAFETY: the client is live and the stream is running.
        let padding = unsafe { self.client.GetCurrentPadding() }
            .map_err(|error| classify(&error, AudioErrorCode::BufferAcquisition))?;
        let available = self.buffer_frames.saturating_sub(padding);
        if available == 0 {
            self.metrics.underruns.fetch_add(1, Ordering::Relaxed);
            return Ok(());
        }

        // SAFETY: `available` frames fit inside the device buffer.
        let buffer_ptr = unsafe { self.render_client.GetBuffer(available) }
            .map_err(|error| classify(&error, AudioErrorCode::BufferAcquisition))?;
        if buffer_ptr.is_null() {
            return Err(LoopExit::Failed(AudioErrorCode::BufferAcquisition));
        }

        let frames = available as usize;
        let samples = self.host.render(frames);
        let bytes = self.format.buffer_bytes(frames);
        // SAFETY: WASAPI guarantees `bytes` writable bytes for `available`
        // frames at the mix format.
        let destination = unsafe { std::slice::from_raw_parts_mut(buffer_ptr, bytes) };
        let report = encode(&self.format, samples, frames, destination);
        self.metrics
            .observe_boundary(report.clamped_samples, report.non_finite_samples);

        // SAFETY: the buffer was written for exactly `available` frames.
        unsafe { self.render_client.ReleaseBuffer(available, 0) }
            .map_err(|error| classify(&error, AudioErrorCode::BufferRelease))?;
        self.metrics.record_callback(started.elapsed());
        Ok(())
    }

    /// Record a fatal producer failure in the shared metrics.
    fn record_failure(&self, code: AudioErrorCode) {
        self.metrics
            .error_code
            .store(code.as_u64(), Ordering::Relaxed);
        match code {
            AudioErrorCode::DeviceInvalidated | AudioErrorCode::DeviceRemoved => {
                self.metrics
                    .device_disconnects
                    .fetch_add(1, Ordering::Relaxed);
            }
            _ => {
                self.metrics.backend_errors.fetch_add(1, Ordering::Relaxed);
            }
        }
        self.shared.running.store(false, Ordering::Relaxed);
    }
}

/// Classify a WASAPI failure, promoting device invalidation.
fn classify(error: &windows::core::Error, fallback: AudioErrorCode) -> LoopExit {
    if error.code() == AUDCLNT_E_DEVICE_INVALIDATED {
        LoopExit::Invalidated
    } else {
        LoopExit::Failed(fallback)
    }
}

/// The control-side handle to a running WASAPI stream.
pub struct RenderStream {
    shared: Arc<StreamShared>,
    thread: Option<JoinHandle<()>>,
    audio_event: usize,
    stop_event: usize,
}

impl RenderStream {
    /// Signal the producer to stop without waiting.
    fn signal_stop(&self) {
        self.shared.running.store(false, Ordering::Relaxed);
        let handle = HANDLE(self.shared.stop_handle as *mut core::ffi::c_void);
        // SAFETY: the handle is a live manual-reset event owned by this stream
        // and is only closed in `Drop`, after the producer thread has joined.
        unsafe {
            let _ = SetEvent(handle);
        }
    }
}

impl RunningStream for RenderStream {
    fn is_running(&self) -> bool {
        self.shared.running.load(Ordering::Relaxed)
    }

    fn terminate(mut self: Box<Self>) {
        self.signal_stop();
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
        self.close_handles();
    }
}

impl RenderStream {
    /// Close the two event handles. Idempotent for this owner.
    fn close_handles(&mut self) {
        if self.audio_event != 0 {
            // SAFETY: the producer thread has joined and no longer uses it.
            unsafe {
                let _ = CloseHandle(HANDLE(self.audio_event as *mut core::ffi::c_void));
            }
            self.audio_event = 0;
        }
        if self.stop_event != 0 {
            // SAFETY: the producer thread has joined and no longer uses it.
            unsafe {
                let _ = CloseHandle(HANDLE(self.stop_event as *mut core::ffi::c_void));
            }
            self.stop_event = 0;
        }
    }
}

impl Drop for RenderStream {
    fn drop(&mut self) {
        self.signal_stop();
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
        self.close_handles();
    }
}

/// Open and start a shared-mode render stream on the requested endpoint.
///
/// # Errors
///
/// Returns a typed error when the endpoint cannot be resolved, the audio client
/// cannot be initialized, the stream format does not match the prepared
/// pipeline, or the producer thread cannot be spawned.
pub fn open(
    enumerator: &IMMDeviceEnumerator,
    request: OpenRequest,
) -> Result<RenderStream, AudioError> {
    let OpenRequest {
        device_id,
        format,
        pipeline,
        control,
        channels,
    } = request;

    let device = get_device(enumerator, &device_id)?;

    // SAFETY: the device is live and COM is initialized by the caller. The mix
    // format pointer is freed after `Initialize` consumes it.
    let (client, render_client, buffer_frames, latency_100ns, audio_event) = unsafe {
        let client: IAudioClient = device.Activate(CLSCTX_ALL, None).map_err(|error| {
            AudioError::new(
                AudioErrorCode::AudioClientInit,
                format!("IAudioClient activation failed: {error:?}"),
            )
        })?;
        let mix: *mut WAVEFORMATEX = client.GetMixFormat().map_err(|error| {
            AudioError::new(
                AudioErrorCode::AudioClientInit,
                format!("GetMixFormat failed: {error:?}"),
            )
        })?;

        let mix_format = stream_format_from_mix(mix);
        let mix_format = match mix_format {
            Ok(parsed) => parsed,
            Err(error) => {
                CoTaskMemFree(Some(mix.cast()));
                return Err(error);
            }
        };
        if mix_format != format {
            CoTaskMemFree(Some(mix.cast()));
            return Err(AudioError::new(
                AudioErrorCode::UnsupportedFormat,
                format!(
                    "endpoint format changed: prepared for {}, endpoint reports {}",
                    format.summary(),
                    mix_format.summary()
                ),
            ));
        }

        let mut default_period = 0_i64;
        let mut minimum_period = 0_i64;
        let _ = client.GetDevicePeriod(Some(&mut default_period), Some(&mut minimum_period));
        if default_period <= 0 {
            default_period = 100_000; // 10 ms fallback, in 100 ns units.
        }

        let audio_event =
            CreateEventW(None, false, false, windows::core::PCWSTR::null()).map_err(|error| {
                CoTaskMemFree(Some(mix.cast()));
                AudioError::new(
                    AudioErrorCode::AudioClientInit,
                    format!("CreateEventW failed for the render event: {error:?}"),
                )
            })?;

        let initialize = client.Initialize(
            AUDCLNT_SHAREMODE_SHARED,
            AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
            default_period,
            0,
            mix,
            None,
        );
        CoTaskMemFree(Some(mix.cast()));
        initialize.map_err(|error| {
            let _ = CloseHandle(audio_event);
            AudioError::new(
                AudioErrorCode::AudioClientInit,
                format!("IAudioClient::Initialize failed: {error:?}"),
            )
        })?;

        let buffer_frames = client.GetBufferSize().map_err(|error| {
            let _ = CloseHandle(audio_event);
            AudioError::new(
                AudioErrorCode::AudioClientInit,
                format!("GetBufferSize failed: {error:?}"),
            )
        })?;
        let latency_100ns = client.GetStreamLatency().unwrap_or(0);
        if let Err(error) = client.SetEventHandle(audio_event) {
            let _ = CloseHandle(audio_event);
            return Err(AudioError::new(
                AudioErrorCode::AudioClientInit,
                format!("SetEventHandle failed: {error:?}"),
            ));
        }
        let render_client: IAudioRenderClient = client.GetService().map_err(|error| {
            let _ = CloseHandle(audio_event);
            AudioError::new(
                AudioErrorCode::AudioClientInit,
                format!("IAudioRenderClient activation failed: {error:?}"),
            )
        })?;
        (
            client,
            render_client,
            buffer_frames,
            latency_100ns,
            audio_event,
        )
    };

    let metrics = control.metrics.clone();
    metrics.set_format(&format, buffer_frames);
    metrics.set_stream_latency_100ns(latency_100ns.max(0) as u64);

    let max_frames = buffer_frames.max(1) as usize;
    let host = DspHost::new(
        format.channels(),
        format.sample_rate_hz(),
        max_frames,
        pipeline,
        control,
        channels,
    );

    // SAFETY: a manual-reset event used only to wake the producer.
    let stop_event = unsafe { CreateEventW(None, true, false, windows::core::PCWSTR::null()) }
        .map_err(|error| {
            // SAFETY: `audio_event` is still owned here.
            unsafe {
                let _ = CloseHandle(audio_event);
            }
            AudioError::new(
                AudioErrorCode::AudioClientInit,
                format!("CreateEventW failed for the stop event: {error:?}"),
            )
        })?;

    let shared = Arc::new(StreamShared {
        running: AtomicBool::new(true),
        stop_handle: stop_event.0 as usize,
    });

    let resources = ProducerResources {
        client,
        render_client,
        audio_event,
        stop_event,
        host,
        format,
        buffer_frames,
        metrics,
        shared: shared.clone(),
    };

    let thread = match std::thread::Builder::new()
        .name("uam-wasapi-render".to_owned())
        .spawn(move || resources.run())
    {
        Ok(thread) => thread,
        Err(error) => {
            shared.running.store(false, Ordering::Relaxed);
            // SAFETY: neither handle was handed to the producer.
            unsafe {
                let _ = CloseHandle(audio_event);
                let _ = CloseHandle(stop_event);
            }
            return Err(AudioError::new(
                AudioErrorCode::Internal,
                format!("failed to spawn the render thread: {error}"),
            ));
        }
    };

    Ok(RenderStream {
        shared,
        thread: Some(thread),
        audio_event: audio_event.0 as usize,
        stop_event: stop_event.0 as usize,
    })
}
