import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/reports/report_models.dart';
import 'package:wonderflix/features/reports/report_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/report_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('episodio S2:E3', () {
    expect(
        reportLevelLabel(l, ReportItemType.episode, season: 2, episode: 3),
        'S2:E3');
  });

  test('stagione 0 è Speciali', () {
    expect(reportLevelLabel(l, ReportItemType.season, season: 0), 'Speciali');
    expect(
        reportLevelLabel(l, ReportItemType.season, season: 2), 'Stagione 2');
    expect(reportLevelLabel(l, ReportItemType.season), '');
  });

  test('serie intera', () {
    expect(reportLevelLabel(l, ReportItemType.series), 'Tutta la serie');
  });

  test('film senza livello', () {
    expect(reportLevelLabel(l, ReportItemType.movie), '');
    expect(reportLevelLabel(l, null), '');
  });

  test('riga con titolo, livello e tipo', () {
    expect(
        reportTitleLine(l,
            title: 'Dark',
            itemType: ReportItemType.episode,
            season: 2,
            episode: 3,
            type: ReportType.subtitles),
        'Dark · S2:E3 · Sottotitoli');
  });

  test('episodio senza numeri: solo titolo e tipo', () {
    expect(
        reportTitleLine(l,
            title: 'Dark',
            itemType: ReportItemType.episode,
            type: ReportType.audioVideo),
        'Dark · Audio o video');
  });

  test('icone ed esempi dei quattro tipi', () {
    expect(reportTypeIcon(ReportType.subtitles), LucideIcons.captions);
    expect(reportTypeIcon(ReportType.metadata), LucideIcons.fileText);
    expect(reportTypeIcon(ReportType.audioVideo), LucideIcons.monitorPlay);
    expect(reportTypeIcon(ReportType.other), LucideIcons.messageSquare);
    expect(reportTypeExample(l, ReportType.metadata),
        'Nome, trama o locandina sbagliati');
    expect(reportTypeExample(l, ReportType.other),
        'Qualcos\'altro: scrivilo nella nota');
  });

  test('tipo sconosciuto: Altro', () {
    expect(reportTypeLabel(l, null), 'Altro');
  });

  test('riga del soggetto', () {
    expect(
        reportSubjectLine(
            l,
            testReport(
                itemType: ReportItemType.episode,
                seasonNumber: 1,
                episodeNumber: 4,
                itemName: 'La scatola',
                type: ReportType.subtitles)),
        'S1:E4 La scatola · Sottotitoli');
    expect(
        reportSubjectLine(
            l,
            testReport(
                itemType: ReportItemType.series, type: ReportType.metadata)),
        'Tutta la serie · Titolo o informazioni');
    expect(
        reportSubjectLine(
            l,
            testReport(
                itemType: ReportItemType.season,
                seasonNumber: 1,
                type: ReportType.audioVideo)),
        'Stagione 1 · Audio o video');
    expect(
        reportSubjectLine(
            l,
            testReport(
                itemType: ReportItemType.movie, type: ReportType.other)),
        'Altro');
    expect(
        reportSubjectLine(
            l,
            testReport(
                itemType: ReportItemType.episode,
                seasonNumber: 1,
                episodeNumber: 4,
                itemName: 'La scatola'),
            withType: false),
        'S1:E4 La scatola');
  });
}
