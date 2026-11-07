import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/uam_app.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/result/result.dart';

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

/// Pump the full application with a fixed logical surface size.
Future<void> pumpUamApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1200),
  Result<EngineInfo>? result,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UamApp(
      engineInfoGateway: FakeEngineGateway(
        result ?? const Result<EngineInfo>.success(testEngineInfo),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
