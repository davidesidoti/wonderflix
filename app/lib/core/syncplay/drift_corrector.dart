/// Cosa fare dello scarto dal gruppo.
sealed class DriftAction {
  const DriftAction();
}

/// Lasciare la velocità com'è.
final class KeepRate extends DriftAction {
  const KeepRate();
}

final class ChangeRate extends DriftAction {
  const ChangeRate(this.rate);

  final double rate;
}

/// Scarto troppo grande: saltare alla posizione del gruppo.
final class Resync extends DriftAction {
  const Resync();
}

/// Decide come recuperare lo scarto durante la visione (spec B §4.4). Non
/// legge l'ora e non tocca il player: riceve i tempi dal chiamante.
class DriftCorrector {
  static const deadZone = Duration(milliseconds: 150);
  static const settleZone = Duration(milliseconds: 40);
  static const resyncThreshold = Duration(seconds: 3);
  static const fastRate = 1.05;
  static const slowRate = 0.95;
  static const startGrace = Duration(milliseconds: 1500);
  static const resyncCooldown = Duration(seconds: 5);
  static const window = 3;

  final _samples = <Duration>[];
  Duration? _lastDrift;

  /// Media dell'ultima finestra piena (per i log); `null` all'inizio.
  Duration? get lastDrift => _lastDrift;

  void reset() => _samples.clear();

  /// [drift] = posizione attesa − posizione locale: positivo se siamo
  /// indietro. [rate] è la velocità attuale del player.
  DriftAction update({
    required Duration drift,
    required double rate,
    required Duration sinceUnpause,
    Duration? sinceResync,
  }) {
    final settling = sinceUnpause < startGrace ||
        (sinceResync != null && sinceResync < resyncCooldown);
    if (settling) {
      _samples.clear();
      return rate == 1.0 ? const KeepRate() : const ChangeRate(1.0);
    }
    _samples.add(drift);
    if (_samples.length > window) _samples.removeAt(0);
    if (_samples.length < window) return const KeepRate();
    final average = Duration(
        microseconds: _samples.fold<int>(
                0, (sum, sample) => sum + sample.inMicroseconds) ~/
            _samples.length);
    _lastDrift = average;
    final size = average.abs();
    if (size > resyncThreshold) {
      _samples.clear();
      return const Resync();
    }
    if (rate != 1.0) {
      // Se si sta accelerando, il bersaglio è superato quando lo scarto
      // diventa negativo (e viceversa).
      final overshoot =
          rate > 1.0 ? average.isNegative : average > Duration.zero;
      if (size < settleZone || overshoot) return const ChangeRate(1.0);
      return const KeepRate();
    }
    if (size >= deadZone) {
      return ChangeRate(average > Duration.zero ? fastRate : slowRate);
    }
    return const KeepRate();
  }
}
