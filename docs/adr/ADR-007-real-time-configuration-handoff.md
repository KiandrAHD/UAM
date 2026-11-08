# ADR-007 — Real-time DSP configuration hand-off

- **Status:** Proposed (design recorded; implementation deferred to the live-audio-backend milestone)
- **Date:** 2026-11-08
- **Supersedes:** none
- **Related:** ADR-002 (Rust core), ADR-003 (Flutter–Rust interop), ADR-006 (Windows-first audio integration), `docs/Architecture.md` §5 and §10

## Context

Phase 2.1–2.2 adds a validated DSP configuration DTO (`uam_dsp::DspConfig`) and a
**control-thread** update API (`Equalizer::apply_config`). The audio callback
does not exist yet: the engine remains `configuration_only` and no OS audio
stream is attached. Once a backend exists (Phase 4, Windows first), the audio
callback must consume configuration and coefficient updates without allocating,
locking, blocking, or performing unbounded work.

This record fixes the *ownership and synchronization model* now, so that the
DSP crate's public shape does not have to change when the callback arrives. It
does **not** implement a hand-off. Implementing one before a measured callback
exists would be an unverifiable claim of lock-free behaviour.

Two hard constraints follow from the existing code and the architecture:

1. `crates/uam_dsp` is `#![forbid(unsafe_code)]` and `uam_domain` is
   `#![forbid(unsafe_code)]`. Any unsafe synchronization primitive must live in
   the backend crate (a future `uam_audio`), not in the DSP crate.
2. `Equalizer::process_interleaved` must stay allocation-free and lock-free. The
   hand-off is between a control thread and the audio thread, not inside the
   DSP crate.

## Decision

**Selected model: immutable prepared state with a safe ownership hand-off
(deferred implementation).**

- The control thread builds a complete, validated, immutable *prepared block*:
  the coefficient set for every band × channel and the preamp linear gain. All
  allocation and all coefficient math happen here.
- The audio thread owns one prepared block at a time through a single-owner
  move, and never shares it.
- The transfer uses a **bounded SPSC channel with one in-flight value** (a
  `ringbuf`/`crossbeam`-style bounded channel, or `std::sync::mpsc::sync_channel(1)`
  as the simplest baseline) because it is the only mechanism that is correct by
  construction without bespoke `unsafe`. The receiver performs a single
  `try_recv` per block; the sender never blocks the control thread unboundedly.

The exact primitive is a Phase-4 implementation decision; the *model* — prepare
immutably off-thread, transfer ownership, apply at a block boundary, never share
mutable floating-point payloads — is the decision this ADR records.

## Alternatives considered

### A. Bounded SPSC command queue

The control thread posts a whole prepared configuration (ownership moved into
the queue). The audio thread drains at most N messages per block and applies the
newest.

| Aspect | Analysis |
|---|---|
| Memory ownership | Queue owns each message until the receiver takes it; the DSP block is `Box`/`Arc`-free, movable, single-owner. |
| Allocation | Sender allocates the prepared block once per update (control thread, allowed). The queue itself is pre-allocated at engine construction; the callback allocates nothing. |
| Atomic ordering | Producer publishes with `Release`, consumer reads index with `Acquire` (standard SPSC). No `Relaxed`-only ordering on the data. |
| Data-race safety | Correct by construction: exactly one producer and one consumer; the payload is moved, never aliased. No `unsafe` needed with a maintained crate. |
| Callback worst case | Bounded: drain a fixed maximum of `K` messages, apply once. O(`K`) dequeue attempts regardless of how many updates the UI produced. |
| Parameter update behaviour | Coalescing: if several updates queue up, the callback applies the last and discards older ones (or applies one per block, bounded). |
| Overflow / backpressure | Bounded ring. On full, the producer either overwrites the oldest (coalesce) or fails the *control-thread* update — never blocks or aborts the audio thread. |

### B. Triple-buffer ownership transfer

Three prepared blocks; the producer writes the next free block, then atomically
publishes its index; the consumer reads the published index and its own block.
Classic "triple buffer" (Real-Time Rendering) or a `triple_buffer` crate.

