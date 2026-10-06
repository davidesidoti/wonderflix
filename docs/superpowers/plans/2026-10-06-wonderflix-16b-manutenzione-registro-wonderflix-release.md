# WonderFlix — Piano 16b: Manutenzione, Registro, WonderFlix, release

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** seconda metà della Spec J. La pagina Amministrazione riceve tre schede nuove:
- **Manutenzione:** librerie con "Scansiona" e "Scansiona tutte"; attività pianificate con stato, Avvia e Ferma;
- **Registro:** il registro attività di Jellyfin a pagine, con i filtri Tutto / Utenti / Sistema;
- **WonderFlix** (solo con il plugin): annuncio, novità (interruttore e "Invia ora"), stato e prova di Seerr.

Poi la release dell'app 0.10.0. Il plugin non cambia.

**Spec:** `docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md` (§8.1, §8.2, §8.3, §9.4–9.6, §11, §12, §13, §15).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 10):
1. **Scansione di una libreria come la Dashboard web 10.11.9.** `refreshdialog.js`, nel modo "scan", manda `Recursive=true`, `ImageRefreshMode=Default`, `MetadataRefreshMode=Default`, `ReplaceAllImages=false`, `RegenerateTrickplay=false` e `ReplaceAllMetadata=false`. L'app manda gli stessi.
2. **Ordine delle attività:** per categoria e poi per nome, senza badare alle maiuscole, come la Dashboard web. Il server le dà ordinate solo per nome, quindi "l'ordine del server" della spec mescolerebbe le categorie.
3. **Registro senza avatar:** Jellyfin dà solo l'id dell'utente, e il nome è già nel testo della voce ("viviroby è online su …"). La riga ha l'icona della gravità.
4. **Letture JSON in comune:** le letture tolleranti di `admin_models.dart` (`_string`, `_int`…) passano in `lib/core/jellyfin/json_fields.dart` come funzioni pubbliche, usate anche dai modelli nuovi (`maintenance_models.dart`, `activity_models.dart`, `plugin_admin_models.dart`). `admin_models.dart` riesporta `isEmptyJellyfinId`.
5. **Azioni:** `AdminTabController.act()` esegue un'azione, rilegge l'utente dopo un 403 e rilegge la scheda alla fine. I pulsanti delle azioni sono `AdminActionButton`: disattivati mentre l'azione è in corso, e un errore diventa un avviso con `describeError`.
6. **WonderFlix in due controller:** `InboxAdminController` (novità, annuncio, interruttore, "Invia ora") e `SeerrAdminController` (stato e prova). Ogni card ha il suo stato e il suo errore (spec §9.6).
7. **Tipo dell'ultimo evento di Seerr:** oltre a "Richiesta in attesa" (`MEDIA_PENDING`) e "Richiesta disponibile" (`MEDIA_AVAILABLE`), anche "Messaggio di prova" (`TEST_NOTIFICATION`, quello del pulsante Test di Seerr). Gli altri tipi restano come arrivano.
8. **"Inviati {titles} titoli a {recipients} persone"** è fatto di due testi, uno per il plurale dei titoli e uno per quello delle persone.
9. **Durata delle attività:** "45 s", "3 min", "1 h 5 min".
10. **Data completa nel Registro** (passaggio del mouse): "6 ott 2026, 08:10:00".
11. **Schede nell'indirizzo:** `?tab=sessions|maintenance|activity|wonderflix`. Senza la funzione `inbox` la scheda WonderFlix non c'è, e `?tab=wonderflix` mostra Sessioni.

**Architecture:**
- **Dati:**
  - `AdminApi` riceve `libraries`, `scanAll`, `scanLibrary`, `tasks`, `startTask`, `stopTask`, `activity`;
  - modelli nuovi: `LibraryFolder`, `ScheduledTask`, `TaskResult` in `maintenance_models.dart`; `ActivityEntry`, `ActivityPage` in `activity_models.dart`;
  - `PluginAdminApi` (`lib/core/social/`) con `NewTitlesStatus`, `NewTitlesSent`, `SeerrAdminStatus`, `SeerrTestResult`.
- **Controller:**
  - `MaintenanceController` (`AdminTabController`, 15 s, o 2 s quando qualcosa è in corso);
  - `ActivityController` (pagine da 50, filtri, nessuna rilettura automatica);
  - `InboxAdminController` e `SeerrAdminController` (`AdminTabController`, 30 s).
- **Interfaccia:** `MaintenanceTab`, `ActivityTab`, `WonderflixTab`, `AdminActionButton`, `showAdminConfirmDialog`, `AdminCard`; `AdminScreen` con quattro schede.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.4, go_router 18, lucide_icons_flutter, clock, intl, fake_async (test).

