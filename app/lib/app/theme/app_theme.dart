import 'package:flutter/material.dart';
import 'package:metromitra/app/theme/tokens.dart';

/// Inter for Latin, Noto Sans Devanagari as fallback for Hindi (bundled, OFL).
const _fontFamily = 'Inter';
const _fontFallback = ['NotoSansDevanagari'];

/// [seed] is the admin's brand colour (null = the built-in palette). A seed
/// builds the whole scheme with Material's tonal palette, so contrast holds in
/// light and dark; only the neutral surfaces stay ours.
ThemeData buildTheme(Brightness brightness, {Color? seed}) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: seed ?? AppColors.primaryLight,
    brightness: brightness,
  );
  final scheme = base.copyWith(
    primary: seed != null
        ? base.primary
        : (dark ? AppColors.primaryDark : AppColors.primaryLight),
    secondary: seed != null
        ? base.secondary
        : (dark ? AppColors.secondaryDark : AppColors.secondaryLight),
    surface: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
    surfaceContainer: dark
        ? AppColors.surfaceContainerDark
        : AppColors.surfaceContainerLight,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    textTheme: _textTheme(scheme),
    extensions: [if (dark) StatusColors.dark else StatusColors.light],
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: const StadiumBorder(),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// Scale (sp): display 32/40 · title 22/28 · body 16/24 · label 14/20 ·
/// caption 12/16. Numbers use tabular figures.
TextTheme _textTheme(ColorScheme scheme) {
  TextStyle style(double size, double height, [FontWeight? weight]) =>
      TextStyle(
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        color: scheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  return TextTheme(
    displayLarge: style(32, 40, FontWeight.w600),
    displayMedium: style(32, 40, FontWeight.w600),
    displaySmall: style(32, 40, FontWeight.w600),
    headlineLarge: style(22, 28, FontWeight.w600),
    headlineMedium: style(22, 28, FontWeight.w600),
    headlineSmall: style(22, 28, FontWeight.w600),
    titleLarge: style(22, 28, FontWeight.w600),
    titleMedium: style(16, 24, FontWeight.w600),
    titleSmall: style(14, 20, FontWeight.w600),
    bodyLarge: style(16, 24),
    bodyMedium: style(16, 24),
    bodySmall: style(14, 20),
    labelLarge: style(14, 20, FontWeight.w500),
    labelMedium: style(14, 20, FontWeight.w500),
    labelSmall: style(12, 16, FontWeight.w500),
  );
}
