# Windows audio testing

## Automated checks

Run from `crates`:

```powershell
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo test -p uam_audio --test wasapi_render -- --nocapture
```

Unit and DSP tests are hardware-independent. `wasapi_render` opens actual default output when available, renders a quiet 1 kHz tone for 300 ms, and checks callback/frame/level metrics. No endpoint means `SKIP` and must be reported as `NOT VERIFIED` for hardware acceptance.

## Manual acceptance

On a Windows machine with speakers or headphones:

1. Start UAM and enumerate output endpoints.
2. Select endpoint and start test tone.
3. Confirm audible tone.
4. Set a 1 kHz peaking band to positive and negative gain; compare RMS or peak measurements.
5. Enable bypass without stopping stream; confirm tone continues and output returns toward dry level.
6. Switch endpoints while stopped and running.
7. Disconnect selected endpoint; confirm no crash, failed/recovering status, and selectable replacement.
8. Reconnect endpoint and confirm fresh enumeration and recovery behavior.

Record Windows version, UAM commit, endpoint name, sample format, sample rate, buffer frames, callback duration, underruns, glitches, and audible result. Never mark physical tests passed without recording actual observations.
