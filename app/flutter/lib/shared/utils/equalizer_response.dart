import 'dart:math' as math;

import '../models/equalizer_configuration.dart';

/// Display-only magnitude response for the ten-band editor.
///
/// This mirrors the RBJ biquad forms used by the Rust DSP core so the graph
/// reflects the configured bands. It does not process audio.
abstract final class EqualizerResponse {
  static const double sampleRateHz = 48000;

  static double magnitudeDbAt(
    double frequencyHz,
    List<EqBandConfiguration> bands,
    double preampDb,
  ) {
    var total = preampDb;
    for (final band in bands) {
      total += _bandMagnitudeDb(frequencyHz, band);
    }
    return total;
  }

  static double _bandMagnitudeDb(double frequencyHz, EqBandConfiguration band) {
    final w0 = 2 * math.pi * band.frequencyHz / sampleRateHz;
    final w = 2 * math.pi * frequencyHz / sampleRateHz;
    final (sinW0, cosW0) = _sinCos(w0);
    final alpha = sinW0 / (2 * band.q);
    final a = math.pow(10, band.gainDb / 40).toDouble();
    final sqrtA = math.sqrt(a);
    final twoSqrtAAlpha = 2 * sqrtA * alpha;

    late final double b0;
    late final double b1;
    late final double b2;
    late final double a0;
    late final double a1;
    late final double a2;

    switch (band.filterType) {
      case EqFilterType.peaking:
        b0 = 1 + alpha * a;
        b1 = -2 * cosW0;
        b2 = 1 - alpha * a;
        a0 = 1 + alpha / a;
        a1 = -2 * cosW0;
        a2 = 1 - alpha / a;
      case EqFilterType.lowShelf:
        b0 = a * ((a + 1) - (a - 1) * cosW0 + twoSqrtAAlpha);
        b1 = 2 * a * ((a - 1) - (a + 1) * cosW0);
        b2 = a * ((a + 1) - (a - 1) * cosW0 - twoSqrtAAlpha);
        a0 = (a + 1) + (a - 1) * cosW0 + twoSqrtAAlpha;
        a1 = -2 * ((a - 1) + (a + 1) * cosW0);
        a2 = (a + 1) + (a - 1) * cosW0 - twoSqrtAAlpha;
      case EqFilterType.highShelf:
        b0 = a * ((a + 1) + (a - 1) * cosW0 + twoSqrtAAlpha);
        b1 = -2 * a * ((a - 1) + (a + 1) * cosW0);
        b2 = a * ((a + 1) + (a - 1) * cosW0 - twoSqrtAAlpha);
        a0 = (a + 1) - (a - 1) * cosW0 + twoSqrtAAlpha;
        a1 = 2 * ((a - 1) - (a + 1) * cosW0);
        a2 = (a + 1) - (a - 1) * cosW0 - twoSqrtAAlpha;
    }

    final cosW = math.cos(w);
    final cos2W = math.cos(2 * w);
    final sinW = math.sin(w);
    final sin2W = math.sin(2 * w);

    final numeratorReal = b0 + b1 * cosW + b2 * cos2W;
    final numeratorImag = -(b1 * sinW + b2 * sin2W);
    final denominatorReal = a0 + a1 * cosW + a2 * cos2W;
    final denominatorImag = -(a1 * sinW + a2 * sin2W);
    final numerator = math.sqrt(
      numeratorReal * numeratorReal + numeratorImag * numeratorImag,
    );
    final denominator = math.sqrt(
      denominatorReal * denominatorReal + denominatorImag * denominatorImag,
    );
    if (denominator == 0 || !numerator.isFinite || !denominator.isFinite) {
      return 0;
    }
    final ratio = numerator / denominator;
    if (ratio <= 0) {
      return 0;
    }
    return 20 * (math.log(ratio) / math.ln10);
  }

  static (double, double) _sinCos(double value) =>
      (math.sin(value), math.cos(value));
}
