import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/intake_log_repository.dart';
import 'package:hydrochime/data/repositories/user_profile_repository.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/domain/models/climate_condition.dart';
import 'package:hydrochime/domain/models/intake_log.dart';
import 'package:hydrochime/presentation/providers/analytics_provider.dart';
import 'package:hydrochime/presentation/providers/hydration_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestClimateNotifier extends CurrentClimateNotifier {
  @override
  ClimateCondition build() {
    return const ClimateCondition(
      temperatureCelsius: 20.0,
      relativeHumidity: 50.0,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late IntakeLogRepository intakeRepo;
  late UserProfileRepository profileRepo;
  late ProviderContainer container;

  setUp(() async {
    appDatabase = AppDatabase.inMemory();
    final db = await appDatabase.database;
    intakeRepo = IntakeLogRepository(db);
    profileRepo = UserProfileRepository(db);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(AsyncData(db)),
        intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeRepo)),
        userProfileRepositoryProvider.overrideWithValue(AsyncData(profileRepo)),
        currentClimateProvider.overrideWith(() => _TestClimateNotifier()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await appDatabase.close();
  });

  group('AnalyticsProvider (Live Analytics TDD)', () {
    test('returns clean empty state when no logs are present', () async {
      final analytics = await container.read(analyticsProvider.future);
      expect(analytics.range, AnalyticsRange.week);
      expect(analytics.consistencyScore, 0);
      expect(analytics.dailyAverageMl, 0);
      expect(analytics.targetsMetCount, 0);
      expect(analytics.totalPeriodDays, 7);
      expect(analytics.bars.length, 7);
      expect(analytics.bars.last.isHighlighted, isTrue);
      for (final stat in analytics.beverageStats) {
        expect(stat.percentage, 0);
      }
    });

    test('computes Week analytics: 7 bars, daily average, targets met, and beverage distribution',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10, 0);
      final yesterday = today.subtract(const Duration(days: 1));
      final twoDaysAgo = today.subtract(const Duration(days: 2));

      // Default 70kg @ 20C = 2450 mL daily target
      // Day -2: 2500 ml water (meets target)
      await intakeRepo.insertLog(IntakeLog(
        timestamp: twoDaysAgo,
        volumeMl: 2500,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 2500,
      ));
      // Day -1: 1000 ml herbal tea (under target)
      await intakeRepo.insertLog(IntakeLog(
        timestamp: yesterday,
        volumeMl: 1000,
        beverageType: BeverageType.herbalTea,
        effectiveVolumeMl: 1000,
      ));
      // Today: 2000 ml electrolytes -> effective 2900 ml (meets target)
      await intakeRepo.insertLog(IntakeLog(
        timestamp: today,
        volumeMl: 2000,
        beverageType: BeverageType.electrolytes,
        effectiveVolumeMl: 2900,
      ));

      container.invalidate(hydrationNotifierProvider);
      final analytics = await container.read(analyticsProvider.future);

      expect(analytics.range, AnalyticsRange.week);
      expect(analytics.targetsMetCount, 2);
      expect(analytics.totalPeriodDays, 7);
      // Logged effective totals across 3 logged days: (2500 + 1000 + 2900) / 3 = 2133
      expect(analytics.dailyAverageMl, 2133);
      expect(analytics.bars.length, 7);
      expect(analytics.bars.last.volumeMl, 2900);
      expect(analytics.bars[5].volumeMl, 1000);
      expect(analytics.bars[4].volumeMl, 2500);

      // Total raw volume = 2500 + 1000 + 2000 = 5500 ml
      final waterStat = analytics.beverageStats
          .firstWhere((s) => s.type == BeverageType.water);
      final elecStat = analytics.beverageStats
          .firstWhere((s) => s.type == BeverageType.electrolytes);
      final teaStat = analytics.beverageStats
          .firstWhere((s) => s.type == BeverageType.herbalTea);
      expect(waterStat.percentage, 45); // 2500/5500 = 45.4%
      expect(elecStat.percentage, 36); // 2000/5500 = 36.3%
      expect(teaStat.percentage, 18); // 1000/5500 = 18.1%
    });

    test('computes Day and Month ranges dynamically via analyticsRangeProvider',
        () async {
      final now = DateTime.now();
      for (int h = 8; h <= 16; h += 2) {
        await intakeRepo.insertLog(IntakeLog(
          timestamp: DateTime(now.year, now.month, now.day, h, 15),
          volumeMl: 300,
          beverageType: BeverageType.water,
          effectiveVolumeMl: 300,
        ));
      }

      container.read(analyticsRangeProvider.notifier).setRange(AnalyticsRange.day);
      container.invalidate(hydrationNotifierProvider);

      final dayAnalytics = await container.read(analyticsProvider.future);
      expect(dayAnalytics.range, AnalyticsRange.day);
      expect(dayAnalytics.consistencyScore, greaterThan(0));
      expect(dayAnalytics.bars.length, 15); // active window 7..22
      expect(dayAnalytics.periodTotalMl, 1500);

      container.read(analyticsRangeProvider.notifier).setRange(AnalyticsRange.month);
      final monthAnalytics = await container.read(analyticsProvider.future);
      expect(monthAnalytics.range, AnalyticsRange.month);
      expect(monthAnalytics.totalPeriodDays, 30);
      expect(monthAnalytics.bars.length, 30);
    });

    test('uses effectiveVolumeMl in Day bars and supports overnight window', () async {
      final now = DateTime.now();
      await intakeRepo.insertLog(IntakeLog(
        timestamp: DateTime(now.year, now.month, now.day, 10, 0),
        volumeMl: 1000,
        beverageType: BeverageType.electrolytes,
        effectiveVolumeMl: 1450,
      ));

      container.read(analyticsRangeProvider.notifier).setRange(AnalyticsRange.day);
      container.invalidate(hydrationNotifierProvider);

      final dayAnalytics = await container.read(analyticsProvider.future);
      // 10 AM is index 3 in 7..22 window
      expect(dayAnalytics.bars[3].volumeMl, 1450);
      expect(dayAnalytics.periodTotalMl, 1450);

      // Overnight shift schedule 20:00 -> 08:00 should produce 12 bars
      // and classify 10:00 AM log as outsideWindowMl
      await profileRepo.updateActiveWindow(20, 8);
      container.invalidate(userProfileProvider);
      container.invalidate(hydrationNotifierProvider);

      final overnight = await container.read(analyticsProvider.future);
      expect(overnight.bars.length, 12);
      expect(overnight.outsideWindowMl, 1450);
    });

    test('uses per-day adjusted_goal_ml from daily_summaries when computing historical targetsMet',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10, 0);
      final yesterday = today.subtract(const Duration(days: 1));

      // Yesterday had a heat-wave target of 3600 ml saved in daily_summaries;
      // logging 3000 ml should NOT count as meeting yesterday's target even if today is 2450 ml.
      await intakeRepo.upsertDailySummary(
        date: yesterday,
        baselineGoalMl: 2450,
        adjustedGoalMl: 3600,
        totalIngestedMl: 3000,
        consistencyScore: 80,
      );
      await intakeRepo.insertLog(IntakeLog(
        timestamp: yesterday,
        volumeMl: 3000,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 3000,
      ));

      container.invalidate(hydrationNotifierProvider);
      final analytics = await container.read(analyticsProvider.future);
      expect(analytics.targetsMetCount, 0);
    });

    test('overnight active window includes prior evening intake in Day bars & consistency without polluting rawByBeverage',
        () async {
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final yesterdayEvening =
          todayMidnight.subtract(const Duration(hours: 2)); // yesterday 22:00
      final earlyToday = todayMidnight.add(const Duration(hours: 2)); // today 02:00

      await profileRepo.updateActiveWindow(20, 8);
      await intakeRepo.insertLog(IntakeLog(
        timestamp: yesterdayEvening,
        volumeMl: 500,
        beverageType: BeverageType.coffee,
        effectiveVolumeMl: 400,
      ));
      await intakeRepo.insertLog(IntakeLog(
        timestamp: earlyToday,
        volumeMl: 400,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 400,
      ));

      container.read(analyticsRangeProvider.notifier).setRange(AnalyticsRange.day);
      container.invalidate(userProfileProvider);
      container.invalidate(hydrationNotifierProvider);

      final overnightDay = await container.read(analyticsProvider.future);
      expect(overnightDay.bars.length, 12);
      // 22:00 yesterday is index 2 in 20:00->08:00 shift; 02:00 today is index 6
      expect(overnightDay.bars[2].volumeMl, 400);
      expect(overnightDay.bars[6].volumeMl, 400);
      expect(overnightDay.outsideWindowMl, 0);
      // Today's Beverage Distribution in Day view only includes today's calendar logs (water, not yesterday's coffee)
      final coffeeStat = overnightDay.beverageStats
          .firstWhere((s) => s.type == BeverageType.coffee);
      final waterStat = overnightDay.beverageStats
          .firstWhere((s) => s.type == BeverageType.water);
      expect(coffeeStat.percentage, 0);
      expect(waterStat.percentage, 100);
    });
  });
}

