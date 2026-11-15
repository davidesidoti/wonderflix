# La mia lista, nuova UI — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La mia lista diventa una pagina con:
- un cartellone che propone il prossimo titolo da vedere;
- le schede Tutti / Film / Serie;
- i gruppi Da continuare / Da iniziare / Visti;
- attrezzi che crescono con la lista;
- un modo per togliere un titolo, o tutti i visti, con Annulla;
- l'ordine per data di aggiunta alla lista, salvata dall'app.

**Architecture:**
- **Dati.** La lista resta una richiesta sola (`favoritesProvider`), e `buildMyListView` divide i titoli nei gruppi nell'app. La data di aggiunta sta nei `CustomPrefs` di `wonderflix-home`, con un notifier che scrive una volta alla volta (come `NextUpHidden`), ed è `UserDataOverrides` a scriverla.
- **Pagina.** È una `CustomScrollView`: `CatalogBand` (con un pulsante sotto la riga), poi gli attrezzi, poi i gruppi. La scheda scelta sta nell'indirizzo (`?kind=`).

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, go_router, Jellyfin 10.11. Nessun cambio al plugin.

**Spec:** `docs/superpowers/specs/2026-11-15-mia-lista-ui-design.md` (bozza: `docs/superpowers/specs/2026-11-15-mia-lista-bozze/lista.html`). Chi esegue legge entrambe; i § qui sotto sono quelli della spec.

## Global Constraints

