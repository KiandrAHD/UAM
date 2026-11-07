import '../../../shared/models/audio_device.dart';

/// Boundary for native platform device discovery.
///
/// Phase 1 has no implemented adapter; [UnavailableDeviceRepository] is the
/// sole concrete implementation. Future adapters are introduced behind this
/// interface during Phase 5+.
abstract class DeviceRepository {
  /// Short human-readable description of the current adapter for permission
  /// panels and notices.
  String get adapterDescription;

  /// Reason why discovery is not available in this build.
  String get unavailableReason;

  /// Perform a discovery scan.
  ///
  /// Must not emit fake devices. A successful call with zero results returns a
  /// snapshot with [DeviceDiscoveryStatus.empty], not an empty list.
  Future<DeviceDiscoverySnapshot> discover();
}

/// Always-unavailable repository used in Phase 1.
final class UnavailableDeviceRepository implements DeviceRepository {
  const UnavailableDeviceRepository();

  @override
  String get adapterDescription =>
      'Native device adapter not implemented in Phase 1.';

  @override
  String get unavailableReason =>
      'No native platform adapter is available in this build. '
      'Bluetooth pairing alone does not grant device discovery or metadata access.';

  @override
  Future<DeviceDiscoverySnapshot> discover() async {
    // Brief artificial delay so the UI can show a scanning state during
    // development, without fabricating device data.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return const DeviceDiscoverySnapshot(
      status: DeviceDiscoveryStatus.unavailable,
      reason:
          'Device discovery is not implemented in Phase 1. '
          'No demo devices are shown.',
    );
  }
}
