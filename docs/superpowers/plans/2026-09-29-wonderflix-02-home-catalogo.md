# WonderFlix — Piano 2: Home e catalogo

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dopo il login, l'utente naviga tutta la libreria Film/Serie di WonderFlix:
- Home con righe;
- catalogo con filtri;
- schede di dettaglio di film e serie (stagioni ed episodi), pagina attore;
- ricerca, La mia lista, visto/non visto;
- trailer remoti;
- Impostazioni con la lingua.

I dati restano aggiornati anche quando cambiano da altri dispositivi (WebSocket). La riproduzione vera arriva nel Piano 3: in questo piano i pulsanti "Riproduci" passano da un unico punto (`playItem`), che per ora mostra un avviso.

**Architecture:** si estende il Piano 1 con la stessa divisione a strati.
- **`lib/core/jellyfin/`:** modelli degli elementi, `ItemQuery`, `LibraryApi` scritto a mano, costruttore degli URL delle immagini, client WebSocket (`ServerEventsClient`).
- **`lib/features/library/`:** provider Riverpod condivisi:
  - utente corrente, API;
  - revisione della libreria (sale quando il server segnala modifiche);
  - "override" dei dati utente, per aggiornare preferiti e visti ovunque senza ricaricare.
- **`lib/ui/`:** widget riutilizzabili (immagine con blurhash, card poster/orizzontale, riga scorrevole, pulsanti, stati di caricamento ed errore).
- **Una cartella per schermata** in `lib/features/*`.
- **Router e barra superiore** vengono estesi per ultimi, quando tutte le schermate esistono.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, dio 5, cached_network_image, flutter_blurhash, lucide_icons_flutter, dart:io WebSocket; test con flutter_test, fake_async, mocktail (solo dove già usato) e un `FakeLibraryApi` scritto a mano.

**Spec:** `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md` (sezioni 4 e 6). **Piano precedente:** `docs/superpowers/plans/2026-09-29-wonderflix-01-fondamenta-login.md`.

---

## Regole per chi esegue

- **Commit:** fatti con l'identità git già configurata (quella dell'utente). **MAI** aggiungere trailer `Co-Authored-By` o righe "Generated with…". Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde. Se `lib/l10n/gen` manca, esegui prima `flutter gen-l10n`.
- **Icone:** solo `LucideIcons` (`package:lucide_icons_flutter/lucide_icons.dart`), niente emoji. Se un nome di icona usato nel piano non esiste nella versione installata, cerca il nome corretto nel sorgente del pacchetto (`lib/lucide_icons.dart` nella pub cache), usa l'icona equivalente e segnalalo.
- **Widget test:** il font dei test ha glifi molto più larghi di quelli reali. Se una `Row` va in overflow **solo nei test**, correggi al minimo con `Flexible`/`Wrap` e segnalalo.
- **Test su `LibraryApi`:** usa `FakeLibraryApi` (Task 10), non mocktail.
- **Riferimento API:** `docs/reference/jellyfin-openapi-10.11.9.json` (Task 1). Per dubbi su parametri o campi, cerca lì dentro.

## Mappa dei file

```
docs/reference/jellyfin-openapi-10.11.9.json
lib/core/jellyfin/api_exception.dart        (+ RequestCancelledException)
lib/core/jellyfin/jellyfin_http.dart        (+ delete, cancelToken)
lib/core/jellyfin/item_models.dart          JellyfinItem, ItemKind, UserItemData, PersonRef, TrailerLink, ItemPage, LibraryFilters
lib/core/jellyfin/image_urls.dart           ImageRef, ImageUrls
lib/core/jellyfin/item_query.dart           ItemQuery, CatalogSort, WatchedFilter, cardImageParams
lib/core/jellyfin/library_api.dart          LibraryApi
lib/core/jellyfin/server_events.dart        ServerEvent, parseServerMessage, ServerEventsClient
lib/features/library/item_labels.dart       formatRuntime, formatClock, episodeCode, cardTitle, cardSubtitle
lib/features/library/library_providers.dart currentUserIdProvider, libraryApiProvider, imageUrlsProvider, libraryRevisionProvider
lib/features/library/user_data.dart         UserDataOverrides, userDataOverridesProvider, watchUserData
lib/features/library/server_events_binding.dart serverEventsClientProvider, serverEventsBindingProvider
lib/ui/wf_image.dart                        imageBuilderProvider, WfImage, ImagePlaceholder
lib/ui/wf_buttons.dart                      WfButton, WfIconToggle
lib/ui/poster_card.dart                     PosterCard (+ ProgressStrip, WatchedBadge)
lib/ui/landscape_card.dart                  LandscapeCard
lib/ui/media_row.dart                       MediaRow
lib/ui/states.dart                          SkeletonBox, LoadingView, ErrorView
lib/app/navigation.dart                     itemRoute, openItem, openPerson
lib/features/playback/play_launcher.dart    playItem (collegato al player nel Piano 3)
lib/features/home/home_data.dart            HomeData, loadHome, pickFeatured, homeProvider
lib/features/home/hero_carousel.dart        HeroCarousel
lib/features/home/home_screen.dart          HomeScreen (sostituisce il segnaposto del Piano 1)
lib/features/catalog/catalog_controller.dart CatalogState, CatalogController, catalogFiltersProvider
lib/features/catalog/catalog_filters_bar.dart CatalogFiltersBar
lib/features/catalog/catalog_screen.dart    CatalogScreen
lib/features/detail/detail_providers.dart   itemProvider, similarProvider, seasonsProvider, episodesProvider, seriesNextEpisodeProvider
lib/features/detail/primary_action.dart     PrimaryAction, primaryActionFor, primaryActionLabel
lib/features/detail/detail_header.dart      DetailHeader, MetaLine
lib/features/detail/detail_rows.dart        CastRow, SimilarRow
lib/features/detail/movie_detail_view.dart  MovieDetailView
lib/features/detail/series_detail_view.dart SeriesDetailView, EpisodeTile
lib/features/detail/item_detail_screen.dart ItemDetailScreen
lib/features/person/person_screen.dart      filmographyProvider, PersonScreen
lib/features/search/search_controller.dart  SearchResults, SearchState, SearchController
lib/features/search/search_screen.dart      SearchScreen
lib/features/mylist/my_list_screen.dart     favoritesProvider, MyListScreen
lib/features/settings/locale_controller.dart LocaleController, localeProvider
lib/features/settings/settings_screen.dart  SettingsScreen
lib/app/back_navigation.dart                BackNavigationHandler
lib/app/router.dart, lib/app/app_shell.dart, lib/app/app.dart   (modificati)
l10n/app_it.arb, l10n/app_en.arb            (nuove stringhe)
test/support/library_fakes.dart             FakeLibraryApi, testItem, pageOf
test/support/pump_app.dart                  (override di immagini e WebSocket)
```

---

### Task 1: dipendenze e riferimento API

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`
- Create: `docs/reference/jellyfin-openapi-10.11.9.json`

- [ ] **Step 1: dipendenze**

```bash
flutter pub add cached_network_image flutter_blurhash
```
Expected: `Changed N dependencies!`.

- [ ] **Step 2: spec OpenAPI di riferimento**

```bash
mkdir -p docs/reference
curl -sSL -o docs/reference/jellyfin-openapi-10.11.9.json "https://repo.jellyfin.org/files/openapi/stable/jellyfin-openapi-10.11.9.json"
head -c 120 docs/reference/jellyfin-openapi-10.11.9.json
```
Expected: l'inizio del JSON con `"version": "10.11.9"` (circa 2 MB).

- [ ] **Step 3: verifica e commit**

```bash
flutter analyze && flutter test
git add pubspec.yaml pubspec.lock docs/reference
git commit -m "chore: add image caching deps and Jellyfin 10.11.9 API reference"
```

---

### Task 2: `JellyfinHttp` con DELETE e annullamento

**Files:**
- Modify: `lib/core/jellyfin/api_exception.dart`, `lib/core/jellyfin/jellyfin_http.dart`
- Test: `test/core/jellyfin/jellyfin_http_test.dart` (aggiunte)

- [ ] **Step 1: aggiungi i test** in fondo al `main()` di `test/core/jellyfin/jellyfin_http_test.dart` (aggiungi `import 'package:dio/dio.dart';` in testa se manca):

```dart
  test('delete usa il metodo DELETE', () async {
    await http.delete('/UserFavoriteItems/i1', query: {'userId': 'u1'});
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.queryParameters, {'userId': 'u1'});
  });

  test('richiesta annullata diventa RequestCancelledException', () async {
    final token = CancelToken()..cancel();
    await expectLater(http.get('/a', cancelToken: token),
        throwsA(isA<RequestCancelledException>()));
  });
```

- [ ] **Step 2: esegui**

Run: `flutter test test/core/jellyfin/jellyfin_http_test.dart`
Expected: FAIL (`delete` e `RequestCancelledException` non esistono).

- [ ] **Step 3: implementa**

In `lib/core/jellyfin/api_exception.dart`, dopo `ServerErrorException`, aggiungi:
```dart
/// Richiesta annullata dal client (es. una ricerca superata da una più recente).
final class RequestCancelledException extends ApiException {
  const RequestCancelledException();
}
```
e nello stesso file sostituisci il ramo `cancel` di `mapDioException`:
```dart
    case DioExceptionType.cancel:
      return const RequestCancelledException();
```

In `lib/core/jellyfin/jellyfin_http.dart` sostituisci i metodi `get` e `post` con:
```dart
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send(() => dio.get<dynamic>(path,
          queryParameters: query, cancelToken: cancelToken));

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send(() => dio.post<dynamic>(path, data: body, queryParameters: query));

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) =>
      _send(() => dio.delete<dynamic>(path, queryParameters: query));
```

- [ ] **Step 4: esegui tutti i test**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin test/core/jellyfin/jellyfin_http_test.dart
git commit -m "feat: support DELETE and request cancellation in JellyfinHttp"
```

---

### Task 3: modelli degli elementi

**Files:**
- Create: `lib/core/jellyfin/item_models.dart`
- Test: `test/core/jellyfin/item_models_test.dart`

- [ ] **Step 1: scrivi il test**

`test/core/jellyfin/item_models_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

void main() {
  test('film completo', () {
    final item = JellyfinItem.fromJson({
      'Id': 'm1',
      'Name': 'Dune: Parte Due',
      'Type': 'Movie',
      'Overview': 'Paul Atreides…',
      'ProductionYear': 2024,
      'OfficialRating': 'PG-13',
      'CommunityRating': 8.4,
      'RunTimeTicks': 99600000000,
      'Genres': ['Fantascienza', 'Avventura'],
      'ImageTags': {'Primary': 'p1', 'Logo': 'l1'},
      'BackdropImageTags': ['b1'],
      'ImageBlurHashes': {
        'Primary': {'p1': 'LEHV6nWB2yk8'},
      },
      'UserData': {
        'Played': false,
        'IsFavorite': true,
        'PlaybackPositionTicks': 13940000000,
        'PlayedPercentage': 14.0,
      },
      'People': [
        {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor', 'PrimaryImageTag': 'pp9'},
      ],
      'RemoteTrailers': [
        {'Url': 'https://youtube.com/watch?v=x', 'Name': 'Trailer'},
      ],
      'LocalTrailerCount': 1,
    });

    expect(item.kind, ItemKind.movie);
    expect(item.runtime, const Duration(hours: 2, minutes: 46));
    expect(item.genres, ['Fantascienza', 'Avventura']);
    expect(item.imageTags['Logo'], 'l1');
    expect(item.backdropTags, ['b1']);
    expect(item.blurHashes['Primary']?['p1'], 'LEHV6nWB2yk8');
    expect(item.userData.isFavorite, isTrue);
    expect(item.userData.playbackPosition, const Duration(minutes: 23, seconds: 14));
    expect(item.userData.progress, closeTo(0.14, 0.0001));
    expect(item.people.single.role, 'Chani');
    expect(item.remoteTrailers.single.url, 'https://youtube.com/watch?v=x');
    expect(item.localTrailerCount, 1);
  });

  test('episodio', () {
    final item = JellyfinItem.fromJson({
      'Id': 'e4',
      'Name': 'Please Hold to My Hand',
      'Type': 'Episode',
      'SeriesId': 's1',
      'SeriesName': 'The Last of Us',
      'SeasonId': 'se1',
      'IndexNumber': 4,
      'ParentIndexNumber': 1,
      'SeriesPrimaryImageTag': 'sp1',
      'ParentBackdropItemId': 's1',
      'ParentBackdropImageTags': ['sb1'],
    });
    expect(item.kind, ItemKind.episode);
    expect(item.seriesName, 'The Last of Us');
    expect(item.indexNumber, 4);
    expect(item.parentIndexNumber, 1);
    expect(item.parentBackdropTags, ['sb1']);
  });

  test('campi mancanti e tipo sconosciuto hanno valori di default', () {
    final item = JellyfinItem.fromJson({'Id': 'x', 'Type': 'Folder'});
    expect(item.kind, ItemKind.other);
    expect(item.name, '');
    expect(item.genres, isEmpty);
    expect(item.userData.played, isFalse);
    expect(item.userData.progress, isNull);
    expect(item.runtime, isNull);
  });

  test('progress è null se già visto', () {
    const data = UserItemData(played: true, playedPercentage: 50);
    expect(data.progress, isNull);
    expect(data.copyWith(played: false).progress, 0.5);
  });

  test('ItemKind.parse', () {
    expect(ItemKind.parse('Series'), ItemKind.series);
    expect(ItemKind.parse(''), ItemKind.other);
    expect(ItemKind.parse(null), ItemKind.other);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/core/jellyfin/item_models_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: implementa**

`lib/core/jellyfin/item_models.dart`:
```dart
/// Modelli della libreria Jellyfin (sottoinsieme di `BaseItemDto`).
library;

enum ItemKind {
  movie('Movie'),
  series('Series'),
  season('Season'),
  episode('Episode'),
  person('Person'),
  other('');

  const ItemKind(this.apiName);

  /// Valore di `Type` / `includeItemTypes` nell'API.
  final String apiName;

  static ItemKind parse(String? value) {
    for (final kind in values) {
      if (kind != other && kind.apiName == value) return kind;
    }
    return other;
  }
}

/// 1 tick Jellyfin = 100 ns.
Duration ticksToDuration(int ticks) => Duration(microseconds: ticks ~/ 10);

Map<String, String> _stringMap(Object? value) => value is Map
    ? {for (final e in value.entries) '${e.key}': '${e.value}'}
    : const {};

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

List<Map<String, dynamic>> _objectList(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList()
    : const [];

int? _int(Object? value) => (value as num?)?.toInt();

double? _double(Object? value) => (value as num?)?.toDouble();

/// Stato dell'utente su un elemento: visto, preferito, minutaggio.
class UserItemData {
  const UserItemData({
    this.played = false,
    this.isFavorite = false,
    this.playbackPositionTicks = 0,
    this.playedPercentage,
    this.unplayedItemCount,
  });

  factory UserItemData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserItemData();
    return UserItemData(
      played: json['Played'] as bool? ?? false,
      isFavorite: json['IsFavorite'] as bool? ?? false,
      playbackPositionTicks: _int(json['PlaybackPositionTicks']) ?? 0,
      playedPercentage: _double(json['PlayedPercentage']),
      unplayedItemCount: _int(json['UnplayedItemCount']),
    );
  }

  final bool played;
  final bool isFavorite;
  final int playbackPositionTicks;
  final double? playedPercentage;
  final int? unplayedItemCount;

  Duration get playbackPosition => ticksToDuration(playbackPositionTicks);

  /// Avanzamento 0–1; `null` se non iniziato o già visto.
  double? get progress {
    final percentage = playedPercentage;
    if (played || percentage == null || percentage <= 0) return null;
    return (percentage / 100).clamp(0.0, 1.0);
  }

  UserItemData copyWith({bool? played, bool? isFavorite}) => UserItemData(
        played: played ?? this.played,
        isFavorite: isFavorite ?? this.isFavorite,
        playbackPositionTicks: playbackPositionTicks,
        playedPercentage: playedPercentage,
        unplayedItemCount: unplayedItemCount,
      );
}

class PersonRef {
  const PersonRef({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });

  factory PersonRef.fromJson(Map<String, dynamic> json) => PersonRef(
        id: json['Id'] as String,
        name: json['Name'] as String? ?? '',
        role: json['Role'] as String?,
        type: json['Type'] as String?,
        primaryImageTag: json['PrimaryImageTag'] as String?,
      );

  final String id;
  final String name;
  final String? role;
  final String? type;
  final String? primaryImageTag;
}

class TrailerLink {
  const TrailerLink({required this.url, this.name});

  factory TrailerLink.fromJson(Map<String, dynamic> json) =>
      TrailerLink(url: json['Url'] as String, name: json['Name'] as String?);

  final String url;
  final String? name;
}

class JellyfinItem {
  const JellyfinItem({
    required this.id,
    required this.name,
    required this.kind,
    this.overview,
    this.productionYear,
    this.officialRating,
    this.communityRating,
    this.runTimeTicks,
    this.genres = const [],
    this.imageTags = const {},
    this.backdropTags = const [],
    this.blurHashes = const {},
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.seriesPrimaryImageTag,
    this.parentBackdropItemId,
    this.parentBackdropTags = const [],
    this.parentLogoItemId,
    this.parentLogoImageTag,
    this.parentThumbItemId,
    this.parentThumbImageTag,
    this.indexNumber,
    this.parentIndexNumber,
    this.userData = const UserItemData(),
    this.people = const [],
    this.remoteTrailers = const [],
    this.localTrailerCount = 0,
    this.childCount,
  });

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    final hashes = <String, Map<String, String>>{};
    final rawHashes = json['ImageBlurHashes'];
    if (rawHashes is Map) {
      for (final entry in rawHashes.entries) {
        hashes['${entry.key}'] = _stringMap(entry.value);
      }
    }
    return JellyfinItem(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? '',
      kind: ItemKind.parse(json['Type'] as String?),
      overview: json['Overview'] as String?,
      productionYear: _int(json['ProductionYear']),
      officialRating: json['OfficialRating'] as String?,
      communityRating: _double(json['CommunityRating']),
      runTimeTicks: _int(json['RunTimeTicks']),
      genres: _stringList(json['Genres']),
      imageTags: _stringMap(json['ImageTags']),
      backdropTags: _stringList(json['BackdropImageTags']),
      blurHashes: hashes,
      seriesId: json['SeriesId'] as String?,
      seriesName: json['SeriesName'] as String?,
      seasonId: json['SeasonId'] as String?,
      seriesPrimaryImageTag: json['SeriesPrimaryImageTag'] as String?,
      parentBackdropItemId: json['ParentBackdropItemId'] as String?,
      parentBackdropTags: _stringList(json['ParentBackdropImageTags']),
      parentLogoItemId: json['ParentLogoItemId'] as String?,
      parentLogoImageTag: json['ParentLogoImageTag'] as String?,
      parentThumbItemId: json['ParentThumbItemId'] as String?,
      parentThumbImageTag: json['ParentThumbImageTag'] as String?,
      indexNumber: _int(json['IndexNumber']),
      parentIndexNumber: _int(json['ParentIndexNumber']),
      userData: UserItemData.fromJson(json['UserData'] as Map<String, dynamic>?),
      people: _objectList(json['People']).map(PersonRef.fromJson).toList(),
      remoteTrailers:
          _objectList(json['RemoteTrailers']).map(TrailerLink.fromJson).toList(),
      localTrailerCount: _int(json['LocalTrailerCount']) ?? 0,
      childCount: _int(json['ChildCount']),
    );
  }

  final String id;
  final String name;
  final ItemKind kind;
  final String? overview;
  final int? productionYear;
  final String? officialRating;
  final double? communityRating;
  final int? runTimeTicks;
  final List<String> genres;

  /// Tipo immagine (`Primary`, `Logo`, `Thumb`…) → tag.
  final Map<String, String> imageTags;
  final List<String> backdropTags;

  /// Tipo immagine → (tag → blurhash).
  final Map<String, Map<String, String>> blurHashes;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final String? seriesPrimaryImageTag;
  final String? parentBackdropItemId;
  final List<String> parentBackdropTags;
  final String? parentLogoItemId;
  final String? parentLogoImageTag;
  final String? parentThumbItemId;
  final String? parentThumbImageTag;
  final int? indexNumber;
  final int? parentIndexNumber;
  final UserItemData userData;
  final List<PersonRef> people;
  final List<TrailerLink> remoteTrailers;
  final int localTrailerCount;

  /// Per le serie: numero di stagioni.
  final int? childCount;

  Duration? get runtime {
    final ticks = runTimeTicks;
    return ticks == null ? null : ticksToDuration(ticks);
  }
}

