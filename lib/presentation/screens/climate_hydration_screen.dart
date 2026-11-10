import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/repositories/weather_repository.dart';
import '../../domain/models/climate_condition.dart';
import '../../domain/services/notification_scheduler.dart';
import '../providers/hydration_providers.dart';
import '../widgets/location_picker_section.dart';
import '../widgets/profile_calibration_sheet.dart';

class ClimateHydrationScreen extends ConsumerStatefulWidget {
  const ClimateHydrationScreen({super.key});

  @override
  ConsumerState<ClimateHydrationScreen> createState() =>
      _ClimateHydrationScreenState();
}

class _ClimateHydrationScreenState
    extends ConsumerState<ClimateHydrationScreen> {
  bool _isSyncing = false;

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

  Future<void> _handleSyncWeather(String cityName) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final result = await ref
          .read(weatherSyncProvider.notifier)
          .refreshWeather(forceRefresh: true);
      if (!mounted || result == null) return;
      final message = switch (result.source) {
        WeatherDataSource.liveApi =>
          'Synced ${result.condition.temperatureCelsius.round()}°C weather for $cityName',
        WeatherDataSource.localCache =>
          'Offline — showing cached weather for $cityName',
        WeatherDataSource.offlineFallback =>
          'Offline — using temperate ${result.condition.temperatureCelsius.round()}°C fallback',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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

    final heatSpikePrev = weatherSync?.previousCondition ??
        const ClimateCondition(
          temperatureCelsius: 25,
          relativeHumidity: 50,
        );

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
                Expanded(
                  child: Row(
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
                      Expanded(
                        child: Text(
                          '$cityName • ${climate.temperatureCelsius.round()}°C',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelMicro(
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
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
            ),
            if (weatherSync?.heatSpikeDetected == true) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  const NotificationScheduler().buildHeatSpikeAlertMessage(
                        previous: heatSpikePrev,
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
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
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            color: palette.primaryAtmosphere,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Pacing: ~$pacingHourly mL / hr',
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
                    ),
                    const SizedBox(width: 8),
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
              key: const Key('climate_sync_button'),
              onTap: () => _handleSyncWeather(cityName),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isSyncing)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: palette.primaryAtmosphere,
                      ),
                    )
                  else
                    Icon(
                      Icons.lock_outline,
                      color: palette.primaryAtmosphere.withOpacity(0.8),
                      size: 13,
                    ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _isSyncing ? 'Syncing weather...' : '$updatedText • Tap to sync',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                      ),
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
  final TextEditingController _customActivityController =
      TextEditingController(text: '0');
  int _activityMinutes = 0;
  LocationSelection _selectedCity = kDefaultCityPresets.first;
  bool _hydratedActivityFromProfile = false;
  bool _hydratedCityFromProfile = false;
  bool _userEditedActivity = false;
  bool _userEditedCity = false;
  bool _isSaving = false;
  String? _activityError;

  @override
  void dispose() {
    _customActivityController.dispose();
    super.dispose();
  }

  void _setActivityMinutes(int minutes, {bool fromUser = true}) {
    setState(() {
      if (fromUser) _userEditedActivity = true;
      _activityMinutes = minutes;
      _activityError = null;
      final str = minutes.toString();
      if (_customActivityController.text != str) {
        _customActivityController.text = str;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final profileAsync = ref.watch(userProfileProvider);

    final profile = switch (profileAsync) {
      AsyncValue(:final value?) => value,
      _ => null,
    };

    if (profile != null) {
      if (!_hydratedActivityFromProfile && !_userEditedActivity) {
        _activityMinutes = profile.dailyActivityMinutes;
        _customActivityController.text = profile.dailyActivityMinutes.toString();
        _hydratedActivityFromProfile = true;
      }
      if (!_hydratedCityFromProfile && !_userEditedCity) {
        _selectedCity = LocationSelection(
          profile.cityName,
          profile.latitude,
          profile.longitude,
          mode: profile.locationMode,
        );
        _hydratedCityFromProfile = true;
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: palette.borderSubtle),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
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
                      onSelected: (_) => _setActivityMinutes(mins),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('custom_activity_input'),
                  controller: _customActivityController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: palette.textPrimary, fontSize: 13),
                  onChanged: (val) {
                    setState(() {
                      _userEditedActivity = true;
                      _activityError = null;
                      final parsed = int.tryParse(val.trim());
                      if (parsed != null && parsed >= 0 && parsed <= 300) {
                        _activityMinutes = parsed;
                      }
                    });
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Custom exertion minutes (0–300)',
                    errorText: _activityError,
                    labelStyle:
                        TextStyle(color: palette.textSecondary, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: palette.borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: palette.primaryVital),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Hyper-Local Weather Region (0.01° quantized)',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                LocationPickerSection(
                  selected: _selectedCity,
                  rootRef: widget.rootRef,
                  onSelected: (loc) {
                    setState(() {
                      _userEditedCity = true;
                      _selectedCity = loc;
                    });
                  },
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primaryVital,
                      foregroundColor:
                          palette.isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSaving
                        ? null
                        : () async {
                            final parsed = int.tryParse(
                              _customActivityController.text.trim(),
                            );
                            if (parsed == null || parsed < 0 || parsed > 300) {
                              setState(
                                () => _activityError = 'Enter 0 to 300 minutes',
                              );
                              return;
                            }
                            setState(() {
                              _isSaving = true;
                              _activityError = null;
                            });
                            try {
                              final oldProfile = await widget.rootRef
                                  .read(userProfileProvider.future);
                              final locationChanged =
                                  (oldProfile.latitude - _selectedCity.latitude)
                                          .abs() >
                                      0.001 ||
                                  (oldProfile.longitude - _selectedCity.longitude)
                                          .abs() >
                                      0.001 ||
                                  oldProfile.cityName != _selectedCity.name;

                              final repo = await widget.rootRef
                                  .read(userProfileRepositoryProvider.future);
                              await repo.updateDailyActivityMinutes(parsed);
                              await repo.updateLocation(
                                _selectedCity.name,
                                _selectedCity.latitude,
                                _selectedCity.longitude,
                                locationMode: _selectedCity.mode,
                              );
                              widget.rootRef.invalidate(userProfileProvider);
                              await widget.rootRef
                                  .read(userProfileProvider.future);
                              if (locationChanged) {
                                await widget.rootRef
                                    .read(weatherSyncProvider.future);
                              }
                              widget.rootRef
                                  .invalidate(hydrationNotifierProvider);
                              await widget.rootRef
                                  .read(hydrationNotifierProvider.future);
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(
                                  () => _activityError =
                                      'Unable to apply calibration: $e',
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _isSaving = false);
                              }
                            }
                          },
                    child: _isSaving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  palette.isDark ? Colors.black : Colors.white,
                            ),
                          )
                        : const Text('Apply Calibration'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
