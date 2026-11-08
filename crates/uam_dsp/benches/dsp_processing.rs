//! Reproducible Criterion benchmarks for the UAM DSP processing path.
//!
//! Run from `crates/` with:
//!
//! ```text
//! cargo bench -p uam_dsp --bench dsp_processing --locked
//! ```
//!
//! Initialization and input generation happen outside the timed closure. Each
//! iteration reuses a preallocated buffer, resets the engine, and processes one
//! deterministic block.
//!
//! Matrix:
//!
//! - `eq_only`: 48 kHz mono and stereo, block sizes 128..4096, 0/1/5/10/32 bands.
//! - `eq_meter`, `eq_limiter`, `eq_limiter_meter`: stereo, 10 bands, all block sizes.
//! - `limiter_only`: stereo, all block sizes (isolates limiter cost).
//! - `peak_meter_only`: stereo, all block sizes (isolates meter cost).
//! - `bypass`: stereo, 10 bands, all block sizes.
//!
//! Group timing is reduced (0.5 s warm-up, 1 s measurement, 30 samples) to keep
//! the full matrix reproducible in a few minutes on the reference machine.

use std::hint::black_box;
use std::time::Duration;

use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use uam_domain::AudioConfig;
use uam_dsp::{
    BandConfig, DspConfig, DspPipeline, Equalizer, FilterKind, Limiter, LimiterConfig, PeakMeter,
};

const SAMPLE_RATE_HZ: u32 = 48_000;
const BLOCK_SIZES: &[usize] = &[128, 256, 512, 1024, 2048, 4096];
const BAND_COUNTS: &[usize] = &[0, 1, 5, 10, 32];
const OVERHEAD_BANDS: usize = 10;

fn audio(channels: u16) -> AudioConfig {
    AudioConfig::new(SAMPLE_RATE_HZ, channels).expect("benchmark audio config")
}

fn bands(count: usize) -> Vec<BandConfig> {
    (0..count)
        .map(|index| {
            let frequency_hz = 80.0 * 2.0_f64.powf(index as f64 * 0.22);
            BandConfig::new(
                match index % 3 {
                    0 => FilterKind::Peaking,
                    1 => FilterKind::LowShelf,
                    _ => FilterKind::HighShelf,
                },
                frequency_hz.min(20_000.0),
                (index as f64 % 7.0) - 3.0,
                0.7 + (index as f64 % 5.0) * 0.1,
            )
            .expect("benchmark band")
        })
        .collect()
}

fn input(block_size: usize, channels: u16) -> Vec<f64> {
    let samples = block_size * usize::from(channels);
    (0..samples)
        .map(|index| {
            let phase = index as f64 * 0.013;
            0.25 * phase.sin() + 0.05 * (phase * 0.37).cos()
        })
        .collect()
}

fn short_group<'a>(
    c: &'a mut Criterion,
    name: &str,
) -> criterion::BenchmarkGroup<'a, criterion::measurement::WallTime> {
    let mut group = c.benchmark_group(name);
    group
        .warm_up_time(Duration::from_millis(500))
        .measurement_time(Duration::from_secs(1))
        .sample_size(30);
    group
}

fn bench_eq_only(c: &mut Criterion) {
    let mut group = short_group(c, "eq_only");
    for &channels in &[1_u16, 2] {
        for &band_count in BAND_COUNTS {
            for &block_size in BLOCK_SIZES {
                let id = format!("{channels}ch_{band_count}bands_{block_size}frames");
                group.throughput(Throughput::Elements(block_size as u64));
                let config =
                    DspConfig::new(audio(channels), 0.0, bands(band_count)).expect("config");
                let mut equalizer = Equalizer::from_config(&config).expect("equalizer");
                let mut buffer = input(block_size, channels);
                group.bench_function(BenchmarkId::new("process", id), |bencher| {
                    bencher.iter(|| {
                        equalizer.reset();
                        equalizer
                            .process_interleaved(black_box(&mut buffer))
                            .unwrap();
                        black_box(&buffer);
                    });
                });
            }
        }
    }
    group.finish();
}

