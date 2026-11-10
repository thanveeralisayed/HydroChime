import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/intake_log_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../data/repositories/weather_repository.dart';
import '../../data/services/ip_location_service.dart';
import '../../data/services/local_notification_service.dart';
import '../../data/services/location_service.dart';
import '../../data/services/vault_export_service.dart';
import '../../data/services/vault_transfer_service.dart';
import '../../data/services/weather_api_client.dart';
import '../../domain/calculators/consistency_calculator.dart';
import '../../domain/calculators/hydration_calculator.dart';
import '../../domain/models/beverage_type.dart';
import '../../domain/models/climate_condition.dart';
import '../../domain/models/intake_log.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/services/notification_scheduler.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final databaseProvider = FutureProvider<Database>((ref) async {
  final appDb = ref.watch(appDatabaseProvider);
  return await appDb.database;
});

final intakeLogRepositoryProvider =
    FutureProvider<IntakeLogRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return IntakeLogRepository(db);
});

final userProfileRepositoryProvider =
    FutureProvider<UserProfileRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return UserProfileRepository(db);
});

final weatherApiClientProvider = Provider<WeatherApiClient>((ref) {
  return WeatherApiClient();
});

final weatherRepositoryProvider =
    FutureProvider<WeatherRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final apiClient = ref.watch(weatherApiClientProvider);
  return WeatherRepository(db: db, apiClient: apiClient);
});

final vaultExportServiceProvider =
    FutureProvider<VaultExportService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return VaultExportService(db);
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return LocalNotificationService();
});

final vaultTransferServiceProvider = Provider<VaultTransferService>((ref) {
  return const PlatformVaultTransferService();
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return const GeolocatorLocationService();
});

final ipLocationServiceProvider = Provider<IpLocationService>((ref) {
  return HttpIpLocationService();
});

final locationResolverProvider = Provider<LocationResolver>((ref) {
  return LocationResolver(
    gpsService: ref.watch(locationServiceProvider),
    ipLocationService: ref.watch(ipLocationServiceProvider),
    anonymizer: ref.watch(weatherApiClientProvider),
  );
});

final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.trim().isNotEmpty) {
      return 'v${info.version.trim()}';
    }
  } on MissingPluginException {
    // Headless test fallback
  } catch (_) {}
  return 'v1.0.0';
});

class MainTabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) {
    state = index;
  }
}

final mainTabIndexProvider =
    NotifierProvider<MainTabIndexNotifier, int>(() {
  return MainTabIndexNotifier();
});

class CurrentClimateNotifier extends Notifier<ClimateCondition> {
  static const ClimateCondition initialPlaceholder = ClimateCondition(
    temperatureCelsius: 31.0,
    relativeHumidity: 38.0,
    apparentTemperatureCelsius: 35.2,
  );

  @override
  ClimateCondition build() {
    return initialPlaceholder;
  }

  void updateClimate(ClimateCondition newClimate) {
    state = newClimate;
  }
}

final currentClimateProvider =
    NotifierProvider<CurrentClimateNotifier, ClimateCondition>(() {
  return CurrentClimateNotifier();
});

class WeatherSyncState {
  final ClimateCondition condition;
  final ClimateCondition? previousCondition;
  final DateTime lastUpdated;
  final WeatherDataSource source;
  final bool heatSpikeDetected;

  const WeatherSyncState({
    required this.condition,
    this.previousCondition,
    required this.lastUpdated,
    required this.source,
    this.heatSpikeDetected = false,
  });
}

class WeatherSyncNotifier extends AsyncNotifier<WeatherSyncState> {
  ({double lat, double lon})? _lastSyncedCoords;
  ClimateCondition? _lastObservedCondition;
  WeatherDataSource? _lastSource;

  bool _isInitialPlaceholder(ClimateCondition c) {
    const p = CurrentClimateNotifier.initialPlaceholder;
    return c.temperatureCelsius == p.temperatureCelsius &&
        c.relativeHumidity == p.relativeHumidity &&
        c.apparentTemperatureCelsius == p.apparentTemperatureCelsius;
  }

  bool _coordsDiffer(
    ({double lat, double lon}) a,
    ({double lat, double lon}) b,
  ) {
    return (a.lat - b.lat).abs() > 0.02 || (a.lon - b.lon).abs() > 0.02;
  }

