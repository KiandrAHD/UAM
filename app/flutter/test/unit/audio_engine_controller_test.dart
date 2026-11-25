import 'package:flutter_test/flutter_test.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/errors/uam_failure.dart';
import 'package:uam/core/result/result.dart';
import 'package:uam/features/audio_engine/application/engine_controller.dart';
import 'package:uam/features/device_manager/application/device_controller.dart';
import 'package:uam/features/device_manager/data/device_repository.dart';
import 'package:uam/features/equalizer/application/equalizer_controller.dart';
import 'package:uam/platform/audio/audio_engine_gateway.dart';
import 'package:uam/platform/audio/audio_processing_scope.dart';
import 'package:uam/shared/models/audio_device.dart';
import 'package:uam/shared/models/engine_runtime_state.dart';

import '../support/test_data_stack.dart';

/// Configurable native audio gateway for control-path tests.
final class ScriptedAudioGateway implements AudioEngineGateway {
  bool available = true;
  bool _opened = false;
  bool running = false;
  bool bypassed = false;
  bool tone = false;
  bool failStatus = false;
  bool failEnumeration = false;
  bool failSelection = false;
  List<AudioEndpoint> endpoints = const <AudioEndpoint>[];
  String? defaultId;
  Map<String, Object?>? lastConfiguration;
  AudioStreamFormat format = const AudioStreamFormat(
    sampleRateHz: 48000,
    channels: 2,
    encoding: 'f32',
    containerBits: 32,
    validBits: 32,
    summary: '48000 Hz / 2 ch / f32',
  );

  @override
  bool get isAvailable => available && _opened;

  @override
  String? get unavailableReason =>
      available ? null : 'Native audio backend not available in test.';

  @override
  String get backendName => available ? 'wasapi-shared' : 'unavailable';

  @override
  Future<void> open() async {
    _opened = available;
  }

  @override
  Future<void> close() async {
    _opened = false;
  }

