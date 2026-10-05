# WonderFlix — Piano 15b: seguire e approvare le richieste, release

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** seconda metà della Spec I. Ci sono:
- la pagina **Richieste** (`/requests`) con la voce nella barra in alto, le schede "Le mie", "Da approvare (n)" e "Tutte";
- **Approva** con la finestra di server, profilo e cartella, e **Rifiuta** con conferma;
- **"Richiedi stagioni"** nella scheda delle serie della libreria;
- le righe **"Ora disponibile"** e **"Nuova richiesta"** nella cassetta delle notifiche;
- la configurazione del **webhook** in Seerr, con l'utente;
- poi la release: plugin 1.4.0 dal Catalogo e app 0.9.0.

Il plugin non cambia: tutto quello che serve c'è già dal piano 15a.

**Spec:** `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md` (§7.5, §7.6, §8.4, §9.3–9.6, §10, §11, §12, §14 punto 2).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 10):
1. **Rifiuta senza finestra.** Nell'app le conferme brevi non usano finestre: "Svuota" della cassetta passa a "Conferma" per qualche secondo. Rifiuta fa lo stesso: "Rifiuta" → "Conferma" (rosso) per 4 s (`declineConfirmFor`), e il secondo clic rifiuta. Il testo "Rifiutare la richiesta di {title}?" non serve.
2. **Le prime finestre dell'app** sono Approva e Richiedi stagioni. Hanno un aspetto comune (`showWfDialog` in `lib/ui/wf_dialog.dart`): fondo `surface`, bordo, angoli arrotondati, Esc e clic fuori per chiudere.
3. **Approva:** la finestra restituisce la scelta (server, profilo, cartella, oppure "Predefinito"). La chiamata parte dalla pagina, e la riga mostra un indicatore e resta bloccata finché la risposta non arriva.
4. **La riga esce subito** dall'elenco dopo Approva o Rifiuta, senza animazione, e compare l'avviso "Approvata" o "Rifiutata".
5. **Ricarica degli elenchi a ogni `InboxChanged`**, non solo per le voci delle richieste: l'evento non dice il tipo della voce, e una ricarica in più non costa niente.
6. **Conteggio "Da approvare (n)":** la prima pagina di 50 (`pendingCountTake`); con altre richieste oltre, "50+". Si ricarica dopo Approva e Rifiuta e a ogni `InboxChanged`.
7. **"Richiedi stagioni" riusa `RequestTitleController`**, con la stessa chiave della scheda da richiedere: stagioni scelte, invio, blocco e avvisi sono gli stessi.
8. **Scheda della pagina nell'indirizzo:** `/requests?tab=mine|pending|all`. La cassetta apre `/requests?tab=pending` per "Nuova richiesta" e `/requests` per un titolo arrivato senza id Jellyfin.

**Architecture:**
- **Dati:**
  - `RequestsListController` (family per filtro e lingua): pagine di 20, ricarica, `approve` e `decline` con il blocco della riga;
  - `pendingRequestsCountProvider`;
  - `seasonsToRequestProvider` per le serie della libreria.
- **Interfaccia:**
  - `RequestRow` con l'etichetta di stato;
  - `RequestsScreen` con le schede;
  - `PendingRequestActions` (Approva e Rifiuta);
  - `ApproveDialog`;
  - `RequestSeasonsDialog`;
  - righe nuove della cassetta in `inbox_request_rows.dart`.
- **Navigazione:**
  - la rotta `/requests` nella shell;
  - la voce "Richieste" solo con la funzione;
  - `openRequest` e `openRequests` in `requests_navigation.dart`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, lucide_icons_flutter, clock; plugin C# invariato (release).

**Worktree:** `.claude/worktrees/piano-15b`, branch `feat/piano-15b`. **Base:** `main` con questo piano. **Test a inizio piano:** da contare all'avvio; a fine piano 15a erano 1770 Flutter e 383 plugin.

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-15b`).
  - Comandi git semplici: niente `git -C`, niente variabili nei comandi git.
  - Mai `git checkout -- <file>` su un file che hai modificato.
- **Prima di ogni commit:** `flutter analyze` senza problemi e `flutter test` tutto verde (la suite intera).
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: molti file della working copy sono CRLF (per esempio `router.dart`, `app_shell.dart`, gli ARB, `detail_header.dart`, `inbox_models.dart`, `inbox_panel.dart`), l'indice è LF con `core.autocrlf=true`. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) e controlla con `iconv -f UTF-8 -t UTF-8 <file>`. Non usare strumenti che cambiano la codifica.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; durate da `WfMotion` (dove serve); `clock.now()`, mai `DateTime.now()`.
- **Liste nei test:** un `ListView` costruisce i figli solo vicino allo schermo; per un elemento in basso usa `tester.scrollUntilVisible`/`dragUntilVisible` sul `Scrollable` giusto.
- **Provider `autoDispose`:** restano vivi solo con un ascoltatore; nei test di controller usa `container.listen(...)` prima di leggere.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-05 sul codice di `main` (`bb9befa`).

**Già pronto dal piano 15a**
- `RequestsApi` (`lib/core/requests/requests_api.dart`) ha già:
  - `list(RequestsFilter filter, {required int skip, required int take, required String language})` → `RequestPage {items, hasMore}`;
  - `services(RequestMediaType type)` → `List<ServiceOption>`;
  - `approve(int requestId, ApproveChoice choice, {required String language})` e `decline(int requestId, {required String language})` → `MediaRequest`.
  - Gli errori sono `RequestsException(RequestsFailure.…)`.
- **Modelli** (`lib/core/requests/requests_models.dart`):
  - `MediaRequest {id, mediaType, tmdbId, title, year, posterPath, seasons, requestedBy: Requester {name, isMe}, createdAt, status: RequestStatus, progress, jellyfinItemId}`;
  - `ServiceOption {id, name, isDefault, profiles: [ProfileOption {id, name}], rootFolders, defaultProfileId, defaultRootFolder}`;
  - `ApproveChoice {serverId, profileId, rootFolder}` con `ApproveChoice.defaults`;
  - `RequestsFilter {mine, pending, all}` (`wire`), `RequestStatus {pending, approved, downloading, partial, available, declined, failed}`.
- **Provider:** `requestsApiProvider`, `requestsAvailableProvider` (bool), `requestsMeProvider` (`FutureProvider.autoDispose<RequestsMe>`, con `canRequest` e `canManage`).
- **Scheda da richiedere:**
  - `RequestTitleController` (`requestTitleControllerProvider`, family `RequestTitleKey = ({RequestMediaType type, int tmdbId, String language})`) ha `load`, `toggleSeason`, `toggleAll`, `submit()` → `RequestOutcome?` e `requestOutcomeText(l, outcome)`.
  - Lo stato ha `details`, `selected`, `sending`; `TitleDetails.requestableSeasons`.
- **Componenti:**
  - `SeasonPicker({seasons, selected, onToggle, onToggleAll, enabled})` in `season_picker.dart`;
  - `RequestStatusChip({label})` in `tmdb_title_screen.dart`;
  - `RequestBadge` in `requestable_poster_card.dart`;
  - `tmdbRoute(type, tmdbId)` e `openRequestable` in `requests_navigation.dart`;
  - `TmdbImages.poster(path)`.
- **Finti** (`test/support/requests_fakes.dart`):
  - `FakeRequestsApi` (oggi `list` dà una pagina vuota, `services` una lista vuota, `approve`/`decline` lanciano `UnimplementedError`);
  - `requestsTestOverrides(api, {available})`, `testRequestable`, `testDetails`.

**App, cose da sapere**
- **Finestre e conferme:**
  - Nell'app oggi **non ci sono finestre di dialogo** (`showDialog` non è usato).
  - La conferma a due tempi è `_ClearButton` in `lib/features/inbox/inbox_panel.dart`: un `Timer` di `InboxPanel.clearConfirmFor` (4 s), testo e colore che cambiano.
- **`DropdownButtonFormField.value` è deprecato** in questa versione di Flutter (`flutter analyze` lo segnala): si usa `DropdownButton` con `value`, `isExpanded: true` e `dropdownColor`, con un'etichetta sopra.
- **Paginazione:** come `CatalogScreen` (`lib/features/catalog/catalog_screen.dart`), un listener sullo scroll con `position.extentAfter` sotto una soglia chiama `loadMore`. `loadMore` non fa nulla se sta già caricando, se non c'è altro o dopo un errore.
- **Ora relativa:** `inboxTimeLabel(createdAt, now, l)` (`lib/features/inbox/inbox_time.dart`) dà "5 min fa", "ieri", "3 ott".
- **Eventi:**
  - `socialEventsProvider` (`Provider<Stream<SocialEvent>>`, in `lib/features/social/social_providers.dart`) porta `InboxChangedEvent` (`lib/core/social/social_models.dart`).
  - Nei test si sostituisce con `socialEventsProvider.overrideWithValue(stream)`.
- **Barra in alto:** `_NavBar` in `lib/app/app_shell.dart` riceve una lista di `(label, route, icon)`. La voce attiva è quella con `location.startsWith(route)`, e `onTap` fa `context.go(route)`. `AppShell` è un `ConsumerStatefulWidget`.
- **Pagine della shell:**
  - `shellPage(context, state, child, underBar: true)` (`lib/app/page_transitions.dart`).
  - Il titolo delle pagine è `Text(l.navMyList.toUpperCase(), style: WfText.display(40))` con padding `EdgeInsets.fromLTRB(32, 16, 32, 12)` (vedi `MyListScreen`).
- **Cassetta delle notifiche:**
  - `InboxEntry` è `sealed`, con `InviteEntry`, `AnnouncementEntry`, `NewTitlesEntry`, e si legge con `inboxEntryFromJson`. I tipi sconosciuti danno `null`.
  - `_EntryTile` in `inbox_panel.dart` ha due `switch (entry)` (icona e contenuto) che devono restare esaustivi.
  - Una riga che apre una scheda chiude prima il pannello: `ref.read(shellPanelProvider.notifier).close()`, poi `openItemById(context, id)`.
  - Le costanti di misura sono `InboxPanel.leadingSize` (40) e `InboxPanel.posterHeight`.
- **`DetailHeader`** (`lib/features/detail/detail_header.dart`):
  - è un `ConsumerWidget` con `item`;
  - la fila dei pulsanti è un `Wrap`, con Trailer prima dei toggle cuore e visto;
  - vale per film e serie;
  - `testItem` non dà un `tmdbId` se non lo si chiede, quindi i test di oggi non toccano Seerr.
- **Stato sul server:**
  - Gira il plugin **1.4.0.0 installato a mano**. La copia del Catalogo 1.3.0.0 è in `~/wfwp-backup/1.3.0.0-catalogo`.
  - Seerr è collegato ("Connected to Seerr 3.4.1"), il webhook non ancora.
  - La sincronizzazione "aggiunti di recente" di Seerr è rotta (utente n.1 con un id Jellyfin vecchio), quindi "Ora disponibile" arriva dopo la scansione della notte.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi |
| `test/support/requests_fakes.dart` | modifica | elenchi, server, approva e rifiuta finti; `testMediaRequest`; eventi |
| `lib/features/requests/requests_list_controller.dart` | crea | `RequestsListController`, azioni, conteggio "Da approvare" |
| `lib/features/requests/request_labels.dart` | crea | stagioni "1–3, 5", testo e colore dello stato |
| `lib/features/requests/request_row.dart` | crea | `RequestRow`, `RequestStatusLabel` |
| `lib/features/requests/requests_navigation.dart` | modifica | `RequestsTab`, `openRequest`, `openRequests` |
| `lib/features/requests/requests_screen.dart` | crea | pagina Richieste, schede, elenco a pagine |
| `lib/app/router.dart`, `lib/app/app_shell.dart` | modifica | rotta `/requests`, voce "Richieste" |
| `lib/ui/wf_dialog.dart` | crea | `showWfDialog` |
| `lib/features/requests/approve_dialog.dart` | crea | `ApproveDialog`, `requestServicesProvider` |
| `lib/features/requests/pending_request_actions.dart` | crea | Approva e Rifiuta (a due tempi) |
| `lib/features/requests/request_seasons.dart` | crea | `seasonsToRequestProvider`, `RequestSeasonsDialog` |
| `lib/features/detail/detail_header.dart` | modifica | "Richiedi stagioni" |
| `lib/core/social/inbox_models.dart` | modifica | `RequestAvailableEntry`, `RequestPendingEntry` |
| `lib/features/inbox/inbox_request_rows.dart` | crea | icona e testo delle righe delle richieste |
| `lib/features/inbox/inbox_panel.dart` | modifica | le due voci negli `switch` |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1–4):** testi, dati degli elenchi, righe, pagina Richieste con rotta e voce nella barra.
- **Gruppo B (Task 5–6):** finestre, Approva e Rifiuta.
- **Gruppo C (Task 7–8):** "Richiedi stagioni" e righe della cassetta.
- **Gruppo D (Task 9):** **STOP**, lo fa l'orchestratore con l'utente (webhook in Seerr).
- **Gruppo E (Task 10):** allineamento della spec, verifica, build.

---

## Gruppo A — pagina Richieste

### Task 1: testi del piano

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan15b_test.dart`

