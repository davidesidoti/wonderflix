import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/library_api.dart';
import '../../core/jellyfin/playback_api.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../core/video/video_engine.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import 'playback_authority.dart';
import 'playback_service.dart';
import 'player_providers.dart';
import 'player_settings.dart';
import 'player_volume.dart';
import 'progress_reporter.dart';
import 'segments.dart';
import 'track_mapping.dart';

final _log = Logger('player');

/// Elemento da riprodurre, posizione di partenza e, nel watch party, id
/// dell'elemento nella coda del gruppo (chiave del provider).
typedef PlayerArgs = ({String itemId, Duration start, String? party});

enum PlayerStatus { loading, ready, error }

class PlayerViewState {
  const PlayerViewState({
    this.status = PlayerStatus.loading,
    this.item,
    this.plan,
    this.error,
    this.playing = false,
    this.buffering = false,
    this.volume = 100,
    this.muted = false,
    this.audioIndex,
    this.subtitleIndex,
    this.subtitleDelay = Duration.zero,
    this.transcodingFallback = false,
    this.finished = false,
    this.segments = const [],
    this.nextEpisode,
    this.previousEpisode,
  });

  final PlayerStatus status;
  final JellyfinItem? item;
  final PlaybackPlan? plan;
  final Object? error;
  final bool playing;
  final bool buffering;

  /// 0–100.
  final double volume;
  final bool muted;

  /// Indici Jellyfin (`MediaStream.Index`) delle tracce in uso; `null` =
  /// nessuna.
  final int? audioIndex;
  final int? subtitleIndex;
  final Duration subtitleDelay;

  /// `true` dopo il ripiego automatico sulla transcodifica.
  final bool transcodingFallback;

  /// Il video è arrivato alla fine: la schermata esce dal player.
  final bool finished;

  /// Intro, riassunto, crediti… (vuoto finché non sono caricati).
  final List<MediaSegment> segments;

  /// Episodio che segue quello in riproduzione (solo per le serie).
  final JellyfinItem? nextEpisode;

  /// Episodio che precede quello in riproduzione (solo per le serie).
  final JellyfinItem? previousEpisode;

  List<MediaStreamInfo> get audioStreams =>
      plan?.mediaSource.audioStreams ?? const [];

  List<MediaStreamInfo> get subtitleStreams =>
      plan?.mediaSource.subtitleStreams ?? const [];

  static const _keep = Object();

  /// `error`, `audioIndex` e `subtitleIndex` accettano `null` esplicito.
  PlayerViewState copyWith({
    PlayerStatus? status,
    JellyfinItem? item,
    PlaybackPlan? plan,
    Object? error = _keep,
    bool? playing,
    bool? buffering,
    double? volume,
    bool? muted,
    Object? audioIndex = _keep,
    Object? subtitleIndex = _keep,
    Duration? subtitleDelay,
    bool? transcodingFallback,
    bool? finished,
    List<MediaSegment>? segments,
    JellyfinItem? nextEpisode,
    JellyfinItem? previousEpisode,
  }) =>
      PlayerViewState(
        status: status ?? this.status,
        item: item ?? this.item,
        plan: plan ?? this.plan,
        error: identical(error, _keep) ? this.error : error,
        playing: playing ?? this.playing,
        buffering: buffering ?? this.buffering,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        audioIndex:
            identical(audioIndex, _keep) ? this.audioIndex : audioIndex as int?,
        subtitleIndex: identical(subtitleIndex, _keep)
            ? this.subtitleIndex
            : subtitleIndex as int?,
        subtitleDelay: subtitleDelay ?? this.subtitleDelay,
        transcodingFallback: transcodingFallback ?? this.transcodingFallback,
        finished: finished ?? this.finished,
        segments: segments ?? this.segments,
        nextEpisode: nextEpisode ?? this.nextEpisode,
        previousEpisode: previousEpisode ?? this.previousEpisode,
      );
}

/// Coordina una riproduzione:
/// - PlaybackInfo e apertura nel motore video;
/// - un solo ripiego automatico sulla transcodifica se il direct play non
///   parte;
/// - tracce audio e sottotitoli, comandi, report a Jellyfin;
/// - alla chiusura, fine della sessione e minutaggio aggiornato in tutta
///   l'app.
class PlayerController extends Notifier<PlayerViewState> {
  PlayerController(this.args);