fn bench_pipeline_variants(c: &mut Criterion) {
    let channels = 2_u16;
    let limiter = LimiterConfig::new(true, -3.0, 100.0).expect("limiter");
    let config = DspConfig::new(audio(channels), 0.0, bands(OVERHEAD_BANDS))
        .expect("config")
        .with_limiter(limiter);
    let mut pipeline = DspPipeline::from_config(&config).expect("pipeline");

    for scenario in ["eq_meter", "eq_limiter", "eq_limiter_meter"] {
        let mut group = short_group(c, scenario);
        for &block_size in BLOCK_SIZES {
            let id = format!("{channels}ch_{OVERHEAD_BANDS}bands_{block_size}frames");
            group.throughput(Throughput::Elements(block_size as u64));
            let mut buffer = input(block_size, channels);
            group.bench_function(BenchmarkId::new("process", id), |bencher| {
                bencher.iter(|| {
                    pipeline.reset();
                    match scenario {
                        "eq_meter" => {
                            pipeline
                                .equalizer_mut()
                                .process_interleaved(&mut buffer)
                                .unwrap();
                            pipeline
                                .output_meter_mut()
                                .process_interleaved(&buffer)
                                .unwrap();
                        }
                        "eq_limiter" => {
                            pipeline
                                .equalizer_mut()
                                .process_interleaved(&mut buffer)
                                .unwrap();
                            pipeline
                                .limiter_mut()
                                .process_interleaved(&mut buffer)
                                .unwrap();
                        }
                        _ => {
                            pipeline.process_interleaved(&mut buffer).unwrap();
                        }
                    }
                    black_box(&buffer);
                });
            });
        }
        group.finish();
    }
}

fn bench_limiter_only(c: &mut Criterion) {
    let mut group = short_group(c, "limiter_only");
    let mut limiter = Limiter::new(
        &LimiterConfig::new(true, -3.0, 100.0).expect("limiter"),
        audio(2),
    )
    .expect("limiter");
    for &block_size in BLOCK_SIZES {
        let id = format!("2ch_{block_size}frames");
        group.throughput(Throughput::Elements(block_size as u64));
        let mut buffer = input(block_size, 2);
        group.bench_function(BenchmarkId::new("process", id), |bencher| {
            bencher.iter(|| {
                limiter.reset();
                limiter.process_interleaved(black_box(&mut buffer)).unwrap();
                black_box(&buffer);
            });
        });
    }
    group.finish();
}

fn bench_meter_only(c: &mut Criterion) {
    let mut group = short_group(c, "peak_meter_only");
    let mut meter = PeakMeter::new(2).expect("meter");
    for &block_size in BLOCK_SIZES {
        let id = format!("2ch_{block_size}frames");
        group.throughput(Throughput::Elements(block_size as u64));
        let source = input(block_size, 2);
        group.bench_function(BenchmarkId::new("process", id), |bencher| {
            bencher.iter(|| {
                meter.reset();
                let report = meter.process_interleaved(black_box(&source)).unwrap();
                black_box(report);
            });
        });
    }
    group.finish();
}

fn bench_bypass(c: &mut Criterion) {
    let mut group = short_group(c, "bypass");
    let config = DspConfig::new(audio(2), 0.0, bands(OVERHEAD_BANDS))
        .expect("config")
        .with_bypassed(true);
    let mut equalizer = Equalizer::from_config(&config).expect("equalizer");
    for &block_size in BLOCK_SIZES {
        let id = format!("2ch_{OVERHEAD_BANDS}bands_{block_size}frames");
        group.throughput(Throughput::Elements(block_size as u64));
        let mut buffer = input(block_size, 2);
        group.bench_function(BenchmarkId::new("process", id), |bencher| {
            bencher.iter(|| {
                equalizer
                    .process_interleaved(black_box(&mut buffer))
                    .unwrap();
                black_box(&buffer);
            });
        });
    }
    group.finish();
}

criterion_group!(
    benches,
    bench_eq_only,
    bench_pipeline_variants,
    bench_limiter_only,
    bench_meter_only,
    bench_bypass
);
criterion_main!(benches);
