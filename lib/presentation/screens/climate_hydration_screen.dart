import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/models/climate_condition.dart';
import '../../domain/services/notification_scheduler.dart';
import '../providers/hydration_providers.dart';
import '../widgets/profile_calibration_sheet.dart';

class _CityPreset {
  final String name;
  final double latitude;
  final double longitude;

  const _CityPreset(this.name, this.latitude, this.longitude);
}

const List<_CityPreset> _cityPresets = [
  _CityPreset('Austin', 30.27, -97.74),
  _CityPreset('Seattle', 47.61, -122.33),
  _CityPreset('Phoenix', 33.45, -112.07),
  _CityPreset('New York', 40.71, -74.01),
  _CityPreset('London', 51.51, -0.13),
  _CityPreset('Tokyo', 35.68, 139.77),
];

class ClimateHydrationScreen extends ConsumerWidget {
  const ClimateHydrationScreen({super.key});

  String _advisoryBadge(ClimateCondition climate) {
    if (climate.temperatureCelsius >= 30 ||
        (climate.temperatureCelsius >= 28 && climate.relativeHumidity > 75)) {
      return 'HEAT ADVISORY ACTIVE';
    }
    if (climate.temperatureCelsius >= 22) {
      return 'WARM CLIMATE ADAPTATION';
    }
    return 'TEMPERATE AMBIENT';
  }

  String _conditionSummary(ClimateCondition climate) {
    final t = climate.temperatureCelsius;
    final h = climate.relativeHumidity;
    if (t >= 30) {
      return h < 35 ? 'Hot & Dry' : (h > 70 ? 'Hot & Humid' : 'Warm & Sunny');
    }
    if (t >= 22) {
      return h > 70 ? 'Warm & Humid' : 'Warm & Breezy';
    }
    return 'Cool & Comfortable';
  }

