import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class ZenCircularFluidGauge extends StatelessWidget {
  final int currentVolumeMl;
  final int targetVolumeMl;
  final double percentage; // 0.0 - 1.0
  final int remainingMl;

  const ZenCircularFluidGauge({
    super.key,
    required this.currentVolumeMl,
    required this.targetVolumeMl,
    required this.percentage,
    required this.remainingMl,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final numberFormat = NumberFormat('#,###');
    final formattedCurrent = numberFormat.format(currentVolumeMl);
    final formattedTarget = numberFormat.format(targetVolumeMl);
    final formattedRemaining = numberFormat.format(remainingMl);
    final percentInt = (percentage * 100).round();

    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient Vitality Glow
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: palette.primaryAtmosphere
                      .withOpacity(palette.isDark ? 0.08 : 0.06),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
          ),
          // Custom Arc Progress
          CustomPaint(
            size: const Size(240, 240),
            painter: _ZenArcPainter(
              percentage: percentage.clamp(0.0, 1.0),
              palette: palette,
            ),
          ),
          // Centered Metrics
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TODAY',
                  style: AppTypography.labelMicro(
                    color: palette.primaryAtmosphere.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        formattedCurrent,
                        style: AppTypography.displayLarge(
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ $formattedTarget ml',
                        style: AppTypography.bodyMedium(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$percentInt%',
                        style: TextStyle(
                          color: palette.primaryAtmosphere,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        ' • ',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '$formattedRemaining ml remaining',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZenArcPainter extends CustomPainter {
  final double percentage;
  final HydroChimeColors palette;

  _ZenArcPainter({
    required this.percentage,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 20) / 2;

    // Track Paint
    final trackPaint = Paint()
      ..color = palette.isDark
          ? Colors.white.withOpacity(0.06)
          : const Color(0xFFF1F4EE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (percentage > 0) {
      final sweepAngle = 2 * math.pi * percentage;

      // Gradient Paint
      final rect = Rect.fromCircle(center: center, radius: radius);
      final gradient = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: (3 * math.pi / 2),
        colors: [
          palette.primaryAtmosphere,
          palette.primaryDeep,
        ],
      );

      final progressPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round;

      // Glow Paint (diffuse aura)
      final glowPaint = Paint()
        ..color = palette.primaryAtmosphere.withOpacity(palette.isDark ? 0.35 : 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

      // Rotate from top (-90 degrees)
      canvas.drawArc(rect, -math.pi / 2, sweepAngle, false, glowPaint);
      canvas.drawArc(rect, -math.pi / 2, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ZenArcPainter oldDelegate) =>
      oldDelegate.percentage != percentage ||
      oldDelegate.palette.isDark != palette.isDark;
}