- Stile invariato: Noir & Oro (`WfColors`), Bebas Neue (`WfText.display`), Inter. Nessun colore nuovo.
- Fuori dalla TV il comportamento TV non cambia, e viceversa (`FormFactor.of(context).tv`).
- La pagina non si apre più lenta di oggi. Cartellone, gruppi e card compaiono con la sola risposta di `favoritesProvider`; prossimo episodio e date possono arrivare dopo.
- Restano come sono la riga "La mia lista" della Home, la scheda del titolo, l'anteprima e `CatalogFiltersBar` (la usano ancora altri). `favoritesProvider` resta in `my_list_screen.dart`, perché lo usa anche `queue_add_view.dart`.
- Testi nuovi in `app/l10n/app_it.arb` e `app/l10n/app_en.arb`, poi `flutter gen-l10n`. Si riusano `actionPlay`, `actionPlayEpisode`, `actionResumeEpisode`, `previewResume`, `catalogSeriesToWatch`, `catalogSortTitle/Year/Rating`, `catalogReverse`, `catalogClearFilters`, `catalogAll`, `navMovies`, `navSeries`, `navMyList`, `actionUndo`, e `episodeCode(item)` di `features/library/item_labels.dart`.
- Commit in italiano. Autore solo l'utente: niente `Co-Authored-By` né righe "Generated with". Mai le parole `closes`, `fixes`, `resolves`. Si formattano solo le righe toccate.
- Comandi da `app/`. In Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`.
  - Worktree nuovo: copiare `config/wonderflix.json` dal checkout principale, poi `flutter pub get` e `flutter gen-l10n`.
  - Controlli: `flutter analyze`, `flutter test <file>`.
  - Build di prova: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- Mai `taskkill /IM` o `pkill`.
- Se un comando Flutter cambia `windows/flutter/generated_plugin*` solo nei fine riga: `git checkout --` di quei file.

## Review Focus

1. **Annulla dopo una ricarica della lista.** Togli un titolo e, mentre l'avviso è aperto, cambia qualcosa sul server (`libraryRevisionProvider`): la lista si rilegge senza quel titolo. Premendo Annulla il titolo deve tornare nella pagina, non solo sul server. Test nel Task 7.
2. **Serie senza conteggi.** Il server può mandare una serie senza `UnplayedItemCount` né `RecursiveItemCount`. Deve stare in Da iniziare, senza errori né "0 episodi". Test nel Task 4.
3. **Date non lette all'apertura.** Se la lettura di `myListAdded` fallisce, la prima scrittura rilegge prima di scrivere, così non cancella le date salvate. Test nel Task 2.
4. **Doppio tocco e Togli i visti durante una richiesta.** Un titolo con una richiesta ancora in corso viene saltato (come fa `_toggle`), senza errore. L'avviso conta solo quelli tolti davvero. Test nel Task 3.
5. **Togli i visti con solo serie in corso viste tutte.** Il pulsante non compare, il gruppo sì. Test nel Task 7.

---

### Task 1: Campi della lista e avanzamento che resta

**Files:**
- Modify: `app/lib/core/jellyfin/item_models.dart` (campo nuovo e `fromJson`)
- Modify: `app/lib/core/jellyfin/item_query.dart` (~riga 154, i `fields` di `includeSortFields`)
- Modify: `app/lib/features/library/user_data.dart` (`toggleFavorite`)
- Test: `app/test/core/jellyfin/item_models_test.dart`, `app/test/core/jellyfin/item_query_test.dart`, `app/test/features/library/user_data_test.dart` (crearlo se manca, sul modello dei test che già usano `userDataOverridesProvider`)

**Interfaces:**
- Produces:
  - `JellyfinItem.dateLastMediaAdded` (`DateTime?`, da `DateLastMediaAdded`);
  - con `includeSortFields: true`, i `fields` contengono `SortName,DateCreated,RecursiveItemCount,DateLastMediaAdded`;
  - dopo `toggleFavorite` di una serie, `playedPercentage` e `unplayedItemCount` restano quelli di prima se la risposta del server non li ha.

- [ ] **Step 1: test**

```dart
test('DateLastMediaAdded', () {
  final item = JellyfinItem.fromJson({'Id': 's', 'Name': 'S', 'Type': 'Series',
      'DateLastMediaAdded': '2026-11-10T08:00:00Z'});
  expect(item.dateLastMediaAdded, DateTime.utc(2026, 11, 10, 8));
});
test('i campi per ordinare nell\'app chiedono anche i conteggi delle serie', () {
  final q = const ItemQuery(kinds: {ItemKind.series}, includeSortFields: true)
      .toQueryParameters(userId: 'u', startIndex: 0, limit: 1); // parametri come negli altri test del file
  expect((q['fields'] as String).split(','),
      containsAll(['SortName', 'DateCreated', 'RecursiveItemCount', 'DateLastMediaAdded']));
});
test('il cuore non cancella l\'avanzamento di una serie', () async {
  // FakeLibraryApi.setFavorite risponde UserItemData(isFavorite: …): senza
  // PlayedPercentage né UnplayedItemCount, come Jellyfin per una serie.
  // Serie con userData(playedPercentage: 40, unplayedItemCount: 3, isFavorite: true).
  await overrides.toggleFavorite(series);
  expect(container.read(userDataOverridesProvider)['s']!.isFavorite, isFalse);
  expect(container.read(userDataOverridesProvider)['s']!.playedPercentage, 40);
  expect(container.read(userDataOverridesProvider)['s']!.unplayedItemCount, 3);
});
```

- [ ] **Step 2:** `flutter test test/core/jellyfin/item_models_test.dart test/core/jellyfin/item_query_test.dart test/features/library/user_data_test.dart`. Atteso: FAIL sui tre test nuovi.
- [ ] **Step 3: implementazione.**
  - Aggiungere il campo, il parsing e i due `fields`.
  - In `toggleFavorite` la risposta confermata si unisce a `before`: `playedPercentage: confirmed.playedPercentage ?? before.playedPercentage`, e lo stesso per `unplayedItemCount`. Il resto viene dalla risposta. Il punto è il callback `send` di `toggleFavorite`, non `_toggle` (così `togglePlayed` resta com'è).
- [ ] **Step 4:** stessi test, PASS; poi `flutter test test/features/mylist test/features/player/queue_panel`. Atteso: PASS, oppure gli stessi fallimenti di prima della modifica.
- [ ] **Step 5:** commit `feat(app): campi della lista per serie e nuovi episodi`

### Task 2: Data di aggiunta salvata (`myListAdded`)

**Files:**
- Modify: `app/lib/core/jellyfin/display_preferences_api.dart`
- Create: `app/lib/features/library/my_list_added.dart`
- Modify: `app/test/support/home_fakes.dart` (`FakeDisplayPreferencesApi`)
- Test: `app/test/core/jellyfin/display_preferences_api_test.dart`, `app/test/features/library/my_list_added_test.dart`

**Interfaces:**
- Produces:
  - `DisplayPreferencesApi.myListAddedKey = 'myListAdded'`;
  - `Future<Map<String, DateTime>> readMyListAdded(String userId)`. La voce è una stringa JSON `{"<id>":"<ISO 8601 UTC>"}`. Chiavi `jellyfinIdKey`; voci storte saltate; JSON storto → `{}`;
  - `Future<void> writeMyListAdded(String userId, Map<String, DateTime> added)`. Mappa vuota → la voce sparisce. Le altre voci di `CustomPrefs` restano (`_update`);
  - in `my_list_added.dart`:
    - `class MyListAdded extends AsyncNotifier<Map<String, DateTime>>` con:
      - `Future<bool> change(Map<String, DateTime?> changes)`: `null` toglie la voce. Fa **una** scrittura; restituisce `false` se non salvata, e allora lo stato torna com'era;
      - `void retainOnly(Set<String> ids)`: cambia solo lo stato, senza scrivere; la pulizia va sul server con la scrittura dopo;
    - `final myListAddedProvider = AsyncNotifierProvider<MyListAdded, Map<String, DateTime>>(MyListAdded.new);`
  - nel fake: `Map<String, DateTime> myListAdded`, `List<Map<String, DateTime>> myListAddedWrites`, `Object? myListAddedReadError`, `Object? myListAddedWriteError`, `Completer<void>? myListAddedWriteGate`.

Il notifier copia `NextUpHidden` (`features/home/next_up_hidden.dart`):
- le scritture sono in fila su `_writes`;
- la mappa da scrivere si prende quando tocca a quella scrittura;
- dopo una lettura fallita (`_stale`) si rilegge una volta prima di scrivere;
- si rilegge al cambio di utente (`currentUserIdProvider`).

- [ ] **Step 1: test** (in `my_list_added_test.dart`, con `FakeDisplayPreferencesApi` come i test di `NextUpHidden`)

```dart
test('due change di fila: due scritture, la seconda ha anche la prima', ...
  // gate sulla prima scrittura; change({'a': d1}); change({'b': d2}); apri il gate
  expect(prefs.myListAddedWrites.last, {'a': d1, 'b': d2});
test('null toglie la voce', ... expect(prefs.myListAddedWrites.last, isEmpty));
test('lettura fallita: prima di scrivere rilegge, le date del server restano', ...
  // myListAddedReadError al build, poi lo si toglie e il server ha {'x': d0}
  await notifier.change({'a': d1});
  expect(prefs.myListAddedWrites.single, {'x': d0, 'a': d1});
test('scrittura fallita: false e lo stato torna com\'era', ...);
test('retainOnly non scrive; la scrittura dopo non ha le voci tolte', ...);
```

E in `display_preferences_api_test.dart`, sul modello dei test di `nextUpHidden`:
- `readMyListAdded` con JSON valido, con una voce storta e con JSON storto;
- `writeMyListAdded` che lascia `homeRows` e `nextUpHidden` com'erano e toglie la voce se la mappa è vuota.

- [ ] **Step 2:** `flutter test test/features/library/my_list_added_test.dart test/core/jellyfin/display_preferences_api_test.dart`. Atteso: FAIL (metodi e provider mancanti).
- [ ] **Step 3:** implementare API, notifier e fake.
- [ ] **Step 4:** stessi test, PASS.
- [ ] **Step 5:** commit `feat(app): data di aggiunta a La mia lista nelle preferenze`

### Task 3: Il cuore scrive la data; cuori in blocco

**Files:**
- Modify: `app/lib/features/library/user_data.dart`
- Test: `app/test/features/library/user_data_test.dart`

**Interfaces:**
- Consumes: `myListAddedProvider` (Task 2).
- Produces:
  - `toggleFavorite(JellyfinItem item)`, stessa firma. Quando il server conferma il cuore acceso, `change({id: clock.now().toUtc()})`; quando lo conferma spento, `change({id: null})`. Se la scrittura della data fallisce il cuore resta: l'errore non sale;
  - `Future<List<JellyfinItem>> setFavorites(List<JellyfinItem> items, {required bool favorite, Map<String, DateTime> addedAt = const {}})`:
    - una richiesta per titolo, in parallelo, ognuna come `_toggle` (stato subito, ritorno indietro se fallisce);
    - i titoli che hanno già una richiesta in corso si saltano;
    - alla fine fa **una** `change` della data: per i riusciti spenti `null`, per i riusciti accesi `addedAt[id] ?? now`;
    - restituisce i titoli non riusciti; non lancia errori.

- [ ] **Step 1: test**

```dart
test('cuore acceso: la data di adesso; spento: la voce sparisce', ...
  // withClock(Clock.fixed(DateTime.utc(2026, 11, 15, 10)))
  expect(prefs.myListAddedWrites.last, {'a': DateTime.utc(2026, 11, 15, 10)});
  // secondo toggle
  expect(prefs.myListAddedWrites.last, isEmpty);
test('setFavorites: una scrittura sola della data per tutti', ...
  await overrides.setFavorites([a, b, c], favorite: false);
  expect(api.favoriteCalls, unorderedEquals([('a', false), ('b', false), ('c', false)]));
  expect(prefs.myListAddedWrites, hasLength(1));
test('setFavorites con addedAt rimette le date di prima', ...
  await overrides.setFavorites([a], favorite: true, addedAt: {'a': d0});
  expect(prefs.myListAddedWrites.last['a'], d0);
test('setFavorites: un fallimento torna com\'era ed è nel risultato', ...
  // api.favoriteError per 'b'
  expect(failed.map((i) => i.id), ['b']);
  expect(container.read(userDataOverridesProvider)['b']!.isFavorite, isTrue);
test('setFavorites salta un titolo con una richiesta in corso', ...
  // gate su setFavorite di 'a', toggleFavorite(a) in volo, poi setFavorites([a, b])
  expect(api.favoriteCalls.where((c) => c.$1 == 'a'), hasLength(1));
test('data non salvata: il cuore resta acceso', ... // myListAddedWriteError
```

Se `FakeLibraryApi` non ha un errore o un gate per singolo id su `setFavorite`, si aggiungono lì.

- [ ] **Step 2:** `flutter test test/features/library/user_data_test.dart`. Atteso: FAIL.
- [ ] **Step 3:** implementare. `setFavorites` riusa `_toggle` per ogni titolo e raccoglie i fallimenti; serve un modo per sapere se `_toggle` ha saltato il titolo (per esempio farle restituire `bool`).
- [ ] **Step 4:** `flutter test test/features/library test/features/detail test/ui`. Atteso: PASS.
- [ ] **Step 5:** commit `feat(app): il cuore salva la data e si toglie in blocco`

### Task 4: `buildMyListView`, gruppi e titolo di punta

**Files:**
- Rewrite: `app/lib/features/mylist/my_list_view.dart`
- Rewrite: `app/test/features/mylist/my_list_view_test.dart` (tiene i test d'ordine che valgono ancora)

**Interfaces:**
- Produces (tutto in `my_list_view.dart`):

```dart
enum MyListTab { all, movies, series;
  /// Dal parametro `kind` dell'indirizzo; sconosciuto o assente: all.
  static MyListTab parse(String? raw); }
enum MyListGroup { resume, start, watched }
const myListRefinementsThreshold = 24;
/// Spec §6.1. Serie: watched se unplayedItemCount == 0; resume se
/// unplayedItemCount > 0 e (playedPercentage > 0, oppure
/// recursiveItemCount != null && unplayedItemCount < recursiveItemCount);
/// start negli altri casi, anche senza conteggi.
MyListGroup myListGroup(JellyfinItem item, UserItemData data);
class MyListFilters {
  const MyListFilters({this.sort = CatalogSort.dateAdded, this.reversed = false, this.genre, this.search = ''});
  final CatalogSort sort; final bool reversed; final String? genre; final String search;
  bool get hasRefinements; // genre != null || search non vuota
  MyListFilters copyWith({CatalogSort? sort, bool? reversed, Object? genre = _keep, String? search});
}
class MyListView {
  final JellyfinItem? hero;
  final List<JellyfinItem> resume, start, watched; // genere+ricerca, ordinati, senza hero
  final int tabCount, resumeCount, startCount, watchedCount; // scheda intera, hero compreso
  final List<GenreCount> genres; // della scheda, genreLabel, per conteggio poi nome
  final bool showRefinements; // preferiti di tutte le schede > 24
  final bool listEmpty; // nessun preferito
  final List<JellyfinItem> removableWatched; // `watched` senza le serie status == 'Continuing'
  final bool noResults; // filters.hasRefinements e nessun titolo della scheda (hero compreso) passa genere e ricerca
}
MyListView buildMyListView(List<JellyfinItem> items, MyListTab tab, MyListFilters filters,
    Map<String, UserItemData> overrides, Map<String, DateTime> added);
```

Regole:
- **Cuore.** I titoli senza cuore (contando `overrides`) spariscono, come oggi.
- **Ordine.** Il verso di default è decrescente per Aggiunti, Anno e Voto, e A→Z per Titolo. `reversed` inverte la chiave principale; a parità vale sempre il titolo A→Z (`_byTitle`, che c'è già); chi non ha valore resta in fondo.
- **Aggiunti.** Prima chi ha la data in `added`, dal più recente. Poi chi non ce l'ha, per `dateCreated` dal più recente. Col verso inverso l'ordine si rovescia tutto.
- **Titolo di punta.** Si calcola sulla scheda intera, ignorando genere e ricerca: il primo `resume` nell'ordine, se no il primo `start`, se no `null`.
- **Genere.** Confronto su `genreLabel` dei generi del titolo.
- **Ricerca.** `name.toLowerCase().contains(search.trim().toLowerCase())`.
- **Gruppi.** Tutti e tre contano anche il titolo di punta nei conteggi, ma non lo mostrano nelle liste.

- [ ] **Step 1: test** (helper `fav(...)` esteso con `kind`, `unplayed`, `recursive`, `percentage`, `position`, `status`)

```dart
group('gruppi', () {
  test('film: visto, iniziato, nuovo', () => expect(
      [for (final i in [fPlayed, fStarted, fNew]) myListGroup(i, i.userData)],
      [MyListGroup.watched, MyListGroup.resume, MyListGroup.start]));
  test('serie: vista tutta, iniziata, mai iniziata, senza conteggi', () => expect(
      [for (final i in [sDone, sStarted, sNew, sNoCounts]) myListGroup(i, i.userData)],
      [MyListGroup.watched, MyListGroup.resume, MyListGroup.start, MyListGroup.start]));
  test('serie iniziata senza playedPercentage: decide recursiveItemCount', ...
      // unplayed 3, recursive 8, percentage null → resume
});
group('titolo di punta', () {
  test('il primo da continuare nell\'ordine, fuori dalle liste, dentro i conteggi', ...
      expect(v.hero!.id, 'vq'); expect(ids(v.resume), isNot(contains('vq'))); expect(v.resumeCount, 1));
  test('senza da continuare: il primo da iniziare', ...);
  test('solo visti: nessuno', ... expect(v.hero, isNull));
  test('genere e ricerca non lo cambiano', ...);
});
group('ordine', () {
  test('aggiunti: prima le date salvate, poi dateCreated', ...
      expect(ids(v.start), ['conData2', 'conData1', 'senzaRecente', 'senzaVecchio']));
  test('aggiunti al contrario: tutto rovesciato', ...);
  test('titolo A→Z, al contrario Z→A; a parità per titolo', ...);
});
test('schede: film, serie, tutti; conteggi della scheda', ...);
test('generi uniti con genreLabel, per conteggio', ... expect(v.genres.first, GenreCount('Dramma', 3)));
test('ricerca sul nome senza maiuscole', ...);
test('noResults: filtro che lascia solo il titolo di punta → false; nessuno → true', ...);
test('soglia: 24 preferiti no, 25 sì (tutte le schede)', ...);
test('removableWatched lascia le serie in corso viste tutte', ...);
test('tolto in questa sessione: sparisce; nessuno rimasto: listEmpty', ...);
```

- [ ] **Step 2:** `flutter test test/features/mylist/my_list_view_test.dart`. Atteso: FAIL (compilazione).
- [ ] **Step 3:** implementare. `myListInitialFilters` e l'uso di `ItemQuery.year`/`watched` spariscono. `my_list_screen.dart` smette di compilare: nel Task 6 viene riscritto, e fino ad allora basta adattarlo il minimo perché compili (`MyListFilters()` e la scheda `all`).
- [ ] **Step 4:** stesso test, PASS; `flutter analyze` pulito.
- [ ] **Step 5:** commit `feat(app): La mia lista divisa in gruppi`

### Task 5: Il cartellone della lista

**Files:**
- Modify: `app/lib/features/catalog/catalog_band.dart` (parametro `action`)
- Create: `app/lib/features/mylist/my_list_band.dart`
- Modify: `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/mylist/my_list_band_test.dart`, e un caso in `app/test/features/catalog/catalog_band_test.dart` (o nel test che già prova `CatalogBand`)

**Interfaces:**
- Consumes: `MyListView`, `MyListTab` (Task 4); `seriesNextEpisodeProvider(seriesId)` (`features/detail/detail_providers.dart`); `playItem(context, ref, item)`; `openItem(context, item)`; `episodeCode(item)`.
- Produces:
  - `CatalogBand(..., Widget? action)`: sotto `line`, a 16 px (10 in TV). Senza `action` il cartellone resta uguale;
  - `TextSpan myListBandLine(AppLocalizations l, MyListTab tab, MyListView view)`;
  - `class MyListBandAction extends ConsumerWidget { const MyListBandAction({super.key, required this.hero, required this.resuming, this.autofocus = false}); }`. `resuming` vale `view.resumeCount > 0`, per scegliere tra "Da dove eri rimasto:" e "Il prossimo:".

Testi nuovi (it / en):

| chiave | it | en |
|---|---|---|
| `myListBandMovies` | `{count, plural, =1{1 film} other{{count} film}}` | `{count, plural, =1{1 movie} other{{count} movies}}` |
| `myListBandSeries` | `{count, plural, =1{1 serie} other{{count} serie}}` | `{count, plural, =1{1 series} other{{count} series}}` |
| `myListToResume` | `{count} da continuare` | `{count} to continue` |
| `myListToStart` | `{count} da iniziare` | `{count} not started` |
| `myListWatchedCount` | `{count, plural, =1{1 visto} other{{count} visti}}` | `{count} watched` |
| `myListWhereYouLeft` | `Da dove eri rimasto:` | `Where you left off:` |
| `myListUpNext` | `Il prossimo:` | `Up next:` |
| `myListMinutesLeft` | `ne restano {minutes} min` | `{minutes} min left` |
| `myListLastEpisode` | `l'ultimo episodio` | `the last episode` |

Riga (spec §5):
- **Conteggio.** In grassetto crema: `catalogCount` con Tutti, `myListBandMovies` con Film, `myListBandSeries` con Serie.
- **Gruppi.** Poi ": " e i pezzi diversi da zero, separati da ", ", e il punto finale: "**8 titoli**: 1 da continuare, 4 da iniziare, 3 visti."
- **Senza pezzi** la riga è solo "**8 titoli**.".

Pulsante e frase:
- **Pulsante oro** (`FilledButton` col tema dell'app):
  - film con `playbackPositionTicks > 0`: `previewResume`;
  - altri film: `actionPlay`;
  - serie, con l'episodio arrivato: `actionResumeEpisode(code)` se è iniziato, altrimenti `actionPlayEpisode(code)`;
  - serie, finché l'episodio non c'è: `actionPlay`.
- **Clic sul pulsante.** `playItem(context, ref, hero)`. Per una serie senza episodio ancora arrivato apre la scheda (`openItem`).
- **Frase accanto** (sotto sul telefono):
  - comincia con `myListWhereYouLeft` o `myListUpNext`, poi il nome in grassetto, che si clicca e apre la scheda;
  - film iniziato: ", " + `myListMinutesLeft`, con i minuti da `runTimeTicks - playbackPositionTicks`;
  - serie: ", " + il codice dell'episodio, e ", " + `myListLastEpisode` se `unplayedItemCount == 1`.

- [ ] **Step 1: test**

```dart
testWidgets('riga: conteggio in grassetto e pezzi diversi da zero', ...
  expect(myListBandLine(l, MyListTab.all, v).toPlainText(), '8 titoli: 1 da continuare, 4 da iniziare, 3 visti.'));
testWidgets('scheda Serie: "3 serie: 1 da continuare, 2 da iniziare."', ...);
testWidgets('film iniziato: Riprendi e "ne restano 66 min"', ...);
testWidgets('serie: Riproduci finché arriva l\'episodio, poi Riprendi S1 E8', ...
  // seriesNextEpisodeProvider con un Completer; episodio con playbackPositionTicks > 0
  expect(find.text('Riproduci'), findsOneWidget); /* completa */ expect(find.text('Riprendi S1 E8'), findsOneWidget);
  expect(find.textContaining("l'ultimo episodio"), findsOneWidget));
testWidgets('il pulsante avvia playItem', ...); // come i test del pulsante della scheda
testWidgets('CatalogBand con action la mostra sotto la riga', ...);
```

- [ ] **Step 2:** `flutter gen-l10n`; `flutter test test/features/mylist/my_list_band_test.dart`. Atteso: FAIL.
- [ ] **Step 3:** implementare.
- [ ] **Step 4:** stessi test e i test di `CatalogBand`: PASS.
- [ ] **Step 5:** commit `feat(app): cartellone di La mia lista col prossimo titolo`

### Task 6: La pagina montata

**Files:**
- Rewrite: `app/lib/features/mylist/my_list_screen.dart`
- Create: `app/lib/features/mylist/my_list_groups.dart` (gruppi e card)
- Create: `app/lib/features/mylist/my_list_tools.dart`
- Modify: `app/lib/app/router.dart` (`/mylist`, ~riga 254), `app/lib/app/shell_bottom_bar.dart:69`, `app/lib/app/tv_sidebar.dart:117`
- Modify: `app/lib/features/catalog/catalog_tools.dart`: il pulsante del verso (`_reverse`) diventa `CatalogReverseButton({required bool reversed, required VoidCallback onPressed})`, usato anche da `CatalogTools`
- Modify: arb
- Rewrite: `app/test/features/mylist/my_list_screen_test.dart`; adattare `test/features/compact_screens_test.dart` e `test/ui/skeletons_test.dart` se usano la vecchia pagina

**Interfaces:**
- Consumes: Task 1–5.
- Produces:
  - `MyListScreen({super.key, this.tab = MyListTab.all})`. La rotta passa `MyListTab.parse(state.uri.queryParameters['kind'])`, con `key: const ValueKey('mylist')` e `underBar: false`, come `/movies`;
  - `void openMyList(BuildContext context, MyListTab tab)`: `/mylist`, `/mylist?kind=movies`, `/mylist?kind=series`;
  - `final myListNextUpProvider = FutureProvider.autoDispose<Map<String, JellyfinItem>>`, in `my_list_groups.dart`. È **una** `nextUp(userId, limit: 100, enableResumable: true)`, con chiave `jellyfinIdKey(seriesId)`, e guarda `libraryRevisionProvider`.

Pagina (spec §4, §6, §7, §11):
- **Struttura.** `CustomScrollView`, come `CatalogScreen._titles` ma senza testata ferma:
  - il cartellone (`OverflowBox` sotto la barra, `barGap`);
  - gli attrezzi in uno `SliverToBoxAdapter`;
  - i gruppi.
- **Cartellone.** Titolo `navMyList.toUpperCase()`. Schede `catalogAll`, `navMovies`, `navSeries`, in stile `_BandTab`: rendere pubblica `_BandTab` come `CatalogBandTab` in `catalog_screen.dart` e usarla qui. `hero:` è il titolo di punta, se no il primo dei gruppi che ha un fondale (`catalogBandHero`).
- **Margini.** `side` = 32 / 16 / 24 come nel catalogo.
- **Date.** Si legge `myListAddedProvider`; finché carica vale `{}`. Arrivata la lista: `retainOnly(ids)` solo se `items.length < 500` (shortcut: oltre il limite della richiesta non si pulisce).
- **Attrezzi** (`MyListTools`):
  - `FilterPicker<CatalogSort>` con `myListSortAdded` / `catalogSortTitle` / `catalogSortYear` / `catalogSortRating`; cambiare voce rimette `reversed: false`;
  - `CatalogReverseButton`;
  - con `showRefinements` e non in TV, sopra c'è `CatalogGenreIndex(kind: ItemKind.movie, genres: AsyncData(view.genres), total: view.tabCount, selected: filters.genre, onSelected: ...)`;
  - con `showRefinements`, fuori dal compatto e dalla TV, a destra c'è un `TextField` `myListSearch`, che filtra a ogni tasto, senza attesa.
  - Cambiare scheda azzera genere e ricerca.
- **Gruppi:**
  - titolo Inter semibold crema 17 (15 in compatto), conteggio al 50%;
  - **Da continuare:** `LandscapeCard` in un `Wrap` largo 300, che in compatto è una colonna a tutta larghezza. Il `subtitle` è:
    - film: `myListResumeFrom(at, left)`, in minuti;
    - serie, prima che arrivi il prossimo episodio: `catalogSeriesToWatch(unplayed)`;
    - serie, con l'episodio da `myListNextUpProvider`: `"$code, ${unplayed == 1 ? myListLastOne : catalogSeriesToWatch(unplayed)}"`;
    - davanti, `"$myListNewEpisode, "` se `dateLastMediaAdded` cade negli ultimi 7 giorni (`clock.now()`). Basta il testo: "in oro" della bozza non serve, `LandscapeCard` ha il sottotitolo di un colore solo.
  - **Da iniziare:** `SliverGrid` come il catalogo (`maxCrossAxisExtent: 180`, `catalogCellExtent`), con `PosterCard(catalogStyle: true)`.
  - **Visti:** chiuso all'apertura. Testata = un `InkWell`/`TvFocusable` con chevron, titolo e conteggio, che apre e chiude (`Semantics(expanded: …)`); poi le prime 6 locandine piccole (`ExcludeSemantics`, 30×45, `imageUrls`). Aperto, mostra la stessa griglia. Il pulsante "Togli i visti" arriva nel Task 7.
- **Stati:**
  - caricamento: cartellone con titolo e schede, poi `PosterGridSkeleton(shrinkWrap: true, catalogSide: side)`;
  - errore: `ErrorView`;
  - nessun risultato: `myListNoResults` + `catalogClearFilters`.
- **Lista vuota** (`listEmpty`):
  - cartellone senza schede né attrezzi;
  - riga `myListEmpty` (testo nuovo, §11);
  - action con `FilledButton` `myListGoMovies` (`openCatalog(context, ItemKind.movie)`) e `OutlinedButton` `myListGoSeries`.
- **Scheda vuota** (`tabCount == 0` e non `listEmpty`): `myListEmptyMovies` / `myListEmptySeries` e il solo pulsante della sua pagina.
- **Icona.** `LucideIcons.heart` nelle due barre.

Testi nuovi:

| chiave | it | en |
|---|---|---|
| `myListSortAdded` | `Aggiunti alla lista` | `Added to list` |
| `myListSearch` | `Cerca nella lista` | `Search your list` |
| `myListGroupResume` | `Da continuare` | `Continue watching` |
| `myListGroupStart` | `Da iniziare` | `Not started` |
| `myListGroupWatched` | `Visti` | `Watched` |
| `myListResumeFrom` | `Riprendi da {at} min, ne restano {left}` | `Resume at {at} min, {left} left` |
| `myListLastOne` | `l'ultimo` | `the last one` |
| `myListNewEpisode` | `Nuovo episodio` | `New episode` |
| `myListNoResults` | `Nessun titolo della lista con questi filtri.` | `No titles in your list match these filters.` |
| `myListEmpty` (cambia) | `Qui trovi i film e le serie che salvi con il cuore, nella scheda del titolo o nell'anteprima.` | `This is where the movies and series you save with the heart end up, from a title's page or its preview.` |
| `myListGoMovies` | `Vai ai film` | `Go to movies` |
| `myListGoSeries` | `Vai alle serie` | `Go to series` |
| `myListEmptyMovies` | `Nessun film nella lista.` | `No movies in your list.` |
| `myListEmptySeries` | `Nessuna serie nella lista.` | `No series in your list.` |

- [ ] **Step 1: test** (`my_list_screen_test.dart`, con `FakeLibraryApi`, `FakeDisplayPreferencesApi` e `pumpApp` come oggi; dati: VisionQuest serie iniziata, Parasite film nuovo, Interstellar film visto)

```dart
testWidgets('gruppi: VisionQuest nel cartellone e non in Da continuare', ...
  expect(find.text('Da continuare'), findsNothing); // l'unico iniziato è nel cartellone
  expect(find.text('Da iniziare'), findsOneWidget); expect(find.text('Visti'), findsOneWidget);
  expect(cardNames(tester), ['Parasite']); // Visti chiuso: Interstellar non c'è
testWidgets('Visti si apre e si chiude', ...);
testWidgets('scheda Serie dall\'indirizzo e dal cartellone', ... // /mylist?kind=series
testWidgets('ordina per titolo e verso', ...);
testWidgets('oltre 24 titoli: generi e ricerca; con 24 no', ...);
testWidgets('ricerca senza risultati: Azzera filtri', ...);
testWidgets('cambiare scheda azzera il genere', ...);
testWidgets('lista vuota: testo e Vai ai film / Vai alle serie', ...);
testWidgets('scheda Film vuota: "Nessun film nella lista."', ...);
testWidgets('Da continuare di una serie: "S2 E3, 5 episodi da vedere", con Nuovo episodio', ...
  // withClock; dateLastMediaAdded 3 giorni prima; un secondo titolo iniziato perché non sia il punta
testWidgets('ricaricando dopo un cambio sul server resta la lista', ...); // tenuto da oggi
testWidgets('icona della voce: il cuore', ...); // shell_bottom_bar
```

- [ ] **Step 2:** `flutter gen-l10n`; `flutter test test/features/mylist`. Atteso: FAIL.
- [ ] **Step 3:** implementare.
- [ ] **Step 4:** `flutter test test/features/mylist test/features/compact_screens_test.dart test/ui test/app test/features/catalog`; `flutter analyze`. Atteso: PASS e analisi pulita.
- [ ] **Step 5:** commit `feat(app): La mia lista con cartellone, schede e gruppi`

### Task 7: Togliere dalla lista, con Annulla

**Files:**
- Create: `app/lib/features/mylist/my_list_removal.dart`
- Modify: `app/lib/features/mylist/my_list_groups.dart`, `my_list_screen.dart`, arb
- Test: `app/test/features/mylist/my_list_removal_test.dart`

**Interfaces:**
- Consumes: `setFavorites` (Task 3), `myListAddedProvider` (Task 2), `MyListView.removableWatched` (Task 4).
- Produces:
  - `Future<void> removeFromMyList(BuildContext context, WidgetRef ref, List<JellyfinItem> items, {required String message})`:
    - prende le date di `items` da `myListAddedProvider` **prima** di togliere, e chiama `setFavorites(items, favorite: false)`;
    - mostra una `SnackBar` di 5 s con `message` e `SnackBarAction(label: actionUndo)`, come `features/home/resume_removal.dart`. `message` si calcola sui titoli tolti davvero;
    - se qualcuno fallisce, mostra `myListRemoveFailed(n)` al posto del messaggio;
    - Annulla chiama `setFavorites(tolti, favorite: true, addedAt: date)` e poi `ref.invalidate(favoritesProvider)`;
  - `class MyListRemovable extends StatefulWidget { const MyListRemovable({super.key, required this.item, required this.child, required this.imageHeight, this.onPlay}); }`:
    - avvolge una card. Il cuore pieno (`LucideIcons.heart`, tooltip `myListRemoveTooltip`) sta in alto a destra dell'immagine e si vede al passaggio del mouse, o col focus dentro la card;
    - `onPlay` (solo `LandscapeCard`) mette un pulsante play in basso a destra dell'immagine, con `playItem`. Per una serie senza prossimo episodio arrivato, `openItem` (spec §8.2);
    - niente di tutto questo con `FormFactor.touch` o in TV: lì restituisce `child` com'è.

Il pulsante "Togli i visti dalla lista" (`myListRemoveWatched`) sta nella testata di Visti, a destra, e c'è solo con `removableWatched` non vuoto.
- **Fuori dalla TV:** toglie subito, `removeFromMyList(..., message: myListRemovedWatched(n))`.
- **In TV:** prima un `AlertDialog` con `myListRemoveWatchedConfirm(n)`, i pulsanti `myListRemoveConfirm` e `myListCancel`, e l'autofocus su `myListCancel`.

Testi nuovi:

| chiave | it | en |
|---|---|---|
| `myListRemoveTooltip` | `Togli dalla lista` | `Remove from list` |
| `myListRemoved` | `Tolto dalla lista: {title}` | `Removed from your list: {title}` |
| `myListRemoveWatched` | `Togli i visti dalla lista` | `Remove watched from list` |
| `myListRemovedWatched` | `{count, plural, =1{Tolto dalla lista 1 titolo visto} other{Tolti dalla lista {count} titoli visti}}` | `{count, plural, =1{Removed 1 watched title} other{Removed {count} watched titles}}` |
| `myListRemoveFailed` | `{count, plural, =1{Non sono riuscito a togliere 1 titolo} other{Non sono riuscito a togliere {count} titoli}}` | `{count, plural, =1{Couldn't remove 1 title} other{Couldn't remove {count} titles}}` |
| `myListRemoveWatchedConfirm` | `{count, plural, =1{Togliere 1 titolo visto dalla lista?} other{Togliere {count} titoli visti dalla lista?}}` | `{count, plural, =1{Remove 1 watched title from your list?} other{Remove {count} watched titles from your list?}}` |
| `myListRemoveConfirm` | `Togli` | `Remove` |
| `myListCancel` | `Annulla` | `Cancel` |

- [ ] **Step 1: test**

```dart
testWidgets('cuore al passaggio del mouse: toglie, avviso, Annulla rimette con la data di prima', ...
  // myListAdded {'p': d0}; hover su Parasite; tap sul cuore
  expect(find.text('Tolto dalla lista: Parasite'), findsOneWidget); expect(cardNames(tester), isNot(contains('Parasite')));
  await tester.tap(find.text('Annulla')); await tester.pumpAndSettle();
  expect(cardNames(tester), contains('Parasite')); expect(prefs.myListAddedWrites.last['p'], d0);
testWidgets('Annulla dopo una ricarica: il titolo torna nella pagina', ... // Review Focus 1
  // tolto; il server non lo ha più e libraryRevision cambia; Annulla → api risponde col titolo → c'è
testWidgets('sul touch e in TV la card non ha il cuore', ...);
testWidgets('Togli i visti: tutti tranne la serie in corso, un avviso col numero', ...
  expect(api.favoriteCalls, unorderedEquals([('i', false), ('h', false)]));
  expect(find.text('Tolti dalla lista 2 titoli visti'), findsOneWidget);
testWidgets('solo serie in corso viste tutte: il gruppo c\'è, il pulsante no', ...); // Review Focus 5
testWidgets('un titolo che non si toglie torna e l\'avviso lo dice', ...);
testWidgets('in TV Togli i visti chiede conferma, focus su Annulla', ...
  // FormFactor TV come nei test TV esistenti; OK sul pulsante → dialog; Annulla → nessuna chiamata
```

- [ ] **Step 2:** `flutter gen-l10n`; `flutter test test/features/mylist/my_list_removal_test.dart`. Atteso: FAIL.
- [ ] **Step 3:** implementare.
- [ ] **Step 4:** `flutter test test/features/mylist`; `flutter analyze`. Atteso: PASS.
- [ ] **Step 5:** commit `feat(app): togliere dalla lista con Annulla, anche i visti in blocco`

### Task 8: TV e finestre strette

**Files:**
- Modify: `app/lib/features/mylist/my_list_screen.dart`, `my_list_groups.dart`, `my_list_band.dart`
- Test: `app/test/features/mylist/my_list_tv_test.dart`; un caso compatto in `my_list_screen_test.dart`

**Interfaces:**
- Consumes: Task 5–7; `tvScrollOnFocus` (`catalog_band.dart`), `TvFocusable`, `TvFocusBorder`.

TV (spec §13):
- **Focus all'apertura** sul pulsante del cartellone (`MyListBandAction(autofocus: tv)`). Senza titolo di punta il focus va sul primo controllo degli attrezzi; con la lista vuota su "Vai ai film".
- **Su** dal pulsante arriva a una scheda; **giù** porta agli attrezzi (Ordina e verso), poi ai gruppi.
- **Da continuare** è una fila orizzontale (`SingleChildScrollView`) e non va a capo. **Visti** ha due fermate: testata e "Togli i visti".
- Col focus nei gruppi la pagina scorre oltre il cartellone (`tvScrollOnFocus`, `offset: () => max(_scroll.offset, bandHeight)`); col focus sugli attrezzi o sul cartellone torna in cima.
- Sinistra dal bordo va alla barra laterale, come nel catalogo, senza codice nuovo se il giro funziona già.

Compatto (spec §12):
- il pulsante e la frase vanno su due righe;
- `FilterPicker` senza la parola "Ordina", come il compatto di `CatalogTools`;
- generi sì, ricerca no;
- Da continuare a tutta larghezza;
- griglia a 3 colonne su 390 px (`catalogCellExtent`).

- [ ] **Step 1: test**

```dart
testWidgets('TV: il focus parte da Riprendi S1 E8', ...
  // come i test TV del catalogo (FormFactor tv, androidTvProvider)
  expect(primaryFocusLabel(tester), 'Riprendi S1 E8');
testWidgets('TV: su va alle schede, giù agli attrezzi e poi a Da iniziare', ...);
testWidgets('TV: col focus nei gruppi il cartellone esce dallo schermo', ...
  expect(scrollOffset(tester), greaterThanOrEqualTo(160));
testWidgets('TV: niente generi né ricerca con 30 titoli', ...);
testWidgets('TV, lista vuota: focus su Vai ai film', ...);
testWidgets('compatto 390 px: generi sì, ricerca no, 3 colonne', ...
  // tester.view.physicalSize, non solo setSurfaceSize (vedi CLAUDE.md)
```

Per il focus usare il metodo dei test TV del catalogo (`test/features/catalog/*tv*`). Un `DropdownButton` si mette a fuoco col primo `Focus` discendente con `canRequestFocus`.

- [ ] **Step 2:** `flutter test test/features/mylist/my_list_tv_test.dart`. Atteso: FAIL.
- [ ] **Step 3:** implementare.
- [ ] **Step 4:** `flutter test test/features/mylist`; `flutter analyze`. Atteso: PASS.
- [ ] **Step 5:** commit `feat(app): La mia lista su TV e finestre strette`

### Task 9: Chiusura

**Files:**
- Modify: `docs/RELEASING.md` (checklist, dopo la riga "Film e Serie nuove")

- [ ] **Step 1:** aggiungere la riga:

```markdown
- [ ] La mia lista nuova (app 0.42.0): cartellone col prossimo titolo (VisionQuest "Riprendi S1 E8" apre il player al punto giusto), schede Tutti/Film/Serie e Indietro dalla scheda che torna alla stessa scheda; gruppi Da continuare / Da iniziare / Visti (chiuso, si apre); Ordina con "Aggiunti alla lista" (un titolo aggiunto adesso va in cima) e verso; cuore al passaggio del mouse con Annulla; "Togli i visti dalla lista" con Annulla (le serie in corso restano); lista vuota con Vai ai film / Vai alle serie; icona a cuore nella barra; TV: focus sul pulsante del cartellone, Togli i visti chiede conferma.
```

- [ ] **Step 2:** `flutter gen-l10n`, `flutter analyze`, `flutter test`. Atteso: tutto PASS. I test instabili noti stanno in CLAUDE.md: rilanciarli prima di indagare.
- [ ] **Step 3:** `flutter build windows --release --dart-define-from-file=config/wonderflix.json`. Atteso: `build\windows\x64\runner\Release\wonderflix.exe`.
- [ ] **Step 4:** commit `docs: checklist di La mia lista nuova`
