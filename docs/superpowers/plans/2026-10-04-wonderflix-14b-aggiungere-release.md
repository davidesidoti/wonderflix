# WonderFlix — Piano 14b: aggiungere titoli alla coda e release (plugin 1.3.0, app 0.8.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** seconda metà della Spec H. Dal pannello "Coda" del player si aggiungono film ed episodi alla coda del watch party:
- vista **Aggiungi**: ricerca, e La mia lista a campo vuoto;
- viste **Serie** e **Stagione**;
- "Riproduci dopo" e "Aggiungi in coda", con conferma, tetto di 100 e doppioni;
- avvisi delle aggiunte, per gli altri e per sé.

Poi la release: plugin 1.3.0 dal Catalogo e app **0.8.0 non obbligatoria**.

**Spec:** `docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md` (§3, §8.2–8.3, §9.2 viste Aggiungi, Serie e Stagione, §9.3, §10, §11). Il piano 14a (`docs/superpowers/plans/2026-10-04-wonderflix-14a-coda-party.md`) è realizzato e su `main` (`98cb091`).

**Decisioni del piano** (approvate dall'utente il 2026-10-04):
1. **Lo stato del pannello sopravvive al cambio di player.**
   - Si conservano la vista (Aggiungi, Serie, Stagione), la serie o stagione aperta e il testo della ricerca.
   - Lo stato si azzera quando si **apre** il pannello dal pulsante, e quando si esce dal party.
   - Quando il player si sostituisce (`partyQueuePanelCarryProvider` del 14a) il pannello si riapre dov'era.
2. **Tastiera:**
   - mentre il campo di ricerca ha il focus, i tasti vanno al campo e i comandi del player sono fermi; funzionano solo i tasti multimediali (come la chat);
   - Esc prima svuota il campo, poi chiude il pannello;
   - ← torna alla vista precedente;
   - nel resto del pannello il focus resta al player.
3. **Serie:** aprendo una serie, **una sola richiesta** dà tutti i suoi episodi veri, senza i mancanti (`LibraryApi.allEpisodes`). Da lì escono il numero per stagione, "· N già in coda" e la vista Stagione. Le stagioni senza episodi veri non compaiono.
4. **La mia lista e ricerca:**
   - **La mia lista** sono gli stessi dati della pagina La mia lista (`favoritesProvider`), in ordine di titolo.
   - **La ricerca** dà film e serie, al massimo 20, in ordine di titolo come la pagina Cerca. Parte da 2 lettere, 300 ms dopo l'ultimo tasto; le risposte vecchie si scartano.
5. **Avvisi:**
   - **Per gli altri**, i dettagli dei titoli aggiunti si chiedono con **una** richiesta (al massimo 50 id) per scrivere "Marco ha aggiunto alla coda: 8 episodi di Dark".
   - **Per sé**, "Hai aggiunto…" si compone dai titoli cliccati.
6. **Attesa:**
   - Mentre un'aggiunta aspetta la conferma (al massimo 4 s), il pulsante premuto mostra un piccolo indicatore e i suoi pulsanti non si ripremono.
   - Confermata, la riga diventa ✓ "In coda", perché il titolo è nella coda.
   - Se il tempo scade, compare l'avviso "Non aggiunto: qualcuno nel party non può vedere questo titolo".
   - In più, l'editor tiene da parte gli id di un'aggiunta ancora in attesa: una seconda aggiunta degli stessi titoli (una stagione intera mentre un suo episodio aspetta) non li manda due volte.
7. **Release** in fondo al piano, fuori dai task, con l'utente.

**Architecture:**
- **Regole** (`party_queue_rules.dart`): posto libero, titoli già in coda, piano dell'aggiunta (doppioni, tetto, quelli in attesa), cosa dice l'avviso (`PartyQueueAddition`).
- **Editor:** `PartyQueueEditor.add(items, next:)` manda `Queue`, annuncia `Queue`/`QueueNext` e aspetta sul flusso `updates` della sessione la coda con i titoli nuovi. Mostra "Hai…", o l'avviso di errore.
- **Avvisi:** `PartyNotices` riconosce le aggiunte degli altri (id nuovi nella coda con `Reason` `Queue`/`QueueNext`) e chiede i loro dettagli per il testo.
- **Stato del pannello:** `queuePanelNavProvider` (pila delle viste) e `queueAddSearchProvider` (ricerca), globali.
- **Viste:** `QueueAddView`, `QueueSeriesView`, `QueueSeasonView` più i pezzi comuni (`QueuePanelFrame`, `QueuePanelHeader`, `QueueItemRow`, `QueueAddButtons`, `QueueMessage`). `PartyQueuePanel` sceglie la vista dalla pila.
- **Player:** il focus del campo di ricerca; il pannello non è più dentro `ExcludeFocus`, perché ci pensa il pannello stesso.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, dio (`CancelToken`), lucide_icons_flutter. Il plugin non cambia: la 1.3.0 è già sul server, copiata a mano nel 14a.

**Worktree:** `.claude/worktrees/piano-14b`, branch `feat/piano-14b`. **Base:** `main` con questo piano. **Test a inizio piano:** 1600 Flutter, 249 plugin (da verificare all'avvio).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:**
  - Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-14b`).
  - Comandi git semplici: niente `git -C`, niente variabili nei comandi git.
  - Mai `git checkout -- <file>` su un file che hai modificato.
  - `git add` solo dei propri percorsi, mai `git add -A`.
- **Prima di ogni commit:** `flutter analyze` senza problemi e `flutter test` tutto verde.
- **File generati:**
  - Se `flutter test`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: quasi tutti CRLF nella working copy, `test/features/watch_party/party_player_test.dart` LF. I file nuovi come i vicini.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; durate da `WfMotion`; `clock.now()`, mai `DateTime.now()`.
- **Se il codice del piano ha un errore** (analyzer o lint, import, un dettaglio di un test, un'API con firma diversa, un test che vuole un `pump` in più):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-04 sul codice di `main` (`98cb091`) e sull'OpenAPI di Jellyfin 10.11.9.

- **`GET /Shows/{seriesId}/Episodes`:**
  - Senza `seasonId` dà tutti gli episodi della serie, in ordine.
  - Con `isMissing=false` toglie i mancanti.
  - Ogni episodio ha `SeasonId`, `IndexNumber`, `ParentIndexNumber`, `RunTimeTicks`.
  - `JellyfinItem` ha `seasonId`, `indexNumber`, `parentIndexNumber`, `runtime`, `childCount` (le stagioni di una serie), `sortName`.
- **Riusabili nell'app:**
  - `seasonsProvider(seriesId)` (`lib/features/detail/detail_providers.dart`, autoDispose, family);
  - `favoritesProvider` (`lib/features/mylist/my_list_screen.dart`: film e serie preferiti, `includeSortFields`, `limit 500`);
  - il modello di ricerca con `CancelToken` di `SearchController` (`lib/features/search/search_controller.dart`): `RequestCancelledException`, attesa di 300 ms, minimo 2 lettere;
  - `ImageUrls.poster(item)` (per un episodio la locandina della serie) e `landscape(item)`.
- **Testi già presenti negli ARB:**
  - `retry` ("Riprova"), `navBack` ("Indietro");
  - `detailSeasons(count)` ("3 stagioni"), `catalogCount(count)` ("3 titoli");
  - `partyQueueMovie` ("Film"), `playerClosePanel` ("Chiudi").
- **`WfButton.primary` / `WfButton.secondary`** (`lib/ui/wf_buttons.dart`): `label`, `icon`, `onPressed` (null = spento).
- **Focus nel player:**
  - Il player ha un `Focus` (`_focusNode`) con `onKeyEvent: _onKey`. Un tasto arriva prima al widget con il focus, poi risale ai genitori fino a `_onKey`.
  - Con un `TextField` a fuoco, `_onKey` deve rispondere `ignored` ai tasti da scrivere: un tasto gestito non arriva più al campo.
  - Esc va preso **sopra il campo** (`CallbackShortcuts` attorno al `TextField`), che lo vede prima di `_onKey`.
  - La chat fa già così (`_onChatKey`).
  - Quando un campo a fuoco sparisce, il focus va allo scope della rotta (`primaryFocus` è un `FocusScopeNode`): il player deve riprenderselo.
- **14a:**
  - `PartyQueueEditor` (`lib/features/watch_party/party_queue_editor.dart`) ha `_send` (avviso `queueFailed` solo se si è ancora nel gruppo) e il blocco dell'ordine casuale.
  - `PartyNotices` ha `mine(kind, show:)`, `forget(kind)`, `_isEcho` con `_queueEchoKinds` (finestra 4 s), `_showOthers(notice, action)`, e in `_onQueue` i rami per `ShuffleMode` e per il cambio di titolo.
  - Gli aggiornamenti della sessione arrivano su `WatchPartySession.updates`, già applicati allo stato.
  - `FakeSyncPlayApi.queue` registra `add a,b` o `add-next a,b`.
- **Pannello del 14a:**
  - `QueuePanel` (vista Coda) e `PartyQueuePanel` sono in `lib/features/player/queue_panel/queue_panel.dart`; `QueueRow` e `queueRowDetails` in `queue_rows.dart`.
  - Nel player il pannello sta in `Positioned.fill(key: ValueKey('player-queue-panel'), child: ExcludeFocus(child: PlayerSidePanelHost(...)))`.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi del 14b |
| `lib/features/watch_party/party_queue_rules.dart` | modifica | posto, già in coda, piano dell'aggiunta, `PartyQueueAddition` |
| `lib/core/jellyfin/library_api.dart` | modifica | `allEpisodes` |
| `lib/features/watch_party/party_notices.dart`, `party_notice_pill.dart` | modifica | avvisi delle aggiunte |
| `lib/features/watch_party/party_queue_editor.dart` | modifica | `add` con la conferma |
| `lib/features/player/queue_panel/queue_panel_state.dart` | crea | `QueuePanelPage`, `queuePanelNavProvider`, `queueAddSearchProvider`, `queueSeriesEpisodesProvider` |
| `lib/features/player/queue_panel/queue_add_widgets.dart` | crea | `QueuePanelFrame`, `QueuePanelHeader`, `QueueItemRow`, `QueueAddButtons`, `QueueMessage` |
| `lib/features/player/queue_panel/queue_panel.dart` | modifica | vista Coda nel `QueuePanelFrame`, "＋ Aggiungi titoli", `PartyQueuePanel` sceglie la vista |
| `lib/features/player/queue_panel/queue_add_view.dart` | crea | vista Aggiungi |
| `lib/features/player/queue_panel/queue_series_views.dart` | crea | viste Serie e Stagione |
| `lib/features/player/player_screen.dart` | modifica | focus della ricerca, azzeramento all'apertura |
| `test/support/library_fakes.dart`, `test/support/watch_party_fakes.dart` | modifica | finti |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md`, `docs/RELEASING.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1–5):** testi, regole, libreria, avvisi, `add`.
- **Gruppo B (Task 6–9):** stato del pannello, pezzi comuni, viste Aggiungi, Serie e Stagione.
- **Gruppo C (Task 10):** il pannello nel player (viste, focus, tasti).
- **Gruppo D (Task 11):** allineamento della spec, verifica finale, build.
- **Release** (dopo la prova manuale e il merge, con l'utente): fuori dai task.

---

## Gruppo A — testi, regole, libreria, avvisi, `add`

### Task 1: testi

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`

- [ ] **Step 1: testi italiani**

In `l10n/app_it.arb`, in fondo, prima della `}` finale: metti la virgola dopo l'ultima voce attuale e aggiungi:

```json
  "partyQueueAddTitles": "Aggiungi titoli",
  "partyQueueAddTitle": "Aggiungi",
  "partyQueueSearchHint": "Cerca film e serie",
  "partyQueueMyList": "La mia lista",
  "partyQueueResults": "Risultati",
  "partyQueueMyListEmpty": "La tua lista è vuota",
  "partyQueueNoResults": "Nessun risultato",
  "partyQueueLoadFailed": "Non riesco a caricare i titoli",
  "partyQueuePlayNext": "Riproduci dopo",
  "partyQueueAddToEnd": "Aggiungi in coda",
  "partyQueueInQueue": "In coda",
  "partyQueueFull": "La coda è piena ({limit} titoli)",
  "@partyQueueFull": {"placeholders": {"limit": {"type": "int"}}},
  "partyQueueSeries": "Serie",
  "partyQueueEpisodeCount": "{count, plural, =1{1 episodio} other{{count} episodi}}",
  "@partyQueueEpisodeCount": {"placeholders": {"count": {"type": "int"}}},
  "partyQueueAlreadyQueuedCount": "{count} già in coda",
  "@partyQueueAlreadyQueuedCount": {"placeholders": {"count": {"type": "int"}}},
  "partyQueueWholeSeasonNext": "Tutta dopo",
  "partyQueueWholeSeasonEnd": "Tutta in coda",
  "partyQueueEpisodeTitle": "{number}. {title}",
  "@partyQueueEpisodeTitle": {"placeholders": {"number": {"type": "int"}, "title": {"type": "String"}}},
  "watchPartyNoticeQueued": "Aggiunto alla coda: {what}",
  "@watchPartyNoticeQueued": {"placeholders": {"what": {"type": "String"}}},
  "watchPartyNoticeQueuedBy": "{name} ha aggiunto alla coda: {what}",
  "@watchPartyNoticeQueuedBy": {"placeholders": {"name": {"type": "String"}, "what": {"type": "String"}}},
  "watchPartyNoticeQueuedByYou": "Hai aggiunto alla coda: {what}",
  "@watchPartyNoticeQueuedByYou": {"placeholders": {"what": {"type": "String"}}},
  "watchPartyNoticeQueuedNext": "Subito dopo: {what}",
  "@watchPartyNoticeQueuedNext": {"placeholders": {"what": {"type": "String"}}},
  "watchPartyNoticeQueuedNextBy": "{name} ha messo subito dopo: {what}",
  "@watchPartyNoticeQueuedNextBy": {"placeholders": {"name": {"type": "String"}, "what": {"type": "String"}}},
  "watchPartyNoticeQueuedNextByYou": "Hai messo subito dopo: {what}",
  "@watchPartyNoticeQueuedNextByYou": {"placeholders": {"what": {"type": "String"}}},
  "partyQueueWhatEpisodes": "{count} episodi di {series}",
  "@partyQueueWhatEpisodes": {"placeholders": {"count": {"type": "int"}, "series": {"type": "String"}}},
  "partyQueueRejected": "Non aggiunto: qualcuno nel party non può vedere questo titolo",
  "partyQueuePartialEpisodes": "Aggiunti {added} episodi su {wanted}: la coda è piena",
  "@partyQueuePartialEpisodes": {"placeholders": {"added": {"type": "int"}, "wanted": {"type": "int"}}},
  "partyQueuePartialTitles": "Aggiunti {added} titoli su {wanted}: la coda è piena",
  "@partyQueuePartialTitles": {"placeholders": {"added": {"type": "int"}, "wanted": {"type": "int"}}}
```

- [ ] **Step 2: testi inglesi**

In `l10n/app_en.arb`, allo stesso modo (senza metadati, come il resto del file):

```json
  "partyQueueAddTitles": "Add titles",
  "partyQueueAddTitle": "Add",
  "partyQueueSearchHint": "Search movies and series",
  "partyQueueMyList": "My List",
  "partyQueueResults": "Results",
  "partyQueueMyListEmpty": "Your list is empty",
  "partyQueueNoResults": "No results",
  "partyQueueLoadFailed": "Couldn't load the titles",
  "partyQueuePlayNext": "Play next",
  "partyQueueAddToEnd": "Add to queue",
  "partyQueueInQueue": "In queue",
  "partyQueueFull": "The queue is full ({limit} titles)",
  "partyQueueSeries": "Series",
  "partyQueueEpisodeCount": "{count, plural, =1{1 episode} other{{count} episodes}}",
  "partyQueueAlreadyQueuedCount": "{count} already queued",
  "partyQueueWholeSeasonNext": "All next",
  "partyQueueWholeSeasonEnd": "All to queue",
  "partyQueueEpisodeTitle": "{number}. {title}",
  "watchPartyNoticeQueued": "Added to the queue: {what}",
  "watchPartyNoticeQueuedBy": "{name} added to the queue: {what}",
  "watchPartyNoticeQueuedByYou": "You added to the queue: {what}",
  "watchPartyNoticeQueuedNext": "Up next: {what}",
  "watchPartyNoticeQueuedNextBy": "{name} put up next: {what}",
  "watchPartyNoticeQueuedNextByYou": "You put up next: {what}",
  "partyQueueWhatEpisodes": "{count} episodes of {series}",
  "partyQueueRejected": "Not added: someone in the party can't see this title",
  "partyQueuePartialEpisodes": "Added {added} of {wanted} episodes: the queue is full",
  "partyQueuePartialTitles": "Added {added} of {wanted} titles: the queue is full"
```

- [ ] **Step 3: genera e verifica**

Run: `flutter gen-l10n` → nessun errore; `flutter analyze` → nessun problema.

- [ ] **Step 4: commit**

```bash
git add l10n
git commit -m "feat(party): texts for adding titles to the queue"
```

### Task 2: regole dell'aggiunta

**Files:**
- Modify: `lib/features/watch_party/party_queue_rules.dart`
- Test: `test/features/watch_party/party_queue_rules_test.dart`

- [ ] **Step 1: test che falliscono**

In fondo a `main` di `party_queue_rules_test.dart` (aggiungi l'import di `ItemKind` se manca: `package:wonderflix/core/jellyfin/item_models.dart` c'è già):

```dart
  group('aggiunta (spec H §8.2)', () {
    test('posto libero e titoli già in coda', () {
      final q = queue(); // e3 già visto, e4 in corso, e5, e6
      expect(partyQueueRoom(q), partyQueueLimit - 4);
      expect(partyQueueQueuedIds(q), {'e4', 'e5', 'e6'},
          reason: 'il già visto si può riaggiungere');
      final full = testSeriesQueue(
          itemIds: [for (var i = 0; i < 101; i++) 'x$i'], playingIndex: 0);
      expect(partyQueueRoom(full), 0);
    });

    test('piano: toglie i già in coda, i doppioni e quelli in attesa, '
        'taglia al posto libero', () {
      final q = queue();
      final plan = partyQueueAddPlan(
          q, const ['e3', 'e5', 'm1', 'm1', 'm2', 'm3'],
          pending: const {'m3'});
      expect(plan.send, ['e3', 'm1', 'm2']);
      expect(plan.alreadyQueued, 2, reason: 'e5 e m3 (in attesa)');
      expect(plan.cut, 0);

      final nearlyFull = testSeriesQueue(
          itemIds: [for (var i = 0; i < 98; i++) 'x$i'], playingIndex: 0);
      final cut = partyQueueAddPlan(nearlyFull, const ['a', 'b', 'c', 'd']);
      expect(cut.send, ['a', 'b']);
      expect(cut.cut, 2);
    });

    test('cosa dice l\'avviso: un film, un episodio, episodi della stessa '
        'serie, titoli misti', () {
      final film = testItem(id: 'm1', name: 'Alien');
      JellyfinItem episode(String id, int index,
              {String series = 'Dark', String seriesId = 's1'}) =>
          testItem(
              id: id,
              name: 'E$index',
              kind: ItemKind.episode,
              seriesName: series,
              seriesId: seriesId,
              index: index,
              seasonIndex: 1);

      final one = partyQueueAddition([film]);
      expect((one.count, one.title, one.series), (1, 'Alien', null));

      final single = partyQueueAddition([episode('e1', 1)]);
      expect(single.title, 'Dark · S1:E1');

      final season = partyQueueAddition([episode('e1', 1), episode('e2', 2)]);
      expect((season.count, season.title, season.series), (2, null, 'Dark'));

      final mixed = partyQueueAddition([episode('e1', 1), film]);
      expect((mixed.count, mixed.title, mixed.series), (2, null, null));

      final twoSeries = partyQueueAddition([
        episode('e1', 1),
        episode('x1', 1, series: 'Lost', seriesId: 's2'),
      ]);
      expect(twoSeries.series, isNull);

      // Dettagli di una parte soltanto: si dice solo quanti.
      final partial = partyQueueAddition([episode('e1', 1)], count: 3);
      expect((partial.count, partial.title, partial.series), (3, null, null));
    });
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/watch_party/party_queue_rules_test.dart`
Expected: FAIL, funzioni non definite.

- [ ] **Step 3: implementazione**

In `party_queue_rules.dart` aggiungi l'import `import 'dart:math' as math;` e `import '../library/item_labels.dart';`, poi in fondo:

```dart
/// Posto libero nella coda, sotto il tetto di [partyQueueLimit] (mai meno
/// di 0: una coda fatta da un altro client può essere più lunga).
int partyQueueRoom(PlayQueue queue) =>
    math.max(0, partyQueueLimit - queue.entries.length);

/// `ItemId` già in coda per un'aggiunta (spec H §8.2): l'elemento in
/// riproduzione e i prossimi. Un titolo già visto si può riaggiungere.
Set<String> partyQueueQueuedIds(PlayQueue queue) {
  final sections = partyQueueSections(queue);
  return {
    ?sections.playing?.itemId,
    for (final entry in sections.upcoming) entry.itemId,
  };
}

/// Cosa si manda per un'aggiunta (spec H §8.2).
class PartyQueueAddPlan {
  const PartyQueueAddPlan({
    required this.send,
    required this.alreadyQueued,
    required this.cut,
  });

  /// Gli id da mandare, nell'ordine dato.
  final List<String> send;

  /// Quanti erano già in coda (o in un'aggiunta ancora in attesa).
  final int alreadyQueued;

  /// Quanti restano fuori per il tetto.
  final int cut;
}

/// I candidati [itemIds], in ordine, senza quelli già in coda, quelli di
/// un'aggiunta ancora in attesa ([pending]) e i doppioni; poi tagliati al
/// posto libero.
PartyQueueAddPlan partyQueueAddPlan(PlayQueue queue, List<String> itemIds,
    {Set<String> pending = const {}}) {
  final queued = {...partyQueueQueuedIds(queue), ...pending};
  final fresh = <String>[];
  var alreadyQueued = 0;
  for (final id in itemIds) {
    if (queued.contains(id)) {
      alreadyQueued++;
    } else if (!fresh.contains(id)) {
      fresh.add(id);
    }
  }
  final send = fresh.take(partyQueueRoom(queue)).toList();
  return PartyQueueAddPlan(
    send: send,
    alreadyQueued: alreadyQueued,
    cut: fresh.length - send.length,
  );
}

/// Cosa dice un avviso di aggiunta (spec H §10): un titolo; oppure quanti
/// episodi di quale serie; oppure quanti titoli.
class PartyQueueAddition {
  const PartyQueueAddition({required this.count, this.title, this.series});

  final int count;

  /// Un titolo solo: il film, o "Dark · S1:E1".
  final String? title;

  /// Più episodi, tutti della stessa serie.
  final String? series;
}

/// [items]: i dettagli dei titoli aggiunti; [count]: quanti sono in tutto,
/// se i dettagli sono solo di una parte (allora si dice solo quanti).
PartyQueueAddition partyQueueAddition(List<JellyfinItem> items, {int? count}) {
  final total = count ?? items.length;
  if (items.length != total) return PartyQueueAddition(count: total);
  if (total == 1) {
    final item = items.single;
    final code = episodeCode(item);
    return PartyQueueAddition(
      count: 1,
      title: item.kind == ItemKind.episode && code != null
          ? '${cardTitle(item)} · $code'
          : cardTitle(item),
    );
  }
  final seriesIds = {
    for (final item in items) item.kind == ItemKind.episode ? item.seriesId : null,
  };
  final series = items.first.seriesName;
  if (seriesIds.length == 1 && seriesIds.single != null && series != null) {
    return PartyQueueAddition(count: total, series: series);
  }
  return PartyQueueAddition(count: total);
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/watch_party/party_queue_rules_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/watch_party/party_queue_rules.dart test/features/watch_party/party_queue_rules_test.dart
git commit -m "feat(party): rules for adding titles to the queue"
```

### Task 3: tutti gli episodi veri di una serie

**Files:**
- Modify: `lib/core/jellyfin/library_api.dart`
- Modify: `test/support/library_fakes.dart`
- Test: `test/core/jellyfin/library_api_test.dart`

- [ ] **Step 1: test che fallisce**

In `library_api_test.dart`, dopo il test `previousEpisode`:

```dart
  test('allEpisodes: tutti gli episodi della serie, senza i mancanti',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['e1', 'e2']));
    final episodes = await api.allEpisodes('u1', 's1');
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['isMissing'], false);
    expect(last().query['userId'], 'u1');
    expect(last().query, isNot(contains('seasonId')));
    expect(last().query['enableImageTypes'], 'Primary,Backdrop,Thumb,Logo');
    expect(episodes.map((e) => e.id), ['e1', 'e2']);
  });
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/core/jellyfin/library_api_test.dart`
Expected: FAIL, `allEpisodes` non definito.

- [ ] **Step 3: implementazione**

In `library_api.dart`, dopo `episodes`:

```dart
  /// Tutti gli episodi veri della serie, in ordine e con le immagini delle
  /// card (spec H §9.2, viste Serie e Stagione): senza i mancanti, che non
  /// si possono guardare.
  Future<List<JellyfinItem>> allEpisodes(String userId, String seriesId) async =>
      _list(await _http.get('/Shows/$seriesId/Episodes', query: {
        ...cardImageParams,
        'userId': userId,
        'isMissing': false,
      }));
```

In `test/support/library_fakes.dart`, in `FakeLibraryApi`. Il campo `seriesEpisodes` (per `episodesFrom`) esiste già: si riusa.

```dart
  /// Serie chieste ad [allEpisodes].
  final allEpisodesCalls = <String>[];

  /// Gli episodi di [seriesEpisodes] (gli stessi di `episodesFrom`).
  @override
  Future<List<JellyfinItem>> allEpisodes(String userId, String seriesId) {
    allEpisodesCalls.add(seriesId);
    return _answer(() => seriesEpisodes[seriesId] ?? const []);
  }
```

- [ ] **Step 4: il test passa**

Run: `flutter test test/core/jellyfin/library_api_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/core/jellyfin/library_api.dart test/support/library_fakes.dart test/core/jellyfin/library_api_test.dart
git commit -m "feat(library): fetch all the real episodes of a series"
```

### Task 4: avvisi delle aggiunte

**Files:**
- Modify: `lib/features/watch_party/party_notices.dart`
- Modify: `lib/features/watch_party/party_notice_pill.dart`
- Test: `test/features/watch_party/party_notices_test.dart`, `test/features/watch_party/party_notice_pill_test.dart`

- [ ] **Step 1: test che falliscono**

In `party_notices_test.dart`, dentro il `group('coda del party (spec H §10)', …)`:

```dart
    test('aggiunta di un altro: un film, con il nome (spec H §10)', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices().attribute(testActionEvent(PartyAction.queue));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    itemIds: const ['e4', 'e5', 'e6', 'm2'],
                    reason: 'Queue',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.queued);
        expect(current()?.title, 'Arrival');
        expect(current()?.name, 'Luigi');
        expect(library.itemsByIdsCalls.last, ['m2']);
        finish(async);
      });
    });

    test('subito dopo: più episodi della stessa serie', () {
      fakeAsync((async) {
        library.itemsById['e7'] = testItem(
            id: 'e7',
            name: 'E7',
            kind: ItemKind.episode,
            seriesId: 's1',
            seriesName: 'Breaking Bad',
            index: 7,
            seasonIndex: 1);
        library.itemsById['e8'] = testItem(
            id: 'e8',
            name: 'E8',
            kind: ItemKind.episode,
            seriesId: 's1',
            seriesName: 'Breaking Bad',
            index: 8,
            seasonIndex: 1);
        mount(async);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        // Id nella coda stabili: e7 ed e8 entrano dopo e4 (p1).
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                PlayQueue(
                  reason: 'QueueNext',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 5),
                  entries: const [
                    PlayQueueEntry(itemId: 'e4', playlistItemId: 'p1'),
                    PlayQueueEntry(itemId: 'e7', playlistItemId: 'n1'),
                    PlayQueueEntry(itemId: 'e8', playlistItemId: 'n2'),
                    PlayQueueEntry(itemId: 'e5', playlistItemId: 'p2'),
                    PlayQueueEntry(itemId: 'e6', playlistItemId: 'p3'),
                  ],
                  playingIndex: 0,
                  startPosition: Duration.zero,
                  isPlaying: false,
                )));
        expect(current()?.kind, PartyNoticeKind.queuedNext);
        expect(current()?.count, 2);
        expect(current()?.series, 'Breaking Bad');
        expect(current()?.title, isNull);
        finish(async);
      });
    });

    test('la mia aggiunta: l\'eco non fa avvisi', () {
      fakeAsync((async) {
        mount(async);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices().mine(PartyNoticeKind.queued, show: false);
        async.elapse(const Duration(milliseconds: 3500));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    itemIds: const ['e4', 'e5', 'e6', 'm2'],
                    reason: 'Queue',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current(), isNull);
        expect(library.itemsByIdsCalls, isEmpty);
        finish(async);
      });
    });

    test('prima coda dopo l\'ingresso con Reason Queue: nessun avviso', () {
      fakeAsync((async) {
        mount(async);
        emit(async,
            PlayQueueUpdate('g1', testSeriesQueue(reason: 'Queue')));
        expect(current(), isNull);
        finish(async);
      });
    });
```

In `party_notice_pill_test.dart`, in fondo a `main`:

```dart
  test('avvisi delle aggiunte (spec H §10)', () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect(
        partyNoticeText(l,
            const PartyNotice(PartyNoticeKind.queued, title: 'Alien', count: 1)),
        'Aggiunto alla coda: Alien');
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.queued,
                count: 8, series: 'Dark', name: 'Marco')),
        'Marco ha aggiunto alla coda: 8 episodi di Dark');
    expect(
        partyNoticeText(l,
            const PartyNotice(PartyNoticeKind.queuedNext, count: 3, mine: true)),
        'Hai messo subito dopo: 3 titoli');
    expect(
        partyNoticeText(
            l, const PartyNotice(PartyNoticeKind.queueRejected, mine: true)),
        'Non aggiunto: qualcuno nel party non può vedere questo titolo');
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.queuePartial,
                mine: true, count: 10, total: 24, series: 'Dark')),
        'Aggiunti 10 episodi su 24: la coda è piena');
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.queuePartial,
                mine: true, count: 2, total: 5)),
        'Aggiunti 2 titoli su 5: la coda è piena');
    expect(
        partyNoticeText(
            l, const PartyNotice(PartyNoticeKind.queueFull, mine: true)),
        'La coda è piena (100 titoli)');
    expect(partyNoticeIcon(PartyNoticeKind.queued), LucideIcons.listPlus);
    expect(partyNoticeIcon(PartyNoticeKind.queuedNext), LucideIcons.listStart);
    expect(partyNoticeIcon(PartyNoticeKind.queueRejected),
        LucideIcons.circleAlert);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/watch_party/party_notices_test.dart test/features/watch_party/party_notice_pill_test.dart`
Expected: FAIL, tipi e campi non definiti.

- [ ] **Step 3: avvisi**

In `party_notices.dart`:

1. In `PartyNoticeKind`, dopo `queueFailed`:

```dart
  /// Titoli aggiunti in fondo alla coda (spec H §10): `title`, oppure
  /// `count` e `series`.
  queued,

  /// Titoli messi subito dopo quello in corso.
  queuedNext,

  /// Aggiunta scartata dal server: qualcuno nel party non può vedere un
  /// titolo (solo per chi agisce).
  queueRejected,

  /// Aggiunta tagliata dal tetto: `count` aggiunti su `total` (solo per chi
  /// agisce); con `series`, erano episodi della stessa serie.
  queuePartial,

  /// Coda piena, niente aggiunto (solo per chi agisce).
  queueFull,
```

2. In `PartyNotice`: i campi `count`, `total`, `series` nel costruttore (`{…, this.count, this.total, this.series}`) e:

```dart
  /// Aggiunte: quanti titoli (spec H §10).
  final int? count;

  /// Aggiunta tagliata: quanti se ne volevano.
  final int? total;

  /// Aggiunte: la serie, se sono tutti episodi della stessa.
  final String? series;
```

   `withName` li copia: `PartyNotice(kind, mine: mine, position: position, name: name, title: title, count: count, total: total, series: series)`.

3. `_queueEchoKinds` comprende anche `PartyNoticeKind.queued` e `PartyNoticeKind.queuedNext`.

4. Dopo `bool? _shuffled;`:

```dart
  /// Id nella coda dell'ultima coda vista; `null` prima della prima.
  Set<String>? _entryIds;
```

   Valorizzalo come `_shuffled`:
   - in `build`: `_entryIds = _idsOf(party.queue);`
   - nel `ref.listen` dell'ingresso: `_entryIds = _idsOf(joined.queue);`
   - in `_clear`: `_entryIds = null;`

   Con:

```dart
  static Set<String>? _idsOf(PlayQueue? queue) => queue == null
      ? null
      : {for (final entry in queue.entries) entry.playlistItemId};
```

5. All'inizio di `_onQueue`, prima del ramo `ShuffleMode`:

```dart
    final previousIds = _entryIds;
    _entryIds = _idsOf(queue);
    // Titoli aggiunti da qualcuno (spec H §10): gli id nuovi nella coda. La
    // prima coda dopo l'ingresso non è un'aggiunta.
    if (queue.reason == 'Queue' || queue.reason == 'QueueNext') {
      if (previousIds == null) return;
      final added = [
        for (final entry in queue.entries)
          if (!previousIds.contains(entry.playlistItemId)) entry.itemId,
      ];
      if (added.isEmpty) return;
      final next = queue.reason == 'QueueNext';
      final kind = next ? PartyNoticeKind.queuedNext : PartyNoticeKind.queued;
      if (_isEcho(kind)) return;
      unawaited(_announceAddition(
          kind, added, next ? PartyAction.queueNext : PartyAction.queue));
      return;
    }
```

   (Il resto di `_onQueue` resta: `wasShuffled` e `_playing` si aggiornano come prima.)

6. Dopo `_announce`:

```dart
  /// Al massimo tanti dettagli per il testo di un'aggiunta: oltre, una coda
  /// fatta da un altro client direbbe solo "N titoli".
  static const additionDetails = 50;

  /// Avviso di un'aggiunta altrui: i dettagli dei titoli (una richiesta)
  /// danno il testo; senza dettagli, nessun avviso.
  Future<void> _announceAddition(
      PartyNoticeKind kind, List<String> itemIds, PartyAction action) async {
    try {
      final items = await ref.read(libraryApiProvider).itemsByIds(
          ref.read(currentUserIdProvider),
          itemIds.take(additionDetails).toList());
      if (!ref.mounted || !ref.read(watchPartySessionProvider).inGroup) return;
      if (items.isEmpty) return;
      final addition = partyQueueAddition(items, count: itemIds.length);
      _showOthers(
          PartyNotice(kind,
              title: addition.title,
              count: addition.count,
              series: addition.series),
          action);
    } on Object catch (error) {
      _log.info('titoli aggiunti non disponibili: ${error.runtimeType}');
    }
  }
```

   Aggiungi l'import `import 'party_queue_rules.dart';`.

In `party_notice_pill.dart`:

1. Import `party_queue_rules.dart`.
2. Nello `switch` di `partyNoticeText`:

```dart
    PartyNoticeKind.queued => notice.mine
        ? l.watchPartyNoticeQueuedByYou(_what(l, notice))
        : by != null
            ? l.watchPartyNoticeQueuedBy(by, _what(l, notice))
            : l.watchPartyNoticeQueued(_what(l, notice)),
    PartyNoticeKind.queuedNext => notice.mine
        ? l.watchPartyNoticeQueuedNextByYou(_what(l, notice))
        : by != null
            ? l.watchPartyNoticeQueuedNextBy(by, _what(l, notice))
            : l.watchPartyNoticeQueuedNext(_what(l, notice)),
    PartyNoticeKind.queueRejected => l.partyQueueRejected,
    PartyNoticeKind.queuePartial => notice.series != null
        ? l.partyQueuePartialEpisodes(notice.count ?? 0, notice.total ?? 0)
        : l.partyQueuePartialTitles(notice.count ?? 0, notice.total ?? 0),
    PartyNoticeKind.queueFull => l.partyQueueFull(partyQueueLimit),
```

   E fuori dalla funzione:

```dart
/// Cosa si è aggiunto (spec H §10): il titolo, "8 episodi di Dark" o "3
/// titoli".
String _what(AppLocalizations l, PartyNotice notice) {
  final title = notice.title;
  if (title != null) return title;
  final count = notice.count ?? 0;
  final series = notice.series;
  return series != null
      ? l.partyQueueWhatEpisodes(count, series)
      : l.catalogCount(count);
}
```

3. In `partyNoticeIcon`:
   - `PartyNoticeKind.queued => LucideIcons.listPlus,`
   - `PartyNoticeKind.queuedNext => LucideIcons.listStart,`
   - `queueRejected`, `queuePartial` e `queueFull` vanno nel gruppo di `circleAlert`.

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/watch_party`
Expected: PASS, compresi i test esistenti degli avvisi.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/watch_party/party_notices.dart lib/features/watch_party/party_notice_pill.dart test/features/watch_party/party_notices_test.dart test/features/watch_party/party_notice_pill_test.dart
git commit -m "feat(party): notices for titles added to the queue"
```

### Task 5: `add` con la conferma

**Files:**
- Modify: `lib/features/watch_party/party_queue_editor.dart`
- Test: `test/features/watch_party/party_queue_editor_test.dart`

- [ ] **Step 1: test che falliscono**

In `party_queue_editor_test.dart` (`mount` mette nel gruppo con la coda e3 già visto, e4 in corso, e5, e6; `emit(async, queue)`; `announced()`; `notices` è il `FakePartyNotices`), aggiungi l'import `package:wonderflix/core/jellyfin/item_models.dart` e `../../support/library_fakes.dart`, poi in fondo a `main`:

```dart
  group('aggiunta (spec H §8.3)', () {
    final film = testItem(id: 'm9', name: 'Alien', year: 1979);
    JellyfinItem episode(String id, int index) => testItem(
        id: id,
        name: 'E$index',
        kind: ItemKind.episode,
        seriesId: 's2',
        seriesName: 'Dark',
        index: index,
        seasonIndex: 1);

    /// La coda del server con [added] dopo il titolo in corso (o in fondo).
    PlayQueue withAdded(List<String> added, {required bool next}) {
      final before = ['e3', 'e4', 'e5', 'e6'];
      final ids = next
          ? [...before.take(2), ...added, ...before.skip(2)]
          : [...before, ...added];
      return PlayQueue(
        reason: next ? 'QueueNext' : 'Queue',
        lastUpdate: DateTime.utc(2026, 9, 30, 10, 5),
        entries: [
          for (var i = 0; i < ids.length; i++)
            PlayQueueEntry(itemId: ids[i], playlistItemId: 'q$i'),
        ],
        playingIndex: 1,
        startPosition: Duration.zero,
        isPlaying: false,
      );
    }

    test('riproduci dopo: manda, annuncia, aspetta la conferma, "Hai…"', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: true)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add-next m9']);
        expect(announced(), ['QueueNext']);
        expect(notices.hiddenMineCalls, [PartyNoticeKind.queuedNext]);
        expect(outcome, isNull, reason: 'aspetta la coda del server');

        emit(async, withAdded(['m9'], next: true));
        expect(outcome, PartyQueueAddOutcome.added);
        expect(notices.shown.last.kind, PartyNoticeKind.queuedNext);
        expect(notices.shown.last.mine, isTrue);
        expect(notices.shown.last.title, 'Alien');
        finish(async);
      });
    });

    test('nessuna conferma in 4 s: rifiutata, eco dimenticata', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add m9']);
        async.elapse(PartyQueueEditor.addConfirmTimeout);
        expect(outcome, PartyQueueAddOutcome.rejected);
        expect(notices.shown.last.kind, PartyNoticeKind.queueRejected);
        expect(notices.forgotten, [PartyNoticeKind.queued]);
        finish(async);
      });
    });

    test('una coda di un altro (altri titoli) non conferma', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        emit(async, withAdded(['zz'], next: false));
        expect(outcome, isNull);
        async.elapse(PartyQueueEditor.addConfirmTimeout);
        expect(outcome, PartyQueueAddOutcome.rejected);
        finish(async);
      });
    });

    test('tutti già in coda: niente richiesta, niente avviso', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([testItem(id: 'e5')], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(outcome, PartyQueueAddOutcome.alreadyQueued);
        expect(api.calls, isEmpty);
        expect(notices.shown, isEmpty);
        finish(async);
      });
    });

    test('coda piena: avviso, niente richiesta', () {
      fakeAsync((async) {
        mount(async);
        emit(
            async,
            testSeriesQueue(
                itemIds: [for (var i = 0; i < 100; i++) 'x$i'],
                playingIndex: 0,
                lastUpdate: DateTime.utc(2026, 9, 30, 10, 1)));
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(outcome, PartyQueueAddOutcome.full);
        expect(api.calls, isEmpty);
        expect(notices.shown.last.kind, PartyNoticeKind.queueFull);
        finish(async);
      });
    });

    test('tagliata dal tetto: "Aggiunti 2 episodi su 3"', () {
      fakeAsync((async) {
        mount(async);
        // 98 titoli: posto per 2.
        final full = [for (var i = 0; i < 98; i++) 'x$i'];
        emit(
            async,
            testSeriesQueue(
                itemIds: full,
                playingIndex: 0,
                lastUpdate: DateTime.utc(2026, 9, 30, 10, 1)));
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([episode('d1', 1), episode('d2', 2), episode('d3', 3)],
                next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add d1,d2']);
        emit(
            async,
            PlayQueue(
              reason: 'Queue',
              lastUpdate: DateTime.utc(2026, 9, 30, 10, 5),
              entries: [
                for (var i = 0; i < 98; i++)
                  PlayQueueEntry(itemId: full[i], playlistItemId: 'p${i + 1}'),
                const PlayQueueEntry(itemId: 'd1', playlistItemId: 'n1'),
                const PlayQueueEntry(itemId: 'd2', playlistItemId: 'n2'),
              ],
              playingIndex: 0,
              startPosition: Duration.zero,
              isPlaying: false,
            ));
        expect(outcome, PartyQueueAddOutcome.added);
        final notice = notices.shown.last;
        expect(notice.kind, PartyNoticeKind.queuePartial);
        expect((notice.count, notice.total, notice.series), (2, 3, 'Dark'));
        finish(async);
      });
    });

    test('due aggiunte uguali insieme: la seconda non rimanda gli stessi', () {
      fakeAsync((async) {
        mount(async);
        unawaited(editor().add([film], next: false));
        unawaited(editor().add([film], next: true));
        async.flushMicrotasks();
        expect(api.calls, ['add m9']);
        emit(async, withAdded(['m9'], next: false));
        finish(async);
      });
    });

    test('richiesta fallita: "Non riuscito", eco dimenticata', () {
      fakeAsync((async) {
        mount(async);
        api.error = const ServerUnreachableException();
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(outcome, PartyQueueAddOutcome.failed);
        expect(notices.shown.last.kind, PartyNoticeKind.queueFailed);
        expect(notices.forgotten, [PartyNoticeKind.queued]);
        expect(announced(), isEmpty);
        finish(async);
      });
    });
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/watch_party/party_queue_editor_test.dart`
Expected: FAIL, `add` e `PartyQueueAddOutcome` non definiti.

- [ ] **Step 3: implementazione**

In `party_queue_editor.dart`:
- import `dart:async` e `../../core/jellyfin/item_models.dart`;
- prima della classe:

```dart
/// Esito di [PartyQueueEditor.add] (spec H §8.3).
enum PartyQueueAddOutcome {
  /// La coda del server ha i titoli (anche solo una parte, per il tetto).
  added,

  /// Erano già tutti in coda: niente richiesta, niente avviso.
  alreadyQueued,

  /// Coda piena: niente richiesta.
  full,

  /// Il server non l'ha presa entro [PartyQueueEditor.addConfirmTimeout].
  rejected,

  /// Richiesta non riuscita, o fuori dal gruppo.
  failed,
}
```

- nella classe:

```dart
  /// La coda nuova del server, dopo la richiesta, deve arrivare entro questo
  /// tempo: altrimenti il server ha scartato l'aggiunta, perché qualcuno nel
  /// party non può vedere un titolo (spec H §3).
  static const addConfirmTimeout = Duration(seconds: 4);

  /// Id di un'aggiunta che aspetta ancora la conferma: un'altra aggiunta non
  /// li rimanda.
  final _pendingAdds = <String>{};

  /// Aggiunge [items] in fondo alla coda o, con [next], subito dopo il titolo
  /// in corso (spec H §8.3): senza i titoli già in coda, tagliati al tetto.
  /// Aspetta la coda del server con i titoli nuovi, poi mostra "Hai…" (o
  /// l'avviso di errore).
  Future<PartyQueueAddOutcome> add(List<JellyfinItem> items,
      {required bool next}) async {
    final queue = _queue;
    if (queue == null || items.isEmpty) return PartyQueueAddOutcome.failed;
    final notices = _ref.read(partyNoticesProvider.notifier);
    final plan = partyQueueAddPlan(queue, [for (final item in items) item.id],
        pending: _pendingAdds);
    if (plan.send.isEmpty) {
      if (plan.cut == 0) return PartyQueueAddOutcome.alreadyQueued;
      notices.show(const PartyNotice(PartyNoticeKind.queueFull, mine: true));
      return PartyQueueAddOutcome.full;
    }
    final session = _ref.read(watchPartySessionProvider.notifier);
    final channel = _ref.read(partyChannelProvider.notifier);
    final kind = next ? PartyNoticeKind.queuedNext : PartyNoticeKind.queued;
    final before = {for (final entry in queue.entries) entry.playlistItemId};
    final confirmed = Completer<void>();
    // In ascolto prima della richiesta: la coda può arrivare prima della
    // risposta HTTP.
    final subscription = session.updates.listen((update) {
      if (update is PlayQueueUpdate &&
          _confirms(update.queue, before, plan.send) &&
          !confirmed.isCompleted) {
        confirmed.complete();
      }
    });
    _pendingAdds.addAll(plan.send);
    // La coda che torna dal server è nostra: l'avviso lo dà la conferma.
    notices.mine(kind, show: false);
    try {
      if (!await _send(
          'aggiunta alla coda', (api) => api.queue(plan.send, next: next))) {
        notices.forget(kind);
        return PartyQueueAddOutcome.failed;
      }
      channel.announce(next ? PartyAction.queueNext : PartyAction.queue);
      try {
        await confirmed.future.timeout(addConfirmTimeout);
      } on TimeoutException {
        notices.forget(kind);
        if (_ref.mounted && _ref.read(watchPartySessionProvider).inGroup) {
          notices.show(
              const PartyNotice(PartyNoticeKind.queueRejected, mine: true));
        }
        return PartyQueueAddOutcome.rejected;
      }
      final sent = [
        for (final id in plan.send) items.firstWhere((item) => item.id == id),
      ];
      final addition = partyQueueAddition(sent);
      notices.show(plan.cut > 0
          ? PartyNotice(PartyNoticeKind.queuePartial,
              mine: true,
              count: plan.send.length,
              total: plan.send.length + plan.cut,
              series: addition.series)
          : PartyNotice(kind,
              mine: true,
              title: addition.title,
              count: addition.count,
              series: addition.series));
      return PartyQueueAddOutcome.added;
    } finally {
      _pendingAdds.removeAll(plan.send);
      await subscription.cancel();
    }
  }

  /// La coda [queue] ha, tra gli elementi che non c'erano ([before]), tutti
  /// i titoli [sent] (un titolo già visto può tornare due volte).
  static bool _confirms(PlayQueue queue, Set<String> before, List<String> sent) {
    if (queue.reason != 'Queue' && queue.reason != 'QueueNext') return false;
    final added = [
      for (final entry in queue.entries)
        if (!before.contains(entry.playlistItemId)) entry.itemId,
    ];
    for (final id in sent) {
      if (!added.remove(id)) return false;
    }
    return true;
  }
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/watch_party/party_queue_editor_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/watch_party/party_queue_editor.dart test/features/watch_party/party_queue_editor_test.dart
git commit -m "feat(party): add titles to the queue with confirmation"
```

---

## Gruppo B — stato del pannello e viste

### Task 6: stato del pannello (viste, ricerca, episodi della serie)

**Files:**
- Create: `lib/features/player/queue_panel/queue_panel_state.dart`
- Test: `test/features/player/queue_panel_state_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/features/player/queue_panel_state_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/queue_panel/queue_panel_state.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakeLibraryApi library;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeSyncPlayApi();
    library = FakeLibraryApi();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  void mount(FakeAsync async) {
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      libraryApiProvider.overrideWithValue(library),
    ]);
    container
      ..listen(queuePanelNavProvider, (_, _) {})
      ..listen(queueAddSearchProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    async.flushMicrotasks();
  }

  QueuePanelNav nav() => container.read(queuePanelNavProvider.notifier);
  QueueAddSearch search() => container.read(queueAddSearchProvider.notifier);

  test('viste: apri, indietro, azzera; fuori dal gruppo si azzera', () {
    fakeAsync((async) {
      mount(async);
      expect(container.read(queuePanelNavProvider).last, isA<QueuePanelQueue>());
      final series = testItem(id: 's1', name: 'Dark', kind: ItemKind.series);
      nav()
        ..open(const QueuePanelAdd())
        ..open(QueuePanelSeries(series));
      expect(container.read(queuePanelNavProvider).last, isA<QueuePanelSeries>());
      nav().back();
      expect(container.read(queuePanelNavProvider).last, isA<QueuePanelAdd>());
      nav()
        ..back()
        ..back();
      expect(container.read(queuePanelNavProvider), hasLength(1),
          reason: 'la vista Coda resta');
      nav().open(const QueuePanelAdd());
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      expect(container.read(queuePanelNavProvider).last, isA<QueuePanelQueue>());
      container.dispose();
    });
  });

  test('ricerca: da 2 lettere, dopo 300 ms, film e serie, al massimo 20', () {
    fakeAsync((async) {
      library.onItems = (query, start, limit) =>
          pageOf([testItem(id: 'm1', name: 'Alien')]);
      mount(async);
      search().setTerm('a');
      async.elapse(QueueAddSearch.debounce);
      expect(library.itemQueries, isEmpty, reason: 'una lettera sola');
      search().setTerm('al');
      async.elapse(const Duration(milliseconds: 200));
      search().setTerm('ali');
      async.elapse(QueueAddSearch.debounce);
      expect(library.itemQueries, hasLength(1));
      final query = library.itemQueries.single;
      expect(query.searchTerm, 'ali');
      expect(query.kinds, {ItemKind.movie, ItemKind.series});
      expect(container.read(queueAddSearchProvider).results?.single.id, 'm1');
      expect(container.read(queueAddSearchProvider).term, 'ali');
      container.dispose();
    });
  });

  test('ricerca: errore, poi Riprova; azzera', () {
    fakeAsync((async) {
      library.error = const ServerUnreachableException();
      mount(async);
      search().setTerm('dark');
      async.elapse(QueueAddSearch.debounce);
      expect(container.read(queueAddSearchProvider).error, isNotNull);
      library.error = null;
      search().retry();
      async.flushMicrotasks();
      expect(container.read(queueAddSearchProvider).error, isNull);
      expect(container.read(queueAddSearchProvider).results, isNotNull);
      search().reset();
      expect(container.read(queueAddSearchProvider).term, '');
      expect(container.read(queueAddSearchProvider).results, isNull);
      container.dispose();
    });
  });

  test('episodi della serie: una richiesta sola', () {
    fakeAsync((async) {
      library.seriesEpisodes['s1'] = [testItem(id: 'e1')];
      mount(async);
      final sub = container.listen(
          queueSeriesEpisodesProvider('s1'), (_, _) {});
      async.flushMicrotasks();
      expect(container.read(queueSeriesEpisodesProvider('s1')).value?.single.id,
          'e1');
      expect(library.allEpisodesCalls, ['s1']);
      sub.close();
      container.dispose();
    });
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/player/queue_panel_state_test.dart`
Expected: FAIL, file non trovato.

- [ ] **Step 3: implementazione**

Crea `lib/features/player/queue_panel/queue_panel_state.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/jellyfin/api_exception.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../core/jellyfin/item_query.dart';
import '../../library/library_providers.dart';
import '../../watch_party/watch_party_session.dart';

/// Una vista del pannello "Coda" (spec H §9.2).
sealed class QueuePanelPage {
  const QueuePanelPage();
}

/// La coda del gruppo.
final class QueuePanelQueue extends QueuePanelPage {
  const QueuePanelQueue();
}

/// Ricerca e La mia lista.
final class QueuePanelAdd extends QueuePanelPage {
  const QueuePanelAdd();
}

/// Le stagioni di una serie.
final class QueuePanelSeries extends QueuePanelPage {
  const QueuePanelSeries(this.series);

  final JellyfinItem series;
}

/// Gli episodi di una stagione.
final class QueuePanelSeason extends QueuePanelPage {
  const QueuePanelSeason(this.series, this.season);

  final JellyfinItem series;
  final JellyfinItem season;
}

/// Le viste aperte nel pannello, dalla Coda in giù (l'ultima è quella
/// mostrata). Globale: quando il gruppo cambia titolo il player si
/// sostituisce, e il pannello si riapre dov'era (spec H §9.1). Si azzera
/// aprendo il pannello dal pulsante e uscendo dal gruppo.
class QueuePanelNav extends Notifier<List<QueuePanelPage>> {
  @override
  List<QueuePanelPage> build() {
    ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
        (_, inGroup) {
      if (!inGroup) reset();
    });
    return const [QueuePanelQueue()];
  }

  void open(QueuePanelPage page) => state = [...state, page];

  /// Torna alla vista prima; la Coda resta.
  void back() {
    if (state.length > 1) state = state.sublist(0, state.length - 1);
  }

  void reset() => state = const [QueuePanelQueue()];
}

final queuePanelNavProvider =
    NotifierProvider<QueuePanelNav, List<QueuePanelPage>>(QueuePanelNav.new);

class QueueAddSearchState {
  const QueueAddSearchState(
      {this.term = '', this.results, this.loading = false, this.error});

  final String term;

  /// Film e serie trovati; `null` finché non c'è una risposta.
  final List<JellyfinItem>? results;
  final bool loading;
  final Object? error;
}

/// La ricerca della vista Aggiungi (spec H §9.2): film e serie, da
/// [minLength] lettere, [debounce] dopo l'ultimo tasto, al massimo [limit];
/// una ricerca nuova annulla la vecchia. Globale come [QueuePanelNav], e si
/// azzera con lei.
class QueueAddSearch extends Notifier<QueueAddSearchState> {
  static const debounce = Duration(milliseconds: 300);
  static const minLength = 2;
  static const limit = 20;

  Timer? _debounce;
  CancelToken? _cancel;

  @override
  QueueAddSearchState build() {
    ref.onDispose(_stop);
    ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
        (_, inGroup) {
      if (!inGroup) reset();
    });
    return const QueueAddSearchState();
  }

  void setTerm(String raw) {
    final term = raw.trim();
    _stop();
    if (term.length < minLength) {
      state = QueueAddSearchState(term: term);
      return;
    }
    state =
        QueueAddSearchState(term: term, results: state.results, loading: true);
    _debounce = Timer(debounce, () => unawaited(_search(term)));
  }

  /// Rifà subito la ricerca di adesso (dopo un errore).
  void retry() {
    final term = state.term;
    if (term.length < minLength) return;
    _stop();
    state = QueueAddSearchState(term: term, loading: true);
    unawaited(_search(term));
  }

  void reset() {
    _stop();
    state = const QueueAddSearchState();
  }

  void _stop() {
    _debounce?.cancel();
    _cancel?.cancel();
  }

  Future<void> _search(String term) async {
    final cancel = _cancel = CancelToken();
    try {
      // Letti qui dentro: un timer scattato dopo il logout non deve lanciare.
      final page = await ref.read(libraryApiProvider).items(
            ItemQuery(
                kinds: const {ItemKind.movie, ItemKind.series},
                searchTerm: term),
            userId: ref.read(currentUserIdProvider),
            startIndex: 0,
            limit: limit,
            cancelToken: cancel,
          );
      if (!ref.mounted || cancel.isCancelled) return;
      state = QueueAddSearchState(term: term, results: page.items);
    } on RequestCancelledException {
      return;
    } on Object catch (error) {
      if (!ref.mounted || cancel.isCancelled) return;
      state = QueueAddSearchState(term: term, error: error);
    }
  }
}

final queueAddSearchProvider =
    NotifierProvider<QueueAddSearch, QueueAddSearchState>(QueueAddSearch.new);

/// Tutti gli episodi veri di una serie, per le viste Serie e Stagione (spec H
/// §9.2): una richiesta sola.
final queueSeriesEpisodesProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, String>((ref, seriesId) {
  ref.watch(libraryRevisionProvider);
  return ref
      .watch(libraryApiProvider)
      .allEpisodes(ref.watch(currentUserIdProvider), seriesId);
});
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/player/queue_panel_state_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player/queue_panel/queue_panel_state.dart test/features/player/queue_panel_state_test.dart
git commit -m "feat(party): queue panel pages and search state"
```

### Task 7: pezzi comuni; la vista Coda nel riquadro, con "＋ Aggiungi titoli"

**Files:**
- Create: `lib/features/player/queue_panel/queue_add_widgets.dart`
- Modify: `lib/features/player/queue_panel/queue_panel.dart`
- Test: `test/features/player/queue_add_widgets_test.dart`, `test/features/player/queue_panel_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/features/player/queue_add_widgets_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/features/player/queue_panel/queue_add_widgets.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  Future<void> pumpButtons(WidgetTester tester,
      {bool queued = false,
      bool full = false,
      required Future<void> Function({required bool next}) onAdd}) {
    return pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: QueueAddButtons(queued: queued, full: full, onAdd: onAdd),
        ),
      ),
    );
  }

  testWidgets('pulsanti: riproduci dopo e in coda, attesa, un clic alla volta',
      (tester) async {
    final calls = <bool>[];
    final gate = Completer<void>();
    await pumpButtons(tester, onAdd: ({required next}) {
      calls.add(next);
      return gate.future;
    });
    await tester.tap(find.byTooltip(l.partyQueuePlayNext));
    await tester.pump();
    expect(calls, [true]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip(l.partyQueueAddToEnd));
    await tester.pump();
    expect(calls, [true], reason: 'mentre aspetta non si ripreme');
    gate.complete();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byTooltip(l.partyQueueAddToEnd));
    await tester.pump();
    expect(calls, [true, false]);
  });

  testWidgets('pulsanti: già in coda → ✓; coda piena → spenti',
      (tester) async {
    await pumpButtons(tester, queued: true, onAdd: ({required next}) async {});
    expect(find.text(l.partyQueueInQueue), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);

    final calls = <bool>[];
    await pumpButtons(tester, full: true, onAdd: ({required next}) async {
      calls.add(next);
    });
    expect(find.byTooltip(l.partyQueueFull(100)), findsNWidgets(2));
    await tester.tap(find.byIcon(LucideIcons.listStart));
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('intestazione: indietro, titolo, sottotitolo, chiudi',
      (tester) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: SizedBox(
          width: 360,
          child: QueuePanelHeader(
            title: 'Dark',
            subtitle: '3 stagioni',
            onBack: () => calls.add('back'),
            onClose: () => calls.add('close'),
          ),
        ),
      ),
    );
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('3 stagioni'), findsOneWidget);
    await tester.tap(find.byTooltip(l.navBack));
    await tester.tap(find.byTooltip(l.playerClosePanel));
    expect(calls, ['back', 'close']);
  });

  testWidgets('messaggio con Riprova', (tester) async {
    var retries = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: QueueMessage(
            text: l.partyQueueLoadFailed, onRetry: () => retries++),
      ),
    );
    await tester.tap(find.text(l.retry));
    expect(retries, 1);
  });
}
```

In `queue_panel_test.dart`:
1. `pumpPanel` riceve `VoidCallback? onAddTitles` e lo passa a `QueuePanel(..., onAddTitles: onAddTitles)`.
2. In fondo a `main`:

```dart
  testWidgets('"＋ Aggiungi titoli" in fondo alla vista Coda', (tester) async {
    var opened = 0;
    await pumpPanel(tester, onAddTitles: () => opened++);
    await tester.tap(find.text(l.partyQueueAddTitles));
    expect(opened, 1);
  });

  testWidgets('senza onAddTitles nessun pulsante', (tester) async {
    await pumpPanel(tester);
    expect(find.text(l.partyQueueAddTitles), findsNothing);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/player/queue_add_widgets_test.dart test/features/player/queue_panel_test.dart`
Expected: FAIL, file e parametri non definiti.

- [ ] **Step 3: pezzi comuni**

Crea `lib/features/player/queue_panel/queue_add_widgets.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/jellyfin/image_urls.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../ui/wf_image.dart';
import '../../watch_party/party_queue_rules.dart';
import '../player_side_panel_host.dart';

/// Il riquadro delle viste del pannello "Coda" (spec H §9.2): fondo al 94 %,
/// bordo sinistro, la rotella che non arriva al volume. Tutto fuori dal
/// focus tranne [field] (il campo della ricerca): i tasti restano al player.
class QueuePanelFrame extends StatelessWidget {
  const QueuePanelFrame({
    super.key,
    required this.header,
    required this.body,
    this.field,
    this.footer,
  });

  final Widget header;
  final Widget? field;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final field = this.field;
    final footer = this.footer;
    return PanelWheelBarrier(
      child: Material(
        color: WfColors.surface.withValues(alpha: 0.94),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: WfColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeFocus(child: header),
              ?field,
              Expanded(child: ExcludeFocus(child: body)),
              if (footer != null) ExcludeFocus(child: footer),
            ],
          ),
        ),
      ),
    );
  }
}

/// Intestazione di una vista: ← (se c'è una vista prima), titolo con
/// sottotitolo, altri pulsanti, ✕.
class QueuePanelHeader extends StatelessWidget {
  const QueuePanelHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final subtitle = this.subtitle;
    final onBack = this.onBack;
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack == null ? 24 : 12, 20, 12, 8),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              tooltip: l.navBack,
              color: WfColors.cream,
              onPressed: onBack,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WfText.display(24)),
                if (subtitle != null)
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 12)),
              ],
            ),
          ),
          ...actions,
          IconButton(
            icon: const Icon(LucideIcons.x),
            tooltip: l.playerClosePanel,
            color: WfColors.cream,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Una riga delle viste Aggiungi, Serie e Stagione: immagine, titolo, riga
/// secondaria, in fondo [trailing].
class QueueItemRow extends ConsumerWidget {
  const QueueItemRow({
    super.key,
    required this.image,
    required this.title,
    this.details,
    this.trailing,
    this.onTap,
    this.landscape = false,
  });

  final ImageRef? image;
  final String title;
  final String? details;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Immagine 16:9 (episodi); altrimenti locandina 2:3.
  final bool landscape;

  /// Locandina 2:3 delle righe di film, serie e stagioni.
  static const posterWidth = 34.0;
  static const posterHeight = 51.0;

  /// Immagine 16:9 delle righe degli episodi.
  static const thumbWidth = 64.0;
  static const thumbHeight = 36.0;

  static const radius = 6.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = this.details;
    final trailing = this.trailing;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        hoverColor: WfColors.surfaceHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: landscape ? thumbWidth : posterWidth,
                  height: landscape ? thumbHeight : posterHeight,
                  child: WfImage(image: image),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    if (details != null)
                      Text(details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: WfColors.creamMuted)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// ↳ "Riproduci dopo" e ＋ "Aggiungi in coda" (spec H §9.2). Durante
/// l'attesa il pulsante premuto mostra un indicatore e nessuno dei due si
/// ripreme; già in coda → ✓ "In coda"; coda piena → spenti.
class QueueAddButtons extends StatefulWidget {
  const QueueAddButtons({
    super.key,
    required this.queued,
    required this.full,
    required this.onAdd,
  });

  final bool queued;
  final bool full;
  final Future<void> Function({required bool next}) onAdd;

  /// Lato dell'indicatore dell'attesa.
  static const pendingSize = 16.0;

  @override
  State<QueueAddButtons> createState() => _QueueAddButtonsState();
}

class _QueueAddButtonsState extends State<QueueAddButtons> {
  /// Il pulsante che aspetta (`true` = "Riproduci dopo"); `null` = nessuno.
  bool? _pendingNext;

  Future<void> _run(bool next) async {
    setState(() => _pendingNext = next);
    try {
      await widget.onAdd(next: next);
    } finally {
      if (mounted) setState(() => _pendingNext = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (widget.queued && _pendingNext == null) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.check, size: 14, color: WfColors.creamMuted),
            const SizedBox(width: 4),
            Text(l.partyQueueInQueue,
                style:
                    const TextStyle(fontSize: 11.5, color: WfColors.creamMuted)),
          ],
        ),
      );
    }
    Widget button(bool next) {
      final pending = _pendingNext == next;
      return IconButton(
        icon: pending
            ? const SizedBox.square(
                dimension: QueueAddButtons.pendingSize,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: WfColors.gold),
              )
            : Icon(next ? LucideIcons.listStart : LucideIcons.listPlus,
                size: 18),
        tooltip: widget.full
            ? l.partyQueueFull(partyQueueLimit)
            : next
                ? l.partyQueuePlayNext
                : l.partyQueueAddToEnd,
        color: WfColors.gold,
        visualDensity: VisualDensity.compact,
        onPressed: widget.full || _pendingNext != null ? null : () => _run(next),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [button(true), button(false)],
    );
  }
}

/// Lista vuota o errore, con "Riprova" se c'è [onRetry].
class QueueMessage extends StatelessWidget {
  const QueueMessage({super.key, required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final onRetry = this.onRetry;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: WfColors.creamMuted)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(l.retry)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: la vista Coda nel riquadro, con il pulsante in fondo**

In `queue_panel.dart`:

1. Import `queue_add_widgets.dart` e `../../../ui/wf_buttons.dart`. `QueuePanel` riceve `this.onAddTitles` e il campo:

```dart
  /// "＋ Aggiungi titoli" in fondo (spec H §9.2); `null` = nessun pulsante.
  final VoidCallback? onAddTitles;
```

2. Il `return PanelWheelBarrier(…)` di `_QueuePanelState.build` diventa un `QueuePanelFrame`. L'intestazione è `QueuePanelHeader` con il pulsante dell'ordine casuale tra gli `actions`. Il riepilogo e la lista vanno nel `body`:

```dart
    final onAddTitles = widget.onAddTitles;
    return QueuePanelFrame(
      header: QueuePanelHeader(
        title: l.partyQueueTitle,
        onClose: widget.onClose,
        actions: [
          IconButton(
            key: const Key('party-queue-shuffle'),
            icon: const Icon(LucideIcons.shuffle),
            isSelected: queue.shuffled,
            tooltip: l.partyQueueShuffle,
            color: queue.shuffled ? WfColors.gold : WfColors.cream,
            style: IconButton.styleFrom(
              backgroundColor: queue.shuffled
                  ? WfColors.gold.withValues(alpha: QueuePanel.shuffleOnFill)
                  : null,
            ),
            onPressed: () => widget.onShuffle(!queue.shuffled),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              runtime == null
                  ? titles
                  : l.partyQueueSummary(titles, formatRuntime(runtime)),
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 12),
            ),
          ),
          Expanded(child: list),
        ],
      ),
      footer: onAddTitles == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: WfButton.secondary(
                label: l.partyQueueAddTitles,
                icon: LucideIcons.plus,
                onPressed: onAddTitles,
              ),
            ),
    );