  @override
  Future<WeatherSyncState> build() async {
    final profile = await ref.watch(userProfileProvider.future);
    final weatherRepo = await ref.watch(weatherRepositoryProvider.future);

    final previous = ref.read(currentClimateProvider);
    final currentCoords = (lat: profile.latitude, lon: profile.longitude);
    final locationChanged =
        _lastSyncedCoords != null && _coordsDiffer(_lastSyncedCoords!, currentCoords);
    final hasPriorBaseline = _lastSyncedCoords != null &&
        !locationChanged &&
        _lastObservedCondition != null &&
        _lastSource != WeatherDataSource.offlineFallback;

    final result = await weatherRepo.getOrFetchWeatherWithMeta(
      latitude: profile.latitude,
      longitude: profile.longitude,
    );
    _lastSyncedCoords = currentCoords;

    final shouldReplaceWithOfflineFallback =
        result.source == WeatherDataSource.offlineFallback &&
            (locationChanged || _isInitialPlaceholder(previous));

    final shouldUpdateClimate =
        result.source != WeatherDataSource.offlineFallback ||
            shouldReplaceWithOfflineFallback;

    final effectiveCondition =
        shouldUpdateClimate ? result.condition : previous;

    if (shouldUpdateClimate && ref.mounted) {
      ref.read(currentClimateProvider.notifier).updateClimate(effectiveCondition);
    }

    final spike = result.source == WeatherDataSource.liveApi &&
        hasPriorBaseline &&
        weatherRepo.isHeatSpikeDelta(
          previous: _lastObservedCondition!,
          current: effectiveCondition,
        );

    final priorForState = _lastObservedCondition ?? previous;
    _lastSource = result.source;
    if (result.source != WeatherDataSource.offlineFallback) {
      _lastObservedCondition = effectiveCondition;
    } else if (locationChanged) {
      _lastObservedCondition = null;
    }

    return WeatherSyncState(
      condition: effectiveCondition,
      previousCondition: priorForState,
      lastUpdated: result.updatedAt,
      source: result.source,
      heatSpikeDetected: spike,
    );
  }

  Future<WeatherSyncState?> refreshWeather({bool forceRefresh = true}) async {
    final currentData = switch (state) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final ClimateCondition previous =
        _lastObservedCondition ?? currentData?.condition ?? ref.read(currentClimateProvider);
    final profile = await ref.read(userProfileProvider.future);
    final weatherRepo = await ref.read(weatherRepositoryProvider.future);

    final currentCoords = (lat: profile.latitude, lon: profile.longitude);
    final locationChanged =
        _lastSyncedCoords != null && _coordsDiffer(_lastSyncedCoords!, currentCoords);
    final hasPriorBaseline = _lastSyncedCoords != null &&
        !locationChanged &&
        _lastObservedCondition != null &&
        _lastSource != WeatherDataSource.offlineFallback;

    final result = await weatherRepo.getOrFetchWeatherWithMeta(
      latitude: profile.latitude,
      longitude: profile.longitude,
      forceRefresh: forceRefresh,
    );
    _lastSyncedCoords = currentCoords;

    if (!ref.mounted) return null;

    final shouldReplaceWithOfflineFallback =
        result.source == WeatherDataSource.offlineFallback &&
            (locationChanged || _isInitialPlaceholder(previous));

    final shouldUpdateClimate =
        result.source != WeatherDataSource.offlineFallback ||
            shouldReplaceWithOfflineFallback;

    final effectiveCondition =
        shouldUpdateClimate ? result.condition : previous;

    if (shouldUpdateClimate) {
      ref.read(currentClimateProvider.notifier).updateClimate(effectiveCondition);
    }

    final spike = result.source == WeatherDataSource.liveApi &&
        hasPriorBaseline &&
        weatherRepo.isHeatSpikeDelta(
          previous: previous,
          current: effectiveCondition,
        );

    _lastSource = result.source;
    if (result.source != WeatherDataSource.offlineFallback) {
      _lastObservedCondition = effectiveCondition;
    } else if (locationChanged) {
      _lastObservedCondition = null;
    }

    final nextState = WeatherSyncState(
      condition: effectiveCondition,
      previousCondition: previous,
      lastUpdated: result.updatedAt,
      source: result.source,
      heatSpikeDetected: spike,
    );
    state = AsyncData(nextState);
    return nextState;
  }
}

