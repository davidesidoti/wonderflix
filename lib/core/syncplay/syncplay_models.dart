import 'package:logging/logging.dart';

import '../jellyfin/item_models.dart';
import 'party_mode.dart';

export 'party_mode.dart';

final _log = Logger('watchparty');

/// Stato di un gruppo SyncPlay (`GroupStateType`).
enum GroupState { idle, waiting, paused, playing }

GroupState? parseGroupState(Object? value) => switch (value) {
      'Idle' => GroupState.idle,
      'Waiting' => GroupState.waiting,
      'Paused' => GroupState.paused,
      'Playing' => GroupState.playing,
      _ => null,
    };

/// Date del server (UTC, fino a 7 decimali: si tronca ai microsecondi).
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

/// Un gruppo come lo descrive il server (`GroupInfoDto`).
class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    required this.state,
    required this.participants,
    required this.lastUpdatedAt,
    this.mode,
  });

  /// Lancia se manca `GroupId`.
  factory GroupInfo.fromJson(Map<String, dynamic> json) => GroupInfo(
        id: json['GroupId'] as String,
        name: json['GroupName'] as String? ?? '',
        state: parseGroupState(json['State']) ?? GroupState.idle,
        participants: (json['Participants'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        lastUpdatedAt: _date(json['LastUpdatedAt']) ?? DateTime.utc(1970),
      );

  final String id;
  final String name;
  final GroupState state;

  /// Nomi utente dei membri (il server non dà altro).
  final List<String> participants;

  /// Quando il server ha creato questa descrizione.
  final DateTime lastUpdatedAt;

  /// Modalità del party, se l'elenco viene dal plugin (spec F §9.6);
  /// `null` dall'elenco di Jellyfin.
  final PartyMode? mode;

  GroupInfo copyWith({GroupState? state, List<String>? participants}) =>
      GroupInfo(
        id: id,
        name: name,
        state: state ?? this.state,
        participants: participants ?? this.participants,
        lastUpdatedAt: lastUpdatedAt,
        mode: mode,
      );
}

enum SyncPlayCommandType { unpause, pause, stop, seek }

/// Comando del gruppo (`SendCommand`): cosa fare, da quale posizione e a
/// quale istante (orario del server).
class SyncPlayCommand {
  const SyncPlayCommand({
    required this.groupId,
    required this.playlistItemId,
    required this.when,
    required this.position,
    required this.type,
    required this.emittedAt,
  });

  /// `null` se il comando è sconosciuto o mancano gli istanti.
  static SyncPlayCommand? fromJson(Map<String, dynamic> json) {
    final type = switch (json['Command']) {
      'Unpause' => SyncPlayCommandType.unpause,
      'Pause' => SyncPlayCommandType.pause,
      'Stop' => SyncPlayCommandType.stop,
      'Seek' => SyncPlayCommandType.seek,
      _ => null,
    };
    final when = _date(json['When']);
    final emittedAt = _date(json['EmittedAt']);
    if (type == null || when == null || emittedAt == null) return null;
    return SyncPlayCommand(
      groupId: json['GroupId'] as String? ?? '',
      playlistItemId: json['PlaylistItemId'] as String? ?? '',
      when: when,
      position: ticksToDuration(_int(json['PositionTicks']) ?? 0),
      type: type,
      emittedAt: emittedAt,
    );
  }

  final String groupId;
  final String playlistItemId;

  /// Istante (orario del server) in cui eseguire il comando.
  final DateTime when;
  final Duration position;
  final SyncPlayCommandType type;
  final DateTime emittedAt;

  /// Stesso comando ricevuto di nuovo (il server a volte lo ripete).
  bool sameAs(SyncPlayCommand other) =>
      type == other.type &&
      when == other.when &&
      position == other.position &&
      playlistItemId == other.playlistItemId;

  @override
  String toString() => 'SyncPlayCommand(${type.name}, $position, $when, '
      '$playlistItemId)';
}

/// Elemento della coda del gruppo.
class PlayQueueEntry {
  const PlayQueueEntry({required this.itemId, required this.playlistItemId});

  final String itemId;

  /// Id dell'elemento *nella coda* (lo stesso film due volte ha due id).
  final String playlistItemId;
}

/// Coda del gruppo (`PlayQueueUpdate`).
class PlayQueue {
  const PlayQueue({
    required this.reason,
    required this.lastUpdate,
    required this.entries,
    required this.playingIndex,
    required this.startPosition,
    required this.isPlaying,
    this.shuffled = false,
  });

  factory PlayQueue.fromJson(Map<String, dynamic> json) => PlayQueue(
        reason: json['Reason'] as String? ?? '',
        lastUpdate: _date(json['LastUpdate']) ?? DateTime.utc(1970),
        entries: [
          for (final entry in (json['Playlist'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
            if (entry['ItemId'] is String && entry['PlaylistItemId'] is String)
              PlayQueueEntry(
                itemId: entry['ItemId'] as String,
                playlistItemId: entry['PlaylistItemId'] as String,
              ),
        ],
        playingIndex: _int(json['PlayingItemIndex']) ?? -1,
        startPosition: ticksToDuration(_int(json['StartPositionTicks']) ?? 0),
        isPlaying: json['IsPlaying'] as bool? ?? false,
        shuffled: json['ShuffleMode'] == 'Shuffle',
      );

  /// Cosa ha cambiato la coda (`NewPlaylist`, `NextItem`…).
  final String reason;

  /// Ultima modifica della coda (orario del server).
  final DateTime lastUpdate;
  final List<PlayQueueEntry> entries;
  final int playingIndex;

  /// Posizione del gruppo quando il server ha mandato la coda.
  final Duration startPosition;
  final bool isPlaying;

  /// Ordine casuale attivo (`ShuffleMode`): [entries] è nell'ordine
  /// mescolato (spec H §3).
  final bool shuffled;

  PlayQueueEntry? get playing =>
      playingIndex >= 0 && playingIndex < entries.length
          ? entries[playingIndex]
          : null;
}

/// Aggiornamento del gruppo (`SyncPlayGroupUpdate`).
sealed class GroupUpdate {
  const GroupUpdate(this.groupId);

  final String groupId;
}

/// Siamo entrati (o abbiamo creato il gruppo).
final class GroupJoined extends GroupUpdate {
  const GroupJoined(super.groupId, this.info);

  final GroupInfo info;
}

final class UserJoined extends GroupUpdate {
  const UserJoined(super.groupId, this.userName);

  final String userName;
}

final class UserLeft extends GroupUpdate {
  const UserLeft(super.groupId, this.userName);

  final String userName;
}

final class GroupLeft extends GroupUpdate {
  const GroupLeft(super.groupId);
}

final class NotInGroup extends GroupUpdate {
  const NotInGroup(super.groupId);
}

final class GroupDoesNotExist extends GroupUpdate {
  const GroupDoesNotExist(super.groupId);
}

final class LibraryAccessDenied extends GroupUpdate {
  const LibraryAccessDenied(super.groupId);
}

/// Il gruppo è passato a [state]; [reason] è la richiesta che l'ha causato
/// (`Pause`, `Seek`, `Buffer`…).
final class GroupStateUpdate extends GroupUpdate {
  const GroupStateUpdate(super.groupId, this.state, this.reason);

  final GroupState state;
  final String? reason;
}

final class PlayQueueUpdate extends GroupUpdate {
  const PlayQueueUpdate(super.groupId, this.queue);

  final PlayQueue queue;
}

/// Il `Data` di un messaggio `SyncPlayGroupUpdate`; `null` se non valido o
/// di un tipo che non usiamo.
GroupUpdate? parseGroupUpdate(Object? data) {
  if (data is! Map<String, dynamic>) return null;
  final groupId = data['GroupId'] as String? ?? '';
  final payload = data['Data'];
  try {
    switch (data['Type']) {
      case 'GroupJoined':
        if (payload is! Map<String, dynamic>) return null;
        return GroupJoined(groupId, GroupInfo.fromJson(payload));
      case 'UserJoined':
        return UserJoined(groupId, payload as String? ?? '');
      case 'UserLeft':
        return UserLeft(groupId, payload as String? ?? '');
      case 'GroupLeft':
        return GroupLeft(groupId);
      case 'NotInGroup':
        return NotInGroup(groupId);
      case 'GroupDoesNotExist':
        return GroupDoesNotExist(groupId);
      case 'LibraryAccessDenied':
        return LibraryAccessDenied(groupId);
      case 'StateUpdate':
        if (payload is! Map<String, dynamic>) return null;
        final state = parseGroupState(payload['State']);
        if (state == null) return null;
        return GroupStateUpdate(groupId, state, payload['Reason'] as String?);
      case 'PlayQueue':
        if (payload is! Map<String, dynamic>) return null;
        return PlayQueueUpdate(groupId, PlayQueue.fromJson(payload));
      default:
        _log.info('aggiornamento SyncPlay non gestito: ${data['Type']}');
        return null;
    }
  } on Object catch (error) {
    _log.warning('aggiornamento SyncPlay non valido: $error');
    return null;
  }
}
