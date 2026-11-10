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
import 'package:hydrochime/data/services/ip_location_service.dart';
import 'package:hydrochime/data/services/local_notification_service.dart';
import 'package:hydrochime/data/services/location_service.dart';
import 'package:hydrochime/data/services/weather_api_client.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/domain/models/intake_log.dart';
import 'package:hydrochime/domain/models/user_profile.dart';
import 'package:hydrochime/domain/services/notification_scheduler.dart';
import 'package:hydrochime/main.dart';
import 'package:hydrochime/presentation/providers/hydration_providers.dart';
import 'package:hydrochime/presentation/screens/main_tab_shell.dart';
import 'package:hydrochime/presentation/screens/today_dashboard_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FailingInsertIntakeRepo extends IntakeLogRepository {
  _FailingInsertIntakeRepo(super.db);

  @override
  Future<int> insertLog(IntakeLog log) async {
    throw Exception('disk full');
  }
}

class _IdleNotificationService implements NotificationService {
  @override
  bool get supportsScheduledNotifications => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<void> syncPacingSchedule({
    required List<HydrationChimeSlot> slots,
    required bool enabled,
  }) async {}

  @override
  Future<TestChimeStatus> showTestChime() async => TestChimeStatus.unavailable;

  @override
  Future<void> cancelAll() async {}
}

class _RecordingHydrationNotifier extends HydrationNotifier {
  final List<DateTime?> recordedRefreshChecks = [];

  @override
  Future<void> refreshIfNewDay({DateTime? now}) async {
    recordedRefreshChecks.add(now);
    await super.refreshIfNewDay(now: now);
  }
}

class _StartupDeniedGpsService implements PermissionAwareLocationService {
  final List<bool> requestedFlags = [];

  @override
  Future<({double latitude, double longitude})> getCurrentCoordinates({
    bool requestPermission = true,
  }) async {
    requestedFlags.add(requestPermission);
    throw const LocationLookupException(
      'Permission denied',
      reason: LocationFailureReason.permissionDenied,
    );
  }
}

class _StartupIpService implements IpLocationService {
  final IpLocationResult result;
  int calls = 0;

  _StartupIpService(this.result);

  @override
  Future<IpLocationResult> lookupPublicIpLocation() async {
    calls++;
    return result;
  }
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

