# Scarica subito Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trovare un titolo nella scheda Download e far passare davanti tutta la sua serie o il film, anche se è stato appena aggiunto.

**Architecture:** Il plugin aggiunge `RushAt` alle voci (persistito) e un segnale in memoria che ferma il giro dopo la ricerca in corso, poi ne fa ripartire uno che comincia dalle voci con la precedenza. L'app filtra in locale e raggruppa le righe per `SeriesId`.

**Tech Stack:** .NET 9 + xUnit (plugin), Flutter 3.47.5 + Riverpod 3 (app).

**Spec:** `docs/superpowers/specs/2026-11-10-scarica-subito-design.md`. Leggila per intero prima di iniziare.

## Global Constraints

- Lavora solo nel worktree `.claude/worktrees/scarica-subito`, branch `feat/scarica-subito`.
- Commit in italiano, senza `Co-Authored-By`, senza "Generated with Claude Code", senza le parole `closes`, `fixes`, `resolves`. Niente push.
- Vietato uccidere processi per nome d'immagine (`taskkill /IM`, `pkill`).
- Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Build release dell'app, se serve: da `app/`, `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- Plugin compilato contro Jellyfin 10.11.0. DTO: i campi nullable sempre presenti usano `[property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]`.
- `dart format` solo sulle righe che cambi. Flutter può riscrivere `app/windows/flutter/generated_plugin*` con soli fine riga: `git checkout --` prima di committare.
- Una ricerca alla volta resta la regola: nessun parallelismo verso Sonarr/Radarr.
- Testi nuovi in `app/l10n/app_it.arb` e `app_en.arb`, poi `flutter gen-l10n`.

## Review Focus

1. **Telecomando sul campo:** su TV il D-pad non deve restare intrappolato nel `TextField`. Test nel Task 4.
2. **Ricaricamenti con il campo pieno:** il poll ogni 5 o 60 secondi non cancella il testo e non toglie il focus. Test nel Task 4.
3. **Titoli con accenti e maiuscole:** "pokemon" trova "Pokémon". Test nel Task 3.
4. **Pressione senza effetto:** un `Rush` su una voce senza righe da anticipare non ferma il giro. Test nel Task 1.
5. **Voce con `SeriesId` 0 (libro vecchio):** il `Rush` tocca solo lei, non tutte le voci con 0. Test nel Task 1.

---

