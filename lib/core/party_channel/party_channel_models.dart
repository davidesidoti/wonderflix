import 'dart:convert';

import 'package:logging/logging.dart';

import '../jellyfin/item_models.dart';

final _log = Logger('watchparty');

/// Versione del protocollo tra l'app e il plugin "WonderFlix Watch Party"
/// (spec E §6.3). Un plugin con un protocollo diverso vale come assente.
const partyChannelProtocol = 1;

/// Chiave degli `Arguments` del `GeneralCommand` `SendString` con cui il
/// plugin inoltra gli eventi (spec E §6.3). Non è `String`, che jellyfin-web
/// scriverebbe nel campo con il focus.
const partyChannelArgumentKey = 'WonderFlixWatchParty';

/// Lunghezza massima di un messaggio in punti di codice Unicode (spec E
/// §6.3); il plugin usa lo stesso limite.
const maxChatLength = 200;

/// Il testo di un messaggio come lo vuole il plugin: a capo diventati spazi,
/// spazi esterni tolti.
String normalizeChatText(String text) =>
    text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

/// Lunghezza di un messaggio in punti di codice (un'emoji semplice vale 1).
int chatTextLength(String text) => text.runes.length;

/// Risposta di `GET /WonderFlixWatchParty/Info`.
class PartyPluginInfo {
  const PartyPluginInfo({required this.version, required this.protocol});

  factory PartyPluginInfo.fromJson(Map<String, dynamic> json) =>
      PartyPluginInfo(
        version: json['Version'] as String,
        protocol: (json['Protocol'] as num).toInt(),
      );

  final String version;
  final int protocol;
}

/// Azioni annunciate al gruppo: hanno i nomi delle richieste SyncPlay.
enum PartyAction {
  pause('Pause'),
  unpause('Unpause'),
  seek('Seek'),
  nextItem('NextItem'),
  newQueue('NewQueue');

  const PartyAction(this.wire);

  /// Nome nel protocollo.
  final String wire;

  static PartyAction? fromWire(Object? value) {
    for (final action in values) {
      if (action.wire == value) return action;
    }
    return null;
  }
}

/// Reazioni rapide (spec E §10.1). In rete viaggia [id], mai l'emoji.
enum PartyReaction {
  joy('joy', '😂'),
  scream('scream', '😱'),
  cry('cry', '😢'),
  wow('wow', '😮'),
  clap('clap', '👏'),
  facepalm('facepalm', '🤦');

  const PartyReaction(this.id, this.emoji);

  final String id;
  final String emoji;

  /// Tasto della reazione, da 1 a 6.
  int get key => index + 1;

  /// `null` per le reazioni che questa versione dell'app non conosce.
  static PartyReaction? fromId(Object? id) {
    for (final reaction in values) {
      if (reaction.id == id) return reaction;
    }
    return null;
  }
}

/// Un evento timbrato dal plugin (spec E §6.3): chi l'ha mandato lo dice il
/// server, non il client.
sealed class PartyEvent {
  const PartyEvent({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    required this.sentAt,
  });

  final String id;
  final String groupId;
  final String userId;
  final String userName;

  /// Ora UTC del server.
  final DateTime sentAt;
}

/// Un membro annuncia un'azione sul gruppo (spec E §7.4).
final class PartyActionEvent extends PartyEvent {
  const PartyActionEvent({
    required super.id,
    required super.groupId,
    required super.userId,
    required super.userName,
    required super.sentAt,
    required this.action,
    this.position,
  });

  final PartyAction action;

  /// Solo per [PartyAction.seek].
  final Duration? position;
}

final class PartyChatEvent extends PartyEvent {
  const PartyChatEvent({
    required super.id,
    required super.groupId,
    required super.userId,
    required super.userName,
    required super.sentAt,
    required this.text,
  });

  final String text;
}

final class PartyReactionEvent extends PartyEvent {
  const PartyReactionEvent({
    required super.id,
    required super.groupId,
    required super.userId,
    required super.userName,
    required super.sentAt,
    required this.reaction,
  });

  final PartyReaction reaction;
}

/// Tipi degli avvisi del plugin che non riguardano il canale del gruppo
/// (spec F §6.8, spec G §6.4): li legge `parseSocialEvent`, qui si scartano
/// in silenzio.
const socialEventTypes = {
  'FriendRequest',
  'FriendsChanged',
  'PartyStarted',
  'PartyInvite',
  'InboxChanged',
};

/// Legge un evento timbrato, da stringa JSON (WebSocket) o già decodificato
/// (storico di `Join`, risposta di `Events`). `null`, con una riga nel log,
/// se è malformato, di un altro protocollo o di un tipo che non conosciamo.
PartyEvent? parsePartyEvent(Object? raw) {
  try {
    final json = raw is String ? jsonDecode(raw) : raw;
    if (json is! Map<String, dynamic>) {
      throw const FormatException('non è un oggetto');
    }
    final protocol = json['Protocol'];
    if (protocol != partyChannelProtocol) {
      _log.info('evento del canale con protocollo $protocol: scartato');
      return null;
    }
    if (socialEventTypes.contains(json['Type'])) return null;
    final id = json['Id'] as String;
    final groupId = json['GroupId'] as String;
    final userId = json['UserId'] as String;
    final userName = json['UserName'] as String;
    final sentAt = DateTime.parse(json['SentAt'] as String).toUtc();
    switch (json['Type']) {
      case 'Action':
        final action = PartyAction.fromWire(json['Action']);
        if (action == null) break;
        final ticks = json['PositionTicks'];
        return PartyActionEvent(
          id: id,
          groupId: groupId,
          userId: userId,
          userName: userName,
          sentAt: sentAt,
          action: action,
          position: ticks is num ? ticksToDuration(ticks.toInt()) : null,
        );
      case 'Chat':
        return PartyChatEvent(
          id: id,
          groupId: groupId,
          userId: userId,
          userName: userName,
          sentAt: sentAt,
          text: json['Text'] as String,
        );
      case 'Reaction':
        final reaction = PartyReaction.fromId(json['Reaction']);
        if (reaction == null) break;
        return PartyReactionEvent(
          id: id,
          groupId: groupId,
          userId: userId,
          userName: userName,
          sentAt: sentAt,
          reaction: reaction,
        );
    }
    _log.info('evento del canale non riconosciuto '
        '(${json['Type']}): scartato');
    return null;
  } on Object catch (error) {
    // Solo il tipo: il messaggio di un errore può citare il JSON, cioè il
    // testo della chat.
    _log.info('evento del canale non valido: ${error.runtimeType}');
    return null;
  }
}

/// Evento da mandare al plugin (corpo di `Events`, spec E §6.3).
sealed class PartyOutgoing {
  const PartyOutgoing();

  Map<String, dynamic> toJson();
}

final class PartyOutgoingAction extends PartyOutgoing {
  const PartyOutgoingAction(this.action, {this.position});

  final PartyAction action;
  final Duration? position;

  @override
  Map<String, dynamic> toJson() {
    final position = this.position;
    return {
      'Type': 'Action',
      'Action': action.wire,
      if (position != null) 'PositionTicks': durationToTicks(position),
    };
  }
}

final class PartyOutgoingChat extends PartyOutgoing {
  const PartyOutgoingChat(this.text);

  final String text;

  @override
  Map<String, dynamic> toJson() => {'Type': 'Chat', 'Text': text};
}

final class PartyOutgoingReaction extends PartyOutgoing {
  const PartyOutgoingReaction(this.reaction);

  final PartyReaction reaction;

  @override
  Map<String, dynamic> toJson() => {'Type': 'Reaction', 'Reaction': reaction.id};
}
