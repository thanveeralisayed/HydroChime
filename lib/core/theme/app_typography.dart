import 'package:flutter/material.dart';

abstract class AppTypography {
  static const String headlineFontFamily = 'Plus Jakarta Sans';
  static const String bodyFontFamily = 'Inter';

  /// Numerical displays with tabular figures enabled to prevent layout jitter.
  static TextStyle displayLarge({Color? color}) => TextStyle(
        fontFamily: headlineFontFamily,
        fontSize: 48,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.03,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle headlineMedium({Color? color}) => TextStyle(
        fontFamily: headlineFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01,
        color: color,
      );

  static TextStyle bodyMedium({Color? color}) => TextStyle(
        fontFamily: bodyFontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  static TextStyle labelMicro({Color? color}) => TextStyle(
        fontFamily: bodyFontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.5,
        color: color,
      );
}
