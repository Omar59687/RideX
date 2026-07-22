import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';

class AppTextStyles {
  const AppTextStyles._();

  static const fontFamily = 'Plus Jakarta Sans';
  static const fontFamilyFallback = <String>[
    'Avenir Next',
    'Segoe UI',
    'sans-serif',
  ];

  static TextTheme textTheme({
    Color textPrimary = AppColors.textPrimary,
    Color textSecondary = AppColors.textSecondary,
  }) {
    TextStyle style({
      required double size,
      required FontWeight weight,
      required Color color,
      double? height,
      double? letterSpacing,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }

    return TextTheme(
      displayLarge: style(
        size: 34,
        weight: FontWeight.w800,
        color: textPrimary,
        height: 1.08,
        letterSpacing: -1.02,
      ),
      displayMedium: style(
        size: 34,
        weight: FontWeight.w800,
        color: textPrimary,
        height: 1.08,
        letterSpacing: -1.02,
      ),
      displaySmall: style(
        size: 34,
        weight: FontWeight.w800,
        color: textPrimary,
        height: 1.08,
        letterSpacing: -1.02,
      ),
      headlineLarge: style(
        size: 26,
        weight: FontWeight.w700,
        color: textPrimary,
        height: 1.15,
        letterSpacing: -0.52,
      ),
      headlineMedium: style(
        size: 26,
        weight: FontWeight.w700,
        color: textPrimary,
        height: 1.15,
        letterSpacing: -0.52,
      ),
      headlineSmall: style(
        size: 19,
        weight: FontWeight.w700,
        color: textPrimary,
        height: 1.15,
        letterSpacing: -0.38,
      ),
      titleLarge: style(
        size: 19,
        weight: FontWeight.w700,
        color: textPrimary,
        height: 1.15,
        letterSpacing: -0.38,
      ),
      titleMedium: style(
        size: 15,
        weight: FontWeight.w600,
        color: textPrimary,
        height: 1.55,
      ),
      titleSmall: style(
        size: 13,
        weight: FontWeight.w600,
        color: textPrimary,
        height: 1.45,
        letterSpacing: 0.26,
      ),
      bodyLarge: style(
        size: 15,
        weight: FontWeight.w500,
        color: textPrimary,
        height: 1.55,
      ),
      bodyMedium: style(
        size: 15,
        weight: FontWeight.w400,
        color: textSecondary,
        height: 1.55,
      ),
      bodySmall: style(
        size: 11,
        weight: FontWeight.w400,
        color: textSecondary,
        height: 1.45,
      ),
      labelLarge: style(
        size: 13,
        weight: FontWeight.w700,
        color: textPrimary,
        height: 1.45,
        letterSpacing: 0.26,
      ),
      labelMedium: style(
        size: 13,
        weight: FontWeight.w600,
        color: textSecondary,
        height: 1.45,
        letterSpacing: 0.26,
      ),
      labelSmall: style(
        size: 11,
        weight: FontWeight.w700,
        color: textSecondary,
        height: 1.45,
        letterSpacing: 0.88,
      ),
    );
  }
}
