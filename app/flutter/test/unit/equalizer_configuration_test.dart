import 'package:flutter_test/flutter_test.dart';
import 'package:uam/shared/models/equalizer_configuration.dart';

void main() {
  group('EqualizerConfiguration', () {
    test('default graphic configuration has ten peaking bands at zero', () {
      final configuration = EqualizerConfiguration.defaultGraphic();
      expect(configuration.bands, hasLength(10));
      expect(configuration.preampDb, 0);
      expect(configuration.bypassed, isFalse);
      for (final band in configuration.bands) {
        expect(band.filterType, EqFilterType.peaking);
        expect(band.gainDb, 0);
      }
      expect(
        configuration.bands.map((band) => band.frequencyHz),
        EqConstraints.graphicFrequenciesHz,
      );
      expect(configuration.validate(), isNull);
    });

    test('band gain is clamped to the editor range', () {
      final configuration = EqualizerConfiguration.defaultGraphic()
          .withBandGain(0, 40)
          .withBandGain(1, -40);
      expect(configuration.bands[0].gainDb, EqConstraints.editorMaxGainDb);
      expect(configuration.bands[1].gainDb, EqConstraints.editorMinGainDb);
    });

    test('suggested preamp leaves headroom for positive gain', () {
      final configuration = EqualizerConfiguration.defaultGraphic()
          .withBandGain(0, 4)
          .withBandGain(1, 3);
      expect(configuration.totalPositiveGainDb, 7);
      expect(configuration.suggestedPreampDb, -7);
    });

    test('preamp is bounded by the portable contract', () {
      final configuration = EqualizerConfiguration.defaultGraphic().copyWith(
        preampDb: 99,
      );
      expect(configuration.validate(), contains('Preamp'));
    });

    test('preset bands map onto the nearest graphic frequency', () {
      final configuration = EqualizerConfiguration.fromGraphicPreset(
        preampDb: -4.5,
        presetBands: const <EqBandConfiguration>[
          EqBandConfiguration(
            filterType: EqFilterType.lowShelf,
            frequencyHz: 120,
            gainDb: 6,
            q: 0.707,
          ),
          EqBandConfiguration(
            filterType: EqFilterType.highShelf,
            frequencyHz: 8000,
            gainDb: -2.5,
            q: 0.707,
          ),
        ],
      );
      expect(configuration.bands, hasLength(10));
      expect(configuration.preampDb, -4.5);
      final at125 = configuration.bands.firstWhere(
        (band) => band.frequencyHz == 125,
      );
      final at8000 = configuration.bands.firstWhere(
        (band) => band.frequencyHz == 8000,
      );
      expect(at125.gainDb, 6);
      expect(at8000.gainDb, -2.5);
    });

    test('invalid band bounds are reported', () {
      const band = EqBandConfiguration(
        filterType: EqFilterType.peaking,
        frequencyHz: 5,
        gainDb: 0,
        q: 1,
      );
      expect(band.validate(), contains('Frequency'));
    });
  });
}
