import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/library_api.dart';
import '../../core/jellyfin/playback_api.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../core/video/video_engine.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import 'playback_service.dart';
import 'player_providers.dart';
import 'progress_reporter.dart';
import 'track_mapping.dart';

/// Elemento da riprodurre e posizione di partenza (chiave del provider).
typedef PlayerArgs = ({String itemId, Duration start});

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

  /// Copia dello stato, leggibile anche dopo la dispose del provider.
  PlayerViewState _view = const PlayerViewState();
  ProgressReporter? _reporter;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Sottotitoli esterni già caricati nel motore: indice Jellyfin → id.
  final _externalSubtitles = <int, String>{};
  Future<void>? _closing;
  int _generation = 0;
  Duration _resumeAt = Duration.zero;
  bool _forceTranscode = false;

  VideoEngine get engine => _engine;

  @override
  PlayerViewState build() {
    _engine = ref.read(videoEngineFactoryProvider)();
    _service = ref.read(playbackServiceProvider);
    _api = ref.read(playbackApiProvider);
    _library = ref.read(libraryApiProvider);
    _userId = ref.read(currentUserIdProvider);
    _overrides = ref.read(userDataOverridesProvider.notifier);
    _userDataRevision = ref.read(userDataRevisionProvider.notifier);
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
          .listen((message) => debugPrint('[player] motore: $message')),
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
      );
      if (stale()) return;
      _externalSubtitles.clear();
      await _engine.open(plan.source);
      if (stale()) return;
      await _engine.setVolume(_view.muted ? 0 : _view.volume);
      if (_view.subtitleDelay != Duration.zero) {
        await _engine.setSubtitleDelay(_view.subtitleDelay);
      }
      await _applyTracks(plan);
      if (stale()) return;
      _emit(_view.copyWith(
        status: PlayerStatus.ready,
        plan: plan,
        audioIndex: plan.audioIndex,
        subtitleIndex: plan.subtitleIndex,
        playing: _engine.playing,
      ));
      final reporter =
          _reporter = ProgressReporter(api: _api, snapshot: _report);
      await reporter.start();
    } on EngineOpenException catch (error) {
      if (stale()) return;
      if (plan != null && !plan.isTranscode) {
        debugPrint(
            '[player] direct play non riuscito ($error): provo la transcodifica');
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
    debugPrint('[player] errore: $error');
    _emit(_view.copyWith(status: PlayerStatus.error, error: error));
  }

  /// Seleziona nel motore le tracce del piano. In transcodifica l'audio è già
  /// quello scelto dal server.
  Future<void> _applyTracks(PlaybackPlan plan) async {
    final audioIndex = plan.audioIndex;
    if (!plan.isTranscode && audioIndex != null) {
      final stream = plan.mediaSource.stream(audioIndex);
      final track =
          stream == null ? null : engineTrackFor(stream, await _engine.tracks());
      if (track != null) await _engine.selectAudio(track.id);
    }
    await _showSubtitle(plan, plan.subtitleIndex);
  }

  /// Mostra il sottotitolo Jellyfin [index] (`null` = nessuno):
  /// - consegnato a parte (esterno o estratto dal server): caricato una
  ///   volta dal suo URL, poi riusato;
  /// - interno in direct play: la traccia del file con lo stesso `ff-index`;
  /// - bruciato in transcodifica: è già nel video, non c'è nulla da fare.
  Future<void> _showSubtitle(PlaybackPlan plan, int? index) async {
    final stream = index == null ? null : plan.mediaSource.stream(index);
    if (stream == null) return _engine.selectSubtitle(null);
    if (stream.deliveredExternally) {
      final known = _externalSubtitles[stream.index];
      if (known != null) return _engine.selectSubtitle(known);
      final id = await _engine.addSubtitle(_service.subtitleUrl(stream),
          title: stream.displayTitle, language: stream.language);
      if (id != null) _externalSubtitles[stream.index] = id;
      return;
    }
    if (plan.isTranscode) return;
    final track = engineTrackFor(stream, await _engine.tracks());
    await _engine.selectSubtitle(track?.id);
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

  /// Dopo un errore: stesso punto, stesso metodo (direct play o
  /// transcodifica), stesse tracce se erano già state scelte.
  Future<void> retry() {
    final hadPlan = _view.plan != null;
    return _start(
      _resumeAt,
      forceTranscode: _forceTranscode,
      audioIndex: hadPlan ? _view.audioIndex : null,
      subtitleIndex: hadPlan ? (_view.subtitleIndex ?? -1) : null,
    );
  }

  /// Chiude la riproduzione: segnala la fine a Jellyfin (attesa massima 2 s),
  /// libera il motore e aggiorna il minutaggio locale. Si può chiamare più
  /// volte.
  Future<void> close() => _closing ??= _shutdown();

  Future<void> _shutdown() async {
    _generation++;
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
      debugPrint('[player] chiusura del motore: $error');
    }
    if (reporter != null && item != null) {
      await _refreshUserData(item, position);
    }
  }

  /// Aggiorna subito minutaggio e percentuale in tutta l'app (Home, schede,
  /// prossimo episodio) senza aspettare il WebSocket: prima una stima
  /// locale, poi i dati del server se raggiungibile.
  Future<void> _refreshUserData(JellyfinItem item, Duration position) async {
    try {
      final ticks = durationToTicks(position);
      final runtime = item.runTimeTicks;
      _overrides.apply(
        item.id,
        _overrides.effective(item).copyWith(
              playbackPositionTicks: ticks,
              playedPercentage: runtime == null || runtime == 0
                  ? null
                  : ticks / runtime * 100,
            ),
      );
      try {
        _overrides.apply(item.id, await _api.userData(_userId, item.id));
      } on Object catch (error) {
        debugPrint('[player] dati utente non aggiornati dal server: $error');
      }
      _userDataRevision.bump();
    } on Object catch (error) {
      // Es. utente disconnesso nel frattempo: non c'è nulla da aggiornare.
      debugPrint('[player] dati utente non aggiornati: $error');
    }
  }
}

final playerControllerProvider = NotifierProvider.autoDispose
    .family<PlayerController, PlayerViewState, PlayerArgs>(
        PlayerController.new);
