# WonderFlix — Piano 25b: calendario delle uscite, app 0.20.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte app della Spec S nell'app 0.20.0:
- la pagina **Calendario** (`/calendar?month=YYYY-MM`): griglia del mese da lunedì, sei righe, con le uscite di Sonarr e Radarr, l'elenco del giorno in una finestra e il clic che porta alla scheda;
- la voce "Calendario" nella barra, solo con la funzione `calendar` del plugin;
- nella pagina **Richieste**, le date di ogni richiesta e lo stato "In attesa dell'uscita".

Il plugin 1.13.0 (piano 25a) è già sul server come build di prova.

**Architecture:**
- **Dati:** `UpcomingEpisode` e `UpcomingMovie` (`home_models.dart`) imparano `onServer` e, per i film, `jellyfinItemId`. `CalendarPage` è la risposta di `GET Upcoming/Calendar`, letta da `HomeApi.calendar`. `MediaRequest` impara le date; `RequestStatus` impara `awaitingRelease`.
- **Logica pura** in `lib/features/calendar/calendar_logic.dart`: i 42 giorni della griglia, le voci di ogni giorno (raggruppate per serie), le etichette e la destinazione del clic. Le date delle richieste in `request_labels.dart`.
- **Interfaccia** in `lib/features/calendar/`: `calendar_providers.dart`, `calendar_screen.dart`, `calendar_month_grid.dart`, `calendar_day_dialog.dart`, `calendar_navigation.dart`.

**Tech Stack:** Flutter 3.47.5 (Windows), Riverpod 3, go_router, intl, lucide_icons_flutter, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-22-wonderflix-calendario-uscite-design.md` (§3, §6.1–§6.2 per il JSON, §7, §8, §9.2, §9.3, §10, §11).

**Decisioni del piano** (rispetto alla spec; si allineano nel Task 6):
1. **Niente modelli nuovi per le uscite:** il calendario riusa `UpcomingEpisode` e `UpcomingMovie`, con i campi nuovi facoltativi (`onServer` falso se manca, `jellyfinItemId` null). La Home li ignora.
2. **Campi mancanti = null.** Jellyfin non scrive i null (spec §6.1), quindi `SeriesError`, `MoviesError`, `JellyfinSeriesId`, `JellyfinItemId` e le date delle richieste di solito **mancano**. Si leggono con gli aiutanti tolleranti di `json_fields.dart`.
3. **`NotConfigured` non è un errore da mostrare:** con solo Sonarr configurato, `MoviesError` è `NotConfigured` e la pagina non dice niente dei film. Le righe "non si possono caricare" sono solo per `Unauthorized` e `Unreachable`. "Errore con Riprova" a pagina intera solo se **ogni** servizio configurato è in errore.
4. **Il motivo per l'admin** (spec §7.6) è il testo di `arrTestLabel` della card admin, dopo un " · ": "Le serie non si possono caricare ora · Chiave rifiutata". Gli altri vedono solo la prima parte.
5. **Tastiera:** frecce (±1 giorno, ±7 giorni) e Invio, dentro i 42 giorni della griglia, dal giorno di oggi (o dal primo del mese, se oggi non c'è). Invio apre l'elenco del giorno. **Niente PagSu/PagGiù** (la spec la lascia al costruttore "se costa poco"; le frecce in alto bastano).
6. **Caselle strette:** sotto `CalendarMonthGrid.compactCellWidth = 96` px la casella mostra solo il numero e un puntino per voce (al massimo 4). Il clic apre l'elenco del giorno.
7. **Quante voci in una casella:** `max(2, (altezza − 22) ~/ 20)` (riga del numero 22 px, voce 20 px). Se le voci sono di più, l'ultima riga diventa "+{n}".
8. **Raggruppamento delle serie:** nello stesso giorno locale, gli episodi della stessa serie (stesso `tvdbId`, altrimenti `tmdbId`, altrimenti nome senza badare alle maiuscole) sono **una** voce. `count` = episodi totali (un blocco "E01–E03" vale 3). `onServer` vero solo se lo sono tutti.
9. **Righe delle date nelle richieste:**
   - film senza nessuna data (né cinema né digitale) → nessuna riga: Radarr non configurato o plugin vecchio, e "data non ancora nota" sarebbe falso;
   - la prima parte comincia con la maiuscola ("In digitale previsto il…" se manca il cinema);
   - in oro le parti con una data **futura**.
10. **La pagina si rifà a ogni mese:** `ValueKey(state.uri.toString())` come la pagina Richieste. Il fuoco della tastiera ricomincia da capo dopo un cambio di mese.
11. **Colori nuovi** in `WfColors`: `calendarMovie = Color(0xFF2B2418)` (oro scuro) e `calendarSeries = Color(0xFF1D2630)` (blu scuro), presi dalla bozza approvata.

## Global Constraints

- App **0.20.0** (`pubspec.yaml`). Plugin minimo per il calendario: 1.13.0 (si vede dalla funzione `calendar`, non dalla versione).
- **JSON del plugin** (PascalCase; un campo null **manca**):
  - `GET /WonderFlixWatchParty/Upcoming/Calendar?start=YYYY-MM-DD&end=YYYY-MM-DD` (`end` escluso, al massimo 42 giorni) → `{"Episodes":[…],"Movies":[…],"SeriesError"?,"MoviesError"?}`;
  - episodio: i campi di `Upcoming/Series` più `OnServer` (bool);
  - film: i campi di `Upcoming/Movies` più `JellyfinItemId`? e `OnServer`;
  - errori: `NotConfigured`, `Unauthorized`, `Unreachable` (`UpcomingError`);
  - `MediaRequest` in più: `InCinemas`?, `DigitalRelease`?, `NextAiring`? (date ISO UTC), `NextSeasonNumber`?, `NextEpisodeNumber`? (int); stato nuovo `"AwaitingRelease"`.
- **Funzione:** `calendar` in `Info.Features`.
- **Date:**
  - un episodio va nel giorno **locale** di `AirDateUtc` (`airDate.toLocal()`);
  - un film va nel giorno **UTC** di `DigitalRelease` (`digitalRelease.toUtc()`, anno/mese/giorno), mai spostato dal fuso (spec §10). Lo stesso per `InCinemas` e `DigitalRelease` delle richieste;
  - `NextAiring` di una serie è un'ora vera: giorno locale;
  - conti tra giorni con `DateTime.utc(y, m, d)`; `clock.now()` (package `clock`), mai `DateTime.now()`;
  - formati con `l.localeName`: "12 novembre" = `DateFormat.MMMMd`, con l'anno (`DateFormat.yMMMMd`) solo se non è quello di oggi; titolo del mese `DateFormat.yMMMM` con l'iniziale maiuscola; titolo della finestra `DateFormat.MMMMEEEEd` con l'iniziale maiuscola; ora `DateFormat.Hm`.
- **Griglia:** sette colonne da **lunedì** a domenica, **sei righe sempre** (42 giorni). Il periodo chiesto al plugin è dal primo giorno della griglia al giorno dopo l'ultimo.
- **Testi** (ARB, `l10n/app_it.arb` è il modello; anche `app_en.arb`):

  | Chiave | it | en |
  |---|---|---|
  | `navCalendar` | Calendario | Calendar |
  | `calendarToday` | Oggi | Today |
  | `calendarPreviousMonth` | Mese precedente | Previous month |
  | `calendarNextMonth` | Mese successivo | Next month |
  | `calendarEmpty` | Nessuna uscita in questo mese | No releases this month |
  | `calendarMore` | +{count} | +{count} |
  | `calendarSeriesCount` | {name} ×{count} | {name} ×{count} |
  | `calendarMovieDigital` | Film · in digitale | Movie · digital |
  | `calendarOnServer` | Sul server | On the server |
  | `calendarSeriesUnavailable` | Le serie non si possono caricare ora | Series can't be loaded right now |
  | `calendarMoviesUnavailable` | I film non si possono caricare ora | Movies can't be loaded right now |
  | `calendarDayReleases` | {date}: {count, plural, =1{1 uscita} other{{count} uscite}} | {date}: {count, plural, =1{1 release} other{{count} releases}} |
  | `calendarAlreadyOnServer` | già sul server | already on the server |
  | `requestsStatusAwaitingRelease` | In attesa dell'uscita | Waiting for release |
  | `requestsInCinemas` | Al cinema dal {date} | In cinemas from {date} |
  | `requestsDigitalExpected` | in digitale previsto il {date} | digital expected on {date} |
  | `requestsDigitalReleased` | uscito in digitale il {date} | out digitally on {date} |
  | `requestsDigitalUnknown` | in digitale: data non ancora nota | digital: date not known yet |
  | `requestsNextEpisode` | Prossimo episodio: {episode} il {date} | Next episode: {episode} on {date} |
  | `requestsNextEpisodeDate` | Prossimo episodio il {date} | Next episode on {date} |

  Per "Film" e "Serie" (screen reader) si riusano `requestsKindMovie` e `requestsKindSeries`. `{episode}` è "S03E04", composto dal codice con due cifre.
- **Commit:** con l'identità git del repository; **mai** trailer `Co-Authored-By` né righe "Generated with…"; mai le parole `closes`, `fixes`, `resolves` (né simili) nei messaggi.
- **Processi:** mai terminarli per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`); solo per PID.
- **Build per la prova:** sempre `flutter build windows --release --dart-define-from-file=config/wonderflix.json` (copiare prima `config/wonderflix.json` dal checkout principale).

