/// Availability of one hardware capability.
///
/// Phase 0 defines the vocabulary only. No Bluetooth adapter is implemented,
/// and no capability may be reported as available without a tested adapter.
enum BluetoothCapabilityAvailability {
  /// Verified against a device and platform adapter.
  available,

  /// The API exists but has not been validated on target hardware.
  unverified,

  /// The platform API is documented but no adapter is implemented.
  notImplemented,

  /// Permission is required before the feature can be evaluated.
  permissionRequired,

  /// The platform or device does not expose the feature.
  unsupported,
}

/// Provenance of a reported capability.
enum BluetoothCapabilitySource {
  /// Documented operating-system API.
  operatingSystem,

  /// Standard Bluetooth profile.
  standardProfile,

  /// Reviewed vendor-specific adapter.
  vendorAdapter,

  /// Inferred from another signal and therefore not authoritative.
  inferred,
}

/// One capability report with provenance.
///
/// Adapters must attach a source and reason. A connected device is not proof
/// that a feature is controllable.
final class BluetoothCapability {
  const BluetoothCapability({
    required this.featureId,
    required this.availability,
    required this.source,
    this.reason,
  });

  /// Stable feature identifier such as `battery` or `anc`.
  final String featureId;

  /// Current availability.
  final BluetoothCapabilityAvailability availability;

  /// Where the capability claim came from.
  final BluetoothCapabilitySource source;

  /// Optional explanation shown to the user.
  final String? reason;
}
