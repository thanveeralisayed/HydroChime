import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/calculators/consistency_calculator.dart';
import '../../domain/models/beverage_type.dart';
import '../../domain/models/intake_log.dart';
import 'hydration_providers.dart';

enum AnalyticsRange {
  day,
  week,
  month,
}

class AnalyticsBarPoint {
  final String label;
  final String fullLabel;
  final int volumeMl;
  final bool isHighlighted;

  const AnalyticsBarPoint({
    required this.label,
    required this.fullLabel,
    required this.volumeMl,
    this.isHighlighted = false,
  });
}

class AnalyticsBeverageStat {
  final BeverageType type;
  final int volumeMl;
  final int percentage;

  const AnalyticsBeverageStat({
    required this.type,
    required this.volumeMl,
    required this.percentage,
  });
}

class AnalyticsData {
  final AnalyticsRange range;
  final int consistencyScore;
  final List<AnalyticsBarPoint> bars;
  final int periodTotalMl;
  final int dailyAverageMl;
  final int targetsMetCount;
  final int totalPeriodDays;
  final List<AnalyticsBeverageStat> beverageStats;

  const AnalyticsData({
    required this.range,
    required this.consistencyScore,
    required this.bars,
    required this.periodTotalMl,
    required this.dailyAverageMl,
    required this.targetsMetCount,
    required this.totalPeriodDays,
    required this.beverageStats,
  });
}

class AnalyticsRangeNotifier extends Notifier<AnalyticsRange> {
  @override
  AnalyticsRange build() => AnalyticsRange.week;

  void setRange(AnalyticsRange range) {
    state = range;
  }
}

final analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeNotifier, AnalyticsRange>(() {
  return AnalyticsRangeNotifier();
});

