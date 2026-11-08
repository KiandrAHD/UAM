//! Phase 2.3D — steady-state allocation-safety test.
//!
//! # Isolation strategy
//!
//! A counting allocator is installed as this test binary's `#[global_allocator]`.
//! It only counts while an atomic `ARMED` flag is set, and this file contains a
//! **single** `#[test]`, so no sibling test thread can pollute the count. The
//! counting windows are opened and closed immediately around the code under
//! test, with no formatting or I/O inside a window.
//!
//! Three categories are measured and asserted separately:
//!
//! - **Initialization** (`from_config`) is allowed to allocate: it builds the
//!   per-band, per-channel filter state.
//! - **Configuration replacement** (`apply_config`) is a control-thread
//!   operation and is allowed to allocate.
//! - **Steady-state processing** (`process_interleaved`) must not allocate.
//!
//! This test is intentionally kept in its own integration binary.

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use uam_domain::AudioConfig;
use uam_dsp::{BandConfig, DspConfig, DspPipeline, FilterKind, LimiterConfig};

struct CountingAllocator;

static ARMED: AtomicBool = AtomicBool::new(false);
static ALLOCATIONS: AtomicUsize = AtomicUsize::new(0);

// SAFETY: this wraps `System` and only adds an atomic counter; it forwards every
// layout unchanged, so the allocator invariants are preserved.
unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if ARMED.load(Ordering::Relaxed) {
            ALLOCATIONS.fetch_add(1, Ordering::Relaxed);
        }
        // SAFETY: `System` is a valid allocator for this layout.
        unsafe { System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        if ARMED.load(Ordering::Relaxed) {
            ALLOCATIONS.fetch_add(1, Ordering::Relaxed);
        }
        // SAFETY: `System` is a valid allocator for this layout.
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        // SAFETY: `pointer` was produced by this allocator via `System`.
        unsafe { System.dealloc(pointer, layout) }
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        if ARMED.load(Ordering::Relaxed) {
            ALLOCATIONS.fetch_add(1, Ordering::Relaxed);
        }
        // SAFETY: `pointer` was produced by this allocator and `new_size` is a
        // valid size for the new layout.
        unsafe { System.realloc(pointer, layout, new_size) }
    }
}

#[global_allocator]
static GLOBAL: CountingAllocator = CountingAllocator;

fn audio() -> AudioConfig {
    AudioConfig::new(48_000, 2).expect("valid config")
}

fn config(bands: usize) -> DspConfig {
    let bands = (0..bands)
        .map(|index| {
            BandConfig::new(FilterKind::Peaking, 200.0 * (index as f64 + 1.0), 3.0, 1.0)
                .expect("band")
        })
        .collect();
    DspConfig::new(audio(), 2.0, bands)
        .expect("config")
        .with_limiter(LimiterConfig::new(true, -3.0, 100.0).expect("limiter"))
}

fn measure(body: impl FnOnce()) -> usize {
    ALLOCATIONS.store(0, Ordering::SeqCst);
    ARMED.store(true, Ordering::SeqCst);
    body();
    ARMED.store(false, Ordering::SeqCst);
    ALLOCATIONS.load(Ordering::SeqCst)
}

#[test]
fn allocation_categories_are_distinguished() {
    // --- Initialization: allowed to allocate. -------------------------------
    let mut pipeline: Option<DspPipeline> = None;
    let init_allocations = measure(|| {
        pipeline = Some(DspPipeline::from_config(&config(10)).expect("pipeline"));
    });
    let mut pipeline = pipeline.expect("pipeline built");
    assert!(
        init_allocations > 0,
        "initialization should allocate filter state, counted {init_allocations}"
    );

    // --- Steady-state processing: must not allocate. ------------------------
    let mut buffer = vec![0.0_f64; 512 * 2];
    for (index, sample) in buffer.iter_mut().enumerate() {
        *sample = 0.2 * (index as f64 * 0.03).sin();
    }
    // Warm up outside the measured window.
    for _ in 0..16 {
        pipeline.process_interleaved(&mut buffer).expect("warm up");
    }
    let steady_allocations = measure(|| {
        for _ in 0..2_000 {
            pipeline
                .process_interleaved(&mut buffer)
                .expect("steady-state process");
        }
    });
    assert_eq!(
        steady_allocations, 0,
        "steady-state processing allocated {steady_allocations} times"
    );

    // --- Configuration replacement: allowed to allocate. --------------------
    let replacement = config(12);
    let reconfig_allocations = measure(|| {
        pipeline
            .apply_config(&replacement)
            .expect("apply replacement");
    });
    assert!(
        reconfig_allocations > 0,
        "configuration replacement should allocate the new chain, counted {reconfig_allocations}"
    );

    // After replacement, steady-state is allocation-free again.
    let steady_after = measure(|| {
        for _ in 0..500 {
            pipeline
                .process_interleaved(&mut buffer)
                .expect("steady-state process");
        }
    });
    assert_eq!(
        steady_after, 0,
        "processing allocated after reconfiguration"
    );
}
