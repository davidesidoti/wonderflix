# WonderFlix — Piano 16a: pagina Amministrazione, server e sessioni

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** prima metà della Spec J. Ci sono:
- l'app **sa chi è admin** (`Policy.IsAdministrator`) e rilegge l'utente dopo un 403;
- la voce **"Amministrazione"** nel menu dell'avatar, solo per gli admin, e la pagina `/admin`;
- la **striscia del server** (nome, versione, "Riavvio necessario") con **Riavvia**, la conferma che dice chi sta guardando e l'attesa del ritorno di Jellyfin;
- la scheda **Sessioni**: chi guarda cosa e come (Diretta, Remux, Transcodifica con i motivi), chi è collegato, i watch party in corso;
- la **rilettura periodica** comune, ferma quando la finestra è ridotta a icona.

Il plugin non cambia. Manutenzione, Registro, WonderFlix e la release sono nel piano 16b.

**Spec:** `docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md` (§7, §8.1, §8.2, §9.1–9.3, §10, §11, §12, §15).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 9):
1. **Due piani** (spec §15): il 16a fa accesso, striscia, riavvio e Sessioni. Il 16b fa Manutenzione, Registro, WonderFlix e la release. Nel 16a la pagina ha una sola scheda, "Sessioni".
2. **Avatar con l'iniziale**, come il menu dell'avatar: l'app non ha un indirizzo per le immagini degli utenti, e non serve.
3. **La scheda sta nell'indirizzo** (`/admin?tab=…`), cambiata con `context.go` come la pagina Richieste. La rotta **non** mette una chiave alla pagina: cambiando scheda la pagina resta la stessa, e con lei la striscia e un riavvio in corso.
4. **Ritmo della rilettura:** l'intervallo parte dalla **fine** della lettura precedente, quindi due letture non si sovrappongono mai. Una lettura chiesta durante un'altra (dopo un'azione, dopo il riavvio) ne fa partire una sola, appena quella finisce.
5. **Finestra in vista:** `adminForegroundProvider` ascolta un `AppLifecycleListener` (`onHide`/`onShow`). Le riletture si fermano quando la finestra è nascosta (ridotta a icona) e ripartono, con una lettura subito, quando torna.
6. **Dopo il riavvio** tutte le schede e la striscia rileggono subito, tramite `adminEpochProvider` (un contatore che il riavvio fa crescere).
7. **Metodo mostrato:**
   - `DirectPlay` → "Diretta";
   - con `TranscodingInfo`: video e audio diretti → "Remux", altrimenti "Transcodifica";
   - senza `TranscodingInfo`: `DirectStream` → "Remux", `Transcode` → "Transcodifica", altro → nessuna etichetta.
8. **File delle etichette:** `session_labels.dart` (la spec dice `transcode_labels.dart`): ci sono anche titolo, dispositivo e stato dei party.
9. **Nessun titolo nella barra:** la pagina ha il titolo grande come Richieste, senza `ShellPageFrame`.
10. **Watch party:** se l'utente non ha accesso ai watch party (`SyncPlayAccess.none`) l'elenco non si chiede e resta vuoto.
11. **Sessioni senza utente:** si scartano anche quelle con `UserId` di soli zeri.
12. **Sistema operativo:** sul server `OperatingSystemDisplayName` è vuoto, quindi la striscia mostra solo "Jellyfin 10.11.9".
13. **Caricamento:** le schede mostrano `LoadingView` (come la pagina Richieste) e la striscia uno `SkeletonBox`, non gli scheletri della spec §9.1.
14. **Dalla review del Gruppo A** (già fatto nel Gruppo A, commit `8d4d546`, `28d337b`, `6dd9ba9`):
    - le riletture si fermano anche quando la pagina è coperta da un'altra rotta (Riverpod mette in pausa gli ascoltatori: `onCancel`/`onResume` in `AdminTabController`), e `AdminForeground` parte dallo stato vero della finestra;
    - `JellyfinUser` ha `==`; `refreshUser` applica il risultato solo per lo stesso utente e solo se è cambiato, e le chiamate contemporanee ne fanno una sola;
    - `AdminPoller` usa `Future.sync`, e un intervallo nuovo non rimanda la prima lettura;
    - `isServerUp` dà "giù" per ogni `ApiException`; 502/503/504 delle letture vanno nel log come info.
15. **Gli endpoint letti non danno 403 a chi non è più admin** (`/Sessions`, `/System/Info`, `/SyncPlay/List` non chiedono di essere admin; solo `/System/Restart` sì). Quindi `ServerInfoController` rilegge l'utente a ogni lettura: all'apertura della pagina e ogni 60 s (Task 7). Il 403 resta un segnale in più.
16. **Riavvio:** un 502/503/504 di nginx sul `POST /System/Restart` conta come riavvio partito, come un errore di rete (Task 7).

**Architecture:**
- **Dati:**
  - `JellyfinUser.isAdministrator`, `AuthService.currentUser()`, `SessionController.refreshUser()`;
  - `AdminApi` (Jellyfin) con i modelli in `admin_models.dart`.
- **Rilettura:**
  - `AdminPoller` (timer, una lettura alla volta);
  - `AdminTabController<T>`, la base dei controller delle schede, con `AdminData<T>` (valore, errore, ora dell'ultimo aggiornamento);
  - `adminForegroundProvider` e `adminEpochProvider`.
- **Interfaccia:**
  - `ServerStrip` con `ServerInfoController` e `RestartArea`;
  - `RestartController` e `RestartDialog`;
  - `SessionsTab` con `SessionsController`;
  - `AdminScreen`;
  - `WfTabButton` condiviso con la pagina Richieste.
- **Navigazione:** la rotta `/admin` nella shell e la voce nel menu dell'avatar.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, lucide_icons_flutter, clock, intl, fake_async (test).

**Worktree:** `.claude/worktrees/piano-16a`, branch `feat/piano-16a`. **Base:** `main` con questo piano. **Test a inizio piano:** da contare all'avvio; a fine piano 15b erano 1875 Flutter e 383 plugin.

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-16a`).
  - Comandi git semplici: niente `git -C`, niente variabili nei comandi git.
  - Mai `git checkout -- <file>` su un file che hai modificato.
- **Prima di ogni commit:** `flutter analyze` senza problemi e `flutter test` tutto verde (la suite intera).
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: molti file della working copy sono CRLF (per esempio `router.dart`, `app_shell.dart`, gli ARB, `requests_screen.dart`, `auth_models.dart`), l'indice è LF con `core.autocrlf=true`. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) e controlla con `iconv -f UTF-8 -t UTF-8 <file>`. Non usare strumenti che cambiano la codifica.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; `clock.now()`, mai `DateTime.now()`.
- **Spinner e `pumpAndSettle`:** un `CircularProgressIndicator` senza valore non si ferma mai, quindi `pumpAndSettle` va in timeout. Mentre c'è uno spinner, usa `pump()` o `pump(durata)`.
- **Timer nei test:** i controller della pagina rileggono con dei timer. Nei test di controller usa `fakeAsync` (o `pumpEventQueue` se basta la prima lettura). Nei widget test i timer si chiudono quando l'albero si smonta; un `Future.delayed` del riavvio, invece, va portato a termine dentro il test.
- **Provider `autoDispose`:** restano vivi solo con un ascoltatore; nei test di controller usa `container.listen(...)` prima di leggere.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-06 sul codice di `main` (`17095cf`) e sul server, in sola lettura.

**App**
- `JellyfinUser` (`lib/core/jellyfin/auth_models.dart`) legge da `Policy` solo `SyncPlayAccess` (`_syncPlayAccess`). Il costruttore è `const`, con `id`, `name`, `primaryImageTag`, `syncPlayAccess`.
- **Sessione:**
  - `SessionController` (`lib/features/auth/session_controller.dart`) usa `AuthService` (`_auth`). `AuthService` ha `AuthApi` (`_api`), e `AuthApi.getMe()` legge `/Users/Me`.
  - Nei test `session_controller_test.dart` mocka `AuthService` con mocktail, e `auth_service_test.dart` mocka `AuthApi`.
  - `FakeSessionController` (`test/support/fake_session_controller.dart`) ha `set(state)`.
- **HTTP:**
  - `JellyfinHttp` ha `get`, `post`, `delete` con `quietStatuses`.
  - `parseJson(data, fromJson)` trasforma le forme inattese in `ServerErrorException(null)`.
  - Gli errori sono `ApiException`: `UnauthorizedException`, `ForbiddenException`, `NotFoundException`, `ServerUnreachableException`, `ServerErrorException(statusCode)`.
  - `describeError(l, error)` (`lib/app/error_text.dart`) dà il messaggio.
- **Test HTTP:** `FakeAdapter((options) => FakeResponse(status, body))` in `test/support/fake_adapter.dart`. Un handler che lancia `SocketException` diventa `ServerUnreachableException`.
- **Componenti:**
  - `LoadingView`, `ErrorView(error:, onRetry:)` e `SkeletonBox` sono in `lib/ui/states.dart`;
  - `showWfDialog<T>(context, builder:, semanticLabel:)` è in `lib/ui/wf_dialog.dart`;
  - `WfButton.secondary(label:, icon:, onPressed:)` è in `lib/ui/wf_buttons.dart`;
  - `WfImage(image:)` è in `lib/ui/wf_image.dart`; nei test le immagini sono sostituite da `pumpApp`;
  - `imageUrlsProvider` (`lib/features/library/library_providers.dart`) ha `primaryOf(itemId, maxWidth:)`;
  - `SmoothScrollController` è in `lib/ui/smooth_scroll.dart`;
  - `formatClock(Duration)` (`lib/features/library/item_labels.dart`) dà "12:34" o "1:02:03".
- **Avvisi:** `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(…)))`, come nella pagina Richieste.
- **Colori:** `WfColors.bg`, `surface`, `surfaceHigh`, `border`, `gold`, `cream`, `creamMuted`, `error`. Non c'è un ambra: per gli avvisi si usa `gold`.
- **Pagina Richieste** (`lib/features/requests/requests_screen.dart`):
  - titolo `Text(l.navRequests.toUpperCase(), style: WfText.display(40))` con padding `EdgeInsets.fromLTRB(32, 16, 32, 12)`;
  - schede disegnate da `_TabButton` (privato) in fondo al file;
  - quando la funzione sparisce, `context.go('/home')` dopo il primo frame.
- **Menu dell'avatar:** `_UserMenu` in `lib/app/app_shell.dart`, un `PopupMenuButton<String>` con `key: Key('user-menu')`, voci `settings` e `logout`.
- **Rotte:** in `lib/app/router.dart`, dentro la `ShellRoute`, con `shellPage(context, state, child, underBar: true)`.
- **Ore relative:** le chiavi `inboxNow` ("adesso"), `inboxMinutesAgo(n)` ("{n} min fa"), `inboxHoursAgo(n)` ("{n} h fa"). Nei test servono `initializeDateFormatting()` (`package:intl/date_symbol_data_local.dart`) per `DateFormat` con `it`.
- **Riverpod 3:** `ref.mounted` esiste (lo usa `CatalogController`); `ref.listen(…, fireImmediately: true)` si usa già nell'app; i test usano `ProviderContainer.test(overrides: …, retry: (_, _) => null)`.
- **Icone verificate** in lucide_icons_flutter 3.1.20: `shieldCheck`, `rotateCw`, `refreshCw`, `server`, `triangleAlert`, `pause`, `users`, `circleAlert`.
- **Date:** `DateTime.tryParse('2026-10-06T03:39:07.1141718Z')` funziona (7 cifre decimali).

**Server** (Jellyfin 10.11.9, risposte vere del 2026-10-06)
- `/System/Info`: `ServerName` "WonderFlix", `Version` "10.11.9", `OperatingSystemDisplayName` "" (vuoto), `HasPendingRestart` false, `CanSelfRestart` true.
- `/Sessions` con una chiave API dava un elenco vuoto (nessuno attivo). La forma delle sessioni viene dallo schema OpenAPI 10.11.9 (`docs/reference/jellyfin-openapi-10.11.9.json`, `SessionInfoDto`, `PlayerStateInfo`, `TranscodingInfo`).
- `/SyncPlay/List` con una chiave API risponde 400 (serve un utente). Con l'admin dà `GroupInfoDto[]`: `GroupId`, `GroupName`, `State`, `Participants` (nomi), `LastUpdatedAt`.
- Nel registro le voci di sistema hanno `UserId` "00000000000000000000000000000000".
- **Il riavvio:** Jellyfin gira sotto `s6-supervise` e si rilancia da solo.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi |
| `lib/core/jellyfin/auth_models.dart` | modifica | `JellyfinUser.isAdministrator` |
| `lib/features/auth/auth_service.dart` | modifica | `currentUser()` |
| `lib/features/auth/session_controller.dart` | modifica | `refreshUser()` |
| `test/support/fake_session_controller.dart` | modifica | `refreshUser` finto |
| `lib/core/jellyfin/admin_models.dart` | crea | sessioni, riproduzione, transcodifica, party, server |
| `lib/core/jellyfin/admin_api.dart` | crea | `AdminApi` |
| `test/support/admin_json.dart` | crea | JSON di Jellyfin per i test |
| `test/support/admin_fakes.dart` | crea | `FakeAdminApi`, `FakeAdminForeground`, dati, `adminTestOverrides` |
| `lib/features/admin/admin_providers.dart` | crea | `adminApiProvider`, `isAdminProvider`, `adminForegroundProvider`, `adminEpochProvider` |
| `lib/features/admin/admin_poller.dart` | crea | `AdminPoller` |
| `lib/features/admin/admin_tab_controller.dart` | crea | `AdminData`, `AdminTabController` |
| `lib/features/admin/admin_time.dart` | crea | `adminTimeLabel`, `adminClockLabel` |
| `lib/features/admin/admin_widgets.dart` | crea | titoli di sezione, testo vuoto, riga utente, "Dati non aggiornati" |
| `lib/features/admin/session_labels.dart` | crea | metodo, titolo, dispositivo, transcodifica, motivi, stato dei party |
| `lib/features/admin/sessions_controller.dart` | crea | `SessionsSnapshot`, `SessionsController` |
| `lib/features/admin/sessions_tab.dart` | crea | scheda Sessioni |
| `lib/features/admin/restart_controller.dart` | crea | `RestartController` |
| `lib/features/admin/restart_dialog.dart` | crea | `showRestartDialog`, `RestartDialog` |
| `lib/features/admin/server_strip.dart` | crea | `ServerInfoController`, `ServerStrip`, `RestartArea` |
| `lib/ui/wf_tab_button.dart` | crea | `WfTabButton` |
| `lib/features/requests/requests_screen.dart` | modifica | usa `WfTabButton` |
| `lib/features/admin/admin_navigation.dart` | crea | `AdminTab`, `openAdmin` |
| `lib/features/admin/admin_screen.dart` | crea | pagina Amministrazione |
| `lib/app/router.dart`, `lib/app/app_shell.dart` | modifica | rotta `/admin`, voce nel menu |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1–5):** testi, utente admin, modelli e `AdminApi`, rilettura periodica.
- **Gruppo B (Task 6–8):** scheda Sessioni, striscia e riavvio, pagina con rotta e menu.
- **Gruppo C (Task 9):** allineamento della spec, verifica, build.

---

## Gruppo A — fondamenta

### Task 1: testi del piano

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan16a_test.dart`

- [ ] **Step 1: test che fallisce**

`test/app/l10n_plan16a_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 16a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.menuAdmin, 'Amministrazione');
    expect(it.adminTabSessions, 'Sessioni');
    expect(it.adminServerVersion('10.11.9'), 'Jellyfin 10.11.9');
    expect(it.adminServerVersionOs('10.11.9', 'Linux'), 'Jellyfin 10.11.9 · Linux');
    expect(it.adminRestartViewers(1), '1 persona sta guardando:');
    expect(it.adminRestartViewers(2), '2 persone stanno guardando:');
    expect(it.adminViewer('viviroby', 'Dune (2021)'), 'viviroby — Dune (2021)');
    expect(it.adminBitrate('8,2'), '8,2 Mbps');
    expect(it.adminActive('3 min fa'), 'attivo 3 min fa');
    expect(it.adminMovieYear('Dune', '2021'), 'Dune (2021)');
    expect(it.adminEpisodeTitle('Lost', 'S1:E3', 'Pilota'), 'Lost · S1:E3 · Pilota');
    expect(it.adminEpisodeNoCode('Lost', 'Pilota'), 'Lost · Pilota');
    expect(it.adminStale('12:03'), 'Dati non aggiornati · ultimo aggiornamento 12:03');
    expect(it.adminRestarting, 'Riavvio in corso…');
    expect(en.menuAdmin, 'Administration');
    expect(en.adminRestartViewers(1), '1 person is watching:');
    expect(en.adminRestartViewers(2), '2 people are watching:');
    expect(en.adminStale('12:03'), 'Data not up to date · last update 12:03');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.adminRestart,
        l.adminPendingRestart,
        l.adminPendingRestartHint,
        l.adminRestartBack,
        l.adminRestartTimedOut,
        l.adminRestartRecheck,
        l.adminRestartFailed,
        l.adminRestartTitle,
        l.adminRestartInterrupts,
        l.adminRestartNobody,
        l.adminRestartUnknown,
        l.adminCancel,
        l.adminSessionsPlaying,
        l.adminSessionsIdle,
        l.adminSessionsParties,
        l.adminSessionsNobodyPlaying,
        l.adminSessionsNobodyIdle,
        l.adminSessionsNoParties,
        l.adminMethodDirect,
        l.adminMethodRemux,
        l.adminMethodTranscode,
        l.adminSoftware,
        l.adminPartyPlaying,
        l.adminPartyPaused,
        l.adminPartyWaiting,
        l.adminPartyIdle,
        l.adminReasonContainer,
        l.adminReasonVideoCodec,
        l.adminReasonAudioCodec,
        l.adminReasonSubtitles,
        l.adminReasonVideoProfile,
        l.adminReasonVideoLevel,
        l.adminReasonResolution,
        l.adminReasonBitDepth,
        l.adminReasonVideoRange,
        l.adminReasonAudioChannels,
        l.adminReasonBitrate,
        l.adminReasonExternalAudio,
        l.adminNoLongerAdmin,
      ], everyElement(isNotEmpty));
    }
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/l10n_plan16a_test.dart`
Expected: FAIL in compilazione (`menuAdmin` non esiste).

