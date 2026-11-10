import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrochime/core/theme/app_colors.dart';
import 'package:hydrochime/core/theme/app_theme.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/domain/models/user_profile.dart';
import 'package:hydrochime/main.dart';
import 'package:hydrochime/presentation/providers/hydration_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Theme & Color Tokens (Stitch Design Specification)', () {
    test('Dark Theme tokens match Stitch Nature Material UI specs', () {
      expect(AppColors.darkCanvas, const Color(0xFF000000));
      expect(AppColors.darkSurfaceCard, const Color(0xFF08080A));
      expect(AppColors.darkSurfaceElevated, const Color(0xFF121316));
      expect(AppColors.darkPrimaryVital, const Color(0xFF0EA5E9));
      expect(AppColors.darkPrimaryAtmosphere, const Color(0xFF38BDF8));
      expect(AppColors.darkBorderSubtle, const Color(0x0FFFFFFF));
    });

    test('Light Theme tokens match Stitch Nature Material UI specs', () {
      expect(AppColors.lightCanvas, const Color(0xFFFBFBFA));
      expect(AppColors.lightSurfaceCard, const Color(0xFFFFFFFF));
      expect(AppColors.lightPrimaryVital, const Color(0xFF16A34A));
      expect(AppColors.lightPrimaryAtmosphere, const Color(0xFF22C55E));
    });

    test('AppTheme creates valid Dark and Light ThemeData with HydroChimeColors extension',
        () {
      final darkTheme = AppTheme.dark;
      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.scaffoldBackgroundColor, AppColors.darkCanvas);
      final darkExt = darkTheme.extension<HydroChimeColors>();
      expect(darkExt, isNotNull);
      expect(darkExt!.canvas, AppColors.darkCanvas);
      expect(darkExt.primaryVital, AppColors.darkPrimaryVital);
      expect(darkExt.isDark, isTrue);

      final lightTheme = AppTheme.light;
      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.scaffoldBackgroundColor, AppColors.lightCanvas);
      final lightExt = lightTheme.extension<HydroChimeColors>();
      expect(lightExt, isNotNull);
      expect(lightExt!.canvas, AppColors.lightCanvas);
      expect(lightExt.primaryVital, AppColors.lightPrimaryVital);
      expect(lightExt.isDark, isFalse);
    });

    testWidgets('HydroChimeApp derives ThemeMode dynamically from userProfile.isDarkMode',
        (tester) async {
      Database? db;
      AppDatabase? appDb;
      await tester.runAsync(() async {
        appDb = AppDatabase.inMemory();
        db = await appDb!.database;
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          await appDb?.close();
        });
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(AsyncData(db!)),
            userProfileProvider.overrideWithValue(
              AsyncData(UserProfile.defaultProfile.copyWith(isDarkMode: false)),
            ),
          ],
          child: const HydroChimeApp(),
        ),
      );
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);

      // Unmount ProviderScope before closing DB
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