| Aspect | Analysis |
|---|---|
| Memory ownership | Three immutable blocks. Neither side mutates a block the other may read. |
| Allocation | All three blocks allocated once at construction; steady-state updates allocate nothing. |
| Atomic ordering | Single `AtomicUsize` swap with `Acquire`/`Release` (or `AcqRel`). |
| Data-race safety | Safe with a maintained crate. A hand-rolled version needs `UnsafeCell` and a correct publication protocol; getting it subtly wrong is a data race. |
| Callback worst case | O(1): one atomic load, at most one pointer swap. Best worst-case of all options. |
| Parameter update behaviour | The consumer must *choose* the newest or must interpolate; multiple updates between blocks collapse to the latest. |
| Overflow / backpressure | No overflow by design; the producer overwrites. Intermediate updates are intentionally lost — acceptable for parameter state, not for a command log. |

### C. Immutable prepared state with a safe ownership hand-off (selected)

A specialization of A: what is transferred is a fully prepared, immutable
coefficient block, not a raw parameter struct. The queue (or a single
`sync_channel(1)`) transfers ownership.

| Aspect | Analysis |
|---|---|
| Memory ownership | Single-owner move; no shared mutable state at any point. |
| Allocation | All off-thread. The callback only receives and drops. |
| Atomic ordering | The primitive's own `Acquire`/`Release`; no hand-rolled ordering. |
| Data-race safety | Rust's ownership rules make a data race a compile error, not a review item. |
| Callback worst case | One non-blocking receive plus a bounded apply. |
| Parameter update behaviour | Coalesced to "apply the most recent prepared block at the next block boundary". |
| Overflow / backpressure | Bounded; the control thread drops superseded updates rather than blocking the callback. |

### D. Seqlock over shared coefficients

A shared `f64` coefficient array with a sequence counter read twice.

**Rejected for this project.** A seqlock over ordinary non-atomic `f64` fields
is a data race in the Rust memory model even when the reader retries: the
concurrent unsynchronized read of a torn `f64` is UB, and Rust provides no
legal way to read it without either atomics-per-field or `unsafe`. Making every
coefficient an `AtomicU64` and using `f64::from_bits` on a relaxed load is
possible, but it multiplies the callback's work, cannot atomically publish a
multi-field block (band count, preamp, bypass, coefficients), and reintroduces
exactly the hand-rolled correctness burden this ADR avoids. The DSP crate is
`#![forbid(unsafe_code)]`, so this option cannot even be expressed there.

### E. Other mechanisms

- **Double-buffered `Arc<PreparedState>` swap.** Equivalent guarantees to B with
  an `Arc`; costs an atomic refcount bump per block and gives up single-owner
  clarity. Viable, not preferred.
- **`Mutex`/`RwLock` around the configuration.** Rejected: a normal mutex can
  block the audio thread (priority inversion), violating Architecture §10.
- **Atomic scalars only (one `AtomicU64` per gain, no block publish).** Fine for
  a single gain, but the engine publishes a whole band set at once; per-field
  atomics cannot publish a consistent snapshot.

## Consequences

Positive:

- The DSP crate keeps `#![forbid(unsafe_code)]`; the hand-off, when implemented,
  is confined to the backend crate.
- `process_interleaved` remains allocation- and lock-free and gains no new
  parameters; only a future `try_recv`-and-apply step is added around it.
- The DTO is validated once, off-thread, before any prepared block exists.

Negative / deferred:

- No hand-off is implemented in this milestone, so "parameter updates do not
  block the audio callback" remains an **untested** exit criterion
  (`docs/PHASE_2_READINESS.md`). It can only be closed when a backend and its
  callback exist.
- A real implementation must still choose between A/C (queue, coalescing) and B
  (triple buffer) and prove it with an allocation-count and a
  concurrent-update test. That is Phase 4 work.

## Explicitly out of scope

- Full limiter signal processing (later dynamics milestone).
- Production parameter transport in code (this ADR only fixes the model).
- New DSP FFI symbols and the Flutter DSP controller (later milestones).

## Evidence

- `crates/uam_dsp/src/equalizer/mod.rs` — `apply_config` prepares a replacement
  chain (allocating) and commits only after preparation succeeds; this is the
  control-thread half of the model.
- `crates/uam_dsp/src/equalizer/mod.rs` — `process_interleaved` allocates
  nothing and takes no lock.
- `crates/uam_dsp/src/lib.rs`, `crates/uam_domain/src/lib.rs` — both crates are
  `#![forbid(unsafe_code)]`.
- `docs/Architecture.md` §5 (DSP design requirements) and §10 (threading).
- `docs/PHASE_2_IMPLEMENTATION_REPORT.md` §"Real-time thread safety".
