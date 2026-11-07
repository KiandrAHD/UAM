# Hardware Test Matrix

**Phase:** 0
**Status:** Not executed. No hardware-specific adapter exists yet.

This matrix defines what must be tested before any hardware capability is
advertised. Per ADR-005, a feature is not `available` until it is observed on
real hardware through a documented or validated adapter.

## 1. Result labels

| Label | Meaning |
|---|---|
| `PASS` | Observed working on that device/OS. |
| `FAIL` | Observed not working. |
| `PARTIAL` | Works with documented limits. |
| `BLOCKED` | Could not test (environment or access). |
| `TODO` | Not attempted. |

## 2. Device classes to cover

| Class | Examples | Why it matters |
|---|---|---|
| Built-in output | Laptop speakers | Baseline, no driver assumptions |
| Wired headphones | 3.5 mm / USB-C | Simple analog/USB path |
| USB audio interface | Class-compliant DAC | Multi-channel, sample-rate changes |
| Bluetooth headphones (A2DP) | Common consumer models | Codec, latency, route changes |
| Bluetooth headset (HFP) | Mic + output | Mode switching |
| BLE device | Vendor accessory | GATT discovery vs audio endpoint |
| Virtual device | OS virtual audio device | Routing and loopback behavior |
| Multi-channel output | 5.1/7.1 interface | Channel layout handling |

## 3. Capability matrix to fill

For each row, record the OS version, driver, connection, and observed result.

| Capability | Windows | macOS | Linux | Android | iOS |
|---|---|---|---|---|---|
| Device enumeration | PASS (enumeration only) | TODO | TODO | TODO | TODO |
| Friendly name | PASS | TODO | TODO | TODO | TODO |
| Device state changes | TODO | TODO | TODO | TODO | TODO |
| Default-device change | TODO | TODO | TODO | TODO | TODO |
| App-owned playback through DSP | TODO | TODO | TODO | TODO | TODO |
| Selected-stream processing | TODO | TODO | TODO | TODO | NOT POSSIBLE |
| System-wide output processing | TODO | TODO | TODO | NOT POSSIBLE | NOT POSSIBLE |
| Bluetooth discovery | TODO | TODO | TODO | TODO | TODO |
| Battery level | TODO | TODO | TODO | TODO | TODO |
| ANC control | TODO | TODO | TODO | TODO | TODO |
| Transparency control | TODO | TODO | TODO | TODO | TODO |
| Codec information | TODO | TODO | TODO | TODO | TODO |
| Firmware information | TODO | TODO | TODO | TODO | TODO |

"NOT POSSIBLE" encodes a platform-policy restriction, not a missing
implementation.

## 4. Minimum evidence per claim

A capability is `PASS` only when all of the following are recorded:

1. OS name and version.
2. Device make/model and transport (USB, Bluetooth, built-in).
3. Driver or firmware version where available.
4. Adapter identifier and version.
5. Exact operation performed and observed result.
6. Whether a capability reported `available` and with which `source`
   (`os_api`, `standard_profile`, `vendor_adapter`).
7. Any permission prompt and user decision.

## 5. Phase 0 evidence actually collected

| Item | Result | Evidence |
|---|---|---|
| Windows render endpoint enumeration | PASS | `tools/audio_diagnostics/` (4 active on host) |
| Windows capture endpoint enumeration | PASS | `tools/audio_diagnostics/` (2 active on host) |
| Endpoint friendly name + state | PASS | Same tool |
| Windows OS device list cross-check | PASS (coarse) | `scripts/test/windows_endpoint_inventory.ps1` |
| Audio playback/capture | NOT TESTED | No backend implemented |
| Any Bluetooth capability | NOT TESTED | No adapter implemented |
| Any vendor hardware control | NOT TESTED | No adapter implemented |

Device names from the host are intentionally not committed.

## 6. Process

1. Add a row before implementing the adapter (define the capability).
2. Test with a fake adapter in CI.
3. Test on real hardware; fill the matrix with evidence.
4. Update `docs/COMPATIBILITY.md` with the correct status label.
5. Never mark a capability `PASS` from a library claim alone.