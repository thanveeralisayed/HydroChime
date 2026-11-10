import 'dart:math' as math;
import '../models/climate_condition.dart';

class HydrationChimeSlot {
  final DateTime scheduledTime;
  final int recommendedVolumeMl;
  final String title;
  final String body;

  const HydrationChimeSlot({
    required this.scheduledTime,
    required this.recommendedVolumeMl,
    required this.title,
    required this.body,
  });
}

class NotificationScheduler {
  const NotificationScheduler();

  /// Computes quiet, evenly spaced daytime hydration chimes within the user's
  /// active window. Cancels remaining reminders automatically if disabled or
  /// if today's goal is already met (`remainingMl <= 0`).
  List<HydrationChimeSlot> computeDailySchedule({
    required DateTime now,
    required int activeWindowStartHour,
    required int activeWindowEndHour,
    required int remainingMl,
    required bool mindfulPacingEnabled,
  }) {
    if (!mindfulPacingEnabled || remainingMl <= 0) return const [];
    if (activeWindowEndHour <= activeWindowStartHour) return const [];

    final day = DateTime(now.year, now.month, now.day);
    final windowStart = day.add(Duration(hours: activeWindowStartHour));
    final windowEnd = day.add(Duration(hours: activeWindowEndHour));

    if (!now.isBefore(windowEnd)) return const [];

    final anchor = now.isBefore(windowStart) ? windowStart : now;
    final remainingMinutes = windowEnd.difference(anchor).inMinutes;
    if (remainingMinutes < 20) return const [];

    final slotCount = (remainingMinutes / 90).floor().clamp(1, 8);
    final intervalMinutes = (remainingMinutes / (slotCount + 1)).floor();
    final perSlotMl = (remainingMl / slotCount).round();

    return List.generate(slotCount, (index) {
      final slotTime = anchor.add(Duration(minutes: intervalMinutes * (index + 1)));
      return HydrationChimeSlot(
        scheduledTime: slotTime,
        recommendedVolumeMl: perSlotMl,
        title: 'Mindful Hydration Chime',
        body: 'Sip ~$perSlotMl ml to stay evenly paced before sleep.',
      );
    });
  }

  /// Calculates live hourly fluid pacing recommendation in mL/hr.
  int computeRecommendedHourlyPacingMl({
    required DateTime now,
    required int activeWindowStartHour,
    required int activeWindowEndHour,
    required int remainingMl,
    required int totalTargetMl,
  }) {
    if (remainingMl <= 0) return 0;
    final windowHours = math.max(1, activeWindowEndHour - activeWindowStartHour);

    final day = DateTime(now.year, now.month, now.day);
    final windowStart = day.add(Duration(hours: activeWindowStartHour));
    final windowEnd = day.add(Duration(hours: activeWindowEndHour));

    if (now.isBefore(windowStart)) {
      return (totalTargetMl / windowHours).round();
    }
    if (!now.isBefore(windowEnd)) {
      return (totalTargetMl / windowHours).round();
    }

    final remainingHours = math.max(1.0, windowEnd.difference(now).inMinutes / 60.0);
    return (remainingMl / remainingHours).round();
  }

  /// Formats a gentle climate spike alert when temperature increases by >= +4°C.
  String? buildHeatSpikeAlertMessage({
    required ClimateCondition previous,
    required ClimateCondition current,
    required String cityName,
  }) {
    final delta = current.temperatureCelsius - previous.temperatureCelsius;
    if (delta < 4.0) return null;
    return 'Heat advisory in $cityName: +${delta.toStringAsFixed(1)}°C rise detected. Hydration pacing accelerated.';
  }
}

