import 'dart:convert';

import 'package:logging/logging.dart';

import '../party_channel/party_channel_models.dart';

final _log = Logger('social');

/// Funzioni del plugin oltre al canale dello spec E (spec F §6.7).
abstract final class PluginFeatures {
  static const friends = 'friends';
  static const parties = 'parties';
}

/// Risposta di `GET /WonderFlixWatchParty/Info`, con le funzioni.
class SocialPluginInfo {
  const SocialPluginInfo({required this.version, required this.features});

  factory SocialPluginInfo.fromJson(Map<String, dynamic> json) =>
      SocialPluginInfo(
        version: json['Version'] as String,
        features: {
          for (final feature in json['Features'] as List? ?? const [])
            if (feature is String) feature,
        },
      );

  final String version;
  final Set<String> features;
}

/// Relazione con un utente trovato (spec F §6.2).
enum FriendRelation {
  none('None'),
  friend('Friend'),
  incoming('Incoming'),
  outgoing('Outgoing');

  const FriendRelation(this.wire);

  final String wire;

  static FriendRelation fromWire(Object? value) =>
      values.firstWhere((r) => r.wire == value, orElse: () => none);
}

/// Il party visibile in cui sta un amico (dal piano 12b).
class FriendParty {
  const FriendParty({required this.groupId, required this.title});

  final String groupId;
  final String title;
}

class FriendEntry {
  const FriendEntry({
    required this.userId,
    required this.name,
    required this.online,
    this.party,
  });

  factory FriendEntry.fromJson(Map<String, dynamic> json) {
    // `Party` può mancare del tutto (il plugin la omette) oppure essere null.
    final party = json['Party'];
    return FriendEntry(
      userId: json['UserId'] as String,
      name: json['Name'] as String,
      online: json['Online'] as bool? ?? false,
      party: party is Map<String, dynamic>
          ? FriendParty(
              groupId: party['GroupId'] as String,
              title: party['Title'] as String)
          : null,
    );
  }

  final String userId;
  final String name;
  final bool online;
  final FriendParty? party;
}

/// Chi ha mandato o ricevuto una richiesta in sospeso.
class PersonEntry {
  const PersonEntry({required this.userId, required this.name});

  factory PersonEntry.fromJson(Map<String, dynamic> json) => PersonEntry(
      userId: json['UserId'] as String, name: json['Name'] as String);

  final String userId;
  final String name;
}

/// Risposta di `GET Friends`.
class FriendsSnapshot {
  const FriendsSnapshot({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
  });

  factory FriendsSnapshot.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) => [
          for (final raw in json[key] as List? ?? const [])
            raw as Map<String, dynamic>,
        ];
    return FriendsSnapshot(
      friends: [for (final raw in list('Friends')) FriendEntry.fromJson(raw)],
      incoming: [for (final raw in list('Incoming')) PersonEntry.fromJson(raw)],
      outgoing: [for (final raw in list('Outgoing')) PersonEntry.fromJson(raw)],
    );
  }

  static const empty = FriendsSnapshot();

  final List<FriendEntry> friends;
  final List<PersonEntry> incoming;
  final List<PersonEntry> outgoing;
}

class UserSearchResult {
  const UserSearchResult({
    required this.userId,
    required this.name,
    required this.relation,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) =>
      UserSearchResult(
        userId: json['UserId'] as String,
        name: json['Name'] as String,
        relation: FriendRelation.fromWire(json['Relation']),
      );

  final String userId;
  final String name;
  final FriendRelation relation;
}

/// Avvisi del plugin fuori dal canale di un gruppo (spec F §6.8).
sealed class SocialEvent {
  const SocialEvent();
}

/// Qualcuno ci ha chiesto l'amicizia.
final class FriendRequestEvent extends SocialEvent {
  const FriendRequestEvent({required this.fromUserId, required this.fromName});

  final String fromUserId;
  final String fromName;
}

/// Amici o richieste sono cambiati: si rilegge `GET Friends`.
final class FriendsChangedEvent extends SocialEvent {
  const FriendsChangedEvent();
}

/// Legge un avviso del plugin (stringa JSON dal WebSocket). `null` se non è
/// un avviso sociale; una riga nel log se è malformato.
SocialEvent? parseSocialEvent(Object? raw) {
  try {
    final json = raw is String ? jsonDecode(raw) : raw;
    if (json is! Map<String, dynamic> ||
        json['Protocol'] != partyChannelProtocol) {
      return null;
    }
    switch (json['Type']) {
      case 'FriendRequest':
        return FriendRequestEvent(
          fromUserId: json['FromUserId'] as String,
          fromName: json['FromName'] as String,
        );
      case 'FriendsChanged':
        return const FriendsChangedEvent();
    }
    return null;
  } on Object catch (error) {
    // Solo il tipo: il messaggio può citare il JSON.
    _log.info('avviso del plugin non valido: ${error.runtimeType}');
    return null;
  }
}
