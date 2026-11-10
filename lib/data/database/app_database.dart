import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../domain/models/user_profile.dart';

class AppDatabase {
  final bool isInMemory;
  Database? _db;

  AppDatabase({this.isInMemory = false});

  factory AppDatabase.inMemory() => AppDatabase(isInMemory: true);

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    String path;
    if (isInMemory) {
      path = inMemoryDatabasePath;
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      path = p.join(documentsDirectory.path, 'hydrochime.db');
    }

    return await openDatabase(
      path,
      version: 3,
      singleInstance: !isInMemory,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE user_profile (
        id INTEGER PRIMARY KEY,
        weight_kg REAL NOT NULL,
        custom_baseline_ml INTEGER,
        daily_activity_minutes INTEGER NOT NULL DEFAULT 0,
        active_window_start_hour INTEGER NOT NULL,
        active_window_end_hour INTEGER NOT NULL,
        weather_adaptation_enabled INTEGER NOT NULL,
        mindful_pacing_enabled INTEGER NOT NULL,
        is_dark_mode INTEGER NOT NULL DEFAULT 1,
        city_name TEXT NOT NULL DEFAULT 'Austin',
        latitude REAL NOT NULL DEFAULT 30.27,
        longitude REAL NOT NULL DEFAULT -97.74
      )
    ''');

    await db.execute('''
      CREATE TABLE intake_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        volume_ml INTEGER NOT NULL,
        beverage_type TEXT NOT NULL,
        effective_volume_ml INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_summaries (
        date TEXT PRIMARY KEY,
        baseline_goal_ml INTEGER NOT NULL,
        adjusted_goal_ml INTEGER NOT NULL,
        total_ingested_ml INTEGER NOT NULL,
        weather_temp REAL,
        weather_humidity REAL,
        consistency_score INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE weather_cache (
        id INTEGER PRIMARY KEY,
        timestamp TEXT NOT NULL,
        temperature_celsius REAL NOT NULL,
        relative_humidity REAL NOT NULL,
        apparent_temperature_celsius REAL,
        condition_label TEXT,
        latitude REAL,
        longitude REAL
      )
    ''');

    // Insert default profile
    await db.insert('user_profile', UserProfile.defaultProfile.toMap());
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _runUpgrade(db, oldVersion, newVersion);
  }

  static Future<void> migrateDatabaseForTest(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await _runUpgrade(db, oldVersion, newVersion);
  }

  static Future<void> _runUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2 && newVersion >= 2) {
      await db.execute(
        'ALTER TABLE user_profile ADD COLUMN custom_baseline_ml INTEGER',
      );
      await db.execute(
        'ALTER TABLE user_profile ADD COLUMN daily_activity_minutes INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE user_profile ADD COLUMN is_dark_mode INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute(
        "ALTER TABLE user_profile ADD COLUMN city_name TEXT NOT NULL DEFAULT 'Austin'",
      );
      await db.execute(
        'ALTER TABLE user_profile ADD COLUMN latitude REAL NOT NULL DEFAULT 30.27',
      );
      await db.execute(
        'ALTER TABLE user_profile ADD COLUMN longitude REAL NOT NULL DEFAULT -97.74',
      );
    }
    if (oldVersion < 3 && newVersion >= 3) {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='weather_cache'",
      );
      if (tables.isEmpty) {
        await db.execute('''
          CREATE TABLE weather_cache (
            id INTEGER PRIMARY KEY,
            timestamp TEXT NOT NULL,
            temperature_celsius REAL NOT NULL,
            relative_humidity REAL NOT NULL,
            apparent_temperature_celsius REAL,
            condition_label TEXT,
            latitude REAL,
            longitude REAL
          )
        ''');
      } else {
        final cols = await db.rawQuery("PRAGMA table_info('weather_cache')");
        final colNames = cols.map((c) => c['name'] as String).toSet();
        if (!colNames.contains('latitude')) {
          await db.execute(
            'ALTER TABLE weather_cache ADD COLUMN latitude REAL',
          );
        }
        if (!colNames.contains('longitude')) {
          await db.execute(
            'ALTER TABLE weather_cache ADD COLUMN longitude REAL',
          );
        }
      }
    }
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
