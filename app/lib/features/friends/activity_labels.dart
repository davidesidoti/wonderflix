import '../../core/social/activity_models.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// "Sta guardando Dune", "Sta guardando The Bear · S2 E3" (spec O §7.2):
/// senza stagione o numero solo la serie, senza serie il nome
/// dell'episodio.
String friendNowPlayingText(AppLocalizations l, FriendNowPlaying playing) {
  final series = playing.seriesName;
  if (series == null || series.isEmpty) return l.friendsWatching(playing.title);
  final season = playing.season;
  final episode = playing.episode;
  return season != null && episode != null
      ? l.friendsWatchingEpisode(series, season, episode)
      : l.friendsWatching(series);
}

/// "Luca", "Garg e CaptainC", "Garg e altri 2": chi l'ha visto è già dal più
/// recente (spec O §7.4, piano 21b decisione 6; Home spec §7).
String friendsWatchedNames(AppLocalizations l, List<FriendWatcher> by) =>
    switch (by) {
      [] => '',
      [final one] => one.name,
      [final first, final second] => l.friendsNamesTwo(first.name, second.name),
      [final first, ...final others] =>
        l.friendsNamesMany(first.name, others.length),
    };