- [ ] **Step 1: test che fallisce**

`test/app/l10n_plan15b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 15b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.navRequests, 'Richieste');
    expect(it.requestsTabPendingCount('3'), 'Da approvare (3)');
    expect(it.requestsSeasonsList(1, '2'), 'Stagione 2');
    expect(it.requestsSeasonsList(2, '1–2'), 'Stagioni 1–2');
    expect(it.requestsStatusDownloading(45), 'In arrivo · 45%');
    expect(it.requestsRequestedBy('Garg'), 'chiesto da Garg');
    expect(it.requestsApproveTitle('Dune'), 'Approva: Dune');
    expect(it.requestsServerDefault('Radarr'), 'Predefinito (Radarr)');
    expect(it.inboxRequestAvailable('Dune (2021)'), 'Ora disponibile: Dune (2021)');
    expect(it.inboxRequestPending('Garg', 'Dune (2021)'), 'Garg ha chiesto Dune (2021)');
    expect(it.inboxRequestTitleSeasons('Brothers (2026)', 2, '1–2'),
        'Brothers (2026), stagioni 1–2');
    expect(it.inboxRequestTitleSeasons('Brothers (2026)', 1, '3'),
        'Brothers (2026), stagione 3');
    expect(en.navRequests, 'Requests');
    expect(en.requestsTabPendingCount('50+'), 'To approve (50+)');
    expect(en.requestsSeasonsList(2, '1–2'), 'Seasons 1–2');
    expect(en.inboxRequestPending('Garg', 'Dune'), 'Garg requested Dune');
    expect(en.requestsEmptyMine,
        "You haven't requested anything yet. Search for a missing title and press Request.");
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/l10n_plan15b_test.dart`
Expected: FAIL di compilazione (`navRequests` non esiste).

- [ ] **Step 3: testi**

In fondo a `l10n/app_it.arb` (togli la `}` finale, aggiungi la virgola dopo l'ultima voce):

```json
  "navRequests": "Richieste",
  "requestsTabMine": "Le mie",
  "requestsTabPending": "Da approvare",
  "requestsTabPendingCount": "Da approvare ({count})",
  "@requestsTabPendingCount": {"placeholders": {"count": {"type": "String"}}},
  "requestsTabAll": "Tutte",
  "requestsRequestedBy": "chiesto da {name}",
  "@requestsRequestedBy": {"placeholders": {"name": {"type": "String"}}},
  "requestsSeasonsList": "{count, plural, =1{Stagione {list}} other{Stagioni {list}}}",
  "@requestsSeasonsList": {"placeholders": {"count": {"type": "int"}, "list": {"type": "String"}}},
  "requestsStatusApproved": "Approvata",
  "requestsStatusDownloading": "In arrivo · {percent}%",
  "@requestsStatusDownloading": {"placeholders": {"percent": {"type": "int"}}},
  "requestsStatusDeclined": "Rifiutata",
  "requestsStatusFailed": "Non riuscita",
  "requestsApprove": "Approva",
  "requestsDecline": "Rifiuta",
  "requestsDeclineConfirm": "Conferma",
  "requestsEmptyMine": "Non hai ancora chiesto niente. Cerca un titolo che manca e premi Richiedi.",
  "requestsEmptyPending": "Niente da approvare",
  "requestsEmptyAll": "Nessuna richiesta",
  "requestsUnknownTitle": "Titolo non disponibile",
  "requestsApproveTitle": "Approva: {title}",
  "@requestsApproveTitle": {"placeholders": {"title": {"type": "String"}}},
  "requestsServer": "Server",
  "requestsServerDefault": "Predefinito ({name})",
  "@requestsServerDefault": {"placeholders": {"name": {"type": "String"}}},
  "requestsServerDefaultPlain": "Predefinito",
  "requestsProfile": "Profilo",
  "requestsFolder": "Cartella",
  "requestsServersUnavailable": "Server non disponibili: si approva con i valori predefiniti",
  "requestsCancel": "Annulla",
  "requestsMoreSeasons": "Richiedi stagioni",
  "inboxRequestAvailable": "Ora disponibile: {title}",
  "@inboxRequestAvailable": {"placeholders": {"title": {"type": "String"}}},
  "inboxRequestPending": "{name} ha chiesto {title}",
  "@inboxRequestPending": {"placeholders": {"name": {"type": "String"}, "title": {"type": "String"}}},
  "inboxRequestTitleSeasons": "{title}, {count, plural, =1{stagione {list}} other{stagioni {list}}}",
  "@inboxRequestTitleSeasons": {"placeholders": {"title": {"type": "String"}, "count": {"type": "int"}, "list": {"type": "String"}}}
}
```

In fondo a `l10n/app_en.arb`, allo stesso modo:

```json
  "navRequests": "Requests",
  "requestsTabMine": "Mine",
  "requestsTabPending": "To approve",
  "requestsTabPendingCount": "To approve ({count})",
  "requestsTabAll": "All",
  "requestsRequestedBy": "requested by {name}",
  "requestsSeasonsList": "{count, plural, =1{Season {list}} other{Seasons {list}}}",
  "requestsStatusApproved": "Approved",
  "requestsStatusDownloading": "Coming soon · {percent}%",
  "requestsStatusDeclined": "Declined",
  "requestsStatusFailed": "Failed",
  "requestsApprove": "Approve",
  "requestsDecline": "Decline",
  "requestsDeclineConfirm": "Confirm",
  "requestsEmptyMine": "You haven't requested anything yet. Search for a missing title and press Request.",
  "requestsEmptyPending": "Nothing to approve",
  "requestsEmptyAll": "No requests",
  "requestsUnknownTitle": "Title not available",
  "requestsApproveTitle": "Approve: {title}",
  "requestsServer": "Server",
  "requestsServerDefault": "Default ({name})",
  "requestsServerDefaultPlain": "Default",
  "requestsProfile": "Profile",
  "requestsFolder": "Folder",
  "requestsServersUnavailable": "Servers unavailable: approving with the defaults",
  "requestsCancel": "Cancel",
  "requestsMoreSeasons": "Request seasons",
  "inboxRequestAvailable": "Now available: {title}",
  "inboxRequestPending": "{name} requested {title}",
  "inboxRequestTitleSeasons": "{title}, {count, plural, =1{season {list}} other{seasons {list}}}"
}
```

Poi `flutter gen-l10n`.

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add l10n test/app/l10n_plan15b_test.dart
git commit -m "feat(app): add the texts for following and approving requests"
```

### Task 2: finti, `RequestsListController` e conteggio "Da approvare"

**Files:**
- Modify: `test/support/requests_fakes.dart`
- Create: `lib/features/requests/requests_list_controller.dart`
- Test: `test/features/requests/requests_list_controller_test.dart`

- [ ] **Step 1: i finti**

In `test/support/requests_fakes.dart`:
- aggiungi gli import `package:wonderflix/core/social/social_models.dart` e `package:wonderflix/features/social/social_providers.dart`;
- in `FakeRequestsApi`, dopo `final created = …;`, aggiungi:

```dart

  /// Le richieste di ogni elenco, in ordine: `list` ne dà una pagina.
  final lists = <RequestsFilter, List<MediaRequest>>{};

  /// Se impostato, `list` aspetta che si completi.
  Completer<void>? listGate;

  /// I server per tipo di titolo.
  final servicesByType = <RequestMediaType, List<ServiceOption>>{};

  /// Errore solo per `services`.
  RequestsFailure? servicesFailure;

  /// Errore solo per `approve` e `decline`.
  RequestsFailure? actionFailure;

  /// Se impostato, `approve` e `decline` aspettano che si completi.
  Completer<void>? actionGate;

  final approved = <({int id, ApproveChoice choice})>[];
  final declined = <int>[];
```

- sostituisci i metodi `list`, `services`, `approve` e `decline` con:

```dart
  @override
  Future<RequestPage> list(RequestsFilter filter,
      {required int skip, required int take, required String language}) async {
    calls.add('list:${filter.wire}:$skip:$take');
    final gate = listGate;
    if (gate != null) await gate.future;
    _fail();
    final all = lists[filter] ?? const <MediaRequest>[];
    final page = all.skip(skip).take(take).toList();
    return RequestPage(items: page, hasMore: skip + page.length < all.length);
  }

  @override
  Future<List<ServiceOption>> services(RequestMediaType type) async {
    calls.add('services:${type.wire}');
    _fail();
    final f = servicesFailure;
    if (f != null) throw RequestsException(f);
    return servicesByType[type] ?? const [];
  }

  @override
  Future<MediaRequest> approve(int requestId, ApproveChoice choice,
      {required String language}) async {
    calls.add('approve:$requestId');
    approved.add((id: requestId, choice: choice));
    return _act(requestId, RequestStatus.approved);
  }

  @override
  Future<MediaRequest> decline(int requestId, {required String language}) async {
    calls.add('decline:$requestId');
    declined.add(requestId);
    return _act(requestId, RequestStatus.declined);
  }

  Future<MediaRequest> _act(int requestId, RequestStatus status) async {
    final gate = actionGate;
    if (gate != null) await gate.future;
    _fail();
    final f = actionFailure;
    if (f != null) throw RequestsException(f);
    return testMediaRequest(id: requestId, status: status);
  }
```

- sostituisci `requestsTestOverrides` con:

```dart
/// Provider per i test delle richieste: plugin [api], funzione
/// [available], avvisi della cassetta da [events].
List<Override> requestsTestOverrides(FakeRequestsApi api,
        {bool available = true,
        Stream<SocialEvent> events = const Stream.empty()}) =>
    [
      requestsApiProvider.overrideWithValue(api),
      requestsAvailableProvider.overrideWithValue(available),
      socialEventsProvider.overrideWithValue(events),
    ];
```

- in fondo al file:

```dart
MediaRequest testMediaRequest({
  int id = 1,
  String title = 'Dune - Parte due',
  RequestMediaType type = RequestMediaType.movie,
  int? year = 2024,
  List<int> seasons = const [],
  String requester = 'Mario',
  bool isMe = false,
  RequestStatus status = RequestStatus.pending,
  double? progress,
  String? jellyfinItemId,
  DateTime? createdAt,
}) =>
    MediaRequest(
      id: id,
      mediaType: type,
      tmdbId: 693000 + id,
      title: title,
      year: year,
      posterPath: '/r$id.jpg',
      seasons: seasons,
      requestedBy: Requester(name: requester, isMe: isMe),
      createdAt: createdAt ?? DateTime.utc(2026, 10, 3, 20),
      status: status,
      progress: progress,
      jellyfinItemId: jellyfinItemId,
    );
```

Se un test del piano 15a usava il vecchio `list` (`'list:…'` con due parti), aggiornalo al nuovo formato.

- [ ] **Step 2: test che falliscono**

`test/features/requests/requests_list_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/requests/requests_list_controller.dart';

import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;
  late StreamController<SocialEvent> events;
  const mine = (filter: RequestsFilter.mine, language: 'it');
  const pending = (filter: RequestsFilter.pending, language: 'it');

  setUp(() {
    api = FakeRequestsApi();
    events = StreamController<SocialEvent>.broadcast();
  });

  tearDown(() => events.close());

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: requestsTestOverrides(api, events: events.stream),
      retry: (_, _) => null,
    );
    container.listen(requestsListControllerProvider(mine), (_, _) {});
    container.listen(requestsListControllerProvider(pending), (_, _) {});
    return container;
  }

  List<MediaRequest> requests(int count) =>
      [for (var i = 1; i <= count; i++) testMediaRequest(id: i, title: 'Titolo $i')];

  test('carica a pagine di 20, poi le altre', () async {
    api.lists[RequestsFilter.mine] = requests(25);
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(requestsListControllerProvider(mine).notifier);

    expect(container.read(requestsListControllerProvider(mine)).items, hasLength(20));
    expect(container.read(requestsListControllerProvider(mine)).hasMore, isTrue);
    expect(api.calls, contains('list:mine:0:20'));

    await controller.loadMore();
    expect(container.read(requestsListControllerProvider(mine)).items, hasLength(25));
    expect(container.read(requestsListControllerProvider(mine)).hasMore, isFalse);
    expect(api.calls, contains('list:mine:20:20'));

    await controller.loadMore();
    expect(api.calls.where((c) => c.startsWith('list:mine')), hasLength(2));
  });

  test('ricarica a ogni avviso della cassetta', () async {
    final container = makeContainer();
    await pumpEventQueue();

    events.add(const InboxChangedEvent());
    await pumpEventQueue();

    expect(api.calls.where((c) => c == 'list:mine:0:20'), hasLength(2));
    expect(container.read(requestsListControllerProvider(mine)).loading, isFalse);
  });

  test('errore, poi Riprova', () async {
    api.failure = RequestsFailure.network;
    final container = makeContainer();
    await pumpEventQueue();
    expect(container.read(requestsListControllerProvider(mine)).error,
        isA<RequestsException>());

    api
      ..failure = null
      ..lists[RequestsFilter.mine] = requests(1);
    await container.read(requestsListControllerProvider(mine).notifier).reload();

    final state = container.read(requestsListControllerProvider(mine));
    expect(state.error, isNull);
    expect(state.items, hasLength(1));
  });

  test('Approva: la riga è bloccata durante l\'invio, poi esce', () async {
    api.lists[RequestsFilter.pending] = requests(2);
    final gate = api.actionGate = Completer<void>();
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestsListControllerProvider(pending).notifier);
    const choice =
        ApproveChoice(serverId: 1, profileId: 7, rootFolder: '/media/anime');

    final first = controller.approve(1, choice);
    expect(container.read(requestsListControllerProvider(pending)).busy, {1});
    expect(await controller.approve(1, choice), isNull);
    gate.complete();

    expect(await first, RequestActionOutcome.approved);
    final state = container.read(requestsListControllerProvider(pending));
    expect(state.items.map((r) => r.id), [2]);
    expect(state.busy, isEmpty);
    expect(api.approved.single.id, 1);
    expect(api.approved.single.choice.profileId, 7);
  });

  test('Rifiuta toglie la riga e fa ricontare', () async {
    api.lists[RequestsFilter.pending] = requests(2);
    final container = makeContainer();
    container.listen(pendingRequestsCountProvider('it'), (_, _) {});
    await pumpEventQueue();
    expect(container.read(pendingRequestsCountProvider('it')).value,
        (count: 2, more: false));

    expect(
        await container
            .read(requestsListControllerProvider(pending).notifier)
            .decline(2),
        RequestActionOutcome.declined);
    await pumpEventQueue();

    expect(api.declined, [2]);
    expect(
        container.read(requestsListControllerProvider(pending)).items.map((r) => r.id),
        [1]);
    expect(api.calls.where((c) => c == 'list:pending:0:50'), hasLength(2));
  });

  test('un errore lascia la riga', () async {
    api
      ..lists[RequestsFilter.pending] = requests(2)
      ..actionFailure = RequestsFailure.seerrUnavailable;
    final container = makeContainer();
    await pumpEventQueue();

    expect(
        await container
            .read(requestsListControllerProvider(pending).notifier)
            .decline(1),
        RequestActionOutcome.failed);

    final state = container.read(requestsListControllerProvider(pending));
    expect(state.items, hasLength(2));
    expect(state.busy, isEmpty);
  });

  test('conteggio: oltre 50 è "50+", e si ricarica con la cassetta', () async {
    api.lists[RequestsFilter.pending] = requests(55);
    final container = makeContainer();
    container.listen(pendingRequestsCountProvider('it'), (_, _) {});
    await pumpEventQueue();

    final count = container.read(pendingRequestsCountProvider('it')).value!;
    expect(count, (count: 50, more: true));
    expect(pendingCountLabel(count), '50+');
    expect(pendingCountLabel((count: 3, more: false)), '3');

    events.add(const InboxChangedEvent());
    await pumpEventQueue();
    expect(api.calls.where((c) => c == 'list:pending:0:50'), hasLength(2));
  });
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/features/requests/requests_list_controller_test.dart`
Expected: FAIL di compilazione (`requests_list_controller.dart` non esiste).

- [ ] **Step 4: implementazione**

`lib/features/requests/requests_list_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/requests/requests_api.dart';
import '../../core/requests/requests_models.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../social/social_providers.dart';
import 'requests_providers.dart';

