import 'api_exception.dart';

/// Tick di Jellyfin in un microsecondo (10 milioni al secondo).
const _ticksPerMicrosecond = 10;

String? _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? _int(Map<String, dynamic> json, String key) => switch (json[key]) {
      final int value => value,
      final double value => value.round(),
      _ => null,
    };

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? DateTime.tryParse(value) : null;
}

Duration? _ticks(Map<String, dynamic> json, String key) {
  final ticks = _int(json, key);
  return ticks == null
      ? null
      : Duration(microseconds: ticks ~/ _ticksPerMicrosecond);
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// Stringhe di un elenco JSON; una stringa sola con le virgole (forma di
/// alcune versioni di Jellyfin) vale come elenco.
List<String> _strings(Object? value) => switch (value) {
      final List<dynamic> list => [
          for (final item in list)
            if (item is String && item.isNotEmpty) item,
        ],
      final String text => [
          for (final item in text.split(','))
            if (item.trim().isNotEmpty) item.trim(),
        ],
      _ => const [],
    };

/// Un id di Jellyfin di soli zeri, con o senza trattini: nessuno (per
/// esempio l'utente delle voci di sistema o delle chiavi API).
bool isEmptyJellyfinId(String id) => id.replaceAll(RegExp('[-0]'), '').isEmpty;

/// Un elenco JSON di oggetti. Le voci che [parse] scarta (`null`) e quelle
/// che non sono oggetti si saltano; un corpo che non è un elenco è una
/// risposta inattesa.
List<T> _list<T>(Object? data, T? Function(Map<String, dynamic> json) parse) {
  if (data is! List) throw const ServerErrorException(null);
  return [
    for (final raw in data)
      if (_map(raw) case final json?)
        ?parse(json),
  ];
}

/// Metodo di riproduzione dichiarato dal client (`PlayState.PlayMethod`).
enum PlayMethod { directPlay, directStream, transcode, unknown }

PlayMethod _playMethod(Object? raw) => switch (raw) {
      'DirectPlay' => PlayMethod.directPlay,
      'DirectStream' => PlayMethod.directStream,
      'Transcode' => PlayMethod.transcode,
      _ => PlayMethod.unknown,
    };

enum NowPlayingKind { movie, episode, other }

/// Cosa sta guardando una sessione (`NowPlayingItem`, spec J §8.2).
class NowPlaying {
  const NowPlaying({
    required this.itemId,
    required this.name,
    this.kind = NowPlayingKind.other,
    this.year,
    this.seriesName,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.runtime,
  });

  /// `null` senza `Id` o senza nome: non c'è niente da mostrare.
  static NowPlaying? fromJson(Map<String, dynamic> json) {
    final id = _string(json, 'Id');
    final name = _string(json, 'Name');
    if (id == null || name == null) return null;
    return NowPlaying(
      itemId: id,
      name: name,
      kind: switch (json['Type']) {
        'Movie' => NowPlayingKind.movie,
        'Episode' => NowPlayingKind.episode,
        _ => NowPlayingKind.other,
      },
      year: _int(json, 'ProductionYear'),
      seriesName: _string(json, 'SeriesName'),
      seriesId: _string(json, 'SeriesId'),
      seasonNumber: _int(json, 'ParentIndexNumber'),
      episodeNumber: _int(json, 'IndexNumber'),
      runtime: _ticks(json, 'RunTimeTicks'),
    );
  }

  final String itemId;
  final String name;
  final NowPlayingKind kind;
  final int? year;
  final String? seriesName;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  final Duration? runtime;

  /// L'elemento di cui mostrare la locandina: la serie per gli episodi.
  String get imageItemId =>
      kind == NowPlayingKind.episode ? (seriesId ?? itemId) : itemId;
}

/// La transcodifica in corso di una sessione (`TranscodingInfo`).
class TranscodeInfo {
  const TranscodeInfo({
    this.videoCodec,
    this.audioCodec,
    this.isVideoDirect = false,
    this.isAudioDirect = false,
    this.bitrate,
    this.width,
    this.height,
    this.hardwareAcceleration,
    this.reasons = const [],
  });

  factory TranscodeInfo.fromJson(Map<String, dynamic> json) => TranscodeInfo(
        videoCodec: _string(json, 'VideoCodec'),
        audioCodec: _string(json, 'AudioCodec'),
        isVideoDirect: json['IsVideoDirect'] == true,
        isAudioDirect: json['IsAudioDirect'] == true,
        bitrate: _int(json, 'Bitrate'),
        width: _int(json, 'Width'),
        height: _int(json, 'Height'),
        hardwareAcceleration: _string(json, 'HardwareAccelerationType'),
        reasons: _strings(json['TranscodeReasons']),
      );

  final String? videoCodec;
  final String? audioCodec;
  final bool isVideoDirect;
  final bool isAudioDirect;

  /// In bit al secondo.
  final int? bitrate;
  final int? width;
  final int? height;

  /// `HardwareAccelerationType`: "none", "qsv", "nvenc", "vaapi"…
  final String? hardwareAcceleration;

  /// `TranscodeReasons` come le scrive Jellyfin ("VideoCodecNotSupported"…).
  final List<String> reasons;
}

/// Una sessione di un utente (`SessionInfoDto`, spec J §8.2).
class SessionEntry {
  const SessionEntry({
    required this.id,
    required this.userId,
    required this.userName,
    this.client,
    this.deviceName,
    this.lastActivity,
    this.nowPlaying,
    this.position = Duration.zero,
    this.isPaused = false,
    this.playMethod = PlayMethod.unknown,
    this.transcode,
  });

  /// `null` senza `Id` o senza un utente vero: le sessioni delle chiavi API
  /// (Seerr, jfa-go…) non si mostrano (spec J §8.1).
  static SessionEntry? fromJson(Map<String, dynamic> json) {
    final id = _string(json, 'Id');
    final userId = _string(json, 'UserId');
    if (id == null || userId == null || isEmptyJellyfinId(userId)) return null;
    final playState = _map(json['PlayState']) ?? const <String, dynamic>{};
    final nowPlaying = _map(json['NowPlayingItem']);
    final transcode = _map(json['TranscodingInfo']);
    return SessionEntry(
      id: id,
      userId: userId,
      userName: _string(json, 'UserName') ?? '',
      client: _string(json, 'Client'),
      deviceName: _string(json, 'DeviceName'),
      lastActivity: _date(json, 'LastActivityDate'),
      nowPlaying: nowPlaying == null ? null : NowPlaying.fromJson(nowPlaying),
      position: _ticks(playState, 'PositionTicks') ?? Duration.zero,
      isPaused: playState['IsPaused'] == true,
      playMethod: _playMethod(playState['PlayMethod']),
      transcode: transcode == null ? null : TranscodeInfo.fromJson(transcode),
    );
  }

  final String id;
  final String userId;
  final String userName;
  final String? client;
  final String? deviceName;
  final DateTime? lastActivity;

  /// `null`: collegato senza riprodurre.
  final NowPlaying? nowPlaying;
  final Duration position;
  final bool isPaused;
  final PlayMethod playMethod;
  final TranscodeInfo? transcode;
}

List<SessionEntry> parseSessions(Object? data) =>
    _list(data, SessionEntry.fromJson);

/// Stato di un watch party (`GroupStateType`).
enum PartyState { idle, waiting, paused, playing, unknown }

/// Un watch party in corso (`GroupInfoDto`).
class PartyGroup {
  const PartyGroup({
    required this.id,
    required this.name,
    this.state = PartyState.unknown,
    this.participants = const [],
  });

  static PartyGroup? fromJson(Map<String, dynamic> json) {
    final id = _string(json, 'GroupId');
    if (id == null) return null;
    return PartyGroup(
      id: id,
      name: _string(json, 'GroupName') ?? '',
      state: switch (json['State']) {
        'Idle' => PartyState.idle,
        'Waiting' => PartyState.waiting,
        'Paused' => PartyState.paused,
        'Playing' => PartyState.playing,
        _ => PartyState.unknown,
      },
      participants: _strings(json['Participants']),
    );
  }

  final String id;
  final String name;
  final PartyState state;

  /// I nomi degli utenti nel gruppo.
  final List<String> participants;
}

List<PartyGroup> parsePartyGroups(Object? data) =>
    _list(data, PartyGroup.fromJson);

/// Il server, per la striscia in cima alla pagina (`/System/Info`).
class ServerInfo {
  const ServerInfo({
    required this.name,
    required this.version,
    this.operatingSystem,
    this.hasPendingRestart = false,
  });

  /// Senza `Version` la risposta non è quella attesa.
  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    final version = _string(json, 'Version');
    if (version == null) throw const ServerErrorException(null);
    return ServerInfo(
      name: _string(json, 'ServerName') ?? '',
      version: version,
      operatingSystem: _string(json, 'OperatingSystemDisplayName'),
      hasPendingRestart: json['HasPendingRestart'] == true,
    );
  }

  final String name;
  final String version;

  /// `null` se Jellyfin non lo dice (sul server è vuoto).
  final String? operatingSystem;

  /// Un'installazione o un aggiornamento aspettano un riavvio.
  final bool hasPendingRestart;
}
