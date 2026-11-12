import 'package:flutter/material.dart';

import '../bridge/rust_api.dart';
import '../core/constants/app_constants.dart';
import '../design_system/theme/uam_theme.dart';
import '../features/audio_engine/application/engine_controller.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'services/uam_services.dart';
import 'state/uam_app_controller.dart';

/// Root application.
///
/// The Rust [EngineInfoGateway] remains the sole source for engine metadata. The
/// [services] container owns the single SQLite database and its repositories, so
/// there is exactly one persistence stack for the whole process.
///
/// [initialThemePreference], [initialReducedMotion], and [initialLaunchAtStartup]
/// are read from the database during bootstrap and passed in so the very first
/// frame already uses the persisted appearance. This avoids a visible flash from
/// the default theme to the saved theme.
final class UamApp extends StatefulWidget {
  const UamApp({
    required this.engineInfoGateway,
    required this.services,
    this.initialThemePreference,
    this.initialReducedMotion,
    this.initialLaunchAtStartup,
    super.key,
  });

  final EngineInfoGateway engineInfoGateway;
  final UamServices services;
  final UamThemePreference? initialThemePreference;
  final bool? initialReducedMotion;
  final bool? initialLaunchAtStartup;

  @override
  State<UamApp> createState() => _UamAppState();
}

final class _UamAppState extends State<UamApp> {
  late final UamAppController _controller;
  late final ValueNotifier<(ThemeMode, bool)> _chrome;

  @override
  void initState() {
    super.initState();
    _controller = UamAppController.fromServices(
      engine: EngineController(widget.engineInfoGateway),
      services: widget.services,
      initialThemePreference: widget.initialThemePreference,
      initialReducedMotion: widget.initialReducedMotion,
      initialLaunchAtStartup: widget.initialLaunchAtStartup,
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

/// Explicit, recoverable startup failure state.
///
/// Shown when the local database cannot be opened, migrated, or verified. UAM
/// never falls back to volatile in-memory storage, so this screen replaces the
/// application instead of running with data the user would lose.
final class UamBootstrapErrorApp extends StatelessWidget {
  const UamBootstrapErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.productName,
      debugShowCheckedModeBanner: false,
      theme: UamTheme.dark,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'UAM could not start its local data store',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  Text(message),
                  const SizedBox(height: 16),
                  const Text(
                    'Presets and settings are stored in a local SQLite database. '
                    'Check that the application data directory is writable, then '
                    'restart UAM. Nothing was deleted.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Backward-compatible Phase 0 widget export remains in its original library
/// path through the `RustCoreProofPage` feature implementation.
