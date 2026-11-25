import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/uam_app.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/errors/uam_failure.dart';
import 'package:uam/core/result/result.dart';

import '../support/test_harness.dart';

final class _FakeGateway implements EngineInfoGateway {
  const _FakeGateway(this.result);

  final Result<EngineInfo> result;

  @override
  Future<Result<EngineInfo>> loadEngineInfo() async => result;
}

const EngineInfo _engineInfo = EngineInfo(
  productName: 'Universe Audio Management',
  coreEngineVersion: '0.1.0',
  bridgeAbiVersion: 1,
  rustImplementationStatus: 'prototype',
  supportedPrototypeFunctionality: <String>[
    'bridge.engine_info',
    'dsp.eq.peaking',
  ],
  audioProcessingScope: 'configuration_only',
);

void main() {
  testWidgets('renders live engine metadata and stream state', (tester) async {
    final services = await createWidgetTestServices(tester);
    await tester.pumpWidget(
      UamApp(
        engineInfoGateway: const _FakeGateway(
          Result<EngineInfo>.success(_engineInfo),
        ),
        audioEngineGateway: FakeAudioEngineGateway(),
        services: services,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Audio workspace'), findsOneWidget);
    expect(find.text('Ready, not processing'), findsOneWidget);
    expect(find.text('Configuration only'), findsWidgets);
    expect(find.text('Rust core'), findsOneWidget);
    expect(find.text('Not verified'), findsWidgets);
  });

  testWidgets('renders a safe state when the native audio engine is missing', (
    tester,
  ) async {
    final services = await createWidgetTestServices(tester);
    await tester.pumpWidget(
      UamApp(
        engineInfoGateway: const _FakeGateway(
          Result<EngineInfo>.failure(
            UamFailure(
              code: UamFailureCode.bridgeUnavailable,
              message: 'The UAM Rust core library was not found.',
            ),
          ),
        ),
        audioEngineGateway: FakeAudioEngineGateway(available: false),
        services: services,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Audio workspace'), findsOneWidget);
    expect(find.text('Not processing'), findsOneWidget);
    expect(find.text('Not verified'), findsWidgets);
  });
}