final analyticsProvider = FutureProvider<AnalyticsData>((ref) async {
  const consistencyCalculator = ConsistencyCalculator();

  final range = ref.watch(analyticsRangeProvider);
  final profile = await ref.watch(userProfileProvider.future);
  final intakeRepo = await ref.watch(intakeLogRepositoryProvider.future);
  final hydrationState = await ref.watch(hydrationNotifierProvider.future);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final targetMl = hydrationState.targetVolumeMl;
  final startHour = profile.activeWindowStartHour;
  final endHour = profile.activeWindowEndHour > startHour
      ? profile.activeWindowEndHour
      : 22;
  final windowHours = math.max(1, endHour - startHour);
  final targetHourlyVolume = math.max(1, (targetMl / windowHours).round());

  final totalPeriodDays = switch (range) {
    AnalyticsRange.day => 1,
    AnalyticsRange.week => 7,
    AnalyticsRange.month => 30,
  };
  final rangeStart = today.subtract(Duration(days: totalPeriodDays - 1));

  final logs = await intakeRepo.getLogsForDateRange(rangeStart, today);
  final savedGoals = await intakeRepo.getAdjustedGoalsForDateRange(
    rangeStart,
    today,
  );

  // Partition logs by day and calculate beverage totals
  final logsByDay = <DateTime, List<IntakeLog>>{};
  final rawByBeverage = <BeverageType, int>{
    for (final type in BeverageType.values) type: 0,
  };

  for (final log in logs) {
    final dayKey = DateTime(
      log.timestamp.year,
      log.timestamp.month,
      log.timestamp.day,
    );
    logsByDay.putIfAbsent(dayKey, () => []).add(log);
    rawByBeverage[log.beverageType] =
        (rawByBeverage[log.beverageType] ?? 0) + log.volumeMl;
  }

  List<int> hourlyBucketForDay(List<IntakeLog> dayLogs) {
    final dist = List<int>.filled(windowHours, 0);
    for (final log in dayLogs) {
      final h = log.timestamp.hour;
      if (h >= startHour && h < endHour) {
        dist[h - startHour] += log.volumeMl;
      }
    }
    return dist;
  }

  late final List<AnalyticsBarPoint> bars;
  late final int consistencyScore;
  late final int periodTotalMl;
  late final int dailyAverageMl;
  late final int targetsMetCount;

  if (range == AnalyticsRange.day) {
    final todayLogs = logsByDay[today] ?? const <IntakeLog>[];
    final hourly = hourlyBucketForDay(todayLogs);

    consistencyScore = consistencyCalculator.calculateConsistencyScore(
      hourlyLogs: hourly,
      targetHourlyVolume: targetHourlyVolume,
    );

    bars = List.generate(hourly.length, (index) {
      final hour = startHour + index;
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      final periodSuffix = hour < 12 ? 'a' : 'p';
      final fullSuffix = hour < 12 ? 'AM' : 'PM';
      final shortLabel = index % 3 == 0 ? '$hour12$periodSuffix' : '';
      return AnalyticsBarPoint(
        label: shortLabel,
        fullLabel: '$hour12:00 $fullSuffix',
        volumeMl: hourly[index],
        isHighlighted: hour == now.hour,
      );
    });

    periodTotalMl = hydrationState.currentVolumeMl;
    dailyAverageMl = periodTotalMl;
    targetsMetCount = periodTotalMl >= targetMl ? 1 : 0;
  } else {
    final builtBars = <AnalyticsBarPoint>[];
    final consistencyScores = <int>[];
    int totalEff = 0;
    int loggedDays = 0;
    int metCount = 0;

    for (int i = 0; i < totalPeriodDays; i++) {
      final normalizedDay = rangeStart.add(Duration(days: i));
      final dayLogs = logsByDay[normalizedDay] ?? const <IntakeLog>[];
      final vol = dayLogs.fold<int>(0, (sum, l) => sum + l.effectiveVolumeMl);

      totalEff += vol;
      if (dayLogs.isNotEmpty) {
        loggedDays++;
        final hourly = hourlyBucketForDay(dayLogs);
        consistencyScores.add(
          consistencyCalculator.calculateConsistencyScore(
            hourlyLogs: hourly,
            targetHourlyVolume: targetHourlyVolume,
          ),
        );
      }

      final dateKey =
          '${normalizedDay.year}-${normalizedDay.month.toString().padLeft(2, '0')}-${normalizedDay.day.toString().padLeft(2, '0')}';
      final dayGoal = savedGoals[dateKey] ?? targetMl;
      if (dayGoal > 0 && vol >= dayGoal) {
        metCount++;
      }

      final isToday = normalizedDay == today;
      final label = range == AnalyticsRange.week
          ? DateFormat('E').format(normalizedDay).substring(0, 1)
          : (isToday
              ? 'Today'
              : (i % 7 == 0 ? DateFormat('d').format(normalizedDay) : ''));
      final fullLabel = DateFormat('EEE, MMM d').format(normalizedDay);

      builtBars.add(
        AnalyticsBarPoint(
          label: label,
          fullLabel: fullLabel,
          volumeMl: vol,
          isHighlighted: isToday,
        ),
      );
    }

    bars = builtBars;
    periodTotalMl = totalEff;
    dailyAverageMl = loggedDays > 0 ? (totalEff / loggedDays).round() : 0;
    targetsMetCount = metCount;
    consistencyScore = consistencyScores.isEmpty
        ? 0
        : (consistencyScores.reduce((a, b) => a + b) / consistencyScores.length)
            .round();
  }

  final totalRawVolume = rawByBeverage.values.fold<int>(0, (sum, v) => sum + v);
  final stats = BeverageType.values.map((type) {
    final vol = rawByBeverage[type] ?? 0;
    final pct = totalRawVolume > 0 ? ((vol * 100) / totalRawVolume).round() : 0;
    return AnalyticsBeverageStat(
      type: type,
      volumeMl: vol,
      percentage: pct,
    );
  }).toList();

  return AnalyticsData(
    range: range,
    consistencyScore: consistencyScore,
    bars: bars,
    periodTotalMl: periodTotalMl,
    dailyAverageMl: dailyAverageMl,
    targetsMetCount: targetsMetCount,
    totalPeriodDays: totalPeriodDays,
    beverageStats: stats,
  );
});