  final PlayerArgs args;

  late VideoEngine _engine;
  late PlaybackService _service;
  late PlaybackApi _api;
  late LibraryApi _library;
  late String _userId;
  late UserDataOverrides _overrides;
  late UserDataRevision _userDataRevision;
  late PlayerSettings _settings;

  /// Copia dello stato, leggibile anche dopo la dispose del provider.
  PlayerViewState _view = const PlayerViewState();
  ProgressReporter? _reporter;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Sottotitoli esterni già caricati nel motore: indice Jellyfin → id.
  final _externalSubtitles = <int, String>{};

  /// Coda delle operazioni sulle tracce (vedi [_serialized]).
  Future<void> _trackQueue = Future.value();
  Future<void>? _closing;

  /// Alla chiusura l'elemento va segnato come visto (vedi [close]).
  bool _markWatched = false;
  int _generation = 0;
  Duration _resumeAt = Duration.zero;
  bool _forceTranscode = false;

  /// Tracce chieste all'ultima apertura (`null` = predefinite del server),
  /// riusate da [retry].
  int? _requestedAudio;
  int? _requestedSubtitle;

  /// Segmenti ed episodio successivo si caricano una volta sola.
  bool _extrasRequested = false;

  /// Inizio dei segmenti già saltati in automatico.
  final _autoSkipped = <Duration>{};

  final _autoSkips = StreamController<SkipKind>.broadcast();

  /// Salti automatici di intro e riassunti, per la pillola (spec D §13).
  Stream<SkipKind> get autoSkips => _autoSkips.stream;

  /// Pausa, ripresa e salti chiesti dall'utente.
  late PlaybackAuthority _authority = _LocalAuthority(this);

  /// Il server ci ha tolto dal gruppo: da qui il player è da solo.
  bool _leftParty = false;

  /// Il player fa parte di un watch party: parte e si ferma con il gruppo.
  bool get inParty => args.party != null && !_leftParty;

  /// Il server ci ha tolto dal gruppo: salto automatico dell'intro e
  /// partenza dopo un'apertura tornano come da soli.
  void leaveParty() => _leftParty = true;

  /// `null` = di nuovo il player stesso.
  void setAuthority(PlaybackAuthority? authority) =>
      _authority = authority ?? _LocalAuthority(this);

  VideoEngine get engine => _engine;

  bool get _ready => _view.status == PlayerStatus.ready && _closing == null;

  @override
  PlayerViewState build() {
    _engine = ref.read(videoEngineFactoryProvider)();
    _service = ref.read(playbackServiceProvider);
    _api = ref.read(playbackApiProvider);
    _library = ref.read(libraryApiProvider);
    _userId = ref.read(currentUserIdProvider);
    _overrides = ref.read(userDataOverridesProvider.notifier);
    _userDataRevision = ref.read(userDataRevisionProvider.notifier);
    _settings = ref.read(playerSettingsProvider);
    // Ogni player parte dall'ultimo volume scelto, senza muto (issue #3).
    _view = _view.copyWith(volume: ref.read(playerVolumeProvider));
    _listenToEngine();
    ref.onDispose(() => unawaited(close()));
    unawaited(Future.microtask(() => _start(args.start)));
    return _view;
  }

  void _emit(PlayerViewState next) {
    _view = next;
    if (ref.mounted) state = next;
  }

  void _listenToEngine() {
    _subscriptions.addAll([
      _engine.playingStream.listen((playing) {
        if (playing == _view.playing) return;
        _emit(_view.copyWith(playing: playing));
        _reporter?.onEvent();
      }),
      _engine.bufferingStream
          .listen((buffering) => _emit(_view.copyWith(buffering: buffering))),
      _engine.completedStream.listen((completed) {
        if (completed && _view.status == PlayerStatus.ready) {
          _emit(_view.copyWith(finished: true));
        }
      }),
      _engine.errorStream
          .listen((message) => _log.warning('motore: $message')),
      _engine.positionStream.listen(_onPosition),
    ]);
  }

