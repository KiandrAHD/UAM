import 'package:flutter/foundation.dart';

import '../../../shared/models/equalizer_configuration.dart';

/// Holds the desired equalizer configuration.
///
/// This controller never claims that a DSP stream is running. It only edits the
/// configuration that a later phase can hand to the Rust core.
final class EqualizerController extends ChangeNotifier {
  EqualizerController({EqualizerConfiguration? initial})
    : _configuration = initial ?? EqualizerConfiguration.defaultGraphic(),
      _baseline = initial ?? EqualizerConfiguration.defaultGraphic();

  EqualizerConfiguration _configuration;
  EqualizerConfiguration _baseline;

  EqualizerConfiguration get configuration => _configuration;

  /// Replace the configuration and remember it as the reset target.
  void applyConfiguration(
    EqualizerConfiguration configuration, {
    bool makeBaseline = true,
  }) {
    _configuration = configuration;
    if (makeBaseline) {
      _baseline = configuration;
    }
    notifyListeners();
  }

  void setBandGain(int index, double gainDb) {
    _configuration = _configuration.withBandGain(index, gainDb);
    notifyListeners();
  }

  void setPreamp(double preampDb) {
    final clamped = preampDb.clamp(
      EqConstraints.minPreampDb,
      EqConstraints.maxPreampDb,
    );
    _configuration = _configuration.copyWith(preampDb: clamped);
    notifyListeners();
  }

  void setBypassed(bool bypassed) {
    _configuration = _configuration.copyWith(bypassed: bypassed);
    notifyListeners();
  }

  void toggleBypass() => setBypassed(!_configuration.bypassed);

  /// Restore the last activated preset or the initial configuration.
  void reset() {
    _configuration = _baseline;
    notifyListeners();
  }
}
