# WonderFlix — Piano 29b: download automatici, app 0.23.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte app della Spec T (§8): nuova scheda "Download" nella dashboard admin, con la panoramica ("Serve te", "Scelte automatiche", "In attesa", "Da ripassare") e la ricerca di un titolo con la regola, "scarica", "cambia", "va bene così" e "ricerca di nuovo". PC e web, layout largo e stretto.

**Architecture:**
- `lib/core/downloads/`: modelli e `DownloadsApi` sugli endpoint del piano 29a.
- `lib/features/downloads/`: i controller Riverpod (panoramica con rilettura periodica, ricerca per chiave), le etichette e i widget.
- La scheda si aggiunge ad `AdminTab` e compare solo con la funzione `downloads` del plugin.

**Tech Stack:** Flutter 3.47.5, Riverpod, dio (`JellyfinHttp`), `flutter_test`, ARB it/en.

**Spec:** `docs/superpowers/specs/2026-10-28-wonderflix-download-automatici-design.md` (§8; JSON nel piano 29a, "Global Constraints"). Bozza delle schermate: `.superpowers/brainstorm/1831-1793204853/content/download-tab-v2.html` (nel checkout principale, non nel repo).

**Prerequisito:** il piano 29a finito (plugin 1.14.0) sullo stesso branch.

**Decisioni del piano:**
1. **La ricerca di un titolo è una pagina a schermo intero** sopra la dashboard (`showDialog` con `Dialog.fullscreen`), non un indirizzo nuovo: si apre solo dalle righe della scheda.
2. **Il "perché" della scelta lo compone l'app** dai dati: "Il più leggero tra quelli con punteggio {score} in {res}p". Il plugin non manda testi.
3. **"Scelte automatiche"** mostra gli ultimi 7 giorni; "Mostra altre" le fa vedere tutte (90 giorni, dal plugin). **"Da ripassare"** ne mostra 50; "Mostra altre" altre 50.
4. **Rilettura della panoramica** ogni 60 secondi mentre la scheda è aperta (`AdminPoller`), e subito dopo ogni azione.
5. **Conferma prima di scaricare** quando la release ha punteggio ≤ quello del file attuale o `WouldImport` è falso; il testo dice quale dei due casi.
6. **Pesi** in GB con due decimali e la virgola in italiano, come `media_info_dialog.dart` (`_bytesPerGb` = 10⁹).

## Global Constraints