  /// Prepara e apre la riproduzione da [start]. Senza indici si usano le
  /// tracce predefinite del server; `subtitleIndex: -1` = nessun sottotitolo.
  Future<void> _start(
    Duration start, {
    bool forceTranscode = false,
    String? mediaSourceId,
    int? audioIndex,
    int? subtitleIndex,
  }) async {
    final generation = ++_generation;
    bool stale() =>
        !ref.mounted || generation != _generation || _closing != null;
    _resumeAt = start;
    _forceTranscode = forceTranscode;
    _requestedAudio = audioIndex;
    _requestedSubtitle = subtitleIndex;
    final previous = _reporter;
    _reporter = null;
    _emit(_view.copyWith(
        status: PlayerStatus.loading, error: null, finished: false));
    // Una nuova apertura chiude la sessione precedente (cambio di traccia in
    // transcodifica).
    await previous?.stop();
    PlaybackPlan? plan;
    try {
      final item = _view.item ?? await _library.item(_userId, args.itemId);
      if (stale()) return;
      _emit(_view.copyWith(item: item));
      plan = await _service.prepare(
        itemId: args.itemId,
        userId: _userId,
        start: start,
        forceTranscode: forceTranscode,
        mediaSourceId: mediaSourceId ?? _view.plan?.mediaSource.id,
        audioIndex: audioIndex,
        subtitleIndex: subtitleIndex,
        maxBitrate: _settings.quality.bitrate,
      );
      if (stale()) return;
      _externalSubtitles.clear();
      await _engine.open(plan.source);
      if (stale()) return;
      await _engine.setVolume(_view.muted ? 0 : _view.volume);
      if (_settings.subtitleScale != 1.0) {
        await _engine.setSubtitleScale(_settings.subtitleScale);
      }
      if (_view.subtitleDelay != Duration.zero) {
        await _engine.setSubtitleDelay(_view.subtitleDelay);
      }
      final pendingSubtitle = await _applyTracks(plan);
      if (stale()) return;
      // Il file è aperto in pausa: parte solo con le tracce già scelte. Nel
      // watch party parte con il comando del gruppo.
      if (!inParty) {
        await _engine.play();
        if (stale()) return;
      }
      _emit(_view.copyWith(
        status: PlayerStatus.ready,
        plan: plan,
        audioIndex: plan.audioIndex,
        subtitleIndex: plan.subtitleIndex,
        playing: _engine.playing,
      ));
      if (!_extrasRequested) {
        _extrasRequested = true;
        unawaited(_loadExtras(item));
      }
      final reporter =
          _reporter = ProgressReporter(api: _api, snapshot: _report);
      final reporting = reporter.start();
      if (pendingSubtitle != null) {
        final started = plan;
        unawaited(_serialized(
            () => _loadPendingSubtitle(started, pendingSubtitle, stale)));
      }
      await reporting;
    } on EngineOpenException catch (error) {
      if (stale()) return;
      if (plan != null && !plan.isTranscode) {
        _log.info(
            'direct play non riuscito ($error): provo la transcodifica');
        _emit(_view.copyWith(transcodingFallback: true));
        return _start(
          start,
          forceTranscode: true,
          mediaSourceId: plan.mediaSource.id,
          audioIndex: plan.audioIndex,
          subtitleIndex: plan.subtitleIndex ?? -1,
        );
      }
      _fail(error);
    } on Object catch (error) {
      if (stale()) return;
      _fail(error);
    }
  }

  void _fail(Object error) {
    _log.severe('errore: $error');
    _emit(_view.copyWith(status: PlayerStatus.error, error: error));
  }

  /// Seleziona nel motore le tracce del piano, prima della partenza. In
  /// transcodifica l'audio è già quello scelto dal server.
  ///
  /// Un sottotitolo consegnato a parte non viene caricato qui: scaricarlo (o
  /// estrarlo sul server) può richiedere tempo e non deve ritardare la
  /// partenza. Restituisce il suo indice, da caricare dopo con
  /// [_loadPendingSubtitle].
  Future<int?> _applyTracks(PlaybackPlan plan) async {
    final audioIndex = plan.audioIndex;
    if (!plan.isTranscode && audioIndex != null) {
      final stream = plan.mediaSource.stream(audioIndex);
      final track =
          stream == null ? null : engineTrackFor(stream, await _engine.tracks());
      if (track != null) await _engine.selectAudio(track.id);
    }
    final index = plan.subtitleIndex;
    final stream = index == null ? null : plan.mediaSource.stream(index);
    if (stream != null && stream.deliveredExternally) {
      // Intanto nessun sottotitolo (mpv potrebbe sceglierne uno del file).
      await _engine.selectSubtitle(null);
      return index;
    }
    await _showSubtitle(plan, index);
    return null;
  }

