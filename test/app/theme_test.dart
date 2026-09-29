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
}
