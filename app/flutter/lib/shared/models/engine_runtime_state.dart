import '../../platform/audio/audio_processing_scope.dart';

/// Verified engine readiness and processing state.
///
/// Desired configuration, core-accepted configuration, and actual audio
/// processing are separate fields. Phase 1 can reach `ready` and accept a
/// configuration, but it cannot set [processingVerified].
enum EngineProcessingStatus {
  unavailable('Unavailable'),
  ready('Ready, not processing'),
  standby('Standby'),
  processing('Processing'),
  error('Error');

  const EngineProcessingStatus(this.label);

  final String label;
}

/// Snapshot of the engine shown by Dashboard and Audio Engine.
final class EngineRuntimeState {
  const EngineRuntimeState({
    required this.status,
    required this.coreReachable,
    this.coreVersion,
    this.bridgeAbiVersion,
    this.processingScope = AudioProcessingScope.configurationOnly,
    this.processingVerified = false,
    this.configurationAccepted = false,
    this.backendName,
    this.selectedEndpoint,
    this.activeEndpoint,
    this.sampleRateHz,
    this.bitDepth,
    this.latencyMs,
    this.errorMessage,
    this.checkedAt,
  });

  /// Honest default before the bridge is queried.
  static const EngineRuntimeState unknown = EngineRuntimeState(
    status: EngineProcessingStatus.unavailable,
    coreReachable: false,
  );

  final EngineProcessingStatus status;
  final bool coreReachable;
  final String? coreVersion;
  final int? bridgeAbiVersion;
  final AudioProcessingScope processingScope;

  /// True only when a live audio stream has been observed by the core.
  final bool processingVerified;

  /// True when the core accepted the in-memory configuration.
  final bool configurationAccepted;

  final String? backendName;
  final String? selectedEndpoint;
  final String? activeEndpoint;
  final int? sampleRateHz;
  final int? bitDepth;
  final double? latencyMs;
  final String? errorMessage;
  final DateTime? checkedAt;

  bool get isReadyNotProcessing =>
      status == EngineProcessingStatus.ready && !processingVerified;

  bool get isConfigured =>
      configurationAccepted &&
      processingScope == AudioProcessingScope.configurationOnly;

  /// A single safe sentence for dashboard summaries.
  String get summary {
    if (errorMessage != null) {
      return 'The Rust core could not be reached.';
    }
    if (!coreReachable) {
      return 'Core status has not been verified.';
    }
    if (processingVerified) {
      return 'Audio processing is verified.';
    }
    return 'Configuration is available. Audio processing is not verified.';
  }
}