## Review Focus

1. **Un episodio alle 01:00 UTC** va nel giorno locale (il giorno prima in America, lo stesso in Italia d'estate e d'inverno), e un film a mezzanotte UTC resta nel suo giorno anche con un fuso negativo. Test: Task 3 (`EpisodesUseTheLocalDayMoviesTheUtcDay`).
2. **Il mese che attraversa l'ora legale** (ottobre e marzo): i 42 giorni sono consecutivi, nessun giorno ripetuto o saltato. Test: Task 3 (`GridDaysAreFortyTwoConsecutiveDaysFromMonday`, con marzo e ottobre 2026).
3. **Solo Sonarr configurato:** nessuna riga sui film e nessun errore a pagina intera. Test: Task 5 (`NotConfiguredIsSilent`).
4. **Una richiesta di film approvata con il plugin vecchio** (niente date, stato `Approved`): la riga resta come oggi, senza "data non ancora nota". Test: Task 2 (`NoDatesNoLine`).
5. **Le richieste "In attesa dell'uscita"** restano nella riga Home "Le mie richieste" tra quelle aperte. Test: Task 2 (`AwaitingReleaseIsAnOpenRequest`).

---

## Regole per chi esegue

- **Worktree** `.claude/worktrees/piano-25b` (branch `piano-25b` da `main`). Tutti i comandi partono dalla sua root: fai prima `Set-Location` lì e non toccare mai il checkout principale. In un worktree nuovo `flutter gen-l10n` va fatto prima di tutto.
- **Shell:** PowerShell. In ogni comando con `flutter`, `dart` o `git`, prima rinfresca il PATH:
  `$env:Path = 'C:\Users\sidot\dev\flutter\bin;' + [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
- **Commit:** vedi le Global Constraints. Su una riga sola, `git commit -m "feat(app): …"`. Comandi git semplici: niente `git -C`, e mai `git checkout -- <file>` su un file che hai modificato. Non fare push.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit** `flutter analyze` senza problemi e la suite intera tutta verde con **`flutter test --concurrency=4`** (con i 16 processi predefiniti il PC si è riavviato);
  - prima del Task 1 misura la base (numero di test verdi su `main`) e scrivila nel primo resoconto.
- **File generati:**
  - dopo ogni modifica agli ARB `flutter gen-l10n` (`lib/l10n/gen/` non si committa);
  - se `windows/flutter/generated_plugin*` cambia solo nei fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione:** niente `dart format` su file interi, solo modifiche mirate. Ogni file tiene i suoi fine riga. Scrivi in UTF-8 con gli strumenti di modifica dei file, mai con `Set-Content` o `Out-File`.
- **Codice:** commenti in italiano, codice in inglese; durate, misure e limiti come costanti nominate e commentate. ARB: chiavi piatte, una riga ciascuna, il blocco `@chiave` subito dopo solo in `app_it.arb` quando ci sono segnaposti (come `requestsSeasonsList`).
- **Provider e test:**
  - nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`; i container hanno `retry: (_, _) => null`;
  - in un provider tutti i `ref.watch` stanno prima del primo `await`;
  - nei test di formattazione fuori da un `MaterialApp`: `setUpAll(() => initializeDateFormatting())`.
