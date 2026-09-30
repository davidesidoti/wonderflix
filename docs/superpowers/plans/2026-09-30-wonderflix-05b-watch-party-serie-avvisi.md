# WonderFlix — Piano 5b: serie e avvisi nel watch party

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** completare l'esperienza del watch party durante la visione:
- "Guarda insieme" anche su episodi e serie: la coda del gruppo contiene l'episodio e i successivi (al massimo 50); per una serie si parte dal prossimo episodio da vedere;
- cambio di episodio per tutti:
  - pulsante "Prossimo episodio", tasto N e tasto multimediale mandano `NextItem`;
  - sui titoli di coda la scheda "Prossimo episodio" compare **senza conto alla rovescia**;
  - alla fine vera del video il primo client che ci arriva manda `NextItem` (il server scarta i doppioni);
  - il player passa all'episodio nuovo mantenendo lo schermo intero e segnando come visto quello lasciato sui titoli di coda;
  - a fine coda il gruppo resta aperto;
- "Guarda insieme" stando già in un gruppo cambia il titolo per tutti;
- avvisi a pillola (spec B §5.7): pausa, ripresa, salto, episodio successivo, nuovo titolo, entrate e uscite, riallineamento, ripresa senza aspettare. Le proprie azioni compaiono subito in seconda persona, senza l'eco del server;
- compensazione del ritardo con cui mpv riparte dopo una ripresa programmata (~0,5 s nella prova del 5a);
- membri senza nomi doppi.

Inviti, creazione dal player, rientro automatico, permessi, `SetIgnoreWait`, Discord e diagnostica sono del **Piano 5c**.

**Decisioni prese con l'utente (2026-09-30):**
- in gruppo la scheda "Prossimo episodio" non ha il conto alla rovescia e l'impostazione personale "riproduci automaticamente" non conta: si va avanti con il pulsante o alla fine vera del video;
- coda di una serie: al massimo 50 episodi;
- ritardo alla ripartenza: si misura 1,5 s dopo ogni ripresa programmata partita da fermo, se ne tiene una stima (metà della correzione a ogni misura, tra 0 e 1 s) e alla ripresa successiva ci si allinea in anticipo di quel valore.

**Architecture:**
- `SyncPlayApi.nextItem` e `LibraryApi.episodesFrom` (episodi di una serie da un episodio in poi).
- `WatchPartySession`: coda impostabile alla creazione, `setQueue` dentro un gruppo, `nextItem`, stream `updates` degli aggiornamenti del gruppo, membri senza ripetizioni.
- `buildPartyQueue` (`party_queue.dart`): film = sé stesso, episodio = sé stesso e i successivi.
- `StartLag` (`lib/core/syncplay/start_lag.dart`, Dart puro) e anticipo nel `GroupPlaybackDriver`, che segnala anche i riallineamenti (`onResync`).
- `PartyNotices` (Notifier): coda di avvisi (3 s ciascuno), eco delle proprie azioni scartata entro 3 s. Legge gli aggiornamenti e i comandi della sessione; `GroupAuthority` e il driver gli segnalano azioni proprie e riallineamenti. `PartyNoticePill` li mostra nel player.
- `PlayerScreen` nel gruppo: episodio successivo, scheda senza conto alla rovescia, fine video, passaggio all'episodio nuovo (lo fa il player stesso, non il routing), pillole.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router, `clock` + `fake_async` nei test, `logging`.

**Spec:** `docs/superpowers/specs/2026-09-30-wonderflix-watch-party-design.md` (§5.2, §5.4, §5.7, §6, §7). **Piano precedente:** `docs/superpowers/plans/2026-09-30-wonderflix-05a-watch-party-film.md` (il codice del 5a è su `main`).

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…". Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/watch-party-5b`, branch `feat/watch-party-5b`). Comandi git semplici, non composti con variabili.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde. Se `lib/l10n/gen` manca o è vecchio, esegui prima `flutter gen-l10n`.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione:** non eseguire `dart format` su file interi.
- **Fine riga:** molti file sono CRLF (ARB, `player_screen.dart`, …). Modificali con Edit mirati che mantengono le fini riga; non riscriverli.
- **Import:** se l'analyzer segnala un import superfluo o mancante, correggilo e segnalalo.
- **Icone:** solo `LucideIcons`, niente emoji.
- **Tempo:** solo `clock.now()` (pacchetto `clock`), mai `DateTime.now()`. Nei test `fakeAsync`; nei widget test il tempo è già finto.
- **Test e zone:** gli eventi di uno stream arrivano nella zona in cui ci si è iscritti. Nei test con `fakeAsync` il container va creato **dentro** la zona finta (come fanno i test della sessione del 5a con `mount()`).
- **Widget test:** qualunque `Timer` rimasto aperto a fine test fa fallire il test. L'orologio del gruppo ha dei timer: i test del player chiudono tutto con `finish` (vedi `test/features/watch_party/party_player_test.dart`). `find.byType` non trova le sottoclassi: per `WfButton` cerca il testo.
- **Log nei test:** nessuno ascolta `Logger.root`.
- **Fake:** niente mocktail. `FakeSyncPlayApi`, `testGroup`, `testQueue` sono in `test/support/watch_party_fakes.dart`; `FakeLibraryApi` e `testItem` in `test/support/library_fakes.dart`; `FakeVideoEngine` in `test/support/playback_fakes.dart`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test sfuggito al piano): correggilo in modo minimo, nello spirito del piano, e segnalalo. I test descrivono il comportamento richiesto: preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **`POST /SyncPlay/NextItem`** con `{"PlaylistItemId": <in riproduzione>}`. Il server passa all'elemento successivo solo se l'id coincide con quello in riproduzione: le richieste doppie degli altri membri (arrivate dopo il cambio) vengono ignorate. Il gruppo va in `Waiting`, tutti ricevono la coda (`PlayQueue`, `Reason` = `NextItem`, nuovo `PlayingItemIndex`) e il server aspetta i `Ready`.
- **Ordine dei messaggi del server:** per pausa, ripresa e salto il server manda **prima** il comando (`SyncPlayCommand`) e **poi** lo `StateUpdate` con il motivo (`Reason`: `Pause`, `Unpause`, `Seek`, `Buffer`, `Ready`, `NextItem`, `Play`…). Un `Unpause` con il gruppo in `Waiting` e `ResumePlaying` attivo fa partire tutti subito: `StateUpdate` con `State` = `Playing` e `Reason` = `Unpause`, dopo uno stato `Waiting`. Quando tutti sono pronti dopo un salto il motivo è `Ready` (non `Unpause`).
- **`UserJoined`/`UserLeft`** arrivano agli altri membri, non a chi entra o esce. `Participants` del server è senza ripetizioni (per nome utente), ma `UserJoined`/`UserLeft` arrivano per ogni sessione.
- **Episodi da un episodio in poi:** `GET /Shows/{seriesId}/Episodes?userId=…&startItemId=<episodio>&limit=50&isMissing=false` restituisce l'episodio indicato e i successivi, anche nelle stagioni dopo (lo stesso endpoint che usa già `LibraryApi.nextEpisode`).
- **Scheda "Prossimo episodio":** compare da `nextEpisodeCardFrom(segments, duration)` (inizio dei crediti, altrimenti gli ultimi 30 s). `NextEpisodeCard` ha già il parametro `countdown`.
- **Etichette:** `formatClock(Duration)`, `cardTitle(item)` (per un episodio: la serie) e `cardSubtitle(item)` (per un episodio: `S1:E5 · Titolo`) in `lib/features/library/item_labels.dart`.
- **Testi degli avvisi:** per entrate e uscite si usa "Marco è nel watch party" / "Marco ha lasciato il watch party" (neutri rispetto al genere) invece di "è entrato/uscito" dello spec.

## Mappa dei file

```
lib/core/syncplay/syncplay_api.dart                + nextItem
lib/core/syncplay/start_lag.dart                   StartLag (nuovo)
lib/core/jellyfin/library_api.dart                 + episodesFrom
lib/features/watch_party/watch_party_session.dart  coda, setQueue, nextItem, updates, membri
lib/features/watch_party/party_queue.dart          buildPartyQueue (nuovo)
lib/features/watch_party/watch_party_actions.dart  startWatchParty con la coda
lib/features/watch_party/group_playback_driver.dart  anticipo alla ripartenza, onResync
lib/features/watch_party/party_notices.dart        PartyNotice, PartyNotices (nuovo)
lib/features/watch_party/party_notice_pill.dart    pillola e testi (nuovo)
lib/features/watch_party/group_authority.dart      onAction
lib/features/watch_party/watch_party_routing.dart  non sostituisce un player del gruppo; tiene vivi gli avvisi
lib/features/detail/detail_header.dart             "Guarda insieme" anche per episodi e serie
lib/features/player/player_screen.dart             episodio successivo, passaggio, pillole
l10n/app_it.arb, l10n/app_en.arb                   testi degli avvisi
test/support/watch_party_fakes.dart                nextItem, testSeriesQueue
test/support/library_fakes.dart                    episodesFrom
```

## Gruppi per i subagent

| Gruppo | Task | Contenuto |
|---|---|---|
| A | 1–3 | API, testi, sessione (coda, prossimo elemento, aggiornamenti, membri) |
| B | 4–5 | coda della serie e "Guarda insieme", anticipo alla ripartenza |
| C | 6–7 | avvisi (controller, pillola, azioni proprie) |
| D | 8–9 | player nel gruppo (episodi, passaggio, pillole), verifica finale |

---

### Task 1: `nextItem` ed `episodesFrom`

**Files:**
- Modify: `lib/core/syncplay/syncplay_api.dart`
- Modify: `lib/core/jellyfin/library_api.dart`
- Modify: `test/support/watch_party_fakes.dart`, `test/support/library_fakes.dart`
- Test: `test/core/syncplay/syncplay_api_test.dart`, `test/core/jellyfin/library_api_test.dart`

- [ ] **Step 1: scrivi i test**

In `test/core/syncplay/syncplay_api_test.dart`, dentro `main()`, in fondo:

```dart
  test('nextItem con l\'elemento in riproduzione', () async {
    await api.nextItem('p1');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/SyncPlay/NextItem');
    expect(body(), {'PlaylistItemId': 'p1'});
  });
```

In `test/core/jellyfin/library_api_test.dart`, dopo il test di `nextEpisode`:

```dart
  test('episodesFrom: l\'episodio indicato e i successivi', () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['e4', 'e5', 'e6']));
    final episodes = await api.episodesFrom('u1', 's1', 'e4', limit: 50);
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['startItemId'], 'e4');
    expect(last().query['limit'], 50);
    expect(last().query['isMissing'], false);
    expect(last().query['userId'], 'u1');
    expect(episodes.map((e) => e.id), ['e4', 'e5', 'e6']);
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/syncplay/syncplay_api_test.dart test/core/jellyfin/library_api_test.dart`
Expected: FAIL (`nextItem` ed `episodesFrom` non definiti).

- [ ] **Step 3: aggiungi i due metodi**

In `lib/core/syncplay/syncplay_api.dart`, dopo `seek`:

```dart
  /// Passa all'elemento successivo della coda. [playlistItemId] è quello in
  /// riproduzione: il server ignora le richieste doppie degli altri membri.
  Future<void> nextItem(String playlistItemId) =>
      _post('/SyncPlay/NextItem', {'PlaylistItemId': playlistItemId});
```

In `lib/core/jellyfin/library_api.dart`, dopo `nextEpisode`:

```dart
  /// [startItemId] e gli episodi che lo seguono nella serie, anche nelle
  /// stagioni dopo (al massimo [limit]); senza gli episodi mancanti.
  Future<List<JellyfinItem>> episodesFrom(
          String userId, String seriesId, String startItemId,
          {int limit = 50}) async =>
      _list(await _http.get('/Shows/$seriesId/Episodes', query: {
        'userId': userId,
        'startItemId': startItemId,
        'limit': limit,
        'isMissing': false,
      }));
```

- [ ] **Step 4: aggiorna i fake**

In `test/support/watch_party_fakes.dart`, nella classe `FakeSyncPlayApi`, dopo `seek`:

```dart
  @override
  Future<void> nextItem(String playlistItemId) =>
      _record('next $playlistItemId');
```

e in fondo al file, dopo `testQueue`:

```dart
/// Coda di una serie: episodi [itemIds] con id nella coda `p1`, `p2`, …;
/// in riproduzione quello di indice [playingIndex].
PlayQueue testSeriesQueue({
  List<String> itemIds = const ['e4', 'e5', 'e6'],
  int playingIndex = 0,
  String reason = 'NewPlaylist',
  DateTime? lastUpdate,
}) =>
    PlayQueue(
      reason: reason,
      lastUpdate: lastUpdate ?? DateTime.utc(2026, 9, 30, 10),
      entries: [
        for (var i = 0; i < itemIds.length; i++)
          PlayQueueEntry(itemId: itemIds[i], playlistItemId: 'p${i + 1}'),
      ],
      playingIndex: playingIndex,
      startPosition: Duration.zero,
      isPlaying: false,
    );
```

In `test/support/library_fakes.dart`, nella classe `FakeLibraryApi`, dopo `final Map<String, JellyfinItem> nextEpisodes = {};`:

```dart

  /// Tutti gli episodi di ogni serie, in ordine (per [episodesFrom]).
  final Map<String, List<JellyfinItem>> seriesEpisodes = {};
  final episodesFromCalls =
      <({String seriesId, String startItemId, int limit})>[];
```

e dopo il metodo `nextEpisode`:

```dart
  @override
  Future<List<JellyfinItem>> episodesFrom(
      String userId, String seriesId, String startItemId,
      {int limit = 50}) {
    episodesFromCalls
        .add((seriesId: seriesId, startItemId: startItemId, limit: limit));
    return _answer(() {
      final all = seriesEpisodes[seriesId] ?? const <JellyfinItem>[];
      final start = all.indexWhere((e) => e.id == startItemId);
      if (start < 0) return const <JellyfinItem>[];
      return all.skip(start).take(limit).toList();
    });
  }
```

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/core/`
Expected: PASS.

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/syncplay/syncplay_api.dart lib/core/jellyfin/library_api.dart test/support/watch_party_fakes.dart test/support/library_fakes.dart test/core/syncplay/syncplay_api_test.dart test/core/jellyfin/library_api_test.dart
git commit -m "feat: add next item and episode queue requests"
```

---

### Task 2: testi degli avvisi

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan5b_test.dart`

- [ ] **Step 1: scrivi il test**

`test/app/l10n_plan5b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 5b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.watchPartyNoticePaused, 'Pausa');
    expect(it.watchPartyNoticePausedByYou, 'Hai messo in pausa');
    expect(it.watchPartyNoticeResumed, 'Ripresa');
    expect(it.watchPartyNoticeResumedByYou, 'Hai ripreso');
    expect(it.watchPartyNoticeForcedResume, 'Si riprende senza aspettare');
    expect(it.watchPartyNoticeSeek('32:10'), 'Salto a 32:10');
    expect(it.watchPartyNoticeSeekByYou('32:10'), 'Hai saltato a 32:10');
    expect(it.watchPartyNoticeNextEpisode('S1:E5 · Titolo'),
        'Episodio successivo: S1:E5 · Titolo');
    expect(it.watchPartyNoticeNowWatching('Dune'), 'Si guarda: Dune');
    expect(it.watchPartyNoticeJoined('Luigi'), 'Luigi è nel watch party');
    expect(it.watchPartyNoticeLeft('Luigi'),
        'Luigi ha lasciato il watch party');
    expect(it.watchPartyNoticeResync, 'Riallineamento al gruppo');
    expect(en.watchPartyNoticeSeekByYou('32:10'), 'You jumped to 32:10');
    expect(en.watchPartyNoticeJoined('Luigi'), 'Luigi joined the watch party');
    expect(en.watchPartyNoticeResync, 'Resyncing with the group');
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/l10n_plan5b_test.dart`
Expected: FAIL (getter mancanti).

- [ ] **Step 3: aggiungi i testi**

`l10n/app_it.arb` (CRLF): con un Edit mirato sull'ultima riga, `"watchPartyAccessDenied": "Non hai accesso a questo contenuto."`, aggiungi la virgola e queste righe prima della `}` finale:

```json
  "watchPartyNoticePaused": "Pausa",
  "watchPartyNoticePausedByYou": "Hai messo in pausa",
  "watchPartyNoticeResumed": "Ripresa",
  "watchPartyNoticeResumedByYou": "Hai ripreso",
  "watchPartyNoticeForcedResume": "Si riprende senza aspettare",
  "watchPartyNoticeSeek": "Salto a {time}",
  "@watchPartyNoticeSeek": {"placeholders": {"time": {"type": "String"}}},
  "watchPartyNoticeSeekByYou": "Hai saltato a {time}",
  "@watchPartyNoticeSeekByYou": {"placeholders": {"time": {"type": "String"}}},
  "watchPartyNoticeNextEpisode": "Episodio successivo: {title}",
  "@watchPartyNoticeNextEpisode": {"placeholders": {"title": {"type": "String"}}},
  "watchPartyNoticeNowWatching": "Si guarda: {title}",
  "@watchPartyNoticeNowWatching": {"placeholders": {"title": {"type": "String"}}},
  "watchPartyNoticeJoined": "{name} è nel watch party",
  "@watchPartyNoticeJoined": {"placeholders": {"name": {"type": "String"}}},
  "watchPartyNoticeLeft": "{name} ha lasciato il watch party",
  "@watchPartyNoticeLeft": {"placeholders": {"name": {"type": "String"}}},
  "watchPartyNoticeResync": "Riallineamento al gruppo"
```

`l10n/app_en.arb`, stesso metodo dopo `"watchPartyAccessDenied": "You don't have access to this content."`:

```json
  "watchPartyNoticePaused": "Paused",
  "watchPartyNoticePausedByYou": "You paused",
  "watchPartyNoticeResumed": "Resumed",
  "watchPartyNoticeResumedByYou": "You resumed",
  "watchPartyNoticeForcedResume": "Resuming without waiting",
  "watchPartyNoticeSeek": "Jump to {time}",
  "watchPartyNoticeSeekByYou": "You jumped to {time}",
  "watchPartyNoticeNextEpisode": "Next episode: {title}",
  "watchPartyNoticeNowWatching": "Now watching: {title}",
  "watchPartyNoticeJoined": "{name} joined the watch party",
  "watchPartyNoticeLeft": "{name} left the watch party",
  "watchPartyNoticeResync": "Resyncing with the group"
```

Run: `flutter gen-l10n`
Expected: nessun errore.

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/app/l10n_plan5b_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add l10n/app_it.arb l10n/app_en.arb test/app/l10n_plan5b_test.dart
git commit -m "feat: add watch party notice strings"
```

---

### Task 3: sessione — coda, elemento successivo, aggiornamenti, membri

**Files:**
- Modify: `lib/features/watch_party/watch_party_session.dart`
- Test: `test/features/watch_party/watch_party_session_test.dart`

Cosa si aggiunge:
- `create(item, queue: [...], start: …)`: la coda è facoltativa (default: solo `item`);
- `setQueue(queue, start: …)`: nuova coda per il gruppo in cui siamo (nessuna richiesta fuori da un gruppo);
- `nextItem()`: `NextItem` con l'elemento in riproduzione; `false` (e nessuna richiesta) se non c'è un elemento dopo;
- `WatchPartyState.nextEntry` / `hasNext`;
- `updates`: stream degli aggiornamenti del **nostro** gruppo (entrate, uscite, stato, coda), dopo che lo stato è stato aggiornato. Le code scartate perché vecchie non si inoltrano;
- `members` senza ripetizioni. La lista grezza (`group.participants`) tiene una voce per sessione: `UserLeft` ne toglie una.

- [ ] **Step 1: scrivi i test**

In `test/features/watch_party/watch_party_session_test.dart`, dentro `main()`, in fondo (i test usano `mount()`, `serverAccepts()`, `emit()` già definiti nel file):

