import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Il campo con la chiave [key] ha il fuoco e tutto il suo testo (di
/// [length] caratteri) selezionato: dopo un errore sotto il campo si
/// riscrive subito, senza cliccare di nuovo.
void expectFocusedAndSelected(WidgetTester tester, String key, int length) {
  final editable = tester.widget<EditableText>(find.descendant(
      of: find.byKey(Key(key)), matching: find.byType(EditableText)));
  expect(editable.focusNode.hasPrimaryFocus, isTrue);
  expect(editable.controller.selection,
      TextSelection(baseOffset: 0, extentOffset: length));
}
