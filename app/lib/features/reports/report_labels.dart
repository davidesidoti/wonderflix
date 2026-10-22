import '../../core/reports/report_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// "Tutta la serie", "Stagione 2", "S2 E3"; vuoto per un film o quando
/// mancano i numeri.
String reportLevelLabel(
  AppLocalizations l,
  ReportItemType? type, {
  int? season,
  int? episode,
}) =>
    switch (type) {
      ReportItemType.series => l.reportLevelSeries,
      ReportItemType.season when season == 0 => l.reportLevelSpecials,
      ReportItemType.season when season != null => l.reportLevelSeason(season),
      ReportItemType.episode when season != null && episode != null =>
        l.reportLevelEpisode(season, episode),
      _ => '',
    };

/// Il tipo di problema nella lingua dell'app; `null` (valore sconosciuto) è
/// "Altro".
String reportTypeLabel(AppLocalizations l, ReportType? type) => switch (type) {
      ReportType.subtitles => l.reportTypeSubtitles,
      ReportType.metadata => l.reportTypeMetadata,
      ReportType.audioVideo => l.reportTypeAudioVideo,
      ReportType.other || null => l.reportTypeOther,
    };

/// "Titolo · livello · tipo", senza le parti vuote.
String reportTitleLine(
  AppLocalizations l, {
  required String title,
  ReportItemType? itemType,
  int? season,
  int? episode,
  ReportType? type,
}) =>
    [
      title,
      reportLevelLabel(l, itemType, season: season, episode: episode),
      if (type != null) reportTypeLabel(l, type),
    ].where((part) => part.isNotEmpty).join(' · ');
