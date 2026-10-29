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
}
