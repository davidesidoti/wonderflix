import '../../core/jellyfin/item_models.dart';
import '../../core/requests/requests_models.dart';
import '../../core/social/activity_models.dart';
import '../../core/social/collections_models.dart';
import '../../core/social/home_models.dart';
import '../../core/social/recommendation_models.dart';

/// Cosa mostra una riga della Home (spec M §8.3). Una riga vuota non si
/// vede.
sealed class HomeRowContent {
  const HomeRowContent();

  bool get isEmpty;
}

/// Titoli della libreria: Continua a guardare, Prossimi episodi, Aggiunti
/// di recente, La mia lista.
final class ItemsRowContent extends HomeRowContent {
  const ItemsRowContent(this.items);

  final List<JellyfinItem> items;

  @override
  bool get isEmpty => items.isEmpty;
}

/// "Perché hai visto X": il titolo di partenza e i simili non visti.
final class BecauseYouWatchedContent extends HomeRowContent {
  const BecauseYouWatchedContent({required this.sourceName, required this.items});

  final String sourceName;
  final List<JellyfinItem> items;

  @override
  bool get isEmpty => items.isEmpty;
}

/// "Le mie richieste".
final class RequestsRowContent extends HomeRowContent {
  const RequestsRowContent(this.requests);

  final List<MediaRequest> requests;

  @override
  bool get isEmpty => requests.isEmpty;
}

/// "Continua la saga".
final class SagasRowContent extends HomeRowContent {
  const SagasRowContent(this.sagas);

  final List<SagaProgress> sagas;

  @override
  bool get isEmpty => sagas.isEmpty;
}

/// "Serie in arrivo".
final class UpcomingSeriesRowContent extends HomeRowContent {
  const UpcomingSeriesRowContent(this.episodes);

  final List<UpcomingEpisode> episodes;

  @override
  bool get isEmpty => episodes.isEmpty;
}

/// "Film in arrivo".
final class UpcomingMoviesRowContent extends HomeRowContent {
  const UpcomingMoviesRowContent(this.movies);

  final List<UpcomingMovie> movies;

  @override
  bool get isEmpty => movies.isEmpty;
}

/// "Consigliati per te" (spec N §7.3).
final class RecommendedRowContent extends HomeRowContent {
  const RecommendedRowContent(this.titles);

  final List<RecommendedItem> titles;

  @override
  bool get isEmpty => titles.isEmpty;
}

/// Un titolo consigliato, con chi l'ha consigliato.
class RecommendedItem {
  const RecommendedItem({required this.item, required this.from});

  final JellyfinItem item;
  final List<RecommendationSender> from;
}

/// "Visti dagli amici" (spec O §7.4).
final class FriendsWatchedRowContent extends HomeRowContent {
  const FriendsWatchedRowContent(this.titles);

  final List<FriendsWatchedItem> titles;

  @override
  bool get isEmpty => titles.isEmpty;
}

class FriendsWatchedItem {
  const FriendsWatchedItem({required this.item, required this.by});

  final JellyfinItem item;
  final List<FriendWatcher> by;
}

/// Una saga da continuare: il prossimo film da vedere e quanti sono visti.
class SagaProgress {
  const SagaProgress(
      {required this.saga, required this.next, required this.watched});

  final CollectionSummary saga;
  final JellyfinItem next;
  final int watched;

  /// I titoli della saga che l'utente vede.
  int get total => saga.size;
}
