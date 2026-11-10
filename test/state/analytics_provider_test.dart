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
  });
}

