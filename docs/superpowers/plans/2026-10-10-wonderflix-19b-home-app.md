# WonderFlix — Piano 19b: Home su misura, la Home nell'app

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la Home dell'app dello Spec M:
- le righe in un ordine che combina la Home dell'admin (plugin) e quella dell'utente (`DisplayPreferences` di Jellyfin);
- ogni riga con il suo caricamento, un'unica entrata dopo al massimo 1,5 s e le righe lente che arrivano dopo;
- le cinque righe nuove: Perché hai visto X, Le mie richieste, Continua la saga, Serie in arrivo, Film in arrivo;
- le card con immagini da indirizzi esterni.

La configurazione (Impostazioni → Home, card dell'admin) e "Cosa guardo stasera?" arrivano nel 19c, con la release (app 0.13.0, plugin 1.7.0).

**Architecture:**
- **Client** in `lib/core/`: `HomeApi` (plugin: Home dell'admin e uscite) e `DisplayPreferencesApi` (Jellyfin: Home dell'utente), più due chiamate nuove di `LibraryApi`.
- **Logica pura** in `lib/features/home/`:
  - `home_layout.dart`: righe, combinazione, disponibilità;
  - `home_rows_logic.dart`: le regole delle righe nuove ed etichette delle date;
  - `home_row_content.dart`: cosa mostra ogni riga.
- **Provider** (`home_providers.dart`): la composizione (`homeLayoutProvider`), il carosello e una famiglia `homeRowProvider` con un provider per riga. Le righe esterne restano in memoria 5 minuti.
- **Interfaccia:** `HomeScreen` decide quando aprirsi e come entrano le righe; `HomeRowView` disegna una riga; `RemoteImageCard` è la card con immagine esterna.

**Tech Stack:** Flutter 3.47.5, Riverpod 3, go_router, intl, clock, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-10-wonderflix-home-su-misura-design.md` (§6, §8.1, §8.2, §8.3, §10, §11, §12.2, §12.3, §14, §15).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 10):
1. **Verifiche del §14 fatte il 2026-10-10 sul server, in sola lettura** (vedi *Note tecniche verificate*). Restano da provare nel Task 9, con l'app: il collegamento `JellyfinSeriesId` con un utente vero e la Home dell'utente letta da un account non admin. La scrittura delle `DisplayPreferences` si prova nel 19c, che ha l'editor.
2. **Regola di inserimento (§6.4 punto 1):** una riga di `A` che manca nell'ordine dell'utente va **dopo l'ultima, nell'elenco, delle righe che la precedono in `A`**; se nessuna la precede, in testa. È la regola che dà l'esempio della spec (`nextUp, resume, requests, upcomingSeries`). La frase "subito dopo la riga che la precede" darebbe `nextUp, requests, resume`, contro l'esempio.
3. **Perché hai visto X legge 50 visioni, non 10:** sul server le ultime visioni dell'admin sono sei episodi di fila della stessa serie. Con 10 risultati spesso c'è un solo titolo, e il ritorno al titolo precedente non funzionerebbe.
4. **Continua la saga ordina i film con `PremiereDate`:** `JellyfinItem` impara la data d'uscita (Jellyfin la manda sempre). Così basta una sola chiamata `itemsByIds` per tutte le saghe.
5. **Date:**
   - il giorno di un episodio è nel fuso del PC;
   - la data digitale di un film è una data di calendario: si mostra il giorno UTC, altrimenti a ovest di Greenwich risulterebbe il giorno prima.
6. **Righe arrivate dopo l'apertura:** entrano con un loro piccolo gruppo d'entrata (sale in dissolvenza, le card volano), anche quando l'entrata della sessione è già stata fatta. Con le animazioni ridotte compaiono e basta.
7. **Funzioni del plugin non ancora note all'apertura:** la composizione le aspetta al massimo 2 s (`homeFeaturesWait`) e si ricompone appena arrivano. Di solito `Info` risponde subito dopo l'accesso.
8. **La lingua delle richieste** è quella della Home (`Localizations`): fa parte della chiave di `homeRowProvider`.
9. **Carosello:** se una delle due letture (film o serie aggiunti di recente) fallisce, restano i titoli dell'altra; il carosello manca solo se falliscono tutte e due.
10. **`HomeApi.setLayout`** è già qui (il client del plugin è completo). La prova del collegamento (`Upcoming/Test`) arriva nel 19c, con la card dell'admin.
11. **Niente release:** il 19b va su `main` dopo la prova dell'utente; app 0.13.0 e plugin 1.7.0 escono alla fine del 19c.

## Global Constraints

- **Righe, id e ordine predefinito:** `resume`, `nextUp`, `requests`, `latestMovies`, `latestSeries`, `becauseYouWatched`, `continueSaga`, `upcomingSeries`, `upcomingMovies`, `myList`.
- **Home dell'admin:** `GET /WonderFlixWatchParty/Home/Layout`. `Rows` null **o assente** vuol dire mai impostata (ordine predefinito, tutte accese); un elenco vuoto vuol dire tutte spente.
- **Home dell'utente:** `DisplayPreferences` id `wonderflix-home`, client `wonderflix`, voci `homeRows` e `homeHidden` di `CustomPrefs` (id separati da virgole). Gli id sconosciuti si ignorano. Scrivendo si conserva tutto il resto dell'oggetto.
- **Disponibilità (§6.5):**
  - `requests`: funzione `requests` e `RequestsMe.hasAccount`;
  - `continueSaga`: funzione `collections`;
  - `upcomingSeries` / `upcomingMovies`: le funzioni omonime.
  - Una riga nascosta, spenta o non disponibile non fa chiamate.
- **Funzioni del plugin:** `home`, `upcomingSeries`, `upcomingMovies` in `Info`.
- **Codici d'errore delle uscite:** `NotConfigured`, `Unauthorized`, `Unreachable` (PascalCase). Un campo che manca vale null.
- **Limiti:** 20 titoli per riga, 10 saghe. Le richieste disponibili restano 30 giorni dalla creazione.
- **Caricamento:**
  - entrata dopo al massimo **1,5 s**;
  - righe esterne (`requests`, `upcomingSeries`, `upcomingMovies`) e Home dell'admin rilette al più ogni **5 minuti**;
  - righe di Jellyfin aggiornate con `libraryRevisionProvider` e `userDataRevisionProvider`.
- **Errori:** "Riprova" solo se falliscono il carosello **e** tutte le righe di Jellyfin visibili. Una riga in errore non si vede. Tutto vuoto: "Home vuota".
- **Testi (it/en, §10):** `homeMyRequests`, `homeBecauseYouWatched`, `homeContinueSaga`, `homeSagaProgress`, `homeUpcomingSeries`, `homeUpcomingMovies`, `upcomingEpisode`, `upcomingEpisodes`, `upcomingToday`, `upcomingTomorrow`, `upcomingDigital`, con i testi della tabella del §10.
- **Etichette delle date:** "S02E05 · Oggi" (anche se passata), "S01E05–E06 · Domani", "S03E01 · ven 16 ott"; "Digitale · 13 ott".
- **Clic:**
  - Le mie richieste: `openRequest`;
  - saga: pagina della saga;
  - serie in arrivo: dettaglio Jellyfin con `JellyfinSeriesId`, altrimenti pagina Seerr (`tmdbRoute(tv, TmdbId)`) con la funzione `requests`, altrimenti nessun clic;
  - film in arrivo: pagina Seerr con `requests`, altrimenti nessun clic.

## Review Focus

1. **Cambio di profilo con la Home aperta:** la Home deve rileggere la Home dell'utente nuovo, non tenere quella del vecchio. Test: Task 6 (`homeUserPrefsProvider si rilegge al cambio di utente`).
2. **`Info` del plugin non ancora arrivato all'apertura:** la Home non deve restare ferma; si compone dopo l'attesa e aggiunge le righe del plugin quando arrivano. Test: Task 6 (`funzioni non ancora note: si aspetta, poi si ricompone`).
3. **L'admin spegne tutte le righe:** restano il carosello, niente errore e niente "Riprova". Test: Task 8 (`Home dell'admin senza righe: resta il carosello`).
4. **Seerr, Sonarr o Radarr giù:** quella riga sparisce, le altre restano, niente "Riprova". Test: Task 8 (`una riga in errore non si vede, niente Riprova`).
5. **Binge di una serie, simili che contengono il titolo stesso o titoli visti:** Perché hai visto X trova comunque titoli diversi e mostra solo quelli non visti. Test: Task 5 (`becauseSources: gli episodi valgono come la serie, senza doppioni`, `becauseItems: …`). Inoltre: le `CustomPrefs` con valori nulli e voci di jellyfin-web si conservano scrivendo (Task 2, `scrivere conserva il resto dell'oggetto`).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git del repository (hash_developer), già configurata.
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `Stop-Process -Name …`, `pkill`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** PowerShell su Windows.
  - In ogni comando che usa `flutter`, `dart` o `git`, prima rinfresca il PATH (la shell dello strumento ha un PATH vecchio):
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-19b`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(app): …"`.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit** `flutter analyze` senza problemi e la suite intera, tutta verde, con **`flutter test --concurrency=4`**. Con i 16 processi predefiniti il PC si è riavviato due volte il 2026-10-10;
  - la base di partenza è di **2630** test verdi (ultimo conteggio, `main` dopo `edd0f51`): il primo task lo conferma e lo scrive nel report.
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Codice:**
  - durate, misure e limiti come costanti nominate e commentate;
  - commenti in italiano, codice in inglese;
  - icone solo `LucideIcons`, colori `WfColors`;
  - `clock.now()`, mai `DateTime.now()`.
- **Provider e test:**
  - nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`; i container dei test hanno `retry: (_, _) => null`;
  - in un provider, tutti i `ref.watch` stanno prima del primo `await`;
  - **spinner e `pumpAndSettle`:** il carosello e gli shimmer non si fermano mai: nei test della Home usa `pump()` e `pump(durata)`, non `pumpAndSettle`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-10 sul codice di `main` (`eae2cc3`) e sul server (Jellyfin 10.11.9 con il plugin 1.7.0 di prova), in sola lettura.

**Server** (chiamate con la chiave API e l'id di un admin)
- `GET /DisplayPreferences/wonderflix-home?userId=…&client=wonderflix`, mai salvate, risponde un oggetto completo:
  - chiavi `Client`, `CustomPrefs`, `Id`, `PrimaryImageHeight`, `PrimaryImageWidth`, `RememberIndexing`, `RememberSorting`, `ScrollDirection`, `ShowBackdrop`, `ShowSidebar`, `SortBy`, `SortOrder`;
  - `CustomPrefs` ha già voci di jellyfin-web, alcune **null**: `{"chromecastVersion":"stable","skipForwardLength":"30000","skipBackLength":"10000","enableNextVideoInfoOverlay":"False","tvhome":null,"dashboardTheme":null}`.
- `GET /Items?includeItemTypes=Movie,Episode&isPlayed=true&sortBy=DatePlayed&sortOrder=Descending&recursive=true`: ordina per ultima visione. Gli episodi hanno `SeriesId` e `SeriesName`. Le prime sei voci dell'admin erano tutte episodi di "Ms. Marvel" (decisione 3).
- `GET /Items?includeItemTypes=Movie&isPlayed=true&sortBy=DatePlayed&…&enableImages=false&enableUserData=false&fields=`: 288 film per l'admin. Ogni voce ha anche `PremiereDate` e `ProductionYear` senza chiederle.
- **Serie** (`includeItemTypes=Series`): 161 in tutto.
  - Una serie mai iniziata ha `UserData.PlayedPercentage` 0 (es. "Agatha All Along": 0, `UnplayedItemCount` 9 su 9).
  - Una iniziata ha la percentuale (es. "1899": 37.5).
  - Una finita ha `Played` true. Serve al 19c.
- `sortBy=Random` con `isPlayed=false` e `genres=Commedia` funziona e cambia a ogni chiamata (19c).
- `GET /WonderFlixWatchParty/Home/Layout`:
  - mai impostata risponde `{}`, cioè `Rows` manca;
  - dopo un `POST` con `["resume","bogus","resume","myList"]` risponde `{"Rows":["resume","myList"]}`.
- `GET /WonderFlixWatchParty/Upcoming/Series`:
  - risposta: `{"Items":[{"SeriesName":"American Hostage","SeasonNumber":1,"EpisodeNumber":5,"AirDateUtc":"2026-10-12T01:00:00+00:00","TmdbId":239618,…}]}`; `Error` manca quando va tutto bene;
  - "Crystal Lake" arriva come `EpisodeNumber` 1 con `LastEpisodeNumber` 8;
  - con la chiave API `JellyfinSeriesId` è sempre null; "American Hostage" e "Brothers" sono in libreria con gli stessi id TVDB e TMDB.
- `GET /WonderFlixWatchParty/Upcoming/Movies`: per esempio `{"Title":"Hope","Year":2026,"TmdbId":1058424,"DigitalRelease":"2026-10-13T00:00:00+00:00",…}`.
- `Info` del plugin: `home`, `upcomingSeries`, `upcomingMovies`, `requests`, `collections`, `account`.

**App** (`main`)
- `HomeScreen` (`lib/features/home/home_screen.dart`):
  - oggi guarda un solo `homeProvider` (`home_data.dart`, `loadHome` con cinque chiamate), che nessun altro file usa;
  - `pickFeatured` e `nextUpCutoff` restano utili;
  - l'entrata: `StaggerGroup` con chiave `home-rows`, `homeEntrancePlayedProvider`, `homeRowStagger`, card che volano con `MediaRow(animateEntrance:)`.
- `StaggerGroup` decide l'entrata una volta sola, alla prima costruzione: entrano i primi `count` `StaggerItem`, gli altri compaiono subito. `MediaRow(animateEntrance: true)` fa volare le card solo dentro uno `StaggerItem` che sta entrando.
- `LibraryApi` (`lib/core/jellyfin/library_api.dart`):
  - ha `resume`, `nextUp`, `items(ItemQuery…)`, `similar(userId, itemId, {limit})`, `itemsByIds`;
  - `cardImageParams` dà immagini e `Genres`;
  - `FakeLibraryApi` (`test/support/library_fakes.dart`) la implementa tutta: un metodo nuovo va aggiunto anche lì.
- **Funzioni del plugin:** `SocialFeatures` (`lib/features/social/social_providers.dart`) ha i campi, `==`, `hashCode` e `toString` scritti a mano. `SocialAvailability.refresh` li legge da `PluginFeatures` (`lib/core/social/social_models.dart`). Nei test: `FakeSocialAvailability(features)` con `set(...)`.
- **Richieste:**
  - `requestsApiProvider`, `requestsAvailableProvider`, `requestsMeProvider` (`RequestsMe.hasAccount`);
  - `RequestsApi.list(RequestsFilter.mine, skip:, take:, language:)`;
  - `MediaRequest` (`createdAt`, `status`, `posterPath`, `year`, `jellyfinItemId`), `requestStatusLabel(l, request)`, `RequestBadge(label:, highlighted:)`;
  - `openRequest`, `tmdbRoute(RequestMediaType, tmdbId)`, `TmdbImages.poster(path)`;
  - nei test: `FakeRequestsApi` (`lists[RequestsFilter.mine]`, `meValue` con `hasAccount` true) e `testMediaRequest(...)`.
- **Saghe:**
  - `collectionsProvider` (vuoto senza la funzione), `CollectionSummary` (`itemIds` già normalizzati con `jellyfinIdKey`, `size`, `sortName`), `openCollection`;
  - nei test: `FakeCollectionsApi` e `testCollection(...)`.
- **Immagini e card:**
  - `ImageUrls` (`lib/core/jellyfin/image_urls.dart`, `_base` = indirizzo del server), `ImageRef(url)`, `WfImage(image:, fallbackIcon:)`;
  - `LandscapeCard(item:, onTap:, heroSource:)` prende il sottotitolo da `cardSubtitle(item)`.
- **Navigazione:** `openItemById(context, id)` porta a `/item/{id}`; le rotte Seerr sono `/tmdb/{tv|movie}/{tmdbId}`.
- **Client e test HTTP:**
  - `JellyfinHttp.get/post(path, query:, body:, quietStatuses:)`, `asJsonMap`, `restartGatewayStatuses`;
  - in `json_fields.dart`: `jsonString`, `jsonInt`, `jsonDate`, `jsonStrings`, `jsonList`, `jellyfinIdKey`;
  - nei test HTTP: `FakeAdapter`, `FakeResponse` (`test/support/fake_adapter.dart`), `testServerUrl`, `testClientInfo`, `testUser` (id `u1`).
- **Date:** `inboxTimeLabel` (`lib/features/inbox/inbox_time.dart`) è il modello delle etichette con `now` passato. I test usano `lookupAppLocalizations(const Locale('it'))` e `setUpAll(() => initializeDateFormatting())`.
- **Test dei widget:**
  - `pumpApp` (`test/support/pump_app.dart`) monta in italiano, con le immagini finte e il carosello fermo; `pumpAppRouter(tester, router, overrides:)` lo fa con un router;
  - `FakeSessionController(state)` ha `set(next)`.

## File

| File | Responsabilità |
|---|---|
| `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart` (modifica) | funzioni `home`, `upcomingSeries`, `upcomingMovies` |
| `lib/core/social/home_models.dart`, `lib/core/social/home_api.dart` | Home dell'admin e uscite dal plugin |
| `lib/core/jellyfin/display_preferences_api.dart` | Home dell'utente in Jellyfin |
| `lib/core/jellyfin/item_models.dart`, `library_api.dart`, `image_urls.dart` (modifica) | `premiereDate`, `playHistory`, `playedMovies`, `backdropOf` |
| `lib/features/home/home_layout.dart` | righe, combinazione, disponibilità |
| `lib/features/home/home_row_content.dart`, `home_rows_logic.dart` | contenuti delle righe, regole delle righe nuove, etichette |
| `lib/features/home/home_providers.dart`, `home_data.dart` (modifica) | composizione, carosello, provider delle righe |
| `lib/ui/remote_image_card.dart`, `lib/ui/landscape_card.dart` (modifica) | card con immagine esterna; sottotitolo a scelta |
| `lib/features/home/home_row_view.dart`, `home_screen.dart` (riscritta) | una riga; la Home |
| `l10n/app_it.arb`, `l10n/app_en.arb` (modifica) | testi |
| `test/support/home_fakes.dart`, `test/support/library_fakes.dart` (modifica) | fake della Home e della libreria |

---

## Gruppo A — client

### Task 1: le funzioni della Home nell'app

**Files:**
- Modify: `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart`
- Test: `test/features/social/social_providers_test.dart`

**Interfaces:**
- Produces: `PluginFeatures.home`, `PluginFeatures.upcomingSeries`, `PluginFeatures.upcomingMovies`; `SocialFeatures.home`, `.upcomingSeries`, `.upcomingMovies` (bool, predefinito false), letti da `Info`.

- [ ] **Step 1: i test che falliscono**

In `test/features/social/social_providers_test.dart`, dopo il test "Info con i contatti…":

```dart
  test('Info con la Home: funzioni home e in arrivo, anche senza watch party',
      () async {
    api.install(features: const {
      PluginFeatures.home,
      PluginFeatures.upcomingSeries,
      PluginFeatures.upcomingMovies,
    });
    final c = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(
        c.read(socialAvailabilityProvider),
        const SocialFeatures(
            home: true, upcomingSeries: true, upcomingMovies: true));
  });

  test('le funzioni della Home contano nel confronto e nel testo', () {
    expect(const SocialFeatures(home: true), isNot(const SocialFeatures()));
    expect(const SocialFeatures(upcomingSeries: true),
        isNot(const SocialFeatures(upcomingMovies: true)));
    expect(const SocialFeatures(home: true).hashCode,
        const SocialFeatures(home: true).hashCode);
    expect(const SocialFeatures(upcomingMovies: true).toString(),
        contains('upcomingMovies: true'));
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/social/social_providers_test.dart`
Expected: errore di compilazione (`PluginFeatures.home`, parametro `home` inesistenti).

- [ ] **Step 3: il codice**

In `lib/core/social/social_models.dart`, in `PluginFeatures` dopo `account`:

```dart

  /// La Home dell'admin (spec M §7.2).
  static const home = 'home';

  /// "Serie in arrivo" da Sonarr (spec M §7.6): solo con Sonarr configurato.
  static const upcomingSeries = 'upcomingSeries';

  /// "Film in arrivo" da Radarr (spec M §7.6): solo con Radarr configurato.
  static const upcomingMovies = 'upcomingMovies';
```

In `lib/features/social/social_providers.dart`, in `SocialFeatures`:
- nel costruttore, dopo `this.account = false,`: `this.home = false, this.upcomingSeries = false, this.upcomingMovies = false,`;
- dopo il campo `account`:

```dart

  /// La Home dell'admin (spec M §8.1): senza, vale l'ordine predefinito.
  final bool home;

  /// "Serie in arrivo" (spec M §6.5): il plugin ha Sonarr configurato.
  final bool upcomingSeries;

  /// "Film in arrivo" (spec M §6.5): il plugin ha Radarr configurato.
  final bool upcomingMovies;
```

- in `==` aggiungi `other.home == home && other.upcomingSeries == upcomingSeries && other.upcomingMovies == upcomingMovies &&` prima di `other.known == known`;
- `hashCode`: `Object.hash(friends, parties, inbox, requests, collections, avatars, account, home, upcomingSeries, upcomingMovies, known)`;
- `toString`: aggiungi `'home: $home, upcomingSeries: $upcomingSeries, upcomingMovies: $upcomingMovies, '` prima di `'known: $known)'`;
- in `SocialAvailability.refresh`, nel `_apply(SocialFeatures(...))` dopo `account:`:

```dart
        home: info.features.contains(PluginFeatures.home),
        upcomingSeries: info.features.contains(PluginFeatures.upcomingSeries),
        upcomingMovies: info.features.contains(PluginFeatures.upcomingMovies),
```

Nel commento della classe `SocialAvailability`, nell'elenco di ciò che vale senza watch party, aggiungi "e la Home, spec M §8.1".

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS.

- [ ] **Step 5: commit**

`flutter analyze` pulito, suite intera verde (`flutter test --concurrency=4`), poi:

```powershell
git add lib test
git commit -m "feat(app): Home and upcoming features from the plugin"
```

### Task 2: i client della Home

**Files:**
- Create: `lib/core/social/home_models.dart`, `lib/core/social/home_api.dart`, `lib/core/jellyfin/display_preferences_api.dart`
- Test: `test/core/social/home_api_test.dart`, `test/core/jellyfin/display_preferences_api_test.dart`

**Interfaces:**
- Produces:
  - `enum UpcomingError { notConfigured, unauthorized, unreachable }` con `wire` e `static UpcomingError? parse(Object?)`;
  - `UpcomingPage<T>({List<T> items, UpcomingError? error})`;
  - `UpcomingEpisode` (`seriesName`, `seasonNumber`, `episodeNumber`, `lastEpisodeNumber?`, `episodeTitle?`, `airDate`, `tvdbId?`, `tmdbId?`, `posterUrl?`, `backdropUrl?`, `jellyfinSeriesId?`) e `UpcomingMovie` (`title`, `year?`, `tmdbId`, `digitalRelease`, `posterUrl?`, `backdropUrl?`), con `static … fromJson`;
  - `HomeApi(JellyfinHttp)`: `Future<List<String>?> layout()`, `Future<List<String>?> setLayout(List<String>?)`, `Future<UpcomingPage<UpcomingEpisode>> upcomingSeries()`, `Future<UpcomingPage<UpcomingMovie>> upcomingMovies()`;
  - `HomeUserPrefs({List<String> rows, List<String> hidden})` con `none` e `isEmpty`;
  - `DisplayPreferencesApi(JellyfinHttp)`: `readHome(userId)`, `writeHome(userId, prefs)`, `resetHome(userId)`, costanti `homeId`, `client`, `rowsKey`, `hiddenKey`.

- [ ] **Step 1: i test che falliscono**

`test/core/social/home_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/home_api.dart';
import 'package:wonderflix/core/social/home_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late HomeApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, <String, dynamic>{}));
    api = HomeApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('Home dell\'admin: Rows assente o null vuol dire mai impostata',
      () async {
    expect(await api.layout(), isNull);
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Home/Layout');

    adapter.handler = (_) => const FakeResponse(200, {'Rows': null});
    expect(await api.layout(), isNull);

    adapter.handler = (_) => const FakeResponse(200, {'Rows': <String>[]});
    expect(await api.layout(), isEmpty);

    adapter.handler =
        (_) => const FakeResponse(200, {'Rows': ['resume', 'myList']});
    expect(await api.layout(), ['resume', 'myList']);
  });

  test('salvare la Home dell\'admin manda le righe, anche null', () async {
    adapter.handler = (options) => FakeResponse(200, options.data);
    expect(await api.setLayout(['myList', 'resume']), ['myList', 'resume']);
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.data, {
      'Rows': ['myList', 'resume'],
    });

    expect(await api.setLayout(null), isNull);
    expect(adapter.requests.last.data, {'Rows': null});
  });

  test('serie in arrivo: voci, blocchi e voci incomplete scartate', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {
              'SeriesName': 'American Hostage',
              'SeasonNumber': 1,
              'EpisodeNumber': 5,
              'EpisodeTitle': 'Episode 5',
              'AirDateUtc': '2026-10-12T01:00:00+00:00',
              'TvdbId': 462907,
              'TmdbId': 239618,
              'PosterUrl': 'https://artworks.thetvdb.com/p.jpg',
              'BackdropUrl': 'https://artworks.thetvdb.com/f.jpg',
              'JellyfinSeriesId': 'abc123',
            },
            {
              'SeriesName': 'Crystal Lake',
              'SeasonNumber': 1,
              'EpisodeNumber': 1,
              'LastEpisodeNumber': 8,
              'AirDateUtc': '2026-10-15T09:00:00+00:00',
              'PosterUrl': '/sonarr/MediaCover/1/poster.jpg',
            },
            {'SeriesName': 'Senza data', 'SeasonNumber': 1, 'EpisodeNumber': 1},
            {'AirDateUtc': '2026-10-15T09:00:00+00:00'},
            'non un oggetto',
          ],
        });

    final page = await api.upcomingSeries();

    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Upcoming/Series');
    expect(page.error, isNull);
    expect(page.items, hasLength(2));
    final hostage = page.items.first;
    expect(hostage.seriesName, 'American Hostage');
    expect(hostage.seasonNumber, 1);
    expect(hostage.episodeNumber, 5);
    expect(hostage.lastEpisodeNumber, isNull);
    expect(hostage.episodeTitle, 'Episode 5');
    expect(hostage.airDate, DateTime.utc(2026, 10, 12, 1));
    expect(hostage.tvdbId, 462907);
    expect(hostage.tmdbId, 239618);
    expect(hostage.posterUrl, 'https://artworks.thetvdb.com/p.jpg');
    expect(hostage.backdropUrl, 'https://artworks.thetvdb.com/f.jpg');
    expect(hostage.jellyfinSeriesId, 'abc123');
    final lake = page.items.last;
    expect(lake.lastEpisodeNumber, 8);
    expect(lake.tmdbId, isNull);
    expect(lake.posterUrl, isNull, reason: 'solo indirizzi http(s) completi');
  });

  test('film in arrivo e codici d\'errore', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {
              'Title': 'Hope',
              'Year': 2026,
              'TmdbId': 1058424,
              'DigitalRelease': '2026-10-13T00:00:00+00:00',
              'PosterUrl': 'https://image.tmdb.org/t/p/original/p.jpg',
            },
            {'Title': 'Senza TMDB', 'DigitalRelease': '2026-10-13T00:00:00+00:00'},
          ],
        });
    final page = await api.upcomingMovies();
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Upcoming/Movies');
    final hope = page.items.single;
    expect(hope.title, 'Hope');
    expect(hope.year, 2026);
    expect(hope.tmdbId, 1058424);
    expect(hope.digitalRelease, DateTime.utc(2026, 10, 13));
    expect(hope.posterUrl, 'https://image.tmdb.org/t/p/original/p.jpg');
    expect(hope.backdropUrl, isNull);

    for (final (wire, error) in [
      ('NotConfigured', UpcomingError.notConfigured),
      ('Unauthorized', UpcomingError.unauthorized),
      ('Unreachable', UpcomingError.unreachable),
      ('Sconosciuto', UpcomingError.unreachable),
    ]) {
      adapter.handler =
          (_) => FakeResponse(200, {'Items': <Object>[], 'Error': wire});
      final failed = await api.upcomingMovies();
      expect(failed.error, error, reason: wire);
      expect(failed.items, isEmpty);
    }
  });

  test('risposte inattese', () async {
    adapter.handler = (_) => const FakeResponse(200, ['non un oggetto']);
    await expectLater(api.upcomingSeries(), throwsA(isA<ServerErrorException>()));
    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(api.layout(), throwsA(isA<NotFoundException>()));
  });
}
```

`test/core/jellyfin/display_preferences_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

