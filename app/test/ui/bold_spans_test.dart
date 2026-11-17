import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/bold_spans.dart';

List<String?> _bold(TextSpan span) => [
  for (final s in span.children!.cast<TextSpan>())
    if (s.style?.fontWeight == FontWeight.w700) s.text,
];

void main() {
  test('grassetto sulla prima occorrenza di ogni nome', () {
    final span = boldSpans('Luigi ti invita a guardare Dune', [
      'Luigi',
      'Dune',
    ]);
    expect(_bold(span), ['Luigi', 'Dune']);
    expect(span.toPlainText(), 'Luigi ti invita a guardare Dune');
    expect(boldSpans('Nuova richiesta', ['']).toPlainText(), 'Nuova richiesta');
    expect(
      boldSpans('Nuova richiesta', ['Dune']).toPlainText(),
      'Nuova richiesta',
    );
  });

  test('grassetto crema', () {
    final span = boldSpans('Luigi ti invita', ['Luigi']);
    final bold = span.children!.first as TextSpan;
    expect(bold.style?.color, WfColors.cream);
    expect(bold.style?.fontWeight, FontWeight.w700);
  });

  test('ordine inverso delle parole', () {
    final span = boldSpans('Luigi ti invita a guardare Dune', [
      'Dune',
      'Luigi',
    ]);
    expect(_bold(span), ['Luigi', 'Dune']);
  });

  test('doppioni con una sola occorrenza nel testo', () {
    final span = boldSpans('Dune ti aspetta', ['Dune', 'Dune']);
    expect(_bold(span), ['Dune']);
    expect(span.toPlainText(), 'Dune ti aspetta');
  });

  test('titolo che sta dentro il nome: si cerca di nuovo più avanti', () {
    final span = boldSpans('Italo ti invita a guardare It', ['Italo', 'It']);
    expect(_bold(span), ['Italo', 'It']);
    final reversed = boldSpans('Italo ti invita a guardare It', [
      'It',
      'Italo',
    ]);
    expect(_bold(reversed), ['Italo', 'It']);
    expect(reversed.toPlainText(), 'Italo ti invita a guardare It');
  });

  test('titolo uguale al nome', () {
    final span = boldSpans('Luigi ti invita a guardare Luigi', [
      'Luigi',
      'Luigi',
    ]);
    expect(_bold(span), ['Luigi', 'Luigi']);
    expect(span.toPlainText(), 'Luigi ti invita a guardare Luigi');
  });
}
