import '../../platform/audio/audio_engine_gateway.dart';
import '../../platform/audio/audio_processing_scope.dart';

/// Verified engine readiness and processing state.
///
/// Desired configuration, core-accepted configuration, and actual audio
/// processing are separate fields. `processingVerified` is only true when the
/// native core reports a running stream that has rendered at least one callback.
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
    this.bypassed = false,
    this.testToneEnabled = false,
    this.backendName,
    this.backendDescription,
    this.selectedEndpoint,
    this.activeEndpoint,
    this.sampleRateHz,
    this.bitDepth,
    this.latencyMs,
    this.bufferFrames,
    this.metrics,
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

  /// Whether processing is currently bypassed in the native core.
  final bool bypassed;

  /// Whether the diagnostic test tone is currently enabled.
  final bool testToneEnabled;

  final String? backendName;
  final String? backendDescription;
  final String? selectedEndpoint;
  final String? activeEndpoint;
  final int? sampleRateHz;
  final int? bitDepth;
  final double? latencyMs;
  final int? bufferFrames;

  /// Live metrics reported by the audio thread, when a stream exists.
  final AudioMetrics? metrics;

  final String? errorMessage;
  final DateTime? checkedAt;

  bool get isReadyNotProcessing =>
      status == EngineProcessingStatus.ready && !processingVerified;

  /// Return a copy with selected fields replaced.
  EngineRuntimeState copyWith({
    EngineProcessingStatus? status,
    bool? coreReachable,
    String? coreVersion,
    int? bridgeAbiVersion,
    AudioProcessingScope? processingScope,
    bool? processingVerified,
    bool? configurationAccepted,
    bool? bypassed,
    bool? testToneEnabled,
    String? backendName,
    String? backendDescription,
    String? selectedEndpoint,
    String? activeEndpoint,
    int? sampleRateHz,
    int? bitDepth,
    double? latencyMs,
    int? bufferFrames,
    AudioMetrics? metrics,
    String? errorMessage,
    DateTime? checkedAt,
  }) {
    return EngineRuntimeState(
      status: status ?? this.status,
      coreReachable: coreReachable ?? this.coreReachable,
      coreVersion: coreVersion ?? this.coreVersion,
      bridgeAbiVersion: bridgeAbiVersion ?? this.bridgeAbiVersion,
      processingScope: processingScope ?? this.processingScope,
      processingVerified: processingVerified ?? this.processingVerified,
      configurationAccepted:
          configurationAccepted ?? this.configurationAccepted,
      bypassed: bypassed ?? this.bypassed,
      testToneEnabled: testToneEnabled ?? this.testToneEnabled,
      backendName: backendName ?? this.backendName,
      backendDescription: backendDescription ?? this.backendDescription,
      selectedEndpoint: selectedEndpoint ?? this.selectedEndpoint,
      activeEndpoint: activeEndpoint ?? this.activeEndpoint,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      bitDepth: bitDepth ?? this.bitDepth,
      latencyMs: latencyMs ?? this.latencyMs,
      bufferFrames: bufferFrames ?? this.bufferFrames,
      metrics: metrics ?? this.metrics,
      errorMessage: errorMessage ?? this.errorMessage,
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }

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
      return 'Audio processing is verified on the selected endpoint.';
    }
    return 'Configuration is available. Audio processing is not verified.';
  }
}
