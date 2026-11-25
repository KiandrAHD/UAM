import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/state/uam_app_controller.dart';
import '../../../design_system/components/uam_components.dart';
import '../../../design_system/components/uam_layout.dart';
import '../../../design_system/tokens/uam_colors.dart';
import '../../../design_system/tokens/uam_spacing.dart';

/// Live, native audio diagnostics.
///
/// Values are read from atomic metrics in the Rust audio core. A missing stream
/// produces `Unavailable` rather than synthetic CPU, latency, or level values.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

final class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        unawaited(UamAppScope.read(context).engine.refresh());
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final state = controller.engine.state;
    final metrics = state.metrics;
    return Scaffold(
      appBar: AppBar(title: const Text('Audio diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(UamSpacing.xl),
        children: <Widget>[
          UamPageHeader(
            eyebrow: 'Runtime evidence',
            title: 'Audio diagnostics',
            description:
                'Measurements come from native audio-thread atomics. Refreshes '
                'poll control-path status once per second.',
            actions: <Widget>[
              UamIconButton(
                icon: Icons.refresh,
                label: 'Refresh diagnostics',
                onPressed: () {
                  unawaited(controller.engine.refresh());
                },
              ),
            ],
          ),
          const SizedBox(height: UamSpacing.lg),
          UamNotice(
            tone: metrics == null ? UamStatusTone.info : UamStatusTone.success,
            title: metrics == null ? 'No live measurements' : 'Live measurements',
            message: metrics == null
                ? 'Start a UAM-owned render stream to populate timing, level, '
                      'buffer, and error counters. Third-party system audio is '
                      'not measured or processed.'
                : 'Metrics are from the active UAM-owned stream. Values marked '
                      'estimated by the backend remain estimates.',
          ),
          const SizedBox(height: UamSpacing.xl),
          UamResponsiveGrid(
            minTileWidth: 205,
            children: <Widget>[
              _metric('Callback avg', _us(metrics?.callbackAverageUs),
                  'Measured callback wall time'),
              _metric('Callback p99', _us(metrics?.callbackP99Us),
                  'Histogram estimate'),
              _metric('Callback max', _us(metrics?.callbackMaxUs),
                  'Measured maximum'),
              _metric('CPU load', _percent(metrics?.loadPercent),
                  'Callback / buffer period'),
              _metric('Stream latency', _ms(metrics?.streamLatencyMs),
                  'Reported by endpoint'),
              _metric('Buffer', _frames(metrics?.bufferFrames),
                  metrics == null
                      ? 'Unavailable'
                      : '${metrics.bufferDurationMs.toStringAsFixed(2)} ms'),
              _metric('Peak input', _db(metrics?.peakInputDbfs),
                  'Measured DSP input'),
              _metric('Peak output', _db(metrics?.peakOutputDbfs),
                  'Measured endpoint output'),
              _metric('Limiter reduction', _db(metrics?.limiterReductionDb),
                  'Measured limiter state'),
              _metric('Frames rendered', _integer(metrics?.framesProcessed),
                  'Total frames'),
              _metric('Callbacks', _integer(metrics?.callbacks),
                  'Total render callbacks'),
              _metric('Underruns', _integer(metrics?.underruns),
                  'Backend counter'),
              _metric('Glitches', _integer(metrics?.glitches),
                  'Backend counter'),
              _metric('Deadline misses', _integer(metrics?.deadlineMisses),
                  'Callback deadline counter'),
              _metric('Clipped samples', _integer(metrics?.clippedSamples),
                  'Output clamp counter'),
              _metric('Non-finite samples', _integer(metrics?.nonFiniteSamples),
                  'Output containment counter'),
              _metric('Backend errors', _integer(metrics?.backendErrors),
                  'Backend error counter'),
              _metric('Device disconnects', _integer(metrics?.deviceDisconnects),
                  'Endpoint change counter'),
            ],
          ),
          const SizedBox(height: UamSpacing.xl),
          UamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const UamSectionHeader(
                  title: 'Stream identity',
                  subtitle: 'Backend-reported stream state',
                ),
                const SizedBox(height: UamSpacing.lg),
                UamKeyValue(label: 'BACKEND', value: state.backendName ?? 'Unavailable'),
                UamKeyValue(
                  label: 'ENDPOINT',
                  value: state.activeEndpoint ?? state.selectedEndpoint ?? 'Unavailable',
                ),
                UamKeyValue(
                  label: 'FORMAT',
                  value: state.sampleRateHz == null
                      ? 'Unavailable'
                      : '${state.sampleRateHz} Hz / ${state.bitDepth ?? '?'} bit',
                ),
                UamKeyValue(
                  label: 'BYPASS',
                  value: state.bypassed ? 'Enabled' : 'Disabled',
                ),
                UamKeyValue(
                  label: 'TEST TONE',
                  value: state.testToneEnabled ? 'Enabled' : 'Disabled',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _metric(String label, String value, String caption) =>
      UamMetricTile(
        label: label,
        value: value,
        caption: caption,
        icon: Icons.analytics_outlined,
        tone: value == 'Unavailable' ? UamStatusTone.muted : UamStatusTone.info,
      );

  static String _us(double? value) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(1)} µs';
  static String _ms(double? value) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(2)} ms';
  static String _percent(double? value) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(2)}%';
  static String _db(double? value) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(2)} dBFS';
  static String _frames(int? value) =>
      value == null ? 'Unavailable' : '$value frames';
  static String _integer(int? value) => value == null ? 'Unavailable' : '$value';
}