```

   La padding in alto dell'intestazione cambia di poco (`QueuePanelHeader`: 20 sopra, 8 sotto). I test esistenti della vista Coda devono restare verdi.

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/player`
Expected: PASS.

- [ ] **Step 6: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player/queue_panel test/features/player/queue_add_widgets_test.dart test/features/player/queue_panel_test.dart
git commit -m "feat(party): shared queue panel widgets and the add titles button"
```

### Task 8: vista Aggiungi

**Files:**
- Create: `lib/features/player/queue_panel/queue_add_view.dart`
- Test: `test/features/player/queue_add_view_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/features/player/queue_add_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/queue_panel/queue_add_view.dart';
import 'package:wonderflix/features/player/queue_panel/queue_panel_state.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  late FakeLibraryApi library;

  final heat = testItem(id: 'm1', name: 'Heat', year: 1995, sortName: 'heat');
  final alien =
      testItem(id: 'm2', name: 'Alien', year: 1979, sortName: 'alien');
  final dark = testItem(
      id: 's1',
      name: 'Dark',
      kind: ItemKind.series,
      childCount: 3,
      sortName: 'dark');

  setUp(() {
    library = FakeLibraryApi()
      ..onItems = (query, start, limit) => query.favoritesOnly
          ? pageOf([heat, dark, alien])
          : pageOf([alien]);
  });

  /// La vista con la coda e4 (in corso), m2 (Alien, già in coda).
  Future<List<String>> pumpView(WidgetTester tester,
      {PlayQueue? queue, FocusNode? focusNode}) async {
    final calls = <String>[];
    final node = focusNode ?? FocusNode();
    addTearDown(node.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 360,
            height: 900,
            child: QueueAddView(
              queue: queue ?? testSeriesQueue(itemIds: const ['e4', 'm2']),
              focusNode: node,
              onAdd: (items, {required next}) async => calls.add(
                  '${next ? 'next' : 'end'} ${items.map((i) => i.id).join(',')}'),
              onOpenSeries: (series) => calls.add('series ${series.id}'),
              onBack: () => calls.add('back'),
              onClose: () => calls.add('close'),
            ),
          ),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        libraryApiProvider.overrideWithValue(library),
        // La ricerca ascolta la sessione del party: niente WebSocket.
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    await tester.pump();
    return calls;
  }

  testWidgets('campo vuoto: La mia lista in ordine di titolo, il campo ha il '
      'focus', (tester) async {
    final node = FocusNode();
    await pumpView(tester, focusNode: node);
    expect(find.text(l.partyQueueMyList), findsOneWidget);
    final titles = [
      for (final name in ['Alien', 'Dark', 'Heat'])
        tester.getTopLeft(find.text(name)).dy,
    ];
    expect(titles, orderedEquals([...titles]..sort()));
    expect(find.text('Film · 1995 · 2h'), findsOneWidget);
    expect(find.text('Serie · 3 stagioni'), findsOneWidget);
    expect(node.hasFocus, isTrue);
  });

  testWidgets('film: riproduci dopo e in coda; già in coda → ✓', (tester) async {
    final calls = await pumpView(tester);
    final heatRow = find.byKey(const ValueKey('queue-add-m1'));
    await tester.tap(
        find.descendant(of: heatRow, matching: find.byTooltip(l.partyQueuePlayNext)));
    await tester.pump();
    await tester.tap(
        find.descendant(of: heatRow, matching: find.byTooltip(l.partyQueueAddToEnd)));
    await tester.pump();
    expect(calls, ['next m1', 'end m1']);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('queue-add-m2')),
            matching: find.text(l.partyQueueInQueue)),
        findsOneWidget);
  });

  testWidgets('serie: il clic apre le stagioni', (tester) async {
    final calls = await pumpView(tester);
    await tester.tap(find.text('Dark'));
    expect(calls, ['series s1']);
  });

  testWidgets('ricerca: da 2 lettere i risultati sostituiscono La mia lista',
      (tester) async {
    await pumpView(tester);
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pump(QueueAddSearch.debounce);
    await tester.pump();
    expect(find.text(l.partyQueueResults), findsOneWidget);
    expect(find.text(l.partyQueueMyList), findsNothing);
    expect(find.text('Heat'), findsNothing);
    expect(find.text('Alien'), findsOneWidget);
  });

  testWidgets('Esc: prima svuota il campo, poi chiude', (tester) async {
    final calls = await pumpView(tester);
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty);
    expect(calls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, ['close']);
  });

  testWidgets('← torna indietro', (tester) async {
    final calls = await pumpView(tester);
    await tester.tap(find.byTooltip(l.navBack));
    expect(calls, ['back']);
  });

  testWidgets('coda piena: pulsanti spenti', (tester) async {
    final calls = await pumpView(tester,
        queue: testSeriesQueue(
            itemIds: [for (var i = 0; i < 100; i++) 'x$i'], playingIndex: 0));
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('queue-add-m1')),
        matching: find.byTooltip(l.partyQueueFull(100)).first));
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('lista vuota ed errore con Riprova', (tester) async {
    library.onItems = (query, start, limit) => pageOf(const []);
    await pumpView(tester);
    expect(find.text(l.partyQueueMyListEmpty), findsOneWidget);

    library.error = const ServerUnreachableException();
    await tester.enterText(find.byType(TextField), 'zz');
    await tester.pump(QueueAddSearch.debounce);
    await tester.pump();
    expect(find.text(l.partyQueueLoadFailed), findsOneWidget);
    library.error = null;
    await tester.tap(find.text(l.retry));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.partyQueueNoResults), findsOneWidget);
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/player/queue_add_view_test.dart`
Expected: FAIL, file non trovato.

- [ ] **Step 3: implementazione**

Crea `lib/features/player/queue_panel/queue_add_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../core/syncplay/syncplay_models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/library_providers.dart';
import '../../mylist/my_list_screen.dart';
import '../../watch_party/party_queue_rules.dart';
import 'queue_add_widgets.dart';
import 'queue_panel_state.dart';
import 'queue_rows.dart';