class ItemPage {
  const ItemPage(this.items, this.totalCount);

  final List<JellyfinItem> items;
  final int totalCount;
}

class LibraryFilters {
  const LibraryFilters({this.genres = const [], this.years = const []});

  final List<String> genres;

  /// Dal più recente al più vecchio.
  final List<int> years;
}
```

- [ ] **Step 4: esegui**

Run: `flutter test test/core/jellyfin/item_models_test.dart`
Expected: PASS (5 test).

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin/item_models.dart test/core/jellyfin/item_models_test.dart
git commit -m "feat: add Jellyfin library item models"
```

---

### Task 4: URL delle immagini ed etichette

**Files:**
- Create: `lib/core/jellyfin/image_urls.dart`, `lib/features/library/item_labels.dart`
- Test: `test/core/jellyfin/image_urls_test.dart`, `test/features/library/item_labels_test.dart`

- [ ] **Step 1: scrivi i test**

`test/core/jellyfin/image_urls_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

void main() {
  final urls = ImageUrls(Uri.parse('https://media.example.com/jf'));

  const movie = JellyfinItem(
    id: 'm1',
    name: 'Dune',
    kind: ItemKind.movie,
    imageTags: {'Primary': 'p1', 'Logo': 'l1', 'Thumb': 't1'},
    backdropTags: ['b1'],
    blurHashes: {
      'Primary': {'p1': 'HASH'},
    },
  );

  const episode = JellyfinItem(
    id: 'e1',
    name: 'Ep',
    kind: ItemKind.episode,
    imageTags: {'Primary': 'ep1'},
    seriesId: 's1',
    seriesPrimaryImageTag: 'sp1',
    parentBackdropItemId: 's1',
    parentBackdropTags: ['sb1'],
    parentLogoItemId: 's1',
    parentLogoImageTag: 'sl1',
  );

  test('poster del film con blurhash', () {
    final ref = urls.poster(movie)!;
    expect(ref.url,
        'https://media.example.com/jf/Items/m1/Images/Primary?tag=p1&maxWidth=400&quality=90');
    expect(ref.blurHash, 'HASH');
  });

  test('il poster di un episodio è quello della serie', () {
    expect(urls.poster(episode)!.url, contains('/Items/s1/Images/Primary?tag=sp1'));
  });

  test('sfondo proprio o del genitore', () {
    expect(urls.backdrop(movie)!.url, contains('/Items/m1/Images/Backdrop/0?tag=b1'));
    expect(urls.backdrop(episode)!.url, contains('/Items/s1/Images/Backdrop/0?tag=sb1'));
  });

  test('logo proprio o del genitore', () {
    expect(urls.logo(movie)!.url, contains('/Items/m1/Images/Logo?tag=l1'));
    expect(urls.logo(episode)!.url, contains('/Items/s1/Images/Logo?tag=sl1'));
  });

  test('immagine orizzontale: fotogramma per episodi, Thumb per i film', () {
    expect(urls.landscape(episode)!.url, contains('/Items/e1/Images/Primary?tag=ep1'));
    expect(urls.landscape(movie)!.url, contains('/Items/m1/Images/Thumb?tag=t1'));
  });

  test('senza immagini restituisce null', () {
    const bare = JellyfinItem(id: 'x', name: 'x', kind: ItemKind.movie);
    expect(urls.poster(bare), isNull);
    expect(urls.backdrop(bare), isNull);
    expect(urls.landscape(bare), isNull);
  });

  test('foto di una persona', () {
    const person = PersonRef(id: 'p9', name: 'Zendaya', primaryImageTag: 'pp9');
    expect(urls.person(person)!.url,
        'https://media.example.com/jf/Items/p9/Images/Primary?tag=pp9&maxWidth=240&quality=90');
    expect(urls.person(const PersonRef(id: 'p0', name: 'X')), isNull);
  });
}
```

`test/features/library/item_labels_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/library/item_labels.dart';

void main() {
  test('formatRuntime', () {
    expect(formatRuntime(const Duration(hours: 2, minutes: 46)), '2h 46m');
    expect(formatRuntime(const Duration(minutes: 45)), '45m');
    expect(formatRuntime(const Duration(hours: 2)), '2h');
  });

  test('formatClock', () {
    expect(formatClock(const Duration(minutes: 23, seconds: 14)), '23:14');
    expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  test('episodeCode, cardTitle, cardSubtitle', () {
    const ep = JellyfinItem(
      id: 'e',
      name: 'Please Hold',
      kind: ItemKind.episode,
      seriesName: 'The Last of Us',
      indexNumber: 4,
      parentIndexNumber: 1,
    );
    const movie = JellyfinItem(
        id: 'm', name: 'Dune', kind: ItemKind.movie, productionYear: 2024);
    expect(episodeCode(ep), 'S1:E4');
    expect(cardTitle(ep), 'The Last of Us');
    expect(cardSubtitle(ep), 'S1:E4 · Please Hold');
    expect(cardTitle(movie), 'Dune');
    expect(cardSubtitle(movie), '2024');
    expect(episodeCode(movie), isNull);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/core/jellyfin/image_urls_test.dart test/features/library/item_labels_test.dart`
Expected: FAIL (file mancanti).

- [ ] **Step 3: implementa**

`lib/core/jellyfin/image_urls.dart`:
```dart
import 'item_models.dart';

/// URL di un'immagine + blurhash per il segnaposto (se il server lo fornisce).
class ImageRef {
  const ImageRef(this.url, [this.blurHash]);

  final String url;
  final String? blurHash;
}

/// Costruisce gli URL delle immagini. Gli endpoint immagine di Jellyfin non
/// richiedono autenticazione, quindi nessun token finisce negli URL.
class ImageUrls {
  ImageUrls(Uri serverUrl) : _base = serverUrl.toString();

  final String _base;

  ImageRef _ref(
    JellyfinItem item,
    String ownerId,
    String type,
    String tag,
    int maxWidth, {
    int? index,
  }) {
    final path = index == null ? type : '$type/$index';
    return ImageRef(
      '$_base/Items/$ownerId/Images/$path?tag=$tag&maxWidth=$maxWidth&quality=90',
      item.blurHashes[type]?[tag],
    );
  }

  /// Locandina verticale 2:3. Per gli episodi usa quella della serie.
  ImageRef? poster(JellyfinItem item, {int maxWidth = 400}) {
    final seriesId = item.seriesId;
    final seriesTag = item.seriesPrimaryImageTag;
    if (item.kind == ItemKind.episode && seriesId != null && seriesTag != null) {
      return _ref(item, seriesId, 'Primary', seriesTag, maxWidth);
    }
    final tag = item.imageTags['Primary'];
    return tag == null ? null : _ref(item, item.id, 'Primary', tag, maxWidth);
  }

  ImageRef? backdrop(JellyfinItem item, {int maxWidth = 1920}) {
    if (item.backdropTags.isNotEmpty) {
      return _ref(item, item.id, 'Backdrop', item.backdropTags.first, maxWidth,
          index: 0);
    }
    final parentId = item.parentBackdropItemId;
    if (parentId != null && item.parentBackdropTags.isNotEmpty) {
      return _ref(item, parentId, 'Backdrop', item.parentBackdropTags.first,
          maxWidth,
          index: 0);
    }
    return null;
  }

  ImageRef? logo(JellyfinItem item, {int maxWidth = 600}) {
    final tag = item.imageTags['Logo'];
    if (tag != null) return _ref(item, item.id, 'Logo', tag, maxWidth);
    final parentId = item.parentLogoItemId;
    final parentTag = item.parentLogoImageTag;
    if (parentId != null && parentTag != null) {
      return _ref(item, parentId, 'Logo', parentTag, maxWidth);
    }
    return null;
  }

  /// Immagine 16:9: fotogramma per gli episodi, altrimenti Thumb o sfondo.
  ImageRef? landscape(JellyfinItem item, {int maxWidth = 640}) {
    if (item.kind == ItemKind.episode) {
      final primary = item.imageTags['Primary'];
      if (primary != null) return _ref(item, item.id, 'Primary', primary, maxWidth);
    }
    final thumb = item.imageTags['Thumb'];
    if (thumb != null) return _ref(item, item.id, 'Thumb', thumb, maxWidth);
    final parentThumbId = item.parentThumbItemId;
    final parentThumb = item.parentThumbImageTag;
    if (parentThumbId != null && parentThumb != null) {
      return _ref(item, parentThumbId, 'Thumb', parentThumb, maxWidth);
    }
    return backdrop(item, maxWidth: maxWidth);
  }

  ImageRef? person(PersonRef person, {int maxWidth = 240}) {
    final tag = person.primaryImageTag;
    if (tag == null) return null;
    return ImageRef(
        '$_base/Items/${person.id}/Images/Primary?tag=$tag&maxWidth=$maxWidth&quality=90');
  }
}
```

`lib/features/library/item_labels.dart`:
```dart
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
```

- [ ] **Step 4: esegui**

Run: `flutter test test/core/jellyfin/image_urls_test.dart test/features/library/item_labels_test.dart`
Expected: PASS (10 test).

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin/image_urls.dart lib/features/library/item_labels.dart test/core/jellyfin/image_urls_test.dart test/features/library/item_labels_test.dart
git commit -m "feat: add image URL builder and item labels"
```

---

### Task 5: `ItemQuery` e `LibraryApi`

**Files:**
- Create: `lib/core/jellyfin/item_query.dart`, `lib/core/jellyfin/library_api.dart`
- Test: `test/core/jellyfin/item_query_test.dart`, `test/core/jellyfin/library_api_test.dart`

- [ ] **Step 1: scrivi i test**

`test/core/jellyfin/item_query_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';

void main() {
  test('parametri di base', () {
    final params = const ItemQuery(kinds: {ItemKind.movie})
        .toQueryParameters(userId: 'u1', startIndex: 100, limit: 50);
    expect(params['userId'], 'u1');
    expect(params['recursive'], true);
    expect(params['includeItemTypes'], 'Movie');
    expect(params['sortBy'], 'SortName');
    expect(params['sortOrder'], 'Ascending');
    expect(params['startIndex'], 100);
    expect(params['limit'], 50);
    expect(params['enableTotalRecordCount'], true);
    expect(params.containsKey('genres'), isFalse);
    expect(params.containsKey('isPlayed'), isFalse);
  });

  test('filtri, ordinamento e ricerca', () {
    final params = const ItemQuery(
      kinds: {ItemKind.series, ItemKind.movie},
      sort: CatalogSort.year,
      genres: {'Dramma', 'Azione'},
      year: 2023,
      watched: WatchedFilter.unwatched,
      favoritesOnly: true,
      searchTerm: 'dune',
      personId: 'p9',
    ).toQueryParameters(userId: 'u1', startIndex: 0, limit: 20);
    expect(params['includeItemTypes'], 'Movie,Series');
    expect(params['sortBy'], 'ProductionYear,SortName');
    expect(params['sortOrder'], 'Descending');
    expect(params['genres'], 'Azione|Dramma');
    expect(params['years'], '2023');
    expect(params['isPlayed'], false);
    expect(params['isFavorite'], true);
    expect(params['searchTerm'], 'dune');
    expect(params['personIds'], 'p9');
  });

  test('data di aggiunta: per le serie usa l\'ultimo contenuto aggiunto', () {
    Map<String, dynamic> p(Set<ItemKind> kinds) =>
        ItemQuery(kinds: kinds, sort: CatalogSort.dateAdded)
            .toQueryParameters(userId: 'u', startIndex: 0, limit: 1);
    expect(p({ItemKind.movie})['sortBy'], 'DateCreated,SortName');
    expect(p({ItemKind.series})['sortBy'], 'DateLastContentAdded,SortName');
  });

  test('copyWith e hasFilters', () {
    const base = ItemQuery(kinds: {ItemKind.movie});
    expect(base.hasFilters, isFalse);
    final filtered = base.copyWith(year: 2020, watched: WatchedFilter.watched);
    expect(filtered.hasFilters, isTrue);
    expect(filtered.copyWith(year: null).year, isNull);
    expect(filtered.copyWith(sort: CatalogSort.rating).year, 2020);
  });
}
```

`test/core/jellyfin/library_api_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/library_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

Map<String, dynamic> itemsResult(List<String> ids, {int? total}) => {
      'Items': [
        for (final id in ids) {'Id': id, 'Name': 'N$id', 'Type': 'Movie'},
      ],
      'TotalRecordCount': total ?? ids.length,
    };

void main() {
  late FakeAdapter adapter;
  late LibraryApi api;

  setUp(() {
    adapter = FakeAdapter((_) => FakeResponse(200, itemsResult(['a', 'b'])));
    api = LibraryApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  RequestOptionsView last() => RequestOptionsView(adapter.requests.last);

  test('items usa ItemQuery e legge il totale', () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['a'], total: 250));
    final page = await api.items(const ItemQuery(kinds: {ItemKind.movie}),
        userId: 'u1', startIndex: 0, limit: 100);
    expect(last().path, '/Items');
    expect(last().query['includeItemTypes'], 'Movie');
    expect(page.items.single.id, 'a');
    expect(page.totalCount, 250);
  });

  test('resume e nextUp', () async {
    await api.resume('u1', limit: 10);
    expect(last().path, '/UserItems/Resume');
    expect(last().query['includeItemTypes'], 'Movie,Episode');
    expect(last().query['limit'], 10);

    await api.nextUp('u1', seriesId: 's1', limit: 1, enableResumable: true);
    expect(last().path, '/Shows/NextUp');
    expect(last().query['seriesId'], 's1');
    expect(last().query['enableResumable'], true);
  });

  test('item, stagioni, episodi, simili', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Id': 'm1', 'Name': 'Dune', 'Type': 'Movie'});
    final item = await api.item('u1', 'm1');
    expect(last().path, '/Items/m1');
    expect(last().query['userId'], 'u1');
    expect(item.name, 'Dune');

    adapter.handler = (_) => FakeResponse(200, itemsResult(['x']));
    await api.seasons('u1', 's1');
    expect(last().path, '/Shows/s1/Seasons');
    await api.episodes('u1', 's1', 'se1');
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['seasonId'], 'se1');
    await api.similar('u1', 'm1', limit: 12);
    expect(last().path, '/Items/m1/Similar');
  });

  test('filtri: generi e anni (dal più recente)', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Genres': ['Dramma', 'Azione'],
          'Years': [1999, 2024, 2010],
        });
    final filters = await api.filters('u1', ItemKind.series);
    expect(last().path, '/Items/Filters');
    expect(last().query['includeItemTypes'], 'Series');
    expect(filters.genres, ['Dramma', 'Azione']);
    expect(filters.years, [2024, 2010, 1999]);
  });

  test('ricerca persone', () async {
    await api.searchPeople('u1', 'zen', limit: 12);
    expect(last().path, '/Persons');
    expect(last().query['searchTerm'], 'zen');
  });

  test('preferiti e visti: POST per attivare, DELETE per disattivare', () async {
    adapter.handler = (_) => const FakeResponse(200, {'IsFavorite': true, 'Played': true});
    final fav = await api.setFavorite('u1', 'm1', favorite: true);
    expect(last().method, 'POST');
    expect(last().path, '/UserFavoriteItems/m1');
    expect(fav.isFavorite, isTrue);

    await api.setFavorite('u1', 'm1', favorite: false);
    expect(last().method, 'DELETE');

    await api.setPlayed('u1', 'm1', played: true);
    expect(last().method, 'POST');
    expect(last().path, '/UserPlayedItems/m1');
    await api.setPlayed('u1', 'm1', played: false);
    expect(last().method, 'DELETE');
  });
}

/// Accesso comodo a metodo, percorso e query di una richiesta registrata.
class RequestOptionsView {
  RequestOptionsView(this._options);

  final RequestOptions _options;

  String get method => _options.method;
  String get path => _options.path;
  Map<String, dynamic> get query => _options.queryParameters;
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/core/jellyfin/item_query_test.dart test/core/jellyfin/library_api_test.dart`
Expected: FAIL (file mancanti).

- [ ] **Step 3: implementa**

`lib/core/jellyfin/item_query.dart`:
```dart
import 'item_models.dart';

enum CatalogSort { title, dateAdded, year, rating }

enum WatchedFilter { all, unwatched, watched }

/// Parametri immagine/campi comuni a tutte le liste mostrate come card.
const cardImageParams = <String, dynamic>{
  'fields': 'PrimaryImageAspectRatio',
  'enableImageTypes': 'Primary,Backdrop,Thumb,Logo',
  'imageTypeLimit': 1,
};

const Object _keep = Object();

/// Interrogazione di `GET /Items` (catalogo, preferiti, ricerca, filmografia).
class ItemQuery {
  const ItemQuery({
    required this.kinds,
    this.sort = CatalogSort.title,
    this.genres = const {},
    this.year,
    this.watched = WatchedFilter.all,
    this.favoritesOnly = false,
    this.searchTerm,
    this.personId,
  });

  final Set<ItemKind> kinds;
  final CatalogSort sort;
  final Set<String> genres;
  final int? year;
  final WatchedFilter watched;
  final bool favoritesOnly;
  final String? searchTerm;
  final String? personId;

  /// Filtri scelti dall'utente nel catalogo (esclusi ordinamento e tipo).
  bool get hasFilters =>
      genres.isNotEmpty || year != null || watched != WatchedFilter.all;

  ItemQuery copyWith({
    CatalogSort? sort,
    Set<String>? genres,
    Object? year = _keep,
    WatchedFilter? watched,
  }) =>
      ItemQuery(
        kinds: kinds,
        sort: sort ?? this.sort,
        genres: genres ?? this.genres,
        year: identical(year, _keep) ? this.year : year as int?,
        watched: watched ?? this.watched,
        favoritesOnly: favoritesOnly,
        searchTerm: searchTerm,
        personId: personId,
      );

  Map<String, dynamic> toQueryParameters({
    required String userId,
    required int startIndex,
    required int limit,
  }) {
    final onlySeries = kinds.length == 1 && kinds.contains(ItemKind.series);
    final (sortBy, sortOrder) = switch (sort) {
      CatalogSort.title => ('SortName', 'Ascending'),
      CatalogSort.dateAdded => (
          onlySeries ? 'DateLastContentAdded,SortName' : 'DateCreated,SortName',
          'Descending'
        ),
      CatalogSort.year => ('ProductionYear,SortName', 'Descending'),
      CatalogSort.rating => ('CommunityRating,SortName', 'Descending'),
    };
    final term = searchTerm;
    return {
      ...cardImageParams,
      'userId': userId,
      'recursive': true,
      'includeItemTypes': (kinds.map((k) => k.apiName).toList()..sort()).join(','),
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      'startIndex': startIndex,
      'limit': limit,
      'enableTotalRecordCount': true,
      if (genres.isNotEmpty) 'genres': (genres.toList()..sort()).join('|'),
      if (year != null) 'years': '$year',
      if (watched == WatchedFilter.unwatched) 'isPlayed': false,
      if (watched == WatchedFilter.watched) 'isPlayed': true,
      if (favoritesOnly) 'isFavorite': true,
      if (term != null && term.isNotEmpty) 'searchTerm': term,
      if (personId != null) 'personIds': personId,
    };
  }
}
```

`lib/core/jellyfin/library_api.dart`:
```dart
import 'package:dio/dio.dart';

import 'item_models.dart';
import 'item_query.dart';
import 'jellyfin_http.dart';

/// Endpoint della libreria (Jellyfin 10.11). Lancia solo `ApiException`.
class LibraryApi {
  LibraryApi(this._http);

