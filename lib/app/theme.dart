import 'package:flutter/material.dart';

/// Token colore Noir & Oro (spec, sezione 6).
abstract final class WfColors {
  static const bg = Color(0xFF0A0A0A);
  static const surface = Color(0xFF121212);
  static const surfaceHigh = Color(0xFF1B1B1B);
  static const border = Color(0xFF262626);
  static const gold = Color(0xFFD4A64A);
  static const cream = Color(0xFFF2EAD3);
  static const creamMuted = Color(0x99F2EAD3);
  static const error = Color(0xFFC8463C);
}

abstract final class WfText {
  static const displayFamily = 'BebasNeue';

  /// Titoli in Bebas Neue, come il logo.
  static TextStyle display(double size, {Color color = WfColors.cream}) =>
      TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        height: 1,
        letterSpacing: 1,
        color: color,
      );
}

ThemeData buildWonderflixTheme() {
  const scheme = ColorScheme.dark(
    primary: WfColors.gold,
    onPrimary: WfColors.bg,
    secondary: WfColors.gold,
    onSecondary: WfColors.bg,
    surface: WfColors.bg,
    onSurface: WfColors.cream,
    surfaceContainer: WfColors.surface,
    surfaceContainerHigh: WfColors.surfaceHigh,
    error: WfColors.error,
    outline: WfColors.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WfColors.bg,
    fontFamily: 'Inter',
  );

  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color),
      );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: WfColors.cream,
      displayColor: WfColors.cream,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WfColors.surfaceHigh,
      hintStyle: const TextStyle(color: WfColors.creamMuted),
      border: border(WfColors.border),
      enabledBorder: border(WfColors.border),
      focusedBorder: border(WfColors.gold),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WfColors.gold,
        foregroundColor: WfColors.bg,
        minimumSize: const Size.fromHeight(44),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(
            fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WfColors.gold,
        side: const BorderSide(color: WfColors.gold),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: WfColors.gold),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: WfColors.gold,
      unselectedLabelColor: WfColors.creamMuted,
      indicatorColor: WfColors.gold,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: WfColors.surface,
      textStyle: TextStyle(color: WfColors.cream),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: WfColors.gold),
  );
}