/// Aggiunge [items] alla coda (in fondo, o con `next` subito dopo); finisce
/// quando l'aggiunta è confermata o fallita.
typedef QueueAddCallback = Future<void> Function(List<JellyfinItem> items,
    {required bool next});

/// La vista Aggiungi (spec H §9.2): il campo "Cerca film e serie" con il
/// focus, La mia lista a campo vuoto, i risultati da 2 lettere. Esc nel
/// campo prima lo svuota, poi chiude il pannello.
class QueueAddView extends ConsumerStatefulWidget {
  const QueueAddView({
    super.key,
    required this.queue,
    required this.focusNode,
    required this.onAdd,
    required this.onOpenSeries,
    required this.onBack,
    required this.onClose,
  });

  final PlayQueue queue;

  /// Il focus del campo: è del player, che sa quando i tasti vanno al campo.
  final FocusNode focusNode;
  final QueueAddCallback onAdd;
  final ValueChanged<JellyfinItem> onOpenSeries;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  ConsumerState<QueueAddView> createState() => _QueueAddViewState();
}

class _QueueAddViewState extends ConsumerState<QueueAddView> {
  // Il testo riparte da quello della ricerca: il pannello sopravvive al
  // cambio di player (spec H §9.1).
  late final _controller =
      TextEditingController(text: ref.read(queueAddSearchProvider).term);