/// Un elenco della pagina Richieste: filtro e lingua dell'app.
typedef RequestsListKey = ({RequestsFilter filter, String language});

class RequestsListState {
  const RequestsListState({
    this.items = const [],
    this.hasMore = false,
    this.loading = false,
    this.error,
    this.busy = const {},
  });

  final List<MediaRequest> items;
  final bool hasMore;
  final bool loading;

  /// Errore dell'ultimo caricamento.
  final Object? error;

  /// Richieste con Approva o Rifiuta in viaggio: la riga è bloccata.
  final Set<int> busy;

  RequestsListState copyWith({
    List<MediaRequest>? items,
    bool? hasMore,
    bool? loading,
    Object? error,
    bool clearError = false,
    Set<int>? busy,
  }) =>
      RequestsListState(
        items: items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
      );
}

/// Esito di Approva e Rifiuta, per l'avviso (spec I §9.4).
enum RequestActionOutcome { approved, declined, failed }

String requestActionText(AppLocalizations l, RequestActionOutcome outcome) =>
    switch (outcome) {
      RequestActionOutcome.approved => l.requestsStatusApproved,
      RequestActionOutcome.declined => l.requestsStatusDeclined,
      RequestActionOutcome.failed => l.requestsFailed,
    };

/// Un elenco della pagina Richieste (spec I §8.4): pagine di [pageSize],
/// ricarica a ogni avviso della cassetta, Approva e Rifiuta con la riga
/// bloccata finché la risposta non arriva.
class RequestsListController extends Notifier<RequestsListState> {
  RequestsListController(this.listKey);

  final RequestsListKey listKey;

  /// Richieste per pagina (spec I §8.4).
  static const pageSize = 20;

  /// Numera i caricamenti: vale solo l'ultimo.
  int _generation = 0;

  @override
  RequestsListState build() {
    // Un avviso nella cassetta (nuova richiesta, titolo arrivato) può
    // cambiare l'elenco; l'evento non dice il tipo della voce, quindi si
    // ricarica sempre (decisione 5 del piano 15b).
    final subscription = ref.watch(socialEventsProvider).listen((event) {
      if (event is InboxChangedEvent) unawaited(reload());
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    unawaited(Future.microtask(reload));
    return const RequestsListState(loading: true);
  }

  /// Dalla prima pagina. Le righe di prima restano finché non arrivano le nuove.
  Future<void> reload() => _load(reset: true);

  /// La pagina successiva. Dopo un errore si riprova solo dal pulsante.
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore || state.error != null) return;
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final previous = state.items;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await ref.read(requestsApiProvider).list(listKey.filter,
          skip: reset ? 0 : previous.length,
          take: pageSize,
          language: listKey.language);
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        items: reset ? page.items : [...previous, ...page.items],
        hasMore: page.hasMore,
        loading: false,
      );
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(loading: false, error: error);
    }
  }

  /// Approva con [choice]; `null` se era già in corso.
  Future<RequestActionOutcome?> approve(int requestId, ApproveChoice choice) =>
      _act(
          requestId,
          RequestActionOutcome.approved,
          (api) => api.approve(requestId, choice, language: listKey.language));

  /// Rifiuta; `null` se era già in corso.
  Future<RequestActionOutcome?> decline(int requestId) => _act(
      requestId,
      RequestActionOutcome.declined,
      (api) => api.decline(requestId, language: listKey.language));

  Future<RequestActionOutcome?> _act(int requestId, RequestActionOutcome done,
      Future<MediaRequest> Function(RequestsApi api) call) async {
    if (state.busy.contains(requestId)) return null;
    state = state.copyWith(busy: {...state.busy, requestId});
    RequestActionOutcome outcome;
    try {
      await call(ref.read(requestsApiProvider));
      outcome = done;
    } on Object {
      outcome = RequestActionOutcome.failed;
    }
    if (!ref.mounted) return outcome;
    final failed = outcome == RequestActionOutcome.failed;
    state = state.copyWith(
      items: failed
          ? state.items
          : [for (final request in state.items) if (request.id != requestId) request],
      busy: {...state.busy}..remove(requestId),
    );
    if (!failed) {
      // Il conteggio e l'elenco "Tutte" non sono più giusti.
      ref.invalidate(pendingRequestsCountProvider(listKey.language));
      ref.invalidate(requestsListControllerProvider(
          (filter: RequestsFilter.all, language: listKey.language)));
    }
    return outcome;
  }
}

final requestsListControllerProvider = NotifierProvider.autoDispose
    .family<RequestsListController, RequestsListState, RequestsListKey>(
        RequestsListController.new);

/// Quante richieste aspettano: la prima pagina di [pendingCountTake];
/// `more` se ce ne sono altre.
typedef PendingCount = ({int count, bool more});

/// Richieste contate per "Da approvare (n)" (decisione 6 del piano 15b).
const pendingCountTake = 50;

/// Il conteggio di "Da approvare" (spec I §8.4), per lingua. Si ricarica a
/// ogni avviso della cassetta e dopo Approva e Rifiuta.
final pendingRequestsCountProvider =
    FutureProvider.autoDispose.family<PendingCount, String>((ref, language) async {
  final subscription = ref.watch(socialEventsProvider).listen((event) {
    if (event is InboxChangedEvent) ref.invalidateSelf();
  });
  ref.onDispose(() => unawaited(subscription.cancel()));
  final page = await ref.watch(requestsApiProvider).list(RequestsFilter.pending,
      skip: 0, take: pendingCountTake, language: language);
  return (count: page.items.length, more: page.hasMore);
});

/// "3", oppure "50+" se ce ne sono altre.
String pendingCountLabel(PendingCount count) =>
    count.more ? '${count.count}+' : '${count.count}';
