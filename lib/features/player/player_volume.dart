import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';

/// Volume del player ricordato tra un media e l'altro e tra un avvio e
/// l'altro (issue #3): solo il livello 0–100, il muto no.
class PlayerVolumeController extends Notifier<double> {
  static const _key = 'player.volume';

  /// Pausa dall'ultimo cambio prima di scrivere su disco: trascinando la
  /// barra i cambi arrivano a decine al secondo.
  static const saveDelay = Duration(milliseconds: 500);

  /// Tenute da parte in [build]: in `onDispose` non si può usare `ref`.
  late SharedPreferences _prefs;
  Timer? _timer;

  /// Valore ancora da scrivere su disco.
  double? _pending;

  @override
  double build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    ref.onDispose(_write);
    final saved = _prefs.getDouble(_key);
    if (saved == null || saved.isNaN) return 100;
    return saved.clamp(0.0, 100.0);
  }

  /// Nuovo volume, portato tra 0 e 100: lo stato cambia subito, il disco
  /// dopo [saveDelay] dall'ultimo cambio.
  void set(double volume) {
    if (volume.isNaN) return;
    final value = volume.clamp(0.0, 100.0);
    if (value == state) return;
    state = value;
    _pending = value;
    _timer?.cancel();
    _timer = Timer(saveDelay, _write);
  }

  /// Scrive il valore in sospeso, se c'è (anche alla chiusura del provider).
  void _write() {
    _timer?.cancel();
    _timer = null;
    final value = _pending;
    if (value == null) return;
    _pending = null;
    unawaited(_prefs.setDouble(_key, value));
  }
}

final playerVolumeProvider =
    NotifierProvider<PlayerVolumeController, double>(
        PlayerVolumeController.new);
