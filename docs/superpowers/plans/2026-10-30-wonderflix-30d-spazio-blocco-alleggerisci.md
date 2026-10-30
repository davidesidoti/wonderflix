# WonderFlix — Piano 30d: eliminazione in blocco e progresso di Alleggerisci

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** due aggiunte alla scheda Spazio, approvate dall'admin il 2026-10-30 dopo la prova a mano:
1. **Alleggerisci con progresso:** una riga di Alleggerire con un download avviato da "Alleggerisci" mostra lo stato del download e sparisce quando il file leggero è importato.
2. **Eliminazione in blocco** in Cancellare: si selezionano più righe, si vede una panoramica, si conferma e una finestra mostra i passi di tutti i titoli, uno sotto l'altro.

**Architecture:**
- Plugin (Task 1):
  - `DownloadService` ricorda le chiavi dei grab "Alleggerisci" riusciti, con l'ora, in `downloads.json`;
  - `SpaceService` legge quelle chiavi e, a ogni `GET Space`, la coda di Radarr/Sonarr e i file attuali, e aggiunge lo stato alle righe di Alleggerire;
  - `Overview` diventa asincrono.
- App:
  - il Task 2 mostra lo stato nelle righe;
  - il Task 3 aggiunge la selezione, la panoramica e la finestra di progresso multipla. Nessun endpoint nuovo: un `POST Space/Operations` per titolo.

**Spec:** `docs/superpowers/specs/2026-10-30-wonderflix-spazio-seedbox-design.md`. Il Task 4 aggiunge §5.2a e §6.6.

