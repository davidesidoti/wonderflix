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

  /// Pallino degli amici online (spec F §8.3).
  static const online = Color(0xFF5BBF6A);

  /// Fondo delle voci dei film nel calendario (oro scuro, piano 25b).
  static const calendarMovie = Color(0xFF2B2418);

  /// Fondo delle voci delle serie nel calendario (blu scuro, piano 25b).
  static const calendarSeries = Color(0xFF1D2630);
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

/// Sulla TV il bordo del controllo col focus (spec: "elemento con il focus
/// sempre ben visibile").
const tvFocusSide = BorderSide(color: WfColors.gold, width: 2);

/// Lo stesso sui pulsanti oro, dove un bordo oro non si vedrebbe.
const tvFocusSideOnGold = BorderSide(color: WfColors.cream, width: 2);

/// Sulla TV: [base] in ogni stato e [focus] col focus. Fuori dalla TV `null`,
/// così `ButtonStyle.copyWith` lascia lo stile com'è.
WidgetStateBorderSide? tvButtonSide(
  bool tv,
  BorderSide? base, [
  BorderSide focus = tvFocusSide,
]) => tv
    ? WidgetStateBorderSide.resolveWith(
        (states) => states.contains(WidgetState.focused) ? focus : base,
      )
    : null;

/// Il tema dell'app. Con [tv] ogni controllo col focus ha un bordo largo 2
/// ([tvFocusSide]) e un velo oro; fuori dalla TV non cambia nulla.
ThemeData buildWonderflixTheme({bool tv = false}) {
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

  // Velo dell'elemento col focus (InkWell, voci di elenco, menu) sulla TV.
  final focusColor = tv ? WfColors.gold.withValues(alpha: 0.24) : null;

  return base.copyWith(
    focusColor: focusColor,
    // Avvisi flottanti nei colori dell'app (spec C §11.4).
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: WfColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: WfColors.cream),
      actionTextColor: WfColors.gold,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: WfColors.border),
      ),
    ),
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
      ).copyWith(side: tvButtonSide(tv, null, tvFocusSideOnGold)),
    ),
    elevatedButtonTheme: tv
        ? ElevatedButtonThemeData(
            style: ButtonStyle(side: tvButtonSide(tv, null)))
        : null,
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WfColors.gold,
        side: const BorderSide(color: WfColors.gold),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ).copyWith(
          side: tvButtonSide(tv, const BorderSide(color: WfColors.gold))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: WfColors.gold)
          .copyWith(side: tvButtonSide(tv, null)),
    ),
    iconButtonTheme: tv
        ? IconButtonThemeData(style: ButtonStyle(side: tvButtonSide(tv, null)))
        : null,
    segmentedButtonTheme: tv
        ? SegmentedButtonThemeData(
            // Il contorno è del gruppo: il velo crema (visibile anche sul
            // segmento oro scelto) dice quale segmento.
            style: ButtonStyle(
              side: tvButtonSide(tv, BorderSide(color: scheme.outline)),
              overlayColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.focused)
                      ? WfColors.cream.withValues(alpha: 0.22)
                      : null),
            ))
        : null,
    tabBarTheme: TabBarThemeData(
      labelColor: WfColors.gold,
      unselectedLabelColor: WfColors.creamMuted,
      indicatorColor: WfColors.gold,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      overlayColor: tv
          ? WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused) ? focusColor : null)
          : null,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: WfColors.surface,
      textStyle: TextStyle(color: WfColors.cream),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: WfColors.gold),
  );
}
