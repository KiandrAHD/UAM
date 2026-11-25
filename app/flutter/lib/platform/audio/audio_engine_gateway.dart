import 'dart:convert';

import '../../core/errors/uam_failure.dart';
import '../../core/result/result.dart';

/// Wire-level snapshot of one Windows/OS render endpoint.
///
/// Mirrors `uam_audio::device::OutputDevice`. Every field comes from the native
/// backend; nothing here is inferred from a device name.
final class AudioEndpoint {
  const AudioEndpoint({
    required this.id,
    required this.displayName,
    required this.connectionState,
    required this.isDefault,
    this.transport,
    this.formatSummary,
  });

  factory AudioEndpoint.fromJson(Map<String, Object?> json) {
    String string(String key) {
      final value = json[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
      throw FormatException('Missing or invalid string field "$key"');
    }

    final summary = json['formatSummary'];
    return AudioEndpoint(
      id: string('id'),
      displayName: string('displayName'),
      connectionState: string('connectionState'),
      isDefault: json['isDefault'] == true,
      transport: json['transport'] is String
          ? json['transport']! as String
          : null,
      formatSummary: summary is String ? summary : null,
    );
  }

  /// OS endpoint identifier (the WASAPI device id on Windows).
  final String id;
  final String displayName;
  final String connectionState;
  final bool isDefault;
  final String? transport;
  final String? formatSummary;

  bool get isActive => connectionState == 'active';
}

/// One enumeration result from the native backend.
final class AudioEndpointList {
  const AudioEndpointList({
    required this.endpoints,
    required this.succeeded,
    this.defaultId,
    this.reason,
  });

  factory AudioEndpointList.fromJson(Map<String, Object?> json) {
    final raw = json['devices'];
    final endpoints = <AudioEndpoint>[];
    if (raw is List<Object?>) {
      for (final entry in raw) {
        if (entry is Map<String, Object?>) {
          endpoints.add(AudioEndpoint.fromJson(entry));
        }
      }
    }
    return AudioEndpointList(
      endpoints: List<AudioEndpoint>.unmodifiable(endpoints),
      defaultId: json['defaultId'] as String?,
      succeeded: json['enumerationSucceeded'] == true,
      reason: json['reason'] as String?,
    );
  }

  final List<AudioEndpoint> endpoints;
  final String? defaultId;
  final bool succeeded;
  final String? reason;

  bool get isEmpty => endpoints.isEmpty;

  AudioEndpoint? byId(String? id) {
    if (id == null) {
      return null;
    }
    for (final endpoint in endpoints) {
      if (endpoint.id == id) {
        return endpoint;
      }
    }
    return null;
  }
}

/// Resolved stream format reported by the backend for the selected endpoint.
final class AudioStreamFormat {
  const AudioStreamFormat({
    required this.sampleRateHz,
    required this.channels,
    required this.encoding,
    required this.containerBits,
    required this.validBits,
    required this.summary,
  });

  factory AudioStreamFormat.fromJson(Map<String, Object?> json) {
    return AudioStreamFormat(
      sampleRateHz: (json['sampleRateHz'] as num?)?.toInt() ?? 0,
      channels: (json['channels'] as num?)?.toInt() ?? 0,
      encoding: json['encoding'] as String? ?? 'unknown',
      containerBits: (json['containerBits'] as num?)?.toInt() ?? 0,
      validBits: (json['validBits'] as num?)?.toInt() ?? 0,
      summary: json['summary'] as String? ?? 'unknown',
    );
  }

  final int sampleRateHz;
  final int channels;
  final String encoding;
  final int containerBits;
  final int validBits;
  final String summary;
}

/// RT-safe counters reported by the audio thread.
final class AudioMetrics {
  const AudioMetrics({
    required this.framesProcessed,
    required this.callbacks,
    required this.callbackAverageUs,
    required this.callbackMaxUs,
    required this.callbackP99Us,
    required this.peakInputDbfs,
    required this.peakOutputDbfs,
    required this.limiterReductionDb,
    required this.clippedSamples,
    required this.nonFiniteSamples,
    required this.glitches,
    required this.underruns,
    required this.deadlineMisses,
    required this.streamRestarts,
    required this.deviceDisconnects,
    required this.backendErrors,
    required this.sampleRateHz,
    required this.channels,
    required this.bufferFrames,
    required this.streamLatencyMs,
    required this.bufferDurationMs,
    required this.averageLoad,
  });