- [ ] **Step 3: aggiungi i testi**

In `l10n/app_it.arb`, prima della `}` finale, dopo l'ultima voce (`"@inboxRequestTitleSeasons": …`, a cui va aggiunta la virgola):

```json
  "menuAdmin": "Amministrazione",
  "adminTabSessions": "Sessioni",
  "adminServerVersion": "Jellyfin {version}",
  "@adminServerVersion": {"placeholders": {"version": {"type": "String"}}},
  "adminServerVersionOs": "Jellyfin {version} · {os}",
  "@adminServerVersionOs": {"placeholders": {"version": {"type": "String"}, "os": {"type": "String"}}},
  "adminRestart": "Riavvia",
  "adminPendingRestart": "Riavvio necessario",
  "adminPendingRestartHint": "Jellyfin va riavviato per finire un'installazione o un aggiornamento",
  "adminRestarting": "Riavvio in corso…",
  "adminRestartBack": "Jellyfin è tornato",
  "adminRestartTimedOut": "Jellyfin non risponde ancora",
  "adminRestartRecheck": "Ricontrolla",
  "adminRestartFailed": "Riavvio non riuscito",
  "adminRestartTitle": "Riavviare Jellyfin?",
  "adminRestartViewers": "{count, plural, =1{1 persona sta guardando:} other{{count} persone stanno guardando:}}",
  "@adminRestartViewers": {"placeholders": {"count": {"type": "int"}}},
  "adminRestartInterrupts": "Il riavvio interrompe la visione e i watch party.",
  "adminRestartNobody": "Nessuno sta guardando.",
  "adminRestartUnknown": "Non so chi sta guardando.",
  "adminCancel": "Annulla",
  "adminViewer": "{name} — {title}",
  "@adminViewer": {"placeholders": {"name": {"type": "String"}, "title": {"type": "String"}}},
  "adminSessionsPlaying": "In riproduzione",
  "adminSessionsIdle": "Collegati",
  "adminSessionsParties": "Watch party",
  "adminSessionsNobodyPlaying": "Nessuno sta guardando",
  "adminSessionsNobodyIdle": "Nessun altro collegato",
  "adminSessionsNoParties": "Nessun watch party in corso",
  "adminMethodDirect": "Diretta",
  "adminMethodRemux": "Remux",
  "adminMethodTranscode": "Transcodifica",
  "adminSoftware": "Software",
  "adminBitrate": "{value} Mbps",
  "@adminBitrate": {"placeholders": {"value": {"type": "String"}}},
  "adminActive": "attivo {time}",
  "@adminActive": {"placeholders": {"time": {"type": "String"}}},
  "adminPartyPlaying": "In riproduzione",
  "adminPartyPaused": "In pausa",
  "adminPartyWaiting": "In attesa",
  "adminPartyIdle": "Fermo",
  "adminMovieYear": "{title} ({year})",
  "@adminMovieYear": {"placeholders": {"title": {"type": "String"}, "year": {"type": "String"}}},
  "adminEpisodeTitle": "{series} · {code} · {title}",
  "@adminEpisodeTitle": {"placeholders": {"series": {"type": "String"}, "code": {"type": "String"}, "title": {"type": "String"}}},
  "adminEpisodeNoCode": "{series} · {title}",
  "@adminEpisodeNoCode": {"placeholders": {"series": {"type": "String"}, "title": {"type": "String"}}},
  "adminReasonContainer": "contenitore non supportato",
  "adminReasonVideoCodec": "codec video non supportato",
  "adminReasonAudioCodec": "codec audio non supportato",
  "adminReasonSubtitles": "sottotitoli non supportati",
  "adminReasonVideoProfile": "profilo video non supportato",
  "adminReasonVideoLevel": "livello video non supportato",
  "adminReasonResolution": "risoluzione non supportata",
  "adminReasonBitDepth": "profondità di colore non supportata",
  "adminReasonVideoRange": "gamma dinamica non supportata",
  "adminReasonAudioChannels": "canali audio non supportati",
  "adminReasonBitrate": "bitrate oltre il limite",
  "adminReasonExternalAudio": "audio esterno",
  "adminStale": "Dati non aggiornati · ultimo aggiornamento {time}",
  "@adminStale": {"placeholders": {"time": {"type": "String"}}},
  "adminNoLongerAdmin": "Non sei più amministratore"
```

In `l10n/app_en.arb`, prima della `}` finale, dopo `"inboxRequestTitleSeasons": …` (con la virgola):

```json
  "menuAdmin": "Administration",
  "adminTabSessions": "Sessions",
  "adminServerVersion": "Jellyfin {version}",
  "adminServerVersionOs": "Jellyfin {version} · {os}",
  "adminRestart": "Restart",
  "adminPendingRestart": "Restart needed",
  "adminPendingRestartHint": "Jellyfin needs a restart to finish an installation or an update",
  "adminRestarting": "Restarting…",
  "adminRestartBack": "Jellyfin is back",
  "adminRestartTimedOut": "Jellyfin is not answering yet",
  "adminRestartRecheck": "Check again",
  "adminRestartFailed": "Restart failed",
  "adminRestartTitle": "Restart Jellyfin?",
  "adminRestartViewers": "{count, plural, =1{1 person is watching:} other{{count} people are watching:}}",
  "adminRestartInterrupts": "Restarting stops playback and watch parties.",
  "adminRestartNobody": "Nobody is watching.",
  "adminRestartUnknown": "Can't tell who is watching.",
  "adminCancel": "Cancel",
  "adminViewer": "{name} — {title}",
  "adminSessionsPlaying": "Playing",
  "adminSessionsIdle": "Online",
  "adminSessionsParties": "Watch parties",
  "adminSessionsNobodyPlaying": "Nobody is watching",
  "adminSessionsNobodyIdle": "Nobody else is online",
  "adminSessionsNoParties": "No watch party right now",
  "adminMethodDirect": "Direct play",
  "adminMethodRemux": "Remux",
  "adminMethodTranscode": "Transcoding",
  "adminSoftware": "Software",
  "adminBitrate": "{value} Mbps",
  "adminActive": "active {time}",
  "adminPartyPlaying": "Playing",
  "adminPartyPaused": "Paused",
  "adminPartyWaiting": "Waiting",
  "adminPartyIdle": "Idle",
  "adminMovieYear": "{title} ({year})",
  "adminEpisodeTitle": "{series} · {code} · {title}",
  "adminEpisodeNoCode": "{series} · {title}",
  "adminReasonContainer": "container not supported",
  "adminReasonVideoCodec": "video codec not supported",
  "adminReasonAudioCodec": "audio codec not supported",
  "adminReasonSubtitles": "subtitles not supported",
  "adminReasonVideoProfile": "video profile not supported",
  "adminReasonVideoLevel": "video level not supported",
  "adminReasonResolution": "resolution not supported",
  "adminReasonBitDepth": "bit depth not supported",
  "adminReasonVideoRange": "dynamic range not supported",
  "adminReasonAudioChannels": "audio channels not supported",
  "adminReasonBitrate": "bitrate over the limit",
  "adminReasonExternalAudio": "external audio",
  "adminStale": "Data not up to date · last update {time}",
  "adminNoLongerAdmin": "You are no longer an administrator"
```

Run: `flutter gen-l10n`

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/app/l10n_plan16a_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Run `flutter analyze` e `flutter test` (tutta la suite), poi:

```bash
git add l10n/app_it.arb l10n/app_en.arb test/app/l10n_plan16a_test.dart
git commit -m "feat(app): add plan 16a strings"
```

### Task 2: chi è admin

**Files:**
- Modify: `lib/core/jellyfin/auth_models.dart`, `lib/features/auth/auth_service.dart`, `lib/features/auth/session_controller.dart`, `test/support/fake_session_controller.dart`
- Create: `lib/features/admin/admin_providers.dart`
- Test: `test/core/jellyfin/auth_models_test.dart`, `test/features/auth/auth_service_test.dart`, `test/features/auth/session_controller_test.dart`, `test/features/admin/admin_providers_test.dart`

- [ ] **Step 1: test che falliscono**

In fondo a `main()` di `test/core/jellyfin/auth_models_test.dart`:

```dart
  test('IsAdministrator dalla policy: vero, falso o assente', () {
    JellyfinUser admin(Object? value) => JellyfinUser.fromJson({
          'Id': 'u1',
          'Name': 'Mario',
          'Policy': {'IsAdministrator': ?value},
        });

    expect(admin(true).isAdministrator, isTrue);
    expect(admin(false).isAdministrator, isFalse);
    expect(admin(null).isAdministrator, isFalse);
    expect(admin('true').isAdministrator, isFalse,
        reason: 'solo un booleano vero');
    expect(JellyfinUser.fromJson({'Id': 'u1', 'Name': 'Mario'}).isAdministrator,
        isFalse);
    expect(const JellyfinUser(id: 'u1', name: 'Mario').isAdministrator, isFalse);
  });
```

In `test/features/auth/auth_service_test.dart`, dentro `main()` dopo il gruppo `restore`:

```dart
  test('currentUser rilegge /Users/Me', () async {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);
    when(() => api.getMe()).thenAnswer((_) async => admin);

    expect((await service.currentUser()).isAdministrator, isTrue);
    verify(() => api.getMe()).called(1);
  });
```

In fondo a `main()` di `test/features/auth/session_controller_test.dart` (aggiungi gli import `package:wonderflix/core/jellyfin/auth_models.dart` se manca):

```dart
  group('refreshUser', () {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);

    Future<void> signIn() async {
      when(() => auth.restore())
          .thenAnswer((_) async => const RestoredSession(admin));
      await controller().restore();
    }

    test('rilegge l\'utente e lo mette nella sessione', () async {
      await signIn();
      when(() => auth.currentUser()).thenAnswer((_) async => testUser);

      await controller().refreshUser();

      final session = state() as SessionSignedIn;
      expect(session.user.isAdministrator, isFalse);
    });

    test('errore: la sessione resta com\'è', () async {
      await signIn();
      when(() => auth.currentUser())
          .thenThrow(const ServerUnreachableException());

      await controller().refreshUser();

      expect((state() as SessionSignedIn).user.isAdministrator, isTrue);
    });

    test('senza sessione non chiede nulla', () async {
      await controller().refreshUser();
      verifyNever(() => auth.currentUser());
    });
  });
```

`test/features/admin/admin_providers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';

void main() {
  ProviderContainer containerFor(SessionState session) => ProviderContainer.test(
        overrides: [
          sessionControllerProvider
              .overrideWith(() => FakeSessionController(session)),
        ],
        retry: (_, _) => null,
      );

  test('isAdmin solo con un admin collegato', () {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);
    expect(containerFor(const SessionSignedIn(admin)).read(isAdminProvider),
        isTrue);
    expect(containerFor(const SessionSignedIn(testUser)).read(isAdminProvider),
        isFalse);
    expect(containerFor(const SessionSignedOut()).read(isAdminProvider),
        isFalse);
  });

  test('isAdmin segue la sessione', () {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);
    final fake = FakeSessionController(const SessionSignedIn(admin));
    final container = ProviderContainer.test(
      overrides: [sessionControllerProvider.overrideWith(() => fake)],
      retry: (_, _) => null,
    );
    expect(container.read(isAdminProvider), isTrue);

    fake.set(const SessionSignedIn(testUser));
    expect(container.read(isAdminProvider), isFalse);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/jellyfin/auth_models_test.dart test/features/auth test/features/admin/admin_providers_test.dart`
Expected: FAIL in compilazione (`isAdministrator`, `currentUser`, `refreshUser`, `admin_providers.dart` non esistono).

- [ ] **Step 3: implementa**

`lib/core/jellyfin/auth_models.dart`, dopo `_syncPlayAccess`:

```dart
/// L'utente è amministratore di Jellyfin (`Policy.IsAdministrator`, spec J
/// §7): solo con un `true` vero.
bool _isAdministrator(Object? policy) =>
    policy is Map<String, dynamic> && policy['IsAdministrator'] == true;
```

e `JellyfinUser` diventa:

```dart
class JellyfinUser {
  const JellyfinUser({
    required this.id,
    required this.name,
    this.primaryImageTag,
    this.syncPlayAccess = SyncPlayAccess.createAndJoin,
    this.isAdministrator = false,
  });

  factory JellyfinUser.fromJson(Map<String, dynamic> json) => JellyfinUser(
        id: json['Id'] as String,
        name: json['Name'] as String,
        primaryImageTag: json['PrimaryImageTag'] as String?,
        syncPlayAccess: _syncPlayAccess(json['Policy']),
        isAdministrator: _isAdministrator(json['Policy']),
      );

  final String id;
  final String name;
  final String? primaryImageTag;
  final SyncPlayAccess syncPlayAccess;

  /// Vede la pagina Amministrazione (spec J §7). Il server controlla comunque
  /// ogni chiamata.
  final bool isAdministrator;
}
```

`lib/features/auth/auth_service.dart`, in `AuthService` dopo `restore()`:

```dart
  /// L'utente della sessione riletto dal server (`/Users/Me`), per esempio
  /// dopo un 403 di una chiamata da admin (spec J §12). Lancia
  /// [ApiException].
  Future<JellyfinUser> currentUser() => _api.getMe();
```

`lib/features/auth/session_controller.dart`: aggiungi l'import `'../../core/jellyfin/api_exception.dart'` e, in `SessionController` dopo `logout()`:

```dart
  /// Rilegge l'utente (spec J §12): per esempio i permessi da admin dopo un
  /// 403. Senza sessione non fa nulla. Un errore lascia la sessione com'è
  /// (un 401 passa già da [_onUnauthorized]).
  Future<void> refreshUser() async {
    if (state is! SessionSignedIn) return;
    try {
      final user = await _auth.currentUser();
      if (state is SessionSignedIn) state = SessionSignedIn(user);
    } on ApiException {
      // La sessione resta quella di prima.
    }
  }
```

`test/support/fake_session_controller.dart`, nella classe dopo `approvedUser`:

```dart
  int refreshUserCalls = 0;

  /// L'utente che [refreshUser] mette nella sessione; `null`: la sessione
  /// resta com'è.
  JellyfinUser? refreshedUser;
```

e dopo `logout()`:

```dart
  @override
  Future<void> refreshUser() async {
    refreshUserCalls++;
    final user = refreshedUser;
    if (user != null) state = SessionSignedIn(user);
  }
```

`lib/features/admin/admin_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';

/// L'utente collegato è amministratore di Jellyfin (spec J §7): vede la voce
/// "Amministrazione" e la pagina.
final isAdminProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session is SessionSignedIn && session.user.isAdministrator;
});
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/core/jellyfin/auth_models_test.dart test/features/auth test/features/admin/admin_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/core/jellyfin/auth_models.dart lib/features/auth/auth_service.dart lib/features/auth/session_controller.dart lib/features/admin/admin_providers.dart test/support/fake_session_controller.dart test/core/jellyfin/auth_models_test.dart test/features/auth/auth_service_test.dart test/features/auth/session_controller_test.dart test/features/admin/admin_providers_test.dart
git commit -m "feat(app): know whether the user is a Jellyfin admin"
```

### Task 3: modelli e `AdminApi`

**Files:**
- Create: `lib/core/jellyfin/admin_models.dart`, `lib/core/jellyfin/admin_api.dart`, `test/support/admin_json.dart`, `test/support/admin_fakes.dart`
- Test: `test/core/jellyfin/admin_models_test.dart`, `test/core/jellyfin/admin_api_test.dart`

- [ ] **Step 1: i JSON dei test**

`test/support/admin_json.dart`:

