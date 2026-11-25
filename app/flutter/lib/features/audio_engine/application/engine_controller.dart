import 'dart:async';

import 'package:flutter/foundation.dart' hide DiagnosticLevel;

import '../../../bridge/rust_api.dart';
import '../../../core/result/result.dart';
import '../../../platform/audio/audio_engine_gateway.dart';
import '../../../platform/audio/audio_processing_scope.dart';
import '../../../shared/models/engine_runtime_state.dart';
import '../../../shared/models/equalizer_configuration.dart';
import '../domain/diagnostic_entry.dart';

/// Drives the native audio engine, surfaces real status, and keeps a diagnostic
/// log.
///
/// Metadata (`uam_get_engine_info`) and the live audio engine are separate
/// gateways. The controller merges both: the metadata gateway describes the
/// compiled core, the audio gateway reports the actual render stream. It never
/// fabricates status: `processingVerified` is only true when the core reports a
/// running stream that has rendered at least one callback.
final class EngineController extends ChangeNotifier {
  EngineController(this._infoGateway, this._audioGateway)
    : _state = EngineRuntimeState.unknown,
      _backendName = _audioGateway.backendName;

  final EngineInfoGateway _infoGateway;
  final AudioEngineGateway _audioGateway;
  final List<DiagnosticEntry> _entries = <DiagnosticEntry>[];
  EngineRuntimeState _state;
  String _backendName;
  bool _loading = false;
  bool _hasLoaded = false;
  EqualizerConfiguration? _pendingConfiguration;
  Timer? _debounce;

  EngineRuntimeState get state => _state;
  bool get isLoading => _loading;
  bool get hasLoaded => _hasLoaded;
  bool get isAvailable => _audioGateway.isAvailable;
  String get backendName => _backendName;
  List<DiagnosticEntry> get entries =>
      List<DiagnosticEntry>.unmodifiable(_entries);

  /// Load core metadata, open the native engine, subscribe to endpoint events,
  /// and read an initial status snapshot.
  Future<void> load() async {
    _loading = true;
    _add(DiagnosticLevel.info, 'Requesting engine status from the Rust core.');
    notifyListeners();

    String? coreVersion;
    int? abiVersion;
    final info = await _infoGateway.loadEngineInfo();
    if (info case Success<EngineInfo>(value: final value)) {
      coreVersion = value.coreEngineVersion;
      abiVersion = value.bridgeAbiVersion;
      _add(
        DiagnosticLevel.info,
        'Rust core v${value.coreEngineVersion} (ABI ${value.bridgeAbiVersion}) '
        'loaded.',
      );
    } else if (info case Failure<EngineInfo>(failure: final failure)) {
      _add(DiagnosticLevel.error, failure.message);
    }

    await _audioGateway.open();
    Result<AudioEngineSnapshot>? result;
    if (_audioGateway.isAvailable) {
      await _audioGateway.subscribe();
      result = await _audioGateway.status();
    }

    _loading = false;
    _hasLoaded = true;
    final merged = result;
    if (merged == null) {
      _state = EngineRuntimeState(
        status: EngineProcessingStatus.unavailable,
        coreReachable: coreVersion != null,
        coreVersion: coreVersion,
        bridgeAbiVersion: abiVersion,
        backendName: _backendName,
        errorMessage:
            _audioGateway.unavailableReason ??
            'The native audio engine is not available in this build.',
        checkedAt: DateTime.now(),
      );
    } else {
      switch (merged) {
        case Success<AudioEngineSnapshot>(value: final snapshot):
          _state = _stateFromSnapshot(
            snapshot,
            coreVersion: coreVersion,
            abiVersion: abiVersion,
          );
        case Failure<AudioEngineSnapshot>(failure: final failure):
          _state = EngineRuntimeState(
            status: EngineProcessingStatus.error,
            coreReachable: coreVersion != null,
            coreVersion: coreVersion,
            bridgeAbiVersion: abiVersion,
            backendName: _backendName,
            errorMessage: failure.message,
            checkedAt: DateTime.now(),
          );
          _add(DiagnosticLevel.error, failure.message);
      }
    }
    notifyListeners();
  }

  /// Poll the native engine status and update UI state.
  ///
  /// Callers may invoke this periodically (for example from the diagnostics
  /// panel) to refresh metrics, detect endpoint changes, and observe recovery.
  Future<void> refresh() async {
    if (!_audioGateway.isAvailable) {
      return;
    }
    await _drainEvents();
    final result = await _audioGateway.status();
    switch (result) {
      case Success<AudioEngineSnapshot>(value: final snapshot):
        _state = _stateFromSnapshot(
          snapshot,
          coreVersion: _state.coreVersion,
          abiVersion: _state.bridgeAbiVersion,
        );
      case Failure<AudioEngineSnapshot>(failure: final failure):
        _add(DiagnosticLevel.error, failure.message);
    }
    notifyListeners();
  }

  /// Apply the current equalizer configuration to the live engine.
  ///
  /// Failed configuration is never hidden: the accepted flag only becomes true
  /// when the core acknowledged the request.
  Future<void> applyEqualizer(EqualizerConfiguration configuration) async {
    if (!_audioGateway.isAvailable) {
      await _storePending(configuration);
      _add(
        DiagnosticLevel.notice,
        'Equalizer change was stored but the audio engine is unavailable.',
      );
      notifyListeners();
      return;
    }
    final request = <String, Object?>{
      'preampDb': configuration.preampDb,
      'bypassed': configuration.bypassed,
      'bands': <Object?>[
        for (final band in configuration.bands)
          <String, Object?>{
            'filterType': band.filterType.wireName,
            'frequencyHz': band.frequencyHz,
            'gainDb': band.gainDb,
            'q': band.q,
          },
      ],
      'limiter': null,
    };
    final result = await _audioGateway.configure(request);
    switch (result) {
      case Success<void>():
        _state = _state.copyWith(
          configurationAccepted: true,
          bypassed: configuration.bypassed,
        );
        _pendingConfiguration = null;
        _add(DiagnosticLevel.info, 'Equalizer configuration applied.');
      case Failure<void>(failure: final failure):
        _state = _state.copyWith(errorMessage: failure.message);
        _add(DiagnosticLevel.error, failure.message);
    }
    notifyListeners();
  }

