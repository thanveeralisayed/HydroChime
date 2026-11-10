import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../domain/models/intake_log.dart';
import '../../domain/models/user_profile.dart';

class VaultExportService {
  final Database _db;

  VaultExportService(this._db);

  Future<String> exportToJson() async {
    final profileMaps = await _db.query(
      'user_profile',
      where: 'id = ?',
      whereArgs: [1],
    );
    final profileMap = profileMaps.isEmpty
        ? UserProfile.defaultProfile.toMap()
        : profileMaps.first;

    final logMaps = await _db.query(
      'intake_logs',
      orderBy: 'timestamp ASC',
    );

    final payload = {
      'version': 1,
      'app': 'HydroChime',
      'exported_at': DateTime.now().toIso8601String(),
      'profile': profileMap,
      'logs': logMaps,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<String> exportToCsv() async {
    final logMaps = await _db.query(
      'intake_logs',
      orderBy: 'timestamp ASC',
    );

    final buffer = StringBuffer(
      'id,timestamp,beverage_type,volume_ml,effective_volume_ml\n',
    );
    for (final row in logMaps) {
      buffer.writeln(
        '${row['id']},${row['timestamp']},${row['beverage_type']},${row['volume_ml']},${row['effective_volume_ml']}',
      );
    }
    return buffer.toString();
  }

  Future<int> restoreFromJson(String jsonStr) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (_) {
      throw const FormatException('Malformed JSON backup');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup root must be a JSON object');
    }
    if (decoded['app'] != 'HydroChime' ||
        decoded['profile'] is! Map ||
        decoded['logs'] is! List) {
      throw const FormatException('Invalid HydroChime backup schema');
    }

    final UserProfile parsedProfile;
    final List<IntakeLog> parsedLogs;
    try {
      parsedProfile = UserProfile.fromMap(
        Map<String, dynamic>.from(decoded['profile'] as Map),
      );
      parsedLogs = (decoded['logs'] as List)
          .map(
            (item) => IntakeLog.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      throw const FormatException('Invalid profile or intake log record in backup');
    }

    await _db.transaction((txn) async {
      await txn.insert(
        'user_profile',
        parsedProfile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('intake_logs');
      for (final log in parsedLogs) {
        await txn.insert('intake_logs', log.toMap());
      }
    });

    return parsedLogs.length;
  }

  Future<String> saveJsonBackupToDocuments() async {
    final json = await exportToJson();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'hydrochime_vault_backup.json'));
    await file.writeAsString(json);
    return file.path;
  }

  Future<String> saveCsvToDocuments() async {
    final csv = await exportToCsv();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'hydrochime_hydration_history.csv'));
    await file.writeAsString(csv);
    return file.path;
  }

  Future<int> restoreFromDocumentsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'hydrochime_vault_backup.json'));
    if (!await file.exists()) {
      throw const FormatException('No saved backup file found in local documents');
    }
    final contents = await file.readAsString();
    return restoreFromJson(contents);
  }
}

