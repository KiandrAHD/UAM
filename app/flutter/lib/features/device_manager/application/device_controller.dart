import 'package:flutter/foundation.dart';

import '../../../shared/models/audio_device.dart';
import '../data/device_repository.dart';

/// Manages device state, backed by a [DeviceRepository].
///
/// This controller never fabricates device metadata. All states are derived
/// from the repository's snapshot, and selection is only reported as active
/// when the native backend accepts it.
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
  bool _selectionPending = false;
  String? _selectionError;

  DeviceDiscoverySnapshot get snapshot => _snapshot;
  AudioDevice? get selected => _selected;
  bool get isScanning => _isScanning;
  bool get isSelecting => _selectionPending;
  bool get isAvailable => _repository.isAvailable;
  String? get selectionError => _selectionError;
  List<AudioDevice> get devices => _snapshot.devices;
  String get adapterDescription => _repository.adapterDescription;

  Future<void> refresh() async {
    _isScanning = true;
    _snapshot = DeviceDiscoverySnapshot(
      status: DeviceDiscoveryStatus.scanning,
      reason: 'Enumerating render endpoints...',
    );
    notifyListeners();

    try {
      final result = await _repository.discover();
      _snapshot = result;
      final persisted = await _repository.persistedSelection();
      _selected = _resolveSelection(result.devices, persisted);
      if (_selected == null && persisted != null) {
        // The previously selected endpoint is gone; keep the selection empty
        // rather than pointing at a device that no longer exists.
        _selectionError =
            'The previously selected endpoint is not present right now.';
      } else {
        _selectionError = null;
      }
    } on Object {
      _snapshot = DeviceDiscoverySnapshot(
        status: DeviceDiscoveryStatus.error,
        reason: 'An unexpected error occurred during endpoint discovery.',
      );
      _selected = null;
    }

    _isScanning = false;
    notifyListeners();
  }

  /// Select an endpoint and ask the native backend to resolve its format and
  /// persist the choice.
  Future<bool> selectDevice(AudioDevice device) async {
    if (!_repository.isAvailable) {
      _selectionError = _repository.unavailableReason;
      notifyListeners();
      return false;
    }
    _selectionPending = true;
    _selectionError = null;
    notifyListeners();

    final accepted = await _repository.select(device.id);
    _selectionPending = false;
    if (accepted) {
      _selected = device;
    } else {
      _selectionError =
          'The audio backend did not accept this endpoint. It may have been '
          'removed.';
    }
    notifyListeners();
    return accepted;
  }

  void clearSelection() {
    _selected = null;
    notifyListeners();
  }

  AudioDevice? _resolveSelection(List<AudioDevice> devices, String? persisted) {
    final current = _selected;
    if (current != null) {
      for (final device in devices) {
        if (device.id == current.id) {
          return device;
        }
      }
    }
    if (persisted != null) {
      for (final device in devices) {
        if (device.id == persisted) {
          return device;
        }
      }
    }
    return null;
  }
}
