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
}
