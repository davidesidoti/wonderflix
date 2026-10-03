import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';

void main() {
  test('Info: versione e funzioni; senza Features nessuna', () {
    final info = SocialPluginInfo.fromJson({
      'Version': '1.1.0',
      'Protocol': 1,
      'Features': ['friends', 7, 'parties'],
    });
    expect(info.version, '1.1.0');
    expect(info.features, {'friends', 'parties'});
    expect(
        SocialPluginInfo.fromJson({'Version': '1.0.0', 'Protocol': 1})
            .features,
        isEmpty);
  });

  test('amici e richieste', () {
    final snapshot = FriendsSnapshot.fromJson({
      'Friends': [
        {'UserId': 'u2', 'Name': 'Luigi', 'Online': true, 'Party': null},
        {
          'UserId': 'u4',
          'Name': 'Daisy',
          'Online': false,
          'Party': {'GroupId': 'g1', 'Title': 'Dune'},
        },
        // Sul server vero `Party` è omessa, non `null`.
        {'UserId': 'u5', 'Name': 'Toad', 'Online': true},
      ],
      'Incoming': [
        {'UserId': 'u3', 'Name': 'Peach'},
      ],
      'Outgoing': [],
    });
    expect(snapshot.friends.map((f) => f.name), ['Luigi', 'Daisy', 'Toad']);
    expect(snapshot.friends.first.online, isTrue);
    expect(snapshot.friends.first.party, isNull);
    expect(snapshot.friends[1].party?.title, 'Dune');
    expect(snapshot.friends.last.party, isNull);
    expect(snapshot.incoming.single.userId, 'u3');
    expect(snapshot.outgoing, isEmpty);
  });

  test('risultati della ricerca; relazione sconosciuta = nessuna', () {
    final result = UserSearchResult.fromJson(
        {'UserId': 'u2', 'Name': 'Luigi', 'Relation': 'Incoming'});
    expect(result.relation, FriendRelation.incoming);
    expect(
        UserSearchResult.fromJson(
                {'UserId': 'u2', 'Name': 'Luigi', 'Relation': 'Boh'})
            .relation,
        FriendRelation.none);
  });

  test('avvisi del plugin', () {
    final request = parseSocialEvent(
        '{"Protocol":1,"Type":"FriendRequest","FromUserId":"u2",'
        '"FromName":"Luigi"}');
    expect(request, isA<FriendRequestEvent>());
    expect((request! as FriendRequestEvent).fromName, 'Luigi');
    expect(parseSocialEvent('{"Protocol":1,"Type":"FriendsChanged"}'),
        isA<FriendsChangedEvent>());
    // Un evento del canale, un altro protocollo, JSON rotto: niente.
    expect(parseSocialEvent('{"Protocol":1,"Type":"Chat","Text":"ciao"}'),
        isNull);
    expect(parseSocialEvent('{"Protocol":2,"Type":"FriendsChanged"}'),
        isNull);
    expect(parseSocialEvent('{rotto'), isNull);
    expect(parseSocialEvent('{"Protocol":1,"Type":"FriendRequest"}'), isNull);
  });

  test('modalità in rete', () {
    expect(PartyMode.fromWire('Friends'), PartyMode.friends);
    expect(PartyMode.private.wire, 'Private');
    expect(PartyMode.fromWire('friends'), isNull);
  });

  test('party dell\'elenco del plugin come gruppi con la modalità', () {
    final group = partyGroupFromJson({
      'GroupId': 'g1',
      'Name': 'Mario · Dune',
      'State': 'Playing',
      'Participants': ['Mario', 'Luigi'],
      'Mode': 'Private',
    });
    expect(group.id, 'g1');
    expect(group.name, 'Mario · Dune');
    expect(group.state, GroupState.playing);
    expect(group.participants, ['Mario', 'Luigi']);
    expect(group.mode, PartyMode.private);
    expect(partyGroupFromJson({'GroupId': 'g2'}).mode, PartyMode.public);
  });

  test('dettagli del party: il codice può mancare', () {
    final private =
        PartyDetails.fromJson({'Mode': 'Private', 'Code': 'K7PQ2X'});
    expect(private.mode, PartyMode.private);
    expect(private.code, 'K7PQ2X');
    expect(PartyDetails.fromJson({'Mode': 'Public'}).code, isNull);
  });

  test('avvisi dei party', () {
    final started = parseSocialEvent('{"Protocol":1,"Type":"PartyStarted",'
        '"GroupId":"g1","Name":"Mario \\u00b7 Dune","Mode":"Friends"}');
    expect(started, isA<PartyStartedEvent>());
    started as PartyStartedEvent;
    expect(started.groupId, 'g1');
    expect(started.name, 'Mario · Dune');
    expect(started.mode, PartyMode.friends);
    final invite = parseSocialEvent('{"Protocol":1,"Type":"PartyInvite",'
        '"FromName":"Mario","GroupId":"g1","Name":"Mario · Dune"}');
    expect((invite! as PartyInviteEvent).fromName, 'Mario');
  });

  test('codici: forma canonica e forma da mostrare', () {
    expect(normalizePartyCode(' k7p-q2x '), 'K7PQ2X');
    expect(formatPartyCode('k7pq2x'), 'K7P-Q2X');
    expect(formatPartyCode('K7P'), 'K7P');
  });
}
