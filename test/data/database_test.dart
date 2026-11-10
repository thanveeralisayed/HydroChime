import 'package:flutter_test/flutter_test.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/intake_log_repository.dart';
import 'package:hydrochime/data/repositories/user_profile_repository.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/domain/models/intake_log.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late IntakeLogRepository intakeLogRepository;
  late UserProfileRepository userProfileRepository;

  setUp(() async {
    appDatabase = AppDatabase.inMemory();
    final db = await appDatabase.database;
    intakeLogRepository = IntakeLogRepository(db);
    userProfileRepository = UserProfileRepository(db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('AppDatabase & UserProfileRepository (TDD)', () {
    test('initializes default profile with 70kg weight and active window 7am-10pm', () async {
      final profile = await userProfileRepository.getUserProfile();
      expect(profile.weightKg, 70.0);
      expect(profile.activeWindowStartHour, 7);
      expect(profile.activeWindowEndHour, 22);
      expect(profile.weatherAdaptationEnabled, isTrue);
      expect(profile.mindfulPacingEnabled, isTrue);
      expect(profile.dailyActivityMinutes, 0);
      expect(profile.customBaselineMl, isNull);
      expect(profile.isDarkMode, isTrue);
      expect(profile.cityName, 'Austin');
    });

    test('updates weight, baseline override, activity, window, theme, and location cleanly', () async {
      await userProfileRepository.updateWeight(75.5);
      await userProfileRepository.setWeatherAdaptation(false);
      await userProfileRepository.setMindfulPacing(false);
      await userProfileRepository.updateActiveWindow(8, 21);
      await userProfileRepository.updateDailyActivityMinutes(45);
      await userProfileRepository.updateCustomBaseline(2800);
      await userProfileRepository.setDarkMode(false);
      await userProfileRepository.updateLocation('Seattle', 47.61, -122.33);

      final updated = await userProfileRepository.getUserProfile();
      expect(updated.weightKg, 75.5);
      expect(updated.weatherAdaptationEnabled, isFalse);
      expect(updated.mindfulPacingEnabled, isFalse);
      expect(updated.activeWindowStartHour, 8);
      expect(updated.activeWindowEndHour, 21);
      expect(updated.dailyActivityMinutes, 45);
      expect(updated.customBaselineMl, 2800);
      expect(updated.isDarkMode, isFalse);
      expect(updated.cityName, 'Seattle');
      expect(updated.latitude, 47.61);
      expect(updated.longitude, -122.33);

      // Clearing custom baseline falls back to null
      await userProfileRepository.updateCustomBaseline(null);
      final cleared = await userProfileRepository.getUserProfile();
      expect(cleared.customBaselineMl, isNull);
    });
  });

  group('IntakeLogRepository (TDD)', () {
    test('inserts and queries reverse-chronological intake logs', () async {
      final now = DateTime.now();
      final log1 = IntakeLog(
        timestamp: now.subtract(const Duration(minutes: 60)),
        volumeMl: 250,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 250,
      );
      final log2 = IntakeLog(
        timestamp: now.subtract(const Duration(minutes: 10)),
        volumeMl: 350,
        beverageType: BeverageType.electrolytes,
        effectiveVolumeMl: 508,
      );

      await intakeLogRepository.insertLog(log1);
      await intakeLogRepository.insertLog(log2);

      final recent = await intakeLogRepository.getRecentLogs(limit: 10);
      expect(recent.length, 2);
      expect(recent[0].volumeMl, 350);
      expect(recent[0].beverageType, BeverageType.electrolytes);
      expect(recent[1].volumeMl, 250);
    });

    test('filters logs strictly for a specific date and supports deletion', () async {
      final today = DateTime(2026, 11, 10, 12, 0);
      final yesterday = DateTime(2026, 11, 9, 18, 0);

      final id1 = await intakeLogRepository.insertLog(IntakeLog(
        timestamp: today,
        volumeMl: 250,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 250,
      ));
      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: yesterday,
        volumeMl: 500,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 500,
      ));

      final todayLogs = await intakeLogRepository.getLogsForDate(today);
      expect(todayLogs.length, 1);
      expect(todayLogs.first.id, id1);

      await intakeLogRepository.deleteLog(id1);
      expect((await intakeLogRepository.getLogsForDate(today)).isEmpty, isTrue);
    });

    test('calculates total effective volume for today', () async {
      final now = DateTime.now();
      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: now,
        volumeMl: 500,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 500,
      ));
      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: now,
        volumeMl: 350,
        beverageType: BeverageType.electrolytes,
        effectiveVolumeMl: 508,
      ));

      final totalEffective = await intakeLogRepository.getEffectiveVolumeForDate(now);
      expect(totalEffective, 1008);
    });

    test('aggregates daily effective totals across a multi-day range', () async {
      final day1 = DateTime(2026, 11, 8);
      final day2 = DateTime(2026, 11, 9);
      final day3 = DateTime(2026, 11, 10);

      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: DateTime(2026, 11, 8, 10),
        volumeMl: 1000,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 1000,
      ));
      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: DateTime(2026, 11, 10, 9),
        volumeMl: 500,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 500,
      ));
      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: DateTime(2026, 11, 10, 14),
        volumeMl: 350,
        beverageType: BeverageType.electrolytes,
        effectiveVolumeMl: 508,
      ));

      final totals = await intakeLogRepository.getDailyEffectiveTotals(day1, day3);
      expect(totals[day1], 1000);
      expect(totals[day2], isNull);
      expect(totals[day3], 1008);
    });

    test('computes hourly distribution list for consistency scoring', () async {
      final today = DateTime.now();
      final morning = DateTime(today.year, today.month, today.day, 8, 30);
      final noon = DateTime(today.year, today.month, today.day, 12, 15);

      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: morning,
        volumeMl: 250,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 250,
      ));
      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: noon,
        volumeMl: 500,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 500,
      ));

      final hourlyList = await intakeLogRepository.getHourlyDistribution(
        date: today,
        startHour: 7,
        endHour: 22,
      );

      expect(hourlyList.length, 15);
      expect(hourlyList[1], 250);
      expect(hourlyList[5], 500);
      expect(hourlyList[0], 0);
    });

    test('upserts and reads daily_summaries records accurately', () async {
      final date = DateTime(2026, 11, 10);
      await intakeLogRepository.upsertDailySummary(
        date: date,
        baselineGoalMl: 2450,
        adjustedGoalMl: 3185,
        totalIngestedMl: 2900,
        weatherTemp: 31.0,
        weatherHumidity: 38.0,
        consistencyScore: 92,
      );

      final summary = await intakeLogRepository.getDailySummary(date);
      expect(summary, isNotNull);
      expect(summary!['adjusted_goal_ml'], 3185);
      expect(summary['total_ingested_ml'], 2900);
      expect(summary['consistency_score'], 92);
    });

    test('migrates v1 user_profile schema cleanly to v2 during onUpgrade', () async {
      // Simulate an existing v1 database opened before schema v2
      final legacyDb = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        singleInstance: false,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE user_profile (
              id INTEGER PRIMARY KEY,
              weight_kg REAL NOT NULL,
              active_window_start_hour INTEGER NOT NULL,
              active_window_end_hour INTEGER NOT NULL,
              weather_adaptation_enabled INTEGER NOT NULL,
              mindful_pacing_enabled INTEGER NOT NULL
            )
          ''');
          await db.insert('user_profile', {
            'id': 1,
            'weight_kg': 68.0,
            'active_window_start_hour': 8,
            'active_window_end_hour': 21,
            'weather_adaptation_enabled': 1,
            'mindful_pacing_enabled': 0,
          });
        },
      );

      await AppDatabase.migrateDatabaseForTest(legacyDb, 1, 2);
      final repo = UserProfileRepository(legacyDb);
      final upgraded = await repo.getUserProfile();
      expect(upgraded.weightKg, 68.0);
      expect(upgraded.activeWindowStartHour, 8);
      expect(upgraded.dailyActivityMinutes, 0);
      expect(upgraded.customBaselineMl, isNull);
      expect(upgraded.isDarkMode, isTrue);
      expect(upgraded.cityName, 'Austin');

      await legacyDb.close();
    });
  });
}
