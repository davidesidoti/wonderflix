import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 16b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.adminTabMaintenance, 'Manutenzione');
    expect(it.adminTabActivity, 'Registro');
    expect(it.adminTabWonderflix, 'WonderFlix');
    expect(it.adminTaskLastRun('2 h fa'), 'Ultima: 2 h fa');
    expect(it.adminTaskCompletedIn('3 min'), 'Completata in 3 min');
    expect(it.adminDurationSeconds(45), '45 s');
    expect(it.adminDurationMinutes(3), '3 min');
    expect(it.adminDurationHours(1, 5), '1 h 5 min');
    expect(it.adminAnnouncementSent(1), 'Annuncio inviato a 1 persona');
    expect(it.adminAnnouncementSent(12), 'Annuncio inviato a 12 persone');
    expect(it.adminNewTitlesPending(1), '1 titolo in attesa del prossimo riepilogo');
    expect(it.adminNewTitlesPending(4), '4 titoli in attesa del prossimo riepilogo');
    expect(it.adminNewTitlesSentTitles(1), 'Inviato 1 titolo');
    expect(it.adminNewTitlesSentTitles(3), 'Inviati 3 titoli');
    expect(it.adminNewTitlesSentTo(1), 'a 1 persona');
    expect(it.adminNewTitlesSentTo(9), 'a 9 persone');
    expect(it.adminSeerrLastEvent('2 h fa', 'Richiesta in attesa'),
        'Ultimo evento dal webhook: 2 h fa · Richiesta in attesa');
    expect(it.adminSeerrConnected('3.4.1'), 'Collegato a Seerr 3.4.1');
    expect(en.adminTabActivity, 'Activity');
    expect(en.adminAnnouncementSent(2), 'Announcement sent to 2 people');
    expect(en.adminNewTitlesSentTitles(1), 'Sent 1 title');
    expect(en.adminNewTitlesSentTo(2), 'to 2 people');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.adminLibraries,
        l.adminScanAll,
        l.adminScan,
        l.adminTasks,
        l.adminTaskStart,
        l.adminTaskStop,
        l.adminTaskStopping,
        l.adminTaskFailed,
        l.adminTaskCancelled,
        l.adminTaskAborted,
        l.adminTaskNeverRun,
        l.adminActivityAll,
        l.adminActivityUsers,
        l.adminActivitySystem,
        l.adminActivityRefresh,
        l.adminActivityOpenItem,
        l.adminActivityEmpty,
        l.adminActivityEnd,
        l.adminAnnouncement,
        l.adminAnnouncementSend,
        l.adminAnnouncementConfirm,
        l.adminAnnouncementInvalid,
        l.adminSend,
        l.adminNewTitles,
        l.adminNewTitlesNotify,
        l.adminNewTitlesNone,
        l.adminNewTitlesOff,
        l.adminNewTitlesSendNow,
        l.adminSeerr,
        l.adminSeerrNoEvents,
        l.adminSeerrEventPending,
        l.adminSeerrEventAvailable,
        l.adminSeerrEventTest,
        l.adminSeerrTest,
        l.adminSeerrConnectedPlain,
        l.adminSeerrNotConfiguredError,
        l.adminSeerrAuthError,
        l.adminSeerrUnavailable,
        l.adminSeerrNotConfigured,
      ], everyElement(isNotEmpty));
    }
  });
}
