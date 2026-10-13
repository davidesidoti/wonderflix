import '../../core/jellyfin/display_preferences_api.dart';
import '../social/social_providers.dart';

/// Le righe della Home (spec M §6.1), nell'ordine predefinito: l'id è quello
/// salvato dal plugin e nelle `DisplayPreferences`.
enum HomeRowKind {
  resume('resume'),
  nextUp('nextUp'),
  recommended('recommended'),
  friendsWatched('friendsWatched'),
  requests('requests'),
  latestMovies('latestMovies'),
  latestSeries('latestSeries'),
  becauseYouWatched('becauseYouWatched'),
  continueSaga('continueSaga'),
  upcomingSeries('upcomingSeries'),
  upcomingMovies('upcomingMovies'),
  myList('myList');

  const HomeRowKind(this.id);

  final String id;

  /// `null` per un id sconosciuto (maiuscole comprese).
  static HomeRowKind? parse(String id) {
    for (final row in values) {
      if (row.id == id) return row;
    }
    return null;
  }

  /// Le righe che vengono da Jellyfin: se falliscono tutte, insieme al
  /// carosello, la Home mostra l'errore (spec M §8.2 punto 4).
  bool get fromJellyfin => switch (this) {
        requests || recommended || friendsWatched || upcomingSeries || upcomingMovies => false,
        _ => true,
      };
}

/// Righe dagli id, senza sconosciuti e doppioni, nell'ordine dato.
List<HomeRowKind> parseHomeRows(Iterable<String> ids) {
  final rows = <HomeRowKind>[];
  for (final id in ids) {
    final row = HomeRowKind.parse(id);
    if (row != null && !rows.contains(row)) rows.add(row);
  }
  return rows;
}

/// L'ordine delle righe (spec M §6.4 punto 1; decisione 2 del piano 19b):
/// prima le righe di [user] che sono in [admin], nell'ordine dell'utente;
/// ogni altra riga di [admin] va dopo l'ultima, nell'elenco, delle righe che
/// la precedono in [admin], oppure in testa.
List<HomeRowKind> homeRowOrder(
    {required List<HomeRowKind> admin, required List<HomeRowKind> user}) {
  final order = [
    for (final row in user)
      if (admin.contains(row)) row,
  ];
  for (final (index, row) in admin.indexed) {
    if (order.contains(row)) continue;
    var at = 0;
    for (final (position, placed) in order.indexed) {
      if (admin.indexOf(placed) < index) at = position + 1;
    }
    order.insert(at, row);
  }
  return order;
}

/// Perché una riga può non esserci (spec M §6.5); il motivo serve alle
/// impostazioni (piano 19c).
enum HomeRowGate {
  available,

  /// Il plugin non ha Seerr.
  seerrOff,

  /// L'utente non è collegato a Seerr.
  noSeerrAccount,

  /// Il plugin non ha le saghe (prima della 1.5.0).
  sagasOff,

  /// Il plugin non ha Sonarr configurato.
  sonarrOff,

  /// Il plugin non ha Radarr configurato.
  radarrOff,

  /// Il plugin non ha i consigli (prima della 1.8.0, o senza accesso ai watch
  /// party).
  recommendationsOff,

  /// Il plugin non ha l'attività degli amici (prima della 1.9.0, o senza
  /// accesso ai watch party).
  friendsActivityOff,
}

HomeRowGate homeRowGate(HomeRowKind row, SocialFeatures features,
        {required bool seerrAccount}) =>
    switch (row) {
      HomeRowKind.requests when !features.requests => HomeRowGate.seerrOff,
      HomeRowKind.requests when !seerrAccount => HomeRowGate.noSeerrAccount,
      HomeRowKind.continueSaga when !features.collections =>
        HomeRowGate.sagasOff,
      HomeRowKind.upcomingSeries when !features.upcomingSeries =>
        HomeRowGate.sonarrOff,
      HomeRowKind.upcomingMovies when !features.upcomingMovies =>
        HomeRowGate.radarrOff,
      HomeRowKind.recommended when !features.recommendations =>
        HomeRowGate.recommendationsOff,
      HomeRowKind.friendsWatched when !features.friendsActivity =>
        HomeRowGate.friendsActivityOff,
      _ => HomeRowGate.available,
    };

/// La Home combinata (spec M §6.4).
class HomeLayout {
  const HomeLayout(
      {required this.order, required this.hidden, required this.visible});

  /// Le righe accese dall'admin nell'ordine dell'utente (punto 1): quello
  /// che mostra l'elenco delle impostazioni.
  final List<HomeRowKind> order;

  /// Le righe che l'utente ha nascosto.
  final Set<HomeRowKind> hidden;

  /// Quelle da mostrare (punto 2): non nascoste e disponibili.
  final List<HomeRowKind> visible;
}

/// [adminRows] `null`: mai impostata, tutte le righe accese.
HomeLayout composeHomeLayout({
  required List<String>? adminRows,
  required HomeUserPrefs user,
  required bool Function(HomeRowKind row) available,
}) {
  final admin = adminRows == null ? HomeRowKind.values : parseHomeRows(adminRows);
  final order = homeRowOrder(admin: admin, user: parseHomeRows(user.rows));
  final hidden = parseHomeRows(user.hidden).toSet();
  return HomeLayout(
    order: order,
    hidden: hidden,
    visible: [
      for (final row in order)
        if (!hidden.contains(row) && available(row)) row,
    ],
  );
}
