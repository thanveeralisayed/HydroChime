import 'package:flutter_test/flutter_test.dart';
import 'package:hydrochime/domain/calculators/consistency_calculator.dart';

void main() {
  group('ConsistencyCalculator (Hydration Consistency Score Algorithm)', () {
    const calculator = ConsistencyCalculator();

    test('returns 0 score when no intake is logged', () {
      final score = calculator.calculateConsistencyScore(
        hourlyLogs: List.filled(15, 0),
        targetHourlyVolume: 200,
      );
      expect(score, 0);
    });

    test('returns high consistency score (> 90%) for smooth, evenly spaced intake', () {
      // 15 hours, steady 200 ml every hour
      final hourlyIntakes = List.filled(15, 200);
      final score = calculator.calculateConsistencyScore(
        hourlyLogs: hourlyIntakes,
        targetHourlyVolume: 200,
      );
      expect(score, greaterThanOrEqualTo(95));
      expect(score, lessThanOrEqualTo(100));
    });

    test('penalizes bunched intake / binge drinking at end of the day', () {
      // 0 ml for 14 hours, then 3000 ml in the last hour
      final bunchedIntakes = [...List.filled(14, 0), 3000];
      final score = calculator.calculateConsistencyScore(
        hourlyLogs: bunchedIntakes,
        targetHourlyVolume: 200,
      );
      expect(score, lessThan(40));
    });

    test('gives realistic good score (~94% matching Stitch analytics screen) for realistic steady pacing', () {
      // Realistic intake with gentle variance (e.g. 250, 150, 200, 250...)
      final realisticIntakes = [
        250, 200, 150, 250, 200, 200, 250, 200, 150, 250, 200, 200, 200, 150, 150
      ];
      final score = calculator.calculateConsistencyScore(
        hourlyLogs: realisticIntakes,
        targetHourlyVolume: 200,
      );
      expect(score, inInclusiveRange(90, 96));
    });
  });
}

