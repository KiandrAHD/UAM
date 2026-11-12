import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/uam_app.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/result/result.dart';
import 'package:uam/app/services/uam_services.dart';
import 'package:uam/platform/files/preset_file_gateway.dart';

/// Deterministic engine gateway for widget tests.
final class FakeEngineGateway implements EngineInfoGateway {
  const FakeEngineGateway(this.result);

  final Result<EngineInfo> result;

  @override
  Future<Result<EngineInfo>> loadEngineInfo() async => result;
}

const EngineInfo testEngineInfo = EngineInfo(
  productName: 'Universe Audio Management',
  coreEngineVersion: '0.1.0',
  bridgeAbiVersion: 1,
  rustImplementationStatus: 'prototype',
  supportedPrototypeFunctionality: <String>[
    'bridge.engine_info',
    'dsp.eq.peaking',
    'preset.uam-preset.schema_v1.validate',
  ],
  audioProcessingScope: 'configuration_only',
);

/// Create one in-memory SQLite service bundle for a widget test.
///
/// The bundle is created inside [WidgetTester.runAsync] because creating it
/// touches the real file system (temporary directory + `sqflite` FFI). Once it
/// exists, all repository operations complete synchronously on the test isolate,
/// so the rest of the test can use ordinary `pump`/`pumpAndSettle`.
Future<UamServices> createWidgetTestServices(
  WidgetTester tester, {
  PresetFileGateway? fileGateway,
}) async {
  final services = await tester.runAsync(
    () => UamServices.inMemoryForWidgetTests(fileGateway: fileGateway),
  );
  addTearDown(() => services!.dispose());
  return services!;
}

/// Pump the full application with a fixed logical surface size.
Future<void> pumpUamApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1200),
  Result<EngineInfo>? result,
  UamServices? services,
  PresetFileGateway? fileGateway,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final resolved =
      services ??
      await createWidgetTestServices(tester, fileGateway: fileGateway);
  await tester.pumpWidget(
    UamApp(
      engineInfoGateway: FakeEngineGateway(
        result ?? const Result<EngineInfo>.success(testEngineInfo),
      ),
      services: resolved,
    ),
  );
  await tester.pumpAndSettle();
}
