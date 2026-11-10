import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/calculators/hydration_calculator.dart';
import '../../domain/models/beverage_type.dart';
import '../providers/hydration_providers.dart';
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

  Future<void> _openCustomLogModal() async {
    final result = await showDialog<({int volumeMl, BeverageType type})>(
      context: context,
      builder: (ctx) => const _CustomBeverageDialog(),
    );
    if (result == null || !mounted) return;

    await ref
        .read(hydrationNotifierProvider.notifier)
        .logHydration(amountMl: result.volumeMl, type: result.type);
    if (!mounted) return;

    const calc = HydrationCalculator();
    final eff = calc.calculateEffectiveIntake(result.volumeMl, result.type);
    if (result.type.multiplier == 1.0) {
      _showToast('Logged +${result.volumeMl} ml');
    } else {
      _showToast('Logged +${result.volumeMl} ml ($eff ml eff.)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final hydrationAsync = ref.watch(hydrationNotifierProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final climate = ref.watch(currentClimateProvider);

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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HydroChime',
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
                              Text(
                                '$cityName • ${climate.temperatureCelsius.round()}°C',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
                          // Quick Log Action Bar
                          QuickLogBar(
                            onLog: (amount, type) {
                              ref
                                  .read(hydrationNotifierProvider.notifier)
                                  .logHydration(amountMl: amount, type: type);
                              _showToast('Logged +$amount ml');
                            },
                            onCustomAdd: _openCustomLogModal,
                          ),
                          const SizedBox(height: 32),
                          // Recent Activity
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Recent Activity',
                                style: AppTypography.labelMicro(
                                  color: palette.textSecondary,
                                ),
                              ),
                              Text(
                                'Auto-balanced',
                                style: TextStyle(
                                  color: palette.textTertiary,
                                  fontSize: 12,
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
                              return Container(
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
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          log.beverageType.displayName,
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
                                                  .read(hydrationNotifierProvider
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

class _CustomBeverageDialog extends StatefulWidget {
  const _CustomBeverageDialog();

  @override
  State<_CustomBeverageDialog> createState() => _CustomBeverageDialogState();
}

class _CustomBeverageDialogState extends State<_CustomBeverageDialog> {
  late final TextEditingController _controller;
  BeverageType _selectedType = BeverageType.water;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '250');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final rawVal = int.tryParse(_controller.text.trim()) ?? 0;
    final effectiveVal =
        const HydrationCalculator().calculateEffectiveIntake(rawVal, _selectedType);

    return AlertDialog(
      backgroundColor: palette.surfaceElevated,
      title: Text(
        'Log Beverage & Volume',
        style: AppTypography.headlineMedium(color: palette.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Beverage Type',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BeverageType.values.map((type) {
                final isSelected = _selectedType == type;
                return ChoiceChip(
                  label: Text(
                    type.displayName,
                    style: TextStyle(
                      color: isSelected
                          ? (palette.isDark ? Colors.black : Colors.white)
                          : palette.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: palette.primaryVital,
                  backgroundColor: palette.surfaceCard,
                  side: BorderSide(color: palette.borderSubtle),
                  onSelected: (_) => setState(() => _selectedType = type),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              style: TextStyle(color: palette.textPrimary),
              onChanged: (_) => setState(() => _errorText = null),
              decoration: InputDecoration(
                labelText: 'Volume (mL)',
                errorText: _errorText,
                labelStyle: TextStyle(color: palette.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.primaryVital),
                ),
                errorBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.redAccent),
                ),
                focusedErrorBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              rawVal > 0
                  ? '$rawVal ml × ${_selectedType.multiplier}x = $effectiveVal ml effective'
                  : 'Efficiency multiplier: ${_selectedType.multiplier}x',
              style: TextStyle(
                color: palette.primaryAtmosphere,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.primaryVital,
            foregroundColor: palette.isDark ? Colors.black : Colors.white,
          ),
          onPressed: () {
            final val = int.tryParse(_controller.text.trim());
            if (val == null || val <= 0 || val > 5000) {
              setState(
                () => _errorText = 'Enter a volume between 1 and 5000 ml',
              );
              return;
            }
            Navigator.pop(context, (volumeMl: val, type: _selectedType));
          },
          child: const Text('Log'),
        ),
      ],
    );
  }
}
