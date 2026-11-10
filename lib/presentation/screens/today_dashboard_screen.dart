import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/calculators/hydration_calculator.dart';
import '../../domain/models/beverage_type.dart';
import '../../domain/models/intake_log.dart';
import '../providers/analytics_provider.dart';
import '../providers/hydration_providers.dart';
import '../widgets/beverage_log_dialog.dart';
import '../widgets/profile_calibration_sheet.dart';
import '../widgets/quick_log_bar.dart';
import '../widgets/zen_circular_fluid_gauge.dart';

class TodayDashboardScreen extends ConsumerStatefulWidget {
  const TodayDashboardScreen({super.key});

  @override
  ConsumerState<TodayDashboardScreen> createState() =>
      _TodayDashboardScreenState();
}

class _TodayDashboardScreenState extends ConsumerState<TodayDashboardScreen> {
  String? _toastMessage;
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() => _toastMessage = null);
      }
    });
  }

  void _showLoggedFeedback(int amountMl, BeverageType type) {
    const calc = HydrationCalculator();
    final eff = calc.calculateEffectiveIntake(amountMl, type);
    if (type.multiplier == 1.0) {
      _showToast('Logged +$amountMl ml');
    } else {
      _showToast('Logged +$amountMl ml ($eff ml eff.)');
    }
  }

  Future<void> _openCustomLogModal() async {
    final result = await showBeverageLogDialog(context);
    if (result == null || !mounted) return;

    try {
      await ref.read(hydrationNotifierProvider.notifier).logHydration(
            amountMl: result.volumeMl,
            type: result.type,
            timestamp: result.timestamp,
          );
      if (!mounted) return;
      _showLoggedFeedback(result.volumeMl, result.type);
    } catch (_) {
      if (!mounted) return;
      _showToast('Unable to save hydration log');
    }
  }

  Future<void> _editExistingLog(IntakeLog log) async {
    if (log.id == null) return;
    final result = await showBeverageLogDialog(
      context,
      initialLog: log,
    );
    if (result == null || !mounted) return;

    try {
      await ref.read(hydrationNotifierProvider.notifier).updateLog(
            id: log.id!,
            volumeMl: result.volumeMl,
            type: result.type,
            timestamp: result.timestamp,
          );
      if (!mounted) return;
      _showToast('Updated ${result.volumeMl} ml ${result.type.displayName}');
    } catch (_) {
      if (!mounted) return;
      _showToast('Unable to update hydration log');
    }
  }

  void _openHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HydrationHistorySheet(rootRef: ref),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final hydrationAsync = ref.watch(hydrationNotifierProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final climate = ref.watch(currentClimateProvider);
    ref.watch(pacingScheduleProvider);

    final profile = switch (profileAsync) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final cityName = profile?.cityName ?? 'Austin';
    final isDarkMode = profile?.isDarkMode ?? palette.isDark;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Minimal Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'HydroChime',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.headlineMedium(
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: palette.primaryAtmosphere,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$cityName • ${climate.temperatureCelsius.round()}°C',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          IconButton(
                            key: const Key('theme_toggle_button'),
                            tooltip: isDarkMode
                                ? 'Switch to Light Mode'
                                : 'Switch to Dark Mode',
                            onPressed: () async {
                              final repo = await ref
                                  .read(userProfileRepositoryProvider.future);
                              final nextDark = !isDarkMode;
                              await repo.setDarkMode(nextDark);
                              ref.invalidate(userProfileProvider);
                              if (mounted) {
                                _showToast(
                                  nextDark
                                      ? 'Switched to Dark Mode'
                                      : 'Switched to Light Mode',
                                );
                              }
                            },
                            icon: Icon(
                              isDarkMode
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                              color: palette.textSecondary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            key: const Key('today_profile_button'),
                            onTap: () => showProfileCalibrationSheet(context, ref),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.isDark
                                    ? Colors.white.withOpacity(0.04)
                                    : palette.primaryVital.withOpacity(0.1),
                                border: Border.all(color: palette.borderSubtle),
                              ),
                              child: Icon(
                                Icons.person_outline,
                                color: palette.isDark
                                    ? palette.textSecondary
                                    : palette.primaryVital,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Main Content
                Expanded(
                  child: hydrationAsync.when(
                    data: (state) {
                      return ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        children: [
                          const SizedBox(height: 12),
                          // Hero Circular Gauge
                          Center(
                            child: ZenCircularFluidGauge(
                              currentVolumeMl: state.currentVolumeMl,
                              targetVolumeMl: state.targetVolumeMl,
                              percentage: state.percentage,
                              remainingMl: state.remainingMl,
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Quick Log Action Bar (tap = water, long-press = any beverage)
                          QuickLogBar(
                            onLog: (amount, type) async {
                              try {
                                await ref
                                    .read(hydrationNotifierProvider.notifier)
                                    .logHydration(amountMl: amount, type: type);
                                if (!mounted) return;
                                _showLoggedFeedback(amount, type);
                              } catch (_) {
                                if (!mounted) return;
                                _showToast('Unable to save hydration log');
                              }
                            },
                            onCustomAdd: _openCustomLogModal,
                          ),
                          const SizedBox(height: 32),
                          // Recent Activity
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Recent Activity',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.labelMicro(
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                key: const Key('history_button'),
                                onTap: _openHistorySheet,
                                borderRadius: BorderRadius.circular(9999),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.history,
                                        size: 13,
                                        color: palette.primaryAtmosphere,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'History',
                                        style: TextStyle(
                                          color: palette.primaryAtmosphere,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (state.recentLogs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  'No fluid logged today yet',
                                  style: TextStyle(
                                    color: palette.textTertiary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...state.recentLogs.map((log) {
                              final timeStr =
                                  DateFormat('h:mm a').format(log.timestamp);
                              final hasBonus = log.beverageType.multiplier != 1.0;
                              return InkWell(
                                key: log.id != null
                                    ? Key('recent_log_item_${log.id}')
                                    : null,
                                onTap: () => _editExistingLog(log),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: palette.borderSubtle,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              log.beverageType.displayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: palette.textPrimary,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              hasBonus
                                                  ? '$timeStr • ${log.effectiveVolumeMl} ml eff.'
                                                  : timeStr,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: palette.textTertiary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Row(
                                        children: [
                                          Text(
                                            '+${log.volumeMl} ml',
                                            style: TextStyle(
                                              color: palette.primaryAtmosphere,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (log.id != null) ...[
                                            const SizedBox(width: 4),
                                            IconButton(
                                              tooltip: 'Remove entry',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 28,
                                                minHeight: 28,
                                              ),
                                              onPressed: () async {
                                                await ref
                                                    .read(
                                                        hydrationNotifierProvider
                                                            .notifier)
                                                    .deleteLog(log.id!);
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context)
                                                  ..hideCurrentSnackBar()
                                                  ..showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Removed ${log.volumeMl} ml ${log.beverageType.displayName}',
                                                      ),
                                                      action: SnackBarAction(
                                                        label: 'Undo',
                                                        onPressed: () {
                                                          ref
                                                              .read(
                                                                  hydrationNotifierProvider
                                                                      .notifier)
                                                              .restoreLog(log);
                                                        },
                                                      ),
                                                    ),
                                                  );
                                              },
                                              icon: Icon(
                                                Icons.close,
                                                size: 16,
                                                color: palette.textTertiary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          const SizedBox(height: 40),
                        ],
                      );
                    },
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        color: palette.primaryVital,
                      ),
                    ),
                    error: (err, stack) => Center(
                      child: Text(
                        'Error loading state: $err',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Floating Zen Toast
          if (_toastMessage != null)
            Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.surfaceElevated,
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(color: palette.borderSubtle),
                    boxShadow: [
                      BoxShadow(
                        color: palette.isDark
                            ? Colors.black54
                            : Colors.black.withOpacity(0.1),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette.primaryAtmosphere,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _toastMessage!,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HydrationHistorySheet extends ConsumerStatefulWidget {
  final WidgetRef rootRef;

  const _HydrationHistorySheet({required this.rootRef});

  @override
  ConsumerState<_HydrationHistorySheet> createState() =>
      _HydrationHistorySheetState();
}

class _HydrationHistorySheetState
    extends ConsumerState<_HydrationHistorySheet> {
  late DateTime _selectedDate;
  List<IntakeLog> _logs = const [];
  int _effectiveTotalMl = 0;
  bool _loading = true;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = _today;
    _loadLogsForDate();
  }

  Future<void> _loadLogsForDate() async {
    setState(() => _loading = true);
    final repo = await widget.rootRef.read(intakeLogRepositoryProvider.future);
    final logs = await repo.getLogsForDate(_selectedDate);
    final effTotal = await repo.getEffectiveVolumeForDate(_selectedDate);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _effectiveTotalMl = effTotal;
      _loading = false;
    });
  }

  Future<void> _stepDate(int days) async {
    final next = _selectedDate.add(Duration(days: days));
    if (next.isAfter(_today)) return;
    setState(() => _selectedDate = next);
    await _loadLogsForDate();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: _today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
    await _loadLogsForDate();
  }

  Future<void> _addLogForSelectedDate() async {
    final res = await showBeverageLogDialog(
      context,
      targetDate: _selectedDate,
    );
    if (res == null || !mounted) return;
    await widget.rootRef.read(hydrationNotifierProvider.notifier).logHydration(
          amountMl: res.volumeMl,
          type: res.type,
          timestamp: res.timestamp,
        );
    widget.rootRef.invalidate(analyticsProvider);
    await _loadLogsForDate();
  }

  Future<void> _editHistoryLog(IntakeLog log) async {
    if (log.id == null) return;
    final res = await showBeverageLogDialog(
      context,
      initialLog: log,
    );
    if (res == null || !mounted) return;
    await widget.rootRef.read(hydrationNotifierProvider.notifier).updateLog(
          id: log.id!,
          volumeMl: res.volumeMl,
          type: res.type,
          timestamp: res.timestamp,
        );
    widget.rootRef.invalidate(analyticsProvider);
    await _loadLogsForDate();
  }

  Future<void> _deleteHistoryLog(IntakeLog log) async {
    if (log.id == null) return;
    await widget.rootRef
        .read(hydrationNotifierProvider.notifier)
        .deleteLog(log.id!);
    widget.rootRef.invalidate(analyticsProvider);
    await _loadLogsForDate();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final isToday = _selectedDate == _today;
    final isYesterday =
        _selectedDate == _today.subtract(const Duration(days: 1));
    final dateTitle = isToday
        ? 'Today • ${DateFormat('MMM d').format(_selectedDate)}'
        : isYesterday
            ? 'Yesterday • ${DateFormat('MMM d').format(_selectedDate)}'
            : DateFormat('EEE, MMM d, yyyy').format(_selectedDate);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: palette.borderSubtle),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hydration History',
                  style: AppTypography.headlineMedium(color: palette.textPrimary),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: palette.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Date Navigator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: palette.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.borderSubtle),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    key: const Key('history_prev_day'),
                    tooltip: 'Previous day',
                    onPressed: () => _stepDate(-1),
                    icon: Icon(Icons.chevron_left, color: palette.textPrimary),
                  ),
                  InkWell(
                    key: const Key('history_date_picker_button'),
                    onTap: _pickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: palette.primaryAtmosphere,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dateTitle,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('history_next_day'),
                    tooltip: 'Next day',
                    onPressed: isToday ? null : () => _stepDate(1),
                    icon: Icon(
                      Icons.chevron_right,
                      color: isToday
                          ? palette.textTertiary.withOpacity(0.4)
                          : palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Effective intake: $_effectiveTotalMl ml',
                  style: TextStyle(
                    color: palette.primaryAtmosphere,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton.icon(
                  key: const Key('history_add_button'),
                  onPressed: _addLogForSelectedDate,
                  icon: Icon(
                    Icons.add,
                    size: 15,
                    color: palette.primaryAtmosphere,
                  ),
                  label: Text(
                    'Add entry',
                    style: TextStyle(
                      color: palette.primaryAtmosphere,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: _loading
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                          color: palette.primaryVital,
                        ),
                      ),
                    )
                  : _logs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'No entries recorded for this date',
                              style: TextStyle(
                                color: palette.textTertiary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _logs.length,
                          itemBuilder: (_, idx) {
                            final log = _logs[idx];
                            final timeStr =
                                DateFormat('h:mm a').format(log.timestamp);
                            return InkWell(
                              onTap: () => _editHistoryLog(log),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom:
                                        BorderSide(color: palette.borderSubtle),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          log.beverageType.displayName,
                                          style: TextStyle(
                                            color: palette.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '$timeStr • ${log.effectiveVolumeMl} ml eff.',
                                          style: TextStyle(
                                            color: palette.textTertiary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '+${log.volumeMl} ml',
                                          style: TextStyle(
                                            color: palette.primaryAtmosphere,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (log.id != null)
                                          IconButton(
                                            tooltip: 'Delete entry',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 28,
                                              minHeight: 28,
                                            ),
                                            onPressed: () =>
                                                _deleteHistoryLog(log),
                                            icon: Icon(
                                              Icons.close,
                                              size: 16,
                                              color: palette.textTertiary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
