/// Availability of one hardware capability.
///
/// The distinction between disconnected, unsupported, permission-gated, and
/// not-yet-implemented is product-critical. A control is rendered as actionable
/// only for [CapabilityAvailability.available].
enum CapabilityAvailability {
  available('available', 'Available'),
  unsupported('unsupported', 'Unsupported'),
  permissionRequired('permission_required', 'Permission required'),
  disconnected('disconnected', 'Disconnected'),
  unavailableOnPlatform('unavailable_on_platform', 'Unavailable on platform'),
  notImplemented('not_implemented', 'Not implemented'),
  unknown('unknown', 'Unknown'),
  loading('loading', 'Checking'),
  error('error', 'Error');

  const CapabilityAvailability(this.wireName, this.label);

  final String wireName;
  final String label;

  /// Whether the feature may render an interactive control.
  bool get isActionable => this == CapabilityAvailability.available;

  /// Whether the state is waiting for an adapter or permission response.
  bool get isPending =>
      this == CapabilityAvailability.loading ||
      this == CapabilityAvailability.permissionRequired;

  /// Whether the feature is absent from this build or this platform.
  bool get isUnavailable =>
      this == CapabilityAvailability.unsupported ||
      this == CapabilityAvailability.unavailableOnPlatform ||
      this == CapabilityAvailability.notImplemented ||
      this == CapabilityAvailability.disconnected ||
      this == CapabilityAvailability.unknown ||
      this == CapabilityAvailability.error;

  static CapabilityAvailability? tryParse(String value) {
    for (final availability in values) {
      if (availability.wireName == value) {
        return availability;
      }
    }
    return null;
  }
}

/// Provenance of a capability report.
enum CapabilitySource {
  operatingSystem('Operating system API'),
  standardProfile('Standard profile'),
  vendorAdapter('Vendor adapter'),
  userConfiguration('User configuration'),
  noAdapter('No adapter');

  const CapabilitySource(this.label);

  final String label;
}

/// One capability report attached to a device or platform.
final class FeatureCapability {
  const FeatureCapability({
    required this.featureId,
    required this.label,
    required this.description,
    required this.availability,
    required this.source,
    this.reason,
    this.enabled,
  });

  /// Stable identifier such as `anc`, `transparency`, or `battery`.
  final String featureId;

  /// User-facing feature name.
  final String label;

  /// Short explanation of what the feature does.
  final String description;

  /// Current state from the adapter.
  final CapabilityAvailability availability;

  /// Where the claim came from.
  final CapabilitySource source;

  /// Explanation of why the feature is unavailable, when known.
  final String? reason;

  /// Current value for an available binary control.
  final bool? enabled;

  FeatureCapability copyWith({
    CapabilityAvailability? availability,
    CapabilitySource? source,
    String? reason,
    bool? enabled,
  }) {
    return FeatureCapability(
      featureId: featureId,
      label: label,
      description: description,
      availability: availability ?? this.availability,
      source: source ?? this.source,
      reason: reason ?? this.reason,
      enabled: enabled ?? this.enabled,
    );
  }
}