```

- [ ] **Step 5: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 6: commit**

```bash
git add lib/features/requests test/features/requests test/support/requests_fakes.dart
git commit -m "feat(app): load the request lists and approve or decline"
```

### Task 3: righe delle richieste e navigazione

**Files:**
- Create: `lib/features/requests/request_labels.dart`, `lib/features/requests/request_row.dart`
- Modify: `lib/features/requests/requests_navigation.dart`
- Test: `test/features/requests/request_labels_test.dart`, `test/features/requests/request_row_test.dart`, `test/features/requests/requests_navigation_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/requests/request_labels_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/request_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/requests_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('stagioni in ordine, quelle di fila unite', () {
    expect(formatSeasonList(const []), '');
    expect(formatSeasonList(const [3]), '3');
    expect(formatSeasonList(const [2, 1]), '1–2');
    expect(formatSeasonList(const [5, 1, 2, 3, 3]), '1–3, 5');
  });

  test('testo dello stato', () {
    String label(RequestStatus status, [double? progress]) => requestStatusLabel(
        l, testMediaRequest(status: status, progress: progress));

    expect(label(RequestStatus.pending), 'In attesa');
    expect(label(RequestStatus.approved), 'Approvata');
    expect(label(RequestStatus.downloading, 0.456), 'In arrivo · 46%');
    expect(label(RequestStatus.downloading), 'In arrivo');
    expect(label(RequestStatus.partial), 'In parte disponibile');
    expect(label(RequestStatus.available), 'Disponibile');
    expect(label(RequestStatus.declined), 'Rifiutata');
    expect(label(RequestStatus.failed), 'Non riuscita');
  });

  test('colore dello stato', () {
    expect(requestStatusColor(RequestStatus.pending), WfColors.gold);
    expect(requestStatusColor(RequestStatus.downloading), WfColors.gold);
    expect(requestStatusColor(RequestStatus.approved), WfColors.cream);
    expect(requestStatusColor(RequestStatus.partial), WfColors.online);
    expect(requestStatusColor(RequestStatus.available), WfColors.online);
    expect(requestStatusColor(RequestStatus.declined), WfColors.error);
    expect(requestStatusColor(RequestStatus.failed), WfColors.error);
  });
}
```

`test/features/requests/request_row_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/request_row.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 12);
  final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

  Future<List<String>> pumpRow(WidgetTester tester, MediaRequest request,
      {bool showRequester = false, Widget? trailing}) async {
    final taps = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: RequestRow(
          request: request,
          now: now,
          showRequester: showRequester,
          trailing: trailing,
          onTap: () => taps.add('tap'),
        ),
      ),
    );
    return taps;
  }

  testWidgets('film: titolo, anno, chi l\'ha chiesto, quando, stato', (tester) async {
    final taps = await pumpRow(
      tester,
      testMediaRequest(title: 'Dune', year: 2021, requester: 'Garg', createdAt: fiveMinutesAgo),
      showRequester: true,
    );

    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text('Film · chiesto da Garg · 5 min fa'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);

    await tester.tap(find.text('Dune (2021)'));
    expect(taps, ['tap']);
  });

  testWidgets('serie: le stagioni chieste; senza chi l\'ha chiesto', (tester) async {
    await pumpRow(
      tester,
      testMediaRequest(
          title: 'Brothers',
          year: 2026,
          type: RequestMediaType.tv,
          seasons: const [2, 1],
          status: RequestStatus.downloading,
          progress: 0.45,
          createdAt: fiveMinutesAgo),
    );

    expect(find.text('Stagioni 1–2 · 5 min fa'), findsOneWidget);
    expect(find.text('In arrivo · 45%'), findsOneWidget);
  });

  testWidgets('titolo che Seerr non ha dato; azioni al posto dello stato',
      (tester) async {
    await pumpRow(
      tester,
      testMediaRequest(title: '', year: null, createdAt: fiveMinutesAgo),
      trailing: const Text('azioni'),
    );

    expect(find.text('Titolo non disponibile'), findsOneWidget);
    expect(find.text('azioni'), findsOneWidget);
    expect(find.text('In attesa'), findsNothing);
  });
}
```

In `test/features/requests/requests_navigation_test.dart` aggiungi:

```dart
  testWidgets('pagina Richieste e richieste: libreria o scheda da richiedere',
      (tester) async {
    late BuildContext home;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          home = context;
          return const Scaffold(body: Text('home'));
        },
      ),
      GoRoute(path: '/requests', builder: (context, state) => const Text('richieste')),
      GoRoute(path: '/item/:id', builder: (context, state) => const Text('scheda')),
      GoRoute(
          path: '/tmdb/:type/:tmdbId',
          builder: (context, state) => const Text('scheda tmdb')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    openRequests(home, tab: RequestsTab.pending);
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/requests?tab=pending');

    router.go('/');
    await tester.pumpAndSettle();
    openRequest(home, testMediaRequest(id: 4, jellyfinItemId: 'abc'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/abc');

    router.go('/');
    await tester.pumpAndSettle();
    openRequest(home, testMediaRequest(id: 4));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/tmdb/movie/693004');
  });

  test('scheda della pagina dall\'indirizzo', () {
    expect(RequestsTab.parse('pending'), RequestsTab.pending);
    expect(RequestsTab.parse('mine'), RequestsTab.mine);
    expect(RequestsTab.parse('all'), RequestsTab.all);
    expect(RequestsTab.parse('boh'), isNull);
    expect(RequestsTab.parse(null), isNull);
    expect(RequestsTab.pending.filter, RequestsFilter.pending);
  });
```

(Aggiungi gli import che mancano: `requests_models.dart` per `RequestsFilter`.)

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/requests/request_labels_test.dart test/features/requests/request_row_test.dart test/features/requests/requests_navigation_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`lib/features/requests/request_labels.dart`:

```dart
import 'dart:ui';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Le stagioni in ordine, quelle di fila unite: "1–3, 5" (spec I §9.4).
String formatSeasonList(Iterable<int> seasons) {
  final sorted = seasons.toSet().toList()..sort();
  if (sorted.isEmpty) return '';
  final runs = <String>[];
  var start = sorted.first;
  var previous = start;
  for (final season in sorted.skip(1)) {
    if (season == previous + 1) {
      previous = season;
      continue;
    }
    runs.add(start == previous ? '$start' : '$start–$previous');
    start = previous = season;
  }
  runs.add(start == previous ? '$start' : '$start–$previous');
  return runs.join(', ');
}

/// L'etichetta dello stato di una richiesta (spec I §9.4).
String requestStatusLabel(AppLocalizations l, MediaRequest request) {
  final progress = request.progress;
  return switch (request.status) {
    RequestStatus.pending => l.requestsStatusPending,
    RequestStatus.approved => l.requestsStatusApproved,
    RequestStatus.downloading => progress == null
        ? l.requestsBadgeComing
        : l.requestsStatusDownloading((progress.clamp(0, 1) * 100).round()),
    RequestStatus.partial => l.requestsPartlyAvailable,
    RequestStatus.available => l.requestsStatusAvailable,
    RequestStatus.declined => l.requestsStatusDeclined,
    RequestStatus.failed => l.requestsStatusFailed,
  };
}

/// Il colore dello stato: oro in attesa o in arrivo, crema approvata, verde
/// arrivata, rosso rifiutata o non riuscita (spec I §9.4).
Color requestStatusColor(RequestStatus status) => switch (status) {
      RequestStatus.pending || RequestStatus.downloading => WfColors.gold,
      RequestStatus.approved => WfColors.cream,
      RequestStatus.partial || RequestStatus.available => WfColors.online,
      RequestStatus.declined || RequestStatus.failed => WfColors.error,
    };
```

`lib/features/requests/request_row.dart`:

```dart
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import '../inbox/inbox_time.dart';
import 'request_labels.dart';

/// Una riga della pagina Richieste (spec I §9.4): locandina, titolo e anno,
/// tipo o stagioni, chi l'ha chiesto, quando, e a destra lo stato (o
/// [trailing]).
class RequestRow extends StatelessWidget {
  const RequestRow({
    super.key,
    required this.request,
    required this.now,
    required this.onTap,
    this.showRequester = false,
    this.trailing,
  });

  /// Misure della locandina piccola (2:3).
  static const posterWidth = 46.0;
  static const posterHeight = 69.0;

  final MediaRequest request;

  /// Per l'ora relativa ("5 min fa").
  final DateTime now;
  final VoidCallback onTap;

  /// "chiesto da {name}", nelle schede da admin.
  final bool showRequester;

  /// Al posto dell'etichetta di stato (Approva e Rifiuta).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = request.title.isEmpty ? l.requestsUnknownTitle : request.title;
    final year = request.year;
    final seasons = request.seasons;
    final details = [
      if (request.mediaType == RequestMediaType.movie)
        l.requestsKindMovie
      else if (seasons.isEmpty)
        l.requestsKindSeries
      else
        l.requestsSeasonsList(seasons.length, formatSeasonList(seasons)),
      if (showRequester) l.requestsRequestedBy(request.requestedBy.name),
      inboxTimeLabel(request.createdAt, now, l),
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: posterWidth,
                height: posterHeight,
                child: WfImage(image: TmdbImages.poster(request.posterPath)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(year == null ? title : '$title ($year)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ?? RequestStatusLabel(request: request),
          ],
        ),
      ),
    );
  }
}

/// L'etichetta dello stato, con il bordo e il testo del suo colore.
class RequestStatusLabel extends StatelessWidget {
  const RequestStatusLabel({super.key, required this.request});

  final MediaRequest request;