  @override
  void initState() {
    super.initState();
    // `autofocus` non basta dentro il player: si chiede dopo il fotogramma.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _escape() {
    if (_controller.text.isNotEmpty) {
      _controller.clear();
      ref.read(queueAddSearchProvider.notifier).setTerm('');
    } else {
      widget.onClose();
    }
  }

  Widget _row(AppLocalizations l, JellyfinItem item, Set<String> queued,
      bool full) {
    final urls = ref.watch(imageUrlsProvider);
    if (item.kind == ItemKind.series) {
      final seasons = item.childCount;
      return QueueItemRow(
        key: ValueKey('queue-add-${item.id}'),
        image: urls.poster(item),
        title: item.name,
        details: [
          l.partyQueueSeries,
          if (seasons != null) l.detailSeasons(seasons),
        ].join(' · '),
        trailing: const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(LucideIcons.chevronRight,
              size: 18, color: WfColors.creamMuted),
        ),
        onTap: () => widget.onOpenSeries(item),
      );
    }
    return QueueItemRow(
      key: ValueKey('queue-add-${item.id}'),
      image: urls.poster(item),
      title: item.name,
      details: queueRowDetails(l, item),
      trailing: QueueAddButtons(
        queued: queued.contains(item.id),
        full: full,
        onAdd: ({required next}) => widget.onAdd([item], next: next),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final search = ref.watch(queueAddSearchProvider);
    final queued = partyQueueQueuedIds(widget.queue);
    final full = partyQueueRoom(widget.queue) == 0;
    final searching = search.term.length >= QueueAddSearch.minLength;

    Widget list(String title, List<JellyfinItem> items, String empty) =>
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            QueueSectionTitle(title),
            if (items.isEmpty) QueueMessage(text: empty),
            for (final item in items) _row(l, item, queued, full),
          ],
        );

