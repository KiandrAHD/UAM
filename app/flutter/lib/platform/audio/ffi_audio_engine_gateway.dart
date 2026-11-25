import 'dart:convert';
import 'dart:ffi';

import '../../bridge/generated/uam_ffi_bindings.dart';
import '../../core/errors/uam_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../core/utils/rust_library_locator.dart';
import 'audio_engine_gateway.dart';

/// Real [AudioEngineGateway] over the `uam_ffi` C ABI.
///
/// The opaque engine handle is owned by Rust; this class only stores the `u64`
/// returned by `uam_audio_engine_create`. Every call returns one JSON envelope
/// that is decoded and freed immediately, so no native allocation outlives a
/// call and no audio buffer ever crosses this boundary.
///
/// None of these methods run on the audio thread; they are ordinary control-path
/// calls driven by the Flutter isolate.
final class FfiAudioEngineGateway implements AudioEngineGateway {
  FfiAudioEngineGateway({this.libraryPath});

  /// Optional explicit native library path (tests, packaged builds).
  final String? libraryPath;

  UamFfiBindings? _bindings;
  int? _handle;
  String? _unavailableReason;
  String _backendName = 'unavailable';

  @override
  bool get isAvailable => _bindings != null && _handle != null;

  @override
  String? get unavailableReason => _unavailableReason;

  @override
  String get backendName => _backendName;

  @override
  Future<void> open() async {
    if (_handle != null) {
      return;
    }
    try {
      final bindings = _bindings ??= _openLibrary();
      final decoded = decodeEnvelope<int>(bindings.engineCreate(), (data) {
        final map = data! as Map<String, Object?>;
        return (map['handle']! as num).toInt();
      });
      if (decoded case Success<int>(value: final handle)) {
        _handle = handle;
        _unavailableReason = null;
        AppLogger.info('Audio engine created with handle $handle');
      } else if (decoded case Failure<int>(failure: final failure)) {
        _unavailableReason = failure.message;
        AppLogger.error(
          'Audio engine could not be created: ${failure.message}',
        );
      }
    } on _BridgeUnavailable catch (error) {
      _unavailableReason = error.message;
      AppLogger.warning(error.message);
    } on ArgumentError catch (error) {
      _unavailableReason =
          'The native library is missing an expected UAM audio symbol.';
      AppLogger.error('Native audio symbol lookup failed: ${error.message}');
    }
  }

  @override
  Future<void> close() async {
    final bindings = _bindings;
    final handle = _handle;
    _handle = null;
    if (bindings == null || handle == null) {
      return;
    }
    // Destroy stops the stream and joins the producer thread inside the core.
    try {
      decodeEnvelope<void>(bindings.engineDestroy(handle), (_) {});
    } on StateError {
      // The engine is already gone; nothing else to release.
    }
  }

  @override
  Future<Result<AudioEngineSnapshot>> status() {
    return _call('status', (bindings, handle) {
      final snapshot = decodeEnvelope<AudioEngineSnapshot>(
        bindings.engineStatus(handle),
        (data) => AudioEngineSnapshot.fromJson(data! as Map<String, Object?>),
      );
      if (snapshot case Success<AudioEngineSnapshot>(value: final value)) {
        _backendName = value.backend;
      }
      return snapshot;
    });
  }

  @override
  Future<Result<AudioEndpointList>> enumerate() {
    return _call(
      'enumerate',
      (bindings, handle) => decodeEnvelope<AudioEndpointList>(
        bindings.engineEnumerate(handle),
        (data) => AudioEndpointList.fromJson(data! as Map<String, Object?>),
      ),
    );
  }

  @override
  Future<Result<AudioStreamFormat>> selectDevice(String deviceId) {
    return _call(
      'selectDevice',
      (bindings, handle) => decodeEnvelope<AudioStreamFormat>(
        bindings.engineSelectDevice(handle, deviceId),
        (data) {
          final map = data! as Map<String, Object?>;
          return AudioStreamFormat.fromJson(
            map['format']! as Map<String, Object?>,
          );
        },
      ),
    );
  }

