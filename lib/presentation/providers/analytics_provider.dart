import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/calculators/consistency_calculator.dart';
import '../../domain/models/beverage_type.dart';
import '../../domain/models/intake_log.dart';
import '../../domain/services/notification_scheduler.dart';
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
  final int outsideWindowMl;

  const AnalyticsData({
    required this.range,
    required this.consistencyScore,
    required this.bars,
    required this.periodTotalMl,
    required this.dailyAverageMl,
    required this.targetsMetCount,
    required this.totalPeriodDays,
    required this.beverageStats,
    this.outsideWindowMl = 0,
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
  final endHour = profile.activeWindowEndHour;
  final resolvedWindow = NotificationScheduler.resolveWindowHours(
    startHour,
    endHour,
  );
  final windowHours = math.max(1, resolvedWindow);
  final isOvernight = resolvedWindow > 0 && endHour < startHour;

  final totalPeriodDays = switch (range) {
    AnalyticsRange.day => 1,
    AnalyticsRange.week => 7,
    AnalyticsRange.month => 30,
  };
  final rangeStart = today.subtract(Duration(days: totalPeriodDays - 1));
  final queryStart =
      isOvernight ? rangeStart.subtract(const Duration(days: 1)) : rangeStart;

  final allLogs = await intakeRepo.getLogsForDateRange(queryStart, today);
  final savedGoals = await intakeRepo.getAdjustedGoalsForDateRange(
    rangeStart,
    today,
  );

  // Partition logs by day (only within [rangeStart..today]) and calculate raw beverage totals
  final logsByDay = <DateTime, List<IntakeLog>>{};
  final rawByBeverage = <BeverageType, int>{
    for (final type in BeverageType.values) type: 0,
  };

  for (final log in allLogs) {
    if (log.timestamp.isBefore(rangeStart)) continue;
    final dayKey = DateTime(
      log.timestamp.year,
      log.timestamp.month,
      log.timestamp.day,
    );
    logsByDay.putIfAbsent(dayKey, () => []).add(log);
    rawByBeverage[log.beverageType] =
        (rawByBeverage[log.beverageType] ?? 0) + log.volumeMl;
  }

  ({List<int> buckets, int outsideMl}) hourlyBucketForDay(
    List<IntakeLog> dayLogs,
  ) {
    final dist = List<int>.filled(windowHours, 0);
    int outside = 0;
    for (final log in dayLogs) {
      final h = log.timestamp.hour;
      if (!NotificationScheduler.isHourInActiveWindow(
        hour: h,
        startHour: startHour,
        endHour: endHour,
      )) {
        outside += log.effectiveVolumeMl;
        continue;
      }
      if (!isOvernight) {
        dist[h - startHour] += log.effectiveVolumeMl;
      } else {
        if (h >= startHour) {
          dist[h - startHour] += log.effectiveVolumeMl;
        } else {
          dist[(24 - startHour) + h] += log.effectiveVolumeMl;
        }
      }
    }
    return (buckets: dist, outsideMl: outside);
  }

  List<int> hourlyBucketForOvernightShift(DateTime shiftStartDay) {
    final shiftStart = DateTime(
      shiftStartDay.year,
      shiftStartDay.month,
      shiftStartDay.day,
      startHour,
    );
    final shiftEnd = shiftStart.add(Duration(hours: windowHours));
    final dist = List<int>.filled(windowHours, 0);
    for (final log in allLogs) {
      if (!log.timestamp.isBefore(shiftStart) &&
          log.timestamp.isBefore(shiftEnd)) {
        final idx = log.timestamp.difference(shiftStart).inHours;
        if (idx >= 0 && idx < windowHours) {
          dist[idx] += log.effectiveVolumeMl;
        }
      }
    }
    return dist;
  }

  late final List<AnalyticsBarPoint> bars;
  late final int consistencyScore;
  late final int periodTotalMl;
  late final int dailyAverageMl;
  late final int targetsMetCount;
  int outsideWindowMl = 0;

  if (range == AnalyticsRange.day) {
    final todayLogs = logsByDay[today] ?? const <IntakeLog>[];
    final distributed = hourlyBucketForDay(todayLogs);
    outsideWindowMl = distributed.outsideMl;

    final List<int> hourly;
    if (!isOvernight) {
      hourly = distributed.buckets;
    } else {
      final shiftAnchor =
          now.hour < startHour ? today.subtract(const Duration(days: 1)) : today;
      hourly = hourlyBucketForOvernightShift(shiftAnchor);
    }

    final targetHourlyVolume = math.max(1, (targetMl / windowHours).round());
    consistencyScore = consistencyCalculator.calculateConsistencyScore(
      hourlyLogs: hourly,
      targetHourlyVolume: targetHourlyVolume,
    );

    bars = List.generate(hourly.length, (index) {
      final hour = (startHour + index) % 24;
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

      final dateKey =
          '${normalizedDay.year}-${normalizedDay.month.toString().padLeft(2, '0')}-${normalizedDay.day.toString().padLeft(2, '0')}';
      final dayGoal = savedGoals[dateKey] ?? targetMl;
      final dayTargetHourly = math.max(1, (dayGoal / windowHours).round());

      totalEff += vol;
      if (dayLogs.isNotEmpty) {
        loggedDays++;
      }

      if (!isOvernight) {
        if (dayLogs.isNotEmpty) {
          final distributed = hourlyBucketForDay(dayLogs);
          consistencyScores.add(
            consistencyCalculator.calculateConsistencyScore(
              hourlyLogs: distributed.buckets,
              targetHourlyVolume: dayTargetHourly,
            ),
          );
        }
      } else {
        final shiftAnchor = now.hour < startHour
            ? normalizedDay.subtract(const Duration(days: 1))
            : normalizedDay;
        final buckets = hourlyBucketForOvernightShift(shiftAnchor);
        if (buckets.any((v) => v > 0)) {
          consistencyScores.add(
            consistencyCalculator.calculateConsistencyScore(
              hourlyLogs: buckets,
              targetHourlyVolume: dayTargetHourly,
            ),
          );
        }
      }

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
    outsideWindowMl: outsideWindowMl,
  );
}, retry: (_, _) => null);