    final Widget body;
    if (searching) {
      final results = search.results;
      body = search.error != null
          ? QueueMessage(
              text: l.partyQueueLoadFailed,
              onRetry: ref.read(queueAddSearchProvider.notifier).retry)
          : results == null
              ? const SizedBox.shrink()
              : list(l.partyQueueResults, results, l.partyQueueNoResults);
    } else {
      body = ref.watch(favoritesProvider).when(
            data: (items) => list(
                l.partyQueueMyList,
                [...items]..sort((a, b) => (a.sortName ?? a.name)
                    .toLowerCase()
                    .compareTo((b.sortName ?? b.name).toLowerCase())),
                l.partyQueueMyListEmpty),
            error: (_, _) => QueueMessage(
                text: l.partyQueueLoadFailed,
                onRetry: () => ref.invalidate(favoritesProvider)),
            loading: () => const SizedBox.shrink(),
          );
    }

    return QueuePanelFrame(
      header: QueuePanelHeader(
        title: l.partyQueueAddTitle,
        onBack: widget.onBack,
        onClose: widget.onClose,
      ),
      field: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _escape,
          },
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            onChanged: ref.read(queueAddSearchProvider.notifier).setTerm,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: l.partyQueueSearchHint,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              isDense: true,
              filled: true,
              fillColor: WfColors.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: WfColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: WfColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: WfColors.gold),
              ),
            ),
          ),
        ),
      ),
      body: body,
    );
  }
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/player/queue_add_view_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player/queue_panel/queue_add_view.dart test/features/player/queue_add_view_test.dart
git commit -m "feat(party): add view with search and My List"
```

### Task 9: viste Serie e Stagione

**Files:**
- Create: `lib/features/player/queue_panel/queue_series_views.dart`
- Test: `test/features/player/queue_series_views_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/features/player/queue_series_views_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/queue_panel/queue_series_views.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  late FakeLibraryApi library;

  final dark = testItem(
      id: 's1', name: 'Dark', kind: ItemKind.series, childCount: 3);
  final season1 =
      testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.other);
  final season2 =
      testItem(id: 'se2', name: 'Stagione 2', kind: ItemKind.other);
  final season3 =
      testItem(id: 'se3', name: 'Stagione 3', kind: ItemKind.other);

  JellyfinItem episode(String id, String seasonId, int index) => testItem(
      id: id,
      name: 'Episodio $index',
      kind: ItemKind.episode,
      seriesId: 's1',
      seriesName: 'Dark',
      seasonId: seasonId,
      index: index,
      seasonIndex: seasonId == 'se1' ? 1 : 2,
      runtimeMinutes: 52);

  setUp(() {
    library = FakeLibraryApi()
      ..seasonsBySeries['s1'] = [season1, season2, season3]
      // La stagione 3 ha solo episodi mancanti: non arrivano.
      ..seriesEpisodes['s1'] = [
        episode('a1', 'se1', 1),
        episode('a2', 'se1', 2),
        episode('a3', 'se1', 3),
        episode('b1', 'se2', 1),
        episode('b2', 'se2', 2),
      ];
  });

  /// In coda e4 (in corso), a1, a2: due episodi della stagione 1.
  final queue = testSeriesQueue(itemIds: const ['e4', 'a1', 'a2']);

  Future<List<String>> pump(WidgetTester tester, Widget view) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: 360, height: 900, child: view)),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        libraryApiProvider.overrideWithValue(library),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    await tester.pump();
    await tester.pump();
    return const [];
  }

  testWidgets('serie: stagioni con gli episodi, già in coda, una richiesta',
      (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      QueueSeriesView(
        series: dark,
        queue: queue,
        onAdd: (items, {required next}) async => calls.add(
            '${next ? 'next' : 'end'} ${items.map((i) => i.id).join(',')}'),
        onOpenSeason: (season) => calls.add('season ${season.id}'),
        onBack: () => calls.add('back'),
        onClose: () => calls.add('close'),
      ),
    );
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('3 stagioni'), findsOneWidget);
    expect(find.text('3 episodi · 2 già in coda'), findsOneWidget);
    expect(find.text('2 episodi'), findsOneWidget);
    expect(find.text('Stagione 3'), findsNothing,
        reason: 'nessun episodio vero');
    expect(library.allEpisodesCalls, ['s1']);

    final row1 = find.byKey(const ValueKey('queue-season-se1'));
    await tester.tap(find.descendant(
        of: row1, matching: find.byTooltip(l.partyQueuePlayNext)));
    await tester.pump();
    final row2 = find.byKey(const ValueKey('queue-season-se2'));
    await tester.tap(find.descendant(
        of: row2, matching: find.byTooltip(l.partyQueueAddToEnd)));
    await tester.pump();
    await tester.tap(find.text('Stagione 2'));
    expect(calls, ['next a3', 'end b1,b2', 'season se2'],
        reason: 'la stagione 1 manda solo l\'episodio che manca');
  });

  testWidgets('serie: stagione tutta in coda → ✓', (tester) async {
    await pump(
      tester,
      QueueSeriesView(
        series: dark,
        queue: testSeriesQueue(itemIds: const ['e4', 'a1', 'a2', 'a3']),
        onAdd: (items, {required next}) async {},
        onOpenSeason: (_) {},
        onBack: () {},
        onClose: () {},
      ),
    );
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('queue-season-se1')),
            matching: find.text(l.partyQueueInQueue)),
        findsOneWidget);
  });

  testWidgets('stagione: tutta dopo, tutta in coda, episodi singoli',
      (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      QueueSeasonView(
        series: dark,
        season: season1,
        queue: queue,
        onAdd: (items, {required next}) async => calls.add(
            '${next ? 'next' : 'end'} ${items.map((i) => i.id).join(',')}'),
        onBack: () => calls.add('back'),
        onClose: () => calls.add('close'),
      ),
    );
    expect(find.text('Stagione 1'), findsOneWidget);
    expect(find.text('Dark · 3 episodi'), findsOneWidget);
    expect(find.text('1. Episodio 1'), findsOneWidget);
    expect(find.text('52m'), findsNWidgets(3));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('queue-episode-a1')),
            matching: find.text(l.partyQueueInQueue)),
        findsOneWidget);
    await tester.tap(find.text(l.partyQueueWholeSeasonNext));
    await tester.pump();
    await tester.tap(find.text(l.partyQueueWholeSeasonEnd));
    await tester.pump();
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('queue-episode-a3')),
        matching: find.byTooltip(l.partyQueueAddToEnd)));
    await tester.pump();
    await tester.tap(find.byTooltip(l.navBack));
    expect(calls, ['next a3', 'end a3', 'end a3', 'back']);
  });
}
```

`testItem` ha `seasonId`; le stagioni usano `ItemKind.other`, che `testItem` scrive come `Folder`: il tipo non conta per queste viste.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/player/queue_series_views_test.dart`
Expected: FAIL, file non trovato.

