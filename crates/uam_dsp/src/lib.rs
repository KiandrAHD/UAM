#![forbid(unsafe_code)]
//! Minimal, deterministic audio DSP prototype for UAM.
//!
//! Phase 0 implements a preamp followed by a cascade of biquad equalizer
//! filters. Coefficients follow the RBJ Audio EQ Cookbook forms. Processing
//! uses Direct Form II Transposed sections with explicit per-channel state.
//!
//! Design constraints:
//!
//! - No allocation, locking, file access, or logging occurs in
//!   [`Equalizer::process_interleaved`]. Filter state is allocated when the
//!   chain is constructed.
//! - Every public numeric parameter is validated before coefficients are
//!   produced.
//! - Non-finite input samples are replaced with silence and a poisoned filter
//!   state is reset, so one bad sample cannot persist as `NaN`.
//!
//! The crate is independent of Flutter, SQLite, and operating-system audio
//! APIs. It processes caller-owned `f64` sample buffers only.

pub mod config;
pub mod equalizer;
pub mod filters;
pub mod limiter;
pub mod meter;
pub mod pipeline;
pub mod validation;

pub use config::{DspConfig, LimiterConfig};
pub use equalizer::Equalizer;
pub use filters::{BandConfig, Biquad, BiquadCoefficients, FilterKind};
pub use limiter::Limiter;
pub use meter::{
    linear_to_dbfs, BlockPeak, MeterError, PeakMeter, CLIP_THRESHOLD_LINEAR, DBFS_FLOOR,
};
pub use pipeline::{DspPipeline, PipelineReport};
pub use validation::{
    DspError, MAX_BANDS, MAX_FREQUENCY_HZ, MAX_GAIN_DB, MAX_LIMITER_CEILING_DB,
    MAX_LIMITER_RELEASE_MS, MAX_PREAMP_DB, MAX_Q, MIN_FREQUENCY_HZ, MIN_GAIN_DB,
    MIN_LIMITER_CEILING_DB, MIN_LIMITER_RELEASE_MS, MIN_PREAMP_DB, MIN_Q,
};
