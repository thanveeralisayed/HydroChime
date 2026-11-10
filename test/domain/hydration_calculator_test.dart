import 'package:flutter_test/flutter_test.dart';
import 'package:hydrochime/domain/calculators/hydration_calculator.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/domain/models/climate_condition.dart';

void main() {
  group('HydrationCalculator (TDD - Scientific Framework & Stitch Specs)', () {
    const calculator = HydrationCalculator();

    test('calculates baseline volume requirement accurately (35 mL / kg)', () {
      expect(calculator.calculateBaseline(weightKg: 70), 2450);
      expect(calculator.calculateBaseline(weightKg: 60), 2100);
      expect(calculator.calculateBaseline(weightKg: 85), 2975);
    });

    test('calculates activity adjustment accurately (12 mL / min)', () {
      expect(calculator.calculateActivityAdjustment(durationMinutes: 0), 0);
      expect(calculator.calculateActivityAdjustment(durationMinutes: 35), 420);
      expect(calculator.calculateActivityAdjustment(durationMinutes: 60), 720);
    });

    group('Climate Multiplier (C_factor)', () {
      test('standard ambient (T < 22°C, normal humidity) yields 1.0x baseline factor', () {
        const condition = ClimateCondition(temperatureCelsius: 20, relativeHumidity: 50);
        expect(calculator.calculateClimateMultiplier(condition), 1.0);
      });

      test('moderate heat (22°C <= T < 30°C) yields 1.15x (+15%)', () {
        const condition = ClimateCondition(temperatureCelsius: 25, relativeHumidity: 45);
        expect(calculator.calculateClimateMultiplier(condition), 1.15);
      });

      test('high heat index (T >= 30°C) yields 1.30x (+30%)', () {
        const condition = ClimateCondition(temperatureCelsius: 31, relativeHumidity: 40);
        expect(calculator.calculateClimateMultiplier(condition), 1.30);
      });

      test('arid environment (RH < 30%) adds +0.10x scalar', () {
        const standardArid = ClimateCondition(temperatureCelsius: 20, relativeHumidity: 25);
        expect(calculator.calculateClimateMultiplier(standardArid), closeTo(1.10, 0.001));

        const highHeatArid = ClimateCondition(temperatureCelsius: 32, relativeHumidity: 20);
        expect(calculator.calculateClimateMultiplier(highHeatArid), closeTo(1.40, 0.001));
      });

      test('humid heat (RH > 75% and T >= 28°C) adds +0.05x scalar', () {
        const humidHeat = ClimateCondition(temperatureCelsius: 29, relativeHumidity: 80);
        // Moderate heat (1.15) + Humid heat (0.05) = 1.20x
        expect(calculator.calculateClimateMultiplier(humidHeat), closeTo(1.20, 0.001));

        const extremeHumidHeat = ClimateCondition(temperatureCelsius: 33, relativeHumidity: 85);
        // High heat (1.30) + Humid heat (0.05) = 1.35x
        expect(calculator.calculateClimateMultiplier(extremeHumidHeat), closeTo(1.35, 0.001));
      });
    });

    test('reproduces exact Stitch design calculation: 70kg, 35m workout, 31°C = 3,731 mL', () {
      const condition = ClimateCondition(temperatureCelsius: 31, relativeHumidity: 38);
      final result = calculator.calculateTotalTarget(
        weightKg: 70,
        activityMinutes: 35,
        climate: condition,
      );

      expect(result.baselineMl, 2450);
      expect(result.activityMl, 420);
      expect(result.climateDeltaMl, 861);
      expect(result.totalTargetMl, 3731);
    });

    group('Beverage Efficiencies', () {
      test('water has 1.0x efficiency', () {
        expect(calculator.calculateEffectiveIntake(250, BeverageType.water), 250);
      });

      test('electrolytes have 1.45x efficiency', () {
        expect(calculator.calculateEffectiveIntake(350, BeverageType.electrolytes), 508);
      });

      test('herbal tea has 1.0x efficiency', () {
        expect(calculator.calculateEffectiveIntake(250, BeverageType.herbalTea), 250);
      });

      test('coffee has 0.8x efficiency', () {
        expect(calculator.calculateEffectiveIntake(200, BeverageType.coffee), 160);
      });
    });
  });
}

