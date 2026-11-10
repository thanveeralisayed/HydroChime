import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/intake_log_repository.dart';
import 'package:hydrochime/data/repositories/user_profile_repository.dart';
import 'package:hydrochime/data/services/vault_export_service.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/domain/models/intake_log.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late Database db;
  late VaultExportService vaultService;
  late IntakeLogRepository intakeRepo;
  late UserProfileRepository profileRepo;

  setUp(() async {
    appDatabase = AppDatabase.inMemory();
    db = await appDatabase.database;
    vaultService = VaultExportService(db);
    intakeRepo = IntakeLogRepository(db);
    profileRepo = UserProfileRepository(db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('VaultExportService (TDD)', () {
    test('exports user profile and intake logs to structured JSON', () async {
      await profileRepo.updateWeight(78.0);
      await intakeRepo.insertLog(IntakeLog(
        timestamp: DateTime(2026, 11, 10, 9, 15),
        volumeMl: 500,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 500,
      ));
      await intakeRepo.insertLog(IntakeLog(
        timestamp: DateTime(2026, 11, 10, 11, 30),
        volumeMl: 350,
        beverageType: BeverageType.electrolytes,
        effectiveVolumeMl: 508,
      ));

      final jsonStr = await vaultService.exportToJson();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['version'], 2);
      expect(decoded['app'], 'HydroChime');
      expect((decoded['profile'] as Map<String, dynamic>)['weight_kg'], 78.0);
      expect((decoded['logs'] as List).length, 2);
      expect(decoded['daily_summaries'], isA<List>());
    });

    test('exports intake logs to valid CSV with header row', () async {
      await intakeRepo.insertLog(IntakeLog(
        timestamp: DateTime(2026, 11, 10, 9, 15),
        volumeMl: 250,
        beverageType: BeverageType.herbalTea,
        effectiveVolumeMl: 250,
      ));

      final csv = await vaultService.exportToCsv();
      final lines = csv.trim().split('\n');

      expect(lines.length, 2);
      expect(lines[0], 'id,timestamp,beverage_type,volume_ml,effective_volume_ml');
      expect(lines[1], contains('herbalTea,250,250'));
    });

    test('restores profile and logs cleanly from JSON backup', () async {
      // Create backup from modified state
      await profileRepo.updateWeight(82.5);
      await profileRepo.updateLocation('Phoenix', 33.45, -112.07);
      await intakeRepo.insertLog(IntakeLog(
        timestamp: DateTime(2026, 11, 10, 8, 0),
        volumeMl: 750,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 750,
      ));
      final backupJson = await vaultService.exportToJson();

      // Mutate / wipe current state
      await profileRepo.updateWeight(60.0);
      await db.delete('intake_logs');
      expect((await intakeRepo.getRecentLogs()).length, 0);

      // Restore backup
      final restoredCount = await vaultService.restoreFromJson(backupJson);
      expect(restoredCount, 1);

      final restoredProfile = await profileRepo.getUserProfile();
      expect(restoredProfile.weightKg, 82.5);
      expect(restoredProfile.cityName, 'Phoenix');

      final restoredLogs = await intakeRepo.getRecentLogs();
      expect(restoredLogs.length, 1);
      expect(restoredLogs.first.volumeMl, 750);
    });

    test('throws FormatException for malformed or invalid JSON backup', () async {
      expect(
        () => vaultService.restoreFromJson('{"invalid": true}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => vaultService.restoreFromJson('not json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('exports and restores daily_summaries and preserves v1 backwards compatibility', () async {
      await intakeRepo.upsertDailySummary(
        date: DateTime(2026, 11, 8),
        baselineGoalMl: 2450,
        adjustedGoalMl: 3400,
        totalIngestedMl: 3100,
        weatherTemp: 33.0,
        weatherHumidity: 35.0,
        consistencyScore: 88,
      );
      final backupV2 = await vaultService.exportToJson();
      await db.delete('daily_summaries');
      expect(await intakeRepo.getDailySummary(DateTime(2026, 11, 8)), isNull);

      await vaultService.restoreFromJson(backupV2);
      final restoredSummary = await intakeRepo.getDailySummary(DateTime(2026, 11, 8));
      expect(restoredSummary, isNotNull);
      expect(restoredSummary!['adjusted_goal_ml'], 3400);

      // Legacy v1 JSON without daily_summaries should still restore cleanly
      final decoded = jsonDecode(backupV2) as Map<String, dynamic>;
      decoded.remove('daily_summaries');
      decoded['version'] = 1;
      await vaultService.restoreFromJson(jsonEncode(decoded));
      expect(await profileRepo.getUserProfile(), isNotNull);
    });
  });
}

