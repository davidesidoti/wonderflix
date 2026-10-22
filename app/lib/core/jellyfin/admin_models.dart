import 'api_exception.dart';
import 'json_fields.dart';

export 'json_fields.dart' show isEmptyJellyfinId;

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
    final id = jsonString(json, 'Id');
    final name = jsonString(json, 'Name');
    if (id == null || name == null) return null;
    return NowPlaying(
      itemId: id,
      name: name,
      kind: switch (json['Type']) {
        'Movie' => NowPlayingKind.movie,
        'Episode' => NowPlayingKind.episode,
        _ => NowPlayingKind.other,
      },
      year: jsonInt(json, 'ProductionYear'),
      seriesName: jsonString(json, 'SeriesName'),
      seriesId: jsonString(json, 'SeriesId'),
      seasonNumber: jsonInt(json, 'ParentIndexNumber'),
      episodeNumber: jsonInt(json, 'IndexNumber'),
      runtime: jsonTicks(json, 'RunTimeTicks'),
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
        videoCodec: jsonString(json, 'VideoCodec'),
        audioCodec: jsonString(json, 'AudioCodec'),
        isVideoDirect: json['IsVideoDirect'] == true,
        isAudioDirect: json['IsAudioDirect'] == true,
        bitrate: jsonInt(json, 'Bitrate'),
        width: jsonInt(json, 'Width'),
        height: jsonInt(json, 'Height'),
        hardwareAcceleration: jsonString(json, 'HardwareAccelerationType'),
        reasons: jsonStrings(json['TranscodeReasons']),
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
    this.userImageTag,
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
    final id = jsonString(json, 'Id');
    final userId = jsonString(json, 'UserId');
    if (id == null || userId == null || isEmptyJellyfinId(userId)) return null;
    final playState = jsonMap(json['PlayState']) ?? const <String, dynamic>{};
    final nowPlaying = jsonMap(json['NowPlayingItem']);
    final transcode = jsonMap(json['TranscodingInfo']);
    return SessionEntry(
      id: id,
      userId: userId,
      userName: jsonString(json, 'UserName') ?? '',
      userImageTag: jsonString(json, 'UserPrimaryImageTag'),
      client: jsonString(json, 'Client'),
      deviceName: jsonString(json, 'DeviceName'),
      lastActivity: jsonDate(json, 'LastActivityDate'),
      nowPlaying: nowPlaying == null ? null : NowPlaying.fromJson(nowPlaying),
      position: jsonTicks(playState, 'PositionTicks') ?? Duration.zero,
      isPaused: playState['IsPaused'] == true,
      playMethod: _playMethod(playState['PlayMethod']),
      transcode: transcode == null ? null : TranscodeInfo.fromJson(transcode),
    );
  }

  final String id;
  final String userId;
  final String userName;

  /// Tag dell'immagine dell'utente (spec K §10.5); `null` senza immagine.
  final String? userImageTag;
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
    jsonList(data, SessionEntry.fromJson);

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
    final id = jsonString(json, 'GroupId');
    if (id == null) return null;
    return PartyGroup(
      id: id,
      name: jsonString(json, 'GroupName') ?? '',
      state: switch (json['State']) {
        'Idle' => PartyState.idle,
        'Waiting' => PartyState.waiting,
        'Paused' => PartyState.paused,
        'Playing' => PartyState.playing,
        _ => PartyState.unknown,
      },
      participants: jsonStrings(json['Participants']),
    );
  }

  final String id;
  final String name;
  final PartyState state;

  /// I nomi degli utenti nel gruppo.
  final List<String> participants;
}

List<PartyGroup> parsePartyGroups(Object? data) =>
    jsonList(data, PartyGroup.fromJson);

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
    final version = jsonString(json, 'Version');
    if (version == null) throw const ServerErrorException(null);
    return ServerInfo(
      name: jsonString(json, 'ServerName') ?? '',
      version: version,
      operatingSystem: jsonString(json, 'OperatingSystemDisplayName'),
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