**Worktree:** `.claude/worktrees/piano-16b`, branch `feat/piano-16b`. **Base:** `main` con questo piano. **Test a inizio piano:** da contare all'avvio; a fine piano 16a erano 1997 Flutter.

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git già configurata (quella dell'utente).
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:**
  - Git Bash su Windows.
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-16b`).
  - Comandi git semplici: niente `git -C`, niente variabili nei comandi git.
  - Mai `git checkout -- <file>` su un file che hai modificato. Mai `git stash` senza nome.
- **Prima di ogni commit:** `flutter analyze` senza problemi e `flutter test` tutto verde (la suite intera). Se un solo test estraneo fallisce una volta in caricamento ("did not complete"), rilancia la suite e segnalalo.
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga. Molti file della working copy sono CRLF (per esempio gli ARB, `jellyfin_http.dart`, `app_shell.dart`), l'indice è LF con `core.autocrlf=true`. I file nuovi del 16a e del 16b sono LF. Controlla che non ci siano fini riga misti.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) e controlla con `iconv -f UTF-8 -t UTF-8 <file>`. Non usare strumenti che cambiano la codifica.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; `clock.now()`, mai `DateTime.now()`.
- **Spinner e `pumpAndSettle`:** un `CircularProgressIndicator` o un `LinearProgressIndicator` senza valore non si ferma mai, quindi `pumpAndSettle` va in timeout. Le barre del piano hanno sempre un valore; mentre c'è uno spinner usa `pump()`.
- **Timer nei test:** le schede rileggono con dei timer. Nei test di controller usa `fakeAsync` (o `pumpEventQueue` se basta la prima lettura). Nei widget test i timer si chiudono quando l'albero si smonta.
- **Liste nei test:** un `ListView` costruisce i figli solo vicino allo schermo; per un elemento in basso usa `tester.scrollUntilVisible` sul `Scrollable` giusto.
- **Provider `autoDispose`:** restano vivi solo con un ascoltatore; nei test di controller usa `container.listen(...)` prima di leggere.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-06 sul codice di `main` (`198f047`) e sul server, in sola lettura.

**Dal piano 16a (com'è adesso il codice)**
- **`AdminTabController<T>`** (`lib/features/admin/admin_tab_controller.dart`):
  - si estende con `Duration get interval` e `Future<T> fetch()`; offre `refresh()` e `setInterval(Duration)`;
  - rilegge solo con la finestra in vista e la pagina visibile (`onCancel`/`onResume`), e dopo un riavvio (`adminEpochProvider`);
  - in `_read` un 403 fa `refreshUser()`; lo stato è `AdminData<T>` (`value`, `error`, `updatedAt`, `stale`).
- **`AdminPoller`:** l'intervallo parte dalla fine della lettura. `setInterval` durante una lettura vale dal turno dopo.
- **`AdminApi`** (`lib/core/jellyfin/admin_api.dart`): `sessions`, `partyGroups`, `serverInfo`, `isServerUp`, `restart`. Le letture passano `quietStatuses: restartGatewayStatuses` (`{502, 503, 504}`, in `jellyfin_http.dart`).
- **`admin_models.dart`** ha le letture private `_ticksPerMicrosecond`, `_string`, `_int`, `_date`, `_ticks`, `_map`, `_strings`, `_list` e la pubblica `isEmptyJellyfinId`. `_list` usa `?parse(json)` (elementi null-aware).
- **Componenti:**
  - `admin_widgets.dart`: `AdminSectionTitle(title:)`, `AdminEmptyText(text:)`, `AdminUserLine(name:, detail:)`, `AdminStaleNote(updatedAt:)`;
  - `admin_time.dart`: `adminTimeLabel(at, now, l)`, `adminClockLabel(at, l)`;
  - `admin_navigation.dart`: `AdminTab { sessions }`, `AdminTab.parse`, `adminTabLabel`, `openAdmin(context, tab:)`;
  - `admin_screen.dart`: un ciclo su `AdminTab.values` e uno `switch (tab)`;
  - `sessions_tab.dart`: lo schema delle schede, cioè `ConsumerStatefulWidget` con `SmoothScrollController`, `LoadingView`/`ErrorView` senza dati, `ListView` con padding `EdgeInsets.fromLTRB(32, 0, 32, 40)`.
- **Test** (`test/support/admin_fakes.dart`): `FakeAdminApi` (campi `…Value`/`…Error`, `calls`, `count(call)`), `FakeAdminForeground`, `testAdmin`, `testServerInfo`, `adminTestOverrides(api, {session, foreground})`.
- **Funzioni del plugin:** `socialAvailabilityProvider` (`lib/features/social/social_providers.dart`) dà `SocialFeatures` con `inbox`. Nei test: `FakeSocialAvailability(const SocialFeatures(inbox: true))` (`test/support/social_fakes.dart`).
- **Altro:**
  - `openItemById(context, itemId)` è in `lib/app/navigation.dart`;
  - `describeError(l, error)` è in `lib/app/error_text.dart`;
  - `showWfDialog` è in `lib/ui/wf_dialog.dart`;
  - `WfButton.secondary` è in `lib/ui/wf_buttons.dart`;
  - un `FilledButton` dentro una `Row` vuole `minimumSize: const Size(0, 44)`, perché il tema lo fa largo all'infinito;
  - `JellyfinHttp.delete(path, {query, quietStatuses})`, `asJsonMap`, `parseJson`.
- **Versione:** `pubspec.yaml` ha `version: 0.9.0`, senza numero di build. La release precedente è il commit `chore: release 0.9.0`.

**Server** (Jellyfin 10.11.9, 2026-10-06)
- **`/Library/VirtualFolders`:** quattro librerie, tutte con `RefreshStatus` "Idle" e `RefreshProgress` null:
  - Movies, `movies`;
  - Collezioni2, `boxsets`;
  - Anime, senza `CollectionType`;
  - Shows, `tvshows`.
- **`/ScheduledTasks?isHidden=false`:**
  - 40 attività, ordinate per nome. Le categorie sono in italiano per quelle di Jellyfin ("Libreria", "Manutenzione", "Applicazione") e come le scrive il plugin per le altre ("Maintenance", "Intro Skipper", "Trakt"…);
  - `State` vale "Idle", "Running" o "Cancelling";
  - `LastExecutionResult` ha `StartTimeUtc`, `EndTimeUtc`, `Status` ("Completed", "Cancelled"…), `ErrorMessage` e `Key`;
  - "Scansione della libreria" ha `Key` "RefreshLibrary".
- **`/System/ActivityLog/Entries`:**
  - risponde `{Items, TotalRecordCount, StartIndex}`, con 12.134 voci;
  - le voci di sistema hanno `UserId` di soli zeri; `ShortOverview` contiene l'IP ("Indirizzo IP: …");
  - `Severity` vale "Information" o "Error".
- **Configurazione del plugin** (`/Plugins/882eb47e-668a-4935-ba55-c2858eb4ed90/Configuration`): le chiavi sono `NotifyNewTitles`, `SeerrUrl`, `SeerrApiKey`, `SeerrWebhookSecret`, in PascalCase. `NotifyNewTitles` vale `true`.
- **Plugin 1.4.0:**
  - `Requests/Test` risponde `{Ok, Version, Error}` con `Error` tra "NotConfigured", "SeerrAuth" e "SeerrUnavailable";
  - `Requests/Admin` risponde `{Configured, LastEventAt, LastEventType}`, con `LastEventType` per esempio "MEDIA_PENDING", "MEDIA_AVAILABLE" o "TEST_NOTIFICATION";
  - `Inbox/NewTitles` risponde `{Enabled, Pending}`, `Inbox/NewTitles/Send` `{Titles, Recipients}`, `Inbox/Announcements` `{Recipients}` (400 se il testo non va).

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi |
| `lib/core/jellyfin/json_fields.dart` | crea | letture JSON tolleranti in comune |
| `lib/core/jellyfin/admin_models.dart` | modifica | usa `json_fields.dart` |
| `lib/core/jellyfin/maintenance_models.dart` | crea | `LibraryFolder`, `ScheduledTask`, `TaskResult` |
| `lib/core/jellyfin/activity_models.dart` | crea | `ActivityEntry`, `ActivityPage` |
| `lib/core/jellyfin/admin_api.dart` | modifica | librerie, attività, registro |
| `lib/core/social/plugin_admin_models.dart` | crea | risposte admin del plugin |
| `lib/core/social/plugin_admin_api.dart` | crea | `PluginAdminApi` |
| `lib/features/admin/admin_providers.dart` | modifica | `pluginAdminApiProvider` |
| `lib/features/admin/admin_tab_controller.dart` | modifica | `act()` |
| `lib/features/admin/admin_time.dart` | modifica | durata e data completa |
| `lib/features/admin/admin_action_button.dart` | crea | `AdminActionButton` |
| `lib/features/admin/admin_confirm_dialog.dart` | crea | `showAdminConfirmDialog` |
| `lib/features/admin/admin_widgets.dart` | modifica | `AdminCard` |
| `lib/features/admin/maintenance_controller.dart` | crea | `MaintenanceSnapshot`, `TaskGroup`, `MaintenanceController` |
| `lib/features/admin/task_labels.dart` | crea | stato delle attività in parole |
| `lib/features/admin/maintenance_tab.dart` | crea | scheda Manutenzione |
| `lib/features/admin/activity_controller.dart` | crea | `ActivityFilter`, `ActivityState`, `ActivityController` |
| `lib/features/admin/activity_tab.dart` | crea | scheda Registro |
| `lib/features/admin/wonderflix_controllers.dart` | crea | `InboxAdminController`, `SeerrAdminController` |
| `lib/features/admin/wonderflix_labels.dart` | crea | tipi degli eventi e prova di Seerr in parole |
| `lib/features/admin/wonderflix_tab.dart` | crea | scheda WonderFlix |
| `lib/features/admin/admin_navigation.dart`, `admin_screen.dart` | modifica | quattro schede |
| `test/support/admin_json.dart`, `test/support/admin_fakes.dart` | modifica | JSON, finti, `adminTestOverrides` |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1–5):** testi, letture JSON e modelli, `AdminApi`, `PluginAdminApi`, azioni e pulsanti comuni.
- **Gruppo B (Task 6–9):** schede Manutenzione, Registro, WonderFlix, pagina con quattro schede.
- **Gruppo C (Task 10):** allineamento della spec, verifica, build.

---

## Gruppo A — dati e pezzi comuni

### Task 1: testi del piano

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan16b_test.dart`

- [ ] **Step 1: test che fallisce**

`test/app/l10n_plan16b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 16b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.adminTabMaintenance, 'Manutenzione');
    expect(it.adminTabActivity, 'Registro');
    expect(it.adminTabWonderflix, 'WonderFlix');
    expect(it.adminTaskLastRun('2 h fa'), 'Ultima: 2 h fa');
    expect(it.adminTaskCompletedIn('3 min'), 'Completata in 3 min');
    expect(it.adminDurationSeconds(45), '45 s');
    expect(it.adminDurationMinutes(3), '3 min');
    expect(it.adminDurationHours(1, 5), '1 h 5 min');
    expect(it.adminAnnouncementSent(1), 'Annuncio inviato a 1 persona');
    expect(it.adminAnnouncementSent(12), 'Annuncio inviato a 12 persone');
    expect(it.adminNewTitlesPending(1), '1 titolo in attesa del prossimo riepilogo');
    expect(it.adminNewTitlesPending(4), '4 titoli in attesa del prossimo riepilogo');
    expect(it.adminNewTitlesSentTitles(1), 'Inviato 1 titolo');
    expect(it.adminNewTitlesSentTitles(3), 'Inviati 3 titoli');
    expect(it.adminNewTitlesSentTo(1), 'a 1 persona');
    expect(it.adminNewTitlesSentTo(9), 'a 9 persone');
    expect(it.adminSeerrLastEvent('2 h fa', 'Richiesta in attesa'),
        'Ultimo evento dal webhook: 2 h fa · Richiesta in attesa');
    expect(it.adminSeerrConnected('3.4.1'), 'Collegato a Seerr 3.4.1');
    expect(en.adminTabActivity, 'Activity');
    expect(en.adminAnnouncementSent(2), 'Announcement sent to 2 people');
    expect(en.adminNewTitlesSentTitles(1), 'Sent 1 title');
    expect(en.adminNewTitlesSentTo(2), 'to 2 people');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.adminLibraries,
        l.adminScanAll,
        l.adminScan,
        l.adminTasks,
        l.adminTaskStart,
        l.adminTaskStop,
        l.adminTaskStopping,
        l.adminTaskFailed,
        l.adminTaskCancelled,
        l.adminTaskAborted,
        l.adminTaskNeverRun,
        l.adminActivityAll,
        l.adminActivityUsers,
        l.adminActivitySystem,
        l.adminActivityRefresh,
        l.adminActivityOpenItem,
        l.adminActivityEmpty,
        l.adminActivityEnd,
        l.adminAnnouncement,
        l.adminAnnouncementSend,
        l.adminAnnouncementConfirm,
        l.adminAnnouncementInvalid,
        l.adminSend,
        l.adminNewTitles,
        l.adminNewTitlesNotify,
        l.adminNewTitlesNone,
        l.adminNewTitlesOff,
        l.adminNewTitlesSendNow,
        l.adminSeerr,
        l.adminSeerrNoEvents,
        l.adminSeerrEventPending,
        l.adminSeerrEventAvailable,
        l.adminSeerrEventTest,
        l.adminSeerrTest,
        l.adminSeerrConnectedPlain,
        l.adminSeerrNotConfiguredError,
        l.adminSeerrAuthError,
        l.adminSeerrUnavailable,
        l.adminSeerrNotConfigured,
      ], everyElement(isNotEmpty));
    }
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/l10n_plan16b_test.dart`
Expected: FAIL in compilazione (`adminTabMaintenance` non esiste).

- [ ] **Step 3: aggiungi i testi**

In `l10n/app_it.arb`, prima della `}` finale, dopo l'ultima voce (aggiungile la virgola):

```json
  "adminTabMaintenance": "Manutenzione",
  "adminTabActivity": "Registro",
  "adminTabWonderflix": "WonderFlix",
  "adminLibraries": "Librerie",
  "adminScanAll": "Scansiona tutte",
  "adminScan": "Scansiona",
  "adminTasks": "Attività pianificate",
  "adminTaskStart": "Avvia",
  "adminTaskStop": "Ferma",
  "adminTaskStopping": "Arresto…",
  "adminTaskLastRun": "Ultima: {time}",
  "@adminTaskLastRun": {"placeholders": {"time": {"type": "String"}}},
  "adminTaskCompletedIn": "Completata in {duration}",
  "@adminTaskCompletedIn": {"placeholders": {"duration": {"type": "String"}}},
  "adminTaskFailed": "Non riuscita",
  "adminTaskCancelled": "Annullata",
  "adminTaskAborted": "Interrotta",
  "adminTaskNeverRun": "Mai eseguita",
  "adminDurationSeconds": "{count} s",
  "@adminDurationSeconds": {"placeholders": {"count": {"type": "int"}}},
  "adminDurationMinutes": "{count} min",
  "@adminDurationMinutes": {"placeholders": {"count": {"type": "int"}}},
  "adminDurationHours": "{hours} h {minutes} min",
  "@adminDurationHours": {"placeholders": {"hours": {"type": "int"}, "minutes": {"type": "int"}}},
  "adminActivityAll": "Tutto",
  "adminActivityUsers": "Utenti",
  "adminActivitySystem": "Sistema",
  "adminActivityRefresh": "Aggiorna",
  "adminActivityOpenItem": "Apri il titolo",
  "adminActivityEmpty": "Nessuna voce",
  "adminActivityEnd": "Non ci sono altre voci",
  "adminAnnouncement": "Annuncio",
  "adminAnnouncementSend": "Invia a tutti",
  "adminAnnouncementConfirm": "L'annuncio arriva nella cassetta di tutti gli utenti attivi.",
  "adminAnnouncementSent": "{count, plural, =1{Annuncio inviato a 1 persona} other{Annuncio inviato a {count} persone}}",
  "@adminAnnouncementSent": {"placeholders": {"count": {"type": "int"}}},
  "adminAnnouncementInvalid": "Testo non valido",
  "adminSend": "Invia",
  "adminNewTitles": "Novità",
  "adminNewTitlesNotify": "Avvisa delle novità",
  "adminNewTitlesPending": "{count, plural, =1{1 titolo in attesa del prossimo riepilogo} other{{count} titoli in attesa del prossimo riepilogo}}",
  "@adminNewTitlesPending": {"placeholders": {"count": {"type": "int"}}},
  "adminNewTitlesNone": "Nessun titolo in attesa",
  "adminNewTitlesOff": "Le novità non vengono raccolte",
  "adminNewTitlesSendNow": "Invia ora",
  "adminNewTitlesSentTitles": "{count, plural, =1{Inviato 1 titolo} other{Inviati {count} titoli}}",
  "@adminNewTitlesSentTitles": {"placeholders": {"count": {"type": "int"}}},
  "adminNewTitlesSentTo": "{count, plural, =1{a 1 persona} other{a {count} persone}}",
  "@adminNewTitlesSentTo": {"placeholders": {"count": {"type": "int"}}},
  "adminSeerr": "Seerr",
  "adminSeerrLastEvent": "Ultimo evento dal webhook: {time} · {type}",
  "@adminSeerrLastEvent": {"placeholders": {"time": {"type": "String"}, "type": {"type": "String"}}},
  "adminSeerrNoEvents": "Nessun evento ricevuto",
  "adminSeerrEventPending": "Richiesta in attesa",
  "adminSeerrEventAvailable": "Richiesta disponibile",
  "adminSeerrEventTest": "Messaggio di prova",
  "adminSeerrTest": "Prova collegamento",
  "adminSeerrConnected": "Collegato a Seerr {version}",
  "@adminSeerrConnected": {"placeholders": {"version": {"type": "String"}}},
  "adminSeerrConnectedPlain": "Collegato a Seerr",
  "adminSeerrNotConfiguredError": "Seerr non è configurato",
  "adminSeerrAuthError": "Seerr ha rifiutato la chiave",
  "adminSeerrUnavailable": "Seerr non risponde",
  "adminSeerrNotConfigured": "Non configurato: si imposta dalla pagina del plugin nella Dashboard web."
```

In `l10n/app_en.arb`, prima della `}` finale (con la virgola sull'ultima voce di prima):

```json
  "adminTabMaintenance": "Maintenance",
  "adminTabActivity": "Activity",
  "adminTabWonderflix": "WonderFlix",
  "adminLibraries": "Libraries",
  "adminScanAll": "Scan all",
  "adminScan": "Scan",
  "adminTasks": "Scheduled tasks",
  "adminTaskStart": "Start",
  "adminTaskStop": "Stop",
  "adminTaskStopping": "Stopping…",
  "adminTaskLastRun": "Last: {time}",
  "adminTaskCompletedIn": "Completed in {duration}",
  "adminTaskFailed": "Failed",
  "adminTaskCancelled": "Cancelled",
  "adminTaskAborted": "Aborted",
  "adminTaskNeverRun": "Never run",
  "adminDurationSeconds": "{count} s",
  "adminDurationMinutes": "{count} min",
  "adminDurationHours": "{hours} h {minutes} min",
  "adminActivityAll": "All",
  "adminActivityUsers": "Users",
  "adminActivitySystem": "System",
  "adminActivityRefresh": "Refresh",
  "adminActivityOpenItem": "Open the title",
  "adminActivityEmpty": "No entries",
  "adminActivityEnd": "No more entries",
  "adminAnnouncement": "Announcement",
  "adminAnnouncementSend": "Send to everyone",
  "adminAnnouncementConfirm": "The announcement goes to the inbox of every active user.",
  "adminAnnouncementSent": "{count, plural, =1{Announcement sent to 1 person} other{Announcement sent to {count} people}}",
  "adminAnnouncementInvalid": "Invalid text",
  "adminSend": "Send",
  "adminNewTitles": "New titles",
  "adminNewTitlesNotify": "Notify new titles",
  "adminNewTitlesPending": "{count, plural, =1{1 title waiting for the next summary} other{{count} titles waiting for the next summary}}",
  "adminNewTitlesNone": "No titles waiting",
  "adminNewTitlesOff": "New titles are not being collected",
  "adminNewTitlesSendNow": "Send now",
  "adminNewTitlesSentTitles": "{count, plural, =1{Sent 1 title} other{Sent {count} titles}}",
  "adminNewTitlesSentTo": "{count, plural, =1{to 1 person} other{to {count} people}}",
  "adminSeerr": "Seerr",
  "adminSeerrLastEvent": "Last webhook event: {time} · {type}",
  "adminSeerrNoEvents": "No events received",
  "adminSeerrEventPending": "Request pending",
  "adminSeerrEventAvailable": "Request available",
  "adminSeerrEventTest": "Test message",
  "adminSeerrTest": "Test connection",
  "adminSeerrConnected": "Connected to Seerr {version}",
  "adminSeerrConnectedPlain": "Connected to Seerr",
  "adminSeerrNotConfiguredError": "Seerr is not configured",
  "adminSeerrAuthError": "Seerr rejected the key",
  "adminSeerrUnavailable": "Seerr is not responding",
  "adminSeerrNotConfigured": "Not configured: set it up from the plugin page in the web Dashboard."
```

Run: `flutter gen-l10n`

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/app/l10n_plan16b_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add l10n/app_it.arb l10n/app_en.arb test/app/l10n_plan16b_test.dart
git commit -m "feat(app): add plan 16b strings"
```

### Task 2: letture JSON in comune, modelli di manutenzione e registro

**Files:**
- Create: `lib/core/jellyfin/json_fields.dart`, `lib/core/jellyfin/maintenance_models.dart`, `lib/core/jellyfin/activity_models.dart`
- Modify: `lib/core/jellyfin/admin_models.dart`, `test/support/admin_json.dart`
- Test: `test/core/jellyfin/json_fields_test.dart`, `test/core/jellyfin/maintenance_models_test.dart`, `test/core/jellyfin/activity_models_test.dart`

- [ ] **Step 1: i JSON dei test**

In fondo a `test/support/admin_json.dart`:

```dart
/// Le librerie vere del server (2026-10-06, senza i percorsi), con Movies in
/// scansione.
final librariesJson = <Map<String, dynamic>>[
  {
    'Name': 'Movies',
    'Locations': ['/media/movies'],
    'CollectionType': 'movies',
    'ItemId': 'f137a2dd21bbc1b99aa5c0f6bf02a805',
    'PrimaryImageItemId': 'f137a2dd21bbc1b99aa5c0f6bf02a805',
    'RefreshProgress': 42.5,
    'RefreshStatus': 'Active',
  },
  {
    'Name': 'Collezioni2',
    'CollectionType': 'boxsets',
    'ItemId': '14c252b1242828441caab72deed35f64',
    'RefreshStatus': 'Idle',
  },
  {
    'Name': 'Anime',
    'ItemId': '0c41907140d802bb58430fed7e2cd79e',
    'RefreshStatus': 'Idle',
  },
  {
    'Name': 'Shows',
    'CollectionType': 'tvshows',
    'ItemId': 'a656b907eb3a73532e40e44b968d0225',
    'RefreshStatus': 'Idle',
  },
];

/// Attività vere del server (nomi, chiavi e categorie del 2026-10-06), in
/// ordine di nome come le dà Jellyfin. Gli stati sono vari per i test: Auto
/// Collections in corso, il webhook in arresto, Trakt non riuscita, il
/// Keyframe annullato, SkipMe mai eseguita.
final tasksJson = <Map<String, dynamic>>[
  {
    'Name': 'Aggiorna i plugin',
    'State': 'Idle',
    'Id': 't-plugins',
    'Key': 'PluginUpdates',
    'Category': 'Applicazione',
    'Description': 'Scarica e installa gli aggiornamenti dei plugin.',
    'IsHidden': false,
    'Triggers': <Object>[],
    'LastExecutionResult': {
      'StartTimeUtc': '2026-10-05T22:23:40.0000000Z',
      'EndTimeUtc': '2026-10-05T22:23:46.5083784Z',
      'Status': 'Completed',
      'Name': 'Aggiorna i plugin',
      'Key': 'PluginUpdates',
      'Id': 't-plugins',
    },
  },
  {
    'Name': 'Auto Collections',
    'State': 'Running',
    'CurrentProgressPercentage': 37.5,
    'Id': 't-autocol',
    'Key': 'AutoCollections',
    'Category': 'Auto Collections',
    'Description': 'Aggiorna le collezioni automatiche.',
  },
  {
    'Name': 'Estrattore di Keyframe',
    'State': 'Idle',
    'Id': 't-keyframe',
    'Key': 'KeyframeExtraction',
    'Category': 'Libreria',
    'LastExecutionResult': {
      'StartTimeUtc': '2026-09-13T12:10:00.0000000Z',
      'EndTimeUtc': '2026-09-13T12:18:18.6587334Z',
      'Status': 'Cancelled',
    },
  },
  {
    'Name': 'Export library to trakt.tv',
    'State': 'Idle',
    'Id': 't-trakt',
    'Key': 'TraktSyncLibraryTask',
    'Category': 'Trakt',
    'LastExecutionResult': {
      'StartTimeUtc': '2026-05-28T15:40:00.0000000Z',
      'EndTimeUtc': '2026-05-28T15:49:54.8292125Z',
      'Status': 'Failed',
      'ErrorMessage':
          'Response status code does not indicate success: 401 (Unauthorized).',
    },
  },
  {
    'Name': 'Ottimizza database',
    'State': 'Idle',
    'Id': 't-optimize',
    'Key': 'OptimizeDatabaseTask',
    'Category': 'Manutenzione',
    'LastExecutionResult': {
      'StartTimeUtc': '2026-10-06T04:21:48.0000000Z',
      'EndTimeUtc': '2026-10-06T04:24:48.5097924Z',
      'Status': 'Completed',
    },
  },
  {
    'Name': 'Scansione della libreria',
    'State': 'Idle',
    'Id': 't-scan',
    'Key': 'RefreshLibrary',
    'Category': 'Libreria',
    'Description': 'Analizza la cartella dei media per trovare file nuovi.',
    'LastExecutionResult': {
      'StartTimeUtc': '2026-10-05T03:40:00.0000000Z',
      'EndTimeUtc': '2026-10-05T03:47:36.9500309Z',
      'Status': 'Completed',
    },
  },
  {
    'Name': 'Sync SkipMe.db Segment Database',
    'State': 'Idle',
    'Id': 't-skipme',
    'Key': 'SkipMeDbSync',
    'Category': 'Intro Skipper',
  },
  {
    'Name': 'Webhook Item Added Notifier',
    'State': 'Cancelling',
    'CurrentProgressPercentage': 90.0,
    'Id': 't-webhook',
    'Key': 'WebhookItemAdded',
    'Category': 'Libreria',
  },
];

/// Una pagina del registro, con voci come quelle vere (2026-10-06): IP di
/// documentazione, nomi di prova.
final activityJson = <String, dynamic>{
  'Items': [
    {
      'Id': 12134,
      'Name': 'anna si è disconnesso da FireTV Soggiorno',
      'ShortOverview': 'Indirizzo IP: 203.0.113.7',
      'Type': 'SessionEnded',
      'Date': '2026-10-06T03:39:07.1141718Z',
      'UserId': '6a48860fd4d94124b1890173d68c9de3',
      'Severity': 'Information',
    },
    {
      'Id': 12130,
      'Name': 'anna ha riprodotto Lost - Pilota su FireTV Soggiorno',
      'Type': 'VideoPlayback',
      'ItemId': 'e1',
      'Date': '2026-10-06T03:10:00.0000000Z',
      'UserId': '6a48860fd4d94124b1890173d68c9de3',
      'Severity': 'Information',
    },
    {
      'Id': 12125,
      'Name': 'WonderFlix Watch Party è stato Installato',
      'ShortOverview': 'Versione 1.4.0.0',
      'Type': 'PluginInstalled',
      'Date': '2026-10-05T22:21:46.9886084Z',
      'UserId': '00000000000000000000000000000000',
      'Severity': 'Information',
    },
    {
      'Id': 11950,
      'Name': 'Attività Esporta su trakt.tv non riuscita',
      'Type': 'ScheduledTaskFailed',
      'Date': '2026-10-04T18:00:00.0000000Z',
      'UserId': '00000000000000000000000000000000',
      'Severity': 'Warning',
    },
    {
      'Id': 11904,
      'Name': 'Tentativo di accesso fallito da marco',
      'ShortOverview': 'Indirizzo IP: 203.0.113.9',
      'Overview': 'Nome utente o password non validi.',
      'Type': 'AuthenticationFailed',
      'Date': '2026-10-04T14:06:19.8344887Z',
      'UserId': '00000000000000000000000000000000',
      'Severity': 'Error',
    },
  ],
  'TotalRecordCount': 12134,
  'StartIndex': 0,
};
```

- [ ] **Step 2: test che falliscono**

`test/core/jellyfin/json_fields_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/json_fields.dart';

void main() {
  final json = <String, dynamic>{
    'text': 'ciao',
    'empty': '',
    'int': 3,
    'double': 2.6,
    'date': '2026-10-06T03:39:07.1141718Z',
    'ticks': 7540000000,
    'map': {'a': 1},
    'list': ['x', '', 4, 'y'],
    'csv': 'a, b,,c',
  };

  test('campi semplici: tipo sbagliato o mancante → null', () {
    expect(jsonString(json, 'text'), 'ciao');
    expect(jsonString(json, 'empty'), isNull);
    expect(jsonString(json, 'int'), isNull);
    expect(jsonInt(json, 'int'), 3);
    expect(jsonInt(json, 'double'), 3);
    expect(jsonInt(json, 'text'), isNull);
    expect(jsonDouble(json, 'int'), 3.0);
    expect(jsonDouble(json, 'double'), 2.6);
    expect(jsonDouble(json, 'missing'), isNull);
    expect(jsonDate(json, 'date'), DateTime.parse('2026-10-06T03:39:07.114171Z'));
    expect(jsonDate(json, 'text'), isNull);
    expect(jsonTicks(json, 'ticks'), const Duration(minutes: 12, seconds: 34));
    expect(jsonMap(json['map']), {'a': 1});
    expect(jsonMap(json['list']), isNull);
    expect(jsonStrings(json['list']), ['x', 'y']);
    expect(jsonStrings(json['csv']), ['a', 'b', 'c']);
    expect(jsonStrings(json['int']), isEmpty);
  });

  test('elenchi: voci scartate saltate, corpo sbagliato → errore', () {
    String? name(Map<String, dynamic> item) => jsonString(item, 'Name');
    expect(
        jsonList([
          {'Name': 'a'},
          {'Altro': 1},
          'no',
          {'Name': 'b'},
        ], name),
        ['a', 'b']);
    expect(() => jsonList({'Items': <Object>[]}, name),
        throwsA(isA<ServerErrorException>()));
  });

  test('id vuoti di Jellyfin', () {
    expect(isEmptyJellyfinId('00000000000000000000000000000000'), isTrue);
    expect(isEmptyJellyfinId('00000000-0000-0000-0000-000000000000'), isTrue);
    expect(isEmptyJellyfinId('ab8240c5fc1649e186f662fa00ca0fb0'), isFalse);
  });
}
```

`test/core/jellyfin/maintenance_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/maintenance_models.dart';

import '../../support/admin_json.dart';

void main() {
  test('librerie: genere, scansione in corso, voci senza id saltate', () {
    final libraries = parseLibraries([
      ...librariesJson,
      {'Name': 'senza id'},
    ]);

    expect(libraries.map((l) => l.name),
        ['Movies', 'Collezioni2', 'Anime', 'Shows']);
    expect(libraries.map((l) => l.kind), [
      LibraryKind.movies,
      LibraryKind.other,
      LibraryKind.other,
      LibraryKind.shows,
    ]);
    expect(libraries[0].itemId, 'f137a2dd21bbc1b99aa5c0f6bf02a805');
    expect(libraries[0].refreshing, isTrue);
    expect(libraries[0].refreshProgress, 42.5);
    expect(libraries[1].refreshing, isFalse);
    expect(libraries[1].refreshProgress, isNull);
    expect(() => parseLibraries({'x': 1}), throwsA(isA<ServerErrorException>()));
  });

  test('attività: stato, avanzamento, ultimo risultato', () {
    final tasks = {for (final task in parseTasks(tasksJson)) task.id: task};

    expect(tasks, hasLength(8));
    final plugins = tasks['t-plugins']!;
    expect(plugins.name, 'Aggiorna i plugin');
    expect(plugins.key, 'PluginUpdates');
    expect(plugins.category, 'Applicazione');
    expect(plugins.description, 'Scarica e installa gli aggiornamenti dei plugin.');
    expect(plugins.state, TaskState.idle);
    expect(plugins.lastResult!.status, TaskStatus.completed);
    expect(plugins.lastResult!.end,
        DateTime.parse('2026-10-05T22:23:46.508378Z'));

    expect(tasks['t-autocol']!.state, TaskState.running);
    expect(tasks['t-autocol']!.progress, 37.5);
    expect(tasks['t-autocol']!.lastResult, isNull);
    expect(tasks['t-webhook']!.state, TaskState.cancelling);
    expect(tasks['t-keyframe']!.lastResult!.status, TaskStatus.cancelled);
    expect(tasks['t-trakt']!.lastResult!.status, TaskStatus.failed);
    expect(tasks['t-trakt']!.lastResult!.errorMessage, contains('401'));
    expect(tasks['t-optimize']!.lastResult!.duration!.inMinutes, 3);
    expect(tasks['t-skipme']!.lastResult, isNull);
    expect(tasks['t-scan']!.key, ScheduledTask.refreshLibraryKey);
  });

  test('attività strane: senza id saltate, valori sconosciuti', () {
    final tasks = parseTasks([
      {'Name': 'senza id'},
      {
        'Id': 'x',
        'State': 'Boh',
        'LastExecutionResult': {'Status': 'Boh'},
      },
    ]);

    final task = tasks.single;
    expect(task.name, '');
    expect(task.state, TaskState.idle);
    expect(task.lastResult!.status, TaskStatus.unknown);
    expect(task.lastResult!.duration, isNull);
  });
}
```

`test/core/jellyfin/activity_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/activity_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';

import '../../support/admin_json.dart';

void main() {
  test('una pagina del registro', () {
    final page = parseActivityPage(activityJson);

    expect(page.total, 12134);
    expect(page.items.map((e) => e.id), [12134, 12130, 12125, 11950, 11904]);

    final session = page.items[0];
    expect(session.name, 'anna si è disconnesso da FireTV Soggiorno');
    expect(session.shortOverview, 'Indirizzo IP: 203.0.113.7');
    expect(session.type, 'SessionEnded');
    expect(session.userId, '6a48860fd4d94124b1890173d68c9de3');
    expect(session.itemId, isNull);
    expect(session.date, DateTime.parse('2026-10-06T03:39:07.114171Z'));
    expect(session.severity, ActivitySeverity.info);

    expect(page.items[1].itemId, 'e1');
    expect(page.items[2].userId, isNull, reason: 'id di soli zeri');
    expect(page.items[3].severity, ActivitySeverity.warning);
    expect(page.items[4].severity, ActivitySeverity.error);
    expect(page.items[4].overview, 'Nome utente o password non validi.');
  });

  test('voci strane e corpi sbagliati', () {
    final page = parseActivityPage({
      'Items': [
        {'Name': 'senza id'},
        {'Id': 7, 'Severity': 'Critical', 'ItemId': '00000000000000000000000000000000'},
      ],
    });

    expect(page.items.single.id, 7);
    expect(page.items.single.name, '');
    expect(page.items.single.severity, ActivitySeverity.error);
    expect(page.items.single.itemId, isNull);
    expect(page.total, 1, reason: 'senza TotalRecordCount, le voci lette');
    expect(() => parseActivityPage(<Object>[]),
        throwsA(isA<ServerErrorException>()));
    expect(() => parseActivityPage({'TotalRecordCount': 3}),
        throwsA(isA<ServerErrorException>()));
  });
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/core/jellyfin/json_fields_test.dart test/core/jellyfin/maintenance_models_test.dart test/core/jellyfin/activity_models_test.dart`
Expected: FAIL in compilazione (i file non esistono).

- [ ] **Step 4: le letture in comune**

`lib/core/jellyfin/json_fields.dart`:

```dart
import 'api_exception.dart';

// Letture tolleranti dei JSON di Jellyfin e del plugin (spec J §8.2): un
// campo mancante o di tipo sbagliato vale `null` (o vuoto) e non fa fallire
// la lettura dell'elenco.

/// Tick di Jellyfin in un microsecondo (10 milioni al secondo).
const _ticksPerMicrosecond = 10;

/// Una stringa non vuota.
String? jsonString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? jsonInt(Map<String, dynamic> json, String key) => switch (json[key]) {
      final int value => value,
      final double value => value.round(),
      _ => null,
    };

double? jsonDouble(Map<String, dynamic> json, String key) =>
    switch (json[key]) {
      final num value => value.toDouble(),
      _ => null,
    };

DateTime? jsonDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? DateTime.tryParse(value) : null;
}

/// Una durata in tick di Jellyfin.
Duration? jsonTicks(Map<String, dynamic> json, String key) {
  final ticks = jsonInt(json, key);
  return ticks == null
      ? null
      : Duration(microseconds: ticks ~/ _ticksPerMicrosecond);
}

Map<String, dynamic>? jsonMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// Stringhe di un elenco JSON; una stringa sola con le virgole (forma di
/// alcune versioni di Jellyfin) vale come elenco.
List<String> jsonStrings(Object? value) => switch (value) {
      final List<dynamic> list => [
          for (final item in list)
            if (item is String && item.isNotEmpty) item,
        ],
      final String text => [
          for (final item in text.split(','))
            if (item.trim().isNotEmpty) item.trim(),
        ],
      _ => const [],
    };

/// Un id di Jellyfin di soli zeri, con o senza trattini: nessuno (per
/// esempio l'utente delle voci di sistema o delle chiavi API).
bool isEmptyJellyfinId(String id) => id.replaceAll(RegExp('[-0]'), '').isEmpty;

/// Un elenco JSON di oggetti. Le voci che [parse] scarta (`null`) e quelle
/// che non sono oggetti si saltano; un corpo che non è un elenco è una
/// risposta inattesa.
List<T> jsonList<T>(
    Object? data, T? Function(Map<String, dynamic> json) parse) {
  if (data is! List) throw const ServerErrorException(null);
  return [
    for (final raw in data)
      if (jsonMap(raw) case final json?) ?parse(json),
  ];
}
```

In `lib/core/jellyfin/admin_models.dart`:
- togli le definizioni di `_ticksPerMicrosecond`, `_string`, `_int`, `_date`, `_ticks`, `_map`, `_strings`, `isEmptyJellyfinId` e `_list`, con i loro commenti;
- al posto di `import 'api_exception.dart';` metti:

```dart
import 'api_exception.dart';
import 'json_fields.dart';

export 'json_fields.dart' show isEmptyJellyfinId;
```

- sostituisci le chiamate: `_string(` → `jsonString(`, `_int(` → `jsonInt(`, `_date(` → `jsonDate(`, `_ticks(` → `jsonTicks(`, `_map(` → `jsonMap(`, `_strings(` → `jsonStrings(`, `_list(` → `jsonList(`. Non cambia altro (`_playMethod` resta).

Run: `flutter test test/core/jellyfin/admin_models_test.dart test/core/jellyfin/admin_api_test.dart`
Expected: PASS (nessun cambio di comportamento).

- [ ] **Step 5: i modelli nuovi**

`lib/core/jellyfin/maintenance_models.dart`:

```dart
import 'json_fields.dart';

/// Il genere di una libreria, per l'icona (`CollectionType`).
enum LibraryKind { movies, shows, other }

/// Una libreria del server (`VirtualFolderInfo`, spec J §8.2).
class LibraryFolder {
  const LibraryFolder({
    required this.itemId,
    required this.name,
    this.kind = LibraryKind.other,
    this.refreshing = false,
    this.refreshProgress,
  });

  /// `null` senza `ItemId`: non si potrebbe scansionare.
  static LibraryFolder? fromJson(Map<String, dynamic> json) {
    final itemId = jsonString(json, 'ItemId');
    if (itemId == null) return null;
    return LibraryFolder(
      itemId: itemId,
      name: jsonString(json, 'Name') ?? '',
      kind: switch (json['CollectionType']) {
        'movies' => LibraryKind.movies,
        'tvshows' => LibraryKind.shows,
        _ => LibraryKind.other,
      },
      refreshing: json['RefreshStatus'] == 'Active',
      refreshProgress: jsonDouble(json, 'RefreshProgress'),
    );
  }

  final String itemId;
  final String name;
  final LibraryKind kind;

  /// Una scansione è in corso (`RefreshStatus` "Active").
  final bool refreshing;

  /// Da 0 a 100, se Jellyfin lo dice.
  final double? refreshProgress;
}

List<LibraryFolder> parseLibraries(Object? data) =>
    jsonList(data, LibraryFolder.fromJson);

/// Stato di un'attività pianificata; uno sconosciuto vale come ferma.
enum TaskState { idle, running, cancelling }

/// Com'è finita l'ultima esecuzione (`TaskCompletionStatus`).
enum TaskStatus { completed, failed, cancelled, aborted, unknown }

/// L'ultima esecuzione di un'attività (`LastExecutionResult`).
class TaskResult {
  const TaskResult({
    this.start,
    this.end,
    this.status = TaskStatus.unknown,
    this.errorMessage,
  });

  factory TaskResult.fromJson(Map<String, dynamic> json) => TaskResult(
        start: jsonDate(json, 'StartTimeUtc'),
        end: jsonDate(json, 'EndTimeUtc'),
        status: switch (json['Status']) {
          'Completed' => TaskStatus.completed,
          'Failed' => TaskStatus.failed,
          'Cancelled' => TaskStatus.cancelled,
          'Aborted' => TaskStatus.aborted,
          _ => TaskStatus.unknown,
        },
        errorMessage: jsonString(json, 'ErrorMessage'),
      );

  final DateTime? start;
  final DateTime? end;
  final TaskStatus status;
  final String? errorMessage;

  /// Quanto è durata, se si sanno inizio e fine.
  Duration? get duration {
    final start = this.start;
    final end = this.end;
    return start == null || end == null ? null : end.difference(start);
  }
}

/// Un'attività pianificata (`TaskInfo`, spec J §8.2).
class ScheduledTask {
  const ScheduledTask({
    required this.id,
    required this.name,
    this.key,
    this.description,
    this.category,
    this.state = TaskState.idle,
    this.progress,
    this.lastResult,
  });

  /// La "Scansione della libreria" di Jellyfin: il suo stato sta accanto a
  /// "Scansiona tutte" (spec J §9.4).
  static const refreshLibraryKey = 'RefreshLibrary';

  /// `null` senza `Id`: non si potrebbe avviare.
  static ScheduledTask? fromJson(Map<String, dynamic> json) {
    final id = jsonString(json, 'Id');
    if (id == null) return null;
    final last = jsonMap(json['LastExecutionResult']);
    return ScheduledTask(
      id: id,
      name: jsonString(json, 'Name') ?? '',
      key: jsonString(json, 'Key'),
      description: jsonString(json, 'Description'),
      category: jsonString(json, 'Category'),
      state: switch (json['State']) {
        'Running' => TaskState.running,
        'Cancelling' => TaskState.cancelling,
        _ => TaskState.idle,
      },
      progress: jsonDouble(json, 'CurrentProgressPercentage'),
      lastResult: last == null ? null : TaskResult.fromJson(last),
    );
  }

  final String id;
  final String name;
  final String? key;
  final String? description;
  final String? category;
  final TaskState state;

  /// Da 0 a 100, mentre è in corso.
  final double? progress;
  final TaskResult? lastResult;
}

List<ScheduledTask> parseTasks(Object? data) =>
    jsonList(data, ScheduledTask.fromJson);
```

`lib/core/jellyfin/activity_models.dart`:

```dart
import 'api_exception.dart';
import 'json_fields.dart';

/// Gravità di una voce del registro (`LogLevel`): Trace, Debug e
/// Information sono informazioni, Critical è un errore.
enum ActivitySeverity { info, warning, error }

/// Una voce del registro attività (`ActivityLogEntry`, spec J §8.2).
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.name,
    this.shortOverview,
    this.overview,
    this.type,
    this.itemId,
    this.date,
    this.userId,
    this.severity = ActivitySeverity.info,
  });

  /// `null` senza `Id`.
  static ActivityEntry? fromJson(Map<String, dynamic> json) {
    final id = jsonInt(json, 'Id');
    if (id == null) return null;
    // Le voci di sistema hanno un utente (e a volte un elemento) di soli zeri.
    String? realId(String key) {
      final value = jsonString(json, key);
      return value == null || isEmptyJellyfinId(value) ? null : value;
    }

    return ActivityEntry(
      id: id,
      name: jsonString(json, 'Name') ?? '',
      shortOverview: jsonString(json, 'ShortOverview'),
      overview: jsonString(json, 'Overview'),
      type: jsonString(json, 'Type'),
      itemId: realId('ItemId'),
      date: jsonDate(json, 'Date'),
      userId: realId('UserId'),
      severity: switch (json['Severity']) {
        'Warning' => ActivitySeverity.warning,
        'Error' || 'Critical' => ActivitySeverity.error,
        _ => ActivitySeverity.info,
      },
    );
  }

  final int id;
  final String name;
  final String? shortOverview;
  final String? overview;
  final String? type;

  /// Il titolo della voce (una riproduzione), se c'è.
  final String? itemId;
  final DateTime? date;

  /// `null` per le voci di sistema.
  final String? userId;
  final ActivitySeverity severity;
}

/// Una pagina del registro: le voci e quante sono in tutto con quel filtro.
class ActivityPage {
  const ActivityPage({required this.items, required this.total});

  final List<ActivityEntry> items;
  final int total;
}

/// `{Items, TotalRecordCount, StartIndex}`; senza `TotalRecordCount` il
/// totale è il numero delle voci lette.
ActivityPage parseActivityPage(Object? data) {
  if (data is! Map<String, dynamic>) throw const ServerErrorException(null);
  final items = jsonList(data['Items'], ActivityEntry.fromJson);
  return ActivityPage(
      items: items, total: jsonInt(data, 'TotalRecordCount') ?? items.length);
}
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/core/jellyfin`
Expected: PASS.

- [ ] **Step 7: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/core/jellyfin/json_fields.dart lib/core/jellyfin/admin_models.dart lib/core/jellyfin/maintenance_models.dart lib/core/jellyfin/activity_models.dart test/support/admin_json.dart test/core/jellyfin/json_fields_test.dart test/core/jellyfin/maintenance_models_test.dart test/core/jellyfin/activity_models_test.dart
git commit -m "feat(app): read libraries, scheduled tasks and the activity log"
```

### Task 3: `AdminApi` per librerie, attività e registro

**Files:**
- Modify: `lib/core/jellyfin/admin_api.dart`, `test/support/admin_fakes.dart`
- Test: `test/core/jellyfin/admin_api_test.dart`

- [ ] **Step 1: test che falliscono**

In `test/core/jellyfin/admin_api_test.dart`:
- nell'handler del `setUp` aggiungi le risposte:

```dart
          '/Library/VirtualFolders' => FakeResponse(200, librariesJson),
          '/ScheduledTasks' => FakeResponse(200, tasksJson),
          '/System/ActivityLog/Entries' => FakeResponse(200, activityJson),
          '/Library/Refresh' => const FakeResponse(204),
```

  e, prima del caso `_`, le azioni che rispondono 204:

```dart
          final path when path.startsWith('/Items/') ||
              path.startsWith('/ScheduledTasks/Running/') =>
            const FakeResponse(204),
```

- in fondo a `main()`:

```dart
  group('manutenzione', () {
    test('librerie', () async {
      final libraries = await api.libraries();
      expect(libraries, hasLength(4));
      expect(adapter.requests.single.path, '/Library/VirtualFolders');
    });

    test('scansiona tutte', () async {
      await api.scanAll();
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/Library/Refresh');
    });

    test('scansiona una libreria come la Dashboard web', () async {
      await api.scanLibrary('a656b907eb3a73532e40e44b968d0225');
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/Items/a656b907eb3a73532e40e44b968d0225/Refresh');
      expect(request.queryParameters, {
        'Recursive': true,
        'ImageRefreshMode': 'Default',
        'MetadataRefreshMode': 'Default',
        'ReplaceAllImages': false,
        'RegenerateTrickplay': false,
        'ReplaceAllMetadata': false,
      });
    });

    test('attività visibili', () async {
      final tasks = await api.tasks();
      expect(tasks, hasLength(8));
      expect(adapter.requests.single.path, '/ScheduledTasks');
      expect(adapter.requests.single.queryParameters, {'isHidden': false});
    });

    test('avvia e ferma', () async {
      await api.startTask('t-scan');
      await api.stopTask('t-scan');
      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
        'POST /ScheduledTasks/Running/t-scan',
        'DELETE /ScheduledTasks/Running/t-scan',
      ]);
    });
  });

  group('registro', () {
    test('pagina da 50, tutto', () async {
      final page = await api.activity(startIndex: 0);
      expect(page.items, hasLength(5));
      expect(page.total, 12134);
      final request = adapter.requests.single;
      expect(request.path, '/System/ActivityLog/Entries');
      expect(request.queryParameters, {'startIndex': 0, 'limit': 50});
    });

    test('filtro utenti o sistema', () async {
      await api.activity(startIndex: 50, hasUserId: true);
      await api.activity(startIndex: 0, hasUserId: false);
      expect(adapter.requests[0].queryParameters,
          {'startIndex': 50, 'limit': 50, 'hasUserId': true});
      expect(adapter.requests[1].queryParameters,
          {'startIndex': 0, 'limit': 50, 'hasUserId': false});
    });
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/jellyfin/admin_api_test.dart`
Expected: FAIL in compilazione (`libraries` non esiste).

- [ ] **Step 3: implementa**

In `lib/core/jellyfin/admin_api.dart` aggiungi gli import `'activity_models.dart'` e `'maintenance_models.dart'`, e in `AdminApi`, dopo `restart()`:

```dart
  /// Voci del registro per pagina (spec J §9.5).
  static const activityPageSize = 50;

  /// "Scansiona libreria" della Dashboard web 10.11.9 (`refreshdialog.js`,
  /// modo "scan"): metadati e immagini solo dove mancano, sotto-cartelle
  /// comprese.
  static const _scanLibraryQuery = <String, Object>{
    'Recursive': true,
    'ImageRefreshMode': 'Default',
    'MetadataRefreshMode': 'Default',
    'ReplaceAllImages': false,
    'RegenerateTrickplay': false,
    'ReplaceAllMetadata': false,
  };

  Future<List<LibraryFolder>> libraries() async => parseLibraries(await _http
      .get('/Library/VirtualFolders', quietStatuses: restartGatewayStatuses));

  /// Scansiona tutte le librerie (l'attività "Scansione della libreria").
  Future<void> scanAll() async {
    await _http.post('/Library/Refresh');
  }

  Future<void> scanLibrary(String itemId) async {
    await _http.post('/Items/$itemId/Refresh', query: _scanLibraryQuery);
  }

  /// Le attività pianificate visibili nella Dashboard.
  Future<List<ScheduledTask>> tasks() async => parseTasks(await _http.get(
      '/ScheduledTasks',
      query: {'isHidden': false},
      quietStatuses: restartGatewayStatuses));

  Future<void> startTask(String id) async {
    await _http.post('/ScheduledTasks/Running/$id');
  }

  Future<void> stopTask(String id) async {
    await _http.delete('/ScheduledTasks/Running/$id');
  }

  /// Una pagina del registro dalla voce [startIndex], dalla più recente.
  /// [hasUserId]: `true` solo le voci degli utenti, `false` solo quelle di
  /// sistema, `null` tutte.
  Future<ActivityPage> activity({required int startIndex, bool? hasUserId}) async =>
      parseActivityPage(await _http.get('/System/ActivityLog/Entries',
          query: {
            'startIndex': startIndex,
            'limit': activityPageSize,
            'hasUserId': ?hasUserId,
          },
          quietStatuses: restartGatewayStatuses));
```

In `test/support/admin_fakes.dart`:
- aggiungi gli import `package:wonderflix/core/jellyfin/activity_models.dart` e `package:wonderflix/core/jellyfin/maintenance_models.dart`;
- dopo `testParties()`:

```dart
/// Le librerie di [librariesJson] (Movies in scansione).
List<LibraryFolder> testLibraries() => parseLibraries(librariesJson);

/// Le attività di [tasksJson].
List<ScheduledTask> testTasks() => parseTasks(tasksJson);

/// Le voci di [activityJson], dalla più recente.
List<ActivityEntry> testActivity() => parseActivityPage(activityJson).items;

/// [count] voci del registro, dalla più recente (id da [count] a 1); quelle
/// pari hanno un utente.
List<ActivityEntry> testActivityEntries(int count) => [
      for (var id = count; id >= 1; id--)
        ActivityEntry(
          id: id,
          name: 'Voce $id',
          date: DateTime.utc(2026, 10, 6, 8).subtract(Duration(minutes: count - id)),
          userId: id.isEven ? 'u$id' : null,
        ),
    ];
```

- in `FakeAdminApi`, dopo `final upAnswers = <bool>[];` aggiungi i campi e, dopo `restart()`, i metodi:

```dart
  List<LibraryFolder> librariesValue = const [];
  List<ScheduledTask> tasksValue = const [];

  /// Le voci del registro, dalla più recente: [activity] le filtra e le
  /// divide in pagine come Jellyfin.
  List<ActivityEntry> activityValue = const [];

  Object? librariesError;
  Object? tasksError;
  Object? activityError;

  /// Errore delle azioni: scansioni, Avvia, Ferma.
  Object? actionError;
```

```dart
  @override
  Future<List<LibraryFolder>> libraries() async {
    calls.add('libraries');
    final error = librariesError;
    if (error != null) throw error;
    return librariesValue;
  }

  @override
  Future<void> scanAll() async {
    calls.add('scanAll');
    final error = actionError;
    if (error != null) throw error;
  }

  @override
  Future<void> scanLibrary(String itemId) async {
    calls.add('scan:$itemId');
    final error = actionError;
    if (error != null) throw error;
  }

  @override
  Future<List<ScheduledTask>> tasks() async {
    calls.add('tasks');
    final error = tasksError;
    if (error != null) throw error;
    return tasksValue;
  }

  @override
  Future<void> startTask(String id) async {
    calls.add('start:$id');
    final error = actionError;
    if (error != null) throw error;
  }

  @override
  Future<void> stopTask(String id) async {
    calls.add('stop:$id');
    final error = actionError;
    if (error != null) throw error;
  }

  @override
  Future<ActivityPage> activity({required int startIndex, bool? hasUserId}) async {
    calls.add('activity:$startIndex:${hasUserId ?? 'all'}');
    final error = activityError;
    if (error != null) throw error;
    final matching = [
      for (final entry in activityValue)
        if (hasUserId == null || (entry.userId != null) == hasUserId) entry,
    ];
    return ActivityPage(
      items: matching.skip(startIndex).take(AdminApi.activityPageSize).toList(),
      total: matching.length,
    );
  }
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/core/jellyfin`
Expected: PASS.

- [ ] **Step 5: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/core/jellyfin/admin_api.dart test/support/admin_fakes.dart test/core/jellyfin/admin_api_test.dart
git commit -m "feat(app): scan libraries, run tasks and page the activity log"
```

### Task 4: `PluginAdminApi`

**Files:**
- Create: `lib/core/social/plugin_admin_models.dart`, `lib/core/social/plugin_admin_api.dart`
- Modify: `lib/features/admin/admin_providers.dart`, `test/support/admin_fakes.dart`
- Test: `test/core/social/plugin_admin_api_test.dart`

- [ ] **Step 1: test che fallisce**

`test/core/social/plugin_admin_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/plugin_admin_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late PluginAdminApi api;

  /// La configurazione vera del plugin (senza i valori di Seerr) più una
  /// chiave che l'app non conosce.
  Map<String, dynamic> config() => {
        'NotifyNewTitles': true,
        'SeerrUrl': 'https://seerr.example.com',
        'SeerrApiKey': 'chiave',
        'SeerrWebhookSecret': 'segreto',
        'Nuova': [1, 2],
      };

  setUp(() {
    adapter = FakeAdapter((options) => switch (options.path) {
          '/WonderFlixWatchParty/Inbox/Announcements' =>
            const FakeResponse(200, {'Recipients': 12}),
          '/WonderFlixWatchParty/Inbox/NewTitles' =>
            const FakeResponse(200, {'Enabled': true, 'Pending': 3}),
          '/WonderFlixWatchParty/Inbox/NewTitles/Send' =>
            const FakeResponse(200, {'Titles': 3, 'Recipients': 12}),
          '/WonderFlixWatchParty/Requests/Admin' => const FakeResponse(200, {
              'Configured': true,
              'LastEventAt': '2026-10-05T17:47:00+00:00',
              'LastEventType': 'TEST_NOTIFICATION',
            }),
          '/WonderFlixWatchParty/Requests/Test' => const FakeResponse(
              200, {'Ok': true, 'Version': '3.4.1', 'Error': null}),
          '/Plugins/882eb47e-668a-4935-ba55-c2858eb4ed90/Configuration' =>
            options.method == 'GET'
                ? FakeResponse(200, config())
                : const FakeResponse(204),
          _ => const FakeResponse(404),
        });
    api = PluginAdminApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('annuncio', () async {
    expect(await api.announce('Ciao a tutti'), 12);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.data, {'Text': 'Ciao a tutti'});
  });

  test('annuncio non valido: 400', () async {
    adapter.handler = (_) => const FakeResponse(400);
    await expectLater(api.announce('x'),
        throwsA(isA<ServerErrorException>().having((e) => e.statusCode, 'status', 400)));
  });

  test('novità e "Invia ora"', () async {
    final status = await api.newTitles();
    expect(status.enabled, isTrue);
    expect(status.pending, 3);
    final sent = await api.sendNewTitles();
    expect(sent.titles, 3);
    expect(sent.recipients, 12);
    expect(adapter.requests.last.method, 'POST');
  });

  test('stato di Seerr; plugin vecchio (404) → null', () async {
    final status = (await api.seerrStatus())!;
    expect(status.configured, isTrue);
    expect(status.lastEventAt, DateTime.utc(2026, 10, 5, 17, 47));
    expect(status.lastEventType, 'TEST_NOTIFICATION');

    adapter.handler = (_) => const FakeResponse(404);
    expect(await api.seerrStatus(), isNull);
  });

  test('prova di Seerr', () async {
    final result = await api.testSeerr();
    expect(result.ok, isTrue);
    expect(result.version, '3.4.1');
    expect(result.error, isNull);

    adapter.handler = (_) =>
        const FakeResponse(200, {'Ok': false, 'Version': null, 'Error': 'SeerrAuth'});
    final failed = await api.testSeerr();
    expect(failed.ok, isFalse);
    expect(failed.error, 'SeerrAuth');
  });

  test('interruttore delle novità: cambia solo NotifyNewTitles', () async {
    await api.setNotifyNewTitles(false);

    expect(adapter.requests.map((r) => r.method), ['GET', 'POST']);
    final written = adapter.requests.last.data as Map<String, dynamic>;
    expect(written, {...config(), 'NotifyNewTitles': false});
  });

  test('un 403 arriva com\'è', () async {
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(api.newTitles(), throwsA(isA<ForbiddenException>()));
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/core/social/plugin_admin_api_test.dart`
Expected: FAIL in compilazione (`plugin_admin_api.dart` non esiste).

- [ ] **Step 3: implementa**

`lib/core/social/plugin_admin_models.dart`:

```dart
import '../jellyfin/json_fields.dart';

/// La casella delle novità e quanti titoli aspettano (`Inbox/NewTitles`).
class NewTitlesStatus {
  const NewTitlesStatus({required this.enabled, required this.pending});

  factory NewTitlesStatus.fromJson(Map<String, dynamic> json) =>
      NewTitlesStatus(
        enabled: json['Enabled'] == true,
        pending: jsonInt(json, 'Pending') ?? 0,
      );

  final bool enabled;
  final int pending;
}

/// Esito di "Invia ora" (`Inbox/NewTitles/Send`).
class NewTitlesSent {
  const NewTitlesSent({required this.titles, required this.recipients});

  factory NewTitlesSent.fromJson(Map<String, dynamic> json) => NewTitlesSent(
        titles: jsonInt(json, 'Titles') ?? 0,
        recipients: jsonInt(json, 'Recipients') ?? 0,
      );

  final int titles;
  final int recipients;
}

/// Seerr nel plugin (`Requests/Admin`): configurato e ultimo evento del
/// webhook.
class SeerrAdminStatus {
  const SeerrAdminStatus({
    required this.configured,
    this.lastEventAt,
    this.lastEventType,
  });

  factory SeerrAdminStatus.fromJson(Map<String, dynamic> json) =>
      SeerrAdminStatus(
        configured: json['Configured'] == true,
        lastEventAt: jsonDate(json, 'LastEventAt'),
        lastEventType: jsonString(json, 'LastEventType'),
      );

  final bool configured;
  final DateTime? lastEventAt;

  /// Il `notification_type` di Seerr ("MEDIA_PENDING", "MEDIA_AVAILABLE",
  /// "TEST_NOTIFICATION"…).
  final String? lastEventType;
}

/// Esito di "Prova collegamento" (`Requests/Test`).
class SeerrTestResult {
  const SeerrTestResult({required this.ok, this.version, this.error});

  factory SeerrTestResult.fromJson(Map<String, dynamic> json) =>
      SeerrTestResult(
        ok: json['Ok'] == true,
        version: jsonString(json, 'Version'),
        error: jsonString(json, 'Error'),
      );

  final bool ok;
  final String? version;

  /// "NotConfigured", "SeerrAuth" o "SeerrUnavailable".
  final String? error;
}
```

`lib/core/social/plugin_admin_api.dart`:

```dart
import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'plugin_admin_models.dart';

/// Gli endpoint da admin del plugin WonderFlix Watch Party (spec J §8.3).
/// Gli errori sono [ApiException]: 400 per un annuncio non valido, 403 per
/// chi non è admin.
class PluginAdminApi {
  PluginAdminApi(this._http);

  final JellyfinHttp _http;

  /// L'id del plugin (`Plugin.PluginId`).
  static const pluginId = '882eb47e-668a-4935-ba55-c2858eb4ed90';

  /// Lunghezza massima di un annuncio, come nel plugin.
  static const announcementMaxLength = 500;

  static const _base = '/WonderFlixWatchParty';
  static const _configPath = '/Plugins/$pluginId/Configuration';

  /// Esiti attesi: annuncio non valido, plugin più vecchio (404), Jellyfin
  /// che si riavvia. Nel log come info.
  static const _quiet = {400, 404, ...restartGatewayStatuses};

  /// Manda un annuncio a tutti gli utenti attivi; dà a quanti è arrivato.
  Future<int> announce(String text) async {
    final json = asJsonMap(await _http.post('$_base/Inbox/Announcements',
        body: {'Text': text}, quietStatuses: _quiet));
    final recipients = json['Recipients'];
    if (recipients is! int) throw const ServerErrorException(null);
    return recipients;
  }

  Future<NewTitlesStatus> newTitles() async => parseJson(
      await _http.get('$_base/Inbox/NewTitles', quietStatuses: _quiet),
      NewTitlesStatus.fromJson);

  /// Chiude subito l'ondata dei titoli nuovi ("Invia ora").
  Future<NewTitlesSent> sendNewTitles() async => parseJson(
      await _http.post('$_base/Inbox/NewTitles/Send', quietStatuses: _quiet),
      NewTitlesSent.fromJson);

  /// `null` con un plugin più vecchio della 1.4.0, che non ha l'endpoint.
  Future<SeerrAdminStatus?> seerrStatus() async {
    try {
      return parseJson(
          await _http.get('$_base/Requests/Admin', quietStatuses: _quiet),
          SeerrAdminStatus.fromJson);
    } on NotFoundException {
      return null;
    }
  }

  Future<SeerrTestResult> testSeerr() async => parseJson(
      await _http.post('$_base/Requests/Test', quietStatuses: _quiet),
      SeerrTestResult.fromJson);

  /// Accende o spegne la raccolta delle novità. Rilegge la configurazione
  /// intera del plugin e la riscrive con la sola `NotifyNewTitles` cambiata:
  /// le altre chiavi (Seerr, chiavi nuove) passano intatte. La
  /// configurazione non resta nell'app e non va nel log.
  Future<void> setNotifyNewTitles(bool enabled) async {
    final config = Map<String, dynamic>.of(asJsonMap(await _http.get(_configPath)));
    config['NotifyNewTitles'] = enabled;
    await _http.post(_configPath, body: config);
  }
}
```

In `lib/features/admin/admin_providers.dart` aggiungi l'import `'../../core/social/plugin_admin_api.dart'` e, dopo `adminApiProvider`:

```dart
final pluginAdminApiProvider = Provider<PluginAdminApi>(
    (ref) => PluginAdminApi(ref.watch(jellyfinHttpProvider)));
```

In `test/support/admin_fakes.dart`:
- import `package:wonderflix/core/social/plugin_admin_api.dart`, `package:wonderflix/core/social/plugin_admin_models.dart`, `package:wonderflix/features/social/social_providers.dart` e `'social_fakes.dart'`;
- prima di `adminTestOverrides`:

```dart
/// Seerr configurato, ultimo evento "Richiesta in attesa" alle 9 del
/// 2026-10-06.
final testSeerrStatus = SeerrAdminStatus(
  configured: true,
  lastEventAt: DateTime.utc(2026, 10, 6, 9),
  lastEventType: 'MEDIA_PENDING',
);

/// Il plugin finto per la scheda WonderFlix.
class FakePluginAdminApi implements PluginAdminApi {
  NewTitlesStatus newTitlesValue = const NewTitlesStatus(enabled: true, pending: 3);
  NewTitlesSent sentValue = const NewTitlesSent(titles: 3, recipients: 12);

  /// `null`: plugin più vecchio della 1.4.0.
  SeerrAdminStatus? seerrValue = testSeerrStatus;
  SeerrTestResult testValue = const SeerrTestResult(ok: true, version: '3.4.1');
  int announceRecipients = 12;

  Object? newTitlesError;
  Object? seerrError;

  /// Errore delle azioni: annuncio, interruttore, "Invia ora", prova.
  Object? actionError;

  /// Chiamate in ordine: `announce:<testo>`, `newTitles`, `send`, `seerr`,
  /// `test`, `notify:<true|false>`.
  final calls = <String>[];

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<int> announce(String text) async {
    calls.add('announce:$text');
    final error = actionError;
    if (error != null) throw error;
    return announceRecipients;
  }

  @override
  Future<NewTitlesStatus> newTitles() async {
    calls.add('newTitles');
    final error = newTitlesError;
    if (error != null) throw error;
    return newTitlesValue;
  }

  @override
  Future<NewTitlesSent> sendNewTitles() async {
    calls.add('send');
    final error = actionError;
    if (error != null) throw error;
    return sentValue;
  }

  @override
  Future<SeerrAdminStatus?> seerrStatus() async {
    calls.add('seerr');
    final error = seerrError;
    if (error != null) throw error;
    return seerrValue;
  }

  @override
  Future<SeerrTestResult> testSeerr() async {
    calls.add('test');
    final error = actionError;
    if (error != null) throw error;
    return testValue;
  }

  /// Come il plugin vero: la lettura dopo dà il valore scritto.
  @override
  Future<void> setNotifyNewTitles(bool enabled) async {
    calls.add('notify:$enabled');
    final error = actionError;
    if (error != null) throw error;
    newTitlesValue =
        NewTitlesStatus(enabled: enabled, pending: newTitlesValue.pending);
  }
}
```

- `adminTestOverrides` diventa:

```dart
/// Jellyfin e plugin finti, sessione di un admin, finestra in vista, plugin
/// con la cassetta delle notifiche (scheda WonderFlix).
List<Override> adminTestOverrides(
  FakeAdminApi api, {
  FakeSessionController? session,
  FakeAdminForeground? foreground,
  FakePluginAdminApi? plugin,
  SocialFeatures features = const SocialFeatures(inbox: true),
}) =>
    [
      adminApiProvider.overrideWithValue(api),
      pluginAdminApiProvider.overrideWithValue(plugin ?? FakePluginAdminApi()),
      sessionControllerProvider.overrideWith(() =>
          session ?? FakeSessionController(const SessionSignedIn(testAdmin))),
      adminForegroundProvider
          .overrideWith(() => foreground ?? FakeAdminForeground()),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ];
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/core/social/plugin_admin_api_test.dart test/features/admin`
Expected: PASS (i test del 16a non cambiano).

- [ ] **Step 5: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/core/social/plugin_admin_models.dart lib/core/social/plugin_admin_api.dart lib/features/admin/admin_providers.dart test/support/admin_fakes.dart test/core/social/plugin_admin_api_test.dart
git commit -m "feat(app): call the plugin admin endpoints"
```

### Task 5: azioni, pulsanti, conferma, card e ore

**Files:**
- Create: `lib/features/admin/admin_action_button.dart`, `lib/features/admin/admin_confirm_dialog.dart`
- Modify: `lib/features/admin/admin_tab_controller.dart`, `lib/features/admin/admin_widgets.dart`, `lib/features/admin/admin_time.dart`
- Test: `test/features/admin/admin_tab_controller_test.dart`, `test/features/admin/admin_action_button_test.dart`, `test/features/admin/admin_confirm_dialog_test.dart`, `test/features/admin/admin_time_test.dart`

- [ ] **Step 1: test che falliscono**

In `test/features/admin/admin_tab_controller_test.dart`, nella classe `_TestController` aggiungi:

```dart
  /// Le azioni del controller, per i test di [act].
  Future<R> runAction<R>(Future<R> Function() action) => act(action);
```

e in fondo a `main()`:

```dart
  group('act', () {
    test('esegue l\'azione e poi rilegge la scheda', () {
      fakeAsync((async) {
        final container = makeContainer();
        async.elapse(Duration.zero);
        expect(_reads, 1);

        int? result;
        unawaited(container
            .read(_testProvider.notifier)
            .runAction(() async => 42)
            .then((value) => result = value));
        async.elapse(Duration.zero);

        expect(result, 42);
        expect(_reads, 2);
      });
    });

    test('403: rilegge l\'utente, l\'errore arriva a chi chiama, e rilegge',
        () {
      fakeAsync((async) {
        final container = makeContainer();
        async.elapse(Duration.zero);

        Object? caught;
        unawaited(container
            .read(_testProvider.notifier)
            .runAction<void>(() async => throw const ForbiddenException())
            .catchError((Object error) {
          caught = error;
        }));
        async.elapse(Duration.zero);

        expect(caught, isA<ForbiddenException>());
        expect(session.refreshUserCalls, 1);
        expect(_reads, 2);
      });
    });
  });
```

In `test/features/admin/admin_time_test.dart`, in fondo al test:

```dart
    expect(adminDurationLabel(it, const Duration(seconds: 45)), '45 s');
    expect(adminDurationLabel(it, const Duration(minutes: 3, seconds: 20)),
        '3 min');
    expect(adminDurationLabel(it, const Duration(hours: 1, minutes: 5)),
        '1 h 5 min');
    expect(adminFullDateTime(DateTime(2026, 10, 6, 8, 10, 3), it),
        '6 ott 2026, 08:10:03');
```

`test/features/admin/admin_action_button_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/admin_action_button.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));

  Future<void> pumpButton(
      WidgetTester tester, Future<void> Function()? action) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: AdminActionButton(
              label: 'Avvia', icon: Icons.play_arrow, onPressed: action),
        ),
      ),
    );
  }

  bool enabled(WidgetTester tester) =>
      tester.widget<OutlinedButton>(find.bySubtype<OutlinedButton>()).onPressed !=
      null;

  testWidgets('mentre l\'azione è in corso è disattivato', (tester) async {
    final pending = Completer<void>();
    var runs = 0;
    await pumpButton(tester, () {
      runs++;
      return pending.future;
    });

    await tester.tap(find.text('Avvia'));
    await tester.pump();
    expect(enabled(tester), isFalse);
    await tester.tap(find.text('Avvia'), warnIfMissed: false);
    expect(runs, 1);

    pending.complete();
    await tester.pumpAndSettle();
    expect(enabled(tester), isTrue);
  });

  testWidgets('un errore diventa un avviso', (tester) async {
    await pumpButton(
        tester, () async => throw const ServerUnreachableException());

    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();

    expect(find.text(it.errorServerUnreachable), findsOneWidget);
    expect(enabled(tester), isTrue);
  });

  testWidgets('senza azione è disattivato', (tester) async {
    await pumpButton(tester, null);
    expect(enabled(tester), isFalse);
  });
}
```

`test/features/admin/admin_confirm_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_confirm_dialog.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('Annulla: no; il pulsante di conferma: sì', (tester) async {
    bool? result;
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showAdminConfirmDialog(
              context,
              title: 'Annuncio',
              message: 'Arriva a tutti.',
              confirmLabel: 'Invia',
            ),
            child: const Text('apri'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('Annuncio'), findsOneWidget);
    expect(find.text('Arriva a tutti.'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Invia'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/admin/admin_tab_controller_test.dart test/features/admin/admin_time_test.dart test/features/admin/admin_action_button_test.dart test/features/admin/admin_confirm_dialog_test.dart`
Expected: FAIL in compilazione (`act`, `adminDurationLabel`, `admin_action_button.dart`, `admin_confirm_dialog.dart` non esistono).

- [ ] **Step 3: implementa**

`lib/features/admin/admin_tab_controller.dart`:
- aggiungi l'import `package:flutter/foundation.dart` con `show protected`;
- in `AdminTabController`, dopo `setInterval`:

```dart
  /// Un'azione della scheda (Avvia, Scansiona, Invia…). Un 403 fa rileggere
  /// l'utente (spec J §12); dopo l'azione, riuscita o no, la scheda si
  /// rilegge. L'errore arriva a chi chiama, che lo mostra.
  @protected
  Future<R> act<R>(Future<R> Function() action) async {
    // Come in `_read`: il `Ref` di questa costruzione del provider.
    final ref = this.ref;
    try {
      return await action();
    } on ForbiddenException {
      if (ref.mounted) {
        unawaited(ref.read(sessionControllerProvider.notifier).refreshUser());
      }
      rethrow;
    } finally {
      if (ref.mounted) unawaited(refresh());
    }
  }
```

`lib/features/admin/admin_time.dart`, in fondo:

```dart
/// "45 s", "3 min", "1 h 5 min": quanto è durata un'attività.
String adminDurationLabel(AppLocalizations l, Duration duration) {
  if (duration < const Duration(minutes: 1)) {
    return l.adminDurationSeconds(duration.inSeconds);
  }
  if (duration < const Duration(hours: 1)) {
    return l.adminDurationMinutes(duration.inMinutes);
  }
  return l.adminDurationHours(
      duration.inHours, duration.inMinutes.remainder(60));
}

/// "6 ott 2026, 08:10:03": data e ora complete, al passaggio del mouse nel
/// Registro (spec J §9.5).
String adminFullDateTime(DateTime at, AppLocalizations l) {
  final local = at.toLocal();
  return '${DateFormat.yMMMd(l.localeName).format(local)}, '
      '${DateFormat.Hms(l.localeName).format(local)}';
}
```

`lib/features/admin/admin_action_button.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../../app/error_text.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';

final _log = Logger('admin');

/// Il pulsante di un'azione della pagina Amministrazione (spec J §12):
/// mentre l'azione è in corso è disattivato, così non parte due volte. Se
/// l'azione lancia un errore, compare un avviso con `describeError`; gli
/// esiti da dire (riuscita, errori particolari) li mostra l'azione stessa.
class AdminActionButton extends StatefulWidget {
  const AdminActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;

  /// `null`: disattivato.
  final Future<void> Function()? onPressed;

  @override
  State<AdminActionButton> createState() => _AdminActionButtonState();
}

class _AdminActionButtonState extends State<AdminActionButton> {
  bool _running = false;

  Future<void> _run(Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _running = true);
    try {
      await action();
    } on Object catch (error, stack) {
      // Un errore che non viene dal server è un difetto: resta nel log.
      if (error is! ApiException) {
        _log.warning('azione non riuscita', error, stack);
      }
      messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.onPressed;
    return WfButton.secondary(
      label: widget.label,
      icon: widget.icon,
      onPressed:
          action == null || _running ? null : () => unawaited(_run(action)),
    );
  }
}
```

`lib/features/admin/admin_confirm_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';

/// Una conferma della pagina Amministrazione: titolo, messaggio, "Annulla"
/// e il pulsante [confirmLabel]. `true` solo con la conferma.
Future<bool> showAdminConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showWfDialog<bool>(
    context,
    semanticLabel: title,
    builder: (context) {
      final l = AppLocalizations.of(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Text(message),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l.adminCancel),
              ),
              const SizedBox(width: 12),
              FilledButton(
                // Il tema fa i FilledButton larghi all'infinito: in una Row
                // servono larghi quanto il testo.
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
```

In fondo a `lib/features/admin/admin_widgets.dart` (aggiungi l'import `'../../app/error_text.dart'`):

```dart
/// Una card della pagina (scheda WonderFlix): titolo con l'icona e
/// contenuto.
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WfColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: WfColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: WfColors.gold),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

/// L'errore di una card senza dati, con "Riprova".
class AdminCardError extends StatelessWidget {
  const AdminCardError({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(describeError(l, error),
              style: const TextStyle(color: WfColors.creamMuted)),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: onRetry, child: Text(l.retry)),
      ],
    );
  }
}
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/admin`
Expected: PASS.

- [ ] **Step 5: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/features/admin/admin_tab_controller.dart lib/features/admin/admin_time.dart lib/features/admin/admin_action_button.dart lib/features/admin/admin_confirm_dialog.dart lib/features/admin/admin_widgets.dart test/features/admin/admin_tab_controller_test.dart test/features/admin/admin_time_test.dart test/features/admin/admin_action_button_test.dart test/features/admin/admin_confirm_dialog_test.dart
git commit -m "feat(app): add admin page actions, confirmations and cards"
```

---

## Gruppo B — schede

### Task 6: scheda Manutenzione

**Files:**
- Create: `lib/features/admin/task_labels.dart`, `lib/features/admin/maintenance_controller.dart`, `lib/features/admin/maintenance_tab.dart`
- Test: `test/features/admin/task_labels_test.dart`, `test/features/admin/maintenance_controller_test.dart`, `test/features/admin/maintenance_tab_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/admin/task_labels_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/jellyfin/maintenance_models.dart';
import 'package:wonderflix/features/admin/task_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  test('stato di un\'attività ferma', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final now = DateTime(2026, 10, 6, 10);
    TaskResult result(TaskStatus status) => TaskResult(
          start: DateTime(2026, 10, 6, 8),
          end: DateTime(2026, 10, 6, 8, 3),
          status: status,
        );

    expect(taskIdleLabel(it, null, now), 'Mai eseguita');
    expect(taskIdleLabel(it, result(TaskStatus.completed), now),
        'Ultima: 1 h fa · Completata in 3 min');
    expect(taskIdleLabel(it, result(TaskStatus.cancelled), now),
        'Ultima: 1 h fa · Annullata');
    expect(taskIdleLabel(it, result(TaskStatus.aborted), now),
        'Ultima: 1 h fa · Interrotta');
    expect(taskIdleLabel(it, result(TaskStatus.failed), now), 'Ultima: 1 h fa',
        reason: '"Non riuscita" è un pulsante a parte');
    expect(
        taskIdleLabel(it, const TaskResult(status: TaskStatus.unknown), now), '');
  });

  test('avanzamento', () {
    expect(taskProgressLabel(37.5), '38%');
    expect(taskProgressLabel(null), '0%');
  });
}
```

`test/features/admin/maintenance_controller_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/maintenance_models.dart';
import 'package:wonderflix/features/admin/maintenance_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

void main() {
  late FakeAdminApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAdminApi()
      ..librariesValue = testLibraries()
      ..tasksValue = testTasks();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(api, session: session),
      retry: (_, _) => null,
    );
    container.listen(maintenanceControllerProvider, (_, _) {});
    return container;
  }

  test('attività per categoria e per nome; la scansione della libreria a parte',
      () {
    fakeAsync((async) {
      final container = makeContainer();
      async.elapse(Duration.zero);

      final snapshot = container.read(maintenanceControllerProvider).value!;
      expect(snapshot.libraries, hasLength(4));
      expect(snapshot.groups.map((g) => g.category), [
        'Applicazione',
        'Auto Collections',
        'Intro Skipper',
        'Libreria',
        'Manutenzione',
        'Trakt',
      ]);
      expect(snapshot.groups[3].tasks.map((t) => t.name), [
        'Estrattore di Keyframe',
        'Scansione della libreria',
        'Webhook Item Added Notifier',
      ]);
      expect(snapshot.scanTask!.id, 't-scan');
      expect(snapshot.busy, isTrue);
    });
  });

  test('qualcosa in corso: ogni 2 s; tutto fermo: ogni 15 s', () {
    fakeAsync((async) {
      makeContainer();
      async.elapse(Duration.zero);
      expect(api.count('tasks'), 1);
      async.elapse(const Duration(seconds: 2));
      expect(api.count('tasks'), 2);

      // Finisce tutto: la lettura dopo lo vede e rallenta.
      api
        ..librariesValue = [
          for (final library in testLibraries())
            LibraryFolder(
                itemId: library.itemId, name: library.name, kind: library.kind),
        ]
        ..tasksValue = [
          for (final task in testTasks())
            if (task.state == TaskState.idle) task,
        ];
      async.elapse(const Duration(seconds: 2));
      expect(api.count('tasks'), 3);
      async.elapse(const Duration(seconds: 14));
      expect(api.count('tasks'), 3);
      async.elapse(const Duration(seconds: 1));
      expect(api.count('tasks'), 4);
    });
  });

  test('azioni: chiamano Jellyfin e la scheda si rilegge subito', () {
    fakeAsync((async) {
      final container = makeContainer();
      async.elapse(Duration.zero);
      final controller = container.read(maintenanceControllerProvider.notifier);

      unawaited(controller.scanAll());
      unawaited(controller.scanLibrary('a656b907eb3a73532e40e44b968d0225'));
      unawaited(controller.startTask('t-optimize'));
      unawaited(controller.stopTask('t-autocol'));
      async.elapse(Duration.zero);

      expect(
          api.calls,
          containsAllInOrder([
            'scanAll',
            'scan:a656b907eb3a73532e40e44b968d0225',
            'start:t-optimize',
            'stop:t-autocol',
          ]));
      expect(api.count('tasks'), greaterThanOrEqualTo(2));
    });
  });

  test('azione rifiutata (403): rilegge l\'utente e l\'errore arriva', () {
    fakeAsync((async) {
      api.actionError = const ForbiddenException();
      final container = makeContainer();
      async.elapse(Duration.zero);

      Object? caught;
      unawaited(container
          .read(maintenanceControllerProvider.notifier)
          .startTask('t-optimize')
          .catchError((Object error) {
        caught = error;
      }));
      async.elapse(Duration.zero);

      expect(caught, isA<ForbiddenException>());
      expect(session.refreshUserCalls, 1);
    });
  });

  test('un errore di una delle due letture è un errore della scheda', () {
    fakeAsync((async) {
      api.tasksError = const ServerUnreachableException();
      final container = makeContainer();
      async.elapse(Duration.zero);

      final data = container.read(maintenanceControllerProvider);
      expect(data.value, isNull);
      expect(data.error, isA<ServerUnreachableException>());
    });
  });
}
```

`test/features/admin/maintenance_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/maintenance_tab.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakeAdminApi api;

  setUp(() {
    api = FakeAdminApi()
      ..librariesValue = testLibraries()
      ..tasksValue = testTasks();
  });

  /// Alta abbastanza per tutte le righe.
  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: MaintenanceTab()),
        overrides: adminTestOverrides(api),
        surfaceSize: const Size(1440, 2400));
    await tester.pumpAndSettle();
  }

  Finder inRow(String rowKey, Finder matching) =>
      find.descendant(of: find.byKey(ValueKey(rowKey)), matching: matching);

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<OutlinedButton>(button).onPressed != null;

  testWidgets('librerie: scansione in corso e Scansiona', (tester) async {
    await pumpTab(tester);

    expect(find.text('Librerie'), findsOneWidget);
    for (final name in ['Movies', 'Collezioni2', 'Anime', 'Shows']) {
      expect(find.text(name), findsOneWidget);
    }
    const movies = 'library-f137a2dd21bbc1b99aa5c0f6bf02a805';
    const shows = 'library-a656b907eb3a73532e40e44b968d0225';
    expect(
        find.byKey(const Key(
            'library-progress-f137a2dd21bbc1b99aa5c0f6bf02a805')),
        findsOneWidget);
    expect(enabled(tester, inRow(movies, find.bySubtype<OutlinedButton>())),
        isFalse);
    expect(enabled(tester, inRow(shows, find.bySubtype<OutlinedButton>())),
        isTrue);

    await tester.tap(inRow(shows, find.text('Scansiona')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('scan:a656b907eb3a73532e40e44b968d0225'));

    // "Scansiona tutte", con l'ultima scansione accanto.
    expect(find.byKey(const Key('scan-all-status')), findsOneWidget);
    await tester.tap(find.text('Scansiona tutte'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('scanAll'));
  });

  testWidgets('attività: gruppi in ordine e stati', (tester) async {
    await pumpTab(tester);

    expect(find.text('Attività pianificate'), findsOneWidget);
    final applicazione = tester.getTopLeft(find.text('Applicazione')).dy;
    final introSkipper = tester.getTopLeft(find.text('Intro Skipper')).dy;
    final trakt = tester.getTopLeft(find.text('Trakt')).dy;
    expect(applicazione, lessThan(introSkipper));
    expect(introSkipper, lessThan(trakt));

    expect(inRow('task-t-autocol', find.text('38%')), findsOneWidget);
    expect(inRow('task-t-autocol', find.text('Ferma')), findsOneWidget);
    expect(inRow('task-t-webhook', find.text('Arresto…')), findsOneWidget);
    expect(inRow('task-t-webhook', find.bySubtype<OutlinedButton>()),
        findsNothing);
    expect(inRow('task-t-skipme', find.text('Mai eseguita')), findsOneWidget);
    expect(inRow('task-t-keyframe', find.textContaining('Annullata')),
        findsOneWidget);
    expect(
        inRow('task-t-optimize', find.textContaining('Completata in 3 min')),
        findsOneWidget);
    expect(inRow('task-t-optimize', find.text('Avvia')), findsOneWidget);
  });

  testWidgets('"Non riuscita" apre il messaggio d\'errore', (tester) async {
    await pumpTab(tester);

    expect(find.textContaining('401 (Unauthorized)'), findsNothing);
    await tester.tap(inRow('task-t-trakt', find.text('Non riuscita')));
    await tester.pump();
    expect(find.textContaining('401 (Unauthorized)'), findsOneWidget);
  });

  testWidgets('Avvia e Ferma chiamano Jellyfin', (tester) async {
    await pumpTab(tester);

    await tester.tap(inRow('task-t-optimize', find.text('Avvia')));
    await tester.pumpAndSettle();
    await tester.tap(inRow('task-t-autocol', find.text('Ferma')));
    await tester.pumpAndSettle();

    expect(api.calls, containsAllInOrder(['start:t-optimize', 'stop:t-autocol']));
  });

  testWidgets('azione rifiutata: un avviso', (tester) async {
    api.actionError = const ServerErrorException(500);
    await pumpTab(tester);

    await tester.tap(inRow('task-t-optimize', find.text('Avvia')));
    await tester.pumpAndSettle();

    expect(find.text(it.errorGeneric), findsOneWidget);
  });

  testWidgets('senza dati: errore e Riprova', (tester) async {
    api.librariesError = const ServerUnreachableException();
    await pumpTab(tester);

    expect(find.text('Riprova'), findsOneWidget);
    api.librariesError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsOneWidget);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/admin/task_labels_test.dart test/features/admin/maintenance_controller_test.dart test/features/admin/maintenance_tab_test.dart`
Expected: FAIL in compilazione (i file non esistono).

- [ ] **Step 3: implementa le etichette**

`lib/features/admin/task_labels.dart`:

```dart
import '../../core/jellyfin/maintenance_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'admin_time.dart';

/// Lo stato di un'attività ferma (spec J §9.4): "Ultima: 2 h fa · Completata
/// in 3 min", "Ultima: ieri · Annullata", "Mai eseguita". "Non riuscita"
/// non c'è: è un pulsante a parte, che apre il messaggio d'errore.
String taskIdleLabel(AppLocalizations l, TaskResult? result, DateTime now) {
  if (result == null) return l.adminTaskNeverRun;
  final parts = <String>[];
  final when = result.end ?? result.start;
  if (when != null) parts.add(l.adminTaskLastRun(adminTimeLabel(when, now, l)));
  switch (result.status) {
    case TaskStatus.completed:
      final duration = result.duration;
      if (duration != null) {
        parts.add(l.adminTaskCompletedIn(adminDurationLabel(l, duration)));
      }
    case TaskStatus.cancelled:
      parts.add(l.adminTaskCancelled);
    case TaskStatus.aborted:
      parts.add(l.adminTaskAborted);
    case TaskStatus.failed || TaskStatus.unknown:
      break;
  }
  return parts.join(' · ');
}

/// "38%": l'avanzamento di un'attività in corso.
String taskProgressLabel(double? progress) => '${(progress ?? 0).round()}%';
```

- [ ] **Step 4: implementa il controller**

`lib/features/admin/maintenance_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/maintenance_models.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';

/// Le attività di una categoria.
class TaskGroup {
  const TaskGroup({required this.category, required this.tasks});

  final String category;
  final List<ScheduledTask> tasks;
}

/// Il contenuto della scheda Manutenzione (spec J §9.4).
class MaintenanceSnapshot {
  const MaintenanceSnapshot({
    this.libraries = const [],
    this.groups = const [],
    this.scanTask,
  });

  /// Attività per categoria e poi per nome, senza badare alle maiuscole,
  /// come la Dashboard web (decisione 2 del piano 16b).
  factory MaintenanceSnapshot.from(
      List<LibraryFolder> libraries, List<ScheduledTask> tasks) {
    int byText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    final sorted = [...tasks]..sort((a, b) {
        final byCategory = byText(a.category ?? '', b.category ?? '');
        return byCategory != 0 ? byCategory : byText(a.name, b.name);
      });
    final groups = <TaskGroup>[];
    for (final task in sorted) {
      final category = task.category ?? '';
      if (groups.isNotEmpty && groups.last.category == category) {
        groups.last.tasks.add(task);
      } else {
        groups.add(TaskGroup(category: category, tasks: [task]));
      }
    }
    ScheduledTask? scanTask;
    for (final task in tasks) {
      if (task.key == ScheduledTask.refreshLibraryKey) scanTask = task;
    }
    return MaintenanceSnapshot(
        libraries: libraries, groups: groups, scanTask: scanTask);
  }

  final List<LibraryFolder> libraries;
  final List<TaskGroup> groups;

  /// "Scansione della libreria": il suo stato sta accanto a "Scansiona
  /// tutte".
  final ScheduledTask? scanTask;

  /// Una scansione o un'attività è in corso (o in arresto): la scheda si
  /// rilegge più spesso.
  bool get busy =>
      libraries.any((library) => library.refreshing) ||
      groups.any((group) =>
          group.tasks.any((task) => task.state != TaskState.idle));
}

/// Librerie e attività, rilette ogni 15 s, o ogni 2 s quando qualcosa è in
/// corso (spec J §9.4).
class MaintenanceController extends AdminTabController<MaintenanceSnapshot> {
  static const idleEvery = Duration(seconds: 15);
  static const busyEvery = Duration(seconds: 2);

  @override
  Duration get interval => idleEvery;

  @override
  Future<MaintenanceSnapshot> fetch() async {
    final api = ref.read(adminApiProvider);
    final results = await Future.wait<Object>(
      [api.libraries(), api.tasks()],
      eagerError: true,
    );
    final snapshot = MaintenanceSnapshot.from(
      results[0] as List<LibraryFolder>,
      results[1] as List<ScheduledTask>,
    );
    // Vale dal prossimo turno: questa lettura è ancora in corso.
    setInterval(snapshot.busy ? busyEvery : idleEvery);
    return snapshot;
  }

  Future<void> scanAll() => act(() => ref.read(adminApiProvider).scanAll());

  Future<void> scanLibrary(String itemId) =>
      act(() => ref.read(adminApiProvider).scanLibrary(itemId));

  Future<void> startTask(String id) =>
      act(() => ref.read(adminApiProvider).startTask(id));

  Future<void> stopTask(String id) =>
      act(() => ref.read(adminApiProvider).stopTask(id));
}

final maintenanceControllerProvider = NotifierProvider.autoDispose<
    MaintenanceController,
    AdminData<MaintenanceSnapshot>>(MaintenanceController.new);
```

- [ ] **Step 5: implementa la scheda**

`lib/features/admin/maintenance_tab.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/maintenance_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'admin_action_button.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';
import 'maintenance_controller.dart';
import 'task_labels.dart';

/// La scheda Manutenzione (spec J §9.4): librerie e attività pianificate.
class MaintenanceTab extends ConsumerStatefulWidget {
  const MaintenanceTab({super.key});

  @override
  ConsumerState<MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends ConsumerState<MaintenanceTab> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(maintenanceControllerProvider);
    final controller = ref.read(maintenanceControllerProvider.notifier);
    final snapshot = data.value;
    if (snapshot == null) {
      final error = data.error;
      if (error == null) return const LoadingView();
      return ErrorView(
          error: error, onRetry: () => unawaited(controller.refresh()));
    }
    final now = clock.now();
    final updatedAt = data.updatedAt;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      children: [
        if (data.stale && updatedAt != null) AdminStaleNote(updatedAt: updatedAt),
        _LibrariesHeader(
            scanTask: snapshot.scanTask, now: now, onScanAll: controller.scanAll),
        for (final library in snapshot.libraries)
          LibraryRow(
            key: ValueKey('library-${library.itemId}'),
            library: library,
            onScan: () => controller.scanLibrary(library.itemId),
          ),
        AdminSectionTitle(title: l.adminTasks),
        for (final group in snapshot.groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(group.category,
                style: const TextStyle(
                    color: WfColors.gold, fontWeight: FontWeight.w600)),
          ),
          for (final task in group.tasks)
            TaskRow(
              key: ValueKey('task-${task.id}'),
              task: task,
              now: now,
              onStart: () => controller.startTask(task.id),
              onStop: () => controller.stopTask(task.id),
            ),
        ],
      ],
    );
  }
}

/// "Librerie", lo stato della "Scansione della libreria" e "Scansiona
/// tutte".
class _LibrariesHeader extends StatelessWidget {
  const _LibrariesHeader({
    required this.scanTask,
    required this.now,
    required this.onScanAll,
  });

  final ScheduledTask? scanTask;
  final DateTime now;
  final Future<void> Function() onScanAll;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final task = scanTask;
    final running = task != null && task.state != TaskState.idle;
    final last = task?.lastResult;
    final when = last?.end ?? last?.start;
    final status = running
        ? taskProgressLabel(task.progress)
        : when == null
            ? null
            : l.adminTaskLastRun(adminTimeLabel(when, now, l));
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Text(l.adminLibraries,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (status != null)
            Text(status,
                key: const Key('scan-all-status'),
                style: const TextStyle(color: WfColors.creamMuted, fontSize: 13)),
          const SizedBox(width: 12),
          AdminActionButton(
            label: l.adminScanAll,
            icon: LucideIcons.refreshCw,
            onPressed: running ? null : onScanAll,
          ),
        ],
      ),
    );
  }
}

/// Una libreria: icona, nome, la barra durante la scansione e "Scansiona".
class LibraryRow extends StatelessWidget {
  const LibraryRow({super.key, required this.library, required this.onScan});

  final LibraryFolder library;
  final Future<void> Function() onScan;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final icon = switch (library.kind) {
      LibraryKind.movies => LucideIcons.film,
      LibraryKind.shows => LucideIcons.tv,
      LibraryKind.other => LucideIcons.folder,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: WfColors.gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(library.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (library.refreshing) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    key: Key('library-progress-${library.itemId}'),
                    value: (library.refreshProgress ?? 0) / 100,
                    minHeight: 4,
                    color: WfColors.gold,
                    backgroundColor: WfColors.surfaceHigh,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          AdminActionButton(
            label: l.adminScan,
            icon: LucideIcons.scanLine,
            onPressed: library.refreshing ? null : onScan,
          ),
        ],
      ),
    );
  }
}

/// Un'attività: nome, descrizione, stato e Avvia o Ferma. "Non riuscita"
/// apre il messaggio d'errore.
class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.now,
    required this.onStart,
    required this.onStop,
  });

  final ScheduledTask task;
  final DateTime now;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _showError = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final task = widget.task;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    final description = task.description;
    final result = task.lastResult;
    final errorMessage = result?.errorMessage;
    final failed = result?.status == TaskStatus.failed;
    final Widget status = switch (task.state) {
      TaskState.running => Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: (task.progress ?? 0) / 100,
                minHeight: 4,
                color: WfColors.gold,
                backgroundColor: WfColors.surfaceHigh,
              ),
            ),
            const SizedBox(width: 8),
            Text(taskProgressLabel(task.progress), style: muted),
          ],
        ),
      TaskState.cancelling => Text(l.adminTaskStopping, style: muted),
      TaskState.idle => Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (taskIdleLabel(l, result, widget.now) case final label
                when label.isNotEmpty)
              Text(label, style: muted),
            if (failed)
              InkWell(
                onTap: errorMessage == null
                    ? null
                    : () => setState(() => _showError = !_showError),
                child: Text(l.adminTaskFailed,
                    style: const TextStyle(
                        color: WfColors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
    };
    final Widget action = switch (task.state) {
      TaskState.idle => AdminActionButton(
          label: l.adminTaskStart,
          icon: LucideIcons.play,
          onPressed: widget.onStart,
        ),
      TaskState.running => AdminActionButton(
          label: l.adminTaskStop,
          icon: LucideIcons.square,
          onPressed: widget.onStop,
        ),
      TaskState.cancelling => const SizedBox.shrink(),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(task.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (description != null)
                  Tooltip(
                    message: description,
                    child: Text(description,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  ),
                const SizedBox(height: 4),
                status,
                if (_showError && errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(errorMessage,
                        style: const TextStyle(
                            color: WfColors.creamMuted, fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          action,
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/features/admin/task_labels_test.dart test/features/admin/maintenance_controller_test.dart test/features/admin/maintenance_tab_test.dart`
Expected: PASS.

- [ ] **Step 7: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/features/admin/task_labels.dart lib/features/admin/maintenance_controller.dart lib/features/admin/maintenance_tab.dart test/features/admin/task_labels_test.dart test/features/admin/maintenance_controller_test.dart test/features/admin/maintenance_tab_test.dart
git commit -m "feat(app): add the maintenance tab to the admin page"
```

### Task 7: scheda Registro

**Files:**
- Create: `lib/features/admin/activity_controller.dart`, `lib/features/admin/activity_tab.dart`
- Test: `test/features/admin/activity_controller_test.dart`, `test/features/admin/activity_tab_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/admin/activity_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/activity_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/activity_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

void main() {
  late FakeAdminApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAdminApi()..activityValue = testActivityEntries(120);
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(api, session: session),
      retry: (_, _) => null,
    );
    container.listen(activityControllerProvider, (_, _) {});
    return container;
  }

  ActivityState state(ProviderContainer container) =>
      container.read(activityControllerProvider);

  test('pagine da 50 dalla più recente, fino alla fine', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);

    expect(state(container).items, hasLength(50));
    expect(state(container).items.first.id, 120);
    expect(state(container).total, 120);
    expect(state(container).hasMore, isTrue);

    await controller.loadMore();
    await controller.loadMore();
    expect(state(container).items, hasLength(120));
    expect(state(container).hasMore, isFalse);
    expect(api.calls, ['activity:0:all', 'activity:50:all', 'activity:100:all']);

    await controller.loadMore();
    expect(api.count('activity:100:all'), 1, reason: 'non c\'è altro');
  });

  test('filtro: riparte dalla prima pagina, solo le voci giuste', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);

    await controller.setFilter(ActivityFilter.users);
    expect(state(container).filter, ActivityFilter.users);
    expect(state(container).items.every((e) => e.userId != null), isTrue);
    expect(state(container).total, 60);
    expect(api.calls.last, 'activity:0:true');

    await controller.setFilter(ActivityFilter.system);
    expect(state(container).items.every((e) => e.userId == null), isTrue);
    expect(api.calls.last, 'activity:0:false');
  });

  test('Aggiorna: di nuovo dalla prima pagina', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);
    await controller.loadMore();

    await controller.reload();
    expect(state(container).items, hasLength(50));
    expect(api.calls.last, 'activity:0:all');
  });

  test('voci nuove in cima tra una pagina e l\'altra: niente doppioni',
      () async {
    final container = makeContainer();
    await pumpEventQueue();
    // Arrivano tre voci nuove: la seconda pagina parte tre voci prima.
    api.activityValue = [
      for (var id = 123; id > 120; id--) ActivityEntry(id: id, name: 'Nuova $id'),
      ...api.activityValue,
    ];

    await container.read(activityControllerProvider.notifier).loadMore();

    final ids = state(container).items.map((e) => e.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, hasLength(97));
  });

  test('errore: resta l\'elenco, Riprova ripete la pagina', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);

    api.activityError = const ServerUnreachableException();
    await controller.loadMore();
    expect(state(container).error, isA<ServerUnreachableException>());
    expect(state(container).items, hasLength(50));

    await controller.loadMore();
    expect(api.count('activity:50:all'), 1, reason: 'dopo un errore solo Riprova');

    api.activityError = null;
    await controller.retry();
    expect(state(container).error, isNull);
    expect(state(container).items, hasLength(100));
  });

  test('403: rilegge l\'utente', () async {
    api.activityError = const ForbiddenException();
    makeContainer();
    await pumpEventQueue();

    expect(session.refreshUserCalls, 1);
  });
}
```

`test/features/admin/activity_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/activity_tab.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;

  setUp(() => api = FakeAdminApi()..activityValue = testActivity());

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: ActivityTab()),
        overrides: adminTestOverrides(api));
    await tester.pumpAndSettle();
  }

  testWidgets('voci con gravità, dettagli e titolo', (tester) async {
    await pumpTab(tester);

    expect(find.text('anna si è disconnesso da FireTV Soggiorno'), findsOneWidget);
    expect(find.text('Indirizzo IP: 203.0.113.7'), findsOneWidget);
    expect(find.byKey(const Key('activity-severity-12134-info')), findsOneWidget);
    expect(find.byKey(const Key('activity-severity-11950-warning')),
        findsOneWidget);
    expect(find.byKey(const Key('activity-severity-11904-error')), findsOneWidget);

    // Il dettaglio si apre con un clic.
    expect(find.text('Nome utente o password non validi.'), findsNothing);
    await tester.tap(find.text('Tentativo di accesso fallito da marco'));
    await tester.pump();
    expect(find.text('Nome utente o password non validi.'), findsOneWidget);

    // Solo la riproduzione ha un titolo da aprire.
    expect(find.text('Apri il titolo'), findsOneWidget);

    // Tutto letto: in fondo lo dice.
    expect(find.text('Non ci sono altre voci'), findsOneWidget);
  });

  testWidgets('filtri e Aggiorna', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('Utenti'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'activity:0:true');
    expect(find.text('WonderFlix Watch Party è stato Installato'), findsNothing);

    await tester.tap(find.text('Sistema'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'activity:0:false');
    expect(find.text('WonderFlix Watch Party è stato Installato'), findsOneWidget);

    await tester.tap(find.text('Aggiorna'));
    await tester.pumpAndSettle();
    expect(api.count('activity:0:false'), 2);
  });

  testWidgets('vuoto', (tester) async {
    api.activityValue = const [];
    await pumpTab(tester);

    expect(find.text('Nessuna voce'), findsOneWidget);
  });

  testWidgets('errore della prima pagina: Riprova', (tester) async {
    api.activityError = const ServerUnreachableException();
    await pumpTab(tester);

    expect(find.text('Riprova'), findsOneWidget);
    api.activityError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('anna si è disconnesso da FireTV Soggiorno'), findsOneWidget);
  });

  testWidgets('scorrendo in fondo arriva la pagina dopo', (tester) async {
    api.activityValue = testActivityEntries(120);
    await pumpTab(tester);
    expect(api.calls, ['activity:0:all']);

    await tester.scrollUntilVisible(find.text('Voce 71'), 500,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();

    expect(api.calls, contains('activity:50:all'));
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/admin/activity_controller_test.dart test/features/admin/activity_tab_test.dart`
Expected: FAIL in compilazione (i file non esistono).

- [ ] **Step 3: implementa il controller**

`lib/features/admin/activity_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/activity_models.dart';
import '../../core/jellyfin/api_exception.dart';
import '../auth/session_controller.dart';
import 'admin_providers.dart';

/// I filtri del Registro (spec J §9.5).
enum ActivityFilter {
  all(null),
  users(true),
  system(false);

  const ActivityFilter(this.hasUserId);

  /// Il parametro `hasUserId` di Jellyfin; `null` per tutte le voci.
  final bool? hasUserId;
}

class ActivityState {
  const ActivityState({
    this.filter = ActivityFilter.all,
    this.items = const [],
    this.total = 0,
    this.loading = false,
    this.error,
  });

  final ActivityFilter filter;

  /// Dalla più recente.
  final List<ActivityEntry> items;

  /// Le voci con questo filtro sul server.
  final int total;
  final bool loading;

  /// Errore dell'ultimo caricamento.
  final Object? error;

  bool get hasMore => items.length < total;

  ActivityState copyWith({
    List<ActivityEntry>? items,
    int? total,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      ActivityState(
        filter: filter,
        items: items ?? this.items,
        total: total ?? this.total,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Il Registro (spec J §9.5): pagine da 50 dalla voce più recente, filtri,
/// e nessuna rilettura automatica (le voci nuove in cima farebbero saltare
/// lo scorrimento): si ricarica all'apertura e con "Aggiorna".
class ActivityController extends Notifier<ActivityState> {
  /// Numera i caricamenti: vale solo l'ultimo.
  int _generation = 0;

  @override
  ActivityState build() {
    unawaited(Future.microtask(reload));
    return const ActivityState(loading: true);
  }

  /// Dalla prima pagina, con il filtro di adesso.
  Future<void> reload() => _load(reset: true);

  /// Cambia filtro e riparte dalla prima pagina.
  Future<void> setFilter(ActivityFilter filter) {
    if (filter == state.filter) return Future.value();
    _generation++;
    state = ActivityState(filter: filter, loading: true);
    return _load(reset: true);
  }

  /// La pagina successiva. Dopo un errore si riprova solo da [retry].
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore || state.error != null) return;
    await _load(reset: false);
  }

  /// "Riprova": la prima pagina se l'elenco è vuoto, altrimenti la pagina
  /// che non è arrivata.
  Future<void> retry() => _load(reset: state.items.isEmpty);

  Future<void> _load({required bool reset}) async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final start = reset ? 0 : state.items.length;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await ref
          .read(adminApiProvider)
          .activity(startIndex: start, hasUserId: state.filter.hasUserId);
      if (!ref.mounted || generation != _generation) return;
      // Voci arrivate in cima tra una pagina e l'altra spostano gli indici:
      // la pagina dopo può ridare voci già mostrate.
      final shown = {
        for (final entry in reset ? const <ActivityEntry>[] : state.items)
          entry.id,
      };
      final fresh = [
        for (final entry in page.items)
          if (shown.add(entry.id)) entry,
      ];
      final items = reset ? fresh : [...state.items, ...fresh];
      state = state.copyWith(
        items: items,
        // Una pagina di soli doppioni: non c'è altro da chiedere.
        total: !reset && fresh.isEmpty ? items.length : page.total,
        loading: false,
      );
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      if (error is ForbiddenException) {
        unawaited(ref.read(sessionControllerProvider.notifier).refreshUser());
      }
      state = state.copyWith(loading: false, error: error);
    }
  }
}

final activityControllerProvider =
    NotifierProvider.autoDispose<ActivityController, ActivityState>(
        ActivityController.new);
```

- [ ] **Step 4: implementa la scheda**

`lib/features/admin/activity_tab.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/activity_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'activity_controller.dart';
import 'admin_time.dart';

/// La scheda Registro (spec J §9.5): filtri, "Aggiorna" e le voci a pagine.
class ActivityTab extends ConsumerStatefulWidget {
  const ActivityTab({super.key});

  @override
  ConsumerState<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<ActivityTab> {
  /// Quanto manca alla fine dell'elenco quando si chiede la pagina dopo.
  static const _loadMoreWithin = 600.0;

  final _scroll = SmoothScrollController();

  /// Numero di voci all'ultimo caricamento automatico: evita un ciclo se il
  /// server risponde con pagine vuote.
  int _autoLoadedAt = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < _loadMoreWithin) {
        unawaited(ref.read(activityControllerProvider.notifier).loadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _filterLabel(AppLocalizations l, ActivityFilter filter) =>
      switch (filter) {
        ActivityFilter.all => l.adminActivityAll,
        ActivityFilter.users => l.adminActivityUsers,
        ActivityFilter.system => l.adminActivitySystem,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(activityControllerProvider);
    final controller = ref.read(activityControllerProvider.notifier);

    // Se la prima pagina non riempie la finestra, lo scorrimento non chiede
    // mai la pagina dopo: la si chiede qui.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final current = ref.read(activityControllerProvider);
      if (_scroll.position.maxScrollExtent == 0 &&
          current.hasMore &&
          !current.loading &&
          current.error == null &&
          current.items.length != _autoLoadedAt) {
        _autoLoadedAt = current.items.length;
        unawaited(controller.loadMore());
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Row(
            children: [
              for (final filter in ActivityFilter.values) ...[
                ChoiceChip(
                  key: ValueKey('activity-filter-${filter.name}'),
                  label: Text(_filterLabel(l, filter)),
                  selected: filter == state.filter,
                  onSelected: (_) => unawaited(controller.setFilter(filter)),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: () => unawaited(controller.reload()),
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: Text(l.adminActivityRefresh),
              ),
            ],
          ),
        ),
        Expanded(child: _list(l, state, controller)),
      ],
    );
  }

  Widget _list(
      AppLocalizations l, ActivityState state, ActivityController controller) {
    final error = state.error;
    if (state.items.isEmpty) {
      if (error != null) {
        return ErrorView(
            error: error, onRetry: () => unawaited(controller.reload()));
      }
      if (state.loading) return const LoadingView();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(l.adminActivityEmpty,
            style: const TextStyle(color: WfColors.creamMuted)),
      );
    }
    final now = clock.now();
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      itemCount: state.items.length + 1,
      itemBuilder: (context, index) {
        if (index < state.items.length) {
          final entry = state.items[index];
          return ActivityRow(
              key: ValueKey('activity-${entry.id}'), entry: entry, now: now);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: state.loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : error != null
                    ? TextButton(
                        onPressed: () => unawaited(controller.retry()),
                        child: Text(l.retry))
                    : state.hasMore
                        ? const SizedBox.shrink()
                        : Text(l.adminActivityEnd,
                            style: const TextStyle(color: WfColors.creamMuted)),
          ),
        );
      },
    );
  }
}

/// Una voce del registro: gravità, testo, dettaglio con un clic, il titolo
/// se c'è e l'ora (data completa al passaggio del mouse).
class ActivityRow extends StatefulWidget {
  const ActivityRow({super.key, required this.entry, required this.now});

  final ActivityEntry entry;
  final DateTime now;

  @override
  State<ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<ActivityRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    final overview = entry.overview;
    final shortOverview = entry.shortOverview;
    final itemId = entry.itemId;
    final date = entry.date;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    final (icon, color) = switch (entry.severity) {
      ActivitySeverity.info => (LucideIcons.info, WfColors.creamMuted),
      ActivitySeverity.warning => (LucideIcons.triangleAlert, WfColors.gold),
      ActivitySeverity.error => (LucideIcons.circleX, WfColors.error),
    };
    return InkWell(
      onTap: overview == null ? null : () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                key: Key('activity-severity-${entry.id}-${entry.severity.name}'),
                size: 18,
                color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name),
                  if (shortOverview != null) Text(shortOverview, style: muted),
                  if (_expanded && overview != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(overview, style: const TextStyle(fontSize: 13)),
                    ),
                  if (itemId != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () => openItemById(context, itemId),
                      child: Text(l.adminActivityOpenItem),
                    ),
                ],
              ),
            ),
            if (date != null) ...[
              const SizedBox(width: 12),
              Tooltip(
                message: adminFullDateTime(date, l),
                child: Text(adminTimeLabel(date, widget.now, l), style: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/features/admin/activity_controller_test.dart test/features/admin/activity_tab_test.dart`
Expected: PASS.

- [ ] **Step 6: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/features/admin/activity_controller.dart lib/features/admin/activity_tab.dart test/features/admin/activity_controller_test.dart test/features/admin/activity_tab_test.dart
git commit -m "feat(app): add the activity log tab to the admin page"
```

### Task 8: scheda WonderFlix

**Files:**
- Create: `lib/features/admin/wonderflix_labels.dart`, `lib/features/admin/wonderflix_controllers.dart`, `lib/features/admin/wonderflix_tab.dart`
- Test: `test/features/admin/wonderflix_labels_test.dart`, `test/features/admin/wonderflix_controllers_test.dart`, `test/features/admin/wonderflix_tab_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/admin/wonderflix_labels_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/wonderflix_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));

  test('tipo dell\'ultimo evento di Seerr', () {
    expect(seerrEventLabel(it, 'MEDIA_PENDING'), 'Richiesta in attesa');
    expect(seerrEventLabel(it, 'MEDIA_AVAILABLE'), 'Richiesta disponibile');
    expect(seerrEventLabel(it, 'TEST_NOTIFICATION'), 'Messaggio di prova');
    expect(seerrEventLabel(it, 'MEDIA_FAILED'), 'MEDIA_FAILED');
  });

  test('esito della prova di Seerr', () {
    expect(seerrTestLabel(it, const SeerrTestResult(ok: true, version: '3.4.1')),
        'Collegato a Seerr 3.4.1');
    expect(seerrTestLabel(it, const SeerrTestResult(ok: true)),
        'Collegato a Seerr');
    expect(
        seerrTestLabel(
            it, const SeerrTestResult(ok: false, error: 'NotConfigured')),
        'Seerr non è configurato');
    expect(seerrTestLabel(it, const SeerrTestResult(ok: false, error: 'SeerrAuth')),
        'Seerr ha rifiutato la chiave');
    expect(
        seerrTestLabel(
            it, const SeerrTestResult(ok: false, error: 'SeerrUnavailable')),
        'Seerr non risponde');
    expect(seerrTestLabel(it, const SeerrTestResult(ok: false)),
        'Seerr non risponde');
  });

  test('novità', () {
    expect(
        newTitlesStatusLabel(
            it, const NewTitlesStatus(enabled: true, pending: 3)),
        '3 titoli in attesa del prossimo riepilogo');
    expect(
        newTitlesStatusLabel(
            it, const NewTitlesStatus(enabled: true, pending: 0)),
        'Nessun titolo in attesa');
    expect(
        newTitlesStatusLabel(
            it, const NewTitlesStatus(enabled: false, pending: 3)),
        'Le novità non vengono raccolte');
    expect(
        newTitlesSentLabel(
            it, const NewTitlesSent(titles: 3, recipients: 12)),
        'Inviati 3 titoli a 12 persone');
    expect(
        newTitlesSentLabel(it, const NewTitlesSent(titles: 1, recipients: 1)),
        'Inviato 1 titolo a 1 persona');
  });
}
```

`test/features/admin/wonderflix_controllers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/wonderflix_controllers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

void main() {
  late FakePluginAdminApi plugin;
  late FakeSessionController session;

  setUp(() {
    plugin = FakePluginAdminApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(FakeAdminApi(),
          plugin: plugin, session: session),
      retry: (_, _) => null,
    );
    container.listen(inboxAdminControllerProvider, (_, _) {});
    container.listen(seerrAdminControllerProvider, (_, _) {});
    return container;
  }

  test('legge novità e Seerr; un plugin vecchio non ha la card Seerr',
      () async {
    final container = makeContainer();
    await pumpEventQueue();

    expect(container.read(inboxAdminControllerProvider).value!.pending, 3);
    expect(container.read(seerrAdminControllerProvider).value!.status!.configured,
        isTrue);

    plugin.seerrValue = null;
    await container.read(seerrAdminControllerProvider.notifier).refresh();
    final data = container.read(seerrAdminControllerProvider);
    expect(data.value, isNotNull);
    expect(data.value!.status, isNull);
  });

  test('azioni: chiamano il plugin e rileggono', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final inbox = container.read(inboxAdminControllerProvider.notifier);

    expect(await inbox.announce('Ciao'), 12);
    await inbox.setNotifyNewTitles(false);
    await pumpEventQueue();
    expect(container.read(inboxAdminControllerProvider).value!.enabled, isFalse);
    final sent = await inbox.sendNewTitles();
    expect(sent.titles, 3);
    final result =
        await container.read(seerrAdminControllerProvider.notifier).test();
    expect(result.version, '3.4.1');

    expect(plugin.calls,
        containsAllInOrder(['announce:Ciao', 'notify:false', 'send', 'test']));
    expect(plugin.count('newTitles'), greaterThanOrEqualTo(3));
  });

  test('403 su un\'azione: rilegge l\'utente', () async {
    plugin.actionError = const ForbiddenException();
    final container = makeContainer();
    await pumpEventQueue();

    await expectLater(
        container.read(inboxAdminControllerProvider.notifier).sendNewTitles(),
        throwsA(isA<ForbiddenException>()));
    expect(session.refreshUserCalls, 1);
  });

  test('le due card hanno errori separati', () async {
    plugin.newTitlesError = const ServerUnreachableException();
    final container = makeContainer();
    await pumpEventQueue();

    expect(container.read(inboxAdminControllerProvider).error,
        isA<ServerUnreachableException>());
    expect(container.read(seerrAdminControllerProvider).error, isNull);
  });
}
```

`test/features/admin/wonderflix_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/wonderflix_tab.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakePluginAdminApi plugin;

  setUp(() => plugin = FakePluginAdminApi());

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: WonderflixTab()),
        overrides: adminTestOverrides(FakeAdminApi(), plugin: plugin),
        surfaceSize: const Size(1440, 1400));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) => tester
      .widget<OutlinedButton>(find.ancestor(
          of: find.text(label), matching: find.bySubtype<OutlinedButton>()))
      .onPressed != null;

  group('annuncio', () {
    testWidgets('si scrive, si conferma, arriva', (tester) async {
      await pumpTab(tester);

      expect(find.text('Annuncio'), findsOneWidget);
      expect(find.text('0/500'), findsOneWidget);
      expect(enabled(tester, 'Invia a tutti'), isFalse);

      await tester.enterText(
          find.byKey(const Key('announcement-text')), '  Ciao a tutti  ');
      await tester.pump();
      expect(enabled(tester, 'Invia a tutti'), isTrue);

      await tester.tap(find.text('Invia a tutti'));
      await tester.pumpAndSettle();
      expect(find.text(it.adminAnnouncementConfirm), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Invia'));
      await tester.pumpAndSettle();

      expect(plugin.calls, contains('announce:Ciao a tutti'));
      expect(find.text('Annuncio inviato a 12 persone'), findsOneWidget);
      expect(find.text('Ciao a tutti'), findsNothing, reason: 'campo vuoto');
    });

    testWidgets('Annulla: niente annuncio', (tester) async {
      await pumpTab(tester);
      await tester.enterText(find.byKey(const Key('announcement-text')), 'Ciao');
      await tester.pump();

      await tester.tap(find.text('Invia a tutti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(plugin.calls.where((c) => c.startsWith('announce')), isEmpty);
    });

    testWidgets('testo rifiutato (400): "Testo non valido"', (tester) async {
      plugin.actionError = const ServerErrorException(400);
      await pumpTab(tester);
      await tester.enterText(find.byKey(const Key('announcement-text')), 'Ciao');
      await tester.pump();

      await tester.tap(find.text('Invia a tutti'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Invia'));
      await tester.pumpAndSettle();

      expect(find.text('Testo non valido'), findsOneWidget);
    });
  });

  group('novità', () {
    testWidgets('stato, interruttore e Invia ora', (tester) async {
      await pumpTab(tester);

      expect(find.text('3 titoli in attesa del prossimo riepilogo'),
          findsOneWidget);
      expect(enabled(tester, 'Invia ora'), isTrue);

      await tester.tap(find.text('Invia ora'));
      await tester.pumpAndSettle();
      expect(find.text('Inviati 3 titoli a 12 persone'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notify-new-titles')));
      await tester.pumpAndSettle();
      expect(plugin.calls, contains('notify:false'));
      expect(find.text('Le novità non vengono raccolte'), findsOneWidget);
      expect(enabled(tester, 'Invia ora'), isFalse);
    });

    testWidgets('scrittura fallita: l\'interruttore torna com\'era',
        (tester) async {
      plugin.actionError = const ServerUnreachableException();
      await pumpTab(tester);

      await tester.tap(find.byKey(const Key('notify-new-titles')));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byKey(const Key('notify-new-titles'))).value,
          isTrue);
      expect(find.text(it.errorServerUnreachable), findsOneWidget);
    });

    testWidgets('nessun titolo: Invia ora spento', (tester) async {
      plugin.newTitlesValue = const NewTitlesStatus(enabled: true, pending: 0);
      await pumpTab(tester);

      expect(find.text('Nessun titolo in attesa'), findsOneWidget);
      expect(enabled(tester, 'Invia ora'), isFalse);
    });

    testWidgets('errore delle novità: le altre card funzionano', (tester) async {
      plugin.newTitlesError = const ServerUnreachableException();
      await pumpTab(tester);

      expect(find.text('Riprova'), findsOneWidget);
      expect(find.text('Prova collegamento'), findsOneWidget);
    });
  });

  group('Seerr', () {
    testWidgets('configurato: ultimo evento e prova', (tester) async {
      await pumpTab(tester);

      expect(find.textContaining('Richiesta in attesa'), findsOneWidget);
      await tester.tap(find.text('Prova collegamento'));
      await tester.pumpAndSettle();
      expect(find.text('Collegato a Seerr 3.4.1'), findsOneWidget);

      plugin.testValue = const SeerrTestResult(ok: false, error: 'SeerrAuth');
      await tester.tap(find.text('Prova collegamento'));
      await tester.pumpAndSettle();
      expect(find.text('Seerr ha rifiutato la chiave'), findsOneWidget);
    });

    testWidgets('nessun evento', (tester) async {
      plugin.seerrValue = const SeerrAdminStatus(configured: true);
      await pumpTab(tester);

      expect(find.text('Nessun evento ricevuto'), findsOneWidget);
    });

    testWidgets('non configurato', (tester) async {
      plugin.seerrValue = const SeerrAdminStatus(configured: false);
      await pumpTab(tester);

      expect(find.text(it.adminSeerrNotConfigured), findsOneWidget);
      expect(find.text('Prova collegamento'), findsNothing);
    });

    testWidgets('plugin più vecchio della 1.4.0: niente card', (tester) async {
      plugin.seerrValue = null;
      await pumpTab(tester);

      expect(find.text('Seerr'), findsNothing);
      expect(find.text('Annuncio'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/admin/wonderflix_labels_test.dart test/features/admin/wonderflix_controllers_test.dart test/features/admin/wonderflix_tab_test.dart`
Expected: FAIL in compilazione (i file non esistono).

- [ ] **Step 3: implementa le etichette**

`lib/features/admin/wonderflix_labels.dart`:

```dart
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Il tipo dell'ultimo evento del webhook di Seerr (spec J §9.6); uno
/// sconosciuto resta com'è.
String seerrEventLabel(AppLocalizations l, String type) => switch (type) {
      'MEDIA_PENDING' => l.adminSeerrEventPending,
      'MEDIA_AVAILABLE' => l.adminSeerrEventAvailable,
      'TEST_NOTIFICATION' => l.adminSeerrEventTest,
      _ => type,
    };

/// L'esito di "Prova collegamento".
String seerrTestLabel(AppLocalizations l, SeerrTestResult result) {
  if (result.ok) {
    final version = result.version;
    return version == null
        ? l.adminSeerrConnectedPlain
        : l.adminSeerrConnected(version);
  }
  return switch (result.error) {
    'NotConfigured' => l.adminSeerrNotConfiguredError,
    'SeerrAuth' => l.adminSeerrAuthError,
    _ => l.adminSeerrUnavailable,
  };
}

/// "3 titoli in attesa del prossimo riepilogo", "Nessun titolo in attesa",
/// oppure, con la raccolta spenta, "Le novità non vengono raccolte".
String newTitlesStatusLabel(AppLocalizations l, NewTitlesStatus status) =>
    !status.enabled
        ? l.adminNewTitlesOff
        : status.pending == 0
            ? l.adminNewTitlesNone
            : l.adminNewTitlesPending(status.pending);

/// "Inviati 3 titoli a 12 persone" (decisione 8 del piano 16b).
String newTitlesSentLabel(AppLocalizations l, NewTitlesSent sent) =>
    '${l.adminNewTitlesSentTitles(sent.titles)} '
    '${l.adminNewTitlesSentTo(sent.recipients)}';
```

- [ ] **Step 4: implementa i controller**

`lib/features/admin/wonderflix_controllers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/plugin_admin_models.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';

/// Le funzioni della cassetta del plugin (spec J §9.6): lo stato delle
/// novità, riletto ogni 30 s, e le azioni annuncio, interruttore e "Invia
/// ora".
class InboxAdminController extends AdminTabController<NewTitlesStatus> {
  static const every = Duration(seconds: 30);

  @override
  Duration get interval => every;

  @override
  Future<NewTitlesStatus> fetch() =>
      ref.read(pluginAdminApiProvider).newTitles();

  /// A quante persone è arrivato. Un testo rifiutato dà un
  /// `ServerErrorException` con 400.
  Future<int> announce(String text) =>
      act(() => ref.read(pluginAdminApiProvider).announce(text));

  Future<void> setNotifyNewTitles(bool enabled) =>
      act(() => ref.read(pluginAdminApiProvider).setNotifyNewTitles(enabled));

  Future<NewTitlesSent> sendNewTitles() =>
      act(() => ref.read(pluginAdminApiProvider).sendNewTitles());
}

final inboxAdminControllerProvider = NotifierProvider.autoDispose<
    InboxAdminController, AdminData<NewTitlesStatus>>(InboxAdminController.new);

/// La card Seerr: [status] `null` con un plugin più vecchio della 1.4.0, e
/// allora la card non c'è.
class SeerrCardData {
  const SeerrCardData(this.status);

  final SeerrAdminStatus? status;
}

/// Lo stato di Seerr nel plugin, riletto ogni 30 s, e "Prova collegamento".
class SeerrAdminController extends AdminTabController<SeerrCardData> {
  static const every = Duration(seconds: 30);

  @override
  Duration get interval => every;

  @override
  Future<SeerrCardData> fetch() async =>
      SeerrCardData(await ref.read(pluginAdminApiProvider).seerrStatus());

  Future<SeerrTestResult> test() =>
      act(() => ref.read(pluginAdminApiProvider).testSeerr());
}

final seerrAdminControllerProvider = NotifierProvider.autoDispose<
    SeerrAdminController, AdminData<SeerrCardData>>(SeerrAdminController.new);
```

- [ ] **Step 5: implementa la scheda**

`lib/features/admin/wonderflix_tab.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/social/plugin_admin_api.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'admin_action_button.dart';
import 'admin_confirm_dialog.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';
import 'wonderflix_controllers.dart';
import 'wonderflix_labels.dart';

/// La scheda WonderFlix (spec J §9.6): annuncio, novità, Seerr. Ogni card
/// ha il suo stato: se una non carica, le altre funzionano.
class WonderflixTab extends StatefulWidget {
  const WonderflixTab({super.key});

  @override
  State<WonderflixTab> createState() => _WonderflixTabState();
}

class _WonderflixTabState extends State<WonderflixTab> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
        children: const [AnnouncementCard(), NewTitlesCard(), SeerrCard()],
      );
}

/// L'annuncio a tutti: testo con il contatore, conferma, esito.
class AnnouncementCard extends ConsumerStatefulWidget {
  const AnnouncementCard({super.key});

  @override
  ConsumerState<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends ConsumerState<AnnouncementCard> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAdminConfirmDialog(
      context,
      title: l.adminAnnouncement,
      message: l.adminAnnouncementConfirm,
      confirmLabel: l.adminSend,
    );
    if (!confirmed || !mounted) return;
    try {
      // Come il plugin: il testo si accorcia ai lati.
      final recipients = await ref
          .read(inboxAdminControllerProvider.notifier)
          .announce(_text.text.trim());
      messenger.showSnackBar(
          SnackBar(content: Text(l.adminAnnouncementSent(recipients))));
      _text.clear();
    } on ServerErrorException catch (error) {
      if (error.statusCode != 400) rethrow;
      messenger
          .showSnackBar(SnackBar(content: Text(l.adminAnnouncementInvalid)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AdminCard(
      title: l.adminAnnouncement,
      icon: LucideIcons.megaphone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('announcement-text'),
            controller: _text,
            minLines: 2,
            maxLines: 4,
            maxLength: PluginAdminApi.announcementMaxLength,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _text,
            builder: (context, value, _) => AdminActionButton(
              label: l.adminAnnouncementSend,
              icon: LucideIcons.send,
              onPressed: value.text.trim().isEmpty ? null : _send,
            ),
          ),
        ],
      ),
    );
  }
}

/// Le novità: interruttore, titoli in attesa, "Invia ora".
class NewTitlesCard extends ConsumerStatefulWidget {
  const NewTitlesCard({super.key});

  @override
  ConsumerState<NewTitlesCard> createState() => _NewTitlesCardState();
}

class _NewTitlesCardState extends ConsumerState<NewTitlesCard> {
  /// Il valore che si sta scrivendo: intanto l'interruttore è fermo lì.
  bool? _writing;

  Future<void> _toggle(bool value) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(inboxAdminControllerProvider.notifier);
    setState(() => _writing = value);
    try {
      await controller.setNotifyNewTitles(value);
      // L'azione fa già rileggere: si aspetta quella lettura, così
      // l'interruttore non torna indietro per un attimo.
      await controller.refresh();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
    } finally {
      if (mounted) setState(() => _writing = null);
    }
  }

  Future<void> _sendNow() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sent =
        await ref.read(inboxAdminControllerProvider.notifier).sendNewTitles();
    messenger.showSnackBar(SnackBar(content: Text(newTitlesSentLabel(l, sent))));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(inboxAdminControllerProvider);
    final status = data.value;
    final error = data.error;
    final updatedAt = data.updatedAt;
    final Widget child;
    if (status == null) {
      child = error != null
          ? AdminCardError(
              error: error,
              onRetry: () => unawaited(
                  ref.read(inboxAdminControllerProvider.notifier).refresh()))
          : const SkeletonBox(width: 240, height: 20);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l.adminNewTitlesNotify)),
              Switch(
                key: const Key('notify-new-titles'),
                value: _writing ?? status.enabled,
                onChanged:
                    _writing != null ? null : (value) => unawaited(_toggle(value)),
              ),
            ],
          ),
          Text(newTitlesStatusLabel(l, status),
              style: const TextStyle(color: WfColors.creamMuted)),
          if (data.stale && updatedAt != null)
            AdminStaleNote(updatedAt: updatedAt),
          const SizedBox(height: 12),
          AdminActionButton(
            label: l.adminNewTitlesSendNow,
            icon: LucideIcons.send,
            onPressed: status.enabled && status.pending > 0 ? _sendNow : null,
          ),
        ],
      );
    }
    return AdminCard(
        title: l.adminNewTitles, icon: LucideIcons.sparkles, child: child);
  }
}

/// Seerr nel plugin: ultimo evento del webhook e "Prova collegamento". Con
/// un plugin più vecchio della 1.4.0 non c'è.
class SeerrCard extends ConsumerStatefulWidget {
  const SeerrCard({super.key});

  @override
  ConsumerState<SeerrCard> createState() => _SeerrCardState();
}

class _SeerrCardState extends ConsumerState<SeerrCard> {
  /// L'esito dell'ultima prova, sotto il pulsante.
  SeerrTestResult? _result;

  Future<void> _test() async {
    final result = await ref.read(seerrAdminControllerProvider.notifier).test();
    if (mounted) setState(() => _result = result);
  }

  String _lastEvent(AppLocalizations l, SeerrAdminStatus status) {
    final at = status.lastEventAt;
    if (at == null) return l.adminSeerrNoEvents;
    final type = status.lastEventType;
    return l.adminSeerrLastEvent(adminTimeLabel(at, clock.now(), l),
        type == null ? '—' : seerrEventLabel(l, type));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(seerrAdminControllerProvider);
    final value = data.value;
    final error = data.error;
    const muted = TextStyle(color: WfColors.creamMuted);
    if (value != null && value.status == null) return const SizedBox.shrink();
    final status = value?.status;
    final result = _result;
    final Widget child;
    if (status == null) {
      child = error != null
          ? AdminCardError(
              error: error,
              onRetry: () => unawaited(
                  ref.read(seerrAdminControllerProvider.notifier).refresh()))
          : const SkeletonBox(width: 240, height: 20);
    } else if (!status.configured) {
      child = Text(l.adminSeerrNotConfigured, style: muted);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_lastEvent(l, status), style: muted),
          const SizedBox(height: 12),
          Row(
            children: [
              AdminActionButton(
                label: l.adminSeerrTest,
                icon: LucideIcons.link,
                onPressed: _test,
              ),
              if (result != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(seerrTestLabel(l, result),
                      style: TextStyle(
                          color: result.ok ? WfColors.cream : WfColors.error)),
                ),
              ],
            ],
          ),
        ],
      );
    }
    return AdminCard(title: l.adminSeerr, icon: LucideIcons.listChecks, child: child);
  }
}
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/features/admin/wonderflix_labels_test.dart test/features/admin/wonderflix_controllers_test.dart test/features/admin/wonderflix_tab_test.dart`
Expected: PASS.

- [ ] **Step 7: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/features/admin/wonderflix_labels.dart lib/features/admin/wonderflix_controllers.dart lib/features/admin/wonderflix_tab.dart test/features/admin/wonderflix_labels_test.dart test/features/admin/wonderflix_controllers_test.dart test/features/admin/wonderflix_tab_test.dart
git commit -m "feat(app): add the WonderFlix tab to the admin page"
```