- [ ] **Step 3: implementazione**

Crea `lib/features/player/queue_panel/queue_series_views.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../core/syncplay/syncplay_models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../ui/wf_buttons.dart';
import '../../detail/detail_providers.dart';
import '../../library/item_labels.dart';
import '../../library/library_providers.dart';
import '../../watch_party/party_queue_rules.dart';
import 'queue_add_view.dart';
import 'queue_add_widgets.dart';
import 'queue_panel_state.dart';

/// Gli episodi di [episodes] per stagione, nell'ordine dato.
Map<String, List<JellyfinItem>> _bySeason(List<JellyfinItem> episodes) {
  final seasons = <String, List<JellyfinItem>>{};
  for (final episode in episodes) {
    final seasonId = episode.seasonId;
    if (seasonId != null) (seasons[seasonId] ??= []).add(episode);
  }
  return seasons;
}

/// La vista Serie (spec H §9.2): una riga per stagione con episodi veri, con
/// ↳/＋ per tutta la stagione (gli episodi già in coda si saltano) e ›.
class QueueSeriesView extends ConsumerWidget {
  const QueueSeriesView({
    super.key,
    required this.series,
    required this.queue,
    required this.onAdd,
    required this.onOpenSeason,
    required this.onBack,
    required this.onClose,
  });

  final JellyfinItem series;
  final PlayQueue queue;
  final QueueAddCallback onAdd;
  final ValueChanged<JellyfinItem> onOpenSeason;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final seasons = ref.watch(seasonsProvider(series.id));
    final episodes = ref.watch(queueSeriesEpisodesProvider(series.id));
    final queued = partyQueueQueuedIds(queue);
    final full = partyQueueRoom(queue) == 0;
    final count = series.childCount;

    final Widget body;
    if (seasons.hasError || episodes.hasError) {
      body = QueueMessage(
        text: l.partyQueueLoadFailed,
        onRetry: () => ref
          ..invalidate(seasonsProvider(series.id))
          ..invalidate(queueSeriesEpisodesProvider(series.id)),
      );
    } else if (seasons.value case final seasonList?
        when episodes.value != null) {
      final bySeason = _bySeason(episodes.value!);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          for (final season in seasonList)
            if (bySeason[season.id] case final list? when list.isNotEmpty)
              () {
                final remaining = [
                  for (final episode in list)
                    if (!queued.contains(episode.id)) episode,
                ];
                final already = list.length - remaining.length;
                return QueueItemRow(
                  key: ValueKey('queue-season-${season.id}'),
                  image: urls.poster(season) ?? urls.poster(series),
                  title: season.name,
                  details: [
                    l.partyQueueEpisodeCount(list.length),
                    if (already > 0) l.partyQueueAlreadyQueuedCount(already),
                  ].join(' · '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QueueAddButtons(
                        queued: remaining.isEmpty,
                        full: full,
                        onAdd: ({required next}) =>
                            onAdd(remaining, next: next),
                      ),
                      const Icon(LucideIcons.chevronRight,
                          size: 18, color: WfColors.creamMuted),
                    ],
                  ),
                  onTap: () => onOpenSeason(season),
                );
              }(),
        ],
      );
    } else {
      body = const SizedBox.shrink();
    }

    return QueuePanelFrame(
      header: QueuePanelHeader(
        title: series.name,
        subtitle: count == null ? null : l.detailSeasons(count),
        onBack: onBack,
        onClose: onClose,
      ),
      body: body,
    );
  }
}

/// La vista Stagione (spec H §9.2): "Tutta dopo" e "Tutta in coda" in alto,
/// poi un episodio per riga.
class QueueSeasonView extends ConsumerWidget {
  const QueueSeasonView({
    super.key,
    required this.series,
    required this.season,
    required this.queue,
    required this.onAdd,
    required this.onBack,
    required this.onClose,
  });

  final JellyfinItem series;
  final JellyfinItem season;
  final PlayQueue queue;
  final QueueAddCallback onAdd;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final episodes = ref.watch(queueSeriesEpisodesProvider(series.id));
    final queued = partyQueueQueuedIds(queue);
    final full = partyQueueRoom(queue) == 0;
    final list = _bySeason(episodes.value ?? const [])[season.id] ?? const [];
    final remaining = [
      for (final episode in list)
        if (!queued.contains(episode.id)) episode,
    ];

    final Widget body;
    if (episodes.hasError) {
      body = QueueMessage(
        text: l.partyQueueLoadFailed,
        onRetry: () => ref.invalidate(queueSeriesEpisodesProvider(series.id)),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          if (remaining.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _WholeSeasonButtons(
                full: full,
                onAdd: ({required next}) => onAdd(remaining, next: next),
              ),
            ),
          for (final episode in list)
            QueueItemRow(
              key: ValueKey('queue-episode-${episode.id}'),
              image: urls.landscape(episode),
              landscape: true,
              title: episode.indexNumber == null
                  ? episode.name
                  : l.partyQueueEpisodeTitle(
                      episode.indexNumber!, episode.name),
              details: episode.runtime == null
                  ? null
                  : formatRuntime(episode.runtime!),
              trailing: QueueAddButtons(
                queued: queued.contains(episode.id),
                full: full,
                onAdd: ({required next}) => onAdd([episode], next: next),
              ),
            ),
        ],
      );
    }

    return QueuePanelFrame(
      header: QueuePanelHeader(
        title: season.name,
        subtitle: '${series.name} · ${l.partyQueueEpisodeCount(list.length)}',
        onBack: onBack,
        onClose: onClose,
      ),
      body: body,
    );
  }
}

/// "Tutta dopo" e "Tutta in coda": un'aggiunta alla volta, come
/// [QueueAddButtons].
class _WholeSeasonButtons extends StatefulWidget {
  const _WholeSeasonButtons({required this.full, required this.onAdd});

  final bool full;
  final Future<void> Function({required bool next}) onAdd;

  @override
  State<_WholeSeasonButtons> createState() => _WholeSeasonButtonsState();
}

class _WholeSeasonButtonsState extends State<_WholeSeasonButtons> {
  bool _pending = false;

  Future<void> _run(bool next) async {
    setState(() => _pending = true);
    try {
      await widget.onAdd(next: next);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final enabled = !widget.full && !_pending;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        WfButton.primary(
          label: l.partyQueueWholeSeasonNext,
          icon: LucideIcons.listStart,
          onPressed: enabled ? () => _run(true) : null,
        ),
        WfButton.secondary(
          label: l.partyQueueWholeSeasonEnd,
          icon: LucideIcons.listPlus,
          onPressed: enabled ? () => _run(false) : null,
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/player/queue_series_views_test.dart`
Expected: PASS. Se `seasonsProvider`, che passa da `libraryRevisionProvider`, chiede un override nei test, aggiungilo come negli altri test che usano `seasonsProvider`.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player/queue_panel/queue_series_views.dart test/features/player/queue_series_views_test.dart
git commit -m "feat(party): series and season views of the queue panel"
```

---

## Gruppo C — il pannello nel player

### Task 10: viste nel pannello, focus e tasti

**Files:**
- Modify: `lib/features/player/queue_panel/queue_panel.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono**

