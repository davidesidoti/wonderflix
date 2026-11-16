import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/tv_focusable.dart';

/// Il nodo del fuoco della cornice ([TvFocusable]) che avvolge il campo
/// trovato da [field].
FocusNode tvFrameNode(WidgetTester tester, Finder field) =>
    Focus.of(tester.element(find.descendant(
        of: find.ancestor(of: field, matching: find.byType(TvFocusable)),
        matching: find.byType(AnimatedScale))));

/// Il campo di testo dentro [field] ha il fuoco (la tastiera è aperta).
bool tvFieldFocused(WidgetTester tester, Finder field) {
  final editable = field.evaluate().first.widget is EditableText
      ? field
      : find.descendant(of: field, matching: find.byType(EditableText));
  return tester.widget<EditableText>(editable).focusNode.hasFocus;
}

/// Il fuoco è su un pulsante (il pulsante di `FilledButton`, `TextButton`, ...).
bool focusOnButton() {
  var found = false;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
    found = e.widget is ButtonStyleButton;
    return !found;
  });
  return found;
}
