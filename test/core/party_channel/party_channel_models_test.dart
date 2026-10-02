import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';

/// Evento timbrato come lo manda il plugin, con [fields] sopra i campi
/// comuni.
Map<String, dynamic> stamped(Map<String, dynamic> fields) => {
      'Protocol': 1,
      'Id': 'e1',
      'GroupId': 'g1',
      'UserId': 'u2',
      'UserName': 'Luigi',
      'SentAt': '2026-10-02T21:14:03.512Z',
      ...fields,
    };

void main() {
  test('azione con posizione, da stringa JSON', () {
    final event = parsePartyEvent(jsonEncode(stamped(
        {'Type': 'Action', 'Action': 'Seek', 'PositionTicks': 37350000000})));
    expect(event, isA<PartyActionEvent>());
    event as PartyActionEvent;
    expect(event.action, PartyAction.seek);
    expect(event.position, const Duration(hours: 1, minutes: 2, seconds: 15));
    expect(event.id, 'e1');
    expect(event.groupId, 'g1');
    expect(event.userId, 'u2');
    expect(event.userName, 'Luigi');
    expect(event.sentAt, DateTime.utc(2026, 10, 2, 21, 14, 3, 512));
  });

  test('azione senza posizione, messaggio e reazione, da mappa', () {
    final pause =
        parsePartyEvent(stamped({'Type': 'Action', 'Action': 'Pause'}));
    expect((pause as PartyActionEvent).action, PartyAction.pause);
    expect(pause.position, isNull);

    final chat = parsePartyEvent(stamped({'Type': 'Chat', 'Text': 'che scena'}));
    expect((chat as PartyChatEvent).text, 'che scena');

    final reaction =
        parsePartyEvent(stamped({'Type': 'Reaction', 'Reaction': 'clap'}));
    expect((reaction as PartyReactionEvent).reaction, PartyReaction.clap);
  });

  test('scartati: protocollo, tipo, azione o reazione sconosciuti, campi '
      'mancanti, JSON non valido', () {
    expect(parsePartyEvent(stamped({'Protocol': 2, 'Type': 'Chat', 'Text': 'x'})),
        isNull);
    expect(parsePartyEvent(stamped({'Type': 'Poll'})), isNull);
    expect(parsePartyEvent(stamped({'Type': 'Action', 'Action': 'Shuffle'})),
        isNull);
    expect(parsePartyEvent(stamped({'Type': 'Reaction', 'Reaction': 'heart'})),
        isNull);
    expect(parsePartyEvent(stamped({'Type': 'Chat'})), isNull);
    expect(parsePartyEvent({'Protocol': 1, 'Type': 'Chat', 'Text': 'x'}),
        isNull);
    expect(parsePartyEvent('non json'), isNull);
    expect(parsePartyEvent(42), isNull);
  });

  test('eventi da mandare', () {
    expect(const PartyOutgoingAction(PartyAction.pause).toJson(),
        {'Type': 'Action', 'Action': 'Pause'});
    expect(
        const PartyOutgoingAction(PartyAction.seek,
                position: Duration(minutes: 1))
            .toJson(),
        {'Type': 'Action', 'Action': 'Seek', 'PositionTicks': 600000000});
    expect(const PartyOutgoingChat('ciao').toJson(),
        {'Type': 'Chat', 'Text': 'ciao'});
    expect(const PartyOutgoingReaction(PartyReaction.joy).toJson(),
        {'Type': 'Reaction', 'Reaction': 'joy'});
  });

  test('reazioni: id, emoji e tasti 1–6', () {
    expect(PartyReaction.values.map((r) => r.id),
        ['joy', 'scream', 'cry', 'wow', 'clap', 'facepalm']);
    expect(PartyReaction.values.map((r) => r.emoji).join(), '😂😱😢😮👏🤦');
    expect(PartyReaction.values.map((r) => r.key), [1, 2, 3, 4, 5, 6]);
    expect(PartyReaction.fromId('wow'), PartyReaction.wow);
    expect(PartyReaction.fromId('heart'), isNull);
  });

  test('testo dei messaggi: a capo, spazi, lunghezza in punti di codice', () {
    expect(normalizeChatText('  ciao\r\na tutti\n '), 'ciao a tutti');
    expect(chatTextLength('😂 ok'), 4);
    expect(maxChatLength, 200);
  });

  test('Info del plugin', () {
    final info = PartyPluginInfo.fromJson({'Version': '1.0.0', 'Protocol': 1});
    expect(info.version, '1.0.0');
    expect(info.protocol, 1);
  });
}
