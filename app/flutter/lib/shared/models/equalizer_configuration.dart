import 'dart:math' as math;

/// Portable filter shapes supported by the Rust DSP core.
enum EqFilterType {
  peaking('peaking', 'Peaking'),
  lowShelf('low_shelf', 'Low shelf'),
  highShelf('high_shelf', 'High shelf');

  const EqFilterType(this.wireName, this.label);

  final String wireName;
  final String label;

  static EqFilterType? tryParse(String value) {
    for (final type in values) {
      if (type.wireName == value) {
        return type;
      }
    }
    return null;
  }
}

/// Numeric limits mirrored from `crates/uam_dsp/src/validation.rs`.
abstract final class EqConstraints {
  static const double minFrequencyHz = 10;
  static const double maxFrequencyHz = 20000;
  static const double minGainDb = -24;
  static const double maxGainDb = 24;
  static const double minQ = 0.1;
  static const double maxQ = 10;
  static const double minPreampDb = -24;
  static const double maxPreampDb = 12;
  static const int maxBands = 32;

  /// The graphic editor exposes the Figma range, which is narrower than the
  /// portable preset contract.
  static const double editorMinGainDb = -12;
  static const double editorMaxGainDb = 12;
  static const double gainStepDb = 0.5;

  /// Fixed ten-band grid used by the Equalizer page.
  static const List<double> graphicFrequenciesHz = <double>[
    32,
    64,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];

  static const double defaultQ = 1.0;
}

/// One validated equalizer band.
final class EqBandConfiguration {
  const EqBandConfiguration({
    required this.filterType,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
  });

  final EqFilterType filterType;
  final double frequencyHz;
  final double gainDb;
  final double q;

  EqBandConfiguration copyWith({
    EqFilterType? filterType,
    double? frequencyHz,
    double? gainDb,
    double? q,
  }) {
    return EqBandConfiguration(
      filterType: filterType ?? this.filterType,
      frequencyHz: frequencyHz ?? this.frequencyHz,
      gainDb: gainDb ?? this.gainDb,
      q: q ?? this.q,
    );
  }

  /// Validate against the Rust DSP bounds.
  String? validate() {
    if (!frequencyHz.isFinite) {
      return 'Frequency must be finite.';
    }
    if (frequencyHz < EqConstraints.minFrequencyHz ||
        frequencyHz > EqConstraints.maxFrequencyHz) {
      return 'Frequency must be within 10–20,000 Hz.';
    }
    if (!gainDb.isFinite) {
      return 'Gain must be finite.';
    }
    if (gainDb < EqConstraints.minGainDb || gainDb > EqConstraints.maxGainDb) {
      return 'Gain must be within -24 to +24 dB.';
    }
    if (!q.isFinite || q < EqConstraints.minQ || q > EqConstraints.maxQ) {
      return 'Q must be within 0.1 to 10.';
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'filterType': filterType.wireName,
    'frequencyHz': frequencyHz,
    'gainDb': gainDb,
    'q': q,
  };

  static EqBandConfiguration? tryFromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return null;
    }
    final type = value['filterType'];
    final frequency = value['frequencyHz'];
    final gain = value['gainDb'];
    final q = value['q'];
    if (type is! String || frequency is! num || gain is! num || q is! num) {
      return null;
    }
    final filterType = EqFilterType.tryParse(type);
    if (filterType == null) {
      return null;
    }
    final band = EqBandConfiguration(
      filterType: filterType,
      frequencyHz: frequency.toDouble(),
      gainDb: gain.toDouble(),
      q: q.toDouble(),
    );
    return band.validate() == null ? band : null;
  }

  @override
  bool operator ==(Object other) {
    return other is EqBandConfiguration &&
        other.filterType == filterType &&
        other.frequencyHz == frequencyHz &&
        other.gainDb == gainDb &&
        other.q == q;
  }

  @override
  int get hashCode => Object.hash(filterType, frequencyHz, gainDb, q);
}

/// Desired equalizer configuration. This is never proof of active processing.
final class EqualizerConfiguration {
  EqualizerConfiguration({
    required this.preampDb,
    required List<EqBandConfiguration> bands,
    this.bypassed = false,
  }) : bands = List<EqBandConfiguration>.unmodifiable(bands);

