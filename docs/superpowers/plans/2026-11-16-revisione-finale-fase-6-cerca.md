# Revisione finale, fase 6: Cerca — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cerca che indovina cosa cercavi: ricerche recenti e generi prima di scrivere, un miglior risultato in cima, sezioni in ordine di pertinenza col conteggio e "Vedi tutti", la griglia del catalogo, "Da richiedere" onesto, telefono e TV coi loro layout.

**Architecture:** Il punteggio è una funzione pura in `features/search/search_ranking.dart`. `SearchController` porta i totali (`TotalRecordCount`) e, dopo i risultati, i dati delle prime sei persone. Le ricerche recenti sono un `Notifier` su `SharedPreferences` (già dipendenza, `sharedPreferencesProvider`). La pagina si divide in `search_screen.dart` (campo, stato), `search_start.dart` (prima di scrivere), `search_results.dart` (sezioni e griglia), `search_best.dart` (miglior risultato e persone) e `search_tv.dart` (file della TV). "Vedi tutti" apre il catalogo esistente con `?q=`; per le persone una pagina nuova `/people?q=`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, go_router, shared_preferences, lucide_icons_flutter, flutter_test, fake_async.

**Spec:** `docs/superpowers/specs/2026-11-16-revisione-finale-ui-design.md` (§8 tutta; §3.1 regole, §3.6 generi, §12 test di Cerca). Bozza: `docs/superpowers/specs/2026-11-16-revisione-finale-bozze/cerca.html` (sezione "Cosa serve nel codice").

## Global Constraints

- Lavoro nel worktree `.claude/worktrees/revisione-finale`, branch `revisione-finale-ui`. Comandi da `app/`. In Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Il worktree ha bisogno di `config/wonderflix.json` copiato da `C:\Users\sidot\Documents\Github\wonderflix\app\config\` e di `flutter pub get` e `flutter gen-l10n` prima di `analyze`/`test`.
- La fase 1 è già fatta: temi di chip, checkbox e switch in `theme.dart` (pastiglia scelta oro), generi nuovi in `genre_labels.dart`. Qui si usano `InputChip`, `ActionChip`, `ChoiceChip` col tema, senza stili propri.
- Nessun colore nuovo: solo `WfColors` (`bg`, `surface`, `surfaceHigh`, `border`, `gold`, `cream`, `creamMuted`, `error`, `online`). Titoli con `WfText.display(n)`.
- Misure del catalogo: margini 16 (stretto) / 32 (desktop) / 24 (TV); titoli di sezione `WfText.display` 26 / 30 / 22; griglia `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, crossAxisSpacing: 16, mainAxisSpacing: 24, mainAxisExtent: catalogCellExtent(...))` (o lo stesso calcolo in un `GridView` con `shrinkWrap`), `PosterCard(catalogStyle: true)`.
- Generi sempre con `genreLabel`, al massimo 2 nelle righe dei dati (`heroMeta` lo fa già). Numeri che cambiano (conteggi) con `FontFeature.tabularFigures()`.
- Testi in `l10n/app_it.arb` e `l10n/app_en.arb`, nel blocco `search*` / `requests*`. Niente etichette in maiuscolo. Le chiavi che non servono più si tolgono (e i test l10n che le citano: `test/app/l10n_plan2_test.dart:14`, `test/app/l10n_plan15a_test.dart:10,12`).
- Fuori dalla TV il comportamento TV non cambia, e viceversa: ogni layout TV è `compact && !tv` per lo stretto, `tv` per la TV.
- Nessuna lettura in più all'apertura di Cerca, salvo: le persone (sei `/Items` dopo i risultati), i generi (`catalogFiltersProvider`, una chiamata) e "Aggiunti di recente" (i provider della Home, in cache se la Home li ha letti).
- Widget test con la linea oro (`LinearProgressIndicator` indeterminato): `pumpAndSettle` non finisce mai, pompa a mano (`pump(Duration)`).
- I widget test di `SearchScreen` ora leggono `sharedPreferencesProvider`: `SharedPreferences.setMockInitialValues({...})`, `final prefs = await SharedPreferences.getInstance()`, override `sharedPreferencesProvider.overrideWithValue(prefs)` (anche in `test/features/tv_pages_test.dart`).
- `dart format` solo sulle righe toccate.
- Commit: messaggio in italiano, nessun trailer `Co-Authored-By`, mai le parole `closes`/`fixes`/`resolves`. Messaggi su più righe con `git commit -F <file>` (file senza BOM).
- Mai chiudere processi per nome immagine (`taskkill /IM`, `pkill`).
- Nessun cambio al plugin.

## Review Focus

- **Due profili sullo stesso PC:** le ricerche recenti di uno non compaiono all'altro (chiave per utente, `search.recent.<userId>`). Test in Task 4.
- **Invio subito dopo aver scritto (prima dei 300 ms, o mentre carica):** apre il miglior risultato del termine nuovo, non quello vecchio; se il nuovo non ne ha, non apre niente. Test in Task 6.
- **Apostrofo tipografico e accenti:** "L’Istituto" con `’` e "citta" per "Città" valgono come "L'Istituto" e "città" (punteggio 0, sottolineatura giusta). Test in Task 2.
- **Recenti doppi o vuoti:** "Dune " e "dune" sono un solo termine, spostato in cima; un termine sotto le 2 lettere non si salva; il nono spinge fuori il più vecchio. Test in Task 4.
- **Risultati vecchi mentre si affina:** un clic su una carta attenuata non apre niente, e in TV il focus non ci va. Test in Task 8.

---

### Task 1: Dati della ricerca nell'API

**Files:**
- Modify: `app/lib/core/jellyfin/item_models.dart` (`JellyfinItem`: campo `originalTitle` da `OriginalTitle`), `app/lib/core/jellyfin/item_query.dart` (due flag), `app/lib/core/jellyfin/library_api.dart:294-302` (`searchPeople`), `app/test/support/library_fakes.dart` (`searchPeople`, `peopleTotal`, `peopleCalls`; `testItem(originalTitle:)`)
- Test: `app/test/core/jellyfin/library_api_test.dart` (aggiorna 'ricerca persone'), `app/test/core/jellyfin/item_query_test.dart` (aggiungi; crealo se non c'è)

**Interfaces:**
- Produces:
  - `JellyfinItem.originalTitle: String?` (nel costruttore come gli altri campi facoltativi, letto in `fromJson`).
  - `ItemQuery(includeSearchFields: bool = false)`: aggiunge ai `fields` `OriginalTitle,RecursiveItemCount` (il secondo serve a `PlayedPercentage` delle serie, quindi al "già iniziato"). `ItemQuery(includePeople: bool = false)`: aggiunge `People`. Tutti e due entrano nella condizione che oggi costruisce `fields` (`item_query.dart:156`) e in `copyWith`/`==` se `ItemQuery` li ha.
  - `Future<ItemPage> searchPeople(String userId, String term, {int startIndex = 0, int limit = 12, CancelToken? cancelToken})`: query `{userId, searchTerm, startIndex, limit}`, risposta `ItemPage(items, TotalRecordCount)`.
  - Fake: `int? peopleTotal` (default `people.length`), `final peopleCalls = <(String term, int startIndex, int limit)>[]`; `searchPeople` risponde `pageOf(people.skip(startIndex).take(limit).toList(), peopleTotal ?? people.length)`.

- [ ] **Step 1: Test che falliscono**

```dart
test('ricerca persone: pagina e totale', () async {
  adapter.handler = (_) => const FakeResponse(200, {
    'Items': [{'Id': 'p1', 'Name': 'Christian Bale', 'Type': 'Person'}],
    'TotalRecordCount': 459,
  });
  final page = await api.searchPeople('u1', 'ist', startIndex: 100, limit: 100);
  expect(last().path, '/Persons');
  expect(last().query['startIndex'], 100);
  expect(page.totalCount, 459);
  expect(page.items.single.name, 'Christian Bale');
});
test('i campi della ricerca', () {
  final q = const ItemQuery(kinds: {ItemKind.movie}, includeSearchFields: true, includePeople: true)
      .toQueryParameters(userId: 'u', startIndex: 0, limit: 1);
  expect((q['fields'] as String).split(','),
      containsAll(['OriginalTitle', 'RecursiveItemCount', 'People']));
});
test('OriginalTitle arriva nel titolo', () {
  expect(JellyfinItem.fromJson({'Id': 'm', 'Name': 'Maleficent - Signora del male',
      'Type': 'Movie', 'OriginalTitle': 'Maleficent: Mistress of Evil'}).originalTitle,
      'Maleficent: Mistress of Evil');
});
```

- [ ] **Step 2:** `flutter test test/core/jellyfin` → FAIL.
- [ ] **Step 3:** implementa; aggiorna il fake e l'unica chiamata (`search_controller.dart:83`: `.then((page) => page.items)` per ora).
- [ ] **Step 4:** `flutter test test/core test/features/search` → PASS.
- [ ] **Step 5: Commit** `feat(app): titolo originale e totale delle persone nella ricerca`

### Task 2: Punteggio, miglior risultato, ordine delle sezioni

**Files:**
- Create: `app/lib/features/search/search_ranking.dart`
- Test: `app/test/features/search/search_ranking_test.dart`

**Interfaces:**
- Consumes: `foldForSearch(String)` (`features/collections/collections_logic.dart`); `JellyfinItem.originalTitle` e `testItem(originalTitle:)` (Task 1). `bestResult` guarda solo il nome (un 3 non vince mai); `originalLast` e `sectionOrder` anche il titolo originale.
- Produces:
  - `int? matchScore(String term, String name, {String? originalTitle})`: 0 il nome comincia col termine, anche saltando un articolo iniziale; 1 una parola del nome comincia col termine (anche un termine di più parole, a confine di parola); 2 il nome lo contiene; 3 lo contiene solo `originalTitle`; `null` se nessuno dei due lo contiene. Confronti su `foldForSearch` di tutti e due; `’` (U+2019) vale `'`.
  - `const searchArticles = ["l'", 'il ', 'lo ', 'la ', 'i ', 'gli ', 'le ', "un'", 'un ', 'uno ', 'una ', 'the ', 'a ', 'an ']` (già piegati).
  - `JellyfinItem? bestResult(String term, {required List<JellyfinItem> movies, required List<JellyfinItem> series, required List<JellyfinItem> people})`.
  - `(int, int)? highlightRange(String name, String term)`: inizio e fine (esclusa) del pezzo da sottolineare.
  - `List<JellyfinItem> originalLast(String term, List<JellyfinItem> items)`: stabile, solo i punteggio 3 in fondo.
  - `enum SearchSection { sagas, movies, series, people }` e `List<SearchSection> sectionOrder(String term, Map<SearchSection, String> firstNames, {Map<SearchSection, String?> firstOriginals = const {}})`: le chiavi presenti, per punteggio del primo elemento (`null` in fondo), a parità nell'ordine dell'enum.

