#![forbid(unsafe_code)]
//! Platform-independent domain primitives shared by the UAM crates.
//!
//! This crate must not depend on Flutter, operating-system APIs, persistence,
//! or audio backends. Phase 0 only defines the validated audio configuration
//! that both the DSP prototype and future audio adapters rely on.

pub mod audio_config;

pub use audio_config::{
    AudioConfig, AudioConfigError, ChannelLayout, MAX_CHANNELS, MAX_SAMPLE_RATE_HZ,
    MIN_SAMPLE_RATE_HZ,
};

/// Human-readable product name. Shared by the UI and the native bridge.
pub const PRODUCT_NAME: &str = "Universe Audio Management";

/// Version of the Rust core, derived from this crate's package metadata at
/// compile time rather than duplicated by hand.
pub const CORE_ENGINE_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Version of the C ABI exposed by `uam_ffi`. Increment when an exported
/// function signature or payload contract changes incompatibly.
pub const BRIDGE_ABI_VERSION: u32 = 1;
