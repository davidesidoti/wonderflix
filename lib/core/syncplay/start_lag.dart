/// Ritardo con cui il player riparte dopo una ripresa programmata (mpv
/// impiega qualche centinaio di millisecondi). Si impara dalle misure e si
/// compensa allineandosi in anticipo (Piano 5b).
class StartLag {
  static const max = Duration(seconds: 1);

  /// Quanto di ogni misura entra nella stima.
  static const weight = 0.5;

  Duration _value = Duration.zero;

  Duration get value => _value;

  /// [drift] = scarto misurato alla fine del periodo iniziale (posizione
  /// attesa − posizione), con l'anticipo attuale già applicato.
  void record(Duration drift) {
    final next = _value + drift * weight;
    _value = next < Duration.zero
        ? Duration.zero
        : next > max
            ? max
            : next;
  }
}
