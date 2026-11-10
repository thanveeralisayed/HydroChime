import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/models/beverage_type.dart';
import '../providers/analytics_provider.dart';
import '../providers/hydration_providers.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int? _selectedBarIndex;

  String _consistencySubtitle(int score, AnalyticsRange range) {
    if (score == 0) {
      return range == AnalyticsRange.day
          ? 'Log hydration to start pacing score'
          : 'No fluid intake recorded in this period';
    }
    if (score >= 85) return 'Optimal pacing throughout waking hours';
    if (score >= 65) return 'Steady hydration cadence with minor gaps';
    return 'Try smaller, more frequent sips across the day';
  }

  Color _beverageColor(BeverageType type, HydroChimeColors palette) {
    return switch (type) {
      BeverageType.water => palette.primaryVital,
      BeverageType.electrolytes => palette.primaryAtmosphere,
      BeverageType.herbalTea => const Color(0xFF7DD3FC),
      BeverageType.coffee => const Color(0xFFF59E0B),
    };
  }

  void _openAnalyticsTuneSheet(HydrationState? hydration) {
    final palette = HydroChimeColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: palette.borderSubtle),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Consistency & Goal Parameters',
                  style: AppTypography.headlineMedium(color: palette.textPrimary),
                ),
                const SizedBox(height: 12),
                Text(
                  'Daily target uses your body weight baseline, active workout minutes (+12 ml/min), and open-meteo weather index.',
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
                if (hydration != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Current Adjusted Target: ${hydration.targetVolumeMl} ml',
                    style: TextStyle(
                      color: palette.primaryAtmosphere,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primaryVital,
                      foregroundColor:
                          palette.isDark ? Colors.black : Colors.white,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(mainTabIndexProvider.notifier).setTab(1);
                    },
                    child: const Text('Adjust Climate & Workout Calibration'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openExportHistoryDialog() async {
    final vault = await ref.read(vaultExportServiceProvider.future);
    final csv = await vault.exportToCsv();
    String? savedPath;
    try {
      savedPath = await vault.saveCsvToDocuments();
    } catch (_) {
      savedPath = null;
    }

    if (!mounted) return;
    final palette = HydroChimeColors.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.surfaceElevated,
          title: Text(
            'Export Hydration History',
            style: AppTypography.headlineMedium(color: palette.textPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (savedPath != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Saved CSV to: $savedPath',
                      style: TextStyle(
                        color: palette.primaryAtmosphere,
                        fontSize: 11,
                      ),
                    ),
                  ),
                Container(
                  width: double.maxFinite,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.borderSubtle),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      csv.trim(),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: csv));
                if (!ctx.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('CSV history copied to clipboard')),
                );
              },
              child: Text(
                'Copy CSV',
                style: TextStyle(color: palette.primaryAtmosphere),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Close',
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final selectedRange = ref.watch(analyticsRangeProvider);
    final analyticsAsync = ref.watch(analyticsProvider);
    final hydrationAsync = ref.watch(hydrationNotifierProvider);

    final hydrationState = switch (hydrationAsync) {
      AsyncData(:final value) => value,
      _ => null,
    };

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: analyticsAsync.when(
          data: (data) {
            final maxBarVol = data.bars.fold<int>(
              hydrationState?.targetVolumeMl ?? 1000,
              (maxVal, bar) => math.max(maxVal, bar.volumeMl),
            );
            final selectedBar = (_selectedBarIndex != null &&
                    _selectedBarIndex! < data.bars.length)
                ? data.bars[_selectedBarIndex!]
                : null;

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      key: const Key('analytics_tune_button'),
                      tooltip: 'Calibration & goal details',
                      icon: Icon(
                        Icons.tune,
                        color: palette.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => _openAnalyticsTuneSheet(hydrationState),
                    ),
                    Text(
                      'ANALYTICS',
                      style: AppTypography.labelMicro(
                        color: palette.textSecondary,
                      ),
                    ),
                    IconButton(
                      key: const Key('analytics_refresh_button'),
                      tooltip: 'Refresh analytics',
                      icon: Icon(
                        Icons.refresh,
                        color: palette.textSecondary,
                        size: 20,
                      ),
                      onPressed: () {
                        ref.invalidate(hydrationNotifierProvider);
                        ref.invalidate(analyticsProvider);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(content: Text('Analytics refreshed')),
                          );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Time Filter Pills
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildFilterPill(
                      title: 'Day',
                      range: AnalyticsRange.day,
                      selectedRange: selectedRange,
                      palette: palette,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      title: 'Week',
                      range: AnalyticsRange.week,
                      selectedRange: selectedRange,
                      palette: palette,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      title: 'Month',
                      range: AnalyticsRange.month,
                      selectedRange: selectedRange,
                      palette: palette,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                // Consistency Arc Hero
                Center(
                  child: SizedBox(
                    width: 190,
                    height: 190,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(180, 180),
                          painter: _ConsistencyArcPainter(
                            scorePercent:
                                (data.consistencyScore / 100.0).clamp(0.0, 1.0),
                            palette: palette,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '${data.consistencyScore}',
                                  style: TextStyle(
                                    fontFamily: AppTypography.headlineFontFamily,
                                    fontSize: 58,
                                    fontWeight: FontWeight.bold,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                Text(
                                  '%',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w300,
                                    color: palette.primaryAtmosphere,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'CONSISTENCY',
                              style: AppTypography.labelMicro(
                                color: palette.primaryAtmosphere.withOpacity(0.85),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _consistencySubtitle(data.consistencyScore, data.range),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (selectedBar != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.primaryAtmosphere.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        '${selectedBar.fullLabel} • ${selectedBar.volumeMl} ml',
                        style: TextStyle(
                          color: palette.primaryAtmosphere,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                // Intake Bar Chart
                Container(
                  height: 118,
                  padding: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: palette.borderSubtle),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(data.bars.length, (i) {
                      final bar = data.bars[i];
                      final ratio = maxBarVol > 0
                          ? (bar.volumeMl / maxBarVol).clamp(0.0, 1.0)
                          : 0.0;
                      final barHeight =
                          bar.volumeMl > 0 ? math.max(8.0, ratio * 80.0) : 4.0;
                      final isSelected = _selectedBarIndex == i;
                      final barWidth =
                          data.bars.length > 20 ? 4.0 : (data.bars.length > 10 ? 6.0 : 8.0);

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedBarIndex = isSelected ? null : i;
                          }),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: barWidth,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: (bar.isHighlighted || isSelected)
                                      ? palette.primaryAtmosphere
                                      : palette.textSecondary.withOpacity(
                                          bar.volumeMl > 0 ? 0.35 : 0.14,
                                        ),
                                  borderRadius: BorderRadius.circular(9999),
                                  boxShadow: (bar.isHighlighted || isSelected)
                                      ? [
                                          BoxShadow(
                                            color: palette.primaryAtmosphere
                                                .withOpacity(0.55),
                                            blurRadius: 10,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 14,
                                child: Text(
                                  bar.label,
                                  overflow: TextOverflow.visible,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: (bar.isHighlighted || isSelected)
                                        ? palette.primaryAtmosphere
                                        : palette.textSecondary,
                                    fontSize: data.bars.length > 20 ? 9 : 11,
                                    fontWeight: (bar.isHighlighted || isSelected)
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          data.range == AnalyticsRange.day
                              ? 'Today Total: '
                              : 'Daily Average: ',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${(data.dailyAverageMl / 1000).toStringAsFixed(1)} L',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      data.range == AnalyticsRange.day
                          ? (data.targetsMetCount > 0
                              ? 'Daily Target Met'
                              : 'Pacing In Progress')
                          : 'Target Met ${data.targetsMetCount} of ${data.totalPeriodDays} days',
                      style: TextStyle(
                        color: palette.primaryAtmosphere,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Beverage Distribution Section
                Text(
                  'BEVERAGE DISTRIBUTION',
                  style: AppTypography.labelMicro(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ...data.beverageStats.map(
                  (stat) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildBeverageRow(
                      label: stat.type.displayName,
                      percent: '${stat.percentage}%',
                      color: _beverageColor(stat.type, palette),
                      palette: palette,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Export History Button
                Center(
                  child: TextButton.icon(
                    key: const Key('analytics_export_button'),
                    onPressed: _openExportHistoryDialog,
                    icon: Icon(
                      Icons.ios_share,
                      size: 16,
                      color: palette.primaryAtmosphere,
                    ),
                    label: Text(
                      'Export History',
                      style: TextStyle(
                        color: palette.primaryAtmosphere,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            );
          },
          loading: () => Center(
            child: CircularProgressIndicator(color: palette.primaryVital),
          ),
          error: (err, _) => Center(
            child: Text(
              'Error loading analytics: $err',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String title,
    required AnalyticsRange range,
    required AnalyticsRange selectedRange,
    required HydroChimeColors palette,
  }) {
    final isSelected = selectedRange == range;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedBarIndex = null);
        ref.read(analyticsRangeProvider.notifier).setRange(range);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.primaryAtmosphere.withOpacity(0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: isSelected
                ? palette.primaryAtmosphere.withOpacity(0.55)
                : palette.borderSubtle,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? palette.primaryAtmosphere : palette.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildBeverageRow({
    required String label,
    required String percent,
    required Color color,
    required HydroChimeColors palette,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        Text(
          percent,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ConsistencyArcPainter extends CustomPainter {
  final double scorePercent;
  final HydroChimeColors palette;

  _ConsistencyArcPainter({
    required this.scorePercent,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    final trackPaint = Paint()
      ..color = palette.isDark
          ? const Color(0xFF1F2429)
          : const Color(0xFFF1F4EE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawCircle(center, radius, trackPaint);

    if (scorePercent > 0) {
      final progressPaint = Paint()
        ..color = palette.primaryVital
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      final glowPaint = Paint()
        ..color = palette.primaryVital.withOpacity(palette.isDark ? 0.6 : 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

      final sweep = 2 * math.pi * scorePercent;
      final rect = Rect.fromCircle(center: center, radius: radius);

      canvas.drawArc(rect, -math.pi / 2, sweep, false, glowPaint);
      canvas.drawArc(rect, -math.pi / 2, sweep, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConsistencyArcPainter oldDelegate) =>
      oldDelegate.scorePercent != scorePercent ||
      oldDelegate.palette.isDark != palette.isDark;
}