**Decisioni** (dell'admin, salvo dove è scritto "mia"):
1. In blocco solo per **Cancellare** (film, serie, stagioni).
2. La panoramica elenca i titoli scelti (locandina, titolo, GB subito e dopo il seed), i totali, la nota sui pack e i passi previsti per ogni tipo.
3. L'esecuzione mostra **i passi di tutti uno sotto l'altro**:
   - un'intestazione per titolo con lo stato (in coda, in corso, fatto, non riuscito);
   - in fondo il totale liberato e quello in attesa del seed;
   - un titolo che fallisce non ferma gli altri;
   - chiudere la finestra non ferma niente.
4. Alleggerire mostra "In download {p} %" con una barra e i GB rimanenti, poi "In importazione". Il file leggero importato fa sparire la riga. Un download andato male fa tornare il pulsante "Alleggerisci", con l'etichetta "Download non riuscito".
5. (mia) La scheda si rilegge ogni 5 s finché una riga di Alleggerire è in download o in importazione, altrimenti ogni 60 s, come per il calcolo in corso.

## Global Constraints

- Plugin **1.16.0** (stessa versione, non ancora rilasciata). App **0.25.0** (idem).
- **JSON nuovo** in `SpaceLightenDto` (PascalCase, nullable sempre scritto):
  - `Download`: `SpaceLightenDownloadDto?` con `State` (`Downloading` | `Importing` | `Failed`), `Progress` (double 0–1, due decimali), `SizeLeftBytes` (long);
  - se la riga non ha un download di Alleggerisci è `null`.
- **Regole dello stato** (Task 1), per ogni chiave registrata come Alleggerisci (`movie:{id}` o `season:{id}:{n}`) presente in Alleggerire:
  - una voce nella coda del servizio per quel film, o per quella serie e stagione:
    - `trackedDownloadState` `downloading` → `Downloading`, con `Progress = 1 − sizeleft/size` (0 se size è 0) e `SizeLeftBytes = sizeleft`;
    - gli altri stati non falliti (`importPending`, `importing`, `importBlocked`) → `Importing`;
    - `failed` o `failedPending` → `Failed`;
  - nessuna voce in coda:
    - **importato** → la riga sparisce e la chiave si dimentica. Importato vuol dire che la dimensione attuale del titolo (film: `movieFile.size`; stagione: la somma dei file della stagione da `episodefile`) è sotto il 90% di `SizeBytes` della riga;
    - altrimenti, se il grab ha meno di 10 minuti → `Downloading` con `Progress` 0 e `SizeLeftBytes` 0 (Radarr/Sonarr non l'hanno ancora messo in coda);
    - altrimenti `Failed`.
  - Le chiavi più vecchie di 7 giorni si dimenticano.
  - Un servizio che non risponde lascia `Download` com'era nella lettura precedente (cache in memoria), o `null` se non c'è.
- **Costi:** una lettura della coda per servizio a ogni `GET Space`, solo se c'è almeno una chiave Alleggerisci. Il file attuale si legge solo per le chiavi non in coda.
- **Log:** mai titoli né percorsi; chiavi e conteggi sì.
- **App, eliminazione in blocco:**
  - **Avvio:** le operazioni si avviano in sequenza, una chiamata `start` dopo l'altra. Un `start` fallito (Busy, Unknown…) segna quel titolo come "non avviato" con il motivo e passa al successivo.
  - **Lettura dei passi:** ogni operazione avviata si legge con il controller per id che c'è già (`spaceOperationProvider(id)`). La finestra ne mostra più d'uno.
  - **Fine:** dopo l'ultima operazione finita la panoramica si rilegge una volta.
- **Testi** it/en in ARB, chiavi `space…`:
  - "Seleziona", "Annulla selezione", "Elimina selezionati ({n} · {gb})";
  - "{n} titoli";
  - "In download {p} %", "In importazione", "Download non riuscito", "{gb} rimanenti";
  - "Non avviato: {motivo}".
- **Regole per chi esegue:** come nei piani 30a e 30b (commit con l'identità del repository, niente trailer, niente parole che chiudono le issue, messaggi su una riga in italiano, niente push; mai processi per nome; PATH rinfrescato; suite intere verdi prima di ogni commit: plugin `dotnet test plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` + `dotnet build-server shutdown`, app `flutter gen-l10n`, `flutter analyze`, `flutter test` da `app/`).

## Review Focus

1. **Un grab Alleggerisci di una stagione con più voci in coda** (episodi singoli): lo stato è `Downloading` finché ce n'è una in download, e il progresso è quello complessivo (somma di sizeleft su somma di size). Test: Task 1 (`ASeasonWithSeveralQueueItemsSumsProgress`).
2. **Radarr giù durante un download:** la riga non diventa "non riuscito" ma tiene l'ultimo stato. Test: Task 1 (`AnUnreachableServiceKeepsTheLastStatus`).
3. **Selezione di una serie raggruppata e di una sua stagione insieme:** non si avviano due operazioni sulla stessa stagione. La serie raggruppata seleziona le sue stagioni una per una. Test: Task 3 (`SelectingAGroupSelectsItsSeasonsOnce`).
4. **Uno dei titoli va in 409 Busy:** gli altri partono e quello mostra "Non avviato". Test: Task 3 (`ABusyTitleDoesNotStopTheOthers`).
5. **Chiudere la finestra a metà:** nessun timer resta acceso. Riaprire un'operazione da "Ultime operazioni" funziona come prima. Test: Task 3 (`ClosingTheBulkDialogStopsPolling`).

---

### Task 1: plugin, stato del download di Alleggerisci

**Files:**
- Modify: `Downloads/DownloadBook.cs`, `Downloads/DownloadService.Admin.cs` (registrazione al grab con `lighten`), `Space/SpaceService.cs` / `Space/SpaceService.Scan.cs` (Overview asincrono), `Protocol/SpaceDtos.cs`, `Api/SpaceController.cs`, `PluginServiceRegistrator.cs` (se serve iniettare `DownloadService` in `SpaceService`)
- Create: `Space/SpaceService.Lighten.cs`
- Test: `Tests/SpaceLightenStatusTests.cs`, i test esistenti di `Overview`/controller adattati all'asincrono

**Interfaces:**
- `DownloadFile` / `DownloadBook`: `Dictionary<string, DateTimeOffset> Lightened` (in `downloads.json`, campo nuovo, vuoto se manca nei file vecchi); `Book.MarkLightened(key, at)`, `Book.ForgetLightened(key)`, `IReadOnlyDictionary<string, DateTimeOffset> Book.Lightened`.
- `DownloadService`:
  - `public IReadOnlyDictionary<string, DateTimeOffset> LightenedKeys()` (copia sotto lock);
  - `public void ForgetLightened(string key)`;
  - nel grab con `lighten` riuscito, `MarkLightened` per ogni chiave accettata.
- `SpaceLightenDownloadDto(string State, double Progress, long SizeLeftBytes)`; `SpaceLightenDto` gains `Download` (`SpaceLightenDownloadDto?`, sempre scritto).
- `SpaceService.OverviewAsync(Guid callerId, CancellationToken ct)` sostituisce `Overview`. Le regole sono quelle di Global Constraints e le dimenticanze si fanno via `DownloadService.ForgetLightened`.

- [ ] **Step 1: test che falliscono** in `Tests/SpaceLightenStatusTests.cs`:
  - `ADownloadingMovieShowsProgress`: coda Radarr `movieId` 12, size 4 GB, sizeleft 1 GB → `Downloading`, `Progress` 0,75, `SizeLeftBytes` 1 GB.
  - `ImportPendingIsImporting`.
  - `AFailedQueueItemIsFailed`.
  - `AnImportedLighterFileHidesTheRow`: niente coda, file attuale 3 GB con `SizeBytes` della riga 12 GB → la riga non c'è e la chiave è dimenticata.
  - `ARecentGrabNotYetQueuedIsDownloading`: grab di 5 minuti fa → `Downloading` 0.
  - `AnOldGrabWithoutQueueIsFailed`: 20 minuti fa → `Failed`.
  - `ASeasonWithSeveralQueueItemsSumsProgress`: due voci della stagione, una importata e una in download → `Downloading`, progresso complessivo.
  - `AnUnreachableServiceKeepsTheLastStatus`.
  - `KeysOlderThanSevenDaysAreForgotten`.
  - `RowsWithoutLightenHaveNoDownload` (`Download` null nel JSON).
  - In `DownloadService`: `ALightenGrabIsRemembered` e la lettura di un `downloads.json` vecchio senza `Lightened`.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: la suite intera passa.**
- [ ] **Step 5: commit** `git commit -m "feat(plugin): stato del download di Alleggerisci nella scheda spazio"`

### Task 2: app, progresso nelle righe di Alleggerire

**Files:**
- Modify: `lib/core/space/space_models.dart` (`SpaceLightenDownload`), `lib/features/space/space_rows.dart` (`SpaceLightenRow`), `lib/features/space/space_tab.dart` (polling a 5 s anche con download in corso), `lib/features/space/space_labels.dart`, ARB
- Test: `test/core/space/space_models_test.dart`, `test/features/space/space_tab_test.dart`

**Interfaces:** `SpaceLightenDownload(state, progress, sizeLeftBytes)`; `SpaceLighten.download` (nullable).

- [ ] **Step 1: test che falliscono:**
  - `ALightenDownloadIsRead` (modello);
  - `ADownloadingLightenRowShowsProgress`: barra, "In download 75 %", "1,00 GB rimanenti", nessun pulsante Alleggerisci;
  - `ImportingShowsTheLabel`;
  - `AFailedDownloadShowsTheButtonAgain`: etichetta "Download non riuscito" e il pulsante;
  - `PollingIsFastWhileDownloading`: intervallo del poller a 5 s.
- [ ] **Step 2–4:** rosso, codice, verde (`flutter gen-l10n`, `flutter analyze`, `flutter test`).
- [ ] **Step 5: commit** `git commit -m "feat(app): progresso del download di Alleggerisci"`

### Task 3: app, eliminazione in blocco

**Files:**
- Create: `lib/features/space/space_bulk.dart` (stato della selezione, panoramica, avvio), `lib/features/space/space_bulk_dialog.dart` (finestra dei passi di tutti)
- Modify: `lib/features/space/space_tab.dart`, `space_rows.dart` (casella sulle righe e sui gruppi), `space_operation_dialog.dart` (estrarre il widget dei passi di un'operazione per riusarlo, senza cambiarne il comportamento), ARB
- Test: `test/features/space/space_bulk_test.dart`

**Interfaces:**
- `spaceSelectionProvider` (Notifier di un `Set<String>` di chiavi; si svuota quando la panoramica non ha più quelle chiavi);
- `Future<void> startSpaceBulk(BuildContext, WidgetRef, List<SpaceCandidate>)` (panoramica, conferma, avvio in sequenza, finestra);
- `showSpaceBulkProgress(BuildContext, List<SpaceBulkItem>)` con `SpaceBulkItem(title, kind, operationId?, failure?)`.

- [ ] **Step 1: test che falliscono:**
  - `SelectModeShowsCheckboxesAndTheBar`: "Seleziona" → caselle; due righe scelte → "Elimina selezionati (2 · {gb})";
  - `SelectingAGroupSelectsItsSeasonsOnce`;
  - `TheSummaryListsTitlesAndTotals`: titoli, totale subito e dopo il seed, nota sul pack, passi per tipo;
  - `StartsOneOperationPerTitleInOrder`;
  - `ABusyTitleDoesNotStopTheOthers`;
  - `StepsOfAllTitlesAreShownLive`: due operazioni lette con risposte successive → intestazioni con lo stato e i passi di entrambe, totale liberato alla fine, una rilettura della panoramica;
  - `ClosingTheBulkDialogStopsPolling`;
  - `CancelSelectionClears`.
- [ ] **Step 2–4:** rosso, codice, verde.
- [ ] **Step 5: commit** `git commit -m "feat(app): eliminazione in blocco nella scheda spazio"`

### Task 4: spec

- [ ] Spec U: §5.2a "Alleggerisci con progresso" (regole di Global Constraints) e §6.6 "Eliminazione in blocco" (decisioni 1–3). Commit `git commit -m "docs: spec U, blocco e progresso di Alleggerisci"`.
