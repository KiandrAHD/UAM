import '../../../core/database/app_setting_keys.dart';
import '../../../core/result/result.dart';
import '../../../platform/audio/audio_engine_gateway.dart';
import '../../../features/settings/data/settings_repository.dart';
import '../../../shared/models/audio_device.dart';

/// Boundary for native platform device discovery.
///
/// The only concrete implementation is [EngineDeviceRepository], which delegates
/// to the Rust audio engine. A test can supply a deterministic fake.
abstract class DeviceRepository {
  /// Short human-readable description of the current adapter for permission
  /// panels and notices.
  String get adapterDescription;

  /// Reason why discovery is not available in this build.
  String get unavailableReason;

  /// Whether a native adapter is actually attached.
  bool get isAvailable;

  /// Perform a discovery scan.
  ///
  /// Must not emit fake devices. A successful call with zero results returns a
  /// snapshot with [DeviceDiscoveryStatus.empty], not an empty list.
  Future<DeviceDiscoverySnapshot> discover();

  /// Select [id] and resolve its stream format.
  ///
  /// Returns true when the backend accepted the endpoint.
  Future<bool> select(String id);

  /// Read the device identifier persisted from a previous session.
  Future<String?> persistedSelection();
}

/// Device repository backed by the real WASAPI engine.
final class EngineDeviceRepository implements DeviceRepository {
  EngineDeviceRepository(this._engine, this._settings);

  final AudioEngineGateway _engine;
  final SettingsRepository _settings;

  @override
  String get adapterDescription => _engine.isAvailable
      ? 'Native ${_engine.backendName} endpoint discovery.'
      : 'Native audio backend is not available in this build.';

  @override
  String get unavailableReason =>
      _engine.unavailableReason ??
      'The native audio backend is not available in this build.';

  @override
  bool get isAvailable => _engine.isAvailable;

  @override
  Future<DeviceDiscoverySnapshot> discover() async {
    if (!_engine.isAvailable) {
      return DeviceDiscoverySnapshot(
        status: DeviceDiscoveryStatus.unavailable,
        reason: unavailableReason,
      );
    }
    final result = await _engine.enumerate();
    switch (result) {
      case Success<AudioEndpointList>(value: final list):
        final devices = <AudioDevice>[
          for (final endpoint in list.endpoints)
            _toAudioDevice(endpoint, list.defaultId),
        ];
        if (!list.succeeded) {
          return DeviceDiscoverySnapshot(
            status: DeviceDiscoveryStatus.error,
            reason: list.reason ?? 'Endpoint enumeration failed.',
          );
        }
        return DeviceDiscoverySnapshot(
          status: devices.isEmpty
              ? DeviceDiscoveryStatus.empty
              : DeviceDiscoveryStatus.ready,
          devices: List<AudioDevice>.unmodifiable(devices),
          reason: devices.isEmpty
              ? 'The audio backend reported no active render endpoints.'
              : null,
        );
      case Failure<AudioEndpointList>(failure: final failure):
        return DeviceDiscoverySnapshot(
          status: DeviceDiscoveryStatus.error,
          reason: failure.message,
        );
    }
  }

  @override
  Future<bool> select(String id) async {
    if (!_engine.isAvailable) {
      return false;
    }
    final result = await _engine.selectDevice(id);
    if (result case Success<AudioStreamFormat>()) {
      await _settings.set(AppSettingKeys.selectedOutputDeviceId, id);
      return true;
    }
    return false;
  }

  @override
  Future<String?> persistedSelection() =>
      _settings.get<String>(AppSettingKeys.selectedOutputDeviceId);

  AudioDevice _toAudioDevice(AudioEndpoint endpoint, String? defaultId) {
    return AudioDevice(
      id: endpoint.id,
      displayName: endpoint.displayName,
      type: AudioDeviceType.output,
      transport: _transport(endpoint.transport),
      connectionState: _connection(endpoint.connectionState),
      isDefault: endpoint.isDefault || endpoint.id == defaultId,
      formatSummary: endpoint.formatSummary,
      platformId: endpoint.id,
    );
  }

  static DeviceTransport _transport(String? wire) => switch (wire) {
    'built_in' => DeviceTransport.builtIn,
    'usb' => DeviceTransport.usb,
    'bluetooth' => DeviceTransport.bluetooth,
    'hdmi' => DeviceTransport.hdmi,
    'network' => DeviceTransport.network,
    'virtual' => DeviceTransport.virtual,
    _ => DeviceTransport.unknown,
  };

  static DeviceConnectionState _connection(String wire) => switch (wire) {
    'active' => DeviceConnectionState.connected,
    'disabled' ||
    'unplugged' ||
    'not_present' => DeviceConnectionState.disconnected,
    _ => DeviceConnectionState.unknown,
  };
}

/// Always-unavailable repository used when no native backend is present.
final class UnavailableDeviceRepository implements DeviceRepository {
  const UnavailableDeviceRepository();

  @override
  String get adapterDescription =>
      'Native audio endpoint discovery is not available in this build.';

  @override
  String get unavailableReason =>
      'No native audio render backend is available on this platform.';

  @override
  bool get isAvailable => false;

  @override
  Future<DeviceDiscoverySnapshot> discover() async {
    return const DeviceDiscoverySnapshot(
      status: DeviceDiscoveryStatus.unavailable,
      reason:
          'Endpoint discovery is unavailable because no native backend is '
          'present. No demo devices are shown.',
    );
  }

  @override
  Future<bool> select(String id) async => false;

  @override
  Future<String?> persistedSelection() async => null;
}
