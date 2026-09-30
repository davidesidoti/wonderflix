import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/drift_corrector.dart';

void main() {
  const ms = Duration(milliseconds: 1);
  late DriftCorrector corrector;

  setUp(() => corrector = DriftCorrector());

  DriftAction feed(Duration drift,
          {double rate = 1.0,
          Duration sinceUnpause = const Duration(seconds: 10),
          Duration? sinceResync}) =>
      corrector.update(
          drift: drift,
          rate: rate,
          sinceUnpause: sinceUnpause,
          sinceResync: sinceResync);

  /// Tre letture uguali: riempie la finestra della media.
  DriftAction steady(Duration drift, {double rate = 1.0}) {
    feed(drift, rate: rate);
    feed(drift, rate: rate);
    return feed(drift, rate: rate);
  }

  double rateOf(DriftAction action) => (action as ChangeRate).rate;

  test('servono 3 letture prima di agire', () {
    expect(feed(ms * 500), isA<KeepRate>());
    expect(feed(ms * 500), isA<KeepRate>());
    expect(rateOf(feed(ms * 500)), DriftCorrector.fastRate);
  });

  test('zona morta: sotto i 150 ms nessuna correzione', () {
    expect(steady(ms * 149), isA<KeepRate>());
    corrector.reset();
    expect(steady(ms * -149), isA<KeepRate>());
  });

  test('indietro accelera, avanti rallenta', () {
    expect(rateOf(steady(ms * 150)), 1.05);
    corrector.reset();
    expect(rateOf(steady(ms * -2999)), 0.95);
  });

  test('isteresi: si torna a 1,0 solo sotto i 40 ms', () {
    expect(steady(ms * 100, rate: 1.05), isA<KeepRate>());
    expect(rateOf(steady(ms * 39, rate: 1.05)), 1.0);
    corrector.reset();
    expect(rateOf(steady(ms * -39, rate: 0.95)), 1.0);
  });

  test('bersaglio superato: si torna a 1,0', () {
    expect(rateOf(steady(ms * -60, rate: 1.05)), 1.0);
    corrector.reset();
    expect(rateOf(steady(ms * 60, rate: 0.95)), 1.0);
  });

  test('oltre 3 s: risincronizza e svuota la finestra', () {
    expect(steady(ms * 3001), isA<Resync>());
    expect(feed(ms * 3001), isA<KeepRate>());
    corrector.reset();
    expect(steady(ms * -3001), isA<Resync>());
  });

  test('primi 1,5 s dopo la ripresa: nessuna correzione', () {
    expect(feed(ms * 500, sinceUnpause: ms * 1499), isA<KeepRate>());
    expect(rateOf(feed(ms * 500, rate: 1.05, sinceUnpause: ms * 100)), 1.0);
    // La finestra riparte da zero finito il periodo iniziale.
    expect(feed(ms * 500), isA<KeepRate>());
    expect(feed(ms * 500), isA<KeepRate>());
    expect(rateOf(feed(ms * 500)), 1.05);
  });

  test('5 s dopo un salto: nessuna correzione', () {
    feed(ms * 500, sinceResync: ms * 4999);
    feed(ms * 500, sinceResync: ms * 4999);
    expect(feed(ms * 500, sinceResync: ms * 4999), isA<KeepRate>());
    feed(ms * 500, sinceResync: ms * 5000);
    feed(ms * 500, sinceResync: ms * 5000);
    expect(rateOf(feed(ms * 500, sinceResync: ms * 5000)), 1.05);
  });

  test('lastDrift: media dell\'ultima finestra piena', () {
    expect(corrector.lastDrift, isNull);
    feed(ms * 100);
    feed(ms * 200);
    feed(ms * 300);
    expect(corrector.lastDrift, ms * 200);
  });

  test('reset svuota la finestra', () {
    feed(ms * 500);
    feed(ms * 500);
    corrector.reset();
    expect(feed(ms * 500), isA<KeepRate>());
  });
}
