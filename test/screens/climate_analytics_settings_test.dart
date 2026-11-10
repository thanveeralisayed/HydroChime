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
import 'package:hydrochime/data/services/vault_export_service.dart';
import 'package:hydrochime/data/services/weather_api_client.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/domain/models/climate_condition.dart';
import 'package:hydrochime/domain/models/intake_log.dart';
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
    ClimateCondition climate = const ClimateCondition(
      temperatureCelsius: 31.0,
      relativeHumidity: 38.0,
      apparentTemperatureCelsius: 35.2,
    ),
    WeatherApiClient? weatherApiClient,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(AsyncData(db)),
        intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeRepo)),
        userProfileRepositoryProvider.overrideWithValue(AsyncData(userRepo)),
        currentClimateProvider.overrideWith(
          () => _ConfigurableClimateNotifier(climate),
        ),
        if (weatherApiClient != null)
          weatherApiClientProvider.overrideWithValue(weatherApiClient),
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

      expect(find.text('HYDROCHIME • v2.4'), findsOneWidget);
      expect(find.text('7:00 AM – 10:00 PM'), findsOneWidget);
      // Dynamic climate delta for 70kg @ 31C: 3185 - 2450 = +735 ml today
      expect(find.text('(+735 ml today)'), findsOneWidget);

      // Custom Baseline & Weight edit
      await tester.tap(find.byKey(const Key('edit_baseline_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '75');
      await tester.enterText(find.byType(TextField).last, '2800');
      await tester.tap(find.text('Save'));
      await settleAsync(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await settleAsync(tester);
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
      await settleAsync(tester);
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
      await settleAsync(tester);
      await settleAsync(tester);

      final restoredProfile = await tester.runAsync(() => userRepo.getUserProfile());
      expect(restoredProfile!.weightKg, 85.0);
    });
  });
}
