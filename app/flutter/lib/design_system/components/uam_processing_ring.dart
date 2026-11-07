import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/uam_theme.dart';
import '../tokens/uam_typography.dart';

/// Circular processing summary. It renders an active arc only when the caller
/// explicitly marks verified processing.
class UamProcessingRing extends StatelessWidget {
  const UamProcessingRing({
    required this.primaryLabel,
    required this.secondaryLabel,
    this.active = false,
    this.size = 130,
    super.key,
  });

  final String primaryLabel;
  final String secondaryLabel;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final color = active ? colors.accent : colors.textTertiary;
    return Semantics(
      label: 'Processing: $primaryLabel. $secondaryLabel',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            color: color,
            trackColor: colors.equalizerTrack,
            active: active,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    active ? Icons.graphic_eq : Icons.power_settings_new,
                    size: 22,
                    color: color,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    primaryLabel,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: UamTypography.cardTitle.copyWith(
                      color: colors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    secondaryLabel.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: UamTypography.badge.copyWith(
                      color: active ? colors.accent : colors.textTertiary,
                      fontSize: 7,
                    ),
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

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.color,
    required this.trackColor,
    required this.active,
  });

  final Color color;
  final Color trackColor;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = trackColor.withValues(alpha: 0.55);
    canvas.drawCircle(center, radius, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 3 / 2,
        colors: <Color>[color.withValues(alpha: 0.25), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      active ? math.pi * 1.65 : math.pi * 0.55,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.active != active;
  }
}
