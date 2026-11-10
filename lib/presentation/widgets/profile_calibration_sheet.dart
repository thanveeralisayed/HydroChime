import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../providers/hydration_providers.dart';

String formatHour12(int hour24) {
  final normalized = ((hour24 % 24) + 24) % 24;
  final suffix = normalized < 12 ? 'AM' : 'PM';
  final hour12 = normalized == 0
      ? 12
      : (normalized > 12 ? normalized - 12 : normalized);
  return '$hour12:00 $suffix';
}

String formatWeightKg(double weightKg) {
  final rounded1 = double.parse(weightKg.toStringAsFixed(1));
  if (rounded1 == rounded1.roundToDouble()) {
    return '${rounded1.toInt()} kg';
  }
  return '${rounded1.toStringAsFixed(1)} kg';
}

void showProfileCalibrationSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _ProfileCalibrationSheet(rootRef: ref);
    },
  );
}

class _ProfileCalibrationSheet extends ConsumerWidget {
  final WidgetRef rootRef;

  const _ProfileCalibrationSheet({required this.rootRef});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HydroChimeColors.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final hydrationAsync = ref.watch(hydrationNotifierProvider);

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: palette.borderSubtle),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: SafeArea(
        top: false,
        child: profileAsync.when(
          data: (profile) {
            final targetMl = switch (hydrationAsync) {
              AsyncData(:final value) => value.targetVolumeMl,
              _ => profile.effectiveBaselineMl,
            };

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.borderSubtle,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Hydration Profile',
                      style: AppTypography.headlineMedium(
                        color: palette.textPrimary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: palette.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  palette,
                  'Body Weight',
                  formatWeightKg(profile.weightKg),
                ),
                _buildInfoRow(
                  palette,
                  'Daily Target',
                  '$targetMl ml',
                ),
                _buildInfoRow(
                  palette,
                  'Daily Exertion',
                  '${profile.dailyActivityMinutes} min',
                ),
                _buildInfoRow(
                  palette,
                  'Location',
                  profile.cityName,
                ),
                _buildInfoRow(
                  palette,
                  'Active Window',
                  '${formatHour12(profile.activeWindowStartHour)} – ${formatHour12(profile.activeWindowEndHour)}',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primaryVital,
                      foregroundColor:
                          palette.isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      rootRef.read(mainTabIndexProvider.notifier).setTab(3);
                    },
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Open Settings & Vault'),
                  ),
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Unable to load profile: $e',
              style: TextStyle(color: palette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(HydroChimeColors palette, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