### Task 9: la pagina con quattro schede

**Files:**
- Modify: `lib/features/admin/admin_navigation.dart`, `lib/features/admin/admin_screen.dart`
- Test: `test/features/admin/admin_navigation_test.dart`, `test/features/admin/admin_screen_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/admin/admin_navigation_test.dart` diventa:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';

void main() {
  test('scheda dall\'indirizzo: senza o sconosciuta, Sessioni', () {
    expect(AdminTab.parse('sessions'), AdminTab.sessions);
    expect(AdminTab.parse('maintenance'), AdminTab.maintenance);
    expect(AdminTab.parse('activity'), AdminTab.activity);
    expect(AdminTab.parse('wonderflix'), AdminTab.wonderflix);
    expect(AdminTab.parse(null), AdminTab.sessions);
    expect(AdminTab.parse('boh'), AdminTab.sessions);
  });

  test('WonderFlix solo con la cassetta del plugin', () {
    expect(adminTabs(inbox: true), AdminTab.values);
    expect(adminTabs(inbox: false),
        [AdminTab.sessions, AdminTab.maintenance, AdminTab.activity]);
  });
}
```

In `test/features/admin/admin_screen_test.dart`:
- aggiungi gli import `package:wonderflix/features/social/social_providers.dart`;
- `pumpScreen` riceve anche `SocialFeatures features = const SocialFeatures(inbox: true)` e lo passa: `...adminTestOverrides(api, session: session, features: features)`;
- nel test "admin: titolo, striscia, scheda Sessioni", `expect(find.text('WonderFlix'), findsOneWidget)` diventa `expect(find.text('WonderFlix'), findsNWidgets(2))`, con il commento `// Il nome del server nella striscia e la scheda.`;
- in fondo a `main()`:

```dart
  testWidgets('quattro schede; un clic cambia scheda nell\'indirizzo',
      (tester) async {
    final router = await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)));

    for (final tab in ['sessions', 'maintenance', 'activity', 'wonderflix']) {
      expect(find.byKey(ValueKey('admin-tab-$tab')), findsOneWidget);
    }

    await tester.tap(find.text('Manutenzione'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin?tab=maintenance');
    expect(find.text('Librerie'), findsOneWidget);

    await tester.tap(find.text('Registro'));
    await tester.pumpAndSettle();
    expect(find.text('Aggiorna'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin-tab-wonderflix')));
    await tester.pumpAndSettle();
    expect(find.text('Annuncio'), findsOneWidget);
  });

  testWidgets('senza la cassetta del plugin: niente WonderFlix, si mostra '
      'Sessioni', (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        location: '/admin?tab=wonderflix',
        features: SocialFeatures.none);

    expect(find.byKey(const ValueKey('admin-tab-wonderflix')), findsNothing);
    expect(find.text('viviroby'), findsOneWidget);
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/admin/admin_navigation_test.dart test/features/admin/admin_screen_test.dart`
Expected: FAIL in compilazione (`AdminTab.maintenance`, `adminTabs` non esistono).

- [ ] **Step 3: implementa**

