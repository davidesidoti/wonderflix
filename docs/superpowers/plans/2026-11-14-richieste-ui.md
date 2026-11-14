# Richieste, nuova UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La pagina Richieste divisa in In corso (con il percorso in quattro tappe), Arrivate (scaffale di locandine) e Chiuse, con i gruppi calcolati dal plugin.

**Architecture:** Il plugin aggiunge `group=open|done|closed` a `GET Requests`: legge da Seerr l'elenco grezzo completo (cache 30 s, svuotata dalle azioni e dal webhook), lo divide con regole pure (`RequestGroups`) e completa solo la pagina chiesta. L'app ha un controller per gruppo (stessa logica di oggi, chiave allargata) e una pagina a slivers; senza la funzione `requestsGroups` resta l'elenco unico con le righe nuove.

**Tech Stack:** .NET 9 (xUnit) per il plugin; Flutter 3.47.5, flutter_riverpod 3.x, go_router per l'app.

**Spec:** `docs/superpowers/specs/2026-11-14-richieste-ui-design.md` (bozza: `docs/superpowers/specs/2026-11-14-richieste-bozze/richieste.html`). Ogni compito la legge per le parti che cita.

## Global Constraints

- Plugin resta **1.31.0**, app resta **0.42.0**: niente bump, `InfoControllerTests` non cambia la versione.
- Senza `group` la risposta di `GET Requests` è **identica a oggi**: nessun `Removed`/`NotFound`, nessun `Total` (Jellyfin JSON salta i null).
- Stili: solo token esistenti (`WfColors.*`, `WfText.display`, Inter). Nessun colore nuovo.
- Testi in italiano nell'app (`app_it.arb`) con l'inglese in `app_en.arb`; codice e nomi in inglese; commenti in italiano come il resto del codice.
- Commit: messaggi in italiano, autore l'utente, **nessun** `Co-Authored-By` né "Generated with"; mai le parole closes/fixes/resolves.
- Mai uccidere processi per nome immagine (`taskkill /IM`, `pkill`): solo per PID e solo i propri.
- Comandi: plugin `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` da `plugin/`; app da `app/`: `flutter gen-l10n`, `flutter analyze`, `flutter test`. Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"` prima. Il worktree ha bisogno di `app/config/wonderflix.json` copiato dal checkout principale per la build. Build di rilascio: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- `dart format` solo sulle righe toccate (non riformattare file vecchi interi). Se i comandi Flutter riscrivono `app/windows/flutter/generated_plugin*` con soli fine riga, `git checkout --` quei file.
- Riverpod 3: niente nomi di Riverpod 2.

## Review Focus