  @override
  Future<Result<void>> configure(Map<String, Object?> request) {
    final encoded = _encode(request);
    if (encoded == null) {
      return Future<Result<void>>.value(_encodeFailure);
    }
    return _call(
      'configure',
      (bindings, handle) => decodeEnvelope<void>(
        bindings.engineConfigure(handle, encoded),
        (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> start() {
    return _call(
      'start',
      (bindings, handle) =>
          decodeEnvelope<void>(bindings.engineStart(handle), (_) {}),
    );
  }

  @override
  Future<Result<void>> stop() {
    return _call(
      'stop',
      (bindings, handle) =>
          decodeEnvelope<void>(bindings.engineStop(handle), (_) {}),
    );
  }

  @override
  Future<Result<void>> setBypass(bool bypassed) {
    return _call(
      'setBypass',
      (bindings, handle) => decodeEnvelope<void>(
        bindings.engineSetBypass(handle, bypassed),
        (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> setTestTone({
    required bool enabled,
    double frequencyHz = 1000,
    double levelDb = -20,
  }) {
    final toneJson = enabled
        ? _encode({'frequencyHz': frequencyHz, 'levelDb': levelDb})
        : null;
    if (enabled && toneJson == null) {
      return Future<Result<void>>.value(_encodeFailure);
    }
    return _call(
      'setTestTone',
      (bindings, handle) => decodeEnvelope<void>(
        bindings.engineSetTestTone(handle, toneJson: toneJson),
        (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> subscribe() {
    return _call(
      'subscribe',
      (bindings, handle) =>
          decodeEnvelope<void>(bindings.engineSubscribe(handle), (_) {}),
    );
  }

  @override
  Future<Result<int>> drainDeviceEvents() {
    return _call(
      'drainDeviceEvents',
      (bindings, handle) =>
          decodeEnvelope<int>(bindings.engineDeviceEvents(handle), (data) {
            final map = data! as Map<String, Object?>;
            final events = map['events'];
            return events is List<Object?> ? events.length : 0;
          }),
    );
  }

  Future<Result<T>> _call<T>(
    String operation,
    Result<T> Function(UamFfiBindings bindings, int handle) body,
  ) async {
    final bindings = _bindings;
    final handle = _handle;
    if (bindings == null || handle == null) {
      return Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeUnavailable,
          message:
              _unavailableReason ??
              'The UAM audio engine is not available in this build.',
        ),
      );
    }
    try {
      return body(bindings, handle);
    } on StateError catch (error) {
      AppLogger.error(
        'Audio bridge call $operation returned no payload: ${error.message}',
      );
      return const Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeProtocol,
          message: 'The audio core returned no response.',
        ),
      );
    }
  }

  static String? _encode(Map<String, Object?> value) {
    try {
      return jsonEncode(value);
    } on Object {
      return null;
    }
  }

  UamFfiBindings _openLibrary() {
    final path = RustLibraryLocator.resolve(explicitPath: libraryPath);
    if (path == null) {
      throw const _BridgeUnavailable(
        'The UAM Rust core library was not found. Build it with '
        'scripts/build/build_rust.ps1 and retry.',
      );
    }
    try {
      final library = DynamicLibrary.open(path);
      return UamFfiBindings(library);
    } on ArgumentError {
      throw const _BridgeUnavailable(
        'The UAM Rust core library could not be loaded by the operating system.',
      );
    }
  }

  static const Result<void> _encodeFailure = Result<void>.failure(
    UamFailure(
      code: UamFailureCode.invalidResponse,
      message: 'The audio configuration could not be encoded.',
    ),
  );
}

final class _BridgeUnavailable implements Exception {
  const _BridgeUnavailable(this.message);

  final String message;
}
