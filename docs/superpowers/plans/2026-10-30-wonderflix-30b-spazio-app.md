# WonderFlix — Piano 30b: spazio sul seedbox, app 0.25.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte app della Spec U (§8): la scheda "Spazio" nella dashboard admin.
- **In alto:** quota, divisione dello spazio, "ricalcola".
- **Cancellare**, **Alleggerire** e **Pulizia**.
- **Sotto:** in attesa di fine seed, tenuti, ultime operazioni.
- **Scheda del titolo:** trama, generi e trailer, chi l'ha visto e chi l'ha chiesto, con "Elimina", "Tienilo" e "Alleggerisci".
- **Azioni:** prima una conferma con i passi, poi il riquadro del progresso dal vivo.

PC e web, layout largo e stretto.

**Architecture:**
- `lib/core/space/`: modelli e `SpaceApi` sugli endpoint del piano 30a.
- `lib/features/space/`: il controller della panoramica (letta ogni 60 s), quello di un'operazione (letto ogni secondo finché non finisce), le etichette, i widget.
- "Alleggerisci" riusa la ricerca della Spec T (`showDownloadSearch`) con `lighten: true`, che arriva fino a `DownloadsApi.grab`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, dio (`JellyfinHttp`), `flutter_test`, ARB it/en.

**Spec:** `docs/superpowers/specs/2026-10-30-wonderflix-spazio-seedbox-design.md` (§5, §6, §8). JSON e valori nel piano 30a, "Global Constraints": `docs/superpowers/plans/2026-10-30-wonderflix-30a-spazio-plugin.md`.

**Prerequisito:** il piano 30a finito (plugin 1.16.0) sullo stesso branch.

