import 'package:flutter/material.dart' hide DiagnosticLevel;

import '../../../bridge/rust_api.dart';
import '../../../core/result/result.dart';
import '../../../design_system/components/uam_components.dart';
import '../../../design_system/theme/uam_theme.dart';
import '../../../design_system/tokens/uam_colors.dart';
import '../../../design_system/tokens/uam_spacing.dart';
import '../../../design_system/tokens/uam_typography.dart';
import '../../audio_engine/application/engine_controller.dart';
import '../../audio_engine/domain/diagnostic_entry.dart';

/// Phase 0 Rust interoperability evidence, kept reachable from Settings.
class RustCoreProofPage extends StatefulWidget {
  const RustCoreProofPage({required this.engineController, super.key});

  final EngineController engineController;

  @override
  State<RustCoreProofPage> createState() => _RustCoreProofPageState();
}

class _RustCoreProofPageState extends State<RustCoreProofPage> {
  EngineInfo? _info;
  String? _failureMessage;
  String? _failureDetail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    // Reuse the existing typed bridge through the engine controller's gateway.
    final gateway = _GatewayProbe();
    final Result<EngineInfo> result = await gateway.loadEngineInfo();
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      switch (result) {
        case Success<EngineInfo>(value: final info):
          _info = info;
          _failureMessage = null;
          _failureDetail = null;
        case Failure<EngineInfo>(failure: final failure):
          _info = null;
          _failureMessage = failure.message;
          _failureDetail = failure.detail;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(title: const Text('Rust core proof')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(UamSpacing.xxl),
          children: <Widget>[
            const UamNotice(
              tone: UamStatusTone.info,
              title: 'Phase 0 interoperability evidence',
              message:
                  'This screen displays exactly the metadata the compiled Rust '
                  'core reports. It states which capabilities exist and which do '
                  'not. It never claims audio processing.',
            ),
            const SizedBox(height: UamSpacing.xl),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(UamSpacing.empty),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_failureMessage != null)
              UamNotice(
                tone: UamStatusTone.error,
                title: 'Rust core unavailable',
                message: _failureDetail == null
                    ? _failureMessage!
                    : '$_failureMessage\n$_failureDetail',
              )
            else if (_info != null)
              _InfoCard(info: _info!),
            const SizedBox(height: UamSpacing.xl),
            UamEmptyState(
              icon: Icons.verified_outlined,
              title: 'Engine status from the application shell',
              description:
                  'The Audio Engine module reads the same core through '
                  'EngineInfoGateway. Status: '
                  '${widget.engineController.state.status.label}.',
            ),
            const SizedBox(height: UamSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  widget.engineController.addEvent(
                    DiagnosticLevel.info,
                    'Rust core proof reloaded.',
                  );
                  _load();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reload core information'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _GatewayProbe {
  Future<Result<EngineInfo>> loadEngineInfo() => RustApi().loadEngineInfo();
}

final class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.info});

  final EngineInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: UamSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 190,
            child: Text(
              label,
              style: UamTypography.technicalLabel.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: UamTypography.body.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Core information',
            style: UamTypography.sectionTitle.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: UamSpacing.lg),
          row('Product', info.productName),
          row('Core engine version', info.coreEngineVersion),
          row('Bridge ABI', '${info.bridgeAbiVersion}'),
          row('Implementation status', info.rustImplementationStatus),
          row('Processing scope', info.audioProcessingScope),
          const SizedBox(height: UamSpacing.md),
          Text(
            'Supported prototype functionality',
            style: UamTypography.technicalLabel.copyWith(
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: UamSpacing.sm),
          Wrap(
            spacing: UamSpacing.sm,
            runSpacing: UamSpacing.sm,
            children: <Widget>[
              for (final feature in info.supportedPrototypeFunctionality)
                CapabilityBadge(label: feature, tone: UamStatusTone.success),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compatibility alias for the Phase 0 test and any external import.
typedef PhaseZeroHomePage = RustCoreProofPage;