  factory AudioMetrics.fromJson(Map<String, Object?> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    int integer(String key) => (json[key] as num?)?.toInt() ?? 0;
    final sampleRate = integer('sampleRateHz');
    final bufferFrames = integer('bufferFrames');
    final bufferDurationMs = sampleRate == 0
        ? 0.0
        : bufferFrames / sampleRate * 1000.0;
    final callbackAverageUs = number('callbackAverageUs');
    return AudioMetrics(
      framesProcessed: integer('framesProcessed'),
      callbacks: integer('callbacks'),
      callbackAverageUs: callbackAverageUs,
      callbackMaxUs: number('callbackMaxUs'),
      callbackP99Us: number('callbackP99Us'),
      peakInputDbfs: number('peakInputDbfs'),
      peakOutputDbfs: number('peakOutputDbfs'),
      limiterReductionDb: number('limiterReductionDb'),
      clippedSamples: integer('clippedOutputSamples'),
      nonFiniteSamples: integer('nonFiniteOutputSamples'),
      glitches: integer('glitches'),
      underruns: integer('underruns'),
      deadlineMisses: integer('deadlineMisses'),
      streamRestarts: integer('streamRestarts'),
      deviceDisconnects: integer('deviceDisconnects'),
      backendErrors: integer('backendErrors'),
      sampleRateHz: sampleRate,
      channels: integer('channels'),
      bufferFrames: bufferFrames,
      streamLatencyMs: number('streamLatencyMs'),
      bufferDurationMs: bufferDurationMs,
      averageLoad: bufferDurationMs == 0
          ? 0
          : callbackAverageUs / (bufferDurationMs * 1000.0),
    );
  }

  final int framesProcessed;
  final int callbacks;
  final double callbackAverageUs;
  final double callbackMaxUs;
  final double callbackP99Us;
  final double peakInputDbfs;
  final double peakOutputDbfs;
  final double limiterReductionDb;
  final int clippedSamples;
  final int nonFiniteSamples;
  final int glitches;
  final int underruns;
  final int deadlineMisses;
  final int streamRestarts;
  final int deviceDisconnects;
  final int backendErrors;
  final int sampleRateHz;
  final int channels;
  final int bufferFrames;
  final double streamLatencyMs;
  final double bufferDurationMs;
  final double averageLoad;

  /// Callback duration relative to the buffer period, as a percentage.
  double get loadPercent => averageLoad * 100.0;

  bool get hasStream => callbacks > 0 || framesProcessed > 0;
}

/// Plain model of the engine status envelope.
final class AudioEngineSnapshot {
  const AudioEngineSnapshot({
    required this.state,
    required this.scope,
    required this.backend,
    required this.backendDescription,
    required this.bypassed,
    required this.testToneEnabled,
    required this.deviceId,
    required this.deviceName,
    required this.format,
    required this.metrics,
    required this.lastError,
  });

  factory AudioEngineSnapshot.fromJson(Map<String, Object?> json) {
    final format = json['format'];
    final error = json['lastError'];
    return AudioEngineSnapshot(
      state: json['state'] as String? ?? 'failed',
      scope: json['scope'] as String? ?? 'configuration_only',
      backend: json['backend'] as String? ?? 'unknown',
      backendDescription: json['backendDescription'] as String? ?? '',
      bypassed: json['bypassed'] == true,
      testToneEnabled: json['testToneEnabled'] == true,
      deviceId: json['deviceId'] as String?,
      deviceName: json['deviceName'] as String?,
      format: format is Map<String, Object?>
          ? AudioStreamFormat.fromJson(format)
          : null,
      metrics: json['metrics'] is Map<String, Object?>
          ? AudioMetrics.fromJson(json['metrics']! as Map<String, Object?>)
          : null,
      lastError: error is Map<String, Object?>
          ? AudioEngineError(
              code: error['code'] as String? ?? 'backend_error',
              message: error['message'] as String? ?? 'unknown error',
            )
          : null,
    );
  }

