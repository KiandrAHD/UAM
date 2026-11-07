import 'package:flutter_test/flutter_test.dart';
import 'package:uam/bridge/rust_api.dart';

void main() {
  group('EngineInfo.fromJson', () {
    test('parses the documented payload', () {
      final info = EngineInfo.fromJson(<String, Object?>{
        'productName': 'Universe Audio Management',
        'coreEngineVersion': '0.1.0',
        'bridgeAbiVersion': 1,
        'rustImplementationStatus': 'prototype',
        'supportedPrototypeFunctionality': <Object?>['dsp.eq.peaking'],
        'audioProcessingScope': 'configuration_only',
      });

      expect(info.productName, 'Universe Audio Management');
      expect(info.coreEngineVersion, '0.1.0');
      expect(info.bridgeAbiVersion, 1);
      expect(info.supportedPrototypeFunctionality, <String>['dsp.eq.peaking']);
    });

    test('rejects missing fields', () {
      expect(
        () => EngineInfo.fromJson(const <String, Object?>{
          'productName': 'Universe Audio Management',
        }),
        throwsFormatException,
      );
    });

    test('rejects non-string capability entries', () {
      expect(
        () => EngineInfo.fromJson(<String, Object?>{
          'productName': 'Universe Audio Management',
          'coreEngineVersion': '0.1.0',
          'bridgeAbiVersion': 1,
          'rustImplementationStatus': 'prototype',
          'supportedPrototypeFunctionality': <Object?>[1],
          'audioProcessingScope': 'configuration_only',
        }),
        throwsFormatException,
      );
    });
  });
}
