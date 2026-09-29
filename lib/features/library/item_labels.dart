import '../../core/jellyfin/item_models.dart';

/// "2h 46m", "45m", "2h".
String formatRuntime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
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