  /// Flat ten-band peaking configuration.
  factory EqualizerConfiguration.defaultGraphic() {
    return EqualizerConfiguration(
      preampDb: 0,
      bands: <EqBandConfiguration>[
        for (final frequency in EqConstraints.graphicFrequenciesHz)
          EqBandConfiguration(
            filterType: EqFilterType.peaking,
            frequencyHz: frequency,
            gainDb: 0,
            q: EqConstraints.defaultQ,
          ),
      ],
    );
  }

  final double preampDb;
  final List<EqBandConfiguration> bands;
  final bool bypassed;

  double get totalPositiveGainDb => bands.fold<double>(
    0,
    (sum, band) => band.gainDb > 0 ? sum + band.gainDb : sum,
  );

  /// Suggest a preamp that leaves headroom for the largest boost.
  double get suggestedPreampDb =>
      math.max(EqConstraints.minPreampDb, -totalPositiveGainDb).toDouble();

  String? validate() {
    if (!preampDb.isFinite ||
        preampDb < EqConstraints.minPreampDb ||
        preampDb > EqConstraints.maxPreampDb) {
      return 'Preamp must be within -24 to +12 dB.';
    }
    if (bands.length > EqConstraints.maxBands) {
      return 'At most 32 bands are supported.';
    }
    for (var index = 0; index < bands.length; index += 1) {
      final error = bands[index].validate();
      if (error != null) {
        return 'Band ${index + 1}: $error';
      }
    }
    return null;
  }

  EqualizerConfiguration copyWith({
    double? preampDb,
    List<EqBandConfiguration>? bands,
    bool? bypassed,
  }) {
    return EqualizerConfiguration(
      preampDb: preampDb ?? this.preampDb,
      bands: bands ?? this.bands,
      bypassed: bypassed ?? this.bypassed,
    );
  }

  EqualizerConfiguration withBandGain(int index, double gainDb) {
    if (index < 0 || index >= bands.length) {
      return this;
    }
    final next = List<EqBandConfiguration>.of(bands);
    next[index] = next[index].copyWith(
      gainDb: gainDb.clamp(
        EqConstraints.editorMinGainDb,
        EqConstraints.editorMaxGainDb,
      ),
    );
    return copyWith(bands: next);
  }

  /// Map a portable preset onto the ten-band graphic grid.
  ///
  /// The portable format supports up to 32 bands and shelving filters. The
  /// Phase 1 graphic editor is a ten-band peaking surface, so each preset band
  /// contributes to its nearest graphic frequency. This is a deterministic
  /// editor transform, not audio processing.
  factory EqualizerConfiguration.fromGraphicPreset({
    required double preampDb,
    required List<EqBandConfiguration> presetBands,
    bool bypassed = false,
  }) {
    final gains = List<double>.filled(
      EqConstraints.graphicFrequenciesHz.length,
      0,
    );
    for (final band in presetBands) {
      var nearestIndex = 0;
      var nearestDistance = double.infinity;
      for (
        var index = 0;
        index < EqConstraints.graphicFrequenciesHz.length;
        index += 1
      ) {
        final distance =
            (math.log(band.frequencyHz) -
                    math.log(EqConstraints.graphicFrequenciesHz[index]))
                .abs();
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestIndex = index;
        }
      }
      gains[nearestIndex] += band.gainDb;
    }
    return EqualizerConfiguration(
      preampDb: preampDb.clamp(
        EqConstraints.minPreampDb,
        EqConstraints.maxPreampDb,
      ),
      bypassed: bypassed,
      bands: <EqBandConfiguration>[
        for (
          var index = 0;
          index < EqConstraints.graphicFrequenciesHz.length;
          index += 1
        )
          EqBandConfiguration(
            filterType: EqFilterType.peaking,
            frequencyHz: EqConstraints.graphicFrequenciesHz[index],
            gainDb: gains[index].clamp(
              EqConstraints.editorMinGainDb,
              EqConstraints.editorMaxGainDb,
            ),
            q: EqConstraints.defaultQ,
          ),
      ],
    );
  }
}