  Widget buildTestApp(Widget child, {UserProfile? initialProfile}) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(AsyncData(db)),
        intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeRepo)),
        userProfileRepositoryProvider.overrideWithValue(AsyncData(userRepo)),
        if (initialProfile != null)
          userProfileProvider.overrideWithValue(AsyncData(initialProfile)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: child,
      ),
    );
  }

  Future<void> settleAsync(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  group('TodayDashboardScreen Widget Tests', () {
    testWidgets('renders header with live location, quick log actions, and theme toggle',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.runAsync(() async {
        await userRepo.updateLocation('Seattle', 47.61, -122.33);
      });

      await tester.pumpWidget(buildTestApp(const TodayDashboardScreen()));
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('HydroChime'), findsOneWidget);
      expect(find.text('Seattle • 31°C'), findsOneWidget);
      expect(find.text('+250'), findsOneWidget);
      expect(find.text('+500'), findsOneWidget);
      expect(find.text('+750'), findsOneWidget);
      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.byKey(const Key('theme_toggle_button')), findsOneWidget);
      expect(find.byKey(const Key('today_profile_button')), findsOneWidget);
    });

    testWidgets('tapping theme toggle updates isDarkMode in UserProfileRepository',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp(const TodayDashboardScreen()));
      await settleAsync(tester);
      await settleAsync(tester);

      final before = await tester.runAsync(() => userRepo.getUserProfile());
      expect(before!.isDarkMode, isTrue);

      await tester.tap(find.byKey(const Key('theme_toggle_button')));
      await settleAsync(tester);
      await settleAsync(tester);

      final after = await tester.runAsync(() => userRepo.getUserProfile());
      expect(after!.isDarkMode, isFalse);

      // Drain toast timer
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('tapping Profile avatar opens Profile Calibration sheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp(const TodayDashboardScreen()));
      await settleAsync(tester);
      await settleAsync(tester);

      await tester.tap(find.byKey(const Key('today_profile_button')));
      await tester.pumpAndSettle();

      expect(find.text('Hydration Profile'), findsOneWidget);
      expect(find.textContaining('70 kg'), findsWidgets);
    });

    testWidgets('custom log modal validates input and supports beverage multiplier selection',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp(const TodayDashboardScreen()));
      await settleAsync(tester);
      await settleAsync(tester);

      await tester.tap(find.byKey(const Key('custom_log_button')));
      await tester.pumpAndSettle();

      // Test validation error on 0 ml
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('Log'));
      await tester.pump();
      expect(find.textContaining('Enter a volume between 1 and 5000'), findsOneWidget);

      // Select Electrolytes (1.45x) and enter 350 ml -> 508 ml effective
      await tester.tap(find.text('Cellular Electrolytes'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '350');
      await tester.pump();

      expect(find.textContaining('508 ml effective'), findsOneWidget);

      await tester.tap(find.text('Log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('Cellular Electrolytes'), findsOneWidget);
      expect(find.text('508'), findsOneWidget);

      // Drain toast timer
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('tapping +250ml triggers toast, logs water, and delete+undo works',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestApp(
          const TodayDashboardScreen(),
          initialProfile: UserProfile.defaultProfile,
        ),
      );
      await settleAsync(tester);

      await tester.tap(find.text('+250'));
      await settleAsync(tester);
      await settleAsync(tester);

      // Toast appears after DB insert completes
      expect(find.text('Logged +250 ml'), findsOneWidget);

      // Recent Activity list now displays the logged item
      expect(find.text('Spring Water'), findsOneWidget);
      expect(find.text('+250 ml'), findsOneWidget);

      // Drain toast timer
      await tester.pump(const Duration(seconds: 3));

      // Delete log and Undo
      await tester.tap(find.byIcon(Icons.close).first);
      await settleAsync(tester);
      await settleAsync(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No fluid logged today yet'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('Spring Water'), findsOneWidget);
    });

    testWidgets('tapping Recent Activity row edits log and long-pressing pill picks beverage',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestApp(
          const TodayDashboardScreen(),
          initialProfile: UserProfile.defaultProfile,
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);

      // Long-press +500 pill and choose Cellular Electrolytes (725 ml eff.)
      await tester.longPress(find.text('+500'));
      await tester.pumpAndSettle();
      expect(find.text('Quick Log +500 ml as'), findsOneWidget);
      await tester.tap(find.text('Cellular Electrolytes'));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.text('725'), findsOneWidget);

      // Tap Recent Activity row to edit to Herbal Tea 600 ml
      final logs = await tester.runAsync(() => intakeRepo.getLogsForDate(DateTime.now()));
      final id = logs!.single.id!;
      await tester.tap(find.byKey(Key('recent_log_item_$id')));
      await tester.pumpAndSettle();
      expect(find.text('Edit Hydration Entry'), findsOneWidget);

      await tester.tap(find.text('Herbal Tea'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('beverage_volume_input')), '600');
      await tester.pump();
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('Herbal Tea'), findsOneWidget);
      expect(find.text('600'), findsOneWidget);

      // Drain toast timer
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('History sheet navigates past days and supports backdated logging',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await tester.runAsync(() async {
        await intakeRepo.insertLog(IntakeLog(
          timestamp: DateTime(yesterday.year, yesterday.month, yesterday.day, 14, 0),
          volumeMl: 450,
          beverageType: BeverageType.coffee,
          effectiveVolumeMl: 360,
        ));
      });

      await tester.pumpWidget(
        buildTestApp(
          const TodayDashboardScreen(),
          initialProfile: UserProfile.defaultProfile,
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);

      await tester.tap(find.byKey(const Key('history_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.text('Hydration History'), findsOneWidget);

      await tester.tap(find.byKey(const Key('history_prev_day')));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.text(BeverageType.coffee.displayName), findsOneWidget);
      expect(find.text('Effective intake: 360 ml'), findsOneWidget);

      // Add another log for yesterday
      await tester.tap(find.byKey(const Key('history_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('beverage_volume_input')), '500');
      await tester.tap(find.text('Log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await settleAsync(tester);
      await settleAsync(tester);
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('Effective intake: 860 ml'), findsOneWidget);
    });

    testWidgets('quick-log failure shows error toast instead of false Logged feedback',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(AsyncData(db)),
            intakeLogRepositoryProvider
                .overrideWithValue(AsyncData(_FailingInsertIntakeRepo(db))),
            userProfileRepositoryProvider.overrideWithValue(AsyncData(userRepo)),
            userProfileProvider
                .overrideWithValue(AsyncData(UserProfile.defaultProfile)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: const TodayDashboardScreen(),
          ),
        ),
      );
      await settleAsync(tester);
      await settleAsync(tester);

      await tester.tap(find.text('+250'));
      await settleAsync(tester);
      await settleAsync(tester);

      expect(find.text('Logged +250 ml'), findsNothing);
      expect(find.text('Unable to save hydration log'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('renders 320px narrow screen with long GPS city label without overflow',
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
        await intakeRepo.insertLog(IntakeLog(
          timestamp: DateTime.now(),
          volumeMl: 350,
          beverageType: BeverageType.electrolytes,
          effectiveVolumeMl: 508,
        ));
      });

      await tester.pumpWidget(buildTestApp(const TodayDashboardScreen()));
      await settleAsync(tester);
      await settleAsync(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('HydroChime'), findsOneWidget);
    });
  });

  group('HydroChimeApp Foreground Midnight Rollover', () {
    testWidgets('fires refreshIfNewDay when clock crosses midnight in foreground',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spyNotifier = _RecordingHydrationNotifier();
      var fakeNow = DateTime(2026, 11, 10, 23, 59, 55);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(AsyncData(db)),
            intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeRepo)),
            userProfileRepositoryProvider.overrideWithValue(AsyncData(userRepo)),
            userProfileProvider
                .overrideWithValue(AsyncData(UserProfile.defaultProfile)),
            notificationServiceProvider
                .overrideWithValue(_IdleNotificationService()),
            hydrationNotifierProvider.overrideWith(() => spyNotifier),
          ],
          child: HydroChimeApp(nowProvider: () => fakeNow),
        ),
      );
      await settleAsync(tester);

      expect(spyNotifier.recordedRefreshChecks, isEmpty);

      fakeNow = DateTime(2026, 11, 11, 0, 0, 1);
      await tester.pump(const Duration(seconds: 7));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(spyNotifier.recordedRefreshChecks, isNotEmpty);
      expect(
        spyNotifier.recordedRefreshChecks.first,
        DateTime(2026, 11, 11, 0, 0, 1),
      );

      // Unmount and flush any final sqflite lock timers cleanly
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    });

    testWidgets('asks GPS permission on startup and falls back to public IP weather when denied',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final gpsSpy = _StartupDeniedGpsService();
      final ipStub = _StartupIpService(
        const IpLocationResult(
          latitude: 19.076,
          longitude: 72.8777,
          city: 'Mumbai',
          country: 'India',
        ),
      );
      final weatherClient = WeatherApiClient(
        client: MockClient((req) async {
          final isMumbai = req.url.queryParameters['latitude'] == '19.08' &&
              req.url.queryParameters['longitude'] == '72.88';
          return http.Response(
            jsonEncode({
              'current': {
                'temperature_2m': isMumbai ? 34.0 : 22.0,
                'relative_humidity_2m': 55,
                'apparent_temperature': isMumbai ? 36.0 : 22.0,
              }
            }),
            200,
          );
        }),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(AsyncData(db)),
            intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeRepo)),
            userProfileRepositoryProvider.overrideWithValue(AsyncData(userRepo)),
            notificationServiceProvider
                .overrideWithValue(_IdleNotificationService()),
            locationServiceProvider.overrideWithValue(gpsSpy),
            ipLocationServiceProvider.overrideWithValue(ipStub),
            weatherApiClientProvider.overrideWithValue(weatherClient),
          ],
          child: const HydroChimeApp(),
        ),
      );

      for (var i = 0; i < 6; i++) {
        await settleAsync(tester);
      }

      expect(gpsSpy.requestedFlags, [true]);
      expect(ipStub.calls, 1);
      expect(find.text('Mumbai (IP) • 34°C'), findsOneWidget);

      final savedProfile = await tester.runAsync(() => userRepo.getUserProfile());
      expect(savedProfile!.cityName, 'Mumbai (IP)');
      expect(savedProfile.locationMode, LocationMode.ip);

      // Unmount and flush any final sqflite lock timers cleanly
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    });
  });

  group('MainTabShell Navigation Tests', () {
    testWidgets('switches between Today, Climate, Analytics, and Settings tabs',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestApp(
          const MainTabShell(),
          initialProfile: UserProfile.defaultProfile,
        ),
      );
      await settleAsync(tester);

      expect(find.text('HydroChime'), findsOneWidget);

      // Switch to Climate
      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await settleAsync(tester);
      expect(find.text("Today's Adjusted Goal"), findsOneWidget);

      // Switch to Analytics
      await tester.tap(find.byIcon(Icons.insights_outlined));
      await settleAsync(tester);
      await settleAsync(tester);
      expect(find.text('ANALYTICS'), findsOneWidget);

      // Switch to Settings
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await settleAsync(tester);
      expect(find.text('Weather Adaptation'), findsOneWidget);
    });
  });
}
