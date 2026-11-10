import 'package:flutter_test/flutter_test.dart';
import 'package:hydrochime/domain/models/climate_condition.dart';
import 'package:hydrochime/domain/services/notification_scheduler.dart';

void main() {
  const scheduler = NotificationScheduler();

  group('NotificationScheduler (Smart Pacing TDD)', () {
    test('returns empty schedule when mindfulPacingEnabled is false', () {
      final slots = scheduler.computeDailySchedule(
        now: DateTime(2026, 11, 10, 10, 0),
        activeWindowStartHour: 7,
        activeWindowEndHour: 22,
        remainingMl: 2000,
        mindfulPacingEnabled: false,
      );
      expect(slots, isEmpty);
    });

    test('cancels remaining reminders once hydration goal is 100% met (remainingMl <= 0)',
        () {
      final slots = scheduler.computeDailySchedule(
        now: DateTime(2026, 11, 10, 14, 0),
        activeWindowStartHour: 7,
        activeWindowEndHour: 22,
        remainingMl: 0,
        mindfulPacingEnabled: true,
      );
      expect(slots, isEmpty);
    });

    test('returns empty schedule after active window end hour', () {
      final slots = scheduler.computeDailySchedule(
        now: DateTime(2026, 11, 10, 22, 15),
        activeWindowStartHour: 7,
        activeWindowEndHour: 22,
        remainingMl: 900,
        mindfulPacingEnabled: true,
      );
      expect(slots, isEmpty);
    });

    test('spaces chimes across remaining waking hours and splits remaining volume',
        () {
      final now = DateTime(2026, 11, 10, 13, 0); // 9 hours left until 22:00
      final slots = scheduler.computeDailySchedule(
        now: now,
        activeWindowStartHour: 7,
        activeWindowEndHour: 22,
        remainingMl: 1800,
        mindfulPacingEnabled: true,
      );

      expect(slots, isNotEmpty);
      for (final slot in slots) {
        expect(slot.scheduledTime.isAfter(now), isTrue);
        expect(
          slot.scheduledTime.isBefore(DateTime(2026, 11, 10, 22, 0)),
          isTrue,
        );
        expect(slot.recommendedVolumeMl, greaterThan(0));
      }

      // Total recommended across chimes roughly covers remainingMl
      final totalScheduled = slots.fold<int>(
        0,
        (sum, s) => sum + s.recommendedVolumeMl,
      );
      expect((totalScheduled - 1800).abs(), lessThan(slots.length));
    });

    test('generates heat spike alert message only on >= +4°C rise', () {
      const prev = ClimateCondition(temperatureCelsius: 26.0, relativeHumidity: 45);
      const mild = ClimateCondition(temperatureCelsius: 28.5, relativeHumidity: 45);
      const hot = ClimateCondition(temperatureCelsius: 31.0, relativeHumidity: 38);

      expect(
        scheduler.buildHeatSpikeAlertMessage(
          previous: prev,
          current: mild,
          cityName: 'Austin',
        ),
        isNull,
      );

      final alert = scheduler.buildHeatSpikeAlertMessage(
        previous: prev,
        current: hot,
        cityName: 'Austin',
      );
      expect(alert, isNotNull);
      expect(alert, contains('Austin'));
      expect(alert, contains('+5.0°C'));
    });

    test('calculates active window hourly pacing volume dynamically', () {
      final pacing = scheduler.computeRecommendedHourlyPacingMl(
        now: DateTime(2026, 11, 10, 12, 0), // 10 hours left until 22:00
        activeWindowStartHour: 7,
        activeWindowEndHour: 22,
        remainingMl: 2000,
        totalTargetMl: 3000,
      );
      expect(pacing, 200);
    });
  });
}

