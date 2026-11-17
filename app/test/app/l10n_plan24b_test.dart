import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

/// Le chiavi del piano 24b (Task 1).
const _keys = [
  'itemActionsMenu',
  'itemActionReport',
  'itemActionMediaInfo',
  'itemActionSubtitles',
  'reportDialogTitle',
  'reportLevelThisEpisode',
  'reportLevelThisSeason',
  'reportLevelSeries',
  'reportLevelSeason',
  'reportLevelSpecials',
  'reportLevelEpisode',
  'reportTypeSubtitles',
  'reportTypeMetadata',
  'reportTypeAudioVideo',
  'reportTypeOther',
  'reportNoteHint',
  'reportAlreadySent',
  'reportSend',
  'reportSent',
  'reportLimitReached',
  'reportNoPermission',
  'inboxReportPending',
  'inboxReportFixed',
  'inboxReportCannotFix',
  'inboxReportUnknownTitle',
  'reportsOpenTitle',
  'reportOpen',
  'reportFixedAction',
  'reportCannotFixAction',
  'reportClosed',
  'reportNoNote',
  'reportResolveFixedTitle',
  'reportResolveCannotFixTitle',
  'reportResolveNoteHint',
  'reportAlreadyClosed',
  'reportShortcutSubtitles',
  'adminReportsTitle',
  'adminReportsEmpty',
  'adminReportsNeedPlugin',
  'adminReportsOpen',
  'subtitlesDialogTitle',
  'subtitlesLanguage',
  'subtitlesSearch',
  'subtitlesUpload',
  'subtitlesNoResults',
  'subtitlesDownload',
  'subtitlesHashMatch',
  'subtitlesHearingImpaired',
  'subtitlesForced',
  'subtitlesMachineTranslated',
  'subtitlesDownloads',
  'subtitlesDownloadFailed',
  'subtitlesUploadFailed',
  'subtitlesFileTooLarge',
  'subtitlesWaiting',
  'subtitlesTrackAdded',
  'subtitlesTrackSoon',
  'subtitlesExisting',
  'subtitlesNone',
  'subtitlesExternal',
  'subtitlesEmbedded',
  'subtitlesDelete',
  'subtitlesDeleteTitle',
  'subtitlesDeleteMessage',
  'subtitlesFileTypes',
  'subtitlesNextPlayback',
  'playerSearchSubtitles',
  'mediaInfoTitle',
  'mediaInfoVersion',
  'mediaInfoContainer',
  'mediaInfoSize',
  'mediaInfoDuration',
  'mediaInfoBitrate',
  'mediaInfoFile',
  'mediaInfoVideo',
  'mediaInfoAudio',
  'mediaInfoSubtitles',
  'mediaInfoChannels',
  'mediaInfoDefault',
  'mediaInfoUnavailable',
];

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('l10n/app_$name.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('tutte le chiavi del piano 24b ci sono, non vuote, in it ed en', () {
    for (final lang in ['it', 'en']) {
      final arb = _arb(lang);
      for (final key in _keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$lang: manca $key');
        expect((value as String).trim(), isNotEmpty, reason: '$lang: $key vuota');
      }
    }
  });

  test('testi italiani e plurali', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.itemActionReport, 'Segnala un problema…');
    expect(it.itemActionSubtitles, 'Sottotitoli…');
    expect(it.reportLevelSeason(2), 'Stagione 2');
    expect(it.reportLevelEpisode(1, 4), 'S1:E4');
    expect(it.reportSent, 'Segnalazione inviata agli admin');
    expect(it.reportLimitReached,
        'Hai già 20 segnalazioni aperte: aspetta che gli admin ne chiudano qualcuna');
    expect(it.inboxReportPending('Luigi'), 'Luigi ha segnalato un problema');
    expect(it.inboxReportFixed('Dark'), 'Problema sistemato su Dark');
    expect(it.inboxReportCannotFix('Dark'), 'Non è stato possibile sistemare Dark');
    expect(it.reportsOpenTitle, 'Segnalazioni aperte');
    expect(it.subtitlesDownloads(1), '1 download');
    expect(it.subtitlesDownloads(3), '3 download');
    expect(it.subtitlesWaiting, 'Aspetto che Jellyfin aggiunga la traccia…');
    expect(it.mediaInfoVersion('4K'), 'Versione: 4K');
    expect(it.mediaInfoChannels(6), '6 canali');

    expect(en.reportsOpenTitle, 'Open reports');
    expect(en.subtitlesDownloads(1), '1 download');
    expect(en.subtitlesDownloads(3), '3 downloads');
    expect(en.reportLevelEpisode(1, 4), 'S1:E4');
    expect(en.reportLevelSeason(2), 'Season 2');
  });
}
