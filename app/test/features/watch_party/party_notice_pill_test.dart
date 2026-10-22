import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/features/watch_party/party_notice_pill.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

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
    expect(text(const PartyNotice(PartyNoticeKind.nextTitle, title: 'Arrival')),
        'Successivo: Arrival');
    expect(
        text(const PartyNotice(PartyNoticeKind.nowWatching, title: 'Dune')),
        'Si guarda: Dune');
    expect(text(const PartyNotice(PartyNoticeKind.resync)),
        'Riallineamento al gruppo');
    expect(text(const PartyNotice(PartyNoticeKind.ended)),
        'Il watch party è terminato');
    expect(text(const PartyNotice(PartyNoticeKind.removed)),
        'Non sei più nel watch party');
    expect(
        text(const PartyNotice(PartyNoticeKind.privateCode, title: 'K7P-Q2X')),
        'Party privato · codice K7P-Q2X');
    expect(text(const PartyNotice(PartyNoticeKind.codeCopied)),
        'Codice copiato');
    expect(text(const PartyNotice(PartyNoticeKind.inviteSent, name: 'Luigi')),
        'Invito mandato a Luigi');
    expect(text(const PartyNotice(PartyNoticeKind.inviteFailed)),
        'Operazione non riuscita');
    expect(text(const PartyNotice(PartyNoticeKind.inviteRateLimited)),
        'Troppe richieste, riprova più tardi');
  });

  test('testi con il nome di chi agisce (spec E §8)', () {
    String text(PartyNotice notice) => partyNoticeText(l, notice);
    const time = Duration(minutes: 32, seconds: 10);
    expect(text(const PartyNotice(PartyNoticeKind.paused, name: 'Luigi')),
        'Luigi ha messo in pausa');
    expect(text(const PartyNotice(PartyNoticeKind.resumed, name: 'Luigi')),
        'Luigi ha ripreso');
    expect(
        text(const PartyNotice(PartyNoticeKind.forcedResume, name: 'Luigi')),
        'Luigi ha fatto ripartire senza aspettare');
    expect(
        text(const PartyNotice(PartyNoticeKind.seeked,
            name: 'Luigi', position: time)),
        'Luigi ha saltato a 32:10');
    expect(
        text(const PartyNotice(PartyNoticeKind.nextEpisode,
            name: 'Luigi', title: 'S1:E5 · Titolo')),
        'Luigi ha avviato: S1:E5 · Titolo');
    expect(
        text(const PartyNotice(PartyNoticeKind.nextTitle,
            name: 'Luigi', title: 'Arrival')),
        'Luigi ha avviato: Arrival');
    expect(
        text(const PartyNotice(PartyNoticeKind.nowWatching,
            name: 'Luigi', title: 'Dune')),
        'Luigi ha scelto: Dune');
    // Le proprie azioni restano in seconda persona.
    expect(
        text(const PartyNotice(PartyNoticeKind.paused,
            mine: true, name: 'Mario')),
        'Hai messo in pausa');
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
        partyNoticeText(
            en,
            const PartyNotice(PartyNoticeKind.seeked,
                name: 'Luigi', position: time)),
        'Luigi jumped to 32:10');
    expect(
        partyNoticeText(en,
            const PartyNotice(PartyNoticeKind.nextTitle, title: 'Arrival')),
        'Next: Arrival');
  });

  test('icone degli avvisi', () {
    expect(partyNoticeIcon(PartyNoticeKind.paused), LucideIcons.pause);
    expect(partyNoticeIcon(PartyNoticeKind.resumed), LucideIcons.play);
    expect(partyNoticeIcon(PartyNoticeKind.forcedResume), LucideIcons.play);
    expect(partyNoticeIcon(PartyNoticeKind.seeked), LucideIcons.fastForward);
    expect(partyNoticeIcon(PartyNoticeKind.joined), LucideIcons.userPlus);
    expect(partyNoticeIcon(PartyNoticeKind.left), LucideIcons.userMinus);
    expect(partyNoticeIcon(PartyNoticeKind.nextEpisode), LucideIcons.skipForward);
    expect(partyNoticeIcon(PartyNoticeKind.nextTitle), LucideIcons.skipForward);
    expect(partyNoticeIcon(PartyNoticeKind.nowWatching), LucideIcons.clapperboard);
    expect(partyNoticeIcon(PartyNoticeKind.resync), LucideIcons.refreshCw);
    expect(partyNoticeIcon(PartyNoticeKind.ended), LucideIcons.circleStop);
    expect(partyNoticeIcon(PartyNoticeKind.removed), LucideIcons.logOut);
    expect(partyNoticeIcon(PartyNoticeKind.privateCode), LucideIcons.lock);
    expect(partyNoticeIcon(PartyNoticeKind.codeCopied), LucideIcons.copy);
    expect(partyNoticeIcon(PartyNoticeKind.inviteSent), LucideIcons.send);
    expect(partyNoticeIcon(PartyNoticeKind.inviteFailed),
        LucideIcons.circleAlert);
    expect(partyNoticeIcon(PartyNoticeKind.inviteRateLimited),
        LucideIcons.circleAlert);
  });

  test('avvisi della coda (spec H §10)', () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect(
        partyNoticeText(l,
            const PartyNotice(PartyNoticeKind.previousItem, title: 'S1:E4 · Pilot')),
        'Precedente: S1:E4 · Pilot');
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.previousItem,
                title: 'S1:E4 · Pilot', name: 'Luigi')),
        'Luigi ha avviato il precedente: S1:E4 · Pilot');
    expect(partyNoticeText(l, const PartyNotice(PartyNoticeKind.shuffleOn)),
        'Ordine casuale attivato');
    expect(
        partyNoticeText(
            l, const PartyNotice(PartyNoticeKind.shuffleOff, name: 'Luigi')),
        'Luigi ha tolto l\'ordine casuale');
    expect(
        partyNoticeText(
            l, const PartyNotice(PartyNoticeKind.queueFailed, mine: true)),
        'Non riuscito, riprova');
    expect(partyNoticeIcon(PartyNoticeKind.previousItem), LucideIcons.skipBack);
    expect(partyNoticeIcon(PartyNoticeKind.shuffleOn), LucideIcons.shuffle);
    expect(partyNoticeIcon(PartyNoticeKind.queueFailed), LucideIcons.circleAlert);
  });

  test('avvisi delle aggiunte (spec H §10)', () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect(
        partyNoticeText(l,
            const PartyNotice(PartyNoticeKind.queued, title: 'Alien', count: 1)),
        'Aggiunto alla coda: Alien');
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.queued,
                count: 8, series: 'Dark', name: 'Marco')),
        'Marco ha aggiunto alla coda: 8 episodi di Dark');
    expect(
        partyNoticeText(l,
            const PartyNotice(PartyNoticeKind.queuedNext, count: 3, mine: true)),
        'Hai messo subito dopo: 3 titoli');
    expect(
        partyNoticeText(
            l, const PartyNotice(PartyNoticeKind.queueRejected, mine: true)),
        'Non aggiunto: qualcuno nel party non può vedere questo titolo');
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.queuePartial,
                mine: true, count: 10, total: 24, series: 'Dark')),
        'Aggiunti 10 episodi su 24: la coda è piena');
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.queuePartial,
                mine: true, count: 2, total: 5)),
        'Aggiunti 2 titoli su 5: la coda è piena');
    // Un solo titolo aggiunto: singolare.
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.queuePartial,
                mine: true, count: 1, total: 3, series: 'Dark')),
        'Aggiunto 1 episodio su 3: la coda è piena');
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.queuePartial,
                mine: true, count: 1, total: 5)),
        'Aggiunto 1 titolo su 5: la coda è piena');
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
        partyNoticeText(
            en,
            const PartyNotice(PartyNoticeKind.queuePartial,
                mine: true, count: 1, total: 3, series: 'Dark')),
        'Added 1 of 3 episodes: the queue is full');
    expect(
        partyNoticeText(
            en,
            const PartyNotice(PartyNoticeKind.queuePartial,
                mine: true, count: 2, total: 5)),
        'Added 2 of 5 titles: the queue is full');
    expect(
        partyNoticeText(
            l, const PartyNotice(PartyNoticeKind.queueFull, mine: true)),
        'La coda è piena (100 titoli)');
    expect(partyNoticeIcon(PartyNoticeKind.queued), LucideIcons.listPlus);
    expect(partyNoticeIcon(PartyNoticeKind.queuedNext), LucideIcons.listStart);
    expect(partyNoticeIcon(PartyNoticeKind.queueRejected),
        LucideIcons.circleAlert);
  });
}
