import 'package:flutter/services.dart';

/// Il plugin conta i punti di codice, `maxLength` i caratteri: taglia a [max]
/// punti di codice (un'emoji ne può avere più d'uno).
TextInputFormatter capRunes(int max) =>
    TextInputFormatter.withFunction((old, value) {
      if (value.text.runes.length <= max) return value;
      final text = String.fromCharCodes(value.text.runes.take(max));
      return TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    });
