import 'package:flutter_test/flutter_test.dart';
import 'package:uam/platform/audio/audio_processing_scope.dart';
import 'package:uam/shared/models/engine_runtime_state.dart';

void main() {
  group('EngineRuntimeState', () {
    test('unknown state never claims reachability or processing', () {
      const state = EngineRuntimeState.unknown;
      expect(state.coreReachable, isFalse);
      expect(state.processingVerified, isFalse);
      expect(state.configurationAccepted, isFalse);
      expect(state.processingScope, AudioProcessingScope.configurationOnly);
      expect(state.summary, 'Core status has not been verified.');
    });

    test('reachable configuration-only state is honest about processing', () {
      const state = EngineRuntimeState(
        status: EngineProcessingStatus.ready,
        coreReachable: true,
        coreVersion: '0.1.0',
        bridgeAbiVersion: 1,
        configurationAccepted: true,
      );
      expect(state.isReadyNotProcessing, isTrue);
      expect(state.isConfigured, isTrue);
      expect(
        state.summary,
        'Configuration is available. Audio processing is not verified.',
      );
    });

    test('error state summarises failure before reachability', () {
      const state = EngineRuntimeState(
        status: EngineProcessingStatus.error,
        coreReachable: false,
        errorMessage: 'missing library',
      );
      expect(state.summary, 'The Rust core could not be reached.');
    });

    test('verified processing only reports when the flag is set', () {
      const verified = EngineRuntimeState(
        status: EngineProcessingStatus.processing,
        coreReachable: true,
        processingVerified: true,
        processingScope: AudioProcessingScope.selectedStream,
      );
      expect(verified.processingVerified, isTrue);
      expect(verified.summary, 'Audio processing is verified.');
      expect(verified.isConfigured, isFalse);
    });
  });
}
