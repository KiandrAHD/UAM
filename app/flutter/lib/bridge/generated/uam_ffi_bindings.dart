// Low-level C ABI binding shim for the UAM Rust core.
//
// Phase 0 uses a deliberately small hand-maintained C ABI instead of generated
// bindings. This file is the single low-level boundary: application code must
// import `bridge/rust_api.dart`, never this file. If the ABI changes, update
// this shim and bump `uam_domain::BRIDGE_ABI_VERSION` together.
//
// No audio buffers cross this boundary. Audio callback stays inside Rust; these
// functions expose control-path JSON envelopes only.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();

typedef _GetEngineInfoNative = Pointer<Utf8> Function();
typedef _GetEngineInfoDart = Pointer<Utf8> Function();

typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _StringFreeDart = void Function(Pointer<Utf8>);
typedef _EngineCreateNative = Pointer<Utf8> Function();
typedef _EngineCreateDart = Pointer<Utf8> Function();
typedef _EngineHandleNative = Pointer<Utf8> Function(Uint64);
typedef _EngineHandleDart = Pointer<Utf8> Function(int);
typedef _EngineStringNative = Pointer<Utf8> Function(Uint64, Pointer<Utf8>);
typedef _EngineStringDart = Pointer<Utf8> Function(int, Pointer<Utf8>);
typedef _EngineBoolNative = Pointer<Utf8> Function(Uint64, Uint8);
typedef _EngineBoolDart = Pointer<Utf8> Function(int, int);

/// Thin typed wrapper around exported `uam_ffi` symbols.
final class UamFfiBindings {
  /// Binds to an already-open native library.
  ///
  /// Throws [ArgumentError] when a required symbol is missing.
  UamFfiBindings(DynamicLibrary library)
    : _abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
        'uam_abi_version',
      ),
      _getEngineInfo = library
          .lookupFunction<_GetEngineInfoNative, _GetEngineInfoDart>(
            'uam_get_engine_info',
          ),
      _stringFree = library.lookupFunction<_StringFreeNative, _StringFreeDart>(
        'uam_string_free',
      ),
      _engineCreate = library
          .lookupFunction<_EngineCreateNative, _EngineCreateDart>(
            'uam_audio_engine_create',
          ),
      _engineStatus = library
          .lookupFunction<_EngineHandleNative, _EngineHandleDart>(
            'uam_audio_engine_status',
          ),
      _engineEnumerate = library
          .lookupFunction<_EngineHandleNative, _EngineHandleDart>(
            'uam_audio_engine_enumerate',
          ),
      _engineDefaultDevice = library
          .lookupFunction<_EngineHandleNative, _EngineHandleDart>(
            'uam_audio_engine_default_device',
          ),
      _engineSelectDevice = library
          .lookupFunction<_EngineStringNative, _EngineStringDart>(
            'uam_audio_engine_select_device',
          ),
      _engineConfigure = library
          .lookupFunction<_EngineStringNative, _EngineStringDart>(
            'uam_audio_engine_configure',
          ),
      _engineStart = library
          .lookupFunction<_EngineHandleNative, _EngineHandleDart>(
            'uam_audio_engine_start',
          ),
      _engineStop = library
          .lookupFunction<_EngineHandleNative, _EngineHandleDart>(
            'uam_audio_engine_stop',
          ),
      _engineSetBypass = library
          .lookupFunction<_EngineBoolNative, _EngineBoolDart>(
            'uam_audio_engine_set_bypass',
          ),
      _engineSetTestTone = library
          .lookupFunction<_EngineStringNative, _EngineStringDart>(
            'uam_audio_engine_set_test_tone',
          ),
      _engineDeviceEvents = library
          .lookupFunction<_EngineHandleNative, _EngineHandleDart>(
            'uam_audio_engine_device_events',
          ),
      _engineSubscribe = library
          .lookupFunction<_EngineHandleNative, _EngineHandleDart>(
            'uam_audio_engine_subscribe',
          );

  final _AbiVersionDart _abiVersion;
  final _GetEngineInfoDart _getEngineInfo;
  final _StringFreeDart _stringFree;
  final _EngineCreateDart _engineCreate;
  final _EngineHandleDart _engineStatus;
  final _EngineHandleDart _engineEnumerate;
  final _EngineHandleDart _engineDefaultDevice;
  final _EngineStringDart _engineSelectDevice;
  final _EngineStringDart _engineConfigure;
  final _EngineHandleDart _engineStart;
  final _EngineHandleDart _engineStop;
  final _EngineBoolDart _engineSetBypass;
  final _EngineStringDart _engineSetTestTone;
  final _EngineHandleDart _engineDeviceEvents;
  final _EngineHandleDart _engineSubscribe;

  /// C ABI contract version compiled into the native library.
  int abiVersion() => _abiVersion();

  /// Returns the engine-info JSON and frees the native allocation.
  ///
  /// Throws [StateError] when the native library returns a null pointer.
  String getEngineInfoJson() {
    final pointer = _getEngineInfo();
    if (pointer == nullptr) {
      throw StateError('uam_get_engine_info returned a null pointer');
    }
    try {
      return pointer.toDartString();
    } finally {
      _stringFree(pointer);
    }
  }

  /// Read one engine envelope and release its native allocation.
  String _envelope(Pointer<Utf8> pointer) {
    if (pointer == nullptr) {
      throw StateError('uam_audio_engine call returned a null pointer');
    }
    try {
      return pointer.toDartString();
    } finally {
      _stringFree(pointer);
    }
  }

  /// Create an engine and return its handle envelope.
  String engineCreate() => _envelope(_engineCreate());

  /// Read a complete status snapshot envelope.
  String engineStatus(int handle) => _envelope(_engineStatus(handle));

  /// Enumerate active render endpoints.
  String engineEnumerate(int handle) => _envelope(_engineEnumerate(handle));

  /// Read the current default render endpoint identifier.
  String engineDefaultDevice(int handle) =>
      _envelope(_engineDefaultDevice(handle));

  /// Select an endpoint. [deviceId] is an endpoint identifier from enumeration.
  String engineSelectDevice(int handle, String deviceId) {
    return using(
      (arena) => _envelope(
        _engineSelectDevice(handle, deviceId.toNativeUtf8(allocator: arena)),
      ),
    );
  }

  /// Apply a `DspRequest` JSON configuration.
  String engineConfigure(int handle, String requestJson) {
    return using(
      (arena) => _envelope(
        _engineConfigure(handle, requestJson.toNativeUtf8(allocator: arena)),
      ),
    );
  }

  /// Start the render stream.
  String engineStart(int handle) => _envelope(_engineStart(handle));

  /// Stop the render stream.
  String engineStop(int handle) => _envelope(_engineStop(handle));

  /// Request a bypass change.
  String engineSetBypass(int handle, bool bypassed) =>
      _envelope(_engineSetBypass(handle, bypassed ? 1 : 0));

  /// Enable ([toneJson] non-null) or disable the diagnostic test tone.
  String engineSetTestTone(int handle, {String? toneJson}) {
    return using(
      (arena) => _envelope(
        _engineSetTestTone(
          handle,
          toneJson == null
              ? nullptr
              : toneJson.toNativeUtf8(allocator: arena),
        ),
      ),
    );
  }

  /// Drain endpoint change notifications.
  String engineDeviceEvents(int handle) =>
      _envelope(_engineDeviceEvents(handle));

  /// Ensure endpoint notifications are subscribed.
  String engineSubscribe(int handle) => _envelope(_engineSubscribe(handle));
}