```dart
/// Risposte di Jellyfin 10.11.9 per la pagina Amministrazione. `System/Info`
/// è quella vera del server (2026-10-06) senza percorsi né id; le sessioni e
/// i party seguono lo schema OpenAPI 10.11.9 (`SessionInfoDto`,
/// `GroupInfoDto`).
final serverInfoJson = <String, dynamic>{
  'OperatingSystemDisplayName': '',
  'HasPendingRestart': false,
  'IsShuttingDown': false,
  'SupportsLibraryMonitor': true,
  'WebSocketPortNumber': 8096,
  'CompletedInstallations': <Object>[],
  'CanSelfRestart': true,
  'CanLaunchWebBrowser': false,
  'HasUpdateAvailable': false,
  'SystemArchitecture': 'X64',
  'ServerName': 'WonderFlix',
  'Version': '10.11.9',
  'ProductName': 'Jellyfin Server',
  'OperatingSystem': '',
  'StartupWizardCompleted': true,
};

/// Quattro sessioni:
/// - s1: viviroby su FireTV, un episodio transcodificato (video e audio);
/// - s2: lucia, un film in pausa, dichiarato `Transcode` ma con video e audio
///   diretti (un remux);
/// - s3: davide.sidoti su WonderFlix, collegato senza riprodurre;
/// - s4: la chiave API di Seerr, senza utente (da scartare).
final sessionsJson = <Map<String, dynamic>>[
  {
    'PlayState': {
      'PositionTicks': 7540000000,
      'CanSeek': true,
      'IsPaused': false,
      'IsMuted': false,
      'VolumeLevel': 100,
      'PlayMethod': 'Transcode',
      'RepeatMode': 'RepeatNone',
    },
    'Id': 's1',
    'UserId': '6a48860fd4d94124b1890173d68c9de3',
    'UserName': 'viviroby',
    'Client': 'Jellyfin Android TV',
    'DeviceName': 'FireTV Soggiorno',
    'DeviceId': 'd1',
    'ApplicationVersion': '0.19.10',
    'LastActivityDate': '2026-10-06T07:53:20.8580665Z',
    'NowPlayingItem': {
      'Name': 'Pilota',
      'Id': 'e1',
      'Type': 'Episode',
      'SeriesName': 'Lost',
      'SeriesId': 'ser1',
      'ParentIndexNumber': 1,
      'IndexNumber': 3,
      'ProductionYear': 2004,
      'RunTimeTicks': 25560000000,
    },
    'TranscodingInfo': {
      'AudioCodec': 'aac',
      'VideoCodec': 'h264',
      'Container': 'ts',
      'IsVideoDirect': false,
      'IsAudioDirect': false,
      'Bitrate': 8200000,
      'Width': 1920,
      'Height': 1080,
      'AudioChannels': 2,
      'HardwareAccelerationType': 'none',
      'TranscodeReasons': ['VideoCodecNotSupported', 'AudioCodecNotSupported'],
    },
    'IsActive': true,
    'SupportsMediaControl': true,
    'SupportsRemoteControl': true,
  },
  {
    'PlayState': {
      'PositionTicks': 36000000000,
      'CanSeek': true,
      'IsPaused': true,
      'PlayMethod': 'Transcode',
    },
    'Id': 's2',
    'UserId': 'b1c2d3e4f5a64b7c8d9e0f1a2b3c4d5e',
    'UserName': 'lucia',
    'Client': 'Jellyfin Web',
    'DeviceName': 'Chrome',
    'LastActivityDate': '2026-10-06T08:05:00.0000000Z',
    'NowPlayingItem': {
      'Name': 'Dune',
      'Id': 'm1',
      'Type': 'Movie',
      'ProductionYear': 2021,
      'RunTimeTicks': 93720000000,
    },
    'TranscodingInfo': {
      'AudioCodec': 'eac3',
      'VideoCodec': 'hevc',
      'Container': 'mp4',
      'IsVideoDirect': true,
      'IsAudioDirect': true,
      'Bitrate': 21000000,
      'HardwareAccelerationType': 'none',
      'TranscodeReasons': ['ContainerNotSupported'],
    },
    'IsActive': true,
  },
  {
    'PlayState': {'CanSeek': false, 'IsPaused': false, 'IsMuted': false},
    'Id': 's3',
    'UserId': 'ab8240c5fc1649e186f662fa00ca0fb0',
    'UserName': 'davide.sidoti',
    'Client': 'WonderFlix',
    'DeviceName': 'nocturne',
    'LastActivityDate': '2026-10-06T08:10:00.0000000Z',
    'IsActive': true,
  },
  {
    'PlayState': {'CanSeek': false, 'IsPaused': false},
    'Id': 's4',
    'UserId': '00000000000000000000000000000000',
    'Client': 'Seerr',
    'DeviceName': 'Seerr',
    'LastActivityDate': '2026-10-06T08:09:00.0000000Z',
    'IsActive': true,
  },
];

/// Un watch party in corso.
final partyGroupsJson = <Map<String, dynamic>>[
  {
    'GroupId': 'g1',
    'GroupName': 'Serata Lost',
    'State': 'Playing',
    'Participants': ['viviroby', 'Mario'],
    'LastUpdatedAt': '2026-10-06T08:00:00.0000000Z',
  },
];
```

- [ ] **Step 2: test che falliscono**

`test/core/jellyfin/admin_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';

import '../../support/admin_json.dart';

void main() {
  group('sessioni', () {
    test('legge le sessioni e scarta quelle senza utente', () {
      final sessions = parseSessions(sessionsJson);

      expect(sessions.map((s) => s.id), ['s1', 's2', 's3']);

      final episode = sessions[0];
      expect(episode.userName, 'viviroby');
      expect(episode.client, 'Jellyfin Android TV');
      expect(episode.deviceName, 'FireTV Soggiorno');
      expect(episode.lastActivity, DateTime.parse('2026-10-06T07:53:20.858066Z'));
      expect(episode.position, const Duration(minutes: 12, seconds: 34));
      expect(episode.isPaused, isFalse);
      expect(episode.playMethod, PlayMethod.transcode);
      final playing = episode.nowPlaying!;
      expect(playing.kind, NowPlayingKind.episode);
      expect(playing.name, 'Pilota');
      expect(playing.seriesName, 'Lost');
      expect(playing.seasonNumber, 1);
      expect(playing.episodeNumber, 3);
      expect(playing.runtime, const Duration(minutes: 42, seconds: 36));
      expect(playing.imageItemId, 'ser1', reason: 'la locandina della serie');
      final transcode = episode.transcode!;
      expect(transcode.videoCodec, 'h264');
      expect(transcode.audioCodec, 'aac');
      expect(transcode.isVideoDirect, isFalse);
      expect(transcode.isAudioDirect, isFalse);
      expect(transcode.bitrate, 8200000);
      expect(transcode.height, 1080);
      expect(transcode.hardwareAcceleration, 'none');
      expect(transcode.reasons,
          ['VideoCodecNotSupported', 'AudioCodecNotSupported']);

      final movie = sessions[1];
      expect(movie.isPaused, isTrue);
      expect(movie.nowPlaying!.kind, NowPlayingKind.movie);
      expect(movie.nowPlaying!.year, 2021);
      expect(movie.nowPlaying!.imageItemId, 'm1');
      expect(movie.transcode!.isVideoDirect, isTrue);
      expect(movie.transcode!.isAudioDirect, isTrue);

      final idle = sessions[2];
      expect(idle.nowPlaying, isNull);
      expect(idle.transcode, isNull);
      expect(idle.position, Duration.zero);
      expect(idle.playMethod, PlayMethod.unknown);
    });

    test('voci strane: si saltano o restano senza i campi', () {
      final sessions = parseSessions([
        {'UserId': 'u1', 'UserName': 'senza id'},
        {'Id': 'x1', 'UserName': 'senza utente'},
        {'Id': 'x2', 'UserId': '00000000-0000-0000-0000-000000000000'},
        'non è un oggetto',
        {
          'Id': 'x3',
          'UserId': 'u3',
          'UserName': 'ok',
          'PlayState': 'strano',
          'NowPlayingItem': {'Id': 'i1'},
          'TranscodingInfo': {
            'TranscodeReasons': 'ContainerNotSupported, AudioIsExternal',
          },
          'LastActivityDate': 'ieri',
        },
      ]);

      expect(sessions.map((s) => s.id), ['x3']);
      final session = sessions.single;
      expect(session.nowPlaying, isNull, reason: 'senza nome non si mostra');
      expect(session.lastActivity, isNull);
      expect(session.transcode!.reasons,
          ['ContainerNotSupported', 'AudioIsExternal']);
    });

    test('un corpo che non è un elenco è un errore del server', () {
      expect(() => parseSessions({'Items': <Object>[]}),
          throwsA(isA<ServerErrorException>()));
    });

    test('id vuoti di Jellyfin', () {
      expect(isEmptyJellyfinId('00000000000000000000000000000000'), isTrue);
      expect(isEmptyJellyfinId('00000000-0000-0000-0000-000000000000'), isTrue);
      expect(isEmptyJellyfinId('ab8240c5fc1649e186f662fa00ca0fb0'), isFalse);
    });
  });

  test('watch party', () {
    final groups = parsePartyGroups([
      ...partyGroupsJson,
      {'GroupName': 'senza id'},
      {'GroupId': 'g2', 'State': 'Boh', 'Participants': 42},
    ]);

    expect(groups.map((g) => g.id), ['g1', 'g2']);
    expect(groups[0].name, 'Serata Lost');
    expect(groups[0].state, PartyState.playing);
    expect(groups[0].participants, ['viviroby', 'Mario']);
    expect(groups[1].name, '');
    expect(groups[1].state, PartyState.unknown);
    expect(groups[1].participants, isEmpty);
  });

  test('informazioni sul server', () {
    final info = ServerInfo.fromJson(serverInfoJson);
    expect(info.name, 'WonderFlix');
    expect(info.version, '10.11.9');
    expect(info.operatingSystem, isNull, reason: 'sul server è vuoto');
    expect(info.hasPendingRestart, isFalse);

    final pending = ServerInfo.fromJson({
      ...serverInfoJson,
      'OperatingSystemDisplayName': 'Linux',
      'HasPendingRestart': true,
    });
    expect(pending.operatingSystem, 'Linux');
    expect(pending.hasPendingRestart, isTrue);

    expect(() => ServerInfo.fromJson({'ServerName': 'x'}),
        throwsA(isA<ServerErrorException>()));
  });
}
```

`test/core/jellyfin/admin_api_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_api.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/admin_json.dart';
import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late AdminApi api;

  setUp(() {
    adapter = FakeAdapter((options) => switch (options.path) {
          '/Sessions' => FakeResponse(200, sessionsJson),
          '/SyncPlay/List' => FakeResponse(200, partyGroupsJson),
          '/System/Info' => FakeResponse(200, serverInfoJson),
          '/System/Info/Public' =>
            const FakeResponse(200, {'Version': '10.11.9'}),
          '/System/Restart' => const FakeResponse(204),
          _ => const FakeResponse(404),
        });
    api = AdminApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('sessioni attive negli ultimi 16 minuti, come la Dashboard', () async {
    final sessions = await api.sessions();

    expect(sessions, hasLength(3));
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/Sessions');
    expect(request.queryParameters, {'activeWithinSeconds': 960});
  });

  test('watch party', () async {
    final groups = await api.partyGroups();
    expect(groups.single.name, 'Serata Lost');
    expect(adapter.requests.single.path, '/SyncPlay/List');
  });

  test('informazioni sul server', () async {
    final info = await api.serverInfo();
    expect(info.version, '10.11.9');
    expect(adapter.requests.single.path, '/System/Info');
  });

  test('un 403 arriva com\'è', () async {
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(api.sessions(), throwsA(isA<ForbiddenException>()));
  });

  test('riavvio', () async {
    await api.restart();
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/System/Restart');
  });

  group('isServerUp', () {
    test('risponde: su', () async {
      expect(await api.isServerUp(), isTrue);
      expect(adapter.requests.single.path, '/System/Info/Public');
    });

    test('502 o 503 di nginx durante il riavvio: giù', () async {
      adapter.handler = (_) => const FakeResponse(503);
      expect(await api.isServerUp(), isFalse);
      adapter.handler = (_) => const FakeResponse(502);
      expect(await api.isServerUp(), isFalse);
    });

    test('nessuna connessione: giù', () async {
      adapter.handler = (_) => throw const SocketException('refused');
      expect(await api.isServerUp(), isFalse);
    });
  });
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/core/jellyfin/admin_models_test.dart test/core/jellyfin/admin_api_test.dart`
Expected: FAIL in compilazione (i file non esistono).

- [ ] **Step 4: implementa i modelli**

`lib/core/jellyfin/admin_models.dart`:

```dart
import 'api_exception.dart';

/// Tick di Jellyfin in un microsecondo (10 milioni al secondo).
const _ticksPerMicrosecond = 10;

String? _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? _int(Map<String, dynamic> json, String key) => switch (json[key]) {
      final int value => value,
      final double value => value.round(),
      _ => null,
    };

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? DateTime.tryParse(value) : null;
}

Duration? _ticks(Map<String, dynamic> json, String key) {
  final ticks = _int(json, key);
  return ticks == null
      ? null
      : Duration(microseconds: ticks ~/ _ticksPerMicrosecond);
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// Stringhe di un elenco JSON; una stringa sola con le virgole (forma di
/// alcune versioni di Jellyfin) vale come elenco.
List<String> _strings(Object? value) => switch (value) {
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
List<T> _list<T>(Object? data, T? Function(Map<String, dynamic> json) parse) {
  if (data is! List) throw const ServerErrorException(null);
  return [
    for (final raw in data)
      if (_map(raw) case final json?)
        if (parse(json) case final value?) value,
  ];
}

/// Metodo di riproduzione dichiarato dal client (`PlayState.PlayMethod`).
enum PlayMethod { directPlay, directStream, transcode, unknown }

PlayMethod _playMethod(Object? raw) => switch (raw) {
      'DirectPlay' => PlayMethod.directPlay,
      'DirectStream' => PlayMethod.directStream,
      'Transcode' => PlayMethod.transcode,
      _ => PlayMethod.unknown,
    };

enum NowPlayingKind { movie, episode, other }

/// Cosa sta guardando una sessione (`NowPlayingItem`, spec J §8.2).
class NowPlaying {
  const NowPlaying({
    required this.itemId,
    required this.name,
    this.kind = NowPlayingKind.other,
    this.year,
    this.seriesName,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.runtime,
  });

  /// `null` senza `Id` o senza nome: non c'è niente da mostrare.
  static NowPlaying? fromJson(Map<String, dynamic> json) {
    final id = _string(json, 'Id');
    final name = _string(json, 'Name');
    if (id == null || name == null) return null;
    return NowPlaying(
      itemId: id,
      name: name,
      kind: switch (json['Type']) {
        'Movie' => NowPlayingKind.movie,
        'Episode' => NowPlayingKind.episode,
        _ => NowPlayingKind.other,
      },
      year: _int(json, 'ProductionYear'),
      seriesName: _string(json, 'SeriesName'),
      seriesId: _string(json, 'SeriesId'),
      seasonNumber: _int(json, 'ParentIndexNumber'),
      episodeNumber: _int(json, 'IndexNumber'),
      runtime: _ticks(json, 'RunTimeTicks'),
    );
  }

  final String itemId;
  final String name;
  final NowPlayingKind kind;
  final int? year;
  final String? seriesName;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  final Duration? runtime;

  /// L'elemento di cui mostrare la locandina: la serie per gli episodi.
  String get imageItemId =>
      kind == NowPlayingKind.episode ? (seriesId ?? itemId) : itemId;
}

/// La transcodifica in corso di una sessione (`TranscodingInfo`).
class TranscodeInfo {
  const TranscodeInfo({
    this.videoCodec,
    this.audioCodec,
    this.isVideoDirect = false,
    this.isAudioDirect = false,
    this.bitrate,
    this.width,
    this.height,
    this.hardwareAcceleration,
    this.reasons = const [],
  });

  factory TranscodeInfo.fromJson(Map<String, dynamic> json) => TranscodeInfo(
        videoCodec: _string(json, 'VideoCodec'),
        audioCodec: _string(json, 'AudioCodec'),
        isVideoDirect: json['IsVideoDirect'] == true,
        isAudioDirect: json['IsAudioDirect'] == true,
        bitrate: _int(json, 'Bitrate'),
        width: _int(json, 'Width'),
        height: _int(json, 'Height'),
        hardwareAcceleration: _string(json, 'HardwareAccelerationType'),
        reasons: _strings(json['TranscodeReasons']),
      );

  final String? videoCodec;
  final String? audioCodec;
  final bool isVideoDirect;
  final bool isAudioDirect;

  /// In bit al secondo.
  final int? bitrate;
  final int? width;
  final int? height;

  /// `HardwareAccelerationType`: "none", "qsv", "nvenc", "vaapi"…
  final String? hardwareAcceleration;

  /// `TranscodeReasons` come le scrive Jellyfin ("VideoCodecNotSupported"…).
  final List<String> reasons;
}

/// Una sessione di un utente (`SessionInfoDto`, spec J §8.2).
class SessionEntry {
  const SessionEntry({
    required this.id,
    required this.userId,
    required this.userName,
    this.client,
    this.deviceName,
    this.lastActivity,
    this.nowPlaying,
    this.position = Duration.zero,
    this.isPaused = false,
    this.playMethod = PlayMethod.unknown,
    this.transcode,
  });

  /// `null` senza `Id` o senza un utente vero: le sessioni delle chiavi API
  /// (Seerr, jfa-go…) non si mostrano (spec J §8.1).
  static SessionEntry? fromJson(Map<String, dynamic> json) {
    final id = _string(json, 'Id');
    final userId = _string(json, 'UserId');
    if (id == null || userId == null || isEmptyJellyfinId(userId)) return null;
    final playState = _map(json['PlayState']) ?? const <String, dynamic>{};
    final nowPlaying = _map(json['NowPlayingItem']);
    final transcode = _map(json['TranscodingInfo']);
    return SessionEntry(
      id: id,
      userId: userId,
      userName: _string(json, 'UserName') ?? '',
      client: _string(json, 'Client'),
      deviceName: _string(json, 'DeviceName'),
      lastActivity: _date(json, 'LastActivityDate'),
      nowPlaying: nowPlaying == null ? null : NowPlaying.fromJson(nowPlaying),
      position: _ticks(playState, 'PositionTicks') ?? Duration.zero,
      isPaused: playState['IsPaused'] == true,
      playMethod: _playMethod(playState['PlayMethod']),
      transcode: transcode == null ? null : TranscodeInfo.fromJson(transcode),
    );
  }

  final String id;
  final String userId;
  final String userName;
  final String? client;
  final String? deviceName;
  final DateTime? lastActivity;

  /// `null`: collegato senza riprodurre.
  final NowPlaying? nowPlaying;
  final Duration position;
  final bool isPaused;
  final PlayMethod playMethod;
  final TranscodeInfo? transcode;
}

List<SessionEntry> parseSessions(Object? data) =>
    _list(data, SessionEntry.fromJson);

/// Stato di un watch party (`GroupStateType`).
enum PartyState { idle, waiting, paused, playing, unknown }

/// Un watch party in corso (`GroupInfoDto`).
class PartyGroup {
  const PartyGroup({
    required this.id,
    required this.name,
    this.state = PartyState.unknown,
    this.participants = const [],
  });

  static PartyGroup? fromJson(Map<String, dynamic> json) {
    final id = _string(json, 'GroupId');
    if (id == null) return null;
    return PartyGroup(
      id: id,
      name: _string(json, 'GroupName') ?? '',
      state: switch (json['State']) {
        'Idle' => PartyState.idle,
        'Waiting' => PartyState.waiting,
        'Paused' => PartyState.paused,
        'Playing' => PartyState.playing,
        _ => PartyState.unknown,
      },
      participants: _strings(json['Participants']),
    );
  }

  final String id;
  final String name;
  final PartyState state;

  /// I nomi degli utenti nel gruppo.
  final List<String> participants;
}

List<PartyGroup> parsePartyGroups(Object? data) =>
    _list(data, PartyGroup.fromJson);

/// Il server, per la striscia in cima alla pagina (`/System/Info`).
class ServerInfo {
  const ServerInfo({
    required this.name,
    required this.version,
    this.operatingSystem,
    this.hasPendingRestart = false,
  });

  /// Senza `Version` la risposta non è quella attesa.
  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    final version = _string(json, 'Version');
    if (version == null) throw const ServerErrorException(null);
    return ServerInfo(
      name: _string(json, 'ServerName') ?? '',
      version: version,
      operatingSystem: _string(json, 'OperatingSystemDisplayName'),
      hasPendingRestart: json['HasPendingRestart'] == true,
    );
  }

  final String name;
  final String version;

  /// `null` se Jellyfin non lo dice (sul server è vuoto).
  final String? operatingSystem;

  /// Un'installazione o un aggiornamento aspettano un riavvio.
  final bool hasPendingRestart;
}
```

