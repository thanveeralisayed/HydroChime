import 'dart:math' as math;

class ConsistencyCalculator {
  const ConsistencyCalculator();

  /// Calculates an algorithmic hydration consistency score (0 - 100%)
  /// grading how evenly fluid intake was distributed across active waking hours.
  int calculateConsistencyScore({
    required List<int> hourlyLogs,
    required int targetHourlyVolume,
  }) {
    if (hourlyLogs.isEmpty || targetHourlyVolume <= 0) return 0;

    final totalIntake = hourlyLogs.fold<int>(0, (sum, val) => sum + val);
    if (totalIntake == 0) return 0;

    // 1. Evaluate Coefficient of Variation (CV = standardDeviation / mean)
    final n = hourlyLogs.length;
    final mean = totalIntake / n;

    double varianceSum = 0;
    int maxSingleHour = 0;
    int zeroHourStreak = 0;
    int maxZeroStreak = 0;

    for (final vol in hourlyLogs) {
      varianceSum += (vol - mean) * (vol - mean);
      if (vol > maxSingleHour) {
        maxSingleHour = vol;
      }
      if (vol == 0) {
        zeroHourStreak++;
        if (zeroHourStreak > maxZeroStreak) {
          maxZeroStreak = zeroHourStreak;
        }
      } else {
        zeroHourStreak = 0;
      }
    }

    final stdDev = math.sqrt(varianceSum / n);
    final coefficientOfVariation = mean > 0 ? (stdDev / mean) : 1.0;

    // Standard consistency starts at 100 and scales down by variation
    // CV of 0.0 -> 100%
    // CV of 0.3 -> ~95%
    // CV of 1.0 -> ~70%
    // CV > 2.0 -> < 40%
    double baseScore = 100.0 - (coefficientOfVariation * 20.0);

    // 2. Penalty for prolonged dehydration gaps (> 3 consecutive hours of 0 ml during active window)
    if (maxZeroStreak >= 4) {
      baseScore -= (maxZeroStreak - 3) * 6.0;
    }

    // 3. Penalty for extreme binge drinking (single hour exceeding 3.5x target volume)
    if (maxSingleHour > (targetHourlyVolume * 3.5)) {
      final excessFactor = (maxSingleHour / targetHourlyVolume) - 3.5;
      baseScore -= excessFactor * 8.0;
    }

    return baseScore.clamp(0.0, 100.0).round();
  }
}