```dart
  test('create con la coda di una serie', () async {
    mount();
    serverAccepts();
    await session().create(
        testItem(
            id: 'e4',
            name: 'Pilot',
            kind: ItemKind.episode,
            seriesName: 'Breaking Bad'),
        queue: ['e4', 'e5', 'e6']);
    expect(api.calls, ['create Mario · Breaking Bad', 'queue e4,e5,e6']);
  });

  test('setQueue: nel gruppo solo la nuova coda; fuori nessuna richiesta',
      () async {
    mount();
    await session().setQueue(['m2']);
    expect(api.calls, isEmpty);

    serverAccepts();
    await session().join('g1');
    await session().setQueue(['m2'], start: const Duration(minutes: 2));
    expect(api.calls, ['join g1', 'queue m2']);
    expect(api.queues.single.start, const Duration(minutes: 2));
  });

  test('setQueue con un errore di rete', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    api.error = const ServerUnreachableException();
    await expectLater(
        session().setQueue(['m2']),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.network)));
    expect(state().inGroup, isTrue);
  });

  test('nextItem: solo se c\'è un elemento dopo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    expect(await session().nextItem(), isFalse);

    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    await pumpEventQueue();
    expect(state().hasNext, isTrue);
    expect(state().nextEntry?.itemId, 'e5');
    expect(await session().nextItem(), isTrue);
    expect(api.calls.last, 'next p1');

    emit(PlayQueueUpdate(
        'g1',
        testSeriesQueue(
            playingIndex: 2, lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await pumpEventQueue();
    expect(state().hasNext, isFalse);
    expect(await session().nextItem(), isFalse);
    expect(api.calls.last, 'next p1');
  });

  test('membri: lo stesso utente con due sessioni compare una volta', () async {
    mount();
    serverAccepts(participants: ['Mario', 'Luigi']);
    await session().join('g1');
    emit(const UserJoined('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi']);

    emit(const UserLeft('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi'],
        reason: 'Luigi ha ancora una sessione nel gruppo');

    emit(const UserLeft('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario']);
  });

  test('updates: solo gli aggiornamenti del nostro gruppo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);

    emit(const UserJoined('g1', 'Luigi'));
    emit(const UserJoined('g2', 'Bowser'));
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    // Più vecchia della precedente: scartata e non inoltrata.
    emit(PlayQueueUpdate(
        'g1', testSeriesQueue(lastUpdate: DateTime.utc(2026, 9, 30, 9))));
    await pumpEventQueue();
    expect(updates.map((u) => u.runtimeType),
        [UserJoined, GroupStateUpdate, PlayQueueUpdate]);
  });
```

Se `ServerUnreachableException` non è già importata nel file di test, l'import è `package:wonderflix/core/jellyfin/api_exception.dart` (c'è già dal 5a).

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/watch_party/watch_party_session_test.dart`
Expected: FAIL (`queue:`, `setQueue`, `nextItem`, `hasNext`, `updates` non definiti).

- [ ] **Step 3: aggiorna lo stato**

In `lib/features/watch_party/watch_party_session.dart`, nella classe `WatchPartyState`, sostituisci il getter `members` con:

```dart
  /// Membri senza ripetizioni: lo stesso utente può avere più sessioni.
  List<String> get members => {...?group?.participants}.toList();

  /// Elemento dopo quello in riproduzione; `null` a fine coda.
  PlayQueueEntry? get nextEntry {
    final queue = this.queue;
    if (queue == null || queue.playingIndex < 0) return null;
    final index = queue.playingIndex + 1;
    return index < queue.entries.length ? queue.entries[index] : null;
  }

  bool get hasNext => nextEntry != null;
```

- [ ] **Step 4: aggiorna la sessione**

Nella classe `WatchPartySession`:

1. Dopo `late StreamController<SyncPlayCommand> _commands;`:

```dart
  late StreamController<GroupUpdate> _updates;
```

2. In `build()`, dopo la riga che crea `_commands`:

```dart
    final updates = _updates = StreamController<GroupUpdate>.broadcast();
```

e nel primo `ref.onDispose(...)` aggiungi `unawaited(updates.close());` accanto a `commands.close()`.

3. Dopo il getter `lastCommand`:

```dart
  /// Aggiornamenti del nostro gruppo (entrate, uscite, stato, coda), già
  /// applicati allo stato. Servono agli avvisi.
  Stream<GroupUpdate> get updates => _updates.stream;
```

4. Sostituisci `create` con:

```dart
  /// Crea un gruppo per [item] con la coda [queue] (di default solo [item])
  /// e ci fa partire la riproduzione da [start]. Lancia [WatchPartyException].
  Future<void> create(JellyfinItem item,
      {List<String>? queue, Duration start = Duration.zero}) async {
    if (state.phase == WatchPartyPhase.joining) return;
    final session = ref.read(sessionControllerProvider);
    final userName = session is SessionSignedIn ? session.user.name : '';
    await _enter(() => _api.create('$userName · ${partyTitle(item)}'));
    try {
      await _api.setNewQueue(queue ?? [item.id], start: start);
    } on ApiException catch (error) {
      _log.warning('coda del watch party non impostata: $error');
      await leave();
      throw const WatchPartyException(WatchPartyFailure.network);
    }
  }

  /// Nuova coda per il gruppo in cui siamo ("Guarda insieme" dentro un
  /// gruppo): cambia il titolo per tutti. Fuori da un gruppo non fa nulla.
  /// Lancia [WatchPartyException].
  Future<void> setQueue(List<String> queue,
      {Duration start = Duration.zero}) async {
    if (!state.inGroup) return;
    try {
      await _api.setNewQueue(queue, start: start);
    } on ApiException catch (error) {
      _log.warning('nuova coda del watch party non impostata: $error');
      throw const WatchPartyException(WatchPartyFailure.network);
    }
  }

  /// Il gruppo passa all'elemento successivo della coda (pulsante, tasto N,
  /// fine del video). `false` se non ce n'è uno.
  Future<bool> nextItem() async {
    final playing = state.queue?.playing;
    if (!state.inGroup || playing == null || !state.hasNext) return false;
    try {
      await _api.nextItem(playing.playlistItemId);
    } on Object catch (error) {
      _log.warning('episodio successivo non chiesto: $error');
    }
    return true;
  }
```

5. In `_onGroupUpdate`, sostituisci i quattro casi del gruppo corrente con (la lista grezza tiene i doppioni, `members` li toglie; ogni aggiornamento applicato si inoltra su `updates`):

```dart
      case UserJoined(:final groupId, :final userName) when _isCurrent(groupId):
        state = state.copyWith(
            group: state.group!.copyWith(
                participants: [...state.group!.participants, userName]));
        _updates.add(update);
      case UserLeft(:final groupId, :final userName) when _isCurrent(groupId):
        final participants = [...state.group!.participants]..remove(userName);
        state = state.copyWith(
            group: state.group!.copyWith(participants: participants));
        _updates.add(update);
      case GroupStateUpdate(:final groupId, state: final groupState)
          when _isCurrent(groupId):
        state = state.copyWith(groupState: groupState);
        _updates.add(update);
      case PlayQueueUpdate(:final groupId, :final queue)
          when _isCurrent(groupId):
        final current = state.queue;
        if (current != null && queue.lastUpdate.isBefore(current.lastUpdate)) {
          return;
        }
        state = state.copyWith(queue: queue);
        _updates.add(update);
```

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/features/watch_party/`
Expected: PASS (anche i test del 5a).

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/watch_party_session.dart test/features/watch_party/watch_party_session_test.dart
git commit -m "feat: queue, next item and group updates in the watch party session"
```

---
### Task 4: coda della serie e "Guarda insieme" per episodi e serie

**Files:**
- Create: `lib/features/watch_party/party_queue.dart`
- Modify: `lib/features/watch_party/watch_party_actions.dart`
- Modify: `lib/features/detail/detail_header.dart`
- Test: `test/features/watch_party/party_queue_test.dart`, `test/features/watch_party/watch_party_actions_test.dart`, `test/features/detail/movie_detail_test.dart`

Regole (spec B §5.2):
- film: coda con il solo film;
- episodio: l'episodio e i successivi della serie, al massimo 50;
- serie: il pulsante della scheda della serie riproduce già il prossimo episodio da vedere (`action.target`), quindi vale la regola dell'episodio;
- stando già in un gruppo si manda solo la nuova coda (`setQueue`), senza creare un gruppo;
- si parte dallo stesso punto di "Riproduci/Riprendi".

- [ ] **Step 1: scrivi i test della coda**

`test/features/watch_party/party_queue_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/watch_party/party_queue.dart';

import '../../support/library_fakes.dart';

