import 'capability.dart';

/// Connection state as reported by a platform adapter.
enum DeviceConnectionState {
  connected('connected', 'Connected'),
  disconnected('disconnected', 'Disconnected'),
  unknown('unknown', 'Unknown');

  const DeviceConnectionState(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// Physical transport when the platform exposes it.
enum DeviceTransport {
  bluetooth('bluetooth', 'Bluetooth'),
  usb('usb', 'USB'),
  builtIn('built_in', 'Built-in'),
  analog('analog', 'Analog'),
  unknown('unknown', 'Unknown');

  const DeviceTransport(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// Broad device category.
enum AudioDeviceType {
  output('output', 'Output'),
  input('input', 'Input'),
  headset('headset', 'Headset'),
  speaker('speaker', 'Speaker'),
  unknown('unknown', 'Unknown');

  const AudioDeviceType(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// Battery reading only when a platform adapter exposes it.
final class BatteryReading {
  const BatteryReading({required this.percent, this.estimatedRemaining});

  final int percent;
  final Duration? estimatedRemaining;

  bool get isValid => percent >= 0 && percent <= 100;
}

/// Normalized audio device returned by a platform adapter.
///
/// Every optional field is nullable because the operating system may not expose
/// it. Phase 1 has no discovery adapter, so production code never constructs a
/// demo device.
final class AudioDevice {
  const AudioDevice({
    required this.id,
    required this.displayName,
    required this.type,
    required this.transport,
    required this.connectionState,
    this.platformId,
    this.battery,
    this.codec,
    this.transportVersion,
    this.signalStrength,
    this.capabilities = const <FeatureCapability>[],
  });

  /// Application-level stable identifier. Never a Bluetooth address alone.
  final String id;

  /// Human-readable name.
  final String displayName;

  final AudioDeviceType type;
  final DeviceTransport transport;
  final DeviceConnectionState connectionState;

  /// Optional platform identifier for adapter correlation.
  final String? platformId;

  /// Battery is null unless the OS exposes a reliable reading.
  final BatteryReading? battery;

  /// Codec is null unless the adapter reports it.
  final String? codec;

  /// Bluetooth version or equivalent transport version when reported.
  final String? transportVersion;

  /// Signal description when reported; never inferred from connection state.
  final String? signalStrength;

  /// Capability reports with provenance.
  final List<FeatureCapability> capabilities;

  bool get isConnected => connectionState == DeviceConnectionState.connected;

  FeatureCapability? capability(String featureId) {
    for (final capability in capabilities) {
      if (capability.featureId == featureId) {
        return capability;
      }
    }
    return null;
  }
}

/// Why discovery is or is not available.
enum DeviceDiscoveryStatus {
  idle('idle', 'Not scanned'),
  scanning('scanning', 'Scanning'),
  ready('ready', 'Devices available'),
  empty('empty', 'No devices found'),
  unavailable('unavailable', 'Discovery unavailable'),
  permissionRequired('permission_required', 'Permission required'),
  unsupported('unsupported', 'Unsupported on this platform'),
  error('error', 'Discovery error');

  const DeviceDiscoveryStatus(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// One discovery result from a platform adapter.
final class DeviceDiscoverySnapshot {
  const DeviceDiscoverySnapshot({
    required this.status,
    this.devices = const <AudioDevice>[],
    this.reason,
  });

  final DeviceDiscoveryStatus status;
  final List<AudioDevice> devices;

  /// Safe explanation shown to the user. Never contains device identifiers.
  final String? reason;

  bool get hasDevices => devices.isNotEmpty;
}
