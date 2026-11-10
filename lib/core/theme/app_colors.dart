import 'package:flutter/material.dart';

/// Design tokens derived from Stitch Nature Material UI Design System.
abstract class AppColors {
  // Dark Theme (Default)
  static const Color darkCanvas = Color(0xFF000000);
  static const Color darkSurfaceCard = Color(0xFF08080A);
  static const Color darkSurfaceElevated = Color(0xFF121316);
  static const Color darkPrimaryVital = Color(0xFF0EA5E9);
  static const Color darkPrimaryAtmosphere = Color(0xFF38BDF8);
  static const Color darkPrimaryDeep = Color(0xFF0284C7);
  static const Color darkBorderSubtle = Color(0x0FFFFFFF); // rgba(255, 255, 255, 0.06)
  static const Color darkBorderFocus = Color(0x660EA5E9); // rgba(14, 165, 233, 0.40)
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF475569);

  // Light Theme (Complement)
  static const Color lightCanvas = Color(0xFFFBFBFA);
  static const Color lightSurfaceCard = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF4F4F0);
  static const Color lightPrimaryVital = Color(0xFF16A34A);
  static const Color lightPrimaryAtmosphere = Color(0xFF22C55E);
  static const Color lightPrimaryDeep = Color(0xFF15803D);
  static const Color lightBorderSubtle = Color(0x0F000000); // rgba(0, 0, 0, 0.06)
  static const Color lightBorderFocus = Color(0x6616A34A);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightTextTertiary = Color(0xFF94A3B8);
}

@immutable
class HydroChimeColors extends ThemeExtension<HydroChimeColors> {
  final Color canvas;
  final Color surfaceCard;
  final Color surfaceElevated;
  final Color primaryVital;
  final Color primaryAtmosphere;
  final Color primaryDeep;
  final Color borderSubtle;
  final Color borderFocus;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final bool isDark;

  const HydroChimeColors({
    required this.canvas,
    required this.surfaceCard,
    required this.surfaceElevated,
    required this.primaryVital,
    required this.primaryAtmosphere,
    required this.primaryDeep,
    required this.borderSubtle,
    required this.borderFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.isDark,
  });

  static const dark = HydroChimeColors(
    canvas: AppColors.darkCanvas,
    surfaceCard: AppColors.darkSurfaceCard,
    surfaceElevated: AppColors.darkSurfaceElevated,
    primaryVital: AppColors.darkPrimaryVital,
    primaryAtmosphere: AppColors.darkPrimaryAtmosphere,
    primaryDeep: AppColors.darkPrimaryDeep,
    borderSubtle: AppColors.darkBorderSubtle,
    borderFocus: AppColors.darkBorderFocus,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    isDark: true,
  );

  static const light = HydroChimeColors(
    canvas: AppColors.lightCanvas,
    surfaceCard: AppColors.lightSurfaceCard,
    surfaceElevated: AppColors.lightSurfaceElevated,
    primaryVital: AppColors.lightPrimaryVital,
    primaryAtmosphere: AppColors.lightPrimaryAtmosphere,
    primaryDeep: AppColors.lightPrimaryDeep,
    borderSubtle: AppColors.lightBorderSubtle,
    borderFocus: AppColors.lightBorderFocus,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    isDark: false,
  );

  static HydroChimeColors of(BuildContext context) {
    final ext = Theme.of(context).extension<HydroChimeColors>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.light ? light : dark;
  }

  @override
  HydroChimeColors copyWith({
    Color? canvas,
    Color? surfaceCard,
    Color? surfaceElevated,
    Color? primaryVital,
    Color? primaryAtmosphere,
    Color? primaryDeep,
    Color? borderSubtle,
    Color? borderFocus,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    bool? isDark,
  }) {
    return HydroChimeColors(
      canvas: canvas ?? this.canvas,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      primaryVital: primaryVital ?? this.primaryVital,
      primaryAtmosphere: primaryAtmosphere ?? this.primaryAtmosphere,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderFocus: borderFocus ?? this.borderFocus,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  HydroChimeColors lerp(ThemeExtension<HydroChimeColors>? other, double t) {
    if (other is! HydroChimeColors) return this;
    return HydroChimeColors(
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t) ?? surfaceCard,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t) ?? surfaceElevated,
      primaryVital: Color.lerp(primaryVital, other.primaryVital, t) ?? primaryVital,
      primaryAtmosphere:
          Color.lerp(primaryAtmosphere, other.primaryAtmosphere, t) ??
              primaryAtmosphere,
      primaryDeep: Color.lerp(primaryDeep, other.primaryDeep, t) ?? primaryDeep,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t) ?? borderFocus,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t) ?? textTertiary,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