  final JellyfinHttp _http;

  Future<ItemPage> items(
    ItemQuery query, {
    required String userId,
    required int startIndex,
    required int limit,
    CancelToken? cancelToken,
  }) async {
    final data = await _http.get('/Items',
        query: query.toQueryParameters(
            userId: userId, startIndex: startIndex, limit: limit),
        cancelToken: cancelToken);
    return parseJson(
        data,
        (json) => ItemPage(
            _items(json), (json['TotalRecordCount'] as num?)?.toInt() ?? 0));
  }

  Future<List<JellyfinItem>> resume(String userId, {int limit = 20}) async =>
      _list(await _http.get('/UserItems/Resume', query: {
        ...cardImageParams,
        'userId': userId,
        'limit': limit,
        'mediaTypes': 'Video',
        'includeItemTypes': 'Movie,Episode',
      }));

  Future<List<JellyfinItem>> nextUp(
    String userId, {
    String? seriesId,
    int limit = 20,
    bool enableResumable = false,
  }) async =>
      _list(await _http.get('/Shows/NextUp', query: {
        ...cardImageParams,
        'userId': userId,
        'limit': limit,
        'enableResumable': enableResumable,
        if (seriesId != null) 'seriesId': seriesId,
      }));

  Future<JellyfinItem> item(String userId, String itemId) async => parseJson(
      await _http.get('/Items/$itemId', query: {'userId': userId}),
      JellyfinItem.fromJson);

  Future<List<JellyfinItem>> seasons(String userId, String seriesId) async =>
      _list(await _http.get('/Shows/$seriesId/Seasons',
          query: {...cardImageParams, 'userId': userId}));

  Future<List<JellyfinItem>> episodes(
          String userId, String seriesId, String seasonId) async =>
      _list(await _http.get('/Shows/$seriesId/Episodes', query: {
        ...cardImageParams,
        'userId': userId,
        'seasonId': seasonId,
        'fields': 'Overview,PrimaryImageAspectRatio',
      }));

  Future<List<JellyfinItem>> similar(String userId, String itemId,
          {int limit = 12}) async =>
      _list(await _http.get('/Items/$itemId/Similar',
          query: {...cardImageParams, 'userId': userId, 'limit': limit}));

  Future<LibraryFilters> filters(String userId, ItemKind kind) async =>
      parseJson(
        await _http.get('/Items/Filters',
            query: {'userId': userId, 'includeItemTypes': kind.apiName}),
        (json) => LibraryFilters(
          genres: (json['Genres'] as List? ?? const []).cast<String>().toList(),
          years: (json['Years'] as List? ?? const [])
              .map((y) => (y as num).toInt())
              .toList()
            ..sort((a, b) => b.compareTo(a)),
        ),
      );

  Future<List<JellyfinItem>> searchPeople(
    String userId,
    String term, {
    int limit = 12,
    CancelToken? cancelToken,
  }) async =>
      _list(await _http.get('/Persons',
          query: {'userId': userId, 'searchTerm': term, 'limit': limit},
          cancelToken: cancelToken));

  Future<UserItemData> setFavorite(String userId, String itemId,
          {required bool favorite}) =>
      _toggle('/UserFavoriteItems/$itemId', userId, favorite);

  Future<UserItemData> setPlayed(String userId, String itemId,
          {required bool played}) =>
      _toggle('/UserPlayedItems/$itemId', userId, played);

