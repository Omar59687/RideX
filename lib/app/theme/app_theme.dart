import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_text_styles.dart';
import 'package:ridex/app/theme/ridex_theme.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(
        colorScheme: _lightColorScheme,
        extension: RideXTheme.light,
      );

  static ThemeData dark() => _build(
        colorScheme: _darkColorScheme,
        extension: RideXTheme.dark,
      );

  static ThemeData _build({
    required ColorScheme colorScheme,
    required RideXTheme extension,
  }) {
    final textTheme = AppTextStyles.textTheme(
      textPrimary: colorScheme.onSurface,
      textSecondary: colorScheme.onSurfaceVariant,
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: BorderSide(color: colorScheme.outline),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      fontFamily: AppTextStyles.fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.brightness == Brightness.light
          ? AppColors.pearl50
          : AppColors.midnight900,
      canvasColor: colorScheme.surface,
      cardColor: colorScheme.surface,
      dividerColor: colorScheme.outline,
      disabledColor: extension.disabledContent,
      focusColor: extension.focus,
      shadowColor: colorScheme.shadow,
      extensions: <ThemeExtension<dynamic>>[extension],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: cardShape,
        margin: EdgeInsets.zero,
        shadowColor: colorScheme.shadow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium,
        errorStyle: textTheme.bodySmall?.copyWith(color: colorScheme.error),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: extension.focus, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.error, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: extension.disabledBackground),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          disabledBackgroundColor: extension.disabledBackground,
          disabledForegroundColor: extension.disabledContent,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          disabledBackgroundColor: extension.disabledBackground,
          disabledForegroundColor: extension.disabledContent,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          disabledForegroundColor: extension.disabledContent,
          foregroundColor: colorScheme.onSurface,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          side: BorderSide(color: colorScheme.outline),
          backgroundColor: colorScheme.surface,
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          disabledForegroundColor: extension.disabledContent,
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(44, 44),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          disabledForegroundColor: extension.disabledContent,
          minimumSize: const Size(44, 44),
          shape: controlShape,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        modalBackgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: colorScheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surface,
        selectedColor: colorScheme.primaryContainer,
        disabledColor: extension.disabledBackground,
        labelStyle: textTheme.labelMedium!,
        secondaryLabelStyle:
            textTheme.labelMedium!.copyWith(color: colorScheme.primary),
        side: BorderSide(color: colorScheme.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return extension.disabledContent;
          }
          return colorScheme.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return extension.disabledBackground;
          }
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.outline;
        }),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outline,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        shape: controlShape,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.primaryContainer,
        circularTrackColor: colorScheme.primaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onInverseSurface),
        actionTextColor: colorScheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.24),
        selectionHandleColor: colorScheme.primary,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
    );
  }

  static const _lightColorScheme = ColorScheme.light(
    primary: AppColors.iris500,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: AppColors.iris50,
    onPrimaryContainer: AppColors.iris900,
    secondary: AppColors.aqua700,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: AppColors.aqua50,
    onSecondaryContainer: AppColors.aqua900,
    tertiary: AppColors.coral700,
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: AppColors.coral50,
    onTertiaryContainer: AppColors.coral900,
    error: Color(0xFFB43B52),
    onError: Color(0xFFFFFFFF),
    errorContainer: AppColors.coral50,
    onErrorContainer: AppColors.coral900,
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF242233),
    surfaceDim: AppColors.pearl300,
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: AppColors.lavender50,
    surfaceContainer: AppColors.pearl100,
    surfaceContainerHigh: AppColors.pearl300,
    surfaceContainerHighest: AppColors.pearl500,
    onSurfaceVariant: Color(0xFF6F6B7D),
    outline: Color(0xFFE2DEEB),
    outlineVariant: AppColors.pearl300,
    shadow: Color(0xFF28234A),
    scrim: Color(0xFF19162B),
    inverseSurface: AppColors.midnight700,
    onInverseSurface: AppColors.pearl50,
    inversePrimary: AppColors.iris300,
    surfaceTint: AppColors.iris50,
  );

  static const _darkColorScheme = ColorScheme.dark(
    primary: AppColors.iris300,
    onPrimary: AppColors.midnight900,
    primaryContainer: AppColors.iris900,
    onPrimaryContainer: AppColors.iris100,
    secondary: AppColors.aqua300,
    onSecondary: AppColors.midnight900,
    secondaryContainer: AppColors.aqua900,
    onSecondaryContainer: AppColors.aqua100,
    tertiary: AppColors.coral300,
    onTertiary: AppColors.midnight900,
    tertiaryContainer: AppColors.coral900,
    onTertiaryContainer: AppColors.coral100,
    error: Color(0xFFFF9AAA),
    onError: AppColors.midnight900,
    errorContainer: AppColors.coral900,
    onErrorContainer: AppColors.coral100,
    surface: AppColors.midnight700,
    onSurface: AppColors.pearl50,
    surfaceDim: AppColors.midnight900,
    surfaceBright: AppColors.midnight500,
    surfaceContainerLowest: AppColors.midnight900,
    surfaceContainerLow: Color(0xFF211D38),
    surfaceContainer: AppColors.midnight700,
    surfaceContainerHigh: Color(0xFF332C5C),
    surfaceContainerHighest: AppColors.midnight500,
    onSurfaceVariant: Color(0xFFC5C0D2),
    outline: AppColors.midnight500,
    outlineVariant: Color(0xFF3C3856),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: AppColors.pearl50,
    onInverseSurface: Color(0xFF242233),
    inversePrimary: AppColors.iris700,
    surfaceTint: Color(0xFF332C5C),
  );
}
