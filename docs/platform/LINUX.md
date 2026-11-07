# Linux Platform Notes — Phase 0

**Status:** DOCUMENTED only. Not executed. No Linux host was available.

## 1. Audio integration candidates

| Area | Candidate | Phase 0 status |
|---|---|---|
| Audio graph / routing | PipeWire | DOCUMENTED |
| Compatibility layer | PulseAudio (via `pipewire-pulse`) | DOCUMENTED |
| Low-level device API | ALSA | DOCUMENTED |
| Bluetooth | BlueZ | DOCUMENTED |

PipeWire is the recommended primary target. It handles device enumeration,
streams, and routing, and most current distributions ship it as the default
audio server. PulseAudio compatibility exists through `pipewire-pulse` for older
integrations.

## 2. Processing scope implications

- **App-owned stream:** straightforward via a PipeWire client stream.
- **Selected / system stream:** PipeWire supports virtual sinks/sources and
  per-node routing. A plausible design is to create virtual nodes and route
  selected applications through them, or to use filter nodes. This must be
  prototyped; behavior depends on the session manager (WirePlumber) and desktop
  environment.
- **System-wide output:** achievable with virtual devices/filter chains, but it
  requires understanding of the session manager and can differ across
  distributions and desktops.

Do not claim Linux system-wide processing until a virtual-node or filter-node
design is implemented and tested on at least two distributions.

## 3. Packaging and permissions

- Distribution model affects installation: Flatpak and Snap sandboxes restrict
  access to the audio server and to device files.
- Flatpak requires portal or socket permissions for audio and may restrict
  Bluetooth.
- PipeWire access is usually mediated by the session manager; do not assume raw
  device access.
- Package the app as a distribution package, Flatpak, or AppImage only after the
  sandbox/audio interaction is validated.

## 4. Bluetooth and hardware controls

- BlueZ provides discovery and GATT. Classic audio profiles are handled by the
  stack and PipeWire.
- Vendor controls (ANC, firmware) remain vendor-specific and are not exposed by
  BlueZ generically. No support is claimed.
- Battery reporting may appear via BlueZ but is device-dependent.

## 5. Rust and Flutter

- The Rust workspace is expected to compile unchanged (platform-independent
  crates). This is inferred, not executed.
- The FFI library would be `libuam_ffi.so`; the Dart locator already checks that
  name.
- Flutter Linux desktop requires GTK/Clang/CMake/Ninja and `pkg-config`.

## 6. Remaining validation points

- [ ] Build the Rust core and tests on a Linux host.
- [ ] Build `libuam_ffi.so` and load it from Flutter.
- [ ] Enumerate PipeWire nodes and devices.
- [ ] Prototype an app-owned PipeWire stream.
- [ ] Prototype virtual sink / filter-node routing for selected/system audio.
- [ ] Test Flatpak audio and Bluetooth permissions.
- [ ] Test on at least two distributions/desktops (for example GNOME and KDE).

## 7. Official sources

- PipeWire — https://pipewire.org/
- PipeWire documentation — https://docs.pipewire.org/
- WirePlumber — https://pipewire.pages.freedesktop.org/wireplumber/
- BlueZ — https://www.bluez.org/
- ALSA — https://www.alsa-project.org/