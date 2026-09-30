import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/watch_party/party_notice_pill.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('testi di tutti gli avvisi', () {
    String text(PartyNotice notice) => partyNoticeText(l, notice);
    const time = Duration(minutes: 32, seconds: 10);
    expect(text(const PartyNotice(PartyNoticeKind.paused)), 'Pausa');
    expect(text(const PartyNotice(PartyNoticeKind.paused, mine: true)),
        'Hai messo in pausa');
    expect(text(const PartyNotice(PartyNoticeKind.resumed)), 'Ripresa');
    expect(text(const PartyNotice(PartyNoticeKind.resumed, mine: true)),
        'Hai ripreso');
    expect(text(const PartyNotice(PartyNoticeKind.forcedResume)),
        'Si riprende senza aspettare');
    expect(text(const PartyNotice(PartyNoticeKind.seeked, position: time)),
        'Salto a 32:10');
    expect(
        text(const PartyNotice(PartyNoticeKind.seeked,
            mine: true, position: time)),
        'Hai saltato a 32:10');
    expect(text(const PartyNotice(PartyNoticeKind.joined, name: 'Luigi')),
        'Luigi è nel watch party');
    expect(text(const PartyNotice(PartyNoticeKind.left, name: 'Luigi')),
        'Luigi ha lasciato il watch party');
    expect(
        text(const PartyNotice(PartyNoticeKind.nextEpisode,
            title: 'S1:E5 · Titolo')),
        'Episodio successivo: S1:E5 · Titolo');
    expect(
        text(const PartyNotice(PartyNoticeKind.nowWatching, title: 'Dune')),
        'Si guarda: Dune');
    expect(text(const PartyNotice(PartyNoticeKind.resync)),
        'Riallineamento al gruppo');
  });

  testWidgets('mostra l\'avviso attuale, niente senza avvisi', (tester) async {
    await pumpApp(tester, const Center(child: PartyNoticePill()), overrides: [
      partyNoticesProvider.overrideWith(() => FakePartyNotices(
          const PartyNotice(PartyNoticeKind.joined, name: 'Luigi'))),
    ]);
    expect(find.text('Luigi è nel watch party'), findsOneWidget);
  });

  testWidgets('nessun avviso: nessuna pillola', (tester) async {
    await pumpApp(tester, const Center(child: PartyNoticePill()), overrides: [
      partyNoticesProvider.overrideWith(FakePartyNotices.new),
    ]);
    expect(find.byKey(const Key('party-notice')), findsNothing);
  });
}