In `party_player_test.dart`:
- import di `queue_add_view.dart`, `queue_series_views.dart`, `queue_panel.dart` (c'è già);
- nella libreria finta di `pumpPartyPlayer`: `library.onItems = (query, start, limit) => pageOf([testItem(id: 'm9', name: 'Alien', year: 1979)]);` e `library.itemsById['m9'] = testItem(id: 'm9', name: 'Alien', year: 1979);` (se aggiungerlo per tutti i test cambia altri test, fallo solo nei test nuovi);
- in fondo a `main`:

```dart
  group('aggiungere titoli (spec H §9.2)', () {
    Future<void> openAdd(WidgetTester tester) async {
      library.onItems = (query, start, limit) =>
          pageOf([testItem(id: 'm9', name: 'Alien', year: 1979)]);
      library.itemsById['m9'] = testItem(id: 'm9', name: 'Alien', year: 1979);
      await tester.tap(find.byTooltip(l.partyQueueOpen));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.partyQueueAddTitles));
      await tester.pumpAndSettle();
    }

    testWidgets('dalla vista Coda alla vista Aggiungi; riproduci dopo; la '
        'conferma dà "Hai messo subito dopo"', (tester) async {
      await pumpPartyPlayer(tester);
      await queueSeries(tester);
      await openAdd(tester);
      expect(find.byType(QueueAddView), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('queue-add-m9')),
          matching: find.byTooltip(l.partyQueuePlayNext)));
      await tester.pump();
      expect(api.calls, contains('add-next m9'));
      expect(announced(),
          contains(equals({'Type': 'Action', 'Action': 'QueueNext'})));
      emit(PlayQueueUpdate(
          'g1',
          PlayQueue(
            reason: 'QueueNext',
            lastUpdate: DateTime.utc(2026, 9, 30, 10, 5),
            entries: const [
              PlayQueueEntry(itemId: 'e4', playlistItemId: 'p1'),
              PlayQueueEntry(itemId: 'm9', playlistItemId: 'p9'),
              PlayQueueEntry(itemId: 'e5', playlistItemId: 'p2'),
              PlayQueueEntry(itemId: 'e6', playlistItemId: 'p3'),
            ],
            playingIndex: 0,
            startPosition: Duration.zero,
            isPlaying: false,
          )));
      await tester.pump();
      await tester.pump();
      expect(find.text('Hai messo subito dopo: Alien'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('queue-add-m9')),
              matching: find.text(l.partyQueueInQueue)),
          findsOneWidget);
      await finish(tester);
    });

    testWidgets('mentre si scrive i tasti del player sono fermi; Esc svuota, '
        'poi chiude, e i tasti tornano al player', (tester) async {
      await pumpPartyPlayer(tester);
      await queueSeries(tester);
      await openAdd(tester);
      api.calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(api.calls.where((c) => c == 'unpause' || c.startsWith('next')),
          isEmpty);
      await tester.enterText(find.byType(TextField), 'al');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(QueueAddView), findsOneWidget, reason: 'ha svuotato');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(QueueAddView), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(api.calls, contains('unpause'));
      await finish(tester);
    });

    testWidgets('← torna alla Coda; riaperto dal pulsante parte dalla Coda',
        (tester) async {
      await pumpPartyPlayer(tester);
      await queueSeries(tester);
      await openAdd(tester);
      await tester.tap(find.byTooltip(l.navBack));
      await tester.pumpAndSettle();
      expect(find.byType(QueuePanel), findsOneWidget);
      await tester.tap(find.text(l.partyQueueAddTitles));
      await tester.pumpAndSettle();
      // Il pannello copre il pulsante Coda: si chiude con la ✕, poi si
      // riapre dal pulsante.
      await tester.tap(find.byTooltip(l.playerClosePanel));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l.partyQueueOpen));
      await tester.pumpAndSettle();
      expect(find.byType(QueuePanel), findsOneWidget);
      expect(find.byType(QueueAddView), findsNothing);
      await finish(tester);
    });

    testWidgets('il gruppo cambia titolo mentre si cerca: il pannello resta '
        'sulla vista Aggiungi con il testo', (tester) async {
      await pumpPartyPlayer(tester);
      await queueSeries(tester);
      await openAdd(tester);
      await tester.enterText(find.byType(TextField), 'ali');
      await tester.pump(const Duration(milliseconds: 300));
      emit(PlayQueueUpdate(
          'g1',
          testSeriesQueue(
              playingIndex: 1,
              reason: 'SetCurrentItem',
              lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/play/e5?party=p2');
      expect(find.byType(QueueAddView), findsOneWidget);
      expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'ali');
      await finish(tester);
    });
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/watch_party/party_player_test.dart`
Expected: FAIL, il pannello non ha le viste.

- [ ] **Step 3: il pannello sceglie la vista**

In `queue_panel.dart`, `PartyQueuePanel`:
- riceve `required this.searchFocusNode` e il campo:

```dart
  /// Il focus del campo di ricerca della vista Aggiungi: è del player.
  final FocusNode searchFocusNode;
```

- il `build` diventa:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
        watchPartySessionProvider.select((s) => s.inGroup ? s.queue : null));
    if (queue == null) return const SizedBox.shrink();
    final editor = ref.read(partyQueueEditorProvider);
    final pages = ref.watch(queuePanelNavProvider);
    final nav = ref.read(queuePanelNavProvider.notifier);
    Future<void> add(List<JellyfinItem> items, {required bool next}) =>
        editor.add(items, next: next);
    final view = switch (pages.last) {
      QueuePanelQueue() => QueuePanel(
          queue: queue,
          items: ref.watch(partyQueueItemsProvider),
          onJump: (id) {
            onBeforeJump?.call();
            unawaited(editor.jumpTo(id));
          },
          onRemove: (id) => unawaited(editor.remove(id)),
          onMove: (id, index) => unawaited(editor.move(id, index)),
          onShuffle: (shuffle) => unawaited(editor.setShuffle(shuffle)),
          onAddTitles: () => nav.open(const QueuePanelAdd()),
          onClose: onClose,
        ),
      QueuePanelAdd() => QueueAddView(
          queue: queue,
          focusNode: searchFocusNode,
          onAdd: add,
          onOpenSeries: (series) => nav.open(QueuePanelSeries(series)),
          onBack: nav.back,
          onClose: onClose,
        ),
      QueuePanelSeries(:final series) => QueueSeriesView(
          series: series,
          queue: queue,
          onAdd: add,
          onOpenSeason: (season) => nav.open(QueuePanelSeason(series, season)),
          onBack: nav.back,
          onClose: onClose,
        ),
      QueuePanelSeason(:final series, :final season) => QueueSeasonView(
          series: series,
          season: season,
          queue: queue,
          onAdd: add,
          onBack: nav.back,
          onClose: onClose,
        ),
    };
    // Le viste si sostituiscono sfumando (spec H §9.2); la chiave è la
    // profondità, così tornando indietro la vista è quella di prima.
    return AnimatedSwitcher(
      duration: WfMotion.of(context).duration(WfMotion.fast),
      child: KeyedSubtree(
          key: ValueKey('queue-page-${pages.length}'), child: view),
    );
  }
