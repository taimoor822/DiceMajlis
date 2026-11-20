import 'package:flutter/material.dart';

import 'majlis_colors.dart';
import 'majlis_palette.dart';

/// Dark ("night majlis", the default) and light ("bright majlis") themes.
abstract final class AppTheme {
  static ThemeData dark() => _build(
    colors: const ColorScheme(
      brightness: Brightness.dark,
      primary: MajlisPalette.gold,
      onPrimary: MajlisPalette.onGold,
      primaryContainer: MajlisPalette.goldDeep,
      onPrimaryContainer: MajlisPalette.ivory,
      secondary: MajlisPalette.turquoise,
      onSecondary: Color(0xFF04211E),
      tertiary: MajlisPalette.emerald,
      onTertiary: MajlisPalette.ivory,
      error: MajlisPalette.danger,
      onError: MajlisPalette.ivory,
      surface: MajlisPalette.navySurface,
      onSurface: MajlisPalette.sand,
      onSurfaceVariant: Color(0xFFB4C3C7),
      surfaceContainerHighest: MajlisPalette.navyRaised,
      outline: Color(0xFF3C5A66),
      outlineVariant: Color(0xFF26414D),
    ),
    majlis: MajlisColors.dark,
    scaffold: MajlisPalette.navy,
  );

  static ThemeData light() => _build(
    colors: const ColorScheme(
      brightness: Brightness.light,
      primary: MajlisPalette.teal,
      onPrimary: MajlisPalette.ivory,
      primaryContainer: Color(0xFFCBE6E3),
      onPrimaryContainer: MajlisPalette.teal,
      secondary: MajlisPalette.goldDeep,
      onSecondary: MajlisPalette.ivory,
      tertiary: MajlisPalette.emerald,
      onTertiary: MajlisPalette.ivory,
      error: MajlisPalette.danger,
      onError: MajlisPalette.ivory,
      surface: MajlisPalette.ivory,
      onSurface: MajlisPalette.ink,
      onSurfaceVariant: MajlisPalette.inkMuted,
      surfaceContainerHighest: MajlisPalette.sandDeep,
      outline: Color(0xFFB9A88C),
      outlineVariant: Color(0xFFDCCDB5),
    ),
    majlis: MajlisColors.light,
    scaffold: MajlisPalette.sand,
  );

  static ThemeData _build({
    required ColorScheme colors,
    required MajlisColors majlis,
    required Color scaffold,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      brightness: colors.brightness,
    );
    final text = base.textTheme.apply(
      bodyColor: colors.onSurface,
      displayColor: colors.onSurface,
    );
    final radius = BorderRadius.circular(16);

    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      extensions: [majlis],
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: majlis.glassFill,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: majlis.glassBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: majlis.glassFill,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: majlis.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: majlis.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: majlis.gold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: majlis.glassFill,
        selectedColor: majlis.gold,
        labelStyle: text.labelLarge?.copyWith(color: colors.onSurface),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: colors.onPrimary),
        side: BorderSide(color: majlis.glassBorder),
        shape: const StadiumBorder(),
        showCheckmark: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.surfaceContainerHighest,
        contentTextStyle: text.bodyMedium?.copyWith(color: colors.onSurface),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: majlis.glassBorder),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: majlis.gold),
      dividerTheme: DividerThemeData(color: colors.outlineVariant),
      listTileTheme: ListTileThemeData(
        iconColor: colors.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: majlis.backgroundBottom,
        surfaceTintColor: Colors.transparent,
        indicatorColor: majlis.gold.withValues(alpha: 0.22),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? majlis.gold
                : majlis.textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? majlis.gold
                : majlis.textMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            // Six items share the bar: slightly smaller, no extra spacing,
            // so labels stay on one line on small phones.
            fontSize: 10.5,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
