import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/current_party.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi social;
  late FakeSyncPlayApi syncPlay;
  late StreamController<ServerEvent> events;

  setUp(() {
    social = FakeSocialApi();
    syncPlay = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    syncPlay.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  ProviderContainer container({bool parties = true}) {
    final c = ProviderContainer.test(overrides: [
      ...socialTestOverrides(social,
          events: events.stream,
          features: SocialFeatures(friends: true, parties: parties)),
      syncPlayApiProvider.overrideWithValue(syncPlay),
    ]);
    c.listen(currentPartyProvider, (_, _) {});
    return c;
  }

  test('nel gruppo legge modalità e codice; fuori niente', () async {
    social.details['g1'] =
        const PartyDetails(mode: PartyMode.private, code: 'K7PQ2X');
    final c = container();
    expect(c.read(currentPartyProvider), isNull);
    await c.read(watchPartySessionProvider.notifier).join('g1');
    await pumpEventQueue();
    final current = c.read(currentPartyProvider)!;
    expect(current.code, 'K7PQ2X');
    expect(current.announceCode, isFalse,
        reason: 'si annuncia solo il party appena creato da noi');

    await c.read(watchPartySessionProvider.notifier).leave();
    await pumpEventQueue();
    expect(c.read(currentPartyProvider), isNull);
  });

  test('senza la funzione parties: niente', () async {
    final c = container(parties: false);
    await c.read(watchPartySessionProvider.notifier).join('g1');
    await pumpEventQueue();
    expect(c.read(currentPartyProvider), isNull);
    expect(social.calls, isNot(contains('details g1')));
    await c.read(watchPartySessionProvider.notifier).leave();
  });

  test('registrato da noi: la lettura non lo sovrascrive, il codice si '
      'annuncia una volta', () async {
    // Una lettura dei dettagli può partire prima della registrazione: la
    // sua risposta non deve cancellare il codice da annunciare. La risposta
    // arriva dopo `registered`, per forza.
    social.details['g1'] =
        const PartyDetails(mode: PartyMode.private, code: 'ALTRO1');
    final gate = social.detailsGate = Completer<void>();
    final c = container();
    await c.read(watchPartySessionProvider.notifier).join('g1');
    await pumpEventQueue();
    expect(social.calls, contains('details g1'),
        reason: 'la lettura è partita e aspetta');
    c
        .read(currentPartyProvider.notifier)
        .registered('g1', PartyMode.private, 'K7PQ2X');
    gate.complete();
    await pumpEventQueue();
    expect(c.read(currentPartyProvider)!.code, 'K7PQ2X');
    expect(c.read(currentPartyProvider)!.announceCode, isTrue);
    c.read(currentPartyProvider.notifier).codeAnnounced();
    expect(c.read(currentPartyProvider)!.announceCode, isFalse);
    c.read(currentPartyProvider.notifier).invited('u2');
    expect(c.read(currentPartyProvider)!.invited, {'u2'});
    await c.read(watchPartySessionProvider.notifier).leave();
  });

  test('una registrazione di un gruppo che non è il nostro si ignora',
      () async {
    final c = container();
    // Fuori da un gruppo (es. registrazione finita dopo l'uscita).
    c
        .read(currentPartyProvider.notifier)
        .registered('g1', PartyMode.private, 'K7PQ2X');
    expect(c.read(currentPartyProvider), isNull);

    await c.read(watchPartySessionProvider.notifier).join('g1');
    await pumpEventQueue();
    c
        .read(currentPartyProvider.notifier)
        .registered('g2', PartyMode.private, 'K7PQ2X');
    expect(c.read(currentPartyProvider)?.code, isNull,
        reason: 'un altro gruppo non sostituisce quello in cui siamo');
    expect(c.read(currentPartyProvider)?.announceCode, isNot(true));
    await c.read(watchPartySessionProvider.notifier).leave();
  });
}
