//! Platform-independent core of the UAM audio backend layer.
//!
//! This crate owns the pieces that run inside a real-time audio callback — the
//! DSP host, boundary sample-format conversion, metrics, and the diagnostic
//! test tone — plus the control-path vocabulary (device model, configuration
//! DTOs, errors, lifecycle state) and the engine that drives a platform
//! backend. The actual endpoint and stream code lives in the `windows` module
//! behind the [`crate::backend`] trait.
//!
//! # Real-time contract
//!
//! Code that executes in a render callback ([`crate::host::DspHost::render`],
//! [`crate::format::encode`], [`crate::metrics`]) performs no allocation,
//! locking, I/O, or logging. All buffers are preallocated before the stream
//! starts; parameter changes cross the boundary through bounded atomics and
//! channels per ADR-007.
//!
//! # Unsafe code
//!
//! The crate denies `unsafe` everywhere except the platform modules, which must
//! call location APIs. Only the Windows module relaxes that lint, and every
//! unsafe block there documents its trust boundary. The DSP and format code
//! remain safe.

#![deny(unsafe_code)]

pub mod backend;
pub mod config;
pub mod device;
pub mod engine;
pub mod error;
pub mod format;
pub mod host;
pub mod metrics;
pub mod stub;
pub mod tone;

#[cfg(windows)]
pub mod windows;

/// Sample rate used to build a probe pipeline when probing channel occupancy.
pub const DEFAULT_PROBE_SAMPLE_RATE_HZ: u32 = 48_000;
/// Channel count used to build a probe pipeline when probing channel occupancy.
pub const DEFAULT_PROBE_CHANNELS: u16 = 2;

pub use backend::{create_backend, AudioBackend, DeviceSubscription, OpenRequest, RunningStream};
pub use config::{
    AudioScope, DspRequest, EngineState, EqBandDto, EqFilterTypeDto, LimiterDto, SampleEncoding,
    StreamFormat, TestToneConfig,
};
pub use device::{DeviceEvent, DeviceEventKind, DeviceListSnapshot, DeviceState, OutputDevice};
pub use engine::{AudioEngine, EngineStatus, ErrorDto, FormatSummary};
pub use error::{AudioError, AudioErrorCode};
pub use metrics::{Metrics, MetricsSnapshot};
