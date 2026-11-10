import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hydrochime/core/theme/app_theme.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/intake_log_repository.dart';
import 'package:hydrochime/data/repositories/user_profile_repository.dart';
import 'package:hydrochime/data/services/local_notification_service.dart';
import 'package:hydrochime/data/services/location_service.dart';
import 'package:hydrochime/data/services/vault_export_service.dart';
import 'package:hydrochime/data/services/vault_transfer_service.dart';
import 'package:hydrochime/data/services/weather_api_client.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/domain/models/climate_condition.dart';
import 'package:hydrochime/domain/models/intake_log.dart';
import 'package:hydrochime/domain/services/notification_scheduler.dart';
import 'package:hydrochime/presentation/providers/analytics_provider.dart';
import 'package:hydrochime/presentation/providers/hydration_providers.dart';
import 'package:hydrochime/presentation/screens/analytics_screen.dart';
import 'package:hydrochime/presentation/screens/climate_hydration_screen.dart';
import 'package:hydrochime/presentation/screens/settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ConfigurableClimateNotifier extends CurrentClimateNotifier {
  final ClimateCondition initial;
  _ConfigurableClimateNotifier(this.initial);

  @override
  ClimateCondition build() => initial;
}

class _FakeLocationService implements LocationService {
  final ({double latitude, double longitude}) coords;
  _FakeLocationService(this.coords);

  @override
  Future<({double latitude, double longitude})> getCurrentCoordinates() async =>
      coords;
}

class _FakeVaultTransferService implements VaultTransferService {
  final List<({String fileName, String content})> shared = [];
  final List<({String fileName, String content})> saved = [];
  Rect? lastSharePositionOrigin;
  Object? shareError;
  String? pickBackupResult;

  @override
  Future<bool> shareTextAsFile({
    required String content,
    required String fileName,
    required String mimeType,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    lastSharePositionOrigin = sharePositionOrigin;
    if (shareError != null) throw shareError!;
    shared.add((fileName: fileName, content: content));
    return true;
  }

  @override
  Future<String?> saveTextWithPicker({
    required String content,
    required String fileName,
    required String mimeType,
    required String dialogTitle,
  }) async {
    saved.add((fileName: fileName, content: content));
    return '/picked/$fileName';
  }

  @override
  Future<String?> pickBackupJsonContent() async => pickBackupResult;
}

class _SpyVaultExportService extends VaultExportService {
  int saveCsvCalls = 0;
  int saveJsonCalls = 0;

  _SpyVaultExportService(super.db);

  @override
  Future<String> saveCsvToDocuments() async {
    saveCsvCalls++;
    return '/docs/history.csv';
  }

  @override
  Future<String> saveJsonBackupToDocuments() async {
    saveJsonCalls++;
    return '/docs/vault.json';
  }
}

class _SpyNotificationService implements NotificationService {
  int requestCount = 0;
  int testChimeCount = 0;
  bool supportsScheduled = true;
  TestChimeStatus nextTestChimeStatus = TestChimeStatus.sent;

  @override
  bool get supportsScheduledNotifications => supportsScheduled;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async {
    requestCount++;
    return true;
  }

  @override
  Future<void> syncPacingSchedule({
    required List<HydrationChimeSlot> slots,
    required bool enabled,
  }) async {}

  @override
  Future<TestChimeStatus> showTestChime() async {
    testChimeCount++;
    return nextTestChimeStatus;
  }

  @override
  Future<void> cancelAll() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late Database db;
  late IntakeLogRepository intakeRepo;
  late UserProfileRepository userRepo;

  setUp(() async {
    appDatabase = AppDatabase.inMemory();
    db = await appDatabase.database;
    intakeRepo = IntakeLogRepository(db);
    userRepo = UserProfileRepository(db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Widget buildApp(
    Widget screen, {
    ClimateCondition? climate = const ClimateCondition(
      temperatureCelsius: 31.0,
      relativeHumidity: 38.0,
      apparentTemperatureCelsius: 35.2,
    ),
    WeatherApiClient? weatherApiClient,
    LocationService? locationService,
    VaultTransferService? vaultTransferService,
    VaultExportService? vaultExportService,
    NotificationService? notificationService,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(AsyncData(db)),
        intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeRepo)),
        userProfileRepositoryProvider.overrideWithValue(AsyncData(userRepo)),
        if (climate != null)
          currentClimateProvider.overrideWith(
            () => _ConfigurableClimateNotifier(climate),
          ),
        if (weatherApiClient != null)
          weatherApiClientProvider.overrideWithValue(weatherApiClient),
        if (locationService != null)
          locationServiceProvider.overrideWithValue(locationService),
        if (vaultTransferService != null)
          vaultTransferServiceProvider.overrideWithValue(vaultTransferService),
        if (vaultExportService != null)
          vaultExportServiceProvider.overrideWithValue(AsyncData(vaultExportService)),
        if (notificationService != null)
          notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: screen,
      ),
    );
  }

