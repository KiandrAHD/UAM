import 'package:flutter/foundation.dart';

import '../../../shared/models/audio_device.dart';
import '../data/device_repository.dart';

/// Manages device state, backed by a [DeviceRepository].
///
/// This controller never fabricates device metadata. All states are derived
/// from the repository's snapshot.
final class DeviceController extends ChangeNotifier {
  DeviceController({DeviceRepository? repository})
    : _repository = repository ?? const UnavailableDeviceRepository() {
    _snapshot = DeviceDiscoverySnapshot(
      status: DeviceDiscoveryStatus.idle,
      reason: _repository.adapterDescription,
    );
  }

  final DeviceRepository _repository;
  late DeviceDiscoverySnapshot _snapshot;
  AudioDevice? _selected;
  bool _isScanning = false;

  DeviceDiscoverySnapshot get snapshot => _snapshot;
  AudioDevice? get selected => _selected;
  bool get isScanning => _isScanning;
  List<AudioDevice> get devices => _snapshot.devices;
  String get adapterDescription => _repository.adapterDescription;

  Future<void> refresh() async {
    _isScanning = true;
    _snapshot = DeviceDiscoverySnapshot(
      status: DeviceDiscoveryStatus.scanning,
      reason: 'Searching for audio devices...',
    );
    notifyListeners();

    try {
      final result = await _repository.discover();
      _snapshot = result;
      // Clear the selected device if it is no longer in the list.
      if (_selected != null && !result.devices.contains(_selected)) {
        _selected = null;
      }
    } on Object {
      _snapshot = DeviceDiscoverySnapshot(
        status: DeviceDiscoveryStatus.error,
        reason: 'An unexpected error occurred during device discovery.',
      );
    }

    _isScanning = false;
    notifyListeners();
  }

  void selectDevice(AudioDevice device) {
    _selected = device;
    notifyListeners();
  }

  void clearSelection() {
    _selected = null;
    notifyListeners();
  }
}