`lib/features/admin/admin_navigation.dart`:
- `AdminTab` diventa:

```dart
/// Le schede della pagina Amministrazione (spec J §9).
enum AdminTab {
  sessions,
  maintenance,
  activity,
  wonderflix;

  /// Dal parametro `tab` dell'indirizzo: senza, o con un valore
  /// sconosciuto, Sessioni.
  static AdminTab parse(String? raw) =>
      values.firstWhere((tab) => tab.name == raw, orElse: () => sessions);
}

/// Le schede da mostrare: WonderFlix solo con la cassetta del plugin
/// (`inbox`, spec J §7).
List<AdminTab> adminTabs({required bool inbox}) => [
      for (final tab in AdminTab.values)
        if (tab != AdminTab.wonderflix || inbox) tab,
    ];
```

- `adminTabLabel` diventa:

```dart
String adminTabLabel(AppLocalizations l, AdminTab tab) => switch (tab) {
      AdminTab.sessions => l.adminTabSessions,
      AdminTab.maintenance => l.adminTabMaintenance,
      AdminTab.activity => l.adminTabActivity,
      AdminTab.wonderflix => l.adminTabWonderflix,
    };
```

`lib/features/admin/admin_screen.dart`:
- import `'../social/social_providers.dart'`, `'activity_tab.dart'`, `'maintenance_tab.dart'`, `'wonderflix_tab.dart'`;
- in `build`, al posto di `final tab = widget.tab;`:

```dart
    // Senza la cassetta del plugin la scheda WonderFlix non c'è; se è
    // nell'indirizzo (o la funzione sparisce mentre la si guarda), si mostra
    // Sessioni.
    final tabs = adminTabs(
        inbox: ref.watch(socialAvailabilityProvider.select((f) => f.inbox)));
    final tab = tabs.contains(widget.tab) ? widget.tab : AdminTab.sessions;
```

- nel ciclo dei pulsanti, `for (final item in AdminTab.values)` diventa `for (final item in tabs)`;
- lo `switch` del contenuto diventa:

```dart
          child: switch (tab) {
            AdminTab.sessions => const SessionsTab(),
            AdminTab.maintenance => const MaintenanceTab(),
            AdminTab.activity => const ActivityTab(),
            AdminTab.wonderflix => const WonderflixTab(),
          },
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/admin test/app`
Expected: PASS.

- [ ] **Step 5: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/features/admin/admin_navigation.dart lib/features/admin/admin_screen.dart test/features/admin/admin_navigation_test.dart test/features/admin/admin_screen_test.dart
git commit -m "feat(app): show the maintenance, activity and WonderFlix tabs"
```

---

## Gruppo C — allineamento e verifica finale

### Task 10: spec allineata, verifica, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md`

- [ ] **Step 1: allinea la spec**