**Decisioni del piano:**
1. **Righe in "Cancellare":**
   - le stagioni con lo stesso `SeriesKey` si raggruppano sotto il titolo della serie, che si apre e si chiude (chiuso all'inizio) e mostra la somma dei GB;
   - una riga `Series` è una serie intera;
   - ogni sezione mostra 20 righe, poi "Mostra altri" ne aggiunge 20.
2. **I testi li compone l'app** dai codici:
   - segnali: "Visto da tutti, ultima visione 8 mesi fa", "Visto da Anna, abbandonato da Luca", "Mai aperto da 7 mesi", "Voto medio 1,5 su 2 voti";
   - "tienilo": "In visione", "Richiesto da Anna il 3 ottobre", "Voti alti", "Seguito in arrivo".
   Il plugin non manda testi.
3. **Scheda del titolo:** un `Dialog` (a tutto schermo nel layout stretto).
   - In alto la locandina (`PosterUrl`), il titolo, l'anno e i GB.
   - Poi trama e generi da `itemProvider(ItemId)` (già usato dal dettaglio) e il pulsante "Trailer" (`playTrailer`). Senza `ItemId`, o se la lettura fallisce, la scheda mostra il resto.
   - Poi chi l'ha visto, chi l'ha chiesto, i voti, i segnali.
   - In fondo i pulsanti: "Elimina" (da "Cancellare"), "Alleggerisci" (da "Alleggerire"), "Tienilo" (sempre, per film, serie e stagioni).
4. **Etichetta "generi che guardi spesso"**: c'è se almeno un genere della riga è in `TopGenres`.
5. **Conferma:** `showAdminConfirmDialog` con:
   - l'elenco dei passi in parole, in base al tipo (§6.2 della spec);
   - i GB liberati subito e dopo il seed, con la data;
   - se `InPackBytes > 0`, "{GB} restano: il pack contiene altri episodi o film in libreria".
6. **Il riquadro del progresso** è un `Dialog`:
   - si apre subito dopo `POST Space/Operations` e legge `GET Space/Operations/{id}` ogni secondo finché lo stato è `Queued` o `Running`;
   - ogni passo ha un'icona (in attesa, in corso, fatto, saltato, fallito, non fatto) e una frase con il dettaglio;
   - alla fine: "Liberati {GB}" (`QuotaBefore − QuotaAfter` se ci sono tutti e due, altrimenti `EstimatedFreedBytes`) e "{GB} in attesa del seed" se `PendingBytes > 0`;
   - chiuderlo non ferma l'operazione;
   - alla fine la panoramica si rilegge.
7. **"Ultime operazioni":** si toccano e riaprono lo stesso riquadro (sola lettura se finite).
8. **Pesi:** GB con due decimali e la virgola in italiano (come la scheda Download, `downloadsGb`); la quota in TB con due decimali (10¹² byte).
9. **"Ricalcola"**: chiama `POST Space/Recalculate`, poi rilegge ogni 5 s finché `Scanning` è vero, poi torna ai 60 s.

## Global Constraints

- App **0.25.0** (`pubspec.yaml`; se intanto 0.25.0 è uscita con un altro lavoro, la successiva libera, da segnalare).
- **Funzione** `space` (`PluginFeatures.space`), letta come `downloads` in `SocialAvailability`; senza, la scheda non c'è.
- **Scheda** `AdminTab.space`, subito dopo `downloads`; parametro dell'indirizzo `tab=space`.
- **Endpoint e JSON:** esattamente quelli del piano 30a, "Global Constraints" (PascalCase). Lettura tollerante: un campo mancante o di tipo sbagliato non rompe la pagina, la riga si salta.
- **`Downloads/Grab`**: `"Lighten": true` solo quando la ricerca è aperta da "Alleggerisci"; altrimenti il campo non si manda.
- **Errori:**
  - `POST Space/Operations`: 409 `Busy` → "Su questo titolo c'è già un'operazione in corso"; 409 `NotReady` → "Il calcolo dello spazio non è ancora pronto"; 404 `Unknown` → "Questo titolo non c'è più: ricalcola"; 400 → "Richiesta non valida";
  - 401/403 e rete come le altre schede admin;
  - `Errors` della panoramica (`Radarr`, `Sonarr`, `Qbit`, `Seerr`, `Quota`), una nota in cima alla scheda per ognuno, senza nascondere il resto: "qBittorrent non configurato", "qBittorrent: utente o password sbagliati", "qBittorrent non risponde", e lo stesso per gli altri. Per `Quota` `NotConfigured`: "Quota non disponibile: manca il file della quota (README del plugin)".
- **Testi dei passi** (`Name`):
  - `FindTorrents` "Cerco i torrent";
  - `RemoveFromQueue` "Tolgo i download in coda";
  - `DeleteFromRadarr` "Elimino da Radarr con i file";
  - `DeleteFromSonarr` "Elimino da Sonarr con i file";
  - `UnmonitorSeason` "Smetto di monitorare la stagione";
  - `DeleteEpisodeFiles` "Cancello i file degli episodi";
  - `RemoveTorrents` "Tolgo i torrent" (con `Done`/`Waiting`: "Tolti {n}, {m} in attesa del seed");
  - `RemoveFromSeerr` "Tolgo da Seerr";
  - `RefreshLibrary` "Aggiorno la libreria di Jellyfin";
  - `DeleteFile` "Cancello il file";
  - `ReadQuota` "Leggo la quota".
- **Testi dei dettagli** (`Detail`):
  - `NotConfigured` "non configurato";
  - `Unauthorized` "accesso negato";
  - `Unreachable` "non risponde";
  - `Gone` "non c'era più";
  - `SeedRule` "in seed obbligatorio";
  - `Failed` "non riuscito".
- **Testi:** italiano e inglese in `l10n/app_it.arb` e `l10n/app_en.arb`, chiavi che iniziano con `space`. Si generano con `flutter gen-l10n`.
- **Commit:** con l'identità git del repository; **mai** trailer `Co-Authored-By` né righe "Generated with…"; mai le parole `closes`, `fixes`, `resolves` (né simili) nei messaggi; messaggi in italiano.
- **Processi:** mai terminarli per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`); solo per PID.
- **Build di rilascio** (se serve una prova a mano): `flutter build windows --release --dart-define-from-file=config/wonderflix.json`, da `app/`.

## Review Focus

1. **Il riquadro del progresso aperto mentre il plugin si riavvia** (l'operazione sparisce, 404): il riquadro dice "Operazione non trovata" e smette di leggere, senza un ciclo infinito di errori. Test: Task 5 (`AMissingOperationStopsPolling`).
2. **Doppio clic su "Elimina":** parte una sola operazione (il pulsante si spegne fino alla risposta). Test: Task 5 (`DeleteIsDisabledWhileStarting`).
3. **Telefono (layout stretto):** le righe con titoli lunghi e più segnali vanno a capo, senza scorrimento orizzontale; la scheda del titolo è a tutto schermo. Test: Task 4 (`NarrowLayoutHasNoHorizontalOverflow`).
4. **Prima del primo calcolo** (`ScannedAt` null): la scheda dice "Calcolo in corso…" e si rilegge, senza liste vuote che sembrano "niente da fare". Test: Task 4 (`BeforeTheFirstScanShowsCalculating`).
5. **Plugin senza `space`, o funzione che sparisce:** la scheda non c'è e la dashboard va su Sessioni. Test: Task 3 (`TheTabNeedsTheFeature`).

---

## Regole per chi esegue

- **Commit:** come nel piano 30a: identità del repository, niente trailer, niente push, niente parole che chiudono le issue, una riga in italiano.
- **Processi:** mai per nome d'immagine.
- **Shell:** PowerShell su Windows.
  - Prima di `flutter` o `git`, rinfresca il PATH:
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Si lavora in `.claude/worktrees/spazio-seedbox/app`; mai nel checkout principale. Se manca `config/wonderflix.json`, copialo dal checkout principale (`app/config/`).
  - "Cannot create link … errno 183": `flutter clean`.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit**: `flutter gen-l10n`, `flutter analyze` (nessun problema), `flutter test` (tutto verde);
  - il primo implementatore conta i test verdi di partenza e li scrive nel registro.
- **Stile dell'app:**
  - commenti in italiano, codice in inglese, riferimenti alla spec ("spec U §8");
  - colori e testi da `WfColors`/`WfText`;
  - i widget della dashboard da `admin_widgets.dart` (`AdminCard`, `AdminSectionTitle`, `AdminEmptyText`, `AdminCardError`, `adminTabState`), più `AdminActionButton`, `showAdminConfirmDialog` e `AdminPoller`;
  - margini con `adminSideMargin`; layout con `FormFactor.of(context).compact`;
  - Riverpod 3 (`AsyncNotifier`, `Notifier`, famiglie con argomento nel costruttore), mai i nomi di Riverpod 2.
- **Se il codice del piano ha un errore:** correggilo in modo minimo, nello spirito del piano, e segnalalo.

## Note tecniche verificate

Verificate il 2026-10-30 sul codice di `main` (`40c7ec3`).

- **`DownloadsApi`** (`lib/core/downloads/downloads_api.dart`):
  - modello di API del plugin: `_base`, `_quiet`, `_call` che traduce gli errori in `DownloadsException(failure)`;
  - `grab(String key, String guid, int indexerId)` manda `{'Key','Guid','IndexerId'}`;
  - `downloadsFailureLabel` è in `download_labels.dart` e `error_text.dart` lo usa.
- **`showDownloadSearch(context, key, title, {reviewing})`** (`download_search_page.dart`) apre `_SearchPage`. Il grab passa da `DownloadSearchController.grab(candidate)` e `grabRelease(release)` (`download_search_controller.dart`), che chiamano `api.grab(key, guid, indexerId)`.
- **Funzioni del plugin:**
  - `PluginFeatures.downloads` in `lib/core/social/social_models.dart`;
  - `SocialFeatures.downloads` in `lib/features/social/social_providers.dart` (campo, `==`, `hashCode`, `toString`, lettura `info.features.contains(PluginFeatures.downloads)`).
- **Dashboard:**
  - `AdminTab` e `adminTabs({inbox, account, downloads})` in `admin_navigation.dart`;
  - `admin_screen.dart` legge le funzioni con `socialAvailabilityProvider.select` e fa lo `switch`;
  - test in `test/features/admin/admin_navigation_test.dart` e `admin_screen_test.dart`.
- **Dettaglio del titolo:** `itemProvider` (`lib/features/detail/detail_providers.dart`, `FutureProvider.autoDispose.family<JellyfinItem, String>`), `playTrailer(context, ref, item)` (`lib/features/playback/play_launcher.dart`). Generi e trama in `JellyfinItem`.
- **`AdminPoller(read:, interval:)`** in `admin_poller.dart`; la scheda Download lo usa a 60 s (`downloads_tab.dart`).
- **Peso in GB:** `downloadsGb` ("{value} GB") e la formattazione di `download_labels.dart`.

## File

| File | Responsabilità |
|---|---|
| `lib/core/space/space_models.dart`, `lib/core/space/space_api.dart` | modelli e chiamate |
| `lib/core/downloads/downloads_api.dart`, `lib/features/downloads/download_search_controller.dart`, `lib/features/downloads/download_search_page.dart` | `lighten` |
| `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart` | la funzione `space` |
| `lib/features/admin/admin_navigation.dart`, `lib/features/admin/admin_screen.dart` | la scheda |
| `lib/features/space/space_providers.dart`, `space_controller.dart`, `space_operation_controller.dart` | stato |
| `lib/features/space/space_labels.dart` | testi da codici |
| `lib/features/space/space_tab.dart`, `space_rows.dart`, `space_title_dialog.dart`, `space_operation_dialog.dart` | widget |
| `l10n/app_it.arb`, `l10n/app_en.arb`, `pubspec.yaml` | testi e versione |

---

### Task 1: modelli, API e `lighten`

**Files:**
- Create: `lib/core/space/space_models.dart`, `lib/core/space/space_api.dart`
- Modify: `lib/core/downloads/downloads_api.dart`, `lib/features/downloads/download_search_controller.dart`, `lib/features/downloads/download_search_page.dart`
- Test: `test/core/space/space_models_test.dart`, `test/core/space/space_api_test.dart`, `test/core/downloads/downloads_api_test.dart`, `test/features/downloads/download_search_controller_test.dart`

**Interfaces:**
- Produces (modelli immutabili, `static X? fromJson(Object? json)` che restituisce null per una forma sbagliata, come i modelli dei download):
  - `SpaceQuota(usedBytes, limitBytes)`; `SpaceBreakdown(moviesBytes, seriesBytes, animeBytes, torrentOnlyBytes, otherBytes)`;
  - `SpaceViewer(name, finished, lastPlayed)`; `SpaceRequest(name, at)`;
  - `SpaceCandidate(key, kind, title, year, seasonNumber, seriesKey, itemId, posterUrl, sizeBytes, freeNowBytes, freeLaterBytes, freeLaterAt, inPackBytes, via, keep, viewers, requests, ratingAvg, ratingCount, lastOpened, added, genres)`;
  - `SpaceLighten(key, kind, title, seasonNumber, itemId, posterUrl, sizeBytes, excessBytes, gbPerHour)`;
  - `SpaceTorrent(key, hash, name, tracker, sizeBytes, ratio, seedingDays, canRemoveNow, expectedAt)`; `SpaceFile(key, path, sizeBytes, linked)`; `SpaceCleanup(torrents, orphans, duplicates)`;
  - `SpacePending(hash, name, tracker, sizeBytes, expectedAt, title)`; `SpaceKept(key, title)`;
  - `SpaceStep(name, state, detail, done, waiting)`; `SpaceOperation(id, kind, key, title, state, auto, startedAt, endedAt, estimatedFreedBytes, pendingBytes, quotaBeforeBytes, quotaAfterBytes, steps)` con `bool get running` (`Queued`/`Running`);
  - `SpaceErrors(radarr, sonarr, qbit, seerr, quota)`;
  - `SpaceOverview(scannedAt, scanning, quota, breakdown, delete, lighten, cleanup, pending, kept, operations, topGenres, errors)`.
  - Negli elenchi una voce rotta si salta; le date con `DateTime.tryParse`.
- Produces (`SpaceApi(JellyfinHttp)`, `_base = '/WonderFlixWatchParty/Space'`, `_quiet = {400, 403, 404, 409, 503}`):
  - `Future<SpaceOverview> overview()`;
  - `Future<void> recalculate()`;
  - `Future<String> start(String kind, String key)`;
  - `Future<SpaceOperation> operation(String id)`;
  - `Future<void> keep(String key, String title)`, `Future<void> unkeep(String key)`, `Future<void> dropPending(String hash)`.
  - Errori: `SpaceException(SpaceFailure failure)` con `enum SpaceFailure { invalid, unknown, busy, notReady, notFound, forbidden, network, server }`. 409 si legge da `Reason`; 404 di `start` → `unknown`, 404 di `operation`/`dropPending` → `notFound`.
- Produces (lighten):
  - `DownloadsApi.grab(String key, String guid, int indexerId, {bool lighten = false})`: con `lighten` aggiunge `'Lighten': true`;
  - `DownloadSearchController.grab(candidate, {bool lighten = false})` e `grabRelease(release, {bool lighten = false})`;
  - `showDownloadSearch(context, key, title, {reviewing = false, lighten = false})`, che passa `lighten` a ogni grab della pagina (anche "Scarica tutti").

- [ ] **Step 1: test che falliscono:**
  - `space_models_test.dart`:
    - `AFullOverviewIsRead`: un JSON con un candidato (tutti i campi, `Via` `["NobodyWatching"]`, un `Viewer`), un alleggerire, un torrent, un orfano, un'operazione con due passi → tutti i campi letti;
    - `ABrokenRowIsSkipped`: un candidato con `SizeBytes` stringa → saltato, l'altro letto;
    - `NullsAreAccepted`: `Quota` null, `ScannedAt` null → letti come null.
  - `space_api_test.dart` (con l'HTTP finto dei test di `downloads_api_test.dart`):
    - `StartPostsKindAndKey`: corpo `{"Kind":"Movie","Key":"movie:12"}`, risposta 202 `{"Id":"op1"}` → `"op1"`;
    - `BusyAndNotReadyAreRead`: 409 `{"Reason":"Busy"}` → `SpaceFailure.busy`; `NotReady` → `notReady`; 404 → `unknown`;
    - `UnkeepSendsTheKeyInTheQuery`: `DELETE …/Space/Kept?key=movie%3A12`.
  - `downloads_api_test.dart`: `GrabCanLighten` (corpo con `"Lighten":true`), e senza `lighten` il corpo non ha `Lighten`.
  - `download_search_controller_test.dart`: `ALightenGrabReachesTheApi`.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (`flutter analyze`, poi `flutter test`).
- [ ] **Step 5: commit** `git commit -m "feat(app): API dello spazio e alleggerisci nei download"`

### Task 2: etichette

**Files:**
- Create: `lib/features/space/space_labels.dart`
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/features/space/space_labels_test.dart`

**Interfaces:**
- Consumes: i modelli (Task 1).
- Produces:
  - `String spaceGb(AppLocalizations l, int bytes)` (due decimali, virgola in italiano) e `String spaceTb(AppLocalizations l, int bytes)`;
  - `List<String> spaceViaLines(AppLocalizations l, SpaceCandidate c, DateTime now)`:
    - `NobodyWatching`: "Visto da tutti, ultima visione {quando}" se tutti i `Viewers` hanno `finished`; "Abbandonato da tutti, …" se nessuno; altrimenti "Visto da {nomi}, abbandonato da {nomi}, …";
    - `NeverOpened`: "Mai aperto da {mesi} mesi";
    - `LowRating`: "Voto medio {media} su {n} voti";
    - `{quando}` in mesi ("8 mesi fa"), o in giorni sotto il mese;
  - `List<String> spaceKeepLabels(AppLocalizations l, SpaceCandidate c)`, con i testi della decisione 2. Per `RecentRequest` si usa la richiesta più recente;
  - `String spaceStepLabel(AppLocalizations l, SpaceStep step)` (nome + dettaglio, testi di Global Constraints);
  - `String spaceFailureLabel(AppLocalizations l, SpaceFailure f)`;
  - `String? spaceServiceError(AppLocalizations l, String service, String? code)`;
  - `List<String> spacePlannedSteps(AppLocalizations l, String kind)`: i passi in parole per la conferma, nell'ordine del piano 30a (Task 9).
- I testi in italiano e in inglese, con i plurali ICU dove c'è un numero.

- [ ] **Step 1: test che falliscono** (con `lookupAppLocalizations(const Locale('it'))`, `now` 2026-10-30):
  - `AllFinishedSaysWatchedByEveryone`: Anna e Luca `finished`, ultima visione 2026-02-28 → "Visto da tutti, ultima visione 8 mesi fa".
  - `MixedNamesWhoFinishedAndWhoNot`: Anna finito, Luca no → "Visto da Anna, abbandonato da Luca, ultima visione …".
  - `GbHasTwoDecimalsAndComma`: 12_345_000_000 → "12,35 GB".
  - `TheRemoveTorrentsStepCounts`: `RemoveTorrents` `Done` 1 `Waiting` 2 → "Tolgo i torrent: tolti 1, 2 in attesa del seed".
  - `ASkippedGoneStep`: `DeleteFromRadarr` `Skipped` `Gone` → "Elimino da Radarr con i file: non c'era più".
  - `PlannedStepsForAMovie`: `spacePlannedSteps(l, 'Movie')` → 7 righe, la terza "Elimino da Radarr con i file".
- [ ] **Step 2: i test falliscono** (`flutter gen-l10n`, poi `flutter test test/features/space/space_labels_test.dart`).
- [ ] **Step 3: il codice e le chiavi ARB.**
- [ ] **Step 4: i test passano** (`flutter gen-l10n`, `flutter analyze`, `flutter test`).
- [ ] **Step 5: commit** `git commit -m "feat(app): testi della scheda spazio"`

### Task 3: funzione `space`, scheda e controller della panoramica

**Files:**
- Create: `lib/features/space/space_providers.dart`, `lib/features/space/space_controller.dart`
- Modify: `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart`, `lib/features/admin/admin_navigation.dart`, `lib/features/admin/admin_screen.dart`
- Test: `test/features/admin/admin_navigation_test.dart`, `test/features/admin/admin_screen_test.dart`, `test/features/space/space_controller_test.dart`

**Interfaces:**
- Consumes: `SpaceApi` (Task 1).
- Produces:
  - `PluginFeatures.space = 'space'`; `SocialFeatures.space` (bool, `false`), letta come `downloads`;
  - `AdminTab.space` dopo `downloads`; `adminTabs({required bool inbox, required bool account, required bool downloads, required bool space})`; `adminTabLabel` → `l.adminTabSpace` ("Spazio" / "Storage");
  - `spaceApiProvider` (`Provider<SpaceApi>`);
  - `SpaceController extends AsyncNotifier<SpaceOverview>`, con `spaceControllerProvider`:
    - `build()` legge la panoramica (solo admin, come `DownloadsController`);
    - `reload()` tiene solo l'ultima risposta;
    - `recalculate()` → `api.recalculate()`, poi `reload()`;
    - `keep(key, title)`, `unkeep(key)`, `dropPending(hash)` → l'azione, poi `reload()`, e restituiscono `SpaceFailure?`.
  - `admin_screen.dart`: `AdminTab.space => SpaceTab(header: header)`. Finché il Task 4 non c'è, un segnaposto `SpaceTab` che mostra solo `AdminSectionTitle`.

- [ ] **Step 1: test che falliscono:**
  - `admin_navigation_test.dart`:
    - `AdminTab.parse('space')` → `AdminTab.space`;
    - `TheTabNeedsTheFeature`: `adminTabs(… space: false)` senza `space`, con `true` subito dopo `downloads`.
  - `admin_screen_test.dart`: con la funzione `space` la scheda "Spazio" c'è; senza, `tab=space` va su Sessioni.
  - `space_controller_test.dart`:
    - `KeepThenReloads`: `keep` chiama l'API e poi rilegge la panoramica;
    - `ANonAdminGetsNothing`: come il test equivalente della scheda Download.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (`flutter gen-l10n`, `flutter analyze`, `flutter test`).
- [ ] **Step 5: commit** `git commit -m "feat(app): scheda spazio nella dashboard admin"`

### Task 4: la scheda e la scheda del titolo

**Files:**
- Create: `lib/features/space/space_tab.dart`, `lib/features/space/space_rows.dart`, `lib/features/space/space_title_dialog.dart`
- Test: `test/features/space/space_tab_test.dart`, `test/features/space/space_title_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1–3; `itemProvider`, `playTrailer`, `showDownloadSearch` (con `lighten: true`).
- Produces:
  - `SpaceTab({Widget? header})`, che legge `spaceControllerProvider` con `AdminPoller` a 60 s, e a 5 s mentre `scanning` è vero (decisione 9);
  - `Future<void> showSpaceTitle(BuildContext context, SpaceCandidate candidate, {required bool favoriteGenre, required bool canLighten})`;
  - `Future<void> startSpaceOperation(BuildContext context, WidgetRef ref, {required String kind, required String key, required String title, SpaceCandidate? candidate, int? sizeBytes})`: conferma (decisione 5), poi `api.start`, poi `showSpaceOperation` (Task 5). Nel Task 4 basta la firma e la conferma; il riquadro arriva nel Task 5.
- **La scheda, dall'alto:**
  1. le note d'errore (`Errors`);
  2. una card con la quota ("{usati} TB su {totale} TB · liberi {liberi}"), una barra, la divisione in cinque voci, "Calcolato {quando}" e il pulsante "Ricalcola" (spento mentre `scanning`); prima del primo calcolo, "Calcolo in corso…";
  3. **Cancellare** (decisione 1): ogni riga ha locandina, titolo (con "Stagione N" per le stagioni), GB, "subito {GB}" / "dopo il seed {GB} dal {data}", le frasi dei segnali, le etichette "tienilo" ed eventualmente "Generi che guardi". Si tocca e si apre la scheda del titolo;
  4. **Alleggerire**: titolo (con la stagione), "{GB} · {gb/ora} GB/ora · {eccesso} in più". "Alleggerisci" apre `showDownloadSearch(context, key, title, lighten: true)` e alla chiusura rilegge la panoramica;
  5. **Pulizia**: tre gruppi.
     - Torrent: nome, tracker, GB, ratio, giorni; "Togli" o "In seed fino al {data}".
     - File orfani e doppioni: percorso, GB, "Cancella". Per i `linked`: "ha altri collegamenti, non libera spazio".
     - In cima "Togli tutti quelli possibili ora ({n}, {GB})", che avvia `AllTorrents` con chiave `all-torrents`;
  6. **In attesa di fine seed**: nome, titolo, data prevista, "Smetti di aspettare" (`dropPending`);
  7. **Tenuti**: titolo, "Togli" (`unkeep`);
  8. **Ultime operazioni**: titolo, stato, quando, GB. Si toccano e riaprono il riquadro (Task 5).
- Ogni sezione vuota mostra un `AdminEmptyText` ("Niente da cancellare", …).
- **La scheda del titolo** (decisione 3), con i pulsanti:
  - "Elimina" → `startSpaceOperation(kind: candidate.kind, …)`;
  - "Tienilo" → `keep`, poi chiude;
  - "Alleggerisci" → come sopra, solo se la stessa chiave è anche in `Lighten`.

- [ ] **Step 1: test che falliscono** (con una `SpaceOverview` finta nel provider):
  - `space_tab_test.dart`:
    - `BeforeTheFirstScanShowsCalculating`: `scannedAt` null, `scanning` vero → "Calcolo in corso…", nessuna sezione;
    - `SeasonsAreGroupedUnderTheSeries`: due stagioni con lo stesso `seriesKey` → una riga con il titolo della serie e la somma; aperta, due righe "Stagione 1" e "Stagione 2";
    - `TwentyRowsThenShowMore`: 25 candidati → 20 righe, "Mostra altri" → 25;
    - `LightenOpensTheSearchWithLighten`: il tocco su "Alleggerisci" apre la pagina di ricerca e il grab arriva con `lighten` (con una `DownloadsApi` finta);
    - `ServiceErrorsAreNotes`: `Errors.Qbit` `Unauthorized` → "qBittorrent: utente o password sbagliati", e le liste si vedono;
    - `NarrowLayoutHasNoHorizontalOverflow`: larghezza 360, titoli lunghi e tre segnali → nessun overflow.
  - `space_title_dialog_test.dart`:
    - `ShowsViewersRequestsAndButtons`: un candidato con Anna (finito), una richiesta di Luca, voto 1,5 → i nomi, la data, "Elimina", "Tienilo";
    - `WithoutItemIdStillWorks`: `itemId` null → niente trama né trailer, i pulsanti ci sono;
    - `KeepCallsTheApiAndCloses`.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (`flutter gen-l10n`, `flutter analyze`, `flutter test`).
- [ ] **Step 5: commit** `git commit -m "feat(app): liste dello spazio e scheda del titolo"`

### Task 5: conferma e progresso

**Files:**
- Create: `lib/features/space/space_operation_controller.dart`, `lib/features/space/space_operation_dialog.dart`
- Modify: `lib/features/space/space_tab.dart` (`startSpaceOperation` completa e "Ultime operazioni")
- Test: `test/features/space/space_operation_dialog_test.dart`

**Interfaces:**
- Consumes: `SpaceApi.start`/`operation` (Task 1), `spaceStepLabel`/`spacePlannedSteps` (Task 2), `SpaceController.reload` (Task 3).
- Produces:
  - `SpaceOperationController extends AsyncNotifier<SpaceOperation>` in una famiglia per id (`spaceOperationProvider(id)`). Legge `operation(id)` ogni secondo con un `Timer` finché `running`, e si ferma al primo `notFound` (stato d'errore) o quando il provider viene eliminato. Alla fine chiama `ref.read(spaceControllerProvider.notifier).reload()`.
  - `Future<void> showSpaceOperation(BuildContext context, String id)`: il riquadro della decisione 6.
  - `startSpaceOperation` completa: il pulsante che l'ha chiamata resta spento fino alla risposta di `start`. Un errore di `start` va in uno SnackBar con `spaceFailureLabel`.

- [ ] **Step 1: test che falliscono** (con `SpaceApi` finta e `fakeAsync`/`tester.pump(Duration(seconds: 1))`):
  - `TheConfirmListsTheStepsAndGb`: Elimina su un film con 5 GB subito e 2 GB dopo il seed il 19 novembre → la conferma mostra i 7 passi, "5,00 GB subito", "2,00 GB dopo il seed, dal 19 novembre".
  - `APackNoteWhenBytesStay`: `inPackBytes` 3 GB → la riga sul pack.
  - `StepsUpdateLive`: tre letture successive (`Running` con il primo passo `Running`; `Running` con il secondo `Done`; `Done`) → le icone e i testi cambiano, alla fine "Liberati {GB}" e una rilettura della panoramica.
  - `AFailedStepShowsWhy`: `RemoveTorrents` `Failed` `Unreachable` e i passi dopo `NotDone` → "Tolgo i torrent: non risponde", i successivi "non fatto".
  - `AMissingOperationStopsPolling`: `operation` → `notFound` → "Operazione non trovata", nessuna lettura dopo 3 secondi.
  - `DeleteIsDisabledWhileStarting`: due tocchi su "Elimina" (dopo la conferma) mentre `start` aspetta → una sola chiamata a `start`.
  - `ClosingKeepsTheOperationRunning`: chiudere il riquadro non chiama niente sull'API; la lettura si ferma.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (`flutter gen-l10n`, `flutter analyze`, `flutter test`).
- [ ] **Step 5: commit** `git commit -m "feat(app): conferma e progresso delle operazioni sullo spazio"`

### Task 6: versione e prova a mano

**Files:**
- Modify: `pubspec.yaml` (`version: 0.25.0`, con il build number che segue lo schema che c'è), `docs/superpowers/specs/2026-10-30-wonderflix-spazio-seedbox-design.md` ("Stato": piani 30a e 30b realizzati)

- [ ] **Step 1: versione 0.25.0** e "Stato" della spec.
- [ ] **Step 2: controlli:** `flutter gen-l10n`, `flutter analyze`, `flutter test`, tutti verdi.
- [ ] **Step 3: build di rilascio** da `app/`: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`. Basta che compili: la prova sul server vero la fa l'admin.
- [ ] **Step 4: commit** `git commit -m "chore(app): versione 0.25.0 con la scheda spazio"`