  /// Debounced [applyEqualizer] used while a slider is being dragged.
  void scheduleEqualizer(EqualizerConfiguration configuration) {
    _pendingConfiguration = configuration;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      final pending = _pendingConfiguration;
      if (pending != null) {
        unawaited(applyEqualizer(pending));
      }
    });
  }

  /// Send a bypass change without stopping the stream.
  Future<void> setBypass(bool bypassed) async {
    if (!_audioGateway.isAvailable) {
      return;
    }
    final result = await _audioGateway.setBypass(bypassed);
    if (result case Failure<void>(failure: final failure)) {
      _add(DiagnosticLevel.error, failure.message);
    } else {
      _state = _state.copyWith(bypassed: bypassed);
      _add(
        DiagnosticLevel.info,
        bypassed ? 'Bypass enabled.' : 'Bypass disabled.',
      );
    }
    notifyListeners();
  }

  /// Start the render stream on the selected endpoint.
  Future<void> startStream() async {
    if (!_audioGateway.isAvailable) {
      return;
    }
    final result = await _audioGateway.start();
    _maybeLog(result, 'Render stream started.');
    await refresh();
  }

  /// Stop the render stream.
  Future<void> stopStream() async {
    if (!_audioGateway.isAvailable) {
      return;
    }
    final result = await _audioGateway.stop();
    _maybeLog(result, 'Render stream stopped.');
    await refresh();
  }

  /// Enable or disable the diagnostic test tone.
  Future<void> setTestTone({required bool enabled}) async {
    if (!_audioGateway.isAvailable) {
      return;
    }
    final result = await _audioGateway.setTestTone(enabled: enabled);
    _maybeLog(
      result,
      enabled
          ? 'Diagnostic test tone enabled.'
          : 'Diagnostic test tone disabled.',
    );
    await refresh();
  }

  /// Append a session diagnostic entry.
  void addEvent(DiagnosticLevel level, String message) {
    _add(level, message);
    notifyListeners();
  }

  void _maybeLog(Result<void> result, String successMessage) {
    switch (result) {
      case Success<void>():
        _add(DiagnosticLevel.info, successMessage);
      case Failure<void>(failure: final failure):
        _add(DiagnosticLevel.error, failure.message);
    }
    notifyListeners();
  }

  Future<void> _drainEvents() async {
    final result = await _audioGateway.drainDeviceEvents();
    if (result case Success<int>(value: final count)) {
      if (count > 0) {
        _add(
          DiagnosticLevel.notice,
          '$count endpoint change event(s) received from the audio backend.',
        );
      }
    }
  }

  Future<void> _storePending(EqualizerConfiguration configuration) async {
    _pendingConfiguration = configuration;
    _state = _state.copyWith(configurationAccepted: false);
  }

  EngineRuntimeState _stateFromSnapshot(
    AudioEngineSnapshot snapshot, {
    String? coreVersion,
    int? abiVersion,
  }) {
    final scope =
        AudioProcessingScope.tryParse(snapshot.scope) ??
        AudioProcessingScope.configurationOnly;
    final metrics = snapshot.metrics;
    final processingVerified =
        snapshot.running && (metrics?.hasStream ?? false);
    _backendName = snapshot.backend;
    if (scope == AudioProcessingScope.appOwnedStream) {
      _add(
        DiagnosticLevel.info,
        'Stream attached on ${snapshot.deviceName ?? 'selected endpoint'}.',
      );
    }
    return EngineRuntimeState(
      status: _statusFor(snapshot),
      coreReachable: true,
      coreVersion: coreVersion,
      bridgeAbiVersion: abiVersion,
      processingScope: scope,
      processingVerified: processingVerified,
      configurationAccepted: metrics != null,
      bypassed: snapshot.bypassed,
      testToneEnabled: snapshot.testToneEnabled,
      backendName: snapshot.backend,
      backendDescription: snapshot.backendDescription,
      selectedEndpoint: snapshot.deviceName,
      activeEndpoint: snapshot.running ? snapshot.deviceName : null,
      sampleRateHz: snapshot.format?.sampleRateHz,
      bitDepth: snapshot.format?.containerBits,
      latencyMs: metrics?.streamLatencyMs,
      bufferFrames: metrics?.bufferFrames,
      metrics: metrics,
      errorMessage: snapshot.lastError?.message,
      checkedAt: DateTime.now(),
    );
  }

  static EngineProcessingStatus _statusFor(AudioEngineSnapshot snapshot) {
    if (snapshot.lastError != null) {
      return EngineProcessingStatus.error;
    }
    return switch (snapshot.state) {
      'running' => EngineProcessingStatus.processing,
      'starting' || 'recovering' => EngineProcessingStatus.standby,
      'ready' || 'configured' => EngineProcessingStatus.ready,
      'failed' => EngineProcessingStatus.error,
      _ => EngineProcessingStatus.unavailable,
    };
  }

  void _add(DiagnosticLevel level, String message) {
    _entries.add(
      DiagnosticEntry(
        timestamp: DateTime.now(),
        level: level,
        message: message,
      ),
    );
    if (_entries.length > 500) {
      _entries.removeRange(0, _entries.length - 500);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