  Future<UserItemData> _toggle(String path, String userId, bool on) async {
    final query = {'userId': userId};
    final data = on
        ? await _http.post(path, query: query)
        : await _http.delete(path, query: query);
    return parseJson(data, UserItemData.fromJson);
  }
}

List<JellyfinItem> _items(Map<String, dynamic> json) =>
    (json['Items'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(JellyfinItem.fromJson)
        .toList();

List<JellyfinItem> _list(Object? data) => parseJson(data, _items);
```

- [ ] **Step 4: esegui**

Run: `flutter test test/core/jellyfin`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin/item_query.dart lib/core/jellyfin/library_api.dart test/core/jellyfin/item_query_test.dart test/core/jellyfin/library_api_test.dart
git commit -m "feat: add ItemQuery and LibraryApi"
```

---

### Task 6: provider della libreria e dati utente

**Files:**
- Create: `lib/features/library/library_providers.dart`, `lib/features/library/user_data.dart`
- Create: `test/support/library_fakes.dart`
- Test: `test/features/library/user_data_test.dart`

- [ ] **Step 1: supporto ai test**

`test/support/library_fakes.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/core/jellyfin/library_api.dart';

/// `LibraryApi` in memoria: risposte configurabili e chiamate registrate.
class FakeLibraryApi implements LibraryApi {
  ItemPage Function(ItemQuery query, int startIndex, int limit) onItems =
      (query, startIndex, limit) => const ItemPage([], 0);
  List<JellyfinItem> resumeItems = [];
  List<JellyfinItem> nextUpItems = [];
  final Map<String, JellyfinItem> itemsById = {};
  final Map<String, List<JellyfinItem>> seasonsBySeries = {};
  final Map<String, List<JellyfinItem>> episodesBySeason = {};
  List<JellyfinItem> similarItems = [];
  List<JellyfinItem> people = [];
  LibraryFilters libraryFilters = const LibraryFilters();

  /// Se valorizzato, ogni chiamata lancia questo errore.
  Object? error;

  /// Ritardo simulato di ogni risposta.
  Duration delay = Duration.zero;

  final itemQueries = <ItemQuery>[];
  final nextUpCalls = <String?>[];
  final favoriteCalls = <(String, bool)>[];
  final playedCalls = <(String, bool)>[];

  Future<T> _answer<T>(T Function() value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final failure = error;
    if (failure != null) throw failure;
    return value();
  }

  @override
  Future<ItemPage> items(ItemQuery query,
      {required String userId,
      required int startIndex,
      required int limit,
      CancelToken? cancelToken}) {
    itemQueries.add(query);
    return _answer(() => onItems(query, startIndex, limit));
  }

  @override
  Future<List<JellyfinItem>> resume(String userId, {int limit = 20}) =>
      _answer(() => resumeItems);

  @override
  Future<List<JellyfinItem>> nextUp(String userId,
      {String? seriesId, int limit = 20, bool enableResumable = false}) {
    nextUpCalls.add(seriesId);
    return _answer(() => nextUpItems);
  }

  @override
  Future<JellyfinItem> item(String userId, String itemId) =>
      _answer(() => itemsById[itemId] ?? (throw const NotFoundException()));

  @override
  Future<List<JellyfinItem>> seasons(String userId, String seriesId) =>
      _answer(() => seasonsBySeries[seriesId] ?? const []);

  @override
  Future<List<JellyfinItem>> episodes(
          String userId, String seriesId, String seasonId) =>
      _answer(() => episodesBySeason[seasonId] ?? const []);

  @override
  Future<List<JellyfinItem>> similar(String userId, String itemId,
          {int limit = 12}) =>
      _answer(() => similarItems);

  @override
  Future<LibraryFilters> filters(String userId, ItemKind kind) =>
      _answer(() => libraryFilters);

  @override
  Future<List<JellyfinItem>> searchPeople(String userId, String term,
          {int limit = 12, CancelToken? cancelToken}) =>
      _answer(() => people);

  @override
  Future<UserItemData> setFavorite(String userId, String itemId,
      {required bool favorite}) {
    favoriteCalls.add((itemId, favorite));
    return _answer(() => UserItemData(isFavorite: favorite));
  }

  @override
  Future<UserItemData> setPlayed(String userId, String itemId,
      {required bool played}) {
    playedCalls.add((itemId, played));
    return _answer(() => UserItemData(played: played));
  }
}

/// Elemento di prova con immagini e dati utente configurabili.
JellyfinItem testItem({
  String id = 'm1',
  String name = 'Dune: Parte Due',
  ItemKind kind = ItemKind.movie,
  int? year = 2024,
  int? runtimeMinutes = 120,
  String? overview,
  bool played = false,
  bool favorite = false,
  int positionTicks = 0,
  double? playedPercentage,
  String? seriesId,
  String? seriesName,
  String? seasonId,
  int? index,
  int? seasonIndex,
  int? childCount,
  List<Map<String, dynamic>> people = const [],
  List<Map<String, dynamic>> trailers = const [],
}) =>
    JellyfinItem.fromJson({
      'Id': id,
      'Name': name,
      'Type': kind == ItemKind.other ? 'Folder' : kind.apiName,
      if (year != null) 'ProductionYear': year,
      if (runtimeMinutes != null) 'RunTimeTicks': runtimeMinutes * 600000000,
      if (overview != null) 'Overview': overview,
      'ImageTags': {'Primary': 'p-$id'},
      'BackdropImageTags': ['b-$id'],
      'UserData': {
        'Played': played,
        'IsFavorite': favorite,
        'PlaybackPositionTicks': positionTicks,
        if (playedPercentage != null) 'PlayedPercentage': playedPercentage,
      },
      if (seriesId != null) 'SeriesId': seriesId,
      if (seriesName != null) 'SeriesName': seriesName,
      if (seasonId != null) 'SeasonId': seasonId,
      if (index != null) 'IndexNumber': index,
      if (seasonIndex != null) 'ParentIndexNumber': seasonIndex,
      if (childCount != null) 'ChildCount': childCount,
      'People': people,
      'RemoteTrailers': trailers,
    });

ItemPage pageOf(List<JellyfinItem> items, [int? total]) =>
    ItemPage(items, total ?? items.length);
```

- [ ] **Step 2: scrivi il test**

`test/features/library/user_data_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;
  late ProviderContainer container;

  setUp(() {
    api = FakeLibraryApi();
    container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
  });

  UserDataOverrides overrides() => container.read(userDataOverridesProvider.notifier);

  test('currentUserId viene dalla sessione', () {
    expect(container.read(currentUserIdProvider), 'u1');
  });

  test('toggleFavorite: aggiornamento immediato e conferma del server', () async {
    final item = testItem(favorite: false);
    final pending = overrides().toggleFavorite(item);
    expect(overrides().effective(item).isFavorite, isTrue, reason: 'ottimistico');
    await pending;
    expect(api.favoriteCalls, [('m1', true)]);
    expect(overrides().effective(item).isFavorite, isTrue);
  });

  test('togglePlayed: in caso di errore torna allo stato precedente', () async {
    final item = testItem(played: false);
    api.error = const ServerUnreachableException();
    await expectLater(overrides().togglePlayed(item),
        throwsA(isA<ServerUnreachableException>()));
    expect(overrides().effective(item).played, isFalse);
  });

  test('apply da evento server', () {
    final item = testItem();
    overrides().apply('m1', item.userData.copyWith(played: true));
    expect(container.read(userDataOverridesProvider)['m1']?.played, isTrue);
  });

  test('libraryRevision aumenta', () {
    container.read(libraryRevisionProvider.notifier).bump();
    expect(container.read(libraryRevisionProvider), 1);
  });
}
```

- [ ] **Step 3: esegui**

Run: `flutter test test/features/library/user_data_test.dart`
Expected: FAIL (file mancanti).

- [ ] **Step 4: implementa**

`lib/features/library/library_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/jellyfin/library_api.dart';
import '../auth/session_controller.dart';

/// Id dell'utente autenticato. Da usare solo dentro provider asincroni:
/// senza sessione lancia, e l'errore finisce nell'`AsyncValue`.
final currentUserIdProvider = Provider<String>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session is SessionSignedIn) return session.user.id;
  throw StateError('Nessun utente autenticato');
});

final libraryApiProvider =
    Provider<LibraryApi>((ref) => LibraryApi(ref.watch(jellyfinHttpProvider)));

final imageUrlsProvider =
    Provider<ImageUrls>((ref) => ImageUrls(ref.watch(appConfigProvider).serverUrl));

/// Aumenta quando il server segnala modifiche alla libreria: i provider che
/// lo osservano ricaricano i dati.
class LibraryRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final libraryRevisionProvider =
    NotifierProvider<LibraryRevision, int>(LibraryRevision.new);
```

`lib/features/library/user_data.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/library_api.dart';
import '../auth/session_controller.dart';
import 'library_providers.dart';

/// Dati utente aggiornati dopo il caricamento (azioni locali ed eventi del
/// server), per id elemento. Le card leggono da qui prima che da `item.userData`.
class UserDataOverrides extends Notifier<Map<String, UserItemData>> {
  @override
  Map<String, UserItemData> build() {
    // Si azzera quando cambia l'utente.
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    return const {};
  }

  void apply(String itemId, UserItemData data) =>
      state = {...state, itemId: data};

  UserItemData effective(JellyfinItem item) => state[item.id] ?? item.userData;

  Future<void> toggleFavorite(JellyfinItem item) => _toggle(
        item,
        (data) => data.copyWith(isFavorite: !data.isFavorite),
        (api, userId, next) =>
            api.setFavorite(userId, item.id, favorite: next.isFavorite),
      );

  Future<void> togglePlayed(JellyfinItem item) => _toggle(
        item,
        (data) => data.copyWith(played: !data.played),
        (api, userId, next) => api.setPlayed(userId, item.id, played: next.played),
      );

  Future<void> _toggle(
    JellyfinItem item,
    UserItemData Function(UserItemData current) change,
    Future<UserItemData> Function(LibraryApi api, String userId, UserItemData next)
        send,
  ) async {
    final before = effective(item);
    final next = change(before);
    apply(item.id, next);
    try {
      final confirmed = await send(ref.read(libraryApiProvider),
          ref.read(currentUserIdProvider), next);
      apply(item.id, confirmed);
    } on Object {
      apply(item.id, before);
      rethrow;
    }
  }
}

final userDataOverridesProvider =
    NotifierProvider<UserDataOverrides, Map<String, UserItemData>>(
        UserDataOverrides.new);

/// Dati utente aggiornati di [item], da usare nel `build` dei widget.
UserItemData watchUserData(WidgetRef ref, JellyfinItem item) =>
    ref.watch(userDataOverridesProvider.select((m) => m[item.id])) ??
    item.userData;
```

- [ ] **Step 5: esegui**

Run: `flutter test test/features/library/user_data_test.dart`
Expected: PASS (5 test).

- [ ] **Step 6: commit**

```bash
git add lib/features/library test/features/library/user_data_test.dart test/support/library_fakes.dart
git commit -m "feat: add library providers and optimistic user data overrides"
```

---

### Task 7: eventi del server (WebSocket)

**Files:**
- Create: `lib/core/jellyfin/server_events.dart`
- Test: `test/core/jellyfin/server_events_test.dart`

Il server Jellyfin invia eventi su `wss://<server>/socket`. Ci servono tre messaggi:
- `UserDataChanged`: visto, preferito o minutaggio cambiati da un altro dispositivo;
- `LibraryChanged`: contenuti aggiunti o rimossi;
- `ForceKeepAlive`: il server chiede al client di mandare `KeepAlive` periodici.

L'autenticazione passa nell'header `Authorization`, come per HTTP.

- [ ] **Step 1: scrivi il test**

`test/core/jellyfin/server_events_test.dart`:
```dart
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';

class FakeSocket implements EventSocket {
  final controller = StreamController<dynamic>();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void send(String message) => sent.add(message);

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

void main() {
  test('parseServerMessage', () {
    final changed = parseServerMessage(jsonEncode({
      'MessageType': 'UserDataChanged',
      'Data': {
        'UserId': 'u1',
        'UserDataList': [
          {'ItemId': 'm1', 'Played': true, 'IsFavorite': false},
        ],
      },
    }));
    expect(changed, isA<UserDataChanged>());
    expect((changed as UserDataChanged).changes['m1']?.played, isTrue);
    expect(changed.userId, 'u1');

    expect(parseServerMessage('{"MessageType":"LibraryChanged","Data":{}}'),
        isA<LibraryChanged>());
    expect(
        (parseServerMessage('{"MessageType":"ForceKeepAlive","Data":60}')
                as ForceKeepAlive)
            .seconds,
        60);
    expect(parseServerMessage('{"MessageType":"Sessions"}'), isNull);
    expect(parseServerMessage('non json'), isNull);
    expect(parseServerMessage(42), isNull);
  });

  test('socketUri', () {
    expect(socketUri(Uri.parse('https://media.example.com/jf')).toString(),
        'wss://media.example.com/jf/socket');
  });

  test('connessione, eventi, keep-alive e riconnessione', () {
    fakeAsync((async) {
      final sockets = <FakeSocket>[];
      final requests = <(Uri, Map<String, String>)>[];
      final client = ServerEventsClient(
        serverUrl: Uri.parse('https://media.example.com/jf'),
        authorizationHeader: () => 'MediaBrowser Token="tok"',
        connector: (uri, headers) async {
          requests.add((uri, headers));
          final socket = FakeSocket();
          sockets.add(socket);
          return socket;
        },
      );
      final events = <ServerEvent>[];
      client.events.listen(events.add);

      client.start();
      async.flushMicrotasks();
      expect(requests.single.$1.toString(), 'wss://media.example.com/jf/socket');
      expect(requests.single.$2['Authorization'], 'MediaBrowser Token="tok"');

      sockets.single.controller
          .add('{"MessageType":"ForceKeepAlive","Data":60}');
      async.flushMicrotasks();
      expect(sockets.single.sent.single, contains('KeepAlive'));
      async.elapse(const Duration(seconds: 30));
      expect(sockets.single.sent.length, 2);

      sockets.single.controller
          .add('{"MessageType":"LibraryChanged","Data":{}}');
      async.flushMicrotasks();
      expect(events.whereType<LibraryChanged>(), hasLength(1));

      // Il server chiude: nuovo tentativo dopo 2 s.
      unawaited(sockets.single.controller.close());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      expect(requests, hasLength(2));

      unawaited(client.stop());
      async.flushMicrotasks();
      expect(sockets.last.closed, isTrue);
      async.elapse(const Duration(minutes: 5));
      expect(requests, hasLength(2), reason: 'dopo stop niente riconnessioni');
    });
  });

  test('connessione fallita: riprova con attese crescenti', () {
    fakeAsync((async) {
      var attempts = 0;
      final client = ServerEventsClient(
        serverUrl: Uri.parse('https://media.example.com'),
        authorizationHeader: () => 'x',
        connector: (uri, headers) async {
          attempts++;
          throw StateError('down');
        },
      );
      client.start();
      async.flushMicrotasks();
      expect(attempts, 1);
      async.elapse(const Duration(seconds: 2));
      expect(attempts, 2);
      async.elapse(const Duration(seconds: 5));
      expect(attempts, 3);
      unawaited(client.stop());
      async.flushMicrotasks();
    });
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/core/jellyfin/server_events_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: implementa**

`lib/core/jellyfin/server_events.dart`:
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'item_models.dart';

sealed class ServerEvent {
  const ServerEvent();
}

/// Dati utente cambiati (anche da altri dispositivi), per id elemento.
final class UserDataChanged extends ServerEvent {
  const UserDataChanged(this.userId, this.changes);

  final String userId;
  final Map<String, UserItemData> changes;
}

final class LibraryChanged extends ServerEvent {
  const LibraryChanged();
}

/// Il server chiede un `KeepAlive` entro [seconds] secondi.
final class ForceKeepAlive extends ServerEvent {
  const ForceKeepAlive(this.seconds);

  final int seconds;
}

/// Messaggio del WebSocket → evento; `null` per messaggi ignorati o non validi.
ServerEvent? parseServerMessage(Object? raw) {
  if (raw is! String) return null;
  try {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return null;
    final data = json['Data'];
    switch (json['MessageType']) {
      case 'UserDataChanged':
        if (data is! Map<String, dynamic>) return null;
        final list = (data['UserDataList'] as List? ?? const [])
            .whereType<Map<String, dynamic>>();
        return UserDataChanged(data['UserId'] as String? ?? '', {
          for (final entry in list)
            if (entry['ItemId'] is String)
              entry['ItemId'] as String: UserItemData.fromJson(entry),
        });
      case 'LibraryChanged':
        return const LibraryChanged();
      case 'ForceKeepAlive':
        return ForceKeepAlive((data as num?)?.toInt() ?? 60);
      default:
        return null;
    }
  } on Object {
    return null;
  }
}

Uri socketUri(Uri serverUrl) => serverUrl.replace(
      scheme: serverUrl.scheme == 'https' ? 'wss' : 'ws',
      path: '${serverUrl.path}/socket',
    );

/// Connessione minima di cui ha bisogno il client (sostituibile nei test).
abstract interface class EventSocket {
  Stream<dynamic> get stream;
  void send(String message);
  Future<void> close();
}

typedef EventSocketConnector = Future<EventSocket> Function(
    Uri uri, Map<String, String> headers);

Future<EventSocket> connectIoSocket(Uri uri, Map<String, String> headers) async =>
    _IoEventSocket(await WebSocket.connect(uri.toString(), headers: headers));

class _IoEventSocket implements EventSocket {
  _IoEventSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void send(String message) => _socket.add(message);

  @override
  Future<void> close() => _socket.close();
}

/// Client WebSocket di Jellyfin: riconnessione automatica e keep-alive.
class ServerEventsClient {
  ServerEventsClient({
    required Uri serverUrl,
    required String Function() authorizationHeader,
    EventSocketConnector connector = connectIoSocket,
    List<Duration> retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
  })  : _uri = socketUri(serverUrl),
        _authorizationHeader = authorizationHeader,
        _connector = connector,
        _retryDelays = retryDelays;

  final Uri _uri;
  final String Function() _authorizationHeader;
  final EventSocketConnector _connector;
  final List<Duration> _retryDelays;
  final _events = StreamController<ServerEvent>.broadcast();

  EventSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _keepAlive;
  Timer? _retry;
  bool _running = false;
  int _attempt = 0;

  Stream<ServerEvent> get events => _events.stream;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_connect());
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _keepAlive?.cancel();
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    await subscription?.cancel();
    await socket?.close();
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  Future<void> _connect() async {
    if (!_running) return;
    try {
      final socket =
          await _connector(_uri, {'Authorization': _authorizationHeader()});
      if (!_running) {
        await socket.close();
        return;
      }
      _socket = socket;
      _attempt = 0;
      _subscription = socket.stream.listen(
        _onMessage,
        onDone: _scheduleReconnect,
        onError: (Object _) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } on Object {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    final event = parseServerMessage(raw);
    if (event == null) return;
    if (event is ForceKeepAlive) _startKeepAlive(event.seconds);
    if (!_events.isClosed) _events.add(event);
  }

  void _startKeepAlive(int seconds) {
    _keepAlive?.cancel();
    final period = Duration(seconds: (seconds ~/ 2).clamp(5, 60));
    _sendKeepAlive();
    _keepAlive = Timer.periodic(period, (_) => _sendKeepAlive());
  }

  void _sendKeepAlive() =>
      _socket?.send(jsonEncode({'MessageType': 'KeepAlive'}));

  void _scheduleReconnect() {
    _keepAlive?.cancel();
    _socket = null;
    _subscription = null;
    if (!_running) return;
    final delay = _retryDelays[min(_attempt, _retryDelays.length - 1)];
    _attempt++;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(_connect()));
  }
}
```

- [ ] **Step 4: esegui**

Run: `flutter test test/core/jellyfin/server_events_test.dart`
Expected: PASS (4 test).

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin/server_events.dart test/core/jellyfin/server_events_test.dart
git commit -m "feat: add Jellyfin WebSocket events client with keep-alive and reconnect"
```

---

### Task 8: collegare gli eventi del server allo stato dell'app

**Files:**
- Create: `lib/features/library/server_events_binding.dart`
- Modify: `test/support/pump_app.dart`
- Test: `test/features/library/server_events_binding_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/library/server_events_binding_test.dart`:
```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/library/user_data.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';

class _Socket implements EventSocket {
  final controller = StreamController<dynamic>();

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void send(String message) {}

  @override
  Future<void> close() => controller.close();
}

void main() {
  test('UserDataChanged e LibraryChanged aggiornano lo stato', () async {
    final socket = _Socket();
    final container = ProviderContainer.test(
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        serverEventsClientProvider.overrideWith((ref) => ServerEventsClient(
              serverUrl: Uri.parse('https://media.example.com'),
              authorizationHeader: () => 'x',
              connector: (uri, headers) async => socket,
            )),
      ],
      retry: (_, _) => null,
    );

    container.read(serverEventsBindingProvider);
    await Future<void>.delayed(Duration.zero);

    socket.controller.add('{"MessageType":"UserDataChanged","Data":{"UserId":"u1",'
        '"UserDataList":[{"ItemId":"m1","Played":true}]}}');
    socket.controller.add('{"MessageType":"LibraryChanged","Data":{}}');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(userDataOverridesProvider)['m1']?.played, isTrue);
    expect(container.read(libraryRevisionProvider), 1);
  });

  test('eventi di un altro utente vengono ignorati', () async {
    final socket = _Socket();
    final container = ProviderContainer.test(
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        serverEventsClientProvider.overrideWith((ref) => ServerEventsClient(
              serverUrl: Uri.parse('https://media.example.com'),
              authorizationHeader: () => 'x',
              connector: (uri, headers) async => socket,
            )),
      ],
      retry: (_, _) => null,
    );
    container.read(serverEventsBindingProvider);
    await Future<void>.delayed(Duration.zero);

    socket.controller.add('{"MessageType":"UserDataChanged","Data":{"UserId":"altro",'
        '"UserDataList":[{"ItemId":"m1","Played":true}]}}');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(userDataOverridesProvider), isEmpty);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/features/library/server_events_binding_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: implementa**

`lib/features/library/server_events_binding.dart`:
```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/server_events.dart';
import '../auth/session_controller.dart';
import 'library_providers.dart';
import 'user_data.dart';

final serverEventsClientProvider = Provider<ServerEventsClient>((ref) {
  final client = ServerEventsClient(
    serverUrl: ref.watch(appConfigProvider).serverUrl,
    authorizationHeader: () => ref.read(jellyfinHttpProvider).authorizationHeader,
  );
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
});

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Tiene aperto il WebSocket finché l'utente è autenticato e ne applica gli
/// eventi allo stato. La barra superiore (`AppShell`) lo osserva.
final serverEventsBindingProvider = Provider<void>((ref) {
  final userId = ref.watch(sessionControllerProvider
      .select((s) => s is SessionSignedIn ? s.user.id : null));
  if (userId == null) return;

  final client = ref.watch(serverEventsClientProvider);
  final subscription = client.events.listen((event) {
    switch (event) {
      case UserDataChanged(userId: final changedUser, :final changes)
          when changedUser.isEmpty ||
              _normalizeId(changedUser) == _normalizeId(userId):
        final overrides = ref.read(userDataOverridesProvider.notifier);
        changes.forEach(overrides.apply);
      case LibraryChanged():
        ref.read(libraryRevisionProvider.notifier).bump();
      default:
        break;
    }
  });
  client.start();
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(client.stop());
  });
});
```

In `test/support/pump_app.dart` aggiungi l'import:
```dart
import 'package:wonderflix/features/library/server_events_binding.dart';
```
e nella lista `overrides:` di `ProviderScope`, subito dopo l'override di `appConfigProvider`, aggiungi:
```dart
      // Nessun WebSocket reale nei widget test.
      serverEventsBindingProvider.overrideWithValue(null),
```

- [ ] **Step 4: esegui tutti i test**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/library/server_events_binding.dart test/features/library/server_events_binding_test.dart test/support/pump_app.dart
git commit -m "feat: apply server WebSocket events to user data and library revision"
```

---
### Task 9: stringhe del Piano 2 (it/en)

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan2_test.dart`

- [ ] **Step 1: scrivi il test**

`test/app/l10n_plan2_test.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe con parametri e plurali', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.actionResumeAt('23:14'), 'Riprendi da 23:14');
    expect(it.actionPlayEpisode('S1:E5'), 'Riproduci S1:E5');
    expect(it.detailSeasons(1), '1 stagione');
    expect(it.detailSeasons(3), '3 stagioni');
    expect(it.catalogCount(250), '250 titoli');
    expect(it.searchNoResults('dune'), 'Nessun risultato per "dune"');
    expect(en.detailSeasons(2), '2 seasons');
    expect(en.settingsVersion('1.0.0'), 'Version 1.0.0');
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter gen-l10n; flutter test test/app/l10n_plan2_test.dart`
Expected: FAIL (le nuove chiavi non esistono).

- [ ] **Step 3: aggiungi le chiavi**

In `l10n/app_it.arb`, prima della `}` finale (dopo il blocco `"@homeWelcome"`, aggiungendo una virgola dopo la sua `}`), inserisci:
```json
  "navMovies": "Film",
  "navSeries": "Serie",
  "navMyList": "La mia lista",
  "navSearch": "Cerca",
  "menuSettings": "Impostazioni",
  "homeContinueWatching": "Continua a guardare",
  "homeNextUp": "Prossimi episodi",
  "homeLatestMovies": "Film aggiunti di recente",
  "homeLatestSeries": "Serie aggiunte di recente",
  "homeEmpty": "Qui non c'è ancora niente.",
  "actionPlay": "Riproduci",
  "actionResumeAt": "Riprendi da {time}",
  "@actionResumeAt": {"placeholders": {"time": {"type": "String"}}},
  "actionPlayEpisode": "Riproduci {code}",
  "@actionPlayEpisode": {"placeholders": {"code": {"type": "String"}}},
  "actionResumeEpisode": "Riprendi {code}",
  "@actionResumeEpisode": {"placeholders": {"code": {"type": "String"}}},
  "actionRestart": "Ricomincia",
  "actionTrailer": "Trailer",
  "actionDetails": "Dettagli",
  "actionAddToList": "Aggiungi a La mia lista",
  "actionRemoveFromList": "Rimuovi da La mia lista",
  "actionMarkWatched": "Segna come visto",
  "actionMarkUnwatched": "Segna come non visto",
  "playbackComingSoon": "La riproduzione arriva con il prossimo aggiornamento.",
  "detailCast": "Cast",
  "detailSimilar": "Simili",
  "detailSeasons": "{count, plural, =1{1 stagione} other{{count} stagioni}}",
  "@detailSeasons": {"placeholders": {"count": {"type": "int"}}},
  "detailRemaining": "rimangono {time}",
  "@detailRemaining": {"placeholders": {"time": {"type": "String"}}},
  "detailNoEpisodes": "Nessun episodio disponibile.",
  "catalogSortLabel": "Ordina per",
  "catalogSortTitle": "Titolo",
  "catalogSortDateAdded": "Data di aggiunta",
  "catalogSortYear": "Anno",
  "catalogSortRating": "Voto",
  "catalogAllGenres": "Tutti i generi",
  "catalogAllYears": "Tutti gli anni",
  "catalogWatchedAll": "Tutti",
  "catalogWatchedUnwatched": "Non visti",
  "catalogWatchedWatched": "Visti",
  "catalogCount": "{count, plural, =1{1 titolo} other{{count} titoli}}",
  "@catalogCount": {"placeholders": {"count": {"type": "int"}}},
  "catalogEmpty": "Nessun titolo con questi filtri.",
  "catalogClearFilters": "Azzera filtri",
  "personOnServer": "Su WonderFlix",
  "searchHint": "Cerca film, serie o persone",
  "searchPrompt": "Scrivi almeno 2 lettere per cercare.",
  "searchNoResults": "Nessun risultato per \"{term}\"",
  "@searchNoResults": {"placeholders": {"term": {"type": "String"}}},
  "searchPeople": "Persone",
  "myListEmpty": "La tua lista è vuota. Aggiungi film e serie con il cuore.",
  "settingsLanguage": "Lingua",
  "settingsLanguageSystem": "Lingua di sistema",
  "settingsAccount": "Account",
  "settingsSignedInAs": "Accesso come {name}",
  "@settingsSignedInAs": {"placeholders": {"name": {"type": "String"}}},
  "settingsVersion": "Versione {version}",
  "@settingsVersion": {"placeholders": {"version": {"type": "String"}}}
```

In `l10n/app_en.arb`, prima della `}` finale (virgola dopo `"homeWelcome"`), inserisci:
```json
  "navMovies": "Movies",
  "navSeries": "TV Shows",
  "navMyList": "My List",
  "navSearch": "Search",
  "menuSettings": "Settings",
  "homeContinueWatching": "Continue watching",
  "homeNextUp": "Next up",
  "homeLatestMovies": "Recently added movies",
  "homeLatestSeries": "Recently added shows",
  "homeEmpty": "Nothing here yet.",
  "actionPlay": "Play",
  "actionResumeAt": "Resume from {time}",
  "actionPlayEpisode": "Play {code}",
  "actionResumeEpisode": "Resume {code}",
  "actionRestart": "Start over",
  "actionTrailer": "Trailer",
  "actionDetails": "Details",
  "actionAddToList": "Add to My List",
  "actionRemoveFromList": "Remove from My List",
  "actionMarkWatched": "Mark as watched",
  "actionMarkUnwatched": "Mark as unwatched",
  "playbackComingSoon": "Playback is coming in the next update.",
  "detailCast": "Cast",
  "detailSimilar": "More like this",
  "detailSeasons": "{count, plural, =1{1 season} other{{count} seasons}}",
  "detailRemaining": "{time} left",
  "detailNoEpisodes": "No episodes available.",
  "catalogSortLabel": "Sort by",
  "catalogSortTitle": "Title",
  "catalogSortDateAdded": "Date added",
  "catalogSortYear": "Year",
  "catalogSortRating": "Rating",
  "catalogAllGenres": "All genres",
  "catalogAllYears": "All years",
  "catalogWatchedAll": "All",
  "catalogWatchedUnwatched": "Unwatched",
  "catalogWatchedWatched": "Watched",
  "catalogCount": "{count, plural, =1{1 title} other{{count} titles}}",
  "catalogEmpty": "No titles match these filters.",
  "catalogClearFilters": "Clear filters",
  "personOnServer": "On WonderFlix",
  "searchHint": "Search movies, shows or people",
  "searchPrompt": "Type at least 2 letters to search.",
  "searchNoResults": "No results for \"{term}\"",
  "searchPeople": "People",
  "myListEmpty": "Your list is empty. Add movies and shows with the heart.",
  "settingsLanguage": "Language",
  "settingsLanguageSystem": "System language",
  "settingsAccount": "Account",
  "settingsSignedInAs": "Signed in as {name}",
  "settingsVersion": "Version {version}"
```

- [ ] **Step 4: genera ed esegui**

Run: `flutter gen-l10n; flutter test`
Expected: nessun warning da gen-l10n; PASS.

- [ ] **Step 5: commit**

```bash
git add l10n test/app/l10n_plan2_test.dart
git commit -m "feat: add Italian/English strings for library screens"
```

---

### Task 10: widget condivisi

**Files:**
- Create: `lib/ui/wf_image.dart`, `lib/ui/wf_buttons.dart`, `lib/ui/poster_card.dart`, `lib/ui/landscape_card.dart`, `lib/ui/media_row.dart`, `lib/ui/states.dart`
- Modify: `test/support/pump_app.dart`
- Test: `test/ui/cards_test.dart`, `test/ui/states_test.dart`

- [ ] **Step 1: pump_app senza rete per le immagini**

In `test/support/pump_app.dart` aggiungi l'import:
```dart
import 'package:wonderflix/ui/wf_image.dart';
```
e nella lista `overrides:` (dopo l'override di `serverEventsBindingProvider`):
```dart
      // Nessuna immagine di rete nei widget test.
      imageBuilderProvider.overrideWithValue(
          (image, fit) => const ColoredBox(color: Color(0xFF333333))),
```

- [ ] **Step 2: scrivi i test**

`test/ui/cards_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/landscape_card.dart';
import 'package:wonderflix/ui/media_row.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final signedIn = sessionControllerProvider
      .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser)));

  testWidgets('PosterCard: titolo, anno, badge visto e tap', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Center(
        child: PosterCard(
            item: testItem(played: true), width: 160, onTap: () => taps++),
      ),
      overrides: [signedIn],
    );
    expect(find.text('Dune: Parte Due'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.byType(WatchedBadge), findsOneWidget);
    await tester.tap(find.byType(PosterCard));
    expect(taps, 1);
  });

  testWidgets('PosterCard: barra di avanzamento se iniziato', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: PosterCard(
            item: testItem(playedPercentage: 40), width: 160, onTap: () {}),
      ),
      overrides: [signedIn],
    );
    expect(find.byType(ProgressStrip), findsOneWidget);
    expect(find.byType(WatchedBadge), findsNothing);
  });

  testWidgets('LandscapeCard di un episodio', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: LandscapeCard(
          item: testItem(
            id: 'e4',
            name: 'Please Hold',
            kind: ItemKind.episode,
            seriesName: 'The Last of Us',
            index: 4,
            seasonIndex: 1,
          ),
          onTap: () {},
        ),
      ),
      overrides: [signedIn],
    );
    expect(find.text('The Last of Us'), findsOneWidget);
    expect(find.text('S1:E4 · Please Hold'), findsOneWidget);
  });

  testWidgets('MediaRow: titolo e frecce', (tester) async {
    await pumpApp(
      tester,
      MediaRow(
        title: 'Continua a guardare',
        height: 60,
        itemCount: 30,
        itemBuilder: (context, i) => SizedBox(width: 100, child: Text('i$i')),
      ),
    );
    expect(find.text('Continua a guardare'), findsOneWidget);
    expect(find.byKey(const Key('row-next')), findsOneWidget);
    await tester.tap(find.byKey(const Key('row-next')));
    await tester.pumpAndSettle();
    expect(find.text('i0'), findsNothing, reason: 'la riga è scorsa');
  });

  testWidgets('WfButton in una Row non va in overflow', (tester) async {
    await pumpApp(
      tester,
      Row(children: [
        WfButton.primary(label: 'Riproduci', icon: Icons.play_arrow, onPressed: () {}),
        WfButton.secondary(label: 'Trailer', icon: Icons.movie, onPressed: () {}),
      ]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Riproduci'), findsOneWidget);
  });
}
```

`test/ui/states_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/ui/states.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('ErrorView mostra il messaggio e riprova', (tester) async {
    var retries = 0;
    await pumpApp(
      tester,
      ErrorView(
          error: const ServerUnreachableException(), onRetry: () => retries++),
    );
    expect(find.textContaining('non è raggiungibile'), findsOneWidget);
    await tester.tap(find.text('Riprova'));
    expect(retries, 1);
  });
}
```

- [ ] **Step 3: esegui**

Run: `flutter test test/ui`
Expected: FAIL (file mancanti).

- [ ] **Step 4: implementa**

`lib/ui/wf_image.dart`:
```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import '../core/jellyfin/image_urls.dart';

typedef ImageBuilderFn = Widget Function(ImageRef image, BoxFit fit);

Widget _networkImage(ImageRef image, BoxFit fit) => CachedNetworkImage(
      imageUrl: image.url,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => ImagePlaceholder(blurHash: image.blurHash),
      errorWidget: (context, url, error) => const ImagePlaceholder(),
    );

/// Come si disegna un'immagine di rete (sostituito nei widget test).
final imageBuilderProvider = Provider<ImageBuilderFn>((ref) => _networkImage);

/// Immagine Jellyfin con cache su disco e blurhash durante il caricamento.
class WfImage extends ConsumerWidget {
  const WfImage({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.fallbackIcon = LucideIcons.film,
  });

  final ImageRef? image;
  final BoxFit fit;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = image;
    if (img == null) return ImagePlaceholder(icon: fallbackIcon);
    return ref.watch(imageBuilderProvider)(img, fit);
  }
}

class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder({super.key, this.blurHash, this.icon});

  final String? blurHash;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final hash = blurHash;
    if (hash != null) return BlurHash(hash: hash);
    final symbol = icon;
    return ColoredBox(
      color: WfColors.surfaceHigh,
      child: symbol == null
          ? null
          : Center(child: Icon(symbol, color: WfColors.creamMuted, size: 28)),
    );
  }
}
```

`lib/ui/wf_buttons.dart`:
```dart
import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Pulsante con etichetta e icona. Larghezza adatta al contenuto (il tema
/// globale rende i FilledButton larghi quanto il contenitore, qui no).
class WfButton extends StatelessWidget {
  const WfButton.primary({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  }) : primary = true;

  const WfButton.secondary({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  }) : primary = false;

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    const size = Size(0, 44);
    const padding = EdgeInsets.symmetric(horizontal: 20);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
            minimumSize: size, padding: padding, shape: shape),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: size,
        padding: padding,
        shape: shape,
        foregroundColor: WfColors.cream,
        side: const BorderSide(color: WfColors.border),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// Pulsante tondo con stato attivo (preferito, visto).
class WfIconToggle extends StatelessWidget {
  const WfIconToggle({
    super.key,
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        foregroundColor: selected ? WfColors.gold : WfColors.cream,
        side: BorderSide(color: selected ? WfColors.gold : WfColors.border),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}
```

`lib/ui/poster_card.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import '../core/jellyfin/item_models.dart';
import '../features/library/library_providers.dart';
import '../features/library/user_data.dart';
import 'wf_image.dart';

/// Locandina 2:3 con titolo, anno, avanzamento e badge "visto".
/// Con [width] `null` occupa la larghezza disponibile (griglie).
class PosterCard extends ConsumerStatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width,
  });

  final JellyfinItem item;
  final VoidCallback onTap;
  final double? width;

  @override
  ConsumerState<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends ConsumerState<PosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final userData = watchUserData(ref, item);
    final progress = userData.progress;
    final unplayed = userData.unplayedItemCount ?? 0;
    final year = item.productionYear;

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _hover ? WfColors.gold : Colors.transparent,
                        width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        WfImage(image: ref.watch(imageUrlsProvider).poster(item)),
                        if (progress != null) ProgressStrip(progress: progress),
                        if (userData.played)
                          const Positioned(
                              top: 6, right: 6, child: WatchedBadge())
                        else if (item.kind == ItemKind.series && unplayed > 0)
                          Positioned(
                              top: 6, right: 6, child: CountBadge(count: unplayed)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (year != null)
                Text('$year',
                    style:
                        const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra oro in fondo all'immagine, per il minutaggio.
class ProgressStrip extends StatelessWidget {
  const ProgressStrip({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        height: 3,
        color: Colors.black54,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress,
          child: const ColoredBox(color: WfColors.gold),
        ),
      ),
    );
  }
}

class WatchedBadge extends StatelessWidget {
  const WatchedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration:
          const BoxDecoration(color: WfColors.gold, shape: BoxShape.circle),
      child: const Icon(LucideIcons.check, size: 14, color: WfColors.bg),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: WfColors.gold, borderRadius: BorderRadius.circular(10)),
      child: Text('$count',
          style: const TextStyle(
              color: WfColors.bg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
```

`lib/ui/landscape_card.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../core/jellyfin/item_models.dart';
import '../features/library/item_labels.dart';
import '../features/library/library_providers.dart';
import '../features/library/user_data.dart';
import 'poster_card.dart';
import 'wf_image.dart';

/// Card 16:9 per "Continua a guardare", "Prossimi episodi" ed episodi.
class LandscapeCard extends ConsumerStatefulWidget {
  const LandscapeCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 300,
  });

  final JellyfinItem item;
  final VoidCallback onTap;
  final double width;

  @override
  ConsumerState<LandscapeCard> createState() => _LandscapeCardState();
}

class _LandscapeCardState extends ConsumerState<LandscapeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final userData = watchUserData(ref, item);
    final progress = userData.progress;
    final subtitle = cardSubtitle(item);

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _hover ? WfColors.gold : Colors.transparent,
                        width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        WfImage(
                            image: ref.watch(imageUrlsProvider).landscape(item)),
                        if (progress != null) ProgressStrip(progress: progress),
                        if (userData.played)
                          const Positioned(top: 6, right: 6, child: WatchedBadge()),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(cardTitle(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (subtitle != null)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
```

`lib/ui/media_row.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';

/// Riga orizzontale con titolo e frecce (per chi usa il mouse).
class MediaRow extends StatefulWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scroll(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + direction * position.viewportDimension * 0.8)
        .clamp(0.0, position.maxScrollExtent);
    _controller.animateTo(target,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                Flexible(child: Text(widget.title, style: WfText.display(24))),
                const Spacer(),
                IconButton(
                  key: const Key('row-previous'),
                  onPressed: () => _scroll(-1),
                  icon: const Icon(LucideIcons.chevronLeft, color: WfColors.cream),
                ),
                IconButton(
                  key: const Key('row-next'),
                  onPressed: () => _scroll(1),
                  icon: const Icon(LucideIcons.chevronRight, color: WfColors.cream),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: widget.height,
            child: ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              itemCount: widget.itemCount,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: widget.itemBuilder,
            ),
          ),
        ],
      ),
    );
  }
}
```

`lib/ui/states.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/error_text.dart';
import '../app/theme.dart';
import '../l10n/gen/app_localizations.dart';

/// Blocco statico usato come "scheletro" durante il caricamento.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = 6});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: WfColors.surfaceHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
            width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
}

/// Errore di caricamento con messaggio localizzato e pulsante "Riprova".
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.circleAlert, color: WfColors.gold, size: 40),
            const SizedBox(height: 16),
            Text(describeError(l, error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(l.retry)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: esegui**

Run: `flutter test test/ui && flutter test`
Expected: PASS.

- [ ] **Step 6: commit**

```bash
git add lib/ui test/ui test/support/pump_app.dart
git commit -m "feat: add shared image, card, row, button and state widgets"
```

---

### Task 11: navigazione verso le schede e punto d'ingresso della riproduzione

**Files:**
- Create: `lib/app/navigation.dart`, `lib/features/playback/play_launcher.dart`
- Test: `test/app/navigation_test.dart`

- [ ] **Step 1: scrivi il test**

`test/app/navigation_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

import '../support/library_fakes.dart';

void main() {
  test('itemRoute', () {
    expect(itemRoute(testItem(id: 'm1')), '/item/m1');
    expect(itemRoute(testItem(id: 's1', kind: ItemKind.series)), '/item/s1');
    expect(
      itemRoute(testItem(
          id: 'e4', kind: ItemKind.episode, seriesId: 's1', seasonId: 'se1')),
      '/item/s1?season=se1',
    );
    expect(
      itemRoute(testItem(id: 'e4', kind: ItemKind.episode, seriesId: 's1')),
      '/item/s1',
    );
    expect(itemRoute(testItem(id: 'se1', kind: ItemKind.season, seriesId: 's1')),
        '/item/s1?season=se1');
    expect(itemRoute(testItem(id: 'p9', kind: ItemKind.person)), '/person/p9');
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/app/navigation_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: implementa**

`lib/app/navigation.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/jellyfin/item_models.dart';

/// Percorso da aprire per [item]: episodi e stagioni aprono la serie.
String itemRoute(JellyfinItem item) {
  final seriesId = item.seriesId;
  switch (item.kind) {
    case ItemKind.person:
      return '/person/${item.id}';
    case ItemKind.season when seriesId != null:
      return Uri(path: '/item/$seriesId', queryParameters: {'season': item.id})
          .toString();
    case ItemKind.episode when seriesId != null:
      final seasonId = item.seasonId;
      return Uri(
        path: '/item/$seriesId',
        queryParameters: seasonId == null ? null : {'season': seasonId},
      ).toString();
    default:
      return '/item/${item.id}';
  }
}

void openItem(BuildContext context, JellyfinItem item) =>
    context.push(itemRoute(item));

void openPerson(BuildContext context, PersonRef person) =>
    context.push('/person/${person.id}');
```

`lib/features/playback/play_launcher.dart`:
```dart
import 'package:flutter/material.dart';

import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Unico punto d'ingresso per avviare la riproduzione.
/// Il Piano 3 lo collega al player; per ora avvisa l'utente.
void playItem(BuildContext context, JellyfinItem item, {bool fromStart = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).playbackComingSoon)));
}
```

- [ ] **Step 4: esegui**

Run: `flutter test test/app/navigation_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/app/navigation.dart lib/features/playback test/app/navigation_test.dart
git commit -m "feat: add item navigation helpers and playback entry point"
```

---

### Task 12: Home

**Files:**
- Create: `lib/features/home/home_data.dart`, `lib/features/home/hero_carousel.dart`
- Modify (sostituzione completa): `lib/features/home/home_screen.dart`
- Test: `test/features/home/home_data_test.dart`, `test/features/home/home_screen_test.dart`
- Modify: `test/app/app_shell_test.dart` (la Home non mostra più "Ciao, Mario")

- [ ] **Step 1: scrivi i test**

`test/features/home/home_data_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/home/home_data.dart';

import '../../support/library_fakes.dart';

void main() {
  test('loadHome raccoglie tutte le righe', () async {
    final api = FakeLibraryApi()
      ..resumeItems = [testItem(id: 'r1')]
      ..nextUpItems = [testItem(id: 'n1', kind: ItemKind.episode)]
      ..onItems = (query, start, limit) {
        if (query.favoritesOnly) return pageOf([testItem(id: 'f1')]);
        if (query.kinds.contains(ItemKind.series)) {
          return pageOf([testItem(id: 's1', kind: ItemKind.series)]);
        }
        return pageOf([testItem(id: 'm1'), testItem(id: 'm2')]);
      };

    final home = await loadHome(api, 'u1');

    expect(home.resume.single.id, 'r1');
    expect(home.nextUp.single.id, 'n1');
    expect(home.latestMovies.map((i) => i.id), ['m1', 'm2']);
    expect(home.latestSeries.single.id, 's1');
    expect(home.favorites.single.id, 'f1');
    expect(home.featured.map((i) => i.id), ['m1', 's1', 'm2']);
    expect(home.isEmpty, isFalse);
  });

  test('pickFeatured: alterna film e serie, solo con sfondo, al massimo 5', () {
    const noBackdrop = JellyfinItem(id: 'x', name: 'x', kind: ItemKind.movie);
    final movies = [for (var i = 0; i < 5; i++) testItem(id: 'm$i'), noBackdrop];
    final series = [testItem(id: 's0', kind: ItemKind.series)];
    expect(pickFeatured(movies, series).map((i) => i.id),
        ['m0', 's0', 'm1', 'm2', 'm3']);
  });
}
```

`test/features/home/home_screen_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() => api = FakeLibraryApi());

  Future<void> pumpHome(WidgetTester tester) async {
    await pumpApp(tester, const HomeScreen(), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('mostra le righe con contenuti', (tester) async {
    api
      ..resumeItems = [testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)]
      ..onItems = (query, start, limit) => query.kinds.contains(ItemKind.series)
          ? pageOf([testItem(id: 's1', name: 'The Bear', kind: ItemKind.series)])
          : pageOf([testItem(id: 'm1', name: 'Dune')]);
    await pumpHome(tester);

    expect(find.text('Continua a guardare'), findsOneWidget);
    expect(find.text('Film aggiunti di recente'), findsOneWidget);
    expect(find.text('Serie aggiunte di recente'), findsOneWidget);
    expect(find.text('Oppenheimer'), findsWidgets);
    expect(find.text('Prossimi episodi'), findsNothing, reason: 'riga vuota nascosta');
  });

  testWidgets('libreria vuota', (tester) async {
    await pumpHome(tester);
    expect(find.text("Qui non c'è ancora niente."), findsOneWidget);
  });

  testWidgets('errore con riprova', (tester) async {
    api.error = const ServerUnreachableException();
    await pumpHome(tester);
    expect(find.text('Riprova'), findsOneWidget);

    api.error = null;
    api.onItems = (query, start, limit) => pageOf([testItem(id: 'm1', name: 'Dune')]);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Film aggiunti di recente'), findsOneWidget);
  });
}
```

In `test/app/app_shell_test.dart`, la Home reale ora carica la libreria. Sostituisci il `child` `const AppShell(location: '/home', child: HomeScreen())` con `const AppShell(location: '/home', child: SizedBox())`, elimina l'import di `home_screen.dart` e la riga `expect(find.text('Ciao, Mario'), findsOneWidget);`.

- [ ] **Step 2: esegui**

Run: `flutter test test/features/home`
Expected: FAIL (file mancanti).

- [ ] **Step 3: implementa**

`lib/features/home/home_data.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../core/jellyfin/library_api.dart';
import '../library/library_providers.dart';

class HomeData {
  const HomeData({
    required this.featured,
    required this.resume,
    required this.nextUp,
    required this.latestMovies,
    required this.latestSeries,
    required this.favorites,
  });

  final List<JellyfinItem> featured;
  final List<JellyfinItem> resume;
  final List<JellyfinItem> nextUp;
  final List<JellyfinItem> latestMovies;
  final List<JellyfinItem> latestSeries;
  final List<JellyfinItem> favorites;

  bool get isEmpty =>
      resume.isEmpty &&
      nextUp.isEmpty &&
      latestMovies.isEmpty &&
      latestSeries.isEmpty &&
      favorites.isEmpty;
}

/// Carica tutte le righe della Home in parallelo.
Future<HomeData> loadHome(LibraryApi api, String userId) async {
  Future<List<JellyfinItem>> latest(ItemQuery query) async =>
      (await api.items(query, userId: userId, startIndex: 0, limit: 20)).items;

  final results = await Future.wait<List<JellyfinItem>>([
    api.resume(userId, limit: 20),
    api.nextUp(userId, limit: 20),
    latest(const ItemQuery(kinds: {ItemKind.movie}, sort: CatalogSort.dateAdded)),
    latest(const ItemQuery(kinds: {ItemKind.series}, sort: CatalogSort.dateAdded)),
    latest(const ItemQuery(
      kinds: {ItemKind.movie, ItemKind.series},
      sort: CatalogSort.dateAdded,
      favoritesOnly: true,
    )),
  ]);
  return HomeData(
    featured: pickFeatured(results[2], results[3]),
    resume: results[0],
    nextUp: results[1],
    latestMovies: results[2],
    latestSeries: results[3],
    favorites: results[4],
  );
}

/// Fino a [max] titoli recenti con uno sfondo, alternando film e serie.
List<JellyfinItem> pickFeatured(
  List<JellyfinItem> movies,
  List<JellyfinItem> series, {
  int max = 5,
}) {
  final withBackdrop = [movies, series]
      .map((list) => list.where((i) => i.backdropTags.isNotEmpty).toList())
      .toList();
  final featured = <JellyfinItem>[];
  for (var i = 0; featured.length < max; i++) {
    var added = false;
    for (final list in withBackdrop) {
      if (i < list.length && featured.length < max) {
        featured.add(list[i]);
        added = true;
      }
    }
    if (!added) break;
  }
  return featured;
}

final homeProvider = FutureProvider.autoDispose<HomeData>((ref) {
  ref.watch(libraryRevisionProvider);
  return loadHome(ref.watch(libraryApiProvider), ref.watch(currentUserIdProvider));
});
```

`lib/features/home/hero_carousel.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../playback/play_launcher.dart';

/// Titoli in evidenza a tutta larghezza; cambia ogni 8 secondi.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.items});

  final List<JellyfinItem> items;

  static const interval = Duration(seconds: 8);

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(HeroCarousel.interval, (_) => _next());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (!_controller.hasClients) return;
    final next = (_index + 1) % widget.items.length;
    _controller.animateToPage(next,
        duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 460,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _HeroSlide(item: widget.items[i]),
          ),
          Positioned(
            right: 32,
            bottom: 20,
            child: Row(
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  Container(
                    width: i == _index ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: i == _index ? WfColors.gold : WfColors.creamMuted,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSlide extends ConsumerWidget {
  const _HeroSlide({required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final logo = urls.logo(item);
    final runtime = item.runtime;
    final seasons = item.childCount;
    final meta = [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.kind == ItemKind.movie && runtime != null) formatRuntime(runtime),
      if (item.kind == ItemKind.series && seasons != null) l.detailSeasons(seasons),
      ...item.genres.take(2),
    ].join(' · ');

    return Stack(
      fit: StackFit.expand,
      children: [
        WfImage(image: urls.backdrop(item)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [WfColors.bg, Color(0xCC0A0A0A), Colors.transparent],
              stops: [0, 0.35, 0.75],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [WfColors.bg, Colors.transparent],
              stops: [0, 0.45],
            ),
          ),
        ),
        Positioned(
          left: 32,
          bottom: 48,
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (logo != null)
                SizedBox(
                  height: 110,
                  width: 420,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: WfImage(image: logo, fit: BoxFit.contain),
                  ),
                )
              else
                Text(item.name.toUpperCase(),
                    maxLines: 2, style: WfText.display(56)),
              const SizedBox(height: 10),
              Text(meta, style: const TextStyle(color: WfColors.creamMuted)),
              if (item.overview != null) ...[
                const SizedBox(height: 10),
                Text(item.overview!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.45)),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  WfButton.primary(
                    label: l.actionPlay,
                    icon: LucideIcons.play,
                    onPressed: () => playItem(context, item),
                  ),
                  WfButton.secondary(
                    label: l.actionDetails,
                    icon: LucideIcons.info,
                    onPressed: () => openItem(context, item),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

`lib/features/home/home_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/landscape_card.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/states.dart';
import 'hero_carousel.dart';
import 'home_data.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final home = ref.watch(homeProvider);
    return home.when(
      loading: () => const _HomeSkeleton(),
      error: (error, _) =>
          ErrorView(error: error, onRetry: () => ref.invalidate(homeProvider)),
      data: (data) {
        if (data.isEmpty) {
          return Center(
            child: Text(l.homeEmpty,
                style: const TextStyle(color: WfColors.creamMuted)),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            if (data.featured.isNotEmpty) HeroCarousel(items: data.featured),
            if (data.resume.isNotEmpty)
              _landscapeRow(l.homeContinueWatching, data.resume),
            if (data.nextUp.isNotEmpty) _landscapeRow(l.homeNextUp, data.nextUp),
            if (data.latestMovies.isNotEmpty)
              _posterRow(l.homeLatestMovies, data.latestMovies),
            if (data.latestSeries.isNotEmpty)
              _posterRow(l.homeLatestSeries, data.latestSeries),
            if (data.favorites.isNotEmpty) _posterRow(l.navMyList, data.favorites),
          ],
        );
      },
    );
  }

  Widget _posterRow(String title, List<JellyfinItem> items) => MediaRow(
        title: title,
        height: 300,
        itemCount: items.length,
        itemBuilder: (context, i) => PosterCard(
          item: items[i],
          width: 160,
          onTap: () => openItem(context, items[i]),
        ),
      );

  Widget _landscapeRow(String title, List<JellyfinItem> items) => MediaRow(
        title: title,
        height: 230,
        itemCount: items.length,
        itemBuilder: (context, i) => LandscapeCard(
          item: items[i],
          onTap: () => openItem(context, items[i]),
        ),
      );
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SkeletonBox(height: 380),
        const SizedBox(height: 32),
        for (var row = 0; row < 2; row++) ...[
          const SkeletonBox(width: 240, height: 22),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: Row(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  const SkeletonBox(width: 160, height: 240),
                  const SizedBox(width: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: esegui**

Run: `flutter test`
Expected: PASS. Lo scheletro è largo circa 1100 px: se nei test va in overflow orizzontale, sostituisci la `Row` interna con un `ListView` orizzontale non scorrevole e segnalalo.

- [ ] **Step 5: commit**

```bash
git add lib/features/home test/features/home test/app/app_shell_test.dart
git commit -m "feat: add Home with featured carousel and library rows"
```

---

### Task 13: controller del catalogo

**Files:**
- Create: `lib/features/catalog/catalog_controller.dart`
- Test: `test/features/catalog/catalog_controller_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/catalog/catalog_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;
  late ProviderContainer container;
  final provider = catalogControllerProvider(ItemKind.movie);

  List<JellyfinItem> items(int from, int count) =>
      [for (var i = from; i < from + count; i++) testItem(id: 'm$i')];

  setUp(() {
    api = FakeLibraryApi()
      ..onItems = (query, start, limit) =>
          pageOf(items(start, start + limit > 150 ? 150 - start : limit), 150);
    container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
    container.listen(provider, (_, _) {});
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('prima pagina all\'avvio', () async {
    expect(container.read(provider).loading, isTrue);
    await settle();
    final state = container.read(provider);
    expect(state.items, hasLength(100));
    expect(state.total, 150);
    expect(state.hasMore, isTrue);
    expect(api.itemQueries.single.kinds, {ItemKind.movie});
  });

  test('loadMore aggiunge la pagina successiva e si ferma alla fine', () async {
    await settle();
    await container.read(provider.notifier).loadMore();
    expect(container.read(provider).items, hasLength(150));
    expect(container.read(provider).hasMore, isFalse);
    await container.read(provider.notifier).loadMore();
    expect(api.itemQueries, hasLength(2));
  });

  test('setQuery riparte da zero con i nuovi filtri', () async {
    await settle();
    await container
        .read(provider.notifier)
        .setQuery(const ItemQuery(kinds: {ItemKind.movie}, sort: CatalogSort.year));
    expect(container.read(provider).query.sort, CatalogSort.year);
    expect(container.read(provider).items.first.id, 'm0');
    expect(api.itemQueries.last.sort, CatalogSort.year);
  });

  test('errore e riprova', () async {
    api.error = const ServerUnreachableException();
    await settle();
    expect(container.read(provider).error, isA<ServerUnreachableException>());
    api.error = null;
    await container.read(provider.notifier).retry();
    expect(container.read(provider).items, hasLength(100));
    expect(container.read(provider).error, isNull);
  });

  test('una risposta superata da una query più recente viene ignorata', () async {
    await settle();
    api.delay = const Duration(milliseconds: 50);
    final controller = container.read(provider.notifier);
    final slow = controller.setQuery(
        const ItemQuery(kinds: {ItemKind.movie}, sort: CatalogSort.rating));
    api.delay = Duration.zero;
    await controller.setQuery(
        const ItemQuery(kinds: {ItemKind.movie}, sort: CatalogSort.year));
    await slow;
    expect(container.read(provider).query.sort, CatalogSort.year);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/features/catalog/catalog_controller_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: implementa**

`lib/features/catalog/catalog_controller.dart`:
```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../library/library_providers.dart';

class CatalogState {
  const CatalogState({
    required this.query,
    this.items = const [],
    this.total = 0,
    this.loading = false,
    this.error,
  });

  final ItemQuery query;
  final List<JellyfinItem> items;
  final int total;
  final bool loading;
  final Object? error;

  bool get hasMore => items.length < total;
}

/// Griglia paginata di Film o Serie con ordinamento e filtri.
class CatalogController extends Notifier<CatalogState> {
  CatalogController(this.kind);

  final ItemKind kind;

  static const pageSize = 100;

  int _generation = 0;

  @override
  CatalogState build() {
    final query = ItemQuery(kinds: {kind});
    Future.microtask(() => _load(query, reset: true));
    return CatalogState(query: query, loading: true);
  }

  Future<void> setQuery(ItemQuery query) => _load(query, reset: true);

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    await _load(state.query, reset: false);
  }

  Future<void> retry() => _load(state.query, reset: state.items.isEmpty);

  Future<void> _load(ItemQuery query, {required bool reset}) async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final previous = reset ? const <JellyfinItem>[] : state.items;
    state = CatalogState(
      query: query,
      items: previous,
      total: reset ? 0 : state.total,
      loading: true,
    );
    try {
      final page = await ref.read(libraryApiProvider).items(
            query,
            userId: ref.read(currentUserIdProvider),
            startIndex: previous.length,
            limit: pageSize,
          );
      if (!ref.mounted || generation != _generation) return;
      state = CatalogState(
          query: query, items: [...previous, ...page.items], total: page.totalCount);
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = CatalogState(
          query: query, items: previous, total: state.total, error: error);
    }
  }
}

final catalogControllerProvider = NotifierProvider.autoDispose
    .family<CatalogController, CatalogState, ItemKind>(CatalogController.new);

final catalogFiltersProvider =
    FutureProvider.autoDispose.family<LibraryFilters, ItemKind>((ref, kind) =>
        ref.watch(libraryApiProvider).filters(ref.watch(currentUserIdProvider), kind));
```
(Se con la versione di Riverpod installata la sintassi `NotifierProvider.autoDispose.family<…>(CatalogController.new)` non compila, usa la forma equivalente documentata nel pacchetto per i Notifier con argomento, e segnalalo.)

- [ ] **Step 4: esegui**

Run: `flutter test test/features/catalog/catalog_controller_test.dart`
Expected: PASS (5 test).

- [ ] **Step 5: commit**

```bash
git add lib/features/catalog/catalog_controller.dart test/features/catalog/catalog_controller_test.dart
git commit -m "feat: add paginated catalog controller"
```

---

### Task 14: schermata Catalogo (Film / Serie)

**Files:**
- Create: `lib/features/catalog/catalog_filters_bar.dart`, `lib/features/catalog/catalog_screen.dart`
- Test: `test/features/catalog/catalog_screen_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/catalog/catalog_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..libraryFilters = const LibraryFilters(genres: ['Dramma'], years: [2024])
      ..onItems = (query, start, limit) => query.watched == WatchedFilter.watched
          ? pageOf([])
          : pageOf([testItem(id: 'm1', name: 'Dune'), testItem(id: 'm2', name: 'Alien')]);
  });

  Future<void> pumpCatalog(WidgetTester tester) async {
    await pumpApp(tester, const CatalogScreen(kind: ItemKind.movie), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('titolo, conteggio e griglia', (tester) async {
    await pumpCatalog(tester);
    expect(find.text('FILM'), findsOneWidget);
    expect(find.text('2 titoli'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Alien'), findsOneWidget);
  });

  testWidgets('filtro "Visti" senza risultati e azzeramento', (tester) async {
    await pumpCatalog(tester);
    await tester.tap(find.text('Visti'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nessun titolo con questi filtri.'), findsOneWidget);
    expect(api.itemQueries.last.watched, WatchedFilter.watched);

    await tester.tap(find.text('Azzera filtri').last);
    await tester.pump();
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('errore con riprova', (tester) async {
    api.error = const ServerUnreachableException();
    await pumpCatalog(tester);
    expect(find.text('Riprova'), findsOneWidget);
    api.error = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/features/catalog/catalog_screen_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: implementa**

`lib/features/catalog/catalog_filters_bar.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import 'catalog_controller.dart';

/// Ordinamento, genere, anno e visto/non visto.
class CatalogFiltersBar extends ConsumerWidget {
  const CatalogFiltersBar({
    super.key,
    required this.kind,
    required this.query,
    required this.onChanged,
  });

  final ItemKind kind;
  final ItemQuery query;
  final ValueChanged<ItemQuery> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final filters =
        ref.watch(catalogFiltersProvider(kind)).value ?? const LibraryFilters();
    final genre = query.genres.isEmpty ? null : query.genres.first;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Picker<CatalogSort>(
          value: query.sort,
          items: {
            CatalogSort.title: '${l.catalogSortLabel}: ${l.catalogSortTitle}',
            CatalogSort.dateAdded: '${l.catalogSortLabel}: ${l.catalogSortDateAdded}',
            CatalogSort.year: '${l.catalogSortLabel}: ${l.catalogSortYear}',
            CatalogSort.rating: '${l.catalogSortLabel}: ${l.catalogSortRating}',
          },
          onChanged: (sort) => onChanged(query.copyWith(sort: sort)),
        ),
        _Picker<String?>(
          value: genre,
          items: {
            null: l.catalogAllGenres,
            for (final g in filters.genres) g: g,
          },
          onChanged: (g) =>
              onChanged(query.copyWith(genres: g == null ? const {} : {g})),
        ),
        _Picker<int?>(
          value: query.year,
          items: {
            null: l.catalogAllYears,
            for (final y in filters.years) y: '$y',
          },
          onChanged: (y) => onChanged(query.copyWith(year: y)),
        ),
        SegmentedButton<WatchedFilter>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: WatchedFilter.all, label: Text(l.catalogWatchedAll)),
            ButtonSegment(
                value: WatchedFilter.unwatched,
                label: Text(l.catalogWatchedUnwatched)),
            ButtonSegment(
                value: WatchedFilter.watched, label: Text(l.catalogWatchedWatched)),
          ],
          selected: {query.watched},
          onSelectionChanged: (s) => onChanged(query.copyWith(watched: s.first)),
        ),
        if (query.hasFilters)
          TextButton(
            onPressed: () => onChanged(ItemQuery(kinds: query.kinds, sort: query.sort)),
            child: Text(l.catalogClearFilters),
          ),
      ],
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({required this.value, required this.items, required this.onChanged});

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: WfColors.surfaceHigh,
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.containsKey(value) ? value : null,
          dropdownColor: WfColors.surface,
          style: const TextStyle(color: WfColors.cream, fontSize: 13.5),
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) => onChanged(v as T),
        ),
      ),
    );
  }
}
```

`lib/features/catalog/catalog_screen.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/states.dart';
import 'catalog_controller.dart';
import 'catalog_filters_bar.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, required this.kind});

  final ItemKind kind;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) {
        unawaited(
            ref.read(catalogControllerProvider(widget.kind).notifier).loadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = catalogControllerProvider(widget.kind);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final title = widget.kind == ItemKind.series ? l.navSeries : l.navMovies;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(title.toUpperCase(), style: WfText.display(40)),
              const SizedBox(width: 16),
              if (state.total > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(l.catalogCount(state.total),
                      style: const TextStyle(color: WfColors.creamMuted)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: CatalogFiltersBar(
            kind: widget.kind,
            query: state.query,
            onChanged: (query) => unawaited(controller.setQuery(query)),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: _body(context, l, state, controller)),
      ],
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, CatalogState state,
      CatalogController controller) {
    if (state.items.isEmpty) {
      if (state.loading) return const LoadingView();
      final error = state.error;
      if (error != null) {
        return ErrorView(error: error, onRetry: () => unawaited(controller.retry()));
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.catalogEmpty, style: const TextStyle(color: WfColors.creamMuted)),
            if (state.query.hasFilters)
              TextButton(
                onPressed: () => unawaited(controller.setQuery(
                    ItemQuery(kinds: state.query.kinds, sort: state.query.sort))),
                child: Text(l.catalogClearFilters),
              ),
          ],
        ),
      );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 24,
              crossAxisSpacing: 16,
              childAspectRatio: 0.55,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => PosterCard(
                item: state.items[i],
                onTap: () => openItem(context, state.items[i]),
              ),
              childCount: state.items.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: state.loading
                ? const LoadingView()
                : state.error != null
                    ? Center(
                        child: TextButton(
                          onPressed: () => unawaited(controller.retry()),
                          child: Text(l.retry),
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: esegui**

Run: `flutter test test/features/catalog`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/catalog test/features/catalog/catalog_screen_test.dart
git commit -m "feat: add catalog screen with sort and filters"
```

---
### Task 15: scheda di un film

**Files:**
- Create: `lib/features/detail/detail_providers.dart`, `lib/features/detail/primary_action.dart`, `lib/features/detail/detail_header.dart`, `lib/features/detail/detail_rows.dart`, `lib/features/detail/movie_detail_view.dart`, `lib/features/detail/item_detail_screen.dart`
- Test: `test/features/detail/primary_action_test.dart`, `test/features/detail/movie_detail_test.dart`

`ItemDetailScreen` carica l'elemento e sceglie la vista. In questo task esiste solo `MovieDetailView`, usata per film ed episodi; le serie arrivano nel Task 16.

- [ ] **Step 1: scrivi i test**

`test/features/detail/primary_action_test.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/detail/primary_action.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/library_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('film non iniziato → Riproduci', () {
    final movie = testItem();
    final action = primaryActionFor(movie, movie.userData);
    expect(action, isA<PlayAction>());
    expect(primaryActionLabel(l, action), 'Riproduci');
  });

  test('film iniziato → Riprendi da mm:ss', () {
    final movie = testItem(positionTicks: 13940000000, playedPercentage: 20);
    final action = primaryActionFor(movie, movie.userData);
    expect(action, isA<ResumeAction>());
    expect(primaryActionLabel(l, action), 'Riprendi da 23:14');
  });

  test('film già visto → Riproduci', () {
    final movie = testItem(played: true, positionTicks: 100);
    expect(primaryActionFor(movie, movie.userData), isA<PlayAction>());
  });

  test('episodio: codice nella label', () {
    final ep = testItem(id: 'e5', kind: ItemKind.episode, index: 5, seasonIndex: 1);
    expect(primaryActionLabel(l, primaryActionFor(ep, ep.userData)),
        'Riproduci S1:E5');
    final started = testItem(
        id: 'e4',
        kind: ItemKind.episode,
        index: 4,
        seasonIndex: 1,
        positionTicks: 13940000000,
        playedPercentage: 50);
    expect(primaryActionLabel(l, primaryActionFor(started, started.userData)),
        'Riprendi S1:E4 · 23:14');
  });
}
```

`test/features/detail/movie_detail_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['m1'] = testItem(
        id: 'm1',
        name: 'Dune: Parte Due',
        overview: 'Paul Atreides si unisce ai Fremen.',
        positionTicks: 13940000000,
        playedPercentage: 20,
        people: [
          {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor'},
        ],
        trailers: [
          {'Url': 'https://youtube.com/watch?v=x'},
        ],
      )
      ..similarItems = [testItem(id: 'm2', name: 'Arrival')];
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    await pumpApp(tester, const ItemDetailScreen(itemId: 'm1'), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('titolo, trama, azioni, cast e simili', (tester) async {
    await pumpDetail(tester);
    expect(find.text('DUNE: PARTE DUE'), findsOneWidget);
    expect(find.text('Paul Atreides si unisce ai Fremen.'), findsOneWidget);
    expect(find.text('Riprendi da 23:14'), findsOneWidget);
    expect(find.text('Ricomincia'), findsOneWidget);
    expect(find.text('Trailer'), findsOneWidget);
    expect(find.text('Zendaya'), findsOneWidget);
    expect(find.text('Chani'), findsOneWidget);
    expect(find.text('Simili'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
  });

  testWidgets('cuore: aggiunge a La mia lista', (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.byTooltip('Aggiungi a La mia lista'));
    await tester.pump();
    expect(api.favoriteCalls, [('m1', true)]);
    expect(find.byTooltip('Rimuovi da La mia lista'), findsOneWidget);
  });

  testWidgets('segna come visto', (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.byTooltip('Segna come visto'));
    await tester.pump();
    expect(api.playedCalls, [('m1', true)]);
  });

  testWidgets('elemento inesistente: errore con riprova', (tester) async {
    api.itemsById.clear();
    await pumpDetail(tester);
    expect(find.text('Riprova'), findsOneWidget);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/features/detail`
Expected: FAIL (file mancanti).

- [ ] **Step 3: implementa**

`lib/features/detail/detail_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../library/library_providers.dart';

final itemProvider =
    FutureProvider.autoDispose.family<JellyfinItem, String>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(libraryApiProvider).item(ref.watch(currentUserIdProvider), id);
});

final similarProvider =
    FutureProvider.autoDispose.family<List<JellyfinItem>, String>((ref, id) =>
        ref.watch(libraryApiProvider).similar(ref.watch(currentUserIdProvider), id));

final seasonsProvider =
    FutureProvider.autoDispose.family<List<JellyfinItem>, String>((ref, seriesId) {
  ref.watch(libraryRevisionProvider);
  return ref
      .watch(libraryApiProvider)
      .seasons(ref.watch(currentUserIdProvider), seriesId);
});

final episodesProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, ({String seriesId, String seasonId})>((ref, key) {
  ref.watch(libraryRevisionProvider);
  return ref
      .watch(libraryApiProvider)
      .episodes(ref.watch(currentUserIdProvider), key.seriesId, key.seasonId);
});

/// Episodio da proporre per una serie: il prossimo (o quello iniziato), oppure
/// il primo della prima stagione.
final seriesNextEpisodeProvider =
    FutureProvider.autoDispose.family<JellyfinItem?, String>((ref, seriesId) async {
  ref.watch(libraryRevisionProvider);
  final api = ref.watch(libraryApiProvider);
  final userId = ref.watch(currentUserIdProvider);
  final next =
      await api.nextUp(userId, seriesId: seriesId, limit: 1, enableResumable: true);
  if (next.isNotEmpty) return next.first;
  final seasons = await ref.watch(seasonsProvider(seriesId).future);
  final regular = seasons.where((s) => (s.indexNumber ?? 0) > 0);
  final first = regular.isNotEmpty ? regular.first : seasons.firstOrNull;
  if (first == null) return null;
  final episodes = await api.episodes(userId, seriesId, first.id);
  return episodes.firstOrNull;
});
```

`lib/features/detail/primary_action.dart`:
```dart
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';

/// Azione del pulsante principale di una scheda.
sealed class PrimaryAction {
  const PrimaryAction(this.target);

  /// Elemento da riprodurre (per le serie: l'episodio).
  final JellyfinItem target;
}

final class PlayAction extends PrimaryAction {
  const PlayAction(super.target);
}

final class ResumeAction extends PrimaryAction {
  const ResumeAction(super.target, this.position);

  final Duration position;
}

PrimaryAction primaryActionFor(JellyfinItem target, UserItemData userData) =>
    userData.playbackPositionTicks > 0 && !userData.played
        ? ResumeAction(target, userData.playbackPosition)
        : PlayAction(target);

String primaryActionLabel(AppLocalizations l, PrimaryAction action) {
  final code = episodeCode(action.target);
  return switch (action) {
    ResumeAction(:final position) when code != null =>
      '${l.actionResumeEpisode(code)} · ${formatClock(position)}',
    ResumeAction(:final position) => l.actionResumeAt(formatClock(position)),
    PlayAction() when code != null => l.actionPlayEpisode(code),
    PlayAction() => l.actionPlay,
  };
}
```

`lib/features/detail/detail_header.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import 'primary_action.dart';

/// Parte alta di una scheda: sfondo, logo o titolo, dati, trama, azioni.
class DetailHeader extends ConsumerWidget {
  const DetailHeader({super.key, required this.item, required this.primary});

  final JellyfinItem item;

  /// `null` finché non si sa cosa riprodurre (serie ancora in caricamento).
  final PrimaryAction? primary;

  Future<void> _toggle(BuildContext context, Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final userData = watchUserData(ref, item);
    final overrides = ref.read(userDataOverridesProvider.notifier);
    final logo = urls.logo(item);
    final action = primary;
    final overview = item.overview;

    return SizedBox(
      height: 560,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WfImage(image: urls.backdrop(item)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [WfColors.bg, Color(0xD90A0A0A), Colors.transparent],
                stops: [0, 0.4, 0.8],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [WfColors.bg, Colors.transparent],
                stops: [0, 0.5],
              ),
            ),
          ),
          Positioned(
            left: 32,
            right: 32,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo != null)
                  SizedBox(
                    height: 120,
                    width: 460,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: WfImage(image: logo, fit: BoxFit.contain),
                    ),
                  )
                else
                  Text(item.name.toUpperCase(),
                      maxLines: 2, style: WfText.display(56)),
                const SizedBox(height: 12),
                MetaLine(item: item),
                if (item.genres.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(item.genres.join(' · '),
                      style: const TextStyle(color: WfColors.creamMuted)),
                ],
                if (overview != null) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Text(overview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.45)),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (action != null)
                      WfButton.primary(
                        label: primaryActionLabel(l, action),
                        icon: LucideIcons.play,
                        onPressed: () => playItem(context, action.target),
                      ),
                    if (action is ResumeAction)
                      WfButton.secondary(
                        label: l.actionRestart,
                        icon: LucideIcons.rotateCcw,
                        onPressed: () =>
                            playItem(context, action.target, fromStart: true),
                      ),
                    if (item.remoteTrailers.isNotEmpty)
                      WfButton.secondary(
                        label: l.actionTrailer,
                        icon: LucideIcons.clapperboard,
                        onPressed: () => unawaited(launchUrl(
                          Uri.parse(item.remoteTrailers.first.url),
                          mode: LaunchMode.externalApplication,
                        )),
                      ),
                    WfIconToggle(
                      icon: LucideIcons.heart,
                      selected: userData.isFavorite,
                      tooltip: userData.isFavorite
                          ? l.actionRemoveFromList
                          : l.actionAddToList,
                      onPressed: () => unawaited(
                          _toggle(context, () => overrides.toggleFavorite(item))),
                    ),
                    WfIconToggle(
                      icon: LucideIcons.check,
                      selected: userData.played,
                      tooltip: userData.played
                          ? l.actionMarkUnwatched
                          : l.actionMarkWatched,
                      onPressed: () => unawaited(
                          _toggle(context, () => overrides.togglePlayed(item))),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "2024 · 2h 46m · ★ 8.4 · [PG-13]".
class MetaLine extends StatelessWidget {
  const MetaLine({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final runtime = item.runtime;
    final seasons = item.childCount;
    final rating = item.communityRating;
    final official = item.officialRating;
    const muted = TextStyle(color: WfColors.creamMuted);
    final parts = [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.kind != ItemKind.series && runtime != null) formatRuntime(runtime),
      if (item.kind == ItemKind.series && seasons != null) l.detailSeasons(seasons),
    ];
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (parts.isNotEmpty) Text(parts.join(' · '), style: muted),
        if (rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.star, size: 14, color: WfColors.gold),
              const SizedBox(width: 4),
              Text(rating.toStringAsFixed(1),
                  style: const TextStyle(
                      color: WfColors.gold, fontWeight: FontWeight.w600)),
            ],
          ),
        if (official != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: WfColors.creamMuted),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(official, style: muted.copyWith(fontSize: 12)),
          ),
      ],
    );
  }
}
```

`lib/features/detail/detail_rows.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import 'detail_providers.dart';

class CastRow extends ConsumerWidget {
  const CastRow({super.key, required this.people});

  final List<PersonRef> people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    return MediaRow(
      title: AppLocalizations.of(context).detailCast,
      height: 170,
      itemCount: people.length,
      itemBuilder: (context, i) {
        final person = people[i];
        final role = person.role;
        return GestureDetector(
          onTap: () => openPerson(context, person),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              width: 110,
              child: Column(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: WfImage(
                          image: urls.person(person),
                          fallbackIcon: LucideIcons.user),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(person.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                  if (role != null && role.isNotEmpty)
                    Text(role,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: WfColors.creamMuted)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Riga "Simili": se il caricamento fallisce non mostra nulla (non è essenziale).
class SimilarRow extends ConsumerWidget {
  const SimilarRow({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(similarProvider(itemId)).value ?? const <JellyfinItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return MediaRow(
      title: AppLocalizations.of(context).detailSimilar,
      height: 300,
      itemCount: items.length,
      itemBuilder: (context, i) => PosterCard(
        item: items[i],
        width: 160,
        onTap: () => openItem(context, items[i]),
      ),
    );
  }
}
```

`lib/features/detail/movie_detail_view.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../library/user_data.dart';
import 'detail_header.dart';
import 'detail_rows.dart';
import 'primary_action.dart';

/// Scheda di un film (usata anche per un episodio aperto direttamente).
class MovieDetailView extends ConsumerWidget {
  const MovieDetailView({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = watchUserData(ref, item);
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        DetailHeader(item: item, primary: primaryActionFor(item, userData)),
        if (item.people.isNotEmpty) CastRow(people: item.people),
        SimilarRow(itemId: item.id),
      ],
    );
  }
}
```

`lib/features/detail/item_detail_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/states.dart';
import 'detail_providers.dart';
import 'movie_detail_view.dart';

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({super.key, required this.itemId, this.seasonId});

  final String itemId;

  /// Stagione da mostrare aperta (solo per le serie).
  final String? seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(itemProvider(itemId)).when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorView(
              error: error, onRetry: () => ref.invalidate(itemProvider(itemId))),
          data: (item) => MovieDetailView(item: item),
        );
  }
}
```

- [ ] **Step 4: esegui**

Run: `flutter test test/features/detail && flutter test`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/detail test/features/detail
git commit -m "feat: add movie detail with actions, cast and similar titles"
```

---

### Task 16: scheda di una serie

**Files:**
- Create: `lib/features/detail/series_detail_view.dart`
- Modify: `lib/features/detail/item_detail_screen.dart`
- Test: `test/features/detail/series_detail_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/detail/series_detail_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

JellyfinItem ep(String id, String season, int seasonIndex, int index,
        {bool played = false, int position = 0, double? pct}) =>
    testItem(
      id: id,
      name: 'Episodio $index',
      kind: ItemKind.episode,
      seriesId: 's1',
      seriesName: 'The Last of Us',
      seasonId: season,
      seasonIndex: seasonIndex,
      index: index,
      runtimeMinutes: 45,
      played: played,
      positionTicks: position,
      playedPercentage: pct,
    );

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['s1'] =
          testItem(id: 's1', name: 'The Last of Us', kind: ItemKind.series, childCount: 2)
      ..seasonsBySeries['s1'] = [
        testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.season, index: 1),
        testItem(id: 'se2', name: 'Stagione 2', kind: ItemKind.season, index: 2),
      ]
      ..episodesBySeason['se1'] = [
        ep('e3', 'se1', 1, 3, played: true),
        ep('e4', 'se1', 1, 4, position: 13940000000, pct: 50),
      ]
      ..episodesBySeason['se2'] = [ep('e21', 'se2', 2, 1)]
      ..nextUpItems = [ep('e4', 'se1', 1, 4, position: 13940000000, pct: 50)];
  });

  Future<void> pumpSeries(WidgetTester tester, {String? seasonId}) async {
    await pumpApp(tester, ItemDetailScreen(itemId: 's1', seasonId: seasonId),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ]);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('prossimo episodio, stagioni ed episodi', (tester) async {
    await pumpSeries(tester);
    expect(find.text('THE LAST OF US'), findsOneWidget);
    expect(find.text('2024 · 2 stagioni'), findsOneWidget);
    expect(find.text('Riprendi S1:E4 · 23:14'), findsOneWidget);
    expect(find.text('Stagione 1'), findsOneWidget);
    expect(find.text('Stagione 2'), findsOneWidget);
    expect(find.text('3. Episodio 3'), findsOneWidget);
    expect(find.text('4. Episodio 4'), findsOneWidget);
    expect(api.nextUpCalls, contains('s1'));
  });

  testWidgets('cambio stagione', (tester) async {
    await pumpSeries(tester);
    await tester.tap(find.text('Stagione 2'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1. Episodio 1'), findsOneWidget);
    expect(find.text('3. Episodio 3'), findsNothing);
  });

  testWidgets('stagione iniziale da parametro', (tester) async {
    await pumpSeries(tester, seasonId: 'se2');
    expect(find.text('1. Episodio 1'), findsOneWidget);
  });

  testWidgets('nessun NextUp: propone il primo episodio', (tester) async {
    api.nextUpItems = [];
    await pumpSeries(tester);
    expect(find.text('Riproduci S1:E3'), findsOneWidget);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/features/detail/series_detail_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/features/detail/series_detail_view.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import 'detail_header.dart';
import 'detail_providers.dart';
import 'detail_rows.dart';
import 'primary_action.dart';

class SeriesDetailView extends ConsumerStatefulWidget {
  const SeriesDetailView({super.key, required this.series, this.initialSeasonId});

  final JellyfinItem series;
  final String? initialSeasonId;

  @override
  ConsumerState<SeriesDetailView> createState() => _SeriesDetailViewState();
}

class _SeriesDetailViewState extends ConsumerState<SeriesDetailView> {
  String? _selectedSeasonId;

  String? _seasonToShow(List<JellyfinItem> seasons, JellyfinItem? next) {
    final ids = seasons.map((s) => s.id).toSet();
    for (final candidate in [_selectedSeasonId, widget.initialSeasonId, next?.seasonId]) {
      if (candidate != null && ids.contains(candidate)) return candidate;
    }
    final regular = seasons.where((s) => (s.indexNumber ?? 0) > 0);
    return (regular.isNotEmpty ? regular.first : seasons.firstOrNull)?.id;
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final next = ref.watch(seriesNextEpisodeProvider(series.id)).value;
    final primary = next == null ? null : primaryActionFor(next, watchUserData(ref, next));
    final seasons = ref.watch(seasonsProvider(series.id));

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        DetailHeader(item: series, primary: primary),
        seasons.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(32), child: LoadingView()),
          error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.invalidate(seasonsProvider(series.id))),
          data: (list) {
            final seasonId = _seasonToShow(list, next);
            if (seasonId == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SeasonTabs(
                  seasons: list,
                  selectedId: seasonId,
                  onSelect: (id) => setState(() => _selectedSeasonId = id),
                ),
                _EpisodeList(
                    seriesId: series.id, seasonId: seasonId, highlightId: next?.id),
              ],
            );
          },
        ),
        if (series.people.isNotEmpty) CastRow(people: series.people),
        SimilarRow(itemId: series.id),
      ],
    );
  }
}

class _SeasonTabs extends StatelessWidget {
  const _SeasonTabs({
    required this.seasons,
    required this.selectedId,
    required this.onSelect,
  });

  final List<JellyfinItem> seasons;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Wrap(
        children: [
          for (final season in seasons)
            InkWell(
              onTap: () => onSelect(season.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: season.id == selectedId
                          ? WfColors.gold
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  season.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: season.id == selectedId ? WfColors.gold : WfColors.cream,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EpisodeList extends ConsumerWidget {
  const _EpisodeList({
    required this.seriesId,
    required this.seasonId,
    required this.highlightId,
  });

  final String seriesId;
  final String seasonId;
  final String? highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (seriesId: seriesId, seasonId: seasonId);
    return ref.watch(episodesProvider(key)).when(
          loading: () =>
              const Padding(padding: EdgeInsets.all(32), child: LoadingView()),
          error: (error, _) => ErrorView(
              error: error, onRetry: () => ref.invalidate(episodesProvider(key))),
          data: (episodes) {
            if (episodes.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Text(AppLocalizations.of(context).detailNoEpisodes,
                    style: const TextStyle(color: WfColors.creamMuted)),
              );
            }
            return Column(
              children: [
                for (final episode in episodes)
                  EpisodeTile(
                      episode: episode, highlighted: episode.id == highlightId),
              ],
            );
          },
        );
  }
}

class EpisodeTile extends ConsumerWidget {
  const EpisodeTile({super.key, required this.episode, this.highlighted = false});

  final JellyfinItem episode;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final userData = watchUserData(ref, episode);
    final progress = userData.progress;
    final runtime = episode.runtime;
    final index = episode.indexNumber;
    final details = [
      if (runtime != null) formatRuntime(runtime),
      if (progress != null && runtime != null)
        l.detailRemaining(formatRuntime(runtime - userData.playbackPosition)),
    ].join(' · ');
    final overview = episode.overview;

    return InkWell(
      onTap: () => playItem(context, episode),
      child: Container(
        color: highlighted ? WfColors.surface : null,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      WfImage(image: ref.watch(imageUrlsProvider).landscape(episode)),
                      if (progress != null) ProgressStrip(progress: progress),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(index == null ? episode.name : '$index. ${episode.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(details,
                        style: const TextStyle(
                            color: WfColors.creamMuted, fontSize: 12.5)),
                  ],
                  if (overview != null) ...[
                    const SizedBox(height: 6),
                    Text(overview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: WfColors.creamMuted, fontSize: 12.5, height: 1.4)),
                  ],
                ],
              ),
            ),
            if (userData.played)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: WatchedBadge(),
              ),
          ],
        ),
      ),
    );
  }
}
```

In `lib/features/detail/item_detail_screen.dart` aggiungi gli import:
```dart
import '../../core/jellyfin/item_models.dart';
import 'series_detail_view.dart';
```
e sostituisci `data: (item) => MovieDetailView(item: item),` con:
```dart
          data: (item) => item.kind == ItemKind.series
              ? SeriesDetailView(series: item, initialSeasonId: seasonId)
              : MovieDetailView(item: item),
```

- [ ] **Step 4: esegui**

Run: `flutter test test/features/detail && flutter test`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/detail test/features/detail/series_detail_test.dart
git commit -m "feat: add series detail with seasons, episodes and next episode"
```

---

### Task 17: pagina attore

**Files:**
- Create: `lib/features/person/person_screen.dart`
- Test: `test/features/person/person_screen_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/person/person_screen_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/person/person_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  testWidgets('biografia e filmografia sul server', (tester) async {
    final api = FakeLibraryApi()
      ..itemsById['p9'] = testItem(
          id: 'p9',
          name: 'Zendaya',
          kind: ItemKind.person,
          year: null,
          overview: 'Attrice statunitense.')
      ..onItems = (query, start, limit) => query.personId == 'p9'
          ? pageOf([testItem(id: 'm1', name: 'Dune'), testItem(id: 'm2', name: 'Challengers')])
          : pageOf([]);

    await pumpApp(tester, const PersonScreen(personId: 'p9'), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('ZENDAYA'), findsOneWidget);
    expect(find.text('Attrice statunitense.'), findsOneWidget);
    expect(find.text('Su WonderFlix'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Challengers'), findsOneWidget);
    expect(api.itemQueries.last.kinds, {ItemKind.movie, ItemKind.series});
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/features/person`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/features/person/person_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../detail/detail_providers.dart';
import '../library/library_providers.dart';

/// Film e serie del server in cui compare la persona, dal più recente.
final filmographyProvider =
    FutureProvider.autoDispose.family<List<JellyfinItem>, String>((ref, personId) async {
  final page = await ref.watch(libraryApiProvider).items(
        ItemQuery(
          kinds: const {ItemKind.movie, ItemKind.series},
          sort: CatalogSort.year,
          personId: personId,
        ),
        userId: ref.watch(currentUserIdProvider),
        startIndex: 0,
        limit: 200,
      );
  return page.items;
});

class PersonScreen extends ConsumerWidget {
  const PersonScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return ref.watch(itemProvider(personId)).when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorView(
              error: error, onRetry: () => ref.invalidate(itemProvider(personId))),
          data: (person) {
            final films = ref.watch(filmographyProvider(personId));
            final bio = person.overview;
            return ListView(
              padding: const EdgeInsets.all(32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 200,
                        height: 300,
                        child: WfImage(
                          image: ref.watch(imageUrlsProvider).poster(person),
                          fallbackIcon: LucideIcons.user,
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(person.name.toUpperCase(), style: WfText.display(48)),
                          if (bio != null) ...[
                            const SizedBox(height: 12),
                            Text(bio,
                                maxLines: 10,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(height: 1.5)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(l.personOnServer, style: WfText.display(28)),
                const SizedBox(height: 16),
                films.when(
                  loading: () => const LoadingView(),
                  error: (error, _) => ErrorView(
                      error: error,
                      onRetry: () => ref.invalidate(filmographyProvider(personId))),
                  data: (items) => Wrap(
                    spacing: 16,
                    runSpacing: 24,
                    children: [
                      for (final item in items)
                        PosterCard(
                          item: item,
                          width: 160,
                          onTap: () => openItem(context, item),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
  }
}
```

- [ ] **Step 4: esegui**

Run: `flutter test test/features/person && flutter test`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/person test/features/person
git commit -m "feat: add person page with filmography on the server"
```

---

### Task 18: ricerca

**Files:**
- Create: `lib/features/search/search_controller.dart`, `lib/features/search/search_screen.dart`
- Test: `test/features/search/search_controller_test.dart`, `test/features/search/search_screen_test.dart`

- [ ] **Step 1: scrivi i test**

`test/features/search/search_controller_test.dart`:
```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/search/search_controller.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
    container.listen(searchControllerProvider, (_, _) {});
    return container;
  }

  setUp(() {
    api = FakeLibraryApi()
      ..onItems = (query, start, limit) => query.kinds.contains(ItemKind.series)
          ? pageOf([testItem(id: 's1', name: 'Dune: Prophecy', kind: ItemKind.series)])
          : pageOf([testItem(id: 'm1', name: 'Dune')])
      ..people = [testItem(id: 'p1', name: 'Denis Villeneuve', kind: ItemKind.person)];
  });

  test('meno di 2 lettere: nessuna ricerca', () {
    fakeAsync((async) {
      final container = makeContainer();
      container.read(searchControllerProvider.notifier).setTerm('d');
      async.elapse(const Duration(seconds: 1));
      expect(api.itemQueries, isEmpty);
      expect(container.read(searchControllerProvider).results, isNull);
    });
  });

  test('attende 300 ms dall\'ultima lettera e cerca una volta', () {
    fakeAsync((async) {
      final container = makeContainer();
      final controller = container.read(searchControllerProvider.notifier);
      controller.setTerm('du');
      async.elapse(const Duration(milliseconds: 200));
      controller.setTerm('dune');
      async.elapse(const Duration(milliseconds: 299));
      expect(api.itemQueries, isEmpty);
      async.elapse(const Duration(milliseconds: 2));
      async.flushMicrotasks();

      expect(api.itemQueries.map((q) => q.searchTerm).toSet(), {'dune'});
      final results = container.read(searchControllerProvider).results!;
      expect(results.movies.single.name, 'Dune');
      expect(results.series.single.name, 'Dune: Prophecy');
      expect(results.people.single.name, 'Denis Villeneuve');
      expect(results.isEmpty, isFalse);
    });
  });
}
```

`test/features/search/search_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/search/search_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  testWidgets('scrive, attende e mostra i risultati per sezione', (tester) async {
    final api = FakeLibraryApi()
      ..onItems = (query, start, limit) => query.kinds.contains(ItemKind.movie)
          ? pageOf([testItem(id: 'm1', name: 'Dune')])
          : pageOf([])
      ..people = [];
    await pumpApp(tester, const SearchScreen(), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);

    expect(find.text('Scrivi almeno 2 lettere per cercare.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Film'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Serie'), findsNothing);
  });

  testWidgets('nessun risultato', (tester) async {
    final api = FakeLibraryApi();
    await pumpApp(tester, const SearchScreen(), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Nessun risultato per "zzz"'), findsOneWidget);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/features/search`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/features/search/search_controller.dart`:
```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../library/library_providers.dart';

class SearchResults {
  const SearchResults({
    required this.movies,
    required this.series,
    required this.people,
  });

  final List<JellyfinItem> movies;
  final List<JellyfinItem> series;
  final List<JellyfinItem> people;

  bool get isEmpty => movies.isEmpty && series.isEmpty && people.isEmpty;
}

class SearchState {
  const SearchState({this.term = '', this.results, this.loading = false, this.error});

  final String term;
  final SearchResults? results;
  final bool loading;
  final Object? error;
}

/// Ricerca con attesa di 300 ms: ogni nuova lettera annulla la precedente.
class SearchController extends Notifier<SearchState> {
  static const debounce = Duration(milliseconds: 300);
  static const minLength = 2;

  Timer? _debounce;
  CancelToken? _cancel;

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancel?.cancel();
    });
    return const SearchState();
  }

  void setTerm(String raw) {
    final term = raw.trim();
    _debounce?.cancel();
    _cancel?.cancel();
    if (term.length < minLength) {
      state = SearchState(term: term);
      return;
    }
    state = SearchState(term: term, results: state.results, loading: true);
    _debounce = Timer(debounce, () => unawaited(_search(term)));
  }

  Future<void> _search(String term) async {
    final cancel = _cancel = CancelToken();
    final api = ref.read(libraryApiProvider);
    final userId = ref.read(currentUserIdProvider);
    Future<List<JellyfinItem>> items(ItemKind kind) async => (await api.items(
          ItemQuery(kinds: {kind}, searchTerm: term),
          userId: userId,
          startIndex: 0,
          limit: 24,
          cancelToken: cancel,
        ))
            .items;
    try {
      final results = await Future.wait([
        items(ItemKind.movie),
        items(ItemKind.series),
        api.searchPeople(userId, term, limit: 12, cancelToken: cancel),
      ]);
      if (!ref.mounted || cancel.isCancelled) return;
      state = SearchState(
        term: term,
        results: SearchResults(
            movies: results[0], series: results[1], people: results[2]),
      );
    } on RequestCancelledException {
      return;
    } on Object catch (error) {
      if (!ref.mounted || cancel.isCancelled) return;
      state = SearchState(term: term, error: error);
    }
  }
}

final searchControllerProvider =
    NotifierProvider.autoDispose<SearchController, SearchState>(SearchController.new);
```

`lib/features/search/search_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import 'search_controller.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        TextField(
          autofocus: true,
          onChanged: controller.setTerm,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            hintText: l.searchHint,
            prefixIcon: const Icon(LucideIcons.search, color: WfColors.creamMuted),
          ),
        ),
        const SizedBox(height: 24),
        _results(context, ref, l, state),
      ],
    );
  }

  Widget _results(
      BuildContext context, WidgetRef ref, AppLocalizations l, SearchState state) {
    const muted = TextStyle(color: WfColors.creamMuted);
    if (state.term.length < SearchController.minLength) {
      return Text(l.searchPrompt, style: muted);
    }
    final error = state.error;
    if (error != null) {
      return ErrorView(
        error: error,
        onRetry: () =>
            ref.read(searchControllerProvider.notifier).setTerm(state.term),
      );
    }
    final results = state.results;
    if (results == null) return const LoadingView();
    if (results.isEmpty) return Text(l.searchNoResults(state.term), style: muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (results.movies.isNotEmpty) _posterSection(context, l.navMovies, results.movies),
        if (results.series.isNotEmpty) _posterSection(context, l.navSeries, results.series),
        if (results.people.isNotEmpty) _peopleSection(context, ref, l, results.people),
      ],
    );
  }

  Widget _posterSection(BuildContext context, String title, List<JellyfinItem> items) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: WfText.display(26)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 24,
              children: [
                for (final item in items)
                  PosterCard(item: item, width: 150, onTap: () => openItem(context, item)),
              ],
            ),
          ],
        ),
      );

  Widget _peopleSection(BuildContext context, WidgetRef ref, AppLocalizations l,
      List<JellyfinItem> people) {
    final urls = ref.watch(imageUrlsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.searchPeople, style: WfText.display(26)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final person in people)
              GestureDetector(
                onTap: () => openItem(context, person),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: SizedBox(
                    width: 110,
                    child: Column(
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: 90,
                            height: 90,
                            child: WfImage(
                                image: urls.poster(person),
                                fallbackIcon: LucideIcons.user),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(person.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: esegui**

Run: `flutter test test/features/search && flutter test`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/search test/features/search
git commit -m "feat: add debounced search for movies, shows and people"
```

---

### Task 19: La mia lista

**Files:**
- Create: `lib/features/mylist/my_list_screen.dart`
- Test: `test/features/mylist/my_list_screen_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/mylist/my_list_screen_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  Future<FakeLibraryApi> pumpList(WidgetTester tester, FakeLibraryApi api) async {
    await pumpApp(tester, const MyListScreen(), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.pump();
    await tester.pump();
    return api;
  }

  testWidgets('mostra i preferiti', (tester) async {
    final api = await pumpList(
        tester,
        FakeLibraryApi()
          ..onItems = (query, start, limit) => query.favoritesOnly
              ? pageOf([testItem(id: 'm1', name: 'Dune', favorite: true)])
              : pageOf([]));
    expect(find.text('LA MIA LISTA'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(api.itemQueries.single.favoritesOnly, isTrue);
  });

  testWidgets('lista vuota', (tester) async {
    await pumpList(tester, FakeLibraryApi());
    expect(find.text('La tua lista è vuota. Aggiungi film e serie con il cuore.'),
        findsOneWidget);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/features/mylist`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/features/mylist/my_list_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/states.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';

final favoritesProvider = FutureProvider.autoDispose<List<JellyfinItem>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final page = await ref.watch(libraryApiProvider).items(
        const ItemQuery(
          kinds: {ItemKind.movie, ItemKind.series},
          sort: CatalogSort.dateAdded,
          favoritesOnly: true,
        ),
        userId: ref.watch(currentUserIdProvider),
        startIndex: 0,
        limit: 500,
      );
  return page.items;
});

class MyListScreen extends ConsumerWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final overrides = ref.watch(userDataOverridesProvider);
    return ref.watch(favoritesProvider).when(
          loading: () => const LoadingView(),
          error: (error, _) =>
              ErrorView(error: error, onRetry: () => ref.invalidate(favoritesProvider)),
          data: (items) {
            // Tolti dal cuore in questa sessione: spariscono subito.
            final visible = items
                .where((i) => (overrides[i.id] ?? i.userData).isFavorite)
                .toList();
            return ListView(
              padding: const EdgeInsets.all(32),
              children: [
                Text(l.navMyList.toUpperCase(), style: WfText.display(40)),
                const SizedBox(height: 20),
                if (visible.isEmpty)
                  Text(l.myListEmpty, style: const TextStyle(color: WfColors.creamMuted))
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 24,
                    children: [
                      for (final item in visible)
                        PosterCard(
                          item: item,
                          width: 160,
                          onTap: () => openItem(context, item),
                        ),
                    ],
                  ),
              ],
            );
          },
        );
  }
}
```

- [ ] **Step 4: esegui**

Run: `flutter test test/features/mylist && flutter test`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/mylist test/features/mylist
git commit -m "feat: add My List screen"
```

---

### Task 20: Impostazioni e lingua

**Files:**
- Create: `lib/features/settings/locale_controller.dart`, `lib/features/settings/settings_screen.dart`
- Modify: `lib/app/app.dart`
- Test: `test/features/settings/settings_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/settings/settings_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/locale_controller.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  test('LocaleController salva e rilegge la lingua', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer.test(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(container.read(localeProvider), isNull);
    await container.read(localeProvider.notifier).set(const Locale('en'));
    expect(container.read(localeProvider), const Locale('en'));
    expect(prefs.getString('locale'), 'en');
    await container.read(localeProvider.notifier).set(null);
    expect(prefs.getString('locale'), isNull);
  });

  testWidgets('schermata: utente, lingua, versione, esci', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final session = FakeSessionController(const SessionSignedIn(testUser));
    await pumpApp(tester, const SettingsScreen(), overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(() => session),
    ]);

    expect(find.text('Accesso come Mario'), findsOneWidget);
    expect(find.text('Versione 0.0.1'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pump();
    expect(prefs.getString('locale'), 'en');

    await tester.tap(find.text('Esci'));
    await tester.pump();
    expect(session.logoutCalls, 1);
  });
}
```

- [ ] **Step 2: esegui**

Run: `flutter test test/features/settings`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/features/settings/locale_controller.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Lingua scelta dall'utente; `null` = lingua di Windows.
class LocaleController extends Notifier<Locale?> {
  static const _key = 'locale';

  @override
  Locale? build() {
    final code = ref.watch(sharedPreferencesProvider).getString(_key);
    return code == null ? null : Locale(code);
  }

  Future<void> set(Locale? locale) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (locale == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, locale.languageCode);
    }
    state = locale;
  }
}

final localeProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);
```

`lib/features/settings/settings_screen.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../auth/session_controller.dart';
import 'locale_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final session = ref.watch(sessionControllerProvider);
    final version = ref.watch(clientInfoProvider).version;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 12),
          child: Text(title, style: WfText.display(24)),
        );

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text(l.menuSettings.toUpperCase(), style: WfText.display(40)),
        section(l.settingsLanguage),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'system', label: Text(l.settingsLanguageSystem)),
              const ButtonSegment(value: 'it', label: Text('Italiano')),
              const ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {locale?.languageCode ?? 'system'},
            onSelectionChanged: (selection) {
              final code = selection.first;
              unawaited(ref
                  .read(localeProvider.notifier)
                  .set(code == 'system' ? null : Locale(code)));
            },
          ),
        ),
        section(l.settingsAccount),
        if (session is SessionSignedIn)
          Text(l.settingsSignedInAs(session.user.name)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: WfButton.secondary(
            label: l.menuLogout,
            icon: LucideIcons.logOut,
            onPressed: () =>
                unawaited(ref.read(sessionControllerProvider.notifier).logout()),
          ),
        ),
        const SizedBox(height: 40),
        Text(l.settingsVersion(version),
            style: const TextStyle(color: WfColors.creamMuted, fontSize: 12.5)),
      ],
    );
  }
}
```

In `lib/app/app.dart` aggiungi l'import:
```dart
import '../features/settings/locale_controller.dart';
```
e in `MaterialApp.router(...)`, subito dopo `theme: buildWonderflixTheme(),`, aggiungi:
```dart
      locale: ref.watch(localeProvider),
```

- [ ] **Step 4: esegui**

Run: `flutter test test/features/settings && flutter test`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/settings lib/app/app.dart test/features/settings
git commit -m "feat: add settings screen with language choice"
```

---

### Task 21: router, barra superiore e tasto "indietro"

**Files:**
- Create: `lib/app/back_navigation.dart`
- Modify (sostituzione completa): `lib/app/router.dart`, `lib/app/app_shell.dart`
- Modify: `test/app/app_shell_test.dart`
- Test: `test/app/back_navigation_test.dart`

- [ ] **Step 1: scrivi i test**

`test/app/back_navigation_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/back_navigation.dart';

void main() {
  testWidgets('Esc e Alt+← tornano indietro, la radice resta', (tester) async {
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        ShellRoute(
          builder: (context, state, child) => BackNavigationHandler(child: child),
          routes: [
            GoRoute(path: '/a', builder: (c, s) => const Text('pagina A')),
            GoRoute(path: '/b', builder: (c, s) => const Text('pagina B')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.push('/b');
    await tester.pumpAndSettle();
    expect(find.text('pagina B'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('pagina A'), findsOneWidget);

    router.push('/b');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('pagina A'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('pagina A'), findsOneWidget, reason: 'nessuna pagina da chiudere');
  });
}
```

In `test/app/app_shell_test.dart`, dopo `expect(find.text('Home'), findsOneWidget);` aggiungi:
```dart
    expect(find.text('Film'), findsOneWidget);
    expect(find.text('Serie'), findsOneWidget);
    expect(find.text('La mia lista'), findsOneWidget);
    expect(find.text('Cerca'), findsOneWidget);
```

- [ ] **Step 2: esegui**

Run: `flutter test test/app/back_navigation_test.dart test/app/app_shell_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/app/back_navigation.dart`:
```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Esc, Alt+← e il tasto "indietro" del mouse chiudono la pagina corrente.
/// Non fa nulla se sopra c'è un menu o un dialog (gestiscono loro Esc).
class BackNavigationHandler extends StatefulWidget {
  const BackNavigationHandler({super.key, required this.child});

  final Widget child;

  @override
  State<BackNavigationHandler> createState() => _BackNavigationHandlerState();
}

class _BackNavigationHandlerState extends State<BackNavigationHandler> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final isBack = key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack ||
        (key == LogicalKeyboardKey.arrowLeft &&
            HardwareKeyboard.instance.isAltPressed);
    return isBack && _goBack();
  }

  bool _goBack() {
    if (!mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final router = GoRouter.maybeOf(context);
    if (router == null || !router.canPop()) return false;
    router.pop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons & kBackMouseButton != 0) _goBack();
      },
      child: widget.child,
    );
  }
}
```

`lib/app/router.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/jellyfin/item_models.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/session_controller.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/detail/item_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/mylist/my_list_screen.dart';
import '../features/person/person_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/startup/splash_screen.dart';
import '../features/startup/unreachable_screen.dart';
import 'app_shell.dart';

const _entryRoutes = {'/splash', '/login', '/unreachable'};

/// Dove deve stare l'utente in base allo stato di sessione.
/// `null` = la posizione attuale va bene.
String? sessionRedirect(SessionState session, String location) {
  String? goTo(String target) => location == target ? null : target;
  return switch (session) {
    SessionStarting() => goTo('/splash'),
    SessionSignedOut() => goTo('/login'),
    SessionUnreachable() => goTo('/unreachable'),
    SessionSignedIn() => _entryRoutes.contains(location) ? '/home' : null,
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  final session = ValueNotifier<SessionState>(ref.read(sessionControllerProvider));
  ref.listen(sessionControllerProvider, (_, next) => session.value = next);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: session,
    redirect: (context, state) =>
        sessionRedirect(session.value, state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
          path: '/unreachable',
          builder: (context, state) => const UnreachableScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          GoRoute(
              path: '/movies',
              builder: (context, state) =>
                  const CatalogScreen(key: ValueKey('movies'), kind: ItemKind.movie)),
          GoRoute(
              path: '/series',
              builder: (context, state) =>
                  const CatalogScreen(key: ValueKey('series'), kind: ItemKind.series)),
          GoRoute(path: '/mylist', builder: (context, state) => const MyListScreen()),
          GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
          GoRoute(
              path: '/settings', builder: (context, state) => const SettingsScreen()),
          GoRoute(
            path: '/item/:id',
            builder: (context, state) => ItemDetailScreen(
              key: ValueKey(state.uri.toString()),
              itemId: state.pathParameters['id']!,
              seasonId: state.uri.queryParameters['season'],
            ),
          ),
          GoRoute(
            path: '/person/:id',
            builder: (context, state) => PersonScreen(
              key: ValueKey(state.pathParameters['id']),
              personId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    session.dispose();
  });
  return router;
});
```

`lib/app/app_shell.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/auth_models.dart';
import '../features/auth/session_controller.dart';
import '../features/library/server_events_binding.dart';
import '../l10n/gen/app_localizations.dart';
import 'back_navigation.dart';
import 'theme.dart';

/// Struttura comune alle schermate autenticate: barra superiore + contenuto.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tiene aperto il WebSocket degli eventi finché si è autenticati.
    ref.watch(serverEventsBindingProvider);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionSignedIn ? session.user : null;
    final l = AppLocalizations.of(context);

    Widget nav(String label, String route, {IconData? icon}) => _NavItem(
          label: label,
          icon: icon,
          active: location.startsWith(route),
          onTap: () => context.go(route),
        );

    return Scaffold(
      body: BackNavigationHandler(
        child: Column(
          children: [
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Image.asset('assets/brand/logo.png', height: 40),
                  const SizedBox(width: 32),
                  nav(l.navHome, '/home'),
                  nav(l.navMovies, '/movies'),
                  nav(l.navSeries, '/series'),
                  nav(l.navMyList, '/mylist'),
                  nav(l.navSearch, '/search', icon: LucideIcons.search),
                  const Spacer(),
                  if (user != null) _UserMenu(user: user),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = active ? WfColors.gold : WfColors.cream;
    final symbol = icon;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: active ? WfColors.gold : Colors.transparent, width: 2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (symbol != null) ...[
                Icon(symbol, size: 16, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.user});

  final JellyfinUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final initial = user.name.isEmpty ? '?' : user.name[0].toUpperCase();
    return PopupMenuButton<String>(
      key: const Key('user-menu'),
      tooltip: user.name,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'settings':
            context.go('/settings');
          case 'logout':
            unawaited(ref.read(sessionControllerProvider.notifier).logout());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              const Icon(LucideIcons.settings, size: 18, color: WfColors.cream),
              const SizedBox(width: 12),
              Text(l.menuSettings),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 18, color: WfColors.cream),
              const SizedBox(width: 12),
              Text(l.menuLogout),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: WfColors.gold,
            child: Text(initial,
                style: const TextStyle(
                    color: WfColors.bg, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(user.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: esegui tutto e analizza**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti i test PASS.

- [ ] **Step 5: commit**

```bash
git add lib/app test/app
git commit -m "feat: wire library routes, top navigation and back navigation"
```

---

### Task 22: verifica completa e prova sul server

**Files:** nessuna modifica prevista (solo eventuali correzioni emerse).

- [ ] **Step 1: controlli automatici**

```bash
flutter analyze
flutter test
flutter build windows --debug
```
Expected: nessun problema, tutti i test PASS, build riuscita.

- [ ] **Step 2: prova manuale sul server reale** (con `config/wonderflix.json` già presente)

```bash
flutter run -d windows --dart-define-from-file=config/wonderflix.json
```
Checklist da fare con l'utente (annota l'esito):
1. **Home:**
   - carosello in evidenza, che cambia ogni 8 s;
   - righe Continua a guardare, Prossimi episodi, Film/Serie aggiunti di recente, La mia lista, con immagini e segnaposto sfocato (blurhash) durante il caricamento.
2. **Film / Serie:**
   - griglia che si carica scorrendo;
   - ordinamento, genere, anno, visti/non visti;
   - "Azzera filtri".
3. **Scheda di un film:**
   - sfondo, logo o titolo, dati, trama, cast, simili;
   - "Riprendi da mm:ss" su un film iniziato;
   - Trailer apre il browser;
   - "Riproduci" mostra l'avviso che la riproduzione arriva con il prossimo aggiornamento.
4. **Scheda di una serie:**
   - pulsante sul prossimo episodio;
   - schede delle stagioni;
   - episodi con avanzamento e segno di visto.
5. **Cuore e visto:**
   - lo stato cambia subito;
   - aprendo jellyfin-web, lo stato è lo stesso.
6. **WebSocket:**
   - segna un film come visto da jellyfin-web: entro pochi secondi compare il badge in WonderFlix senza ricaricare;
   - nella Dashboard, la sessione WonderFlix risulta attiva.
7. **Pagina attore:** si apre dal cast e mostra i titoli del server.
8. **Ricerca:** risultati per Film, Serie e Persone; "Nessun risultato" se non c'è nulla.
9. **La mia lista:** mostra i preferiti; un titolo tolto dal cuore sparisce.
10. **Impostazioni:**
    - cambio lingua Italiano/English/Sistema immediato e ricordato al riavvio;
    - Esci funziona.
11. **Navigazione:** Esc, Alt+← e il tasto indietro del mouse tornano alla pagina precedente.

- [ ] **Step 3: correzioni**

Se la prova rivela problemi, correggili con TDD (prima il test che fallisce, poi la correzione), un commit per problema, con messaggio `fix: …`.
