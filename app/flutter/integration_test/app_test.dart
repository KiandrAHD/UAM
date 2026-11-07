import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uam/app/uam_app.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/result/result.dart';

final class _SmokeGateway implements EngineInfoGateway {
  const _SmokeGateway();

  @override
  Future<Result<EngineInfo>> loadEngineInfo() async {
    return const Result<EngineInfo>.success(
      EngineInfo(
        productName: 'Universe Audio Management',
        coreEngineVersion: '0.1.0',
        bridgeAbiVersion: 1,
        rustImplementationStatus: 'prototype',
        supportedPrototypeFunctionality: <String>['bridge.engine_info'],
        audioProcessingScope: 'configuration_only',
      ),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 0 shell starts and renders the core panel', (
    tester,
  ) async {
    await tester.pumpWidget(const UamApp(engineInfoGateway: _SmokeGateway()));
    await tester.pumpAndSettle();

    expect(find.text('Rust core connected'), findsOneWidget);
    expect(find.text('Configuration only'), findsOneWidget);
  });
}
