import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';

void main() {
  test('il tema usa i token Noir & Oro', () {
    final theme = buildWonderflixTheme();
    expect(theme.colorScheme.primary, WfColors.gold);
    expect(theme.colorScheme.onPrimary, WfColors.bg);
    expect(theme.scaffoldBackgroundColor, WfColors.bg);
    expect(theme.colorScheme.onSurface, WfColors.cream);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(WfText.display(40).fontFamily, 'BebasNeue');
  });

  test('snackbar flottanti nel tema', () {
    final snackBar = buildWonderflixTheme().snackBarTheme;
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.backgroundColor, WfColors.surfaceHigh);
    expect(snackBar.actionTextColor, WfColors.gold);
  });

  test('le scelte sono oro', () {
    final t = buildWonderflixTheme();
    const selected = {WidgetState.selected};
    const none = <WidgetState>{};
    expect(t.chipTheme.side?.color, isNotNull);
    expect(t.chipTheme.backgroundColor, WfColors.surfaceHigh);
    expect(t.chipTheme.selectedColor, WfColors.gold.withValues(alpha: 0.14));
    expect(t.chipTheme.checkmarkColor, WfColors.gold);
    expect(t.chipTheme.shape, isA<StadiumBorder>());
    expect(
      WidgetStateProperty.resolveAs(t.chipTheme.side, selected)?.color,
      WfColors.gold,
    );
    expect(
      WidgetStateProperty.resolveAs(t.chipTheme.side, none)?.color,
      WfColors.border,
    );
    expect(
      WidgetStateProperty.resolveAs(t.chipTheme.labelStyle, selected)?.color,
      WfColors.gold,
    );
    expect(
      WidgetStateProperty.resolveAs(t.chipTheme.labelStyle, none)?.color,
      WfColors.cream,
    );
    expect(t.checkboxTheme.fillColor!.resolve(selected), WfColors.gold);
    expect(t.checkboxTheme.checkColor!.resolve(selected), WfColors.bg);
    expect(
      WidgetStateProperty.resolveAs(t.checkboxTheme.side, none)?.color,
      WfColors.creamMuted,
    );
    expect(t.radioTheme.fillColor!.resolve(selected), WfColors.gold);
    expect(t.radioTheme.fillColor!.resolve(none), WfColors.creamMuted);
    expect(t.switchTheme.trackColor!.resolve(selected), WfColors.gold);
    expect(t.switchTheme.thumbColor!.resolve(selected), WfColors.bg);
    expect(t.switchTheme.trackColor!.resolve(none), WfColors.surfaceHigh);
    expect(t.switchTheme.thumbColor!.resolve(none), WfColors.creamMuted);
    expect(t.switchTheme.trackOutlineColor!.resolve(none), WfColors.border);
    expect(t.dropdownMenuTheme.inputDecorationTheme, t.inputDecorationTheme);
    expect(t.dropdownMenuTheme.menuStyle?.backgroundColor?.resolve(none),
        WfColors.surface);
    expect(t.dropdownMenuTheme.menuStyle?.side?.resolve(none)?.color,
        WfColors.border);
  });
}
