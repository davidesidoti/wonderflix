import 'dart:async';
import 'dart:convert';
import 'dart:io' as io show pid;

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';

import '../../core/discord/discord_ipc.dart';
import '../../core/media_session/media_session.dart';
import 'discord_activity.dart';
import 'discord_settings.dart';

final _log = Logger('discord');

/// Attività "Watching" su Discord (Rich Presence). Il player la aggiorna
/// come il pannello media di sistema, attraverso [MediaSession].
///
/// - Si collega a Discord solo quando c'è qualcosa da mostrare; se Discord
///   non è aperto (o si chiude) riprova ogni [retryInterval].
/// - Invia al massimo un aggiornamento ogni [minSendInterval] (limite di
///   Discord: 5 ogni 20 s), sempre con lo stato più recente.
/// - Non invia di nuovo un'attività uguale all'ultima; l'inizio del video
///   (adesso meno la posizione) si considera uguale entro [startTolerance].
class DiscordPresence implements MediaSession {
  DiscordPresence({
    required DiscordIpcClient Function() createClient,
    required DiscordSettings Function() settings,
    required DiscordLabels Function() labels,
    required Uri? buttonUrl,
    int? processId,
    this.retryInterval = const Duration(seconds: 30),
    this.minSendInterval = const Duration(seconds: 5),
  })  : _createClient = createClient,
        _settings = settings,
        _labels = labels,
        _buttonUrl = buttonUrl,
        _pid = processId ?? io.pid;

  final DiscordIpcClient Function() _createClient;
  final DiscordSettings Function() _settings;
  final DiscordLabels Function() _labels;
  final Uri? _buttonUrl;
  final int _pid;
  final Duration retryInterval;
  final Duration minSendInterval;

  static const startTolerance = Duration(seconds: 2);

  DiscordIpcClient? _client;
  bool _connecting = false;
  bool _disposed = false;

  /// Discord ha rifiutato l'Application ID: niente più tentativi fino al
  /// riavvio dell'app.
  bool _rejected = false;
  Timer? _retryTimer;
  Timer? _sendTimer;
  DateTime? _lastSendAt;

  /// Ultima attività inviata, in JSON (`null` = nessuna) e il suo inizio.
  String? _sentJson;
  DateTime? _sentStart;

  // Cosa si sta guardando.
  bool _active = false;
  String _title = '';
  String? _subtitle;
  String? _posterUrl;
  bool _playing = true;
  DateTime? _start;
  Duration? _duration;

  /// Ultima posizione ricevuta: in pausa non avanza, alla ripresa l'inizio
  /// si ricalcola da qui.
  Duration? _position;

  /// Persone nel watch party; `null` = fuori da un gruppo.
  int? _partySize;

  @override
  bool get handlesMediaKeys => false;

  @override
  Stream<MediaButton> get buttons => const Stream.empty();

  @override
  Future<void> setMetadata(
      {required String title, String? subtitle, String? thumbnailUrl}) async {
    _active = true;
    _title = title;
    _subtitle = subtitle;
    _posterUrl = thumbnailUrl;
    // Nuovo video: parte in riproduzione, i tempi arrivano con la timeline.
    _playing = true;
    _start = null;
    _duration = null;
    _position = null;
    _sync();
  }

  @override
  Future<void> setPlaying(bool playing) async {
    _playing = playing;
    final position = _position;
    if (playing && position != null) _start = clock.now().subtract(position);
    _sync();
  }

  @override
  Future<void> setTimeline(
      {required Duration position, required Duration duration}) async {
    _start = clock.now().subtract(position);
    _position = position;
    _duration = duration;
    _sync();
  }

  @override
  Future<void> setNextEnabled(bool enabled) async {}

  @override
  Future<void> setPreviousEnabled(bool enabled) async {}

  @override
  Future<void> setParty(int? members) async {
    _partySize = members;
    _sync();
  }

  @override
  Future<void> clear() async {
    _active = false;
    _start = null;
    _duration = null;
    _position = null;
    _partySize = null;
    _sync();
  }

  /// Impostazioni o lingua cambiate.
  void refresh() => _sync();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _sendTimer?.cancel();
    final client = _client;
    _client = null;
    if (client != null && client.connected) {
      client.setActivity(null, pid: _pid);
      client.close();
    }
  }

  ({Map<String, Object?> activity, DateTime? start})? _desired() {
    if (!_active || !_settings().enabled) return null;
    var start = _playing ? _start : null;
    final sentStart = _sentStart;
    if (start != null &&
        sentStart != null &&
        start.difference(sentStart).abs() <= startTolerance) {
      start = sentStart;
    }
    return (
      activity: buildDiscordActivity(
        title: _title,
        subtitle: _subtitle,
        posterUrl: _posterUrl,
        playing: _playing,
        start: start,
        duration: _duration,
        settings: _settings(),
        labels: _labels(),
        buttonUrl: _buttonUrl,
        partySize: _partySize,
      ),
      start: start,
    );
  }

  void _sync() {
    if (_disposed) return;
    final desired = _desired();
    final json = desired == null ? null : jsonEncode(desired.activity);
    // La connessione caduta si vede solo leggendo: si controlla a ogni
    // aggiornamento, anche quando l'attività non cambia.
    if (_client != null && !_client!.poll()) _lost();
    _checkCommandError();
    if (json == _sentJson) return;
    final client = _client;
    if (client == null || !client.connected) {
      if (desired != null) unawaited(_connect());
      return;
    }
    final last = _lastSendAt;
    if (last != null) {
      final wait = minSendInterval - clock.now().difference(last);
      if (wait > Duration.zero) {
        _sendTimer ??= Timer(wait, () {
          _sendTimer = null;
          _sync();
        });
        return;
      }
    }
    _lastSendAt = clock.now();
    if (client.setActivity(desired?.activity, pid: _pid)) {
      _sentJson = json;
      _sentStart = desired?.start;
      _checkCommandError();
    } else {
      _lost();
    }
  }

  /// Discord ha rifiutato un'attività: si rimanda lo stato al prossimo
  /// aggiornamento (mai subito, per non entrare in un ciclo).
  void _checkCommandError() {
    if (_client?.takeCommandError() ?? false) {
      _sentJson = null;
      _sentStart = null;
    }
  }

  void _lost() {
    _log.info('connessione a Discord interrotta');
    _client = null;
    _sentJson = null;
    _sentStart = null;
    _scheduleRetry();
  }

  Future<void> _connect() async {
    if (_rejected || _connecting || _retryTimer != null) return;
    _connecting = true;
    DiscordIpcClient? created;
    final bool ok;
    try {
      created = _createClient();
      ok = await created.connect();
    } on Object catch (e, stack) {
      created?.close();
      _log.warning('collegamento a Discord non riuscito', e, stack);
      if (!_disposed) _scheduleRetry();
      return;
    } finally {
      _connecting = false;
    }
    final client = created;
    if (_disposed) {
      client.close();
      return;
    }
    if (!ok && client.rejected) {
      _log.warning('Discord ha rifiutato l\'Application ID: Rich Presence '
          'disattivata fino al riavvio');
      _rejected = true;
      client.close();
      return;
    }
    if (!ok) {
      _log.fine('Discord non raggiungibile: nuovo tentativo tra '
          '${retryInterval.inSeconds} s');
      client.close();
      _scheduleRetry();
      return;
    }
    _log.info('collegato a Discord');
    _client = client;
    // Connessione nuova: Discord non ha ancora nessuna nostra attività.
    _sentJson = null;
    _sentStart = null;
    _sync();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(retryInterval, () {
      _retryTimer = null;
      _sync();
    });
  }
}
