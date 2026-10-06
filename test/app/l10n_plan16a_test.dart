import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 16a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.menuAdmin, 'Amministrazione');
    expect(it.adminTabSessions, 'Sessioni');
    expect(it.adminServerVersion('10.11.9'), 'Jellyfin 10.11.9');
    expect(it.adminServerVersionOs('10.11.9', 'Linux'), 'Jellyfin 10.11.9 · Linux');
    expect(it.adminRestartViewers(1), '1 persona sta guardando:');
    expect(it.adminRestartViewers(2), '2 persone stanno guardando:');
    expect(it.adminViewer('viviroby', 'Dune (2021)'), 'viviroby — Dune (2021)');
    expect(it.adminBitrate('8,2'), '8,2 Mbps');
    expect(it.adminActive('3 min fa'), 'attivo 3 min fa');
    expect(it.adminMovieYear('Dune', '2021'), 'Dune (2021)');
    expect(it.adminEpisodeTitle('Lost', 'S1:E3', 'Pilota'), 'Lost · S1:E3 · Pilota');
    expect(it.adminEpisodeNoCode('Lost', 'Pilota'), 'Lost · Pilota');
    expect(it.adminStale('12:03'), 'Dati non aggiornati · ultimo aggiornamento 12:03');
    expect(it.adminRestarting, 'Riavvio in corso…');
    // Nell'elenco c'è anche la sessione dell'admin stesso: non "altro".
    expect(it.adminSessionsNobodyIdle, 'Nessuno collegato');
    expect(en.adminSessionsNobodyIdle, 'Nobody online');
    expect(en.menuAdmin, 'Administration');
    expect(en.adminRestartViewers(1), '1 person is watching:');
    expect(en.adminRestartViewers(2), '2 people are watching:');
    expect(en.adminStale('12:03'), 'Data not up to date · last update 12:03');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.adminRestart,
        l.adminPendingRestart,
        l.adminPendingRestartHint,
        l.adminRestartBack,
        l.adminRestartTimedOut,
        l.adminRestartRecheck,
        l.adminRestartFailed,
        l.adminRestartTitle,
        l.adminRestartInterrupts,
        l.adminRestartNobody,
        l.adminRestartUnknown,
        l.adminCancel,
        l.adminSessionsPlaying,
        l.adminSessionsIdle,
        l.adminSessionsParties,
        l.adminSessionsNobodyPlaying,
        l.adminSessionsNobodyIdle,
        l.adminSessionsNoParties,
        l.adminMethodDirect,
        l.adminMethodRemux,
        l.adminMethodTranscode,
        l.adminSoftware,
        l.adminPartyPlaying,
        l.adminPartyPaused,
        l.adminPartyWaiting,
        l.adminPartyIdle,
        l.adminReasonContainer,
        l.adminReasonVideoCodec,
        l.adminReasonAudioCodec,
        l.adminReasonSubtitles,
        l.adminReasonVideoProfile,
        l.adminReasonVideoLevel,
        l.adminReasonResolution,
        l.adminReasonBitDepth,
        l.adminReasonVideoRange,
        l.adminReasonAudioChannels,
        l.adminReasonBitrate,
        l.adminReasonExternalAudio,
        l.adminNoLongerAdmin,
      ], everyElement(isNotEmpty));
    }
  });
}
