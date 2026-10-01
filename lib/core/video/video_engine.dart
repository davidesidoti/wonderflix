import 'package:flutter/widgets.dart';

/// Cosa aprire: URL, header HTTP (il token non va nell'URL) e posizione di
/// partenza (applicata all'apertura, non come salto successivo).
class VideoSource {
  const VideoSource({
    required this.url,
    this.headers = const {},
    this.start = Duration.zero,
  });

  final String url;
  final Map<String, String> headers;
  final Duration start;
}

enum EngineTrackType { video, audio, subtitle }

/// Traccia vista dal motore (per mpv: una voce di `track-list`).
class EngineTrack {
  const EngineTrack({
    required this.id,
    required this.type,
    this.ffIndex,
    this.external = false,
    this.title,
    this.language,
  });

  /// Id del motore (per mpv: il valore di `aid`/`sid`), numerato per tipo.
  final String id;
  final EngineTrackType type;

  /// Indice dello stream nel file (`ff-index`); `null` per le tracce esterne.
  final int? ffIndex;
  final bool external;
  final String? title;
  final String? language;
}

/// Il file non si è aperto (errore di rete o di formato, timeout).
class EngineOpenException implements Exception {
  const EngineOpenException(this.message);

  final String message;

  @override
  String toString() => 'EngineOpenException($message)';
}

/// Interfaccia del player video, indipendente da media_kit. Serve a provare
/// il player con un motore finto e, nello Spec B (watch party), a
/// controllarne posizione e velocità.
abstract class VideoEngine {
  /// Apre [source] in pausa: la riproduzione parte con [play], dopo aver
  /// scelto le tracce. Si completa quando il file è caricato; lancia
  /// [EngineOpenException] se non si apre (e in quel caso non lascia nulla
  /// di caricato).
  Future<void> open(VideoSource source);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// 0–100.
  Future<void> setVolume(double volume);

  /// Velocità di riproduzione (1.0 = normale). L'audio mantiene il tono. Il
  /// watch party la usa per recuperare piccoli scarti senza salti.
  Future<void> setRate(double rate);

  Future<List<EngineTrack>> tracks();

  /// Id da [tracks]; `null` = nessuna traccia.
  Future<void> selectAudio(String? id);

  Future<void> selectSubtitle(String? id);

  /// Carica e seleziona un sottotitolo esterno. Restituisce il suo id, o
  /// `null` se non si è caricato (resta selezionato quello di prima).
  Future<String?> addSubtitle(String url, {String? title, String? language});

  /// Positivo = sottotitoli più tardi.
  Future<void> setSubtitleDelay(Duration delay);

  /// Dimensione dei sottotitoli: 1.0 = normale.
  Future<void> setSubtitleScale(double scale);

  Future<void> dispose();

  Duration get position;

  Duration get duration;

  /// Fin dove il video è già scaricato.
  Duration get buffer;

  bool get playing;

  Stream<Duration> get positionStream;

  Stream<Duration> get durationStream;

  Stream<Duration> get bufferStream;

  Stream<bool> get playingStream;

  Stream<bool> get bufferingStream;

  /// `true` alla fine del video.
  Stream<bool> get completedStream;

  /// Errori segnalati dal motore durante la riproduzione (solo per il log).
  Stream<String> get errorStream;

  /// Si completa quando il primo fotogramma è disegnato. Vale una volta per
  /// motore: per le aperture successive ("Riprova", ripiego sulla
  /// conversione) è già completato.
  Future<void> get firstFrame;

  /// Superficie su cui viene disegnato il video.
  Widget buildView();
}
