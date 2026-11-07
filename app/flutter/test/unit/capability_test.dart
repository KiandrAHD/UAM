import 'package:flutter_test/flutter_test.dart';
import 'package:uam/shared/models/capability.dart';

void main() {
  group('CapabilityAvailability', () {
    test('only available is actionable', () {
      for (final availability in CapabilityAvailability.values) {
        expect(
          availability.isActionable,
          availability == CapabilityAvailability.available,
          reason: availability.wireName,
        );
      }
    });

    test('unavailable states are not confused with pending states', () {
      expect(CapabilityAvailability.disconnected.isUnavailable, isTrue);
      expect(CapabilityAvailability.unsupported.isUnavailable, isTrue);
      expect(CapabilityAvailability.notImplemented.isUnavailable, isTrue);
      expect(CapabilityAvailability.unknown.isUnavailable, isTrue);
      expect(CapabilityAvailability.permissionRequired.isPending, isTrue);
      expect(CapabilityAvailability.loading.isPending, isTrue);
      expect(CapabilityAvailability.available.isUnavailable, isFalse);
    });

    test('wire names round-trip and unknown values are null', () {
      expect(
        CapabilityAvailability.tryParse('permission_required'),
        CapabilityAvailability.permissionRequired,
      );
      expect(
        CapabilityAvailability.tryParse('not_implemented'),
        CapabilityAvailability.notImplemented,
      );
      expect(CapabilityAvailability.tryParse('magic'), isNull);
    });
  });

  group('FeatureCapability', () {
    test('copyWith preserves identity fields', () {
      const capability = FeatureCapability(
        featureId: 'anc',
        label: 'Noise cancellation',
        description: 'Reduces ambient noise.',
        availability: CapabilityAvailability.notImplemented,
        source: CapabilitySource.noAdapter,
      );
      final next = capability.copyWith(
        availability: CapabilityAvailability.available,
        enabled: true,
      );
      expect(next.featureId, 'anc');
      expect(next.availability, CapabilityAvailability.available);
      expect(next.enabled, isTrue);
    });
  });
}
