import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/notification_text.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  final en = lookupAppLocalizations(const Locale('en'));
  final at = DateTime.utc(2026, 10, 31);

  (String, String, String) it3(InboxEntry e) {
    final t = notificationTextOf(e, it);
    return (t.title, t.body, t.route);
  }

  (String, String, String) en3(InboxEntry e) {
    final t = notificationTextOf(e, en);
    return (t.title, t.body, t.route);
  }

  test('DownloadNeedsYou, in italiano e in inglese', () {
    final e = DownloadNeedsYouEntry(
        id: 'a',
        seq: 1,
        createdAt: at,
        read: false,
        title: 'Severance S02',
        reason: 'GrabRefused');
    expect(it3(e), (
      'Download da sistemare',
      'Severance S02 — grab rifiutato',
      '/admin?tab=downloads'
    ));
    expect(en3(e), (
      'Download needs you',
      'Severance S02 — grab refused',
      '/admin?tab=downloads'
    ));
  });

  test('un motivo sconosciuto o assente esce com\'è o vuoto', () {
    DownloadNeedsYouEntry with_(String? reason) => DownloadNeedsYouEntry(
        id: 'a', seq: 1, createdAt: at, read: false, title: 'X', reason: reason);
    expect(it3(with_('Nuovo')).$2, 'X — Nuovo');
    expect(it3(with_(null)).$2, 'X — ');
  });

  test('RequestAvailable: pagina del titolo o, senza, le richieste', () {
    RequestAvailableEntry with_(String? itemId) => RequestAvailableEntry(
        id: 'a',
        seq: 1,
        createdAt: at,
        read: false,
        title: 'Dune (2021)',
        itemId: itemId);
    expect(it3(with_(null)),
        ('Ora disponibile', 'Dune (2021)', '/requests'));
    expect(en3(with_('m1')), ('Now available', 'Dune (2021)', '/item/m1'));
  });

  test('RecoveryBlocked: per tutti o per un utente', () {
    RecoveryBlockedEntry with_({String? name, bool everyone = false}) =>
        RecoveryBlockedEntry(
            id: 'a',
            seq: 1,
            createdAt: at,
            read: false,
            userName: name,
            everyone: everyone);
    expect(it3(with_(everyone: true)), (
      'Recupero password bloccato',
      'Troppi tentativi: bloccato per tutti',
      '/admin?tab=users'
    ));
    expect(en3(with_(name: 'Luigi')).$2, 'Too many attempts for Luigi');
  });

  test('disco quasi pieno e riavvio', () {
    expect(
        it3(DiskAlmostFullEntry(
            id: 'a', seq: 1, createdAt: at, read: false, percent: 93)),
        ('Disco quasi pieno', 'Usato il 93% della quota', '/admin?tab=space'));
    expect(
        en3(RestartPendingEntry(id: 'a', seq: 1, createdAt: at, read: false)),
        (
          'Jellyfin needs a restart',
          'Restart the server from the admin dashboard',
          '/admin'
        ));
  });

  test('Recommendation e MatchInvite: rotta con id, cassetta senza', () {
    RecommendationEntry rec(String itemId) => RecommendationEntry(
        id: 'a',
        seq: 1,
        createdAt: at,
        read: false,
        itemId: itemId,
        fromName: 'Luigi',
        title: 'Dune');
    MatchInviteEntry match(String roomId) => MatchInviteEntry(
        id: 'a',
        seq: 1,
        createdAt: at,
        read: false,
        roomId: roomId,
        fromName: 'Luigi');
    expect(it3(rec('m1')),
        ('Luigi ti consiglia un titolo', 'Dune', '/item/m1'));
    expect(it3(rec('')).$3, '/inbox');
    expect(en3(match('r1')).$3, '/match/r1');
    expect(en3(match('')).$3, '/inbox');
  });

  test('NewTitles: i primi 3 nomi, prima i film poi le serie', () {
    final e = NewTitlesEntry(
      id: 'a',
      seq: 1,
      createdAt: at,
      read: false,
      movies: const [
        NewTitleMovie(itemId: 'm1', name: 'Dune'),
        NewTitleMovie(itemId: 'm2', name: 'Heat'),
      ],
      series: const [
        NewTitleSeries(seriesId: 's1', name: 'Severance', episodes: []),
        NewTitleSeries(seriesId: 's2', name: 'Andor', episodes: []),
      ],
    );
    expect(it3(e),
        ('Nuovi titoli su WonderFlix', 'Dune, Heat, Severance', '/home'));
  });

  test('il testo oltre 200 caratteri si taglia a 199 più "…"', () {
    final long = 'a' * 201;
    final body = it3(AnnouncementEntry(
        id: 'a', seq: 1, createdAt: at, read: false, text: long)).$2;
    expect(body, '${'a' * 199}…');
    final exact = it3(AnnouncementEntry(
        id: 'a', seq: 1, createdAt: at, read: false, text: 'a' * 200)).$2;
    expect(exact.length, 200);
  });

  test('alcuni tipi già esistenti della cassetta', () {
    expect(
        it3(AnnouncementEntry(
            id: 'a', seq: 1, createdAt: at, read: false, text: 'Manutenzione')),
        ('Annuncio', 'Manutenzione', '/inbox'));
    expect(
        en3(RequestPendingEntry(
            id: 'a',
            seq: 1,
            createdAt: at,
            read: false,
            title: 'Dune',
            requesterName: 'Luigi')),
        ('New request to approve', 'Dune — from Luigi', '/requests'));
    expect(
        it3(ContactReminderEntry(id: 'a', seq: 1, createdAt: at, read: false)),
        (
          'Proteggi il tuo account',
          'Aggiungi un contatto per recuperare la password',
          '/settings'
        ));
  });
}
