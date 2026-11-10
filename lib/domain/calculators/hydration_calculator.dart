import '../models/beverage_type.dart';
import '../models/climate_condition.dart';

class HydrationTargetBreakdown {
  final int baselineMl;
  final int activityMl;
  final int climateDeltaMl;
  final int totalTargetMl;
  final double climateMultiplier;

  const HydrationTargetBreakdown({
    required this.baselineMl,
    required this.activityMl,
    required this.climateDeltaMl,
    required this.totalTargetMl,
    required this.climateMultiplier,
  });
}

class HydrationCalculator {
  const HydrationCalculator();

  /// Baseline requirement (B): Body Weight (kg) * 35 mL
  int calculateBaseline({required double weightKg}) {
    return (weightKg * 35).round();
  }

  /// Activity adjustment (A): Exertion Duration (mins) * 12 mL
  int calculateActivityAdjustment({required int durationMinutes}) {
    return durationMinutes * 12;
  }

  /// Climate Multiplier (C_factor) based on temperature and relative humidity
  double calculateClimateMultiplier(ClimateCondition climate) {
    double factor = 1.0;

    if (climate.temperatureCelsius < 22) {
      factor = 1.0;
    } else if (climate.temperatureCelsius < 30) {
      factor = 1.15;
    } else {
      factor = 1.30;
    }

    if (climate.relativeHumidity < 30) {
      factor += 0.10;
    } else if (climate.relativeHumidity > 75 && climate.temperatureCelsius >= 28) {
      factor += 0.05;
    }

    return factor;
  }

  /// Ingested volume adjusted by beverage bioavailability/efficiency
  int calculateEffectiveIntake(int volumeMl, BeverageType type) {
    return (volumeMl * type.multiplier).round();
  }

  /// Total target: (B + A) * C_factor
  HydrationTargetBreakdown calculateTotalTarget({
    required double weightKg,
    int? baselineOverrideMl,
    int activityMinutes = 0,
    required ClimateCondition climate,
  }) {
    final baseline = baselineOverrideMl ?? calculateBaseline(weightKg: weightKg);
    final activity = calculateActivityAdjustment(durationMinutes: activityMinutes);
    final multiplier = calculateClimateMultiplier(climate);

    final rawTarget = baseline + activity;
    final total = (rawTarget * multiplier).round();
    final climateDelta = total - rawTarget;

    return HydrationTargetBreakdown(
      baselineMl: baseline,
      activityMl: activity,
      climateDeltaMl: climateDelta,
      totalTargetMl: total,
      climateMultiplier: multiplier,
    );
  }

  /// Estimates perspiration & respiratory water loss (mL) for current climate & exertion
  int estimateWaterLossMl({
    required double weightKg,
    int activityMinutes = 0,
    required ClimateCondition climate,
  }) {
    // Basal respiratory + insensible dermal loss (~350-450 mL/day) + sweat from heat & activity
    final basalInsensible = (weightKg * 5.0).round();
    final heatFactor = (calculateClimateMultiplier(climate) - 1.0).clamp(0.0, 1.0);
    final thermalSweat = (weightKg * 22.0 * heatFactor).round();
    final activitySweat = activityMinutes * 10;
    return basalInsensible + thermalSweat + activitySweat;
  }
}