- [ ] **Step 5: implementa `AdminApi`**

`lib/core/jellyfin/admin_api.dart`:

```dart
import 'admin_models.dart';
import 'api_exception.dart';
import 'jellyfin_http.dart';

/// Chiamate da amministratore a Jellyfin (spec J §8.1). Gli errori sono
/// [ApiException]; un 403 vuol dire che l'utente non è più admin.
class AdminApi {
  AdminApi(this._http);

  final JellyfinHttp _http;

  /// Come la Dashboard web: le sessioni attive negli ultimi 16 minuti.
  static const activeWithin = Duration(seconds: 960);

  /// Durante un riavvio nginx risponde così finché Jellyfin non torna: sono
  /// esiti attesi, nel log come info.
  static const _restartStatuses = {502, 503, 504};

  Future<List<SessionEntry>> sessions() async => parseSessions(await _http
      .get('/Sessions', query: {'activeWithinSeconds': activeWithin.inSeconds}));

  Future<List<PartyGroup>> partyGroups() async =>
      parsePartyGroups(await _http.get('/SyncPlay/List'));

  Future<ServerInfo> serverInfo() async =>
      parseJson(await _http.get('/System/Info'), ServerInfo.fromJson);

  /// Jellyfin risponde (`/System/Info/Public`, senza accesso): per l'attesa
  /// del riavvio. Rete assente o errore del server: giù.
  Future<bool> isServerUp() async {
    try {
      await _http.get('/System/Info/Public', quietStatuses: _restartStatuses);
      return true;
    } on ServerUnreachableException {
      return false;
    } on ServerErrorException {
      return false;
    }
  }

  Future<void> restart() async {
    await _http.post('/System/Restart');
  }
}
```

- [ ] **Step 6: il finto per gli altri test**

`test/support/admin_fakes.dart`:

```dart
import 'package:wonderflix/core/jellyfin/admin_api.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';

import 'admin_json.dart';

const testAdmin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);

const testServerInfo = ServerInfo(name: 'WonderFlix', version: '10.11.9');

/// Le sessioni di [sessionsJson]: viviroby (episodio transcodificato), lucia
/// (film in remux, in pausa), davide.sidoti (collegato).
List<SessionEntry> testSessions() => parseSessions(sessionsJson);

/// Il party di [partyGroupsJson] ("Serata Lost").
List<PartyGroup> testParties() => parsePartyGroups(partyGroupsJson);

/// Una sessione costruita a mano.
SessionEntry testSession(
  String id,
  String userName, {
  NowPlaying? playing,
  DateTime? lastActivity,
  PlayMethod playMethod = PlayMethod.unknown,
  TranscodeInfo? transcode,
}) =>
    SessionEntry(
      id: id,
      userId: 'id-$userName',
      userName: userName,
      client: 'WonderFlix',
      deviceName: 'PC',
      lastActivity: lastActivity,
      nowPlaying: playing,
      playMethod: playMethod,
      transcode: transcode,
    );

const testMovie = NowPlaying(
  itemId: 'm1',
  name: 'Dune',
  kind: NowPlayingKind.movie,
  year: 2021,
  runtime: Duration(minutes: 155),
);

/// Jellyfin finto per la pagina Amministrazione.
class FakeAdminApi implements AdminApi {
  List<SessionEntry> sessionsValue = const [];
  List<PartyGroup> partiesValue = const [];
  ServerInfo serverInfoValue = testServerInfo;

  /// Errori delle letture: restano finché il test non li toglie.
  Object? sessionsError;
  Object? partiesError;
  Object? serverInfoError;

  /// Errore di [restart].
  Object? restartError;

  /// Risposte di [isServerUp], in ordine; finite, `true`.
  final upAnswers = <bool>[];

  /// Chiamate in ordine: `sessions`, `parties`, `info`, `up`, `restart`.
  final calls = <String>[];

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<List<SessionEntry>> sessions() async {
    calls.add('sessions');
    final error = sessionsError;
    if (error != null) throw error;
    return sessionsValue;
  }

  @override
  Future<List<PartyGroup>> partyGroups() async {
    calls.add('parties');
    final error = partiesError;
    if (error != null) throw error;
    return partiesValue;
  }

  @override
  Future<ServerInfo> serverInfo() async {
    calls.add('info');
    final error = serverInfoError;
    if (error != null) throw error;
    return serverInfoValue;
  }

  @override
  Future<bool> isServerUp() async {
    calls.add('up');
    return upAnswers.isEmpty ? true : upAnswers.removeAt(0);
  }

  @override
  Future<void> restart() async {
    calls.add('restart');
    final error = restartError;
    if (error != null) throw error;
  }
}
```

- [ ] **Step 7: verifica che passino**

Run: `flutter test test/core/jellyfin/admin_models_test.dart test/core/jellyfin/admin_api_test.dart`
Expected: PASS.

- [ ] **Step 8: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/core/jellyfin/admin_models.dart lib/core/jellyfin/admin_api.dart test/support/admin_json.dart test/support/admin_fakes.dart test/core/jellyfin/admin_models_test.dart test/core/jellyfin/admin_api_test.dart
git commit -m "feat(app): read sessions, watch parties and server info as admin"
```

### Task 4: rilettura periodica

**Files:**
- Create: `lib/features/admin/admin_poller.dart`
- Test: `test/features/admin/admin_poller_test.dart`

- [ ] **Step 1: test che fallisce**

`test/features/admin/admin_poller_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_poller.dart';

void main() {
  const every = Duration(seconds: 5);

  test('accesa: legge subito, poi a ogni intervallo', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 1);
      async.elapse(const Duration(seconds: 4));
      expect(reads, 1);
      async.elapse(const Duration(seconds: 1));
      expect(reads, 2);
      async.elapse(const Duration(seconds: 10));
      expect(reads, 4);

      poller.dispose();
    });
  });

  test('l\'intervallo parte dalla fine della lettura: mai due insieme', () {
    fakeAsync((async) {
      var reads = 0;
      var running = 0;
      var overlap = false;
      final poller = AdminPoller(
        read: () async {
          reads++;
          running++;
          if (running > 1) overlap = true;
          await Future<void>.delayed(const Duration(seconds: 8));
          running--;
        },
        interval: every,
      );

      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 1);
      // 8 s di lettura e 4 di attesa: la seconda non è ancora partita.
      async.elapse(const Duration(seconds: 12));
      expect(reads, 1);
      async.elapse(const Duration(seconds: 1));
      expect(reads, 2);
      expect(overlap, isFalse);

      poller.dispose();
      async.elapse(const Duration(seconds: 10));
    });
  });

  test('now durante una lettura: una sola lettura in più, subito dopo', () {
    fakeAsync((async) {
      final pending = <Completer<void>>[];
      final poller = AdminPoller(
        read: () {
          final read = Completer<void>();
          pending.add(read);
          return read.future;
        },
        interval: every,
      );

      poller.start();
      async.elapse(Duration.zero);
      expect(pending, hasLength(1));

      var done = false;
      unawaited(poller.now().then((_) => done = true));
      unawaited(poller.now());
      async.flushMicrotasks();
      expect(pending, hasLength(1));

      pending[0].complete();
      async.flushMicrotasks();
      expect(pending, hasLength(2));
      expect(done, isFalse);

      pending[1].complete();
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(pending, hasLength(2));

      async.elapse(every);
      expect(pending, hasLength(3));
      pending[2].complete();
      poller.dispose();
    });
  });

  test('spenta non legge; riaccesa legge subito', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 1);
      poller.stop();
      async.elapse(const Duration(seconds: 20));
      expect(reads, 1);
      expect(poller.active, isFalse);

      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 2);
      poller.dispose();
    });
  });

  test('un intervallo nuovo vale da subito', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      poller.start();
      async.elapse(Duration.zero);
      poller.interval = const Duration(seconds: 2);
      async.elapse(const Duration(seconds: 2));
      expect(reads, 2);
      async.elapse(const Duration(seconds: 2));
      expect(reads, 3);
      poller.dispose();
    });
  });

  test('una lettura che fallisce non ferma la rilettura', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(
        read: () async {
          reads++;
          if (reads == 1) throw StateError('rete');
        },
        interval: every,
      );

      poller.start();
      async.elapse(Duration.zero);
      async.elapse(every);
      expect(reads, 2);
      poller.dispose();
    });
  });

  test('chiusa: niente più letture, e now non legge', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      poller.start();
      async.elapse(Duration.zero);
      poller.dispose();
      unawaited(poller.now());
      poller.start();
      async.elapse(const Duration(seconds: 30));
      expect(reads, 1);
    });
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/admin/admin_poller_test.dart`
Expected: FAIL in compilazione (`admin_poller.dart` non esiste).

- [ ] **Step 3: implementa**

`lib/features/admin/admin_poller.dart`:

```dart
import 'dart:async';

/// Rilettura periodica di una scheda della pagina Amministrazione (spec J
/// §10). L'intervallo parte dalla fine della lettura precedente, quindi due
/// letture non si sovrappongono mai. Gli errori li gestisce [read]: qui si
/// ignorano, e la rilettura continua.
class AdminPoller {
  AdminPoller({required Future<void> Function() read, required Duration interval})
      : _read = read,
        _interval = interval;

  final Future<void> Function() _read;
  Duration _interval;
  Timer? _timer;

  /// Le letture in corso (una, più quelle chieste nel frattempo).
  Future<void>? _running;

  /// Una lettura chiesta mentre un'altra era in corso: parte appena finisce.
  bool _again = false;
  bool _active = false;
  bool _disposed = false;

  bool get active => _active;

  Duration get interval => _interval;

  /// Vale da subito: se si sta aspettando, l'attesa riparte con il valore
  /// nuovo.
  set interval(Duration value) {
    if (value == _interval) return;
    _interval = value;
    if (_active && _running == null) _schedule(value);
  }

  /// Accende la rilettura: una lettura subito, poi a ogni intervallo.
  void start() {
    if (_active || _disposed) return;
    _active = true;
    if (_running == null) _schedule(Duration.zero);
  }

  /// Spegne la rilettura; una lettura in corso finisce.
  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Una lettura adesso (dopo un'azione, "Riprova"). Se una è già in corso,
  /// ne parte un'altra appena finisce; il futuro si completa dopo quella.
  Future<void> now() {
    if (_disposed) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _run();
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  Future<void> _run() {
    _timer?.cancel();
    _timer = null;
    final run = _loop();
    _running = run;
    return run;
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        try {
          await _read();
        } on Object {
          // Lo stato dell'errore lo tiene chi legge.
        }
      } while (_again && !_disposed);
    } finally {
      _running = null;
      if (_active && !_disposed) _schedule(_interval);
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_run());
    });
  }
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/features/admin/admin_poller_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/features/admin/admin_poller.dart test/features/admin/admin_poller_test.dart
git commit -m "feat(app): add the admin page poller"
```

### Task 5: base dei controller delle schede, finestra in vista, ore

**Files:**
- Modify: `lib/features/admin/admin_providers.dart`, `test/support/admin_fakes.dart`
- Create: `lib/features/admin/admin_tab_controller.dart`, `lib/features/admin/admin_time.dart`
- Test: `test/features/admin/admin_tab_controller_test.dart`, `test/features/admin/admin_time_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/admin/admin_time_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/features/admin/admin_time.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  test('ore della pagina Amministrazione', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 10, 6, 9, 30);
    String label(DateTime at, [AppLocalizations? l]) =>
        adminTimeLabel(at, now, l ?? it);

    expect(label(now.subtract(const Duration(seconds: 20))), 'adesso');
    expect(label(now.add(const Duration(seconds: 20))), 'adesso',
        reason: 'un orologio un po\' avanti sul server');
    expect(label(now.subtract(const Duration(minutes: 3))), '3 min fa');
    expect(label(DateTime(2026, 10, 6, 7, 10)), '2 h fa');
    expect(label(DateTime(2026, 10, 5, 22, 53)), '5 ott, 22:53');
    expect(label(DateTime(2026, 10, 5, 22, 53), en), 'Oct 5, 22:53');
    // Poco dopo mezzanotte una voce di poco prima resta in minuti.
    expect(adminTimeLabel(DateTime(2026, 10, 5, 23, 50),
            DateTime(2026, 10, 6, 0, 10), it),
        '20 min fa');

    expect(adminClockLabel(DateTime(2026, 10, 6, 12, 3), it), '12:03');
  });
}
```

`test/features/admin/admin_tab_controller_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/admin/admin_tab_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

/// Risposte delle letture della scheda finta, in ordine: un numero, oppure
/// un errore da lanciare. Finite le risposte, il numero della lettura.
final _answers = <Object>[];
var _reads = 0;

class _TestController extends AdminTabController<int> {
  @override
  Duration get interval => const Duration(seconds: 5);

  @override
  Future<int> fetch() async {
    _reads++;
    final next = _answers.isEmpty ? _reads : _answers.removeAt(0);
    if (next is int) return next;
    throw next;
  }
}

final _testProvider =
    NotifierProvider.autoDispose<_TestController, AdminData<int>>(
        _TestController.new);