final weatherSyncProvider =
    AsyncNotifierProvider<WeatherSyncNotifier, WeatherSyncState>(() {
  return WeatherSyncNotifier();
});

final userProfileProvider = FutureProvider<UserProfile>((ref) async {
  final repo = await ref.watch(userProfileRepositoryProvider.future);
  return await repo.getUserProfile();
});

class HydrationState {
  final int currentVolumeMl;
  final int targetVolumeMl;
  final double percentage;
  final int remainingMl;
  final List<IntakeLog> recentLogs;
  final HydrationTargetBreakdown breakdown;
  final int estimatedWaterLossMl;

  const HydrationState({
    required this.currentVolumeMl,
    required this.targetVolumeMl,
    required this.percentage,
    required this.remainingMl,
    required this.recentLogs,
    required this.breakdown,
    this.estimatedWaterLossMl = 0,
  });
}

class HydrationNotifier extends AsyncNotifier<HydrationState> {
  static const HydrationCalculator _calculator = HydrationCalculator();
  static const ConsistencyCalculator _consistencyCalculator =
      ConsistencyCalculator();

  DateTime? _lastLoadedDay;

  @override
  Future<HydrationState> build() async {
    final intakeRepo = await ref.watch(intakeLogRepositoryProvider.future);
    final userProfile = await ref.watch(userProfileProvider.future);
    final climate = ref.watch(currentClimateProvider);

    final effectiveClimate = userProfile.weatherAdaptationEnabled
        ? climate
        : const ClimateCondition(
            temperatureCelsius: 20.0,
            relativeHumidity: 50.0,
          );

    final breakdown = _calculator.calculateTotalTarget(
      weightKg: userProfile.weightKg,
      baselineOverrideMl: userProfile.customBaselineMl,
      activityMinutes: userProfile.dailyActivityMinutes,
      climate: effectiveClimate,
    );

    final waterLossMl = _calculator.estimateWaterLossMl(
      weightKg: userProfile.weightKg,
      activityMinutes: userProfile.dailyActivityMinutes,
      climate: climate,
    );

    final today = DateTime.now();
    _lastLoadedDay = DateTime(today.year, today.month, today.day);
    final currentVolume = await intakeRepo.getEffectiveVolumeForDate(today);
    final todayLogs = await intakeRepo.getLogsForDate(today);

    final startH = userProfile.activeWindowStartHour;
    final endH = userProfile.activeWindowEndHour;
    final hourlyDist = await intakeRepo.getHourlyDistribution(
      date: today,
      startHour: startH,
      endHour: endH,
      resolveActiveShift: true,
    );
    final hourlyTarget = hourlyDist.isNotEmpty
        ? math.max(1, (breakdown.totalTargetMl / hourlyDist.length).round())
        : 200;
    final consistency = _consistencyCalculator.calculateConsistencyScore(
      hourlyLogs: hourlyDist,
      targetHourlyVolume: hourlyTarget,
    );

    await intakeRepo.upsertDailySummary(
      date: today,
      baselineGoalMl: breakdown.baselineMl,
      adjustedGoalMl: breakdown.totalTargetMl,
      totalIngestedMl: currentVolume,
      weatherTemp: climate.temperatureCelsius,
      weatherHumidity: climate.relativeHumidity,
      consistencyScore: consistency,
    );

    final fraction = breakdown.totalTargetMl > 0
        ? (currentVolume / breakdown.totalTargetMl).clamp(0.0, 1.0)
        : 0.0;
    final remaining = math.max(0, breakdown.totalTargetMl - currentVolume);

    return HydrationState(
      currentVolumeMl: currentVolume,
      targetVolumeMl: breakdown.totalTargetMl,
      percentage: fraction,
      remainingMl: remaining,
      recentLogs: todayLogs,
      breakdown: breakdown,
      estimatedWaterLossMl: waterLossMl,
    );
  }

