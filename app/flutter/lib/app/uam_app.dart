import 'package:flutter/material.dart';

import '../bridge/rust_api.dart';
import '../core/constants/app_constants.dart';
import '../design_system/theme/uam_theme.dart';
import '../features/audio_engine/application/engine_controller.dart';
import '../features/device_manager/application/device_controller.dart';
import '../features/equalizer/application/equalizer_controller.dart';
import '../features/presets/application/preset_library_controller.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'state/uam_app_controller.dart';

/// Root application. The existing Phase 0 [EngineInfoGateway] remains the sole
/// source for Rust engine metadata.
final class UamApp extends StatefulWidget {
  const UamApp({required this.engineInfoGateway, super.key});

  final EngineInfoGateway engineInfoGateway;

  @override
  State<UamApp> createState() => _UamAppState();
}

final class _UamAppState extends State<UamApp> {
  late final UamAppController _controller;
  late final ValueNotifier<(ThemeMode, bool)> _chrome;

  @override
  void initState() {
    super.initState();
    _controller = UamAppController(
      engine: EngineController(widget.engineInfoGateway),
      devices: DeviceController(),
      equalizer: EqualizerController(),
      presets: PresetLibraryController(),
    );
    _chrome = ValueNotifier<(ThemeMode, bool)>(_chromeState);
    _controller.addListener(_syncChrome);
    _controller.initialize();
  }

  (ThemeMode, bool) get _chromeState =>
      (_controller.themeMode, _controller.reducedMotion);

  /// Only appearance changes rebuild [MaterialApp]. Feature state flows through
  /// [UamAppScope], so preset or engine updates never rebuild the navigator.
  void _syncChrome() {
    final next = _chromeState;
    if (_chrome.value != next) {
      _chrome.value = next;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncChrome);
    _chrome.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UamAppScope(
      controller: _controller,
      child: ValueListenableBuilder<(ThemeMode, bool)>(
        valueListenable: _chrome,
        builder: (context, chrome, _) {
          final (themeMode, reducedMotion) = chrome;
          return MaterialApp(
            title: AppConstants.productName,
            debugShowCheckedModeBanner: false,
            theme: UamTheme.light,
            darkTheme: UamTheme.dark,
            themeMode: themeMode,
            onGenerateRoute: AppRouter.onGenerateRoute,
            initialRoute: AppRoutes.dashboard,
            builder: (context, child) {
              final media = MediaQuery.of(context);
              if (!reducedMotion || media.disableAnimations) {
                return child ?? const SizedBox.shrink();
              }
              return MediaQuery(
                data: media.copyWith(disableAnimations: true),
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}

/// Backward-compatible Phase 0 widget export remains in its original library
/// path through the `RustCoreProofPage` feature implementation.
