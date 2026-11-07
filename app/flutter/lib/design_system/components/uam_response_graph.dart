import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/models/equalizer_configuration.dart';
import '../../shared/utils/equalizer_response.dart';
import '../theme/uam_theme.dart';
import '../tokens/uam_colors.dart';
import '../tokens/uam_typography.dart';

/// Equalizer response graph. The curve is calculated from the current band
/// configuration; it is not a live audio measurement.
class UamResponseGraph extends StatelessWidget {
  const UamResponseGraph({
    required this.bands,
    required this.preampDb,
    required this.bypassed,
    this.height = 210,
    this.showLabels = true,
    this.frequencies = EqConstraints.graphicFrequenciesHz,
    super.key,
  });

  final List<EqBandConfiguration> bands;
  final double preampDb;
  final bool bypassed;
  final double height;
  final bool showLabels;
  final List<double> frequencies;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final semantic = bypassed
        ? 'Equalizer response graph. Bypass is enabled; the displayed response is flat.'
        : 'Equalizer response graph. Preamp ${preampDb.toStringAsFixed(1)} dB with '
              '${bands.length} bands.';
    return Semantics(
      label: semantic,
      image: true,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: colors.curveBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CustomPaint(
            painter: _ResponsePainter(
              bands: bands,
              preampDb: preampDb,
              bypassed: bypassed,
              colors: colors,
              frequencies: frequencies,
              showLabels: showLabels,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _ResponsePainter extends CustomPainter {
  _ResponsePainter({
    required this.bands,
    required this.preampDb,
    required this.bypassed,
    required this.colors,
    required this.frequencies,
    required this.showLabels,
  });

  final List<EqBandConfiguration> bands;
  final double preampDb;
  final bool bypassed;
  final UamColorTokens colors;
  final List<double> frequencies;
  final bool showLabels;

  static const double _minDb = -24;
  static const double _maxDb = 24;
  static const double _minHz = 20;
  static const double _maxHz = 20000;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final grid = Paint()
      ..color = colors.border.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final strongGrid = Paint()
      ..color = colors.borderEmphasis.withValues(alpha: 0.8)
      ..strokeWidth = 1;

    for (var index = 0; index <= 4; index += 1) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final frequency in frequencies) {
      final x = _xFor(frequency, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final zeroY = _yFor(0, size.height);
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), strongGrid);

    final path = Path();
    const points = 180;
    for (var index = 0; index < points; index += 1) {
      final fraction = index / (points - 1);
      final frequency = _minHz * math.pow(_maxHz / _minHz, fraction);
      final value = bypassed
          ? 0.0
          : EqualizerResponse.magnitudeDbAt(
              frequency.toDouble(),
              bands,
              preampDb,
            ).clamp(_minDb, _maxDb);
      final x = fraction * size.width;
      final y = _yFor(value, size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(size.width, zeroY)
      ..lineTo(0, zeroY)
      ..close();
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          colors.accent.withValues(alpha: bypassed ? 0.05 : 0.18),
          colors.accent.withValues(alpha: 0.01),
        ],
      ).createShader(rect);
    canvas.drawPath(fillPath, fill);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = bypassed
          ? colors.textTertiary.withValues(alpha: 0.5)
          : colors.accent;
    canvas.drawPath(path, line);

    if (showLabels) {
      _paintLabels(canvas, size);
    }
  }

  double _xFor(double frequency, double width) {
    final fraction = math.log(frequency / _minHz) / math.log(_maxHz / _minHz);
    return fraction * width;
  }

  double _yFor(double db, double height) {
    final fraction = ((db - _minDb) / (_maxDb - _minDb)).clamp(0.0, 1.0);
    return height - fraction * height;
  }

  void _paintLabels(Canvas canvas, Size size) {
    final labels = <String>['20', '100', '1k', '10k', '20k'];
    final positions = <double>[20, 100, 1000, 10000, 20000];
    for (var index = 0; index < labels.length; index += 1) {
      final painter = TextPainter(
        text: TextSpan(
          text: labels[index],
          style: UamTypography.monospace.copyWith(
            color: colors.textTertiary,
            fontSize: 8,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (_xFor(positions[index], size.width) - painter.width / 2).clamp(
        2.0,
        size.width - painter.width - 2,
      );
      painter.paint(canvas, Offset(x, size.height - painter.height - 3));
    }
  }

  @override
  bool shouldRepaint(covariant _ResponsePainter oldDelegate) {
    return oldDelegate.bands != bands ||
        oldDelegate.preampDb != preampDb ||
        oldDelegate.bypassed != bypassed ||
        oldDelegate.colors != colors;
  }
}
