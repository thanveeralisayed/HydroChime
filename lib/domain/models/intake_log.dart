import 'beverage_type.dart';

class IntakeLog {
  final int? id;
  final DateTime timestamp;
  final int volumeMl;
  final BeverageType beverageType;
  final int effectiveVolumeMl;

  const IntakeLog({
    this.id,
    required this.timestamp,
    required this.volumeMl,
    required this.beverageType,
    required this.effectiveVolumeMl,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'volume_ml': volumeMl,
      'beverage_type': beverageType.name,
      'effective_volume_ml': effectiveVolumeMl,
    };
  }

  factory IntakeLog.fromMap(Map<String, dynamic> map) {
    return IntakeLog(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      volumeMl: map['volume_ml'] as int,
      beverageType: BeverageType.values.byName(map['beverage_type'] as String),
      effectiveVolumeMl: map['effective_volume_ml'] as int,
    );
  }
}

