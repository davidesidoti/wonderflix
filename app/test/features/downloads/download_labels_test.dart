import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/core/downloads/downloads_api.dart';
import 'package:wonderflix/features/downloads/download_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/download_fakes.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() => initializeDateFormatting('it'));

  test('GigabytesUseTheItalianComma', () {
    expect(formatGb(it, 1890000000), '1,89 GB');
    expect(formatGb(en, 1890000000), '1.89 GB');
  });

  test('TheChoiceExplainsItself', () {
    final text = choiceWhy(
      it,
      DownloadCandidate(
        rank: 1,
        release: testRelease(score: 150),
        isChoice: true,
        wouldImport: true,
      ),
    );
    expect(text, contains('150'));
    expect(text, contains('1080p'));
  });

  test('TooSmallShowsTheRate', () {
    final rejected = DownloadRejected(
      release: testRelease(),
      reason: RejectedReason.tooSmall,
      detail: '0.62',
    );
    expect(rejectedLabel(it, rejected), '0,62 GB/ora, sotto la soglia');
    expect(rejectedLabel(en, rejected), contains('0.62'));
    final arr = DownloadRejected(
      release: testRelease(),
      reason: RejectedReason.arr,
      detail: 'Not an upgrade',
    );
    expect(rejectedLabel(it, arr), 'Not an upgrade');
  });

  test('FailuresAndReasonsHaveTexts', () {
    expect(
      downloadsFailureLabel(it, DownloadsFailure.busy),
      'Un altro download di questo titolo è in corso: riprova tra poco',
    );
    expect(
      downloadsFailureLabel(it, DownloadsFailure.arrUnavailable),
      'Radarr o Sonarr non rispondono',
    );
    expect(
      downloadsFailureLabel(it, DownloadsFailure.refused),
      contains('qBittorrent'),
    );
    expect(
      downloadsFailureLabel(it, DownloadsFailure.expired),
      'Questa release non c\'è più: ricerca di nuovo',
    );
    expect(
      downloadReasonLabel(it, DownloadReason.searchFailed),
      'ricerca non riuscita',
    );
    expect(
      downloadReasonLabel(it, DownloadReason.grabRefused),
      contains('qBittorrent'),
    );
  });

  test('StatesAndNextSearch', () {
    DownloadItem item(DownloadState s, [DownloadReason? r]) => DownloadItem(
      key: 'movie:1',
      kind: DownloadKind.movie,
      title: 'Film',
      state: s,
      reason: r,
      availableSince: DateTime.utc(2026, 10, 1),
    );
    expect(downloadStateLabel(it, item(DownloadState.waiting)), 'In attesa');
    expect(
      downloadStateLabel(it, item(DownloadState.downloading)),
      'In download',
    );
    expect(
      downloadStateLabel(it, item(DownloadState.upgradeWatch)),
      'Cerca un upgrade',
    );
    expect(
      downloadStateLabel(
        it,
        item(DownloadState.needsYou, DownloadReason.nothingFound),
      ),
      'Serve te: nessun file valido',
    );

    final now = DateTime(2026, 10, 28, 10);
    expect(nextSearchLabel(it, null, now), '');
    expect(
      nextSearchLabel(it, now.add(const Duration(hours: 3)), now),
      'prossima ricerca tra 3 h',
    );
    expect(
      nextSearchLabel(it, DateTime(2026, 10, 29, 12), now),
      'prossima ricerca domani',
    );
    expect(
      nextSearchLabel(it, DateTime(2026, 11, 2, 12), now),
      contains('2 nov'),
    );
  });

  group('downloadExplanation', () {
    DownloadItem item(
      DownloadReason reason, {
      DownloadState state = DownloadState.needsYou,
      DownloadSummary? summary,
    }) =>
        DownloadItem(
          key: 'movie:1',
          kind: DownloadKind.movie,
          title: 'Film',
          state: state,
          reason: reason,
          availableSince: DateTime(2026, 10, 1),
          summary: summary,
        );

    DownloadSummary summary(
      int found, {
      int? best,
      int tooSmall = 0,
      int arrRejected = 0,
      String? top,
      bool stopgap = false,
    }) =>
        DownloadSummary(
          found: found,
          bestScore: best,
          minScore: 100,
          tooSmall: tooSmall,
          arrRejected: arrRejected,
          topRejection: top,
          stopgapAvailable: stopgap,
        );

    test('punteggio basso', () {
      expect(
        downloadExplanation(
            it,
            item(DownloadReason.belowMinScore,
                summary: summary(6, best: 40)),
            'Radarr'),
        it.downloadsExplainLowScore(6, 40, 100),
      );
    });

    test('tutti scartati, con il tappabuchi', () {
      final text = downloadExplanation(
          it,
          item(DownloadReason.nothingFound,
              summary: summary(14,
                  tooSmall: 9, arrRejected: 5, top: 'Not English', stopgap: true)),
          'Radarr');
      expect(text, contains('9 troppo piccoli'));
      expect(text, contains('5 rifiutati da Radarr (Not English)'));
      expect(text, contains(it.downloadsExplainStopgapHint));
    });

    test('nessun risultato', () {
      expect(
        downloadExplanation(
            it, item(DownloadReason.nothingFound, summary: summary(0)), 'Radarr'),
        it.downloadsExplainNoResults,
      );
    });

    test('import bloccato', () {
      expect(downloadExplanation(it, item(DownloadReason.importBlocked), 'Sonarr'),
          it.downloadsExplainBlocked('Sonarr'));
    });

    test('rifiutato dal client', () {
      expect(downloadExplanation(it, item(DownloadReason.grabRefused), 'Radarr'),
          it.downloadsExplainRefused);
    });

    test('in attesa: niente', () {
      expect(
          downloadExplanation(
              it,
              item(DownloadReason.searchFailed, state: DownloadState.waiting),
              'Radarr'),
          '');
    });
  });
}
