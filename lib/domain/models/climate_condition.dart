class ClimateCondition {
  final double temperatureCelsius;
  final double relativeHumidity; // in percentage (0 - 100)
  final double? apparentTemperatureCelsius;

  const ClimateCondition({
    required this.temperatureCelsius,
    required this.relativeHumidity,
    this.apparentTemperatureCelsius,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClimateCondition &&
          runtimeType == other.runtimeType &&
          temperatureCelsius == other.temperatureCelsius &&
          relativeHumidity == other.relativeHumidity &&
          apparentTemperatureCelsius == other.apparentTemperatureCelsius;

  @override
  int get hashCode =>
      temperatureCelsius.hashCode ^
      relativeHumidity.hashCode ^
      apparentTemperatureCelsius.hashCode;
}