### Task 1: Plugin, precedenza e giro

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadBook.cs` (`DownloadEntry`)
- Modify: `.../Downloads/DownloadService.cs`, `DownloadService.Admin.cs`, `DownloadService.Search.cs`, `DownloadService.Seasons.cs`
- Modify: `.../Protocol/DownloadsDtos.cs`, `.../Api/DownloadsController.cs`
- Test (nuovo): `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/DownloadServiceRushTests.cs`; aggiungi a `DownloadsControllerTests.cs`

**Interfaces:**
- Produces: `DownloadEntry.RushAt` (`DateTimeOffset?`); `public bool DownloadService.Rush(string key)`; `POST Downloads/Rush` con `KeyRequest` (202 o 400); `DownloadItemDto` con in coda `SeriesId` (`int?`, Never, null per i film e per `SeriesId` 0), `CanRush` (`bool`, default false), `Rush` (`bool`, default false); `private bool _rushRequested`, azzerato in testa a `RunCycleAsync`.

- [ ] **Step 1: Scrivi i test che falliscono** in `DownloadServiceRushTests`. Riusa l'impalcatura di `DownloadServiceManualPriorityTests` (cancelli sulle release, `_nudges`, `Call`, `Finish`). `Episode(...)` ha `SeriesId = 7`: per una seconda serie cambia il campo sull'oggetto.

| Test | Scenario | Asserzione |
|---|---|---|
| `RushBringsTheWholeSeriesToTheFront` | film e 2 episodi della serie 7 già in voce, scaduti prima del `Rush("episode:34")` | le prime 2 `SearchReleaseCalls` sono Sonarr, poi Radarr |
| `RushOnAMovieTouchesOnlyThatMovie` | 2 film | solo `movie:1` ha `Rush == true` in overview |
| `RushSkipsUpgradeWatchAndImportBlocked` | righe della stessa serie in quegli stati | `CanRush == false`, `Rush == false`; `SearchNow` resta com'è |
| `RushIncludesSnoozedAndNeedsYouRows` | | `Rush == true` |
| `RushOfAnUnknownKeyIsFalse` | | `Assert.False(_service.Rush("movie:999"))`, `Assert.False(_service.Rush("x"))` |
| `RushWithNothingToRushDoesNotStopTheCycle` | giro in corso, chiave di una voce in `UpgradeWatch` | il giro fa tutte le sue ricerche, `_nudges == 0` |
| `RushOfAnEntryWithoutSeriesIdTouchesOnlyIt` | due episodi con `SeriesId = 0` nel libro | solo uno con `Rush == true` |
| `ARunningCycleStopsAfterTheSearchInFlight` | 3 film, `Rush` su `movie:3` mentre è aperta la ricerca 0 | finita la 0, `(await cycle).Searched == 1`, `_nudges >= 1` |
| `TheNextCycleStartsFromTheRushedRow` | dopo il precedente | `Call(1).Query == "movieId=3"` |
| `TheCapOfTenDoesNotApplyToRushedRows` | 12 voci con la precedenza e 3 senza | `Searched == 12`, le 3 senza non cercate |
| `RushAtIsClearedAfterTheSearchWhateverTheOutcome` | nessuna release; ricerca che lancia | `Rush == false`, `NextSearchAt` ricalcolato |
| `RushAtIsClearedWhenTheRowLeavesTheRushableStates` | riga con la precedenza che passa a `Downloading` | dopo un giro `RushAt` è null |
| `ManualSearchesStillComeFirst` | `StartSearch` in corso e `Rush` | nessuna ricerca automatica finché la manuale non finisce, poi parte la riga con la precedenza |
| `RushedRowsGoInSeasonOrderWithinARush` | "Stagione 2", "Stagione 10" | la 2 prima della 10 |
| `SplittingARushedSeasonKeepsThePrecedence` | stagione divisa (modello: `DownloadServiceSeasonTests.AHeavyPackSplitsIntoEpisodes`) | episodi con `Rush == true`, giro fermato, `_nudges >= 1` |
| `GroupingRushedEpisodesKeepsTheOldestRushAt` | episodi con la precedenza che diventano stagione intera | la stagione ha `Rush == true` |
| `RushAtSurvivesARestart` | nuovo `DownloadService` sullo stesso file | la riga parte prima |

In `DownloadsControllerTests`: `Status(_controller.Rush(new KeyRequest { Key = "movie:12" }))` è 400 senza voce e 202 con la voce; 400 con `new KeyRequest()`.

- [ ] **Step 2: Verifica che falliscano**

Run (da `plugin/`): `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~DownloadServiceRushTests"`
Expected: errore di compilazione, `Rush` non esiste.

- [ ] **Step 3: Implementa.** Tutto sotto `_lock`, come il codice vicino.

- `CanRush(entry)`: `entry.State != DownloadStates.UpgradeWatch && SearchesByState(entry)`.
- `Rush`: come `SearchNow` per il parsing. Righe: la voce stessa se è un film o ha `SeriesId == 0`, altrimenti le voci con lo stesso `SeriesId` e `Kind` diverso da film. Su quelle con `CanRush`: `RushAt = NextSearchAt = now`. Se ne ha toccata almeno una: `_rushRequested = true`, `store.Save(Book)`, e dopo il lock `Nudge()`. Ritorna true anche se non ne ha toccata nessuna.
- `SearchDueAsync`, nel primo `lock`: `RushAt = null` sulle voci con `RushAt` e senza `CanRush`. Elenco `due` ordinato con questo criterio, e `rushed` = chiavi con `RushAt`:

```csharp
.OrderBy(e => e.RushAt ?? DateTimeOffset.MaxValue)
.ThenBy(e => e.RushAt is null ? e.NextSearchAt : null)
// Stessa serie: la lunghezza prima, così "Stagione 2" viene prima di "Stagione 10".
.ThenBy(e => e.RushAt is null ? 0 : e.Title.Length)
.ThenBy(e => e.RushAt is null ? "" : e.Title, StringComparer.Ordinal)
```

- Limite: `if (searched >= MaxSearchesPerCycle && !rushed.Contains(key)) break;`.
- Stop: nel blocco `lock` con `ManualSearching()`, dopo quel controllo, `if (_rushRequested) break;`. Non azzerare il flag qui: serve vero anche al Task 2.
- Nel `finally` della ricerca, sotto il lock esistente: `if (Book.Get(item.Key) is { } done) done.RushAt = null;`.
- `Split`: legge `entry.RushAt` prima del `Book.Remove`. Per ogni episodio `var e = Book.Get(k) ?? Create(...)`, e se c'era la precedenza `e.RushAt = rushAt; e.NextSearchAt = now;`. Se c'era: `_rushRequested = true` e `Nudge()` dopo il lock. Senza precedenza il comportamento resta identico (`Create` solo se manca).
- `GroupSeasons`: prima di togliere gli episodi `var rushAt = episodeKeys.Select(k => Book.Get(k)?.RushAt).Min();`, poi `Create(season.Title, now).RushAt = rushAt;`.
- `ItemDto`: `SeriesId` (null se 0), `CanRush(e)`, `e.RushAt is not null`.

- [ ] **Step 4: Verifica.** Stesso comando, poi tutta la suite senza filtro. Expected: PASS. Rilancia prima di indagare se falliscono solo `SubtitleServiceTests.AFailedDownloadIsFailed`, `ArrClientTests.ASlowSearchUsesTheReleaseSearchTimeout` o `DownloadAlertsTests`.

- [ ] **Step 5: Commit** `feat(plugin): Scarica subito porta davanti una serie o un film`

### Task 2: Plugin, Aggiorna ora e ritardo breve

**Files:**
- Modify: `.../Downloads/DownloadService.cs`, `DownloadService.Admin.cs`, `.../DownloadsHostedService.cs`, `.../Protocol/DownloadsDtos.cs`, `.../Api/DownloadsController.cs`
- Test: `DownloadServiceRushTests.cs`, `DownloadsHostedServiceTests.cs`, `DownloadsControllerTests.cs`

**Interfaces:**
- Consumes: `_rushRequested` e `Rush` del Task 1.
- Produces: `public void DownloadService.Refresh()`; `POST Downloads/Refresh` (202); `DownloadsOverviewDto.RefreshPending` (`bool`, default false, ultimo parametro); `public bool DownloadService.UrgentCycleWanted`; `public static readonly TimeSpan DownloadService.UrgentNudgeDelay = TimeSpan.FromSeconds(5)`.

- [ ] **Step 1: Scrivi i test che falliscono**

| Test | Scenario | Asserzione |
|---|---|---|
| `RefreshReadsTheListWithoutSearching` | film nuovo e `Refresh()`, poi `Cycle()` | `Searched == 0`, voce creata, `(await Overview).RefreshPending == false` |
| `RefreshPendingIsTrueUntilTheListIsRead` | dopo `Refresh()`, prima del giro | `RefreshPending == true` |
| `RefreshDuringACycleStopsItAndReadsNext` | `Refresh()` a ricerca aperta | `Searched == 1`, `RefreshPending` vero fino al giro dopo, che ha `Searched == 0` |
| `ARefreshCycleSearchesIfARowIsRushed` | `Refresh()` e voce con `RushAt` | la riga viene cercata |
| `TheCycleAfterARefreshSearchesNormally` | | `Cycle()` successivo con `Searched > 0` |