Regole di `bestResult` (spec §8.2): candidati film e serie con punteggio 0 o 1; vince il più basso; a parità prima i già iniziati (`item.userData.progress != null`), poi le serie, poi l'ordine in cui arrivano. Una persona vince solo se il nome comincia col termine (punteggio 0 sul nome, senza articoli) e nessun titolo ha 0; tra più persone la prima della lista. Nessun candidato: `null`.

`highlightRange`: cerca prima l'occorrenza che dà il punteggio (inizio dopo l'articolo, poi inizio di parola), sennò la prima. Indici sul nome originale: va bene piegare carattere per carattere solo se `foldForSearch(name).length == name.length`; altrimenti confronto senza accenti non possibile → `null`. `// shortcut: niente sottolineatura per nomi con 'æ', 'ß'…, se servisse una mappa degli indici`.

- [ ] **Step 1: Test che falliscono**

```dart
group('matchScore', () {
  final cases = <(String, String, String?, int?)>[
    ('ist', "L'Istituto", null, 0),
    ('ist', 'L’Istituto', null, 0),
    ('IST', "L'Istituto", null, 0),
    ('cas', 'La casa di carta', null, 0),
    ('pad', 'Il padrino', null, 0),
    ('wre', 'The Wrestler', null, 0),
    ('quiet', 'A Quiet Place', null, 0),
    ('altra', "Un'altra vita", null, 0),
    ('the', 'The Wrestler', null, 0),
    ('gli inc', 'Gli Incredibili', null, 0),
    ('dune', 'Dune: Parte Due', null, 0),
    ('citta', 'Città di Dio', null, 0),
    ('fist', "Marvel's Iron Fist", null, 1),
    ('iron fist', "Marvel's Iron Fist", null, 1),
    ('list', 'The Terminal List: Lupo Nero', null, 1),
    ('ist', 'Il mistero di Istanbul', null, 1),
    ('ist', 'Il mistero della pietra', null, 2),
    ('tra', 'Lo straniero', null, 2),
    ('ist', 'Maleficent - Signora del male', 'Maleficent: Mistress of Evil', 3),
    ('ist', "L'Istituto", 'The Institute', 0),
    ('ist', 'Dune', null, null),
  ];
  for (final (term, name, original, score) in cases) {
    test('"$term" in "$name" vale $score', () =>
        expect(matchScore(term, name, originalTitle: original), score));
  }
});

group('bestResult', () {
  JellyfinItem m(String n, {double? progress}) => testItem(id: n, name: n, playedPercentage: progress);
  JellyfinItem s(String n) => testItem(id: n, name: n, kind: ItemKind.series);
  JellyfinItem p(String n) => testItem(id: n, name: n, kind: ItemKind.person);
  // (caso, termine, film, serie, persone, nome atteso o null)
  final cases = <(String, String, List<JellyfinItem>, List<JellyfinItem>, List<JellyfinItem>, String?)>[
    ('per "ist" L'Istituto', 'ist', [m('Il mistero della pietra')],
        [s("Marvel's Iron Fist"), s("L'Istituto")], [p('Christian Bale')], "L'Istituto"),
    ('solo "contiene": nessuna carta', 'ist', [m('Il mistero della pietra')], [], [], null),
    ('il più basso', 'dun', [m('Le grandi dune'), m('Dune')], [], [], 'Dune'),
    ('a parità la serie', 'dune', [m('Dune')], [s('Dune: Prophecy')], [], 'Dune: Prophecy'),
    ('a parità il già iniziato', 'dune', [m('Dune', progress: 40)], [s('Dune: Prophecy')], [], 'Dune'),
    ('a parità tra serie la prima', 'dark', [], [s('Dark'), s('Dark Matter')], [], 'Dark'),
    ('persona che comincia batte un 1', 'christ', [m('Il ritorno di Christine')], [], [p('Christopher Nolan')], 'Christopher Nolan'),
    ('un titolo con 0 batte la persona', 'christ', [m('Christine')], [], [p('Christopher Nolan')], 'Christine'),
    ('persona che lo contiene soltanto', 'ist', [], [], [p('Christian Bale')], null),
  ];
  for (final (name, term, movies, series, people, expected) in cases) {
    test(name, () => expect(
        bestResult(term, movies: movies, series: series, people: people)?.name, expected));
  }
});

group('highlightRange', () {
  test('dopo l\'articolo', () => expect(highlightRange("L'Istituto", 'ist'), (2, 5)));
  test('accenti', () => expect(highlightRange('Città di Dio', 'citta'), (0, 5)));
  test('più parole', () => expect(highlightRange("Marvel's Iron Fist", 'iron fist'), (9, 18)));
  test('l\'inizio di parola prima del pezzo interno',
      () => expect(highlightRange('Il mistero di Istanbul', 'ist'), (14, 17)));
  test('nessuna corrispondenza', () => expect(highlightRange('Dune', 'ist'), isNull));
});

test('originalLast porta in fondo solo i titoli originali, nell\'ordine', () {
  // a: 2, b: 3, c: 0, d: 3 → a, c, b, d
});

test('sectionOrder: per punteggio del primo elemento, a parità l\'ordine fisso', () {
  expect(sectionOrder('ist', {
    SearchSection.movies: 'Il mistero della pietra',
    SearchSection.series: "L'Istituto",
    SearchSection.people: 'Christian Bale',
  }), [SearchSection.series, SearchSection.movies, SearchSection.people]);
  expect(sectionOrder('dune', {
    SearchSection.series: 'Dune: Prophecy', SearchSection.movies: 'Dune',
  }), [SearchSection.movies, SearchSection.series]);
});
```

