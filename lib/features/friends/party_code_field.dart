import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../core/social/social_models.dart';

/// Campo del codice di un party privato: maiuscole, solo lettere e cifre,
/// al massimo 6, con il trattino dopo le prime 3 (`K7P-Q2X`). Il cursore
/// resta dopo lo stesso carattere; il trattino non si cancella da solo
/// (Backspace o Canc accanto a lui tolgono il carattere vicino).
class PartyCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    var caret = newValue.selection.isValid
        ? math.min(newValue.selection.extentOffset, text.length)
        : text.length;
    // Tolto solo il trattino (il formato lo rimetterebbe): va via il
    // carattere accanto, prima del cursore con Backspace (il cursore torna
    // indietro), dopo con Canc (il cursore resta).
    final oldCaret = oldValue.selection.extentOffset;
    if (oldValue.selection.isValid &&
        oldValue.selection.isCollapsed &&
        text.length == oldValue.text.length - 1 &&
        normalizePartyCode(text) == normalizePartyCode(oldValue.text)) {
      if (caret < oldCaret && caret > 0) {
        text = text.substring(0, caret - 1) + text.substring(caret);
        caret--;
      } else if (caret == oldCaret && caret < text.length) {
        text = text.substring(0, caret) + text.substring(caret + 1);
      }
    }
    var code = normalizePartyCode(text);
    if (code.length > partyCodeLength) {
      code = code.substring(0, partyCodeLength);
    }
    final formatted = code.length > partyCodeGroupLength
        ? '${code.substring(0, partyCodeGroupLength)}-'
            '${code.substring(partyCodeGroupLength)}'
        : code;
    // Il cursore dopo lo stesso numero di lettere e cifre; oltre il primo
    // gruppo c'è anche il trattino.
    final before = math.min(
        normalizePartyCode(text.substring(0, caret)).length, code.length);
    final offset = before + (before > partyCodeGroupLength ? 1 : 0);
    return TextEditingValue(
        text: formatted, selection: TextSelection.collapsed(offset: offset));
  }
}
