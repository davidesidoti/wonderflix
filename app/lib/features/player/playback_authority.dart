/// Chi esegue pausa, ripresa e salti chiesti dall'utente: il player stesso
/// oppure, nel watch party, il gruppo.
abstract interface class PlaybackAuthority {
  Future<void> play();

  Future<void> pause();

  /// [position] è già entro i limiti del video.
  Future<void> seekTo(Duration position);
}
