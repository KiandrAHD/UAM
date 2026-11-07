import 'dart:convert';
import 'dart:ffi';

import '../core/constants/app_constants.dart';
import '../core/errors/uam_failure.dart';
import '../core/logging/app_logger.dart';
import '../core/result/result.dart';
import '../core/utils/rust_library_locator.dart';
import 'generated/uam_ffi_bindings.dart';

/// Control-path interface used by the application shell.
///
/// Tests may provide a deterministic implementation without touching native
/// code. Production code uses [RustApi].
abstract interface class EngineInfoGateway {
  /// Loads engine metadata from the Rust core.
  Future<Result<EngineInfo>> loadEngineInfo();
}

/// Structured metadata returned by `uam_get_engine_info`.
final class EngineInfo {
  const EngineInfo({
    required this.productName,
    required this.coreEngineVersion,
    required this.bridgeAbiVersion,
    required this.rustImplementationStatus,
    required this.supportedPrototypeFunctionality,
    required this.audioProcessingScope,
  });

  /// Parse and type-check the bridge payload.
  ///
  /// Throws [FormatException] when a required field is missing or has the wrong
  /// type. Callers map that to an application failure.
  factory EngineInfo.fromJson(Map<String, Object?> json) {
    String requireString(String key) {
      final value = json[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
      throw FormatException('Missing or invalid string field "$key"');
    }

    int requireInt(String key) {
      final value = json[key];
      if (value is int) {
        return value;
      }
      throw FormatException('Missing or invalid integer field "$key"');
    }

    final rawFeatures = json['supportedPrototypeFunctionality'];
    if (rawFeatures is! List<Object?>) {
      throw const FormatException(
        'Missing or invalid supportedPrototypeFunctionality field',
      );
    }
    final features = <String>[];
    for (final feature in rawFeatures) {
      if (feature is! String || feature.isEmpty) {
        throw const FormatException(
          'supportedPrototypeFunctionality must contain strings',
        );
      }
      features.add(feature);
    }

    return EngineInfo(
      productName: requireString('productName'),
      coreEngineVersion: requireString('coreEngineVersion'),
      bridgeAbiVersion: requireInt('bridgeAbiVersion'),
      rustImplementationStatus: requireString('rustImplementationStatus'),
      supportedPrototypeFunctionality: List.unmodifiable(features),
      audioProcessingScope: requireString('audioProcessingScope'),
    );
  }

  /// Human-readable product name.
  final String productName;

  /// Rust core version derived from Cargo package metadata.
  final String coreEngineVersion;

  /// C ABI contract version compiled into the native library.
  final int bridgeAbiVersion;

  /// Honest implementation stage label from Rust.
  final String rustImplementationStatus;

  /// Capabilities compiled into this core build.
  final List<String> supportedPrototypeFunctionality;

  /// Processing scope reported by the core.
  final String audioProcessingScope;
}

/// Production bridge implementation using a small C ABI over Dart FFI.
///
/// The native library is loaded lazily. No real-time audio buffer is exposed
/// through this class.
final class RustApi implements EngineInfoGateway {
  RustApi({this.libraryPath});

  /// Optional explicit library location for tests and packaged desktop builds.
  final String? libraryPath;
  UamFfiBindings? _bindings;

  @override
  Future<Result<EngineInfo>> loadEngineInfo() async {
    try {
      final bindings = _bindings ??= _openLibrary();
      final payload = bindings.getEngineInfoJson();
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return const Result.failure(
          UamFailure(
            code: UamFailureCode.invalidResponse,
            message: 'The Rust core returned an unexpected payload.',
          ),
        );
      }

      final info = EngineInfo.fromJson(decoded);
      if (info.bridgeAbiVersion != AppConstants.expectedBridgeAbiVersion) {
        return Result.failure(
          UamFailure(
            code: UamFailureCode.bridgeProtocol,
            message:
                'The Rust core uses bridge ABI ${info.bridgeAbiVersion}, '
                'but this app expects ${AppConstants.expectedBridgeAbiVersion}.',
          ),
        );
      }
      AppLogger.info(
        'Rust core ${info.coreEngineVersion} loaded via bridge ABI '
        '${info.bridgeAbiVersion}',
      );
      return Result.success(info);
    } on _BridgeUnavailable catch (error) {
      AppLogger.warning(error.message);
      return Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeUnavailable,
          message: error.message,
        ),
      );
    } on FormatException catch (error) {
      AppLogger.error('Bridge payload validation failed: ${error.message}');
      return Result.failure(
        UamFailure(
          code: UamFailureCode.invalidResponse,
          message: 'The Rust core returned a payload this app cannot read.',
          detail: error.message,
        ),
      );
    } on StateError catch (error) {
      AppLogger.error('Bridge call failed: ${error.message}');
      return Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeProtocol,
          message: 'The Rust core call did not return a valid response.',
        ),
      );
    } on ArgumentError catch (error) {
      AppLogger.error('Native symbol lookup failed: ${error.message}');
      return const Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeProtocol,
          message:
              'The native library is missing an expected UAM bridge symbol.',
        ),
      );
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
}

final class _BridgeUnavailable implements Exception {
  const _BridgeUnavailable(this.message);

  final String message;
}
