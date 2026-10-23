import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/video/vtt.dart';

void main() {
  test('WebVTT: salta intestazione e NOTE, toglie i tag', () {
    const source =
        'WEBVTT - prova\n'
        '\n'
        'NOTE una nota\n'
        'su due righe\n'
        '\n'
        '1\n'
        '00:00:01.000 --> 00:00:02.500\n'
        'Ciao <i>mondo</i>\n'
        '\n'
        '00:00:03.000 --> 00:00:04.000 align:start\n'
        'Prima riga\n'
        'seconda riga\n';
    final cues = parseVtt(source);
    expect(cues, hasLength(2));
    expect(cues[0].start, const Duration(seconds: 1));
    expect(cues[0].end, const Duration(seconds: 2, milliseconds: 500));
    expect(cues[0].text, 'Ciao mondo');
    expect(cues[1].start, const Duration(seconds: 3));
    expect(cues[1].text, 'Prima riga\nseconda riga');
  });

  test('SRT: virgola nei millisecondi', () {
    const source =
        '\uFEFF1\r\n'
        '00:01:02,003 --> 00:01:04,000\r\n'
        'Testo\r\n';
    final cues = parseVtt(source);
    expect(cues, hasLength(1));
    expect(
      cues.single.start,
      const Duration(minutes: 1, seconds: 2, milliseconds: 3),
    );
    expect(cues.single.end, const Duration(minutes: 1, seconds: 4));
    expect(cues.single.text, 'Testo');
  });
}
