import 'package:sqflite/sqflite.dart';
import '../../domain/models/beverage_type.dart';
import '../../domain/models/intake_log.dart';

class IntakeLogRepository {
  final Database _db;

  IntakeLogRepository(this._db);

  Future<int> insertLog(IntakeLog log) async {
    return await _db.insert('intake_logs', log.toMap());
  }

  Future<int> updateLog(IntakeLog log) async {
    if (log.id == null) {
      throw ArgumentError('Cannot update IntakeLog without an existing id');
    }
    final data = log.toMap()..remove('id');
    return await _db.update(
      'intake_logs',
      data,
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<int> deleteLog(int id) async {
    return await _db.delete(
      'intake_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<IntakeLog>> getRecentLogs({int limit = 20}) async {
    final maps = await _db.query(
      'intake_logs',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((m) => IntakeLog.fromMap(m)).toList();
  }

  Future<List<IntakeLog>> getLogsForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day).toIso8601String();
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999)
        .toIso8601String();

    final maps = await _db.query(
      'intake_logs',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startOfDay, endOfDay],
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => IntakeLog.fromMap(m)).toList();
  }

  Future<List<IntakeLog>> getLogsForDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final rangeStart = DateTime(start.year, start.month, start.day).toIso8601String();
    final rangeEnd = DateTime(end.year, end.month, end.day, 23, 59, 59, 999)
        .toIso8601String();

    final maps = await _db.query(
      'intake_logs',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [rangeStart, rangeEnd],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => IntakeLog.fromMap(m)).toList();
  }

  Future<int> getEffectiveVolumeForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day).toIso8601String();
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999)
        .toIso8601String();

    final result = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(effective_volume_ml), 0) as total
      FROM intake_logs
      WHERE timestamp >= ? AND timestamp <= ?
      ''',
      [startOfDay, endOfDay],
    );

    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<Map<DateTime, int>> getDailyEffectiveTotals(
    DateTime start,
    DateTime end,
  ) async {
    final rangeStart = DateTime(start.year, start.month, start.day).toIso8601String();
    final rangeEnd = DateTime(end.year, end.month, end.day, 23, 59, 59, 999)
        .toIso8601String();

    final maps = await _db.query(
      'intake_logs',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [rangeStart, rangeEnd],
    );

    final totals = <DateTime, int>{};
    for (final map in maps) {
      final log = IntakeLog.fromMap(map);
      final dayKey = DateTime(
        log.timestamp.year,
        log.timestamp.month,
        log.timestamp.day,
      );
      totals[dayKey] = (totals[dayKey] ?? 0) + log.effectiveVolumeMl;
    }
    return totals;
  }

  Future<List<int>> getHourlyDistribution({
    required DateTime date,
    required int startHour,
    required int endHour,
    bool resolveActiveShift = false,
  }) async {
    if (startHour == endHour) return [];
    final isOvernight = endHour < startHour;
    final hoursCount = isOvernight
        ? (24 - startHour + endHour)
        : (endHour - startHour);
    final distribution = List.filled(hoursCount, 0);

    if (!isOvernight) {
      final startOfDay =
          DateTime(date.year, date.month, date.day).toIso8601String();
      final endOfDay =
          DateTime(date.year, date.month, date.day, 23, 59, 59, 999)
              .toIso8601String();

      final logs = await _db.query(
        'intake_logs',
        where: 'timestamp >= ? AND timestamp <= ?',
        whereArgs: [startOfDay, endOfDay],
      );

      for (final map in logs) {
        final log = IntakeLog.fromMap(map);
        final hour = log.timestamp.hour;
        if (hour >= startHour && hour < endHour) {
          distribution[hour - startHour] += log.effectiveVolumeMl;
        }
      }
      return distribution;
    }

    final day = DateTime(date.year, date.month, date.day);
    final offsetDays =
        (resolveActiveShift && date.hour < startHour) ? -1 : 0;
    final shiftStart = day.add(Duration(days: offsetDays, hours: startHour));
    final shiftEnd = shiftStart.add(Duration(hours: hoursCount));

    final logs = await _db.query(
      'intake_logs',
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [shiftStart.toIso8601String(), shiftEnd.toIso8601String()],
    );

    for (final map in logs) {
      final log = IntakeLog.fromMap(map);
      final bucketIndex = log.timestamp.difference(shiftStart).inHours;
      if (bucketIndex >= 0 && bucketIndex < hoursCount) {
        distribution[bucketIndex] += log.effectiveVolumeMl;
      }
    }

    return distribution;
  }

  Future<Map<BeverageType, int>> getBeverageDistributionForDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final maps = await _db.query(
      'intake_logs',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );

    final distribution = <BeverageType, int>{
      for (final type in BeverageType.values) type: 0,
    };

    for (final map in maps) {
      final log = IntakeLog.fromMap(map);
      distribution[log.beverageType] =
          (distribution[log.beverageType] ?? 0) + log.volumeMl;
    }

    return distribution;
  }

  Future<void> upsertDailySummary({
    required DateTime date,
    required int baselineGoalMl,
    required int adjustedGoalMl,
    required int totalIngestedMl,
    double? weatherTemp,
    double? weatherHumidity,
    required int consistencyScore,
  }) async {
    final dateKey = _formatDateKey(date);
    await _db.insert(
      'daily_summaries',
      {
        'date': dateKey,
        'baseline_goal_ml': baselineGoalMl,
        'adjusted_goal_ml': adjustedGoalMl,
        'total_ingested_ml': totalIngestedMl,
        'weather_temp': weatherTemp,
        'weather_humidity': weatherHumidity,
        'consistency_score': consistencyScore,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getDailySummary(DateTime date) async {
    final dateKey = _formatDateKey(date);
    final rows = await _db.query(
      'daily_summaries',
      where: 'date = ?',
      whereArgs: [dateKey],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, int>> getAdjustedGoalsForDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final startKey = _formatDateKey(start);
    final endKey = _formatDateKey(end);
    final rows = await _db.query(
      'daily_summaries',
      columns: ['date', 'adjusted_goal_ml'],
      where: 'date >= ? AND date <= ?',
      whereArgs: [startKey, endKey],
    );
    return {
      for (final row in rows)
        row['date'] as String: (row['adjusted_goal_ml'] as num).toInt(),
    };
  }

  String _formatDateKey(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }
}
