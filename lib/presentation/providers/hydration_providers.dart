import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/intake_log_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../data/repositories/weather_repository.dart';
import '../../data/services/vault_export_service.dart';
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
  @override
  ClimateCondition build() {
    return const ClimateCondition(
      temperatureCelsius: 31.0,
      relativeHumidity: 38.0,
      apparentTemperatureCelsius: 35.2,
    );
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
  final DateTime lastUpdated;
  final WeatherDataSource source;
  final bool heatSpikeDetected;

  const WeatherSyncState({
    required this.condition,
    required this.lastUpdated,
    required this.source,
    this.heatSpikeDetected = false,
  });
}

class WeatherSyncNotifier extends AsyncNotifier<WeatherSyncState> {
  @override
  Future<WeatherSyncState> build() async {
    final profile = await ref.watch(userProfileProvider.future);
    final weatherRepo = await ref.watch(weatherRepositoryProvider.future);

    final previous = ref.read(currentClimateProvider);
    final result = await weatherRepo.getOrFetchWeatherWithMeta(
      latitude: profile.latitude,
      longitude: profile.longitude,
    );

    if (result.source != WeatherDataSource.offlineFallback && ref.mounted) {
      ref.read(currentClimateProvider.notifier).updateClimate(result.condition);
    }

    final spike = result.source == WeatherDataSource.liveApi &&
        weatherRepo.isHeatSpikeDelta(
          previous: previous,
          current: result.condition,
        );

    return WeatherSyncState(
      condition: result.source == WeatherDataSource.offlineFallback
          ? previous
          : result.condition,
      lastUpdated: result.updatedAt,
      source: result.source,
      heatSpikeDetected: spike,
    );
  }

  Future<void> refreshWeather({bool forceRefresh = true}) async {
    final currentData = switch (state) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final ClimateCondition previous =
        currentData?.condition ?? ref.read(currentClimateProvider);
    final profile = await ref.read(userProfileProvider.future);
    final weatherRepo = await ref.read(weatherRepositoryProvider.future);

    final result = await weatherRepo.getOrFetchWeatherWithMeta(
      latitude: profile.latitude,
      longitude: profile.longitude,
      forceRefresh: forceRefresh,
    );

    if (!ref.mounted) return;

    final effectiveCondition =
        result.source == WeatherDataSource.offlineFallback
            ? previous
            : result.condition;

    if (result.source != WeatherDataSource.offlineFallback) {
      ref.read(currentClimateProvider.notifier).updateClimate(effectiveCondition);
    }

    final spike = weatherRepo.isHeatSpikeDelta(
      previous: previous,
      current: effectiveCondition,
    );

    state = AsyncData(
      WeatherSyncState(
        condition: effectiveCondition,
        lastUpdated: result.updatedAt,
        source: result.source,
        heatSpikeDetected: spike,
      ),
    );
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
    final currentVolume = await intakeRepo.getEffectiveVolumeForDate(today);
    final todayLogs = await intakeRepo.getLogsForDate(today);

    final startH = userProfile.activeWindowStartHour;
    final endH = userProfile.activeWindowEndHour > startH
        ? userProfile.activeWindowEndHour
        : 22;
    final hourlyDist = await intakeRepo.getHourlyDistribution(
      date: today,
      startHour: startH,
      endHour: endH,
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

  Future<void> logHydration({
    required int amountMl,
    required BeverageType type,
  }) async {
    final intakeRepo = await ref.read(intakeLogRepositoryProvider.future);
    final effective = _calculator.calculateEffectiveIntake(amountMl, type);

    final log = IntakeLog(
      timestamp: DateTime.now(),
      volumeMl: amountMl,
      beverageType: type,
      effectiveVolumeMl: effective,
    );

    await intakeRepo.insertLog(log);
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

  const PacingScheduleState({
    required this.upcomingChimes,
    required this.recommendedHourlyMl,
  });

  HydrationChimeSlot? get nextChime =>
      upcomingChimes.isEmpty ? null : upcomingChimes.first;
}

final pacingScheduleProvider = FutureProvider<PacingScheduleState>((ref) async {
  const scheduler = NotificationScheduler();
  final profile = await ref.watch(userProfileProvider.future);
  final hydration = await ref.watch(hydrationNotifierProvider.future);
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

  return PacingScheduleState(
    upcomingChimes: chimes,
    recommendedHourlyMl: hourly,
  );
});