  /// Carica il sottotitolo iniziale consegnato a parte, a riproduzione già
  /// partita. Se nel frattempo l'utente ne ha scelto un altro (o il player
  /// è stato riaperto o chiuso) non fa nulla.
  Future<void> _loadPendingSubtitle(
      PlaybackPlan plan, int index, bool Function() stale) async {
    if (stale() || _view.subtitleIndex != index) return;
    final shown = await _showSubtitle(plan, index);
    if (stale() || shown) return;
    _log.warning('sottotitolo $index non caricato');
    if (_view.subtitleIndex == index) {
      _emit(_view.copyWith(subtitleIndex: null));
      _reporter?.onEvent();
    }
  }

  /// Esegue le operazioni sulle tracce una alla volta, nell'ordine in cui
  /// sono chieste: due clic rapidi non si sovrappongono.
  Future<void> _serialized(Future<void> Function() task) {
    final run = _trackQueue.then((_) => task());
    _trackQueue = run.then((_) {}, onError: (Object error) {
      _log.warning('tracce: $error');
    });
    return run;
  }

  /// Mostra il sottotitolo Jellyfin [index] (`null` = nessuno):
  /// - consegnato a parte (esterno o estratto dal server): caricato una
  ///   volta dal suo URL, poi riusato;
  /// - interno in direct play: la traccia del file con lo stesso `ff-index`;
  /// - bruciato in transcodifica: è già nel video, non c'è nulla da fare.
  ///
  /// `false` se il sottotitolo esterno non si è caricato: nel motore resta
  /// quello di prima.
  Future<bool> _showSubtitle(PlaybackPlan plan, int? index) async {
    final stream = index == null ? null : plan.mediaSource.stream(index);
    if (stream == null) {
      await _engine.selectSubtitle(null);
      return true;
    }
    if (stream.deliveredExternally) {
      final known = _externalSubtitles[stream.index];
      if (known != null) {
        await _engine.selectSubtitle(known);
        return true;
      }
      final id = await _engine.addSubtitle(_service.subtitleUrl(stream),
          title: stream.displayTitle, language: stream.language);
      if (id == null) return false;
      _externalSubtitles[stream.index] = id;
      return true;
    }
    if (plan.isTranscode) return true;
    final track = engineTrackFor(stream, await _engine.tracks());
    await _engine.selectSubtitle(track?.id);
    return true;
  }

  PlaybackReport _report() {
    final plan = _view.plan!;
    return PlaybackReport(
      itemId: args.itemId,
      mediaSourceId: plan.mediaSource.id,
      playSessionId: plan.playSessionId,
      position: _engine.position,
      isPaused: !_engine.playing,
      isMuted: _view.muted,
      volume: _view.volume.round(),
      audioStreamIndex: _view.audioIndex,
      subtitleStreamIndex: _view.subtitleIndex,
      playMethod: plan.method,
    );
  }

  /// Dopo un errore ripete l'ultima apertura: stesso punto, stesso metodo
  /// (direct play o transcodifica), stesse tracce chieste (anche quelle di
  /// un cambio di traccia non riuscito; alla prima apertura, le predefinite
  /// del server).
  Future<void> retry() => _start(
        _resumeAt,
        forceTranscode: _forceTranscode,
        audioIndex: _requestedAudio,
        subtitleIndex: _requestedSubtitle,
      );

  Future<void> togglePlay() async {
    if (!_ready) return;
    await (_engine.playing ? _authority.pause() : _authority.play());
  }

  /// Riprende la riproduzione; se è già in corso non cambia nulla (tasti
  /// del pannello media, che possono arrivare su uno stato non aggiornato).
  Future<void> play() async {
    if (!_ready) return;
    await _authority.play();
  }

  /// Mette in pausa; se lo è già non cambia nulla.
  Future<void> pause() async {
    if (!_ready) return;
    await _authority.pause();
  }

  /// Salta a [position], entro i limiti del video.
  Future<void> seekTo(Duration position) async {
    if (!_ready) return;
    final duration = _engine.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (duration > Duration.zero && target > duration) target = duration;
    await _authority.seekTo(target);
  }

  Future<void> seekBy(Duration offset) => seekTo(_engine.position + offset);