- [ ] **Step 2:** `flutter test test/features/search/search_ranking_test.dart` → FAIL (file mancante).
- [ ] **Step 3:** implementa le funzioni in `search_ranking.dart`.
- [ ] **Step 4:** stesso comando → PASS.
- [ ] **Step 5: Commit** `feat(app): punteggio del miglior risultato di Cerca`

### Task 3: SearchController con totali, Invio e persone

**Files:**
- Modify: `app/lib/features/search/search_controller.dart`
- Test: `app/test/features/search/search_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 (`searchPeople` → `ItemPage`, `includeSearchFields`, `includePeople`).
- Produces:
  - `SearchResults({movies, series, people, required int movieTotal, required int seriesTotal, required int peopleTotal, Map<String, PersonFacts>? facts})`; `isEmpty` invariato. `facts == null`: dati delle persone in arrivo.
  - `class PersonFacts { const PersonFacts({required JellyfinItem knownFor, required int titles, String? roleType}); }` (`roleType` = `PersonRef.type` della persona nel `People` di `knownFor`: "Actor", "Director"…).
  - `SearchController.submit()`: se c'è un'attesa o una ricerca in corso per `state.term` (≥ 2 lettere), annulla l'attesa e cerca subito; altrimenti niente.
  - `static const peopleWithFacts = 6`.

Comportamento:
- Film e serie: `ItemQuery(kinds: {kind}, searchTerm: term, includeProviderIds: true, includeOverview: true, includeSearchFields: true)`, `limit: 24` come oggi; il totale da `page.totalCount`.
- Persone: `searchPeople(..., limit: 12)`, totale da `totalCount`.
- Appena arrivati i risultati, `state` li mostra con `facts: null`. Poi, con lo stesso `CancelToken`, una `api.items(ItemQuery(kinds: {ItemKind.movie, ItemKind.series}, personId: id, sort: CatalogSort.rating, includePeople: true), limit: 1)` per ognuna delle prime sei, in parallelo; una che fallisce o non ha titoli resta senza dati (niente errore). Poi `state` con `facts` e con le prime sei riordinate per `titles` decrescente (stabile; senza dati in fondo alle sei); le persone dalla settima restano dove sono.
- Un termine nuovo annulla anche le chiamate delle persone.

- [ ] **Step 1: Test che falliscono**

```dart
test('i totali arrivano dalla risposta', () {
  // onItems: film → pageOf([dune], 15), serie → pageOf([], 0); people 1, peopleTotal 459
  // dopo 350 ms: results.movieTotal 15, seriesTotal 0, peopleTotal 459
});
test('le prime sei persone: titolo noto, numero di titoli, riordinate', () {
  fakeAsync((async) {
    // people p1..p7; onItems con query.personId: p1 → pageOf([a], 2), p2 → pageOf([b], 10), altre → pageOf([], 0)
    // b.people = [{'Id': 'p2', 'Name': 'P2', 'Type': 'Director'}]
    // setTerm('ist'); elapse 350 ms; flushMicrotasks
    final r = container.read(searchControllerProvider).results!;
    expect(api.itemQueries.where((q) => q.personId != null).map((q) => q.personId),
        ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']);
    expect(r.people.map((p) => p.id).take(2), ['p2', 'p1']);
    expect(r.people.last.id, 'p7');
    expect(r.facts!['p2']!.titles, 10);
    expect(r.facts!['p2']!.roleType, 'Director');
    expect(r.facts!.containsKey('p3'), isFalse);
  });
});
test('submit cerca subito, senza aspettare i 300 ms', () {
  // setTerm('dune'); submit(); elapse 10 ms → api.itemQueries non vuoto
});
test('la ricerca chiede titolo originale, trama e conteggio degli episodi', () {
  // ogni query di film/serie ha includeSearchFields e includeOverview
});
```

- [ ] **Step 2:** `flutter test test/features/search/search_controller_test.dart` → FAIL.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** stesso comando → PASS; `flutter test test/features/search test/features/requests` → PASS (`LibraryMatches.fromResults` costruisce `SearchResults`: aggiorna i test che lo creano con i totali).
- [ ] **Step 5: Commit** `feat(app): Cerca conta i risultati e legge le persone più presenti`

### Task 4: Ricerche recenti

**Files:**
- Create: `app/lib/features/search/recent_searches.dart`
- Test: `app/test/features/search/recent_searches_test.dart`

**Interfaces:**
- Consumes: `sharedPreferencesProvider` (`app/providers.dart`), `currentUserIdProvider` (`features/library/library_providers.dart`).
- Produces:
  - `class RecentSearches extends Notifier<List<String>>`: dal più recente; `static const max = 8`; chiave `'search.recent.$userId'` (`getStringList`/`setStringList`).
  - `void add(String term)`: `trim()`; sotto `SearchController.minLength` non fa niente; toglie il doppione senza badare a maiuscole e accenti (`foldForSearch`), lo mette in cima, tiene i primi 8.
  - `void remove(String term)`, `void clear()`.
  - `final recentSearchesProvider = NotifierProvider<RecentSearches, List<String>>(RecentSearches.new);`

- [ ] **Step 1: Test che falliscono** (`ProviderContainer.test` con `sharedPreferencesProvider` e `sessionControllerProvider` finti, come `search_controller_test.dart`)

```dart
test('il più recente in cima, al massimo 8', () {
  for (var i = 1; i <= 9; i++) recent.add('termine $i');
  expect(state(), hasLength(8));
  expect(state().first, 'termine 9');
  expect(state(), isNot(contains('termine 1')));
});
test('un doppione torna in cima una volta sola', () {
  recent..add('dune')..add('dark')..add('Dune ');
  expect(state(), ['Dune', 'dark']);
});
test('sotto le 2 lettere non si salva', () { recent.add(' d '); expect(state(), isEmpty); });
test('resta sul dispositivo dopo un riavvio', () {
  recent.add('chernobyl');
  // nuovo container con le stesse prefs → ['chernobyl']
});
test('ogni profilo ha le sue', () {
  // utente u1 aggiunge 'dune'; container con utente u2 sulle stesse prefs → []
});
test('togli e cancella', () { /* remove('dune') → senza; clear() → [] e chiave vuota */ });
```

- [ ] **Step 2:** `flutter test test/features/search/recent_searches_test.dart` → FAIL.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** stesso comando → PASS.
- [ ] **Step 5: Commit** `feat(app): ricerche recenti salvate sul dispositivo, per profilo`

### Task 5: Catalogo aperto con una ricerca, colonne, margine delle righe

**Files:**
- Modify: `app/lib/features/catalog/catalog_navigation.dart`, `app/lib/app/router.dart:231-253` (`/movies`, `/series`: `search: state.uri.queryParameters['q']`), `app/lib/features/catalog/catalog_screen.dart` (`search`), `app/lib/features/catalog/catalog_controller.dart:59` (`showGenre`), `app/lib/features/catalog/catalog_tools.dart:46` (`_searchOpen` iniziale), `app/lib/ui/poster_card.dart:28` (`catalogColumnCount`), `app/lib/ui/media_row.dart` (`side`)
- Test: `test/features/catalog/catalog_navigation_test.dart`, `test/features/catalog/catalog_controller_test.dart`, `test/features/catalog/catalog_screen_test.dart`, `test/ui/poster_card_test.dart` (o dove sono i test di `catalogCellExtent`)

**Interfaces:**
- Produces:
  - `void openCatalogSearch(BuildContext context, ItemKind kind, String term)`: `context.push('/movies?q=…')` (o `/series`), così Indietro torna a Cerca coi risultati.
  - `CatalogScreen({..., String? search})`; `didUpdateWidget` ricarica anche se cambia `search`. In TV, dove la barra del catalogo non ha il campo di ricerca, con un termine attivo in cima alla griglia c'è una pastiglia "Cerca: “ist”" con la ✕ (prende il focus; OK la toglie e il catalogo torna intero). Test: TV a 960×540 con `search: 'ist'` → `find.text('Cerca: “ist”')`; OK sulla pastiglia → sparisce e la query non ha più il termine.
  - `CatalogController.showGenre(String? genre, {String? searchTerm})`: con `searchTerm` non nullo lo mette nella query; senza, tiene quello di prima (oggi).
  - `int catalogColumnCount(double extent)` = `max(1, (extent / (180 + 16)).ceil())`, usata anche da `catalogCellExtent`.
  - `MediaRow({..., double? side})`: margine laterale; senza, quello di oggi (`compact ? 16 : 32`).
- In `CatalogTools`, `_searchOpen` parte `true` se `widget.query.searchTerm` non è vuoto (nello stretto il termine si vede e "Chiudi" lo toglie). In TV `CatalogTools` non ha la ricerca: non cambia (vedi domanda aperta nel resoconto).

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('openCatalogSearch apre il catalogo con la ricerca e Indietro torna', (tester) async {
  // router '/search' + '/:p' come nel test esistente; openCatalogSearch(ctx, ItemKind.movie, 'ist')
  expect(location(), '/movies?q=ist');
  router.pop(); await tester.pumpAndSettle();
  expect(location(), '/search');
});
test('showGenre con una ricerca la mette nella query', () async {
  // showGenre(null, searchTerm: 'ist') → api.itemQueries.last.searchTerm 'ist'
  // poi showGenre('Dramma') → searchTerm ancora 'ist'
});
testWidgets('il catalogo aperto con ?q mostra il termine nello stretto', (tester) async {
  // CatalogScreen(kind: movie, search: 'ist') a 390×780 → TextField con 'ist'
  // e prima query con searchTerm 'ist'
});
test('colonne come la griglia del catalogo', () {
  expect(catalogColumnCount(358), 2);  // telefono 390 − 32
  expect(catalogColumnCount(1216), 7); // 1280 − 64
});
```

- [ ] **Step 2:** `flutter test test/features/catalog test/ui` → FAIL sui nuovi.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** stessi test → PASS.
- [ ] **Step 5: Commit** `feat(app): il catalogo si apre con una ricerca già scritta`

### Task 6: Campo e pagina prima di scrivere

**Files:**
- Create: `app/lib/features/search/search_start.dart`
- Modify: `app/lib/features/search/search_screen.dart` (`_searchField`, `build`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/search/search_screen_test.dart`, `app/test/features/search/search_start_test.dart` (nuovo)

**Interfaces:**
- Consumes: `recentSearchesProvider` (Task 4), `SearchController.submit()` (Task 3), `bestResult` (Task 2), `catalogFiltersProvider(kind)` (`catalog_controller.dart:119`), `openCatalog(context, kind, genre:)`, `homeLatestMoviesProvider`/`homeLatestSeriesProvider` (`features/home/home_providers.dart`), `catalogColumnCount` (Task 5).
- Produces:
  - `class SearchStart extends ConsumerWidget { const SearchStart({super.key, required ValueChanged<String> onRecent, required double side}); }`.
  - In `_SearchScreenState`: `void _remember()` (salva `state.term` nei recenti) e `void _openBest()`; le usa il Task 7.

Campo (spec §8.1):
- `SizedBox(height: 56)`, lente a sinistra, `hintText: l.searchHint` ("Titolo, attore o regista"), testo 18. Un `TextEditingController` e un `FocusNode` sempre (oggi il nodo c'è solo in TV).
- Fuori dalla TV: `suffixIcon` ✕ (`IconButton`, `LucideIcons.x`, tooltip `l.searchClear` "Svuota") solo con testo: svuota, `setTerm('')` dei due controller, ridà il focus. Esc col testo svuota allo stesso modo (`CallbackShortcuts` sul campo; col campo vuoto Esc passa oltre).
- Invio (`onSubmitted`, `textInputAction: TextInputAction.search`): con termine ≥ 2 lettere salva il termine nei recenti; se lo stato ha già i risultati di questo termine e non carica, apre il miglior risultato (se c'è); sennò `submit()` e lo apre all'arrivo dei risultati di quel termine (un flag `_openWhenReady = term` letto in `ref.listen(searchControllerProvider, ...)`). Aprire = `openItem(context, item, heroSource: 'search.best')`.
- TV: come oggi (`TvFocusable` + `ExcludeFocus`, OK riapre la tastiera col testo), senza ✕.
- Margini: la `ListView` non ha più `EdgeInsets.all(32)`: ogni blocco ha `side` = `tv ? 24 : (compact ? 16 : 32)`, in alto 24 (16 nello stretto).

Prima di scrivere (`state.term.length < 2`, al posto di `l.searchPrompt`, che si toglie):
- **Ricerche recenti** (solo se ce ne sono): testa con "Ricerche recenti" (Inter 15 w600), "Solo su questo dispositivo" in `creamMuted` 12,5, a destra `TextButton` "Cancella". Pastiglie `InputChip` con `LucideIcons.history` 14, il termine, ✕ (`onDeleted` → `remove`, tooltip "Togli “{term}”"); un tocco chiama `onRecent(term)`: lo schermo scrive il termine nel campo e cerca (tutti e due i controller).
- **Prova con un genere**: testa con "Prova con un genere" e a destra due `ChoiceChip` "Film" / "Serie" (`l.navMovies`/`l.navSeries`, stato nel widget, parte da Film); sotto `ActionChip` per ogni genere di `catalogFiltersProvider(kind)` (già tradotti), che chiamano `openCatalog(context, kind, genre: label)`. In caricamento o con errore il blocco non c'è.
- **Aggiunti di recente**: titolo di sezione (26/30/22), griglia del catalogo di una riga (`catalogColumnCount` titoli; 4 nello stretto), film e serie alternati (primo un film) dai due provider della Home; se uno fallisce, l'altro; tutti e due falliti o vuoti: niente sezione.
- Chiavi nuove: `searchClear` "Svuota", `searchRecentTitle` "Ricerche recenti", `searchRecentDeviceOnly` "Solo su questo dispositivo", `searchRecentClearAll` "Cancella", `searchRecentRemove` "Togli “{term}”", `searchGenresTitle` "Prova con un genere", `searchLatestTitle` "Aggiunti di recente"; cambia `searchHint`; via `searchPrompt`. In inglese: "Clear", "Recent searches", "Only on this device", "Clear", "Remove “{term}”", "Try a genre", "Recently added", "Title, actor or director".

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('prima di scrivere: recenti, generi e aggiunti di recente', (tester) async {
  SharedPreferences.setMockInitialValues({'search.recent.${testUser.id}': ['chernobyl', 'dune']});
  // api.filtersByKind[ItemKind.movie] = LibraryFilters(genres: ['Dramma', 'Fantascienza'])
  // onItems: sort dateAdded film → [Hope], serie → [Steins;Gate]
  expect(find.text('Ricerche recenti'), findsOneWidget);
  expect(find.text('Solo su questo dispositivo'), findsOneWidget);
  expect(find.widgetWithText(InputChip, 'chernobyl'), findsOneWidget);
  expect(find.text('Prova con un genere'), findsOneWidget);
  expect(find.widgetWithText(ActionChip, 'Dramma'), findsOneWidget);
  expect(find.text('Aggiunti di recente'), findsOneWidget);
  expect(find.text('Hope'), findsOneWidget);
  expect(find.text('Steins;Gate'), findsOneWidget);
  expect(find.text('Titolo, attore o regista'), findsOneWidget);
});
testWidgets('un recente si cerca, la ✕ lo toglie, Cancella li toglie tutti', (tester) async {
  // tap 'dune' → TextField 'dune', dopo 350 ms i risultati
  // tooltip 'Togli “chernobyl”' → sparisce; 'Cancella' → niente 'Ricerche recenti'
});
testWidgets('Serie e poi un genere aprono il catalogo Serie col genere', (tester) async {
  // pumpAppRouter con '/search' e '/:p'; tap ChoiceChip 'Serie', tap 'Dramma'
  // location '/series?genre=Dramma'
});
testWidgets('✕ ed Esc svuotano e il campo resta col focus', (tester) async {
  // enterText 'dune' → tooltip 'Svuota' c'è; tap → testo vuoto, hasFocus; di nuovo 'dune', Esc → vuoto
});
testWidgets('Invio salva il termine e apre il miglior risultato', (tester) async {
  // router; serie "L'Istituto"; enterText 'ist', pump 350 ms; tester.testTextInput.receiveAction(TextInputAction.search)
  // → location '/item/…' e prefs ha ['ist']
});
testWidgets('Invio prima dei 300 ms apre il miglior risultato del termine nuovo', (tester) async {
  // risultati di 'dun' già mostrati (miglior risultato 'Dune'); enterText 'dark', subito Invio
  // → dopo la risposta la rotta è la scheda di 'Dark', non di 'Dune'
});
testWidgets('scrivere senza aprire nulla non salva', (tester) async {
  // enterText 'dune', pump 350 ms → prefs senza la chiave
});
```

- [ ] **Step 2:** `flutter test test/features/search` → FAIL.
- [ ] **Step 3:** implementa; chiavi in it/en; `flutter gen-l10n`; aggiorna gli override dei test esistenti (Global Constraints) e `l10n_plan2_test.dart` se cita `searchPrompt`.
- [ ] **Step 4:** `flutter test test/features/search test/features/tv_pages_test.dart test/app` → PASS.
- [ ] **Step 5: Commit** `feat(app): Cerca con ricerche recenti, generi e aggiunti di recente`

### Task 7: Miglior risultato e persone

**Files:**
- Create: `app/lib/features/search/search_best.dart`
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/search/search_best_test.dart`

**Interfaces:**
- Consumes: `highlightRange` (Task 2), `PersonFacts` (Task 3), `heroMeta` (`features/home/hero_labels.dart`), `imageUrlsProvider` (`backdrop`, `poster`), `playItem(context, ref, item)` (`features/playback/play_launcher.dart`), `openItem`, `WfButton.primary`/`.secondary`.
- Produces:
  - `class SearchBestCard extends ConsumerWidget { const SearchBestCard({super.key, required JellyfinItem item, required String term, PersonFacts? facts, required VoidCallback onOpened, bool tv = false}); }`.
  - `class SearchPeopleList extends ConsumerWidget { const SearchPeopleList({super.key, required List<JellyfinItem> people, required Map<String, PersonFacts>? facts, required String term, required int total, VoidCallback? onSeeAll, required VoidCallback onOpened}); }`: colonna del desktop, al massimo 6 righe; senza `onSeeAll` niente "Vedi tutte".
  - `class SearchPersonTile extends ConsumerWidget { const SearchPersonTile({super.key, required JellyfinItem person, PersonFacts? facts, required String term, required VoidCallback onOpened}); }`: tondo 72, nome, "N titoli"; per la fila del telefono e della TV.
  - `Text highlightedName(String name, String term, TextStyle style)`: `Text.rich` col pezzo di `highlightRange` sottolineato oro (`decoration: TextDecoration.underline`, `decorationColor: WfColors.gold`, `decorationThickness: 2`).
  - `String? personRoleLabel(AppLocalizations l, String? type)`: "Actor"/"GuestStar" → "Interprete", "Director" → "Regia", "Writer" → "Sceneggiatura", "Producer" → "Produzione", "Composer" → "Musica"; altro → `null`. (Jellyfin non sa il genere della persona: niente "Attore"/"Attrice" della bozza.)
- `onOpened` lo schermo lo collega a `_remember()` (Task 6) e va chiamato prima di ogni apertura.

Carta (spec §8.2):
- Fondale `urls.backdrop(item)` con velo scuro da sinistra (come il carosello), angoli 10, alta 280 (desktop) / 240 (stretto), a tutta la larghezza disponibile.
- Dentro, in basso a sinistra: "Miglior risultato" in oro 12,5 w600; nome `WfText.display(44)` (32 nello stretto) con `highlightedName`; riga dei dati `"${l.navSeries|l.navMovies} · ${heroMeta(item, l)}"` più `★ 7,5` in oro se c'è `communityRating`, cifre tabellari; trama in 2 righe (`maxLines: 2`, ellissi), `creamMuted`; pulsanti `WfButton.primary` "Riproduci" (`l.actionPlay`, `LucideIcons.play`, `playItem`) e `WfButton.secondary` "Scheda" (`l.searchOpenDetails`, `LucideIcons.info`, `openItem`), alti 44 nello stretto.
- Persona come miglior risultato: niente fondale (fondo `surface`), foto tonda 96 a sinistra, sotto il nome "ruolo · titolo noto · N titoli" (quando ci sono i `facts`), un solo pulsante primario "Scheda".
- `SearchPeopleList`: testa "Persone" (`l.searchPeople`, `WfText.display` 26/30/22), il totale piccolo, "Vedi tutte" a destra se c'è `onSeeAll` e `total > 6`; righe con foto 44, `highlightedName`, sotto "Regia · *Il cavaliere oscuro*" (ruolo, poi `knownFor.name` in corsivo), a destra `searchPersonTitles` ("10 titoli", tabellari). Senza `facts` (in arrivo) la seconda riga non c'è e le righe non saltano (altezza fissa).
- Chiavi: `searchBestLabel` "Miglior risultato", `searchOpenDetails` "Scheda", `searchSeeAllPeople` "Vedi tutte", `searchPersonTitles` "{count, plural, =1{1 titolo} other{{count} titoli}}", `searchRoleActor` "Interprete", `searchRoleDirector` "Regia", `searchRoleWriter` "Sceneggiatura", `searchRoleProducer` "Produzione", `searchRoleComposer` "Musica" (en: "Top result", "Details", "See all", "{count, plural, =1{1 title} other{{count} titles}}", "Cast", "Director", "Writer", "Producer", "Music").

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('la carta: etichetta, nome sottolineato, dati, trama, due pulsanti', (tester) async {
  // SearchBestCard(item: serie "L'Istituto" 2025, childCount 2, genres ['Thriller'], overview lunga, rating 7.5, term 'ist')
  expect(find.text('Miglior risultato'), findsOneWidget);
  final rich = tester.widget<RichText>(find.byWidgetPredicate((w) =>
      w is RichText && w.text.toPlainText() == "L'Istituto"));
  // lo span sottolineato è 'Ist', oro
  expect(find.textContaining('Serie · 2025 · 2 stagioni · Thriller'), findsOneWidget);
  expect(find.text('Riproduci'), findsOneWidget);
  expect(find.text('Scheda'), findsOneWidget);
});
testWidgets('una persona: solo Scheda, coi dati', (tester) async { /* facts titles 10, Director → 'Regia', '10 titoli'; find.text('Riproduci') findsNothing */ });
testWidgets('le persone: ruolo, titolo noto, numero; Vedi tutte se sono di più', (tester) async {
  // 6 persone, total 459, facts p2 → 'Regia', 'Il cavaliere oscuro', 10
  expect(find.text('10 titoli'), findsOneWidget);
  expect(find.textContaining('Regia'), findsOneWidget);
  expect(find.text('Vedi tutte'), findsOneWidget);
});
testWidgets('aprire dalla carta chiama onOpened', (tester) async { /* tap Scheda → contatore 1 */ });
test('ruoli senza genere', () {
  expect(personRoleLabel(it, 'Actor'), 'Interprete');
  expect(personRoleLabel(it, 'Director'), 'Regia');
  expect(personRoleLabel(it, 'Producer'), 'Produzione');
  expect(personRoleLabel(it, 'Lighting'), isNull);
});
```

- [ ] **Step 2:** `flutter test test/features/search/search_best_test.dart` → FAIL.
- [ ] **Step 3:** implementa; chiavi; `flutter gen-l10n`.
- [ ] **Step 4:** stesso comando → PASS.
- [ ] **Step 5: Commit** `feat(app): miglior risultato di Cerca e persone con ruolo e titoli`

### Task 8: Sezioni, griglia, Vedi tutti, affinamento, vuoto

**Files:**
- Create: `app/lib/features/search/search_results.dart`
- Modify: `app/lib/features/search/search_screen.dart` (`_results`, `_posterSection`, `_peopleSection` spariscono), `app/lib/features/collections/sagas_search_section.dart` (griglia, titolo 26/30/22), `app/lib/ui/skeletons.dart` (`SearchResultsSkeleton` con la griglia), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/search/search_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 (`bestResult`, `originalLast`, `sectionOrder`, `matchScore`), Task 3 (`SearchResults` coi totali), Task 5 (`openCatalogSearch`, `catalogColumnCount`), Task 7 (carta, persone). "Vedi tutte" delle persone lo collega il Task 10 (qui `onSeeAll: null`).
- Produces: `class SearchResultsView extends ConsumerWidget { const SearchResultsView({super.key, required SearchState state, required List<CollectionSummary> sagas, required VoidCallback onOpened}); }` per desktop e telefono (la TV è il Task 11).

Disposizione (desktop, spec §8.2):
- In cima, se `bestResult` non è `null`: `Row` con la carta (`Expanded`) e, se ci sono persone, `SizedBox(width: 380, child: SearchPeopleList(...))` con 24 in mezzo. Con una persona come miglior risultato, la lista ha le altre.
- Poi le sezioni in `sectionOrder` (primo elemento di ognuna dopo `originalLast`). La sezione Persone compare qui solo se non è già accanto alla carta (nessun miglior risultato): stessa `SearchPeopleList` a tutta larghezza.
- Sezione Film/Serie: testa con titolo (26/30/22), totale piccolo (`movieTotal`/`seriesTotal`, tabellari) e, se il totale supera i titoli mostrati, "Vedi tutti" (`l.searchSeeAll`) → `onOpened()` e `openCatalogSearch(context, kind, term)`. Corpo: griglia del catalogo di **una riga** (`catalogColumnCount(larghezza)` titoli) di `originalLast(term, items)`; una carta di un titolo col punteggio 3 ha `PosterCard(subtitle: l.searchOriginalTitle(item.originalTitle!))`. Ogni `PosterCard` ha `onTap: () { onOpened(); openItem(context, item, heroSource: ...); }`.
- Saghe: `SagasSearchSection` nella griglia (tutte quelle trovate, al massimo 12, nessun "Vedi tutti"), al posto che dà `sectionOrder`. `CollectionCard` non ha `onTap`: aprire una saga non salva il termine (`// shortcut:` nel codice).
- "Da richiedere" (Task 9) resta sempre in fondo.
- Telefono (`compact && !tv`, spec §8.3): carta a tutta larghezza; sotto, le persone in una fila (`MediaRow` di `SearchPersonTile`, conteggio nel titolo, "Vedi tutte" come `trailing`); sezioni con **4 titoli** (due righe da due) e sotto, a tutta larghezza, un `TextButton` "Vedi tutti i 15 film" / "Vedi tutte le 3 serie" (`searchSeeAllMoviesCount`, `searchSeeAllSeriesCount`) quando il totale è più di 4.
- Mentre affina (`state.loading` con risultati vecchi): sotto il campo una `LinearProgressIndicator` alta 2, oro su trasparente; i risultati in `AnimatedOpacity(opacity: 0.4)` dentro `IgnorePointer` ed `ExcludeFocus`. Senza `loading` la linea non c'è (spazio di 2 riservato, il campo non salta).
- Nessun risultato (né titoli, né persone, né saghe): `l.searchNoTitles(term)` "Nessun titolo per “{term}”. Controlla l'ortografia o prova col titolo originale."; quando "Da richiedere" ha finito e non ha titoli da mostrare (o la funzione non c'è) diventa `l.searchNoTitlesAnywhere(term)` "Nessun titolo per “{term}”, nemmeno su TMDB. Controlla l'ortografia o prova col titolo originale." Senza la funzione delle richieste resta la prima frase. "Da richiedere" segue subito sotto.
- Chiavi: `searchSeeAll` "Vedi tutti", `searchSeeAllMoviesCount` "Vedi tutti i {count} film", `searchSeeAllSeriesCount` "Vedi tutte le {count} serie", `searchSeeAllPeopleCount` "Vedi tutte le {count} persone" (la usa il Task 10 sulla fila del telefono), `searchOriginalTitle` "Titolo originale: {title}", `searchNoTitles`, `searchNoTitlesAnywhere`; via `searchNoResults` (e il suo test in `l10n_plan2_test.dart`). En: "See all", "See all {count} movies", "See all {count} series", "See all {count} people", "Original title: {title}", "No titles for “{term}”. Check the spelling or try the original title.", "No titles for “{term}”, not even on TMDB. Check the spelling or try the original title."

- [ ] **Step 1: Test che falliscono** (a `Size(1280, 800)` salvo dove detto)

```dart
testWidgets('per "ist": miglior risultato, poi Serie prima di Film, coi conteggi', (tester) async {
  // film: 15 di totale, 7 in risposta, il primo 'Il mistero della pietra'; serie: "L'Istituto", "Marvel's Iron Fist", totale 3
  expect(find.text('Miglior risultato'), findsOneWidget);
  expect(tester.getTopLeft(find.text('Serie')).dy, lessThan(tester.getTopLeft(find.text('Film')).dy));
  expect(find.text('15'), findsOneWidget);
  expect(find.text('Vedi tutti'), findsOneWidget); // solo Film è tagliata
});
testWidgets('Vedi tutti apre il catalogo Film con la ricerca', (tester) async {
  // router: tap 'Vedi tutti' → '/movies?q=ist'
});
testWidgets('il titolo trovato per il titolo originale va in fondo e lo dice', (tester) async {
  // film ['Maleficent - Signora del male' (originale 'Maleficent: Mistress of Evil'), 'Il mistero della pietra']
  // → 'Il mistero…' prima; find.text('Titolo originale: Maleficent: Mistress of Evil') findsOneWidget
});
testWidgets('griglia: sette colonne a 1280, nessun overflow', (tester) async {
  // 10 film → 7 PosterCard nella sezione Film; tester.takeException() isNull
});
testWidgets('telefono 390: due colonne, quattro titoli e "Vedi tutti i 15 film"', (tester) async {
  // surfaceSize 390×780, touch: true
  // le prime due PosterCard alla stessa dy, la terza sotto; 4 PosterCard nella sezione Film
  expect(find.text('Vedi tutti i 15 film'), findsOneWidget);
  // nessun overflow
});
testWidgets('mentre affina: linea oro, risultati attenuati che non si aprono', (tester) async {
  // risultati di 'ist' mostrati; enterText 'isti'; pump(100 ms)
  expect(find.byType(LinearProgressIndicator), findsOneWidget);
  // tap sulla prima PosterCard → la rotta non cambia
  // pump(350 ms) → linea sparita
});
testWidgets('nessun titolo: la frase e sotto i da richiedere', (tester) async {
  // libreria vuota per 'odissea', Seerr con 'Odissea' (posterPath) → frase con “odissea”, sezione 'Da richiedere'
});
testWidgets('nessun titolo nemmeno su TMDB', (tester) async {
  // Seerr vuoto → 'Nessun titolo per “zzz”, nemmeno su TMDB. Controlla l\'ortografia o prova col titolo originale.'
});
```

Aggiorna i test esistenti di `search_screen_test.dart` ai testi nuovi (es. 'nessun risultato' → la frase nuova) e la sezione saghe (`find.text('Saghe')` resta).

- [ ] **Step 2:** `flutter test test/features/search/search_screen_test.dart` → FAIL.
- [ ] **Step 3:** implementa; chiavi; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/search test/features/collections test/app` → PASS.
- [ ] **Step 5: Commit** `feat(app): risultati di Cerca per pertinenza, coi conteggi e Vedi tutti`

### Task 9: Da richiedere

**Files:**
- Modify: `app/lib/features/requests/requestables_section.dart`, `app/lib/features/requests/requestable_poster_card.dart`, `app/lib/features/requests/requestables_controller.dart:133` (`visibleRequestables`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/requests/requestables_controller_test.dart`, `app/test/features/search/search_screen_test.dart` (sezione), `test/app/l10n_plan15a_test.dart`

**Interfaces:**
- Consumes: `MediaRow({side})` (Task 5), `rowPosterSize(context)`, `openRequestable(context, title)`, `highlightedName` (Task 7).
- Produces:
  - `visibleRequestables(titles, library)`: in più toglie i titoli senza `posterPath` e quelli con `status == TitleStatus.available`.
  - `RequestablesSection({required LibraryMatches? library, String term = '', VoidCallback? onOpened})`: `onOpened` chiamato prima di aprire (salva il recente).
  - `RequestablePosterCard`: senza etichetta in alto a sinistra; sotto la locandina il titolo (sottolineato col termine), "Film · 2026" / "Serie · 1993" (`requestsKindMovie`/`requestsKindSeries` e anno), poi lo stato: con `TitleStatus.none` un pulsante piccolo "+ Richiedi" (`LucideIcons.plus`, `l.requestsRequest`, bordo oro) che chiama `onTap`; altrimenti una riga in oro con icona: `pending` `LucideIcons.check` "Richiesto", `processing` `LucideIcons.clock` "In arrivo", `partial` `LucideIcons.circleDashed` "In parte". Tocco sulla carta e "Richiedi" aprono la stessa scheda di oggi (`openRequestable`). `requestableBadge` sparisce (resta `RequestBadge`, lo usa la Home).

Sezione (spec §8.2): titolo "Da richiedere" (26/30/22), sotto `l.requestsSectionSubtitle` = "Trovati su TMDB, non ancora su WonderFlix: chiedili all'admin" (en "Found on TMDB, not on WonderFlix yet: ask the admin"); una fila sola (`MediaRow`, `side` della pagina, altezza da `rowPosterSize(context).rowHeight` + la riga dello stato), su ogni piattaforma; lo scheletro è una fila. Via `requestsBadgeOnWonderflix` e il suo test.

- [ ] **Step 1: Test che falliscono**

```dart
test('niente titoli senza locandina né già su WonderFlix', () {
  // [a(poster), b(posterPath null), c(status available, poster)] → [a]
});
testWidgets('le carte dicono Richiedi o lo stato', (tester) async {
  // titoli: none 'Fakt ist!', pending, processing 'Odissea', partial
  expect(find.text('Richiedi'), findsOneWidget);
  expect(find.text('Richiesto'), findsOneWidget);
  expect(find.text('In arrivo'), findsOneWidget);
  expect(find.text('In parte'), findsOneWidget);
  expect(find.text('Trovati su TMDB, non ancora su WonderFlix: chiedili all\'admin'), findsOneWidget);
  expect(find.text('Su WonderFlix'), findsNothing);
});
testWidgets('una fila sola', (tester) async {
  // 12 titoli a 1280: tutte le carte alla stessa dy (MediaRow)
});
testWidgets('Richiedi apre la scheda di richiesta', (tester) async {
  // router: tap 'Richiedi' → '/tmdb/movie/<id>'
});
```

- [ ] **Step 2:** `flutter test test/features/requests test/features/search` → FAIL.
- [ ] **Step 3:** implementa; chiavi; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/requests test/features/search test/features/tv_pages_test.dart test/features/tv_focus_borders_test.dart test/app` → PASS.
- [ ] **Step 5: Commit** `feat(app): Da richiedere con Richiedi o lo stato, solo titoli con locandina`

### Task 10: Tutte le persone

**Files:**
- Create: `app/lib/features/search/people_search_screen.dart`
- Modify: `app/lib/app/router.dart` (rotta `/people`, `detailPage`, `underBar: true`, come `/person/:id`), `app/lib/features/search/search_results.dart` (`onSeeAll: () { onOpened(); openPeopleSearch(context, term); }` sulla lista del desktop e sulla fila del telefono, dove il `trailing` è "Vedi tutte le 459 persone" con `searchSeeAllPeopleCount`)
- Test: `app/test/features/search/people_search_screen_test.dart`

**Interfaces:**
- Consumes: `searchPeople(startIndex:, limit:)` (Task 1), `SearchPersonTile` (Task 7).
- Produces:
  - `void openPeopleSearch(BuildContext context, String term)` → `context.push(Uri(path: '/people', queryParameters: {'q': term}).toString())`.
  - `class PeopleSearchScreen extends ConsumerStatefulWidget { const PeopleSearchScreen({super.key, required String term}); }`
  - `class PeopleSearchController extends Notifier<PeopleSearchState>` (family per termine, autoDispose), pagine da 100, `loadMore()`; `PeopleSearchState({items, total, loading, error})` sullo stampo di `CatalogState`.

Pagina: titolo "Persone" in Bebas (26/30/22) col totale accanto, sotto la griglia del catalogo (`maxCrossAxisExtent: 180`, spaziature 16/24) di `SearchPersonTile` (senza `facts`: tondo, nome, niente conteggio); carica la pagina dopo a 800 dal fondo, come `catalog_screen.dart:83-88`; errore con `ErrorView` e "Riprova". Nessun dato per persona (niente chiamate in più).

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('tutte le persone di "ist", 100 per volta', (tester) async {
  // fake people 150, peopleTotal 150
  expect(find.text('Persone'), findsOneWidget);
  expect(find.text('150'), findsOneWidget);
  expect(api.peopleCalls.first, ('ist', 0, 100));
  // scroll in fondo → peopleCalls.last == ('ist', 100, 100)
});
testWidgets('Vedi tutte da Cerca apre la pagina e Indietro torna', (tester) async {
  // router '/search' + '/people': tap 'Vedi tutte' → '/people?q=ist'; pop → '/search'
});
```

- [ ] **Step 2:** `flutter test test/features/search/people_search_screen_test.dart` → FAIL.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** stesso comando e `flutter test test/app` (router) → PASS.
- [ ] **Step 5: Commit** `feat(app): pagina con tutte le persone trovate da Cerca`

### Task 11: Cerca in TV

**Files:**
- Create: `app/lib/features/search/search_tv.dart`
- Modify: `app/lib/features/search/search_screen.dart` (sceglie la vista TV), `app/lib/features/search/search_start.dart` (file TV)
- Test: `app/test/features/tv_pages_test.dart` (gruppo Cerca), `app/test/features/search/search_tv_test.dart` (nuovo)

**Interfaces:**
- Consumes: Task 2, 3, 7, 8, 9; `MediaRow(side: 24, titleSize: 22)`, `rowPosterSize`, `TvFocusable`.
- Produces: `class SearchTvResults extends ConsumerWidget { const SearchTvResults({super.key, required SearchState state, required List<CollectionSummary> sagas, required VoidCallback onOpened}); }`.

Regole (spec §8.3):
- Focus iniziale sulla cornice del campo, come oggi (nessun autofocus nei file sotto).
- Prima di scrivere: due file, "Ricerche recenti" (pastiglie in una `ListView` orizzontale, OK cerca il termine; niente ✕ sulle pastiglie, "Cancella" ultimo della fila) e "Prova con un genere" (prima le due pastiglie Film / Serie, poi i generi). Niente "Aggiunti di recente". Le pastiglie hanno il bordo del focus della TV (`TvFocusBorder`, come `CatalogBandTab`).
- Risultati: una `MediaRow` per sezione nell'ordine di `sectionOrder`, margine 24, titoli 22, conteggio nel titolo. La fila della sezione del miglior risultato comincia con una carta larga (16:9, alta come le locandine della fila, col fondale, "Miglior risultato" e il nome sottolineato; OK apre la scheda) e poi gli altri titoli senza ripeterlo. Se la lista è tagliata (totale > titoli), l'ultima carta della fila è "Vedi tutti" (locandina vuota `surfaceHigh` con `LucideIcons.arrowRight` e la scritta; OK come "Vedi tutti" del desktop). Persone: fila di `SearchPersonTile`, ultima "Vedi tutte". "Da richiedere" ultima fila.
- Su e Giù cambiano fila, Destra e Sinistra scorrono (il comportamento di `MediaRow` in TV).
- Mentre affina: stessa linea oro e `ExcludeFocus` dei risultati vecchi.

- [ ] **Step 1: Test che falliscono** (`tv: true`, `Size(960, 540)`)

```dart
testWidgets('TV: prima di scrivere due file, focus sulla cornice', (tester) async {
  // recenti ['dune'], generi ['Dramma']
  expect(find.text('Ricerche recenti'), findsOneWidget);
  expect(find.text('Prova con un genere'), findsOneWidget);
  expect(find.text('Aggiunti di recente'), findsNothing);
  // il TextField non ha il focus; Giù → focus sulla pastiglia 'dune'
});
testWidgets('TV: il miglior risultato è la prima carta della sua fila', (tester) async {
  // serie "L'Istituto" migliore: nella fila Serie la prima carta ha 'Miglior risultato';
  // "L'Istituto" compare una volta sola nella fila
});
testWidgets('TV: l\'ultima carta di una fila tagliata è Vedi tutti', (tester) async {
  // film totale 15, 7 in risposta → l'ultima card della fila Film è 'Vedi tutti'; OK → '/movies?q=ist'
});
testWidgets('TV: nessun overflow a 960×540', (tester) async { /* takeException isNull */ });
```

Aggiorna 'risultati e "Da richiedere" sono focalizzabili' in `tv_pages_test.dart` (ora le carte stanno in `MediaRow`).

- [ ] **Step 2:** `flutter test test/features/search/search_tv_test.dart test/features/tv_pages_test.dart` → FAIL.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** stessi test e `flutter test test/features/tv_focus_borders_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat(app): Cerca in TV con una fila per sezione`

### Task 12: Checklist e verifica

**Files:**
- Modify: `docs/RELEASING.md` (checklist della 0.42.0, dopo la riga "Stasera e Match nuovi")

- [ ] **Step 1:** aggiungi la riga:
  `- [ ] Cerca nuova (app 0.42.0): campo con ✕, Esc che svuota e Invio che apre il miglior risultato; ricerche recenti (solo su questo dispositivo, per profilo, ✕ e Cancella) e "Prova con un genere" con Film/Serie che apre il catalogo; "Aggiunti di recente"; per "ist" L'Istituto come miglior risultato col pezzo sottolineato, persone con ruolo e numero di titoli, Serie prima di Film, conteggi e "Vedi tutti" che apre il catalogo con la ricerca (Indietro torna), "Vedi tutte" le persone; un titolo trovato per il titolo originale in fondo con "Titolo originale: …"; linea oro mentre affini; "odissea" con Da richiedere sotto (Richiedi o lo stato, niente riquadri vuoti); telefono a due colonne; TV con una fila per sezione e "Vedi tutti" in fondo.`
- [ ] **Step 2: Verifica completa:** `flutter gen-l10n`, `flutter analyze` (nessun problema nuovo), `flutter test` (tutti verdi; i flaky noti si rilanciano una volta).
- [ ] **Step 3: Commit** `docs: checklist di Cerca nuova`

## Prova a mano (dopo la review finale)

Release build e avvio dal worktree (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`, poi `Start-Process build\windows\x64\runner\Release\wonderflix.exe`):
- Cerca vuota: generi Film e Serie (uno apre il catalogo filtrato), "Aggiunti di recente".
- "ist": L'Istituto in cima, persone con ruolo e titoli, ordine Serie / Film, "Vedi tutti" dei film (catalogo con "ist", Indietro torna ai risultati), "Vedi tutte" le persone (459, scorre).
- Scrivi "isti" piano: linea oro, risultati attenuati. Invio su "dune": apre la scheda; il termine compare nei recenti, anche dopo un riavvio, non con un altro profilo.
- "odissea": frase e Da richiedere con "In arrivo"; "zzzq": "nemmeno su TMDB".
- Finestra stretta (sotto 1024 px): due colonne, persone in fila, "Vedi tutti i N film".
- APK sulla Fire Stick (comando in CLAUDE.md): focus sulla cornice, recenti e generi col telecomando, "ist" con le file, miglior risultato come prima carta, "Vedi tutti" in fondo alla fila dei film.
