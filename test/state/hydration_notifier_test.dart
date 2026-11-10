import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/intake_log_repository.dart';
import 'package:hydrochime/data/repositories/user_profile_repository.dart';
import 'package:hydrochime/data/services/weather_api_client.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/domain/models/climate_condition.dart';
import 'package:hydrochime/domain/models/intake_log.dart';
import 'package:hydrochime/presentation/providers/hydration_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestClimateNotifier extends CurrentClimateNotifier {
  @override
  ClimateCondition build() {
    return const ClimateCondition(
      temperatureCelsius: 31.0,
      relativeHumidity: 38.0,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late IntakeLogRepository intakeLogRepository;
  late UserProfileRepository userProfileRepository;
  late ProviderContainer container;

  setUp(() async {
    appDatabase = AppDatabase.inMemory();
    final db = await appDatabase.database;
    intakeLogRepository = IntakeLogRepository(db);
    userProfileRepository = UserProfileRepository(db);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(AsyncData(db)),
        intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeLogRepository)),
        userProfileRepositoryProvider.overrideWithValue(AsyncData(userProfileRepository)),
        currentClimateProvider.overrideWith(() => TestClimateNotifier()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await appDatabase.close();
  });

  group('HydrationNotifier (State Management TDD)', () {
    test('initializes cleanly from async databaseProvider without requireValue crash',
        () async {
      final asyncDb = AppDatabase.inMemory();
      final startupContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(asyncDb),
          currentClimateProvider.overrideWith(() => TestClimateNotifier()),
        ],
      );
      addTearDown(() async {
        startupContainer.dispose();
        await asyncDb.close();
      });

      final state = await startupContainer.read(hydrationNotifierProvider.future);
      expect(state.targetVolumeMl, 3185);
      expect(state.currentVolumeMl, 0);
    });

    test('initializes with target calculated from profile and climate', () async {
      final state = await container.read(hydrationNotifierProvider.future);
      // 70kg weight, 31°C heat -> baseline 2450 * 1.30 = 3185 mL (without activity)
      expect(state.targetVolumeMl, 3185);
      expect(state.currentVolumeMl, 0);
      expect(state.percentage, 0.0);
      expect(state.remainingMl, 3185);
    });

    test('includes dailyActivityMinutes and customBaselineMl in target breakdown',
        () async {
      await userProfileRepository.updateDailyActivityMinutes(35);
      container.invalidate(userProfileProvider);

      var state = await container.read(hydrationNotifierProvider.future);
      // (2450 + 420) * 1.30 = 3731 mL
      expect(state.targetVolumeMl, 3731);
      expect(state.breakdown.activityMl, 420);

      await userProfileRepository.updateCustomBaseline(3000);
      await userProfileRepository.updateDailyActivityMinutes(0);
      container.invalidate(userProfileProvider);

      state = await container.read(hydrationNotifierProvider.future);
      // 3000 * 1.30 = 3900 mL
      expect(state.breakdown.baselineMl, 3000);
      expect(state.targetVolumeMl, 3900);
    });

    test('logging water increments volume and updates progress fraction', () async {
      final notifier = container.read(hydrationNotifierProvider.notifier);
      await notifier.logHydration(amountMl: 500, type: BeverageType.water);

      final state = await container.read(hydrationNotifierProvider.future);
      expect(state.currentVolumeMl, 500);
      expect(state.remainingMl, 2685);
      expect(state.recentLogs.length, 1);
      expect(state.recentLogs.first.volumeMl, 500);
    });

    test('logging electrolytes applies bioavailability multiplier (1.45x)', () async {
      final notifier = container.read(hydrationNotifierProvider.notifier);
      await notifier.logHydration(amountMl: 350, type: BeverageType.electrolytes);

      final state = await container.read(hydrationNotifierProvider.future);
      expect(state.currentVolumeMl, 508); // 350 * 1.45
    });

    test('filters today logs and deletes & restores log cleanly', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: yesterday,
        volumeMl: 1000,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 1000,
      ));

      final notifier = container.read(hydrationNotifierProvider.notifier);
      await notifier.logHydration(amountMl: 250, type: BeverageType.water);

      var state = await container.read(hydrationNotifierProvider.future);
      // Yesterday's log should not appear in today's volume or today's recentLogs
      expect(state.currentVolumeMl, 250);
      expect(state.recentLogs.length, 1);

      final inserted = state.recentLogs.first;
      await notifier.deleteLog(inserted.id!);

      state = await container.read(hydrationNotifierProvider.future);
      expect(state.currentVolumeMl, 0);
      expect(state.recentLogs, isEmpty);

      await notifier.restoreLog(inserted);
      state = await container.read(hydrationNotifierProvider.future);
      expect(state.currentVolumeMl, 250);
      expect(state.recentLogs.length, 1);
    });

    test('weatherSyncProvider fetches live weather and updates climate state',
        () async {
      int calls = 0;
      final mockClient = MockClient((request) async {
        calls++;
        final temp = calls == 1 ? 26.0 : 32.0; // +6°C spike on refresh!
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': temp,
              'relative_humidity_2m': 45,
              'apparent_temperature': temp + 1.5,
            }
          }),
          200,
        );
      });

      final weatherDb = AppDatabase.inMemory();
      final db = await weatherDb.database;
      final weatherContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(db)),
          intakeLogRepositoryProvider.overrideWithValue(
            AsyncData(IntakeLogRepository(db)),
          ),
          userProfileRepositoryProvider.overrideWithValue(
            AsyncData(UserProfileRepository(db)),
          ),
          weatherApiClientProvider.overrideWithValue(
            WeatherApiClient(client: mockClient),
          ),
        ],
      );
      addTearDown(() async {
        weatherContainer.dispose();
        await weatherDb.close();
      });

      final syncState = await weatherContainer.read(weatherSyncProvider.future);
      expect(syncState.condition.temperatureCelsius, 26.0);
      expect(syncState.heatSpikeDetected, isFalse);
      expect(
        weatherContainer.read(currentClimateProvider).temperatureCelsius,
        26.0,
      );

      await weatherContainer
          .read(weatherSyncProvider.notifier)
          .refreshWeather(forceRefresh: true);
      final refreshed = await weatherContainer.read(weatherSyncProvider.future);
      expect(refreshed.condition.temperatureCelsius, 32.0);
      expect(refreshed.heatSpikeDetected, isTrue);
      expect(
        weatherContainer.read(currentClimateProvider).temperatureCelsius,
        32.0,
      );
    });
  });
}
