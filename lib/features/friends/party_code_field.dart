import 'package:flutter/services.dart';

import '../../core/social/social_models.dart';

/// Campo del codice di un party privato: maiuscole, solo lettere e cifre,
/// al massimo 6, con il trattino dopo le prime 3 (`K7P-Q2X`).
class PartyCodeFormatter extends TextInputFormatter {
  /// Caratteri prima del trattino (come `formatPartyCode`).
  static const groupLength = 3;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var code = normalizePartyCode(newValue.text);
    if (code.length > partyCodeLength) {
      code = code.substring(0, partyCodeLength);
    }
    final text = code.length > groupLength
        ? '${code.substring(0, groupLength)}-${code.substring(groupLength)}'
        : code;
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