```

- import `../../../app/motion.dart`, `queue_add_view.dart`, `queue_series_views.dart`, `queue_panel_state.dart`.

- [ ] **Step 4: il player**

In `player_screen.dart`:

1. Dopo `_chatFocusNode`:

```dart
  /// Focus del campo di ricerca del pannello "Coda" (spec H §9.3): è del
  /// player, che finché il campo ce l'ha gli lascia i tasti.
  final _queueSearchFocusNode = FocusNode(debugLabel: 'party-queue-search');
```

   In `initState`: `_queueSearchFocusNode.addListener(_onQueueSearchFocus);`. In `dispose`, dopo `_chatFocusNode.dispose();`: `_queueSearchFocusNode.dispose();`.

2. Dopo `_onChatKey`:

```dart
  /// Il campo di ricerca del pannello "Coda" ha il focus: i tasti vanno a
  /// lui (spec H §9.3), tranne quelli multimediali; Tab non lo lascia. Esc lo
  /// prende il campo stesso (svuota, poi chiude il pannello).
  KeyEventResult _onQueueSearchKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    _chrome.keyActivity();
    final key = event.logicalKey;
    if (isMediaKey(key)) {
      final command = _commandFor(event);
      if (command == null) return KeyEventResult.ignored;
      _run(command);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  /// Il campo di ricerca ha perso il focus (vista cambiata, pannello chiuso):
  /// se non l'ha preso nessun altro, torna al player.
  void _onQueueSearchFocus() {
    if (_queueSearchFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.isCurrentOf(context) ?? true)) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null || primary is FocusScopeNode) {
        _focusNode.requestFocus();
      }
    });
  }
```

3. In `_onKey`, dopo `if (_chrome.chatOpen) return _onChatKey(event);`:

```dart
    if (_queueSearchFocusNode.hasFocus) return _onQueueSearchKey(event);
```

4. In `_onChromeChanged`, dopo il blocco della chat:

```dart
    // Pannello "Coda" chiuso con il campo di ricerca a fuoco: i tasti tornano
    // al player subito, non a fine animazione.
    if (_chrome.popup != PlayerPopup.queue &&
        _queueSearchFocusNode.hasFocus &&
        (ModalRoute.isCurrentOf(context) ?? true)) {
      _focusNode.requestFocus();
    }
```

5. `onToggleQueue` del `PlayerOverlay` diventa:

```dart
                        onToggleQueue: party != null &&
                                party.inGroup &&
                                party.queue != null
                            ? () {
                                // Aperto dal pulsante: si riparte dalla Coda
                                // (spec H §9.1).
                                if (_chrome.popup != PlayerPopup.queue) {
                                  ref.read(queuePanelNavProvider.notifier)
                                      .reset();
                                  ref.read(queueAddSearchProvider.notifier)
                                      .reset();
                                }
                                _chrome.togglePopup(PlayerPopup.queue);
                              }
                            : null,
```

6. Il pannello non sta più dentro `ExcludeFocus`, perché il campo di ricerca deve prendere il focus: il resto lo esclude `QueuePanelFrame`. Diventa:

```dart
                if (party != null)
                  Positioned.fill(
                    key: const ValueKey('player-queue-panel'),
                    child: PlayerSidePanelHost(
                      open: _chrome.popup == PlayerPopup.queue &&
                          party.inGroup,
                      panel: PartyQueuePanel(
                        searchFocusNode: _queueSearchFocusNode,
                        onClose: () => _chrome.closePopup(PlayerPopup.queue),
                        // Come ⏮ e ⏭: il `Seek` in sospeso non deve
                        // arrivare dopo il salto di riga.
                        onBeforeJump: () => _authority?.cancelPendingSeek(),
                      ),
                    ),
                  ),
```

7. Import `queue_panel/queue_panel_state.dart`.

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/watch_party/party_player_test.dart test/features/player`
Expected: PASS. Restano verdi anche i test del 14a sul pannello: tastiera dopo un clic su una riga, rotella, Esc, clic sul film.

- [ ] **Step 6: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player test/features/watch_party/party_player_test.dart
git commit -m "feat(party): add titles from the player's queue panel"
```

---

## Gruppo D — allineamento e verifica finale

### Task 11: spec allineata, verifica, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md`
- Modify: `docs/RELEASING.md`, solo se descrive versioni di esempio del plugin da aggiornare

- [ ] **Step 1: allinea la spec**

Edit mirati nella spec:
1. **Stato:** `approvato; piani 14a e 14b realizzati (docs/superpowers/plans/2026-10-04-wonderflix-14a-coda-party.md, docs/superpowers/plans/2026-10-04-wonderflix-14b-aggiungere-release.md)`.
2. **§8.1:** aggiungi `LibraryApi.allEpisodes(userId, seriesId)`: tutti gli episodi veri della serie (`isMissing=false`, senza `seasonId`), una richiesta per le viste Serie e Stagione.
3. **§8.2:** il piano dell'aggiunta salta anche gli id di un'aggiunta ancora in attesa (`pending`).
4. **§8.3, `add`:** l'esito è `PartyQueueAddOutcome` (`added`, `alreadyQueued`, `full`, `rejected`, `failed`). La conferma si aspetta sul flusso `updates` della sessione, in ascolto prima della richiesta. Gli id in attesa (`_pendingAdds`) non si rimandano.
5. **§9.1:** il pannello si riapre dov'era (vista, serie o stagione, testo della ricerca) dopo il cambio di player. Lo stato (`queuePanelNavProvider`, `queueAddSearchProvider`) si azzera aprendo il pannello dal pulsante e uscendo dal gruppo.
6. **§9.2, vista Aggiungi:** La mia lista è `favoritesProvider` ordinato per titolo. Durante il caricamento non si mostra niente (nessuno scheletro).
7. **§9.2, vista Serie:** le stagioni da `seasonsProvider`; i conteggi da `allEpisodes`; le stagioni senza episodi veri non compaiono.
8. **§9.3:** il pannello non sta più dentro `ExcludeFocus`: `QueuePanelFrame` esclude dal focus tutto tranne il campo. Esc lo prende il campo (`CallbackShortcuts`). Il player riprende il focus quando il campo lo perde.
9. **§10:** gli avvisi delle aggiunte altrui chiedono i dettagli di al massimo 50 titoli (`PartyNotices.additionDetails`). Oltre, dicono solo "N titoli".

- [ ] **Step 2: verifica completa**

Run:
- `flutter analyze` → nessun problema;
- `flutter test` → tutto verde. Annota il numero.
- `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → tutto verde (il plugin non cambia).

- [ ] **Step 3: build di release**

Prima copia nel worktree `config/wonderflix.json` dal checkout principale, se non c'è già. Poi:

Run: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
Expected: `build/windows/x64/runner/Release/wonderflix.exe` creato.

Dopo la build, se `windows/flutter/` ha solo cambi di fine riga, `git checkout -- windows/flutter/`.

- [ ] **Step 4: commit**

```bash
git add docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md
git commit -m "docs: align spec H with plan 14b"
```

---

## Prova manuale (con l'utente, dopo la review finale)

Due istanze con due utenti Jellyfin diversi: la seconda con `WONDERFLIX_PROFILE=b`. Il plugin 1.3.0 è sul server.

1. **Aggiungi.** A apre la Coda e poi "＋ Aggiungi titoli". Controlla:
   - il campo ha il focus;
   - La mia lista è in ordine di titolo;
   - scrivendo 2 lettere compaiono i risultati.
2. **Riproduci dopo un film.**
   - Su A: la riga mostra l'attesa, poi ✓, e la pillola dice "Hai messo subito dopo: …".
   - Su B: "A ha messo subito dopo: …".
   - Nella Coda il film è subito dopo il titolo in corso.
3. **Serie.** A apre una serie: ci sono le stagioni con il numero di episodi. Con "Tutta in coda" su una stagione B vede "A ha aggiunto alla coda: N episodi di …". La stagione mostra "· N già in coda" o ✓.
4. **Stagione.**
   - "Tutta dopo" mette la stagione dopo il titolo in corso, nell'ordine giusto.
   - Un episodio singolo si aggiunge.
   - Gli episodi già in coda mostrano ✓.
5. **Tastiera:**
   - mentre si scrive, Spazio, N e P non comandano il player;
   - Esc svuota il campo, il secondo Esc chiude il pannello;
   - dopo la chiusura Spazio mette in pausa.
6. **Il gruppo va avanti** (B preme ⏭) mentre A cerca: il pannello di A resta sulla vista Aggiungi con il testo.
7. **Coda piena o titolo non visibile.**
   - Se c'è un titolo che B non può vedere (libreria non condivisa), aggiungerlo dà "Non aggiunto: qualcuno nel party non può vedere questo titolo".
   - Con una coda quasi a 100 titoli, una stagione lunga dà "Aggiunti N episodi su M: la coda è piena".

---

## Release (dopo il merge, con l'utente)

Segue `docs/RELEASING.md`, prima il plugin e poi l'app.

1. **Plugin 1.3.0, con l'ok dell'utente.**
   - Tag `watch-party-plugin-v1.3.0` su `main` e push del tag. Il workflow `watch-party-plugin.yml` crea la **pre-release** con lo zip e il suo MD5. Controllare che `releases/latest` resti l'app.
   - Voce 1.3.0.0 in `jellyfin-plugin-watch-party/manifest.json`: `sourceUrl` dello zip, `checksum` MD5, `changelog` in inglese "Names for the party queue actions (previous, jump, add, shuffle)", `targetAbi` 10.11.0.0, `timestamp`. Commit `chore: publish the watch party plugin 1.3.0` e push.
2. **Server** (`ssh ultra`; prima controllare nel log che nessuno stia guardando):
   1. `app-jellyfin stop`;
   2. spostare `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.3.0.0` (la copia manuale) in `~/wfwp-backup/1.3.0.0-manuale`;
   3. `app-jellyfin start`.

   L'utente aggiorna dal Catalogo (Dashboard → Plugin → WonderFlix Watch Party → 1.3.0.0). Poi `app-jellyfin restart` e nel log `Loaded plugin: "WonderFlix Watch Party" "1.3.0.0"`; la dll ha lo stesso MD5 dello zip.
3. **App 0.8.0, non obbligatoria.**
   - Commit `chore: release 0.8.0`: `pubspec.yaml` `version: 0.8.0+…`, come le release precedenti.
   - Con l'ok dell'utente: tag `v0.8.0`, push, pipeline Release.
   - A pipeline finita scrivo le note in italiano nella bozza (`gh release edit v0.8.0 --notes-file …`), **senza** il marcatore `min-version`. Le note parlano di: coda del watch party, aggiungere titoli, titolo precedente, ordine casuale, plugin 1.3.0 per i nomi.
   - **Pubblica l'utente.**
