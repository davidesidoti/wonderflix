import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// "2h 46m", "45m", "2h".
String formatRuntime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// "18 min" sotto l'ora (minuti per eccesso), da un'ora in su "1h 15m".
String shortDuration(AppLocalizations l, Duration d) {
  final minutes = (d.inSeconds / 60).ceil();
  return minutes < 60
      ? l.ticketMinutes(minutes)
      // 59m30s arrotonda a "1h", non a "60 min".
      : formatRuntime(
          d < const Duration(hours: 1) ? const Duration(hours: 1) : d,
        );
}

/// "23:14" oppure "1:02:03".
String formatClock(Duration duration) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

/// "S1:E4" per gli episodi, `null` per il resto.
String? episodeCode(JellyfinItem item) {
  final episode = item.indexNumber;
  if (item.kind != ItemKind.episode || episode == null) return null;
  final season = item.parentIndexNumber;
  return season == null ? 'E$episode' : 'S$season:E$episode';
}

/// Titolo principale di una card: per gli episodi è il nome della serie.
String cardTitle(JellyfinItem item) =>
    item.kind == ItemKind.episode ? (item.seriesName ?? item.name) : item.name;

/// Riga secondaria: "S1:E4 · Titolo" per gli episodi, l'anno per il resto.
String? cardSubtitle(JellyfinItem item) {
  if (item.kind == ItemKind.episode) {
    final code = episodeCode(item);
    return code == null ? item.name : '$code · ${item.name}';
  }
  return item.productionYear?.toString();
}

/// Sottotitolo delle finestre su un titolo: "L'Istituto · S1:E4 La scatola",
/// "L'Istituto · Stagione 1", "The Wrestler · Film · 2008". Parti vuote saltate.
String itemContextLine(AppLocalizations l, JellyfinItem item) {
  final year = item.productionYear?.toString();
  final parts = switch (item.kind) {
    ItemKind.episode => [
      item.seriesName,
      [episodeCode(item), item.name].whereType<String>().join(' '),
    ],
    ItemKind.season => [item.seriesName, item.name],
    ItemKind.movie => [item.name, l.dialogKindMovie, year],
    ItemKind.series => [item.name, l.dialogKindSeries, year],
    _ => [item.name],
  };
  return parts.whereType<String>().where((p) => p.isNotEmpty).join(' · ');
}