void main() {
  late FakeSessionController session;
  late FakeAdminForeground foreground;

  setUp(() {
    _answers.clear();
    _reads = 0;
    session = FakeSessionController(const SessionSignedIn(testAdmin));
    foreground = FakeAdminForeground();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(FakeAdminApi(),
          session: session, foreground: foreground),
      retry: (_, _) => null,
    );
    container.listen(_testProvider, (_, _) {});
    return container;
  }

  test('legge subito e ogni 5 s, con l\'ora dell\'ultima lettura', () {
    fakeAsync((async) {
      final container = makeContainer();
      expect(container.read(_testProvider).value, isNull);

      async.elapse(Duration.zero);
      final first = container.read(_testProvider);
      expect(first.value, 1);
      expect(first.error, isNull);
      expect(first.stale, isFalse);
      expect(first.updatedAt, isNotNull);

      async.elapse(const Duration(seconds: 5));
      expect(container.read(_testProvider).value, 2);
      expect(container.read(_testProvider).updatedAt!.difference(first.updatedAt!),
          const Duration(seconds: 5));
    }, initialTime: DateTime(2026, 10, 6, 12));
  });

  test('errore dopo i dati: restano i dati e l\'ora, con l\'errore', () {
    fakeAsync((async) {
      _answers.addAll([7, const ServerUnreachableException()]);
      final container = makeContainer();
      async.elapse(Duration.zero);
      final updatedAt = container.read(_testProvider).updatedAt;

      async.elapse(const Duration(seconds: 5));
      final data = container.read(_testProvider);
      expect(data.value, 7);
      expect(data.error, isA<ServerUnreachableException>());
      expect(data.stale, isTrue);
      expect(data.updatedAt, updatedAt);

      async.elapse(const Duration(seconds: 5));
      expect(container.read(_testProvider).stale, isFalse,
          reason: 'la lettura dopo è riuscita');
    });
  });

  test('errore senza dati: solo l\'errore', () {
    fakeAsync((async) {
      _answers.add(const ServerUnreachableException());
      final container = makeContainer();
      async.elapse(Duration.zero);

      final data = container.read(_testProvider);
      expect(data.value, isNull);
      expect(data.error, isA<ServerUnreachableException>());
      expect(data.stale, isFalse);
    });
  });

  test('un 403 fa rileggere l\'utente', () {
    fakeAsync((async) {
      _answers.add(const ForbiddenException());
      makeContainer();
      async.elapse(Duration.zero);

      expect(session.refreshUserCalls, 1);
    });
  });

  test('finestra nascosta: si ferma; tornata: legge subito', () {
    fakeAsync((async) {
      makeContainer();
      async.elapse(Duration.zero);
      expect(_reads, 1);

      foreground.set(false);
      async.elapse(const Duration(seconds: 30));
      expect(_reads, 1);

      foreground.set(true);
      async.elapse(Duration.zero);
      expect(_reads, 2);
    });
  });

  test('refresh legge subito; dopo un riavvio si rilegge da soli', () {
    fakeAsync((async) {
      final container = makeContainer();
      async.elapse(Duration.zero);
      expect(_reads, 1);

      unawaited(container.read(_testProvider.notifier).refresh());
      async.elapse(Duration.zero);
      expect(_reads, 2);

      container.read(adminEpochProvider.notifier).bump();
      async.elapse(Duration.zero);
      expect(_reads, 3);
    });
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/admin/admin_time_test.dart test/features/admin/admin_tab_controller_test.dart`
Expected: FAIL in compilazione (`admin_time.dart`, `admin_tab_controller.dart`, `adminTestOverrides` non esistono).

- [ ] **Step 3: implementa**

`lib/features/admin/admin_time.dart`:

```dart
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';

/// Ora di una voce della pagina Amministrazione (spec J §9.5): "adesso"
/// (meno di un minuto, anche nel futuro se l'orologio del server è avanti),
/// "5 min fa" (meno di un'ora), "2 h fa" (stesso giorno); prima, data e ora
/// nella lingua dell'app ("5 ott, 22:53").
String adminTimeLabel(DateTime at, DateTime now, AppLocalizations l) {
  final elapsed = now.difference(at);
  if (elapsed < const Duration(minutes: 1)) return l.inboxNow;
  if (elapsed < const Duration(hours: 1)) {
    return l.inboxMinutesAgo(elapsed.inMinutes);
  }
  final local = at.toLocal();
  final today = now.toLocal();
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    return l.inboxHoursAgo(elapsed.inHours);
  }
  return '${DateFormat.MMMd(l.localeName).format(local)}, '
      '${DateFormat.Hm(l.localeName).format(local)}';
}

/// "12:03": l'ora dell'ultimo aggiornamento riuscito.
String adminClockLabel(DateTime at, AppLocalizations l) =>
    DateFormat.Hm(l.localeName).format(at.toLocal());
```

`lib/features/admin/admin_providers.dart` diventa:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/admin_api.dart';
import '../auth/session_controller.dart';

final adminApiProvider =
    Provider<AdminApi>((ref) => AdminApi(ref.watch(jellyfinHttpProvider)));

/// L'utente collegato è amministratore di Jellyfin (spec J §7): vede la voce
/// "Amministrazione" e la pagina.
final isAdminProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session is SessionSignedIn && session.user.isAdministrator;
});

/// La finestra è in vista (spec J §10): falso quando è nascosta, per
/// esempio ridotta a icona. Le riletture della pagina si fermano finché è
/// falso. Vive finché la pagina la usa.
class AdminForeground extends Notifier<bool> {
  @override
  bool build() {
    final listener = AppLifecycleListener(
      onHide: () => state = false,
      onShow: () => state = true,
    );
    ref.onDispose(listener.dispose);
    return true;
  }
}

final adminForegroundProvider =
    NotifierProvider.autoDispose<AdminForeground, bool>(AdminForeground.new);

/// Cresce quando Jellyfin torna dopo un riavvio: la striscia e le schede
/// rileggono subito (spec J §9.2).
class AdminEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final adminEpochProvider = NotifierProvider<AdminEpoch, int>(AdminEpoch.new);
```

`lib/features/admin/admin_tab_controller.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../auth/session_controller.dart';
import 'admin_poller.dart';
import 'admin_providers.dart';

/// I dati di una scheda (spec J §10): il valore dell'ultima lettura
/// riuscita, l'errore dell'ultima lettura (se è fallita) e l'ora dell'ultima
/// lettura riuscita.
class AdminData<T> {
  const AdminData({this.value, this.error, this.updatedAt});

  final T? value;
  final Object? error;
  final DateTime? updatedAt;

  /// L'ultima lettura è fallita ma restano i dati di prima: la scheda
  /// mostra "Dati non aggiornati".
  bool get stale => value != null && error != null;
}

/// Base dei controller della pagina Amministrazione (spec J §10): legge con
/// [fetch] subito e ogni [interval] mentre la finestra è in vista, e di nuovo
/// quando Jellyfin torna da un riavvio. Un 403 fa rileggere l'utente: se non
/// è più admin, la pagina va via (§12).
abstract class AdminTabController<T> extends Notifier<AdminData<T>> {
  late AdminPoller _poller;

  /// Ogni quanto si rilegge.
  Duration get interval;

  /// Una lettura. Gli errori sono di solito [ApiException].
  Future<T> fetch();

  @override
  AdminData<T> build() {
    final poller = AdminPoller(read: _read, interval: interval);
    _poller = poller;
    ref.onDispose(poller.dispose);
    ref.listen<bool>(adminForegroundProvider, (_, visible) {
      if (visible) {
        poller.start();
      } else {
        poller.stop();
      }
    }, fireImmediately: true);
    ref.listen<int>(adminEpochProvider, (_, _) => unawaited(poller.now()));
    return AdminData<T>();
  }

  /// Rilegge subito ("Riprova", dopo un'azione).
  Future<void> refresh() => _poller.now();

  /// Cambia il ritmo della rilettura (Manutenzione, spec J §9.4).
  void setInterval(Duration value) => _poller.interval = value;

  Future<void> _read() async {
    try {
      final value = await fetch();
      if (!ref.mounted) return;
      state = AdminData<T>(value: value, updatedAt: clock.now());
    } on Object catch (error) {
      if (!ref.mounted) return;
      if (error is ForbiddenException) {
        unawaited(ref.read(sessionControllerProvider.notifier).refreshUser());
      }
      state = AdminData<T>(
          value: state.value, error: error, updatedAt: state.updatedAt);
    }
  }
}
```

In fondo a `test/support/admin_fakes.dart` aggiungi (e gli import `package:flutter_riverpod/misc.dart`, `package:wonderflix/features/admin/admin_providers.dart`, `package:wonderflix/features/auth/session_controller.dart` e `'fake_session_controller.dart'`):

```dart
/// Finestra in vista finta: niente `AppLifecycleListener`, la cambia il test.
class FakeAdminForeground extends AdminForeground {
  FakeAdminForeground([this.initial = true]);

  final bool initial;

  @override
  bool build() => initial;

  void set(bool visible) => state = visible;
}

/// Jellyfin finto, sessione di un admin e finestra in vista.
List<Override> adminTestOverrides(
  FakeAdminApi api, {
  FakeSessionController? session,
  FakeAdminForeground? foreground,
}) =>
    [
      adminApiProvider.overrideWithValue(api),
      sessionControllerProvider.overrideWith(() =>
          session ?? FakeSessionController(const SessionSignedIn(testAdmin))),
      adminForegroundProvider
          .overrideWith(() => foreground ?? FakeAdminForeground()),
    ];
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/admin/admin_time_test.dart test/features/admin/admin_tab_controller_test.dart test/features/admin/admin_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/features/admin/admin_providers.dart lib/features/admin/admin_tab_controller.dart lib/features/admin/admin_time.dart test/support/admin_fakes.dart test/features/admin/admin_tab_controller_test.dart test/features/admin/admin_time_test.dart
git commit -m "feat(app): add the base of the admin page controllers"
```

---

## Gruppo B — interfaccia

### Task 6: scheda Sessioni

**Files:**
- Create: `lib/features/admin/session_labels.dart`, `lib/features/admin/admin_widgets.dart`, `lib/features/admin/sessions_controller.dart`, `lib/features/admin/sessions_tab.dart`
- Test: `test/features/admin/session_labels_test.dart`, `test/features/admin/sessions_controller_test.dart`, `test/features/admin/sessions_tab_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/admin/session_labels_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/features/admin/session_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));

  group('metodo mostrato', () {
    SessionEntry session(PlayMethod method, [TranscodeInfo? transcode]) =>
        testSession('s', 'mario',
            playing: testMovie, playMethod: method, transcode: transcode);

    test('regole della spec J §9.3 (decisione 7 del piano)', () {
      const both = TranscodeInfo(isVideoDirect: true, isAudioDirect: true);
      const audio = TranscodeInfo(isVideoDirect: true);
      const video = TranscodeInfo(isAudioDirect: true);

      expect(displayMethod(session(PlayMethod.directPlay)), DisplayMethod.direct);
      expect(displayMethod(session(PlayMethod.directPlay, video)),
          DisplayMethod.direct);
      expect(displayMethod(session(PlayMethod.transcode, both)),
          DisplayMethod.remux, reason: 'remux dichiarato Transcode');
      expect(displayMethod(session(PlayMethod.directStream, audio)),
          DisplayMethod.transcode, reason: 'l\'audio si transcodifica');
      expect(displayMethod(session(PlayMethod.transcode, video)),
          DisplayMethod.transcode);
      expect(displayMethod(session(PlayMethod.directStream)), DisplayMethod.remux);
      expect(displayMethod(session(PlayMethod.transcode)),
          DisplayMethod.transcode);
      expect(displayMethod(session(PlayMethod.unknown)), DisplayMethod.unknown);

      expect(displayMethodLabel(it, DisplayMethod.direct), 'Diretta');
      expect(displayMethodLabel(it, DisplayMethod.remux), 'Remux');
      expect(displayMethodLabel(it, DisplayMethod.transcode), 'Transcodifica');
      expect(displayMethodLabel(it, DisplayMethod.unknown), isNull);
    });
  });

  test('titolo di quel che si guarda', () {
    expect(nowPlayingTitle(it, testMovie), 'Dune (2021)');
    expect(
        nowPlayingTitle(
            it, const NowPlaying(itemId: 'm', name: 'Senza anno', kind: NowPlayingKind.movie)),
        'Senza anno');
    const episode = NowPlaying(
      itemId: 'e1',
      name: 'Pilota',
      kind: NowPlayingKind.episode,
      seriesName: 'Lost',
      seasonNumber: 1,
      episodeNumber: 3,
    );
    expect(nowPlayingTitle(it, episode), 'Lost · S1:E3 · Pilota');
    expect(
        nowPlayingTitle(
            it,
            const NowPlaying(
                itemId: 'e2',
                name: 'Speciale',
                kind: NowPlayingKind.episode,
                seriesName: 'Lost',
                episodeNumber: 2)),
        'Lost · E2 · Speciale');
    expect(
        nowPlayingTitle(
            it,
            const NowPlaying(
                itemId: 'e3',
                name: 'Extra',
                kind: NowPlayingKind.episode,
                seriesName: 'Lost')),
        'Lost · Extra');
    expect(
        nowPlayingTitle(it, const NowPlaying(itemId: 'x', name: 'Un video')),
        'Un video');
  });

  test('client e dispositivo', () {
    final sessions = testSessions();
    expect(sessionDevice(sessions[0]), 'Jellyfin Android TV · FireTV Soggiorno');
    expect(
        sessionDevice(const SessionEntry(
            id: 's', userId: 'u', userName: 'x', deviceName: 'PC')),
        'PC');
  });

  test('riga della transcodifica e motivi', () {
    final transcode = testSessions()[0].transcode!;
    expect(transcodeLine(it, transcode), '→ H264 1080p · AAC · 8,2 Mbps · Software');
    expect(transcodeReasons(it, transcode.reasons),
        'codec video non supportato, codec audio non supportato');

    // Solo l'audio: niente video né accelerazione.
    expect(
        transcodeLine(
            it,
            const TranscodeInfo(
                isVideoDirect: true, audioCodec: 'aac', bitrate: 640000)),
        '→ AAC · 0,6 Mbps');
    expect(
        transcodeLine(
            it,
            const TranscodeInfo(
                videoCodec: 'hevc', hardwareAcceleration: 'vaapi')),
        '→ HEVC · VA-API');

    // Due motivi di bitrate diventano uno; uno sconosciuto resta com'è.
    expect(
        transcodeReasons(it, [
          'ContainerBitrateExceedsLimit',
          'VideoBitrateNotSupported',
          'SomethingNew',
        ]),
        'bitrate oltre il limite, SomethingNew');
  });

  test('accelerazione hardware', () {
    expect(hardwareLabel(it, null), 'Software');
    expect(hardwareLabel(it, 'none'), 'Software');
    expect(hardwareLabel(it, 'nvenc'), 'NVIDIA NVENC');
    expect(hardwareLabel(it, 'qsv'), 'Intel QSV');
    expect(hardwareLabel(it, 'boh'), 'boh');
  });

  test('stato dei watch party', () {
    expect(partyStateLabel(it, PartyState.playing), 'In riproduzione');
    expect(partyStateLabel(it, PartyState.paused), 'In pausa');
    expect(partyStateLabel(it, PartyState.waiting), 'In attesa');
    expect(partyStateLabel(it, PartyState.idle), 'Fermo');
    expect(partyStateLabel(it, PartyState.unknown), isNull);
  });
}
```

`test/features/admin/sessions_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/admin/sessions_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

void main() {
  late FakeAdminApi api;

  setUp(() => api = FakeAdminApi());

  ProviderContainer makeContainer({FakeSessionController? session}) {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(api, session: session),
      retry: (_, _) => null,
    );
    container.listen(sessionsControllerProvider, (_, _) {});
    return container;
  }

  test('chi guarda per nome, i collegati per attività, i party', () async {
    api
      ..sessionsValue = [
        testSession('a', 'zeno', playing: testMovie),
        testSession('b', 'Anna', playing: testMovie),
        testSession('c', 'vecchio', lastActivity: DateTime.utc(2026, 10, 6, 7)),
        testSession('d', 'recente', lastActivity: DateTime.utc(2026, 10, 6, 8)),
        testSession('e', 'senza ora'),
      ]
      ..partiesValue = testParties();
    final container = makeContainer();
    await pumpEventQueue();

    final snapshot = container.read(sessionsControllerProvider).value!;
    expect(snapshot.playing.map((s) => s.userName), ['Anna', 'zeno']);
    expect(snapshot.idle.map((s) => s.userName),
        ['recente', 'vecchio', 'senza ora']);
    expect(snapshot.parties.single.name, 'Serata Lost');
    expect(api.calls, containsAll(['sessions', 'parties']));
  });

  test('senza accesso ai watch party l\'elenco non si chiede', () async {
    api.sessionsValue = testSessions();
    const noParties = JellyfinUser(
      id: 'u1',
      name: 'Mario',
      isAdministrator: true,
      syncPlayAccess: SyncPlayAccess.none,
    );
    final container = makeContainer(
        session: FakeSessionController(const SessionSignedIn(noParties)));
    await pumpEventQueue();

    expect(container.read(sessionsControllerProvider).value!.parties, isEmpty);
    expect(api.count('parties'), 0);
  });

  test('un errore dei party è un errore della scheda', () async {
    api
      ..sessionsValue = testSessions()
      ..partiesError = const ForbiddenException();
    final session = FakeSessionController(const SessionSignedIn(testAdmin));
    final container = makeContainer(session: session);
    await pumpEventQueue();

    expect(container.read(sessionsControllerProvider).error,
        isA<ForbiddenException>());
    expect(session.refreshUserCalls, 1);
  });
}
```

`test/features/admin/sessions_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/sessions_tab.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;

  setUp(() => api = FakeAdminApi());

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: SessionsTab()),
        overrides: adminTestOverrides(api));
    await tester.pumpAndSettle();
  }

  testWidgets('chi guarda, chi è collegato e i party', (tester) async {
    api
      ..sessionsValue = testSessions()
      ..partiesValue = testParties();
    await pumpTab(tester);

    // Episodio transcodificato su FireTV.
    expect(find.text('viviroby'), findsOneWidget);
    expect(find.text('Jellyfin Android TV · FireTV Soggiorno'), findsOneWidget);
    expect(find.text('Lost · S1:E3 · Pilota'), findsOneWidget);
    expect(find.text('12:34 / 42:36'), findsOneWidget);
    expect(find.text('Transcodifica'), findsOneWidget);
    expect(find.text('→ H264 1080p · AAC · 8,2 Mbps · Software'), findsOneWidget);
    expect(find.text('codec video non supportato, codec audio non supportato'),
        findsOneWidget);

    // Film in remux, in pausa: niente riga della transcodifica.
    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text('Remux'), findsOneWidget);
    expect(find.byKey(const Key('session-paused-s2')), findsOneWidget);
    expect(find.byKey(const Key('session-paused-s1')), findsNothing);
    expect(find.textContaining('→ HEVC'), findsNothing);

    // Collegato senza riprodurre.
    expect(find.text('davide.sidoti'), findsOneWidget);
    expect(find.text('WonderFlix · nocturne'), findsOneWidget);
    expect(find.textContaining('attivo '), findsOneWidget);

    // Il party.
    expect(find.text('Serata Lost'), findsOneWidget);
    expect(find.text('viviroby, Mario'), findsOneWidget);

    // La chiave API di Seerr non c'è.
    expect(find.text('Seerr'), findsNothing);
  });

  testWidgets('nessuno: tre testi vuoti', (tester) async {
    await pumpTab(tester);

    expect(find.text('Nessuno sta guardando'), findsOneWidget);
    expect(find.text('Nessun altro collegato'), findsOneWidget);
    expect(find.text('Nessun watch party in corso'), findsOneWidget);
  });

  testWidgets('primo caricamento fallito: errore e Riprova', (tester) async {
    api.sessionsError = const ServerUnreachableException();
    await pumpTab(tester);

    expect(find.text('Riprova'), findsOneWidget);

    api.sessionsError = null;
    api.sessionsValue = testSessions();
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('rilettura fallita: restano i dati con "Dati non aggiornati"',
      (tester) async {
    api.sessionsValue = testSessions();
    await pumpTab(tester);
    expect(find.textContaining('Dati non aggiornati'), findsNothing);

    api.sessionsError = const ServerUnreachableException();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.textContaining('Dati non aggiornati'), findsOneWidget);
    expect(find.text('viviroby'), findsOneWidget);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/admin/session_labels_test.dart test/features/admin/sessions_controller_test.dart test/features/admin/sessions_tab_test.dart`
Expected: FAIL in compilazione (i file non esistono).

- [ ] **Step 3: implementa le etichette**

`lib/features/admin/session_labels.dart`:

```dart
import 'package:intl/intl.dart';

import '../../core/jellyfin/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Bit in un megabit.
const _bitsPerMegabit = 1000000;

/// Come si vede una riproduzione nella scheda Sessioni (spec J §9.3).
enum DisplayMethod { direct, remux, transcode, unknown }

/// `DirectPlay` è sempre diretta. Con `TranscodingInfo` decide lui: video e
/// audio diretti sono un remux (anche se il client dichiara `Transcode`),
/// altrimenti è una transcodifica. Senza, decide il metodo dichiarato.
DisplayMethod displayMethod(SessionEntry session) {
  if (session.playMethod == PlayMethod.directPlay) return DisplayMethod.direct;
  final transcode = session.transcode;
  if (transcode != null) {
    return transcode.isVideoDirect && transcode.isAudioDirect
        ? DisplayMethod.remux
        : DisplayMethod.transcode;
  }
  return switch (session.playMethod) {
    PlayMethod.directStream => DisplayMethod.remux,
    PlayMethod.transcode => DisplayMethod.transcode,
    _ => DisplayMethod.unknown,
  };
}

String? displayMethodLabel(AppLocalizations l, DisplayMethod method) =>
    switch (method) {
      DisplayMethod.direct => l.adminMethodDirect,
      DisplayMethod.remux => l.adminMethodRemux,
      DisplayMethod.transcode => l.adminMethodTranscode,
      DisplayMethod.unknown => null,
    };

/// "Dune (2021)", "Lost · S1:E3 · Pilota", oppure il nome.
String nowPlayingTitle(AppLocalizations l, NowPlaying item) {
  switch (item.kind) {
    case NowPlayingKind.movie:
      final year = item.year;
      return year == null ? item.name : l.adminMovieYear(item.name, '$year');
    case NowPlayingKind.episode:
      final series = item.seriesName;
      if (series == null) return item.name;
      final episode = item.episodeNumber;
      if (episode == null) return l.adminEpisodeNoCode(series, item.name);
      final season = item.seasonNumber;
      final code = season == null ? 'E$episode' : 'S$season:E$episode';
      return l.adminEpisodeTitle(series, code, item.name);
    case NowPlayingKind.other:
      return item.name;
  }
}

/// "Jellyfin Android TV · FireTV Soggiorno" (solo le parti note).
String sessionDevice(SessionEntry session) =>
    [session.client, session.deviceName].whereType<String>().join(' · ');

/// "→ H264 1080p · AAC · 8,2 Mbps · Software": cosa si transcodifica, il
/// bitrate e, se si transcodifica il video, l'accelerazione.
String transcodeLine(AppLocalizations l, TranscodeInfo info) {
  final parts = <String>[];
  final video = info.videoCodec;
  if (!info.isVideoDirect && video != null) {
    final height = info.height;
    parts.add(height == null
        ? video.toUpperCase()
        : '${video.toUpperCase()} ${height}p');
  }
  final audio = info.audioCodec;
  if (!info.isAudioDirect && audio != null) parts.add(audio.toUpperCase());
  final bitrate = info.bitrate;
  if (bitrate != null && bitrate > 0) {
    parts.add(l.adminBitrate(
        NumberFormat('0.0', l.localeName).format(bitrate / _bitsPerMegabit)));
  }
  if (!info.isVideoDirect) {
    parts.add(hardwareLabel(l, info.hardwareAcceleration));
  }
  return '→ ${parts.join(' · ')}';
}

/// Nome dell'accelerazione hardware; senza, "Software".
String hardwareLabel(AppLocalizations l, String? type) =>
    switch (type?.toLowerCase()) {
      null || 'none' => l.adminSoftware,
      'qsv' => 'Intel QSV',
      'nvenc' => 'NVIDIA NVENC',
      'amf' => 'AMD AMF',
      'vaapi' => 'VA-API',
      'videotoolbox' => 'VideoToolbox',
      'v4l2m2m' => 'V4L2',
      'rkmpp' => 'Rockchip MPP',
      _ => type!,
    };

/// I motivi della transcodifica tradotti, senza doppioni; uno sconosciuto
/// resta come lo scrive Jellyfin.
String transcodeReasons(AppLocalizations l, List<String> reasons) =>
    {for (final reason in reasons) _reasonLabel(l, reason)}.join(', ');

String _reasonLabel(AppLocalizations l, String reason) => switch (reason) {
      'ContainerNotSupported' => l.adminReasonContainer,
      'VideoCodecNotSupported' ||
      'VideoCodecTagNotSupported' =>
        l.adminReasonVideoCodec,
      'AudioCodecNotSupported' ||
      'AudioProfileNotSupported' =>
        l.adminReasonAudioCodec,
      'SubtitleCodecNotSupported' => l.adminReasonSubtitles,
      'VideoProfileNotSupported' => l.adminReasonVideoProfile,
      'VideoLevelNotSupported' => l.adminReasonVideoLevel,
      'VideoResolutionNotSupported' => l.adminReasonResolution,
      'VideoBitDepthNotSupported' => l.adminReasonBitDepth,
      'VideoRangeTypeNotSupported' => l.adminReasonVideoRange,
      'AudioChannelsNotSupported' => l.adminReasonAudioChannels,
      'ContainerBitrateExceedsLimit' ||
      'VideoBitrateNotSupported' ||
      'AudioBitrateNotSupported' =>
        l.adminReasonBitrate,
      'AudioIsExternal' => l.adminReasonExternalAudio,
      _ => reason,
    };

/// Lo stato di un watch party; `null` se Jellyfin ne dice uno sconosciuto.
String? partyStateLabel(AppLocalizations l, PartyState state) =>
    switch (state) {
      PartyState.playing => l.adminPartyPlaying,
      PartyState.paused => l.adminPartyPaused,
      PartyState.waiting => l.adminPartyWaiting,
      PartyState.idle => l.adminPartyIdle,
      PartyState.unknown => null,
    };
```

- [ ] **Step 4: implementa i pezzi comuni della pagina**

`lib/features/admin/admin_widgets.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'admin_time.dart';

/// Titolo di una sezione di una scheda ("In riproduzione", "Collegati"…).
class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      );
}

/// Il testo di una sezione vuota.
class AdminEmptyText extends StatelessWidget {
  const AdminEmptyText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: WfColors.creamMuted));
}

/// Un utente: l'iniziale in un cerchio, il nome e un dettaglio (client e
/// dispositivo).
class AdminUserLine extends StatelessWidget {
  const AdminUserLine({super.key, required this.name, this.detail = ''});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: WfColors.gold,
          child: Text(initial,
              style: const TextStyle(
                  color: WfColors.bg, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(detail,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
        ],
      ],
    );
  }
}

/// "Dati non aggiornati · ultimo aggiornamento 12:03" (spec J §10).
class AdminStaleNote extends StatelessWidget {
  const AdminStaleNote({super.key, required this.updatedAt});

  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(LucideIcons.circleAlert, size: 14, color: WfColors.gold),
          const SizedBox(width: 8),
          Flexible(
            child: Text(l.adminStale(adminClockLabel(updatedAt, l)),
                style: const TextStyle(color: WfColors.gold, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: implementa il controller**

`lib/features/admin/sessions_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/admin_models.dart';
import '../../core/jellyfin/auth_models.dart';
import '../watch_party/watch_party_providers.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';

/// Il contenuto della scheda Sessioni (spec J §9.3).
class SessionsSnapshot {
  const SessionsSnapshot({
    this.playing = const [],
    this.idle = const [],
    this.parties = const [],
  });

  /// Chi guarda va per nome (senza badare alle maiuscole), chi è solo
  /// collegato dal più recente.
  factory SessionsSnapshot.from(
      List<SessionEntry> sessions, List<PartyGroup> parties) {
    final playing = [
      for (final session in sessions)
        if (session.nowPlaying != null) session,
    ]..sort((a, b) =>
        a.userName.toLowerCase().compareTo(b.userName.toLowerCase()));
    final never = DateTime.utc(0);
    final idle = [
      for (final session in sessions)
        if (session.nowPlaying == null) session,
    ]..sort((a, b) =>
        (b.lastActivity ?? never).compareTo(a.lastActivity ?? never));
    return SessionsSnapshot(playing: playing, idle: idle, parties: parties);
  }

  final List<SessionEntry> playing;
  final List<SessionEntry> idle;
  final List<PartyGroup> parties;
}

/// Sessioni e watch party, riletti ogni 5 s.
class SessionsController extends AdminTabController<SessionsSnapshot> {
  static const every = Duration(seconds: 5);

  @override
  Duration get interval => every;

  @override
  Future<SessionsSnapshot> fetch() async {
    final api = ref.read(adminApiProvider);
    // Senza accesso ai watch party Jellyfin rifiuterebbe l'elenco.
    final withParties = ref.read(syncPlayAccessProvider) != SyncPlayAccess.none;
    final results = await Future.wait<Object>(
      [api.sessions(), if (withParties) api.partyGroups()],
      eagerError: true,
    );
    return SessionsSnapshot.from(
      results[0] as List<SessionEntry>,
      withParties ? results[1] as List<PartyGroup> : const [],
    );
  }
}

final sessionsControllerProvider = NotifierProvider.autoDispose<
    SessionsController, AdminData<SessionsSnapshot>>(SessionsController.new);
```

- [ ] **Step 6: implementa la scheda**

`lib/features/admin/sessions_tab.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';
import 'session_labels.dart';
import 'sessions_controller.dart';

/// La scheda Sessioni (spec J §9.3): chi guarda, chi è collegato, i watch
/// party.
class SessionsTab extends ConsumerStatefulWidget {
  const SessionsTab({super.key});

  @override
  ConsumerState<SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends ConsumerState<SessionsTab> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(sessionsControllerProvider);
    final snapshot = data.value;
    if (snapshot == null) {
      final error = data.error;
      if (error == null) return const LoadingView();
      return ErrorView(
        error: error,
        onRetry: () =>
            unawaited(ref.read(sessionsControllerProvider.notifier).refresh()),
      );
    }
    final now = clock.now();
    final updatedAt = data.updatedAt;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      children: [
        if (data.stale && updatedAt != null) AdminStaleNote(updatedAt: updatedAt),
        AdminSectionTitle(title: l.adminSessionsPlaying),
        if (snapshot.playing.isEmpty)
          AdminEmptyText(text: l.adminSessionsNobodyPlaying)
        else
          for (final session in snapshot.playing)
            PlayingSessionCard(
                key: ValueKey('playing-${session.id}'), session: session),
        AdminSectionTitle(title: l.adminSessionsIdle),
        if (snapshot.idle.isEmpty)
          AdminEmptyText(text: l.adminSessionsNobodyIdle)
        else
          for (final session in snapshot.idle)
            IdleSessionRow(
                key: ValueKey('idle-${session.id}'), session: session, now: now),
        AdminSectionTitle(title: l.adminSessionsParties),
        if (snapshot.parties.isEmpty)
          AdminEmptyText(text: l.adminSessionsNoParties)
        else
          for (final party in snapshot.parties)
            PartyRow(key: ValueKey('party-${party.id}'), party: party),
      ],
    );
  }
}

