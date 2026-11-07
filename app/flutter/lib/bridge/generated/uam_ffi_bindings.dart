// Low-level C ABI binding shim for the UAM Rust core.
//
// Phase 0 uses a deliberately small hand-maintained C ABI instead of generated
// bindings. This file is the single low-level boundary: application code must
// import `bridge/rust_api.dart`, never this file. If the ABI changes, update
// this shim and bump `uam_domain::BRIDGE_ABI_VERSION` together.
//
// No audio buffers cross this boundary. It exposes control-path metadata only.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();

typedef _GetEngineInfoNative = Pointer<Utf8> Function();
typedef _GetEngineInfoDart = Pointer<Utf8> Function();

typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _StringFreeDart = void Function(Pointer<Utf8>);

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
      );

  final _AbiVersionDart _abiVersion;
  final _GetEngineInfoDart _getEngineInfo;
  final _StringFreeDart _stringFree;

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
}
