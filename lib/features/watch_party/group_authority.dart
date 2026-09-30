import 'dart:async';

import 'package:logging/logging.dart';

import '../../core/syncplay/syncplay_api.dart';
import '../../core/video/video_engine.dart';
import '../player/playback_authority.dart';
import 'party_notices.dart';

final _log = Logger('watchparty');

/// Nel watch party pausa, ripresa e salti dell'utente diventano richieste al
/// gruppo (spec B §6.1). Il motore si muove con i comandi del gruppo, tranne
/// la pausa e il salto, che si vedono subito. I salti ravvicinati (tasto
/// tenuto premuto) diventano un solo `Seek`, con l'ultima posizione.
class GroupAuthority implements PlaybackAuthority {
  GroupAuthority({
    required SyncPlayApi api,
    required VideoEngine engine,
    PartyActionCallback? onAction,
  })  : _api = api,
        _engine = engine,
        _onAction = onAction;

  /// Il `Seek` parte quando i salti si fermano da questo tempo.
  static const seekDebounce = Duration(milliseconds: 400);

  final SyncPlayApi _api;
  final VideoEngine _engine;

  /// Annuncia le azioni dell'utente (avviso "Hai…" subito, spec B §5.7).
  final PartyActionCallback? _onAction;

  Timer? _seekTimer;
  Duration? _pendingSeek;

  /// Il player si chiude o esce dal gruppo: il salto in sospeso non parte.
  void dispose() {
    _seekTimer?.cancel();
    _seekTimer = null;
    _pendingSeek = null;
  }

  /// Con il gruppo in attesa fa ripartire tutti senza aspettare.
  @override
  Future<void> play() async {
    // Il salto in sospeso parte prima, così il gruppo riparte da lì.
    await _flushSeek();
    _onAction?.call(PartyNoticeKind.resumed);
    await _send('ripresa', _api.unpause);
  }

  @override
  Future<void> pause() async {
    await _engine.pause();
    _onAction?.call(PartyNoticeKind.paused);
    await _send('pausa', _api.pause);
  }

  @override
  Future<void> seekTo(Duration position) async {
    _pendingSeek = position;
    _seekTimer?.cancel();
    _seekTimer = Timer(seekDebounce, () => unawaited(_flushSeek()));
    await _engine.pause();
    await _engine.seek(position);
  }

  Future<void> _flushSeek() async {
    _seekTimer?.cancel();
    _seekTimer = null;
    final position = _pendingSeek;
    _pendingSeek = null;
    if (position == null) return;
    _onAction?.call(PartyNoticeKind.seeked, position: position);
    await _send('salto', () => _api.seek(position));
  }

  Future<void> _send(String what, Future<void> Function() request) async {
    try {
      await request();
    } on Object catch (error) {
      _log.warning('$what non inviata al gruppo: $error');
    }
  }
}