/// Una sessione che sta riproducendo: locandina, utente, titolo,
/// avanzamento e metodo.
class PlayingSessionCard extends ConsumerWidget {
  const PlayingSessionCard({super.key, required this.session});

  static const posterWidth = 64.0;
  static const posterHeight = 96.0;

  /// Larghezza della locandina chiesta al server (il doppio, per gli schermi
  /// ad alta densità).
  static const _posterRequestWidth = 128;

  final SessionEntry session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final item = session.nowPlaying!;
    final runtime = item.runtime;
    final position = session.position;
    final progress = runtime == null || runtime == Duration.zero
        ? 0.0
        : (position.inMilliseconds / runtime.inMilliseconds).clamp(0.0, 1.0);
    final method = displayMethod(session);
    final methodLabel = displayMethodLabel(l, method);
    final transcode = session.transcode;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WfColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WfColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: posterWidth,
              height: posterHeight,
              child: WfImage(
                image: ref.watch(imageUrlsProvider).primaryOf(item.imageItemId,
                    maxWidth: _posterRequestWidth),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminUserLine(
                    name: session.userName, detail: sessionDevice(session)),
                const SizedBox(height: 8),
                Text(nowPlayingTitle(l, item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (session.isPaused) ...[
                      Icon(LucideIcons.pause,
                          key: Key('session-paused-${session.id}'),
                          size: 14,
                          color: WfColors.creamMuted),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        color: WfColors.gold,
                        backgroundColor: WfColors.surfaceHigh,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                        runtime == null
                            ? formatClock(position)
                            : '${formatClock(position)} / ${formatClock(runtime)}',
                        style: muted),
                  ],
                ),
                if (methodLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(methodLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: method == DisplayMethod.transcode
                            ? WfColors.gold
                            : WfColors.cream,
                      )),
                ],
                if (method == DisplayMethod.transcode && transcode != null) ...[
                  const SizedBox(height: 4),
                  Text(transcodeLine(l, transcode), style: muted),
                  if (transcode.reasons.isNotEmpty)
                    Text(transcodeReasons(l, transcode.reasons), style: muted),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una sessione collegata senza riprodurre.
class IdleSessionRow extends StatelessWidget {
  const IdleSessionRow({super.key, required this.session, required this.now});

  final SessionEntry session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final last = session.lastActivity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: AdminUserLine(
                name: session.userName, detail: sessionDevice(session)),
          ),
          if (last != null)
            Text(l.adminActive(adminTimeLabel(last, now, l)),
                style: const TextStyle(color: WfColors.creamMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Un watch party in corso: nome, stato e partecipanti.
class PartyRow extends StatelessWidget {
  const PartyRow({super.key, required this.party});

  final PartyGroup party;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = partyStateLabel(l, party.state);
    const muted = TextStyle(color: WfColors.creamMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(LucideIcons.users, size: 18, color: WfColors.gold),
          const SizedBox(width: 10),
          Text(party.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (state != null) ...[
            const SizedBox(width: 10),
            Text(state, style: muted),
          ],
          const SizedBox(width: 16),
          Expanded(
            child: Text(party.participants.join(', '),
                overflow: TextOverflow.ellipsis, style: muted),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: verifica che passino**

Run: `flutter test test/features/admin/session_labels_test.dart test/features/admin/sessions_controller_test.dart test/features/admin/sessions_tab_test.dart`
Expected: PASS.

- [ ] **Step 8: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/features/admin/session_labels.dart lib/features/admin/admin_widgets.dart lib/features/admin/sessions_controller.dart lib/features/admin/sessions_tab.dart test/features/admin/session_labels_test.dart test/features/admin/sessions_controller_test.dart test/features/admin/sessions_tab_test.dart
git commit -m "feat(app): show who is watching in the admin page"
```

### Task 7: striscia del server e riavvio

**Files:**
- Create: `lib/features/admin/restart_controller.dart`, `lib/features/admin/restart_dialog.dart`, `lib/features/admin/server_strip.dart`
- Test: `test/features/admin/restart_controller_test.dart`, `test/features/admin/restart_dialog_test.dart`, `test/features/admin/server_strip_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/admin/restart_controller_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/admin/restart_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

void main() {
  late FakeAdminApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAdminApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(api, session: session),
      retry: (_, _) => null,
    );
    container.listen(restartControllerProvider, (_, _) {});
    return container;
  }

  RestartController controller(ProviderContainer container) =>
      container.read(restartControllerProvider.notifier);

  test('giù e poi su: tornato, e le schede rileggono', () {
    fakeAsync((async) {
      api.upAnswers.addAll([true, false, false, true]);
      final container = makeContainer();
      var epoch = 0;
      container.listen<int>(adminEpochProvider, (_, next) => epoch = next);
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.flushMicrotasks();
      expect(api.calls, ['restart']);
      expect(container.read(restartControllerProvider), RestartPhase.waiting);

      // 3 s: ancora su (non è caduto); 6 e 9 s: giù.
      async.elapse(const Duration(seconds: 9));
      expect(outcome, isNull);
      // 12 s: di nuovo su dopo essere caduto.
      async.elapse(const Duration(seconds: 3));
      expect(outcome, RestartOutcome.back);
      expect(container.read(restartControllerProvider), RestartPhase.idle);
      expect(epoch, 1);
      expect(api.count('up'), 4);
    });
  });

  test('mai caduto in 60 s: tornato', () {
    fakeAsync((async) {
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.elapse(const Duration(seconds: 57));
      expect(outcome, isNull);
      async.elapse(const Duration(seconds: 3));
      expect(outcome, RestartOutcome.back);
    });
  });

  test('giù per 3 minuti: non risponde ancora; Ricontrolla aspetta di nuovo',
      () {
    fakeAsync((async) {
      api.upAnswers.addAll(List.filled(60, false));
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.elapse(const Duration(seconds: 177));
      expect(outcome, isNull);
      async.elapse(const Duration(seconds: 3));
      expect(outcome, RestartOutcome.timedOut);
      expect(container.read(restartControllerProvider), RestartPhase.timedOut);

      RestartOutcome? again;
      unawaited(controller(container).recheck().then((o) => again = o));
      expect(container.read(restartControllerProvider), RestartPhase.waiting);
      async.elapse(const Duration(seconds: 3));
      expect(again, RestartOutcome.back,
          reason: 'era già giù: la prima risposta basta');
    });
  });

  test('errore di rete sul POST: il riavvio è partito', () {
    fakeAsync((async) {
      api.restartError = const ServerUnreachableException();
      final container = makeContainer();

      unawaited(controller(container).restart());
      async.flushMicrotasks();
      expect(container.read(restartControllerProvider), RestartPhase.waiting);
      async.elapse(const Duration(seconds: 60));
    });
  });

  test('403 sul POST: non riuscito, e si rilegge l\'utente', () {
    fakeAsync((async) {
      api.restartError = const ForbiddenException();
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.flushMicrotasks();
      expect(outcome, RestartOutcome.failed);
      expect(container.read(restartControllerProvider), RestartPhase.idle);
      expect(session.refreshUserCalls, 1);
      expect(api.count('up'), 0);
    });
  });

  test('altro errore sul POST: non riuscito', () {
    fakeAsync((async) {
      api.restartError = const ServerErrorException(500);
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.flushMicrotasks();
      expect(outcome, RestartOutcome.failed);
      expect(session.refreshUserCalls, 0);
    });
  });

  test('502/503/504 di nginx sul POST: il riavvio è partito', () {
    for (final status in [502, 503, 504]) {
      fakeAsync((async) {
        api.restartError = ServerErrorException(status);
        final container = makeContainer();

        unawaited(controller(container).restart());
        async.flushMicrotasks();
        expect(container.read(restartControllerProvider), RestartPhase.waiting,
            reason: '$status');
        async.elapse(const Duration(seconds: 60));
      });
    }
  });

  test('pagina chiusa durante l\'attesa: l\'attesa si ferma', () {
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: adminTestOverrides(api, session: session),
        retry: (_, _) => null,
      );
      container.listen(restartControllerProvider, (_, _) {});
      RestartOutcome? outcome;

      unawaited(container
          .read(restartControllerProvider.notifier)
          .restart()
          .then((o) => outcome = o));
      async.elapse(const Duration(seconds: 3));
      container.dispose();
      async.elapse(const Duration(seconds: 60));

      expect(outcome, RestartOutcome.cancelled);
      expect(api.count('up'), 1);
    });
  });
}
```

`test/features/admin/restart_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/restart_dialog.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;
  bool? result;

  setUp(() {
    api = FakeAdminApi();
    result = null;
  });

  Future<void> openDialog(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showRestartDialog(context),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: adminTestOverrides(api),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  testWidgets('chi sta guardando, con titolo', (tester) async {
    api.sessionsValue = testSessions();
    await openDialog(tester);

    expect(find.text('Riavviare Jellyfin?'), findsOneWidget);
    expect(find.text('2 persone stanno guardando:'), findsOneWidget);
    expect(find.text('viviroby — Lost · S1:E3 · Pilota'), findsOneWidget);
    expect(find.text('lucia — Dune (2021)'), findsOneWidget);
    expect(find.text('Il riavvio interrompe la visione e i watch party.'),
        findsOneWidget);
    expect(find.textContaining('davide.sidoti'), findsNothing,
        reason: 'è collegato ma non guarda');
    expect(api.count('sessions'), 1);
  });

  testWidgets('una persona: singolare', (tester) async {
    api.sessionsValue = [testSession('a', 'anna', playing: testMovie)];
    await openDialog(tester);

    expect(find.text('1 persona sta guardando:'), findsOneWidget);
  });

  testWidgets('nessuno', (tester) async {
    api.sessionsValue = [testSession('a', 'anna')];
    await openDialog(tester);

    expect(find.text('Nessuno sta guardando.'), findsOneWidget);
    expect(find.textContaining('interrompe'), findsNothing);
  });

  testWidgets('sessioni illeggibili', (tester) async {
    api.sessionsError = const ServerUnreachableException();
    await openDialog(tester);

    expect(find.text('Non so chi sta guardando.'), findsOneWidget);
  });

  testWidgets('Annulla: no; Riavvia: sì', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Riavvia'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
```

`test/features/admin/server_strip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/server_strip.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAdminApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  Future<void> pumpStrip(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: Padding(padding: EdgeInsets.all(16), child: ServerStrip())),
      overrides: adminTestOverrides(api, session: session),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nome e versione; il sistema solo se Jellyfin lo dice',
      (tester) async {
    await pumpStrip(tester);

    expect(find.text('WonderFlix'), findsOneWidget);
    expect(find.text('Jellyfin 10.11.9'), findsOneWidget);
    expect(find.byKey(const Key('pending-restart')), findsNothing);
    expect(find.text('Riavvia'), findsOneWidget);
  });

  testWidgets('rilegge l\'utente all\'apertura e a ogni lettura del server',
      (tester) async {
    await pumpStrip(tester);
    expect(session.refreshUserCalls, 1);

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(session.refreshUserCalls, 2);
  });

  testWidgets('con il sistema e il riavvio necessario', (tester) async {
    api.serverInfoValue = const ServerInfo(
      name: 'WonderFlix',
      version: '10.11.9',
      operatingSystem: 'Linux',
      hasPendingRestart: true,
    );
    await pumpStrip(tester);

    expect(find.text('Jellyfin 10.11.9 · Linux'), findsOneWidget);
    expect(find.byKey(const Key('pending-restart')), findsOneWidget);
    expect(find.textContaining('Riavvio necessario'), findsOneWidget);
  });

  testWidgets('informazioni illeggibili: errore e Riprova', (tester) async {
    api.serverInfoError = const ServerUnreachableException();
    await pumpStrip(tester);

    expect(find.text('Riprova'), findsOneWidget);

    api.serverInfoError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('WonderFlix'), findsOneWidget);
  });

  testWidgets('Riavvia: conferma, attesa e "Jellyfin è tornato"',
      (tester) async {
    api.upAnswers.addAll([false, true]);
    await pumpStrip(tester);

    await tester.tap(find.text('Riavvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Riavvia'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.calls, contains('restart'));
    expect(find.text('Riavvio in corso…'), findsOneWidget);

    // 3 s: giù; 6 s: di nuovo su.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Jellyfin è tornato'), findsOneWidget);
    expect(find.text('Riavvio in corso…'), findsNothing);
    expect(api.count('info'), greaterThanOrEqualTo(2),
        reason: 'la striscia si rilegge al ritorno');
  });

  testWidgets('Annulla nella conferma: nessun riavvio', (tester) async {
    await pumpStrip(tester);

    await tester.tap(find.text('Riavvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(api.calls, isNot(contains('restart')));
  });

  testWidgets('3 minuti senza risposta: "non risponde ancora" e Ricontrolla',
      (tester) async {
    api.upAnswers.addAll(List.filled(60, false));
    await pumpStrip(tester);

    await tester.tap(find.text('Riavvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Riavvia'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 180));
    await tester.pump();

    expect(find.text('Jellyfin non risponde ancora'), findsOneWidget);
    expect(find.text('Ricontrolla'), findsOneWidget);

    await tester.tap(find.text('Ricontrolla'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Jellyfin è tornato'), findsOneWidget);
  });

  testWidgets('riavvio rifiutato: "Riavvio non riuscito"', (tester) async {
    api.restartError = const ServerErrorException(500);
    await pumpStrip(tester);

    await tester.tap(find.text('Riavvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Riavvia'));
    await tester.pumpAndSettle();

    expect(find.text('Riavvio non riuscito'), findsOneWidget);
    expect(find.text('Riavvia'), findsOneWidget);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/admin/restart_controller_test.dart test/features/admin/restart_dialog_test.dart test/features/admin/server_strip_test.dart`
Expected: FAIL in compilazione (i file non esistono).

- [ ] **Step 3: implementa il riavvio**

`lib/features/admin/restart_controller.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../auth/session_controller.dart';
import 'admin_providers.dart';

/// A che punto è il riavvio di Jellyfin (spec J §9.2).
enum RestartPhase { idle, sending, waiting, timedOut }

/// Com'è finito un riavvio, per l'avviso della pagina.
enum RestartOutcome { back, timedOut, failed, cancelled }

/// Riavvia Jellyfin e aspetta che torni. Vive con la pagina: chiudendola,
/// l'attesa si ferma senza avvisi.
class RestartController extends Notifier<RestartPhase> {
  /// Ogni quanto si chiede a Jellyfin se è tornato.
  static const pollEvery = Duration(seconds: 3);

  /// Se in questo tempo Jellyfin non è mai sembrato giù, conta come
  /// tornato: il riavvio è stato più veloce delle domande.
  static const settleAfter = Duration(seconds: 60);

  /// Oltre, "Jellyfin non risponde ancora".
  static const giveUpAfter = Duration(minutes: 3);

  /// Cresce a ogni attesa e alla chiusura: un'attesa vecchia si ferma.
  int _wait = 0;

  @override
  RestartPhase build() {
    ref.onDispose(() => _wait++);
    return RestartPhase.idle;
  }

  /// Risposte di nginx quando Jellyfin chiude la connessione fermandosi.
  static const _gatewayStatuses = {502, 503, 504};

  /// Chiede il riavvio e aspetta il ritorno. Una richiesta persa per rete, o
  /// un 502/503/504 di nginx, conta come riavvio partito: Jellyfin può
  /// fermarsi prima di rispondere.
  Future<RestartOutcome> restart() async {
    if (state == RestartPhase.sending || state == RestartPhase.waiting) {
      return RestartOutcome.cancelled;
    }
    state = RestartPhase.sending;
    try {
      await ref.read(adminApiProvider).restart();
    } on ApiException catch (error) {
      if (!_meansStarted(error)) {
        if (!ref.mounted) return RestartOutcome.cancelled;
        if (error is ForbiddenException) {
          unawaited(ref.read(sessionControllerProvider.notifier).refreshUser());
        }
        state = RestartPhase.idle;
        return RestartOutcome.failed;
      }
    }
    if (!ref.mounted) return RestartOutcome.cancelled;
    return _waitForServer(sawDown: false);
  }

  static bool _meansStarted(ApiException error) =>
      error is ServerUnreachableException ||
      (error is ServerErrorException &&
          _gatewayStatuses.contains(error.statusCode));

  /// "Ricontrolla" dopo [RestartPhase.timedOut]: Jellyfin era già giù, la
  /// prima risposta basta.
  Future<RestartOutcome> recheck() {
    if (state != RestartPhase.timedOut) {
      return Future.value(RestartOutcome.cancelled);
    }
    return _waitForServer(sawDown: true);
  }

  Future<RestartOutcome> _waitForServer({required bool sawDown}) async {
    final wait = ++_wait;
    state = RestartPhase.waiting;
    final api = ref.read(adminApiProvider);
    final started = clock.now();
    var down = sawDown;
    while (true) {
      await Future<void>.delayed(pollEvery);
      if (wait != _wait) return RestartOutcome.cancelled;
      bool up;
      try {
        up = await api.isServerUp();
      } on Object {
        up = false;
      }
      if (wait != _wait) return RestartOutcome.cancelled;
      final elapsed = clock.now().difference(started);
      if (up && (down || elapsed >= settleAfter)) {
        state = RestartPhase.idle;
        ref.read(adminEpochProvider.notifier).bump();
        return RestartOutcome.back;
      }
      if (!up) down = true;
      if (elapsed >= giveUpAfter) {
        state = RestartPhase.timedOut;
        return RestartOutcome.timedOut;
      }
    }
  }
}

final restartControllerProvider =
    NotifierProvider.autoDispose<RestartController, RestartPhase>(
        RestartController.new);
```

- [ ] **Step 4: implementa la conferma**

`lib/features/admin/restart_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import 'admin_providers.dart';
import 'session_labels.dart';

/// Chiede conferma del riavvio (spec J §9.2); `true` solo con "Riavvia".
Future<bool> showRestartDialog(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final confirmed = await showWfDialog<bool>(
    context,
    semanticLabel: l.adminRestartTitle,
    builder: (_) => const RestartDialog(),
  );
  return confirmed ?? false;
}

/// La conferma del riavvio: all'apertura rilegge le sessioni e dice chi sta
/// guardando, così i dati sono freschi.
class RestartDialog extends ConsumerStatefulWidget {
  const RestartDialog({super.key});

  @override
  ConsumerState<RestartDialog> createState() => _RestartDialogState();
}

class _RestartDialogState extends ConsumerState<RestartDialog> {
  late final Future<List<SessionEntry>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(adminApiProvider).sessions();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.adminRestartTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        FutureBuilder<List<SessionEntry>>(
          future: _sessions,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2));
            }
            final sessions = snapshot.data;
            if (sessions == null) return Text(l.adminRestartUnknown);
            final viewers = [
              for (final session in sessions)
                if (session.nowPlaying != null) session,
            ];
            if (viewers.isEmpty) return Text(l.adminRestartNobody);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.adminRestartViewers(viewers.length)),
                const SizedBox(height: 8),
                for (final viewer in viewers)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                        l.adminViewer(viewer.userName,
                            nowPlayingTitle(l, viewer.nowPlaying!)),
                        style: const TextStyle(color: WfColors.creamMuted)),
                  ),
                const SizedBox(height: 8),
                Text(l.adminRestartInterrupts),
              ],
            );
          },
        ),
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
              style: FilledButton.styleFrom(
                backgroundColor: WfColors.error,
                foregroundColor: WfColors.cream,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.adminRestart),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: implementa la striscia**

`lib/features/admin/server_strip.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../auth/session_controller.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';
import 'admin_widgets.dart';
import 'restart_controller.dart';
import 'restart_dialog.dart';

/// Le informazioni del server, rilette ogni 60 s (spec J §9.2). A ogni
/// lettura (all'apertura della pagina e ogni 60 s) rilegge anche l'utente:
/// le letture della pagina non chiedono di essere admin e non danno 403, e
/// chi perde i permessi va scoperto così (spec J §12).
class ServerInfoController extends AdminTabController<ServerInfo> {
  static const every = Duration(seconds: 60);

  @override
  Duration get interval => every;

  @override
  Future<ServerInfo> fetch() {
    unawaited(ref.read(sessionControllerProvider.notifier).refreshUser());
    return ref.read(adminApiProvider).serverInfo();
  }
}

final serverInfoControllerProvider =
    NotifierProvider.autoDispose<ServerInfoController, AdminData<ServerInfo>>(
        ServerInfoController.new);

/// La striscia in cima alla pagina Amministrazione: nome e versione del
/// server, "Riavvio necessario" e Riavvia.
class ServerStrip extends ConsumerWidget {
  const ServerStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(serverInfoControllerProvider);
    final info = data.value;
    final error = data.error;
    final updatedAt = data.updatedAt;
    final Widget title;
    if (info != null) {
      final os = info.operatingSystem;
      title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(info.name.isEmpty ? 'Jellyfin' : info.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          Text(
              os == null
                  ? l.adminServerVersion(info.version)
                  : l.adminServerVersionOs(info.version, os),
              style: const TextStyle(color: WfColors.creamMuted)),
        ],
      );
    } else if (error != null) {
      title = Row(
        children: [
          Flexible(
            child: Text(describeError(l, error),
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => unawaited(
                ref.read(serverInfoControllerProvider.notifier).refresh()),
            child: Text(l.retry),
          ),
        ],
      );
    } else {
      title = const Align(
          alignment: Alignment.centerLeft,
          child: SkeletonBox(width: 220, height: 20));
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WfColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WfColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.server, color: WfColors.gold),
              const SizedBox(width: 12),
              Expanded(child: title),
              const SizedBox(width: 16),
              const RestartArea(),
            ],
          ),
          if (info?.hasPendingRestart ?? false) ...[
            const SizedBox(height: 12),
            Row(
              key: const Key('pending-restart'),
              children: [
                const Icon(LucideIcons.triangleAlert,
                    size: 16, color: WfColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${l.adminPendingRestart}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: l.adminPendingRestartHint),
                  ])),
                ),
              ],
            ),
          ],
          if (data.stale && updatedAt != null) AdminStaleNote(updatedAt: updatedAt),
        ],
      ),
    );
  }
}

/// Riavvia, l'attesa del ritorno, oppure "non risponde ancora" con
/// Ricontrolla.
class RestartArea extends ConsumerWidget {
  const RestartArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return switch (ref.watch(restartControllerProvider)) {
      RestartPhase.idle => WfButton.secondary(
          label: l.adminRestart,
          icon: LucideIcons.rotateCw,
          onPressed: () => unawaited(_restart(context, ref)),
        ),
      RestartPhase.sending || RestartPhase.waiting => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
                dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(l.adminRestarting),
          ],
        ),
      RestartPhase.timedOut => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.adminRestartTimedOut,
                style: const TextStyle(color: WfColors.gold)),
            const SizedBox(width: 12),
            WfButton.secondary(
              label: l.adminRestartRecheck,
              icon: LucideIcons.refreshCw,
              onPressed: () => unawaited(_report(context,
                  ref.read(restartControllerProvider.notifier).recheck())),
            ),
          ],
        ),
    };
  }

  Future<void> _restart(BuildContext context, WidgetRef ref) async {
    final confirmed = await showRestartDialog(context);
    if (!confirmed || !context.mounted) return;
    await _report(
        context, ref.read(restartControllerProvider.notifier).restart());
  }

  /// L'avviso alla fine: "Jellyfin è tornato" o "Riavvio non riuscito". Il
  /// tempo scaduto si vede nella striscia; una pagina chiusa non avvisa.
  Future<void> _report(
      BuildContext context, Future<RestartOutcome> pending) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final text = switch (await pending) {
      RestartOutcome.back => l.adminRestartBack,
      RestartOutcome.failed => l.adminRestartFailed,
      RestartOutcome.timedOut || RestartOutcome.cancelled => null,
    };
    if (text != null) messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/features/admin/restart_controller_test.dart test/features/admin/restart_dialog_test.dart test/features/admin/server_strip_test.dart`
Expected: PASS.

- [ ] **Step 7: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/features/admin/restart_controller.dart lib/features/admin/restart_dialog.dart lib/features/admin/server_strip.dart test/features/admin/restart_controller_test.dart test/features/admin/restart_dialog_test.dart test/features/admin/server_strip_test.dart
git commit -m "feat(app): restart Jellyfin from the admin page"
```

### Task 8: pagina Amministrazione, rotta e menu

**Files:**
- Create: `lib/ui/wf_tab_button.dart`, `lib/features/admin/admin_navigation.dart`, `lib/features/admin/admin_screen.dart`
- Modify: `lib/features/requests/requests_screen.dart`, `lib/app/router.dart`, `lib/app/app_shell.dart`
- Test: `test/ui/wf_tab_button_test.dart`, `test/features/admin/admin_navigation_test.dart`, `test/features/admin/admin_screen_test.dart`, `test/app/app_shell_admin_test.dart`

- [ ] **Step 1: test che falliscono**

`test/ui/wf_tab_button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/wf_tab_button.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('scheda scelta in crema con la riga oro; clic', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Row(children: [
          WfTabButton(label: 'Sessioni', selected: true, onTap: () => taps++),
          WfTabButton(label: 'Registro', selected: false, onTap: () {}),
        ]),
      ),
    );