void main() {
  late FakeLibraryApi library;

  JellyfinItem episode(String id, {String? seriesId = 's1'}) => testItem(
      id: id, name: 'Ep $id', kind: ItemKind.episode, seriesId: seriesId);

  setUp(() {
    library = FakeLibraryApi()
      ..seriesEpisodes['s1'] = [
        episode('e1'),
        episode('e2'),
        episode('e3'),
      ];
  });

  test('film: solo il film, senza richieste', () async {
    expect(await buildPartyQueue(library, 'u1', testItem(id: 'm1')), ['m1']);
    expect(library.episodesFromCalls, isEmpty);
  });

  test('episodio: lui e i successivi, al massimo 50', () async {
    expect(await buildPartyQueue(library, 'u1', episode('e2')), ['e2', 'e3']);
    final call = library.episodesFromCalls.single;
    expect(call.seriesId, 's1');
    expect(call.startItemId, 'e2');
    expect(call.limit, maxPartyQueue);
    expect(maxPartyQueue, 50);
  });

  test('episodio non restituito dal server: solo lui', () async {
    expect(await buildPartyQueue(library, 'u1', episode('e9')), ['e9']);
  });

  test('episodio senza serie: solo lui', () async {
    expect(
        await buildPartyQueue(library, 'u1', episode('e1', seriesId: null)),
        ['e1']);
    expect(library.episodesFromCalls, isEmpty);
  });

  test('errore del server: si propaga', () async {
    library.error = const ServerUnreachableException();
    expect(buildPartyQueue(library, 'u1', episode('e1')),
        throwsA(isA<ServerUnreachableException>()));
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/watch_party/party_queue_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi la coda**

`lib/features/watch_party/party_queue.dart`:

```dart
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/library_api.dart';

/// Episodi al massimo nella coda di una serie: bastano per qualunque serata,
/// e una serie lunga non diventa una richiesta enorme.
const maxPartyQueue = 50;

/// Coda del gruppo per [item] (spec B §5.2): un film da solo; un episodio
/// con quelli che lo seguono nella serie, al massimo [maxPartyQueue].
Future<List<String>> buildPartyQueue(
    LibraryApi library, String userId, JellyfinItem item) async {
  final seriesId = item.seriesId;
  if (item.kind != ItemKind.episode || seriesId == null) return [item.id];
  final episodes = await library.episodesFrom(userId, seriesId, item.id,
      limit: maxPartyQueue);
  final ids = [for (final episode in episodes) episode.id];
  final start = ids.indexOf(item.id);
  return start < 0 ? [item.id] : ids.sublist(start);
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/features/watch_party/party_queue_test.dart`
Expected: PASS.

- [ ] **Step 5: scrivi i test di `startWatchParty`**

`test/features/watch_party/watch_party_actions_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_actions.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakeLibraryApi library;
  late StreamController<ServerEvent> events;
  final pilot = testItem(
      id: 'e4',
      name: 'Pilot',
      kind: ItemKind.episode,
      seriesId: 's1',
      seriesName: 'Breaking Bad');

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    library = FakeLibraryApi()
      ..seriesEpisodes['s1'] = [
        pilot,
        testItem(id: 'e5', kind: ItemKind.episode, seriesId: 's1'),
      ];
    api.onCall = (call) {
      if (call.startsWith('create') || call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  Future<void> pumpButton(WidgetTester tester) => pumpApp(
        tester,
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => unawaited(startWatchParty(context, ref, pilot,
                  start: const Duration(minutes: 3))),
              child: const Text('via'),
            ),
          ),
        ),
        overrides: [
          libraryApiProvider.overrideWithValue(library),
          syncPlayApiProvider.overrideWithValue(api),
          watchPartyEventsProvider.overrideWithValue(events.stream),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
      );

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.text('via')));

  /// Esce dal gruppo: ferma l'orologio (i suoi timer non devono restare).
  Future<void> leave(WidgetTester tester) async {
    await container(tester).read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets('fuori da un gruppo: crea il gruppo con la coda della serie',
      (tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(api.calls, ['create Mario · Breaking Bad', 'queue e4,e5']);
    expect(api.queues.single.start, const Duration(minutes: 3));
    await leave(tester);
  });

  testWidgets('dentro un gruppo: solo la nuova coda', (tester) async {
    await pumpButton(tester);
    unawaited(container(tester).read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(api.calls, ['join g1', 'queue e4,e5']);
    await leave(tester);
  });

  testWidgets('coda non disponibile: avviso, nessun gruppo', (tester) async {
    library.error = const ServerUnreachableException();
    await pumpButton(tester);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(find.text('Non è stato possibile avviare il watch party.'),
        findsOneWidget);
    expect(api.calls, isEmpty);
  });
}
```

- [ ] **Step 6: verifica che fallisca**

Run: `flutter test test/features/watch_party/watch_party_actions_test.dart`
Expected: FAIL (oggi `startWatchParty` crea il gruppo con il solo elemento: `queue e4`).

- [ ] **Step 7: aggiorna `startWatchParty`**

In `lib/features/watch_party/watch_party_actions.dart` aggiungi gli import:

```dart
import '../library/library_providers.dart';
import 'party_queue.dart';
```

e sostituisci `startWatchParty`:

```dart
/// "Guarda insieme": crea il gruppo con la coda di [item] (per un episodio:
/// anche i successivi), oppure, stando già in un gruppo, gli cambia la coda.
/// Il player si apre quando il server conferma la coda
/// (`watchPartyRoutingProvider`).
Future<void> startWatchParty(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item, {
  Duration start = Duration.zero,
}) =>
    _run(
      context,
      () async {
        final queue = await buildPartyQueue(ref.read(libraryApiProvider),
            ref.read(currentUserIdProvider), item);
        final session = ref.read(watchPartySessionProvider.notifier);
        if (ref.read(watchPartySessionProvider).inGroup) {
          await session.setQueue(queue, start: start);
        } else {
          await session.create(item, queue: queue, start: start);
        }
      },
      creating: true,
    );
```

- [ ] **Step 8: verifica che passino**

Run: `flutter test test/features/watch_party/watch_party_actions_test.dart`
Expected: PASS.

- [ ] **Step 9: il pulsante anche per episodi e serie**

In `test/features/detail/movie_detail_test.dart`, in fondo a `main()`, aggiungi (sul modello del test "Guarda insieme: crea il gruppo dal punto di ripresa" del 5a, che è già nel file; se `ItemKind` non è importato aggiungi `import 'package:wonderflix/core/jellyfin/item_models.dart';`):

```dart
  testWidgets('Guarda insieme su un episodio: coda con gli episodi dopo',
      (tester) async {
    final pilot = testItem(
        id: 'm1',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesId: 's1',
        seriesName: 'Breaking Bad');
    api.itemsById['m1'] = pilot;
    api.seriesEpisodes['s1'] = [
      pilot,
      testItem(id: 'e2', kind: ItemKind.episode, seriesId: 's1'),
    ];
    final syncPlay = FakeSyncPlayApi();
    final events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
    syncPlay.onCall = (call) {
      if (call.startsWith('create')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          syncPlayApiProvider.overrideWithValue(syncPlay),
          watchPartyEventsProvider.overrideWithValue(events.stream),
        ]);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Guarda insieme'));
    await tester.pumpAndSettle();
    expect(syncPlay.calls, ['create Mario · Breaking Bad', 'queue m1,e2']);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(ItemDetailScreen)));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });
```

Run: `flutter test test/features/detail/movie_detail_test.dart`
Expected: FAIL (per un episodio il pulsante non c'è).

In `lib/features/detail/detail_header.dart` sostituisci il commento e la condizione del pulsante "Guarda insieme":

```dart
                    // Nel Piano 5a solo i film; serie ed episodi nel 5b.
                    if (action != null && item.kind == ItemKind.movie)
```

con:

```dart
                    // Film ed episodi; per una serie l'azione riproduce il
                    // prossimo episodio da vedere, e la coda parte da lì.
                    if (action != null &&
                        const {ItemKind.movie, ItemKind.episode, ItemKind.series}
                            .contains(item.kind))
```

- [ ] **Step 10: verifica che passino**

Run: `flutter test test/features/detail/ test/features/watch_party/`
Expected: PASS.

- [ ] **Step 11: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/party_queue.dart lib/features/watch_party/watch_party_actions.dart lib/features/detail/detail_header.dart test/features/watch_party/party_queue_test.dart test/features/watch_party/watch_party_actions_test.dart test/features/detail/movie_detail_test.dart
git commit -m "feat: watch series together with an episode queue"
```

---

### Task 5: anticipo alla ripartenza e riallineamenti segnalati

**Files:**
- Create: `lib/core/syncplay/start_lag.dart`
- Test: `test/core/syncplay/start_lag_test.dart`
- Modify: `lib/features/watch_party/group_playback_driver.dart`
- Test: `test/features/watch_party/group_playback_driver_test.dart`

Il problema (log della prova del 5a): dopo ogni ripresa programmata mpv riparte ~0,5 s in ritardo, e la correzione con la velocità impiega una decina di secondi a recuperarlo. Rimedio:
- a ogni ripresa programmata partita **da fermo**, 1,5 s dopo il via (fine del periodo iniziale) si misura lo scarto;
- la stima del ritardo si corregge di metà dello scarto misurato, restando tra 0 e 1 s (lo scarto misurato tiene già conto dell'anticipo usato);
- alla ripresa programmata successiva, da fermo, ci si allinea a `posizione + stima`.

Riprese con l'istante già passato, o con il video già in corsa, non si misurano (non c'è stato un allineamento da fermo).

Il driver riceve anche `onResync`, chiamato a ogni riallineamento (salto per scarto oltre 3 s): servirà all'avviso "Riallineamento al gruppo".

- [ ] **Step 1: scrivi i test della stima**

`test/core/syncplay/start_lag_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/start_lag.dart';

void main() {
  const ms = Duration(milliseconds: 1);

  test('parte da zero e si corregge di metà di ogni misura', () {
    final lag = StartLag();
    expect(lag.value, Duration.zero);
    lag.record(ms * 400);
    expect(lag.value, ms * 200);
    lag.record(ms * 200);
    expect(lag.value, ms * 300);
    lag.record(ms * -100);
    expect(lag.value, ms * 250);
  });

  test('resta tra 0 e 1 s', () {
    final lag = StartLag();
    lag.record(ms * -500);
    expect(lag.value, Duration.zero);
    lag.record(const Duration(seconds: 5));
    expect(lag.value, StartLag.max);
    expect(StartLag.max, const Duration(seconds: 1));
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/core/syncplay/start_lag_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi la stima**

`lib/core/syncplay/start_lag.dart`:

```dart
/// Ritardo con cui il player riparte dopo una ripresa programmata (mpv
/// impiega qualche centinaio di millisecondi). Si impara dalle misure e si
/// compensa allineandosi in anticipo (Piano 5b).
class StartLag {
  static const max = Duration(seconds: 1);

  /// Quanto di ogni misura entra nella stima.
  static const weight = 0.5;

  Duration _value = Duration.zero;

  Duration get value => _value;

  /// [drift] = scarto misurato alla fine del periodo iniziale (posizione
  /// attesa − posizione), con l'anticipo attuale già applicato.
  void record(Duration drift) {
    final next = _value + drift * weight;
    _value = next < Duration.zero
        ? Duration.zero
        : next > max
            ? max
            : next;
  }
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/core/syncplay/start_lag_test.dart`
Expected: PASS.

- [ ] **Step 5: scrivi i test del driver**

In `test/features/watch_party/group_playback_driver_test.dart`:

1. Dopo `late GroupPlaybackDriver driver;`:

```dart
  /// Riallineamenti segnalati dal driver (`onResync`).
  var resyncs = 0;
```

2. In `setUpDriver`, prima di creare il driver: `resyncs = 0;`, e nel costruttore del driver aggiungi `onResync: () => resyncs++,`.

3. Dopo `runPlayback`:

```dart
  /// Come mpv: il video parte [startLag] dopo l'istante del comando [from],
  /// dalla posizione su cui era fermo.
  void runLaggedStart(FakeAsync async, Duration duration,
      {required SyncPlayCommand from, required Duration startLag}) {
    final origin = engine.position;
    const step = Duration(milliseconds: 100);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
      final next = clock.now().toUtc().add(step);
      final running = next.difference(from.when) - startLag;
      engine.emitPosition(
          origin + (running.isNegative ? Duration.zero : running));
      async.elapse(step);
    }
  }
```

4. In fondo a `main()`:

```dart
  group('ritardo alla ripartenza', () {
    test('si impara e alla ripresa dopo ci si allinea in anticipo', () {
      fakeAsync((async) {
        setUpDriver(async);
        final first = command(SyncPlayCommandType.unpause,
            at: const Duration(milliseconds: 500));
        send(async, first);
        expect(engine.seeks, isEmpty, reason: 'già a 10:00');
        // mpv parte 400 ms dopo il via: la stima diventa 200 ms.
        runLaggedStart(async, const Duration(seconds: 3),
            from: first, startLag: const Duration(milliseconds: 400));

        send(
            async,
            command(SyncPlayCommandType.pause,
                position: const Duration(minutes: 20)));
        engine.seeks.clear();
        send(
            async,
            command(SyncPlayCommandType.unpause,
                position: const Duration(minutes: 20),
                at: const Duration(milliseconds: 500)));
        expect(engine.seeks,
            [const Duration(minutes: 20, milliseconds: 200)]);
        tearDownDriver(async);
      });
    });

    test('ripresa con l\'istante già passato: nessuna misura', () {
      fakeAsync((async) {
        setUpDriver(async);
        final first = command(SyncPlayCommandType.unpause);
        send(async, first);
        runLaggedStart(async, const Duration(seconds: 3),
            from: first, startLag: const Duration(milliseconds: 400));

        send(
            async,
            command(SyncPlayCommandType.pause,
                position: const Duration(minutes: 20)));
        engine.seeks.clear();
        send(
            async,
            command(SyncPlayCommandType.unpause,
                position: const Duration(minutes: 20),
                at: const Duration(milliseconds: 500)));
        expect(engine.seeks, isEmpty, reason: 'nessun anticipo: già a 20:00');
        tearDownDriver(async);
      });
    });
  });

  test('riallineamento: segnalato con onResync', () {
    fakeAsync((async) {
      setUpDriver(async);
      final unpause = command(SyncPlayCommandType.unpause);
      send(async, unpause);
      runPlayback(async, const Duration(seconds: 3),
          from: unpause, lag: const Duration(seconds: 4));
      expect(resyncs, 1);
      tearDownDriver(async);
    });
  });
```

- [ ] **Step 6: verifica che falliscano**

Run: `flutter test test/features/watch_party/group_playback_driver_test.dart`
Expected: FAIL (parametro `onResync` mancante, poi nessun anticipo).

- [ ] **Step 7: aggiorna il driver**

In `lib/features/watch_party/group_playback_driver.dart`:

1. Import: `import '../../core/syncplay/start_lag.dart';`
2. Nel costruttore, dopo `SyncPlayCommand? lastCommand,` aggiungi `void Function()? onResync,` e nella lista di inizializzazione `_onResync = onResync,`.
3. Dopo `final Stream<SyncPlayCommand> _commandStream;`:

```dart

  /// Chiamato a ogni riallineamento (salto per scarto oltre 3 s).
  final void Function()? _onResync;
```

4. Dopo `final _corrector = DriftCorrector();`:

```dart

  /// Ritardo con cui mpv riparte dopo una ripresa programmata.
  final _startLag = StartLag();

  /// La ripresa in corso è partita da fermo all'istante previsto: a fine
  /// periodo iniziale se ne misura il ritardo.
  bool _measureLag = false;
```

5. In `_apply`, dopo `_playingSince = null;`: `_measureLag = false;`
6. Nel ramo `unpause` con `wait > Duration.zero`, sostituisci:

```dart
          if (!_engine.playing) await _align(command.position);
          if (_stale(command)) return;
```

con:

```dart
          if (!_engine.playing) {
            // Da fermo ci si allinea in anticipo del ritardo con cui mpv
            // riparte: al via si è già in pari.
            await _align(command.position + _startLag.value);
            _measureLag = true;
          }
          if (_stale(command)) return;
```

7. In `_reanchor`, dopo `_corrector.reset();`: `_measureLag = false;`
8. In `_onTick`, sostituisci il blocco da `final expected = _expectedPosition(command);` fino alla chiamata `_corrector.update(...)` con:

```dart
    final expected = _expectedPosition(command);
    final now = _clock.now();
    final sinceUnpause = now.difference(since);
    if (_measureLag && sinceUnpause >= DriftCorrector.startGrace) {
      _measureLag = false;
      _startLag.record(expected - _engine.position);
      _log.info('ritardo alla ripartenza: '
          '${_startLag.value.inMilliseconds} ms');
    }
    final lastResync = _lastResync;
    final action = _corrector.update(
      drift: expected - _engine.position,
      rate: _rate,
      sinceUnpause: sinceUnpause,
      sinceResync: lastResync == null ? null : now.difference(lastResync),
    );
```

9. Nel caso `Resync()` di `_onTick`, dopo `_lastResync = now;`: `_onResync?.call();`

- [ ] **Step 8: verifica che passino**

Run: `flutter test test/features/watch_party/ test/core/syncplay/`
Expected: PASS (anche tutti i test del driver del 5a).

- [ ] **Step 9: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/syncplay/start_lag.dart test/core/syncplay/start_lag_test.dart lib/features/watch_party/group_playback_driver.dart test/features/watch_party/group_playback_driver_test.dart
git commit -m "feat: compensate the player restart lag in the watch party"
```

---
### Task 6: `PartyNotices`, gli avvisi del gruppo

**Files:**
- Create: `lib/features/watch_party/party_notices.dart`
- Modify: `test/support/watch_party_fakes.dart`
- Test: `test/features/watch_party/party_notices_test.dart`

Regole (spec B §5.7, Piano 5b):
- un avviso alla volta, per 3 s; gli altri in coda;
- dagli aggiornamenti del gruppo (`WatchPartySession.updates`):
  - `StateUpdate` con motivo `Pause` → "Pausa";
  - motivo `Unpause` → "Ripresa", oppure "Si riprende senza aspettare" se il gruppo passa da `Waiting` a `Playing`;
  - motivo `Seek` → "Salto a <posizione>", con la posizione dell'ultimo comando `Seek` (che il server manda prima dello `StateUpdate`); senza un comando noto, nessun avviso;
  - `UserJoined` / `UserLeft` → "<nome> è nel watch party" / "<nome> ha lasciato il watch party";
  - `PlayQueue` con un elemento in riproduzione diverso dal precedente (non la prima coda dopo l'ingresso): motivo `NextItem` → "Episodio successivo: S1:E5 · Titolo", altrimenti → "Si guarda: <titolo>". Il titolo si chiede alla libreria; se non arriva, nessun avviso;
- le azioni proprie (`mine`) si mostrano subito in seconda persona, e lo `StateUpdate` corrispondente che arriva entro 3 s non ne produce un secondo. Una ripresa propria copre anche "Si riprende senza aspettare";
- altri avvisi diretti (`show`), es. "Riallineamento al gruppo" dal driver;
- uscendo dal gruppo gli avvisi spariscono.

`PartyNotices` resta attivo per tutta la sessione (non `autoDispose`): nel Task 8 lo tiene vivo `watchPartyRoutingProvider`, così vede anche la prima coda del gruppo.

- [ ] **Step 1: scrivi i test**

`test/features/watch_party/party_notices_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
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
    events = StreamController<ServerEvent>.broadcast();
    library = FakeLibraryApi()
      ..itemsById['e5'] = testItem(
          id: 'e5',
          name: 'Cat\'s in the Bag',
          kind: ItemKind.episode,
          seriesName: 'Breaking Bad',
          index: 5,
          seasonIndex: 1)
      ..itemsById['m2'] = testItem(id: 'm2', name: 'Arrival');
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  /// Dentro la zona finta: container, avvisi attivi, ingresso nel gruppo.
  void mount(FakeAsync async) {
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      libraryApiProvider.overrideWithValue(library),
    ]);
    container.listen(partyNoticesProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    async.flushMicrotasks();
  }

  void finish(FakeAsync async) {
    container.dispose();
    async.flushMicrotasks();
  }

  PartyNotice? current() => container.read(partyNoticesProvider);
  PartyNotices notices() => container.read(partyNoticesProvider.notifier);

  void emit(FakeAsync async, GroupUpdate update) {
    events.add(SyncPlayGroupUpdated(update));
    async.flushMicrotasks();
  }

  void seekCommand(FakeAsync async, Duration position) {
    events.add(SyncPlayCommandReceived(SyncPlayCommand(
      groupId: 'g1',
      playlistItemId: 'p1',
      when: DateTime.utc(2100),
      position: position,
      type: SyncPlayCommandType.seek,
      emittedAt: DateTime.utc(2100),
    )));
    async.flushMicrotasks();
  }

  test('pausa e ripresa degli altri: uno alla volta, 3 s ciascuno', () {
    fakeAsync((async) {
      mount(async);
      expect(current(), isNull);
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      emit(async, const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
      expect(current()?.kind, PartyNoticeKind.paused);
      expect(current()?.mine, isFalse);
      async.elapse(PartyNotices.showFor);
      expect(current()?.kind, PartyNoticeKind.resumed);
      async.elapse(PartyNotices.showFor);
      expect(current(), isNull);
      finish(async);
    });
  });

  test('salto: con la posizione del comando; senza comando nessun avviso', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
      expect(current(), isNull);

      seekCommand(async, const Duration(minutes: 32, seconds: 10));
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
      expect(current()?.kind, PartyNoticeKind.seeked);
      expect(current()?.position, const Duration(minutes: 32, seconds: 10));
      finish(async);
    });
  });

  test('ripresa che fa partire il gruppo in attesa: senza aspettare', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
      expect(current(), isNull, reason: 'il buffering ha la sua schermata');
      emit(async, const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
      expect(current()?.kind, PartyNoticeKind.forcedResume);
      async.elapse(PartyNotices.showFor);

      // Ripresa durante l'attesa che non fa partire nessuno: ripresa normale.
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Unpause'));
      expect(current()?.kind, PartyNoticeKind.resumed);
      finish(async);
    });
  });

  test('entrate e uscite', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const UserJoined('g1', 'Luigi'));
      expect(current()?.kind, PartyNoticeKind.joined);
      expect(current()?.name, 'Luigi');
      async.elapse(PartyNotices.showFor);
      emit(async, const UserLeft('g1', 'Luigi'));
      expect(current()?.kind, PartyNoticeKind.left);
      finish(async);
    });
  });

  test('le mie azioni: subito, e l\'eco del server entro 3 s non si ripete',
      () {
    fakeAsync((async) {
      mount(async);
      notices().mine(PartyNoticeKind.paused);
      expect(current()?.kind, PartyNoticeKind.paused);
      expect(current()?.mine, isTrue);
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      async.elapse(PartyNotices.showFor);
      expect(current(), isNull);

      // Un'altra pausa, di qualcun altro: si mostra.
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      expect(current()?.mine, isFalse);
      finish(async);
    });
  });

  test('eco arrivata oltre 3 s: si mostra', () {
    fakeAsync((async) {
      mount(async);
      notices().mine(PartyNoticeKind.paused);
      async.elapse(const Duration(seconds: 4));
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      expect(current()?.kind, PartyNoticeKind.paused);
      expect(current()?.mine, isFalse);
      finish(async);
    });
  });

  test('la mia ripresa copre la ripresa senza aspettare', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
      notices().mine(PartyNoticeKind.resumed);
      emit(async, const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
      async.elapse(PartyNotices.showFor);
      expect(current(), isNull);
      finish(async);
    });
  });

  test('cambio di episodio e nuovo titolo', () {
    fakeAsync((async) {
      mount(async);
      // La prima coda dopo l'ingresso non è un cambio.
      emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
      expect(current(), isNull);

      emit(
          async,
          PlayQueueUpdate(
              'g1',
              testSeriesQueue(
                  playingIndex: 1,
                  reason: 'NextItem',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
      expect(current()?.kind, PartyNoticeKind.nextEpisode);
      expect(current()?.title, 'S1:E5 · Cat\'s in the Bag');
      async.elapse(PartyNotices.showFor);

      emit(
          async,
          PlayQueueUpdate(
              'g1',
              testQueue(
                  itemId: 'm2',
                  playlistItemId: 'p9',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 10))));
      expect(current()?.kind, PartyNoticeKind.nowWatching);
      expect(current()?.title, 'Arrival');
      finish(async);
    });
  });

  test('titolo non disponibile: nessun avviso', () {
    fakeAsync((async) {
      mount(async);
      emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
      emit(
          async,
          PlayQueueUpdate(
              'g1',
              testSeriesQueue(
                  playingIndex: 2,
                  reason: 'NextItem',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
      expect(current(), isNull, reason: 'e6 non è nella libreria finta');
      finish(async);
    });
  });

  test('avvisi diretti e uscita dal gruppo', () {
    fakeAsync((async) {
      mount(async);
      notices().show(const PartyNotice(PartyNoticeKind.resync));
      notices().show(const PartyNotice(PartyNoticeKind.paused));
      expect(current()?.kind, PartyNoticeKind.resync);
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      expect(current(), isNull);
      async.elapse(const Duration(seconds: 10));
      expect(current(), isNull, reason: 'la coda è stata svuotata');
      finish(async);
    });
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/watch_party/party_notices_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi gli avvisi**

`lib/features/watch_party/party_notices.dart`:

```dart
import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/syncplay/syncplay_models.dart';
import '../auth/session_controller.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

enum PartyNoticeKind {
  paused,
  resumed,
  forcedResume,
  seeked,
  joined,
  left,
  nextEpisode,
  nowWatching,
  resync,
}

/// Un avviso del watch party (spec B §5.7). Il testo lo compone
/// `partyNoticeText`.
class PartyNotice {
  const PartyNotice(this.kind,
      {this.mine = false, this.position, this.name, this.title});

  final PartyNoticeKind kind;

  /// Azione dell'utente stesso: testo in seconda persona ("Hai…").
  final bool mine;

  /// Per i salti.
  final Duration? position;

  /// Per entrate e uscite.
  final String? name;

  /// Per episodio successivo e nuovo titolo.
  final String? title;
}

/// Chi annuncia un'azione dell'utente (vedi [PartyNotices.mine]).
typedef PartyActionCallback = void Function(PartyNoticeKind kind,
    {Duration? position});

/// Avvisi del watch party, uno alla volta per [showFor]. Lo stato è
/// l'avviso da mostrare adesso (`null` = nessuno).
class PartyNotices extends Notifier<PartyNotice?> {
  static const showFor = Duration(seconds: 3);

  /// Entro questo tempo lo `StateUpdate` di una nostra azione è la sua eco.
  static const echoWindow = Duration(seconds: 3);

  final _queue = Queue<PartyNotice>();
  final _echoes = <({PartyNoticeKind kind, DateTime at})>[];
  Timer? _timer;
  GroupState? _groupState;
  String? _playing;
  Duration? _lastSeek;

  @override
  PartyNotice? build() {
    // Nuovo utente = nuova sessione del gruppo: ci si iscrive di nuovo.
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    final party = ref.read(watchPartySessionProvider);
    final session = ref.read(watchPartySessionProvider.notifier);
    _queue.clear();
    _echoes.clear();
    _timer = null;
    _groupState = party.inGroup ? party.groupState : null;
    _playing = party.queue?.playing?.playlistItemId;
    _lastSeek = null;
    final subscriptions = [
      session.updates.listen(_onUpdate),
      session.commands.listen((command) {
        if (command.type == SyncPlayCommandType.seek) {
          _lastSeek = command.position;
        }
      }),
    ];
    ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
        (_, inGroup) {
      if (!inGroup) _clear();
    });
    ref.onDispose(() {
      _timer?.cancel();
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    });
    return null;
  }

  /// Mostra [notice] dopo quelli già in coda.
  void show(PartyNotice notice) {
    _queue.add(notice);
    if (_timer == null) _next();
  }

  /// Azione dell'utente: l'avviso compare subito, e l'eco del server (entro
  /// [echoWindow]) non ne produce un secondo.
  void mine(PartyNoticeKind kind, {Duration? position}) {
    _echoes.add((kind: kind, at: clock.now()));
    show(PartyNotice(kind, mine: true, position: position));
  }

  void _next() {
    _timer?.cancel();
    if (_queue.isEmpty) {
      _timer = null;
      if (ref.mounted) state = null;
      return;
    }
    if (ref.mounted) state = _queue.removeFirst();
    _timer = Timer(showFor, _next);
  }

  void _clear() {
    _queue.clear();
    _echoes.clear();
    _timer?.cancel();
    _timer = null;
    _groupState = null;
    _playing = null;
    _lastSeek = null;
    if (ref.mounted) state = null;
  }

  /// `true` (e l'eco si consuma) se [kind] è l'eco di una nostra azione.
  bool _isEcho(PartyNoticeKind kind) {
    final now = clock.now();
    _echoes.removeWhere((echo) => now.difference(echo.at) > echoWindow);
    final index = _echoes.indexWhere((echo) =>
        echo.kind == kind ||
        (echo.kind == PartyNoticeKind.resumed &&
            kind == PartyNoticeKind.forcedResume));
    if (index < 0) return false;
    _echoes.removeAt(index);
    return true;
  }

  void _onUpdate(GroupUpdate update) {
    switch (update) {
      case GroupStateUpdate(state: final groupState, :final reason):
        final previous = _groupState;
        _groupState = groupState;
        final kind = switch (reason) {
          'Pause' => PartyNoticeKind.paused,
          'Unpause' => previous == GroupState.waiting &&
                  groupState == GroupState.playing
              ? PartyNoticeKind.forcedResume
              : PartyNoticeKind.resumed,
          'Seek' => PartyNoticeKind.seeked,
          _ => null,
        };
        if (kind == null || _isEcho(kind)) return;
        if (kind == PartyNoticeKind.seeked) {
          final position = _lastSeek;
          if (position == null) return;
          show(PartyNotice(kind, position: position));
        } else {
          show(PartyNotice(kind));
        }
      case UserJoined(:final userName):
        show(PartyNotice(PartyNoticeKind.joined, name: userName));
      case UserLeft(:final userName):
        show(PartyNotice(PartyNoticeKind.left, name: userName));
      case PlayQueueUpdate(:final queue):
        _onQueue(queue);
      default:
        break;
    }
  }

  void _onQueue(PlayQueue queue) {
    final entry = queue.playing;
    final previous = _playing;
    _playing = entry?.playlistItemId;
    if (entry == null || previous == null || previous == entry.playlistItemId) {
      return;
    }
    final kind = queue.reason == 'NextItem'
        ? PartyNoticeKind.nextEpisode
        : PartyNoticeKind.nowWatching;
    unawaited(_announce(kind, entry.itemId));
  }

  Future<void> _announce(PartyNoticeKind kind, String itemId) async {
    try {
      final item = await ref
          .read(libraryApiProvider)
          .item(ref.read(currentUserIdProvider), itemId);
      if (!ref.mounted) return;
      show(PartyNotice(kind,
          title: kind == PartyNoticeKind.nextEpisode
              ? cardSubtitle(item) ?? item.name
              : cardTitle(item)));
    } on Object catch (error) {
      _log.info('titolo per l\'avviso non disponibile: $error');
    }
  }
}

final partyNoticesProvider =
    NotifierProvider<PartyNotices, PartyNotice?>(PartyNotices.new);
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/features/watch_party/party_notices_test.dart`
Expected: PASS. Se l'analyzer segnala che il `default` dello `switch` in `_onUpdate` non è raggiungibile, sostituiscilo con i casi mancanti (`GroupJoined() || GroupLeft() || NotInGroup() || GroupDoesNotExist() || LibraryAccessDenied() => break`), come nel 5a per la sessione.

- [ ] **Step 5: aggiungi il fake degli avvisi**

In `test/support/watch_party_fakes.dart` aggiungi l'import `import 'package:wonderflix/features/watch_party/party_notices.dart';` e in fondo:

```dart
/// Avvisi fissi: registra quelli mostrati e le azioni proprie, senza timer.
class FakePartyNotices extends PartyNotices {
  FakePartyNotices([this.initial]);

  final PartyNotice? initial;
  final shown = <PartyNotice>[];
  final mineCalls = <(PartyNoticeKind, Duration?)>[];

  @override
  PartyNotice? build() => initial;

  @override
  void show(PartyNotice notice) => shown.add(notice);

  @override
  void mine(PartyNoticeKind kind, {Duration? position}) =>
      mineCalls.add((kind, position));
}
```

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/party_notices.dart test/features/watch_party/party_notices_test.dart test/support/watch_party_fakes.dart
git commit -m "feat: add watch party notices"
```

---

### Task 7: la pillola degli avvisi e le azioni proprie

**Files:**
- Create: `lib/features/watch_party/party_notice_pill.dart`
- Modify: `lib/features/watch_party/group_authority.dart`
- Test: `test/features/watch_party/party_notice_pill_test.dart`, `test/features/watch_party/group_authority_test.dart`

- [ ] **Step 1: scrivi i test della pillola**

`test/features/watch_party/party_notice_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/watch_party/party_notice_pill.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('testi di tutti gli avvisi', () {
    String text(PartyNotice notice) => partyNoticeText(l, notice);
    const time = Duration(minutes: 32, seconds: 10);
    expect(text(const PartyNotice(PartyNoticeKind.paused)), 'Pausa');
    expect(text(const PartyNotice(PartyNoticeKind.paused, mine: true)),
        'Hai messo in pausa');
    expect(text(const PartyNotice(PartyNoticeKind.resumed)), 'Ripresa');
    expect(text(const PartyNotice(PartyNoticeKind.resumed, mine: true)),
        'Hai ripreso');
    expect(text(const PartyNotice(PartyNoticeKind.forcedResume)),
        'Si riprende senza aspettare');
    expect(text(const PartyNotice(PartyNoticeKind.seeked, position: time)),
        'Salto a 32:10');
    expect(
        text(const PartyNotice(PartyNoticeKind.seeked,
            mine: true, position: time)),
        'Hai saltato a 32:10');
    expect(text(const PartyNotice(PartyNoticeKind.joined, name: 'Luigi')),
        'Luigi è nel watch party');
    expect(text(const PartyNotice(PartyNoticeKind.left, name: 'Luigi')),
        'Luigi ha lasciato il watch party');
    expect(
        text(const PartyNotice(PartyNoticeKind.nextEpisode,
            title: 'S1:E5 · Titolo')),
        'Episodio successivo: S1:E5 · Titolo');
    expect(
        text(const PartyNotice(PartyNoticeKind.nowWatching, title: 'Dune')),
        'Si guarda: Dune');
    expect(text(const PartyNotice(PartyNoticeKind.resync)),
        'Riallineamento al gruppo');
  });

  testWidgets('mostra l\'avviso attuale, niente senza avvisi', (tester) async {
    await pumpApp(tester, const Center(child: PartyNoticePill()), overrides: [
      partyNoticesProvider.overrideWith(() => FakePartyNotices(
          const PartyNotice(PartyNoticeKind.joined, name: 'Luigi'))),
    ]);
    expect(find.text('Luigi è nel watch party'), findsOneWidget);
  });

  testWidgets('nessun avviso: nessuna pillola', (tester) async {
    await pumpApp(tester, const Center(child: PartyNoticePill()), overrides: [
      partyNoticesProvider.overrideWith(FakePartyNotices.new),
    ]);
    expect(find.byKey(const Key('party-notice')), findsNothing);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/watch_party/party_notice_pill_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi la pillola**

`lib/features/watch_party/party_notice_pill.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'party_notices.dart';

String partyNoticeText(AppLocalizations l, PartyNotice notice) {
  final time = formatClock(notice.position ?? Duration.zero);
  return switch (notice.kind) {
    PartyNoticeKind.paused =>
      notice.mine ? l.watchPartyNoticePausedByYou : l.watchPartyNoticePaused,
    PartyNoticeKind.resumed =>
      notice.mine ? l.watchPartyNoticeResumedByYou : l.watchPartyNoticeResumed,
    PartyNoticeKind.forcedResume => l.watchPartyNoticeForcedResume,
    PartyNoticeKind.seeked => notice.mine
        ? l.watchPartyNoticeSeekByYou(time)
        : l.watchPartyNoticeSeek(time),
    PartyNoticeKind.joined => l.watchPartyNoticeJoined(notice.name ?? ''),
    PartyNoticeKind.left => l.watchPartyNoticeLeft(notice.name ?? ''),
    PartyNoticeKind.nextEpisode =>
      l.watchPartyNoticeNextEpisode(notice.title ?? ''),
    PartyNoticeKind.nowWatching =>
      l.watchPartyNoticeNowWatching(notice.title ?? ''),
    PartyNoticeKind.resync => l.watchPartyNoticeResync,
  };
}

/// Avviso del watch party in alto al centro del player, visibile anche a
/// controlli nascosti (spec B §7.1).
class PartyNoticePill extends ConsumerWidget {
  const PartyNoticePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(partyNoticesProvider);
    if (notice == null) return const SizedBox.shrink();
    return Container(
      key: const Key('party-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE61B1B1B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WfColors.border),
      ),
      child: Text(partyNoticeText(AppLocalizations.of(context), notice),
          style: const TextStyle(color: WfColors.cream)),
    );
  }
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/features/watch_party/party_notice_pill_test.dart`
Expected: PASS.

- [ ] **Step 5: scrivi il test delle azioni proprie**

In `test/features/watch_party/group_authority_test.dart` aggiungi gli import (se mancano) `import 'dart:async';`, `import 'package:fake_async/fake_async.dart';`, `import 'package:wonderflix/features/watch_party/party_notices.dart';` e in fondo a `main()`:

```dart
  test('le azioni si annunciano subito come mie', () {
    fakeAsync((async) {
      final actions = <(PartyNoticeKind, Duration?)>[];
      final announcing = GroupAuthority(
        api: api,
        engine: engine,
        onAction: (kind, {position}) => actions.add((kind, position)),
      );
      unawaited(announcing.pause());
      async.flushMicrotasks();
      unawaited(announcing.seekTo(const Duration(minutes: 5)));
      unawaited(announcing.seekTo(const Duration(minutes: 6)));
      async.flushMicrotasks();
      expect(actions, [(PartyNoticeKind.paused, null)]);

      async.elapse(GroupAuthority.seekDebounce);
      expect(actions.last,
          (PartyNoticeKind.seeked, const Duration(minutes: 6)));

      unawaited(announcing.play());
      async.flushMicrotasks();
      expect(actions.last, (PartyNoticeKind.resumed, null));
      expect(actions, hasLength(3));
      announcing.dispose();
    });
  });
```

- [ ] **Step 6: verifica che fallisca**

Run: `flutter test test/features/watch_party/group_authority_test.dart`
Expected: FAIL (parametro `onAction` mancante).

- [ ] **Step 7: aggiorna `GroupAuthority`**

In `lib/features/watch_party/group_authority.dart`:

1. Import: `import 'party_notices.dart';`
2. Costruttore e campi:

```dart
  GroupAuthority({
    required SyncPlayApi api,
    required VideoEngine engine,
    PartyActionCallback? onAction,
  })  : _api = api,
        _engine = engine,
        _onAction = onAction;
```

e dopo `final VideoEngine _engine;`:

```dart

  /// Annuncia le azioni dell'utente (avviso "Hai…" subito, spec B §5.7).
  final PartyActionCallback? _onAction;
```

3. In `play()`, dopo `await _flushSeek();` e prima di `_send`: `_onAction?.call(PartyNoticeKind.resumed);`
4. In `pause()`, dopo `await _engine.pause();`: `_onAction?.call(PartyNoticeKind.paused);`
5. In `_flushSeek()`, dopo `if (position == null) return;`: `_onAction?.call(PartyNoticeKind.seeked, position: position);`

- [ ] **Step 8: verifica che passino**

Run: `flutter test test/features/watch_party/`
Expected: PASS.

- [ ] **Step 9: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/party_notice_pill.dart lib/features/watch_party/group_authority.dart test/features/watch_party/party_notice_pill_test.dart test/features/watch_party/group_authority_test.dart
git commit -m "feat: show watch party notices and announce own actions"
```

---
### Task 8: il player nel gruppo — episodi, passaggio, avvisi

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Modify: `lib/features/watch_party/watch_party_routing.dart`
- Test: `test/features/watch_party/party_player_test.dart`, `test/features/watch_party/watch_party_routing_test.dart`

Cosa cambia nel player con `args.party` valorizzato:
- **Episodio successivo** (pulsante, tasto N, tasto multimediale, "Riproduci ora" nella scheda): `session.nextItem()`. Il pulsante c'è solo se la coda ha un elemento dopo (`hasNext`).
- **Scheda "Prossimo episodio"**: sui titoli di coda, solo se la coda ha un elemento dopo, **senza conto alla rovescia**.
- **Fine del video**: `session.nextItem()` (se non c'è un elemento dopo non succede nulla: si resta sull'ultimo fotogramma).
- **Passaggio**: quando la coda del gruppo cambia elemento in riproduzione, il player stesso passa a quello nuovo con `pushReplacement`:
  - mantiene lo schermo intero (`fs=1`) e il pannello media, come `_playNext`;
  - segna come visto l'episodio lasciato se era finito o sui titoli di coda;
  - usa `estimatedPosition()` come partenza.
- **Routing**: `watchPartyRoutingProvider` non sostituisce più un player del gruppo già aperto (lo fa il player), e tiene vivo `partyNoticesProvider`, così gli avvisi vedono anche la prima coda del gruppo.
- **Avvisi**: pillola in alto al centro, sopra i controlli, senza intercettare i clic. Le azioni proprie passano da `GroupAuthority(onAction: notices.mine)`, i riallineamenti dal driver (`onResync`).

- [ ] **Step 1: scrivi il test del routing**

In `test/features/watch_party/watch_party_routing_test.dart`, in fondo a `main()`:

```dart
  test('un player del gruppo già aperto: lo cambia lui, non il routing',
      () async {
    navigator.location = Uri.parse('/play/e4?party=p1');
    await joinAndQueue(testSeriesQueue(playingIndex: 1));
    expect(navigator.opened, isEmpty);
    expect(navigator.replaced, isEmpty);
  });
```

- [ ] **Step 2: scrivi i test del player**

In `test/features/watch_party/party_player_test.dart`:

1. Sostituisci `late FakeVideoEngine engine;` con:

```dart
  /// Motore del primo player; ogni player dopo (episodio nuovo) ne ha uno.
  late FakeVideoEngine engine;
  late List<FakeVideoEngine> engines;
  late FakePlayerWindow window;
```

2. In `pumpPartyPlayer`:
   - dopo `engine = FakeVideoEngine()..engineTracks = testEngineTracks;` aggiungi `engines = [];` e `window = FakePlayerWindow();`;
   - nella libreria finta aggiungi l'episodio dopo, completo (serve al nuovo player):

```dart
      ..itemsById['e5'] = testItem(
        id: 'e5',
        name: 'Cat\'s in the Bag',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 5,
        seasonIndex: 1,
      )
```

   - sostituisci `videoEngineFactoryProvider.overrideWithValue(() => engine),` con:

```dart
        videoEngineFactoryProvider.overrideWithValue(() {
          final created = engines.isEmpty
              ? engine
              : (FakeVideoEngine()..engineTracks = testEngineTracks);
          engines.add(created);
          return created;
        }),
```

   - sostituisci `playerWindowProvider.overrideWithValue(FakePlayerWindow()),` con `playerWindowProvider.overrideWithValue(window),`.

3. Aggiungi in fondo a `main()`:

```dart
  /// Il gruppo guarda la serie: e4 (p1), poi e5 (p2) ed e6 (p3).
  Future<void> queueSeries(WidgetTester tester) async {
    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('prossimo episodio: il pulsante lo chiede al gruppo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.playerNextEpisode));
    await tester.pump();
    expect(api.calls, contains('next p1'));
    await finish(tester);
  });

  testWidgets('fine del video: episodio successivo per tutti', (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    engine.emitCompleted();
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('next p1'));
    expect(find.byType(PlayerScreen), findsOneWidget,
        reason: 'nel gruppo il player non esce da solo');
    await finish(tester);
  });

  testWidgets('titoli di coda: scheda senza conto alla rovescia',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    // Senza segmenti la scheda compare negli ultimi 30 s (durata: 2 h).
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.playerNextEpisodeTitle.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Inizia tra'), findsNothing);
    await tester.tap(find.text(l.playerPlayNow));
    await tester.pump();
    expect(api.calls, contains('next p1'));
    await finish(tester);
  });

  testWidgets(
      'il gruppo passa all\'episodio dopo: nuovo player a schermo intero, '
      'episodio lasciato sui titoli segnato come visto', (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.playerFullscreen));
    await tester.pump();
    expect(window.fullScreenCalls, [true]);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();

    emit(PlayQueueUpdate(
        'g1',
        testSeriesQueue(
            playingIndex: 1,
            reason: 'NextItem',
            lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(),
        '/play/e5?fs=1&party=p2');
    expect(window.fullScreenCalls, [true],
        reason: 'passando all\'episodio dopo lo schermo intero resta');
    expect(library.playedCalls, contains(('e4', true)));
    expect(engines, hasLength(2));
    await finish(tester);
  });

  testWidgets('avvisi: pillola nel player, e le mie azioni in seconda persona',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyNoticePaused), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(l.watchPartyNoticePaused), findsNothing);

    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(find.text(l.watchPartyNoticeResumedByYou), findsOneWidget);
    await finish(tester);
  });
```

Se `find.byTooltip(l.playerFullscreen)` non trova il pulsante (controlli nascosti), aggiungi prima un `await tester.pump()`: i controlli restano visibili perché il video è in pausa.

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/features/watch_party/party_player_test.dart test/features/watch_party/watch_party_routing_test.dart`
Expected: FAIL (nessun pulsante nel gruppo, nessun passaggio, nessuna pillola; il routing sostituisce il player).

- [ ] **Step 4: aggiorna il routing**

In `lib/features/watch_party/watch_party_routing.dart`:

1. Import: `import 'party_notices.dart';`
2. All'inizio del corpo di `watchPartyRoutingProvider`:

```dart
  // Gli avvisi devono vedere anche la prima coda del gruppo.
  ref.listen(partyNoticesProvider, (_, _) {});
```

3. Sostituisci:

```dart
    if (location.queryParameters['party'] == playlistItemId) return;
```

con:

```dart
    // Un player del gruppo è già aperto: il cambio di elemento lo fa lui,
    // mantenendo lo schermo intero e segnando l'episodio visto.
    if (location.queryParameters.containsKey('party')) return;
```

e aggiorna il commento del provider: "Apre il player quando il gruppo sceglie cosa guardare (ingresso). Con un player del gruppo già aperto il cambio lo fa il player."

- [ ] **Step 5: aggiorna il player**

In `lib/features/player/player_screen.dart` (CRLF: Edit mirati):

1. Import (in ordine con gli altri):

```dart
import '../watch_party/party_notice_pill.dart';
import '../watch_party/party_notices.dart';
```

2. In `_attachParty`, prima di creare il driver:

```dart
    final notices = ref.read(partyNoticesProvider.notifier);
```

nel costruttore di `GroupPlaybackDriver` aggiungi:

```dart
      onResync: () =>
          notices.show(const PartyNotice(PartyNoticeKind.resync)),
```

e crea l'autorità con gli annunci:

```dart
    final authority = GroupAuthority(
        api: session.api, engine: controller.engine, onAction: notices.mine);
```

3. All'inizio di `_playNext`, prima di `final view = …`:

```dart
    // Nel gruppo l'episodio lo cambia il gruppo: il player passa a quello
    // nuovo quando arriva la coda (vedi [_handOverTo]).
    if (_inParty) {
      if (!_leaving) {
        unawaited(ref.read(watchPartySessionProvider.notifier).nextItem());
      }
      return;
    }
```

e la condizione di uscita torna quella di prima del gruppo:

```dart
    if (next == null || _leaving) return;
```

4. In `_onFinished` sostituisci:

```dart
    // Nel watch party la fine la decide il gruppo: si resta sul video.
    if (_inParty) return;
```

con:

```dart
    // Nel gruppo si passa all'elemento dopo della coda (il server scarta le
    // richieste doppie degli altri). A fine coda si resta sul video.
    if (_inParty) {
      unawaited(ref.read(watchPartySessionProvider.notifier).nextItem());
      return;
    }
```

5. Dopo `_detachParty`:

```dart
  /// Il gruppo è passato a un altro elemento della coda (episodio
  /// successivo, nuovo titolo): questo player lascia il posto a quello
  /// nuovo, con lo schermo intero com'è. L'episodio lasciato finito o sui
  /// titoli di coda si segna come visto.
  void _handOverTo(PlayQueueEntry entry) {
    if (_leaving) return;
    _leaving = true;
    _handingOver = true;
    final view = ref.read(playerControllerProvider(widget.args));
    final engine = _controller.engine;
    final from = nextEpisodeCardFrom(view.segments, engine.duration);
    final watched = view.finished || (from != null && engine.position >= from);
    unawaited(_controller.close(watched: watched));
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    context.pushReplacement(playerRoute(
      entry.itemId,
      start: ref.read(watchPartySessionProvider.notifier).estimatedPosition(),
      fullscreen: _fullscreen,
      party: entry.playlistItemId,
    ));
  }
```

6. In `build`, dentro il blocco `if (_inParty) { … }` che contiene già il `ref.listen` su `inGroup`, aggiungi:

```dart
      ref.listen(
          watchPartySessionProvider.select((s) =>
              s.inGroup ? s.queue?.playing?.playlistItemId : null),
          (_, playlistItemId) {
        if (playlistItemId == null || playlistItemId == widget.args.party) {
          return;
        }
        final entry = ref.read(watchPartySessionProvider).queue?.playing;
        if (entry != null) _handOverTo(entry);
      });
```

7. Nel `PlayerOverlay` sostituisci `onNextEpisode:` con:

```dart
                          onNextEpisode: _inParty
                              ? (party != null && party.hasNext
                                  ? _playNext
                                  : null)
                              : (next == null ? null : _playNext),
```

8. La condizione della scheda "Prossimo episodio" diventa:

```dart
                  if (next != null &&
                      !_nextCardDismissed &&
                      (!_inParty || (party?.hasNext ?? false)))
```

e nel `NextEpisodeCard`:

```dart
                                  // Nel gruppo nessun conto alla rovescia:
                                  // si va avanti con il pulsante o a fine
                                  // video (Piano 5b).
                                  countdown: !_inParty && settings.autoplayNext,
```

9. Nello `Stack`, prima del blocco `if (_tracksOpen && view.plan != null)`:

```dart
                if (party != null && party.inGroup)
                  const Positioned(
                    top: 96,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(child: PartyNoticePill()),
                    ),
                  ),
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/features/watch_party/ test/features/player/`
Expected: PASS (anche i test del 5a e del player da solo).

Il test esistente "nel watch party non c'è l'episodio successivo" deve continuare a passare: senza coda del gruppo non c'è un elemento dopo.

- [ ] **Step 7: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/player/player_screen.dart lib/features/watch_party/watch_party_routing.dart test/features/watch_party/party_player_test.dart test/features/watch_party/watch_party_routing_test.dart
git commit -m "feat: next episode and notices in the watch party player"
```

---

### Task 9: verifica finale

**Files:** nessuno (salvo correzioni).

- [ ] **Step 1: analisi e test**

```bash
flutter analyze
flutter test
```

Expected: `No issues found!` e tutti i test verdi (erano 587 prima del piano).

- [ ] **Step 2: build di release con la configurazione**

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

Expected: `Built build\windows\x64\runner\Release\wonderflix.exe`. **Senza `--dart-define-from-file` l'app mostra "Configurazione mancante".** Se fallisce con `LNK1168`: `taskkill //IM wonderflix.exe //F` e riprova.

- [ ] **Step 3: controllo dei file generati**

Run: `git status --short`
Expected: nessun file modificato (altrimenti `git checkout -- windows/flutter/` se sono solo fini riga).

- [ ] **Step 4: istruzioni per la prova manuale (da riportare all'utente)**

Le due istanze le avvia l'utente (l'app avviata da Claude viene virtualizzata):
1. istanza A: doppio clic su `build\windows\x64\runner\Release\wonderflix.exe`;
2. istanza B, da PowerShell nella stessa cartella: `$env:WONDERFLIX_PROFILE = 'b'; .\wonderflix.exe`.

Da controllare:
- "Guarda insieme" dalla scheda di una serie (parte dal prossimo episodio) e da un episodio;
- pulsante "Prossimo episodio" e tasto N da A e da B: cambiano episodio a entrambi, a schermo intero resta a schermo intero;
- titoli di coda: la scheda compare senza conto alla rovescia; alla fine vera dell'episodio si passa al successivo per tutti;
- l'episodio lasciato sui titoli risulta visto;
- avvisi: pausa, ripresa, salto (anche da tastiera), entrata e uscita di B, "Episodio successivo: …"; le proprie azioni come "Hai…";
- "Guarda insieme" su un altro titolo stando nel gruppo: "Si guarda: …" su entrambi (per arrivarci serve la scheda aperta durante il gruppo: se non è raggiungibile dall'interfaccia, segnalarlo);
- dopo alcuni salti: nei log `[watchparty]` la riga "ritardo alla ripartenza: … ms" e scarti dopo la ripresa più piccoli dei ~500 ms della prova del 5a.
