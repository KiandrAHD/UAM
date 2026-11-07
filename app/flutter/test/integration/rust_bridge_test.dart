import 'package:flutter_test/flutter_test.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/result/result.dart';
import 'package:uam/core/utils/rust_library_locator.dart';

void main() {
  final libraryPath = RustLibraryLocator.resolve();

  test(
    'Flutter loads the Rust core and receives structured engine info',
    () async {
      expect(libraryPath, isNotNull);
      final api = RustApi(libraryPath: libraryPath);
      final result = await api.loadEngineInfo();

      expect(
        result,
        isA<Success<EngineInfo>>(),
        reason: result.failureOrNull?.message,
      );
      final info = result.valueOrNull!;
      expect(info.productName, 'Universe Audio Management');
      expect(info.coreEngineVersion, '0.1.0');
      expect(info.bridgeAbiVersion, 1);
      expect(info.rustImplementationStatus, 'prototype');
      expect(info.audioProcessingScope, 'configuration_only');
      expect(info.supportedPrototypeFunctionality, contains('dsp.eq.peaking'));
      expect(
        info.supportedPrototypeFunctionality,
        contains('preset.uam-preset.schema_v1.validate'),
      );
    },
    skip: libraryPath == null
        ? 'Native Rust library not built; run scripts/build/build_rust.ps1'
        : false,
  );
}
