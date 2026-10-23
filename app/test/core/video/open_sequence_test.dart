import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/video/open_sequence.dart';
import 'package:wonderflix/core/video/video_engine.dart';

void main() {
  late OpenSequence openings;
  late List<String> released;

  setUp(() {
    openings = OpenSequence(timeout: const Duration(milliseconds: 50));
    released = [];
  });

  Future<void> run(String name, {void Function()? attach}) => openings.run(
      attach: attach ?? () {}, release: () => released.add(name));

  test('caricato: si completa senza liberare', () async {
    final opening = run('a');
    openings.loaded();
    await opening;
    expect(released, isEmpty);
    expect(openings.pending, isFalse);
  });

  test('errore: EngineOpenException e sorgente liberata', () async {
    final opening = run('a');
    openings.failed('rete');
    await expectLater(opening, throwsA(isA<EngineOpenException>()));
    expect(released, ['a']);
  });

  test('timeout: EngineOpenException e sorgente liberata', () async {
    await expectLater(run('a'), throwsA(isA<EngineOpenException>()));
    expect(released, ['a']);
  });

  test('attach che lancia: sorgente liberata', () async {
    await expectLater(
        run('a', attach: () => throw const EngineOpenException('hls.js')),
        throwsA(isA<EngineOpenException>()));
    expect(released, ['a']);
  });

  test('una nuova apertura fa fallire subito la precedente senza toccarla',
      () async {
    final first = run('a');
    final second = run('b');
    await expectLater(first, throwsA(isA<EngineOpenException>()));
    expect(released, isEmpty);
    openings.loaded();
    await second;
    // Oltre il timeout della prima: la nuova sorgente resta caricata.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(released, isEmpty);
  });
}