/// Le DisplayPreferences mai salvate come le dà Jellyfin 10.11.9 (2026-10-10).
Map<String, dynamic> serverPrefs([Map<String, dynamic>? extra]) => {
      'Id': 'd0c1a2b3',
      'SortBy': 'SortName',
      'RememberIndexing': false,
      'PrimaryImageHeight': 250,
      'PrimaryImageWidth': 250,
      'CustomPrefs': {
        'chromecastVersion': 'stable',
        'tvhome': null,
        ...?extra,
      },
      'ScrollDirection': 'Horizontal',
      'ShowBackdrop': true,
      'RememberSorting': false,
      'SortOrder': 'Ascending',
      'ShowSidebar': false,
      'Client': 'wonderflix',
    };

void main() {
  late FakeAdapter adapter;
  late DisplayPreferencesApi api;

  setUp(() {
    adapter = FakeAdapter((_) => FakeResponse(200, serverPrefs()));
    api = DisplayPreferencesApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('leggere: id, utente e client; senza voci nessun ritocco', () async {
    final prefs = await api.readHome('u1');
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/DisplayPreferences/wonderflix-home');
    expect(request.queryParameters, {'userId': 'u1', 'client': 'wonderflix'});
    expect(prefs.isEmpty, isTrue);
  });

  test('leggere: ordine e nascoste, senza spazi e voci vuote', () async {
    adapter.handler = (_) => FakeResponse(
        200,
        serverPrefs(
            {'homeRows': 'myList, resume,,nextUp', 'homeHidden': 'requests'}));
    final prefs = await api.readHome('u1');
    expect(prefs.rows, ['myList', 'resume', 'nextUp']);
    expect(prefs.hidden, ['requests']);
  });

  test('scrivere conserva il resto dell\'oggetto, anche i valori nulli',
      () async {
    await api.writeHome('u1',
        const HomeUserPrefs(rows: ['resume', 'myList'], hidden: <String>[]));
    final post = adapter.requests.last;
    expect(post.method, 'POST');
    expect(post.path, '/DisplayPreferences/wonderflix-home');
    expect(post.queryParameters, {'userId': 'u1', 'client': 'wonderflix'});
    final body = post.data as Map<String, dynamic>;
    expect(body['SortBy'], 'SortName');
    expect(body['ShowSidebar'], false);
    expect(body['CustomPrefs'], {
      'chromecastVersion': 'stable',
      'tvhome': null,
      'homeRows': 'resume,myList',
      'homeHidden': '',
    });
  });

  test('ripristinare toglie solo le due voci', () async {
    adapter.handler = (options) => options.method == 'GET'
        ? FakeResponse(200,
            serverPrefs({'homeRows': 'myList', 'homeHidden': 'resume'}))
        : const FakeResponse(204);
    await api.resetHome('u1');
    final body = adapter.requests.last.data as Map<String, dynamic>;
    expect(body['CustomPrefs'], {'chromecastVersion': 'stable', 'tvhome': null});
  });

  test('un errore di Jellyfin arriva a chi chiama', () async {
    adapter.handler = (_) => const FakeResponse(401);
    await expectLater(api.readHome('u1'), throwsA(isA<ApiException>()));
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/social/home_api_test.dart test/core/jellyfin/display_preferences_api_test.dart`
Expected: errore di compilazione (file inesistenti).

- [ ] **Step 3: il codice**

`lib/core/social/home_models.dart`:

```dart
import '../jellyfin/json_fields.dart';

/// Perché il plugin non ha dato le uscite (spec M §7.4). I codici arrivano
/// in PascalCase.
enum UpcomingError {
  notConfigured('NotConfigured'),
  unauthorized('Unauthorized'),
  unreachable('Unreachable');

  const UpcomingError(this.wire);

  final String wire;

  /// `null` senza errore (Jellyfin può non scrivere il campo); un codice
  /// sconosciuto vale come irraggiungibile.
  static UpcomingError? parse(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    for (final error in values) {
      if (error.wire == raw) return error;
    }
    return unreachable;
  }
}

/// Le uscite di Sonarr o Radarr come le dà il plugin (spec M §7.3): con un
/// errore l'elenco è vuoto.
class UpcomingPage<T> {
  const UpcomingPage({this.items = const [], this.error});

  factory UpcomingPage.fromJson(Map<String, dynamic> json,
          T? Function(Map<String, dynamic> json) parse) =>
      UpcomingPage(
        items: json['Items'] is List ? jsonList(json['Items'], parse) : const [],
        error: UpcomingError.parse(json['Error']),
      );

  final List<T> items;
  final UpcomingError? error;
}

/// Un episodio in arrivo, o un blocco di episodi usciti insieme (spec M
/// §7.3): [lastEpisodeNumber] c'è solo per un blocco.
class UpcomingEpisode {
  const UpcomingEpisode({
    required this.seriesName,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.airDate,
    this.lastEpisodeNumber,
    this.episodeTitle,
    this.tvdbId,
    this.tmdbId,
    this.posterUrl,
    this.backdropUrl,
    this.jellyfinSeriesId,
  });

  /// `null` senza nome della serie, numeri o una data valida: la voce si
  /// scarta.
  static UpcomingEpisode? fromJson(Map<String, dynamic> json) {
    final name = jsonString(json, 'SeriesName');
    final season = jsonInt(json, 'SeasonNumber');
    final episode = jsonInt(json, 'EpisodeNumber');
    final airDate = jsonDate(json, 'AirDateUtc');
    if (name == null || season == null || episode == null || airDate == null) {
      return null;
    }
    return UpcomingEpisode(
      seriesName: name,
      seasonNumber: season,
      episodeNumber: episode,
      airDate: airDate,
      lastEpisodeNumber: jsonInt(json, 'LastEpisodeNumber'),
      episodeTitle: jsonString(json, 'EpisodeTitle'),
      tvdbId: jsonInt(json, 'TvdbId'),
      tmdbId: jsonInt(json, 'TmdbId'),
      posterUrl: _webAddress(json, 'PosterUrl'),
      backdropUrl: _webAddress(json, 'BackdropUrl'),
      jellyfinSeriesId: jsonString(json, 'JellyfinSeriesId'),
    );
  }

  final String seriesName;
  final int seasonNumber;
  final int episodeNumber;
  final int? lastEpisodeNumber;
  final String? episodeTitle;

  /// Uscita, in UTC.
  final DateTime airDate;
  final int? tvdbId;
  final int? tmdbId;
  final String? posterUrl;
  final String? backdropUrl;

  /// La serie di Jellyfin, solo se l'utente la vede.
  final String? jellyfinSeriesId;
}

/// Un film in arrivo (spec M §7.3).
class UpcomingMovie {
  const UpcomingMovie({
    required this.title,
    required this.tmdbId,
    required this.digitalRelease,
    this.year,
    this.posterUrl,
    this.backdropUrl,
  });

  /// `null` senza titolo, id TMDB o data d'uscita: la voce si scarta.
  static UpcomingMovie? fromJson(Map<String, dynamic> json) {
    final title = jsonString(json, 'Title');
    final tmdbId = jsonInt(json, 'TmdbId');
    final release = jsonDate(json, 'DigitalRelease');
    if (title == null || tmdbId == null || release == null) return null;
    return UpcomingMovie(
      title: title,
      tmdbId: tmdbId,
      digitalRelease: release,
      year: jsonInt(json, 'Year'),
      posterUrl: _webAddress(json, 'PosterUrl'),
      backdropUrl: _webAddress(json, 'BackdropUrl'),
    );
  }

  final String title;
  final int? year;
  final int tmdbId;

  /// Uscita digitale: una data di calendario, a mezzanotte UTC.
  final DateTime digitalRelease;
  final String? posterUrl;
  final String? backdropUrl;
}

/// Solo indirizzi http(s) completi: un'immagine non si chiede a un
/// indirizzo qualunque.
String? _webAddress(Map<String, dynamic> json, String key) {
  final value = jsonString(json, key);
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.scheme == 'https' || uri.scheme == 'http' ? value : null;
}
```

`lib/core/social/home_api.dart`:

```dart
import '../jellyfin/json_fields.dart';
import '../jellyfin/jellyfin_http.dart';
import 'home_models.dart';

/// La Home dell'admin e le uscite in arrivo del plugin (spec M §7.2, §7.3).
/// Gli errori sono `ApiException`; un corpo di forma inattesa è
/// `ServerErrorException`.
class HomeApi {
  HomeApi(this._http);

  final JellyfinHttp _http;

  static const _base = '/WonderFlixWatchParty';

  /// Jellyfin che si riavvia: nel log come info.
  static const _quiet = restartGatewayStatuses;

  /// La Home dell'admin: gli id delle righe accese, in ordine; `null` se
  /// mai impostata, anche quando `Rows` manca (Jellyfin non scrive i null).
  Future<List<String>?> layout() async => _rows(
      asJsonMap(await _http.get('$_base/Home/Layout', quietStatuses: _quiet)));

  /// Salva la Home dell'admin (solo admin); `null` torna all'ordine
  /// predefinito. Risponde con quella salvata.
  Future<List<String>?> setLayout(List<String>? rows) async => _rows(asJsonMap(
      await _http.post('$_base/Home/Layout',
          body: {'Rows': rows}, quietStatuses: _quiet)));

  Future<UpcomingPage<UpcomingEpisode>> upcomingSeries() async =>
      UpcomingPage.fromJson(
          asJsonMap(await _http.get('$_base/Upcoming/Series',
              quietStatuses: _quiet)),
          UpcomingEpisode.fromJson);

  Future<UpcomingPage<UpcomingMovie>> upcomingMovies() async =>
      UpcomingPage.fromJson(
          asJsonMap(await _http.get('$_base/Upcoming/Movies',
              quietStatuses: _quiet)),
          UpcomingMovie.fromJson);

  static List<String>? _rows(Map<String, dynamic> json) =>
      json['Rows'] is List ? jsonStrings(json['Rows']) : null;
}
```

`lib/core/jellyfin/display_preferences_api.dart`:

```dart
import 'jellyfin_http.dart';
import 'json_fields.dart';

/// La Home dell'utente (spec M §6.3): l'ordine delle righe e quelle
/// nascoste, come id (gli sconosciuti li scarta chi li usa).
class HomeUserPrefs {
  const HomeUserPrefs({this.rows = const [], this.hidden = const []});

  /// Nessun ritocco: vale la Home dell'admin.
  static const none = HomeUserPrefs();

  final List<String> rows;
  final List<String> hidden;

  bool get isEmpty => rows.isEmpty && hidden.isEmpty;
}

/// Le `DisplayPreferences` di Jellyfin che tengono la Home dell'utente
/// (spec M §6.3, §8.1): ogni utente le sue, su ogni PC. Gli errori sono
/// `ApiException`.
class DisplayPreferencesApi {
  DisplayPreferencesApi(this._http);

  final JellyfinHttp _http;

  /// Id e client nostri: le preferenze di jellyfin-web non si toccano.
  static const homeId = 'wonderflix-home';
  static const client = 'wonderflix';

  /// Le voci di `CustomPrefs`: id separati da virgole.
  static const rowsKey = 'homeRows';
  static const hiddenKey = 'homeHidden';

  static const _path = '/DisplayPreferences/$homeId';

  /// Jellyfin che si riavvia: nel log come info.
  static const _quiet = restartGatewayStatuses;

  Future<HomeUserPrefs> readHome(String userId) async {
    final custom = jsonMap((await _read(userId))['CustomPrefs']) ?? const {};
    return HomeUserPrefs(
        rows: _ids(custom[rowsKey]), hidden: _ids(custom[hiddenKey]));
  }

  /// Salva ordine e righe nascoste; il resto dell'oggetto e le altre voci di
  /// `CustomPrefs` (anche quelle di jellyfin-web, anche nulle) restano.
  Future<void> writeHome(String userId, HomeUserPrefs prefs) =>
      _update(userId, (custom) {
        custom[rowsKey] = prefs.rows.join(',');
        custom[hiddenKey] = prefs.hidden.join(',');
      });

  /// "Ripristina la Home predefinita": toglie le due voci.
  Future<void> resetHome(String userId) => _update(userId, (custom) {
        custom
          ..remove(rowsKey)
          ..remove(hiddenKey);
      });

  Future<Map<String, dynamic>> _read(String userId) async => asJsonMap(
      await _http.get(_path, query: _query(userId), quietStatuses: _quiet));

  /// Jellyfin riscrive l'oggetto intero: si rilegge, si cambia `CustomPrefs`
  /// e si rimanda tutto.
  Future<void> _update(
      String userId, void Function(Map<String, dynamic> custom) change) async {
    final prefs = Map<String, dynamic>.of(await _read(userId));
    final custom =
        Map<String, dynamic>.of(jsonMap(prefs['CustomPrefs']) ?? const {});
    change(custom);
    prefs['CustomPrefs'] = custom;
    await _http.post(_path,
        query: _query(userId), body: prefs, quietStatuses: _quiet);
  }

  static Map<String, dynamic> _query(String userId) =>
      {'userId': userId, 'client': client};

  static List<String> _ids(Object? raw) => raw is String
      ? [
          for (final id in raw.split(','))
            if (id.trim().isNotEmpty) id.trim(),
        ]
      : const [];
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Se `FakeAdapter` non espone il corpo come `Map` in `options.data`, leggi come lo registra e adegua solo le asserzioni sul corpo.

- [ ] **Step 5: commit**

`flutter analyze`, suite intera verde, poi:

```powershell
git add lib test
git commit -m "feat(app): clients for the admin Home, upcoming titles and the user Home"
```

### Task 3: la libreria per le righe nuove

**Files:**
- Modify: `lib/core/jellyfin/item_models.dart`, `lib/core/jellyfin/library_api.dart`, `lib/core/jellyfin/image_urls.dart`, `test/support/library_fakes.dart`
- Test: `test/core/jellyfin/library_api_test.dart`, `test/core/jellyfin/item_models_test.dart`, `test/core/jellyfin/image_urls_test.dart`

**Interfaces:**
- Produces:
  - `JellyfinItem.premiereDate: DateTime?`;
  - `LibraryApi.playHistory(String userId, {required int limit})`, `LibraryApi.playedMovies(String userId, {required int limit})` → `Future<List<JellyfinItem>>`;
  - `ImageUrls.backdropOf(String itemId, {int maxWidth = 640})` → `ImageRef`;
  - in `FakeLibraryApi`: `playHistoryItems`, `playHistoryCalls` (limiti), `playedMovieItems`, `playedMoviesCalls`, `similarById`, `similarCalls` (`(itemId, limit)`);
  - in `testItem`: parametro `String? premiereDate`.

- [ ] **Step 1: i test che falliscono**

In `test/core/jellyfin/library_api_test.dart` (usa `last()` e `RequestOptionsView` del file):

```dart
  test('playHistory: film ed episodi visti, dal più recente, solo i dati di base',
      () async {
    await api.playHistory('u1', limit: 50);
    expect(last().path, '/Items');
    expect(last().query, {
      'userId': 'u1',
      'includeItemTypes': 'Movie,Episode',
      'isPlayed': true,
      'sortBy': 'DatePlayed',
      'sortOrder': 'Descending',
      'recursive': true,
      'limit': 50,
      'enableImages': false,
      'enableUserData': false,
    });
  });

  test('playedMovies: solo film visti, dal più recente, senza campi in più',
      () async {
    final movies = await api.playedMovies('u1', limit: 500);
    expect(movies.map((m) => m.id), ['a', 'b']);
    expect(last().query, {
      'userId': 'u1',
      'includeItemTypes': 'Movie',
      'isPlayed': true,
      'sortBy': 'DatePlayed',
      'sortOrder': 'Descending',
      'recursive': true,
      'limit': 500,
      'enableImages': false,
      'enableUserData': false,
      'fields': '',
    });
  });
```

In `test/core/jellyfin/item_models_test.dart`:

```dart
  test('la data d\'uscita, se c\'è', () {
    final item = JellyfinItem.fromJson({
      'Id': 'm1',
      'Name': 'Matrix',
      'Type': 'Movie',
      'PremiereDate': '1999-03-31T00:00:00.0000000Z',
    });
    expect(item.premiereDate, DateTime.utc(1999, 3, 31));
    expect(
        JellyfinItem.fromJson({'Id': 'm2', 'Name': 'x', 'Type': 'Movie'})
            .premiereDate,
        isNull);
  });
```

In `test/core/jellyfin/image_urls_test.dart` (usa l'`ImageUrls` del file, o creane uno con `ImageUrls(Uri.parse('https://media.example.com'))`):

```dart
  test('backdropOf: lo sfondo di un elemento di cui si conosce solo l\'id', () {
    final urls = ImageUrls(Uri.parse('https://media.example.com'));
    expect(urls.backdropOf('s1').url,
        'https://media.example.com/Items/s1/Images/Backdrop/0?maxWidth=640&quality=90');
    expect(urls.backdropOf('s1', maxWidth: 300).url, contains('maxWidth=300'));
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/jellyfin/library_api_test.dart test/core/jellyfin/item_models_test.dart test/core/jellyfin/image_urls_test.dart`
Expected: errori di compilazione (metodi e campo inesistenti).

- [ ] **Step 3: il codice**

In `item_models.dart`, `JellyfinItem`:
- costruttore: `this.premiereDate,` dopo `this.dateCreated,`;
- `fromJson`: `premiereDate: _date(json['PremiereDate']),` dopo `dateCreated:`;
- campo, dopo `dateCreated`:

```dart

  /// Prima uscita. Jellyfin la manda sempre negli elenchi (spec M §8.3,
  /// ordine dei film di una saga).
  final DateTime? premiereDate;
```

In `library_api.dart`, dopo `itemsByIds`:

```dart
  /// Le ultime visioni dell'utente (spec M §8.3, "Perché hai visto X"): film
  /// ed episodi visti, dal più recente. Solo i dati di base: servono tipo,
  /// nome e serie.
  Future<List<JellyfinItem>> playHistory(String userId,
          {required int limit}) async =>
      _list(await _http.get('/Items', query: {
        'userId': userId,
        'includeItemTypes': 'Movie,Episode',
        'isPlayed': true,
        'sortBy': 'DatePlayed',
        'sortOrder': 'Descending',
        'recursive': true,
        'limit': limit,
        'enableImages': false,
        'enableUserData': false,
      }));

  /// I film visti dall'utente, dal più recente (spec M §8.3, "Continua la
  /// saga"): servono solo gli id, quindi niente campi in più.
  Future<List<JellyfinItem>> playedMovies(String userId,
          {required int limit}) async =>
      _list(await _http.get('/Items', query: {
        'userId': userId,
        'includeItemTypes': 'Movie',
        'isPlayed': true,
        'sortBy': 'DatePlayed',
        'sortOrder': 'Descending',
        'recursive': true,
        'limit': limit,
        'enableImages': false,
        'enableUserData': false,
        'fields': '',
      }));
```

In `image_urls.dart`, dopo `primaryWithTag`:

```dart
  /// Sfondo di un elemento di cui si conosce solo l'id (una serie in
  /// arrivo, spec M §8.3): senza tag Jellyfin dà quello attuale.
  ImageRef backdropOf(String itemId, {int maxWidth = 640}) => ImageRef(
      '$_base/Items/$itemId/Images/Backdrop/0?maxWidth=$maxWidth&quality=90');
```

In `test/support/library_fakes.dart`:
- in `FakeLibraryApi`, vicino a `similarItems`:

```dart
  /// Ultime visioni, per [playHistory].
  List<JellyfinItem> playHistoryItems = [];

  /// Il `limit` di ogni [playHistory].
  final playHistoryCalls = <int>[];

  /// Film visti, per [playedMovies].
  List<JellyfinItem> playedMovieItems = [];

  /// Il `limit` di ogni [playedMovies].
  final playedMoviesCalls = <int>[];

  /// Simili di ogni titolo; un titolo assente usa [similarItems].
  final Map<String, List<JellyfinItem>> similarById = {};

  /// Titolo e `limit` di ogni [similar].
  final similarCalls = <(String, int)>[];
```

- i metodi:

```dart
  @override
  Future<List<JellyfinItem>> playHistory(String userId, {required int limit}) {
    playHistoryCalls.add(limit);
    return _answer(() => playHistoryItems);
  }

  @override
  Future<List<JellyfinItem>> playedMovies(String userId, {required int limit}) {
    playedMoviesCalls.add(limit);
    return _answer(() => playedMovieItems);
  }
```

- `similar` diventa:

```dart
  @override
  Future<List<JellyfinItem>> similar(String userId, String itemId,
      {int limit = 12}) {
    similarCalls.add((itemId, limit));
    return _answer(() => similarById[itemId] ?? similarItems);
  }
```

- in `testItem`: parametro `String? premiereDate,` dopo `String? dateCreated,` e, nella mappa, `'PremiereDate': ?premiereDate,`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS.

- [ ] **Step 5: commit**

`flutter analyze`, suite intera verde, poi:

```powershell
git add lib test
git commit -m "feat(app): play history, played movies and release dates for the Home"
```

---

## Gruppo B — logica

### Task 4: righe e combinazione

**Files:**
- Create: `lib/features/home/home_layout.dart`
- Test: `test/features/home/home_layout_test.dart`

**Interfaces:**
- Consumes: `HomeUserPrefs` (Task 2), `SocialFeatures` (Task 1).
- Produces:
  - `enum HomeRowKind` (i dieci id, `id`, `parse(String)`, `fromJellyfin`);
  - `List<HomeRowKind> parseHomeRows(Iterable<String>)`;
  - `List<HomeRowKind> homeRowOrder({required List<HomeRowKind> admin, required List<HomeRowKind> user})`;
  - `enum HomeRowGate { available, seerrOff, noSeerrAccount, sagasOff, sonarrOff, radarrOff }` e `HomeRowGate homeRowGate(HomeRowKind, SocialFeatures, {required bool seerrAccount})`;
  - `class HomeLayout { order, hidden, visible }` e `HomeLayout composeHomeLayout({required List<String>? adminRows, required HomeUserPrefs user, required bool Function(HomeRowKind) available})`.

- [ ] **Step 1: i test che falliscono**

`test/features/home/home_layout_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/social/social_providers.dart';

void main() {
  List<String> ids(Iterable<HomeRowKind> rows) => [for (final r in rows) r.id];
  List<HomeRowKind> rows(List<String> ids) => parseHomeRows(ids);

  test('gli id delle righe e l\'ordine predefinito', () {
    expect(ids(HomeRowKind.values), [
      'resume', 'nextUp', 'requests', 'latestMovies', 'latestSeries',
      'becauseYouWatched', 'continueSaga', 'upcomingSeries', 'upcomingMovies',
      'myList',
    ]);
    expect(HomeRowKind.parse('myList'), HomeRowKind.myList);
    expect(HomeRowKind.parse('MyList'), isNull);
    expect([for (final r in HomeRowKind.values) if (!r.fromJellyfin) r], [
      HomeRowKind.requests,
      HomeRowKind.upcomingSeries,
      HomeRowKind.upcomingMovies,
    ]);
  });

  test('parseHomeRows: sconosciuti e doppioni via, ordine tenuto', () {
    expect(ids(rows(['myList', 'bogus', 'resume', 'myList'])),
        ['myList', 'resume']);
  });

  test('l\'esempio della spec (§6.4)', () {
    final layout = composeHomeLayout(
      adminRows: ['resume', 'nextUp', 'requests', 'upcomingSeries'],
      user: const HomeUserPrefs(
          rows: ['nextUp', 'resume'], hidden: ['requests']),
      available: (_) => true,
    );
    expect(ids(layout.order),
        ['nextUp', 'resume', 'requests', 'upcomingSeries']);
    expect(layout.hidden, {HomeRowKind.requests});
    expect(ids(layout.visible), ['nextUp', 'resume', 'upcomingSeries']);
  });

  test('senza Home dell\'admin: tutte, nell\'ordine predefinito', () {
    final layout = composeHomeLayout(
        adminRows: null, user: HomeUserPrefs.none, available: (_) => true);
    expect(layout.order, HomeRowKind.values);
    expect(layout.visible, HomeRowKind.values);
  });

  test('Home dell\'admin vuota: nessuna riga, qualunque cosa dica l\'utente',
      () {
    final layout = composeHomeLayout(
        adminRows: const [],
        user: const HomeUserPrefs(rows: ['resume']),
        available: (_) => true);
    expect(layout.order, isEmpty);
    expect(layout.visible, isEmpty);
  });

  test('una riga che l\'utente non ha sistemato va dopo quelle che la precedono',
      () {
    // A = resume, nextUp, requests, latestMovies; U = latestMovies, resume.
    expect(
        ids(homeRowOrder(
            admin: rows(['resume', 'nextUp', 'requests', 'latestMovies']),
            user: rows(['latestMovies', 'resume']))),
        ['latestMovies', 'resume', 'nextUp', 'requests']);
    // Nessuna riga la precede in A: in testa.
    expect(
        ids(homeRowOrder(
            admin: rows(['resume', 'nextUp', 'myList']),
            user: rows(['myList']))),
        ['resume', 'nextUp', 'myList']);
  });

  test('le righe dell\'utente che l\'admin ha spento non ci sono', () {
    expect(
        ids(homeRowOrder(
            admin: rows(['resume']), user: rows(['myList', 'resume']))),
        ['resume']);
  });

  test('righe non disponibili: nell\'ordine, ma non visibili', () {
    final layout = composeHomeLayout(
        adminRows: null,
        user: HomeUserPrefs.none,
        available: (row) => row != HomeRowKind.upcomingSeries);
    expect(layout.order, contains(HomeRowKind.upcomingSeries));
    expect(layout.visible, isNot(contains(HomeRowKind.upcomingSeries)));
  });

  test('id sconosciuti dell\'utente si ignorano', () {
    final layout = composeHomeLayout(
        adminRows: ['resume', 'myList'],
        user: const HomeUserPrefs(
            rows: ['rigaFutura', 'myList'], hidden: ['altraRiga']),
        available: (_) => true);
    expect(ids(layout.order), ['myList', 'resume']);
    expect(layout.hidden, isEmpty);
  });

  test('homeRowGate (§6.5)', () {
    const none = SocialFeatures.none;
    const all = SocialFeatures(
        requests: true,
        collections: true,
        upcomingSeries: true,
        upcomingMovies: true);
    expect(homeRowGate(HomeRowKind.resume, none, seerrAccount: false),
        HomeRowGate.available);
    expect(homeRowGate(HomeRowKind.requests, none, seerrAccount: true),
        HomeRowGate.seerrOff);
    expect(homeRowGate(HomeRowKind.requests, all, seerrAccount: false),
        HomeRowGate.noSeerrAccount);
    expect(homeRowGate(HomeRowKind.requests, all, seerrAccount: true),
        HomeRowGate.available);
    expect(homeRowGate(HomeRowKind.continueSaga, none, seerrAccount: false),
        HomeRowGate.sagasOff);
    expect(homeRowGate(HomeRowKind.upcomingSeries, none, seerrAccount: false),
        HomeRowGate.sonarrOff);
    expect(homeRowGate(HomeRowKind.upcomingMovies, none, seerrAccount: false),
        HomeRowGate.radarrOff);
    for (final row in [
      HomeRowKind.continueSaga,
      HomeRowKind.upcomingSeries,
      HomeRowKind.upcomingMovies,
    ]) {
      expect(homeRowGate(row, all, seerrAccount: false), HomeRowGate.available);
    }
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/home/home_layout_test.dart`
Expected: errore di compilazione (`home_layout.dart` inesistente).

- [ ] **Step 3: il codice**

`lib/features/home/home_layout.dart`:

```dart
import '../../core/jellyfin/display_preferences_api.dart';
import '../social/social_providers.dart';

/// Le righe della Home (spec M §6.1), nell'ordine predefinito: l'id è quello
/// salvato dal plugin e nelle `DisplayPreferences`.
enum HomeRowKind {
  resume('resume'),
  nextUp('nextUp'),
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
        requests || upcomingSeries || upcomingMovies => false,
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
```

Nota: nel test "id sconosciuti" `hidden` è vuoto perché `altraRiga` non è una riga. Una riga nascosta che l'admin ha spento resta in `hidden` ma non in `order`: è voluto, l'editor del 19c la mostrerà solo se torna accesa.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS.

- [ ] **Step 5: commit**

`flutter analyze`, suite intera verde, poi:

```powershell
git add lib test
git commit -m "feat(app): Home rows, layout merge and availability"
```

### Task 5: le righe nuove e i loro testi

**Files:**
- Create: `lib/features/home/home_row_content.dart`, `lib/features/home/home_rows_logic.dart`
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/features/home/home_rows_logic_test.dart`

**Interfaces:**
- Consumes: `LibraryApi.playHistory/playedMovies/similar/itemsByIds`, `JellyfinItem.premiereDate` (Task 3); `UpcomingEpisode`, `UpcomingMovie` (Task 2); `CollectionSummary`, `MediaRequest`.
- Produces:
  - costanti `homeRowLimit` (20), `homeSagaLimit` (10), `becauseHistoryLimit` (50), `becauseSourcesTried` (3), `becauseSimilarLimit` (30), `becauseMinimumItems` (4), `homeRequestsTake` (50), `recentAvailableRequest` (30 giorni), `playedMoviesLimit` (500);
  - `sealed class HomeRowContent` (`isEmpty`) con `ItemsRowContent(items)`, `BecauseYouWatchedContent(sourceName:, items:)`, `RequestsRowContent(requests)`, `SagasRowContent(sagas)`, `UpcomingSeriesRowContent(episodes)`, `UpcomingMoviesRowContent(movies)`; `SagaProgress(saga:, next:, watched:)` con `total`;
  - `becauseSources`, `becauseItems`, `loadBecauseYouWatched(LibraryApi, userId)`;
  - `homeRequests(List<MediaRequest>, DateTime now)`;
  - `sagasToContinue`, `nextInSaga`, `loadContinueSaga(LibraryApi, userId, List<CollectionSummary>)`;
  - `upcomingDayLabel`, `upcomingEpisodeLabel`, `upcomingMovieLabel`;
  - i testi ARB di §10 per le righe e le date.

- [ ] **Step 1: i test che falliscono**

`test/features/home/home_rows_logic_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_rows_logic.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/collections_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/requests_fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  final it = lookupAppLocalizations(const Locale('it'));
  final en = lookupAppLocalizations(const Locale('en'));

  JellyfinItem episode(String id, String seriesId, String seriesName) =>
      testItem(
          id: id,
          name: 'Episodio',
          kind: ItemKind.episode,
          seriesId: seriesId,
          seriesName: seriesName);

  group('Perché hai visto X', () {
    test('becauseSources: gli episodi valgono come la serie, senza doppioni',
        () {
      final sources = becauseSources([
        episode('e1', 's1', 'Ms. Marvel'),
        episode('e2', 's1', 'Ms. Marvel'),
        episode('e3', 'S-1', 'Ms. Marvel'),
        testItem(id: 'm1', name: 'Dune'),
        testItem(id: 'x', name: 'Senza serie', kind: ItemKind.episode),
        episode('e4', 's2', 'The Bear'),
        testItem(id: 'm2', name: 'Arrival'),
      ]);
      expect(sources, [
        (id: 's1', name: 'Ms. Marvel'),
        (id: 'm1', name: 'Dune'),
        (id: 's2', name: 'The Bear'),
      ]);
    });

    test('becauseItems: film non visti e serie non finite, senza il titolo stesso',
        () {
      final items = becauseItems([
        testItem(id: 'S1', kind: ItemKind.series),
        testItem(id: 'a', name: 'Arrival'),
        testItem(id: 'b', name: 'Già visto', played: true),
        testItem(id: 'c', name: 'Serie finita', kind: ItemKind.series, played: true),
        testItem(id: 'd', name: 'Andor', kind: ItemKind.series),
        testItem(id: 'e', name: 'Episodio', kind: ItemKind.episode),
      ], 's1');
      expect(items.map((i) => i.id), ['a', 'd']);
      expect(
          becauseItems([for (var i = 0; i < 25; i++) testItem(id: 'm$i')], 'x'),
          hasLength(homeRowLimit));
    });

    test('loadBecauseYouWatched: se il primo titolo ha pochi simili, prova il dopo',
        () async {
      final api = FakeLibraryApi()
        ..playHistoryItems = [
          episode('e1', 's1', 'Ms. Marvel'),
          testItem(id: 'm1', name: 'Dune'),
        ]
        ..similarById['s1'] = [testItem(id: 'x1'), testItem(id: 'x2')]
        ..similarById['m1'] = [
          for (final id in ['a', 'b', 'c', 'd']) testItem(id: id),
        ];

      final content = await loadBecauseYouWatched(api, 'u1');

      expect(content!.sourceName, 'Dune');
      expect(content.items.map((i) => i.id), ['a', 'b', 'c', 'd']);
      expect(api.playHistoryCalls, [becauseHistoryLimit]);
      expect(api.similarCalls,
          [('s1', becauseSimilarLimit), ('m1', becauseSimilarLimit)]);
    });

    test('loadBecauseYouWatched: nessun titolo basta, niente riga', () async {
      final api = FakeLibraryApi()
        ..playHistoryItems = [testItem(id: 'm1', name: 'Dune')]
        ..similarItems = [testItem(id: 'a')];
      expect(await loadBecauseYouWatched(api, 'u1'), isNull);
      expect(await loadBecauseYouWatched(FakeLibraryApi(), 'u1'), isNull);
    });
  });

  test('Le mie richieste: in corso prima, poi le arrivate degli ultimi 30 giorni',
      () {
    final now = DateTime(2026, 10, 10, 12);
    MediaRequest request(int id, RequestStatus status, int daysAgo) =>
        testMediaRequest(
            id: id,
            status: status,
            createdAt: now.subtract(Duration(days: daysAgo)));
    final shown = homeRequests([
      request(1, RequestStatus.available, 2),
      request(2, RequestStatus.pending, 5),
      request(3, RequestStatus.declined, 1),
      request(4, RequestStatus.downloading, 1),
      request(5, RequestStatus.available, 31),
      request(6, RequestStatus.failed, 1),
      request(7, RequestStatus.approved, 3),
      request(8, RequestStatus.partial, 9),
      request(9, RequestStatus.available, 30),
    ], now);
    expect(shown.map((r) => r.id), [4, 7, 2, 8, 1, 9]);
    expect(
        homeRequests([
          for (var i = 0; i < 30; i++) request(i, RequestStatus.pending, i),
        ], now),
        hasLength(homeRowLimit));
  });

  group('Continua la saga', () {
    test('sagasToContinue: iniziate e non finite, dalla visione più recente',
        () {
      final candidates = sagasToContinue([
        testCollection(id: 'c1', name: 'Matrix', itemIds: ['m1', 'm2', 'm3']),
        testCollection(id: 'c2', name: 'Alien', itemIds: ['a1', 'a2']),
        testCollection(id: 'c3', name: 'Finita', itemIds: ['f1']),
        testCollection(id: 'c4', name: 'Mai vista', itemIds: ['n1', 'n2']),
      ], ['A2', 'f1', 'm1', 'm2', 'a2']);
      expect([for (final c in candidates) c.saga.id], ['c2', 'c1']);
      expect(candidates.first.unwatched, ['a1']);
      expect(candidates.first.watched, 1);
      expect(candidates.last.unwatched, ['m3']);
      expect(candidates.last.watched, 2);
      expect(
          sagasToContinue([
            for (var i = 0; i < 15; i++)
              testCollection(id: 'c$i', name: 'S$i', itemIds: ['p$i', 'u$i']),
          ], [for (var i = 0; i < 15; i++) 'p$i']),
          hasLength(homeSagaLimit));
    });

    test('nextInSaga: il primo non visto in ordine di uscita', () {
      final next = nextInSaga([
        testItem(id: 'm3', name: 'Revolutions', premiereDate: '2003-11-05T00:00:00Z'),
        testItem(id: 'm2', name: 'Reloaded', premiereDate: '2003-05-15T00:00:00Z'),
        testItem(id: 'm9', name: 'Senza data', year: 2021),
        testItem(id: 'm0', name: 'Visto', premiereDate: '1990-01-01T00:00:00Z', played: true),
      ]);
      expect(next!.id, 'm2');
      expect(nextInSaga([testItem(id: 'x', played: true)]), isNull);
      expect(nextInSaga(const []), isNull);
    });

    test('loadContinueSaga: una chiamata per i titoli, saghe senza titoli saltate',
        () async {
      final api = FakeLibraryApi()
        ..playedMovieItems = [testItem(id: 'm1'), testItem(id: 'a1')]
        ..itemsById['m2'] = testItem(id: 'm2', name: 'Matrix Reloaded');
      final sagas = await loadContinueSaga(api, 'u1', [
        testCollection(id: 'c1', name: 'Matrix', itemIds: ['m1', 'm2']),
        testCollection(id: 'c2', name: 'Alien', itemIds: ['a1', 'a2']),
      ]);
      expect(api.playedMoviesCalls, [playedMoviesLimit]);
      expect(api.itemsByIdsCalls.single, unorderedEquals(['m2', 'a2']));
      expect(sagas.single.saga.id, 'c1');
      expect(sagas.single.next.name, 'Matrix Reloaded');
      expect(sagas.single.watched, 1);
      expect(sagas.single.total, 2);

      final none = FakeLibraryApi();
      expect(await loadContinueSaga(none, 'u1', const []), isEmpty);
      expect(none.playedMoviesCalls, isEmpty);
    });
  });

  group('etichette delle date', () {
    final now = DateTime(2026, 10, 10, 20, 30);

    UpcomingEpisode upcoming(DateTime at, {int? last}) => UpcomingEpisode(
        seriesName: 'The Bear',
        seasonNumber: 2,
        episodeNumber: 5,
        lastEpisodeNumber: last,
        airDate: at);

    test('oggi (anche se passata), domani, poi il giorno', () {
      expect(upcomingDayLabel(DateTime(2026, 10, 10, 2), now, it), 'Oggi');
      expect(upcomingDayLabel(DateTime(2026, 10, 9, 23), now, it), 'Oggi');
      expect(upcomingDayLabel(DateTime(2026, 10, 11, 1), now, it), 'Domani');
      expect(upcomingDayLabel(DateTime(2026, 10, 16, 4), now, it), 'ven 16 ott');
      expect(upcomingDayLabel(DateTime(2026, 10, 16, 4), now, en), 'Fri, Oct 16');
    });

    test('episodi e blocchi di episodi', () {
      expect(upcomingEpisodeLabel(upcoming(DateTime(2026, 10, 11, 9)), now, it),
          'S02E05 · Domani');
      expect(
          upcomingEpisodeLabel(
              upcoming(DateTime(2026, 10, 10, 22), last: 6), now, it),
          'S02E05–E06 · Oggi');
      expect(upcomingEpisodeLabel(upcoming(DateTime(2026, 10, 11, 9)), now, en),
          'S02E05 · Tomorrow');
    });

    test('film: la data digitale come data di calendario', () {
      final hope = UpcomingMovie(
          title: 'Hope', tmdbId: 1, digitalRelease: DateTime.utc(2026, 10, 13));
      expect(upcomingMovieLabel(hope, it), 'Digitale · 13 ott');
      expect(upcomingMovieLabel(hope, en), 'Digital · Oct 13');
    });
  });

  test('contenuti vuoti', () {
    expect(const ItemsRowContent([]).isEmpty, isTrue);
    expect(const RequestsRowContent([]).isEmpty, isTrue);
    expect(const SagasRowContent([]).isEmpty, isTrue);
    expect(const UpcomingSeriesRowContent([]).isEmpty, isTrue);
    expect(const UpcomingMoviesRowContent([]).isEmpty, isTrue);
    expect(BecauseYouWatchedContent(sourceName: 'x', items: [testItem()]).isEmpty,
        isFalse);
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/home/home_rows_logic_test.dart`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

**Testi.** In `l10n/app_it.arb`, dopo `"homeEmpty"`:

```json
  "homeMyRequests": "Le mie richieste",
  "homeBecauseYouWatched": "Perché hai visto {title}",
  "@homeBecauseYouWatched": {"placeholders": {"title": {"type": "String"}}},
  "homeContinueSaga": "Continua la saga",
  "homeSagaProgress": "{saga} · {watched} di {total} visti",
  "@homeSagaProgress": {"placeholders": {"saga": {"type": "String"}, "watched": {"type": "int"}, "total": {"type": "int"}}},
  "homeUpcomingSeries": "Serie in arrivo",
  "homeUpcomingMovies": "Film in arrivo",
  "upcomingEpisode": "S{season}E{episode} · {day}",
  "@upcomingEpisode": {"placeholders": {"season": {"type": "String"}, "episode": {"type": "String"}, "day": {"type": "String"}}},
  "upcomingEpisodes": "S{season}E{first}–E{last} · {day}",
  "@upcomingEpisodes": {"placeholders": {"season": {"type": "String"}, "first": {"type": "String"}, "last": {"type": "String"}, "day": {"type": "String"}}},
  "upcomingToday": "Oggi",
  "upcomingTomorrow": "Domani",
  "upcomingDigital": "Digitale · {day}",
  "@upcomingDigital": {"placeholders": {"day": {"type": "String"}}},
```

In `l10n/app_en.arb`, dopo `"homeEmpty"`:

```json
  "homeMyRequests": "My requests",
  "homeBecauseYouWatched": "Because you watched {title}",
  "homeContinueSaga": "Continue the saga",
  "homeSagaProgress": "{saga} · {watched} of {total} watched",
  "homeUpcomingSeries": "Upcoming episodes",
  "homeUpcomingMovies": "Upcoming movies",
  "upcomingEpisode": "S{season}E{episode} · {day}",
  "upcomingEpisodes": "S{season}E{first}–E{last} · {day}",
  "upcomingToday": "Today",
  "upcomingTomorrow": "Tomorrow",
  "upcomingDigital": "Digital · {day}",
```

Poi `flutter gen-l10n`.

`lib/features/home/home_row_content.dart`:

```dart
import '../../core/jellyfin/item_models.dart';
import '../../core/requests/requests_models.dart';
import '../../core/social/collections_models.dart';
import '../../core/social/home_models.dart';

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
```

`lib/features/home/home_rows_logic.dart`:

```dart
import 'dart:math';

import 'package:intl/intl.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/jellyfin/library_api.dart';
import '../../core/requests/requests_models.dart';
import '../../core/social/collections_models.dart';
import '../../core/social/home_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'home_row_content.dart';

/// Titoli al massimo in una riga della Home (spec M §8.3).
const homeRowLimit = 20;

/// Saghe al massimo in "Continua la saga".
const homeSagaLimit = 10;

/// Visioni lette per "Perché hai visto X": con molti episodi di fila della
/// stessa serie 10 non bastano a trovare tre titoli diversi (decisione 3 del
/// piano 19b).
const becauseHistoryLimit = 50;

/// Titoli di partenza provati, dal più recente.
const becauseSourcesTried = 3;

/// Simili chiesti a Jellyfin per ogni titolo di partenza.
const becauseSimilarLimit = 30;

/// Con meno simili di così si prova il titolo dopo.
const becauseMinimumItems = 4;

/// Richieste lette per "Le mie richieste".
const homeRequestsTake = 50;

/// Per quanto una richiesta disponibile resta nella riga, dalla creazione.
const recentAvailableRequest = Duration(days: 30);

/// Film visti letti per "Continua la saga".
const playedMoviesLimit = 500;

/// Anno dei titoli senza data d'uscita: in fondo.
const _unknownYear = 9999;

/// Un titolo di partenza di "Perché hai visto X".
typedef BecauseSource = ({String id, String name});

/// I titoli di partenza, dalle ultime visioni: un episodio vale come la sua
/// serie; senza doppioni; al massimo [becauseSourcesTried].
List<BecauseSource> becauseSources(List<JellyfinItem> history) {
  final seen = <String>{};
  final sources = <BecauseSource>[];
  for (final item in history) {
    final BecauseSource? source = switch (item.kind) {
      ItemKind.episode => switch ((item.seriesId, item.seriesName)) {
          (final String id, final String name) => (id: id, name: name),
          _ => null,
        },
      ItemKind.movie => (id: item.id, name: item.name),
      _ => null,
    };
    if (source == null || !seen.add(jellyfinIdKey(source.id))) continue;
    sources.add(source);
    if (sources.length == becauseSourcesTried) break;
  }
  return sources;
}

/// I simili da mostrare: film non visti e serie non finite, senza il titolo
/// di partenza; al massimo [homeRowLimit].
List<JellyfinItem> becauseItems(List<JellyfinItem> similar, String sourceId) {
  final source = jellyfinIdKey(sourceId);
  return [
    for (final item in similar)
      if ((item.kind == ItemKind.movie || item.kind == ItemKind.series) &&
          !item.userData.played &&
          jellyfinIdKey(item.id) != source)
        item,
  ].take(homeRowLimit).toList();
}

/// "Perché hai visto X" (spec M §8.3); `null` se nessun titolo di partenza
/// ha abbastanza simili.
Future<BecauseYouWatchedContent?> loadBecauseYouWatched(
    LibraryApi api, String userId) async {
  final history = await api.playHistory(userId, limit: becauseHistoryLimit);
  for (final source in becauseSources(history)) {
    final items = becauseItems(
        await api.similar(userId, source.id, limit: becauseSimilarLimit),
        source.id);
    if (items.length >= becauseMinimumItems) {
      return BecauseYouWatchedContent(sourceName: source.name, items: items);
    }
  }
  return null;
}

/// Le richieste ancora in corso.
const _openRequests = {
  RequestStatus.pending,
  RequestStatus.approved,
  RequestStatus.downloading,
  RequestStatus.partial,
};

/// "Le mie richieste" (spec M §8.3): prima quelle in corso, poi le
/// disponibili create negli ultimi [recentAvailableRequest]; ognuna dalla
/// più recente. Rifiutate e fallite no.
List<MediaRequest> homeRequests(List<MediaRequest> mine, DateTime now) {
  int newestFirst(MediaRequest a, MediaRequest b) =>
      b.createdAt.compareTo(a.createdAt);
  final open = [
    for (final request in mine)
      if (_openRequests.contains(request.status)) request,
  ]..sort(newestFirst);
  final arrived = [
    for (final request in mine)
      if (request.status == RequestStatus.available &&
          now.difference(request.createdAt) <= recentAvailableRequest)
        request,
  ]..sort(newestFirst);
  return [...open, ...arrived].take(homeRowLimit).toList();
}

/// Una saga da continuare, prima di leggere i suoi titoli: i non visti e
/// quanti sono visti.
typedef SagaCandidate = ({
  CollectionSummary saga,
  List<String> unwatched,
  int watched,
});

/// Le saghe con almeno un film visto e almeno un titolo non visto, contando
/// i soli titoli visibili; dalla saga col film visto più di recente
/// ([playedMovieIds] va dal più recente), a parità per nome; al massimo
/// [homeSagaLimit].
List<SagaCandidate> sagasToContinue(
    List<CollectionSummary> sagas, List<String> playedMovieIds) {
  final recency = <String, int>{};
  for (final (index, id) in playedMovieIds.indexed) {
    recency.putIfAbsent(jellyfinIdKey(id), () => index);
  }
  final found = <({SagaCandidate candidate, int recency})>[];
  for (final saga in sagas) {
    final played = [
      for (final id in saga.itemIds) ?recency[id],
    ];
    final unwatched = [
      for (final id in saga.itemIds)
        if (!recency.containsKey(id)) id,
    ];
    if (played.isEmpty || unwatched.isEmpty) continue;
    found.add((
      candidate: (saga: saga, unwatched: unwatched, watched: played.length),
      recency: played.reduce(min),
    ));
  }
  found.sort((a, b) {
    final byRecency = a.recency.compareTo(b.recency);
    return byRecency != 0
        ? byRecency
        : a.candidate.saga.sortName.compareTo(b.candidate.saga.sortName);
  });
  return [for (final f in found.take(homeSagaLimit)) f.candidate];
}

/// Il prossimo film di una saga: il primo non visto in ordine di uscita
/// (la regola della pagina della saga, spec K §8.2); `null` se nessuno.
JellyfinItem? nextInSaga(List<JellyfinItem> unwatched) {
  DateTime release(JellyfinItem item) =>
      item.premiereDate ?? DateTime.utc(item.productionYear ?? _unknownYear);
  final candidates = [
    for (final item in unwatched)
      if (!item.userData.played) item,
  ]..sort((a, b) {
      final byDate = release(a).compareTo(release(b));
      return byDate != 0 ? byDate : a.name.compareTo(b.name);
    });
  return candidates.isEmpty ? null : candidates.first;
}

/// "Continua la saga" (spec M §8.3): una lettura dei film visti e una sola
/// dei titoli non visti di tutte le saghe scelte.
Future<List<SagaProgress>> loadContinueSaga(
    LibraryApi api, String userId, List<CollectionSummary> sagas) async {
  if (sagas.isEmpty) return const [];
  final played = await api.playedMovies(userId, limit: playedMoviesLimit);
  final candidates =
      sagasToContinue(sagas, [for (final item in played) item.id]);
  if (candidates.isEmpty) return const [];
  final ids = {for (final c in candidates) ...c.unwatched}.toList();
  final byId = {
    for (final item in await api.itemsByIds(userId, ids))
      jellyfinIdKey(item.id): item,
  };
  return [
    for (final c in candidates)
      if (nextInSaga([for (final id in c.unwatched) ?byId[id]])
          case final next?)
        SagaProgress(saga: c.saga, next: next, watched: c.watched),
  ];
}

/// Il giorno di un'uscita, nel fuso del PC (spec M §8.3): "Oggi" anche se è
/// passata, "Domani", poi giorno della settimana e data.
String upcomingDayLabel(DateTime when, DateTime now, AppLocalizations l) {
  final local = when.toLocal();
  final days = _calendarDays(now.toLocal(), local);
  if (days <= 0) return l.upcomingToday;
  if (days == 1) return l.upcomingTomorrow;
  return DateFormat.MMMEd(l.localeName).format(local);
}

/// "S02E05 · Domani", "S01E05–E06 · Oggi".
String upcomingEpisodeLabel(
    UpcomingEpisode episode, DateTime now, AppLocalizations l) {
  final day = upcomingDayLabel(episode.airDate, now, l);
  final season = _twoDigits(episode.seasonNumber);
  final first = _twoDigits(episode.episodeNumber);
  final last = episode.lastEpisodeNumber;
  return last == null
      ? l.upcomingEpisode(season, first, day)
      : l.upcomingEpisodes(season, first, _twoDigits(last), day);
}

/// "Digitale · 13 ott": una data di calendario, quindi il giorno UTC e non
/// quello del fuso del PC (decisione 5 del piano 19b).
String upcomingMovieLabel(UpcomingMovie movie, AppLocalizations l) {
  final release = movie.digitalRelease.toUtc();
  return l.upcomingDigital(DateFormat.MMMd(l.localeName)
      .format(DateTime(release.year, release.month, release.day)));
}

String _twoDigits(int number) => number.toString().padLeft(2, '0');

/// Giorni di calendario tra le due date (locali), senza l'effetto dell'ora
/// legale.
int _calendarDays(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Se il formato inglese di `DateFormat.MMMEd` differisce di poco (per esempio senza virgola) nella versione di `intl` in uso, adegua l'asserzione al formato vero e scrivilo nel report.

- [ ] **Step 5: commit**

`flutter analyze`, suite intera verde, poi:

```powershell
git add lib l10n test
git commit -m "feat(app): rules and labels of the new Home rows"
```

---

## Gruppo C — Home

### Task 6: i provider della Home

**Files:**
- Create: `lib/features/home/home_providers.dart`, `test/support/home_fakes.dart`
- Test: `test/features/home/home_providers_test.dart`

`home_data.dart` (con `homeProvider`, che `HomeScreen` usa ancora) resta com'è fino al Task 8: così la suite è verde a ogni commit. I nuovi provider usano i suoi `pickFeatured` e `nextUpCutoff`.

**Interfaces:**
- Consumes: Task 1–5.
- Produces:
  - `homeApiProvider`, `displayPreferencesApiProvider`;
  - costanti `homeExternalRefresh` (5 minuti) e `homeFeaturesWait` (2 s); `keepFor(Ref, Duration)`;
  - `homeAdminRowsProvider` (`List<String>?`), `homeUserPrefsProvider` (`HomeUserPrefs`), `homeLayoutProvider` (`HomeLayout`);
  - `homeLatestMoviesProvider`, `homeLatestSeriesProvider`, `homeFeaturedProvider` (`List<JellyfinItem>`);
  - `typedef HomeRowKey = ({HomeRowKind kind, String language})` e `homeRowProvider` (`FutureProvider.autoDispose.family<HomeRowContent, HomeRowKey>`);
  - in `test/support/home_fakes.dart`: `FakeHomeApi`, `FakeDisplayPreferencesApi`, `testEpisode(...)`, `testUpcomingMovie(...)`, `homeOverrides(...)`.

- [ ] **Step 1: i fake e i test che falliscono**

`test/support/home_fakes.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/social/home_api.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import 'collections_fakes.dart';
import 'fake_session_controller.dart';
import 'library_fakes.dart';
import 'requests_fakes.dart';
import 'social_fakes.dart';
import 'test_data.dart';

/// `HomeApi` in memoria: Home dell'admin e uscite configurabili, chiamate
/// contate.
class FakeHomeApi implements HomeApi {
  List<String>? layoutRows;
  Object? layoutError;
  int layoutCalls = 0;
  final setLayoutCalls = <List<String>?>[];

  UpcomingPage<UpcomingEpisode> series = const UpcomingPage();
  UpcomingPage<UpcomingMovie> movies = const UpcomingPage();
  Object? seriesError;
  Object? moviesError;

  /// Se valorizzato, [upcomingSeries] aspetta che si completi.
  Completer<void>? seriesGate;
  int seriesCalls = 0;
  int moviesCalls = 0;

  @override
  Future<List<String>?> layout() async {
    layoutCalls++;
    final error = layoutError;
    if (error != null) throw error;
    return layoutRows;
  }

  @override
  Future<List<String>?> setLayout(List<String>? rows) async {
    setLayoutCalls.add(rows);
    layoutRows = rows;
    return rows;
  }

  @override
  Future<UpcomingPage<UpcomingEpisode>> upcomingSeries() async {
    seriesCalls++;
    final gate = seriesGate;
    if (gate != null) await gate.future;
    final error = seriesError;
    if (error != null) throw error;
    return series;
  }

  @override
  Future<UpcomingPage<UpcomingMovie>> upcomingMovies() async {
    moviesCalls++;
    final error = moviesError;
    if (error != null) throw error;
    return movies;
  }
}

/// `DisplayPreferencesApi` in memoria.
class FakeDisplayPreferencesApi implements DisplayPreferencesApi {
  HomeUserPrefs prefs = HomeUserPrefs.none;
  Object? error;
  final readUsers = <String>[];
  final written = <(String, HomeUserPrefs)>[];
  final resets = <String>[];

  @override
  Future<HomeUserPrefs> readHome(String userId) async {
    readUsers.add(userId);
    final failure = error;
    if (failure != null) throw failure;
    return prefs;
  }

  @override
  Future<void> writeHome(String userId, HomeUserPrefs prefs) async {
    written.add((userId, prefs));
    this.prefs = prefs;
  }

  @override
  Future<void> resetHome(String userId) async {
    resets.add(userId);
    prefs = HomeUserPrefs.none;
  }
}

UpcomingEpisode testEpisode({
  String seriesName = 'The Bear',
  int season = 2,
  int episode = 5,
  int? last,
  DateTime? airDate,
  int? tmdbId = 136315,
  String? jellyfinSeriesId,
  String? backdropUrl = 'https://artworks.thetvdb.com/f.jpg',
}) =>
    UpcomingEpisode(
      seriesName: seriesName,
      seasonNumber: season,
      episodeNumber: episode,
      lastEpisodeNumber: last,
      airDate: airDate ?? DateTime.utc(2026, 10, 12, 1),
      tmdbId: tmdbId,
      jellyfinSeriesId: jellyfinSeriesId,
      backdropUrl: backdropUrl,
    );

UpcomingMovie testUpcomingMovie({
  String title = 'Hope',
  int tmdbId = 1058424,
  DateTime? digitalRelease,
}) =>
    UpcomingMovie(
      title: title,
      tmdbId: tmdbId,
      year: 2026,
      digitalRelease: digitalRelease ?? DateTime.utc(2026, 10, 13),
      posterUrl: 'https://image.tmdb.org/t/p/original/p.jpg',
    );

/// I provider della Home nei test: libreria, plugin, Seerr, saghe e
/// preferenze finti; funzioni del plugin [features], oppure [availability]
/// per cambiarle durante il test.
List<Override> homeOverrides({
  required FakeLibraryApi library,
  FakeHomeApi? home,
  FakeDisplayPreferencesApi? prefs,
  SocialFeatures features = SocialFeatures.none,
  FakeSocialAvailability? availability,
  FakeRequestsApi? requests,
  FakeCollectionsApi? collections,
  FakeSessionController? session,
}) =>
    [
      libraryApiProvider.overrideWithValue(library),
      homeApiProvider.overrideWithValue(home ?? FakeHomeApi()),
      displayPreferencesApiProvider
          .overrideWithValue(prefs ?? FakeDisplayPreferencesApi()),
      socialAvailabilityProvider.overrideWith(
          () => availability ?? FakeSocialAvailability(features)),
      requestsApiProvider.overrideWithValue(requests ?? FakeRequestsApi()),
      collectionsApiProvider
          .overrideWithValue(collections ?? FakeCollectionsApi()),
      sessionControllerProvider.overrideWith(() =>
          session ?? FakeSessionController(const SessionSignedIn(testUser))),
    ];
```

(Se `Override` sta in un altro import di Riverpod 3, usa quello di `test/support/pump_app.dart`.)

`test/features/home/home_providers_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_rows_logic.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/requests_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakeHomeApi home;
  late FakeDisplayPreferencesApi prefs;
  late FakeRequestsApi requests;
  late FakeCollectionsApi collections;
  late FakeSocialAvailability availability;
  late FakeSessionController session;

  setUp(() {
    library = FakeLibraryApi();
    home = FakeHomeApi();
    prefs = FakeDisplayPreferencesApi();
    requests = FakeRequestsApi();
    collections = FakeCollectionsApi();
    availability = FakeSocialAvailability(SocialFeatures.none);
    session = FakeSessionController(const SessionSignedIn(testUser));
  });

  ProviderContainer container() => ProviderContainer.test(
        overrides: homeOverrides(
            library: library,
            home: home,
            prefs: prefs,
            availability: availability,
            requests: requests,
            collections: collections,
            session: session),
        retry: (_, _) => null,
      );

  Future<HomeLayout> layout(ProviderContainer c) {
    c.listen(homeLayoutProvider, (_, _) {});
    return c.read(homeLayoutProvider.future);
  }

  Future<HomeRowContent> row(ProviderContainer c, HomeRowKind kind) {
    final key = (kind: kind, language: 'it');
    c.listen(homeRowProvider(key), (_, _) {});
    return c.read(homeRowProvider(key).future);
  }

  test('senza plugin: righe della libreria, ordine predefinito, nessuna chiamata al plugin',
      () async {
    final c = container();
    final result = await layout(c);
    expect(result.visible, [
      HomeRowKind.resume,
      HomeRowKind.nextUp,
      HomeRowKind.latestMovies,
      HomeRowKind.latestSeries,
      HomeRowKind.becauseYouWatched,
      HomeRowKind.myList,
    ]);
    expect(home.layoutCalls, 0);
    expect(prefs.readUsers, ['u1']);
    expect(requests.calls, isEmpty);
  });

  test('con il plugin: Home dell\'admin, ritocchi dell\'utente e righe disponibili',
      () async {
    availability = FakeSocialAvailability(const SocialFeatures(
        home: true,
        requests: true,
        collections: true,
        upcomingSeries: true,
        upcomingMovies: true));
    home.layoutRows = ['upcomingSeries', 'requests', 'resume', 'continueSaga'];
    prefs.prefs = const HomeUserPrefs(rows: ['resume'], hidden: ['continueSaga']);
    final result = await layout(container());
    expect(result.visible,
        [HomeRowKind.upcomingSeries, HomeRowKind.requests, HomeRowKind.resume]);
    expect(home.layoutCalls, 1);
    expect(requests.calls, contains('me'));
  });

  test('Le mie richieste solo per chi è collegato a Seerr', () async {
    availability =
        FakeSocialAvailability(const SocialFeatures(requests: true));
    requests.meValue =
        const RequestsMe(canRequest: true, canManage: false, hasAccount: false);
    expect((await layout(container())).visible,
        isNot(contains(HomeRowKind.requests)));
  });

  test('errori di lettura: ordine predefinito e nessun ritocco', () async {
    availability = FakeSocialAvailability(const SocialFeatures(home: true));
    home.layoutError = const ServerUnreachableException();
    prefs.error = const ServerUnreachableException();
    final result = await layout(container());
    expect(result.order, HomeRowKind.values);
  });

  test('homeUserPrefsProvider si rilegge al cambio di utente', () async {
    final c = container();
    await layout(c);
    session.set(const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi')));
    await c.read(homeLayoutProvider.future);
    expect(prefs.readUsers, ['u1', 'u2']);
  });

  test('funzioni non ancora note: si aspetta, poi si ricompone', () {
    fakeAsync((async) {
      availability = FakeSocialAvailability(SocialFeatures.unknown);
      final c = container();
      HomeLayout? result;
      c.listen(homeLayoutProvider, (_, next) => result = next.value,
          fireImmediately: true);
      async.elapse(homeFeaturesWait - const Duration(milliseconds: 100));
      expect(result, isNull, reason: 'si aspettano le funzioni');
      availability.set(const SocialFeatures(upcomingSeries: true));
      async.flushMicrotasks();
      expect(result?.visible, contains(HomeRowKind.upcomingSeries));
      c.dispose();
    });
  });

  test('funzioni mai arrivate: dopo l\'attesa la Home si compone senza', () {
    fakeAsync((async) {
      availability = FakeSocialAvailability(SocialFeatures.unknown);
      final c = container();
      HomeLayout? result;
      c.listen(homeLayoutProvider, (_, next) => result = next.value,
          fireImmediately: true);
      async.elapse(homeFeaturesWait + const Duration(milliseconds: 100));
      expect(result?.visible, contains(HomeRowKind.resume));
      expect(result?.visible, isNot(contains(HomeRowKind.upcomingSeries)));
      c.dispose();
    });
  });

  test('righe della libreria: limiti e prossimi episodi dell\'ultimo anno',
      () async {
    library
      ..resumeItems = [testItem(id: 'r1')]
      ..nextUpItems = [testItem(id: 'n1', kind: ItemKind.episode)]
      ..onItems = (query, start, limit) => query.favoritesOnly
          ? pageOf([testItem(id: 'f1')])
          : pageOf([testItem(id: 'm1')]);
    final c = container();
    expect(((await row(c, HomeRowKind.resume)) as ItemsRowContent).items.single.id,
        'r1');
    expect(((await row(c, HomeRowKind.nextUp)) as ItemsRowContent).items.single.id,
        'n1');
    final cutoff = library.nextUpCutoffs.single!;
    expect(DateTime.now().difference(cutoff).inDays, inInclusiveRange(364, 365));
    expect(((await row(c, HomeRowKind.myList)) as ItemsRowContent).items.single.id,
        'f1');
    expect(
        ((await row(c, HomeRowKind.latestMovies)) as ItemsRowContent)
            .items
            .single
            .id,
        'm1');
    expect(library.itemQueries.where((q) => q.favoritesOnly).single.kinds,
        {ItemKind.movie, ItemKind.series});
  });

  test('Perché hai visto X e Continua la saga dai loro caricamenti', () async {
    availability =
        FakeSocialAvailability(const SocialFeatures(collections: true));
    library
      ..playHistoryItems = [testItem(id: 'm9', name: 'Dune')]
      ..similarById['m9'] = [
        for (final id in ['a', 'b', 'c', 'd']) testItem(id: id),
      ]
      ..playedMovieItems = [testItem(id: 'm1')]
      ..itemsById['m2'] = testItem(id: 'm2', name: 'Matrix Reloaded');
    collections.collectionsList = [
      testCollection(id: 'c1', name: 'Matrix', itemIds: ['m1', 'm2']),
    ];
    final c = container();
    final because =
        await row(c, HomeRowKind.becauseYouWatched) as BecauseYouWatchedContent;
    expect(because.sourceName, 'Dune');
    final sagas = await row(c, HomeRowKind.continueSaga) as SagasRowContent;
    expect(sagas.sagas.single.next.name, 'Matrix Reloaded');
  });

  test('Le mie richieste: filtro mine, lingua della Home, regole della riga',
      () async {
    requests.lists[RequestsFilter.mine] = [
      testMediaRequest(id: 1, status: RequestStatus.declined),
      testMediaRequest(id: 2, status: RequestStatus.pending),
    ];
    final content =
        await row(container(), HomeRowKind.requests) as RequestsRowContent;
    expect(content.requests.map((r) => r.id), [2]);
    expect(requests.calls, contains('list:mine:0:$homeRequestsTake'));
  });

  test('uscite: elenco limitato, errore del plugin come riga vuota', () async {
    home
      ..series = UpcomingPage(items: [for (var i = 0; i < 25; i++) testEpisode(episode: i + 1)])
      ..movies = const UpcomingPage(error: UpcomingError.unreachable);
    final c = container();
    expect(
        ((await row(c, HomeRowKind.upcomingSeries)) as UpcomingSeriesRowContent)
            .episodes,
        hasLength(homeRowLimit));
    expect((await row(c, HomeRowKind.upcomingMovies)).isEmpty, isTrue);
  });

  test('righe esterne: tenute 5 minuti senza ascoltatori', () {
    fakeAsync((async) {
      final c = container();
      final key = (kind: HomeRowKind.upcomingSeries, language: 'it');
      final sub = c.listen(homeRowProvider(key), (_, _) {});
      async.flushMicrotasks();
      sub.close();
      async.elapse(const Duration(minutes: 4));
      c.listen(homeRowProvider(key), (_, _) {}).close();
      async.flushMicrotasks();
      expect(home.seriesCalls, 1, reason: 'entro 5 minuti non si rilegge');
      async.elapse(homeExternalRefresh);
      c.listen(homeRowProvider(key), (_, _) {});
      async.flushMicrotasks();
      expect(home.seriesCalls, 2);
      c.dispose();
    });
  });

  test('carosello: con una lettura fallita restano i titoli dell\'altra',
      () async {
    library.onItems = (query, start, limit) {
      if (query.kinds.contains(ItemKind.series)) {
        throw const ServerUnreachableException();
      }
      return pageOf([testItem(id: 'm1')]);
    };
    final c = container();
    c.listen(homeFeaturedProvider, (_, _) {});
    expect((await c.read(homeFeaturedProvider.future)).map((i) => i.id), ['m1']);

    library.error = const ServerUnreachableException();
    c.invalidate(homeLatestMoviesProvider);
    c.invalidate(homeLatestSeriesProvider);
    await expectLater(c.read(homeFeaturedProvider.future),
        throwsA(isA<ServerUnreachableException>()));
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/home/home_providers_test.dart`
Expected: errore di compilazione (`home_providers.dart` inesistente).

- [ ] **Step 3: il codice**

`lib/features/home/home_providers.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/display_preferences_api.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../core/requests/requests_models.dart';
import '../../core/social/home_api.dart';
import '../../core/social/home_models.dart';
import '../collections/collections_providers.dart';
import '../library/library_providers.dart';
import '../requests/requests_providers.dart';
import '../social/social_providers.dart';
import 'home_data.dart';
import 'home_layout.dart';
import 'home_row_content.dart';
import 'home_rows_logic.dart';

final _log = Logger('home');

final homeApiProvider =
    Provider<HomeApi>((ref) => HomeApi(ref.watch(jellyfinHttpProvider)));

final displayPreferencesApiProvider = Provider<DisplayPreferencesApi>(
    (ref) => DisplayPreferencesApi(ref.watch(jellyfinHttpProvider)));

/// Quanto restano in memoria, senza nessuno che le guardi, le righe che non
/// vengono da Jellyfin e la Home dell'admin (spec M §8.2 punto 5): tornando
/// alla Home entro questo tempo non si rileggono.
const homeExternalRefresh = Duration(minutes: 5);

/// Quanto la composizione aspetta le funzioni del plugin, se all'apertura non
/// sono ancora note (decisione 7 del piano 19b).
const homeFeaturesWait = Duration(seconds: 2);

/// Tiene il risultato del provider per [duration] anche senza ascoltatori.
void keepFor(Ref ref, Duration duration) {
  final link = ref.keepAlive();
  final timer = Timer(duration, link.close);
  ref.onDispose(timer.cancel);
}

/// La Home dell'admin (spec M §6.2): solo con la funzione `home`. Senza, o se
/// la lettura fallisce, `null` (vale l'ordine predefinito).
final homeAdminRowsProvider =
    FutureProvider.autoDispose<List<String>?>((ref) async {
  if (!ref.watch(socialAvailabilityProvider.select((f) => f.home))) {
    return null;
  }
  try {
    final rows = await ref.watch(homeApiProvider).layout();
    keepFor(ref, homeExternalRefresh);
    return rows;
  } on Object catch (error) {
    _log.info('Home dell\'admin non letta: ${error.runtimeType}');
    return null;
  }
});

/// La Home dell'utente (spec M §6.3); se non si legge, nessun ritocco. Si
/// rilegge al cambio di utente (profilo).
final homeUserPrefsProvider =
    FutureProvider.autoDispose<HomeUserPrefs>((ref) async {
  try {
    final userId = ref.watch(currentUserIdProvider);
    return await ref.watch(displayPreferencesApiProvider).readHome(userId);
  } on Object catch (error) {
    _log.info('Home dell\'utente non letta: ${error.runtimeType}');
    return HomeUserPrefs.none;
  }
});

/// La Home combinata e le righe da mostrare (spec M §6.4, §6.5, §8.2 punto
/// 1). Si ricompone quando cambiano le funzioni del plugin.
final homeLayoutProvider = FutureProvider.autoDispose<HomeLayout>((ref) async {
  final features = ref.watch(socialAvailabilityProvider);
  final adminRows = ref.watch(homeAdminRowsProvider.future);
  final userPrefs = ref.watch(homeUserPrefsProvider.future);
  // Un gestore subito: un errore di Seerr non resta senza nessuno che lo
  // raccolga mentre si aspetta il resto.
  final Future<bool> seerrAccount = features.requests
      ? ref.watch(requestsMeProvider.future).then((me) => me.hasAccount,
          onError: (Object error) {
          _log.info('Seerr non letto: ${error.runtimeType}');
          return false;
        })
      : Future.value(false);
  if (!features.known) await Future<void>.delayed(homeFeaturesWait);
  final hasSeerrAccount = await seerrAccount;
  return composeHomeLayout(
    adminRows: await adminRows,
    user: await userPrefs,
    available: (row) =>
        homeRowGate(row, features, seerrAccount: hasSeerrAccount) ==
        HomeRowGate.available,
  );
});

Future<List<JellyfinItem>> _latest(Ref ref, ItemKind kind) {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  final api = ref.watch(libraryApiProvider);
  final userId = ref.watch(currentUserIdProvider);
  return api
      .items(ItemQuery(kinds: {kind}, sort: CatalogSort.dateAdded),
          userId: userId, startIndex: 0, limit: homeRowLimit)
      .then((page) => page.items);
}

final homeLatestMoviesProvider = FutureProvider.autoDispose<List<JellyfinItem>>(
    (ref) => _latest(ref, ItemKind.movie));

final homeLatestSeriesProvider = FutureProvider.autoDispose<List<JellyfinItem>>(
    (ref) => _latest(ref, ItemKind.series));

/// Il carosello (spec M §6.1): i titoli aggiunti di recente, anche se
/// l'utente nasconde quelle righe. Con una lettura fallita restano i titoli
/// dell'altra; con tutte e due, l'errore (decisione 9 del piano 19b).
final homeFeaturedProvider =
    FutureProvider.autoDispose<List<JellyfinItem>>((ref) async {
  Object? failure;
  Future<List<JellyfinItem>?> guarded(Future<List<JellyfinItem>> future) =>
      future.then<List<JellyfinItem>?>((items) => items,
          onError: (Object error) {
        failure = error;
        return null;
      });
  final movies = guarded(ref.watch(homeLatestMoviesProvider.future));
  final series = guarded(ref.watch(homeLatestSeriesProvider.future));
  final movieItems = await movies;
  final seriesItems = await series;
  if (movieItems == null && seriesItems == null) throw failure!;
  return pickFeatured(movieItems ?? const [], seriesItems ?? const []);
});

/// Una riga della Home: il tipo e la lingua delle richieste (decisione 8
/// del piano 19b).
typedef HomeRowKey = ({HomeRowKind kind, String language});

/// Il contenuto di una riga (spec M §8.3). Un provider per riga: le righe
/// nascoste o non disponibili non sono guardate, quindi non chiamano.
final homeRowProvider = FutureProvider.autoDispose
    .family<HomeRowContent, HomeRowKey>((ref, key) async {
  switch (key.kind) {
    case HomeRowKind.latestMovies:
      return ItemsRowContent(await ref.watch(homeLatestMoviesProvider.future));
    case HomeRowKind.latestSeries:
      return ItemsRowContent(await ref.watch(homeLatestSeriesProvider.future));
    case HomeRowKind.requests:
      final api = ref.watch(requestsApiProvider);
      final page = await api.list(RequestsFilter.mine,
          skip: 0, take: homeRequestsTake, language: key.language);
      keepFor(ref, homeExternalRefresh);
      return RequestsRowContent(homeRequests(page.items, clock.now()));
    case HomeRowKind.upcomingSeries:
      final page = await ref.watch(homeApiProvider).upcomingSeries();
      keepFor(ref, homeExternalRefresh);
      _logUpcoming('serie', page.error);
      return UpcomingSeriesRowContent(
          page.items.take(homeRowLimit).toList());
    case HomeRowKind.upcomingMovies:
      final page = await ref.watch(homeApiProvider).upcomingMovies();
      keepFor(ref, homeExternalRefresh);
      _logUpcoming('film', page.error);
      return UpcomingMoviesRowContent(page.items.take(homeRowLimit).toList());
    case HomeRowKind.resume ||
          HomeRowKind.nextUp ||
          HomeRowKind.myList ||
          HomeRowKind.becauseYouWatched ||
          HomeRowKind.continueSaga:
      return _libraryRow(ref, key.kind);
  }
});

/// Le righe di Jellyfin: si rileggono quando cambiano la libreria o i dati
/// dell'utente (spec M §8.2 punto 5).
Future<HomeRowContent> _libraryRow(Ref ref, HomeRowKind kind) async {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  final api = ref.watch(libraryApiProvider);
  final userId = ref.watch(currentUserIdProvider);
  switch (kind) {
    case HomeRowKind.resume:
      return ItemsRowContent(await api.resume(userId, limit: homeRowLimit));
    case HomeRowKind.nextUp:
      return ItemsRowContent(await api.nextUp(userId,
          limit: homeRowLimit, dateCutoff: nextUpCutoff(clock.now())));
    case HomeRowKind.myList:
      final page = await api.items(
          const ItemQuery(
              kinds: {ItemKind.movie, ItemKind.series},
              sort: CatalogSort.dateAdded,
              favoritesOnly: true),
          userId: userId,
          startIndex: 0,
          limit: homeRowLimit);
      return ItemsRowContent(page.items);
    case HomeRowKind.becauseYouWatched:
      return await loadBecauseYouWatched(api, userId) ??
          const ItemsRowContent([]);
    case HomeRowKind.continueSaga:
      final sagas = ref.watch(collectionsProvider.future);
      return SagasRowContent(await loadContinueSaga(api, userId, await sagas));
    case HomeRowKind.latestMovies ||
          HomeRowKind.latestSeries ||
          HomeRowKind.requests ||
          HomeRowKind.upcomingSeries ||
          HomeRowKind.upcomingMovies:
      throw StateError('non è una riga della libreria: $kind');
  }
}

void _logUpcoming(String what, UpcomingError? error) {
  if (error != null) _log.info('$what in arrivo non disponibili: ${error.wire}');
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/home/home_providers_test.dart`
Expected: PASS. Se un test con `fakeAsync` non vede la ricomposizione dopo `availability.set(...)`, aggiungi un `async.elapse(Duration.zero)` dopo `flushMicrotasks()` (Riverpod può ricostruire nel giro dopo).

- [ ] **Step 5: commit**

`flutter analyze`, suite intera verde, poi:

```powershell
git add lib test
git commit -m "feat(app): Home layout, carousel and per-row providers"
```

### Task 7: le card con immagini esterne

**Files:**
- Create: `lib/ui/remote_image_card.dart`
- Modify: `lib/ui/landscape_card.dart`
- Test: `test/ui/remote_image_card_test.dart`, `test/ui/cards_test.dart`

**Interfaces:**
- Produces:
  - `enum RemoteCardShape { poster, landscape }` con `aspectRatio` e `width` (160 e 300);
  - `RemoteImageCard({required RemoteCardShape shape, required ImageRef? image, required String title, String? subtitle, Widget? badge, VoidCallback? onTap})`;
  - `LandscapeCard.subtitle` (`String?`, al posto di `cardSubtitle(item)`).

- [ ] **Step 1: i test che falliscono**

`test/ui/remote_image_card_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/ui/remote_image_card.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('locandina: immagine, titolo, sottotitolo, etichetta e clic',
      (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Center(
        child: RemoteImageCard(
          shape: RemoteCardShape.poster,
          image: const ImageRef('https://image.tmdb.org/t/p/w342/p.jpg'),
          title: 'Hope',
          subtitle: 'Digitale · 13 ott',
          badge: const Text('In attesa'),
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.text('Hope'), findsOneWidget);
    expect(find.text('Digitale · 13 ott'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);
    expect(tester.widget<WfImage>(find.byType(WfImage)).image?.url,
        'https://image.tmdb.org/t/p/w342/p.jpg');
    expect(tester.getSize(find.byType(RemoteImageCard)).width,
        RemoteCardShape.poster.width);
    await tester.tap(find.text('Hope'));
    expect(taps, 1);
  });

  testWidgets('senza clic: niente cursore a mano', (tester) async {
    await pumpApp(
      tester,
      const Center(
        child: RemoteImageCard(
            shape: RemoteCardShape.landscape, image: null, title: 'Andor'),
      ),
    );
    expect(tester.getSize(find.byType(RemoteImageCard)).width,
        RemoteCardShape.landscape.width);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Andor')));
    addTearDown(gesture.removePointer);
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        isNot(SystemMouseCursors.click));
  });
}
```

In `test/ui/cards_test.dart`, dopo "LandscapeCard di un episodio":

```dart
  testWidgets('LandscapeCard: sottotitolo a scelta', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: LandscapeCard(
            item: testItem(), subtitle: 'Matrix · 1 di 3 visti', onTap: () {}),
      ),
      overrides: [signedIn],
    );
    expect(find.text('Matrix · 1 di 3 visti'), findsOneWidget);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/ui/remote_image_card_test.dart test/ui/cards_test.dart`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

`lib/ui/remote_image_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../app/motion.dart';
import '../app/theme.dart';
import '../core/jellyfin/image_urls.dart';
import 'wf_image.dart';

/// Forma di una [RemoteImageCard], uguale alle card della libreria.
enum RemoteCardShape {
  /// Locandina 2:3, larga come le `PosterCard` della Home.
  poster(2 / 3, 160),

  /// Card 16:9, larga come le `LandscapeCard`.
  landscape(16 / 9, 300);

  const RemoteCardShape(this.aspectRatio, this.width);

  final double aspectRatio;
  final double width;
}

/// Card di un titolo con l'immagine da un indirizzo qualunque (TMDB, TVDB:
/// spec M §8.3), nello stile delle card della libreria: titolo, sottotitolo
/// ed etichetta in alto a sinistra, facoltativi. Senza [onTap] non si
/// clicca, e non cambia aspetto al passaggio del mouse.
class RemoteImageCard extends StatefulWidget {
  const RemoteImageCard({
    super.key,
    required this.shape,
    required this.image,
    required this.title,
    this.subtitle,
    this.badge,
    this.onTap,
  });

  final RemoteCardShape shape;
  final ImageRef? image;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final VoidCallback? onTap;

  @override
  State<RemoteImageCard> createState() => _RemoteImageCardState();
}

class _RemoteImageCardState extends State<RemoteImageCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final subtitle = widget.subtitle;
    final badge = widget.badge;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: widget.shape.aspectRatio,
          child: AnimatedContainer(
            duration: WfMotion.fast,
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
                  WfImage(image: widget.image),
                  if (badge != null) Positioned(top: 6, left: 6, child: badge),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        if (subtitle != null)
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
      ],
    );
    return SizedBox(
      width: widget.shape.width,
      child: onTap == null
          ? content
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(onTap: onTap, child: content),
            ),
    );
  }
}
```

In `lib/ui/landscape_card.dart`:
- nel costruttore `this.subtitle,` dopo `this.heroSource,`;
- campo, dopo `heroSource`:

```dart

  /// Al posto di quello della libreria (`cardSubtitle`): per esempio il
  /// punto di una saga (spec M §8.3).
  final String? subtitle;
```

- in `build`: `final subtitle = widget.subtitle ?? cardSubtitle(item);`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Se `debugDeviceActiveCursor` non è disponibile, verifica l'assenza di `MouseRegion` con cursore `click` dentro la card (`find.descendant` su `MouseRegion` e il suo `cursor`).

- [ ] **Step 5: commit**

`flutter analyze`, suite intera verde, poi:

```powershell
git add lib test
git commit -m "feat(app): cards with external images and a custom landscape subtitle"
```

### Task 8: la Home

**Files:**
- Create: `lib/features/home/home_row_view.dart`
- Modify: `lib/features/home/home_screen.dart` (riscritta), `lib/features/home/home_data.dart` (togli `HomeData`, `loadHome` e `homeProvider`; restano `nextUpCutoff` e `pickFeatured`)
- Test: `test/features/home/home_screen_test.dart` (riscritto), `test/features/home/home_entrance_test.dart`, `test/features/home/home_data_test.dart`, `test/features/home/home_row_view_test.dart` (nuovo)

**Interfaces:**
- Consumes: Task 4–7.
- Produces: `homeRevealWait` (1,5 s), `HomeScreen` (stesso nome e chiavi di oggi: `home-rows`), `HomeRowView({kind, content, animateEntrance})`.

- [ ] **Step 1: i test che falliscono**

`test/features/home/home_screen_test.dart` (sostituisce il file):

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/home/hero_carousel.dart';
import 'package:wonderflix/features/home/home_screen.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/landscape_card.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/states.dart';

import '../../support/collections_fakes.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  late FakeLibraryApi library;
  late FakeHomeApi home;
  late FakeDisplayPreferencesApi prefs;
  late FakeRequestsApi requests;
  late FakeCollectionsApi collections;

  setUp(() {
    library = FakeLibraryApi();
    home = FakeHomeApi();
    prefs = FakeDisplayPreferencesApi();
    requests = FakeRequestsApi();
    collections = FakeCollectionsApi();
  });

  /// Le risposte finte arrivano in pochi fotogrammi: composizione, poi
  /// righe.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> pumpHome(WidgetTester tester,
      {SocialFeatures features = SocialFeatures.none,
      double height = 1600}) async {
    await pumpApp(tester, const HomeScreen(),
        surfaceSize: Size(1440, height),
        overrides: homeOverrides(
            library: library,
            home: home,
            prefs: prefs,
            features: features,
            requests: requests,
            collections: collections));
    await settle(tester);
  }

  void someRows() => library
    ..resumeItems = [testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)]
    ..onItems = (query, start, limit) {
      if (query.favoritesOnly) return pageOf([testItem(id: 'f1', name: 'Interstellar')]);
      return query.kinds.contains(ItemKind.series)
          ? pageOf([testItem(id: 's1', name: 'The Bear', kind: ItemKind.series)])
          : pageOf([testItem(id: 'm1', name: 'Dune')]);
    };

  testWidgets('mostra le righe con contenuti', (tester) async {
    someRows();
    await pumpHome(tester);
    expect(find.text('Continua a guardare'), findsOneWidget);
    expect(find.text('Film aggiunti di recente'), findsOneWidget);
    expect(find.text('Serie aggiunte di recente'), findsOneWidget);
    expect(find.text('La mia lista'), findsOneWidget);
    expect(find.text('Oppenheimer'), findsWidgets);
    expect(find.text('Prossimi episodi'), findsNothing, reason: 'riga vuota nascosta');
  });

  testWidgets('lo scheletro sta in una finestra stretta', (tester) async {
    // I preferiti non rispondono: la Home resta in caricamento.
    library.favoritesGate = Completer<void>();
    await pumpApp(tester, const HomeScreen(),
        surfaceSize: const Size(1024, 700),
        overrides: homeOverrides(library: library, home: home, prefs: prefs));
    await settle(tester);
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('senza carosello la prima riga inizia sotto la barra',
      (tester) async {
    library.resumeItems = [
      testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)
    ];
    await pumpHome(tester, height: 900);
    expect(tester.getTopLeft(find.text('Continua a guardare')).dy,
        greaterThanOrEqualTo(shellBarHeight));
  });

  testWidgets('libreria vuota', (tester) async {
    await pumpHome(tester);
    expect(find.text("Qui non c'è ancora niente."), findsOneWidget);
  });

  testWidgets('errore con riprova', (tester) async {
    library.error = const ServerUnreachableException();
    await pumpHome(tester);
    expect(find.text('Riprova'), findsOneWidget);

    library.error = null;
    library.onItems = (query, start, limit) => pageOf([testItem(id: 'm1', name: 'Dune')]);
    await tester.tap(find.text('Riprova'));
    await settle(tester);
    expect(find.text('Film aggiunti di recente'), findsOneWidget);
  });

  testWidgets('le card delle righe aprono l\'anteprima al passaggio del mouse',
      (tester) async {
    someRows();
    await pumpHome(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    for (final (cardType, play) in [
      (LandscapeCard, 'Riprendi'),
      (PosterCard, 'Riproduci'),
    ]) {
      final card = find.byType(cardType).first;
      expect(find.byType(CardPreview), findsNothing);
      await gesture.moveTo(tester.getCenter(card));
      await tester.pump(previewHoverDelay);
      await tester.pumpAndSettle();
      expect(find.byType(CardPreview), findsOneWidget, reason: '$cardType');
      expect(find.byTooltip(play), findsOneWidget, reason: '$cardType: $play');
      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('ordine dell\'admin e ritocchi dell\'utente', (tester) async {
    someRows();
    home.layoutRows = ['myList', 'resume', 'latestMovies'];
    prefs.prefs = const HomeUserPrefs(
        rows: ['resume', 'myList'], hidden: ['latestMovies']);
    await pumpHome(tester, features: const SocialFeatures(home: true));
    expect(tester.getTopLeft(find.text('Continua a guardare')).dy,
        lessThan(tester.getTopLeft(find.text('La mia lista')).dy));
    expect(find.text('Film aggiunti di recente'), findsNothing);
    expect(find.text('Prossimi episodi'), findsNothing);
    expect(library.nextUpCalls, isEmpty, reason: 'riga spenta dall\'admin');
  });

  testWidgets('righe nascoste: nessuna chiamata', (tester) async {
    someRows();
    prefs.prefs = const HomeUserPrefs(hidden: ['becauseYouWatched', 'nextUp']);
    await pumpHome(tester);
    expect(library.playHistoryCalls, isEmpty);
    expect(library.nextUpCalls, isEmpty);
    expect(find.text('Continua a guardare'), findsOneWidget);
  });

  testWidgets('una riga lenta entra dopo 1,5 s, al suo posto', (tester) async {
    someRows();
    home
      ..seriesGate = Completer<void>()
      ..series = UpcomingPage(items: [testEpisode()]);
    await pumpHome(tester, features: const SocialFeatures(upcomingSeries: true));
    expect(find.byType(SkeletonBox), findsWidgets, reason: 'si aspetta');
    expect(find.text('Continua a guardare'), findsNothing);

    await tester.pump(homeRevealWait);
    await tester.pump();
    expect(find.text('Continua a guardare'), findsOneWidget);
    expect(find.text('Serie in arrivo'), findsNothing);

    home.seriesGate!.complete();
    await settle(tester);
    expect(find.text('Serie in arrivo'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Serie in arrivo')).dy,
        greaterThan(tester.getTopLeft(find.text('Serie aggiunte di recente')).dy));
  });

  testWidgets('una riga in errore non si vede, niente Riprova', (tester) async {
    someRows();
    home.moviesError = const ServerUnreachableException();
    await pumpHome(tester, features: const SocialFeatures(upcomingMovies: true));
    expect(find.text('Continua a guardare'), findsOneWidget);
    expect(find.text('Film in arrivo'), findsNothing);
    expect(find.text('Riprova'), findsNothing);
  });

  testWidgets('Home dell\'admin senza righe: resta il carosello', (tester) async {
    someRows();
    home.layoutRows = [];
    await pumpHome(tester, features: const SocialFeatures(home: true));
    expect(find.byType(HeroCarousel), findsOneWidget);
    expect(find.text('Film aggiunti di recente'), findsNothing);
    expect(find.text("Qui non c'è ancora niente."), findsNothing);
    expect(find.text('Riprova'), findsNothing);
  });

  testWidgets('le righe nuove', (tester) async {
    final it = lookupAppLocalizations(const Locale('it'));
    final now = DateTime.now();
    final tomorrowNoon = DateTime(now.year, now.month, now.day + 1, 12);
    library
      ..playHistoryItems = [testItem(id: 'm9', name: 'Dune')]
      ..similarById['m9'] = [
        for (final (id, name) in [
          ('a', 'Arrival'),
          ('b', 'Sicario'),
          ('c', 'Prisoners'),
          ('d', 'Enemy'),
        ])
          testItem(id: id, name: name),
      ]
      ..playedMovieItems = [testItem(id: 'm1')]
      ..itemsById['m2'] = testItem(id: 'm2', name: 'Matrix Reloaded');
    requests.lists[RequestsFilter.mine] = [
      testMediaRequest(id: 1, title: 'Andor', status: RequestStatus.pending,
          createdAt: now),
    ];
    collections.collectionsList = [
      testCollection(id: 'c1', name: 'Matrix - Collezione', itemIds: ['m1', 'm2']),
    ];
    home
      ..series = UpcomingPage(items: [
        testEpisode(seriesName: 'The Bear', airDate: tomorrowNoon, jellyfinSeriesId: 's1'),
      ])
      ..movies = UpcomingPage(items: [testUpcomingMovie()]);

    await pumpHome(tester,
        height: 4000,
        features: const SocialFeatures(
            requests: true,
            collections: true,
            upcomingSeries: true,
            upcomingMovies: true));

    expect(find.text('Perché hai visto Dune'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Le mie richieste'), findsOneWidget);
    expect(find.text('Andor'), findsOneWidget);
    expect(find.text(it.requestsStatusPending), findsOneWidget);
    expect(find.text('Continua la saga'), findsOneWidget);
    expect(find.text('Matrix Reloaded'), findsOneWidget);
    expect(find.text('Matrix - Collezione · 1 di 2 visti'), findsOneWidget);
    expect(find.text('Serie in arrivo'), findsOneWidget);
    expect(find.text('S02E05 · Domani'), findsOneWidget);
    expect(find.text('Film in arrivo'), findsOneWidget);
    expect(find.text('Digitale · 13 ott'), findsOneWidget);
  });
}
```

`test/features/home/home_row_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_row_view.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  Future<void> pumpRow(WidgetTester tester, HomeRowKind kind,
      HomeRowContent content,
      {SocialFeatures features = SocialFeatures.none}) async {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
              body: HomeRowView(
                  kind: kind, content: content, animateEntrance: false))),
      GoRoute(
          path: '/collection/:id',
          builder: (_, state) => Text('saga ${state.pathParameters['id']}')),
      GoRoute(
          path: '/item/:id',
          builder: (_, state) => Text('scheda ${state.pathParameters['id']}')),
      GoRoute(
          path: '/tmdb/:type/:id',
          builder: (_, state) => Text(
              'seerr ${state.pathParameters['type']} ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router, overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ]);
    await tester.pump();
  }

  testWidgets('saga: il clic apre la pagina della saga', (tester) async {
    await pumpRow(
        tester,
        HomeRowKind.continueSaga,
        SagasRowContent([
          SagaProgress(
              saga: testCollection(id: 'c1', name: 'Matrix', itemIds: ['m1', 'm2']),
              next: testItem(id: 'm2', name: 'Matrix Reloaded'),
              watched: 1),
        ]));
    expect(find.text('Matrix · 1 di 2 visti'), findsOneWidget);
    await tester.tap(find.text('Matrix Reloaded'));
    await tester.pumpAndSettle();
    expect(find.text('saga c1'), findsOneWidget);
  });

  testWidgets('serie in arrivo nella libreria: la scheda', (tester) async {
    await pumpRow(tester, HomeRowKind.upcomingSeries,
        UpcomingSeriesRowContent([testEpisode(jellyfinSeriesId: 's1')]));
    await tester.tap(find.text('The Bear'));
    await tester.pumpAndSettle();
    expect(find.text('scheda s1'), findsOneWidget);
  });

  testWidgets('serie in arrivo fuori dalla libreria: Seerr, se c\'è',
      (tester) async {
    await pumpRow(tester, HomeRowKind.upcomingSeries,
        UpcomingSeriesRowContent([testEpisode()]),
        features: const SocialFeatures(requests: true));
    await tester.tap(find.text('The Bear'));
    await tester.pumpAndSettle();
    expect(find.text('seerr tv 136315'), findsOneWidget);
  });

  testWidgets('film in arrivo senza Seerr: non si clicca', (tester) async {
    await pumpRow(tester, HomeRowKind.upcomingMovies,
        UpcomingMoviesRowContent([testUpcomingMovie()]));
    await tester.tap(find.text('Hope'));
    await tester.pumpAndSettle();
    expect(find.textContaining('seerr'), findsNothing);
    expect(find.text('Hope'), findsOneWidget);
  });

  testWidgets('richiesta: la pagina Seerr del titolo', (tester) async {
    await pumpRow(tester, HomeRowKind.requests,
        RequestsRowContent([testMediaRequest(id: 1, type: RequestMediaType.movie)]));
    await tester.tap(find.text('Dune - Parte due'));
    await tester.pumpAndSettle();
    expect(find.text('seerr movie 693001'), findsOneWidget);
  });
}
```

(Se `pumpAppRouter` ha una firma diversa, adegua la chiamata.)

In `test/features/home/home_entrance_test.dart`:
- sostituisci gli `overrides()` con `homeOverrides(library: api)` (importa `../../support/home_fakes.dart`; togli gli import non più usati);
- dopo ogni `pumpApp(…)`, al posto dei due `tester.pump()`, chiama un `settle(tester)` come in `home_screen_test.dart` (sei `pump()`).

In `test/features/home/home_data_test.dart` togli i due test di `loadHome` ("loadHome raccoglie tutte le righe" e "prossimi episodi: solo serie guardate nell'ultimo anno").

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/home`
Expected: errori di compilazione (`homeRevealWait`, `HomeRowView` inesistenti).

- [ ] **Step 3: il codice**

`lib/features/home/home_data.dart` diventa (il corpo di `pickFeatured` resta quello di oggi, invariato):

```dart
import '../../core/jellyfin/item_models.dart';

/// Come jellyfin-web: nei "Prossimi episodi" solo le serie guardate negli
/// ultimi 365 giorni.
DateTime nextUpCutoff(DateTime now) => now.subtract(const Duration(days: 365));

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
```

`lib/features/home/home_row_view.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../core/social/home_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/landscape_card.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/remote_image_card.dart';
import '../library/library_providers.dart';
import '../requests/request_labels.dart';
import '../requests/requestable_poster_card.dart';
import '../requests/requests_navigation.dart';
import '../requests/requests_providers.dart';
import 'home_layout.dart';
import 'home_row_content.dart';
import 'home_rows_logic.dart';

/// Una riga della Home (spec M §6.1, §8.3): il titolo e le card del suo
/// tipo.
class HomeRowView extends ConsumerWidget {
  const HomeRowView({
    super.key,
    required this.kind,
    required this.content,
    required this.animateEntrance,
  });

  final HomeRowKind kind;
  final HomeRowContent content;

  /// Le card volano dentro con la riga (vedi `MediaRow.animateEntrance`).
  final bool animateEntrance;

  /// Altezze delle righe di locandine e di card orizzontali.
  static const posterRowHeight = 300.0;
  static const landscapeRowHeight = 230.0;

  /// Larghezza delle locandine della libreria (come `RemoteCardShape.poster`).
  static const posterWidth = 160.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return switch (content) {
      ItemsRowContent(:final items) => kind == HomeRowKind.resume ||
              kind == HomeRowKind.nextUp
          ? _landscapes(_title(l), items)
          : _posters(_title(l), items),
      BecauseYouWatchedContent(:final sourceName, :final items) =>
        _posters(l.homeBecauseYouWatched(sourceName), items),
      RequestsRowContent(:final requests) => _row(
          l.homeMyRequests, posterRowHeight, requests.length, (context, i) {
          final request = requests[i];
          final year = request.year;
          return RemoteImageCard(
            shape: RemoteCardShape.poster,
            image: TmdbImages.poster(request.posterPath),
            title: request.title,
            subtitle: year?.toString(),
            badge: RequestBadge(
                label: requestStatusLabel(l, request), highlighted: true),
            onTap: () => openRequest(context, request),
          );
        }),
      SagasRowContent(:final sagas) => _row(
          l.homeContinueSaga, landscapeRowHeight, sagas.length, (context, i) {
          final saga = sagas[i];
          return LandscapeCard(
            item: saga.next,
            subtitle:
                l.homeSagaProgress(saga.saga.name, saga.watched, saga.total),
            onTap: () => openCollection(context, saga.saga.id),
          );
        }),
      UpcomingSeriesRowContent(:final episodes) =>
        _upcomingSeries(context, ref, l, episodes),
      UpcomingMoviesRowContent(:final movies) =>
        _upcomingMovies(ref, l, movies),
    };
  }

  String _title(AppLocalizations l) => switch (kind) {
        HomeRowKind.resume => l.homeContinueWatching,
        HomeRowKind.nextUp => l.homeNextUp,
        HomeRowKind.requests => l.homeMyRequests,
        HomeRowKind.latestMovies => l.homeLatestMovies,
        HomeRowKind.latestSeries => l.homeLatestSeries,
        // Il titolo vero ha il nome del titolo di partenza.
        HomeRowKind.becauseYouWatched => '',
        HomeRowKind.continueSaga => l.homeContinueSaga,
        HomeRowKind.upcomingSeries => l.homeUpcomingSeries,
        HomeRowKind.upcomingMovies => l.homeUpcomingMovies,
        HomeRowKind.myList => l.navMyList,
      };

  Widget _row(String title, double height, int count,
          IndexedWidgetBuilder itemBuilder) =>
      MediaRow(
        title: title,
        height: height,
        itemCount: count,
        animateEntrance: animateEntrance,
        itemBuilder: itemBuilder,
      );

  Widget _posters(String title, List<JellyfinItem> items) =>
      _row(title, posterRowHeight, items.length, (context, i) => PosterCard(
            item: items[i],
            width: posterWidth,
            heroSource: 'home.${kind.id}.$i',
          ));

  Widget _landscapes(String title, List<JellyfinItem> items) =>
      _row(title, landscapeRowHeight, items.length, (context, i) =>
          LandscapeCard(item: items[i], heroSource: 'home.${kind.id}.$i'));

  /// Sfondo: quello di Jellyfin se la serie c'è, poi quello di Sonarr, poi la
  /// locandina; clic: la scheda, poi Seerr, poi niente (spec M §8.3).
  Widget _upcomingSeries(BuildContext context, WidgetRef ref,
      AppLocalizations l, List<UpcomingEpisode> episodes) {
    final urls = ref.watch(imageUrlsProvider);
    final canRequest = ref.watch(requestsAvailableProvider);
    final now = clock.now();
    return _row(l.homeUpcomingSeries, landscapeRowHeight, episodes.length,
        (context, i) {
      final episode = episodes[i];
      final seriesId = episode.jellyfinSeriesId;
      final tmdbId = episode.tmdbId;
      final remote = episode.backdropUrl ?? episode.posterUrl;
      return RemoteImageCard(
        shape: RemoteCardShape.landscape,
        image: seriesId != null
            ? urls.backdropOf(seriesId)
            : remote == null
                ? null
                : ImageRef(remote),
        title: episode.seriesName,
        subtitle: upcomingEpisodeLabel(episode, now, l),
        onTap: seriesId != null
            ? () => openItemById(context, seriesId)
            : tmdbId != null && canRequest
                ? () => unawaited(
                    context.push(tmdbRoute(RequestMediaType.tv, tmdbId)))
                : null,
      );
    });
  }

  Widget _upcomingMovies(
      WidgetRef ref, AppLocalizations l, List<UpcomingMovie> movies) {
    final canRequest = ref.watch(requestsAvailableProvider);
    return _row(l.homeUpcomingMovies, posterRowHeight, movies.length,
        (context, i) {
      final movie = movies[i];
      final poster = movie.posterUrl;
      return RemoteImageCard(
        shape: RemoteCardShape.poster,
        image: poster == null ? null : ImageRef(poster),
        title: movie.title,
        subtitle: upcomingMovieLabel(movie, l),
        onTap: canRequest
            ? () => unawaited(context
                .push(tmdbRoute(RequestMediaType.movie, movie.tmdbId)))
            : null,
      );
    });
  }
}
```

`lib/features/home/home_screen.dart` (sostituisce la parte sopra `_HomeSkeleton`, che resta com'è):

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shimmer.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import 'hero_carousel.dart';
import 'home_layout.dart';
import 'home_providers.dart';
import 'home_row_content.dart';
import 'home_row_view.dart';

/// L'entrata delle righe della Home si vede una volta per sessione
/// (decisione 6b): tornando alla Home dalla barra non si ripete.
class HomeEntrancePlayed extends Notifier<bool> {
  @override
  bool build() => false;

  void markPlayed() => state = true;
}

final homeEntrancePlayedProvider =
    NotifierProvider<HomeEntrancePlayed, bool>(HomeEntrancePlayed.new);

/// Ritardo tra una riga e l'altra nell'entrata della Home.
const homeRowStagger = Duration(milliseconds: 80);

/// Quanto la Home aspetta le righe prima di aprirsi (spec M §8.2 punto 3):
/// quelle più lente entrano dopo, al loro posto.
const homeRevealWait = Duration(milliseconds: 1500);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = SmoothScrollController();

  /// Deciso una volta per istanza della Home: lo stato sta sopra al
  /// `WfSwitcher`, quindi resta lo stesso da scheletro a contenuto.
  late final bool _animate = !ref.read(homeEntrancePlayedProvider);

  /// Scade [homeRevealWait] dopo la composizione, se le righe non sono
  /// ancora arrivate tutte.
  Timer? _revealTimer;

  /// Le righe arrivate quando la Home si è aperta, con il loro posto
  /// nell'entrata scaglionata; `null` finché non si è aperta.
  Map<HomeRowKind, int>? _entrance;

  @override
  void dispose() {
    _revealTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  String get _language => Localizations.localeOf(context).languageCode;

  static bool _settled(AsyncValue<Object?> value) =>
      value.hasValue || value.hasError;

  static bool _failed(AsyncValue<Object?> value) =>
      value.hasError && !value.hasValue;

  /// Apre la Home: entrano insieme le righe già arrivate, nell'ordine.
  void _open(Map<HomeRowKind, AsyncValue<HomeRowContent>> rows) {
    _revealTimer?.cancel();
    _revealTimer = null;
    var index = 0;
    _entrance = {
      for (final MapEntry(:key, :value) in rows.entries)
        if (_settled(value)) key: index++,
    };
  }

  void _onRevealTimeout() {
    if (!mounted) return;
    final layout = ref.read(homeLayoutProvider).value;
    if (layout == null) return;
    setState(() => _open({
          for (final kind in layout.visible)
            kind: ref.read(homeRowProvider((kind: kind, language: _language))),
        }));
  }

  void _retry() {
    ref
      ..invalidate(homeLayoutProvider)
      ..invalidate(homeLatestMoviesProvider)
      ..invalidate(homeLatestSeriesProvider)
      ..invalidate(homeFeaturedProvider)
      ..invalidate(homeRowProvider);
    setState(() {
      _revealTimer?.cancel();
      _revealTimer = null;
      _entrance = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final layout = ref.watch(homeLayoutProvider).value;
    final (state, content) =
        layout == null ? ('loading', const _HomeSkeleton()) : _content(l, layout);
    return WfSwitcher(
      expand: true,
      child: KeyedSubtree(key: ValueKey(state), child: content),
    );
  }

  (String, Widget) _content(AppLocalizations l, HomeLayout layout) {
    final featured = ref.watch(homeFeaturedProvider);
    final rows = <HomeRowKind, AsyncValue<HomeRowContent>>{
      for (final kind in layout.visible)
        kind: ref.watch(homeRowProvider((kind: kind, language: _language))),
    };
    if (_entrance == null) {
      if (_settled(featured) && rows.values.every(_settled)) {
        _open(rows);
      } else {
        _revealTimer ??= Timer(homeRevealWait, _onRevealTimeout);
        return ('loading', const _HomeSkeleton());
      }
    }
    final entrance = _entrance!;
    // "Riprova" solo se il carosello e tutte le righe di Jellyfin visibili
    // hanno fallito (spec M §8.2 punto 4).
    if (_failed(featured) &&
        rows.entries
            .where((row) => row.key.fromJellyfin)
            .every((row) => _failed(row.value))) {
      return ('error', ErrorView(error: featured.error!, onRetry: _retry));
    }
    final featuredItems = featured.value ?? const [];
    final shown = <Widget>[
      for (final kind in layout.visible)
        if (rows[kind]!.value case final content? when !content.isEmpty)
          _row(kind, content, entrance[kind]),
    ];
    if (featuredItems.isEmpty && shown.isEmpty) {
      final pending = !_settled(featured) || !rows.values.every(_settled);
      if (pending) return ('loading', const _HomeSkeleton());
      return (
        'empty',
        Center(
          child: Text(l.homeEmpty,
              style: const TextStyle(color: WfColors.creamMuted)),
        ),
      );
    }
    return (
      'data',
      StaggerGroup(
        key: const Key('home-rows'),
        count: entrance.length,
        stagger: homeRowStagger,
        play: _animate,
        onPlayed: () =>
            ref.read(homeEntrancePlayedProvider.notifier).markPlayed(),
        child: ListView(
          controller: _scroll,
          // Il carosello parte dal bordo della finestra, sotto la barra;
          // senza carosello la prima riga inizia sotto la barra.
          padding: EdgeInsets.only(
              top: featuredItems.isEmpty ? shellBarHeight : 0, bottom: 40),
          children: [
            if (featuredItems.isNotEmpty) HeroCarousel(items: featuredItems),
            ...shown,
          ],
        ),
      ),
    );
  }

  /// Una riga arrivata all'apertura entra con le altre; una arrivata dopo
  /// entra da sola, al suo posto (decisione 6 del piano 19b).
  Widget _row(HomeRowKind kind, HomeRowContent content, int? index) {
    if (index == null) {
      return StaggerGroup(
        key: ValueKey('home-late-${kind.id}'),
        count: 1,
        child: StaggerItem(
          index: 0,
          child: HomeRowView(kind: kind, content: content, animateEntrance: true),
        ),
      );
    }
    return StaggerItem(
      key: ValueKey('home-row-${kind.id}'),
      index: index,
      child: HomeRowView(kind: kind, content: content, animateEntrance: _animate),
    );
  }
}
```

(Se `StaggerItem` non accetta una `key`, togli la `key` dal `StaggerItem` e avvolgilo in un `KeyedSubtree(key: …)`.)

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/home test/ui`
Expected: PASS. In `home_entrance_test.dart` il test "seconda volta nella stessa sessione" deve trovare **un solo** `StaggerGroup`: nessuna riga arriva tardi, quindi nessun gruppo in più. Se un test conta i fotogrammi in modo diverso, aggiusta solo il numero di `pump()`, non le asserzioni.

- [ ] **Step 5: commit**

`flutter analyze`, suite intera verde, poi:

```powershell
git add lib test
git commit -m "feat(app): customizable Home with per-row loading and the new rows"
```

---

## Gruppo D — prova e chiusura

### Task 9: STOP — review finale e prova con l'utente (lo fa l'orchestratore)

Il subagent del Gruppo C si ferma qui.

1. **Review finale del branch** (modello più capace) con il pacchetto della review, poi un solo giro di correzioni e una nuova review mirata, come nel 19a.
2. **Build di prova:** copia `config/wonderflix.json` nel worktree, poi `flutter build windows --release --dart-define-from-file=config/wonderflix.json`. Senza il flag l'exe mostra "Configurazione mancante".
3. **Prova con l'utente sul server vero** (il plugin 1.7.0 di prova ha già Sonarr e Radarr):
   - la Home con l'admin e con un account normale di prova:
     - Perché hai visto X, Le mie richieste, Continua la saga;
     - Serie in arrivo e Film in arrivo, con il clic su una serie della libreria e su una che non c'è;
   - **`JellyfinSeriesId` con un utente vero:** "American Hostage" o "Brothers" devono aprire la scheda della serie;
   - **Home dell'admin:** con l'OK dell'utente, l'orchestratore la imposta via API con la chiave "Wonderflix" (`POST /WonderFlixWatchParty/Home/Layout`, per esempio `["myList","resume","upcomingSeries"]`). L'utente controlla ordine e righe nell'app, poi la si rimette a `null`;
   - **Home dell'utente:** con l'OK dell'utente, l'orchestratore scrive per l'account di prova `homeRows` e `homeHidden` con un `POST /DisplayPreferences/wonderflix-home?userId=…&client=wonderflix` (rilegge e riscrive l'oggetto intero, come l'app). L'utente controlla con quell'account, poi l'orchestratore toglie le due voci;
   - Sonarr irraggiungibile: **solo se l'utente lo vuole provare**, con un indirizzo sbagliato salvato apposta e poi rimesso. La Home si apre lo stesso, senza la riga;
   - riga lenta: con la rete lenta non si prova a mano, è coperta dai test.
4. Aspetta l'esito dell'utente. Le modifiche chieste durante la prova si fanno con TDD nel worktree, prima del merge.

### Task 10: allineamento della spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-10-wonderflix-home-su-misura-design.md`
- Modify: `docs/superpowers/plans/2026-10-10-wonderflix-19b-home-app.md` (solo una voce "Dalle review dei gruppi", se ci sono differenze)

- [ ] **Step 1: la spec**

Controllando ogni frase sul codice:
- **Stato:** piano 19b realizzato e provato, con la data; piano 19c da scrivere.
- **§6.4 punto 1:** la regola della decisione 2 ("dopo l'ultima delle righe che la precedono in `A`"), allineata all'esempio.
- **§8.2:**
  - le funzioni del plugin aspettate al massimo 2 s;
  - le righe arrivate dopo hanno una loro entrata, anche dopo la prima visita;
  - il carosello con una sola lettura riuscita.
- **§8.3:**
  - 50 visioni per Perché hai visto X;
  - la data d'uscita (`PremiereDate`) per i film delle saghe;
  - la data digitale come data di calendario;
  - le card `RemoteImageCard` e il sottotitolo di `LandscapeCard`.
- **§14:** le verifiche del 2026-10-10 e quelle del Task 9, con l'esito.
- **§15:** 19b realizzato.
- Ogni altra differenza venuta fuori nei task, con il motivo.

- [ ] **Step 2: commit**

```powershell
git add docs
git commit -m "docs: align the Home spec with plan 19b"
```

### Task 11: ok dell'utente e merge

Con l'ok dell'utente sulla prova del Task 9: merge fast-forward su `main` e push (memoria `wonderflix-workflow`). Niente release: app 0.13.0 e plugin 1.7.0 escono alla fine del 19c.
