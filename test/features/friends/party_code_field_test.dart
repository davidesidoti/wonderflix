import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/friends/party_code_field.dart';

void main() {
  String format(String text) => PartyCodeFormatter()
      .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text))
      .text;

  test('maiuscole, solo lettere e cifre, trattino dopo 3, al massimo 6', () {
    expect(format('k7p'), 'K7P');
    expect(format('k7pq'), 'K7P-Q');
    expect(format('k7p q2x'), 'K7P-Q2X');
    expect(format('K7P-Q2X9'), 'K7P-Q2X');
    expect(format('K7P-'), 'K7P');
  });

  TextEditingValue at(String text, int caret) => TextEditingValue(
      text: text, selection: TextSelection.collapsed(offset: caret));

  TextEditingValue edit(TextEditingValue old, TextEditingValue next) =>
      PartyCodeFormatter().formatEditUpdate(old, next);

  test('scrivendo in fondo il cursore resta in fondo, dopo il trattino', () {
    final result = edit(at('K7P', 3), at('K7PQ', 4));
    expect(result.text, 'K7P-Q');
    expect(result.selection, const TextSelection.collapsed(offset: 5));
  });

  test('modifica in mezzo: il cursore resta dove si scrive', () {
    // K|7P-Q2: si scrive A dopo la K.
    final result = edit(at('K7P-Q2', 1), at('KA7P-Q2', 2));
    expect(result.text, 'KA7-PQ2');
    expect(result.selection, const TextSelection.collapsed(offset: 2));
  });

  test('Backspace subito dopo il trattino: va via anche il carattere prima',
      () {
    final result = edit(at('K7P-Q2X', 4), at('K7PQ2X', 3));
    expect(result.text, 'K7Q-2X');
    expect(result.selection, const TextSelection.collapsed(offset: 2));
  });

  test('Canc subito prima del trattino: va via il carattere dopo', () {
    final result = edit(at('K7P-Q2X', 3), at('K7PQ2X', 3));
    expect(result.text, 'K7P-2X');
    expect(result.selection, const TextSelection.collapsed(offset: 3));
  });
}
