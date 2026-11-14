# Film e Serie, "Sala per genere" — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le pagine Film, Serie e Saghe diventano una "sala per genere": cartellone con il genere scelto, indice dei generi con i conteggi, attrezzi fermi in cima, card più parlanti; e i filtri di genere tornano a funzionare (anche in "Cosa guardo stasera?" e nel Match).

**Architecture:** I generi si leggono da `/Items/Filters2` e passano per una tabella inglese→italiano in `core/jellyfin/genre_labels.dart`: nell'app un genere è un'etichetta ("Dramma"), verso il server diventa `Drama|Dramma`. `CatalogScreen` diventa una `CustomScrollView`: cartellone (`SliverToBoxAdapter`), barra generi+attrezzi (`SliverPersistentHeader`, ferma fuori dalla TV), griglia. Il genere sta nell'indirizzo (`?genre=`); il controller carica solo quando la pagina gli dice il genere.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, go_router, Jellyfin 10.11; plugin .NET 9 (una riga).

**Spec:** `docs/superpowers/specs/2026-11-14-catalogo-ui-design.md` (bozza: `docs/superpowers/specs/2026-11-14-catalogo-bozze/sala.html`). Chi esegue legge entrambe.

## Global Constraints

- Stile invariato: Noir & Oro (`WfColors`), Bebas Neue (`WfText.display`) per i titoli, Inter per il resto. Nessun colore nuovo.
- Fuori dalla TV il comportamento TV non cambia, e viceversa (`FormFactor.of(context).tv`).
- La pagina non si apre più lenta di oggi: il cartellone non aspetta conteggi né letture in più.
- La mia lista, Home, Cerca, pagina persona, pagina saga e scheda titolo non cambiano: `CatalogFiltersBar`, `PosterCard` di default e `CollectionCard` restano come sono.
- Plugin: solo la divisione del genere su `|` in `JellyfinMatchLibrary`, versione 1.31.0 invariata (non ancora pubblicata).
- Testi nuovi in `app/l10n/app_it.arb` e `app/l10n/app_en.arb`; poi `flutter gen-l10n`.
- Commit in italiano, senza `Co-Authored-By`, senza le parole `closes`/`fixes`/`resolves`. Format solo delle righe toccate (`dart format` su file vecchi riscrive tutto).
- Comandi da `app/` (Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`): `flutter gen-l10n`, `flutter analyze`, `flutter test <file>`. Build di prova: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`. Mai `taskkill /IM` o `pkill`.
- Se un comando Flutter modifica `windows/flutter/generated_plugin*` solo nei fine riga: `git checkout --` quei file.

## Review Focus

1. **Nessun fondale nella prima pagina** (titoli senza `Backdrop`): il cartellone resta nero con la sfumatura e il titolo, niente errore né spazio vuoto. Test nel Task 6.
2. **Cambi di genere rapidi** (clic su tre generi di fila): vince l'ultimo; griglia, cartellone e conteggi sono tutti di quel genere. Test nel Task 4.
3. **Conteggi dei generi che non arrivano** (una lettura `limit=0` fallisce): la riga mostra "Tutti" (o i nomi senza numeri) e la griglia funziona. Test nel Task 4.
4. **Ricerca mentre si scrive** (tasti ravvicinati, poi campo svuotato): una sola richiesta per pausa di 300 ms, e svuotando torna la lista del genere. Test nel Task 7.
5. **Genere di Stasera salvato in inglese o sparito** (`tonight.genre` = "Drama", o un genere ora sotto i 5 titoli): si legge "Dramma"; un genere che non c'è più torna a "Tutti i generi" come oggi. Test nel Task 2.

---

### Task 1: Generi da `/Items/Filters2` con etichette italiane

**Files:**
- Create: `app/lib/core/jellyfin/genre_labels.dart`
- Modify: `app/lib/core/jellyfin/library_api.dart` (`filters`, ~riga 271)
- Test: `app/test/core/jellyfin/genre_labels_test.dart`, `app/test/core/jellyfin/library_api_test.dart` (aggiungere al file esistente; se non c'è, crearlo come gli altri test di `core/jellyfin/`)

**Interfaces:**
- Produces: `String genreLabel(String serverName)`; `List<String> genreServerNames(String label)` (l'etichetta per prima, poi i nomi inglesi che vi portano, in ordine alfabetico); `LibraryApi.filters(userId, kind)` restituisce `LibraryFilters(genres: <etichette senza doppioni, ordine alfabetico>, years: const [])`.

- [ ] **Step 1: test di `genre_labels`**

```dart
test('i nomi inglesi diventano italiani, gli altri restano', () {
  expect(genreLabel('Drama'), 'Dramma');
  expect(genreLabel('Science Fiction'), 'Fantascienza');
  expect(genreLabel('Sci-Fi'), 'Fantascienza');
  expect(genreLabel('Suspense'), 'Thriller');
  expect(genreLabel('Anime'), 'Anime');
  expect(genreLabel('Dramma'), 'Dramma');
});
test('un\'etichetta torna a tutti i suoi nomi del server', () {
  expect(genreServerNames('Dramma'), ['Dramma', 'Drama']);
  expect(genreServerNames('Fantascienza'), ['Fantascienza', 'Sci-Fi', 'Science Fiction']);
  expect(genreServerNames('Anime'), ['Anime']);
});
```

- [ ] **Step 2:** `flutter test test/core/jellyfin/genre_labels_test.dart` → FAIL (file mancante).
- [ ] **Step 3:** crea `genre_labels.dart` con la tabella della spec §6.2, esattamente: Drama→Dramma, Action→Azione, Adventure→Avventura, Science Fiction→Fantascienza, Sci-Fi→Fantascienza, Comedy→Commedia, Mystery→Mistero, Animation→Animazione, Documentary→Documentario, History→Storia, War→Guerra, Family→Famiglia, Sport→Sport, Sports→Sport, Suspense→Thriller, Mini-Series→Miniserie, Music→Musica, Supernatural→Soprannaturale.
- [ ] **Step 4: test di `LibraryApi.filters`**: con la risposta `{"Genres":[{"Name":"Drama","Id":"1"},{"Name":"Dramma","Id":"2"},{"Name":"Anime","Id":"3"}],"Tags":[]}` chiede `GET /Items/Filters2` con `userId`, `includeItemTypes=Movie`, `recursive=true` e restituisce `genres == ['Anime', 'Dramma']`, `years` vuoto.
- [ ] **Step 5:** test → FAIL; poi cambia `filters` (endpoint, `recursive`, `Name` degli oggetti, `genreLabel`, senza doppioni, ordine alfabetico senza maiuscole/minuscole) → PASS.
- [ ] **Step 6:** `flutter test test/core/jellyfin test/features/catalog test/features/tonight` → PASS (sistemare i test che si aspettavano `/Items/Filters`).
- [ ] **Step 7: Commit** `fix(app): generi da /Items/Filters2 con nomi italiani`

### Task 2: Stasera e Match con le etichette; il plugin divide su `|`

**Files:**
- Modify: `app/lib/core/jellyfin/library_api.dart` (`randomUnplayed`), `app/lib/core/social/match_api.dart` (~riga 97, `'Genre'`), `app/lib/features/tonight/tonight_controller.dart` (`readTonightFilters`, ~riga 22)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinMatchLibrary.cs:55`
- Test: `app/test/features/tonight/tonight_controller_test.dart`, il test esistente di `MatchApi` (cercarlo in `app/test/core/social/`), `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/JellyfinMatchLibraryTests.cs`

**Interfaces:**
- Consumes: `genreLabel`, `genreServerNames` (Task 1).
- Produces: `randomUnplayed(genre: 'Dramma')` manda `genres=Dramma|Drama`; `MatchApi` manda `Genre: "Dramma|Drama"`; `readTonightFilters` restituisce l'etichetta.

- [ ] **Step 1: test app**: (a) `randomUnplayed(..., genre: 'Dramma')` → parametro `genres` = `'Dramma|Drama'`; (b) `MatchApi` con `genre: 'Dramma'` → corpo con `'Genre': 'Dramma|Drama'`, con `null` resta `null`; (c) `readTonightFilters` con `tonight.genre` = `'Drama'` → `filters.genre == 'Dramma'`.
- [ ] **Step 2:** test → FAIL.
- [ ] **Step 3:** in `randomUnplayed` e `MatchApi` unisci `genreServerNames(genre)` con `|`; in `readTonightFilters` passa il valore salvato per `genreLabel`. `tonightGenresProvider` e `TonightFiltersBar` non cambiano: ricevono già etichette dal Task 1 (la regola "un genere che non c'è più torna a Tutti" resta).
- [ ] **Step 4: test plugin** `AGenreWithBarsAsksForEachName`: filtri con `Genre = "Dramma|Drama"` → `query.Genres` = `["Dramma", "Drama"]`. Il test esistente con `"Drama"` resta `["Drama"]`.
- [ ] **Step 5:** `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter JellyfinMatchLibraryTests` (da `plugin/`) → FAIL; poi `query.Genres = genre.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)` → PASS.
- [ ] **Step 6:** `flutter test test/features/tonight test/features/match test/core` → PASS.
- [ ] **Step 7: Commit** `fix: Stasera e Match con i generi uniti (Drama e Dramma)`

### Task 3: `ItemQuery`: decennio, stato serie, verso, ricerca

**Files:**
- Modify: `app/lib/core/jellyfin/item_query.dart`
- Test: `app/test/core/jellyfin/item_query_test.dart` (esistente o nuovo)

**Interfaces:**
- Produces:
  - `enum SeriesStatusFilter { all, continuing, ended }`
  - in `ItemQuery`: `final int? decade` (2020, 2010, 2000, 1990, oppure `ItemQuery.olderDecades` = 0 per "Prima"), `final SeriesStatusFilter seriesStatus` (default `all`), `final bool reversed` (default `false`); `copyWith` accetta anche `decade` (con `_keep` come `year`), `seriesStatus`, `reversed`, `searchTerm` (con `_keep`).
  - `bool get hasRefinements` = `decade != null || seriesStatus != all || watched != all || (searchTerm ?? '').isNotEmpty`; `ItemQuery clearRefinements()` li azzera e tiene tipi, generi, ordine, verso.
  - `hasFilters`/`clearFilters` restano come sono (li usa La mia lista).

- [ ] **Step 1: test** di `toQueryParameters`:
  - `decade: 2010` → `years` = `'2010,2011,2012,2013,2014,2015,2016,2017,2018,2019'`; `decade: ItemQuery.olderDecades` → `years` dal `'1900'` al `'1989'` (90 anni, separati da virgola);
  - `seriesStatus: continuing` → `seriesStatus=Continuing`; `ended` → `Ended`; `all` → chiave assente;
  - `sort: rating, reversed: true` → `sortOrder` = `'Ascending,Ascending'`; `sort: title, reversed: true` → `'Descending'`; `sort: dateAdded` (serie) `reversed: false` → invariato rispetto a oggi;
  - `copyWith(searchTerm: 'dune')` → `searchTerm=dune`; `clearRefinements()` toglie decennio, stato, `isPlayed`, ricerca e tiene `genres` e ordine.
- [ ] **Step 2:** FAIL → implementa → `flutter test test/core/jellyfin/item_query_test.dart test/features/mylist` PASS.
- [ ] **Step 3: Commit** `feat(app): decennio, stato delle serie e verso nella query del catalogo`

### Task 4: Controller, generi con conteggi, totali del cartellone

**Files:**
- Modify: `app/lib/features/catalog/catalog_controller.dart`
- Create: `app/lib/features/catalog/catalog_genres.dart`
- Test: `app/test/features/catalog/catalog_controller_test.dart`, `app/test/features/catalog/catalog_genres_test.dart`

**Interfaces:**
- Consumes: `genreServerNames` (Task 1), `ItemQuery` nuovi campi (Task 3).
- Produces:
  - `CatalogState` con in più `final String? genre` (l'etichetta mostrata).
  - `CatalogSort catalogDefaultSort(String? genre)` → `rating` con un genere, `dateAdded` senza.
  - `CatalogController.build()` **non carica più**: restituisce `CatalogState(query: ItemQuery(kinds: {kind}, sort: CatalogSort.dateAdded), loading: true)`. `Future<void> showGenre(String? genre)` imposta `genres: genreServerNames(genre)` (o vuoto), `sort: catalogDefaultSort(genre)`, `reversed: false`, tiene decennio/stato/visti/ricerca, e carica. `setQuery`, `loadMore`, `retry` come oggi.
  - `class GenreCount { final String label; final int count; }`
  - `final catalogGenresProvider = FutureProvider.autoDispose.family<List<GenreCount>, ItemKind>`: etichette da `catalogFiltersProvider`, poi per ognuna `LibraryApi.items(ItemQuery(kinds: {kind}, genres: genreServerNames(label).toSet()), startIndex: 0, limit: 0)` in parallelo; tiene quelle con `count >= 5`, ordine per conteggio decrescente e poi nome. Resta in vita per la sessione (`ref.keepAlive()`), si rilegge con `libraryRevisionProvider`.
  - `class CatalogTotals { final int total; final int secondary; }` (film: visti; serie: in corso).
  - `final catalogTotalsProvider = FutureProvider.autoDispose.family<CatalogTotals, (ItemKind, String?)>`: due letture `limit: 0` (tutti; poi `watched: watched` per i film, `seriesStatus: continuing` per le serie), con i generi dell'etichetta. Stesso `keepAlive` e rilettura.

- [ ] **Step 1: test controller**: (a) senza `showGenre` nessuna richiesta; (b) `showGenre('Horror')` → una richiesta con `genres` = `{'Horror'}` e `sort == rating`, `state.genre == 'Horror'`; (c) `showGenre(null)` → `sort == dateAdded`; (d) con `decade: 2010` già scelto, `showGenre('Dramma')` lo tiene e manda `genres` `{'Dramma','Drama'}`; (e) **Review Focus 2**: `showGenre('Azione')`, `showGenre('Horror')`, `showGenre('Dramma')` con risposte che arrivano in ordine inverso → stato finale di "Dramma" con i suoi titoli.
- [ ] **Step 2: test generi**: risposte finte con conteggi Azione 330, Western 6, Psychological 1, Drama/Dramma unite 212 → `[Azione 330, Dramma 212, Western 6]`; **Review Focus 3**: una lettura `limit: 0` che lancia → il provider va in errore (la riga lo gestisce nel Task 7) e il controller della griglia non ne risente.
- [ ] **Step 3: test totali**: film "Horror" → `CatalogTotals(128, 58)` dalle due letture giuste; serie senza genere → la seconda lettura ha `seriesStatus=Continuing`.
- [ ] **Step 4:** FAIL → implementa → `flutter test test/features/catalog` PASS (i test della schermata che si aspettavano il caricamento in `build()` si sistemano nel Task 8; qui solo il controller).
- [ ] **Step 5: Commit** `feat(app): generi con conteggi e totali per il catalogo`

### Task 5: Indirizzi con il genere, pagina sotto la barra

**Files:**
- Modify: `app/lib/features/catalog/catalog_navigation.dart`, `app/lib/app/router.dart` (~righe 229-249), chi usa `openMovies` (`grep -rn openMovies lib test`)
- Test: `app/test/features/catalog/catalog_navigation_test.dart`, `app/test/app/router_test.dart`

**Interfaces:**
- Produces: `void openCatalog(BuildContext context, ItemKind kind, {CatalogView view = CatalogView.titles, String? genre})` (sostituisce `openMovies`): `/movies`, `/movies?genre=Fantascienza`, `/movies?view=sagas`, `/series?genre=Dramma` (genere codificato nell'URL). `CatalogScreen` riceve `final String? genre` dal parametro `genre`. `/movies` e `/series` passano a `underBar: false` (il cartellone va sotto la barra, come la Home).

- [ ] **Step 1: test** degli indirizzi sopra (anche un genere con spazi, "Slice of Life"), e nel router che `/series?genre=Dramma` costruisce `CatalogScreen(kind: series, genre: 'Dramma')`.
- [ ] **Step 2:** FAIL → implementa → PASS.
- [ ] **Step 3: Commit** `feat(app): il genere del catalogo nell'indirizzo`

### Task 6: Il cartellone

**Files:**
- Create: `app/lib/features/catalog/catalog_band.dart`
- Modify: `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/catalog/catalog_band_test.dart`

**Interfaces:**
- Produces:
  - `class CatalogBand extends ConsumerWidget { CatalogBand({required String title, JellyfinItem? hero, String? line, Widget? tabs, required double height}) }` — immagine `imageUrlsProvider.backdrop(hero, maxWidth: 1920)` con `WfImage`, sfumature della spec §5, `tabs` in alto a sinistra, `title` con `WfText.display`, `line` sotto. Cambio di `hero`/`title` con `WfSwitcher` (secco con movimento ridotto). Immagine esclusa dalla semantica.
  - `JellyfinItem? catalogBandHero(List<JellyfinItem> items)` → il primo con `backdropTags` non vuoto.
  - `String catalogBandLine(AppLocalizations l, {required ItemKind kind, required CatalogSort sort, required bool reversed, CatalogTotals? totals})`.
  - Altezze: `catalogBandHeight` 320 (desktop), 220 (`compact`), 160 (TV); titolo 112 / 64 / 64.
- Testi (it): `catalogAllMovies` "Tutti i film", `catalogAllSeries` "Tutte le serie", `catalogBandMovies` "{total} film, {watched} già visti.", `catalogBandSeries` "{total} serie, {continuing} in corso.", `catalogOrderAdded` "Gli ultimi arrivati per primi" / `catalogOrderAddedReversed` "I primi arrivati per primi", `catalogOrderNewEpisodes` "Nuovi episodi per prime" / `catalogOrderNewEpisodesReversed` "Le ferme da più tempo per prime", `catalogOrderTitle` "Dalla A alla Z" / `catalogOrderTitleReversed` "Dalla Z alla A", `catalogOrderYear` "Dal più recente" / `catalogOrderYearReversed` "Dal più vecchio", `catalogOrderRating` "I più votati per primi" / `catalogOrderRatingReversed` "I meno votati per primi". (it e en.)

- [ ] **Step 1: test**: (a) `catalogBandHero` salta i titoli senza fondale; (b) **Review Focus 1**: con `hero: null` il cartellone mostra il titolo e nessuna immagine (l'`imageBuilderProvider` finto non viene chiamato), senza eccezioni; (c) `catalogBandLine` film `rating` non invertito con totali 243/211 → "243 film, 211 già visti. I più votati per primi."; senza totali → solo "I più votati per primi."; serie `dateAdded` → frase "Nuovi episodi per prime"; (d) l'URL passato all'image builder è quello del fondale del primo titolo che ne ha uno.
- [ ] **Step 2:** FAIL → `flutter gen-l10n` + implementa → PASS.
- [ ] **Step 3: Commit** `feat(app): cartellone del catalogo`

### Task 7: Indice dei generi e attrezzi

**Files:**
- Create: `app/lib/features/catalog/catalog_genre_index.dart`, `app/lib/features/catalog/catalog_tools.dart`
- Modify: `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/catalog/catalog_genre_index_test.dart`, `app/test/features/catalog/catalog_tools_test.dart`

**Interfaces:**
- Consumes: `GenreCount` (Task 4), `ItemQuery` (Task 3).
- Produces:
  - `class CatalogGenreIndex extends StatelessWidget { ({required ItemKind kind, required AsyncValue<List<GenreCount>> genres, required int? total, required String? selected, required ValueChanged<String?> onSelected}) }` — riga orizzontale che scorre, sfumatura a destra; prima voce "Tutti"/"Tutte" (serie) con `total`; numero piccolo in alto (opacità 32%, oro se scelto); scelto in oro con linea sotto. Con `genres` in errore o vuoto: solo "Tutti". Mentre carica: i nomi non ci sono ancora, solo "Tutti" (decisione del piano: i nomi da soli arriverebbero insieme ai conteggi, che servono per la soglia). Ogni voce è `TvFocusable`; su TV il genere scelto prende il focus all'apertura.
  - `class CatalogTools extends StatefulWidget { ({required ItemKind kind, required ItemQuery query, required ValueChanged<ItemQuery> onChanged, CatalogTotals? totals}) }` — Ordina (menu `FilterPicker` esistente: Aggiunti/Nuovi episodi, Titolo, Anno, Voto), verso (icona freccia, tooltip "Inverti l'ordine"), Decennio (Tutti, 2020, 2010, 2000, 1990, Prima), serie: Tutte / In corso N / Concluse M (`totals`; senza totali senza numeri), interruttore "Nascondi i visti"/"Nascondi le viste" (`watched: unwatched`), "Azzera filtri" solo se `query.hasRefinements`, campo di ricerca a destra con attesa di 300 ms. Varianti: `compact` (Ordina, verso, Decennio — per le serie "Filtri" con dentro anche lo stato —, icona occhio, icona lente che sostituisce la riga con il campo e "Chiudi"); `tv` (niente ricerca).
- Testi (it): `catalogAll` "Tutti", `catalogAllFeminine` "Tutte", `catalogSortAdded` "Aggiunti", `catalogSortNewEpisodes` "Nuovi episodi", `catalogSortShort` "Ordina", `catalogReverse` "Inverti l'ordine", `catalogDecade` "Decennio", `catalogDecadeOlder` "Prima", `catalogFilters` "Filtri", `catalogStatusContinuing` "In corso", `catalogStatusEnded` "Concluse", `catalogHideWatched` "Nascondi i visti", `catalogHideWatchedSeries` "Nascondi le viste", `catalogSearchMovies` "Cerca tra i film", `catalogSearchSeries` "Cerca tra le serie", `catalogSearchClose` "Chiudi". (it e en.)

- [ ] **Step 1: test indice**: ordine e numeri come arrivano; tap su "Horror" → `onSelected('Horror')`, tap su "Tutti" → `onSelected(null)`; errore → solo "Tutti"; serie → "Tutte".
- [ ] **Step 2: test attrezzi**: cambio ordine → `onChanged` con `sort` nuovo e `reversed: false`; freccia → `reversed` invertito; Decennio "Prima" → `decade == ItemQuery.olderDecades`; interruttore → `watched: unwatched` e di nuovo `all`; "Azzera filtri" assente con query pulita, presente con decennio e riporta `clearRefinements()`; **Review Focus 4**: "d","u","n","e" a 100 ms l'uno dall'altro → un solo `onChanged` con `searchTerm: 'dune'` dopo 300 ms; svuotando il campo → `searchTerm` vuoto; `compact` mostra occhio e lente e la lente apre il campo; `tv` non ha il campo.
- [ ] **Step 3:** FAIL → `flutter gen-l10n` + implementa → PASS.
- [ ] **Step 4: Commit** `feat(app): indice dei generi e attrezzi del catalogo`

### Task 8: La pagina Film/Serie montata

**Files:**
- Modify: `app/lib/features/catalog/catalog_screen.dart`, `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/catalog/catalog_screen_test.dart`

**Interfaces:**
- Consumes: Task 4–7.
- Produces: `CatalogScreen({required ItemKind kind, CatalogView view, String? genre})`. In `initState` chiama `showGenre(widget.genre)`, in `didUpdateWidget` se il genere cambia. Struttura: `CustomScrollView` con `CatalogBand` (schede FILM/SAGHE come `tabs` per i film con le saghe disponibili, "SERIE" per le serie), `SliverPersistentHeader(pinned: !tv)` con indice + attrezzi su sfondo `WfColors.bg` (fermo sotto la barra: con `underBar: false` lo spazio della barra in cima va lasciato dalla testata ferma), griglia come oggi (`maxCrossAxisExtent` 180, pagine da 100, `BatchedEntrance`, `WfSwitcher` tra stati). Tap su un genere → `openCatalog(context, kind, genre: label)`. Stati della spec §12.
- Testi (it): `catalogEmptyMovies` "Nessun film con questi filtri.", `catalogEmptyMoviesGenre` "Nessun film di questo genere con questi filtri.", `catalogEmptySeries` "Nessuna serie con questi filtri.", `catalogEmptySeriesGenre` "Nessuna serie di questo genere con questi filtri.". (it e en.)

- [ ] **Step 1: test** (aggiornare quelli esistenti al nuovo disegno): apertura senza genere → titolo "TUTTI I FILM" (o come lo rende `WfText.display`), ordine "Aggiunti"; con `genre: 'Horror'` → titolo "Horror", una sola richiesta della griglia con `genres` Horror; dopo uno scroll di 1000 px su desktop la riga dei generi è ancora visibile (`find.byType(CatalogGenreIndex)` con `hitTestable()`); vuoto con genere → testo "di questo genere" e "Azzera filtri" che chiama `clearRefinements`; durante il primo caricamento il cartellone mostra già il titolo del genere sopra lo scheletro della griglia; errore → `ErrorView`; schede FILM/SAGHE presenti solo con la funzione `collections`.
- [ ] **Step 2:** FAIL → implementa → `flutter test test/features/catalog test/features/collections` PASS.
- [ ] **Step 3: Commit** `feat(app): pagine Film e Serie come sala per genere`

### Task 9: Card del catalogo

**Files:**
- Modify: `app/lib/ui/poster_card.dart`, `app/lib/core/jellyfin/item_models.dart` (campi `status`, `endDate`), `app/l10n/app_it.arb`, `app/l10n/app_en.arb`; in `catalog_screen.dart` passare `catalogStyle: true`
- Test: `app/test/ui/poster_card_test.dart` (esistente), test di `JellyfinItem.fromJson`

**Interfaces:**
- Produces: `JellyfinItem.status` (`String?`, da `Status`) e `JellyfinItem.endDate` (`DateTime?`, da `EndDate`). `PosterCard(..., catalogStyle: false)`: con `true` titolo su 2 righe; film: "anno  ★ 8.5" (voto con una cifra decimale, se c'è); visto: locandina con saturazione 55% e luminosità 80% (`ColorFiltered` con matrice), piena al passaggio del mouse o al focus; serie: riga "In corso" in oro se `status == 'Continuing'`, altrimenti "2008–2013" (`productionYear`–`endDate.year`, solo l'inizio se manca la fine o è lo stesso anno), terza riga episodi da vedere o "Vista tutta"; niente `CountBadge`. Con `false` tutto come oggi.
- Prima di implementare: verificare sul server (script python come in `CLAUDE.md`, "Live-test") che `/Items?includeItemTypes=Series` dia `Status` ed `EndDate` senza chiederli in `fields`; se no, aggiungerli ai `fields` della query del catalogo (`ItemQuery.toQueryParameters`) solo per le serie.
- Testi (it): `catalogSeriesContinuing` "In corso", `catalogSeriesToWatch` "{count, plural, =1{1 episodio da vedere} other{{count} episodi da vedere}}", `catalogSeriesAllWatched` "Vista tutta". (it e en.)

- [ ] **Step 1: test**: serie `Continuing` con 5 non visti → "In corso" e "5 episodi da vedere", nessun `CountBadge`; serie conclusa 2008–2013 tutta vista → "2008–2013", "Vista tutta"; senza `endDate` → "2022"; film visto → `ColorFiltered` presente, assente con `catalogStyle: false`; titolo lungo su 2 righe (`maxLines: 2`); `catalogStyle: false` invariato (i test esistenti passano senza modifiche).
- [ ] **Step 2:** FAIL → implementa → `flutter test test/ui test/features/catalog test/core/jellyfin` PASS.
- [ ] **Step 3: Commit** `feat(app): card del catalogo con stato e voto`

### Task 10: Saghe

**Files:**
- Create: `app/lib/features/collections/saga_fan_card.dart`
- Modify: `app/lib/features/collections/collections_grid.dart`, `collections_logic.dart` (`CollectionSort.added`, nome ripulito), `collections_providers.dart` (provider dei visti), `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/collections/collections_logic_test.dart`, `collections_grid_test.dart`, `collections_providers_test.dart`

**Interfaces:**
- Produces:
  - `String cleanSagaName(String name)`: toglie in fondo " - Collezione", " - Collection", " Collection", " Collezione" (senza maiuscole/minuscole).
  - `CollectionSort.added` (da `dateCreated`, più recente prima).
  - `final sagaItemsProvider = FutureProvider.autoDispose<Map<String, JellyfinItem>>`: tutti gli `itemIds` di `collectionsProvider` in una `LibraryApi.itemsByIds`, per `jellyfinIdKey`; `keepAlive` come `collectionsProvider`, rilettura con `libraryRevisionProvider` e `userDataRevisionProvider`.
  - `class SagaFanCard` (usata solo nella vista Saghe del catalogo): tre locandine dei primi titoli (ordine di `itemIds`) a ventaglio, la centrale più alta; nome ripulito; "4 film, 3 visti" / "tutti visti" / "nessuno visto"; barra con un tratto per film, oro se visto. Finché `sagaItemsProvider` non c'è: locandina della saga come oggi e nessuna barra.
  - Vista Saghe: `CatalogBand` con titolo "Saghe", fondale del primo film della saga aggiunta più di recente, riga "{count} saghe, {done} finite." (`done` dai visti); attrezzi: Ordina (Nome, Aggiunte di recente, Numero di film), verso, "Nascondi le saghe finite", Cerca (quella di oggi). Niente riga dei generi.
- Testi (it): `sagasBandLine` "{count} saghe, {done} finite.", `sagaSeenSome` "{total} film, {seen} visti", `sagaSeenAll` "{total} film, tutti visti", `sagaSeenNone` "{total} film, nessuno visto", `sagasHideDone` "Nascondi le saghe finite", `collectionsSortAdded` "Aggiunte di recente". (it e en.)

- [ ] **Step 1: test**: `cleanSagaName('Avengers - Collezione') == 'Avengers'`, `'Batman Collection' → 'Batman'`, `'Il padrino' → 'Il padrino'`; `CollectionSort.added`; provider chiama `itemsByIds` una volta con tutti gli id; card con 4 film di cui 3 visti → testo e 3 tratti oro su 4; "Nascondi le saghe finite" toglie quelle tutte viste; senza `sagaItemsProvider` la card mostra la locandina della saga.
- [ ] **Step 2:** FAIL → implementa → `flutter test test/features/collections test/features/search` PASS (Cerca usa ancora `CollectionCard`, invariata).
- [ ] **Step 3: Commit** `feat(app): saghe con ventaglio e film visti`

### Task 11: TV e finestre strette

**Files:**
- Modify: `catalog_screen.dart`, `catalog_band.dart`, `catalog_tools.dart`, `collections_grid.dart` (solo dove servono le varianti)
- Test: `app/test/features/tv_pages_test.dart`, `app/test/features/catalog/catalog_screen_test.dart`

**Interfaces:**
- Consumes: tutto il resto.
- Produces (spec §10–§11):
  - TV: cartellone 160 px, titolo 64; testata **non** ferma; il focus parte dal genere scelto; giù → attrezzi → griglia; quando il focus entra nella griglia la pagina scorre finché il cartellone e la barra escono (prima fila in cima); su dalla prima fila → attrezzi e pagina in cima; su dalla riga dei generi → schede FILM/SAGHE; sinistra dal primo genere → barra laterale come oggi. Ricorda: `goBack` va ignorato nei gestori di tasti; `ListView.builder` non costruisce fuori schermo (nei test di focus usare liste costruite).
  - `compact` (larghezza < 1024): cartellone 220, titolo 64, schede 26; attrezzi su una riga (Task 7); griglia come oggi.

- [ ] **Step 1: test TV** (con `pumpApp(..., tv: true)` a 960×540): all'apertura su "Horror" il focus è su "Horror"; giù due volte → focus sulla prima card e il cartellone non è più `hitTestable`; su → focus negli attrezzi e cartellone di nuovo visibile; nessun campo di ricerca.
- [ ] **Step 2: test stretto** (390×780 con `tester.view.physicalSize`): cartellone alto 220; ci sono l'icona occhio e la lente; tap sulla lente → campo di ricerca e "Chiudi".
- [ ] **Step 3:** FAIL → implementa → `flutter test test/features/tv_pages_test.dart test/features/catalog` PASS.
- [ ] **Step 4: Commit** `feat(app): sala per genere su TV e finestre strette`

### Task 12: Chiusura

**Files:**
- Modify: `docs/RELEASING.md` (checklist della 0.42.0), spec e bozze già nel ramo

- [ ] **Step 1:** aggiungi alla checklist manuale di `docs/RELEASING.md` (sezione della 0.42.0) una riga: "Film e Serie: generi con conteggi, un genere apre il suo cartellone e Indietro ci torna; Ordina, verso, Decennio, Nascondi i visti, ricerca; serie In corso / Concluse; Saghe con ventaglio e visti; Stasera e Match filtrano per genere (anche serie con generi inglesi); TV: la griglia prende lo schermo quando il focus ci entra."
- [ ] **Step 2:** da `app/`: `flutter gen-l10n && flutter analyze && flutter test` → nessun problema, tutti PASS; da `plugin/`: `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` → PASS.
- [ ] **Step 3: Commit** `docs: checklist della sala per genere`
