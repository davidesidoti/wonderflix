/// Pulsanti del pannello media di sistema e dei tasti multimediali.
enum MediaButton { play, pause, next, previous, stop }

/// Pannello media di sistema (su Windows: SMTC): titolo, immagine, stato
/// e tasti multimediali, attivi anche con l'app in secondo piano.
///
/// Una sola sessione per tutta l'app (il pannello di sistema è uno per
/// processo): ogni schermata del player la aggiorna e ascolta [buttons];
/// uscendo dal player la si nasconde con [clear], senza chiuderla.
abstract class MediaSession {
  /// `true` se la sessione riceve già i tasti multimediali della tastiera
  /// (play/pausa, successivo, stop): il player non deve gestirli una
  /// seconda volta.
  bool get handlesMediaKeys;

  Future<void> setMetadata({
    required String title,
    String? subtitle,
    String? thumbnailUrl,
  });

  Future<void> setPlaying(bool playing);

  Future<void> setTimeline({
    required Duration position,
    required Duration duration,
  });

  Future<void> setNextEnabled(bool enabled);

  /// Pulsante "precedente" del pannello (spec H §9.1).
  Future<void> setPreviousEnabled(bool enabled);

  /// Persone nel watch party (`null` = fuori da un gruppo). Solo Discord lo
  /// mostra.
  Future<void> setParty(int? members);

  Stream<MediaButton> get buttons;

  /// Nasconde e disattiva il pannello (uscita dal player); il prossimo
  /// [setMetadata] lo mostra di nuovo.
  Future<void> clear();

  /// Libera le risorse: solo alla chiusura dell'app.
  Future<void> dispose();
}

/// Nessun pannello (test, o SMTC non disponibile).
class NoopMediaSession implements MediaSession {
  @override
  bool get handlesMediaKeys => false;

  @override
  Future<void> setMetadata(
      {required String title, String? subtitle, String? thumbnailUrl}) async {}

  @override
  Future<void> setPlaying(bool playing) async {}

  @override
  Future<void> setTimeline(
      {required Duration position, required Duration duration}) async {}

  @override
  Future<void> setNextEnabled(bool enabled) async {}

  @override
  Future<void> setPreviousEnabled(bool enabled) async {}

  @override
  Future<void> setParty(int? members) async {}

  @override
  Stream<MediaButton> get buttons => const Stream.empty();

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}
}
