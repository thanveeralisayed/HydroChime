import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkCanvas,
        colorScheme: const ColorScheme.dark(
          surface: AppColors.darkSurfaceCard,
          primary: AppColors.darkPrimaryVital,
          secondary: AppColors.darkPrimaryAtmosphere,
          onSurface: AppColors.darkTextPrimary,
        ),
        extensions: const [HydroChimeColors.dark],
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.lightCanvas,
        colorScheme: const ColorScheme.light(
          surface: AppColors.lightSurfaceCard,
          primary: AppColors.lightPrimaryVital,
          secondary: AppColors.lightPrimaryAtmosphere,
          onSurface: AppColors.lightTextPrimary,
        ),
        extensions: const [HydroChimeColors.light],
      );
}
