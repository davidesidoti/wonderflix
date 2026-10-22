import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/player/player_volume.dart';

void main() {
  const key = 'player.volume';

  Future<SharedPreferences> prefsWith(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    return SharedPreferences.getInstance();
  }

  ProviderContainer containerFor(SharedPreferences prefs) =>
      ProviderContainer.test(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);

  test('volume salvato: assente, valido, fuori intervallo, NaN', () async {
    Future<double> read(Map<String, Object> saved) async =>
        containerFor(await prefsWith(saved)).read(playerVolumeProvider);
    expect(await read({}), 100);
    expect(await read({key: 35.0}), 35);
    expect(await read({key: 150.0}), 100);
    expect(await read({key: -5.0}), 0);
    expect(await read({key: double.nan}), 100);
  });

  test('set: stato subito, disco dopo 500 ms dall\'ultimo cambio', () async {
    final prefs = await prefsWith({});
    fakeAsync((async) {
      final container = containerFor(prefs);
      final volume = container.read(playerVolumeProvider.notifier);
      volume.set(80);
      expect(container.read(playerVolumeProvider), 80);
      async.elapse(const Duration(milliseconds: 300));
      volume.set(60);
      expect(container.read(playerVolumeProvider), 60);
      // 700 ms dal primo cambio: il conto è ripartito con il secondo, l'80
      // non è mai stato scritto.
      async.elapse(const Duration(milliseconds: 400));
      expect(prefs.getDouble(key), isNull);
      async.elapse(const Duration(milliseconds: 100));
      expect(prefs.getDouble(key), 60);
    });
  });

  test('set: stesso valore, fuori intervallo, NaN', () async {
    final prefs = await prefsWith({});
    fakeAsync((async) {
      final container = containerFor(prefs);
      final volume = container.read(playerVolumeProvider.notifier);
      // 100 è già lo stato (chiave assente): niente da scrivere.
      volume.set(100);
      volume.set(150);
      volume.set(double.nan);
      async.elapse(PlayerVolumeController.saveDelay);
      expect(container.read(playerVolumeProvider), 100);
      expect(prefs.getDouble(key), isNull);

      volume.set(-5);
      expect(container.read(playerVolumeProvider), 0);
      async.elapse(PlayerVolumeController.saveDelay);
      expect(prefs.getDouble(key), 0);

      // NaN va ignorato davvero: senza il controllo, `clamp` lo porterebbe
      // a 100 e lo stato cambierebbe.
      volume.set(double.nan);
      async.elapse(PlayerVolumeController.saveDelay);
      expect(container.read(playerVolumeProvider), 0);
      expect(prefs.getDouble(key), 0);
    });
  });

  test('flush: scrive subito il valore in sospeso, poi niente', () async {
    final prefs = await prefsWith({});
    fakeAsync((async) {
      final container = containerFor(prefs);
      final volume = container.read(playerVolumeProvider.notifier);
      volume.set(45);
      expect(prefs.getDouble(key), isNull);
      unawaited(volume.flush());
      expect(prefs.getDouble(key), 45);
      // Il timer è stato annullato: allo scadere non succede niente.
      async.elapse(PlayerVolumeController.saveDelay);
      expect(prefs.getDouble(key), 45);
      expect(container.read(playerVolumeProvider), 45);
      // Senza niente in sospeso un secondo flush non tocca il disco: un
      // valore scritto da fuori resta com'è.
      unawaited(prefs.setDouble(key, 7));
      unawaited(volume.flush());
      async.flushMicrotasks();
      expect(prefs.getDouble(key), 7);
      expect(container.read(playerVolumeProvider), 45);
    });
  });

  test('chiusura con una scrittura in sospeso: scritta subito', () async {
    final prefs = await prefsWith({});
    fakeAsync((async) {
      final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      container.read(playerVolumeProvider.notifier).set(30);
      expect(prefs.getDouble(key), isNull);
      container.dispose();
      expect(prefs.getDouble(key), 30);
      // Il timer è fermo: nessun'altra scrittura.
      async.elapse(PlayerVolumeController.saveDelay);
      expect(prefs.getDouble(key), 30);
    });
  });
}
