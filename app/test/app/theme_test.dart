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
}
