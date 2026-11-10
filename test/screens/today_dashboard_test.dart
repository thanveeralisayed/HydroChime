import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrochime/core/theme/app_theme.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/intake_log_repository.dart';
import 'package:hydrochime/data/repositories/user_profile_repository.dart';
import 'package:hydrochime/domain/models/user_profile.dart';
import 'package:hydrochime/presentation/providers/hydration_providers.dart';
import 'package:hydrochime/presentation/screens/main_tab_shell.dart';
import 'package:hydrochime/presentation/screens/today_dashboard_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      await tester.pump();

      // Toast appears immediately on tap
      expect(find.text('Logged +250 ml'), findsOneWidget);

      await settleAsync(tester);
      await settleAsync(tester);

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
      expect(find.text('ANALYTICS'), findsOneWidget);

      // Switch to Settings
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await settleAsync(tester);
      expect(find.text('Weather Adaptation'), findsOneWidget);
    });
  });
}
