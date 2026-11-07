import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/uam_app.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/errors/uam_failure.dart';
import 'package:uam/core/result/result.dart';

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
  testWidgets('renders Rust core information on success', (tester) async {
    await tester.pumpWidget(
      const UamApp(
        engineInfoGateway: _FakeGateway(
          Result<EngineInfo>.success(_engineInfo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rust core connected'), findsOneWidget);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('Configuration only'), findsOneWidget);
    expect(find.text('dsp.eq.peaking'), findsOneWidget);
    expect(find.text('Supported prototype functionality'), findsOneWidget);
  });

  testWidgets('renders a safe failure state when the bridge is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const UamApp(
        engineInfoGateway: _FakeGateway(
          Result<EngineInfo>.failure(
            UamFailure(
              code: UamFailureCode.bridgeUnavailable,
              message: 'The UAM Rust core library was not found.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rust core unavailable'), findsOneWidget);
    expect(
      find.text('The UAM Rust core library was not found.'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