- **Se il codice del piano ha un errore** (analyzer, firma diversa, `switch` esaustivo da completare in un file non elencato, icona Lucide con un altro nome): correggilo in modo minimo e segnalalo. Meglio correggere il codice che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-22 sul codice di `main` (`4585cf3`) e sul server.

- **Funzioni del plugin:** `PluginFeatures` (`lib/core/social/social_models.dart:13`, `upcomingMovies` a :39). `SocialFeatures` (`lib/features/social/social_providers.dart:19`) ha ogni flag in sei punti: costruttore, campo, `==` (:104-120), `hashCode` (:122-139), `toString` (:142) e `SocialAvailability.refresh()` (:237-257). Modello del cancello: `requestsAvailableProvider` e `requestsGoneProvider` (`lib/features/requests/requests_providers.dart:69,76`); `requests_screen.dart:53-61` torna a `/home` quando la funzione sparisce.
- **Barra:** voci in `lib/app/app_shell.dart:109-122` (record `_NavEntry`), Richieste a :114-116; i test cercano `Key('nav-/requests')`. Rotte in `lib/app/router.dart`: `/requests` a :170-179 è il modello (`shellPage(..., underBar: true)`, chiave dall'indirizzo, parametro letto da `state.uri.queryParameters`).
- **Uscite:** `lib/core/social/home_models.dart`: `UpcomingError` (:5, `parse` a :16), `UpcomingPage` (:27), `UpcomingEpisode` (:43), `UpcomingMovie` (:101), `_webAddress` privato (:139). Aiutanti tolleranti in `lib/core/jellyfin/json_fields.dart` (`jsonString`, `jsonInt`, `jsonDate`, `jsonList`). I booleani si leggono come `json['X'] == true`. `HomeApi` (`lib/core/social/home_api.dart`, `_http.get(path, query:, quietStatuses: _quiet)`); `homeApiProvider` in `lib/features/home/home_providers.dart:28`. `FakeHomeApi implements HomeApi` in `test/support/home_fakes.dart`: un metodo nuovo va aggiunto anche lì, o la suite non compila.
- **Etichette esistenti:** `upcomingEpisodeLabel`/`upcomingMovieLabel` e `_calendarDays` in `lib/features/home/home_rows_logic.dart:247-280`; `arrTestLabel(l, ArrTestResult)` in `lib/features/admin/home_admin_cards.dart:222` (testi `adminArrNotConfigured/Unauthorized/Unreachable`); `isAdminProvider` in `lib/features/admin/admin_providers.dart:17`.
- **Navigazione:** `openItemById(context, id)` (`lib/app/navigation.dart:58`) per film e serie della libreria; `tmdbRoute(RequestMediaType type, int tmdbId)` (`lib/features/requests/requests_navigation.dart:10`) per la scheda da richiedere, aperta con `context.push`.
- **Richieste:** `RequestStatus` (`lib/core/requests/requests_models.dart:41-60`, sconosciuto → `approved`); `MediaRequest` (:256, `fromJson` a :272 con cast rigidi). Due `switch` esaustivi in `lib/features/requests/request_labels.dart` (`requestStatusLabel` :27, `requestStatusColor` :44). `_openRequests` in `lib/features/home/home_rows_logic.dart:102`. `RequestRow` (`lib/features/requests/request_row.dart:58-95`): la riga delle date è il terzo figlio della `Column`. Fabbrica di test `testMediaRequest(...)` in `test/support/requests_fakes.dart:352`.
- **Interfaccia:** `showWfDialog` (`lib/ui/wf_dialog.dart:100`), `WfImage` + `ImageRef` (`lib/ui/wf_image.dart`, `lib/core/jellyfin/image_urls.dart`), `WfColors` e `WfText.display` (`lib/app/theme.dart`), `LoadingView`/`ErrorView` (`lib/ui/states.dart`), `HoverBuilder` (`lib/ui/hover_builder.dart`), `WfTabButton`. La Home **non** ha tastiera da copiare: la griglia usa `Focus` con `onKeyEvent` (`LogicalKeyboardKey.arrowLeft/Right/Up/Down`, `enter`). Icone Lucide: verifica i nomi (`LucideIcons.chevronLeft`, `chevronRight`, `film`, `tv`).
- **Test:** `pumpApp`/`pumpAppRouter` (`test/support/pump_app.dart`), `FakeAdapter` (`test/support/fake_adapter.dart`), `FakeSocialAvailability` (`test/support/social_fakes.dart`), `requestsTestOverrides` (`test/support/requests_fakes.dart`). Modelli: `test/core/social/home_api_test.dart`, `test/features/requests/requests_screen_test.dart` (GoRouter locale con rotte finte `/home`, `/tmdb/:type/:tmdbId`), `test/app/app_shell_test.dart` ("voce Richieste solo con la funzione delle richieste"), `test/app/l10n_plan24c_test.dart`. Niente golden.
- **Server:** il calendario del 27 ottobre – 8 dicembre 2026 ha 44 episodi e 4 film; le risposte non hanno i campi null.

## File

| File | Responsabilità |
|---|---|
| `lib/core/social/home_models.dart`, `lib/core/social/home_api.dart`, `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart` | dati del calendario e funzione `calendar` |
| `lib/core/requests/requests_models.dart`, `lib/features/requests/request_labels.dart`, `lib/features/requests/request_row.dart`, `lib/features/home/home_rows_logic.dart` | date e stato nuovo delle richieste |
| `lib/features/calendar/calendar_logic.dart` | giorni della griglia, voci per giorno, etichette, destinazione del clic |
| `lib/features/calendar/calendar_month_grid.dart`, `lib/features/calendar/calendar_day_dialog.dart` | griglia e finestra del giorno |
| `lib/features/calendar/calendar_providers.dart`, `lib/features/calendar/calendar_navigation.dart`, `lib/features/calendar/calendar_screen.dart`, `lib/app/router.dart`, `lib/app/app_shell.dart`, `lib/app/theme.dart` | pagina, rotta, voce nella barra, colori |
| `l10n/app_it.arb`, `l10n/app_en.arb`, `test/app/l10n_plan25b_test.dart` | testi |
| `pubspec.yaml`, `docs/RELEASING.md`, spec | versione e documenti |

---

### Task 1: dati del calendario e funzione `calendar`

**Files:**
- Modify: `lib/core/social/home_models.dart`, `lib/core/social/home_api.dart`, `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart`
- Modify (test): `test/support/home_fakes.dart`
- Test: `test/core/social/home_api_test.dart`, `test/core/social/home_models_test.dart` (o il file di test dei modelli che c'è), il test di `SocialAvailability` in `test/features/social/`

**Interfaces:**
- Produces:
  - `UpcomingEpisode` in più: `final bool onServer` (predefinito `false`, da `json['OnServer'] == true`).
  - `UpcomingMovie` in più: `final bool onServer` (come sopra) e `final String? jellyfinItemId` (da `jsonString(json, 'JellyfinItemId')`).
  - `class CalendarPage { const CalendarPage({this.episodes = const [], this.movies = const [], this.seriesError, this.moviesError}); final List<UpcomingEpisode> episodes; final List<UpcomingMovie> movies; final UpcomingError? seriesError; final UpcomingError? moviesError; factory CalendarPage.fromJson(Map<String, dynamic> json); }` in `home_models.dart`. Liste mancanti o non liste → vuote (come `UpcomingPage`); righe incomplete scartate.
  - `HomeApi.calendar(DateTime start, DateTime end)` → `Future<CalendarPage>`: `GET $_base/Upcoming/Calendar` con `query: {'start': 'yyyy-MM-dd', 'end': 'yyyy-MM-dd'}` (giorni di calendario di `start` e `end`, senza ora), `quietStatuses: _quiet`.
  - `FakeHomeApi` in più: `CalendarPage calendarPage` (predefinita vuota), `Object? calendarError` (se non null il metodo lancia), `List<(DateTime, DateTime)> calendarCalls`.
  - `PluginFeatures.calendar = 'calendar'` (dopo `upcomingMovies`, con il `///` "Il calendario delle uscite (spec S §6.4)"); `SocialFeatures.calendar` (bool, nei sei punti), letto in `refresh()` da `info.features.contains(PluginFeatures.calendar)`, senza il cancello `_canJoin`.

- [ ] **Step 1: test che falliscono.**
  - `home_api_test.dart`: `CalendarAsksThePeriodAsDays`: `api.calendar(DateTime(2026, 9, 28), DateTime(2026, 11, 9))` → path `/WonderFlixWatchParty/Upcoming/Calendar`, query `start=2026-09-28`, `end=2026-11-09`.
  - `CalendarReadsBothListsAndMissingFieldsAsNull`: risposta `{"Episodes":[{"SeriesName":"Andor","SeasonNumber":3,"EpisodeNumber":1,"AirDateUtc":"2026-10-23T01:00:00Z","OnServer":true}],"Movies":[{"Title":"Weapons","TmdbId":1078605,"DigitalRelease":"2026-10-20T00:00:00Z","JellyfinItemId":"abc"},{"Title":"Senza id"}]}` → un episodio con `onServer` vero e `jellyfinSeriesId` null; un film con `jellyfinItemId` `"abc"` e `onServer` falso; il secondo film scartato; `seriesError` e `moviesError` null.
  - `CalendarReadsTheErrors`: `{"Episodes":[],"Movies":[],"SeriesError":"Unreachable","MoviesError":"NotConfigured"}` → `UpcomingError.unreachable`, `UpcomingError.notConfigured`.
  - Test delle funzioni: con `Features` che contiene `"calendar"` → `SocialFeatures.calendar` vero; senza → falso; `SocialFeatures(calendar: true) != SocialFeatures()`.
- [ ] **Step 2: i test falliscono** (`flutter test test/core/social/home_api_test.dart` e gli altri file): errori di compilazione.
- [ ] **Step 3: il codice** con le firme sopra, più `FakeHomeApi`.
- [ ] **Step 4: i test passano**, poi `flutter analyze` e la suite intera.
- [ ] **Step 5: commit** `git commit -m "feat(app): calendar data and plugin feature"`

### Task 2: date e "In attesa dell'uscita" nelle richieste

**Files:**
- Modify: `lib/core/requests/requests_models.dart`, `lib/features/requests/request_labels.dart`, `lib/features/requests/request_row.dart`, `lib/features/home/home_rows_logic.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify (test): `test/support/requests_fakes.dart` (`testMediaRequest` con `inCinemas`, `digitalRelease`, `nextAiring`, `nextSeasonNumber`, `nextEpisodeNumber` facoltativi)
- Test: `test/core/requests/requests_models_test.dart` (o quello che c'è), `test/features/requests/request_labels_test.dart`, `test/features/requests/request_row_test.dart`, `test/features/home/home_rows_logic_test.dart`, `test/app/l10n_plan25b_test.dart` (nuovo)

**Interfaces:**
- Produces:
  - `RequestStatus.awaitingRelease`, `'AwaitingRelease' => awaitingRelease` in `parse`.
  - `MediaRequest` in più (facoltativi nel costruttore): `DateTime? inCinemas`, `DateTime? digitalRelease`, `DateTime? nextAiring`, `int? nextSeasonNumber`, `int? nextEpisodeNumber`, letti con `jsonDate`/`jsonInt` (una data sbagliata non fa fallire l'elenco).
  - `requestStatusLabel` → `l.requestsStatusAwaitingRelease`; `requestStatusColor` → `WfColors.gold`.
  - `typedef RequestDatePart = ({String text, bool upcoming});` e `List<RequestDatePart> requestDateParts(MediaRequest request, DateTime now, AppLocalizations l)` in `request_labels.dart`, con le regole della decisione 9 e della spec §7.5:
    - **film:** niente per `available`, `declined`, `failed`; niente se `inCinemas` e `digitalRelease` sono null. Altrimenti, in ordine: "Al cinema dal {date}" se c'è `inCinemas` (`upcoming` se dopo oggi); poi `digitalRelease` nel futuro → "in digitale previsto il {date}" (`upcoming`), passato o oggi → "uscito in digitale il {date}", null → "in digitale: data non ancora nota". Date nel giorno UTC.
    - **serie:** con `nextAiring` → "Prossimo episodio: S{nn}E{nn} il {date}" se ci sono i due numeri, altrimenti "Prossimo episodio il {date}"; `upcoming` vero; giorno locale. Per ogni stato.
    - La prima parte con l'iniziale maiuscola. "Dopo oggi" = giorno di calendario successivo a quello di `now`.
    - `{date}` = `DateFormat.MMMMd(l.localeName)`, o `DateFormat.yMMMMd` se l'anno non è quello di `now`.
  - `RequestRow`: con almeno una parte, una terza riga sotto i dettagli (`Text.rich`, 13 px, `creamMuted`, le parti unite da " · ", quelle `upcoming` in `WfColors.gold`, una riga con ellissi).
  - `_openRequests` con `RequestStatus.awaitingRelease`.
  - Testi: le sette chiavi `requests*` della tabella in Global Constraints.

- [ ] **Step 1: test che falliscono** (`now` = 22 ottobre 2026 12:00 locale):
  - modello: `ReadsTheReleaseFields` (i cinque campi da JSON) e `AGarbledDateDoesNotBreakTheRow` (`"DigitalRelease": "boh"` → null, la riga c'è); `'AwaitingRelease'` → `awaitingRelease`.
  - `request_labels_test.dart`:
    - `AwaitingReleaseHasItsLabelAndGold`;
    - `AMovieWaitingForDigital`: cinema 25 set 2026, digitale 12 nov 2026 → `["Al cinema dal 25 settembre" (false), "in digitale previsto il 12 novembre" (true)]`;
    - `AMovieAlreadyOutDigitally`: digitale 20 ott 2026 → "uscito in digitale il 20 ottobre" (false);
    - `AMovieWithoutDigitalDate`: cinema 18 dic 2026, digitale null → `["Al cinema dal 18 dicembre" (true), "in digitale: data non ancora nota" (false)]`;
    - `OnlyDigitalStartsUppercase`: solo digitale 12 nov → "In digitale previsto il 12 novembre";
    - `NoDatesNoLine`: film approvato senza date → vuoto;
    - `FinishedMoviesHaveNoDates`: `available` con le date → vuoto;
    - `AnotherYearShowsTheYear`: digitale 31 mar 2027 → "… il 31 marzo 2027";
    - `AMovieDateIsTheUtcDay`: digitale `DateTime.utc(2026, 11, 12)` e lo stesso istante passato come `.toLocal()` danno entrambi "12 novembre" (il giorno viene da `toUtc()`);
    - `ASeriesShowsItsNextEpisode`: `nextAiring` 2 nov 2026 01:00 UTC, S1E4 → "Prossimo episodio: S01E04 il 2 novembre" (true); senza numeri → "Prossimo episodio il 2 novembre"; anche con stato `available`.
  - `request_row_test.dart`: `TheDatesLineShowsUnderTheDetails` (il testo delle parti si trova; nessuna riga in più senza date).
  - `home_rows_logic_test.dart`: `AwaitingReleaseIsAnOpenRequest`.
  - `l10n_plan25b_test.dart`: le sette chiavi in it e en con i segnaposti (forma di `l10n_plan24c_test.dart`).
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice**, `flutter gen-l10n` dopo gli ARB.
- [ ] **Step 4: i test passano**, `flutter analyze`, suite intera.
- [ ] **Step 5: commit** `git commit -m "feat(app): release dates and awaiting release on requests"`

### Task 3: logica del calendario

**Files:**
- Create: `lib/features/calendar/calendar_logic.dart`
- Test: `test/features/calendar/calendar_logic_test.dart`

**Interfaces:**
- Consumes: Task 1 (`UpcomingEpisode.onServer`, `UpcomingMovie.onServer`/`jellyfinItemId`, `CalendarPage`).
- Produces (tutto puro, senza widget):
  - `const calendarGridLength = 42;`
  - `DateTime calendarMonthOf(DateTime day)` → `DateTime(day.year, day.month)`.
  - `List<DateTime> gridDaysOf(DateTime month)`: 42 date locali a mezzanotte, dal lunedì della settimana del primo del mese; costruite con `DateTime(y, m, d + i)`, non sommando `Duration`.
  - `({DateTime start, DateTime end}) calendarPeriod(DateTime month)`: primo giorno della griglia e giorno dopo l'ultimo.
  - `DateTime dayKey(DateTime local)` → `DateTime(local.year, local.month, local.day)`.
  - `enum CalendarEntryKind { movie, series }`.
  - `class CalendarEntry { kind; String title; int count; bool onServer; String? posterUrl; int? tmdbId; String? jellyfinId; List<UpcomingEpisode> episodes; UpcomingMovie? movie; }` (const, campi `final`; `episodes` vuoto per un film).
  - `Map<DateTime, List<CalendarEntry>> entriesByDay(CalendarPage page)`: chiave `dayKey`. Episodi nel giorno locale di `airDate`; film nel giorno UTC di `digitalRelease` (`DateTime(u.year, u.month, u.day)` con `u = digitalRelease.toUtc()`). Raggruppamento della decisione 8 (`count` = somma di `lastEpisodeNumber - episodeNumber + 1`, o 1). In ogni giorno: prima i film, poi le serie, ognuno per titolo senza badare alle maiuscole. `posterUrl` = `posterUrl` (o `backdropUrl` se manca); `jellyfinId` = `jellyfinSeriesId` / `jellyfinItemId`; `tmdbId` dalla prima voce.
  - `String calendarEntryLabel(CalendarEntry entry, AppLocalizations l)`: il titolo per un film o una serie con `count` 1; `l.calendarSeriesCount(title, count)` altrimenti.
  - `String episodeCode(int season, int episode, {int? last})` → "S03E04" o "S03E01–E03".
  - `String? calendarEntryRoute(CalendarEntry entry, {required bool canRequest})`: la tabella della spec §7.4 (`/item/{id}` come `openItemById`, oppure `tmdbRoute(RequestMediaType.tv|movie, tmdbId)` solo con `canRequest`), altrimenti null.
  - `String calendarMonthTitle(DateTime month, AppLocalizations l)` ("Ottobre 2026") e `String calendarDayTitle(DateTime day, AppLocalizations l)` ("Mercoledì 22 ottobre"), con l'iniziale maiuscola.

- [ ] **Step 1: test che falliscono** (`setUpAll(() => initializeDateFormatting())`, `l = lookupAppLocalizations(const Locale('it'))`):
  - `GridDaysAreFortyTwoConsecutiveDaysFromMonday`: ottobre 2026 → primo 28 set 2026 (lunedì), ultimo 8 nov 2026; marzo 2026 (ora legale il 29) e ottobre 2026 (il 25): 42 date con giorni consecutivi, tutte a mezzanotte; febbraio 2026 (comincia di domenica) → primo 26 gen 2026; giugno 2026 (comincia di lunedì) → primo 1 giu.
  - `ThePeriodEndsTheDayAfterTheGrid`: ottobre 2026 → `start` 28 set, `end` 9 nov.
  - `EpisodesUseTheLocalDayMoviesTheUtcDay`: un episodio `2026-10-23T01:00:00Z` sta nel giorno di `airDate.toLocal()`; un film `DateTime.utc(2026, 11, 12)`, anche passato come `.toLocal()`, sta nel 12 novembre (la chiave viene dal giorno UTC).
  - `EpisodesOfOneSeriesInADayAreOneEntry`: Andor S3E1–E3 (un blocco) e S3E4 lo stesso giorno → una voce con `count` 4; `onServer` vero solo se lo sono tutti; un'altra serie resta a parte.
  - `MoviesComeFirstThenSeriesByTitle`: ordine film (A, B) poi serie (a, B) senza badare alle maiuscole.
  - `LabelsAndCodes`: `calendarEntryLabel` → "Andor ×4" e "Weapons"; `episodeCode(3, 4)` → "S03E04", `episodeCode(3, 1, last: 3)` → "S03E01–E03".
  - `RoutesFollowTheTable`: serie con id → `/item/abc`; serie senza id con `tmdbId` e `canRequest` → `/tmdb/tv/123`; senza `canRequest` → null; film con id → `/item/def`; film senza id → `/tmdb/movie/456` con `canRequest`, null senza.
  - `TitlesAreCapitalized`: "Ottobre 2026", "Giovedì 22 ottobre" (per il 22 ottobre 2026, che è un giovedì).
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano**, `flutter analyze`, suite intera.
- [ ] **Step 5: commit** `git commit -m "feat(app): calendar grid and day logic"`

### Task 4: griglia del mese e finestra del giorno

**Files:**
- Create: `lib/features/calendar/calendar_month_grid.dart`, `lib/features/calendar/calendar_day_dialog.dart`
- Modify: `lib/app/theme.dart` (`WfColors.calendarMovie`, `WfColors.calendarSeries`, decisione 11), `l10n/app_it.arb`, `l10n/app_en.arb`, `test/app/l10n_plan25b_test.dart`
- Test: `test/features/calendar/calendar_month_grid_test.dart`, `test/features/calendar/calendar_day_dialog_test.dart`

**Interfaces:**
- Consumes: Task 3.
- Produces:
  - `class CalendarMonthGrid extends StatefulWidget { const CalendarMonthGrid({super.key, required this.month, required this.today, required this.entries, required this.onOpenDay, required this.onOpenEntry}); final DateTime month; final DateTime today; final Map<DateTime, List<CalendarEntry>> entries; final void Function(DateTime day) onOpenDay; final void Function(CalendarEntry entry) onOpenEntry; static const compactCellWidth = 96.0; static const dayRowHeight = 22.0; static const entryHeight = 20.0; static const minEntries = 2; }`.
    - Intestazioni dei giorni da lunedì: `DateFormat.E(l.localeName)` dei giorni 28 set – 4 ott 2026 (lun–dom), in minuscolo come li dà `intl` ("lun", "mar", …).
    - Casella (chiave `Key('calendar-day-yyyy-MM-dd')`): numero del giorno (spento fuori dal mese); bordo oro 1 px per `today`; voci come la decisione 7, ognuna (chiave `Key('calendar-entry-…')` con giorno e indice) con fondo `calendarMovie`/`calendarSeries`, icona Lucide film/serie di 12 px, testo `calendarEntryLabel` (11 px, una riga, ellissi) e un puntino `WfColors.online` per `onServer`; l'ultima riga "+{n}" (`l.calendarMore`) quando non ci stanno.
    - Clic su una voce → `onOpenEntry`; clic sul resto della casella o su "+{n}" → `onOpenDay`.
    - Stretta (decisione 6): numero e puntini.
    - Ogni casella ha `Semantics(button: true, label: l.calendarDayReleases(calendarDayTitle(day, l), n))` (con n = 0 resta il titolo del giorno); ogni voce `Semantics(label: "{Film|Serie}, {etichetta}[, già sul server]")`.
    - Tastiera (decisione 5): un `Focus` sulla griglia; il giorno scelto ha un bordo `cream` 2 px quando la griglia ha il fuoco; frecce ±1/±7 dentro i 42 giorni; Invio → `onOpenDay(giorno scelto)`.
  - `Future<void> showCalendarDay(BuildContext context, {required DateTime day, required List<CalendarEntry> entries, required void Function(CalendarEntry entry) onOpenEntry})` in `calendar_day_dialog.dart`, con `showWfDialog`:
    - titolo `calendarDayTitle(day, l)` (`WfText.display(24)`);
    - una riga per voce (per una serie raggruppata, una riga per episodio o blocco): locandina 34×51 (`WfImage`, `ImageRef(posterUrl)`), nome, sotto "Film · in digitale" oppure "{episodeCode} · {episodeTitle}" / "{episodeCode}" e l'ora locale (`DateFormat.Hm`), a destra "Sul server" in `WfColors.online` per `onServer`;
    - clic su una riga → chiude la finestra, poi `onOpenEntry(voce)`;
    - la griglia non chiama `onOpenDay` per un giorno senza voci, quindi la finestra ha sempre almeno una riga.
  - Testi della tabella: `calendarMore`, `calendarSeriesCount`, `calendarMovieDigital`, `calendarOnServer`, `calendarDayReleases`, `calendarAlreadyOnServer` (aggiunti al test l10n).

- [ ] **Step 1: test che falliscono** (`pumpApp` con `surfaceSize` 1440×900, `withClock` dove serve):
  - `TheGridHasFortyTwoDaysFromMonday`: 42 chiavi `calendar-day-…`, la prima `2026-09-28`; le intestazioni cominciano da "lun".
  - `TodayHasAGoldBorder` (cerca il `BoxDecoration` della casella del 22 ottobre).
  - `EntriesShowLabelsAndTheOnServerDot`: una serie ×3 e un film sul server nello stesso giorno → "Andor ×3", "Weapons" e un puntino.
  - `TooManyEntriesBecomePlusN`: 8 film in un giorno con l'altezza di prova → si vede "+{n}" e il numero di voci mostrate è quello della decisione 7.
  - `TappingAnEntryOpensItTappingTheDayOpensTheList`: clic su una voce → `onOpenEntry` con quella voce; clic su "+n" → `onOpenDay` con quel giorno.
  - `NarrowCellsShowDots`: `surfaceSize` 600×900 → nessun testo di voce, i puntini sì.
  - `ArrowsAndEnterOpenTheChosenDay`: fuoco sulla griglia, freccia giù e freccia destra dal 22 ottobre → Invio apre il 30 ottobre.
  - `calendar_day_dialog_test.dart`: `TheDayListShowsEveryEpisodeAndTime` (titolo "Giovedì 22 ottobre", "S03E01–E03", "S03E04 · Il ponte", l'ora, "Sul server"); `TappingARowClosesAndOpens` (la finestra si chiude e `onOpenEntry` riceve la voce).
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice**, `flutter gen-l10n` dopo gli ARB.
- [ ] **Step 4: i test passano**, `flutter analyze`, suite intera.
- [ ] **Step 5: commit** `git commit -m "feat(app): calendar month grid and day list"`

### Task 5: pagina Calendario, rotta e voce nella barra

**Files:**
- Create: `lib/features/calendar/calendar_providers.dart`, `lib/features/calendar/calendar_navigation.dart`, `lib/features/calendar/calendar_screen.dart`
- Modify: `lib/app/router.dart`, `lib/app/app_shell.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`, `test/app/l10n_plan25b_test.dart`
- Test: `test/features/calendar/calendar_screen_test.dart`, `test/features/calendar/calendar_navigation_test.dart`, `test/app/app_shell_test.dart`, `test/app/router_test.dart`

**Interfaces:**
- Consumes: Task 1 (`HomeApi.calendar`, `SocialFeatures.calendar`), Task 3, Task 4.
- Produces:
  - `calendar_navigation.dart`: `DateTime? parseCalendarMonth(String? raw)` (`YYYY-MM`, mese 1–12, altrimenti null); `String calendarRoute(DateTime month)` → `/calendar?month=2026-10`; `void openCalendarMonth(BuildContext context, DateTime month)` con `context.go`.
  - `calendar_providers.dart`:
    - `calendarAvailableProvider = Provider<bool>` (`socialAvailabilityProvider.select((f) => f.calendar)`); `calendarGoneProvider` (`f.known && !f.calendar`), come quelli delle richieste;
    - `calendarPageProvider = FutureProvider.autoDispose.family<CalendarPage, DateTime>` (chiave: il mese): prima `ref.watch` del cancello (senza funzione → `const CalendarPage()`), poi `ref.watch(currentUserIdProvider)`, poi `ref.watch(homeApiProvider).calendar(period.start, period.end)` con `calendarPeriod(month)`. Errori `UpcomingError` nel log come `_logUpcoming` (solo `error.wire`).
  - `class CalendarScreen extends ConsumerWidget { const CalendarScreen({super.key, this.month}); final DateTime? month; }` (null = mese di oggi, da `clock.now()`):
    - in alto `Text(l.navCalendar.toUpperCase(), style: WfText.display(40))` con lo stesso padding della pagina Richieste; sotto una riga con `IconButton` ‹ (`tooltip: l.calendarPreviousMonth`, chiave `Key('calendar-previous')`), `calendarMonthTitle` (`WfText.display(28)`), › (`Key('calendar-next')`, `l.calendarNextMonth`) e `TextButton` "Oggi" (`Key('calendar-today')`, spento sul mese di oggi); i tre vanno a `calendarRoute`;
    - con `calendarGoneProvider` → torna a `/home` come la pagina Richieste;
    - caricamento → `LoadingView`; `ApiException` → `ErrorView` con `ref.invalidate(calendarPageProvider(month))`;
    - errori del plugin (decisione 3): un servizio è **spento** se il suo errore è `notConfigured`, **in errore** se è `unauthorized` o `unreachable`. Se tutti i servizi non spenti sono in errore (e almeno uno lo è) → `ErrorView` con `Riprova` (errore `ServerErrorException(null)` per il testo generico). Altrimenti, sopra la griglia, una riga per servizio in errore (`l.calendarSeriesUnavailable` / `l.calendarMoviesUnavailable`, più " · " e il motivo per l'admin, decisione 4, con un'icona `circleAlert` oro);
    - la griglia (`CalendarMonthGrid`) con `entriesByDay(page)`, `today` = `dayKey(clock.now())`; `onOpenDay` → `showCalendarDay` solo se il giorno ha voci; `onOpenEntry` → `calendarEntryRoute(entry, canRequest: ref.watch(requestsAvailableProvider))` e `context.push` se non è null;
    - se nessun giorno **del mese** ha voci: sotto la griglia `l.calendarEmpty` in `creamMuted`.
  - `router.dart`: `GoRoute(path: '/calendar', pageBuilder: (context, state) => shellPage(context, state, CalendarScreen(key: ValueKey(state.uri.toString()), month: parseCalendarMonth(state.uri.queryParameters['month'])), underBar: true))`, accanto a `/requests`.
  - `app_shell.dart`: `if (ref.watch(calendarAvailableProvider)) (label: l.navCalendar, route: '/calendar', icon: null),` tra Richieste e Cerca.
  - Testi: `navCalendar`, `calendarToday`, `calendarPreviousMonth`, `calendarNextMonth`, `calendarEmpty`, `calendarSeriesUnavailable`, `calendarMoviesUnavailable`.

- [ ] **Step 1: test che falliscono** (`withClock` al 22 ottobre 2026 12:00; GoRouter locale come `requests_screen_test.dart`, con rotte finte `/home`, `/item/:id`, `/tmdb/:type/:tmdbId`; `FakeHomeApi`; `FakeSocialAvailability(SocialFeatures(calendar: true, requests: true))`):
  - `calendar_navigation_test.dart`: `"2026-10"` → ottobre 2026; `"2026-13"`, `"2026-1"`, `"boh"`, null → null; `calendarRoute(DateTime(2026, 3))` → `/calendar?month=2026-03`.
  - `ShowsTheMonthOfTodayAndAsksItsPeriod`: senza `month` → "Ottobre 2026"; `FakeHomeApi.calendarCalls` = `(28 set, 9 nov)`.
  - `ArrowsAndTodayChangeTheAddress`: clic su `calendar-next` → indirizzo `/calendar?month=2026-11`; poi `calendar-today` → `/calendar?month=2026-10`; "Oggi" spento su ottobre.
  - `TappingAnEntryOpensItsPage`: una serie con `jellyfinSeriesId` → "scheda abc" (rotta finta `/item/:id`); un film senza id → `/tmdb/movie/456`.
  - `OneServiceFailingShowsALine`: `seriesError` `unreachable` → "Le serie non si possono caricare ora" e la griglia con i film; da admin anche il motivo.
  - `NotConfiguredIsSilent`: `moviesError` `notConfigured` → nessuna riga sui film, nessun errore.
  - `EveryServiceFailingIsAnError`: `seriesError` `unreachable` e `moviesError` `unauthorized` → `ErrorView`; "Riprova" rilegge (due chiamate).
  - `AnEmptyMonthSaysSo`: nessuna voce → "Nessuna uscita in questo mese".
  - `GoesHomeWhenTheFeatureDisappears`: `FakeSocialAvailability.set(SocialFeatures(known: true))` → indirizzo `/home`.
  - `app_shell_test.dart`: `voce "Calendario" solo con la funzione calendar` (con `calendar: true` c'è `Key('nav-/calendar')` dopo `nav-/requests` e prima di Cerca; senza no).
  - `router_test.dart`: `/calendar?month=2026-11` costruisce `CalendarScreen` con novembre 2026.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice**, `flutter gen-l10n` dopo gli ARB.
- [ ] **Step 4: i test passano**, `flutter analyze`, suite intera.
- [ ] **Step 5: commit** `git commit -m "feat(app): calendar page, route and navigation entry"`

### Task 6: versione 0.20.0, spec e build

**Files:**
- Modify: `pubspec.yaml`, `docs/RELEASING.md`, `docs/superpowers/specs/2026-10-22-wonderflix-calendario-uscite-design.md`

- [ ] **Step 1:** `pubspec.yaml` → `version: 0.20.0`. In `docs/RELEASING.md`, dopo la voce degli strumenti admin dei metadati, la voce "Calendario delle uscite (app 0.20.0, plugin 1.13.0)" con i passi della spec §9.3.
- [ ] **Step 2: la spec**, controllando ogni frase sul codice:
  - **Stato:** "piano 25b realizzato (`docs/superpowers/plans/2026-10-22-wonderflix-25b-calendario-app.md`)";
  - **§7.2:** tastiera (decisione 5), caselle strette (decisione 6), quante voci (decisione 7), raggruppamento (decisione 8), colori (decisione 11);
  - **§7.5:** riga delle date senza date (decisione 9);
  - **§7.6:** `NotConfigured` silenzioso e il motivo per l'admin (decisioni 3, 4); campi mancanti (decisione 2);
  - **§7.1:** chiave dall'indirizzo (decisione 10);
  - ogni altra differenza venuta fuori, con il motivo.
- [ ] **Step 3:** `flutter analyze` e la suite intera verdi, poi la build esatta: copia `config/wonderflix.json` dal checkout principale in `config/` del worktree, poi `flutter build windows --release --dart-define-from-file=config/wonderflix.json`. Annota il percorso dell'exe nel resoconto.
- [ ] **Step 4: commit** `git commit -m "chore: app 0.20.0 and spec aligned with plan 25b"`

### Task 7: STOP — prova a mano con l'utente

Il subagent si ferma dopo il Task 6. L'orchestratore fa la review finale e i ritocchi, poi **aspetta l'utente** prima di lanciare l'app.

Prova (spec §9.3), con il plugin 1.13.0 già sul server:
- il mese di oggi e quello dopo, con serie e film; un'uscita già scaricata con il puntino verde; clic su una serie della libreria e su un film da richiedere; "+n" e l'elenco del giorno; le frecce e "Oggi";
- pagina Richieste: un film approvato non ancora uscito in digitale ("In attesa dell'uscita" con le date), una serie con il prossimo episodio;
- la finestra stretta (caselle con i puntini).

Con l'ok dell'utente: merge su `main`, push, release del plugin (tag `watch-party-plugin-v1.13.0`, manifest, Catalog) e dell'app (tag `v0.20.0`, non obbligatoria, note in italiano nella bozza: memoria `release-notes`), idea 16 di `docs/IDEE.md` tra le fatte, spec "Stato: realizzata"; pubblicazione dopo l'ok dell'utente.
