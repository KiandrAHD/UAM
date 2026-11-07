import 'package:flutter/foundation.dart' hide DiagnosticLevel;

import '../../../bridge/rust_api.dart';
import '../../../core/result/result.dart';
import '../../../platform/audio/audio_processing_scope.dart';
import '../../../shared/models/engine_runtime_state.dart';
import '../domain/diagnostic_entry.dart';

/// Loads engine metadata and exposes an honest runtime snapshot.
///
/// The Phase 1 bridge is read-only. It can report that the core is reachable,
/// but it cannot report a live audio stream, so [EngineRuntimeState.processingVerified]
/// is always false.
final class EngineController extends ChangeNotifier {
  EngineController(this._gateway);

  final EngineInfoGateway _gateway;
  final List<DiagnosticEntry> _entries = <DiagnosticEntry>[];
  EngineRuntimeState _state = EngineRuntimeState.unknown;
  bool _loading = false;
  bool _hasLoaded = false;

  EngineRuntimeState get state => _state;
  bool get isLoading => _loading;
  bool get hasLoaded => _hasLoaded;
  List<DiagnosticEntry> get entries =>
      List<DiagnosticEntry>.unmodifiable(_entries);

  Future<void> load() async {
    _loading = true;
    _add(
      DiagnosticLevel.info,
      'Requesting engine information from the Rust core.',
    );
    notifyListeners();
    final Result<EngineInfo> result = await _gateway.loadEngineInfo();
    _loading = false;
    _hasLoaded = true;
    switch (result) {
      case Success<EngineInfo>(value: final info):
        final scope =
            AudioProcessingScope.tryParse(info.audioProcessingScope) ??
            AudioProcessingScope.configurationOnly;
        _state = EngineRuntimeState(
          status: EngineProcessingStatus.ready,
          coreReachable: true,
          coreVersion: info.coreEngineVersion,
          bridgeAbiVersion: info.bridgeAbiVersion,
          processingScope: scope,
          processingVerified: false,
          configurationAccepted: false,
          checkedAt: DateTime.now(),
        );
        _add(
          DiagnosticLevel.info,
          'Rust core ${info.coreEngineVersion} loaded via bridge ABI '
          '${info.bridgeAbiVersion}.',
        );
        if (scope != AudioProcessingScope.configurationOnly) {
          _add(
            DiagnosticLevel.notice,
            'Core reports ${scope.label}; no live stream verification exists in '
            'this build.',
          );
        }
      case Failure<EngineInfo>(failure: final failure):
        _state = EngineRuntimeState(
          status: EngineProcessingStatus.error,
          coreReachable: false,
          errorMessage: failure.message,
          checkedAt: DateTime.now(),
        );
        _add(DiagnosticLevel.error, failure.message);
    }
    notifyListeners();
  }

  /// Record an application event in the shared diagnostic log.
  void addEvent(DiagnosticLevel level, String message) {
    _add(level, message);
    notifyListeners();
  }

  void _add(DiagnosticLevel level, String message) {
    _entries.add(
      DiagnosticEntry(
        timestamp: DateTime.now(),
        level: level,
        message: message,
      ),
    );
  }
}