  @override
  Widget build(BuildContext context) {
    final color = requestStatusColor(request.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        requestStatusLabel(AppLocalizations.of(context), request),
        style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
```

In `lib/features/requests/requests_navigation.dart` aggiungi:

```dart
/// Le schede della pagina Richieste (spec I §9.4).
enum RequestsTab {
  mine(RequestsFilter.mine),
  pending(RequestsFilter.pending),
  all(RequestsFilter.all);

  const RequestsTab(this.filter);

  final RequestsFilter filter;

  /// Dal parametro `tab` dell'indirizzo; `null` se manca o non vale.
  static RequestsTab? parse(String? raw) => switch (raw) {
        'mine' => mine,
        'pending' => pending,
        'all' => all,
        _ => null,
      };
}

/// Apre la pagina Richieste, sulla scheda [tab] se c'è (spec I §9.6).
void openRequests(BuildContext context, {RequestsTab? tab}) =>
    context.go(tab == null ? '/requests' : '/requests?tab=${tab.name}');

/// Apre una richiesta (spec I §9.4): la scheda della libreria se il titolo
/// c'è, altrimenti la scheda da richiedere.
void openRequest(BuildContext context, MediaRequest request) {
  final itemId = request.jellyfinItemId;
  if (itemId != null) {
    openItemById(context, itemId);
    return;
  }
  unawaited(context.push(tmdbRoute(request.mediaType, request.tmdbId)));
}
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/features/requests test/features/requests
git commit -m "feat(app): show request rows with their status"
```

### Task 4: pagina Richieste, rotta e voce nella barra

**Files:**
- Create: `lib/features/requests/requests_screen.dart`
- Modify: `lib/app/router.dart`, `lib/app/app_shell.dart`
- Test: `test/features/requests/requests_screen_test.dart`, `test/app/app_shell_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/requests/requests_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requests_navigation.dart';
import 'package:wonderflix/features/requests/requests_screen.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;
  const manager = RequestsMe(canRequest: true, canManage: true, hasAccount: true);

  setUp(() => api = FakeRequestsApi());

  Future<void> pumpScreen(WidgetTester tester, {RequestsTab? initialTab}) async {
    await pumpApp(
      tester,
      Scaffold(body: RequestsScreen(initialTab: initialTab)),
      overrides: requestsTestOverrides(api),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('utente normale: le sue richieste, senza schede', (tester) async {
    api.lists[RequestsFilter.mine] = [
      testMediaRequest(id: 1, title: 'Dune', year: 2021, status: RequestStatus.approved),
    ];
    await pumpScreen(tester);

    expect(find.text('RICHIESTE'), findsOneWidget);
    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text('Approvata'), findsOneWidget);
    expect(find.text('Le mie'), findsNothing);
    expect(find.textContaining('chiesto da'), findsNothing);
    expect(api.calls.where((c) => c.startsWith('list:pending')), isEmpty);
  });

  testWidgets('admin con richieste in attesa: si apre su "Da approvare (2)"',
      (tester) async {
    api
      ..meValue = manager
      ..lists[RequestsFilter.pending] = [
        testMediaRequest(id: 1, title: 'Dune', requester: 'Garg'),
        testMediaRequest(id: 2, title: 'Brothers', requester: 'sronweb'),
      ]
      ..lists[RequestsFilter.mine] = [testMediaRequest(id: 3, title: 'Mia')];
    await pumpScreen(tester);

    expect(find.text('Da approvare (2)'), findsOneWidget);
    expect(find.text('Le mie'), findsOneWidget);
    expect(find.text('Tutte'), findsOneWidget);
    expect(find.textContaining('chiesto da Garg'), findsOneWidget);
    expect(find.text('Mia (2024)'), findsNothing);

    await tester.tap(find.text('Le mie'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Mia (2024)'), findsOneWidget);
    expect(find.textContaining('chiesto da'), findsNothing);
  });

  testWidgets('admin senza richieste in attesa: si apre su "Le mie"',
      (tester) async {
    api.meValue = manager;
    await pumpScreen(tester);

    expect(find.text('Da approvare (0)'), findsOneWidget);
    expect(find.text('Non hai ancora chiesto niente. Cerca un titolo che manca e premi Richiedi.'),
        findsOneWidget);
  });

  testWidgets('scheda dall\'indirizzo e pagine vuote', (tester) async {
    api.meValue = manager;
    await pumpScreen(tester, initialTab: RequestsTab.all);
    expect(find.text('Nessuna richiesta'), findsOneWidget);

    await tester.tap(find.text('Da approvare (0)'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Niente da approvare'), findsOneWidget);
  });

  testWidgets('errore e Riprova', (tester) async {
    api.failure = RequestsFailure.network;
    await pumpScreen(tester);
    expect(find.text('Riprova'), findsOneWidget);

    api
      ..failure = null
      ..lists[RequestsFilter.mine] = [testMediaRequest(id: 1, title: 'Dune', year: 2021)];
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Dune (2021)'), findsOneWidget);
  });

  testWidgets('scorrendo in fondo carica le altre', (tester) async {
    api.lists[RequestsFilter.mine] = [
      for (var i = 1; i <= 25; i++) testMediaRequest(id: i, title: 'Titolo $i'),
    ];
    await pumpScreen(tester);
    expect(api.calls, isNot(contains('list:mine:20:20')));

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump();

    expect(api.calls, contains('list:mine:20:20'));
  });
}
```

In `test/app/app_shell_test.dart`:
- nel test che c'è, dopo `expect(find.text('Cerca'), findsOneWidget);`: `expect(find.text('Richieste'), findsNothing);`;
- aggiungi (con gli import `social_providers.dart` e `../support/social_fakes.dart`):

```dart
  testWidgets('voce "Richieste" solo con la funzione delle richieste',
      (tester) async {
    await pumpApp(
      tester,
      const AppShell(location: '/requests', child: SizedBox()),
      overrides: [
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        socialAvailabilityProvider.overrideWith(
            () => FakeSocialAvailability(const SocialFeatures(requests: true))),
      ],
    );

    expect(find.text('Richieste'), findsOneWidget);
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/requests/requests_screen_test.dart test/app/app_shell_test.dart`
Expected: FAIL (`requests_screen.dart` non esiste, nessuna voce "Richieste").

- [ ] **Step 3: la pagina**

`lib/features/requests/requests_screen.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'request_row.dart';
import 'requests_list_controller.dart';
import 'requests_navigation.dart';
import 'requests_providers.dart';

/// La pagina Richieste (spec I §9.4): "Le mie" e, per chi può approvare,
/// "Da approvare (n)" e "Tutte". Senza una scheda scelta si apre su "Da
/// approvare" se c'è qualcosa da approvare, altrimenti su "Le mie".
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key, this.initialTab});

  /// La scheda dell'indirizzo (`?tab=`), se c'è.
  final RequestsTab? initialTab;

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  /// La scheda scelta dall'utente; `null` finché non ne sceglie una.
  RequestsTab? _chosen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final me = ref.watch(requestsMeProvider);
    final canManage = me.value?.canManage ?? false;
    final count = canManage ? ref.watch(pendingRequestsCountProvider(language)) : null;
    final explicit = _chosen ?? widget.initialTab;
    // Per scegliere da sola la scheda la pagina aspetta i permessi e, per
    // chi approva, il conteggio.
    final ready = (me.hasValue || me.hasError) &&
        (count == null || count.hasValue || count.hasError || explicit != null);
    final tabs = [
      RequestsTab.mine,
      if (canManage) ...[RequestsTab.pending, RequestsTab.all],
    ];
    final pendingCount = count?.value;
    var tab = explicit ??
        ((pendingCount?.count ?? 0) > 0 ? RequestsTab.pending : RequestsTab.mine);
    if (!tabs.contains(tab)) tab = RequestsTab.mine;

    String tabLabel(RequestsTab tab) => switch (tab) {
          RequestsTab.mine => l.requestsTabMine,
          RequestsTab.pending => pendingCount == null
              ? l.requestsTabPending
              : l.requestsTabPendingCount(pendingCountLabel(pendingCount)),
          RequestsTab.all => l.requestsTabAll,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
          child: Text(l.navRequests.toUpperCase(), style: WfText.display(40)),
        ),
        if (!ready)
          const Expanded(child: LoadingView())
        else ...[
          if (tabs.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  for (final item in tabs) ...[
                    _TabButton(
                      key: ValueKey('requests-tab-${item.name}'),
                      label: tabLabel(item),
                      selected: item == tab,
                      onTap: () => setState(() => _chosen = item),
                    ),
                    const SizedBox(width: 24),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _RequestsList(
              key: ValueKey(tab),
              tab: tab,
              listKey: (filter: tab.filter, language: language),
            ),
          ),
        ],
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
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

class _RequestsList extends ConsumerStatefulWidget {
  const _RequestsList({super.key, required this.tab, required this.listKey});

  final RequestsTab tab;
  final RequestsListKey listKey;

  @override
  ConsumerState<_RequestsList> createState() => _RequestsListState();
}

class _RequestsListState extends ConsumerState<_RequestsList> {
  /// Quanto manca alla fine dell'elenco quando si chiede la pagina dopo.
  static const _loadMoreWithin = 600.0;

  final _scroll = SmoothScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < _loadMoreWithin) {
        unawaited(ref
            .read(requestsListControllerProvider(widget.listKey).notifier)
            .loadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _emptyText(AppLocalizations l) => switch (widget.tab) {
        RequestsTab.mine => l.requestsEmptyMine,
        RequestsTab.pending => l.requestsEmptyPending,
        RequestsTab.all => l.requestsEmptyAll,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = requestsListControllerProvider(widget.listKey);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final error = state.error;
    if (state.items.isEmpty) {
      if (error != null) {
        return ErrorView(error: error, onRetry: () => unawaited(controller.reload()));
      }
      if (state.loading) return const LoadingView();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(_emptyText(l), style: const TextStyle(color: WfColors.creamMuted)),
      );
    }
    final now = clock.now();
    final footer = state.loading || error != null;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      itemCount: state.items.length + (footer ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: error != null
                  ? TextButton(
                      onPressed: () => unawaited(controller.loadMoreAfterError()),
                      child: Text(l.retry))
                  : const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final request = state.items[index];
        return RequestRow(
          key: ValueKey('request-${request.id}'),
          request: request,
          now: now,
          showRequester: widget.tab != RequestsTab.mine,
          onTap: () => openRequest(context, request),
        );
      },
    );
  }
}
```

In `requests_list_controller.dart`, sotto `loadMore`, aggiungi:

```dart
  /// La pagina successiva dopo un errore (il pulsante in fondo all'elenco).
  Future<void> loadMoreAfterError() => _load(reset: false);
```

- [ ] **Step 4: rotta e voce nella barra**

In `lib/app/router.dart` importa `../features/requests/requests_navigation.dart` e `../features/requests/requests_screen.dart` e, nella `ShellRoute`, dopo la rotta `/mylist`:

```dart
          GoRoute(
              path: '/requests',
              pageBuilder: (context, state) => shellPage(
                  context,
                  state,
                  RequestsScreen(
                      key: ValueKey(state.uri.toString()),
                      initialTab:
                          RequestsTab.parse(state.uri.queryParameters['tab'])),
                  underBar: true)),
```

In `lib/app/app_shell.dart` importa `../features/requests/requests_providers.dart` e, nella lista di `_NavBar`, dopo la voce di `/mylist`:

```dart
                          // Solo con le richieste con Seerr (spec I §9.4).
                          if (ref.watch(requestsAvailableProvider))
                            (label: l.navRequests, route: '/requests', icon: null),
```

- [ ] **Step 5: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 6: commit**

```bash
git add lib test
git commit -m "feat(app): add the requests page and its menu entry"
```

## Gruppo B — Approva e Rifiuta

### Task 5: finestre dell'app e finestra Approva

**Files:**
- Create: `lib/ui/wf_dialog.dart`
- Create: `lib/features/requests/approve_dialog.dart`
- Test: `test/ui/wf_dialog_test.dart`, `test/features/requests/approve_dialog_test.dart`

- [ ] **Step 1: test che falliscono**

`test/ui/wf_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/wf_dialog.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('finestra: aspetto, valore restituito, Esc chiude', (tester) async {
    String? result = 'niente';
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showWfDialog<String>(
                context,
                builder: (dialogContext) => TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop('ok'),
                  child: const Text('conferma'),
                ),
              );
            },
            child: const Text('apri'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('conferma'), findsOneWidget);
    expect(tester.widget<Dialog>(find.byType(Dialog)).backgroundColor, WfColors.surface);

    await tester.tap(find.text('conferma'));
    await tester.pumpAndSettle();
    expect(result, 'ok');

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('conferma'), findsNothing);
    expect(result, isNull);
  });
}
```

`test/features/requests/approve_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/approve_dialog.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;

  setUp(() {
    api = FakeRequestsApi()
      ..servicesByType[RequestMediaType.movie] = const [
        ServiceOption(
          id: 0,
          name: 'Radarr',
          isDefault: true,
          profiles: [ProfileOption(id: 8, name: 'Main Profile')],
          rootFolders: ['/media/movies'],
          defaultProfileId: 8,
          defaultRootFolder: '/media/movies',
        ),
        ServiceOption(
          id: 1,
          name: 'Radarr Anime',
          isDefault: false,
          profiles: [
            ProfileOption(id: 7, name: 'Anime Main Profile'),
            ProfileOption(id: 8, name: 'Main Profile'),
          ],
          rootFolders: ['/media/anime', '/media/movies'],
          defaultProfileId: 7,
          defaultRootFolder: '/media/anime',
        ),
      ];
  });

  /// Apre la finestra e restituisce come leggere la scelta.
  Future<ApproveChoice? Function()> openDialog(WidgetTester tester) async {
    ApproveChoice? result;
    var closed = false;
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showApproveDialog(
                  context, testMediaRequest(id: 53, title: 'Dune'));
              closed = true;
            },
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: requestsTestOverrides(api),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    return () {
      expect(closed, isTrue);
      return result;
    };
  }

  testWidgets('"Predefinito": nessun profilo né cartella, decide Seerr',
      (tester) async {
    final choice = await openDialog(tester);

    expect(find.text('Approva: Dune'), findsOneWidget);
    expect(find.text('Predefinito (Radarr)'), findsOneWidget);
    expect(find.text('Profilo'), findsNothing);

    await tester.tap(find.text('Approva'));
    await tester.pumpAndSettle();

    final result = choice()!;
    expect((result.serverId, result.profileId, result.rootFolder), (null, null, null));
    expect(api.calls, ['services:movie']);
  });

  testWidgets('un altro server: profilo e cartella, con i suoi predefiniti',
      (tester) async {
    final choice = await openDialog(tester);

    await tester.tap(find.byKey(const Key('approve-server')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radarr Anime').last);
    await tester.pumpAndSettle();

    expect(find.text('Profilo'), findsOneWidget);
    expect(find.text('Anime Main Profile'), findsOneWidget);
    expect(find.text('/media/anime'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('/media/movies').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approva'));
    await tester.pumpAndSettle();

    final result = choice()!;
    expect((result.serverId, result.profileId, result.rootFolder), (1, 7, '/media/movies'));
  });

  testWidgets('server non disponibili: solo "Predefinito" con una nota',
      (tester) async {
    api.servicesFailure = RequestsFailure.seerrUnavailable;
    final choice = await openDialog(tester);

    expect(find.text('Predefinito'), findsOneWidget);
    expect(find.text('Server non disponibili: si approva con i valori predefiniti'),
        findsOneWidget);

    await tester.tap(find.text('Approva'));
    await tester.pumpAndSettle();
    expect(choice()!.serverId, isNull);
  });

  testWidgets('Annulla: nessuna scelta', (tester) async {
    final choice = await openDialog(tester);

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(choice(), isNull);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/ui/wf_dialog_test.dart test/features/requests/approve_dialog_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`lib/ui/wf_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Il velo dietro le finestre: il nero dell'app, quasi opaco.
const _barrier = Color(0xB30A0A0A);

/// Una finestra dell'app (decisione 2 del piano 15b): fondo `surface`,
/// bordo, angoli arrotondati, larga al massimo [maxWidth]. Esc e il clic
/// fuori la chiudono con `null`.
Future<T?> showWfDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 480,
}) =>
    showDialog<T>(
      context: context,
      barrierColor: _barrier,
      builder: (context) => Dialog(
        backgroundColor: WfColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: WfColors.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
```

`lib/features/requests/approve_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import 'requests_providers.dart';

/// I server di Radarr (film) o Sonarr (serie) per la finestra Approva.
final requestServicesProvider = FutureProvider.autoDispose
    .family<List<ServiceOption>, RequestMediaType>(
        (ref, type) => ref.watch(requestsApiProvider).services(type));

/// Apre la finestra Approva (spec I §9.5): la scelta, o `null` se annullata.
Future<ApproveChoice?> showApproveDialog(
        BuildContext context, MediaRequest request) =>
    showWfDialog<ApproveChoice>(context,
        builder: (_) => ApproveDialog(request: request));

/// Approva con il server "Predefinito" (decide Seerr, anche per gli anime)
/// oppure con un server, un profilo e una cartella scelti (spec I §9.5).
class ApproveDialog extends ConsumerStatefulWidget {
  const ApproveDialog({super.key, required this.request});

  final MediaRequest request;

  @override
  ConsumerState<ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends ConsumerState<ApproveDialog> {
  /// Il valore del menu per "Predefinito": gli id dei server partono da 0.
  static const _defaultServer = -1;

  int _serverId = _defaultServer;
  int? _profileId;
  String? _folder;

  void _selectServer(List<ServiceOption> servers, int? serverId) {
    setState(() {
      _serverId = serverId ?? _defaultServer;
      final server = servers.where((s) => s.id == serverId).firstOrNull;
      if (server == null) {
        _profileId = null;
        _folder = null;
        return;
      }
      final profiles = server.profiles.map((p) => p.id).toList();
      _profileId = profiles.contains(server.defaultProfileId)
          ? server.defaultProfileId
          : profiles.firstOrNull;
      _folder = server.rootFolders.contains(server.defaultRootFolder)
          ? server.defaultRootFolder
          : server.rootFolders.firstOrNull;
    });
  }

  /// La scelta; `null` se manca il profilo o la cartella di un server scelto.
  ApproveChoice? get _choice {
    if (_serverId == _defaultServer) return ApproveChoice.defaults;
    final profileId = _profileId;
    final folder = _folder;
    if (profileId == null || folder == null) return null;
    return ApproveChoice(serverId: _serverId, profileId: profileId, rootFolder: folder);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final request = widget.request;
    final title = request.title.isEmpty ? l.requestsUnknownTitle : request.title;
    final services = ref.watch(requestServicesProvider(request.mediaType));
    final servers = services.value ?? const <ServiceOption>[];
    final defaultServer = servers.where((s) => s.isDefault).firstOrNull;
    final server = servers.where((s) => s.id == _serverId).firstOrNull;
    final choice = _choice;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.requestsApproveTitle(title),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        if (services.isLoading && !services.hasValue)
          const SkeletonBox(height: 48)
        else ...[
          _Field(
            label: l.requestsServer,
            child: DropdownButton<int>(
              key: const Key('approve-server'),
              isExpanded: true,
              value: _serverId,
              dropdownColor: WfColors.surfaceHigh,
              items: [
                DropdownMenuItem(
                  value: _defaultServer,
                  child: Text(defaultServer == null
                      ? l.requestsServerDefaultPlain
                      : l.requestsServerDefault(defaultServer.name)),
                ),
                for (final option in servers)
                  DropdownMenuItem(value: option.id, child: Text(option.name)),
              ],
              onChanged: (value) => _selectServer(servers, value),
            ),
          ),
          if (services.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.requestsServersUnavailable,
                  style: const TextStyle(color: WfColors.creamMuted, fontSize: 13)),
            ),
          if (server != null) ...[
            const SizedBox(height: 12),
            _Field(
              label: l.requestsProfile,
              child: DropdownButton<int>(
                key: const Key('approve-profile'),
                isExpanded: true,
                value: _profileId,
                dropdownColor: WfColors.surfaceHigh,
                items: [
                  for (final profile in server.profiles)
                    DropdownMenuItem(value: profile.id, child: Text(profile.name)),
                ],
                onChanged: (value) => setState(() => _profileId = value),
              ),
            ),
            const SizedBox(height: 12),
            _Field(
              label: l.requestsFolder,
              child: DropdownButton<String>(
                key: const Key('approve-folder'),
                isExpanded: true,
                value: _folder,
                dropdownColor: WfColors.surfaceHigh,
                items: [
                  for (final folder in server.rootFolders)
                    DropdownMenuItem(value: folder, child: Text(folder)),
                ],
                onChanged: (value) => setState(() => _folder = value),
              ),
            ),
          ],
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.requestsCancel),
            ),
            const SizedBox(width: 12),
            WfButton.primary(
              label: l.requestsApprove,
              icon: LucideIcons.check,
              onPressed: choice == null ? null : () => Navigator.of(context).pop(choice),
            ),
          ],
        ),
      ],
    );
  }
}

/// Un menu con la sua etichetta sopra.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: WfColors.creamMuted, fontSize: 12.5)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/ui/wf_dialog.dart lib/features/requests/approve_dialog.dart test/ui/wf_dialog_test.dart test/features/requests/approve_dialog_test.dart
git commit -m "feat(app): add the app dialog and the approve window"
```

### Task 6: Approva e Rifiuta nella scheda "Da approvare"

**Files:**
- Create: `lib/features/requests/pending_request_actions.dart`
- Modify: `lib/features/requests/requests_screen.dart`
- Test: `test/features/requests/pending_request_actions_test.dart`, `test/features/requests/requests_screen_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/requests/pending_request_actions_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/requests/pending_request_actions.dart';

import '../../support/pump_app.dart';

void main() {
  Future<List<String>> pumpActions(WidgetTester tester, {bool busy = false}) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: PendingRequestActions(
          busy: busy,
          onApprove: () => calls.add('approva'),
          onDecline: () => calls.add('rifiuta'),
        ),
      ),
    );
    return calls;
  }

  testWidgets('Rifiuta chiede conferma con un secondo clic', (tester) async {
    final calls = await pumpActions(tester);

    await tester.tap(find.text('Rifiuta'));
    await tester.pump();
    expect(find.text('Conferma'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.text('Conferma'));
    await tester.pump();
    expect(calls, ['rifiuta']);
    expect(find.text('Rifiuta'), findsOneWidget);
  });

  testWidgets('la conferma scade', (tester) async {
    final calls = await pumpActions(tester);

    await tester.tap(find.text('Rifiuta'));
    await tester.pump();
    await tester.pump(declineConfirmFor);

    expect(find.text('Rifiuta'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('Approva; durante l\'invio solo l\'indicatore', (tester) async {
    final calls = await pumpActions(tester);
    await tester.tap(find.text('Approva'));
    expect(calls, ['approva']);

    await pumpActions(tester, busy: true);
    expect(find.text('Approva'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
```

In `test/features/requests/requests_screen_test.dart` aggiungi:

```dart
  group('Da approvare', () {
    setUp(() {
      api
        ..meValue = manager
        ..lists[RequestsFilter.pending] = [
          testMediaRequest(id: 1, title: 'Dune', requester: 'Garg'),
          testMediaRequest(id: 2, title: 'Brothers', requester: 'sronweb'),
        ]
        ..servicesByType[RequestMediaType.movie] = const [
          ServiceOption(
            id: 0,
            name: 'Radarr',
            isDefault: true,
            profiles: [ProfileOption(id: 8, name: 'Main Profile')],
            rootFolders: ['/media/movies'],
          ),
        ];
    });

    testWidgets('Approva: finestra, poi la riga esce e c\'è l\'avviso',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Approva').first);
      await tester.pumpAndSettle();
      expect(find.text('Approva: Dune'), findsOneWidget);

      await tester.tap(find.text('Approva').last);
      await tester.pumpAndSettle();

      expect(api.approved.single.id, 1);
      expect(api.approved.single.choice.serverId, isNull);
      expect(find.text('Dune (2024)'), findsNothing);
      expect(find.text('Brothers (2024)'), findsOneWidget);
      expect(find.text('Approvata'), findsOneWidget);
    });

    testWidgets('Rifiuta con conferma', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Rifiuta').last);
      await tester.pump();
      await tester.tap(find.text('Conferma'));
      await tester.pump();
      await tester.pump();

      expect(api.declined, [2]);
      expect(find.text('Brothers (2024)'), findsNothing);
      expect(find.text('Rifiutata'), findsOneWidget);
    });

    testWidgets('un errore lascia la riga e lo dice', (tester) async {
      api.actionFailure = RequestsFailure.seerrUnavailable;
      await pumpScreen(tester);

      await tester.tap(find.text('Rifiuta').first);
      await tester.pump();
      await tester.tap(find.text('Conferma'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Dune (2024)'), findsOneWidget);
      expect(find.text('Non riuscito, riprova'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/requests/pending_request_actions_test.dart test/features/requests/requests_screen_test.dart`
Expected: FAIL (`pending_request_actions.dart` non esiste, nessun Approva nelle righe).

- [ ] **Step 3: implementazione**

`lib/features/requests/pending_request_actions.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';

/// Quanto resta "Conferma" dopo il primo clic su Rifiuta, come "Svuota"
/// della cassetta (decisione 1 del piano 15b).
const declineConfirmFor = Duration(seconds: 4);

/// Rifiuta (a due tempi) e Approva in una riga di "Da approvare" (spec I
/// §9.4). Con [busy] c'è solo l'indicatore.
class PendingRequestActions extends StatefulWidget {
  const PendingRequestActions({
    super.key,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
  });

  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  State<PendingRequestActions> createState() => _PendingRequestActionsState();
}

class _PendingRequestActionsState extends State<PendingRequestActions> {
  Timer? _confirm;

  @override
  void dispose() {
    _confirm?.cancel();
    super.dispose();
  }

  void _ask() {
    _confirm?.cancel();
    setState(() {
      _confirm = Timer(declineConfirmFor, () {
        if (mounted) setState(() => _confirm = null);
      });
    });
  }

  void _decline() {
    _confirm?.cancel();
    setState(() => _confirm = null);
    widget.onDecline();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.busy) {
      return const SizedBox.square(
          dimension: 20, child: CircularProgressIndicator(strokeWidth: 2));
    }
    final l = AppLocalizations.of(context);
    final confirming = _confirm != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          // Stessa chiave nei due tempi: il fuoco da tastiera resta.
          key: const Key('request-decline'),
          onPressed: confirming ? _decline : _ask,
          style: TextButton.styleFrom(
              foregroundColor: confirming ? WfColors.error : WfColors.creamMuted),
          child: Text(confirming ? l.requestsDeclineConfirm : l.requestsDecline),
        ),
        const SizedBox(width: 8),
        WfButton.primary(
          label: l.requestsApprove,
          icon: LucideIcons.check,
          onPressed: widget.onApprove,
        ),
      ],
    );
  }
}
```

In `lib/features/requests/requests_screen.dart`:
- importa `../../core/requests/requests_models.dart`, `approve_dialog.dart` e `pending_request_actions.dart`;
- in `_RequestsListState` aggiungi:

```dart
  Future<void> _approve(MediaRequest request) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showApproveDialog(context, request);
    if (choice == null || !mounted) return;
    final outcome = await ref
        .read(requestsListControllerProvider(widget.listKey).notifier)
        .approve(request.id, choice);
    if (outcome != null) {
      messenger.showSnackBar(SnackBar(content: Text(requestActionText(l, outcome))));
    }
  }

  Future<void> _decline(MediaRequest request) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(requestsListControllerProvider(widget.listKey).notifier)
        .decline(request.id);
    if (outcome != null) {
      messenger.showSnackBar(SnackBar(content: Text(requestActionText(l, outcome))));
    }
  }
```

- nel `RequestRow` di `itemBuilder` aggiungi:

```dart
          trailing: widget.tab == RequestsTab.pending
              ? PendingRequestActions(
                  busy: state.busy.contains(request.id),
                  onApprove: () => unawaited(_approve(request)),
                  onDecline: () => unawaited(_decline(request)),
                )
              : null,
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/features/requests test/features/requests
git commit -m "feat(app): approve and decline requests from the requests page"
```

## Gruppo C — serie della libreria e cassetta

### Task 7: "Richiedi stagioni" sulle serie della libreria

**Files:**
- Create: `lib/features/requests/request_seasons.dart`
- Modify: `lib/features/detail/detail_header.dart`
- Test: `test/features/requests/request_seasons_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/requests/request_seasons_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakeRequestsApi requests;

  setUp(() {
    library = FakeLibraryApi()
      ..itemsById['s1'] = testItem(
          id: 's1',
          name: 'The Last of Us',
          kind: ItemKind.series,
          childCount: 1,
          tmdbId: 100088)
      ..seasonsBySeries['s1'] = [
        testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.season, index: 1),
      ];
    requests = FakeRequestsApi()
      ..titles[100088] = testDetails(
        tmdbId: 100088,
        title: 'The Last of Us',
        type: RequestMediaType.tv,
        status: TitleStatus.partial,
        seasons: const [
          SeasonInfo(seasonNumber: 1, episodeCount: 9, status: TitleStatus.available),
          SeasonInfo(seasonNumber: 2, episodeCount: 7),
          SeasonInfo(seasonNumber: 3, episodeCount: 8),
        ],
      );
  });

  Future<void> pumpSeries(WidgetTester tester, {bool available = true}) async {
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 's1')),
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        ...requestsTestOverrides(requests, available: available),
      ],
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('stagioni mancanti: "Richiedi stagioni" apre la scelta e chiede',
      (tester) async {
    await pumpSeries(tester);
    expect(find.text('Richiedi stagioni'), findsOneWidget);

    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(find.descendant(of: dialog, matching: find.text('The Last of Us')), findsOneWidget);
    expect(find.text('Stagione 2 · 7 episodi'), findsOneWidget);

    await tester.tap(find.text('Stagione 3 · 8 episodi'));
    await tester.pump();
    await tester.tap(find.text('Richiedi 1 stagione'));
    await tester.pumpAndSettle();

    expect(requests.created.single.seasons, [2]);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Richiesta inviata'), findsOneWidget);
  });

  testWidgets('nessuna stagione da chiedere: niente pulsante', (tester) async {
    requests.titles[100088] = testDetails(
      tmdbId: 100088,
      type: RequestMediaType.tv,
      status: TitleStatus.available,
      seasons: const [
        SeasonInfo(seasonNumber: 1, episodeCount: 9, status: TitleStatus.available),
      ],
    );
    await pumpSeries(tester);

    expect(find.text('Richiedi stagioni'), findsNothing);
  });

  testWidgets('senza la funzione: niente pulsante e niente Seerr', (tester) async {
    await pumpSeries(tester, available: false);

    expect(find.text('Richiedi stagioni'), findsNothing);
    expect(requests.calls, isEmpty);
  });

  testWidgets('chi non può chiedere non vede il pulsante', (tester) async {
    requests.meValue =
        const RequestsMe(canRequest: false, canManage: false, hasAccount: true);
    await pumpSeries(tester);

    expect(find.text('Richiedi stagioni'), findsNothing);
    expect(requests.calls.where((c) => c.startsWith('title:')), isEmpty);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/requests/request_seasons_test.dart`
Expected: FAIL (nessun "Richiedi stagioni").

- [ ] **Step 3: implementazione**

`lib/features/requests/request_seasons.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import 'request_title_controller.dart';
import 'requests_providers.dart';
import 'season_picker.dart';

/// La serie della libreria ha stagioni che si possono chiedere (spec I
/// §9.3). La scheda di Seerr si carica in silenzio, e solo con la funzione
/// e se l'utente può chiedere; un errore vale "no".
final seasonsToRequestProvider =
    Provider.autoDispose.family<bool, RequestTitleKey>((ref, key) {
  if (!ref.watch(requestsAvailableProvider)) return false;
  if (!(ref.watch(requestsMeProvider).value?.canRequest ?? false)) return false;
  final details = ref.watch(requestTitleControllerProvider(key)).details;
  return details != null && details.requestableSeasons.isNotEmpty;
});

/// Apre "Richiedi stagioni" (spec I §9.3) e mostra l'esito come avviso.
Future<void> showRequestSeasonsDialog(
    BuildContext context, RequestTitleKey key, String title) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await showWfDialog<RequestOutcome>(context,
      builder: (_) => RequestSeasonsDialog(titleKey: key, title: title));
  if (outcome != null) {
    messenger.showSnackBar(SnackBar(content: Text(requestOutcomeText(l, outcome))));
  }
}

/// Le stagioni con le caselle, Annulla e Richiedi: lo stesso controller
/// della scheda da richiedere (decisione 7 del piano 15b).
class RequestSeasonsDialog extends ConsumerWidget {
  const RequestSeasonsDialog({super.key, required this.titleKey, required this.title});

  /// Altezza massima dell'elenco delle stagioni; oltre scorre.
  static const _seasonsMaxHeight = 360.0;

  final RequestTitleKey titleKey;

  /// Il nome della serie nella libreria.
  final String title;

  Future<void> _submit(BuildContext context, RequestTitleController controller) async {
    final outcome = await controller.submit();
    if (context.mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final provider = requestTitleControllerProvider(titleKey);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final details = state.details;
    if (details == null) return const SizedBox(height: 120, child: LoadingView());
    final chosen = state.selected.length;
    final all = chosen == details.requestableSeasons.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.requestsMoreSeasons,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(color: WfColors.creamMuted)),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _seasonsMaxHeight),
          child: SingleChildScrollView(
            child: SeasonPicker(
              seasons: details.seasons,
              selected: state.selected,
              enabled: !state.sending,
              onToggle: controller.toggleSeason,
              onToggleAll: controller.toggleAll,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.requestsCancel),
            ),
            const SizedBox(width: 12),
            WfButton.primary(
              label: all ? l.requestsRequest : l.requestsRequestSeasons(chosen),
              icon: LucideIcons.plus,
              onPressed: state.sending || chosen == 0
                  ? null
                  : () => unawaited(_submit(context, controller)),
            ),
          ],
        ),
      ],
    );
  }
}
```

In `lib/features/detail/detail_header.dart`:
- importa `../../core/requests/requests_models.dart` e `../requests/request_seasons.dart`;
- in `build`, dopo `final hasTrailer = …;`:

```dart
    // Serie della libreria con stagioni che mancano (spec I §9.3): la
    // scheda di Seerr si carica solo per le serie con l'id TMDB.
    final tmdbId = item.kind == ItemKind.series ? item.tmdbId : null;
    final seasonsKey = tmdbId == null
        ? null
        : (
            type: RequestMediaType.tv,
            tmdbId: tmdbId,
            language: Localizations.localeOf(context).languageCode,
          );
    final canRequestSeasons =
        seasonsKey != null && ref.watch(seasonsToRequestProvider(seasonsKey));
```

- nel `Wrap` dei pulsanti, subito dopo il pulsante Trailer:

```dart
                        if (seasonsKey != null && canRequestSeasons)
                          WfButton.secondary(
                            label: l.requestsMoreSeasons,
                            icon: LucideIcons.plus,
                            onPressed: () => unawaited(showRequestSeasonsDialog(
                                context, seasonsKey, item.name)),
                          ),
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde (anche i test delle schede di oggi: `testItem` senza `tmdbId` non tocca Seerr).

- [ ] **Step 5: commit**

```bash
git add lib/features/requests/request_seasons.dart lib/features/detail/detail_header.dart test/features/requests/request_seasons_test.dart
git commit -m "feat(app): request missing seasons from the series page"
```

### Task 8: righe delle richieste nella cassetta

**Files:**
- Modify: `lib/core/social/inbox_models.dart`
- Create: `lib/features/inbox/inbox_request_rows.dart`
- Modify: `lib/features/inbox/inbox_panel.dart`
- Modify: `test/support/social_fakes.dart`
- Test: `test/core/social/inbox_models_test.dart`, `test/features/inbox/inbox_panel_test.dart`, `test/features/inbox/inbox_requests_navigation_test.dart`

- [ ] **Step 1: test che falliscono**

In `test/core/social/inbox_models_test.dart` aggiungi:

```dart
  test('voci delle richieste', () {
    final available = inboxEntryFromJson({
      'Id': 'r1',
      'Seq': 3,
      'Type': 'RequestAvailable',
      'CreatedAt': '2026-10-05T12:00:00+00:00',
      'Read': false,
      'RequestId': 53,
      'MediaType': 'tv',
      'TmdbId': 250203,
      'Title': 'Brothers (2026)',
      'Seasons': [1, 2],
      'ItemId': '6d1c8ea33a794f76fdbe92a216959073',
    }) as RequestAvailableEntry;
    expect(available.title, 'Brothers (2026)');
    expect(available.seasons, [1, 2]);
    expect(available.itemId, '6d1c8ea33a794f76fdbe92a216959073');

    final pending = inboxEntryFromJson({
      'Id': 'r2',
      'Seq': 4,
      'Type': 'RequestPending',
      'CreatedAt': '2026-10-05T12:00:00+00:00',
      'Read': true,
      'RequestId': 54,
      'MediaType': 'movie',
      'TmdbId': 438631,
      'Title': 'Dune (2021)',
      'RequesterName': 'Garg',
    }) as RequestPendingEntry;
    expect(pending.title, 'Dune (2021)');
    expect(pending.requesterName, 'Garg');
    expect(pending.seasons, isEmpty);
    expect(pending.read, isTrue);
  });
```

In `test/support/social_fakes.dart`, dopo `testNewTitles`:

```dart
RequestAvailableEntry testRequestAvailable({
  String id = 'r1',
  int seq = 1,
  bool read = false,
  String title = 'Dune (2021)',
  List<int> seasons = const [],
  String? itemId,
  DateTime? createdAt,
}) =>
    RequestAvailableEntry(
      id: id,
      seq: seq,
      createdAt: createdAt ?? DateTime.utc(2026, 10, 5, 10),
      read: read,
      title: title,
      seasons: seasons,
      itemId: itemId,
    );

RequestPendingEntry testRequestPending({
  String id = 'p1',
  int seq = 1,
  bool read = false,
  String title = 'Dune (2021)',
  String requesterName = 'Garg',
  List<int> seasons = const [],
  DateTime? createdAt,
}) =>
    RequestPendingEntry(
      id: id,
      seq: seq,
      createdAt: createdAt ?? DateTime.utc(2026, 10, 5, 10),
      read: read,
      title: title,
      requesterName: requesterName,
      seasons: seasons,
    );
```

In `test/features/inbox/inbox_panel_test.dart` aggiungi:

```dart
  testWidgets('richieste: "Ora disponibile" e "ha chiesto", con le stagioni',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testRequestAvailable(
          id: 'r1',
          seq: 2,
          title: 'Brothers (2026)',
          seasons: const [1, 2],
          createdAt: fiveMinutesAgo()),
      testRequestPending(id: 'p1', seq: 1, createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester);

    expect(find.text('Ora disponibile: Brothers (2026), stagioni 1–2'), findsOneWidget);
    expect(find.text('Garg ha chiesto Dune (2021)'), findsOneWidget);
    expect(find.text('5 min fa'), findsNWidgets(2));
  });
```

`test/features/inbox/inbox_requests_navigation_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  /// Apre il pannello con [entries] in un router con la pagina Richieste e
  /// la scheda `/item/:id`.
  Future<(GoRouter, ProviderContainer)> pumpPanel(
      WidgetTester tester, List<InboxEntry> entries) async {
    final api = FakeSocialApi()
      ..inboxSnapshot = InboxSnapshot(entries: entries, unread: entries.length);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: InboxPanel.width, child: InboxPanel()),
            ),
          ),
        ),
        GoRoute(path: '/requests', builder: (context, state) => const Text('richieste')),
        GoRoute(path: '/item/:id', builder: (context, state) => const Text('scheda')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider.overrideWithValue((image, fit) => const SizedBox.shrink()),
        ...socialTestOverrides(api, features: const SocialFeatures(inbox: true)),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(InboxPanel)));
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    return (router, container);
  }

  testWidgets('"ha chiesto" apre Richieste su "Da approvare" e chiude il pannello',
      (tester) async {
    final (router, container) = await pumpPanel(tester, [testRequestPending()]);

    await tester.tap(find.text('Garg ha chiesto Dune (2021)'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/requests?tab=pending');
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  testWidgets('"Ora disponibile" apre la scheda, o Richieste senza id', (tester) async {
    final (router, container) = await pumpPanel(tester, [
      testRequestAvailable(id: 'r1', seq: 2, title: 'Dune (2021)', itemId: 'ee39'),
      testRequestAvailable(id: 'r2', seq: 1, title: 'Brothers (2026)'),
    ]);

    await tester.tap(find.text('Ora disponibile: Dune (2021)'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/ee39');

    // Di nuovo nella pagina con il pannello: il contenitore è lo stesso.
    router.go('/');
    await tester.pumpAndSettle();
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    await tester.tap(find.text('Ora disponibile: Brothers (2026)'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/requests');
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/social/inbox_models_test.dart test/features/inbox`
Expected: FAIL di compilazione (`RequestAvailableEntry` non esiste).

- [ ] **Step 3: modelli**

In `lib/core/social/inbox_models.dart`, dopo `NewTitlesEntry`:

```dart
/// Un titolo chiesto è arrivato (spec I §9.6), a chi l'aveva chiesto.
final class RequestAvailableEntry extends InboxEntry {
  const RequestAvailableEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    required this.title,
    this.seasons = const [],
    this.itemId,
  });

  /// "Dune (2021)", dal webhook di Seerr.
  final String title;

  /// Le stagioni chieste, per le serie.
  final List<int> seasons;

  /// L'elemento della libreria, se Seerr lo conosce.
  final String? itemId;
}

/// Una richiesta da approvare (spec I §9.6), a chi può approvare.
final class RequestPendingEntry extends InboxEntry {
  const RequestPendingEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    required this.title,
    required this.requesterName,
    this.seasons = const [],
  });

  final String title;
  final String requesterName;
  final List<int> seasons;
}
```

In `inboxEntryFromJson`, prima di `_ => null,`:

```dart
    'RequestAvailable' => RequestAvailableEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        title: json['Title'] as String? ?? '',
        seasons: _seasons(json['Seasons']),
        itemId: json['ItemId'] as String?,
      ),
    'RequestPending' => RequestPendingEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        title: json['Title'] as String? ?? '',
        requesterName: json['RequesterName'] as String? ?? '',
        seasons: _seasons(json['Seasons']),
      ),
```

e, dopo la funzione:

```dart
List<int> _seasons(Object? raw) =>
    [for (final season in raw as List? ?? const []) (season as num).toInt()];
```

- [ ] **Step 4: righe e pannello**

`lib/features/inbox/inbox_request_rows.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../requests/request_labels.dart';

/// Il titolo di una voce delle richieste, con le stagioni se ci sono:
/// "Brothers (2026), stagioni 1–2". Senza titolo da Seerr, "Titolo non
/// disponibile".
String inboxRequestTitle(AppLocalizations l, String title, List<int> seasons) {
  final name = title.isEmpty ? l.requestsUnknownTitle : title;
  return seasons.isEmpty
      ? name
      : l.inboxRequestTitleSeasons(name, seasons.length, formatSeasonList(seasons));
}

/// L'icona tonda delle voci delle richieste (spec I §9.6).
class InboxRequestIcon extends StatelessWidget {
  const InboxRequestIcon({super.key, required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
            color: WfColors.surfaceHigh, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: WfColors.gold),
      );
}

/// Il testo di una voce delle richieste: il clic chiude il pannello e
/// poi [onOpen] apre la scheda o la pagina Richieste.
class InboxRequestContent extends ConsumerWidget {
  const InboxRequestContent({
    super.key,
    required this.text,
    required this.time,
    required this.onOpen,
  });

  final String text;
  final String time;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: () {
          ref.read(shellPanelProvider.notifier).close();
          onOpen();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  style: const TextStyle(
                      color: WfColors.cream, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(time,
                  style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
```

In `lib/features/inbox/inbox_panel.dart`:
- importa `inbox_request_rows.dart` e `../requests/requests_navigation.dart`;
- nel primo `switch (entry)` (le icone) aggiungi:

```dart
              RequestAvailableEntry() => const InboxRequestIcon(
                  icon: LucideIcons.clapperboard, size: InboxPanel.leadingSize),
              RequestPendingEntry() => const InboxRequestIcon(
                  icon: LucideIcons.inbox, size: InboxPanel.leadingSize),
```

- nel secondo (il contenuto):

```dart
                RequestAvailableEntry() => InboxRequestContent(
                    key: Key('inbox-request-${entry.id}'),
                    text: l.inboxRequestAvailable(
                        inboxRequestTitle(l, entry.title, entry.seasons)),
                    time: widget.time,
                    onOpen: () {
                      final itemId = entry.itemId;
                      if (itemId != null) {
                        openItemById(context, itemId);
                      } else {
                        openRequests(context);
                      }
                    },
                  ),
                RequestPendingEntry() => InboxRequestContent(
                    key: Key('inbox-request-${entry.id}'),
                    text: l.inboxRequestPending(entry.requesterName,
                        inboxRequestTitle(l, entry.title, entry.seasons)),
                    time: widget.time,
                    onOpen: () => openRequests(context, tab: RequestsTab.pending),
                  ),
```

- [ ] **Step 5: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 6: commit**

```bash
git add lib test
git commit -m "feat(app): show request notifications in the inbox"
```

## Gruppo D — STOP

### Task 9: STOP — webhook in Seerr (lo fa l'orchestratore con l'utente)

Il subagent del Gruppo C si ferma qui. L'orchestratore:

1. **Indirizzo e modello.** Chiede all'utente di aprire la pagina del plugin nella Dashboard (sezione Seerr → "Seerr webhook") e di copiare l'indirizzo del webhook e il modello JSON con "Copy the JSON payload". L'indirizzo atteso è `https://hashvps.proton.usbx.me/jellyfin/WonderFlixWatchParty/Requests/Webhook`.
2. **In Seerr** (Settings → Notifications → Webhook), l'utente:
   - accende il webhook;
   - incolla l'indirizzo e il JSON;
   - spunta solo "Request Pending Approval" e "Request Available";
   - salva e preme **Test**.
3. **Controllo:**
   - nella pagina del plugin, "Last event received" mostra `TEST_NOTIFICATION` con l'ora;
   - nel registro di Jellyfin non ci sono righe "Webhook di Seerr rifiutato": `ssh ultra 'grep "Webhook di Seerr" ~/.apps/jellyfin/log/log_$(date +%Y%m%d).log'` (niente segreti nell'output: il plugin non li scrive).
4. **Se non arriva:** controlla nel log di nginx (`~/.apps/nginx/`) che il `POST` arrivi a `/jellyfin/WonderFlixWatchParty/Requests/Webhook`, e riporta all'utente.

Il webhook vale per il plugin installato a mano e resterà valido con quello del Catalogo: la configurazione del plugin non cambia.

## Gruppo E — allineamento e verifica finale

### Task 10: spec allineata, verifica, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md`

- [ ] **Step 1: allinea la spec**

In `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md`:
- **Stato:** aggiungi `, piano 15b realizzato (docs/superpowers/plans/2026-10-05-wonderflix-15b-richieste-approvazioni-release.md)`.
- **§8.4:**
  - gli elenchi si ricaricano a ogni `InboxChanged` (decisione 5);
  - Approva e Rifiuta bloccano la riga finché la risposta non arriva;
  - il conteggio usa la prima pagina di 50 e mostra "50+" oltre (decisione 6);
  - "Richiedi stagioni" usa lo stesso `RequestTitleController` della scheda da richiedere (decisione 7).
- **§9.4:**
  - Rifiuta è a due tempi, "Rifiuta" → "Conferma" per 4 secondi, senza finestra (decisione 1);
  - la riga esce subito, senza animazione, con l'avviso (decisione 4);
  - la scheda si sceglie anche dall'indirizzo, con `?tab=mine|pending|all` (decisione 8).
- **§9.5:**
  - le finestre dell'app hanno un aspetto comune (`showWfDialog`) (decisione 2);
  - la finestra restituisce la scelta e la chiamata parte dalla pagina (decisione 3);
  - "Predefinito" è sempre la prima voce, e anche il server predefinito compare nel menu per sceglierne profilo e cartella.
- **§9.6:** "Nuova richiesta" apre `/requests?tab=pending`; "Ora disponibile" senza `ItemId` apre `/requests`.
- **§10:** togli "Rifutare la richiesta di {title}?" dai testi delle finestre, e aggiungi "Conferma" ai pulsanti della pagina.

```bash
git add docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md
git commit -m "docs: align spec I with plan 15b"
```

- [ ] **Step 2: verifica finale**

Run: `flutter analyze` e `flutter test`. Poi `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`: il plugin non è cambiato, i test devono essere tutti verdi.
Expected: tutto verde, nessun problema. Annota i numeri.

- [ ] **Step 3: build per la prova manuale**

Copia `config/wonderflix.json` dalla root del repository principale nella stessa cartella del worktree (non si committa), poi:

Run: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
Expected: `build/windows/x64/runner/Release/wonderflix.exe`.

## Prova manuale (con l'utente, dopo la review finale)

Con il plugin 1.4.0 (installato a mano) e il webhook configurato (Task 9):

1. **Barra:** c'è "Richieste" tra "La mia lista" e "Cerca".
2. **Pagina Richieste come admin:**
   - si apre su "Da approvare (n)" se ci sono richieste in attesa, altrimenti su "Le mie";
   - nelle righe ci sono locandina, titolo, stagioni, "chiesto da", data e stato.
3. **Una richiesta da un account normale** (o da un amico):
   - arriva nella cassetta dell'admin "{nome} ha chiesto {titolo}", e il clic apre "Da approvare";
   - **Rifiuta → Conferma** la rifiuta, e in Seerr risulta rifiutata;
   - una seconda richiesta, **Approva → "Predefinito" → Approva**, finisce in Radarr o Sonarr;
   - una terza con **"Radarr Anime"** (o la cartella anime di Sonarr): in Radarr il film ha il profilo e la cartella scelti.
4. **"Le mie"** di un account normale: le sue richieste con lo stato. "In arrivo · n%" durante un download.
5. **"Richiedi stagioni"** su una serie della libreria a cui mancano stagioni: la finestra, la scelta e l'avviso, e il pulsante sparisce quando non manca più niente.
6. **"Ora disponibile":** quando un titolo chiesto arriva (dopo la scansione della notte, finché la sincronizzazione di Seerr è rotta), chi l'ha chiesto riceve la voce, e il clic apre la scheda.

Dopo l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria del flusso).

## Release (dopo il merge, con l'utente)

Segue `docs/RELEASING.md`, prima il plugin e poi l'app.

1. **Plugin 1.4.0, con l'ok dell'utente.**
   - Tag `watch-party-plugin-v1.4.0` su `main` e push del tag. Il workflow `watch-party-plugin.yml` crea la **pre-release** con lo zip e il suo MD5. Controllare che `releases/latest` resti l'app.
   - Voce 1.4.0.0 in `jellyfin-plugin-watch-party/manifest.json`, in cima:
     - `sourceUrl` dello zip e `checksum` MD5;
     - `changelog` in italiano come le voci precedenti: richieste con Seerr (cercare, chiedere, approvare dall'app) e avvisi "Ora disponibile" e "Nuova richiesta";
     - `targetAbi` 10.11.0.0 e `timestamp`.
   - Se `description` e `overview` del manifest (in inglese) non citano le richieste con Seerr, aggiungile.
   - Commit `chore: publish the watch party plugin 1.4.0` e push.
2. **Server** (`ssh ultra`; prima controllare nel log che nessuno stia guardando):
   1. `app-jellyfin stop`;
   2. spostare `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.4.0.0` (la copia manuale) in `~/wfwp-backup/1.4.0.0-manuale`;
   3. `app-jellyfin start` (l'avvio richiede qualche minuto).

   L'utente installa 1.4.0.0 dal Catalogo (Dashboard → Plugin → WonderFlix Watch Party). Poi `app-jellyfin restart`; nel log deve comparire `Loaded plugin: "WonderFlix Watch Party" "1.4.0.0"`, e la dll deve avere lo stesso MD5 dello zip. La configurazione di Seerr (indirizzo, chiave, segreto) resta, perché sta in `plugins/configurations`.
3. **App 0.9.0, non obbligatoria.**
   - Commit `chore: release 0.9.0`: `pubspec.yaml` `version: 0.9.0+…`, come le release precedenti.
   - Con l'ok dell'utente: tag `v0.9.0`, push, pipeline Release.
   - A pipeline finita scrivo le note in italiano nella bozza (`gh release edit v0.9.0 --notes-file …`), **senza** il marcatore `min-version`. Le note parlano di:
     - chiedere film e serie che mancano (sezione "Da richiedere" nella ricerca, scheda con le stagioni, "Richiedi stagioni");
     - pagina Richieste;
     - avvisi nella cassetta;
     - per l'admin, Approva e Rifiuta;
     - serve il plugin 1.4.0 collegato a Seerr.
   - **Pubblica l'utente.**
4. **Dopo la release:** aggiorna `docs/IDEE.md`, togliendo l'idea 2 e aggiungendo "Spec I — richieste con Seerr (plugin 1.4.0, app 0.9.0)" alle fatte.