    Text text(String label) => tester.widget<Text>(find.text(label));
    expect(text('Sessioni').style!.color, WfColors.cream);
    expect(text('Registro').style!.color, WfColors.creamMuted);

    await tester.tap(find.text('Sessioni'));
    expect(taps, 1);
  });
}
```

`test/features/admin/admin_navigation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';

void main() {
  test('scheda dall\'indirizzo: senza o sconosciuta, Sessioni', () {
    expect(AdminTab.parse('sessions'), AdminTab.sessions);
    expect(AdminTab.parse(null), AdminTab.sessions);
    expect(AdminTab.parse('boh'), AdminTab.sessions);
  });
}
```

`test/features/admin/admin_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';
import 'package:wonderflix/features/admin/admin_screen.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdminApi api;

  setUp(() {
    api = FakeAdminApi()
      ..sessionsValue = testSessions()
      ..partiesValue = testParties();
  });

  /// La pagina in un router con `/admin` e `/home`, come nell'app.
  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    required FakeSessionController session,
    String location = '/admin',
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/admin',
          builder: (context, state) => Scaffold(
            body: AdminScreen(
                tab: AdminTab.parse(state.uri.queryParameters['tab'])),
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider.overrideWithValue(
            (image, fit) => const ColoredBox(color: Color(0xFF333333))),
        ...adminTestOverrides(api, session: session),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => WfMotionScope(
            motion: const WfMotion(MotionLevel.reduced), child: child!),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('admin: titolo, striscia, scheda Sessioni', (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)));

    expect(find.text('AMMINISTRAZIONE'), findsOneWidget);
    expect(find.text('WonderFlix'), findsOneWidget);
    expect(find.text('Jellyfin 10.11.9'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-tab-sessions')), findsOneWidget);
    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('scheda sconosciuta nell\'indirizzo: Sessioni', (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        location: '/admin?tab=boh');

    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('non admin: torna alla Home senza chiamare Jellyfin',
      (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testUser)));

    expect(find.text('home'), findsOneWidget);
    expect(find.text('Non sei più amministratore'), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('non più admin mentre guarda la pagina: avviso e Home',
      (tester) async {
    final session = FakeSessionController(const SessionSignedIn(testAdmin));
    await pumpScreen(tester, session: session);

    session.set(const SessionSignedIn(testUser));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('home'), findsOneWidget);
    expect(find.text('Non sei più amministratore'), findsOneWidget);
  });
}
```

`test/app/app_shell_admin_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester, JellyfinUser user) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: appShellBuilder,
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const Text('pagina home')),
            GoRoute(
                path: '/admin', builder: (_, _) => const Text('pagina admin')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(SessionSignedIn(user))),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => WfMotionScope(
            motion: const WfMotion(MotionLevel.reduced), child: child!),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('admin: "Amministrazione" nel menu apre la pagina',
      (tester) async {
    await pumpShell(tester,
        const JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true));

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('Amministrazione'), findsOneWidget);
    expect(find.text('Esci'), findsOneWidget);

    await tester.tap(find.text('Amministrazione'));
    await tester.pumpAndSettle();
    expect(find.text('pagina admin'), findsOneWidget);
  });

  testWidgets('utente normale: niente "Amministrazione"', (tester) async {
    await pumpShell(tester, testUser);

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('Amministrazione'), findsNothing);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/ui/wf_tab_button_test.dart test/features/admin/admin_navigation_test.dart test/features/admin/admin_screen_test.dart test/app/app_shell_admin_test.dart`
Expected: FAIL in compilazione (`wf_tab_button.dart`, `admin_navigation.dart`, `admin_screen.dart` non esistono).

- [ ] **Step 3: il pulsante delle schede condiviso**

`lib/ui/wf_tab_button.dart` (lo stesso disegno di `_TabButton` della pagina Richieste):

```dart
import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Il pulsante di una scheda (pagine Richieste e Amministrazione): testo,
/// con la riga oro sotto quella scelta.
class WfTabButton extends StatelessWidget {
  const WfTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: selected ? WfColors.gold : Colors.transparent, width: 2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? WfColors.cream : WfColors.creamMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
```

In `lib/features/requests/requests_screen.dart`:
- aggiungi l'import `'../../ui/wf_tab_button.dart'`;
- sostituisci `_TabButton(` con `WfTabButton(`;
- togli la classe `_TabButton` in fondo al file.

Run: `flutter test test/features/requests/requests_screen_test.dart test/ui/wf_tab_button_test.dart`
Expected: PASS (la pagina Richieste non cambia).

- [ ] **Step 4: navigazione e pagina**

`lib/features/admin/admin_navigation.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';

/// Le schede della pagina Amministrazione (spec J §9). Il piano 16b
/// aggiunge Manutenzione, Registro e WonderFlix.
enum AdminTab {
  sessions;

  /// Dal parametro `tab` dell'indirizzo: senza, o con un valore
  /// sconosciuto, Sessioni.
  static AdminTab parse(String? raw) =>
      values.firstWhere((tab) => tab.name == raw, orElse: () => sessions);
}

String adminTabLabel(AppLocalizations l, AdminTab tab) => switch (tab) {
      AdminTab.sessions => l.adminTabSessions,
    };

/// Apre la pagina Amministrazione, sulla scheda [tab] se c'è.
void openAdmin(BuildContext context, {AdminTab? tab}) =>
    context.go(tab == null ? '/admin' : '/admin?tab=${tab.name}');
```

`lib/features/admin/admin_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_tab_button.dart';
import 'admin_navigation.dart';
import 'admin_providers.dart';
import 'server_strip.dart';
import 'sessions_tab.dart';

/// La pagina Amministrazione (spec J §7, §9.1): la striscia del server, le
/// schede e il contenuto della scheda scelta. La scheda sta nell'indirizzo;
/// cambiandola la pagina resta la stessa (con la striscia e un riavvio in
/// corso). Chi non è admin torna alla Home; chi smette di esserlo mentre la
/// guarda riceve anche un avviso.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key, this.tab = AdminTab.sessions});

  final AdminTab tab;

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  static const _homeRoute = '/home';

  /// La pagina è stata vista da admin: se smette di esserlo, l'avviso.
  bool _wasAdmin = false;

  /// Già partita verso la Home: ci va una volta sola.
  bool _leaving = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!ref.watch(isAdminProvider)) {
      if (!_leaving) {
        _leaving = true;
        final lost = _wasAdmin;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (lost) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l.adminNoLongerAdmin)));
          }
          context.go(_homeRoute);
        });
      }
      return const SizedBox.shrink();
    }
    _wasAdmin = true;
    final tab = widget.tab;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
          child: Text(l.menuAdmin.toUpperCase(), style: WfText.display(40)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: ServerStrip(),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: [
              for (final item in AdminTab.values) ...[
                WfTabButton(
                  key: ValueKey('admin-tab-${item.name}'),
                  label: adminTabLabel(l, item),
                  selected: item == tab,
                  onTap: () => openAdmin(context, tab: item),
                ),
                const SizedBox(width: 24),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (tab) {
            AdminTab.sessions => const SessionsTab(),
          },
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: rotta e menu**

`lib/app/router.dart`:
- aggiungi gli import `'../features/admin/admin_navigation.dart'` e `'../features/admin/admin_screen.dart'`;
- nella `ShellRoute`, dopo la rotta `/settings`:

```dart
          GoRoute(
              path: '/admin',
              // Senza chiave: cambiando scheda la pagina resta la stessa
              // (striscia e riavvio in corso compresi).
              pageBuilder: (context, state) => shellPage(
                  context,
                  state,
                  AdminScreen(
                      tab: AdminTab.parse(state.uri.queryParameters['tab'])),
                  underBar: true)),
```

`lib/app/app_shell.dart`, in `_UserMenu`:
- in `onSelected`, dopo `case 'settings':`:

```dart
          case 'admin':
            context.go('/admin');
```

- in `itemBuilder`, tra la voce `settings` e la voce `logout`:

```dart
        // Solo per gli admin di Jellyfin (spec J §7).
        if (user.isAdministrator)
          PopupMenuItem(
            value: 'admin',
            child: Row(
              children: [
                const Icon(LucideIcons.shieldCheck,
                    size: 18, color: WfColors.cream),
                const SizedBox(width: 12),
                Text(l.menuAdmin),
              ],
            ),
          ),
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/ui/wf_tab_button_test.dart test/features/admin test/app/app_shell_admin_test.dart test/app/app_shell_test.dart test/features/requests/requests_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: commit**

Run `flutter analyze` e `flutter test`, poi:

```bash
git add lib/ui/wf_tab_button.dart lib/features/requests/requests_screen.dart lib/features/admin/admin_navigation.dart lib/features/admin/admin_screen.dart lib/app/router.dart lib/app/app_shell.dart test/ui/wf_tab_button_test.dart test/features/admin/admin_navigation_test.dart test/features/admin/admin_screen_test.dart test/app/app_shell_admin_test.dart
git commit -m "feat(app): add the admin page to the user menu"
```

---

## Gruppo C — allineamento e verifica finale

### Task 9: spec allineata, verifica, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md`

- [ ] **Step 1: allinea la spec**

In `docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md`:
- **Stato:** `approvato; piano 16a realizzato (docs/superpowers/plans/2026-10-06-wonderflix-16a-admin-sessioni.md)`.
- **§6:**
  - `transcode_labels.dart` diventa `session_labels.dart` (decisione 8);
  - aggiungi `admin_tab_controller.dart` (`AdminData`, `AdminTabController`) e `admin_widgets.dart`;
  - la striscia e il suo controller stanno in `server_strip.dart`, non c'è `restart_flow.dart`.
- **§7:**
  - la scheda cambia con `context.go` e la pagina non ha chiave nella rotta (decisione 3);
  - nessun titolo nella barra (decisione 9).
- **§9.3:**
  - gli avatar sono l'iniziale (decisione 2);
  - la regola del metodo è quella della decisione 7;
  - senza accesso ai watch party l'elenco non si chiede (decisione 10);
  - si scartano anche le sessioni con `UserId` di soli zeri (decisione 11).
- **§9.1:** la scheda in caricamento mostra `LoadingView`, la striscia uno `SkeletonBox` (decisione 13).
- **§9.2:**
  - la striscia mostra il sistema solo se Jellyfin lo dice; sul server è vuoto (decisione 12);
  - un 502/503/504 sul `POST` di riavvio conta come riavvio partito (decisione 16).
- **§10:**
  - l'intervallo parte dalla fine della lettura; una lettura chiesta durante un'altra ne fa partire una sola, subito dopo (decisione 4);
  - la finestra in vista viene da `AppLifecycleListener`, e le riletture si fermano anche quando la pagina è coperta da un'altra rotta (decisioni 5 e 14);
  - dopo il riavvio si rilegge tramite `adminEpochProvider` (decisione 6).
- **§12:** le letture della pagina non danno 403 a chi non è più admin; l'utente si rilegge all'apertura e ogni 60 s, con la striscia, e il 403 resta un segnale in più (decisione 15).
- **§8.1:** togli "un 403 vuol dire che l'utente non è più admin": vale solo per il riavvio.
- **§15:** il piano è diviso in 16a (fatto) e 16b.

```bash
git add docs/superpowers/specs/2026-10-06-wonderflix-dashboard-admin-design.md
git commit -m "docs: align spec J with plan 16a"
```

- [ ] **Step 2: verifica finale**

Run: `flutter analyze` e `flutter test`.
Expected: tutto verde, nessun problema. Annota i numeri. Il plugin non è cambiato.

- [ ] **Step 3: build per la prova manuale**

Copia `config/wonderflix.json` dalla root del repository principale nella stessa cartella del worktree (non si committa), poi:

Run: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
Expected: `build/windows/x64/runner/Release/wonderflix.exe`.

## Prova manuale (con l'utente, dopo la review finale)

1. **Menu:** con l'account admin, nel menu dell'avatar c'è "Amministrazione" tra Impostazioni ed Esci. Con un account normale (se l'utente ne ha uno di prova) non c'è.
2. **Striscia:** "WonderFlix" e "Jellyfin 10.11.9", con Riavvia.
3. **Sessioni:**
   - una riproduzione da un altro dispositivo (per esempio Jellyfin Web con una qualità più bassa, così transcodifica) compare in "In riproduzione" con titolo, avanzamento, "Transcodifica", la riga dei codec e i motivi;
   - una riproduzione da WonderFlix compare come "Diretta" o "Remux";
   - in pausa compare l'icona;
   - i dispositivi collegati compaiono in "Collegati" con "attivo …"; Seerr e jfa-go (chiavi API) non ci sono;
   - un watch party compare in "Watch party" con stato e partecipanti, anche se è privato e l'admin non ne fa parte.
4. **Finestra ridotta a icona:** per 30 secondi le richieste `/Sessions` si fermano. L'orchestratore lo controlla nel log di accesso di nginx sul server (`~/.apps/nginx/`). Tornando alla finestra, i dati si aggiornano subito.
5. **Riavvio, con nessuno che guarda:**
   - la conferma dice "Nessuno sta guardando.";
   - Riavvia → "Riavvio in corso…" → "Jellyfin è tornato" entro un paio di minuti;
   - dopo, la striscia e le sessioni si aggiornano da sole.

Dopo l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria del flusso). Poi il piano 16b (Manutenzione, Registro, WonderFlix, release 0.10.0).
