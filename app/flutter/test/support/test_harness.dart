import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/uam_app.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/errors/uam_failure.dart';
import 'package:uam/core/result/result.dart';
import 'package:uam/app/services/uam_services.dart';
import 'package:uam/platform/audio/audio_engine_gateway.dart';
import 'package:uam/platform/audio/audio_processing_scope.dart';
import 'package:uam/platform/files/preset_file_gateway.dart';

/// Deterministic metadata gateway for widget tests.
final class FakeEngineGateway implements EngineInfoGateway {
  const FakeEngineGateway(this.result);

  final Result<EngineInfo> result;

  @override
  Future<Result<EngineInfo>> loadEngineInfo() async => result;
}

/// Deterministic native-audio gateway for widget and controller tests.
final class FakeAudioEngineGateway implements AudioEngineGateway {
  FakeAudioEngineGateway({this.available = true});

  final bool available;
  bool _opened = false;
  bool _running = false;
  bool _bypassed = false;
  bool _tone = false;

  @override
  bool get isAvailable => available && _opened;

  @override
  String? get unavailableReason =>
      available ? null : 'The test audio gateway is unavailable.';

  @override
  String get backendName => available ? 'fake-wasapi' : 'unavailable';

  @override
  Future<void> open() async {
    _opened = available;
  }

  @override
  Future<void> close() async {
    _opened = false;
    _running = false;
  }

  @override
  Future<Result<AudioEngineSnapshot>> status() async {
    if (!isAvailable) {
      return const Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeUnavailable,
          message: 'The test audio gateway is unavailable.',
        ),
      );
    }
    return Result.success(
      AudioEngineSnapshot(
        state: _running ? 'running' : 'ready',
        scope: _running
            ? AudioProcessingScope.appOwnedStream.wireName
            : AudioProcessingScope.configurationOnly.wireName,
        backend: backendName,
        backendDescription: 'Deterministic test backend.',
        bypassed: _bypassed,
        testToneEnabled: _tone,
        deviceId: null,
        deviceName: null,
        format: null,
        metrics: _running
            ? const AudioMetrics(
                framesProcessed: 480,
                callbacks: 1,
                callbackAverageUs: 100,
                callbackMaxUs: 100,
                callbackP99Us: 100,
                peakInputDbfs: -20,
                peakOutputDbfs: -20,
                limiterReductionDb: 0,
                clippedSamples: 0,
                nonFiniteSamples: 0,
                glitches: 0,
                underruns: 0,
                deadlineMisses: 0,
                streamRestarts: 0,
                deviceDisconnects: 0,
                backendErrors: 0,
                sampleRateHz: 48000,
                channels: 2,
                bufferFrames: 480,
                streamLatencyMs: 10,
                bufferDurationMs: 10,
                averageLoad: 0.01,
              )
            : null,
        lastError: null,
      ),
    );
  }

  @override
  Future<Result<AudioEndpointList>> enumerate() async => const Result.success(
    AudioEndpointList(endpoints: <AudioEndpoint>[], succeeded: true),
  );

  @override
  Future<Result<AudioStreamFormat>> selectDevice(String deviceId) async =>
      const Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeUnavailable,
          message: 'No test endpoint is configured.',
        ),
      );

  @override
  Future<Result<void>> configure(Map<String, Object?> request) async =>
      const Result.success(null);

  @override
  Future<Result<void>> start() async {
    _running = true;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> stop() async {
    _running = false;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> setBypass(bool bypassed) async {
    _bypassed = bypassed;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> setTestTone({
    required bool enabled,
    double frequencyHz = 1000,
    double levelDb = -20,
  }) async {
    _tone = enabled;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> subscribe() async => const Result.success(null);

  @override
  Future<Result<int>> drainDeviceEvents() async => const Result.success(0);
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
      audioEngineGateway: FakeAudioEngineGateway(),
      services: resolved,
    ),
  );
  await tester.pumpAndSettle();
}