In `DownloadsHostedServiceTests` (i nomi di metodo sono esatti):
- `AnUrgentNudgeRunsACycleWithinSeconds`: `_downloads.Refresh()`, `Advance(UrgentNudgeDelay)`, `_cycles == 1`.
- `AnUrgentNudgeShortensAPendingNormalOne`: `Nudge()`, poi `Refresh()`, `Advance(UrgentNudgeDelay)`, `_cycles == 1`.
- `ACycleStoppedByARushRestartsWithinSeconds`: giro tenuto aperto con `Hold()`, `Refresh()`, chiusura, `Advance(UrgentNudgeDelay)`, due giri.
- `ANudgeRunsACycleAfterAMinute` resta invariato.

Controller: `Refresh()` è 202.

- [ ] **Step 2: Verifica che falliscano**, con il comando del Task 1 e filtro `FullyQualifiedName~DownloadServiceRushTests|FullyQualifiedName~DownloadsHostedServiceTests`.

- [ ] **Step 3: Implementa.**

- `Refresh`: sotto il lock `_rushRequested = _refreshPending = true`, poi `Nudge()`.
- `UrgentCycleWanted`: legge `_rushRequested` sotto il lock.
- `RunCycleAsync`: in testa, sotto il lock, `_rushRequested = false; var refreshing = _refreshPending;`. Alla fine del lock di `Apply`, `if (refreshing) _refreshPending = false;`. Una `Refresh` arrivata durante le letture resta così per il giro dopo.
- Prima di `SearchDueAsync`: si cerca se `enabled` e non (`refreshing` e nessuna voce con `RushAt`).
- `DownloadsHostedService.ScheduleNudge`:

```csharp
var urgent = downloads.UrgentCycleWanted;
if (Interlocked.CompareExchange(ref _nudgeScheduled, 1, 0) == 0 || urgent)
{
    // Change su un timer già armato lo sposta: l'urgente accorcia un nudge normale.
    _nudgeTimer?.Change(urgent ? DownloadService.UrgentNudgeDelay : DownloadService.NudgeDelay, Timeout.InfiniteTimeSpan);
}
```

Mantieni il `try/catch ObjectDisposedException` esistente.

- [ ] **Step 4: Verifica.** Filtro, poi suite intera. Expected: PASS.

- [ ] **Step 5: Commit** `feat(plugin): Aggiorna ora rilegge Sonarr e Radarr senza cercare`

### Task 3: App, contratto e logica del filtro

**Files:**
- Modify: `app/lib/core/downloads/download_models.dart`, `downloads_api.dart`, `app/test/support/download_fakes.dart`
- Create: `app/lib/features/downloads/download_filter.dart`
- Test: `app/test/core/downloads/downloads_api_test.dart`; nuovo `app/test/features/downloads/download_filter_test.dart`

**Interfaces:**
- Produces:
  - `DownloadItem.seriesId` (`int?`), `.canRush` (`bool`, default false), `.rush` (`bool`, default false), letti da `SeriesId`, `CanRush`, `Rush`.
  - `DownloadsOverview.refreshPending` (`bool?`): null con plugin vecchio.
  - `Future<void> DownloadsApi.rush(String key)`, `Future<void> DownloadsApi.refresh()`, con `quietStatuses: _quiet`; nel fake `_action('rush $key')`, `_action('refresh')`.
  - In `download_filter.dart`: `bool titleMatches(String title, String query)`; classe `DownloadRushGroup` con `key` (`String`, la riga da mandare a `rush`), `title`, `posterUrl`, `missing` (`int`), `canPress` (`bool`), `pending` (`bool`); `List<DownloadRushGroup> rushGroups(List<DownloadItem> waiting, String query)`.

- [ ] **Step 1: Scrivi i test che falliscono**

```dart
expect(titleMatches('Pokémon · S01E02', 'pokemon'), isTrue);
expect(titleMatches('Dune (2021)', '  DUNE '), isTrue);
expect(titleMatches('Dune (2021)', 'arrival'), isFalse);
```