  /// 0–100. Toglie anche il muto e diventa il volume dei prossimi player
  /// (issue #3).
  Future<void> setVolume(double volume) async {
    final value = volume.clamp(0.0, 100.0);
    _emit(_view.copyWith(volume: value, muted: false));
    if (ref.mounted) ref.read(playerVolumeProvider.notifier).set(value);
    await _engine.setVolume(value);
  }

  Future<void> changeVolumeBy(double delta) => setVolume(_view.volume + delta);

  Future<void> toggleMute() async {
    final muted = !_view.muted;
    _emit(_view.copyWith(muted: muted));
    await _engine.setVolume(muted ? 0 : _view.volume);
    _reporter?.onEvent();
  }

  /// `true` se [plan] è ancora quello in riproduzione (dopo un'attesa).
  bool _current(PlaybackPlan plan) => _ready && identical(_view.plan, plan);

  Future<void> selectAudio(int index) => _serialized(() async {
        final plan = _view.plan;
        if (plan == null || !_ready || index == _view.audioIndex) return;
        if (plan.isTranscode) {
          // L'audio è scelto dal server nella conversione: va rifatta.
          return _start(_engine.position,
              forceTranscode: true,
              audioIndex: index,
              subtitleIndex: _view.subtitleIndex ?? -1);
        }
        final stream = plan.mediaSource.stream(index);
        final track = stream == null
            ? null
            : engineTrackFor(stream, await _engine.tracks());
        if (track == null || !_current(plan)) return;
        await _engine.selectAudio(track.id);
        if (!_current(plan)) return;
        _emit(_view.copyWith(audioIndex: index));
        _reporter?.onEvent();
      });

  /// `null` = nessun sottotitolo. Se il sottotitolo non si carica resta
  /// quello di prima.
  Future<void> selectSubtitle(int? index) => _serialized(() async {
        final plan = _view.plan;
        if (plan == null || !_ready || index == _view.subtitleIndex) return;
        if (plan.burnsIn(_view.subtitleIndex) || plan.burnsIn(index)) {
          // Sottotitolo bruciato nel video: il server deve rifare la
          // conversione.
          return _start(_engine.position,
              forceTranscode: true,
              audioIndex: _view.audioIndex,
              subtitleIndex: index ?? -1);
        }
        final shown = await _showSubtitle(plan, index);
        if (!_current(plan)) return;
        if (!shown) {
          _log.warning('sottotitolo $index non caricato: resta il '
              'precedente');
          return;
        }
        _emit(_view.copyWith(subtitleIndex: index));
        _reporter?.onEvent();
      });

  /// Positivo = sottotitoli più tardi.
  Future<void> shiftSubtitleDelay(Duration step) async {
    final delay = _view.subtitleDelay + step;
    _emit(_view.copyWith(subtitleDelay: delay));
    await _engine.setSubtitleDelay(delay);
  }

  /// Dimensione dei sottotitoli scelta nel pannello del player: si applica
  /// subito e diventa la preferenza delle Impostazioni (spec D §14).
  Future<void> setSubtitleScale(double scale) async {
    _settings = _settings.copyWith(subtitleScale: scale);
    final settings = ref.read(playerSettingsProvider.notifier);
    final current = ref.read(playerSettingsProvider);
    await Future.wait([
      _engine.setSubtitleScale(scale),
      settings.update(current.copyWith(subtitleScale: scale)),
    ]);
  }

  /// Salta l'intro o il riassunto in corso.
  Future<void> skipCurrentSegment() async {
    final target = skipTargetAt(_view.segments, _engine.position);
    if (target != null) await seekTo(target.end);
  }

  /// Salto automatico di intro e riassunti (se attivo nelle impostazioni):
  /// una volta per segmento, così tornando indietro lo si può rivedere.
  void _onPosition(Duration position) {
    if (!_settings.autoSkipIntro || inParty || !_ready) return;
    final target = skipTargetAt(_view.segments, position);
    if (target == null || !_autoSkipped.add(target.segment.start)) return;
    unawaited(seekTo(target.end));
    _autoSkips.add(target.kind);
  }