1. **Richiesta che cambia gruppo mentre la pagina è aperta** (arriva, viene tolta, viene approvata): deve sparire dal gruppo vecchio e comparire nel nuovo al primo aggiornamento, senza doppioni tra gruppi → test in Task 7 (`refreshAllGroupsAfterEvent`).
2. **Approva da "Da approvare" con i gruppi di "Tutte" già aperti**: la riga deve comparire in In corso di "Tutte" (oggi si aggiorna solo l'elenco `all` senza gruppo) → test in Task 7.
3. **Plugin vecchio (senza `requestsGroups`)**: l'app non deve mandare `group` né mostrare gruppi vuoti → test in Task 8 (`fallbackWithoutFeature`).
4. **Webhook arrivato subito dopo un'azione**: la cache deve essere già vuota quando parte l'avviso nella cassetta, o l'app rilegge lo stato vecchio → test in Task 3 (`webhookClearsTheListBeforeTheInbox`).
5. **Gruppo In corso lungo (44 in "Tutte") con un errore a metà caricamento automatico**: le righe già caricate restano, compare "Riprova" in fondo al gruppo, gli altri gruppi restano → test in Task 7/8.

---

### Task 1: Plugin — stati e gruppi (`RequestGroups`)

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/RequestsDtos.cs` (costanti `RequestStatuses`)
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Seerr/RequestGroups.cs`
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/RequestGroupsTests.cs`

**Interfaces:**
- Produces:
  - `RequestStatuses.Removed = "Removed"`, `RequestStatuses.NotFound = "NotFound"`.
  - `public static class RequestGroups` con `const string Open = "open", Done = "done", Closed = "closed"`, `static readonly TimeSpan NotFoundAfter = TimeSpan.FromDays(30)`.
  - `public static bool IsGroup(string? raw)`.
  - `public static bool NeedsMovieDates(SeerrRequest request, DateTimeOffset now)`: true per un film con stato di base `Approved` (da `SeerrMapping.RequestStatus`), media non eliminato e `now - CreatedAt > NotFoundAfter`.
  - `public static string StatusOf(SeerrRequest request, MovieDates? movie, DateTimeOffset now)`: stato per l'app con i gruppi (spec §4.2).
  - `public static string GroupOf(string status)`: `Open`/`Done`/`Closed` (tabella spec §4.2).

- [ ] **Step 1: Test che falliscono** in `RequestGroupsTests.cs` (costruire `SeerrRequest` come `RequestsServiceTests.Request`, `now = 2026-11-14T12:00Z`):
  - `CompletedWithDeletedMediaIsRemoved`: status 5, media 7, nessun download → `Removed`, gruppo `closed`.
  - `ApprovedWithDeletedMediaIsRemoved`: status 2, media 7, nessun download → `Removed`.
  - `ApprovedWithDeletedMediaButDownloadingStaysDownloading`: status 2, media 7, un `DownloadStatus` → `Downloading`, gruppo `open`.
  - `DeclinedWithDeletedMediaStaysDeclined`: status 3, media 7 → `Declined`.
  - `ApprovedUnknownMediaAt31DaysIsNotFound` / `...At29DaysIsApproved`: status 2, media 1, `CreatedAt = now - 31/29 giorni` → `NotFound` (`closed`) / `Approved` (`open`).
  - `ApprovedMovieNotYetReleasedAt31DaysIsAwaitingRelease`: film, `movie` con digitale futuro → `AwaitingRelease` (`open`); `NeedsMovieDates` true.
  - `ApprovedSeriesAt31DaysIsNotFound`: serie, media 3 → `NotFound`; `NeedsMovieDates` false.
  - `PartialStaysOpen`: status 2, una stagione completata → `Partial`, `open`.
  - `CompletedWithUnknownMediaIsAvailable`: status 5, media 1 → `Available`, `done`.
  - `GroupsOfEveryStatus`: Pending/Approved/Downloading/Partial/AwaitingRelease → open; Available → done; Declined/Failed/Removed/NotFound → closed.
  - `IsGroupAcceptsOnlyTheThreeNames`: "open","done","closed" true; "pending", "", null, "OPEN" false.

- [ ] **Step 2: Eseguire e vederli fallire**

Run (da `plugin/`): `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter RequestGroupsTests`
Expected: errori di compilazione (`RequestGroups` non esiste).

- [ ] **Step 3: Implementare** le costanti e `RequestGroups`. `StatusOf`: parte da `SeerrMapping.RequestStatus(request)`; media `MediaDeleted` senza download e base in {Available, Approved, Partial} → `Removed`; base `Approved` e `ReleaseRules.IsAwaitingRelease(movie, now)` → `AwaitingRelease`; base `Approved`, più vecchia di `NotFoundAfter`, media in {Unknown, Pending, Processing} → `NotFound`; altrimenti la base.

- [ ] **Step 4: Eseguire i test**: stesso comando, Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/RequestsDtos.cs plugin/Jellyfin.Plugin.WonderFlixWatchParty/Seerr/RequestGroups.cs plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/RequestGroupsTests.cs
git commit -m "feat(plugin): stati Tolta dal server e Non trovata, e i gruppi delle richieste"
```

---

### Task 2: Plugin — elenco grezzo con cache (`SeerrRequestList`)

**Files:**
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Seerr/SeerrRequestList.cs`
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs` (`AddSingleton<SeerrRequestList>()` accanto a `SeerrTitleCache`)
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/SeerrRequestListTests.cs`

**Interfaces:**
- Produces: `public sealed class SeerrRequestList(ISeerrClient seerr, TimeProvider time)` con
  - `public static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(30)`, `public const int PageSize = 100`;
  - `public Task<IReadOnlyList<SeerrRequest>> GetAsync(int asUser, int? requestedBy, CancellationToken ct)`: tutte le richieste dell'ambito (`requestedBy` null = tutte), nell'ordine di Seerr, filtro `"all"`;
  - `public void Clear()`.
- Consumes: `ISeerrClient.GetRequestsAsync(int asUser, string filter, int take, int skip, int? requestedBy, CancellationToken)`.

- [ ] **Step 1: Test che falliscono** (usare `FakeSeerrClient`, `FakeTimeProvider` come negli altri test):
  - `ReadsEveryPageAdvancingByTheResultsReceived`: 250 richieste, `TotalRequests = 250` → 250 righe; `Listed` mostra skip 0, 100, 200. Con un fake che restituisce al massimo 40 per pagina, skip avanza di 40.
  - `SecondCallWithin30SecondsDoesNotReadAgain`: due `GetAsync(3, null)` → una sola chiamata `GetRequests`; dopo `time.Advance(31 s)` → seconda lettura.
  - `ScopesAreSeparate`: `GetAsync(3, null)` e `GetAsync(24, 24)` → due letture, la seconda con `requestedBy` 24.
  - `ConcurrentCallsShareOneRead`: due `GetAsync` avviati prima che il fake risponda (fake con gate) → una lettura.
  - `ClearForcesANewRead`.
  - `AFailedReadIsNotCached`: prima chiamata lancia `SeerrException` → la seconda rilegge.

- [ ] **Step 2: Eseguire** con `--filter SeerrRequestListTests`. Expected: errori di compilazione.

- [ ] **Step 3: Implementare.** Dizionario per `requestedBy` (`int?`, chiave `-1` per null va bene) di `(Task<IReadOnlyList<SeerrRequest>>, DateTimeOffset readAt)` sotto lock; un task fallito si toglie. Ciclo come `SpaceService.Scan.cs` righe ~291–302 (avanza di `results.Count`, si ferma a 0 risultati o a `pageInfo.results`). `SpaceService` non si tocca.

- [ ] **Step 4: Eseguire i test**: PASS.

- [ ] **Step 5: Commit** — `feat(plugin): elenco delle richieste di Seerr letto una volta ogni 30 secondi`

---

### Task 3: Plugin — `group` in `GET Requests`, `Total`, cache svuotata, funzione

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Hub/RequestsService.cs` (costruttore, `ListAsync`, `ToDtoAsync`, `ApproveAsync`, `DeclineAsync`, `CreateAsync`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Api/RequestsController.cs` (`List`: `[FromQuery] string? group`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/RequestsDtos.cs` (`RequestPageDto` + `Total`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Hub/RequestWebhookHandler.cs` (costruttore + `Clear()` in `HandleAsync`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs` (`RequestsGroupsFeature`)
- Test: `RequestsServiceTests.cs`, `RequestsControllerTests.cs`, `InfoControllerTests.cs` (solo la lista delle funzioni, se la verifica)

**Interfaces:**
- Consumes: Task 1 (`RequestGroups`, `RequestStatuses.Removed/NotFound`), Task 2 (`SeerrRequestList`).
- Produces:
  - `RequestsService(ISeerrClient seerr, SeerrUserMap users, SeerrTitleCache titles, SeerrRequestList list, ReleaseDatesService dates, DownloadService downloads, TimeProvider time)`.
  - `Task<RequestPageDto> ListAsync(Guid userId, string? filter, string? group, int skip, int take, string language, CancellationToken ct)`.
  - `RequestPageDto(IReadOnlyList<MediaRequestDto> Items, bool HasMore, [property: JsonPropertyName("Total")] int? Total = null)`.
  - `GET .../Requests?filter=&group=&skip=&take=&language=` (JSON: `Items`, `HasMore`, `Total` solo con `group`).
  - `WatchPartyProtocol.RequestsGroupsFeature = "requestsGroups"`, aggiunta in `FeaturesWith` quando `requests` è vero.
  - `RequestWebhookHandler` prende `SeerrRequestList` nel costruttore.

- [ ] **Step 1: Test che falliscono** in `RequestsServiceTests` (aggiornare il costruttore nei due punti; `RequestsControllerTests` riga ~36–37 idem):
  - `GroupsSplitTheRequests`: richieste con le coppie (2,1) recente, (2,3), (2,4), (2,5), (5,5), (5,7), (3,1), (2,1) a 40 giorni → `open` = (2,1) recente, (2,3), (2,4); `done` = (2,5), (5,5); `closed` = (5,7) `Removed`, (3,1) `Declined`, (2,1) vecchia `NotFound`. `Total` uguale al numero del gruppo.
  - `GroupPagesKeepTheOrderAndHasMore`: 25 richieste aperte, `skip 20 take 20` → 5 righe, `HasMore` false, `Total` 25; `skip 0 take 20` → `HasMore` true.
  - `WithoutGroupTheResponseIsUnchanged`: (5,7) senza `group` → `Available`, `Total` null, `JellyfinItemId` quello di Seerr.
  - `RemovedHasNoJellyfinItemId`: (5,7) con `JellyfinMediaId` impostato e `group=closed` → `JellyfinItemId` null.
  - `PendingWithGroupIsBadRequest` e `UnknownGroupIsBadRequest` → `SeerrError.BadRequest`.
  - `AllWithGroupNeedsAManager`: Mario `FilterAll` + `open` → `NoPermission`.
  - `ThreeGroupsReadSeerrOnce`: `open`, `done`, `closed` di fila → una chiamata `GetRequests`.
  - `ApproveDeclineAndCreateClearTheList`: dopo ciascuna azione, una nuova `ListAsync` con `group` rilegge Seerr.
  - `MovieDatesAreReadOnlyForOldApprovedMovies`: una (2,1) film a 40 giorni e una a 2 giorni con `group=closed` → `FakeArrClient` interrogato per date solo per la vecchia (o, se più semplice, `NotFound` vs `AwaitingRelease` secondo le date del fake).
  - In `RequestsControllerTests`: `ListPassesTheGroup` (query `group=done` arriva al servizio) e `webhookClearsTheListBeforeTheInbox` (dopo un evento `MEDIA_AVAILABLE` la lista si rilegge; l'avviso nella cassetta parte dopo `Clear`).
  - Info: la lista delle funzioni con Seerr configurato contiene `requestsGroups`, senza Seerr no.

- [ ] **Step 2: Eseguire** l'intera suite del plugin. Expected: compilazione fallita / test rossi.

- [ ] **Step 3: Implementare.**
  - `ListAsync`: validazioni di oggi + `group` (nullo, o `RequestGroups.IsGroup`; con `FilterPending` → 400). Senza `group`: codice di oggi invariato (con `ToDtoAsync(..., grouped: false)`).
  - Con `group`: `list.GetAsync(user.Id, filter == FilterMine ? user.Id : null, ct)`; per le richieste con `RequestGroups.NeedsMovieDates` leggere `dates.GetMovieAsync` in parallelo; `StatusOf` per ognuna; tenere quelle con `GroupOf(status) == group`; `Total = count`; fetta `skip/take`; `ToDtoAsync(r, ..., grouped: true)` solo per la fetta; `HasMore = skip + fetta < Total`.
  - `ToDtoAsync(SeerrRequest request, int me, string language, bool grouped, CancellationToken ct)`: con `grouped` lo stato finale è `RequestGroups.StatusOf(request, movie, now)` e, se `Removed`, `JellyfinItemId` null. Le date del film si leggono come oggi (non per Available/Declined/Failed/Removed/NotFound).
  - `ApproveAsync`, `DeclineAsync`, `CreateAsync`: `list.Clear()` dopo che Seerr ha risposto.
  - `RequestWebhookHandler.HandleAsync`: `list.Clear()` subito dopo il controllo del segreto, prima dello `switch`.

- [ ] **Step 4: Eseguire** l'intera suite del plugin. Expected: tutto verde (`SubtitleServiceTests.AFailedDownloadIsFailed`, `ArrClientTests.ASlowSearchUsesTheReleaseSearchTimeout`, `DownloadAlertsTests` sono instabili: ripetere prima di indagare).

- [ ] **Step 5: Commit** — `feat(plugin): richieste divise in gruppi (in corso, arrivate, chiuse)`

---

### Task 4: App — modelli, API, funzione, etichette e testi

**Files:**
- Modify: `app/lib/core/requests/requests_models.dart`, `app/lib/core/requests/requests_api.dart`
- Modify: `app/lib/core/social/social_models.dart` (`PluginFeatures.requestsGroups`), `app/lib/features/social/social_providers.dart` (`SocialFeatures.requestsGroups`, letto da `info.features`)
- Modify: `app/lib/features/requests/requests_providers.dart` (`requestsGroupsProvider`)
- Modify: `app/lib/features/requests/request_labels.dart`
- Modify: `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/support/requests_fakes.dart` (`FakeRequestsApi.list` con `group`), `test/features/requests/request_labels_test.dart`, test dei modelli/API esistenti

**Interfaces:**
- Produces:
  - `RequestStatus.removed`, `RequestStatus.notFound` (`parse('Removed')`, `parse('NotFound')`).
  - `enum RequestsGroup { open('open'), done('done'), closed('closed'); final String wire; }`.
  - `RequestPage({required items, required hasMore, this.total})`, `final int? total` da `json['Total']`.
  - `RequestsApi.list(RequestsFilter filter, {RequestsGroup? group, required int skip, required int take, required String language})`: `group` nella query solo se non nullo.
  - `final requestsGroupsProvider = Provider<bool>` (`socialAvailabilityProvider.select((f) => f.requests && f.requestsGroups)`).
  - `requestStatusLabel`/`requestStatusColor` per i due stati nuovi: "Tolta dal server" / "Non trovata", `WfColors.creamMuted`.
  - Chiavi l10n (it / en) — testi esatti dalla spec §5.10:
    `requestsAskTitle` "Richiedi un titolo" / "Request a title"; `requestsGroupOpen` "In corso" / "In progress"; `requestsGroupDone` "Arrivate" / "Arrived"; `requestsGroupClosed` "Chiuse" / "Closed"; `requestsShowMore` "Mostra altre" / "Show more"; `requestsStepRequested` "Chiesta" / "Requested"; `requestsStepToApprove` "Da approvare" / "Awaiting approval"; `requestsStepApproved` "Approvata" / "Approved"; `requestsStepComing` "In arrivo" / "On its way"; `requestsStepNotReleased` "Non ancora uscito" / "Not out yet"; `requestsStepOnWonderflix` "Su WonderFlix" / "On WonderFlix"; `requestsStepPartial` "In parte" / "Partly"; `requestsStatusRemoved` "Tolta dal server" / "Removed from the server"; `requestsStatusNotFound` "Non trovata" / "Not found"; `requestsDetailPending` "Aspetta l'ok di chi gestisce le richieste" / "Waiting for whoever manages requests"; `requestsDetailApproved` "Approvata: si cerca una versione da scaricare" / "Approved: looking for a version to download"; `requestsDetailPercent` "{percent}% scaricato" / "{percent}% downloaded"; `requestsDetailDownloading` "Download in corso" / "Downloading"; `requestsDetailPartial` "Una parte è già su WonderFlix" / "Part of it is already on WonderFlix"; `requestsEmptyMineTitle` "Non hai ancora chiesto niente" / "You haven't requested anything yet"; `requestsEmptyMine` (testo nuovo) "Se un film o una serie non è su WonderFlix, cercalo e premi Richiedi. Lo trovi qui mentre arriva." / "If a film or series isn't on WonderFlix, search for it and press Request. You'll find it here while it arrives."; `requestsYou` "tu" / "you"; `requestsTrackSemantics` "Fatte: {done}. Ora: {current}" / "Done: {done}. Now: {current}"; `requestsRequestedBy` diventa "chiesta da {name}" / "requested by {name}".

- [ ] **Step 1: Test che falliscono:** `parse` dei due stati; `RequestPage.fromJson` con e senza `Total`; `list` con `group: RequestsGroup.done` mette `group=done` nella query e senza `group` non c'è (con il fake HTTP che usano i test di `requests_api`); `requestStatusLabel`/`Color` per i nuovi stati; `requestsGroupsProvider` vero solo con `requests` e `requestsGroups`.
- [ ] **Step 2: Eseguire** `flutter test test/features/requests test/core` — Expected: FAIL.
- [ ] **Step 3: Implementare**, poi `flutter gen-l10n`. `FakeRequestsApi.list` registra il gruppo e risponde da liste per `(filter, group)` (estendere senza rompere i test esistenti).
- [ ] **Step 4: Eseguire** `flutter gen-l10n && flutter analyze && flutter test test/features/requests test/core test/features/social` — Expected: PASS, analyze pulito.
- [ ] **Step 5: Commit** — `feat(app): stati, gruppi e testi della nuova pagina Richieste`

---

### Task 5: App — il percorso (`RequestTrack`)

**Files:**
- Create: `app/lib/features/requests/request_track.dart`
- Test: `app/test/features/requests/request_track_test.dart`

**Interfaces:**
- Consumes: Task 4 (stati, testi), `requestDateParts` di `request_labels.dart`.
- Produces:
  - `typedef RequestTrackModel = ({int current, bool half, double fill, List<String> labels})` — `current` 0–3, `fill` in tappe (es. 2.42), `labels` quattro.
  - `RequestTrackModel? requestTrackModel(MediaRequest request, AppLocalizations l)`: null per gli stati non in corso.
  - `List<RequestDatePart> requestTrackDetail(MediaRequest request, DateTime now, AppLocalizations l)`: la riga sotto il percorso (tabella spec §5.4).
  - `class RequestTrack extends StatelessWidget { const RequestTrack({super.key, required this.request, required this.now, this.labels = true}); }`: punti, linea, etichette se `labels`, riga del dettaglio sotto; con `labels: false` il dettaglio comincia con la tappa attuale in crema semibold e " · ".

- [ ] **Step 1: Test che falliscono:**
  - modello per ogni riga della tabella §5.4: pending → `current 1`, `labels[1] == "Da approvare"`, `fill 1`; approved → `current 2`, `fill 2`; awaitingRelease → `labels[2] == "Non ancora uscito"`; downloading con progress 0.42 → `fill` 2.42, senza progress → `fill` 2; partial → `current 3`, `half` true, `labels[3] == "In parte"`; available/declined/removed → null.
  - dettaglio: pending "Aspetta l'ok…"; downloading 0.42 → "42% scaricato"; downloading senza progress → "Download in corso"; partial senza prossimo episodio → "Una parte è già su WonderFlix"; partial con `nextAiring` futuro → la parte di `requestDateParts` con `upcoming: true`; awaitingRelease con le date del film.
  - widget: con `labels: true` si vedono le quattro etichette; con `false` nessuna e il dettaglio comincia con "In arrivo · 42% scaricato"; `Semantics` con "Fatte: Chiesta, Approvata. Ora: In arrivo, 42%" (testo esatto composto da `requestsTrackSemantics`).
- [ ] **Step 2: Eseguire** `flutter test test/features/requests/request_track_test.dart` — FAIL.
- [ ] **Step 3: Implementare** secondo spec §5.4 (misure: punti 12 px, anello 2 px con alone oro al 18%, linea 2 px `WfColors.border` e oro, etichette 11,5 px; prima a sinistra, ultima a destra). Transizione della linea con `WfMotion` breve, ferma con animazioni ridotte (come gli altri widget che leggono le impostazioni di movimento).
- [ ] **Step 4: Eseguire** il test — PASS; `flutter analyze` pulito.
- [ ] **Step 5: Commit** — `feat(app): il percorso in quattro tappe di una richiesta`

---

### Task 6: App — righe nuove (`RequestRow`)

**Files:**
- Modify: `app/lib/features/requests/request_row.dart`
- Test: `app/test/features/requests/request_row_test.dart`

**Interfaces:**
- Consumes: Task 5 (`RequestTrack`), Task 4 (testi, etichette).
- Produces: `RequestRow` con la stessa firma di oggi (`request`, `now`, `onTap`, `showRequester`, `trailing`); `RequestRow.posterWidth/Height` diventano 56/84 (40/60 nello stretto via `FormFactor`). Tre aspetti:
  - con `trailing` → righe "Da approvare" (azioni a destra, sotto a destra nello stretto, come oggi);
  - stato in corso (`requestTrackModel != null`) → colonna di 400 px con `RequestTrack` (nello stretto sotto, `labels: false`); sulla TV `labels: true`;
  - altrimenti → etichetta di testo a destra (12,5 px semibold, colore `requestStatusColor`, niente bordo).
- Meta: tipo o stagioni · "chiesta da" + `UserAvatar.lookup(name:, size: 18)` (o iniziale) + nome, oppure "tu" se `requestedBy.isMe` · ora relativa. Requester solo con `showRequester`.

- [ ] **Step 1: Test che falliscono** (adattare quelli di oggi): riga in corso larga con il percorso e le etichette; stretta (`tester.view.physicalSize` sotto 1024) con il percorso sotto e senza etichette; "chiesta da Luca" con avatar e "chiesta da tu" per `isMe`; riga arrivata con "Disponibile" in `WfColors.online`; riga tolta con "Tolta dal server" in `creamMuted`; riga con `trailing` senza percorso; `onTap` null blocca il tocco (come oggi).
- [ ] **Step 2: Eseguire** `flutter test test/features/requests/request_row_test.dart` — FAIL.
- [ ] **Step 3: Implementare** (spec §5.3). Hover `surfaceHigh`; niente card.
- [ ] **Step 4: Eseguire** `flutter test test/features/requests` — PASS (i test della pagina di oggi possono richiedere ritocchi ai testi cercati: aggiornarli qui).
- [ ] **Step 5: Commit** — `feat(app): righe delle richieste con il percorso e chi ha chiesto`

---

### Task 7: App — controller per gruppo

**Files:**
- Modify: `app/lib/features/requests/requests_list_controller.dart`
- Test: `app/test/features/requests/requests_list_controller_test.dart`

**Interfaces:**
- Consumes: Task 4 (`RequestsGroup`, `RequestsApi.list(group:)`, `RequestPage.total`).
- Produces:
  - `typedef RequestsListKey = ({RequestsFilter filter, RequestsGroup? group, String language});` (tutti gli usi di oggi passano `group: null`).
  - `RequestsListState.total` (`int?`, dall'ultima pagina letta; `copyWith` lo aggiorna).
  - Con `group == RequestsGroup.open`: dopo ogni pagina riuscita con `hasMore`, la successiva parte da sola; timer di 30 s (`Timer.periodic`, `clock`) che chiama `refresh()` solo se almeno una riga è `downloading` e non c'è un caricamento in corso; cancellato in `onDispose`. `static const openRefreshEvery = Duration(seconds: 30)`.
  - In `_act`, dopo un'azione riuscita: aggiornare (`refresh`) ogni controller esistente di `filter: all` con `group` null, open, done o closed.

- [ ] **Step 1: Test che falliscono** (`fake_async` come negli altri test del controller):
  - `openLoadsEveryPage`: 44 righe aperte nel fake → dopo il primo caricamento il controller arriva a 44 senza `loadMore` esterni; `total` 44.
  - `doneWaitsForLoadMore`: 45 righe arrivate → 20, poi 40 con `loadMore`.
  - `openRefreshesEvery30SecondsWhileDownloading`: una riga `downloading` → dopo 30 s un'altra chiamata `list`; senza righe in download nessuna chiamata dopo 90 s; dopo dispose nessuna chiamata.
  - `approveRefreshesTheGroupsOfAll`: con i controller di `all/open` e `all/done` vivi, `approve` da `pending` → entrambi richiamano `list`.
  - `refreshAllGroupsAfterEvent`: un `InboxChangedEvent` con una richiesta passata da open a done nel fake → sparisce da open, compare in done, nessun doppione.
  - `errorMidAutoLoadKeepsRows`: la seconda pagina di open fallisce → restano 20 righe, `error` impostato, `retry` carica la pagina dopo.
- [ ] **Step 2: Eseguire** `flutter test test/features/requests/requests_list_controller_test.dart` — FAIL.
- [ ] **Step 3: Implementare**; aggiornare le chiavi in `requests_screen.dart` (`group: null`) perché compili.
- [ ] **Step 4: Eseguire** `flutter analyze && flutter test test/features/requests` — PASS.
- [ ] **Step 5: Commit** — `feat(app): un elenco per gruppo, In corso completo e aggiornato durante i download`

---

### Task 8: App — la pagina

**Files:**
- Modify: `app/lib/features/requests/requests_screen.dart`
- Create (se serve tenere il file piccolo): `app/lib/features/requests/requests_groups_view.dart`, `app/lib/features/requests/request_shelf.dart`
- Test: `app/test/features/requests/requests_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 (`requestsGroupsProvider`, testi), Task 6 (`RequestRow`), Task 7 (controller per gruppo).
- Produces: la pagina della spec §5.2–§5.9. `openRequest` per righe e locandine; "Richiedi un titolo" → `context.go('/search')`.

- [ ] **Step 1: Test che falliscono** (montaggio come i test di oggi, fake con liste per gruppo):
  - `groupsWithCounts`: "IN CORSO" con `total`, "ARRIVATE", "CHIUSE" con i conteggi; Chiuse chiusa (righe non visibili) e aperta al tocco.
  - `emptyGroupIsHidden`: nessuna arrivata → niente "ARRIVATE".
  - `showMoreLoadsTheNextPage`: 25 arrivate → 20 locandine, "Mostra altre", 25 dopo il tocco, pulsante sparito.
  - `oneGroupErrorKeepsTheOthers`: errore su done → "Riprova" al posto dello scaffale, In corso visibile.
  - `allErrorsShowErrorView`.
  - `emptyMineShowsTheAskButton`: tutti vuoti in "Le mie" → "Non hai ancora chiesto niente" e "Richiedi un titolo" porta a `/search`; "Tutte" vuota → "Nessuna richiesta".
  - `fallbackWithoutFeature`: `SocialFeatures(requests: true)` senza `requestsGroups` → nessun `group` nelle chiamate del fake, elenco unico con righe nuove.
  - `pendingTabUnchanged`: "Da approvare" con Approva/Rifiuta, senza gruppi; i test di oggi su schede, indirizzo, scelta automatica e uscita verso la Home restano verdi.
  - `posterOpensTheRequest`: tocco su una locandina → `openRequest` (scheda della libreria se c'è l'id).
  - TV (`tv: true`): solo "Le mie", niente Approva; con le frecce il fuoco raggiunge una riga, una locandina, "Mostra altre", "Chiuse" e "Richiedi un titolo".
- [ ] **Step 2: Eseguire** `flutter test test/features/requests/requests_screen_test.dart` — FAIL.
- [ ] **Step 3: Implementare.** Un `CustomScrollView` (controller `SmoothScrollController`) con i gruppi come slivers, larghezza massima del contenuto come Impostazioni (1040 + margini, a sinistra); titolo di gruppo Bebas 24 + conteggio Inter 13 `creamMuted`; scaffale: locandine 112×168 fuori dallo stretto, 3 colonne nello stretto, titolo su due righe e "Film"/"Serie", hover con bordo `creamMuted`, `TvFocusable`; Chiuse con freccia, chiusa all'apertura; "Mostra altre" (testo oro) sotto Arrivate e Chiuse finché `hasMore`; `LoadingView` finché i tre gruppi non hanno la prima risposta. Pulsante "Richiedi un titolo" (`WfButton.secondary`, icona di ricerca) a destra del titolo. La scheda "Da approvare" e il ripiego usano l'elenco di oggi (`_RequestsList`) con le righe nuove. Se l'elenco senza gruppi di oggi diventa usato solo da "Da approvare" e dal ripiego, tenerlo com'è.
- [ ] **Step 4: Eseguire** `flutter gen-l10n && flutter analyze && flutter test` (tutta la suite) — PASS.
- [ ] **Step 5: Commit** — `feat(app): pagina Richieste divisa in In corso, Arrivate e Chiuse`

---

### Task 9: Documenti e verifica finale

**Files:**
- Modify: `docs/RELEASING.md` (riga nuova nella checklist della prova a mano, sezione dell'app 0.42.0, dal §7 della spec)
- Modify: `docs/superpowers/specs/2026-11-14-richieste-ui-design.md` (riga di stato "realizzata" in testa, se le altre spec lo fanno)

- [ ] **Step 1:** Aggiungere la riga in `RELEASING.md` accanto a quelle del Calendario 0.42.0.
- [ ] **Step 2:** Rimuovere dagli arb le chiavi non più usate (`grep` di ogni chiave `requests*` in `lib/`), poi `flutter gen-l10n`.
- [ ] **Step 3: Verifica completa:** da `plugin/` `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`; da `app/` `flutter gen-l10n && flutter analyze && flutter test`. Expected: tutto verde, analyze senza problemi.
- [ ] **Step 4: Build di rilascio** da `app/` (con `config/wonderflix.json` copiato nel worktree): `flutter build windows --release --dart-define-from-file=config/wonderflix.json`. Expected: `build\windows\x64\runner\Release\wonderflix.exe`.
- [ ] **Step 5: Commit** — `docs: checklist della nuova pagina Richieste`
