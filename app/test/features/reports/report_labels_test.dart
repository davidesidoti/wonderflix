import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/reports/report_models.dart';
import 'package:wonderflix/features/reports/report_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('episodio S2 E3', () {
    expect(
        reportLevelLabel(l, ReportItemType.episode, season: 2, episode: 3),
        'S2 E3');
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
        'Dark · S2 E3 · Sottotitoli');
  });

  test('episodio senza numeri: solo titolo e tipo', () {
    expect(
        reportTitleLine(l,
            title: 'Dark',
            itemType: ReportItemType.episode,
            type: ReportType.audioVideo),
        'Dark · Audio o video');
  });

  test('tipo sconosciuto: Altro', () {
    expect(reportTypeLabel(l, null), 'Altro');
  });
}