  @override
  Future<Result<AudioEngineSnapshot>> status() async {
    if (failStatus) {
      return const Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeProtocol,
          message: 'Status call failed.',
        ),
      );
    }
    return Result.success(
      AudioEngineSnapshot(
        state: running ? 'running' : 'ready',
        scope: running
            ? AudioProcessingScope.appOwnedStream.wireName
            : AudioProcessingScope.configurationOnly.wireName,
        backend: backendName,
        backendDescription: 'Test backend.',
        bypassed: bypassed,
        testToneEnabled: tone,
        deviceId: running ? 'dev-a' : null,
        deviceName: running ? 'Speakers (Test)' : null,
        format: format,
        metrics: running
            ? const AudioMetrics(
                framesProcessed: 960,
                callbacks: 2,
                callbackAverageUs: 120,
                callbackMaxUs: 300,
                callbackP99Us: 250,
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
                streamLatencyMs: 8,
                bufferDurationMs: 10,
                averageLoad: 0.012,
              )
            : null,
        lastError: null,
      ),
    );
  }

  @override
  Future<Result<AudioEndpointList>> enumerate() async {
    if (failEnumeration) {
      return const Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeUnavailable,
          message: 'Enumeration failed.',
        ),
      );
    }
    return Result.success(
      AudioEndpointList(
        endpoints: endpoints,
        defaultId: defaultId,
        succeeded: true,
      ),
    );
  }

  @override
  Future<Result<AudioStreamFormat>> selectDevice(String deviceId) async {
    if (failSelection) {
      return const Result.failure(
        UamFailure(
          code: UamFailureCode.bridgeUnavailable,
          message: 'Selection rejected.',
        ),
      );
    }
    return Result.success(format);
  }

  @override
  Future<Result<void>> configure(Map<String, Object?> request) async {
    lastConfiguration = request;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> start() async {
    running = true;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> stop() async {
    running = false;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> setBypass(bool value) async {
    bypassed = value;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> setTestTone({
    required bool enabled,
    double frequencyHz = 1000,
    double levelDb = -20,
  }) async {
    tone = enabled;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> subscribe() async => const Result.success(null);

  @override
  Future<Result<int>> drainDeviceEvents() async => const Result.success(0);
}

const EngineInfo _info = EngineInfo(
  productName: 'Universe Audio Management',
  coreEngineVersion: '0.1.0',
  bridgeAbiVersion: 1,
  rustImplementationStatus: 'prototype',
  supportedPrototypeFunctionality: <String>['audio.engine.lifecycle'],
  audioProcessingScope: 'configuration_only',
);

final class _InfoGateway implements EngineInfoGateway {
  const _InfoGateway();

  @override
  Future<Result<EngineInfo>> loadEngineInfo() async =>
      const Result.success(_info);
}

AudioEndpoint _endpoint(
  String id,
  String name, {
  String state = 'active',
  bool isDefault = false,
}) {
  return AudioEndpoint(
    id: id,
    displayName: name,
    connectionState: state,
    isDefault: isDefault,
    transport: 'usb',
    formatSummary: '48000 Hz / 2 ch / f32',
  );
}

void main() {
  group('EngineController', () {
    test('reports configuration only until the stream renders', () async {
      final gateway = ScriptedAudioGateway();
      final controller = EngineController(const _InfoGateway(), gateway);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.status, EngineProcessingStatus.ready);
      expect(controller.state.processingVerified, isFalse);
      expect(
        controller.state.processingScope,
        AudioProcessingScope.configurationOnly,
      );

      await controller.startStream();
      expect(controller.state.processingVerified, isTrue);
      expect(controller.state.metrics?.callbacks, 2);
      expect(
        controller.state.processingScope,
        AudioProcessingScope.appOwnedStream,
      );
    });

    test('sends the equalizer request through the gateway', () async {
      final gateway = ScriptedAudioGateway();
      final controller = EngineController(const _InfoGateway(), gateway);
      addTearDown(controller.dispose);
      await controller.load();

      final equalizer = EqualizerController()..setBandGain(0, 6);
      await controller.applyEqualizer(equalizer.configuration);

      final request = gateway.lastConfiguration!;
      expect(request['preampDb'], 0);
      expect(request['bypassed'], isFalse);
      final bands = request['bands']! as List<Object?>;
      expect(bands, hasLength(10));
      expect((bands.first! as Map<String, Object?>)['gainDb'], 6);
      expect(controller.state.configurationAccepted, isTrue);
    });

    test('bypass is reflected in state', () async {
      final gateway = ScriptedAudioGateway();
      final controller = EngineController(const _InfoGateway(), gateway);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.setBypass(true);
      expect(gateway.bypassed, isTrue);
      expect(controller.state.bypassed, isTrue);
    });

    test('a failing status call surfaces an error state', () async {
      final gateway = ScriptedAudioGateway()..failStatus = true;
      final controller = EngineController(const _InfoGateway(), gateway);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.status, EngineProcessingStatus.error);
      expect(
        controller.entries.any((entry) => entry.message.isNotEmpty),
        isTrue,
      );
    });

    test('unavailable backend keeps processing unverified', () async {
      final gateway = ScriptedAudioGateway()..available = false;
      final controller = EngineController(const _InfoGateway(), gateway);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.processingVerified, isFalse);
      expect(controller.state.status, EngineProcessingStatus.unavailable);
    });
  });

  group('DeviceController with EngineDeviceRepository', () {
    late TestDataStack stack;

    setUp(() async {
      stack = await TestDataStack.create();
    });

    tearDown(() async {
      await stack.dispose();
    });

    test('enumerates real endpoints and persists selection', () async {
      final gateway = ScriptedAudioGateway()
        ..endpoints = <AudioEndpoint>[
          _endpoint('dev-a', 'Speakers', isDefault: true),
          _endpoint('dev-b', 'Headphones'),
        ]
        ..defaultId = 'dev-a';
      await gateway.open();

      final controller = DeviceController(
        repository: EngineDeviceRepository(gateway, stack.settings),
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.devices, hasLength(2));
      expect(controller.devices.first.isDefault, isTrue);

      final accepted = await controller.selectDevice(controller.devices[1]);
      expect(accepted, isTrue);
      expect(controller.selected?.id, 'dev-b');
      expect(
        await stack.settings.get<String>('general.selectedOutputDeviceId'),
        'dev-b',
      );
    });

    test(
      'a removed endpoint clears the selection and reports a notice',
      () async {
        final gateway = ScriptedAudioGateway()
          ..endpoints = <AudioEndpoint>[
            _endpoint('dev-a', 'Speakers', isDefault: true),
          ];
        await gateway.open();

        final controller = DeviceController(
          repository: EngineDeviceRepository(gateway, stack.settings),
        );
        addTearDown(controller.dispose);

        await controller.refresh();
        await controller.selectDevice(controller.devices.first);
        expect(controller.selected?.id, 'dev-a');

        gateway.endpoints = <AudioEndpoint>[];
        await controller.refresh();
        expect(controller.selected, isNull);
        expect(controller.selectionError, isNotNull);
      },
    );

    test('a rejected selection is not reported as selected', () async {
      final gateway = ScriptedAudioGateway()
        ..endpoints = <AudioEndpoint>[_endpoint('dev-a', 'Speakers')]
        ..failSelection = true;
      await gateway.open();

      final controller = DeviceController(
        repository: EngineDeviceRepository(gateway, stack.settings),
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      final accepted = await controller.selectDevice(controller.devices.first);
      expect(accepted, isFalse);
      expect(controller.selected, isNull);
      expect(controller.selectionError, isNotNull);
    });

    test('disconnected endpoints map to disconnected state', () async {
      final gateway = ScriptedAudioGateway()
        ..endpoints = <AudioEndpoint>[
          _endpoint('dev-a', 'Speakers', state: 'unplugged'),
        ];
      await gateway.open();

      final repository = EngineDeviceRepository(gateway, stack.settings);
      final snapshot = await repository.discover();
      expect(
        snapshot.devices.single.connectionState,
        DeviceConnectionState.disconnected,
      );
    });
  });
}