  final String state;
  final String scope;
  final String backend;
  final String backendDescription;
  final bool bypassed;
  final bool testToneEnabled;
  final String? deviceId;
  final String? deviceName;
  final AudioStreamFormat? format;
  final AudioMetrics? metrics;
  final AudioEngineError? lastError;

  bool get running => state == 'running';
}

/// A typed error raised by the native core.
final class AudioEngineError {
  const AudioEngineError({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Control-path boundary between Flutter and the Rust audio engine.
///
/// The real implementation talks over FFI to `uam_audio::engine::AudioEngine`.
/// Tests inject a deterministic fake. No audio buffer ever crosses this
/// boundary: only JSON status snapshots and configuration requests.
abstract interface class AudioEngineGateway {
  /// Whether the native core could be loaded at all.
  bool get isAvailable;

  /// A human-readable reason when [isAvailable] is false.
  String? get unavailableReason;

  /// Backend identifier reported by the core (e.g. `wasapi-shared`).
  String get backendName;

  /// Create the native engine instance. Safe to call once.
  Future<void> open();

  /// Tear down the native engine instance.
  Future<void> close();

  /// Read a status snapshot.
  Future<Result<AudioEngineSnapshot>> status();

  /// Enumerate output endpoints.
  Future<Result<AudioEndpointList>> enumerate();

  /// Select a render endpoint and resolve its format.
  Future<Result<AudioStreamFormat>> selectDevice(String deviceId);

  /// Apply a full DSP configuration (preamp, bands, bypass, limiter).
  Future<Result<void>> configure(Map<String, Object?> request);

  /// Start the render stream.
  Future<Result<void>> start();

  /// Stop the render stream.
  Future<Result<void>> stop();

  /// Request a bypass change.
  Future<Result<void>> setBypass(bool bypassed);

  /// Enable or disable the diagnostic test tone.
  Future<Result<void>> setTestTone({
    required bool enabled,
    double frequencyHz = 1000,
    double levelDb = -20,
  });

  /// Ensure endpoint change notifications are subscribed.
  Future<Result<void>> subscribe();

  /// Drain pending endpoint change notifications.
  Future<Result<int>> drainDeviceEvents();
}

/// Decode the JSON envelope shared by every engine FFI call.
Result<T> decodeEnvelope<T>(String payload, T Function(Object? data) convert) {
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException catch (error) {
    return Result.failure(
      UamFailure(
        code: UamFailureCode.invalidResponse,
        message: 'The audio core returned a payload this app cannot read.',
        detail: error.message,
      ),
    );
  }
  if (decoded is! Map<String, Object?>) {
    return const Result.failure(
      UamFailure(
        code: UamFailureCode.invalidResponse,
        message: 'The audio core returned an unexpected payload.',
      ),
    );
  }
  if (decoded['ok'] != true) {
    final error = decoded['error'];
    final code = error is Map<String, Object?>
        ? (error['code'] as String? ?? 'internal')
        : 'internal';
    final message = error is Map<String, Object?>
        ? (error['message'] as String? ?? 'The audio core reported an error.')
        : 'The audio core reported an error.';
    return Result.failure(
      UamFailure(code: _mapErrorCode(code), message: message, detail: code),
    );
  }
  try {
    return Result.success(convert(decoded['data']));
  } on FormatException catch (error) {
    return Result.failure(
      UamFailure(
        code: UamFailureCode.invalidResponse,
        message: 'The audio core returned a payload this app cannot read.',
        detail: error.message,
      ),
    );
  }
}

UamFailureCode _mapErrorCode(String code) {
  return switch (code) {
    'invalid_argument' => UamFailureCode.invalidResponse,
    'no_output_endpoint' ||
    'invalid_endpoint' ||
    'device_removed' ||
    'device_invalidated' => UamFailureCode.bridgeUnavailable,
    _ => UamFailureCode.bridgeProtocol,
  };
}
