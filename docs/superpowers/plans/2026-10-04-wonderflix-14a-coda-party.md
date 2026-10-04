# WonderFlix — Piano 14a: la coda del watch party

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** prima metà della Spec H. Ci sono:
- il plugin 1.3.0 con le azioni della coda;
- nell'app i comandi della coda: salto, rimozione, spostamento, ordine casuale;
- il titolo precedente (⏮, P, tasto multimediale, SMTC), nel party e da soli;
- il post-play dal prossimo titolo della coda;
- il pannello "Coda" nel player, con la sola vista Coda;
- gli avvisi di precedente, salto e ordine casuale.

L'aggiunta di titoli (viste Aggiungi, Serie e Stagione) è il piano 14b.

**Spec:** `docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md` (§3, §7, §8.1–8.5, §9.1–9.3 tranne Aggiungi, Serie e Stagione, §10 tranne le aggiunte, §11).

**Decisioni del piano** (approvate dall'utente il 2026-10-04):
1. **⏮ e ⏭ quando non servono:** come ⏭ oggi, se non c'è un titolo da raggiungere il pulsante **non compare** (la spec diceva "spento": si allinea nel Task 18).
2. **Il pannello Coda si chiude da solo:**
   - quando compare il post-play;
   - quando il video va in errore;
   - quando si esce dal gruppo.

   Per i primi due casi è come il pannello delle tracce.
3. **Trascinamento:** la riga resta subito dove la si lascia, finché arriva la coda nuova del server. Se dopo 4 s non è arrivata, le righe tornano nell'ordine della coda.
4. **Riga sotto l'intestazione:** "14 titoli · 3h 40m dopo questo", contando **solo i prossimi**. Le durate sono nel formato dell'app (`formatRuntime`: "1h 57m", "22m").
5. **Post-play nel party:**
   - mostra il prossimo titolo della coda appena se ne conoscono i dettagli;
   - l'occhiello è "Prossimo episodio" se è l'episodio che segue nella libreria, altrimenti "Prossimo nella coda";
   - il test che verificava il contrario si riscrive (Task 13).
6. **⏮ da soli** apre l'episodio precedente dal punto in cui era rimasto, come ⏭, e **non** segna come visto quello che si lascia.
7. **Plugin 1.3.0 sul server:** a metà piano l'orchestratore lo installa a mano (Task 2).

**Decisione tecnica:** si annunciano le azioni nuove solo se il plugin ha la funzione `queue`. L'app lo legge dall'`Info` che il canale del party già chiede (`PartyPluginInfo.features` → `PartyChannelState.queueActions`), non da `SocialFeatures`. Così il controllo sta dove partono gli annunci, e i test del canale non dipendono da `SocialAvailability`. La spec si allinea nel Task 18.

**Architecture:**
- **Plugin:** `EventValidator` accetta 5 azioni nuove; `WatchPartyProtocol.Features` aggiunge `queue`; versione 1.3.0.
- **App:**
  - `SyncPlayApi` ha 6 metodi nuovi; `PlayQueue.shuffled`.
  - `LibraryApi` ha `itemsByIds` e `previousEpisode`.
  - Funzioni pure in `party_queue_rules.dart`.
  - `PartyQueueEditor` (provider) per salto, rimozione, spostamento e ordine casuale.
  - `partyQueueItemsProvider`: i dettagli dei titoli in coda.
  - `WatchPartySession`: `previousItem` e `previousEntry`.
  - `PartyNotices`: avvisi per `Reason`.
  - Nel player: ⏮, `PlayerPopup.queue`, `PlayerSidePanelHost` (estratto da `TracksPanelHost`), `QueuePanel` e `PartyQueuePanel`.

**Tech Stack:** C# net9.0 contro Jellyfin.Controller/Model 10.11.0 (test con le dll 10.11.9), xUnit; Flutter 3.47.5, flutter_riverpod 3, go_router 18, lucide_icons_flutter, smtc_windows 1.1.0.

**Worktree:** `.claude/worktrees/piano-14a`, branch `feat/piano-14a`. **Base:** `main` con questo piano. **Test a inizio piano:** 1487 Flutter, 244 plugin (da verificare all'avvio).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git già configurata (quella dell'utente).
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:**
  - Git Bash su Windows.
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-14a`).
  - Comandi git semplici: niente `git -C`, niente variabili nei comandi git.
  - Mai `git checkout -- <file>` su un file che hai modificato.
- **Prima di ogni commit:**
  - **lato plugin:** `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` tutto verde e senza warning (il plugin ha `TreatWarningsAsErrors`);
  - **lato app:** `flutter analyze` senza problemi e `flutter test` tutto verde.
- **File generati:**
  - Se `flutter test`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` né `dotnet format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: molti file della working copy sono CRLF, l'indice è LF con `core.autocrlf=true`.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese, anche nel C# (commenti `///` in italiano, identificatori in inglese). Nel C# sempre le graffe.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; durate da `WfMotion`; `clock.now()`, mai `DateTime.now()`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa, un gesto di trascinamento che nei test va mosso diversamente):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-04 sul codice di jellyfin v10.11.9 e sull'OpenAPI `docs/reference/jellyfin-openapi-10.11.9.json`.

**Endpoint SyncPlay** (tutti `POST`, risposta sempre 204, anche quando il server scarta la richiesta):

| Endpoint | Corpo |
|---|---|
| `/SyncPlay/Queue` | `{ItemIds: [...], Mode: "Queue"\|"QueueNext"}` |
| `/SyncPlay/SetPlaylistItem` | `{PlaylistItemId}` |
| `/SyncPlay/PreviousItem` | `{PlaylistItemId}` |
| `/SyncPlay/RemoveFromPlaylist` | `{PlaylistItemIds: [...], ClearPlaylist, ClearPlayingItem}` |
| `/SyncPlay/MovePlaylistItem` | `{PlaylistItemId, NewIndex}` |
| `/SyncPlay/SetShuffleMode` | `{Mode: "Sorted"\|"Shuffle"}` |

**Bug del server 10.11, da evitare:**
- `PreviousItem` o `NextItem` con un `PlaylistItemId` che non è quello in corso lasciano il gruppo in attesa: si manda solo l'id in corso.
- `RemoveFromPlaylist` con più id, tra cui quello in corso, può rompere il gruppo: si toglie un id per richiesta, mai quello in corso.
- `SetShuffleMode` `Sorted` su una coda già ordinata dà 500: si manda solo se lo stato è diverso.

**Coda e aggiornamenti:**
- **`MovePlaylistItem`** agisce sulla lista attiva, quella mescolata se c'è l'ordine casuale. `NewIndex` si conta dopo aver tolto l'elemento. L'elemento in corso resta lui: sposta solo il suo indice.
- **`PlayQueue` sul WebSocket:**
  - porta `ShuffleMode` (`"Sorted"`/`"Shuffle"`);
  - con l'ordine casuale la `Playlist` è quella mescolata.
- **`Reason`:** `NewPlaylist`, `SetCurrentItem`, `RemoveItems`, `MoveItem`, `Queue`, `QueueNext`, `NextItem`, `PreviousItem`, `RepeatMode`, `ShuffleMode`.
- **Ordine casuale acceso:** l'elemento in corso va in testa (`PlayingItemIndex` 0).

**Episodio precedente:** `GET /Shows/{seriesId}/Episodes?adjacentTo=<id>&isMissing=false`.
- Il filtro sui mancanti si applica **prima** dell'adiacenza.
- Senza `seasonId` vale su tutta la serie, quindi anche a cavallo delle stagioni.
- Restituisce [precedente, quello dato, successivo], quelli che esistono.

**`GET /Items?ids=a,b`** restituisce gli elementi visibili all'utente, in ordine qualunque: quelli cancellati o non visibili mancano.

**SMTC:** `smtc_windows` 1.1.0 ha `setIsPrevEnabled(bool)` e `PressedButton.previous`.

**App, cose da sapere:**
- **Pulsante ⏭:** oggi c'è solo se `onNextEpisode != null`.
- **Pannello delle tracce:**
  - `TracksPanelHost` (in `tracks_panel.dart`) fa entrata, uscita e velo.
  - La barriera della rotella sta dentro `TracksPanel`.
  - I test della rotella in `tracks_panel_test.dart` provano `TracksPanel` da solo: la barriera deve restare nel pannello (si estrae in un widget comune, `PanelWheelBarrier`).
- **`PlayerChromeController`:** con `PlayerPopup.tracks` o `.reactions` aperti i controlli restano visibili e la schermata di pausa non parte (`_scheduleHide`).
- **`SliverReorderableList`:**
  - mostra il trascinato in un `Overlay`;
  - le righe con `InkWell` vogliono un `Material` sopra, quindi serve un `proxyDecorator` con un `Material`;
  - ogni riga deve avere una chiave;
  - `onReorder(old, new)` conta `new` prima di togliere la riga: scendendo `new -= 1`.
- **`PartyNotices`:** gli avvisi di cambio titolo nascono dagli aggiornamenti `PlayQueue`. Il nome si aggancia all'annuncio di un'azione (`_showOthers`): con il canale attivo l'avviso aspetta al massimo 300 ms, e un annuncio vale 2 s. Il plugin non rimanda a chi agisce i suoi annunci: le proprie azioni di cambio titolo escono senza nome, come oggi (spec E §8).
- **`PartyChannel.announce`** parte solo con il canale attivo. `Info` si chiede finché il plugin non risulta presente, poi resta in memoria.
- **Test del player nel gruppo:** `test/features/watch_party/party_player_test.dart` (`pumpPartyPlayer`, `queueSeries`, `announced()`, `finish`).
- **Test del player da solo:** `test/features/player/player_screen_test.dart` (`pumpPlayer`, `withNextEpisode`, `unmount`).

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/EventValidator.cs` | modifica | 5 azioni nuove |
| `…/Protocol/WatchPartyProtocol.cs` | modifica | `Features` + `queue` |
| `…/Jellyfin.Plugin.WonderFlixWatchParty.csproj` | modifica | versione 1.3.0 |
| `jellyfin-plugin-watch-party/README.md` | modifica | azioni della coda, esempio 1.3.0 |
| `…Tests/EventValidatorTests.cs`, `…Tests/InfoControllerTests.cs` | modifica | test |
| `lib/core/syncplay/syncplay_api.dart`, `syncplay_models.dart` | modifica | comandi della coda, `PlayQueue.shuffled` |
| `lib/core/jellyfin/library_api.dart` | modifica | `itemsByIds`, `previousEpisode` |
| `lib/core/party_channel/party_channel_models.dart` | modifica | `PartyAction` nuove, `PartyPluginInfo.features`, `partyQueueFeature` |
| `lib/features/watch_party/party_channel.dart` | modifica | `queueActions`, annunci filtrati |
| `lib/features/watch_party/party_queue_rules.dart` | crea | sezioni, indici, durate, ordine provvisorio |
| `lib/features/watch_party/watch_party_session.dart` | modifica | `previousEntry`, `hasPrevious`, `previousItem` |
| `lib/features/watch_party/party_notices.dart`, `party_notice_pill.dart` | modifica | avvisi per `Reason`, ordine casuale, errore |
| `lib/features/watch_party/party_queue_editor.dart` | crea | `PartyQueueEditor` |
| `lib/features/watch_party/party_queue_items.dart` | crea | `partyQueueItemsProvider` |
| `lib/core/media_session/*.dart`, `lib/features/discord/discord_presence.dart` | modifica | "precedente" |
| `lib/features/player/player_commands.dart` | modifica | `PlayerCommand.previous` |
| `lib/features/player/player_controller.dart` | modifica | `previousEpisode` |
| `lib/features/player/player_overlay.dart` | modifica | ⏮, suggerimenti nel party, pulsante Coda |
| `lib/features/player/post_play.dart`, `player_extras.dart` | modifica | occhiello `label` |
| `lib/features/player/player_side_panel_host.dart` | crea | `PlayerSidePanelHost`, `PanelWheelBarrier` |
| `lib/features/player/tracks_panel.dart` | modifica | usa i due widget comuni |
| `lib/features/player/player_chrome.dart` | modifica | `PlayerPopup.queue` |
| `lib/features/player/queue_panel/queue_rows.dart`, `queue_panel.dart` | crea | righe, `QueuePanel`, `PartyQueuePanel` |
| `lib/features/player/player_screen.dart` | modifica | ⏮, post-play dalla coda, pannello Coda |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi |
| `test/support/watch_party_fakes.dart`, `library_fakes.dart`, `playback_fakes.dart` | modifica | finti |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1):** plugin. **Poi ci si ferma:** il Task 2 lo fa l'orchestratore (installazione sul server).
- **Gruppo B (Task 3–7):** API, modelli, regole, canale, sessione.
- **Gruppo C (Task 8–10):** testi e avvisi, editor, dettagli della coda.
- **Gruppo D (Task 11–13):** player: precedente e post-play.
- **Gruppo E (Task 14–17):** pannello Coda.
- **Gruppo F (Task 18):** allineamento della spec, verifica finale, build.

---

## Gruppo A — plugin

### Task 1: plugin 1.3.0, le azioni della coda

**Files:**
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/EventValidator.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj`
- Modify: `jellyfin-plugin-watch-party/README.md`
- Test: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/EventValidatorTests.cs`, `InfoControllerTests.cs`

- [ ] **Step 1: test che falliscono**

In `EventValidatorTests.cs`, nel `[Theory]` `ActionsWithoutPosition`, dopo `[InlineData("NewQueue")]`:

```csharp
    [InlineData("PreviousItem")]
    [InlineData("SetCurrentItem")]
    [InlineData("Queue")]
    [InlineData("QueueNext")]
    [InlineData("ShuffleMode")]
```

In `InfoControllerTests.cs`, in `InfoReportsVersionProtocolAndFeatures`:

```csharp
        Assert.Equal("1.3.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(new[] { "friends", "parties", "inbox", "queue" }, info.Features);
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: FAIL. I 5 nuovi `ActionsWithoutPosition` falliscono (`valid` è null), e falliscono anche versione e funzioni di `Info`.

- [ ] **Step 3: implementazione**

In `EventValidator.cs`, l'insieme delle azioni diventa:

```csharp
    private static readonly HashSet<string> Actions = new(StringComparer.Ordinal)
    {
        "Pause", "Unpause", "Seek", "NextItem", "NewQueue",
        // Coda del watch party (spec H §7).
        "PreviousItem", "SetCurrentItem", "Queue", "QueueNext", "ShuffleMode",
    };
```

In `WatchPartyProtocol.cs`:

```csharp
    /// <summary>
    /// Funzioni in più rispetto allo spec E, in GET Info (spec F §6.7, spec
    /// G §6.3, spec H §7). Il protocollo resta 1: le app 0.5.x accettano solo quello.
    /// </summary>
    public static readonly IReadOnlyList<string> Features = ["friends", "parties", "inbox", "queue"];
```

Nel `.csproj`: `<Version>1.3.0</Version>`.

In `README.md`, nel primo paragrafo, dopo la frase sulla cassetta delle notifiche (spec G), aggiungi la coda. Il paragrafo diventa:

```markdown
Plugin del server Jellyfin per il watch party di WonderFlix (spec E,
`docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md`):
dice chi ha agito, porta la chat e le reazioni tra i membri di un gruppo
SyncPlay e tiene la lista amici (spec F,
`docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md`)
e la cassetta delle notifiche (spec G,
`docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md`). Dalla
1.3.0 dice anche chi ha cambiato la coda del gruppo (spec H,
`docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md`).
Senza il plugin WonderFlix funziona lo stesso, con gli avvisi
anonimi.
```

Nella sezione "Installazione a mano (prove)" l'esempio diventa `bash jellyfin-plugin-watch-party/pack.sh 1.3.0`, con la cartella `WonderFlix Watch Party_1.3.0.0/`.

- [ ] **Step 4: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, 249 test (244 + 5), nessun warning.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): accept the party queue actions (1.3.0)"
```

### Task 2: STOP — installazione sul server (lo fa l'orchestratore)

I subagent si fermano qui. L'orchestratore:

1. Crea la cartella del plugin: `bash jellyfin-plugin-watch-party/pack.sh 1.3.0`.
2. Ricrea nella scratchpad della sessione il progetto di controllo dei riferimenti (console `net9.0` con `<FrameworkReference Include="Microsoft.AspNetCore.App" />` e i pacchetti `Jellyfin.Controller`/`Jellyfin.Model` **10.11.9**) e lo lancia sulla dll. Atteso: 0 riferimenti non risolti.
3. Controlla nel log (`ssh ultra`, `~/.apps/jellyfin/log/log_YYYYMMDD.log` di oggi, in UTC) che nessuno stia guardando: l'ultimo `Playback start` deve avere il suo `Playback stopped`. Se qualcuno guarda, lo chiede all'utente.
4. Ferma Jellyfin, copia, riavvia:
   1. `ssh ultra 'app-jellyfin stop'`;
   2. `scp -r "jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.3.0.0" ultra:~/.apps/jellyfin/data/plugins/`;
   3. `ssh ultra 'app-jellyfin start'`.

   La cartella 1.2.0.0 del Catalogo resta: la 1.3.0.0 è più nuova e vince.
5. Nel log controlla `Loaded plugin: "WonderFlix Watch Party" "1.3.0.0"`.

Poi riparte il Gruppo B.

---

## Gruppo B — API, modelli, regole, canale, sessione

### Task 3: comandi SyncPlay della coda e `PlayQueue.shuffled`

**Files:**
- Modify: `lib/core/syncplay/syncplay_api.dart`
- Modify: `lib/core/syncplay/syncplay_models.dart`
- Modify: `test/support/watch_party_fakes.dart`
- Test: `test/core/syncplay/syncplay_api_test.dart`, `test/core/syncplay/syncplay_models_test.dart`

- [ ] **Step 1: test che falliscono**

In `syncplay_api_test.dart`, dopo il test `nextItem con l'elemento in riproduzione`:

```dart
  test('comandi della coda (spec H §8.1)', () async {
    await api.previousItem('p2');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/SyncPlay/PreviousItem');
    expect(body(), {'PlaylistItemId': 'p2'});

    adapter.requests.clear();
    await api.setPlaylistItem('p3');
    expect(adapter.requests.single.path, '/SyncPlay/SetPlaylistItem');
    expect(body(), {'PlaylistItemId': 'p3'});

    adapter.requests.clear();
    await api.queue(['m1', 'm2'], next: false);
    expect(adapter.requests.single.path, '/SyncPlay/Queue');
    expect(body(), {
      'ItemIds': ['m1', 'm2'],
      'Mode': 'Queue',
    });

    adapter.requests.clear();
    await api.queue(['m3'], next: true);
    expect(body(), {
      'ItemIds': ['m3'],
      'Mode': 'QueueNext',
    });

    adapter.requests.clear();
    await api.removeFromPlaylist('p4');
    expect(adapter.requests.single.path, '/SyncPlay/RemoveFromPlaylist');
    expect(body(), {
      'PlaylistItemIds': ['p4'],
      'ClearPlaylist': false,
      'ClearPlayingItem': false,
    });

    adapter.requests.clear();
    await api.movePlaylistItem('p4', 2);
    expect(adapter.requests.single.path, '/SyncPlay/MovePlaylistItem');
    expect(body(), {'PlaylistItemId': 'p4', 'NewIndex': 2});

    adapter.requests.clear();
    await api.setShuffleMode(shuffle: true);
    expect(adapter.requests.single.path, '/SyncPlay/SetShuffleMode');
    expect(body(), {'Mode': 'Shuffle'});

    adapter.requests.clear();
    await api.setShuffleMode(shuffle: false);
    expect(body(), {'Mode': 'Sorted'});
  });
```

In `syncplay_models_test.dart`, in fondo a `main`:

```dart
  test('PlayQueue: ordine casuale (spec H §8.1)', () {
    final queue = PlayQueue.fromJson({
      'Reason': 'ShuffleMode',
      'LastUpdate': '2026-10-04T10:00:00Z',
      'Playlist': [
        {'ItemId': 'e4', 'PlaylistItemId': 'p1'},
      ],
      'PlayingItemIndex': 0,
      'ShuffleMode': 'Shuffle',
    });
    expect(queue.shuffled, isTrue);
    expect(PlayQueue.fromJson({'ShuffleMode': 'Sorted'}).shuffled, isFalse);
    expect(PlayQueue.fromJson(const <String, dynamic>{}).shuffled, isFalse);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/syncplay`
Expected: FAIL, metodi e getter non definiti.

- [ ] **Step 3: implementazione**

In `syncplay_api.dart`, dopo `nextItem`:

```dart
  /// Torna all'elemento prima di quello in riproduzione. [playlistItemId] è
  /// quello in riproduzione: con un id diverso il server 10.11 lascia il
  /// gruppo in attesa (spec H §3), quindi lo si manda solo se è ancora lui.
  Future<void> previousItem(String playlistItemId) =>
      _post('/SyncPlay/PreviousItem', {'PlaylistItemId': playlistItemId});

  /// Il gruppo passa all'elemento [playlistItemId] della coda, da 0.
  Future<void> setPlaylistItem(String playlistItemId) =>
      _post('/SyncPlay/SetPlaylistItem', {'PlaylistItemId': playlistItemId});

  /// Aggiunge [itemIds] in fondo alla coda o, con [next], subito dopo
  /// l'elemento in riproduzione; l'ordine dato si mantiene.
  Future<void> queue(List<String> itemIds, {required bool next}) =>
      _post('/SyncPlay/Queue',
          {'ItemIds': itemIds, 'Mode': next ? 'QueueNext' : 'Queue'});

  /// Toglie un elemento dalla coda. Uno per richiesta: con più id, tra cui
  /// quello in riproduzione, il server 10.11 può rompere il gruppo (spec H
  /// §3).
  Future<void> removeFromPlaylist(String playlistItemId) =>
      _post('/SyncPlay/RemoveFromPlaylist', {
        'PlaylistItemIds': [playlistItemId],
        'ClearPlaylist': false,
        'ClearPlayingItem': false,
      });

  /// Sposta un elemento alla posizione [newIndex] della coda com'è adesso
  /// (quella mescolata, con l'ordine casuale), contata dopo averlo tolto.
  Future<void> movePlaylistItem(String playlistItemId, int newIndex) =>
      _post('/SyncPlay/MovePlaylistItem',
          {'PlaylistItemId': playlistItemId, 'NewIndex': newIndex});

  /// Ordine casuale acceso o spento. `Sorted` su una coda già ordinata fa
  /// rispondere 500 al server 10.11 (spec H §3): chi chiama controlla prima.
  Future<void> setShuffleMode({required bool shuffle}) => _post(
      '/SyncPlay/SetShuffleMode', {'Mode': shuffle ? 'Shuffle' : 'Sorted'});
```

In `syncplay_models.dart`, in `PlayQueue`:
- **costruttore:** aggiungi in fondo `this.shuffled = false,`;
- **`fromJson`:** aggiungi `shuffled: json['ShuffleMode'] == 'Shuffle',`;
- **campo**, dopo `isPlaying`:

```dart
  /// Ordine casuale attivo (`ShuffleMode`): [entries] è nell'ordine
  /// mescolato (spec H §3).
  final bool shuffled;
```

In `test/support/watch_party_fakes.dart`, in `FakeSyncPlayApi`, dopo `nextItem`:

```dart
  @override
  Future<void> previousItem(String playlistItemId) =>
      _record('previous $playlistItemId');

  @override
  Future<void> setPlaylistItem(String playlistItemId) =>
      _record('set-item $playlistItemId');

  /// Registra `add a,b` o `add-next a,b`.
  @override
  Future<void> queue(List<String> itemIds, {required bool next}) =>
      _record('${next ? 'add-next' : 'add'} ${itemIds.join(',')}');

  @override
  Future<void> removeFromPlaylist(String playlistItemId) =>
      _record('remove $playlistItemId');

  @override
  Future<void> movePlaylistItem(String playlistItemId, int newIndex) =>
      _record('move $playlistItemId $newIndex');

  @override
  Future<void> setShuffleMode({required bool shuffle}) =>
      _record('shuffle ${shuffle ? 'on' : 'off'}');
```

`testSeriesQueue` riceve `bool shuffled = false` (dopo `lastUpdate`) e lo passa a `PlayQueue(..., shuffled: shuffled)`.

- [ ] **Step 4: i test passano**

Run: `flutter test test/core/syncplay`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze` → nessun problema; `flutter test` → tutto verde.

```bash
git add lib/core/syncplay test/core/syncplay test/support/watch_party_fakes.dart
git commit -m "feat(party): add the SyncPlay queue commands"
```

### Task 4: `LibraryApi.itemsByIds` e `previousEpisode`

**Files:**
- Modify: `lib/core/jellyfin/library_api.dart`
- Modify: `test/support/library_fakes.dart`
- Test: `test/core/jellyfin/library_api_test.dart`

- [ ] **Step 1: test che falliscono**

In `library_api_test.dart`, dopo il test `nextEpisode`:

```dart
  test('previousEpisode: l\'episodio prima di quello indicato (spec H §8.1)',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['e3', 'e4', 'e5']));
    final previous = await api.previousEpisode('u1', 's1', 'e4');
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['adjacentTo'], 'e4');
    expect(last().query['isMissing'], false);
    expect(last().query['userId'], 'u1');
    expect(last().query, isNot(contains('seasonId')),
        reason: 'anche dalla stagione prima');
    expect(previous?.id, 'e3');

    adapter.handler = (_) => FakeResponse(200, itemsResult(['e1', 'e2']));
    expect(await api.previousEpisode('u1', 's1', 'e1'), isNull,
        reason: 'primo episodio');
  });

  test('itemsByIds: gli elementi indicati, con le immagini delle card',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['m2', 'm1']));
    final items = await api.itemsByIds('u1', ['m1', 'm2']);
    expect(last().path, '/Items');
    expect(last().query['ids'], 'm1,m2');
    expect(last().query['userId'], 'u1');
    expect(last().query['enableImageTypes'], 'Primary,Backdrop,Thumb,Logo');
    expect(items.map((item) => item.id), ['m2', 'm1']);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/jellyfin/library_api_test.dart`
Expected: FAIL, metodi non definiti.

- [ ] **Step 3: implementazione**

In `library_api.dart`, dopo `nextEpisode`:

```dart
  /// Episodio che precede [episodeId] nella serie, anche nella stagione
  /// prima (spec H §8.1); `null` se è il primo. Jellyfin toglie i mancanti
  /// prima di cercare i vicini.
  Future<JellyfinItem?> previousEpisode(
      String userId, String seriesId, String episodeId) async {
    final episodes = _list(await _http.get('/Shows/$seriesId/Episodes', query: {
      ...cardImageParams,
      'userId': userId,
      'adjacentTo': episodeId,
      'isMissing': false,
      'fields': 'Overview,PrimaryImageAspectRatio',
    }));
    final index = episodes.indexWhere((e) => e.id == episodeId);
    return index > 0 ? episodes[index - 1] : null;
  }

  /// Gli elementi [ids] (la coda del watch party, spec H §8.5), in ordine
  /// qualunque: quelli cancellati o che l'utente non vede mancano.
  Future<List<JellyfinItem>> itemsByIds(String userId, List<String> ids) async =>
      _list(await _http.get('/Items', query: {
        ...cardImageParams,
        'userId': userId,
        'ids': ids.join(','),
      }));
```

In `test/support/library_fakes.dart`, in `FakeLibraryApi`:

```dart
  /// Episodio precedente, per id dell'episodio corrente.
  final Map<String, JellyfinItem> previousEpisodes = {};
  final previousEpisodeCalls = <String>[];

  /// Id chiesti a [itemsByIds], una lista per chiamata.
  final itemsByIdsCalls = <List<String>>[];

  @override
  Future<JellyfinItem?> previousEpisode(
      String userId, String seriesId, String episodeId) {
    previousEpisodeCalls.add(episodeId);
    return _answer(() => previousEpisodes[episodeId]);
  }

  /// Gli elementi di [itemsById] tra [ids]; gli altri mancano, come quelli
  /// cancellati sul server.
  @override
  Future<List<JellyfinItem>> itemsByIds(String userId, List<String> ids) {
    itemsByIdsCalls.add(ids);
    return _answer(() => [
          for (final id in ids)
            if (itemsById[id] case final item?) item,
        ]);
  }
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/core/jellyfin/library_api_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/core/jellyfin/library_api.dart test/support/library_fakes.dart test/core/jellyfin/library_api_test.dart
git commit -m "feat(library): fetch items by id and the previous episode"
```

### Task 5: regole della coda (funzioni pure)

**Files:**
- Create: `lib/features/watch_party/party_queue_rules.dart`
- Test: `test/features/watch_party/party_queue_rules_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/features/watch_party/party_queue_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/watch_party/party_queue_rules.dart';

import '../../support/library_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  /// e3 (p1), e4 (p2), e5 (p3), e6 (p4); in riproduzione [playingIndex].
  PlayQueue queue({int playingIndex = 1}) => testSeriesQueue(
      itemIds: const ['e3', 'e4', 'e5', 'e6'], playingIndex: playingIndex);

  List<String> ids(List<PlayQueueEntry> entries) =>
      [for (final entry in entries) entry.playlistItemId];

  test('sezioni: già visti, in riproduzione, prossimi (spec H §9.2)', () {
    final sections = partyQueueSections(queue());
    expect(ids(sections.watched), ['p1']);
    expect(sections.playing?.playlistItemId, 'p2');
    expect(ids(sections.upcoming), ['p3', 'p4']);

    final first = partyQueueSections(queue(playingIndex: 0));
    expect(first.watched, isEmpty);
    expect(ids(first.upcoming), ['p2', 'p3', 'p4']);

    final last = partyQueueSections(queue(playingIndex: 3));
    expect(ids(last.watched), ['p1', 'p2', 'p3']);
    expect(last.upcoming, isEmpty);
  });

  test('sezioni senza elemento in riproduzione: tutto tra i prossimi', () {
    final sections = partyQueueSections(queue(playingIndex: -1));
    expect(sections.watched, isEmpty);
    expect(sections.playing, isNull);
    expect(ids(sections.upcoming), ['p1', 'p2', 'p3', 'p4']);
  });

  test('indice dello spostamento: dopo l\'elemento in riproduzione', () {
    expect(partyQueueMoveIndex(queue(), 0), 2);
    expect(partyQueueMoveIndex(queue(), 1), 3);
    expect(partyQueueMoveIndex(queue(playingIndex: 0), 0), 1);
    expect(partyQueueMoveIndex(queue(playingIndex: -1), 2), 2);
  });

  test('durata dei prossimi: solo quelli noti con una durata', () {
    final items = <String, JellyfinItem?>{
      'e4': testItem(id: 'e4', runtimeMinutes: 30),
      'e5': testItem(id: 'e5', runtimeMinutes: 22),
      'e6': null,
    };
    expect(partyQueueUpcomingRuntime(queue(), items),
        const Duration(minutes: 22),
        reason: 'e4 è in riproduzione, e6 non è disponibile');
    expect(partyQueueUpcomingRuntime(queue(), const {}), isNull);
    expect(
        partyQueueUpcomingRuntime(queue(playingIndex: 3), items), isNull);
  });

  test('ordine provvisorio: vale solo con gli stessi elementi', () {
    final upcoming = partyQueueSections(queue(playingIndex: 0)).upcoming;
    expect(ids(partyQueueInOrder(upcoming, null)), ['p2', 'p3', 'p4']);
    expect(ids(partyQueueInOrder(upcoming, const ['p4', 'p2', 'p3'])),
        ['p4', 'p2', 'p3']);
    expect(ids(partyQueueInOrder(upcoming, const ['p4', 'p2'])),
        ['p2', 'p3', 'p4'], reason: 'un elemento in più nella coda');
    expect(ids(partyQueueInOrder(upcoming, const ['p4', 'p2', 'p9'])),
        ['p2', 'p3', 'p4'], reason: 'un elemento tolto');
  });

  test('tetto della coda', () {
    expect(partyQueueLimit, 100);
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/watch_party/party_queue_rules_test.dart`
Expected: FAIL, file non trovato.

- [ ] **Step 3: implementazione**

Crea `lib/features/watch_party/party_queue_rules.dart`:

```dart
import '../../core/jellyfin/item_models.dart';
import '../../core/syncplay/syncplay_models.dart';

/// Al massimo questi titoli in tutta la coda del gruppo (spec H §4). La coda
/// iniziale di una serie resta di `maxPartyQueue` (`party_queue.dart`).
const partyQueueLimit = 100;

/// La coda divisa come nel pannello "Coda" (spec H §9.2).
class PartyQueueSections {
  const PartyQueueSections({
    required this.watched,
    required this.playing,
    required this.upcoming,
  });

  /// Gli elementi prima di quello in riproduzione.
  final List<PlayQueueEntry> watched;
  final PlayQueueEntry? playing;

  /// Gli elementi dopo quello in riproduzione (tutti, se non ce n'è uno).
  final List<PlayQueueEntry> upcoming;
}

PartyQueueSections partyQueueSections(PlayQueue queue) {
  final playing = queue.playing;
  if (playing == null) {
    return PartyQueueSections(
        watched: const [], playing: null, upcoming: queue.entries);
  }
  return PartyQueueSections(
    watched: queue.entries.sublist(0, queue.playingIndex),
    playing: playing,
    upcoming: queue.entries.sublist(queue.playingIndex + 1),
  );
}

/// `NewIndex` di `MovePlaylistItem` per un prossimo portato alla posizione
/// [upcomingIndex] tra i prossimi (contata dopo averlo tolto). Spostare un
/// prossimo non cambia la posizione dell'elemento in riproduzione.
int partyQueueMoveIndex(PlayQueue queue, int upcomingIndex) =>
    queue.playingIndex + 1 + upcomingIndex;

/// Durata dei prossimi dai dettagli [items] (per `ItemId`); quelli senza
/// durata, o non ancora noti, non contano. `null` se nessuno ne ha una.
Duration? partyQueueUpcomingRuntime(
    PlayQueue queue, Map<String, JellyfinItem?> items) {
  Duration? total;
  for (final entry in partyQueueSections(queue).upcoming) {
    final runtime = items[entry.itemId]?.runtime;
    if (runtime != null) total = (total ?? Duration.zero) + runtime;
  }
  return total;
}

/// I prossimi nell'ordine [order] (id nella coda) di un trascinamento non
/// ancora confermato dal server, se sono ancora gli stessi elementi;
/// altrimenti come sono nella coda.
List<PlayQueueEntry> partyQueueInOrder(
    List<PlayQueueEntry> upcoming, List<String>? order) {
  if (order == null || order.length != upcoming.length) return upcoming;
  final byId = {for (final entry in upcoming) entry.playlistItemId: entry};
  final sorted = [for (final id in order) ?byId[id]];
  return sorted.length == upcoming.length ? sorted : upcoming;
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/watch_party/party_queue_rules_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/watch_party/party_queue_rules.dart test/features/watch_party/party_queue_rules_test.dart
git commit -m "feat(party): add the queue rules"
```

### Task 6: azioni nuove e funzione `queue` del plugin nel canale

**Files:**
- Modify: `lib/core/party_channel/party_channel_models.dart`
- Modify: `lib/features/watch_party/party_channel.dart`
- Modify: `test/support/watch_party_fakes.dart`
- Test: `test/core/party_channel/party_channel_models_test.dart`, `test/features/watch_party/party_channel_test.dart`

- [ ] **Step 1: test che falliscono**

In `party_channel_models_test.dart`, il test `Info del plugin` diventa:

```dart
  test('Info del plugin', () {
    final info = PartyPluginInfo.fromJson({'Version': '1.0.0', 'Protocol': 1});
    expect(info.version, '1.0.0');
    expect(info.protocol, 1);
    expect(info.features, isEmpty);

    final queue = PartyPluginInfo.fromJson({
      'Version': '1.3.0',
      'Protocol': 1,
      'Features': ['friends', 'queue', 7],
    });
    expect(queue.features, {'friends', partyQueueFeature});
  });

  test('azioni della coda (spec H §7)', () {
    expect(PartyAction.fromWire('PreviousItem'), PartyAction.previousItem);
    expect(PartyAction.fromWire('SetCurrentItem'), PartyAction.setCurrentItem);
    expect(PartyAction.fromWire('Queue'), PartyAction.queue);
    expect(PartyAction.fromWire('QueueNext'), PartyAction.queueNext);
    expect(PartyAction.fromWire('ShuffleMode'), PartyAction.shuffleMode);
    expect(PartyAction.pause.queueFeature, isFalse);
    expect(PartyAction.newQueue.queueFeature, isFalse);
    expect(PartyAction.shuffleMode.queueFeature, isTrue);
  });
```

In `party_channel_test.dart`, in fondo a `main`:

```dart
  test('azioni della coda: senza la funzione queue del plugin non partono',
      () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      expect(channel().queueActions, isFalse);
      notifier()
        ..announce(PartyAction.shuffleMode)
        ..announce(PartyAction.pause);
      async.flushMicrotasks();
      expect(sentJson(), [
        {'Type': 'Action', 'Action': 'Pause'},
      ]);
      finish(async);
    });
  });

  test('plugin 1.3.0: le azioni della coda partono (spec H §7)', () {
    fakeAsync((async) {
      channelApi.install(version: '1.3.0', features: const {partyQueueFeature});
      mount(async);
      joinGroup(async);
      expect(channel().queueActions, isTrue);
      notifier()
        ..announce(PartyAction.previousItem)
        ..announce(PartyAction.setCurrentItem)
        ..announce(PartyAction.shuffleMode);
      async.flushMicrotasks();
      expect(sentJson(), [
        {'Type': 'Action', 'Action': 'PreviousItem'},
        {'Type': 'Action', 'Action': 'SetCurrentItem'},
        {'Type': 'Action', 'Action': 'ShuffleMode'},
      ]);

      // Uscendo dal gruppo la funzione resta nota (come la versione).
      leaveGroup(async);
      expect(channel().queueActions, isTrue);
      finish(async);
    });
  });

  test('plugin sparito: la funzione queue si dimentica', () {
    fakeAsync((async) {
      channelApi.install(version: '1.3.0', features: const {partyQueueFeature});
      mount(async);
      joinGroup(async);
      channelApi.sendFailures.add(PartyChannelFailure.unavailable);
      notifier().announce(PartyAction.pause);
      async.flushMicrotasks();
      expect(channel().queueActions, isFalse);
      finish(async);
    });
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/party_channel test/features/watch_party/party_channel_test.dart`
Expected: FAIL, membri non definiti.

- [ ] **Step 3: implementazione**

In `party_channel_models.dart`, sopra `PartyPluginInfo`:

```dart
/// Funzione del plugin con le azioni della coda (spec H §7, plugin 1.3.0).
const partyQueueFeature = 'queue';
```

`PartyPluginInfo` diventa:

```dart
/// Risposta di `GET /WonderFlixWatchParty/Info`.
class PartyPluginInfo {
  const PartyPluginInfo({
    required this.version,
    required this.protocol,
    this.features = const {},
  });

  factory PartyPluginInfo.fromJson(Map<String, dynamic> json) =>
      PartyPluginInfo(
        version: json['Version'] as String,
        protocol: (json['Protocol'] as num).toInt(),
        features: {
          for (final feature in json['Features'] as List? ?? const [])
            if (feature is String) feature,
        },
      );

  final String version;
  final int protocol;

  /// Funzioni in più del plugin (es. [partyQueueFeature]).
  final Set<String> features;
}
```

`PartyAction` diventa:

```dart
/// Azioni annunciate al gruppo: hanno i nomi delle richieste SyncPlay.
enum PartyAction {
  pause('Pause'),
  unpause('Unpause'),
  seek('Seek'),
  nextItem('NextItem'),
  newQueue('NewQueue'),
  previousItem('PreviousItem', queueFeature: true),
  setCurrentItem('SetCurrentItem', queueFeature: true),
  queue('Queue', queueFeature: true),
  queueNext('QueueNext', queueFeature: true),
  shuffleMode('ShuffleMode', queueFeature: true);

  const PartyAction(this.wire, {this.queueFeature = false});

  /// Nome nel protocollo.
  final String wire;

  /// Il plugin la accetta solo con la funzione [partyQueueFeature] (1.3.0):
  /// uno più vecchio risponderebbe 400.
  final bool queueFeature;

  static PartyAction? fromWire(Object? value) {
    for (final action in values) {
      if (action.wire == value) return action;
    }
    return null;
  }
}
```

In `party_channel.dart`, in `PartyChannelState`:
- costruttore `this.queueActions = false,`;
- campo:

```dart
  /// Il plugin accetta le azioni della coda (funzione [partyQueueFeature]):
  /// solo allora si annunciano (spec H §7).
  final bool queueActions;
```

- in `copyWith` il parametro `bool? queueActions,` e il valore `queueActions: clearPluginVersion ? false : queueActions ?? this.queueActions,`.

Sempre in `party_channel.dart`:
- **`refreshInfo`:** nel `state.copyWith(...)` riuscito aggiungi `queueActions: info.features.contains(partyQueueFeature),`.
- **`_join`:** il `state = state.copyWith(availability: PartyPluginAvailability.available, pluginVersion: info.version)` diventa

  ```dart
          state = state.copyWith(
              availability: PartyPluginAvailability.available,
              pluginVersion: info.version,
              queueActions: info.features.contains(partyQueueFeature));
  ```

- **`_leave`:** lo stato nuovo tiene anche la funzione:

  ```dart
      state = PartyChannelState(
          availability: state.availability,
          pluginVersion: state.pluginVersion,
          queueActions: state.queueActions);
  ```

- **`announce`:**

  ```dart
    /// Annuncia agli altri un'azione nostra sul gruppo (spec E §7.4). Le
    /// azioni della coda partono solo se il plugin le conosce (spec H §7):
    /// senza, l'avviso degli altri resta senza nome.
    void announce(PartyAction action, {Duration? position}) {
      if (_groupId == null) return;
      if (action.queueFeature && !state.queueActions) return;
      unawaited(_sendQuietly(PartyOutgoingAction(action, position: position)));
    }
  ```

In `test/support/watch_party_fakes.dart`, `FakePartyChannelApi.install` diventa:

```dart
  /// Plugin presente, con il nostro protocollo e le funzioni [features].
  void install({String version = '1.0.0', Set<String> features = const {}}) =>
      pluginInfo = PartyPluginInfo(
          version: version, protocol: partyChannelProtocol, features: features);
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/core/party_channel test/features/watch_party/party_channel_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/core/party_channel lib/features/watch_party/party_channel.dart test/core/party_channel test/features/watch_party/party_channel_test.dart test/support/watch_party_fakes.dart
git commit -m "feat(party): announce queue actions only to a plugin that knows them"
```

### Task 7: "precedente" nella sessione

**Files:**
- Modify: `lib/features/watch_party/watch_party_session.dart`
- Test: `test/features/watch_party/watch_party_session_test.dart`

- [ ] **Step 1: test che falliscono**

In `watch_party_session_test.dart`, dopo `nextItem con la richiesta fallita: false, niente annuncio`:

```dart
  test('previousItem: solo se c\'è un elemento prima (spec H §8.4)', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    await pumpEventQueue();
    expect(state().hasPrevious, isFalse);
    expect(state().previousEntry, isNull);
    expect(await session().previousItem('p1'), isFalse);
    expect(api.calls, isNot(contains('previous p1')));

    emit(PlayQueueUpdate(
        'g1',
        testSeriesQueue(
            playingIndex: 1,
            reason: 'NextItem',
            lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await pumpEventQueue();
    expect(state().previousEntry?.itemId, 'e4');
    // Il player di e4 (p1) non chiede il precedente quando il gruppo è già
    // su e5: il server resterebbe in attesa.
    expect(await session().previousItem('p1'), isFalse);
    expect(await session().previousItem('p2'), isTrue);
    expect(api.calls.last, 'previous p2');
  });

  test('previousItem con la richiesta fallita: false', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    emit(PlayQueueUpdate('g1', testSeriesQueue(playingIndex: 1)));
    await pumpEventQueue();
    api.error = const ServerUnreachableException();
    expect(await session().previousItem('p2'), isFalse);
    expect(api.calls.last, 'previous p2');
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/watch_party/watch_party_session_test.dart`
Expected: FAIL, membri non definiti.

- [ ] **Step 3: implementazione**

In `WatchPartyState`, dopo `hasNext`:

```dart
  /// Elemento prima di quello in riproduzione; `null` sul primo.
  PlayQueueEntry? get previousEntry {
    final queue = this.queue;
    if (queue == null ||
        queue.playingIndex <= 0 ||
        queue.playingIndex >= queue.entries.length) {
      return null;
    }
    return queue.entries[queue.playingIndex - 1];
  }

  bool get hasPrevious => previousEntry != null;
```

In `WatchPartySession`, dopo `nextItem`:

```dart
  /// Il gruppo torna all'elemento prima (pulsante ⏮, tasto P, spec H §8.4),
  /// se è ancora in riproduzione [fromPlaylistItemId]: con un id diverso il
  /// server resterebbe in attesa (spec H §3). `false` se il gruppo è già
  /// altrove, se non c'è un elemento prima o se la richiesta non è arrivata.
  Future<bool> previousItem(String fromPlaylistItemId) async {
    final playing = state.queue?.playing;
    if (!state.inGroup ||
        playing == null ||
        playing.playlistItemId != fromPlaylistItemId ||
        !state.hasPrevious) {
      return false;
    }
    try {
      await _api.previousItem(playing.playlistItemId);
      return true;
    } on Object catch (error) {
      _log.warning('elemento precedente non chiesto: $error');
      return false;
    }
  }
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/watch_party/watch_party_session_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/watch_party/watch_party_session.dart test/features/watch_party/watch_party_session_test.dart
git commit -m "feat(party): ask the group for the previous item"
```

---

## Gruppo C — testi, avvisi, editor, dettagli della coda

### Task 8: testi del piano e avvisi della coda

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify: `lib/features/watch_party/party_notices.dart`
- Modify: `lib/features/watch_party/party_notice_pill.dart`
- Test: `test/features/watch_party/party_notices_test.dart`, `test/features/watch_party/party_notice_pill_test.dart`

- [ ] **Step 1: testi**

In `l10n/app_it.arb`, in fondo, prima della `}` finale: metti la virgola dopo l'ultima voce attuale (`"@inboxMore": …`) e aggiungi tutti i testi del piano 14a.

```json
  "playerPreviousEpisode": "Episodio precedente",
  "playerPreviousInQueue": "Titolo precedente",
  "playerNextInQueue": "Titolo successivo",
  "playerNextInQueueTitle": "Prossimo nella coda",
  "watchPartyNoticePrevious": "Precedente: {title}",
  "@watchPartyNoticePrevious": {"placeholders": {"title": {"type": "String"}}},
  "watchPartyNoticePreviousBy": "{name} ha avviato il precedente: {title}",
  "@watchPartyNoticePreviousBy": {"placeholders": {"name": {"type": "String"}, "title": {"type": "String"}}},
  "watchPartyNoticeShuffleOn": "Ordine casuale attivato",
  "watchPartyNoticeShuffleOnBy": "{name} ha attivato l'ordine casuale",
  "@watchPartyNoticeShuffleOnBy": {"placeholders": {"name": {"type": "String"}}},
  "watchPartyNoticeShuffleOff": "Ordine casuale tolto",
  "watchPartyNoticeShuffleOffBy": "{name} ha tolto l'ordine casuale",
  "@watchPartyNoticeShuffleOffBy": {"placeholders": {"name": {"type": "String"}}},
  "partyQueueActionFailed": "Non riuscito, riprova",
  "partyQueueOpen": "Coda",
  "partyQueueTitle": "Coda",
  "partyQueueShuffle": "Ordine casuale",
  "partyQueueSummary": "{titles} · {time} dopo questo",
  "@partyQueueSummary": {"placeholders": {"titles": {"type": "String"}, "time": {"type": "String"}}},
  "partyQueueWatched": "Già visti",
  "partyQueuePlaying": "In riproduzione",
  "partyQueueUpcoming": "Prossimi",
  "partyQueueNow": "ora",
  "partyQueueMovie": "Film",
  "partyQueueRemove": "Togli dalla coda",
  "partyQueueMove": "Trascina per spostare",
  "partyQueueUnavailable": "Titolo non disponibile"
```

In `l10n/app_en.arb`, allo stesso modo (virgola dopo `"inboxMore": …`):

```json
  "playerPreviousEpisode": "Previous episode",
  "playerPreviousInQueue": "Previous title",
  "playerNextInQueue": "Next title",
  "playerNextInQueueTitle": "Next in the queue",
  "watchPartyNoticePrevious": "Previous: {title}",
  "watchPartyNoticePreviousBy": "{name} went back to: {title}",
  "watchPartyNoticeShuffleOn": "Shuffle on",
  "watchPartyNoticeShuffleOnBy": "{name} turned shuffle on",
  "watchPartyNoticeShuffleOff": "Shuffle off",
  "watchPartyNoticeShuffleOffBy": "{name} turned shuffle off",
  "partyQueueActionFailed": "That didn't work, try again",
  "partyQueueOpen": "Queue",
  "partyQueueTitle": "Queue",
  "partyQueueShuffle": "Shuffle",
  "partyQueueSummary": "{titles} · {time} after this one",
  "partyQueueWatched": "Watched",
  "partyQueuePlaying": "Now playing",
  "partyQueueUpcoming": "Up next",
  "partyQueueNow": "now",
  "partyQueueMovie": "Movie",
  "partyQueueRemove": "Remove from the queue",
  "partyQueueMove": "Drag to move",
  "partyQueueUnavailable": "Title not available"
```

Run: `flutter gen-l10n` → nessun errore.

- [ ] **Step 2: test che falliscono**

In `party_notices_test.dart`, in fondo a `main`:

```dart
  group('coda del party (spec H §10)', () {
    test('precedente: titolo dell\'episodio e nome dall\'annuncio giusto', () {
      fakeAsync((async) {
        library.itemsById['e4'] = testItem(
            id: 'e4',
            name: 'Pilot',
            kind: ItemKind.episode,
            seriesName: 'Breaking Bad',
            index: 4,
            seasonIndex: 1);
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue(playingIndex: 1)));
        notices()
          ..attribute(testActionEvent(PartyAction.nextItem, userName: 'Mario'))
          ..attribute(testActionEvent(PartyAction.previousItem));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'PreviousItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.previousItem);
        expect(current()?.title, 'S1:E4 · Pilot');
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('salto dalla coda: "Si guarda" con il nome di SetCurrentItem', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices()
          ..attribute(testActionEvent(PartyAction.newQueue, userName: 'Mario'))
          ..attribute(testActionEvent(PartyAction.setCurrentItem));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    playingIndex: 1,
                    reason: 'SetCurrentItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.nowWatching);
        expect(current()?.title, 'Breaking Bad');
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('successivo verso un film: il titolo del film, non l\'anno', () {
      fakeAsync((async) {
        mount(async);
        emit(async,
            PlayQueueUpdate('g1', testSeriesQueue(itemIds: ['e4', 'm2'])));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    itemIds: ['e4', 'm2'],
                    playingIndex: 1,
                    reason: 'NextItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.nextEpisode);
        expect(current()?.title, 'Arrival');
        finish(async);
      });
    });

    test('ordine casuale degli altri: acceso, poi spento', () {
      fakeAsync((async) {
        mount(async);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    shuffled: true,
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.shuffleOn);
        async.elapse(PartyNotices.showFor);
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 10))));
        expect(current()?.kind, PartyNoticeKind.shuffleOff);
        finish(async);
      });
    });

    test('ordine casuale: il nome dall\'annuncio ShuffleMode', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices().attribute(testActionEvent(PartyAction.shuffleMode));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    shuffled: true,
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.shuffleOn);
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('il mio ordine casuale: nessun avviso, anche con l\'eco dopo 3 s',
        () {
      fakeAsync((async) {
        mount(async);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices().mine(PartyNoticeKind.shuffleOn, show: false);
        async.elapse(const Duration(milliseconds: 3500));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    shuffled: true,
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current(), isNull);
        finish(async);
      });
    });

    test('prima coda già mescolata, rimozioni e spostamenti: nessun avviso',
        () {
      fakeAsync((async) {
        mount(async);
        emit(async,
            PlayQueueUpdate('g1', testSeriesQueue(shuffled: true)));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    itemIds: ['e4', 'e5'],
                    shuffled: true,
                    reason: 'RemoveItems',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    itemIds: ['e4', 'e5'],
                    shuffled: true,
                    reason: 'MoveItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 10))));
        expect(current(), isNull);
        finish(async);
      });
    });
  });
```

In `party_notice_pill_test.dart`, in fondo a `main` (`l` è il `lookupAppLocalizations(const Locale('it'))` del file; se il file lo chiama in un altro modo, usa quello):

```dart
  test('avvisi della coda (spec H §10)', () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect(
        partyNoticeText(l,
            const PartyNotice(PartyNoticeKind.previousItem, title: 'S1:E4 · Pilot')),
        'Precedente: S1:E4 · Pilot');
    expect(
        partyNoticeText(
            l,
            const PartyNotice(PartyNoticeKind.previousItem,
                title: 'S1:E4 · Pilot', name: 'Luigi')),
        'Luigi ha avviato il precedente: S1:E4 · Pilot');
    expect(partyNoticeText(l, const PartyNotice(PartyNoticeKind.shuffleOn)),
        'Ordine casuale attivato');
    expect(
        partyNoticeText(
            l, const PartyNotice(PartyNoticeKind.shuffleOff, name: 'Luigi')),
        'Luigi ha tolto l\'ordine casuale');
    expect(
        partyNoticeText(
            l, const PartyNotice(PartyNoticeKind.queueFailed, mine: true)),
        'Non riuscito, riprova');
    expect(partyNoticeIcon(PartyNoticeKind.previousItem), LucideIcons.skipBack);
    expect(partyNoticeIcon(PartyNoticeKind.shuffleOn), LucideIcons.shuffle);
    expect(partyNoticeIcon(PartyNoticeKind.queueFailed), LucideIcons.circleAlert);
  });
```

Aggiungi gli import che mancano: `package:flutter/widgets.dart` per `Locale`, `package:lucide_icons_flutter/lucide_icons.dart`, `package:wonderflix/l10n/gen/app_localizations.dart`.

- [ ] **Step 3: i test falliscono**

Run: `flutter test test/features/watch_party/party_notices_test.dart test/features/watch_party/party_notice_pill_test.dart`
Expected: FAIL, tipi di avviso non definiti.

- [ ] **Step 4: implementazione**

In `party_notices.dart`:

1. Aggiungi l'import `import '../../core/jellyfin/item_models.dart';`.
2. In `PartyNoticeKind`, dopo `inviteRateLimited`:

```dart
  /// Il gruppo è tornato al titolo prima (spec H §10), in `title`.
  previousItem,

  /// Ordine casuale acceso da qualcuno.
  shuffleOn,

  /// Ordine casuale spento da qualcuno.
  shuffleOff,

  /// Un comando della coda non è arrivato al server (solo per chi agisce).
  queueFailed,
```

3. In `PartyNotices`, dopo `announcementLifetime`:

```dart
  /// Le proprie azioni sulla coda (spec H §10): l'eco può arrivare più tardi
  /// di quella delle pause (per le aggiunte, fino alla conferma).
  static const queueEchoWindow = Duration(seconds: 4);

  static const _queueEchoKinds = {
    PartyNoticeKind.shuffleOn,
    PartyNoticeKind.shuffleOff,
  };

  static Duration _echoWindowOf(PartyNoticeKind kind) =>
      _queueEchoKinds.contains(kind) ? queueEchoWindow : echoWindow;
```

4. Dopo il campo `String? _playing;` aggiungi:

```dart
  /// Ordine casuale dell'ultima coda vista; `null` prima della prima.
  bool? _shuffled;
```

   Valorizzalo dove si valorizza `_playing`:
   - in `build`: `_shuffled = party.queue?.shuffled;`
   - nel `ref.listen` dell'ingresso: `_shuffled = joined.queue?.shuffled;`
   - in `_clear`: `_shuffled = null;`

5. In `_isEcho`, la pulizia usa la finestra del tipo:

```dart
    _echoes.removeWhere(
        (echo) => now.difference(echo.at) > _echoWindowOf(echo.kind));
```

6. `_showOthers` riceve l'azione da chi chiama: `null` vuol dire che l'avviso non aspetta un nome.

```dart
  /// Avviso di un'azione altrui (spec E §8): con il nome se l'annuncio di
  /// [action] è già arrivato; altrimenti, con il canale attivo, lo aspetta
  /// al massimo [attributionWait]. Senza [action] esce subito.
  void _showOthers(PartyNotice notice, PartyAction? action) {
    if (action == null) {
      show(notice);
      return;
    }
    final name = _takeAnnouncement(action);
    if (name != null) {
      show(notice.withName(name));
    } else if (!_attribution) {
      show(notice);
    } else {
      final waiting = _WaitingNotice(notice, action);
      waiting.timer = Timer(attributionWait, () {
        _waiting.remove(waiting);
        show(waiting.notice);
      });
      _waiting.add(waiting);
    }
  }
```

   In `_onUpdate` (ramo `GroupStateUpdate`) le due chiamate diventano `_showOthers(PartyNotice(kind, position: position), _actionOf(kind));` e `_showOthers(PartyNotice(kind), _actionOf(kind));`.

   In `_actionOf` togli le righe di `nextEpisode` e `nowWatching`: restano pausa, ripresa e salto.

7. `_onQueue` e `_announce` diventano:

```dart
  void _onQueue(PlayQueue queue) {
    final entry = queue.playing;
    final previous = _playing;
    final wasShuffled = _shuffled;
    _playing = entry?.playlistItemId;
    _shuffled = queue.shuffled;
    // Ordine casuale acceso o spento da qualcuno (spec H §10); la prima coda
    // dopo l'ingresso non è un cambio. L'elemento in corso resta lui.
    if (queue.reason == 'ShuffleMode') {
      if (wasShuffled == null || wasShuffled == queue.shuffled) return;
      final kind = queue.shuffled
          ? PartyNoticeKind.shuffleOn
          : PartyNoticeKind.shuffleOff;
      if (!_isEcho(kind)) {
        _showOthers(PartyNotice(kind), PartyAction.shuffleMode);
      }
      return;
    }
    if (entry == null || previous == null || previous == entry.playlistItemId) {
      return;
    }
    // Il nome viene dall'annuncio dell'azione che ha cambiato titolo; un
    // cambio per un altro motivo (per esempio una rimozione del titolo in
    // corso da un altro client) resta senza nome.
    final (kind, action) = switch (queue.reason) {
      'NextItem' => (PartyNoticeKind.nextEpisode, PartyAction.nextItem),
      'PreviousItem' => (PartyNoticeKind.previousItem, PartyAction.previousItem),
      'SetCurrentItem' => (
          PartyNoticeKind.nowWatching,
          PartyAction.setCurrentItem
        ),
      'NewPlaylist' => (PartyNoticeKind.nowWatching, PartyAction.newQueue),
      _ => (PartyNoticeKind.nowWatching, null),
    };
    unawaited(_announce(kind, entry.itemId, action));
  }

  Future<void> _announce(
      PartyNoticeKind kind, String itemId, PartyAction? action) async {
    try {
      final item = await ref
          .read(libraryApiProvider)
          .item(ref.read(currentUserIdProvider), itemId);
      if (!ref.mounted) return;
      // Nel frattempo si è usciti dal gruppo o si guarda già altro.
      final party = ref.read(watchPartySessionProvider);
      if (!party.inGroup || party.queue?.playing?.itemId != itemId) return;
      _showOthers(PartyNotice(kind, title: _noticeTitle(kind, item)), action);
    } on Object catch (error) {
      _log.info('titolo per l\'avviso non disponibile: $error');
    }
  }

  /// Successivo e precedente: l'episodio ("S1:E5 · Titolo") o il film. Un
  /// titolo nuovo: la serie o il film.
  static String _noticeTitle(PartyNoticeKind kind, JellyfinItem item) {
    final step = kind == PartyNoticeKind.nextEpisode ||
        kind == PartyNoticeKind.previousItem;
    return step && item.kind == ItemKind.episode
        ? cardSubtitle(item) ?? item.name
        : cardTitle(item);
  }
```

In `party_notice_pill.dart`, nello `switch` di `partyNoticeText`, dopo `inviteRateLimited`:

```dart
    PartyNoticeKind.previousItem => by != null
        ? l.watchPartyNoticePreviousBy(by, title)
        : l.watchPartyNoticePrevious(title),
    PartyNoticeKind.shuffleOn => by != null
        ? l.watchPartyNoticeShuffleOnBy(by)
        : l.watchPartyNoticeShuffleOn,
    PartyNoticeKind.shuffleOff => by != null
        ? l.watchPartyNoticeShuffleOffBy(by)
        : l.watchPartyNoticeShuffleOff,
    PartyNoticeKind.queueFailed => l.partyQueueActionFailed,
```

In `partyNoticeIcon`:
- `PartyNoticeKind.previousItem => LucideIcons.skipBack,`
- `PartyNoticeKind.shuffleOn || PartyNoticeKind.shuffleOff => LucideIcons.shuffle,`
- `queueFailed` si aggiunge al gruppo di `inviteFailed || inviteRateLimited` (`LucideIcons.circleAlert`).

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/watch_party`
Expected: PASS. Anche i test esistenti degli avvisi: `NewPlaylist` → "Si guarda" con il nome di `NewQueue`, `NextItem` → "Episodio successivo".

- [ ] **Step 6: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add l10n lib/features/watch_party/party_notices.dart lib/features/watch_party/party_notice_pill.dart test/features/watch_party/party_notices_test.dart test/features/watch_party/party_notice_pill_test.dart
git commit -m "feat(party): queue notices for previous, jump and shuffle"
```

### Task 9: `PartyQueueEditor`

**Files:**
- Create: `lib/features/watch_party/party_queue_editor.dart`
- Test: `test/features/watch_party/party_queue_editor_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/features/watch_party/party_queue_editor_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/features/watch_party/party_queue_editor.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakePartyChannelApi channelApi;
  late FakePartyNotices notices;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeSyncPlayApi();
    channelApi = FakePartyChannelApi();
    notices = FakePartyNotices();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  void emit(FakeAsync async, PlayQueue queue) {
    events.add(SyncPlayGroupUpdated(PlayQueueUpdate('g1', queue)));
    async.flushMicrotasks();
  }

  /// Nel gruppo, con la coda e3 (p1, già visto), e4 (p2, in riproduzione),
  /// e5 (p3), e6 (p4). Con [queueFeature] il plugin è il 1.3.0.
  void mount(FakeAsync async, {bool queueFeature = true}) {
    channelApi.install(
        version: '1.3.0',
        features: queueFeature ? const {partyQueueFeature} : const {});
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      partyChannelApiProvider.overrideWithValue(channelApi),
      partyNoticesProvider.overrideWith(() => notices),
    ]);
    container.listen(partyChannelProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    async.flushMicrotasks();
    emit(
        async,
        testSeriesQueue(
            itemIds: const ['e3', 'e4', 'e5', 'e6'], playingIndex: 1));
    api.calls.clear();
  }

  void finish(FakeAsync async) {
    container.dispose();
    async.flushMicrotasks();
  }

  PartyQueueEditor editor() => container.read(partyQueueEditorProvider);

  List<Object?> announced() => [
        for (final event in channelApi.sent)
          if (event is PartyOutgoingAction) event.action.wire,
      ];

  test('salto: solo verso un altro elemento della coda, annunciato', () {
    fakeAsync((async) {
      mount(async);
      unawaited(editor().jumpTo('p4'));
      unawaited(editor().jumpTo('p2'));
      unawaited(editor().jumpTo('p9'));
      async.flushMicrotasks();
      expect(api.calls, ['set-item p4']);
      expect(announced(), ['SetCurrentItem']);
      finish(async);
    });
  });

  test('rimozione: mai l\'elemento in riproduzione, senza annuncio', () {
    fakeAsync((async) {
      mount(async);
      unawaited(editor().remove('p3'));
      unawaited(editor().remove('p1'));
      unawaited(editor().remove('p2'));
      unawaited(editor().remove('p9'));
      async.flushMicrotasks();
      expect(api.calls, ['remove p3', 'remove p1']);
      expect(announced(), isEmpty);
      finish(async);
    });
  });

  test('spostamento: solo tra i prossimi, con l\'indice del server', () {
    fakeAsync((async) {
      mount(async);
      unawaited(editor().move('p4', 0));
      unawaited(editor().move('p3', 0));
      unawaited(editor().move('p1', 0));
      unawaited(editor().move('p4', 2));
      async.flushMicrotasks();
      expect(api.calls, ['move p4 2'],
          reason: 'p3 è già lì, p1 è già visto, 2 è fuori dai prossimi');
      expect(announced(), isEmpty);
      finish(async);
    });
  });

  test('ordine casuale: solo se cambia; la propria eco non fa avvisi', () {
    fakeAsync((async) {
      mount(async);
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls, isEmpty, reason: '"ordinato" su una coda ordinata: 500');

      unawaited(editor().setShuffle(true));
      async.flushMicrotasks();
      expect(api.calls, ['shuffle on']);
      expect(notices.hiddenMineCalls, [PartyNoticeKind.shuffleOn]);
      expect(announced(), ['ShuffleMode']);

      emit(
          async,
          testSeriesQueue(
              itemIds: const ['e4', 'e6', 'e3', 'e5'],
              shuffled: true,
              reason: 'ShuffleMode',
              lastUpdate: DateTime.utc(2026, 9, 30, 10, 5)));
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls.last, 'shuffle off');
      expect(notices.hiddenMineCalls.last, PartyNoticeKind.shuffleOff);
      finish(async);
    });
  });

  test('plugin senza la funzione queue: comandi sì, annunci no', () {
    fakeAsync((async) {
      mount(async, queueFeature: false);
      unawaited(editor().jumpTo('p3'));
      unawaited(editor().setShuffle(true));
      async.flushMicrotasks();
      expect(api.calls, ['set-item p3', 'shuffle on']);
      expect(announced(), isEmpty);
      finish(async);
    });
  });

  test('richiesta fallita: avviso "Non riuscito", niente annuncio', () {
    fakeAsync((async) {
      mount(async);
      api.error = const ServerUnreachableException();
      unawaited(editor().jumpTo('p3'));
      async.flushMicrotasks();
      expect(notices.shown.last.kind, PartyNoticeKind.queueFailed);
      expect(announced(), isEmpty);
      finish(async);
    });
  });

  test('fuori dal gruppo: niente', () {
    fakeAsync((async) {
      mount(async);
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      api.calls.clear();
      unawaited(editor().jumpTo('p3'));
      unawaited(editor().remove('p3'));
      unawaited(editor().setShuffle(true));
      async.flushMicrotasks();
      expect(api.calls, isEmpty);
      finish(async);
    });
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/watch_party/party_queue_editor_test.dart`
Expected: FAIL, file non trovato.

- [ ] **Step 3: implementazione**

Crea `lib/features/watch_party/party_queue_editor.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/party_channel/party_channel_models.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../../core/syncplay/syncplay_models.dart';
import 'party_channel.dart';
import 'party_notices.dart';
import 'party_queue_rules.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

/// Comandi sulla coda del gruppo (spec H §8.3): salto, rimozione,
/// spostamento, ordine casuale. Lavorano sempre sulla coda **attuale**: fuori
/// da un gruppo, o con un elemento non più nella coda, non fanno nulla. Una
/// richiesta non riuscita dà l'avviso "Non riuscito, riprova" (spec H §10).
class PartyQueueEditor {
  PartyQueueEditor(this._ref);

  final Ref _ref;

  PlayQueue? get _queue {
    final party = _ref.read(watchPartySessionProvider);
    return party.inGroup ? party.queue : null;
  }

  /// Il gruppo passa a [playlistItemId], da 0; annunciato agli altri.
  Future<void> jumpTo(String playlistItemId) async {
    final queue = _queue;
    if (queue == null ||
        queue.playing?.playlistItemId == playlistItemId ||
        !_contains(queue, playlistItemId)) {
      return;
    }
    // Il canale si prende prima dell'attesa: nel frattempo il player può
    // chiudersi.
    final channel = _ref.read(partyChannelProvider.notifier);
    if (await _send('salto nella coda',
        (api) => api.setPlaylistItem(playlistItemId))) {
      channel.announce(PartyAction.setCurrentItem);
    }
  }

  /// Toglie [playlistItemId] dalla coda: mai quello in riproduzione (spec H
  /// §3). Nessun avviso.
  Future<void> remove(String playlistItemId) async {
    final queue = _queue;
    if (queue == null ||
        queue.playing?.playlistItemId == playlistItemId ||
        !_contains(queue, playlistItemId)) {
      return;
    }
    await _send('rimozione dalla coda',
        (api) => api.removeFromPlaylist(playlistItemId));
  }

  /// Porta il prossimo [playlistItemId] alla posizione [upcomingIndex] tra i
  /// prossimi (contata dopo averlo tolto). Nessun avviso.
  Future<void> move(String playlistItemId, int upcomingIndex) async {
    final queue = _queue;
    if (queue == null) return;
    final upcoming = partyQueueSections(queue).upcoming;
    final from =
        upcoming.indexWhere((entry) => entry.playlistItemId == playlistItemId);
    if (from < 0 ||
        upcomingIndex < 0 ||
        upcomingIndex >= upcoming.length ||
        upcomingIndex == from) {
      return;
    }
    await _send(
        'spostamento nella coda',
        (api) => api.movePlaylistItem(
            playlistItemId, partyQueueMoveIndex(queue, upcomingIndex)));
  }

  /// Ordine casuale acceso o spento, solo se cambia: `Sorted` su una coda già
  /// ordinata fa rispondere 500 al server (spec H §3).
  Future<void> setShuffle(bool shuffle) async {
    final queue = _queue;
    if (queue == null || queue.shuffled == shuffle) return;
    final channel = _ref.read(partyChannelProvider.notifier);
    // La coda che torna dal server è nostra: niente avviso (spec H §10).
    _ref.read(partyNoticesProvider.notifier).mine(
        shuffle ? PartyNoticeKind.shuffleOn : PartyNoticeKind.shuffleOff,
        show: false);
    if (await _send(
        'ordine casuale', (api) => api.setShuffleMode(shuffle: shuffle))) {
      channel.announce(PartyAction.shuffleMode);
    }
  }

  bool _contains(PlayQueue queue, String playlistItemId) =>
      queue.entries.any((entry) => entry.playlistItemId == playlistItemId);

  /// `true` se [request] è arrivata al server.
  Future<bool> _send(
      String what, Future<void> Function(SyncPlayApi api) request) async {
    final api = _ref.read(watchPartySessionProvider.notifier).api;
    final notices = _ref.read(partyNoticesProvider.notifier);
    try {
      await request(api);
      return true;
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.warning('$what non riuscito: ${error.runtimeType}');
      notices.show(const PartyNotice(PartyNoticeKind.queueFailed, mine: true));
      return false;
    }
  }
}

final partyQueueEditorProvider =
    Provider<PartyQueueEditor>(PartyQueueEditor.new);
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/watch_party/party_queue_editor_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/watch_party/party_queue_editor.dart test/features/watch_party/party_queue_editor_test.dart
git commit -m "feat(party): add the queue editor"
```

### Task 10: dettagli dei titoli in coda

**Files:**
- Create: `lib/features/watch_party/party_queue_items.dart`
- Test: `test/features/watch_party/party_queue_items_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/features/watch_party/party_queue_items_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/watch_party/party_queue_items.dart';
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
    library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(id: 'e4', name: 'Pilot')
      ..itemsById['e5'] = testItem(id: 'e5', name: 'Cat');
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
    container.listen(partyQueueItemsProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    async.flushMicrotasks();
  }

  void emit(FakeAsync async, PlayQueue queue) {
    events.add(SyncPlayGroupUpdated(PlayQueueUpdate('g1', queue)));
    async.flushMicrotasks();
  }

  Map<String, Object?> items() => container.read(partyQueueItemsProvider);

  test('i titoli in coda si chiedono insieme; i mancanti valgono null', () {
    fakeAsync((async) {
      mount(async);
      emit(async, testSeriesQueue());
      expect(library.itemsByIdsCalls, [
        ['e4', 'e5', 'e6'],
      ]);
      expect(items().keys, ['e4', 'e5', 'e6']);
      expect(items()['e6'], isNull, reason: 'e6 non è nella libreria');

      // Solo gli id nuovi.
      emit(
          async,
          testSeriesQueue(
              itemIds: const ['e4', 'e5', 'e6', 'e7'],
              lastUpdate: DateTime.utc(2026, 9, 30, 10, 5)));
      expect(library.itemsByIdsCalls.last, ['e7']);
      container.dispose();
    });
  });

  test('richiesta fallita: si riprova al prossimo aggiornamento', () {
    fakeAsync((async) {
      mount(async);
      library.error = const ServerUnreachableException();
      emit(async, testSeriesQueue());
      expect(items(), isEmpty);
      library.error = null;
      emit(async,
          testSeriesQueue(lastUpdate: DateTime.utc(2026, 9, 30, 10, 5)));
      expect(library.itemsByIdsCalls.last, ['e4', 'e5', 'e6']);
      expect(items().keys, ['e4', 'e5', 'e6']);
      container.dispose();
    });
  });

  test('uscita dal gruppo: la mappa si svuota', () {
    fakeAsync((async) {
      mount(async);
      emit(async, testSeriesQueue());
      expect(items(), isNotEmpty);
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      expect(items(), isEmpty);
      container.dispose();
    });
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/watch_party/party_queue_items_test.dart`
Expected: FAIL, file non trovato.

- [ ] **Step 3: implementazione**

Crea `lib/features/watch_party/party_queue_items.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/item_models.dart';
import '../library/library_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Dettagli dei titoli nella coda del gruppo (spec H §8.5), per `ItemId`:
/// assente = in arrivo, `null` = non disponibile (cancellato, o non più
/// visibile). Gli id nuovi si chiedono tutti insieme con `itemsByIds` (sono
/// al massimo 100); la mappa si svuota all'uscita dal gruppo.
class PartyQueueItems extends Notifier<Map<String, JellyfinItem?>> {
  /// Id chiesti e non ancora arrivati.
  final _requested = <String>{};

  /// Cambia all'uscita dal gruppo: una risposta arrivata dopo non vale più.
  int _generation = 0;

  @override
  Map<String, JellyfinItem?> build() {
    _requested.clear();
    final generation = ++_generation;
    ref.listen(watchPartySessionProvider, (_, party) => _sync(party));
    // La coda può esserci già (il player si apre a gruppo avviato): la si
    // legge dopo la costruzione, quando lo stato si può cambiare.
    scheduleMicrotask(() {
      if (ref.mounted && generation == _generation) {
        _sync(ref.read(watchPartySessionProvider));
      }
    });
    return const {};
  }

  void _sync(WatchPartyState party) {
    if (!party.inGroup) {
      _requested.clear();
      _generation++;
      if (state.isNotEmpty) state = const {};
      return;
    }
    final queue = party.queue;
    if (queue == null) return;
    final missing = {
      for (final entry in queue.entries)
        if (!state.containsKey(entry.itemId) &&
            !_requested.contains(entry.itemId))
          entry.itemId,
    }.toList();
    if (missing.isEmpty) return;
    _requested.addAll(missing);
    unawaited(_fetch(missing, _generation));
  }

  Future<void> _fetch(List<String> ids, int generation) async {
    try {
      final items = await ref
          .read(libraryApiProvider)
          .itemsByIds(ref.read(currentUserIdProvider), ids);
      if (!ref.mounted || generation != _generation) return;
      final byId = {for (final item in items) _normalizeId(item.id): item};
      _requested.removeAll(ids);
      state = {
        ...state,
        for (final id in ids) id: byId[_normalizeId(id)],
      };
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      _log.info('dettagli della coda non disponibili: ${error.runtimeType}');
      // Al prossimo aggiornamento della coda si riprova.
      _requested.removeAll(ids);
    }
  }
}

final partyQueueItemsProvider =
    NotifierProvider<PartyQueueItems, Map<String, JellyfinItem?>>(
        PartyQueueItems.new);
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/watch_party/party_queue_items_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/watch_party/party_queue_items.dart test/features/watch_party/party_queue_items_test.dart
git commit -m "feat(party): load the details of the queued titles"
```

---

## Gruppo D — player: precedente e post-play

### Task 11: ⏮ "precedente" (da soli; nel gruppo il comando c'è già)

**Files:**
- Modify: `lib/core/media_session/media_session.dart`, `mirrored_media_session.dart`, `smtc_media_session.dart`
- Modify: `lib/features/discord/discord_presence.dart`
- Modify: `lib/features/player/player_commands.dart`
- Modify: `lib/features/player/player_controller.dart`
- Modify: `lib/features/player/player_overlay.dart`
- Modify: `lib/features/player/player_screen.dart`
- Modify: `test/support/playback_fakes.dart`
- Test: `test/core/media_session/mirrored_media_session_test.dart`, `test/features/player/player_commands_test.dart`, `player_controller_test.dart`, `player_overlay_test.dart`, `player_screen_test.dart`

- [ ] **Step 1: test che falliscono**

`mirrored_media_session_test.dart`, primo test:
- dopo `await session.setNextEnabled(true);` aggiungi `await session.setPreviousEnabled(false);`;
- nel `for` aggiungi `expect(s.previousEnabled, [false]);`.

`player_commands_test.dart`, in fondo a `main`:

```dart
  test('P e il tasto multimediale "indietro": precedente (spec H §9.1)', () {
    expect(playerCommandFor(down(LogicalKeyboardKey.keyP)),
        PlayerCommand.previous);
    expect(playerCommandFor(down(LogicalKeyboardKey.mediaTrackPrevious)),
        PlayerCommand.previous);
    expect(isMediaKey(LogicalKeyboardKey.mediaTrackPrevious), isTrue);
    expect(
        playerCommandFor(down(LogicalKeyboardKey.mediaTrackPrevious),
            mediaKeys: false),
        isNull,
        reason: 'lo riceve già la sessione media di sistema');
    expect(playerCommandFor(repeat(LogicalKeyboardKey.keyP)), isNull);
  });
```

`player_controller_test.dart`, dopo `segmenti ed episodio successivo caricati dopo la partenza`:

```dart
  test('episodio precedente caricato dopo la partenza (spec H §8.4)',
      () async {
    library.itemsById['m1'] =
        testItem(id: 'm1', kind: ItemKind.episode, seriesId: 's1');
    library.previousEpisodes['m1'] =
        testItem(id: 'm0', kind: ItemKind.episode, seriesId: 's1');
    await start();
    expect(view().previousEpisode?.id, 'm0');
    expect(library.previousEpisodeCalls, ['m1']);
  });
```

Nel test `film: nessun episodio successivo; segmenti non disponibili ignorati` aggiungi:

```dart
    expect(view().previousEpisode, isNull);
    expect(library.previousEpisodeCalls, isEmpty);
```

`player_overlay_test.dart`:
- nel test `senza episodio successivo: nessun pulsante` aggiungi `expect(find.byTooltip('Episodio precedente'), findsNothing);`;
- in fondo a `main`:

```dart
  testWidgets('precedente prima di successivo; nel watch party si parla di '
      'titoli (spec H §9.1)', (tester) async {
    final calls = <String>[];
    Future<void> pump({required bool partyQueue}) => pumpApp(
          tester,
          Scaffold(
            body: PlayerOverlay(
              view: const PlayerViewState(status: PlayerStatus.ready),
              engine: FakeVideoEngine(),
              fullscreen: false,
              onBack: () {},
              onTogglePlay: () {},
              onSeekBy: (_) {},
              onSeekTo: (_) {},
              onVolume: (_) {},
              onToggleMute: () {},
              onToggleTracks: () {},
              onToggleFullscreen: () {},
              onPrevious: () => calls.add('previous'),
              onNextEpisode: () => calls.add('next'),
              partyQueue: partyQueue,
            ),
          ),
        );
    await pump(partyQueue: false);
    await tester.tap(find.byTooltip('Episodio precedente'));
    await tester.tap(find.byTooltip('Episodio successivo'));
    expect(
        tester.getCenter(find.byTooltip('Episodio precedente')).dx,
        lessThan(tester.getCenter(find.byTooltip('Episodio successivo')).dx));
    await pump(partyQueue: true);
    await tester.tap(find.byTooltip('Titolo precedente'));
    await tester.tap(find.byTooltip('Titolo successivo'));
    expect(calls, ['previous', 'next', 'previous', 'next']);
  });
```

`player_screen_test.dart`, dopo `withNextEpisode`:

```dart
  JellyfinItem episode3({int positionTicks = 0}) => testItem(
        id: 'e3',
        name: 'The Cat',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 3,
        seasonIndex: 1,
        positionTicks: positionTicks,
        playedPercentage: positionTicks > 0 ? 10 : null,
      );

  void withPreviousEpisode({int positionTicks = 0}) {
    final previous = episode3(positionTicks: positionTicks);
    library.itemsById['e3'] = previous;
    library.previousEpisodes['e4'] = previous;
  }
```

E in fondo a `main`:

```dart
  testWidgets('episodio precedente (spec H §9.1): pulsante, da dove era',
      (tester) async {
    withPreviousEpisode(
        positionTicks: durationToTicks(const Duration(minutes: 5)));
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Episodio precedente'));
    await tester.pumpAndSettle();
    expect(find.text('S1:E3 · The Cat'), findsOneWidget);
    expect(engines, hasLength(2));
    expect(engines.last.opened.single.start, const Duration(minutes: 5));
    expect(library.playedCalls, isEmpty,
        reason: 'tornando indietro non si segna come visto');
    await unmount(tester);
  });

  testWidgets('senza episodio precedente: né pulsante né tasto P',
      (tester) async {
    await pumpPlayer(tester);
    expect(find.byTooltip('Episodio precedente'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(engines, hasLength(1));
    await unmount(tester);
  });

  testWidgets('P a schermo intero: il precedente resta a schermo intero',
      (tester) async {
    withPreviousEpisode();
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(find.text('S1:E3 · The Cat'), findsOneWidget);
    expect(window.fullScreenCalls, [true], reason: 'mai uscito');
    await unmount(tester);
  });

  testWidgets('pannello media: "precedente" solo se c\'è un episodio prima',
      (tester) async {
    withPreviousEpisode();
    await pumpPlayer(tester);
    expect(mediaSession.previousEnabled.last, isTrue);
    mediaSession.press(MediaButton.previous);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('S1:E3 · The Cat'), findsOneWidget);
    expect(mediaSession.previousEnabled.last, isFalse,
        reason: 'e3 non ha un episodio prima');
    await unmount(tester);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/media_session test/features/player`
Expected: FAIL, membri non definiti.

- [ ] **Step 3: sessione media**

In `media_session.dart`:
- l'enum diventa `enum MediaButton { play, pause, next, previous, stop }`;
- in `MediaSession`, dopo `setNextEnabled`:

```dart
  /// Pulsante "precedente" del pannello (spec H §9.1).
  Future<void> setPreviousEnabled(bool enabled);
```

- in `NoopMediaSession`:

```dart
  @override
  Future<void> setPreviousEnabled(bool enabled) async {}
```

In `mirrored_media_session.dart`, dopo `setNextEnabled`:

```dart
  @override
  Future<void> setPreviousEnabled(bool enabled) =>
      _all((s) => s.setPreviousEnabled(enabled));
```

In `smtc_media_session.dart`:
- dopo `setNextEnabled`:

```dart
  @override
  Future<void> setPreviousEnabled(bool enabled) =>
      _run(() => _smtc.setIsPrevEnabled(enabled));
```

- in `_button` aggiungi `PressedButton.previous => MediaButton.previous,`.

In `discord_presence.dart`, dopo `setNextEnabled`:

```dart
  @override
  Future<void> setPreviousEnabled(bool enabled) async {}
```

In `test/support/playback_fakes.dart`, in `FakeMediaSession`:
- campo `final previousEnabled = <bool>[];`;
- metodo:

```dart
  @override
  Future<void> setPreviousEnabled(bool enabled) async =>
      previousEnabled.add(enabled);
```

- [ ] **Step 4: tasti**

In `player_commands.dart`:

```dart
  nextEpisode,

  /// Titolo o episodio precedente (spec H §9.1).
  previous,
```

- nella mappa `_commands`, dopo `mediaTrackNext`:

```dart
  LogicalKeyboardKey.keyP: PlayerCommand.previous,
  LogicalKeyboardKey.mediaTrackPrevious: PlayerCommand.previous,
```

- in `_mediaKeys` aggiungi `LogicalKeyboardKey.mediaTrackPrevious,`;
- nel commento di `isMediaKey` e di `_mediaKeys` "(play/pausa, successivo, stop)" diventa "(play/pausa, successivo, precedente, stop)".

- [ ] **Step 5: episodio precedente nel controller**

In `player_controller.dart`, `PlayerViewState`:
- costruttore `this.previousEpisode,`;
- campo:

```dart
  /// Episodio che precede quello in riproduzione (solo per le serie).
  final JellyfinItem? previousEpisode;
```

- in `copyWith` parametro `JellyfinItem? previousEpisode,` e `previousEpisode: previousEpisode ?? this.previousEpisode,`.

In `_loadExtras`, accanto a `next`:

```dart
    final previous = item.kind == ItemKind.episode && seriesId != null
        ? safely<JellyfinItem?>(
            () => _library.previousEpisode(_userId, seriesId, item.id),
            null,
            'episodio precedente')
        : Future<JellyfinItem?>.value();
```

E in fondo:

```dart
    final loadedSegments = await segments;
    final loadedNext = await next;
    final loadedPrevious = await previous;
    if (_closing != null) return;
    _emit(_view.copyWith(
        segments: loadedSegments,
        nextEpisode: loadedNext,
        previousEpisode: loadedPrevious));
```

- [ ] **Step 6: pulsante nei controlli**

In `player_overlay.dart`:
- parametri `this.onPrevious,` e `this.partyQueue = false,` (dopo `this.onNextEpisode,`);
- campi:

```dart
  /// `null` se non c'è un titolo prima (spec H §9.1).
  final VoidCallback? onPrevious;

  /// Nel watch party ⏮ e ⏭ seguono la coda, che può avere anche film: i
  /// suggerimenti dicono "Titolo", non "Episodio".
  final bool partyQueue;
```

- nella riga in basso, il blocco di ⏭ diventa:

```dart
                          if (onPrevious != null)
                            PlayerIconButton(
                              icon: const Icon(LucideIcons.skipBack),
                              tooltip: partyQueue
                                  ? l.playerPreviousInQueue
                                  : l.playerPreviousEpisode,
                              onPressed: onPrevious,
                            ),
                          if (onNextEpisode != null)
                            PlayerIconButton(
                              icon: const Icon(LucideIcons.skipForward),
                              tooltip: partyQueue
                                  ? l.playerNextInQueue
                                  : l.playerNextEpisode,
                              onPressed: onNextEpisode,
                            ),
```

- [ ] **Step 7: player**

In `player_screen.dart`:

1. In `initState`, dopo `setNextEnabled(...)`:

```dart
    unawaited(_mediaSession.setPreviousEnabled(
        party != null && party.inGroup && party.hasPrevious));
```

2. Dopo `_requestNextInParty`:

```dart
  /// Torna al titolo precedente (spec H §9.1). Nel gruppo lo chiede al
  /// gruppo; da soli apre l'episodio prima, da dove era rimasto, senza
  /// segnare come visto quello che si lascia.
  void _playPrevious() {
    if (_inParty) {
      if (!_leaving) {
        // Come per il successivo: un `Seek` in sospeso salterebbe
        // nell'elemento nuovo.
        _authority?.cancelPendingSeek();
        unawaited(_requestPreviousInParty(widget.args.party!));
      }
      return;
    }
    final previous =
        ref.read(playerControllerProvider(widget.args)).previousEpisode;
    if (previous == null || _leaving) return;
    _leaving = true;
    _handingOver = true;
    unawaited(_controller.close());
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    final userData =
        ref.read(userDataOverridesProvider)[previous.id] ?? previous.userData;
    final action = primaryActionFor(previous, userData);
    final start = action is ResumeAction ? action.position : Duration.zero;
    context.pushReplacement(
        playerRoute(previous.id, start: start, fullscreen: _fullscreen),
        extra: playerReplacement);
  }

  /// Chiede al gruppo l'elemento prima di [playlistItemId] e, se la
  /// richiesta arriva al server, la annuncia agli altri (spec H §10).
  Future<void> _requestPreviousInParty(String playlistItemId) async {
    final channel = ref.read(partyChannelProvider.notifier);
    final requested = await ref
        .read(watchPartySessionProvider.notifier)
        .previousItem(playlistItemId);
    if (requested) channel.announce(PartyAction.previousItem);
  }
```

3. In `_onMediaButton`, dopo `case MediaButton.next:`:

```dart
      case MediaButton.previous:
        _playPrevious();
```

4. In `_run`, dopo `case PlayerCommand.nextEpisode:`:

```dart
      case PlayerCommand.previous:
        _playPrevious();
```

5. In `build`, dopo il `ref.listen` di `nextEpisode != null`:

```dart
    ref.listen(provider.select((s) => s.previousEpisode != null),
        (_, hasPrevious) {
      // Nel gruppo il "precedente" segue la coda.
      if (!_inParty) unawaited(_mediaSession.setPreviousEnabled(hasPrevious));
    });
```

6. In `PlayerOverlay(...)`, dopo `onNextEpisode:`:

```dart
                        onPrevious: _inParty
                            ? null
                            : (view.previousEpisode == null
                                ? null
                                : _playPrevious),
```

   Nel Task 12 lo stesso parametro prende anche il gruppo.

- [ ] **Step 8: i test passano**

Run: `flutter test test/core/media_session test/features/player`
Expected: PASS.

- [ ] **Step 9: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/core/media_session lib/features/discord/discord_presence.dart lib/features/player test/support/playback_fakes.dart test/core/media_session test/features/player
git commit -m "feat(player): go back to the previous episode"
```

### Task 12: ⏮ nel watch party

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono**

In `party_player_test.dart`:

1. `pumpPartyPlayer` riceve `bool queueFeature = true`. `if (plugin) channelApi.install();` diventa:

```dart
    if (plugin) {
      channelApi.install(
          features: queueFeature ? const {partyQueueFeature} : const {});
    }
```

2. Nei test che cercano ⏭ **mentre si è nel gruppo**, `find.byTooltip(l.playerNextEpisode)` diventa `find.byTooltip(l.playerNextInQueue)`. Sono:
   - `nel watch party non c'è l'episodio successivo`;
   - `prossimo episodio: il pulsante lo chiede al gruppo`;
   - `scheda "Prossimo episodio" solo se è il prossimo della coda` (il pulsante);
   - `canale: il prossimo episodio chiesto dall'utente si annuncia`.

   Il test `gruppo chiuso dal server…` resta con `l.playerNextEpisode`: lì si è tornati da soli.
3. Dopo `queueSeries`:

```dart
  /// La coda con un elemento prima: e3 (p0), e4 (p1, in riproduzione), e5.
  PlayQueue queueWithPrevious() => PlayQueue(
        reason: 'NewPlaylist',
        lastUpdate: DateTime.utc(2026, 9, 30, 10),
        entries: const [
          PlayQueueEntry(itemId: 'e3', playlistItemId: 'p0'),
          PlayQueueEntry(itemId: 'e4', playlistItemId: 'p1'),
          PlayQueueEntry(itemId: 'e5', playlistItemId: 'p2'),
        ],
        playingIndex: 1,
        startPosition: Duration.zero,
        isPlaying: false,
      );
```

4. In fondo a `main`:

```dart
  testWidgets('precedente nel gruppo (spec H §9.1): pulsante, P, annuncio',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    expect(find.byTooltip(l.playerPreviousInQueue), findsNothing,
        reason: 'e4 è il primo della coda');
    expect(mediaSession.previousEnabled.last, isFalse);

    emit(PlayQueueUpdate('g1', queueWithPrevious()));
    await tester.pump();
    await tester.pump();
    expect(mediaSession.previousEnabled.last, isTrue);
    await tester.tap(find.byTooltip(l.playerPreviousInQueue));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('previous p1'));
    expect(announced(), contains({'Type': 'Action', 'Action': 'PreviousItem'}));

    api.calls.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(api.calls, ['previous p1']);
    await finish(tester);
  });

  testWidgets('precedente con un plugin vecchio: niente annuncio',
      (tester) async {
    await pumpPartyPlayer(tester, queueFeature: false);
    emit(PlayQueueUpdate('g1', queueWithPrevious()));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip(l.playerPreviousInQueue));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('previous p1'));
    expect(announced(), isEmpty);
    await finish(tester);
  });

  testWidgets('gruppo chiuso dal server: il precedente torna quello da soli',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(PlayQueueUpdate('g1', queueWithPrevious()));
    await tester.pump();
    await tester.pump();
    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip(l.playerPreviousInQueue), findsNothing);
    expect(mediaSession.previousEnabled.last, isFalse,
        reason: 'e4 non ha un episodio prima nella libreria finta');
    await finish(tester);
  });
```

Aggiungi gli import che mancano (`package:wonderflix/core/party_channel/party_channel_models.dart` c'è già).

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/watch_party/party_player_test.dart`
Expected: FAIL. Nel gruppo ⏮ non compare e i suggerimenti dicono ancora "Episodio".

- [ ] **Step 3: implementazione**

In `player_screen.dart`:

1. In `PlayerOverlay(...)` il parametro del Task 11 diventa:

```dart
                        onPrevious: _inParty
                            ? (party != null && party.hasPrevious
                                ? _playPrevious
                                : null)
                            : (view.previousEpisode == null
                                ? null
                                : _playPrevious),
                        partyQueue: _inParty,
```

2. Nel blocco `if (_inParty) { … }`, accanto al `ref.listen` di `s.inGroup && s.hasNext`:

```dart
      ref.listen(
          watchPartySessionProvider.select((s) => s.inGroup && s.hasPrevious),
          (_, hasPrevious) {
        if (_inParty && !_leaving) {
          unawaited(_mediaSession.setPreviousEnabled(hasPrevious));
        }
      });
```

3. Nel `ref.listen` di `s.inGroup`, il ramo "il server ci ha tolto dal gruppo", dopo il `setNextEnabled(...)`:

```dart
        unawaited(_mediaSession
            .setPreviousEnabled(ref.read(provider).previousEpisode != null));
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/watch_party/party_player_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player/player_screen.dart test/features/watch_party/party_player_test.dart
git commit -m "feat(party): previous title for the whole group"
```

### Task 13: post-play e schedina dal prossimo titolo della coda

**Files:**
- Modify: `lib/features/player/post_play.dart`
- Modify: `lib/features/player/player_extras.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/post_play_test.dart`, `test/features/player/player_extras_test.dart`, `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono**

In `post_play_test.dart`, nel gruppo del `PostPlayLayer`, dopo `dati del prossimo episodio e pulsanti`:

```dart
    testWidgets('occhiello scelto da chi lo mostra (spec H §9.1)',
        (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: PostPlayLayer(
            episode: episode,
            label: 'Prossimo nella coda',
            countdown: false,
            paused: false,
            onPlay: () {},
            onWatchCredits: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PROSSIMO NELLA CODA'), findsOneWidget);
      expect(find.text('PROSSIMO EPISODIO'), findsNothing);
    });
```

In `player_extras_test.dart`, dopo `scheda: episodio, pulsanti, entra da destra`:

```dart
  testWidgets('scheda: occhiello scelto da chi la mostra (spec H §9.1)',
      (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: NextEpisodeCard(
            episode: episode,
            label: 'Prossimo nella coda',
            countdown: false,
            onPlay: () {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PROSSIMO NELLA CODA'), findsOneWidget);
  });
```

In `party_player_test.dart`, il test `scheda "Prossimo episodio" solo se è il prossimo della coda` si sostituisce con:

```dart
  testWidgets('scheda nel gruppo: il prossimo della coda, anche un film '
      '(spec H §9.1)', (tester) async {
    await pumpPartyPlayer(tester);
    library.itemsById['m9'] = testItem(id: 'm9', name: 'Alien', year: 1979);
    // Dopo e4 nella coda c'è un film, non e5 (il successivo nella libreria).
    emit(PlayQueueUpdate('g1', testSeriesQueue(itemIds: ['e4', 'm9'])));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip(l.playerNextInQueue), findsOneWidget,
        reason: 'il pulsante segue la coda');
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.playerNextInQueueTitle.toUpperCase()), findsOneWidget);
    expect(find.text(l.playerNextEpisodeTitle.toUpperCase()), findsNothing);
    expect(find.text('Alien'), findsOneWidget);
    await tester.tap(find.byType(PlayNowButton));
    await tester.pump();
    expect(api.calls, contains('next p1'));
    await finish(tester);
  });

  testWidgets('scheda nel gruppo: l\'episodio dopo è "Prossimo episodio"',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.playerNextEpisodeTitle.toUpperCase()), findsOneWidget);
    await finish(tester);
  });

  testWidgets('scheda nel gruppo: senza i dettagli del prossimo non compare',
      (tester) async {
    await pumpPartyPlayer(tester);
    // e6 non è nella libreria finta: "non disponibile".
    emit(PlayQueueUpdate('g1', testSeriesQueue(itemIds: ['e4', 'e6'])));
    await tester.pump();
    await tester.pump();
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.byType(NextEpisodeCard), findsNothing);
    await finish(tester);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/player/post_play_test.dart test/features/player/player_extras_test.dart test/features/watch_party/party_player_test.dart`
Expected: FAIL, parametro `label` non definito.

- [ ] **Step 3: occhiello**

In `PostPlayLayer` (`post_play.dart`) e in `NextEpisodeCard` (`player_extras.dart`):
- parametro `this.label,`;
- campo:

```dart
  /// Occhiello; di default "Prossimo episodio" (nel watch party può essere
  /// "Prossimo nella coda", spec H §9.1).
  final String? label;
```

- il testo `l.playerNextEpisodeTitle.toUpperCase()` diventa `(label ?? l.playerNextEpisodeTitle).toUpperCase()`.

- [ ] **Step 4: player**

In `player_screen.dart`:

1. Import `../watch_party/party_queue_items.dart`.
2. Prima di `_canOfferNext`:

```dart
  /// Il titolo proposto come prossimo (spec H §9.1): da soli l'episodio
  /// successivo della serie; nel gruppo il prossimo della coda (anche un
  /// film), appena se ne conoscono i dettagli.
  JellyfinItem? _nextOffer(PlayerViewState view) {
    if (!_inParty) return view.nextEpisode;
    final entry = ref.read(watchPartySessionProvider).nextEntry;
    return entry == null ? null : ref.read(partyQueueItemsProvider)[entry.itemId];
  }

  /// "Prossimo episodio", o "Prossimo nella coda" se nel gruppo il prossimo
  /// non è l'episodio che segue nella libreria.
  String _nextOfferLabel(
          AppLocalizations l, PlayerViewState view, JellyfinItem offer) =>
      !_inParty || offer.id == view.nextEpisode?.id
          ? l.playerNextEpisodeTitle
          : l.playerNextInQueueTitle;
```

3. `_canOfferNext` diventa:

```dart
  /// C'è un titolo da proporre ([_nextOffer]), il caricamento è finito
  /// (primo fotogramma: aprendo nei titoli il post-play e il suo conto non
  /// partono sotto il caricamento) e l'utente non l'ha rifiutato.
  bool _canOfferNext(PlayerViewState view) =>
      _nextOffer(view) != null &&
      view.status == PlayerStatus.ready &&
      _firstFrame &&
      !_chrome.postPlayDismissed;
```

4. In `build`, dopo `final party = _inParty ? … : null;`:

```dart
    // I dettagli dei titoli in coda arrivano dopo: il post-play li aspetta.
    if (_inParty) ref.watch(partyQueueItemsProvider);
    final offer = _nextOffer(view);
```

5. Nella scheda e nel post-play `next` diventa `offer`, con l'occhiello. La scheda:

```dart
                        child: card && offer != null
                            ? NextEpisodeCard(
                                key: ValueKey(offer.id),
                                episode: offer,
                                label: _nextOfferLabel(l, view, offer),
```

   Il post-play:

```dart
                      child: postPlay && offer != null
                          ? SizedBox.expand(
                              key: ValueKey(offer.id),
                              child: PostPlayLayer(
                                episode: offer,
                                label: _nextOfferLabel(l, view, offer),
```

   Il resto dei due blocchi resta com'è. `next` (= `view.nextEpisode`) resta per ⏭ da soli.

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/player test/features/watch_party/party_player_test.dart`
Expected: PASS. Restano verdi anche i test esistenti del post-play nel gruppo con `queueSeries`: e5 è nella libreria finta ed è il successivo della serie.

- [ ] **Step 6: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player test/features/player test/features/watch_party/party_player_test.dart
git commit -m "feat(party): offer the next title of the queue after the credits"
```

---

## Gruppo E — pannello Coda

### Task 14: `PlayerSidePanelHost` e `PanelWheelBarrier` comuni

**Files:**
- Create: `lib/features/player/player_side_panel_host.dart`
- Modify: `lib/features/player/tracks_panel.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/tracks_panel_test.dart`, `test/features/player/player_screen_test.dart`

Il comportamento non cambia: è uno spostamento, con i test esistenti aggiornati.

- [ ] **Step 1: aggiorna i test**

In `tracks_panel_test.dart`:
- **`pumpHost`:** `TracksPanelHost(open: value, panel: panel())` diventa `PlayerSidePanelHost(open: value, panel: panel())`.
- **`slideFinder`:** `of: find.byType(TracksPanelHost)` diventa `of: find.byType(PlayerSidePanelHost)`.
- **Import:** `package:wonderflix/features/player/player_side_panel_host.dart`.

In `player_screen_test.dart`, nel test `strati dello stack: gli altri non si rimontano`, `TracksPanelHost,` diventa `PlayerSidePanelHost,`, con l'import.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/player/tracks_panel_test.dart`
Expected: FAIL, `PlayerSidePanelHost` non definito.

- [ ] **Step 3: implementazione**

Crea `lib/features/player/player_side_panel_host.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';

/// Un pannello a destra del player, a tutta altezza sopra i controlli, con
/// un velo sul film verso di lui (spec D §14): entra scorrendo (`medium`),
/// esce in `fast`; con le animazioni ridotte solo dissolvenza. Chiuso, non è
/// nell'albero (e le voci rientrano scaglionate alla prossima apertura). Lo
/// usano "Audio e sottotitoli" e la coda del watch party (spec H §9.1).
class PlayerSidePanelHost extends StatefulWidget {
  const PlayerSidePanelHost({
    super.key,
    required this.open,
    required this.panel,
    this.width = defaultWidth,
    this.maxWidthFraction = defaultMaxWidthFraction,
  });

  final bool open;
  final Widget panel;

  /// Larghezza del pannello, e la parte della finestra che può occupare al
  /// massimo.
  final double width;
  final double maxWidthFraction;

  static const defaultWidth = 360.0;
  static const defaultMaxWidthFraction = 0.35;

  @override
  State<PlayerSidePanelHost> createState() => _PlayerSidePanelHostState();
}

class _PlayerSidePanelHostState extends State<PlayerSidePanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WfMotion.medium,
    reverseDuration: WfMotion.fast,
    value: widget.open ? 1 : 0,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: WfMotion.emphasized,
    // Chiudendo il controller torna da 1 a 0: la curva girata accelera.
    reverseCurve: WfMotion.accelerateReverse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = WfMotion.of(context).duration(WfMotion.medium);
  }

  @override
  void didUpdateWidget(PlayerSidePanelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      if (widget.open) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    // Prima la curva (si stacca dal controller), poi il controller.
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    // La larghezza si misura sullo spazio che l'host ha davvero (nel player
    // è la finestra intera), non su `MediaQuery`.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
            widget.width, constraints.maxWidth * widget.maxWidthFraction);
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            if (_controller.isDismissed) return const SizedBox.shrink();
            final t = _progress.value.clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(opacity: t, child: const _PanelVeil()),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: width,
                  child: reduced
                      ? Opacity(opacity: t, child: widget.panel)
                      : FractionalTranslation(
                          translation: Offset(1 - t, 0),
                          child: widget.panel,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Il film si scurisce appena verso il pannello.
class _PanelVeil extends StatelessWidget {
  const _PanelVeil();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              WfColors.bg.withValues(alpha: 0),
              WfColors.bg.withValues(alpha: 0.45),
            ],
            stops: const [0.4, 1],
          ),
        ),
      );
}

/// La rotella su un pannello del player non arriva mai al volume (issue
/// #4). Vince chi registra per primo, cioè il widget più interno: se la
/// lista può scorrere registra lei; se no (in cima, in fondo, lista corta)
/// vince questa azione vuota.
class PanelWheelBarrier extends StatelessWidget {
  const PanelWheelBarrier({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            GestureBinding.instance.pointerSignalResolver
                .register(event, (_) {});
          }
        },
        child: child,
      );
}
```

In `tracks_panel.dart`:
1. Togli `TracksPanelHost`, `_TracksPanelHostState` e `_PanelVeil`: dal commento `/// Il pannello a destra, a tutta altezza, …` fino alla fine del file.
2. In `TracksPanel.build`, il `return Listener(...)` finale (con il suo commento sulla rotella) diventa `return PanelWheelBarrier(child: content);`.
3. Le costanti diventano:

```dart
  /// Larghezza del pannello, e la parte della finestra che può occupare al
  /// massimo.
  static const width = PlayerSidePanelHost.defaultWidth;
  static const maxWidthFraction = PlayerSidePanelHost.defaultMaxWidthFraction;
```

4. Import `player_side_panel_host.dart`. Togli `package:flutter/gestures.dart` se non serve più (`flutter analyze` lo dice).

In `player_screen.dart`:
- `TracksPanelHost(` diventa `PlayerSidePanelHost(`;
- import `player_side_panel_host.dart`.

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/player`
Expected: PASS, compresi i test della rotella.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player test/features/player
git commit -m "refactor(player): share the side panel host between panels"
```

### Task 15: `PlayerPopup.queue`

**Files:**
- Modify: `lib/features/player/player_chrome.dart`
- Test: `test/features/player/player_chrome_test.dart`

- [ ] **Step 1: test che fallisce**

In `player_chrome_test.dart`, dopo il test della barretta delle reazioni:

```dart
  test('coda del watch party (spec H §9.1): come le tracce, controlli su e '
      'niente pausa', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      async.elapse(PlayerChromeController.hideDelay);
      expect(chrome.controlsVisible, isFalse);
      chrome.openPopup(PlayerPopup.queue);
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(seconds: 10));
      expect(chrome.controlsVisible, isTrue);
      chrome.setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(const Duration(seconds: 20));
      expect(chrome.pauseScreen, isFalse);
      chrome.togglePopup(PlayerPopup.tracks);
      expect(chrome.popup, PlayerPopup.tracks, reason: 'uno alla volta');
      chrome.dispose();
    });
  });
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/features/player/player_chrome_test.dart`
Expected: FAIL, `PlayerPopup.queue` non definito.

- [ ] **Step 3: implementazione**

In `player_chrome.dart`:

```dart
/// Riquadri del player che si aprono uno alla volta (spec E §11): il
/// pannello "Audio e sottotitoli", la chat e la barretta delle reazioni del
/// watch party, il pannello "Coda" del gruppo (spec H §9.1).
enum PlayerPopup { tracks, chat, reactions, queue }
```

In `_scheduleHide` la condizione diventa:

```dart
    if (_popup == PlayerPopup.tracks ||
        _popup == PlayerPopup.reactions ||
        _popup == PlayerPopup.queue) {
      return;
    }
```

Nei commenti di `openPopup` e `_scheduleHide`, "il pannello" vale per i due pannelli: tracce e coda.

- [ ] **Step 4: il test passa**

Run: `flutter test test/features/player/player_chrome_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player/player_chrome.dart test/features/player/player_chrome_test.dart
git commit -m "feat(player): add the queue panel to the player popups"
```

### Task 16: `QueuePanel`, la vista Coda

**Files:**
- Create: `lib/features/player/queue_panel/queue_rows.dart`
- Create: `lib/features/player/queue_panel/queue_panel.dart`
- Test: `test/features/player/queue_panel_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/features/player/queue_panel_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/player/queue_panel/queue_panel.dart';
import 'package:wonderflix/features/player/queue_panel/queue_rows.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  JellyfinItem episode(String id, String name, int index) => testItem(
        id: id,
        name: name,
        kind: ItemKind.episode,
        seriesName: 'The Office',
        seriesId: 's1',
        index: index,
        seasonIndex: 2,
        runtimeMinutes: 22,
      );

  /// e3 già visto (p1), e4 in riproduzione (p2), poi e5 (p3), il film m1
  /// (p4) e x9 non disponibile (p5).
  PlayQueue queue(
          {bool shuffled = false,
          DateTime? lastUpdate,
          List<String>? upcoming}) =>
      PlayQueue(
        reason: 'NewPlaylist',
        lastUpdate: lastUpdate ?? DateTime.utc(2026, 10, 4, 10),
        entries: [
          const PlayQueueEntry(itemId: 'e3', playlistItemId: 'p1'),
          const PlayQueueEntry(itemId: 'e4', playlistItemId: 'p2'),
          for (final id in upcoming ?? const ['p3', 'p4', 'p5'])
            PlayQueueEntry(
                itemId: const {'p3': 'e5', 'p4': 'm1', 'p5': 'x9'}[id]!,
                playlistItemId: id),
        ],
        playingIndex: 1,
        startPosition: Duration.zero,
        isPlaying: true,
        shuffled: shuffled,
      );

  final items = <String, JellyfinItem?>{
    'e3': episode('e3', 'Ufficio in fiamme', 3),
    'e4': episode('e4', 'La festa', 4),
    'e5': episode('e5', 'Halloween', 5),
    'm1': testItem(id: 'm1', name: 'Alien', year: 1979, runtimeMinutes: 117),
    'x9': null,
  };

  Future<List<String>> pumpPanel(WidgetTester tester,
      {ValueNotifier<PlayQueue>? notifier,
      Map<String, JellyfinItem?>? details}) async {
    final calls = <String>[];
    final current = notifier ?? ValueNotifier(queue());
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: QueuePanel.width,
            height: 900,
            child: ValueListenableBuilder<PlayQueue>(
              valueListenable: current,
              builder: (context, value, _) => QueuePanel(
                queue: value,
                items: details ?? items,
                onJump: (id) => calls.add('jump $id'),
                onRemove: (id) => calls.add('remove $id'),
                onMove: (id, index) => calls.add('move $id $index'),
                onShuffle: (on) => calls.add('shuffle $on'),
                onClose: () => calls.add('close'),
              ),
            ),
          ),
        ),
      ),
    );
    return calls;
  }

  Finder row(String playlistItemId) =>
      find.byKey(ValueKey('party-queue-$playlistItemId'));

  Finder inRow(String playlistItemId, Finder finder) =>
      find.descendant(of: row(playlistItemId), matching: finder);

  test('riga secondaria: episodio, film, in riproduzione', () {
    expect(queueRowDetails(l, items['e5']!), 'The Office · S2:E5 · 22m');
    expect(queueRowDetails(l, items['m1']!), 'Film · 1979 · 1h 57m');
    expect(queueRowDetails(l, items['e4']!, playing: true),
        'The Office · S2:E4 · ora');
  });

  testWidgets('sezioni, righe e riepilogo (spec H §9.2)', (tester) async {
    await pumpPanel(tester);
    expect(find.text(l.partyQueueTitle), findsOneWidget);
    // Prossimi: e5 (22m) e Alien (1h 57m); x9 non ha durata.
    expect(find.text('5 titoli · 2h 19m dopo questo'), findsOneWidget);
    expect(find.text(l.partyQueueWatched), findsOneWidget);
    expect(find.text(l.partyQueuePlaying), findsOneWidget);
    expect(find.text(l.partyQueueUpcoming), findsOneWidget);
    expect(find.text('Ufficio in fiamme'), findsOneWidget);
    expect(find.text('The Office · S2:E4 · ora'), findsOneWidget);
    expect(find.text('Film · 1979 · 1h 57m'), findsOneWidget);
    expect(find.text(l.partyQueueUnavailable), findsOneWidget);
    // Le righe già viste sono attenuate.
    expect(
        tester
            .widget<Opacity>(find
                .ancestor(of: find.text('Ufficio in fiamme'),
                    matching: find.byType(Opacity))
                .first)
            .opacity,
        QueueRow.watchedOpacity);
  });

  testWidgets('primo titolo in riproduzione: niente "Già visti"',
      (tester) async {
    await pumpPanel(tester,
        notifier: ValueNotifier(PlayQueue(
          reason: 'NewPlaylist',
          lastUpdate: DateTime.utc(2026, 10, 4, 10),
          entries: const [
            PlayQueueEntry(itemId: 'e4', playlistItemId: 'p2'),
            PlayQueueEntry(itemId: 'e5', playlistItemId: 'p3'),
          ],
          playingIndex: 0,
          startPosition: Duration.zero,
          isPlaying: true,
        )));
    expect(find.text(l.partyQueueWatched), findsNothing);
    expect(find.text('2 titoli · 22m dopo questo'), findsOneWidget);
  });

  testWidgets('clic su una riga: ci si va; quella in corso non fa nulla',
      (tester) async {
    final calls = await pumpPanel(tester);
    await tester.tap(find.text('Halloween'));
    await tester.tap(find.text('Ufficio in fiamme'));
    await tester.tap(find.text('La festa'));
    expect(calls, ['jump p3', 'jump p1']);
  });

  testWidgets('togli: sui prossimi e sui già visti, non su quella in corso',
      (tester) async {
    final calls = await pumpPanel(tester);
    expect(inRow('p2', find.byTooltip(l.partyQueueRemove)), findsNothing);
    await tester.tap(inRow('p3', find.byTooltip(l.partyQueueRemove)));
    await tester.tap(inRow('p1', find.byTooltip(l.partyQueueRemove)));
    expect(calls, ['remove p3', 'remove p1']);
  });

  testWidgets('passando sopra una riga compaiono maniglia e ✕',
      (tester) async {
    await pumpPanel(tester);
    double opacityOf(Finder finder) => tester
        .widget<AnimatedOpacity>(find
            .ancestor(of: finder, matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;
    final remove = inRow('p3', find.byTooltip(l.partyQueueRemove));
    final grip = inRow('p3', find.byIcon(LucideIcons.gripVertical));
    expect(opacityOf(remove), 0);
    expect(opacityOf(grip), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('Halloween')));
    addTearDown(mouse.removePointer);
    await tester.pump();
    expect(opacityOf(remove), 1);
    expect(opacityOf(grip), 1);
    expect(inRow('p2', find.byIcon(LucideIcons.gripVertical)), findsNothing,
        reason: 'la riga in corso non si trascina');
    expect(inRow('p1', find.byIcon(LucideIcons.gripVertical)), findsNothing,
        reason: 'i già visti non si trascinano');
  });

  testWidgets('trascinamento tra i prossimi: la riga resta dove la si lascia, '
      'poi vale la coda del server', (tester) async {
    final notifier = ValueNotifier(queue());
    final calls = await pumpPanel(tester, notifier: notifier);
    double top(String id) => tester.getTopLeft(row(id)).dy;
    final rowHeight = tester.getSize(row('p3')).height;
    final gesture = await tester.startGesture(
        tester.getCenter(inRow('p4', find.byIcon(LucideIcons.gripVertical))));
    await tester.pump();
    await gesture.moveBy(Offset(0, -rowHeight));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, ['move p4 0']);
    expect(top('p4'), lessThan(top('p3')),
        reason: 'prima della coda nuova la riga resta dove la si è lasciata');

    // La coda nuova del server.
    notifier.value = queue(
        lastUpdate: DateTime.utc(2026, 10, 4, 10, 1),
        upcoming: const ['p4', 'p3', 'p5']);
    await tester.pump();
    expect(top('p4'), lessThan(top('p3')));
  });

  testWidgets('trascinamento senza risposta: dopo 4 s torna l\'ordine della '
      'coda', (tester) async {
    await pumpPanel(tester);
    double top(String id) => tester.getTopLeft(row(id)).dy;
    final rowHeight = tester.getSize(row('p3')).height;
    final gesture = await tester.startGesture(
        tester.getCenter(inRow('p4', find.byIcon(LucideIcons.gripVertical))));
    await tester.pump();
    await gesture.moveBy(Offset(0, -rowHeight));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(top('p4'), lessThan(top('p3')));
    await tester.pump(QueuePanel.pendingTimeout);
    await tester.pumpAndSettle();
    expect(top('p4'), greaterThan(top('p3')));
  });

  testWidgets('ordine casuale: il pulsante dice lo stato e lo cambia',
      (tester) async {
    final notifier = ValueNotifier(queue());
    final calls = await pumpPanel(tester, notifier: notifier);
    final button = find.byKey(const Key('party-queue-shuffle'));
    expect(tester.widget<IconButton>(button).isSelected, isFalse);
    await tester.tap(button);
    notifier.value =
        queue(shuffled: true, lastUpdate: DateTime.utc(2026, 10, 4, 10, 1));
    await tester.pump();
    expect(tester.widget<IconButton>(button).isSelected, isTrue);
    await tester.tap(button);
    expect(calls, ['shuffle true', 'shuffle false']);
  });

  testWidgets('chiudi', (tester) async {
    final calls = await pumpPanel(tester);
    await tester.tap(find.byTooltip(l.playerClosePanel));
    expect(calls, ['close']);
  });

  testWidgets('dettagli in arrivo: righe senza titolo, poi complete',
      (tester) async {
    await pumpPanel(tester, details: const {});
    expect(find.text('…'), findsNWidgets(5));
    expect(find.text('5 titoli'), findsOneWidget, reason: 'nessuna durata nota');
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/player/queue_panel_test.dart`
Expected: FAIL, file non trovati.

- [ ] **Step 3: righe**

Crea `lib/features/player/queue_panel/queue_rows.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/motion.dart';
import '../../../app/theme.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../ui/wf_image.dart';
import '../../library/item_labels.dart';
import '../../library/library_providers.dart';

/// Riga secondaria di un titolo della coda (spec H §9.2): "The Office ·
/// S2:E5 · 22m" per un episodio, "Film · 1979 · 1h 57m" per un film. Con
/// [playing] "ora" al posto della durata.
String queueRowDetails(AppLocalizations l, JellyfinItem item,
    {bool playing = false}) {
  final runtime = item.runtime;
  final parts = item.kind == ItemKind.episode
      ? [?item.seriesName, ?episodeCode(item)]
      : [l.partyQueueMovie, ?item.productionYear?.toString()];
  return [
    ...parts,
    if (playing)
      l.partyQueueNow
    else if (runtime != null)
      formatRuntime(runtime),
  ].join(' · ');
}

/// Titolo di una sezione del pannello: in oro, i già visti attenuati.
class QueueSectionTitle extends StatelessWidget {
  const QueueSectionTitle(this.title, {super.key, this.muted = false});

  final String title;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(title,
            style: WfText.display(17,
                color: muted ? WfColors.creamMuted : WfColors.gold)),
      );
}

enum QueueRowKind { watched, playing, upcoming }

/// Un titolo della coda (spec H §9.2): immagine, titolo, riga secondaria.
/// Passando sopra compaiono la maniglia (solo i prossimi) e ✕ (non sulla
/// riga in corso).
class QueueRow extends ConsumerStatefulWidget {
  const QueueRow({
    super.key,
    required this.kind,
    required this.item,
    required this.known,
    this.index,
    this.onTap,
    this.onRemove,
  });

  final QueueRowKind kind;

  /// Dettagli del titolo; `null` con [known] = non disponibile.
  final JellyfinItem? item;

  /// I dettagli sono arrivati (o si sa che non ci sono).
  final bool known;

  /// Posizione tra i prossimi, per il trascinamento.
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  static const radius = 6.0;

  /// Immagine 16:9 della riga.
  static const thumbWidth = 64.0;
  static const thumbHeight = 36.0;

  /// I titoli già visti sono attenuati.
  static const watchedOpacity = 0.5;

  /// Fondo e barra a sinistra della riga in corso.
  static const playingFill = 0.12;
  static const playingBar = 3.0;

  @override
  ConsumerState<QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends ConsumerState<QueueRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = widget.item;
    final playing = widget.kind == QueueRowKind.playing;
    final index = widget.index;
    final title =
        item?.name ?? (widget.known ? l.partyQueueUnavailable : '…');
    final details =
        item == null ? null : queueRowDetails(l, item, playing: playing);
    Widget hoverOnly(Widget child) => AnimatedOpacity(
        opacity: _hovered ? 1 : 0, duration: WfMotion.fast, child: child);
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: widget.kind == QueueRowKind.upcoming && index != null
                ? hoverOnly(ReorderableDragStartListener(
                    index: index,
                    child: Tooltip(
                      message: l.partyQueueMove,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(LucideIcons.gripVertical,
                            size: 16, color: WfColors.creamMuted),
                      ),
                    ),
                  ))
                : null,
          ),
          const SizedBox(width: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: QueueRow.thumbWidth,
              height: QueueRow.thumbHeight,
              child: WfImage(
                  image: item == null
                      ? null
                      : ref.watch(imageUrlsProvider).landscape(item)),
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
                      style: TextStyle(
                          fontSize: 11.5,
                          color:
                              playing ? WfColors.gold : WfColors.creamMuted)),
              ],
            ),
          ),
          SizedBox(
            width: 40,
            child: widget.onRemove == null
                ? null
                : hoverOnly(IconButton(
                    icon: const Icon(LucideIcons.x, size: 16),
                    tooltip: l.partyQueueRemove,
                    color: WfColors.creamMuted,
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onRemove,
                  )),
          ),
        ],
      ),
    );
    final decorated = playing
        ? ClipRRect(
            borderRadius: BorderRadius.circular(QueueRow.radius),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                      color:
                          WfColors.gold.withValues(alpha: QueueRow.playingFill)),
                ),
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: QueueRow.playingBar,
                  child: ColoredBox(color: WfColors.gold),
                ),
                row,
              ],
            ),
          )
        : row;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Opacity(
        opacity:
            widget.kind == QueueRowKind.watched ? QueueRow.watchedOpacity : 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(QueueRow.radius),
            hoverColor: WfColors.surfaceHigh,
            child: decorated,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: pannello**

Crea `lib/features/player/queue_panel/queue_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../core/syncplay/syncplay_models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/item_labels.dart';
import '../../watch_party/party_queue_editor.dart';
import '../../watch_party/party_queue_items.dart';
import '../../watch_party/party_queue_rules.dart';
import '../../watch_party/watch_party_session.dart';
import '../player_side_panel_host.dart';
import 'queue_rows.dart';

/// Il pannello "Coda" con i dati del watch party (spec H §9.2): la coda del
/// gruppo, i dettagli dei titoli e i comandi di [PartyQueueEditor].
class PartyQueuePanel extends ConsumerWidget {
  const PartyQueuePanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
        watchPartySessionProvider.select((s) => s.inGroup ? s.queue : null));
    if (queue == null) return const SizedBox.shrink();
    final editor = ref.read(partyQueueEditorProvider);
    return QueuePanel(
      queue: queue,
      items: ref.watch(partyQueueItemsProvider),
      onJump: (id) => unawaited(editor.jumpTo(id)),
      onRemove: (id) => unawaited(editor.remove(id)),
      onMove: (id, index) => unawaited(editor.move(id, index)),
      onShuffle: (shuffle) => unawaited(editor.setShuffle(shuffle)),
      onClose: onClose,
    );
  }
}

/// La vista Coda (spec H §9.2): intestazione con ordine casuale e ✕,
/// riepilogo, poi "Già visti", "In riproduzione" e "Prossimi"
/// (trascinabili). Non conosce il watch party: riceve la coda, i dettagli e
/// i comandi.
class QueuePanel extends StatefulWidget {
  const QueuePanel({
    super.key,
    required this.queue,
    required this.items,
    required this.onJump,
    required this.onRemove,
    required this.onMove,
    required this.onShuffle,
    required this.onClose,
  });

  final PlayQueue queue;

  /// Dettagli per `ItemId`: assente = in arrivo, `null` = non disponibile.
  final Map<String, JellyfinItem?> items;
  final ValueChanged<String> onJump;
  final ValueChanged<String> onRemove;

  /// Un prossimo (id nella coda) portato alla posizione data tra i
  /// prossimi, contata dopo averlo tolto.
  final void Function(String playlistItemId, int upcomingIndex) onMove;
  final ValueChanged<bool> onShuffle;
  final VoidCallback onClose;

  static const width = PlayerSidePanelHost.defaultWidth;

  /// Senza la coda nuova del server entro questo tempo (spostamento non
  /// riuscito), le righe tornano nell'ordine della coda.
  static const pendingTimeout = Duration(seconds: 4);

  /// Dove sta la riga in corso all'apertura (0 = in cima alla lista).
  static const playingAlignment = 0.25;

  /// Fondo del pulsante dell'ordine casuale quando è attivo.
  static const shuffleOnFill = 0.14;

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  final _playingKey = GlobalKey();

  /// Ordine dei prossimi dopo un trascinamento, finché il server non manda
  /// la coda nuova: la riga resta dove la si è lasciata.
  List<String>? _pendingOrder;
  Timer? _pendingTimer;

  @override
  void initState() {
    super.initState();
    // All'apertura la lista mostra la riga in corso.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playing = _playingKey.currentContext;
      if (!mounted || playing == null) return;
      unawaited(Scrollable.ensureVisible(playing,
          alignment: QueuePanel.playingAlignment));
    });
  }

  @override
  void didUpdateWidget(QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // La coda nuova del server vale più dell'ordine provvisorio.
    if (widget.queue.lastUpdate != oldWidget.queue.lastUpdate) _clearPending();
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  void _clearPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingOrder = null;
  }

  void _reorder(List<PlayQueueEntry> upcoming, int oldIndex, int newIndex) {
    // `newIndex` è contato prima di togliere la riga: scendendo vale uno in
    // più.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final order = [for (final entry in upcoming) entry.playlistItemId];
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    _pendingTimer?.cancel();
    _pendingTimer = Timer(QueuePanel.pendingTimeout, () {
      if (mounted) setState(_clearPending);
    });
    setState(() => _pendingOrder = order);
    widget.onMove(moved, newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final queue = widget.queue;
    final sections = partyQueueSections(queue);
    final upcoming = partyQueueInOrder(sections.upcoming, _pendingOrder);
    final runtime = partyQueueUpcomingRuntime(queue, widget.items);
    final titles = l.catalogCount(queue.entries.length);
    final playing = sections.playing;

    QueueRow rowFor(PlayQueueEntry entry, QueueRowKind kind, {int? index}) =>
        QueueRow(
          key: ValueKey('party-queue-${entry.playlistItemId}'),
          kind: kind,
          item: widget.items[entry.itemId],
          known: widget.items.containsKey(entry.itemId),
          index: index,
          onTap: kind == QueueRowKind.playing
              ? null
              : () => widget.onJump(entry.playlistItemId),
          onRemove: kind == QueueRowKind.playing
              ? null
              : () => widget.onRemove(entry.playlistItemId),
        );

    final list = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList.list(children: [
            if (sections.watched.isNotEmpty) ...[
              QueueSectionTitle(l.partyQueueWatched, muted: true),
              for (final entry in sections.watched)
                rowFor(entry, QueueRowKind.watched),
            ],
            if (playing != null) ...[
              QueueSectionTitle(l.partyQueuePlaying),
              KeyedSubtree(
                  key: _playingKey,
                  child: rowFor(playing, QueueRowKind.playing)),
            ],
            if (upcoming.isNotEmpty) QueueSectionTitle(l.partyQueueUpcoming),
          ]),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverReorderableList(
            itemCount: upcoming.length,
            onReorder: (oldIndex, newIndex) =>
                _reorder(upcoming, oldIndex, newIndex),
            // La riga trascinata sta in un `Overlay`: il suo `InkWell` vuole
            // un `Material` sopra.
            proxyDecorator: (child, index, animation) => Material(
              color: WfColors.surfaceHigh,
              elevation: 6,
              borderRadius: BorderRadius.circular(QueueRow.radius),
              child: child,
            ),
            itemBuilder: (context, index) =>
                rowFor(upcoming[index], QueueRowKind.upcoming, index: index),
          ),
        ),
      ],
    );

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
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l.partyQueueTitle,
                          style: WfText.display(24)),
                    ),
                    IconButton(
                      key: const Key('party-queue-shuffle'),
                      icon: const Icon(LucideIcons.shuffle),
                      isSelected: queue.shuffled,
                      tooltip: l.partyQueueShuffle,
                      color: queue.shuffled ? WfColors.gold : WfColors.cream,
                      style: IconButton.styleFrom(
                        backgroundColor: queue.shuffled
                            ? WfColors.gold
                                .withValues(alpha: QueuePanel.shuffleOnFill)
                            : null,
                      ),
                      onPressed: () => widget.onShuffle(!queue.shuffled),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      tooltip: l.playerClosePanel,
                      color: WfColors.cream,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  runtime == null
                      ? titles
                      : l.partyQueueSummary(titles, formatRuntime(runtime)),
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12),
                ),
              ),
              Expanded(child: list),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/player/queue_panel_test.dart`
Expected: PASS. Se i test del trascinamento non spostano la riga, cambia gesto e misure (per esempio `moveBy` in più passi, o `tester.timedDrag`) ma tieni le stesse attese; segnalalo.

- [ ] **Step 6: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player/queue_panel test/features/player/queue_panel_test.dart
git commit -m "feat(party): add the queue panel"
```

### Task 17: pulsante Coda e pannello nel player

**Files:**
- Modify: `lib/features/player/player_overlay.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_overlay_test.dart`, `test/features/player/player_screen_test.dart`, `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono**

In `player_overlay_test.dart`, in fondo a `main`:

```dart
  testWidgets('coda del watch party: pulsante tra reazioni e tracce (spec H '
      '§9.1)', (tester) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: PlayerOverlay(
          view: const PlayerViewState(status: PlayerStatus.ready),
          engine: FakeVideoEngine(),
          fullscreen: false,
          onBack: () {},
          onTogglePlay: () {},
          onSeekBy: (_) {},
          onSeekTo: (_) {},
          onVolume: (_) {},
          onToggleMute: () {},
          onToggleTracks: () {},
          onToggleFullscreen: () {},
          onToggleReactions: () {},
          onToggleQueue: () => calls.add('queue'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Coda'));
    expect(calls, ['queue']);
    final queue = tester.getCenter(find.byTooltip('Coda')).dx;
    expect(tester.getCenter(find.byTooltip('Reazioni (1–6)')).dx,
        lessThan(queue));
    expect(queue,
        lessThan(tester.getCenter(find.byTooltip('Audio e sottotitoli')).dx));
  });
```

Nel test `titolo, episodio e comandi` aggiungi `expect(find.byTooltip('Coda'), findsNothing);`.

In `player_screen_test.dart`, nel test `video, titolo, episodio e controlli` aggiungi `expect(find.byTooltip('Coda'), findsNothing, reason: 'solo nel watch party');`.

In `party_player_test.dart`:
- aggiungi gli import `package:wonderflix/features/player/queue_panel/queue_panel.dart`;
- in fondo a `main`:

```dart
  testWidgets('pannello Coda (spec H §9): si apre dal pulsante, salta, '
      'toglie, mescola; Esc lo chiude', (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.partyQueueOpen));
    await tester.pumpAndSettle();
    expect(find.byType(QueuePanel), findsOneWidget);
    final panel = find.byType(QueuePanel);
    expect(
        find.descendant(of: panel, matching: find.text('Cat\'s in the Bag')),
        findsOneWidget);
    expect(
        find.descendant(
            of: panel, matching: find.text(l.partyQueueUnavailable)),
        findsOneWidget,
        reason: 'e6 non è nella libreria finta');

    await tester.tap(
        find.descendant(of: panel, matching: find.text('Cat\'s in the Bag')));
    await tester.pump();
    expect(api.calls, contains('set-item p2'));
    expect(announced(),
        contains({'Type': 'Action', 'Action': 'SetCurrentItem'}));

    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('party-queue-p3')),
        matching: find.byTooltip(l.partyQueueRemove)));
    await tester.pump();
    expect(api.calls, contains('remove p3'));

    await tester.tap(find.byTooltip(l.partyQueueShuffle));
    await tester.pump();
    expect(api.calls, contains('shuffle on'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QueuePanel), findsNothing);
    await finish(tester);
  });

  testWidgets('pannello Coda: si chiude se il server ci toglie dal gruppo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.partyQueueOpen));
    await tester.pumpAndSettle();
    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(QueuePanel), findsNothing);
    expect(find.byTooltip(l.partyQueueOpen), findsNothing);
    await finish(tester);
  });

  testWidgets('pannello Coda: si chiude quando compare il post-play',
      (tester) async {
    await pumpPartyPlayer(tester, segments: const [
      MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration(hours: 1, minutes: 55),
          end: Duration(hours: 2)),
    ]);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.partyQueueOpen));
    await tester.pumpAndSettle();
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatchCredits), findsOneWidget);
    expect(find.byType(QueuePanel), findsNothing);
    await finish(tester);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/player/player_overlay_test.dart test/features/watch_party/party_player_test.dart`
Expected: FAIL, `onToggleQueue` non definito.

- [ ] **Step 3: pulsante**

In `player_overlay.dart`:
- parametro `this.onToggleQueue,` (dopo `this.reactionsLink,`);
- campo:

```dart
  /// Pannello "Coda" del watch party (spec H §9.1): solo nel gruppo; `null`
  /// = nessun pulsante.
  final VoidCallback? onToggleQueue;
```

- nella riga in basso, tra il blocco delle reazioni e il pulsante delle tracce:

```dart
                          if (onToggleQueue != null)
                            PlayerIconButton(
                              key: const Key('player-queue-button'),
                              icon: const Icon(LucideIcons.listVideo),
                              tooltip: l.partyQueueOpen,
                              onPressed: onToggleQueue,
                            ),
```

- [ ] **Step 4: player**

In `player_screen.dart`:

1. Import `queue_panel/queue_panel.dart`.
2. In `PlayerOverlay(...)`, dopo `reactionsLink: _reactionsLink,`:

```dart
                        onToggleQueue: party != null &&
                                party.inGroup &&
                                party.queue != null
                            ? () => _chrome.togglePopup(PlayerPopup.queue)
                            : null,
```

3. In fondo allo `Stack`, dopo il `Positioned.fill` del pannello delle tracce:

```dart
                // Pannello "Coda" del watch party (spec H §9.1): come quello
                // delle tracce, a destra sopra i controlli.
                if (party != null)
                  Positioned.fill(
                    key: const ValueKey('player-queue-panel'),
                    child: ExcludeFocus(
                      child: PlayerSidePanelHost(
                        open: _chrome.popup == PlayerPopup.queue &&
                            party.inGroup,
                        panel: PartyQueuePanel(
                          onClose: () =>
                              _chrome.closePopup(PlayerPopup.queue),
                        ),
                      ),
                    ),
                  ),
```

4. Il pannello si chiude da solo:
   - nel `ref.listen` di `s.status`, ramo `PlayerStatus.error`, la catena `_chrome..closePanel()..closePopup(PlayerPopup.reactions)` aggiunge `..closePopup(PlayerPopup.queue)`;
   - nel post-frame di `postPlay` (`if (postPlay) { _chrome..closePanel()..closePopup(PlayerPopup.reactions); }`) aggiungi `..closePopup(PlayerPopup.queue)`;
   - nel `ref.listen` di `s.inGroup`, ramo "il server ci ha tolto dal gruppo", la catena `_chrome..closePopup(PlayerPopup.chat)..closePopup(PlayerPopup.reactions)` aggiunge `..closePopup(PlayerPopup.queue)`.

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/player test/features/watch_party`
Expected: PASS.

- [ ] **Step 6: verifica completa e commit**

Run: `flutter analyze`; `flutter test`.

```bash
git add lib/features/player test/features/player test/features/watch_party/party_player_test.dart
git commit -m "feat(party): open the queue panel from the player"
```

---

## Gruppo F — allineamento e verifica finale

### Task 18: spec allineata, verifica, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md`

- [ ] **Step 1: allinea la spec**

Nella spec, edit mirati:

1. Riga **Stato**: `approvato; piano 14a realizzato (docs/superpowers/plans/2026-10-04-wonderflix-14a-coda-party.md), piano 14b da scrivere`.
2. §8.1, la voce `**SocialFeatures.queue:** da Info.Features.` diventa:
   `**Funzione queue del plugin:** \`PartyPluginInfo.features\` (l'\`Info\` che chiede il canale del party) → \`PartyChannelState.queueActions\`; \`PartyChannel.announce\` manda le azioni della coda solo con questa funzione.`
3. §9.1:
   - **Pulsanti:** la voce "⏮ è acceso: nel party se `hasPrevious`; da soli se c'è `previousEpisode`." diventa "⏮ c'è nel party se `hasPrevious`, da soli se c'è `previousEpisode`; altrimenti non compare, come ⏭."
   - **Pannello:** "Si chiude con ✕, con un clic sul film, con Esc (vedi §9.3), oppure quando il player esce dal party." diventa "Si chiude con ✕, con un clic sul film, con Esc (vedi §9.3), quando compare il post-play, quando il video va in errore, oppure quando il player esce dal party."
4. §9.2, vista Coda:
   - **Riepilogo:** "14 titoli · 3 h 40 min dopo questo". La somma delle durate conta l'elemento in corso e i prossimi; i titoli senza durata non contano." diventa "14 titoli · 3h 40m dopo questo". La somma conta solo i prossimi; i titoli senza durata non contano. Le durate sono nel formato dell'app (`formatRuntime`)."
   - **Riga:** "The Office · S2:E5 · 22 min" diventa "The Office · S2:E5 · 22m", e "Film · 1979 · 1 h 57 min" diventa "Film · 1979 · 1h 57m".
   - Dopo la voce del trascinamento: "Rilasciata la riga, il titolo resta dove lo si è lasciato finché arriva la coda nuova del server; se dopo 4 s non è arrivata, le righe tornano nell'ordine della coda."
5. §6, nello schema dell'architettura: `lib/core/syncplay/      SyncPlayApi (+6 metodi), PlayQueue.shuffled` resta. Aggiungi la riga `lib/core/party_channel/  PartyPluginInfo.features, PartyAction (+5)`.

- [ ] **Step 2: verifica completa**

Run:
- `flutter analyze` → nessun problema;
- `flutter test` → tutto verde. Annota il numero.
- `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → tutto verde, nessun warning.

- [ ] **Step 3: build di release**

Prima copia nel worktree la configurazione (`config/wonderflix.json` del checkout principale), se non c'è già. Poi:

Run: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
Expected: `build/windows/x64/runner/Release/wonderflix.exe` creato.

Dopo la build, `git status`: se `windows/flutter/` ha solo cambi di fine riga, `git checkout -- windows/flutter/`. `config/wonderflix.json` non si committa: è ignorato.

- [ ] **Step 4: commit**

```bash
git add docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md
git commit -m "docs: align spec H with plan 14a"
```

---

## Prova manuale (con l'utente, dopo la review finale)

Due istanze: la seconda con `WONDERFLIX_PROFILE=b` e un secondo utente Jellyfin. Il plugin 1.3.0 è sul server.

1. **Pannello Coda.** A crea un party su un episodio di una serie, B entra. A apre il pannello Coda. Controlla:
   - le sezioni e la riga in corso in oro;
   - il riepilogo "N titoli · …h …m dopo questo";
   - all'apertura la lista è già scorsa sulla riga in corso.
2. **Salto.** A clicca un episodio dei prossimi. Tutti ci vanno, da 0. B vede "A ha scelto: …".
3. **Precedente.** A preme ⏮, poi P. B vede "A ha avviato il precedente: …". Sul primo titolo ⏮ non c'è.
4. **Togli e sposta.** A toglie un prossimo con ✕ e ne trascina un altro più in alto: B vede il pannello aggiornarsi, senza avvisi.
5. **Ordine casuale.** A attiva ⤮. Controlla:
   - B vede "A ha attivato l'ordine casuale";
   - a B il pannello mostra la coda mescolata, senza "Già visti";
   - A non vede l'avviso.

   Poi A lo spegne: torna l'ordine originale.
6. **Post-play dalla coda.** Con un film come prossimo (lo si mette con lo spostamento, se la serie è finita usare due episodi lontani), negli ultimi 30 s compare "Prossimo nella coda" con il titolo giusto.
7. **Da soli.** Su un episodio, ⏮, P e il tasto "indietro" del pannello multimediale di Windows aprono l'episodio prima, dal punto in cui era rimasto. Su un film ⏮ non c'è.
8. **Il pannello si chiude da solo:** quando compare il post-play, con Esc, e con un clic sul film.