  /// Segmenti ed episodio successivo, a riproduzione già partita: se non
  /// arrivano il player funziona lo stesso, senza pulsanti extra.
  Future<void> _loadExtras(JellyfinItem item) async {
    Future<T> safely<T>(
        Future<T> Function() load, T fallback, String what) async {
      try {
        return await load();
      } on Object catch (error) {
        _log.warning('$what non disponibili: $error');
        return fallback;
      }
    }

    final seriesId = item.seriesId;
    final segments = safely(
        () => _api.mediaSegments(item.id), const <MediaSegment>[], 'segmenti');
    final next = item.kind == ItemKind.episode && seriesId != null
        ? safely<JellyfinItem?>(
            () => _library.nextEpisode(_userId, seriesId, item.id),
            null,
            'episodio successivo')
        : Future<JellyfinItem?>.value();
    final previous = item.kind == ItemKind.episode && seriesId != null
        ? safely<JellyfinItem?>(
            () => _library.previousEpisode(_userId, seriesId, item.id),
            null,
            'episodio precedente')
        : Future<JellyfinItem?>.value();
    final loadedSegments = await segments;
    final loadedNext = await next;
    final loadedPrevious = await previous;
    if (_closing != null) return;
    _emit(_view.copyWith(
        segments: loadedSegments,
        nextEpisode: loadedNext,
        previousEpisode: loadedPrevious));
  }

  /// Chiude la riproduzione: segnala la fine a Jellyfin (attesa massima 2 s),
  /// libera il motore e aggiorna il minutaggio locale. Si può chiamare più
  /// volte.
  ///
  /// Con [watched] l'elemento viene anche segnato come visto (si passa
  /// all'episodio successivo durante i titoli di coda: altrimenti resterebbe
  /// "in corso"). Vale anche se la chiusura è già partita, finché non è
  /// arrivato quel punto.
  Future<void> close({bool watched = false}) {
    if (watched) _markWatched = true;
    return _closing ??= _shutdown();
  }

  Future<void> _shutdown() async {
    _generation++;
    unawaited(_autoSkips.close());
    final item = _view.item;
    final position = _engine.position;
    final reporter = _reporter;
    _reporter = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    await reporter?.stop();
    try {
      await _engine.dispose();
    } on Object catch (error) {
      _log.warning('chiusura del motore: $error');
    }
    if (reporter != null && item != null) {
      final watched = _markWatched && await _setPlayed(item);
      await _refreshUserData(item, position, watched: watched);
    }
  }

  /// Segna [item] come visto, dopo il report di fine (che altrimenti
  /// riscriverebbe il minutaggio). Tentativo singolo: `false` se non riesce.
  Future<bool> _setPlayed(JellyfinItem item) async {
    try {
      await _library.setPlayed(_userId, item.id, played: true);
      return true;
    } on Object catch (error) {
      _log.warning('"visto" non salvato: $error');
      return false;
    }
  }

  /// Aggiorna subito minutaggio e percentuale in tutta l'app (Home, schede,
  /// prossimo episodio) senza aspettare il WebSocket: prima una stima
  /// locale, poi i dati del server se raggiungibile.
  Future<void> _refreshUserData(JellyfinItem item, Duration position,
      {bool watched = false}) async {
    try {
      final ticks = durationToTicks(position);
      final runtime = item.runTimeTicks;
      final current = _overrides.effective(item);
      _overrides.apply(
        item.id,
        watched
            ? current.copyWith(played: true)
            : current.copyWith(
                playbackPositionTicks: ticks,
                playedPercentage: runtime == null || runtime == 0
                    ? null
                    : ticks / runtime * 100,
              ),
      );
      try {
        _overrides.apply(item.id, await _api.userData(_userId, item.id));
      } on Object catch (error) {
        _log.info('dati utente non aggiornati dal server: $error');
      }
      _userDataRevision.bump();
    } on Object catch (error) {
      // Es. utente disconnesso nel frattempo: non c'è nulla da aggiornare.
      _log.info('dati utente non aggiornati: $error');
    }
  }
}

final playerControllerProvider = NotifierProvider.autoDispose
    .family<PlayerController, PlayerViewState, PlayerArgs>(
        PlayerController.new);

/// Il player esegue da sé pausa, ripresa e salti.
class _LocalAuthority implements PlaybackAuthority {
  _LocalAuthority(this._controller);

  final PlayerController _controller;

  @override
  Future<void> play() => _controller._engine.play();

  @override
  Future<void> pause() => _controller._engine.pause();

  @override
  Future<void> seekTo(Duration position) async {
    await _controller._engine.seek(position);
    _controller._reporter?.onEvent();
  }
}
