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

  static int resolveWindowHours(int startHour, int endHour) {
    if (startHour == endHour) return 0;
    return endHour > startHour ? (endHour - startHour) : (24 - startHour + endHour);
  }

  static bool isHourInActiveWindow({
    required int hour,
    required int startHour,
    required int endHour,
  }) {
    if (startHour == endHour) return false;
    if (endHour > startHour) {
      return hour >= startHour && hour < endHour;
    }
    return hour >= startHour || hour < endHour;
  }

  static ({DateTime start, DateTime end})? _resolveWindowBounds(
    DateTime now,
    int startHour,
    int endHour,
  ) {
    if (startHour == endHour) return null;
    final day = DateTime(now.year, now.month, now.day);
    if (endHour > startHour) {
      return (
        start: day.add(Duration(hours: startHour)),
        end: day.add(Duration(hours: endHour)),
      );
    }
    // Overnight / shift window (e.g. 20:00 -> 08:00)
    if (now.hour < endHour) {
      return (
        start: day.subtract(Duration(hours: 24 - startHour)),
        end: day.add(Duration(hours: endHour)),
      );
    }
    return (
      start: day.add(Duration(hours: startHour)),
      end: day.add(Duration(hours: 24 + endHour)),
    );
  }

  /// Computes quiet, evenly spaced daytime (or overnight shift) hydration chimes
  /// within the user's active window. Cancels remaining reminders automatically
  /// if disabled or if today's goal is already met (`remainingMl <= 0`).
  List<HydrationChimeSlot> computeDailySchedule({
    required DateTime now,
    required int activeWindowStartHour,
    required int activeWindowEndHour,
    required int remainingMl,
    required bool mindfulPacingEnabled,
  }) {
    if (!mindfulPacingEnabled || remainingMl <= 0) return const [];
    final bounds = _resolveWindowBounds(
      now,
      activeWindowStartHour,
      activeWindowEndHour,
    );
    if (bounds == null) return const [];

    if (!now.isBefore(bounds.end)) return const [];

    final anchor = now.isBefore(bounds.start) ? bounds.start : now;
    final remainingMinutes = bounds.end.difference(anchor).inMinutes;
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
    final windowHours = math.max(
      1,
      resolveWindowHours(activeWindowStartHour, activeWindowEndHour),
    );
    final bounds = _resolveWindowBounds(
      now,
      activeWindowStartHour,
      activeWindowEndHour,
    );
    if (bounds == null) return (totalTargetMl / windowHours).round();

    if (now.isBefore(bounds.start) || !now.isBefore(bounds.end)) {
      return (totalTargetMl / windowHours).round();
    }

    final remainingHours =
        math.max(1.0, bounds.end.difference(now).inMinutes / 60.0);
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