  Future<void> settleAsync(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  Future<void> settleWhileSaving(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await settleAsync(tester);
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pump();
  }

  void expectNoException(WidgetTester tester) {
    final err = tester.takeException();
    if (err != null) {
      fail(
        'Unexpected exception:\n'
        '${err is FlutterError ? err.toStringDeep() : err}',
      );
    }
  }

  group('ClimateHydrationScreen Interactive Tests', () {
    testWidgets('shows dynamic climate status & heat badge (cool vs hot)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildApp(
          const ClimateHydrationScreen(),
          climate: const ClimateCondition(
            temperatureCelsius: 18.0,
            relativeHumidity: 52.0,
            apparentTemperatureCelsius: 18.0,
          ),
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('TEMPERATE AMBIENT'), findsOneWidget);
      expect(find.text('HEAT ADVISORY ACTIVE'), findsNothing);
      expect(find.text('18'), findsOneWidget);
      expect(find.textContaining('2450 base + 0 active + 0 climate'), findsOneWidget);
    });

    testWidgets('Tune button adjusts activity minutes & city with live weather sync',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': 31.0,
              'relative_humidity_2m': 38,
              'apparent_temperature': 35.2,
            }
          }),
          200,
        );
      });

      await tester.pumpWidget(
        buildApp(
          const ClimateHydrationScreen(),
          weatherApiClient: WeatherApiClient(client: mockClient),
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);

      await tester.tap(find.byKey(const Key('climate_tune_button')));
      await tester.pumpAndSettle();

      // Tap 35m workout preset & Seattle location
      await tester.tap(find.text('35 min'));
      await tester.pump();
      await tester.tap(find.text('Seattle'));
      await tester.pump();
      await tester.tap(find.text('Apply Calibration'));
      await tester.pump(const Duration(milliseconds: 300));
      await settleAsync(tester);
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('Seattle • 31°C'), findsOneWidget);
      // 70kg + 35m @ 31C = 3,731 mL
      expect(find.text('3731'), findsOneWidget);
      expect(find.byKey(const Key('climate_profile_button')), findsOneWidget);
    });

    testWidgets('supports GPS, city search, custom exertion, exact heat-spike delta, and sync feedback',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int forecastCalls = 0;
      final mockClient = MockClient((req) async {
        if (req.url.host == 'geocoding-api.open-meteo.com') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'name': 'Kyoto',
                  'admin1': 'Kyoto',
                  'country': 'Japan',
                  'latitude': 35.0116,
                  'longitude': 135.7681,
                }
              ],
            }),
            200,
          );
        }
        forecastCalls++;
        final temp = forecastCalls == 1 ? 26.0 : 32.0; // +6.0C spike!
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': temp,
              'relative_humidity_2m': 42,
              'apparent_temperature': temp + 1.0,
            }
          }),
          200,
        );
      });

      await tester.pumpWidget(
        buildApp(
          const ClimateHydrationScreen(),
          climate: null,
          weatherApiClient: WeatherApiClient(client: mockClient),
          locationService: _FakeLocationService((latitude: 35.6762, longitude: 139.6503)),
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('26'), findsOneWidget);

      // Tap to sync triggers +6.0C heat spike banner & SnackBar feedback
      await tester.tap(find.byKey(const Key('climate_sync_button')));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.text('Synced 32°C weather for Austin'), findsOneWidget);
      expect(find.textContaining('+6.0°C rise detected'), findsOneWidget);

      // Open calibration sheet -> test custom exertion minutes + GPS + City Search
      await tester.tap(find.byKey(const Key('climate_tune_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('custom_activity_input')), '45');
      await tester.pump();

      await tester.tap(find.byKey(const Key('gps_location_button')));
      await settleAsync(tester);
      expect(find.textContaining('GPS (35.68, 139.65)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('city_search_input')), 'Kyoto');
      await tester.tap(find.byKey(const Key('city_search_submit')));
      await settleAsync(tester);
      expect(find.text('Kyoto, Kyoto, Japan'), findsOneWidget);
      await tester.tap(find.text('Kyoto, Kyoto, Japan'));
      await tester.pump();

      await tester.tap(find.text('Apply Calibration'));
      await settleAsync(tester);
      await settleAsync(tester);
      await settleAsync(tester);

      final savedProfile = await tester.runAsync(() => userRepo.getUserProfile());
      expect(savedProfile!.dailyActivityMinutes, 45);
      expect(savedProfile.cityName, 'Kyoto');
    });

    testWidgets('switching city in ClimateTuneSheet fetches weather once and handles 320px narrow layout',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.runAsync(() async {
        await userRepo.updateLocation(
          'GPS (37.42, -122.08) • San Francisco Peninsula',
          37.42,
          -122.08,
        );
      });

      int forecastCalls = 0;
      final mockClient = MockClient((req) async {
        forecastCalls++;
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': 24.0,
              'relative_humidity_2m': 55,
              'apparent_temperature': 24.0,
            }
          }),
          200,
        );
      });

      await tester.pumpWidget(
        buildApp(
          const ClimateHydrationScreen(),
          climate: null,
          weatherApiClient: WeatherApiClient(client: mockClient),
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);

      expectNoException(tester);
      expect(forecastCalls, 1);

      await tester.tap(find.byKey(const Key('climate_tune_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Seattle'));
      await tester.pump();
      await tester.tap(find.text('Seattle'));
      await tester.pump();
      await tester.ensureVisible(find.text('Apply Calibration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Calibration'));
      await settleWhileSaving(tester);
      await settleAsync(tester);

      // Single weather fetch for Seattle, not double-fetch
      expect(forecastCalls, 2);
      expectNoException(tester);
    });
  });

  group('AnalyticsScreen Live Engine & Interactive Tests', () {
    testWidgets('renders real SQLite metrics, supports Day/Week/Month pills & bar tap',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      await tester.runAsync(() async {
        await intakeRepo.insertLog(IntakeLog(
          timestamp: DateTime(now.year, now.month, now.day, 9, 0),
          volumeMl: 1500,
          beverageType: BeverageType.water,
          effectiveVolumeMl: 1500,
        ));
        await intakeRepo.insertLog(IntakeLog(
          timestamp: DateTime(now.year, now.month, now.day, 13, 0),
          volumeMl: 1000,
          beverageType: BeverageType.electrolytes,
          effectiveVolumeMl: 1450,
        ));
      });

      await tester.pumpWidget(
        buildApp(
          const AnalyticsScreen(),
          climate: const ClimateCondition(
            temperatureCelsius: 20.0,
            relativeHumidity: 50.0,
          ),
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);
      await settleAsync(tester);

      // Should NOT display hardcoded 94% or 3.1 L
      expect(find.text('3.1 L'), findsNothing);
      // Total effective today = 2950 -> 3.0 L, target 2450 -> Target Met 1 of 7 days
      expect(find.text('3.0 L'), findsOneWidget);
      expect(find.text('Target Met 1 of 7 days'), findsOneWidget);
      // 1500 water / 2500 raw = 60%, 1000 electrolytes / 2500 raw = 40%
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);

      // Tap Today's bar in Week view shows tooltip
      await tester.tap(find.text('60%').first); // reset tap or scroll safety
      await tester.pump();

      // Switch to Day
      await tester.tap(find.text('Day'));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.textContaining('Today Total:'), findsOneWidget);

      // Switch to Month
      await tester.tap(find.text('Month'));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.text('Target Met 1 of 30 days'), findsOneWidget);

      // Switch back to Week and tap Today's bar to verify inspect tooltip
      await tester.tap(find.text('Week'));
      await settleAsync(tester);
      await settleAsync(tester);
      final dayLetter =
          ['M', 'T', 'W', 'T', 'F', 'S', 'S'][DateTime.now().weekday - 1];
      await tester.tap(find.text(dayLetter).last);
      await tester.pump();
      expect(find.textContaining('• 2950 ml'), findsOneWidget);

      // Tap Export History opens real CSV modal
      await tester.ensureVisible(find.byKey(const Key('analytics_export_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('analytics_export_button')));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.text('Export Hydration History'), findsOneWidget);
      expect(find.textContaining('electrolytes,1000,1450'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Tune opens calibration parameters sheet
      await tester.tap(find.byKey(const Key('analytics_tune_button')));
      await tester.pumpAndSettle();
      expect(find.text('Consistency & Goal Parameters'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Refresh button works
      await tester.tap(find.byKey(const Key('analytics_refresh_button')));
      await settleAsync(tester);
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.text('Analytics refreshed'), findsOneWidget);
    });
  });

  group('SettingsScreen All Controls Tests', () {
    testWidgets('edits custom baseline, active window, privacy modal, and vault restore',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildApp(const SettingsScreen()));
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('HYDROCHIME • v1.0.0'), findsOneWidget);
      expect(find.text('7:00 AM – 10:00 PM'), findsOneWidget);
      // Dynamic climate delta for 70kg @ 31C: 3185 - 2450 = +735 ml today
      expect(find.text('(+735 ml today)'), findsOneWidget);

      // Custom Baseline & Weight edit
      await tester.tap(find.byKey(const Key('edit_baseline_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '75');
      await tester.enterText(find.byType(TextField).last, '2800');
      await tester.tap(find.text('Save'));
      await settleWhileSaving(tester);
      await tester.pumpAndSettle();
      expect(find.text('2800'), findsOneWidget);

      // Active window edit
      await tester.tap(find.byKey(const Key('active_window_row')));
      await tester.pumpAndSettle();
      expect(find.text('Active Hydration Window'), findsOneWidget);
      await tester.tap(find.text('8:00 AM'));
      await tester.pump();
      await tester.tap(find.text('9:00 PM'));
      await tester.pump();
      await tester.tap(find.text('Save Window'));
      await settleWhileSaving(tester);
      await settleAsync(tester);
      expect(find.text('8:00 AM – 9:00 PM'), findsOneWidget);

      // Privacy modal
      await tester.tap(find.byKey(const Key('privacy_vault_row')));
      await tester.pumpAndSettle();
      expect(find.text('On-Device Zero-Knowledge Vault'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Vault Export opens real JSON payload
      await tester.tap(find.byKey(const Key('settings_export_button')));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.text('Vault JSON Backup'), findsOneWidget);
      expect(find.textContaining('"app": "HydroChime"'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Vault Restore parses valid JSON backup & updates DB
      late final String backup;
      await tester.runAsync(() async {
        final vault = VaultExportService(db);
        await userRepo.updateWeight(85.0);
        backup = await vault.exportToJson();
        await userRepo.updateWeight(60.0);
      });

      await tester.tap(find.byKey(const Key('settings_restore_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('restore_json_input')), backup);
      await tester.tap(find.text('Restore Backup'));
      await settleWhileSaving(tester);

      final restoredProfile = await tester.runAsync(() => userRepo.getUserProfile());
      expect(restoredProfile!.weightKg, 85.0);
    });

    testWidgets('preserves decimal weight, supports overnight steppers, test chime, and vault Share/Picker',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final transferSpy = _FakeVaultTransferService();
      final notifSpy = _SpyNotificationService();

      late final String validBackup;
      await tester.runAsync(() async {
        final vault = VaultExportService(db);
        await userRepo.updateWeight(64.5);
        validBackup = await vault.exportToJson();
        await userRepo.updateWeight(70.0);
      });
      transferSpy.pickBackupResult = validBackup;

      await tester.pumpWidget(
        buildApp(
          const SettingsScreen(),
          vaultTransferService: transferSpy,
          notificationService: notifSpy,
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);

      // Decimal weight preservation
      await tester.tap(find.byKey(const Key('edit_baseline_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '72.5');
      await tester.tap(find.text('Save'));
      await settleWhileSaving(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('72.5 kg'), findsOneWidget);

      // Overnight active window steppers (10 PM -> 11 PM -> 12 AM)
      await tester.tap(find.byKey(const Key('active_window_row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end_hour_inc')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('end_hour_inc')));
      await tester.pump();
      expect(find.textContaining('Overnight shift'), findsOneWidget);
      await tester.tap(find.text('Save Window'));
      await settleWhileSaving(tester);
      await settleAsync(tester);
      expect(find.text('7:00 AM – 12:00 AM'), findsOneWidget);

      // Test chime button calls NotificationService.showTestChime
      await tester.tap(find.byKey(const Key('test_chime_button')));
      await settleAsync(tester);
      expect(notifSpy.testChimeCount, 1);

      // Vault export triggers Save JSON and Share
      await tester.tap(find.byKey(const Key('settings_export_button')));
      await settleAsync(tester);
      await settleAsync(tester);
      await tester.tap(find.byKey(const Key('export_save_json_button')));
      await settleAsync(tester);
      await tester.tap(find.byKey(const Key('export_share_json_button')));
      await settleAsync(tester);
      expect(transferSpy.saved, hasLength(1));
      expect(transferSpy.shared, hasLength(1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Vault restore via Pick Backup File
      await tester.tap(find.byKey(const Key('settings_restore_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('restore_pick_file_button')));
      await settleWhileSaving(tester);
      final restored = await tester.runAsync(() => userRepo.getUserProfile());
      expect(restored!.weightKg, 64.5);
    });

    testWidgets('Analytics export invokes Share/Save and Day shows outside-window intake',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      await tester.runAsync(() async {
        // Default window is 7..22 -> 2 AM is outside window
        await intakeRepo.insertLog(IntakeLog(
          timestamp: DateTime(now.year, now.month, now.day, 2, 0),
          volumeMl: 250,
          beverageType: BeverageType.water,
          effectiveVolumeMl: 250,
        ));
      });

      final transferSpy = _FakeVaultTransferService();
      await tester.pumpWidget(
        buildApp(
          const AnalyticsScreen(),
          climate: const ClimateCondition(
            temperatureCelsius: 20.0,
            relativeHumidity: 50.0,
          ),
          vaultTransferService: transferSpy,
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);
      await settleAsync(tester);

      await tester.tap(find.text('Day'));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(
        find.text('Includes 250 ml logged outside active window'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('analytics_export_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('analytics_export_button')));
      await settleAsync(tester);
      await settleAsync(tester);
      await tester.tap(find.byKey(const Key('export_save_csv_button')));
      await settleAsync(tester);
      await tester.tap(find.byKey(const Key('export_share_csv_button')));
      await settleAsync(tester);
      expect(transferSpy.saved.single.fileName, 'hydrochime_history.csv');
      expect(transferSpy.shared.single.fileName, 'hydrochime_history.csv');
      expect(transferSpy.lastSharePositionOrigin, isNotNull);
    });

    testWidgets('AnalyticsScreen keeps header/pills visible while loading and recovers on Retry',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pendingCompleter = Completer<AnalyticsData>();
      int attempt = 0;
      const recoveredData = AnalyticsData(
        range: AnalyticsRange.week,
        consistencyScore: 88,
        bars: [],
        periodTotalMl: 15400,
        dailyAverageMl: 2200,
        targetsMetCount: 4,
        totalPeriodDays: 7,
        beverageStats: [
          AnalyticsBeverageStat(
            type: BeverageType.water,
            volumeMl: 15400,
            percentage: 100,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            databaseProvider.overrideWithValue(AsyncData(db)),
            intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeRepo)),
            userProfileRepositoryProvider.overrideWithValue(AsyncData(userRepo)),
            analyticsProvider.overrideWith((_) {
              attempt++;
              if (attempt == 1) {
                return pendingCompleter.future;
              }
              return Future.value(recoveredData);
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: const AnalyticsScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ANALYTICS'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pendingCompleter.completeError('Simulated outage');
      await settleAsync(tester);
      expect(find.byKey(const Key('analytics_retry_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('analytics_retry_button')));
      await settleWhileSaving(tester);
      expect(attempt, greaterThanOrEqualTo(2));
      expect(find.text('88'), findsOneWidget);
      expect(find.text('Target Met 4 of 7 days'), findsOneWidget);
      expectNoException(tester);
    });

    testWidgets('AnalyticsScreen avoids auto-overwrite on CSV export open and handles unsupported Share on 320px layout',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spyVault = _SpyVaultExportService(db);
      final transferSpy = _FakeVaultTransferService()
        ..shareError = const VaultTransferUnsupportedException(
          'System file sharing is not supported on Linux. Use Save or Copy instead.',
        );
      await tester.pumpWidget(
        buildApp(
          const AnalyticsScreen(),
          vaultExportService: spyVault,
          vaultTransferService: transferSpy,
        ),
      );
      await settleWhileSaving(tester);
      await settleAsync(tester);
      expectNoException(tester);

      await tester.ensureVisible(find.byKey(const Key('analytics_export_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('analytics_export_button')));
      await settleAsync(tester);
      expect(spyVault.saveCsvCalls, 0);

      await tester.tap(find.byKey(const Key('export_share_csv_button')));
      await settleAsync(tester);
      expect(
        find.text(
          'System file sharing is not supported on Linux. Use Save or Copy instead.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Unable to share CSV:'), findsNothing);
      expectNoException(tester);
    });

    testWidgets('SettingsScreen handles test chime statuses, Linux scheduling status, empty restore validation, export no-overwrite, single location fetch, and 320px layout',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.runAsync(() async {
        await userRepo.updateLocation(
          'GPS (37.42, -122.08) • San Francisco Peninsula',
          37.42,
          -122.08,
        );
      });

      int forecastCalls = 0;
      final mockClient = MockClient((_) async {
        forecastCalls++;
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': 19.0,
              'relative_humidity_2m': 60,
              'apparent_temperature': 19.0,
            }
          }),
          200,
        );
      });

      final spyVault = _SpyVaultExportService(db);
      final transferSpy = _FakeVaultTransferService();
      final notifSpy = _SpyNotificationService()
        ..supportsScheduled = false
        ..nextTestChimeStatus = TestChimeStatus.permissionDenied;

      await tester.pumpWidget(
        buildApp(
          const SettingsScreen(),
          climate: null,
          weatherApiClient: WeatherApiClient(client: mockClient),
          vaultExportService: spyVault,
          vaultTransferService: transferSpy,
          notificationService: notifSpy,
        ),
      );
      await settleWhileSaving(tester);
      await settleAsync(tester);

      expectNoException(tester);
      expect(
        find.textContaining('OS background chimes unavailable on this platform'),
        findsOneWidget,
      );

      // Test chime permissionDenied vs unavailable
      await tester.ensureVisible(find.byKey(const Key('test_chime_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('test_chime_button')));
      await settleAsync(tester);
      expect(
        find.text(
          'Notification permission not granted — test chime could not be delivered.',
        ),
        findsOneWidget,
      );

      notifSpy.nextTestChimeStatus = TestChimeStatus.unavailable;
      await tester.tap(find.byKey(const Key('test_chime_button')));
      await settleAsync(tester);
      expect(
        find.text('Notifications unavailable on this platform'),
        findsOneWidget,
      );

      // Export dialog does NOT overwrite before Save JSON & passes sharePositionOrigin
      await tester.ensureVisible(find.byKey(const Key('settings_export_button')));
      await tester.pump();
      expectNoException(tester);
      await tester.tap(find.byKey(const Key('settings_export_button')));
      await settleAsync(tester);
      expect(spyVault.saveJsonCalls, 0);

      await tester.tap(find.byKey(const Key('export_share_json_button')));
      await settleAsync(tester);
      expect(transferSpy.lastSharePositionOrigin, isNotNull);

      await tester.tap(find.byKey(const Key('export_save_json_button')));
      await settleAsync(tester);
      expect(spyVault.saveJsonCalls, 1);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Empty restore validation
      await tester.ensureVisible(find.byKey(const Key('settings_restore_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_restore_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore Backup'));
      await tester.pump();
      expect(
        find.text('Paste backup JSON or choose a file above'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Location sheet makes only 1 weather fetch when switching city
      final callsBeforeLocationSwitch = forecastCalls;
      await tester.ensureVisible(find.byKey(const Key('settings_location_row')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_location_row')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Seattle'));
      await tester.pump();
      await tester.tap(find.text('Seattle'));
      await tester.pump();
      await tester.ensureVisible(find.text('Save Location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Location'));
      await settleWhileSaving(tester);
      await settleAsync(tester);
      expect(forecastCalls - callsBeforeLocationSwitch, 1);
      expectNoException(tester);
    });
  });
}
