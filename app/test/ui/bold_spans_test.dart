import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/bold_spans.dart';

void main() {
  test('grassetto sulla prima occorrenza di ogni nome', () {
    final span = boldSpans('Luigi ti invita a guardare Dune', [
      'Luigi',
      'Dune',
    ]);
    final bold = [
      for (final s in span.children!.cast<TextSpan>())
        if (s.style?.fontWeight == FontWeight.w600) s.text,
    ];
    expect(bold, ['Luigi', 'Dune']);
    expect(span.toPlainText(), 'Luigi ti invita a guardare Dune');
    expect(boldSpans('Nuova richiesta', ['']).toPlainText(), 'Nuova richiesta');
    expect(
      boldSpans('Nuova richiesta', ['Dune']).toPlainText(),
      'Nuova richiesta',
    );
  });
}