- App **0.23.0** (`pubspec.yaml`; se intanto 0.23.0 è uscita con un altro lavoro, la successiva libera, da segnalare).
- **Funzione** `downloads` (`PluginFeatures.downloads`), letta come le altre in `SocialAvailability`; senza, la scheda non c'è.
- **Scheda** `AdminTab.downloads`, tra `activity` e `wonderflix`; parametro dell'indirizzo `tab=downloads`.
- **Endpoint e JSON:** esattamente quelli del piano 29a, "Global Constraints" (PascalCase, campi null ammessi ovunque). Lettura tollerante: un campo mancante o di tipo sbagliato non rompe la pagina, la riga si salta.
- **Ricerca:** `GET /WonderFlixWatchParty/Downloads/Search?key=` con `receiveTimeout` di **150 secondi** (il plugin aspetta Radarr/Sonarr fino a 2 minuti).
- **Errori:** 400 → "Richiesta non valida"; 409 `Expired` → "Questa release non c'è più: ricerca di nuovo"; 401/403 → come le altre schede admin; rete → messaggio di rete. Codici `SonarrError`/`RadarrError` (`NotConfigured`, `Unauthorized`, `Unreachable`) con le etichette che ci sono già per il calendario, se ci sono; altrimenti nuove.
- **Testi:** italiano e inglese in `l10n/app_it.arb` e `l10n/app_en.arb`, chiavi che iniziano con `downloads`. Si generano con `flutter gen-l10n`.
- **Commit:** con l'identità git del repository; **mai** trailer `Co-Authored-By` né righe "Generated with…"; mai le parole `closes`, `fixes`, `resolves` (né simili) nei messaggi; messaggi in italiano.
- **Processi:** mai terminarli per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`); solo per PID.
- **Build di rilascio** (se serve una prova a mano): `flutter build windows --release --dart-define-from-file=config/wonderflix.json`, da `app/`.

## Review Focus

1. **Una ricerca che dura un minuto e mezzo:** la pagina mostra l'attesa senza scadere prima, e chiuderla prima della fine non lascia errori a schermo. Test: Task 1 (`SearchWaitsUpToTwoAndAHalfMinutes`), Task 4 (`ClosingDuringASearchIsQuiet`).
2. **Due "scarica" di fila sulla stessa pagina:** il pulsante si spegne finché la prima non risponde, così non partono due download. Test: Task 4 (`GrabIsDisabledWhileRunning`).
3. **Telefono (layout stretto):** le righe della ricerca vanno a capo come schede, senza scorrimento orizzontale della pagina. Test: Task 4 (`NarrowLayoutHasNoHorizontalOverflow`).
4. **Plugin vecchio (senza `downloads`) o funzione che sparisce mentre la scheda è aperta:** la scheda non c'è e la dashboard va su Sessioni, come per le altre schede del plugin. Test: Task 3 (`TheTabNeedsTheFeature`).
5. **Un JSON con una riga rotta** (per esempio `SizeBytes` stringa): la riga si salta e le altre si vedono. Test: Task 1 (`ABrokenRowIsSkipped`).

---

## Regole per chi esegue

- **Commit:** come nel piano 29a: identità del repository, niente trailer, niente push, niente parole che chiudono le issue, una riga in italiano.
- **Processi:** mai per nome d'immagine.
- **Shell:** PowerShell su Windows.
  - Prima di `flutter` o `git`, rinfresca il PATH:
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Si lavora in `.claude/worktrees/download-automatici/app`; mai nel checkout principale.
  - "Cannot create link … errno 183": `flutter clean`.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit**: `flutter gen-l10n`, `flutter analyze` (nessun problema), `flutter test` (tutto verde);
  - il primo implementatore conta i test verdi di partenza e li scrive nel registro.
- **Stile dell'app:** commenti in italiano, codice in inglese, riferimenti alla spec ("spec T §8.1"); colori e testi da `WfColors`/`WfText`; i widget della dashboard da `admin_widgets.dart` (`AdminCard`, `AdminSectionTitle`, `AdminEmptyText`, `AdminCardError`, `adminTabState`), `AdminActionButton`, `showAdminConfirmDialog`, `AdminPoller`; margini con `adminSideMargin`; layout con `FormFactor.of(context).compact`.
- **Se il codice del piano ha un errore:** correggilo in modo minimo, nello spirito del piano, e segnalalo.

## Note tecniche verificate

Verificate il 2026-10-28 sul codice di `main` (`716e744`).

- `JellyfinHttp.get(path, {query, cancelToken, quietStatuses})` non ha `receiveTimeout`; `post` sì (`Options(receiveTimeout: …)`). Base: 30 s.
- `ReportsApi` (`lib/core/reports/reports_api.dart`) è il modello per un'API del plugin: `_base`, `_quiet`, un'eccezione con un enum di fallimenti, `_call` che traduce gli errori.
- `PluginFeatures` in `lib/core/social/social_models.dart`; `SocialFeatures` e `SocialAvailability` in `lib/features/social/social_providers.dart` (campo, `==`, `hashCode`, `toString`, lettura da `info.features`, come `calendar`).
- `adminTabs({required bool inbox, required bool account})` e `adminTabLabel` in `admin_navigation.dart`; `admin_screen.dart` legge le funzioni con `socialAvailabilityProvider.select` e fa lo `switch` delle schede.
- `AdminReportsController` (`lib/features/reports/admin_reports_controller.dart`): `AsyncNotifier` admin-only con `_loads` per tenere solo l'ultima risposta.

## File

| File | Responsabilità |
|---|---|
| `lib/core/downloads/download_models.dart`, `lib/core/downloads/downloads_api.dart`, `lib/core/jellyfin/jellyfin_http.dart` | modelli, chiamate, `receiveTimeout` per `get` |
| `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart` | la funzione `downloads` |
| `lib/features/downloads/downloads_providers.dart`, `downloads_controller.dart`, `download_search_controller.dart`, `download_labels.dart` | stato e testi |
| `lib/features/downloads/downloads_tab.dart`, `download_rows.dart`, `download_search_page.dart` | i widget |
| `lib/features/admin/admin_navigation.dart`, `admin_screen.dart` | la scheda |
| `l10n/app_it.arb`, `l10n/app_en.arb`, `pubspec.yaml`, `../docs/RELEASING.md` | testi, versione, checklist |

Percorsi relativi ad `app/`, se non è detto altro.

---

### Task 1: modelli e `DownloadsApi`

**Files:**
- Create: `lib/core/downloads/download_models.dart`, `lib/core/downloads/downloads_api.dart`
- Modify: `lib/core/jellyfin/jellyfin_http.dart`, `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart`
- Test: `test/core/downloads/download_models_test.dart`, `test/core/downloads/downloads_api_test.dart`, i test di `SocialAvailability` che controllano le funzioni

**Interfaces:**
- Produces:
  - Modelli immutabili con `static X? fromJson(Map<String, dynamic>)` e `static List<X> listFromJson(Object?)` (righe non valide saltate): `DownloadRelease`, `DownloadChoice`, `DownloadItem`, `ReviewItem`, `DownloadsOverview`, `DownloadCandidate`, `DownloadRejected`, `DownloadCurrentFile`, `DownloadSearch`. Campi = quelli JSON del piano 29a in camelCase Dart (`sizeBytes`, `previousScore`, …); date `DateTime` UTC.
  - Enum con `fromWire(String?)` e un valore `unknown`: `DownloadKind { movie, episode, season, unknown }`, `DownloadState { waiting, downloading, upgradeWatch, needsYou, unknown }`, `DownloadReason { nothingFound, belowMinScore, importBlocked, searchFailed, unknown }`, `RejectedReason { arr, tooSmall, unknown }`.
  - `enum DownloadsFailure { unavailable, invalid, forbidden, expired, network }`; `class DownloadsException implements Exception { final DownloadsFailure failure; }`.
  - `class DownloadsApi(JellyfinHttp http)`: `Future<DownloadsOverview> overview()`, `Future<DownloadSearch> search(String key, {CancelToken? cancelToken})`, `Future<void> grab(String key, String guid, int indexerId)`, `Future<void> accept(String key)`, `Future<void> searchNow(String key)`. `static const searchTimeout = Duration(seconds: 150)`.
  - `JellyfinHttp.get` impara `Duration? receiveTimeout`, come `post`.
  - `PluginFeatures.downloads = 'downloads'`; `SocialFeatures.downloads` (bool, falso di base).

- [ ] **Step 1: test che falliscono:**
  - `download_models_test.dart`: `AnOverviewParses` (un JSON completo con una scelta, una voce `NeedsYou`/`BelowMinScore`, una riga da ripassare); `ASearchParses` (candidati, scarti con `TooSmall` e `Detail` `"0.57"`, `Current`); `ABrokenRowIsSkipped` (`SizeBytes` `"tanti"` in un candidato su tre → due); `UnknownValuesAreUnknown` (`State` `"Exploded"` → `unknown`).
  - `downloads_api_test.dart` (con il finto `JellyfinHttp` dei test di `ReportsApi`): `SearchWaitsUpToTwoAndAHalfMinutes` (la GET di `Search` ha `receiveTimeout` 150 s e la chiave in `query`), `GrabPostsKeyGuidAndIndexer` (corpo `{"Key","Guid","IndexerId"}`), `ConflictIsExpired` (409 → `expired`), `NotFoundIsUnavailable` (404), `BadRequestIsInvalid` (400).
  - Test di `SocialAvailability`: `downloads` vero quando `Info.Features` lo contiene.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice**, sul modello di `ReportsApi`.
- [ ] **Step 4: i test passano**, poi `flutter analyze` e `flutter test`.
- [ ] **Step 5: commit** `git commit -m "feat(app): modelli e chiamate dei download automatici"`

### Task 2: controller e etichette

**Files:**
- Create: `lib/features/downloads/downloads_providers.dart`, `downloads_controller.dart`, `download_search_controller.dart`, `download_labels.dart`
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/features/downloads/downloads_controller_test.dart`, `download_search_controller_test.dart`, `download_labels_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `final downloadsApiProvider = Provider<DownloadsApi>(…)` (da `jellyfinHttpProvider`).
  - `DownloadsController extends AsyncNotifier<DownloadsOverview>` (`downloadsControllerProvider`, autoDispose): legge solo per un admin con la funzione `downloads`, altrimenti una panoramica vuota; `Future<void> reload()`; vale solo l'ultima risposta (come `AdminReportsController._loads`).
  - `DownloadSearchController extends AutoDisposeFamilyAsyncNotifier<DownloadSearch, String>` (`downloadSearchControllerProvider(key)`): `build` fa la ricerca; `Future<void> searchAgain()`; `Future<DownloadsFailure?> grab(DownloadCandidate c)` e `Future<DownloadsFailure?> accept()`, che dopo un successo rileggono la panoramica (`ref.invalidate(downloadsControllerProvider)`); `bool get busy` (vero durante `grab`/`accept`). Un `CancelToken` annulla la ricerca quando il provider si smonta.
  - `download_labels.dart`:
    - `String formatGb(AppLocalizations l, int bytes)` (decisione 6);
    - `String downloadStateLabel(AppLocalizations l, DownloadItem item)`: "In attesa", "In download", "Cerca un upgrade", "Serve te: {motivo}";
    - `String downloadReasonLabel(AppLocalizations l, DownloadReason r)`: "nessun file valido", "solo file con punteggio basso", "Radarr/Sonarr non lo importano", "ricerca non riuscita";
    - `String rejectedLabel(AppLocalizations l, DownloadRejected r)`: `tooSmall` → "{detail} GB/ora, sotto la soglia"; `arr` → il `Detail` così com'è;
    - `String choiceWhy(AppLocalizations l, DownloadCandidate c)` (decisione 2);
    - `String nextSearchLabel(AppLocalizations l, DateTime? at, DateTime now)`: "prossima ricerca tra {n} h" / "domani" / "il {data}".

- [ ] **Step 1: test che falliscono:**
  - `downloads_controller_test.dart`: `NonAdminsGetNothing` (nessuna chiamata), `WithoutTheFeatureGetsNothing`, `OnlyTheLastAnswerCounts`.
  - `download_search_controller_test.dart`: `GrabReloadsTheOverview`, `GrabIsBusyUntilItAnswers`, `ExpiredIsReturned` (`grab` dà `DownloadsFailure.expired` e la ricerca resta a schermo), `DisposingCancelsTheSearch`.
  - `download_labels_test.dart`: `GigabytesUseTheItalianComma` (1 890 000 000 → "1,89 GB" in it, "1.89 GB" in en), `TheChoiceExplainsItself` (150, 1080 → testo con "150" e "1080p"), `TooSmallShowsTheRate`.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice**, con le chiavi ARB nuove in it e en.
- [ ] **Step 4: i test passano**, poi `flutter gen-l10n`, `flutter analyze`, `flutter test`.
- [ ] **Step 5: commit** `git commit -m "feat(app): stato e testi dei download automatici"`

### Task 3: la scheda "Download" (panoramica)

**Files:**
- Create: `lib/features/downloads/downloads_tab.dart`, `lib/features/downloads/download_rows.dart`
- Modify: `lib/features/admin/admin_navigation.dart`, `lib/features/admin/admin_screen.dart`, ARB
- Test: `test/features/downloads/downloads_tab_test.dart`, `test/features/admin/admin_navigation_test.dart`, `test/features/admin/admin_screen_test.dart`

**Interfaces:**
- Consumes: Task 2.
- Produces:
  - `AdminTab.downloads` (dopo `activity`); `adminTabs({required bool inbox, required bool account, required bool downloads})` (tutti i chiamanti aggiornati); etichetta "Download" / "Downloads".
  - `DownloadsTab({Widget? header})` (`ConsumerStatefulWidget`, come le altre schede): `AdminPoller` a 60 secondi (decisione 4); stato con `adminTabState`; se `Enabled` è falso, una nota in cima: "Download automatici spenti: WonderFlix non scarica da solo. Ricerca e Da ripassare funzionano." Errori di Sonarr/Radarr con `AdminCardError`.
  - Sezioni nell'ordine, con `AdminSectionTitle` e il numero:
    1. **Serve te** (solo se non vuota): le voci `NeedsYou`, pulsante "Guarda".
    2. **Scelte automatiche**: `DownloadChoiceRow` (poster, titolo, release, peso, punteggio come pastiglia, indexer, quando; "upgrade" con prima → dopo se `PreviousScore` c'è; "scelta tua" se `ByAdmin`), pulsante "Cambia"; 7 giorni e "Mostra altre" (decisione 3).
    3. **In attesa**: `DownloadItemRow` per `Waiting`, `Downloading`, `UpgradeWatch` (titolo, stato, uscita o da quanto, prossima ricerca); pulsanti "Guarda" e "Cerca ora" (`searchNow`).
    4. **Da ripassare**: `ReviewRow` (titolo, punteggio e peso del file attuale), pulsante "Apri"; 50 e "Mostra altre"; sotto il titolo "aggiornato {quando}" da `ReviewAt`.
  - "Guarda", "Cambia", "Apri" chiamano `showDownloadSearch(context, key, title)` (Task 4).

- [ ] **Step 1: test che falliscono:**
  - `admin_navigation_test.dart`: `TheTabNeedsTheFeature` (senza `downloads` non c'è; con, viene dopo Registro); `ParsesDownloads` (`tab=downloads`).
  - `admin_screen_test.dart`: la scheda c'è con la funzione; senza, l'indirizzo `tab=downloads` va su Sessioni.
  - `downloads_tab_test.dart`: `SectionsComeInOrder`; `NeedsYouHidesWhenEmpty`; `OnlySevenDaysUntilShowMore`; `ReviewShowsFiftyAtATime`; `DisabledShowsTheNote`; `AServiceErrorIsShown`; `AnUpgradeShowsBeforeAndAfter`.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.** Le righe come nella bozza: poster piccolo (`CachedNetworkImage` o il widget di poster che usano già le righe della Home, con `PosterUrl` di Radarr/Sonarr), pastiglie con `WfColors.online` per 150 o più, `WfColors.gold` sotto l'obiettivo, `WfColors.error` per "Serve te".
- [ ] **Step 4: i test passano**, poi `flutter gen-l10n`, `flutter analyze`, `flutter test`.
- [ ] **Step 5: commit** `git commit -m "feat(app): scheda Download nella dashboard admin"`

### Task 4: la ricerca di un titolo

**Files:**
- Create: `lib/features/downloads/download_search_page.dart`
- Modify: ARB
- Test: `test/features/downloads/download_search_page_test.dart`

**Interfaces:**
- Consumes: Task 2 e 3.
- Produces:
  - `Future<void> showDownloadSearch(BuildContext context, String key, String title)` (decisione 1).
  - In alto: titolo, durata, file attuale (peso, punteggio, qualità) o "nessun file", "{validi} risultati validi su {totali}", pulsante "Ricerca di nuovo".
  - Durante la ricerca: attesa con il testo "Cerco su Radarr/Sonarr, può volerci un minuto".
  - **Candidati**, in ordine: numero, release, punteggio, peso, seeders, indexer, pulsante "Scarica". La scelta è evidenziata (sfondo `WfColors.calendarMovie`, come la bozza) con `choiceWhy` sotto. Largo: una tabella; stretto: una scheda per release con le stesse informazioni.
  - **Scartati** sotto, in grigio, con `rejectedLabel`.
  - "Scarica": conferma per decisione 5 (`showAdminConfirmDialog`); spento mentre `busy`; dopo il successo uno SnackBar "Download avviato" e la pagina si chiude; con `expired` un messaggio e la ricerca resta.
  - "Va bene così" (solo per una chiave in "Da ripassare", cioè quando la pagina è aperta da `ReviewRow`: parametro `bool reviewing` di `showDownloadSearch`): `accept`, poi si chiude.
  - Errore della ricerca (`Error` nel DTO o eccezione): messaggio e "Riprova".

- [ ] **Step 1: test che falliscono:** `TheChoiceIsHighlightedWithItsReason`; `RejectedAreGreyWithTheirReason`; `ALowerScoreAsksFirst` (punteggio uguale al file attuale → conferma; annullare non scarica); `ANonImportAsksFirst` (`WouldImport` falso → conferma con il testo dell'import manuale); `GrabIsDisabledWhileRunning`; `ExpiredKeepsThePage`; `AcceptOnlyWhenReviewing`; `ClosingDuringASearchIsQuiet` (chiudere durante l'attesa: nessun errore e nessun SnackBar); `NarrowLayoutHasNoHorizontalOverflow` (larghezza 375: nessun overflow, le release sono schede).
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano**, poi `flutter gen-l10n`, `flutter analyze`, `flutter test`.
- [ ] **Step 5: commit** `git commit -m "feat(app): ricerca di un titolo con la regola dell'admin"`

### Task 5: versione, checklist, spec

**Files:**
- Modify: `pubspec.yaml`, `../docs/RELEASING.md`, `../docs/superpowers/specs/2026-10-28-wonderflix-download-automatici-design.md`

- [ ] **Step 1: versione** 0.23.0 in `pubspec.yaml` (vedi Global Constraints).
- [ ] **Step 2: checklist.** In `docs/RELEASING.md`, "Checklist dei test manuali", le voci della scheda Download: si vede solo da admin con il plugin 1.14.0; la ricerca di un film mostra la scelta e gli scarti; "Scarica" chiede conferma per un punteggio non migliore; "Cambia" toglie il download precedente da qBittorrent; "Va bene così" toglie il titolo da "Da ripassare"; layout stretto dal telefono.
- [ ] **Step 3: spec.** **Stato** "piani 29a e 29b realizzati" e le decisioni di questo piano dove precisano §8.
- [ ] **Step 4:** `flutter gen-l10n`, `flutter analyze`, `flutter test`, tutto verde.
- [ ] **Step 5: commit** `git commit -m "chore: versione 0.23.0, spec T realizzata"`
