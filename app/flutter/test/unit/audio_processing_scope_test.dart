import 'package:flutter_test/flutter_test.dart';
import 'package:uam/platform/audio/audio_processing_scope.dart';

void main() {
  test('known wire names map to labels', () {
    expect(
      AudioProcessingScope.fromWireName('configuration_only'),
      AudioProcessingScope.configurationOnly,
    );
    expect(AudioProcessingScope.tryParse('unknown'), isNull);
  });

  test('unknown wire names throw instead of being overstated', () {
    expect(
      () => AudioProcessingScope.fromWireName('system_wide_magic'),
      throwsFormatException,
    );
  });
}
