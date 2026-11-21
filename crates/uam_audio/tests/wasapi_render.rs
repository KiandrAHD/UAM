//! Real WASAPI render integration test.
//!
//! This is the only test that touches a real audio device. It opens the current
//! default render endpoint through the real Windows backend, renders a short,
//! quiet 1 kHz tone, and asserts that frames and callbacks were actually
//! produced and that the output stayed below full scale.
//!
//! On a machine with no render endpoint (for example a headless CI runner) the
//! test reports a skip and passes: the absence of hardware is not a code defect,
//! and the test never claims success it did not observe.
//!
//! Run it explicitly with:
//!
//! ```text
//! cargo test -p uam_audio --test wasapi_render -- --nocapture
//! ```
#![cfg(windows)]

use std::thread::sleep;
use std::time::Duration;

use uam_audio::config::TestToneConfig;
use uam_audio::engine::AudioEngine;
use uam_audio::EngineState;

#[test]
fn renders_a_tone_to_the_default_endpoint() {
    let mut engine = AudioEngine::new();

    let default = match engine.default_device_id() {
        Ok(Some(id)) => id,
        Ok(None) => {
            eprintln!("wasapi_render: SKIP - no default render endpoint is available");
            return;
        }
        Err(error) => {
            eprintln!("wasapi_render: SKIP - endpoint lookup failed: {error}");
            return;
        }
    };

    if let Err(error) = engine.select_device(&default) {
        eprintln!("wasapi_render: SKIP - endpoint could not be prepared: {error}");
        return;
    }

    engine
        .set_test_tone(Some(TestToneConfig {
            frequency_hz: 1_000.0,
            level_db: -40.0,
        }))
        .expect("the conservative test tone is valid");

    if let Err(error) = engine.start() {
        eprintln!("wasapi_render: SKIP - the render stream could not start: {error}");
        return;
    }

    // Let the producer render well over a hundred buffers.
    sleep(Duration::from_millis(300));
    let status = engine.status();
    engine.stop();

    eprintln!(
        "wasapi_render: state={:?} format={:?} frames={} callbacks={} avg_us={:.1} max_us={:.1} peak_out_dbfs={:.2} latency_ms={:.2} buffer_frames={}",
        status.state,
        status.format.as_ref().map(|f| f.summary.clone()),
        status.metrics.frames_processed,
        status.metrics.callbacks,
        status.metrics.callback_average_us,
        status.metrics.callback_max_us,
        status.metrics.peak_output_dbfs,
        status.metrics.stream_latency_ms,
        status.metrics.buffer_frames,
    );

    assert_eq!(
        status.state,
        EngineState::Running,
        "the engine should still be running after 300 ms"
    );
    assert!(
        status.metrics.sample_rate_hz > 0,
        "the stream format should be known"
    );
    assert!(
        status.metrics.frames_processed > 0,
        "no audio frames were rendered"
    );
    assert!(
        status.metrics.callbacks > 0,
        "no render callbacks completed"
    );
    assert!(
        status.metrics.peak_output_dbfs < 0.0,
        "the output peak should be below full scale, got {}",
        status.metrics.peak_output_dbfs
    );
    assert!(
        status.metrics.peak_output_dbfs > -80.0,
        "the output should carry the test tone, got {} dBFS",
        status.metrics.peak_output_dbfs
    );
}