`rushGroups`, un test per ognuno:
- 3 righe `seriesId: 7` dà 1 gruppo con `title == 'Serie'` e `missing == 3`.
- Titolo `'A · B · S01E01'` dà `title == 'A · B'`.
- Serie con una sola riga che corrisponde al filtro: `missing` conta tutte le righe del gruppo.
- Tutte in `needsYou` con `canRush`: `canPress == true`.
- Solo in download, nessun `canRush` né `rush`: nessun gruppo.
- Tutte `canRush: true, rush: true`: `pending == true`, `canPress == false`.
- Film: gruppo singolo con il titolo intero, anche con ` · ` nel titolo.
- Due serie omonime con `seriesId` diversi: 2 gruppi.
- `key` è una riga con `canRush` del gruppo.

API: `rush('k')` fa `POST /WonderFlixWatchParty/Downloads/Rush` con `{'Key': 'k'}`; `refresh()` fa `POST .../Refresh`. Modelli: JSON senza i campi nuovi dà `canRush == false`, `seriesId == null`, `refreshPending == null`.

- [ ] **Step 2: Verifica che falliscano**

Run (da `app/`): `flutter test test/features/downloads/download_filter_test.dart test/core/downloads/downloads_api_test.dart`
Expected: errore di compilazione.

- [ ] **Step 3: Implementa.** `titleMatches`: minuscole, trim della query, una mappa `const` dei caratteri latini accentati (à→a, é→e, ō→o, ñ→n e simili) applicata a entrambi i testi. Query vuota: true. Il nome della serie è il titolo prima di `lastIndexOf(' · ')`, solo per i non film. Gruppi nell'ordine della prima riga incontrata, senza `sort` (Dart non è stabile).

- [ ] **Step 4: Verifica.** Stesso comando. Expected: PASS.

- [ ] **Step 5: Commit** `feat(app): modello e filtro di Scarica subito`

### Task 4: App, il campo e le righe nella scheda

**Files:**
- Modify: `app/lib/features/downloads/downloads_tab.dart`, `download_rows.dart`, `app/l10n/app_it.arb`, `app_en.arb`
- Test: `app/test/features/downloads/downloads_tab_test.dart`

**Interfaces:**
- Consumes: Task 3 per intero.
- Produces: `DownloadRushRow` in `download_rows.dart` (`group`, `onRush: VoidCallback?`, costruita su `RowShell`). Chiavi: `ValueKey('downloads-filter')` sul campo, `ValueKey('rush-${group.key}')` sulla riga.

Testi: `downloadsFilterHint` "Cerca nella lista" / "Search the list"; `downloadsRushNow` "Scarica subito" / "Download now"; `downloadsRushMissing` "{count} mancanti" / "{count} missing"; `downloadsRushPending` "In testa alla coda" / "At the front of the queue"; `downloadsNotListed` "Non è in lista" / "Not in the list"; `downloadsRefreshNow` "Aggiorna ora" / "Refresh now"; `downloadsRefreshing` "Aggiornamento…" / "Refreshing…".

- [ ] **Step 1: Scrivi i test che falliscono** in `downloads_tab_test.dart`. Estendi `_item` con `seriesId`, `title`, `canRush`, `rush`. Per il testo usa `tester.enterText(find.byKey(const ValueKey('downloads-filter')), ...)`.

| Test | Asserzione |
|---|---|
| `il filtro restringe ogni sezione e nasconde le vuote` | intestazione "Da ripassare" assente se non ha risultati |
| `il filtro apre le sezioni chiuse senza salvarle` | righe visibili; `prefs.getStringList('downloads.collapsedSections')` invariata |
| `il filtro ignora i 7 giorni e la paginazione` | scelta di 30 giorni fa e riga oltre la cinquantesima trovate |
| `il ricaricamento non tocca il testo né il focus` | dopo `pump(_slowPoll)`, stesso testo e `hasFocus` |
| `il campo si svuota con la X` | lista completa |
| `Scarica subito chiama rush e rilegge` | `api.calls` contiene `'rush episode:1', 'overview'` |
| `niente pulsante con i download spenti` | `enabled: false`: niente testo `downloadsRushNow` |
| `con tutte le righe davanti si legge In testa alla coda` | niente pulsante |
| `Non è in lista compare anche con righe vecchie trovate` | scelta che corrisponde e nessuna riga `waiting`: testo presente, pulsante `downloadsRefreshNow` presente |
| `Aggiorna ora chiama refresh` | `api.calls` contiene `'refresh'` |
| `con RefreshPending si legge Aggiornamento e si rilegge ogni 5 secondi` | testo presente, nessun pulsante, `overview` chiamata di nuovo dopo `pump(5 s)` |
| `con un plugin vecchio niente Aggiorna ora` | `refreshPending: null`: testo assente |
| `su TV il campo è una tappa del telecomando` | `pumpTab(tv: true)`: il campo sta dentro un `TvFocusable`; un D-pad Giù dal campo porta al controllo successivo, non resta sul campo |