In `docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md` (in italiano, con lo stile del resto; tieni le fini riga del file):
- **Stato:** aggiungi `, piano 16b realizzato (docs/superpowers/plans/2026-10-06-wonderflix-16b-manutenzione-registro-wonderflix-release.md)`.
- **§6:**
  - aggiungi `json_fields.dart`, `maintenance_models.dart`, `activity_models.dart`, `plugin_admin_models.dart` (decisione 4);
  - aggiungi `admin_action_button.dart`, `admin_confirm_dialog.dart`, `task_labels.dart`, `maintenance_controller.dart`, `activity_controller.dart`, `wonderflix_controllers.dart`, `wonderflix_labels.dart`;
  - togli i nomi che non esistono (`wonderflix_controller.dart` al singolare);
  - nota che le API admin del plugin passano da `pluginAdminApiProvider`.
- **§8.1, `scanLibrary`:** i parametri sono quelli della decisione 1, con `Recursive=true` e `RegenerateTrickplay=false`; non "da verificare".
- **§8.2:**
  - `LibraryFolder.kind` (`LibraryKind`: film, serie, altro);
  - `ScheduledTask` ha uno stato sconosciuto che vale come fermo;
  - `ActivityEntry` non ha `userImageTag` (decisione 3); `ActivityPage`.