  Future<void> refreshIfNewDay({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final currentDay = DateTime(current.year, current.month, current.day);
    if (_lastLoadedDay != null && _lastLoadedDay == currentDay) return;
    _lastLoadedDay = currentDay;
    if (!ref.mounted) return;
    ref.invalidateSelf();
    await future;
  }

  Future<void> logHydration({
    required int amountMl,
    required BeverageType type,
    DateTime? timestamp,
  }) async {
    final intakeRepo = await ref.read(intakeLogRepositoryProvider.future);
    final effective = _calculator.calculateEffectiveIntake(amountMl, type);

    final log = IntakeLog(
      timestamp: timestamp ?? DateTime.now(),
      volumeMl: amountMl,
      beverageType: type,
      effectiveVolumeMl: effective,
    );

    await intakeRepo.insertLog(log);
    if (!ref.mounted) return;
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateLog({
    required int id,
    required int volumeMl,
    required BeverageType type,
    required DateTime timestamp,
  }) async {
    final intakeRepo = await ref.read(intakeLogRepositoryProvider.future);
    final effective = _calculator.calculateEffectiveIntake(volumeMl, type);

    await intakeRepo.updateLog(
      IntakeLog(
        id: id,
        timestamp: timestamp,
        volumeMl: volumeMl,
        beverageType: type,
        effectiveVolumeMl: effective,
      ),
    );
    if (!ref.mounted) return;
    ref.invalidateSelf();
    await future;
  }

  Future<void> deleteLog(int id) async {
    final intakeRepo = await ref.read(intakeLogRepositoryProvider.future);
    await intakeRepo.deleteLog(id);
    if (!ref.mounted) return;
    ref.invalidateSelf();
    await future;
  }

  Future<void> restoreLog(IntakeLog log) async {
    final intakeRepo = await ref.read(intakeLogRepositoryProvider.future);
    await intakeRepo.insertLog(
      IntakeLog(
        timestamp: log.timestamp,
        volumeMl: log.volumeMl,
        beverageType: log.beverageType,
        effectiveVolumeMl: log.effectiveVolumeMl,
      ),
    );
    if (!ref.mounted) return;
    ref.invalidateSelf();
    await future;
  }
}

final hydrationNotifierProvider =
    AsyncNotifierProvider<HydrationNotifier, HydrationState>(() {
  return HydrationNotifier();
});

class PacingScheduleState {
  final List<HydrationChimeSlot> upcomingChimes;
  final int recommendedHourlyMl;
  final bool osSchedulingSupported;

  const PacingScheduleState({
    required this.upcomingChimes,
    required this.recommendedHourlyMl,
    this.osSchedulingSupported = true,
  });

  HydrationChimeSlot? get nextChime =>
      upcomingChimes.isEmpty ? null : upcomingChimes.first;
}

final pacingScheduleProvider = FutureProvider<PacingScheduleState>((ref) async {
  const scheduler = NotificationScheduler();
  final profile = await ref.watch(userProfileProvider.future);
  final hydration = await ref.watch(hydrationNotifierProvider.future);
  final notificationService = ref.watch(notificationServiceProvider);
  final now = DateTime.now();

  final chimes = scheduler.computeDailySchedule(
    now: now,
    activeWindowStartHour: profile.activeWindowStartHour,
    activeWindowEndHour: profile.activeWindowEndHour,
    remainingMl: hydration.remainingMl,
    mindfulPacingEnabled: profile.mindfulPacingEnabled,
  );
  final hourly = scheduler.computeRecommendedHourlyPacingMl(
    now: now,
    activeWindowStartHour: profile.activeWindowStartHour,
    activeWindowEndHour: profile.activeWindowEndHour,
    remainingMl: hydration.remainingMl,
    totalTargetMl: hydration.targetVolumeMl,
  );

  try {
    await notificationService.syncPacingSchedule(
      slots: chimes,
      enabled: profile.mindfulPacingEnabled,
    );
  } catch (_) {
    // Graceful no-op on headless or unsupported environments.
  }

  return PacingScheduleState(
    upcomingChimes: chimes,
    recommendedHourlyMl: hourly,
    osSchedulingSupported: notificationService.supportsScheduledNotifications,
  );
});

enum StartupLocationStatus {
  idle,
  resolving,
  resolvedGps,
  resolvedIp,
  manualSkipped,
  failed,
}

class StartupLocationState {
  final StartupLocationStatus status;
  final ResolvedLocation? location;
  final String? message;

  const StartupLocationState({
    required this.status,
    this.location,
    this.message,
  });

  static const idle = StartupLocationState(status: StartupLocationStatus.idle);
}

class LocationBootstrapNotifier extends Notifier<StartupLocationState> {
  bool _hasAttemptedStartup = false;
  bool _askedGpsPermissionThisSession = false;
  Future<StartupLocationState>? _inFlight;

  @override
  StartupLocationState build() {
    ref.onDispose(() {
      _inFlight = null;
    });
    return StartupLocationState.idle;
  }

  Future<StartupLocationState> resolveOnStartup({bool force = false}) {
    if (!force && _hasAttemptedStartup) {
      return Future.value(state);
    }
    if (_inFlight != null) return _inFlight!;

    final future = _runStartupResolution(force: force);
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  Future<StartupLocationState> retryIfFailedOnResume() async {
    if (_inFlight != null) return _inFlight!;
    if (state.status != StartupLocationStatus.failed) return state;
    return resolveOnStartup(force: true);
  }

  Future<StartupLocationState> _runStartupResolution({
    required bool force,
  }) async {
    _hasAttemptedStartup = true;
    state = const StartupLocationState(
      status: StartupLocationStatus.resolving,
    );

    try {
      final initialProfile = await ref.read(userProfileProvider.future);
      if (!ref.mounted) return state;

      if (initialProfile.locationMode == LocationMode.manual) {
        const next = StartupLocationState(
          status: StartupLocationStatus.manualSkipped,
        );
        state = next;
        return next;
      }

      final requestGpsPermission = !_askedGpsPermissionThisSession &&
          (force || initialProfile.locationMode == LocationMode.auto);
      if (requestGpsPermission) {
        _askedGpsPermissionThisSession = true;
      }

      final resolver = ref.read(locationResolverProvider);
      final resolved = await resolver.resolveLocation(
        requestGpsPermission: requestGpsPermission,
      );
      if (!ref.mounted) return state;

      final latestProfile = await ref.read(userProfileProvider.future);
      if (!ref.mounted) return state;

      // Respect manual city choices made while OS permission dialog was open.
      if (!force && latestProfile.locationMode == LocationMode.manual) {
        const next = StartupLocationState(
          status: StartupLocationStatus.manualSkipped,
        );
        state = next;
        return next;
      }

      final locationChanged = latestProfile.cityName != resolved.name ||
          (latestProfile.latitude - resolved.latitude).abs() > 0.005 ||
          (latestProfile.longitude - resolved.longitude).abs() > 0.005 ||
          latestProfile.locationMode != resolved.locationMode;

      if (locationChanged) {
        final repo = await ref.read(userProfileRepositoryProvider.future);
        if (!ref.mounted) return state;
        await repo.updateLocation(
          resolved.name,
          resolved.latitude,
          resolved.longitude,
          locationMode: resolved.locationMode,
        );
        if (!ref.mounted) return state;
        ref.invalidate(userProfileProvider);
        await ref.read(userProfileProvider.future);
        if (!ref.mounted) return state;
      }

      // Ensure weather info is fetched for the resolved GPS or IP location.
      try {
        await ref.read(weatherSyncProvider.future);
      } catch (_) {
        // WeatherRepository provides offline fallback safely.
      }
      if (!ref.mounted) return state;

      final next = StartupLocationState(
        status: resolved.source == ResolvedLocationSource.gps
            ? StartupLocationStatus.resolvedGps
            : StartupLocationStatus.resolvedIp,
        location: resolved,
        message: resolved.source == ResolvedLocationSource.ip
            ? 'GPS unavailable — using public IP location (${resolved.name}).'
            : null,
      );
      state = next;
      return next;
    } catch (e) {
      if (!ref.mounted) return state;
      final next = StartupLocationState(
        status: StartupLocationStatus.failed,
        message: e.toString(),
      );
      state = next;
      return next;
    }
  }
}

final locationBootstrapProvider =
    NotifierProvider<LocationBootstrapNotifier, StartupLocationState>(() {
  return LocationBootstrapNotifier();
});