- [ ] **Step 2: Verifica che falliscano**

Run (da `app/`): `flutter gen-l10n && flutter test test/features/downloads/downloads_tab_test.dart`
Expected: FAIL. Niente `pumpAndSettle` con una barra indeterminata: `pumpTab(settle: false)`.

- [ ] **Step 3: Implementa** in `_DownloadsTabState`.

- `_filter = TextEditingController()`, liberato in `dispose`, `setState` su ogni modifica. `q = _filter.text.trim()`, `filtering = q.isNotEmpty`.
- Campo come figlio del `ListView`, subito dopo il pulsante di aggiornamento, sempre presente. Su TV copia lo schema di `_searchField` in `app/lib/features/search/search_screen.dart` (`TvFocusable` come unica tappa, `_typing`, `FocusNode` tuo).
- Con `filtering`: ogni sezione usa le righe filtrate da `titleMatches`, `recent` parte da `overview.recent`, `review.take` senza limite, niente `_MoreButton`, niente sezioni vuote o `AdminEmptyText`. Sezione aperta = `filtering || !_collapsed.contains(id)`. Senza filtro il comportamento resta identico.
- Sotto il campo, con `filtering`: le `DownloadRushRow` di `rushGroups(overview.waiting, q)`. `onRush`: `overview.enabled && group.canPress ? () => _call(() => api.rush(group.key), started: true) : null`. Con `pending` mostra `downloadsRushPending` al posto del pulsante.
- Poi: `filtering && overview.enabled && overview.refreshPending != null && !overview.waiting.any((i) => titleMatches(i.title, q))` mostra `downloadsNotListed` con il pulsante `downloadsRefreshNow` (`_call(api.refresh)`), o `downloadsRefreshing` se `refreshPending == true`.
- Poller: `_fastPoll` se `waiting.any(searchPhase != null) || refreshPending == true`.

- [ ] **Step 4: Verifica.** Da `app/`: `flutter gen-l10n && flutter analyze && flutter test`. Expected: nessun problema, tutti i test passano.

- [ ] **Step 5: Commit** `feat(app): cerca nella lista Download e Scarica subito`

### Task 5: Versioni e checklist

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/*.csproj` (`<Version>1.27.0</Version>`), `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InfoControllerTests.cs:17`, `app/pubspec.yaml` (`version: 0.38.0`, stesso formato di ora), `docs/RELEASING.md`

- [ ] **Step 1:** Applica i numeri di versione. In `docs/RELEASING.md`, dopo la riga "Precedenza alle ricerche manuali", aggiungi:

```markdown
- [ ] Scarica subito (app 0.38.0, plugin 1.27.0, un admin, con la coda automatica piena e una ricerca in corso): nella scheda Download il campo restringe tutte le sezioni; una serie appena aggiunta mostra "Non è in lista", "Aggiorna ora" la fa comparire senza avviare altre ricerche; "Scarica subito" la porta davanti: nel log è la prima ricerca dopo quella in corso. Con il plugin 1.26.0: il filtro funziona, i due pulsanti non compaiono.
```

- [ ] **Step 2: Verifica.** Da `plugin/`: `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`. Da `app/`: `flutter analyze`. Expected: PASS.

- [ ] **Step 3: Commit** `chore: plugin 1.27.0 e app 0.38.0`