  void _openCalibrationSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ClimateTuneSheet(rootRef: ref),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HydroChimeColors.of(context);
    final climate = ref.watch(currentClimateProvider);
    final hydrationAsync = ref.watch(hydrationNotifierProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final pacingAsync = ref.watch(pacingScheduleProvider);
    final weatherSyncAsync = ref.watch(weatherSyncProvider);

    final profile = switch (profileAsync) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final cityName = profile?.cityName ?? 'Austin';
    final weatherSync = switch (weatherSyncAsync) {
      AsyncData(:final value) => value,
      _ => null,
    };

    final hydrationState = switch (hydrationAsync) {
      AsyncValue(:final value?) => value,
      _ => null,
    };

    final pacingHourly = switch (pacingAsync) {
      AsyncData(:final value) => value.recommendedHourlyMl,
      _ => 230,
    };

    final multiplier = hydrationState?.breakdown.climateMultiplier ?? 1.0;
    final impactPct = ((multiplier - 1.0) * 100).round();
    final impactText = !(profile?.weatherAdaptationEnabled ?? true)
        ? 'Weather adaptation paused in Settings'
        : impactPct > 0
            ? 'Thermal load increases fluid demand by +$impactPct%'
            : 'Ambient conditions keep baseline hydration (0% delta)';

    final updatedText = weatherSync == null
        ? 'On-device hyper-local calibration'
        : 'Synced ${DateFormat('h:mm a').format(weatherSync.lastUpdated)}';

    final goalPercent =
        hydrationState != null ? (hydrationState.percentage * 100).round() : 0;
    final barFactor =
        hydrationState != null ? hydrationState.percentage.clamp(0.05, 1.0) : 0.05;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette.primaryAtmosphere,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: palette.primaryAtmosphere,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$cityName • ${climate.temperatureCelsius.round()}°C',
                      style: AppTypography.labelMicro(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      key: const Key('climate_tune_button'),
                      tooltip: 'Calibrate exertion & location',
                      icon: Icon(
                        Icons.tune,
                        color: palette.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => _openCalibrationSheet(context, ref),
                    ),
                    GestureDetector(
                      key: const Key('climate_profile_button'),
                      onTap: () => showProfileCalibrationSheet(context, ref),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              palette.primaryAtmosphere.withOpacity(0.2),
                              palette.primaryDeep.withOpacity(0.2),
                            ],
                          ),
                          border: Border.all(
                            color: palette.primaryAtmosphere.withOpacity(0.25),
                          ),
                        ),
                        child: Icon(
                          Icons.person_outline,
                          color: palette.primaryAtmosphere,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Dynamic Climate Advisory Pill
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.primaryDeep.withOpacity(palette.isDark ? 0.25 : 0.1),
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(
                    color: palette.primaryVital.withOpacity(0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      climate.temperatureCelsius >= 22
                          ? Icons.wb_sunny_outlined
                          : Icons.ac_unit_outlined,
                      color: palette.primaryAtmosphere,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _advisoryBadge(climate),
                      style: TextStyle(
                        color: palette.primaryAtmosphere,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (weatherSync?.heatSpikeDetected == true) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  const NotificationScheduler().buildHeatSpikeAlertMessage(
                        previous: const ClimateCondition(
                          temperatureCelsius: 25,
                          relativeHumidity: 50,
                        ),
                        current: climate,
                        cityName: cityName,
                      ) ??
                      'Rapid heat spike detected',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.primaryAtmosphere,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Large Temp Hero
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${climate.temperatureCelsius.round()}',
                    style: TextStyle(
                      fontFamily: AppTypography.headlineFontFamily,
                      fontSize: 88,
                      fontWeight: FontWeight.w200,
                      color: palette.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    '°',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w300,
                      color: palette.primaryAtmosphere.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                _conditionSummary(climate),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                impactText,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Humidity & Apparent Temp Pill
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.isDark
                      ? Colors.white.withOpacity(0.03)
                      : palette.surfaceCard,
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(color: palette.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.water_drop_outlined,
                      color: palette.primaryAtmosphere,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${climate.relativeHumidity.round()}% Humidity',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.borderSubtle,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.air,
                      color: palette.primaryAtmosphere,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Apparent ${(climate.apparentTemperatureCelsius ?? climate.temperatureCelsius).toStringAsFixed(1)}°C',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 36),
            // Adjusted Goal Display
            if (hydrationState != null) ...[
              Builder(builder: (_) {
                final base = hydrationState.breakdown.baselineMl;
                final active = hydrationState.breakdown.activityMl;
                final climateDelta = hydrationState.breakdown.climateDeltaMl;
                final total = hydrationState.breakdown.totalTargetMl;

                return Column(
                  children: [
                    Text(
                      "Today's Adjusted Goal",
                      style: AppTypography.labelMicro(
                        color: palette.primaryAtmosphere,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$total',
                          style: TextStyle(
                            fontFamily: AppTypography.headlineFontFamily,
                            fontSize: 54,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'mL',
                          style: TextStyle(
                            fontSize: 16,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$base base + $active active + $climateDelta climate',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
              }),
            ],
            const SizedBox(height: 28),
            // Dynamic Pacing bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          color: palette.primaryAtmosphere,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pacing: ~$pacingHourly mL / hr',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$goalPercent% Optimal',
                      style: TextStyle(
                        color: palette.primaryAtmosphere,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 6,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: palette.isDark
                        ? Colors.white.withOpacity(0.06)
                        : palette.borderSubtle,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: barFactor,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.primaryDeep,
                            palette.primaryAtmosphere,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(9999),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primaryAtmosphere.withOpacity(0.45),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Estimated Water Loss Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.isDark
                    ? Colors.white.withOpacity(0.02)
                    : palette.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.borderSubtle),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.primaryAtmosphere.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.water_drop,
                      color: palette.primaryAtmosphere,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated Water Loss',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Perspiration & respiration rate',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${hydrationState?.estimatedWaterLossMl ?? 0} mL',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Privacy Lock & Refresh Footnote
            GestureDetector(
              onTap: () => ref
                  .read(weatherSyncProvider.notifier)
                  .refreshWeather(forceRefresh: true),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: palette.primaryAtmosphere.withOpacity(0.8),
                    size: 13,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$updatedText • Tap to sync',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _ClimateTuneSheet extends ConsumerStatefulWidget {
  final WidgetRef rootRef;

  const _ClimateTuneSheet({required this.rootRef});

  @override
  ConsumerState<_ClimateTuneSheet> createState() => _ClimateTuneSheetState();
}

class _ClimateTuneSheetState extends ConsumerState<_ClimateTuneSheet> {
  late int _activityMinutes;
  late _CityPreset _selectedCity;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final profileAsync = ref.watch(userProfileProvider);

    final profile = switch (profileAsync) {
      AsyncValue(:final value?) => value,
      _ => null,
    };

    if (!_initialized && profile != null) {
      _activityMinutes = profile.dailyActivityMinutes;
      final currentCityName = profile.cityName;
      _selectedCity = _cityPresets.firstWhere(
        (c) => c.name == currentCityName,
        orElse: () => _CityPreset(
          currentCityName,
          profile.latitude,
          profile.longitude,
        ),
      );
      _initialized = true;
    } else if (!_initialized) {
      _activityMinutes = 0;
      _selectedCity = _cityPresets.first;
    }

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
              'Climate & Exertion Calibration',
              style: AppTypography.headlineMedium(color: palette.textPrimary),
            ),
            const SizedBox(height: 16),
            Text(
              'Daily Workout / Exertion Duration (+12 ml / min)',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [0, 20, 35, 60, 90].map((mins) {
                final isSelected = _activityMinutes == mins;
                return ChoiceChip(
                  label: Text(
                    '$mins min',
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
                  onSelected: (_) => setState(() => _activityMinutes = mins),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            Text(
              'Hyper-Local Weather Region (0.01° quantized)',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cityPresets.map((city) {
                final isSelected = _selectedCity.name == city.name;
                return ChoiceChip(
                  label: Text(
                    city.name,
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
                  onSelected: (_) => setState(() => _selectedCity = city),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.primaryVital,
                  foregroundColor: palette.isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final repo = await widget.rootRef
                      .read(userProfileRepositoryProvider.future);
                  await repo.updateDailyActivityMinutes(_activityMinutes);
                  await repo.updateLocation(
                    _selectedCity.name,
                    _selectedCity.latitude,
                    _selectedCity.longitude,
                  );
                  widget.rootRef.invalidate(userProfileProvider);
                  widget.rootRef.invalidate(hydrationNotifierProvider);
                  await widget.rootRef
                      .read(weatherSyncProvider.notifier)
                      .refreshWeather(forceRefresh: true);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Apply Calibration'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