- **§9.4:**
  - attività per categoria e poi per nome (decisione 2), non "nell'ordine del server";
  - i pulsanti sono disattivati mentre l'azione è in corso, e un errore diventa un avviso (decisione 5);
  - la durata si scrive come nella decisione 9.
- **§9.5:**
  - niente avatar (decisione 3);
  - data completa come nella decisione 10;
  - le voci arrivate in cima tra una pagina e l'altra non si ripetono.
- **§9.6:**
  - "Messaggio di prova" per `TEST_NOTIFICATION` (decisione 7);
  - i due controller (decisione 6);
  - con un ultimo evento senza tipo si scrive "—".
- **§11:** i testi nuovi del 16b (le due parti di "Inviati … a …", le durate, "Messaggio di prova", "Invia"); il test dei testi del 16b è `test/app/l10n_plan16b_test.dart`.
- **§14:** togli i punti verificati: i parametri della scansione e il nome di `NotifyNewTitles` (PascalCase, verificato sulla risposta vera).
- **§15:** il 16b è fatto.

```bash
git add docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md
git commit -m "docs: align spec J with plan 16b"
```

- [ ] **Step 2: verifica finale**

Run: `flutter analyze` e `flutter test`.
Expected: tutto verde, nessun problema. Annota i numeri. Il plugin non è cambiato.

- [ ] **Step 3: build per la prova manuale**

Copia `config/wonderflix.json` dalla root del repository principale nella stessa cartella del worktree (non si committa), poi:

Run: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
Expected: `build/windows/x64/runner/Release/wonderflix.exe`.

## Prova manuale (con l'utente, dopo la review finale)

1. **Schede:** Sessioni, Manutenzione, Registro, WonderFlix.
2. **Manutenzione:**
   - le quattro librerie con l'icona; "Scansiona" su una libreria piccola (Collezioni2) mostra la barra mentre va, poi torna normale;
   - accanto a "Scansiona tutte" c'è "Ultima: …";
   - le attività sono raggruppate per categoria;
   - **Avvia** su un'attività leggera (per esempio "Pulisci la cartella dei log") mostra la barra e "Ferma", poi "Ultima: adesso · Completata in …";
   - **Ferma** su un'attività lunga, se l'utente vuole provarlo, porta ad "Arresto…" e poi ad "Annullata".
3. **Registro:**
   - le voci più recenti, con l'icona della gravità;
   - i filtri Utenti e Sistema;
   - "Aggiorna";
   - scorrendo arrivano le voci più vecchie;
   - "Apri il titolo" su una riproduzione apre la scheda.
4. **WonderFlix:**
   - **Novità:** spegni l'interruttore, poi controlla nella pagina web del plugin (Dashboard → Plugin → WonderFlix Watch Party) che "Notify new titles" sia spento; riaccendilo dall'app;
   - **Seerr:** "Ultimo evento dal webhook: …" e "Prova collegamento" → "Collegato a Seerr 3.4.1";
   - **Annuncio e "Invia ora":** arrivano davvero a tutti, quindi solo se l'utente vuole.

Dopo l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria del flusso).

## Release (dopo il merge, con l'utente)

Segue `docs/RELEASING.md`. Solo l'app: il plugin non cambia.

1. **App 0.10.0, non obbligatoria.**
   - Commit `chore: release 0.10.0`: in `pubspec.yaml` `version: 0.10.0`.
   - Con l'ok dell'utente: tag `v0.10.0`, push, pipeline Release.
   - A pipeline finita scrivo le note in italiano nella bozza (`gh release edit v0.10.0 --notes-file …`), **senza** il marcatore `min-version`. Le note parlano di:
     - la pagina Amministrazione per gli admin (menu dell'avatar);
     - la striscia del server con il riavvio;
     - Sessioni (chi guarda cosa, diretta, remux o transcodifica e perché, i watch party);
     - Manutenzione (scansioni e attività);
     - Registro;
     - WonderFlix (annuncio, novità, Seerr).
   - **Pubblica l'utente.**
2. **Dopo la release:** aggiorna `docs/IDEE.md`:
   - togli l'idea 1 e rinumera le altre dalla 1 alla 4;
   - aggiungi "Spec J — dashboard admin (app 0.10.0)" alle fatte.
