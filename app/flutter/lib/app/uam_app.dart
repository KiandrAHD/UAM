import 'package:flutter/material.dart';

import '../app/config/app_config.dart';
import '../app/router/app_routes.dart';
import '../app/theme/app_theme.dart';
import '../bridge/rust_api.dart';
import '../core/result/result.dart';
import '../platform/audio/audio_processing_scope.dart';

/// Root widget for the Phase 0 application shell.
final class UamApp extends StatelessWidget {
  const UamApp({required this.engineInfoGateway, super.key});

  /// Gateway used to load Rust core metadata.
  final EngineInfoGateway engineInfoGateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.applicationTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.home,
      routes: <String, WidgetBuilder>{
        AppRoutes.home: (_) =>
            PhaseZeroHomePage(engineInfoGateway: engineInfoGateway),
      },
    );
  }
}

/// Minimal Phase 0 screen that proves the Flutter-to-Rust control path.
///
/// This is not the product dashboard. It displays exactly the metadata the
/// compiled core reports and states which capabilities are absent.
final class PhaseZeroHomePage extends StatefulWidget {
  const PhaseZeroHomePage({required this.engineInfoGateway, super.key});

  /// Gateway used to load Rust core metadata.
  final EngineInfoGateway engineInfoGateway;

  @override
  State<PhaseZeroHomePage> createState() => _PhaseZeroHomePageState();
}

final class _PhaseZeroHomePageState extends State<PhaseZeroHomePage> {
  late Future<ResultView> _engineInfo;

  @override
  void initState() {
    super.initState();
    _engineInfo = _load();
  }

  Future<ResultView> _load() async {
    final result = await widget.engineInfoGateway.loadEngineInfo();
    return ResultView.fromResult(result);
  }

  void _retry() {
    setState(() {
      _engineInfo = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.applicationTitle),
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: Chip(label: Text(AppConfig.phaseLabel))),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: FutureBuilder<ResultView>(
              future: _engineInfo,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final view = snapshot.data;
                if (view == null) {
                  return _FailurePanel(
                    message: 'The bridge call ended without a result.',
                    onRetry: _retry,
                  );
                }
                if (view.failureMessage != null) {
                  return _FailurePanel(
                    message: view.failureMessage!,
                    detail: view.failureDetail,
                    onRetry: _retry,
                  );
                }
                return _InfoPanel(info: view.info!, onRetry: _retry);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Flattened view model so the widget layer does not depend on `Result`
/// internals in build methods.
final class ResultView {
  const ResultView._({this.info, this.failureMessage, this.failureDetail});

  factory ResultView.fromResult(Result<EngineInfo> result) {
    return switch (result) {
      Success<EngineInfo>(value: final info) => ResultView._(info: info),
      Failure<EngineInfo>(failure: final failure) => ResultView._(
        failureMessage: failure.message,
        failureDetail: failure.detail,
      ),
    };
  }

  final EngineInfo? info;
  final String? failureMessage;
  final String? failureDetail;
}

final class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.info, required this.onRetry});

  final EngineInfo info;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AudioProcessingScopeView.labelFor(info.audioProcessingScope);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text('Rust core connected', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'This screen is a Phase 0 interoperability proof, not a product '
          'dashboard. Values below were returned by the compiled Rust core.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Core information', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _KeyValue(label: 'Product', value: info.productName),
                _KeyValue(
                  label: 'Core engine version',
                  value: info.coreEngineVersion,
                ),
                _KeyValue(
                  label: 'Bridge ABI',
                  value: '${info.bridgeAbiVersion}',
                ),
                _KeyValue(
                  label: 'Implementation status',
                  value: info.rustImplementationStatus,
                ),
                _KeyValue(label: 'Processing scope', value: scope),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Supported prototype functionality',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final feature in info.supportedPrototypeFunctionality)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.check_circle_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(feature)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Scope and limitations',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(AppConfig.processingScopeNotice),
                const SizedBox(height: 8),
                const Text(AppConfig.deviceNotice),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reload core information'),
          ),
        ),
      ],
    );
  }
}

final class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    required this.message,
    required this.onRetry,
    this.detail,
  });

  final String message;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.usb_off_outlined,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Rust core unavailable',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  AppConfig.coreBuildHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// UI-only label mapping. Unknown wire values are shown verbatim rather than
/// being silently treated as a supported processing scope.
abstract final class AudioProcessingScopeView {
  static String labelFor(String wireName) {
    final scope = AudioProcessingScope.tryParse(wireName);
    return scope?.label ?? 'Unknown ($wireName)';
  }
}
