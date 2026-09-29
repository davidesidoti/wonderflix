# WonderFlix — Piano 5a: guardare un film insieme

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** il cuore dello Spec B. Due o più istanze di WonderFlix guardano **un film** insieme, sincronizzate:
- "Guarda insieme" nei dettagli di un film crea un gruppo SyncPlay e apre il player;
- il pulsante "Watch party · N" nella barra in alto elenca i gruppi e permette di unirsi;
- pausa, ripresa e salti valgono per tutti; il buffering di un membro fa aspettare tutti, con "Riprendi senza aspettare";
- lo scarto durante la visione si corregge con la velocità (0,95×/1,05×), con un salto solo sopra i 3 s;
- nel player: distintivo "Watch party · N" con i membri ed "Esci dal watch party", schermata di attesa;
- una seconda istanza per le prove (`WONDERFLIX_PROFILE`).

Serie, avvisi a pillola, inviti, creazione dal player, rientro automatico, permessi, errori con `SetIgnoreWait`, Discord e diagnostica sono del **Piano 5b**.

**Architecture:**
- **`lib/core/syncplay/` (Dart puro: nessun import di Flutter, media_kit o `dart:io`):**
  - `syncplay_models.dart`: gruppi, comandi, coda, aggiornamenti del gruppo e loro lettura dal JSON;
  - `syncplay_api.dart`: gli endpoint `/SyncPlay/*` e `/GetUtcTime` sopra `JellyfinHttp`;
  - `server_clock.dart`: stima dello scarto dall'orologio del server (metodo di NTP, come jellyfin-web);
  - `drift_corrector.dart`: decide, dallo scarto, se non fare nulla, cambiare velocità o risincronizzare.
- **`ServerEventsClient`** legge anche `SyncPlayCommand` e `SyncPlayGroupUpdate`.
- **`lib/features/watch_party/`:**
  - `WatchPartySession` (Riverpod, sopra le route): creare, entrare, uscire, stato del gruppo, coda, comandi, orologio;
  - `WatchPartyDirectory`: elenco dei gruppi ogni 30 s, per la barra in alto;
  - `watchPartyRoutingProvider`: apre il player quando il gruppo sceglie cosa guardare;
  - `GroupPlaybackDriver`: applica i comandi del gruppo al `VideoEngine`, corregge lo scarto, manda `Buffering`/`Ready`;
  - `GroupAuthority`: pausa, ripresa e salti dell'utente diventano richieste al gruppo;
  - interfaccia: pulsante della barra, "Guarda insieme", distintivo e schermata di attesa nel player.
- **Player:** `PlayerArgs` ha il campo `party` (id dell'elemento nella coda del gruppo). `PlayerController` passa pausa, ripresa e salti per una `PlaybackAuthority` (locale di default); in gruppo non avvia da solo la riproduzione e non salta l'intro in automatico.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router, dio, media_kit (`Player.setRate`), `clock` + `fake_async` per i test, `logging`.

**Spec:** `docs/superpowers/specs/2026-09-30-wonderflix-watch-party-design.md`. **Passaggio di consegne:** `docs/superpowers/handoff/2026-09-30-handoff-spec-b.md`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…". Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/watch-party-5a`, branch `feat/watch-party-5a`). Comandi git semplici, non composti con variabili.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde. Se `lib/l10n/gen` manca o è vecchio, esegui prima `flutter gen-l10n`.
- **File generati:** `flutter test` e `flutter pub get` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga. Se `git diff windows/flutter/` non mostra cambi di contenuto, esegui `git checkout -- windows/flutter/` prima del commit.
- **Formattazione:** non eseguire `dart format` su file interi.
- **Fine riga:** molti file sono CRLF (ARB, `main.dart`…). Modificali con Edit mirati, non riscriverli.
- **Import:** se l'analyzer segnala un import superfluo o mancante, correggilo e segnalalo.
- **Lint `use_null_aware_elements`:** nelle mappe scrivi `'key': ?value`.
- **Icone:** solo `LucideIcons` (verificate sulla 3.1.20: `users`, `logOut`, `hourglass`, `play`), niente emoji.
- **Tempo:** il codice nuovo legge l'ora solo con `clock.now()` (pacchetto `clock`), mai `DateTime.now()`. Nei test si usa `fakeAsync` (pacchetto `fake_async`), che sposta anche `clock.now()`.
- **Widget test:**
  - `pumpApp` (`test/support/pump_app.dart`) ha il parametro `surfaceSize`; non chiamare `setSurfaceSize` prima;
  - `pumpApp` non mette uno `Scaffold`: SnackBar e menu lo richiedono (`Scaffold(body: …)`);
  - i fake di motore e sessione media usano stream broadcast asincroni: dopo un evento può servire un `await tester.pump()` in più;
  - `find.byType` non trova le sottoclassi: per `WfButton.secondary` cerca il testo.
- **Log nei test:** nessuno ascolta `Logger.root`. Chi verifica i log si iscrive a `Logger.root.onRecord`.
- **Fake:** niente mocktail. I fake nuovi stanno in `test/support/watch_party_fakes.dart` (Task 7).

## Note tecniche verificate

- **SyncPlay in Jellyfin 10.11.9** (`docs/reference/jellyfin-openapi-10.11.9.json` e sorgenti del server `MediaBrowser.Controller/SyncPlay/GroupStates/`):
  - tutti gli endpoint sono `POST` tranne `GET /SyncPlay/List` e `GET /SyncPlay/{id}`; le risposte sono `204` (`/SyncPlay/New` può rispondere `200` con il `GroupInfoDto`: lo si ignora, la conferma arriva dal WebSocket);
  - `GroupInfoDto`: `GroupId`, `GroupName`, `State` (`Idle|Waiting|Paused|Playing`), `Participants` (**solo nomi utente**), `LastUpdatedAt`;
  - WebSocket `SyncPlayCommand` → `Data` = `SendCommand`: `GroupId`, `PlaylistItemId`, `When`, `PositionTicks` (può essere `null`), `Command` (`Unpause|Pause|Stop|Seek`), `EmittedAt`;
  - WebSocket `SyncPlayGroupUpdate` → `Data` = `{GroupId, Type, Data}`. `Type`: `GroupJoined` (Data = `GroupInfoDto`), `UserJoined`/`UserLeft` (Data = nome utente), `GroupLeft`, `NotInGroup`, `GroupDoesNotExist`, `LibraryAccessDenied` (Data = stringa), `StateUpdate` (Data = `{State, Reason}`), `PlayQueue` (Data = `{Reason, LastUpdate, Playlist: [{ItemId, PlaylistItemId}], PlayingItemIndex, StartPositionTicks, IsPlaying, ShuffleMode, RepeatMode}`);
  - **nessun proprietario del gruppo:** qualunque membro può mettere in pausa, riprendere e saltare;
  - **ingresso in un gruppo:** il server manda al nuovo membro `GroupJoined` e poi la coda (`PlayQueue`, `NewPlaylist`), mette gli altri in pausa (`Pause`) e aspetta il `Ready` del nuovo membro;
  - **`Ready`** (`When`, `PositionTicks`, `IsPlaying`, `PlaylistItemId`): con il gruppo in attesa e `IsPlaying: false`, se la posizione differisce di oltre 500 ms dalla posizione del gruppo, il server risponde con un `Seek` solo a quel client. Quando tutti sono pronti manda `Unpause` a tutti, con `When` nel futuro;
  - **`Buffering`** con il gruppo in riproduzione: il gruppo passa a `Waiting` e gli altri ricevono `Pause`;
  - **`Unpause` durante l'attesa** fa ripartire il gruppo senza aspettare chi non è pronto;
  - **`Seek`:** il gruppo passa a `Waiting`, tutti ricevono `Seek`, poi aspetta i `Ready`;
  - `GET /GetUtcTime` → `{RequestReceptionTime, ResponseTransmissionTime}` (UTC, anche senza autenticazione);
  - le date del server hanno 7 cifre decimali (`2026-09-30T10:00:00.1234567Z`): `DateTime.parse` le accetta e tronca ai microsecondi (verificato).
- **Tick:** 1 tick = 100 ns. In `lib/core/jellyfin/item_models.dart` ci sono già `ticksToDuration(int)` e `durationToTicks(Duration)`.
- **media_kit 1.2.6:** `Player.setRate(double)`. Con `PlayerConfiguration.pitch` a `false` (il nostro caso) imposta la proprietà `speed` di mpv, e mpv mantiene il tono dell'audio (`audio-pitch-correction` attivo di default).
- **Seconda istanza:** l'app è a istanza singola (mutex `Local\WonderFlix.SingleInstance` in `windows/runner/main.cpp`). Il server tratta due istanze con lo stesso `DeviceId` come **una sola sessione**. `DeviceId` sta nelle `SharedPreferences` (chiave `device_id`); `SharedPreferences.setPrefix(String)` (shared_preferences 2.5.5) va chiamato **prima** di `getInstance()`.
- **Riverpod 3:** tutte le risorse create in `build()` di un `Notifier` si chiudono con `ref.onDispose` (il `build` può essere rieseguito).
- **Navigazione:** il player è una route di primo livello (`/play/:id`) aperta con `push` sopra la `ShellRoute`, quindi `AppShell` resta montata sotto il player.

## Mappa dei file

```
lib/core/video/video_engine.dart                   + setRate
lib/core/video/media_kit_engine.dart               + setRate
lib/core/syncplay/syncplay_models.dart             modelli e lettura del JSON (nuovo)
lib/core/syncplay/syncplay_api.dart                SyncPlayApi, UtcTime, ClientPlaybackState (nuovo)
lib/core/syncplay/server_clock.dart                ServerClock, ClockSample (nuovo)
lib/core/syncplay/drift_corrector.dart             DriftCorrector, DriftAction (nuovo)
lib/core/jellyfin/server_events.dart               + SyncPlayCommandReceived, SyncPlayGroupUpdated
lib/core/storage/session_store.dart                chiave configurabile (seconda istanza)
lib/core/logging/app_log.dart                      cartella dei log per profilo
lib/app/dev_profile.dart                           profilo di sviluppo (nuovo)
lib/app/navigation.dart                            playerRoute(…, party:)
lib/app/router.dart                                PlayerArgs con party
lib/app/app.dart                                   osserva watchPartyRoutingProvider
lib/app/app_shell.dart                             + WatchPartyButton
lib/app/providers.dart                             chiave della sessione per profilo
lib/main.dart                                      prefisso delle preferenze per profilo
windows/runner/main.cpp                            mutex per profilo
lib/features/player/playback_authority.dart        PlaybackAuthority (nuovo)
lib/features/player/player_controller.dart         PlayerArgs.party, autorità, niente play/auto-skip in gruppo
lib/features/player/player_overlay.dart            + partyBadge
lib/features/player/player_screen.dart             modalità gruppo
lib/features/detail/detail_header.dart             + "Guarda insieme" (film)
lib/features/watch_party/watch_party_providers.dart  syncPlayApiProvider, watchPartyEventsProvider (nuovo)
lib/features/watch_party/watch_party_session.dart    WatchPartySession, WatchPartyState (nuovo)
lib/features/watch_party/watch_party_directory.dart  WatchPartyDirectory (nuovo)
lib/features/watch_party/watch_party_routing.dart    PartyNavigator, watchPartyRoutingProvider (nuovo)
lib/features/watch_party/group_playback_driver.dart  GroupPlaybackDriver (nuovo)
lib/features/watch_party/group_authority.dart        GroupAuthority (nuovo)
lib/features/watch_party/watch_party_actions.dart    startWatchParty, joinWatchParty, testi d'errore (nuovo)
lib/features/watch_party/watch_party_button.dart     pulsante e menu della barra in alto (nuovo)
lib/features/watch_party/party_badge.dart            distintivo e menu nel player (nuovo)
lib/features/watch_party/party_waiting_overlay.dart  schermata di attesa (nuovo)
l10n/app_it.arb, l10n/app_en.arb                   testi del watch party
test/support/watch_party_fakes.dart                FakeSyncPlayApi, FakeWatchPartyDirectory, FakePartyNavigator (nuovo)
test/support/playback_fakes.dart                   FakeVideoEngine.setRate
test/app/app_shell_test.dart, app_shell_back_button_test.dart  directory finta
```

## Gruppi per i subagent

| Gruppo | Task | Contenuto |
|---|---|---|
| A | 1–4 | `setRate`, modelli, messaggi WebSocket, API |
| B | 5–7 | orologio, correttore, testi e fake |
| C | 8–10 | player con autorità, sessione di gruppo, routing |
| D | 11–13 | driver (comandi, buffering, scarto) e autorità di gruppo |
| E | 14–15 | player in gruppo, barra in alto e "Guarda insieme" |
| F | 16–17 | seconda istanza, verifica finale |

---

### Task 1: `VideoEngine.setRate`

**Files:**
- Modify: `lib/core/video/video_engine.dart`
- Modify: `lib/core/video/media_kit_engine.dart`
- Modify: `test/support/playback_fakes.dart`

`MediaKitEngine` non si può provare senza libmpv: qui si aggiunge solo il metodo. Il fake registra le velocità per i test dei task successivi.

- [ ] **Step 1: aggiungi il metodo all'interfaccia**

In `lib/core/video/video_engine.dart`, dopo `Future<void> setVolume(double volume);`:

```dart
  /// Velocità di riproduzione (1.0 = normale). L'audio mantiene il tono. Il
  /// watch party la usa per recuperare piccoli scarti senza salti.
  Future<void> setRate(double rate);
```

- [ ] **Step 2: implementalo in `MediaKitEngine`**

In `lib/core/video/media_kit_engine.dart`, dopo `setVolume`:

```dart
  /// Con `PlayerConfiguration.pitch` a `false` media_kit imposta `speed` di
  /// mpv, che mantiene il tono dell'audio (`audio-pitch-correction`).
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
```

- [ ] **Step 3: aggiungilo a `FakeVideoEngine`**

In `test/support/playback_fakes.dart`, nella classe `FakeVideoEngine`, dopo `final volumes = <double>[];`:

```dart
  /// Velocità chieste con [setRate], in ordine (non registrate in [calls]).
  final rates = <double>[];

  /// Ultima velocità impostata.
  double currentRate = 1.0;
```

e dopo il metodo `setVolume`:

```dart
  @override
  Future<void> setRate(double rate) async {
    rates.add(rate);
    currentRate = rate;
  }
```

- [ ] **Step 4: verifica**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: tutti verdi.

- [ ] **Step 5: commit**

```bash
git add lib/core/video/video_engine.dart lib/core/video/media_kit_engine.dart test/support/playback_fakes.dart
git commit -m "feat: add playback rate control to the video engine"
```

---

### Task 2: modelli SyncPlay

**Files:**
- Create: `lib/core/syncplay/syncplay_models.dart`
- Test: `test/core/syncplay/syncplay_models_test.dart`

- [ ] **Step 1: scrivi i test**

`test/core/syncplay/syncplay_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';

void main() {
  test('GroupInfo dal JSON', () {
    final info = GroupInfo.fromJson({
      'GroupId': 'g1',
      'GroupName': 'Mario · Dune',
      'State': 'Playing',
      'Participants': ['Mario', 'Luigi'],
      'LastUpdatedAt': '2026-09-30T10:00:00.1234567Z',
    });
    expect(info.id, 'g1');
    expect(info.name, 'Mario · Dune');
    expect(info.state, GroupState.playing);
    expect(info.participants, ['Mario', 'Luigi']);
    expect(info.lastUpdatedAt, DateTime.utc(2026, 9, 30, 10, 0, 0, 123, 456));
  });

  test('GroupInfo: stato sconosciuto e campi mancanti', () {
    final info = GroupInfo.fromJson({'GroupId': 'g1', 'State': 'Nuovo'});
    expect(info.name, '');
    expect(info.state, GroupState.idle);
    expect(info.participants, isEmpty);
  });

  test('SyncPlayCommand dal JSON', () {
    final command = SyncPlayCommand.fromJson({
      'GroupId': 'g1',
      'PlaylistItemId': 'p1',
      'When': '2026-09-30T10:00:01Z',
      'PositionTicks': 6000000000,
      'Command': 'Unpause',
      'EmittedAt': '2026-09-30T10:00:00Z',
    })!;
    expect(command.groupId, 'g1');
    expect(command.playlistItemId, 'p1');
    expect(command.when, DateTime.utc(2026, 9, 30, 10, 0, 1));
    expect(command.position, const Duration(minutes: 10));
    expect(command.type, SyncPlayCommandType.unpause);
    expect(command.emittedAt, DateTime.utc(2026, 9, 30, 10));
  });

  test('SyncPlayCommand: posizione nulla, comando sconosciuto', () {
    final stop = SyncPlayCommand.fromJson({
      'GroupId': 'g1',
      'PlaylistItemId': '',
      'When': '2026-09-30T10:00:01Z',
      'PositionTicks': null,
      'Command': 'Stop',
      'EmittedAt': '2026-09-30T10:00:00Z',
    })!;
    expect(stop.position, Duration.zero);
    expect(stop.type, SyncPlayCommandType.stop);
    expect(
        SyncPlayCommand.fromJson({
          'GroupId': 'g1',
          'When': '2026-09-30T10:00:01Z',
          'Command': 'Rewind',
          'EmittedAt': '2026-09-30T10:00:00Z',
        }),
        isNull);
    expect(SyncPlayCommand.fromJson({'Command': 'Pause'}), isNull);
  });

  test('sameAs confronta comando, istante, posizione ed elemento', () {
    SyncPlayCommand command({String item = 'p1', int seconds = 1}) =>
        SyncPlayCommand(
          groupId: 'g1',
          playlistItemId: item,
          when: DateTime.utc(2026, 9, 30, 10, 0, seconds),
          position: const Duration(minutes: 10),
          type: SyncPlayCommandType.pause,
          emittedAt: DateTime.utc(2026, 9, 30, 10, 0, seconds),
        );
    expect(command().sameAs(command()), isTrue);
    expect(command().sameAs(command(item: 'p2')), isFalse);
    expect(command().sameAs(command(seconds: 2)), isFalse);
  });

  test('parseGroupUpdate: tutti i tipi', () {
    Map<String, dynamic> update(String type, Object? data) =>
        {'GroupId': 'g1', 'Type': type, 'Data': data};

    final joined = parseGroupUpdate(update('GroupJoined', {
      'GroupId': 'g1',
      'GroupName': 'Mario · Dune',
      'State': 'Idle',
      'Participants': ['Mario'],
      'LastUpdatedAt': '2026-09-30T10:00:00Z',
    }));
    expect(joined, isA<GroupJoined>());
    expect((joined as GroupJoined).info.participants, ['Mario']);
    expect(joined.groupId, 'g1');

    expect((parseGroupUpdate(update('UserJoined', 'Luigi')) as UserJoined)
            .userName,
        'Luigi');
    expect((parseGroupUpdate(update('UserLeft', 'Luigi')) as UserLeft)
            .userName,
        'Luigi');
    expect(parseGroupUpdate(update('GroupLeft', 'g1')), isA<GroupLeft>());
    expect(parseGroupUpdate(update('NotInGroup', '')), isA<NotInGroup>());
    expect(parseGroupUpdate(update('GroupDoesNotExist', '')),
        isA<GroupDoesNotExist>());
    expect(parseGroupUpdate(update('LibraryAccessDenied', '')),
        isA<LibraryAccessDenied>());

    final state = parseGroupUpdate(
        update('StateUpdate', {'State': 'Waiting', 'Reason': 'Buffer'}));
    expect((state as GroupStateUpdate).state, GroupState.waiting);
    expect(state.reason, 'Buffer');

    final queue = parseGroupUpdate(update('PlayQueue', {
      'Reason': 'NewPlaylist',
      'LastUpdate': '2026-09-30T10:00:00Z',
      'Playlist': [
        {'ItemId': 'm1', 'PlaylistItemId': 'p1'},
        {'ItemId': 'm2', 'PlaylistItemId': 'p2'},
      ],
      'PlayingItemIndex': 1,
      'StartPositionTicks': 600000000,
      'IsPlaying': true,
      'ShuffleMode': 'Sorted',
      'RepeatMode': 'RepeatNone',
    }));
    final playQueue = (queue as PlayQueueUpdate).queue;
    expect(playQueue.reason, 'NewPlaylist');
    expect(playQueue.lastUpdate, DateTime.utc(2026, 9, 30, 10));
    expect(playQueue.entries.map((e) => e.itemId), ['m1', 'm2']);
    expect(playQueue.playing?.playlistItemId, 'p2');
    expect(playQueue.startPosition, const Duration(minutes: 1));
    expect(playQueue.isPlaying, isTrue);
  });

  test('parseGroupUpdate: forme non valide', () {
    expect(parseGroupUpdate(null), isNull);
    expect(parseGroupUpdate({'GroupId': 'g1', 'Type': 'Sconosciuto'}),
        isNull);
    expect(parseGroupUpdate({'GroupId': 'g1', 'Type': 'GroupJoined', 'Data': 3}),
        isNull);
  });

  test('coda senza elemento in riproduzione', () {
    final queue = PlayQueue.fromJson({
      'Reason': 'RemoveItems',
      'LastUpdate': '2026-09-30T10:00:00Z',
      'Playlist': [],
      'PlayingItemIndex': -1,
    });
    expect(queue.playing, isNull);
    expect(queue.startPosition, Duration.zero);
    expect(queue.isPlaying, isFalse);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/core/syncplay/syncplay_models_test.dart`
Expected: FAIL (il file `syncplay_models.dart` non esiste).

- [ ] **Step 3: scrivi i modelli**

`lib/core/syncplay/syncplay_models.dart`:

```dart
import 'package:logging/logging.dart';

import '../jellyfin/item_models.dart';

final _log = Logger('watchparty');

/// Stato di un gruppo SyncPlay (`GroupStateType`).
enum GroupState { idle, waiting, paused, playing }

GroupState? parseGroupState(Object? value) => switch (value) {
      'Idle' => GroupState.idle,
      'Waiting' => GroupState.waiting,
      'Paused' => GroupState.paused,
      'Playing' => GroupState.playing,
      _ => null,
    };

/// Date del server (UTC, fino a 7 decimali: si tronca ai microsecondi).
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

/// Un gruppo come lo descrive il server (`GroupInfoDto`).
class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    required this.state,
    required this.participants,
    required this.lastUpdatedAt,
  });

  /// Lancia se manca `GroupId`.
  factory GroupInfo.fromJson(Map<String, dynamic> json) => GroupInfo(
        id: json['GroupId'] as String,
        name: json['GroupName'] as String? ?? '',
        state: parseGroupState(json['State']) ?? GroupState.idle,
        participants: (json['Participants'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        lastUpdatedAt: _date(json['LastUpdatedAt']) ?? DateTime.utc(1970),
      );

  final String id;
  final String name;
  final GroupState state;

  /// Nomi utente dei membri (il server non dà altro).
  final List<String> participants;

  /// Quando il server ha creato questa descrizione.
  final DateTime lastUpdatedAt;

  GroupInfo copyWith({GroupState? state, List<String>? participants}) =>
      GroupInfo(
        id: id,
        name: name,
        state: state ?? this.state,
        participants: participants ?? this.participants,
        lastUpdatedAt: lastUpdatedAt,
      );
}

enum SyncPlayCommandType { unpause, pause, stop, seek }

/// Comando del gruppo (`SendCommand`): cosa fare, da quale posizione e a
/// quale istante (orario del server).
class SyncPlayCommand {
  const SyncPlayCommand({
    required this.groupId,
    required this.playlistItemId,
    required this.when,
    required this.position,
    required this.type,
    required this.emittedAt,
  });

  /// `null` se il comando è sconosciuto o mancano gli istanti.
  static SyncPlayCommand? fromJson(Map<String, dynamic> json) {
    final type = switch (json['Command']) {
      'Unpause' => SyncPlayCommandType.unpause,
      'Pause' => SyncPlayCommandType.pause,
      'Stop' => SyncPlayCommandType.stop,
      'Seek' => SyncPlayCommandType.seek,
      _ => null,
    };
    final when = _date(json['When']);
    final emittedAt = _date(json['EmittedAt']);
    if (type == null || when == null || emittedAt == null) return null;
    return SyncPlayCommand(
      groupId: json['GroupId'] as String? ?? '',
      playlistItemId: json['PlaylistItemId'] as String? ?? '',
      when: when,
      position: ticksToDuration(_int(json['PositionTicks']) ?? 0),
      type: type,
      emittedAt: emittedAt,
    );
  }

  final String groupId;
  final String playlistItemId;

  /// Istante (orario del server) in cui eseguire il comando.
  final DateTime when;
  final Duration position;
  final SyncPlayCommandType type;
  final DateTime emittedAt;

  /// Stesso comando ricevuto di nuovo (il server a volte lo ripete).
  bool sameAs(SyncPlayCommand other) =>
      type == other.type &&
      when == other.when &&
      position == other.position &&
      playlistItemId == other.playlistItemId;

  @override
  String toString() => 'SyncPlayCommand(${type.name}, $position, $when, '
      '$playlistItemId)';
}

/// Elemento della coda del gruppo.
class PlayQueueEntry {
  const PlayQueueEntry({required this.itemId, required this.playlistItemId});

  final String itemId;

  /// Id dell'elemento *nella coda* (lo stesso film due volte ha due id).
  final String playlistItemId;
}

/// Coda del gruppo (`PlayQueueUpdate`).
class PlayQueue {
  const PlayQueue({
    required this.reason,
    required this.lastUpdate,
    required this.entries,
    required this.playingIndex,
    required this.startPosition,
    required this.isPlaying,
  });

  factory PlayQueue.fromJson(Map<String, dynamic> json) => PlayQueue(
        reason: json['Reason'] as String? ?? '',
        lastUpdate: _date(json['LastUpdate']) ?? DateTime.utc(1970),
        entries: [
          for (final entry in (json['Playlist'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
            if (entry['ItemId'] is String && entry['PlaylistItemId'] is String)
              PlayQueueEntry(
                itemId: entry['ItemId'] as String,
                playlistItemId: entry['PlaylistItemId'] as String,
              ),
        ],
        playingIndex: _int(json['PlayingItemIndex']) ?? -1,
        startPosition: ticksToDuration(_int(json['StartPositionTicks']) ?? 0),
        isPlaying: json['IsPlaying'] as bool? ?? false,
      );

  /// Cosa ha cambiato la coda (`NewPlaylist`, `NextItem`…).
  final String reason;

  /// Ultima modifica della coda (orario del server).
  final DateTime lastUpdate;
  final List<PlayQueueEntry> entries;
  final int playingIndex;

  /// Posizione del gruppo quando il server ha mandato la coda.
  final Duration startPosition;
  final bool isPlaying;

  PlayQueueEntry? get playing =>
      playingIndex >= 0 && playingIndex < entries.length
          ? entries[playingIndex]
          : null;
}

/// Aggiornamento del gruppo (`SyncPlayGroupUpdate`).
sealed class GroupUpdate {
  const GroupUpdate(this.groupId);

  final String groupId;
}

/// Siamo entrati (o abbiamo creato il gruppo).
final class GroupJoined extends GroupUpdate {
  const GroupJoined(super.groupId, this.info);

  final GroupInfo info;
}

final class UserJoined extends GroupUpdate {
  const UserJoined(super.groupId, this.userName);

  final String userName;
}

final class UserLeft extends GroupUpdate {
  const UserLeft(super.groupId, this.userName);

  final String userName;
}

final class GroupLeft extends GroupUpdate {
  const GroupLeft(super.groupId);
}

final class NotInGroup extends GroupUpdate {
  const NotInGroup(super.groupId);
}

final class GroupDoesNotExist extends GroupUpdate {
  const GroupDoesNotExist(super.groupId);
}

final class LibraryAccessDenied extends GroupUpdate {
  const LibraryAccessDenied(super.groupId);
}

/// Il gruppo è passato a [state]; [reason] è la richiesta che l'ha causato
/// (`Pause`, `Seek`, `Buffer`…).
final class GroupStateUpdate extends GroupUpdate {
  const GroupStateUpdate(super.groupId, this.state, this.reason);

  final GroupState state;
  final String? reason;
}

final class PlayQueueUpdate extends GroupUpdate {
  const PlayQueueUpdate(super.groupId, this.queue);

  final PlayQueue queue;
}

/// Il `Data` di un messaggio `SyncPlayGroupUpdate`; `null` se non valido o
/// di un tipo che non usiamo.
GroupUpdate? parseGroupUpdate(Object? data) {
  if (data is! Map<String, dynamic>) return null;
  final groupId = data['GroupId'] as String? ?? '';
  final payload = data['Data'];
  try {
    switch (data['Type']) {
      case 'GroupJoined':
        if (payload is! Map<String, dynamic>) return null;
        return GroupJoined(groupId, GroupInfo.fromJson(payload));
      case 'UserJoined':
        return UserJoined(groupId, payload as String? ?? '');
      case 'UserLeft':
        return UserLeft(groupId, payload as String? ?? '');
      case 'GroupLeft':
        return GroupLeft(groupId);
      case 'NotInGroup':
        return NotInGroup(groupId);
      case 'GroupDoesNotExist':
        return GroupDoesNotExist(groupId);
      case 'LibraryAccessDenied':
        return LibraryAccessDenied(groupId);
      case 'StateUpdate':
        if (payload is! Map<String, dynamic>) return null;
        final state = parseGroupState(payload['State']);
        if (state == null) return null;
        return GroupStateUpdate(groupId, state, payload['Reason'] as String?);
      case 'PlayQueue':
        if (payload is! Map<String, dynamic>) return null;
        return PlayQueueUpdate(groupId, PlayQueue.fromJson(payload));
      default:
        _log.info('aggiornamento SyncPlay non gestito: ${data['Type']}');
        return null;
    }
  } on Object catch (error) {
    _log.warning('aggiornamento SyncPlay non valido: $error');
    return null;
  }
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/core/syncplay/syncplay_models_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/syncplay/syncplay_models.dart test/core/syncplay/syncplay_models_test.dart
git commit -m "feat: add SyncPlay models and message parsing"
```

---

### Task 3: messaggi SyncPlay dal WebSocket

**Files:**
- Modify: `lib/core/jellyfin/server_events.dart`
- Test: `test/core/jellyfin/server_events_test.dart`

- [ ] **Step 1: scrivi il test**

In `test/core/jellyfin/server_events_test.dart` aggiungi l'import:

```dart
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
```

e dentro `main()`, dopo il test `'parseServerMessage'`:

```dart
  test('parseServerMessage: messaggi SyncPlay', () {
    final command = parseServerMessage(jsonEncode({
      'MessageType': 'SyncPlayCommand',
      'Data': {
        'GroupId': 'g1',
        'PlaylistItemId': 'p1',
        'When': '2026-09-30T10:00:01Z',
        'PositionTicks': 0,
        'Command': 'Pause',
        'EmittedAt': '2026-09-30T10:00:00Z',
      },
    }));
    expect(command, isA<SyncPlayCommandReceived>());
    expect((command as SyncPlayCommandReceived).command.type,
        SyncPlayCommandType.pause);

    final update = parseServerMessage(jsonEncode({
      'MessageType': 'SyncPlayGroupUpdate',
      'Data': {'GroupId': 'g1', 'Type': 'UserJoined', 'Data': 'Luigi'},
    }));
    expect(update, isA<SyncPlayGroupUpdated>());
    expect(((update as SyncPlayGroupUpdated).update as UserJoined).userName,
        'Luigi');

    expect(
        parseServerMessage(jsonEncode({
          'MessageType': 'SyncPlayCommand',
          'Data': {'Command': 'Boh'},
        })),
        isNull);
    expect(
        parseServerMessage(jsonEncode({
          'MessageType': 'SyncPlayGroupUpdate',
          'Data': {'GroupId': 'g1', 'Type': 'Boh'},
        })),
        isNull);
  });
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/core/jellyfin/server_events_test.dart`
Expected: FAIL (`SyncPlayCommandReceived` non definito).

- [ ] **Step 3: aggiungi gli eventi**

In `lib/core/jellyfin/server_events.dart`, aggiungi l'import (dopo `import 'item_models.dart';`):

```dart
import '../syncplay/syncplay_models.dart';
```

Dopo la classe `ForceKeepAlive`:

```dart
/// Comando del gruppo SyncPlay di cui facciamo parte.
final class SyncPlayCommandReceived extends ServerEvent {
  const SyncPlayCommandReceived(this.command);

  final SyncPlayCommand command;
}

/// Aggiornamento del gruppo SyncPlay (membri, stato, coda, errori).
final class SyncPlayGroupUpdated extends ServerEvent {
  const SyncPlayGroupUpdated(this.update);

  final GroupUpdate update;
}
```

In `parseServerMessage`, prima di `default:`:

```dart
      case 'SyncPlayCommand':
        if (data is! Map<String, dynamic>) return null;
        final command = SyncPlayCommand.fromJson(data);
        return command == null ? null : SyncPlayCommandReceived(command);
      case 'SyncPlayGroupUpdate':
        final update = parseGroupUpdate(data);
        return update == null ? null : SyncPlayGroupUpdated(update);
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/core/jellyfin/server_events_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/jellyfin/server_events.dart test/core/jellyfin/server_events_test.dart
git commit -m "feat: read SyncPlay messages from the server WebSocket"
```

---

### Task 4: `SyncPlayApi`

**Files:**
- Create: `lib/core/syncplay/syncplay_api.dart`
- Test: `test/core/syncplay/syncplay_api_test.dart`

Solo gli endpoint del Piano 5a. `NextItem`, `SetIgnoreWait` e gli altri arrivano con il 5b.

- [ ] **Step 1: scrivi i test**

`test/core/syncplay/syncplay_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/syncplay/syncplay_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SyncPlayApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SyncPlayApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Map<String, dynamic>? body() =>
      adapter.requests.single.data as Map<String, dynamic>?;

  test('create, join, leave', () async {
    await api.create('Mario · Dune');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/SyncPlay/New');
    expect(body(), {'GroupName': 'Mario · Dune'});

    adapter.requests.clear();
    await api.join('g1');
    expect(adapter.requests.single.path, '/SyncPlay/Join');
    expect(body(), {'GroupId': 'g1'});

    adapter.requests.clear();
    await api.leave();
    expect(adapter.requests.single.path, '/SyncPlay/Leave');
  });

  test('create accetta anche la risposta 200 con il gruppo', () async {
    adapter.handler = (_) => const FakeResponse(200, {'GroupId': 'g1'});
    await api.create('Mario · Dune');
    expect(adapter.requests.single.path, '/SyncPlay/New');
  });

  test('list legge i gruppi e scarta quelli non validi', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {
            'GroupId': 'g1',
            'GroupName': 'Mario · Dune',
            'State': 'Paused',
            'Participants': ['Mario'],
            'LastUpdatedAt': '2026-09-30T10:00:00Z',
          },
          {'GroupName': 'senza id'},
        ]);
    final groups = await api.list();
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/SyncPlay/List');
    expect(groups.single.id, 'g1');
    expect(groups.single.state, GroupState.paused);
  });

  test('list con una risposta non valida', () async {
    adapter.handler = (_) => const FakeResponse(200, {'non': 'lista'});
    expect(api.list(), throwsA(isA<ServerErrorException>()));
  });

  test('coda, pausa, ripresa, salto', () async {
    await api.setNewQueue(['m1'], start: const Duration(minutes: 1));
    expect(adapter.requests.single.path, '/SyncPlay/SetNewQueue');
    expect(body(), {
      'PlayingQueue': ['m1'],
      'PlayingItemPosition': 0,
      'StartPositionTicks': 600000000,
    });

    adapter.requests.clear();
    await api.pause();
    expect(adapter.requests.single.path, '/SyncPlay/Pause');

    adapter.requests.clear();
    await api.unpause();
    expect(adapter.requests.single.path, '/SyncPlay/Unpause');

    adapter.requests.clear();
    await api.seek(const Duration(seconds: 90));
    expect(adapter.requests.single.path, '/SyncPlay/Seek');
    expect(body(), {'PositionTicks': 900000000});
  });

  test('buffering, ready, ping', () async {
    final state = ClientPlaybackState(
      when: DateTime.utc(2026, 9, 30, 10),
      position: const Duration(minutes: 10),
      isPlaying: true,
      playlistItemId: 'p1',
    );
    await api.buffering(state);
    expect(adapter.requests.single.path, '/SyncPlay/Buffering');
    expect(body(), {
      'When': '2026-09-30T10:00:00.000Z',
      'PositionTicks': 6000000000,
      'IsPlaying': true,
      'PlaylistItemId': 'p1',
    });

    adapter.requests.clear();
    await api.ready(state);
    expect(adapter.requests.single.path, '/SyncPlay/Ready');
    expect(body()!['PlaylistItemId'], 'p1');

    adapter.requests.clear();
    await api.ping(const Duration(milliseconds: 42));
    expect(adapter.requests.single.path, '/SyncPlay/Ping');
    expect(body(), {'Ping': 42});
  });

  test('utcTime legge i due istanti del server', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'RequestReceptionTime': '2026-09-30T10:00:00.1000000Z',
          'ResponseTransmissionTime': '2026-09-30T10:00:00.1050000Z',
        });
    final time = await api.utcTime();
    expect(adapter.requests.single.path, '/GetUtcTime');
    expect(time.requestReceived, DateTime.utc(2026, 9, 30, 10, 0, 0, 100));
    expect(time.responseSent, DateTime.utc(2026, 9, 30, 10, 0, 0, 105));
  });

  test('utcTime con una risposta non valida', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Boh': 1});
    expect(api.utcTime(), throwsA(isA<ServerErrorException>()));
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/core/syncplay/syncplay_api_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi l'API**

`lib/core/syncplay/syncplay_api.dart`:

```dart
import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/item_models.dart';
import '../jellyfin/jellyfin_http.dart';
import 'syncplay_models.dart';

final _log = Logger('watchparty');

/// I due istanti di `/GetUtcTime` (orario del server).
class UtcTime {
  const UtcTime({required this.requestReceived, required this.responseSent});

  final DateTime requestReceived;
  final DateTime responseSent;
}

/// Stato del nostro player da riferire al gruppo (`Buffering` e `Ready`).
class ClientPlaybackState {
  const ClientPlaybackState({
    required this.when,
    required this.position,
    required this.isPlaying,
    required this.playlistItemId,
  });

  /// Orario del server a cui si riferisce [position].
  final DateTime when;
  final Duration position;
  final bool isPlaying;
  final String playlistItemId;

  Map<String, dynamic> toJson() => {
        'When': when.toUtc().toIso8601String(),
        'PositionTicks': durationToTicks(position),
        'IsPlaying': isPlaying,
        'PlaylistItemId': playlistItemId,
      };
}

/// Endpoint SyncPlay di Jellyfin 10.11. Lancia solo `ApiException`. Le
/// conferme arrivano dal WebSocket (`SyncPlayGroupUpdate`).
class SyncPlayApi {
  SyncPlayApi(this._http);

  final JellyfinHttp _http;

  /// Crea un gruppo e ci entra.
  Future<void> create(String name) =>
      _post('/SyncPlay/New', {'GroupName': name});

  Future<void> join(String groupId) =>
      _post('/SyncPlay/Join', {'GroupId': groupId});

  Future<void> leave() => _post('/SyncPlay/Leave');

  /// Gruppi di cui l'utente può vedere la coda.
  Future<List<GroupInfo>> list() async {
    final data = await _http.get('/SyncPlay/List');
    if (data is! List) throw const ServerErrorException(null);
    final groups = <GroupInfo>[];
    for (final json in data.whereType<Map<String, dynamic>>()) {
      try {
        groups.add(GroupInfo.fromJson(json));
      } on Object catch (error) {
        _log.warning('gruppo non valido: $error');
      }
    }
    return groups;
  }

  /// Nuova coda del gruppo: si parte da [itemIds][[playingIndex]] a [start].
  Future<void> setNewQueue(List<String> itemIds,
          {int playingIndex = 0, Duration start = Duration.zero}) =>
      _post('/SyncPlay/SetNewQueue', {
        'PlayingQueue': itemIds,
        'PlayingItemPosition': playingIndex,
        'StartPositionTicks': durationToTicks(start),
      });

  Future<void> pause() => _post('/SyncPlay/Pause');

  /// Riprende; con il gruppo in attesa riparte senza aspettare gli altri.
  Future<void> unpause() => _post('/SyncPlay/Unpause');

  Future<void> seek(Duration position) =>
      _post('/SyncPlay/Seek', {'PositionTicks': durationToTicks(position)});

  Future<void> buffering(ClientPlaybackState state) =>
      _post('/SyncPlay/Buffering', state.toJson());

  Future<void> ready(ClientPlaybackState state) =>
      _post('/SyncPlay/Ready', state.toJson());

  /// Ping verso il server, che lo usa per calcolare i ritardi dei comandi.
  Future<void> ping(Duration ping) =>
      _post('/SyncPlay/Ping', {'Ping': ping.inMilliseconds});

  Future<UtcTime> utcTime() async {
    final json = asJsonMap(await _http.get('/GetUtcTime'));
    final received = DateTime.tryParse(
        json['RequestReceptionTime'] as String? ?? '');
    final sent = DateTime.tryParse(
        json['ResponseTransmissionTime'] as String? ?? '');
    if (received == null || sent == null) {
      throw const ServerErrorException(null);
    }
    return UtcTime(requestReceived: received.toUtc(), responseSent: sent.toUtc());
  }

  Future<void> _post(String path, [Map<String, dynamic>? body]) async {
    await _http.post(path, body: body);
  }
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/core/syncplay/syncplay_api_test.dart`
Expected: PASS. Se il test "create accetta anche la risposta 200" fallisce per il tipo di risposta, controlla che `_post` non provi a leggere il corpo.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/syncplay/syncplay_api.dart test/core/syncplay/syncplay_api_test.dart
git commit -m "feat: add the SyncPlay API client"
```

---
### Task 5: `ServerClock`

**Files:**
- Create: `lib/core/syncplay/server_clock.dart`
- Test: `test/core/syncplay/server_clock_test.dart`

Metodo di NTP, come jellyfin-web (`TimeSync.js`): t0 invio, t1 ricezione sul server, t2 risposta del server, t3 ricezione. Offset = ((t1 − t0) + (t2 − t3)) / 2, ritardo = (t3 − t0) − (t2 − t1). Si tengono le ultime 8 misure e si usa quella con il ritardo più basso. 3 misure a 1 s di distanza, poi una ogni 60 s.

- [ ] **Step 1: scrivi i test**

`test/core/syncplay/server_clock_test.dart`:

```dart
import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/server_clock.dart';

/// Server con l'orologio avanti di [offset]. Ogni misura usa la coppia
/// successiva di [legs] (andata, ritorno); l'ultima si ripete.
ServerTimeFetcher fakeServer(Duration offset,
    [List<(Duration, Duration)> legs = const [(Duration.zero, Duration.zero)]]) {
  var index = 0;
  return () async {
    final (out, back) = legs[min(index++, legs.length - 1)];
    await Future<void>.delayed(out);
    final serverTime = clock.now().toUtc().add(offset);
    await Future<void>.delayed(back);
    return (serverReceived: serverTime, serverSent: serverTime);
  };
}

void main() {
  test('ClockSample: offset, ritardo e ping', () {
    final t0 = DateTime.utc(2026, 9, 30, 10);
    final sample = ClockSample(
      sent: t0,
      serverReceived: t0.add(const Duration(milliseconds: 2050)),
      serverSent: t0.add(const Duration(milliseconds: 2060)),
      received: t0.add(const Duration(milliseconds: 110)),
    );
    expect(sample.offset, const Duration(seconds: 2));
    expect(sample.delay, const Duration(milliseconds: 100));
    expect(sample.ping, const Duration(milliseconds: 50));
  });

  test('prima misura, conversioni e ping', () {
    fakeAsync((async) {
      const ms50 = Duration(milliseconds: 50);
      final pings = <Duration>[];
      final serverClock = ServerClock(
        fetch: fakeServer(const Duration(seconds: 2), [(ms50, ms50)]),
        onPing: pings.add,
      );
      var first = false;
      unawaited(serverClock.firstSample.then((_) => first = true));
      expect(serverClock.ready, isFalse);
      expect(serverClock.offset, Duration.zero);

      serverClock.start();
      async.elapse(const Duration(milliseconds: 100));
      expect(first, isTrue);
      expect(serverClock.ready, isTrue);
      expect(serverClock.offset, const Duration(seconds: 2));
      expect(serverClock.ping, ms50);
      expect(pings, [ms50]);

      final local = DateTime.utc(2026, 9, 30, 10);
      expect(serverClock.toServer(local), local.add(const Duration(seconds: 2)));
      expect(serverClock.toLocal(local),
          local.subtract(const Duration(seconds: 2)));
      expect(serverClock.serverNow().difference(clock.now().toUtc()),
          const Duration(seconds: 2));
      serverClock.stop();
    });
  });

  test('3 misure a 1 s di distanza, poi una ogni 60 s', () {
    fakeAsync((async) {
      var calls = 0;
      final serverClock = ServerClock(fetch: () async {
        calls++;
        final now = clock.now().toUtc();
        return (serverReceived: now, serverSent: now);
      });
      serverClock.start();
      async.flushMicrotasks();
      expect(calls, 1);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 2);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 3);
      async.elapse(const Duration(seconds: 59));
      expect(calls, 3);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 4);
      async.elapse(const Duration(seconds: 60));
      expect(calls, 5);

      serverClock.stop();
      async.elapse(const Duration(minutes: 5));
      expect(calls, 5);
    });
  });

  test('usa la misura con il ritardo più basso', () {
    fakeAsync((async) {
      // Andata e ritorno asimmetrici falsano l'offset: la misura migliore è
      // quella con il ritardo più basso (20+20 ms, offset esatto).
      final serverClock = ServerClock(
        fetch: fakeServer(const Duration(seconds: 1), const [
          (Duration(milliseconds: 300), Duration(milliseconds: 100)),
          (Duration(milliseconds: 20), Duration(milliseconds: 20)),
          (Duration(milliseconds: 150), Duration(milliseconds: 50)),
        ]),
      );
      serverClock.start();
      async.elapse(const Duration(milliseconds: 500));
      expect(serverClock.offset, const Duration(milliseconds: 1100));
      async.elapse(const Duration(seconds: 5));
      expect(serverClock.offset, const Duration(seconds: 1));
      expect(serverClock.ping, const Duration(milliseconds: 20));
      serverClock.stop();
    });
  });

  test('misure non riuscite: si riprova, senza diventare pronto', () {
    fakeAsync((async) {
      var calls = 0;
      final serverClock = ServerClock(fetch: () async {
        calls++;
        throw Exception('rete');
      });
      serverClock.start();
      async.elapse(const Duration(seconds: 3));
      expect(calls, 3);
      expect(serverClock.ready, isFalse);
      serverClock.stop();
    });
  });

  test('una risposta che arriva dopo stop() viene ignorata', () {
    fakeAsync((async) {
      final serverClock = ServerClock(
        fetch: fakeServer(Duration.zero, const [
          (Duration(milliseconds: 100), Duration(milliseconds: 100)),
        ]),
      );
      serverClock.start();
      async.elapse(const Duration(milliseconds: 50));
      serverClock.stop();
      async.elapse(const Duration(seconds: 5));
      expect(serverClock.ready, isFalse);
    });
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/core/syncplay/server_clock_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi `ServerClock`**

`lib/core/syncplay/server_clock.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';

final _log = Logger('watchparty');

/// Una misura dell'orologio del server, con il metodo di NTP.
class ClockSample {
  factory ClockSample({
    required DateTime sent,
    required DateTime serverReceived,
    required DateTime serverSent,
    required DateTime received,
  }) {
    final offset = Duration(
        microseconds: (serverReceived.difference(sent).inMicroseconds +
                serverSent.difference(received).inMicroseconds) ~/
            2);
    final delay =
        received.difference(sent) - serverSent.difference(serverReceived);
    return ClockSample._(offset, delay);
  }

  const ClockSample._(this.offset, this.delay);

  /// Orario del server − orario locale.
  final Duration offset;

  /// Andata e ritorno in rete, senza il tempo passato sul server.
  final Duration delay;

  Duration get ping => Duration(microseconds: delay.inMicroseconds ~/ 2);
}

/// Chiede al server i suoi due istanti (`/GetUtcTime`).
typedef ServerTimeFetcher = Future<({DateTime serverReceived, DateTime serverSent})>
    Function();

/// Stima dell'orologio del server, per eseguire i comandi del gruppo
/// all'istante giusto. Usa solo `clock.now()`: nei test il tempo è finto.
class ServerClock {
  ServerClock({required ServerTimeFetcher fetch, void Function(Duration)? onPing})
      : _fetch = fetch,
        _onPing = onPing;

  static const greedyInterval = Duration(seconds: 1);
  static const greedyCount = 3;
  static const slowInterval = Duration(seconds: 60);
  static const maxSamples = 8;

  final ServerTimeFetcher _fetch;

  /// Chiamato dopo ogni misura riuscita con il ping della misura migliore
  /// (il gruppo lo manda al server con `/SyncPlay/Ping`).
  final void Function(Duration ping)? _onPing;

  final _samples = <ClockSample>[];
  final _first = Completer<void>();
  ClockSample? _best;
  Timer? _timer;
  bool _running = false;
  int _taken = 0;

  /// `true` dopo la prima misura riuscita.
  bool get ready => _best != null;

  /// Si completa alla prima misura riuscita.
  Future<void> get firstSample => _first.future;

  Duration get offset => _best?.offset ?? Duration.zero;

  Duration get ping => _best?.ping ?? Duration.zero;

  /// Ora locale (UTC).
  DateTime now() => clock.now().toUtc();

  DateTime serverNow() => toServer(clock.now());

  DateTime toServer(DateTime local) => local.toUtc().add(offset);

  DateTime toLocal(DateTime server) => server.toUtc().subtract(offset);

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_measure());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _measure() async {
    if (!_running) return;
    final sent = clock.now().toUtc();
    try {
      final (:serverReceived, :serverSent) = await _fetch();
      final received = clock.now().toUtc();
      if (!_running) return;
      _add(ClockSample(
        sent: sent,
        serverReceived: serverReceived,
        serverSent: serverSent,
        received: received,
      ));
      _onPing?.call(ping);
    } on Object catch (error) {
      _log.info('misura dell\'orologio del server non riuscita: $error');
    }
    if (!_running) return;
    _taken++;
    _timer = Timer(_taken < greedyCount ? greedyInterval : slowInterval,
        () => unawaited(_measure()));
  }

  void _add(ClockSample sample) {
    _samples.add(sample);
    if (_samples.length > maxSamples) _samples.removeAt(0);
    _best = _samples.reduce((a, b) => b.delay < a.delay ? b : a);
    if (!_first.isCompleted) _first.complete();
    _log.fine('orologio: offset ${offset.inMilliseconds} ms, '
        'ping ${ping.inMilliseconds} ms');
  }
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/core/syncplay/server_clock_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/syncplay/server_clock.dart test/core/syncplay/server_clock_test.dart
git commit -m "feat: estimate the server clock offset for SyncPlay"
```

---

### Task 6: `DriftCorrector`

**Files:**
- Create: `lib/core/syncplay/drift_corrector.dart`
- Test: `test/core/syncplay/drift_corrector_test.dart`

Regole dello spec (§4.4): media delle ultime 3 letture; sotto i 150 ms niente; tra 150 ms e 3 s velocità 1,05× (indietro) o 0,95× (avanti); si torna a 1,0× sotto i 40 ms o se si supera il bersaglio; oltre 3 s si risincronizza con un salto; niente correzioni nei primi 1,5 s dopo la ripresa e nei 5 s dopo un salto.

- [ ] **Step 1: scrivi i test**

`test/core/syncplay/drift_corrector_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/drift_corrector.dart';

void main() {
  const ms = Duration(milliseconds: 1);
  late DriftCorrector corrector;

  setUp(() => corrector = DriftCorrector());

  DriftAction feed(Duration drift,
          {double rate = 1.0,
          Duration sinceUnpause = const Duration(seconds: 10),
          Duration? sinceResync}) =>
      corrector.update(
          drift: drift,
          rate: rate,
          sinceUnpause: sinceUnpause,
          sinceResync: sinceResync);

  /// Tre letture uguali: riempie la finestra della media.
  DriftAction steady(Duration drift, {double rate = 1.0}) {
    feed(drift, rate: rate);
    feed(drift, rate: rate);
    return feed(drift, rate: rate);
  }

  double rateOf(DriftAction action) => (action as ChangeRate).rate;

  test('servono 3 letture prima di agire', () {
    expect(feed(ms * 500), isA<KeepRate>());
    expect(feed(ms * 500), isA<KeepRate>());
    expect(rateOf(feed(ms * 500)), DriftCorrector.fastRate);
  });

  test('zona morta: sotto i 150 ms nessuna correzione', () {
    expect(steady(ms * 149), isA<KeepRate>());
    corrector.reset();
    expect(steady(ms * -149), isA<KeepRate>());
  });

  test('indietro accelera, avanti rallenta', () {
    expect(rateOf(steady(ms * 150)), 1.05);
    corrector.reset();
    expect(rateOf(steady(ms * -2999)), 0.95);
  });

  test('isteresi: si torna a 1,0 solo sotto i 40 ms', () {
    expect(steady(ms * 100, rate: 1.05), isA<KeepRate>());
    expect(rateOf(steady(ms * 39, rate: 1.05)), 1.0);
    corrector.reset();
    expect(rateOf(steady(ms * -39, rate: 0.95)), 1.0);
  });

  test('bersaglio superato: si torna a 1,0', () {
    expect(rateOf(steady(ms * -60, rate: 1.05)), 1.0);
    corrector.reset();
    expect(rateOf(steady(ms * 60, rate: 0.95)), 1.0);
  });

  test('oltre 3 s: risincronizza e svuota la finestra', () {
    expect(steady(ms * 3001), isA<Resync>());
    expect(feed(ms * 3001), isA<KeepRate>());
    corrector.reset();
    expect(steady(ms * -3001), isA<Resync>());
  });

  test('primi 1,5 s dopo la ripresa: nessuna correzione', () {
    expect(feed(ms * 500, sinceUnpause: ms * 1499), isA<KeepRate>());
    expect(rateOf(feed(ms * 500, rate: 1.05, sinceUnpause: ms * 100)), 1.0);
    // La finestra riparte da zero finito il periodo iniziale.
    expect(feed(ms * 500), isA<KeepRate>());
    expect(feed(ms * 500), isA<KeepRate>());
    expect(rateOf(feed(ms * 500)), 1.05);
  });

  test('5 s dopo un salto: nessuna correzione', () {
    feed(ms * 500, sinceResync: ms * 4999);
    feed(ms * 500, sinceResync: ms * 4999);
    expect(feed(ms * 500, sinceResync: ms * 4999), isA<KeepRate>());
    feed(ms * 500, sinceResync: ms * 5000);
    feed(ms * 500, sinceResync: ms * 5000);
    expect(rateOf(feed(ms * 500, sinceResync: ms * 5000)), 1.05);
  });

  test('lastDrift: media dell\'ultima finestra piena', () {
    expect(corrector.lastDrift, isNull);
    feed(ms * 100);
    feed(ms * 200);
    feed(ms * 300);
    expect(corrector.lastDrift, ms * 200);
  });

  test('reset svuota la finestra', () {
    feed(ms * 500);
    feed(ms * 500);
    corrector.reset();
    expect(feed(ms * 500), isA<KeepRate>());
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/core/syncplay/drift_corrector_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi il correttore**

`lib/core/syncplay/drift_corrector.dart`:

```dart
/// Cosa fare dello scarto dal gruppo.
sealed class DriftAction {
  const DriftAction();
}

/// Lasciare la velocità com'è.
final class KeepRate extends DriftAction {
  const KeepRate();
}

final class ChangeRate extends DriftAction {
  const ChangeRate(this.rate);

  final double rate;
}

/// Scarto troppo grande: saltare alla posizione del gruppo.
final class Resync extends DriftAction {
  const Resync();
}

/// Decide come recuperare lo scarto durante la visione (spec B §4.4). Non
/// legge l'ora e non tocca il player: riceve i tempi dal chiamante.
class DriftCorrector {
  static const deadZone = Duration(milliseconds: 150);
  static const settleZone = Duration(milliseconds: 40);
  static const resyncThreshold = Duration(seconds: 3);
  static const fastRate = 1.05;
  static const slowRate = 0.95;
  static const startGrace = Duration(milliseconds: 1500);
  static const resyncCooldown = Duration(seconds: 5);
  static const window = 3;

  final _samples = <Duration>[];
  Duration? _lastDrift;

  /// Media dell'ultima finestra piena (per i log); `null` all'inizio.
  Duration? get lastDrift => _lastDrift;

  void reset() => _samples.clear();

  /// [drift] = posizione attesa − posizione locale: positivo se siamo
  /// indietro. [rate] è la velocità attuale del player.
  DriftAction update({
    required Duration drift,
    required double rate,
    required Duration sinceUnpause,
    Duration? sinceResync,
  }) {
    final settling = sinceUnpause < startGrace ||
        (sinceResync != null && sinceResync < resyncCooldown);
    if (settling) {
      _samples.clear();
      return rate == 1.0 ? const KeepRate() : const ChangeRate(1.0);
    }
    _samples.add(drift);
    if (_samples.length > window) _samples.removeAt(0);
    if (_samples.length < window) return const KeepRate();
    final average = Duration(
        microseconds: _samples.fold<int>(
                0, (sum, sample) => sum + sample.inMicroseconds) ~/
            _samples.length);
    _lastDrift = average;
    final size = average.abs();
    if (size > resyncThreshold) {
      _samples.clear();
      return const Resync();
    }
    if (rate != 1.0) {
      // Se si sta accelerando, il bersaglio è superato quando lo scarto
      // diventa negativo (e viceversa).
      final overshoot =
          rate > 1.0 ? average.isNegative : average > Duration.zero;
      if (size < settleZone || overshoot) return const ChangeRate(1.0);
      return const KeepRate();
    }
    if (size >= deadZone) {
      return ChangeRate(average > Duration.zero ? fastRate : slowRate);
    }
    return const KeepRate();
  }
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/core/syncplay/drift_corrector_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/syncplay/drift_corrector.dart test/core/syncplay/drift_corrector_test.dart
git commit -m "feat: add drift correction rules for the watch party"
```

---

### Task 7: testi del watch party e `FakeSyncPlayApi`

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan5a_test.dart`
- Create: `test/support/watch_party_fakes.dart`

- [ ] **Step 1: scrivi il test dei testi**

`test/app/l10n_plan5a_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 5a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.watchPartyWatchTogether, 'Guarda insieme');
    expect(en.watchPartyWatchTogether, 'Watch together');
    expect(it.watchPartyButton(3), 'Watch party · 3');
    expect(it.watchPartyListTitle, 'Watch party attivi');
    expect(it.watchPartyJoin, 'Unisciti');
    expect(it.watchPartyMembers(1), '1 persona');
    expect(it.watchPartyMembers(3), '3 persone');
    expect(en.watchPartyMembers(3), '3 people');
    expect(it.watchPartyStateIdle, 'Fermo');
    expect(it.watchPartyStateWaiting, 'In attesa');
    expect(it.watchPartyStatePaused, 'In pausa');
    expect(it.watchPartyStatePlaying, 'In riproduzione');
    expect(it.watchPartyLeave, 'Esci dal watch party');
    expect(it.watchPartyWaiting, 'In attesa degli altri membri…');
    expect(it.watchPartyResumeNow, 'Riprendi senza aspettare');
    expect(en.watchPartyResumeNow, 'Resume without waiting');
    expect(it.watchPartyCreateError,
        'Non è stato possibile avviare il watch party.');
    expect(it.watchPartyJoinError,
        'Non è stato possibile entrare nel watch party.');
    expect(it.watchPartyGone, 'Questo watch party non esiste più.');
    expect(it.watchPartyAccessDenied, 'Non hai accesso a questo contenuto.');
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/l10n_plan5a_test.dart`
Expected: FAIL (getter mancanti).

- [ ] **Step 3: aggiungi i testi**

`l10n/app_it.arb` è CRLF: usa Edit sull'ultima riga, `"updateDownloadFailed": "Download non riuscito. Controlla la connessione e riprova."`, aggiungendo una virgola e poi queste righe (prima della `}` finale):

```json
  "watchPartyWatchTogether": "Guarda insieme",
  "watchPartyButton": "Watch party · {count}",
  "@watchPartyButton": {"placeholders": {"count": {"type": "int"}}},
  "watchPartyListTitle": "Watch party attivi",
  "watchPartyJoin": "Unisciti",
  "watchPartyMembers": "{count, plural, =1{1 persona} other{{count} persone}}",
  "@watchPartyMembers": {"placeholders": {"count": {"type": "int"}}},
  "watchPartyStateIdle": "Fermo",
  "watchPartyStateWaiting": "In attesa",
  "watchPartyStatePaused": "In pausa",
  "watchPartyStatePlaying": "In riproduzione",
  "watchPartyLeave": "Esci dal watch party",
  "watchPartyWaiting": "In attesa degli altri membri…",
  "watchPartyResumeNow": "Riprendi senza aspettare",
  "watchPartyCreateError": "Non è stato possibile avviare il watch party.",
  "watchPartyJoinError": "Non è stato possibile entrare nel watch party.",
  "watchPartyGone": "Questo watch party non esiste più.",
  "watchPartyAccessDenied": "Non hai accesso a questo contenuto."
```

`l10n/app_en.arb`, stesso metodo dopo `"updateDownloadFailed": "Download failed. Check your connection and try again."`:

```json
  "watchPartyWatchTogether": "Watch together",
  "watchPartyButton": "Watch party · {count}",
  "watchPartyListTitle": "Active watch parties",
  "watchPartyJoin": "Join",
  "watchPartyMembers": "{count, plural, =1{1 person} other{{count} people}}",
  "watchPartyStateIdle": "Stopped",
  "watchPartyStateWaiting": "Waiting",
  "watchPartyStatePaused": "Paused",
  "watchPartyStatePlaying": "Playing",
  "watchPartyLeave": "Leave watch party",
  "watchPartyWaiting": "Waiting for the others…",
  "watchPartyResumeNow": "Resume without waiting",
  "watchPartyCreateError": "Couldn't start the watch party.",
  "watchPartyJoinError": "Couldn't join the watch party.",
  "watchPartyGone": "This watch party no longer exists.",
  "watchPartyAccessDenied": "You don't have access to this content."
```

Run: `flutter gen-l10n`
Expected: nessun errore.

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/app/l10n_plan5a_test.dart`
Expected: PASS.

- [ ] **Step 5: crea `FakeSyncPlayApi`**

`test/support/watch_party_fakes.dart`:

```dart
import 'package:clock/clock.dart';
import 'package:wonderflix/core/syncplay/syncplay_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';

/// `SyncPlayApi` in memoria: registra le chiamate. Il server "risponde"
/// tramite [onCall], con cui i test mandano gli eventi del WebSocket.
class FakeSyncPlayApi implements SyncPlayApi {
  /// Chiamate in ordine, es. `create Mario · Dune`, `join g1`, `pause`,
  /// `seek 0:01:30.000000`, `ready`. `ping` e `utcTime` non compaiono.
  final calls = <String>[];
  final queues =
      <({List<String> itemIds, int playingIndex, Duration start})>[];
  final readyStates = <ClientPlaybackState>[];
  final bufferingStates = <ClientPlaybackState>[];
  final pings = <Duration>[];

  /// Risposta di [list].
  List<GroupInfo> groups = const [];

  /// Se valorizzato, ogni chiamata registrata lancia questo errore.
  Object? error;

  /// Orologio del server rispetto a `clock.now()`.
  Duration serverOffset = Duration.zero;

  /// Chiamato dopo aver registrato ogni chiamata.
  void Function(String call)? onCall;

  Future<void> _record(String call) async {
    calls.add(call);
    onCall?.call(call);
    final failure = error;
    if (failure != null) throw failure;
  }

  @override
  Future<void> create(String name) => _record('create $name');

  @override
  Future<void> join(String groupId) => _record('join $groupId');

  @override
  Future<void> leave() => _record('leave');

  @override
  Future<List<GroupInfo>> list() async {
    await _record('list');
    return groups;
  }

  @override
  Future<void> setNewQueue(List<String> itemIds,
      {int playingIndex = 0, Duration start = Duration.zero}) {
    queues.add((itemIds: itemIds, playingIndex: playingIndex, start: start));
    return _record('queue ${itemIds.join(',')}');
  }

  @override
  Future<void> pause() => _record('pause');

  @override
  Future<void> unpause() => _record('unpause');

  @override
  Future<void> seek(Duration position) => _record('seek $position');

  @override
  Future<void> buffering(ClientPlaybackState state) {
    bufferingStates.add(state);
    return _record('buffering');
  }

  @override
  Future<void> ready(ClientPlaybackState state) {
    readyStates.add(state);
    return _record('ready');
  }

  @override
  Future<void> ping(Duration ping) async => pings.add(ping);

  @override
  Future<UtcTime> utcTime() async {
    final now = clock.now().toUtc().add(serverOffset);
    return UtcTime(requestReceived: now, responseSent: now);
  }
}

/// Gruppo di prova: `g1`, "Mario · Dune", in pausa.
GroupInfo testGroup({
  String id = 'g1',
  String name = 'Mario · Dune',
  GroupState state = GroupState.paused,
  List<String> participants = const ['Mario'],
}) =>
    GroupInfo(
      id: id,
      name: name,
      state: state,
      participants: participants,
      lastUpdatedAt: DateTime.utc(2026, 9, 30, 10),
    );

/// Coda di prova con un solo elemento.
PlayQueue testQueue({
  String itemId = 'm1',
  String playlistItemId = 'p1',
  Duration start = Duration.zero,
  bool isPlaying = false,
  DateTime? lastUpdate,
}) =>
    PlayQueue(
      reason: 'NewPlaylist',
      lastUpdate: lastUpdate ?? DateTime.utc(2026, 9, 30, 10),
      entries: [PlayQueueEntry(itemId: itemId, playlistItemId: playlistItemId)],
      playingIndex: 0,
      startPosition: start,
      isPlaying: isPlaying,
    );
```

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add l10n/app_it.arb l10n/app_en.arb test/app/l10n_plan5a_test.dart test/support/watch_party_fakes.dart
git commit -m "feat: add watch party strings and test fakes"
```

---
### Task 8: player con `party` e `PlaybackAuthority`

**Files:**
- Create: `lib/features/player/playback_authority.dart`
- Modify: `lib/features/player/player_controller.dart`
- Modify: `lib/app/navigation.dart`
- Modify: `lib/app/router.dart`
- Modify: `test/features/player/player_controller_test.dart`
- Modify: `test/features/player/player_screen_test.dart` (solo gli argomenti)
- Modify: `test/app/navigation_test.dart`

`PlayerArgs` è la chiave del provider del player: aggiungere un campo al record obbliga ad aggiornare tutti i letterali `(itemId: …, start: …)`. Oggi sono tre: `lib/app/router.dart`, `test/features/player/player_controller_test.dart`, `test/features/player/player_screen_test.dart`. Verificalo con `grep -rn "start: " lib test | grep "itemId"`.

- [ ] **Step 1: scrivi i test del percorso**

In `test/app/navigation_test.dart`, dopo il test `'playerRoute con schermo intero'`:

```dart
  test('playerRoute nel watch party', () {
    expect(playerRoute('m1', party: 'p1'), '/play/m1?party=p1');
    expect(
        playerRoute('m1',
            start: const Duration(seconds: 1), fullscreen: true, party: 'p1'),
        '/play/m1?start=1000&fs=1&party=p1');
  });
```

- [ ] **Step 2: scrivi i test del controller**

In `test/features/player/player_controller_test.dart`:
- sostituisci `const args = (itemId: 'm1', start: Duration(minutes: 3));` con `const args = (itemId: 'm1', start: Duration(minutes: 3), party: null);`
- aggiungi l'import `import 'package:wonderflix/features/player/playback_authority.dart';`
- in fondo al file, fuori da `main()`:

```dart
/// Autorità che registra le richieste invece di muovere il motore.
class RecordingAuthority implements PlaybackAuthority {
  final calls = <String>[];

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seekTo(Duration position) async => calls.add('seek $position');
}
```

- dentro `main()`, in fondo:

```dart
  group('watch party', () {
    const partyArgs =
        (itemId: 'm1', start: Duration(minutes: 3), party: 'p1');
    final partyProvider = playerControllerProvider(partyArgs);

    Future<PlayerController> startParty() async {
      container.listen(partyProvider, (_, _) {});
      await pumpEventQueue();
      return container.read(partyProvider.notifier);
    }

    test('il file si apre in pausa e non parte da solo', () async {
      final controller = await startParty();
      expect(controller.inParty, isTrue);
      expect(container.read(partyProvider).status, PlayerStatus.ready);
      expect(engine.opened.single.start, const Duration(minutes: 3));
      expect(engine.calls, isNot(contains('play')));
      expect(container.read(partyProvider).playing, isFalse);
    });

    test('pausa, ripresa e salti passano per l\'autorità', () async {
      final controller = await startParty();
      final authority = RecordingAuthority();
      controller.setAuthority(authority);
      await controller.togglePlay();
      await controller.seekTo(const Duration(hours: 5));
      await controller.seekBy(const Duration(seconds: -10));
      await controller.pause();
      await controller.play();
      expect(authority.calls, [
        'play',
        'seek ${const Duration(hours: 2)}',
        'seek ${const Duration(minutes: 2, seconds: 50)}',
        'pause',
        'play',
      ]);
      expect(engine.seeks, isEmpty);

      // Senza autorità si torna al motore.
      controller.setAuthority(null);
      await controller.seekTo(const Duration(minutes: 1));
      expect(engine.seeks, [const Duration(minutes: 1)]);
    });

    test('niente salto automatico dell\'intro', () async {
      settings = const PlayerSettings(autoSkipIntro: true);
      playback.segments = const [
        MediaSegment(
            type: MediaSegmentType.intro,
            start: Duration(seconds: 10),
            end: Duration(seconds: 90)),
      ];
      await startParty();
      engine.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();
      expect(engine.seeks, isEmpty);
    });
  });
```

Nota: `seekBy(-10 s)` parte dalla posizione del motore (3:00), quindi chiede 2:50.

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/app/navigation_test.dart test/features/player/player_controller_test.dart`
Expected: FAIL (parametro `party` e `playback_authority.dart` mancanti).

- [ ] **Step 4: crea l'interfaccia**

`lib/features/player/playback_authority.dart`:

```dart
/// Chi esegue pausa, ripresa e salti chiesti dall'utente: il player stesso
/// oppure, nel watch party, il gruppo.
abstract interface class PlaybackAuthority {
  Future<void> play();

  Future<void> pause();

  /// [position] è già entro i limiti del video.
  Future<void> seekTo(Duration position);
}
```

- [ ] **Step 5: aggiorna il controller**

In `lib/features/player/player_controller.dart`:

1. Aggiungi l'import `import 'playback_authority.dart';`.
2. Sostituisci il typedef:

```dart
/// Elemento da riprodurre, posizione di partenza e, nel watch party, id
/// dell'elemento nella coda del gruppo (chiave del provider).
typedef PlayerArgs = ({String itemId, Duration start, String? party});
```

3. Dopo `final _autoSkipped = <Duration>{};`:

```dart
  /// Pausa, ripresa e salti chiesti dall'utente.
  late PlaybackAuthority _authority = _LocalAuthority(this);

  /// Il player fa parte di un watch party: parte e si ferma con il gruppo.
  bool get inParty => args.party != null;

  /// `null` = di nuovo il player stesso.
  void setAuthority(PlaybackAuthority? authority) =>
      _authority = authority ?? _LocalAuthority(this);
```

4. In `_start`, sostituisci:

```dart
      // Il file è aperto in pausa: parte solo con le tracce già scelte.
      await _engine.play();
      if (stale()) return;
```

con:

```dart
      // Il file è aperto in pausa: parte solo con le tracce già scelte. Nel
      // watch party parte con il comando del gruppo.
      if (!inParty) {
        await _engine.play();
        if (stale()) return;
      }
```

5. Sostituisci `togglePlay`, `play`, `pause` e `seekTo`:

```dart
  Future<void> togglePlay() async {
    if (!_ready) return;
    await (_engine.playing ? _authority.pause() : _authority.play());
  }

  /// Riprende la riproduzione; se è già in corso non cambia nulla (tasti
  /// del pannello media, che possono arrivare su uno stato non aggiornato).
  Future<void> play() async {
    if (!_ready) return;
    await _authority.play();
  }

  /// Mette in pausa; se lo è già non cambia nulla.
  Future<void> pause() async {
    if (!_ready) return;
    await _authority.pause();
  }

  /// Salta a [position], entro i limiti del video.
  Future<void> seekTo(Duration position) async {
    if (!_ready) return;
    final duration = _engine.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (duration > Duration.zero && target > duration) target = duration;
    await _authority.seekTo(target);
  }
```

6. In `_onPosition` la prima riga diventa:

```dart
    if (!_settings.autoSkipIntro || inParty || !_ready) return;
```

7. In fondo al file, dopo `playerControllerProvider`:

```dart
/// Il player esegue da sé pausa, ripresa e salti.
class _LocalAuthority implements PlaybackAuthority {
  _LocalAuthority(this._controller);

  final PlayerController _controller;

  @override
  Future<void> play() => _controller._engine.play();

  @override
  Future<void> pause() => _controller._engine.pause();

  @override
  Future<void> seekTo(Duration position) async {
    await _controller._engine.seek(position);
    _controller._reporter?.onEvent();
  }
}
```

- [ ] **Step 6: aggiorna percorso e router**

In `lib/app/navigation.dart` sostituisci `playerRoute`:

```dart
/// Percorso del player; [start] è la posizione di partenza, [fullscreen]
/// dice che la finestra è già a schermo intero (passaggio all'episodio
/// successivo), [party] è l'id dell'elemento nella coda del watch party.
String playerRoute(String itemId,
    {Duration start = Duration.zero, bool fullscreen = false, String? party}) {
  final query = {
    if (start > Duration.zero) 'start': '${start.inMilliseconds}',
    if (fullscreen) 'fs': '1',
    'party': ?party,
  };
  return Uri(
    path: '/play/$itemId',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}
```

In `lib/app/router.dart`, negli `args` di `PlayerScreen`, dopo `start: playerStartFrom(state.uri),`:

```dart
              party: state.uri.queryParameters['party'],
```

In `test/features/player/player_screen_test.dart`, negli `args` di `pumpPlayer`, stessa riga dopo `start: playerStartFrom(state.uri),`.

- [ ] **Step 7: verifica che passino**

Run: `flutter test test/app/navigation_test.dart test/features/player/`
Expected: PASS.

- [ ] **Step 8: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/player/playback_authority.dart lib/features/player/player_controller.dart lib/app/navigation.dart lib/app/router.dart test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart test/app/navigation_test.dart
git commit -m "feat: let the player follow an external playback authority"
```

---

### Task 9: `WatchPartySession`

**Files:**
- Create: `lib/features/watch_party/watch_party_providers.dart`
- Create: `lib/features/watch_party/watch_party_session.dart`
- Test: `test/features/watch_party/watch_party_session_test.dart`

La sessione vive per tutto il login e non conosce il player: espone lo stato del gruppo, i comandi (stream), l'ultimo comando, l'orologio del server e l'API.

- [ ] **Step 1: crea i provider di base**

`lib/features/watch_party/watch_party_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../library/server_events_binding.dart';

final syncPlayApiProvider =
    Provider<SyncPlayApi>((ref) => SyncPlayApi(ref.watch(jellyfinHttpProvider)));

/// Eventi del WebSocket per il watch party. Tiene aperto il WebSocket anche
/// se la barra superiore non è montata.
final watchPartyEventsProvider = Provider<Stream<ServerEvent>>((ref) {
  ref.watch(serverEventsBindingProvider);
  return ref.watch(serverEventsClientProvider).events;
});
```

- [ ] **Step 2: scrivi i test**

`test/features/watch_party/watch_party_session_test.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
  });

  tearDown(() => events.close());

  /// Crea il container e monta la sessione. Nei test con `fakeAsync` va
  /// chiamato dentro la zona finta: gli eventi arrivano nella zona in cui la
  /// sessione si è iscritta allo stream.
  void mount() {
    container = ProviderContainer.test(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
    ]);
    container.listen(watchPartySessionProvider, (_, _) {});
  }

  WatchPartySession session() =>
      container.read(watchPartySessionProvider.notifier);
  WatchPartyState state() => container.read(watchPartySessionProvider);
  void emit(GroupUpdate update) => events.add(SyncPlayGroupUpdated(update));

  /// Il server conferma l'ingresso appena riceve `create` o `join`.
  void serverAccepts({List<String> participants = const ['Mario']}) {
    api.onCall = (call) {
      if (call.startsWith('create') || call.startsWith('join')) {
        emit(GroupJoined('g1', testGroup(participants: participants)));
      }
    };
  }

  SyncPlayCommand command(SyncPlayCommandType type,
          {DateTime? emittedAt, String group = 'g1'}) =>
      SyncPlayCommand(
        groupId: group,
        playlistItemId: 'p1',
        when: DateTime.utc(2026, 9, 30, 11),
        position: const Duration(minutes: 5),
        type: type,
        emittedAt: emittedAt ?? DateTime.utc(2026, 9, 30, 11),
      );

  test('create: nome del gruppo, conferma e coda', () async {
    mount();
    serverAccepts();
    await session().create(testItem(id: 'm1', name: 'Dune'),
        start: const Duration(minutes: 1));
    expect(api.calls, ['create Mario · Dune', 'queue m1']);
    expect(api.queues.single.start, const Duration(minutes: 1));
    expect(state().phase, WatchPartyPhase.inGroup);
    expect(state().group?.id, 'g1');
    expect(state().members, ['Mario']);
  });

  test('create per un episodio: nel nome c\'è la serie', () async {
    mount();
    serverAccepts();
    await session().create(testItem(
        id: 'e1',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad'));
    expect(api.calls.first, 'create Mario · Breaking Bad');
  });

  test('join, poi membri che entrano ed escono', () async {
    mount();
    serverAccepts(participants: ['Mario', 'Luigi']);
    await session().join('g1');
    expect(api.calls, ['join g1']);
    expect(state().members, ['Mario', 'Luigi']);

    emit(const UserJoined('g1', 'Peach'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi', 'Peach']);

    emit(const UserLeft('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Peach']);

    // Aggiornamenti di un altro gruppo: ignorati.
    emit(const UserJoined('g2', 'Bowser'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Peach']);
  });

  test('id dei gruppi con e senza trattini', () async {
    mount();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        emit(GroupJoined('AAAA-BBBB', testGroup(id: 'AAAA-BBBB')));
      }
    };
    await session().join('AAAA-BBBB');
    emit(const UserJoined('aaaabbbb', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi']);
  });

  test('stato del gruppo e coda; le code vecchie si scartano', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
    await pumpEventQueue();
    expect(state().groupState, GroupState.waiting);

    emit(PlayQueueUpdate(
        'g1', testQueue(lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await pumpEventQueue();
    expect(state().queue?.playing?.playlistItemId, 'p1');

    emit(PlayQueueUpdate('g1',
        testQueue(playlistItemId: 'p0', lastUpdate: DateTime.utc(2026, 9, 30, 10))));
    await pumpEventQueue();
    expect(state().queue?.playing?.playlistItemId, 'p1');
  });

  test('gruppo inesistente', () async {
    mount();
    api.onCall = (call) => emit(const GroupDoesNotExist(''));
    await expectLater(
        session().join('g9'),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.groupGone)));
    expect(state().phase, WatchPartyPhase.none);
  });

  test('accesso negato', () async {
    mount();
    api.onCall = (call) => emit(const LibraryAccessDenied('g1'));
    await expectLater(
        session().join('g1'),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.accessDenied)));
    expect(state().phase, WatchPartyPhase.none);
  });

  test('errore di rete', () async {
    mount();
    api.error = const ServerUnreachableException();
    await expectLater(
        session().join('g1'),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.network)));
    expect(state().phase, WatchPartyPhase.none);
  });

  test('coda non impostata: si esce dal gruppo appena creato', () async {
    mount();
    api.onCall = (call) {
      if (call.startsWith('create')) {
        emit(GroupJoined('g1', testGroup()));
      }
      if (call.startsWith('queue')) throw const ServerErrorException(500);
    };
    await expectLater(
        session().create(testItem()),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.network)));
    expect(api.calls.last, 'leave');
    expect(state().phase, WatchPartyPhase.none);
  });

  test('nessuna conferma entro 10 s', () {
    fakeAsync((async) {
      mount();
      Object? error;
      unawaited(session().join('g1').catchError((Object e) {
        error = e;
      }));
      async.elapse(const Duration(seconds: 9));
      expect(error, isNull);
      expect(state().phase, WatchPartyPhase.joining);
      async.elapse(const Duration(seconds: 1));
      expect((error! as WatchPartyException).failure,
          WatchPartyFailure.timeout);
      expect(state().phase, WatchPartyPhase.none);

      // Una conferma che arriva tardi: si esce subito dal gruppo.
      emit(GroupJoined('g1', testGroup()));
      async.flushMicrotasks();
      expect(api.calls.last, 'leave');
      expect(state().phase, WatchPartyPhase.none);
    });
  });

  test('leave: una volta sola', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    await session().leave();
    expect(api.calls, ['join g1', 'leave']);
    expect(state().phase, WatchPartyPhase.none);
    await session().leave();
    expect(api.calls, ['join g1', 'leave']);
  });

  test('il server ci toglie dal gruppo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    emit(const GroupLeft('g1'));
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
  });

  test('comandi: solo del gruppo e non più vecchi dell\'ingresso', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final received = <SyncPlayCommand>[];
    final subscription = session().commands.listen(received.add);
    addTearDown(subscription.cancel);

    // testGroup().lastUpdatedAt = 10:00: questo è di prima.
    events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.pause,
        emittedAt: DateTime.utc(2026, 9, 30, 9, 59))));
    events.add(SyncPlayCommandReceived(
        command(SyncPlayCommandType.pause, group: 'g2')));
    events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.unpause)));
    await pumpEventQueue();
    expect(received.map((c) => c.type), [SyncPlayCommandType.unpause]);
    expect(session().lastCommand?.type, SyncPlayCommandType.unpause);
  });

  test('orologio: parte con l\'ingresso e riferisce il ping', () async {
    mount();
    serverAccepts();
    expect(session().serverClock, isNull);
    await session().join('g1');
    await pumpEventQueue();
    expect(session().serverClock?.ready, isTrue);
    expect(api.pings, isNotEmpty);
    await session().leave();
    expect(session().serverClock, isNull);
  });

  test('estimatedPosition: dalla coda o dall\'ultimo comando', () {
    fakeAsync((async) {
      mount();
      serverAccepts();
      unawaited(session().join('g1'));
      async.flushMicrotasks();
      expect(session().estimatedPosition(), Duration.zero);

      emit(PlayQueueUpdate('g1', testQueue(start: const Duration(minutes: 7))));
      async.flushMicrotasks();
      expect(session().estimatedPosition(), const Duration(minutes: 7));

      final now = clock.now().toUtc();
      events.add(SyncPlayCommandReceived(SyncPlayCommand(
        groupId: 'g1',
        playlistItemId: 'p1',
        when: now.subtract(const Duration(seconds: 2)),
        position: const Duration(minutes: 5),
        type: SyncPlayCommandType.unpause,
        emittedAt: DateTime.utc(2100),
      )));
      async.flushMicrotasks();
      expect(session().estimatedPosition(),
          const Duration(minutes: 5, seconds: 2));

      events.add(SyncPlayCommandReceived(SyncPlayCommand(
        groupId: 'g1',
        playlistItemId: 'p1',
        when: now,
        position: const Duration(minutes: 6),
        type: SyncPlayCommandType.pause,
        emittedAt: DateTime.utc(2100, 1, 1, 0, 0, 1),
      )));
      async.flushMicrotasks();
      expect(session().estimatedPosition(), const Duration(minutes: 6));
      unawaited(session().leave());
      async.flushMicrotasks();
    });
  });

  test('logout: si torna a nessun gruppo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    await container.read(sessionControllerProvider.notifier).logout();
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
  });
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/features/watch_party/watch_party_session_test.dart`
Expected: FAIL (`watch_party_session.dart` mancante).

- [ ] **Step 4: scrivi la sessione**

`lib/features/watch_party/watch_party_session.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/syncplay/server_clock.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../auth/session_controller.dart';
import 'watch_party_providers.dart';

final _log = Logger('watchparty');

enum WatchPartyPhase { none, joining, inGroup }

enum WatchPartyFailure { groupGone, accessDenied, timeout, network }

class WatchPartyException implements Exception {
  const WatchPartyException(this.failure);

  final WatchPartyFailure failure;

  @override
  String toString() => 'WatchPartyException(${failure.name})';
}

class WatchPartyState {
  const WatchPartyState({
    this.phase = WatchPartyPhase.none,
    this.group,
    this.groupState = GroupState.idle,
    this.queue,
  });

  final WatchPartyPhase phase;
  final GroupInfo? group;
  final GroupState groupState;
  final PlayQueue? queue;

  bool get inGroup => phase == WatchPartyPhase.inGroup;

  List<String> get members => group?.participants ?? const [];

  WatchPartyState copyWith(
          {GroupInfo? group, GroupState? groupState, PlayQueue? queue}) =>
      WatchPartyState(
        phase: phase,
        group: group ?? this.group,
        groupState: groupState ?? this.groupState,
        queue: queue ?? this.queue,
      );
}

/// Titolo nel nome del gruppo: l'elenco dei gruppi del server non dice cosa
/// si sta guardando. Per un episodio vale il nome della serie.
String partyTitle(JellyfinItem item) => item.seriesName ?? item.name;

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Il watch party dell'utente (spec B §5): creare, entrare, uscire, stato
/// del gruppo, coda, comandi e orologio del server. Non conosce il player.
class WatchPartySession extends Notifier<WatchPartyState> {
  static const joinTimeout = Duration(seconds: 10);

  late SyncPlayApi _api;
  late StreamController<SyncPlayCommand> _commands;
  ServerClock? _clock;
  SyncPlayCommand? _lastCommand;
  Completer<void>? _joining;
  DateTime? _joinedAt;

  @override
  WatchPartyState build() {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _api = ref.watch(syncPlayApiProvider);
    final commands = _commands = StreamController<SyncPlayCommand>.broadcast();
    _clock = null;
    _lastCommand = null;
    _joining = null;
    _joinedAt = null;
    ref.onDispose(() {
      _stopClock();
      unawaited(commands.close());
    });
    if (userId == null) return const WatchPartyState();
    final subscription = ref.watch(watchPartyEventsProvider).listen(_onEvent);
    ref.onDispose(() => unawaited(subscription.cancel()));
    return const WatchPartyState();
  }

  SyncPlayApi get api => _api;

  /// Orologio del server; `null` fuori da un gruppo.
  ServerClock? get serverClock => _clock;

  /// Comandi del gruppo, già filtrati (solo il nostro gruppo, nessuno più
  /// vecchio dell'ingresso).
  Stream<SyncPlayCommand> get commands => _commands.stream;

  SyncPlayCommand? get lastCommand => _lastCommand;

  /// Crea un gruppo per [item] e ci fa partire la riproduzione da [start].
  /// Lancia [WatchPartyException].
  Future<void> create(JellyfinItem item, {Duration start = Duration.zero}) async {
    if (state.phase == WatchPartyPhase.joining) return;
    final session = ref.read(sessionControllerProvider);
    final userName = session is SessionSignedIn ? session.user.name : '';
    await _enter(() => _api.create('$userName · ${partyTitle(item)}'));
    try {
      await _api.setNewQueue([item.id], start: start);
    } on ApiException catch (error) {
      _log.warning('coda del watch party non impostata: $error');
      await leave();
      throw const WatchPartyException(WatchPartyFailure.network);
    }
  }

  /// Lancia [WatchPartyException].
  Future<void> join(String groupId) async {
    if (state.phase == WatchPartyPhase.joining) return;
    await _enter(() => _api.join(groupId));
  }

  /// Esce dal gruppo. Se la richiesta non arriva al server, la sessione
  /// scade da sola.
  Future<void> leave() async {
    if (state.phase == WatchPartyPhase.none) return;
    _reset();
    try {
      await _api.leave();
    } on Object catch (error) {
      _log.info('uscita dal watch party non inviata: $error');
    }
  }

  /// Posizione da cui aprire l'elemento in riproduzione nel gruppo. Se è
  /// lontana più di 500 ms il server la corregge con un `Seek`.
  Duration estimatedPosition() {
    final queue = state.queue;
    final playing = queue?.playing;
    if (queue == null || playing == null) return Duration.zero;
    final command = _lastCommand;
    if (command != null && command.playlistItemId == playing.playlistItemId) {
      if (command.type != SyncPlayCommandType.unpause) return command.position;
      final now = _clock?.serverNow() ?? clock.now().toUtc();
      final elapsed = now.difference(command.when);
      return elapsed.isNegative ? command.position : command.position + elapsed;
    }
    return queue.startPosition;
  }

  Future<void> _enter(Future<void> Function() request) async {
    if (state.inGroup) await leave();
    final joining = _joining = Completer<void>();
    // L'esito può arrivare dal WebSocket prima che la richiesta HTTP finisca.
    joining.future.ignore();
    state = const WatchPartyState(phase: WatchPartyPhase.joining);
    try {
      await request();
      await joining.future.timeout(joinTimeout,
          onTimeout: () =>
              throw const WatchPartyException(WatchPartyFailure.timeout));
    } on WatchPartyException catch (error) {
      _log.warning('ingresso nel watch party non riuscito: $error');
      if (!state.inGroup) _reset();
      rethrow;
    } on ApiException catch (error) {
      _log.warning('ingresso nel watch party non riuscito: $error');
      _reset();
      throw const WatchPartyException(WatchPartyFailure.network);
    } finally {
      if (identical(_joining, joining)) _joining = null;
    }
  }

  void _reset() {
    _stopClock();
    _lastCommand = null;
    _joinedAt = null;
    if (ref.mounted) state = const WatchPartyState();
  }

  void _stopClock() {
    _clock?.stop();
    _clock = null;
  }

  void _startClock() {
    _stopClock();
    _clock = ServerClock(
      fetch: () async {
        final time = await _api.utcTime();
        return (
          serverReceived: time.requestReceived,
          serverSent: time.responseSent,
        );
      },
      onPing: (ping) => unawaited(_api.ping(ping).catchError(
          (Object error) => _log.info('ping non inviato: $error'))),
    )..start();
  }

  bool _isCurrent(String groupId) {
    final id = state.group?.id;
    return id != null && _normalizeId(id) == _normalizeId(groupId);
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case SyncPlayGroupUpdated(:final update):
        _onGroupUpdate(update);
      case SyncPlayCommandReceived(:final command):
        _onCommand(command);
      default:
        break;
    }
  }

  void _onGroupUpdate(GroupUpdate update) {
    switch (update) {
      case GroupJoined(:final info):
        if (state.phase != WatchPartyPhase.joining) {
          // Conferma arrivata dopo un timeout o un'uscita.
          if (!state.inGroup) {
            unawaited(_api.leave().catchError((Object error) =>
                _log.info('uscita dal watch party non inviata: $error')));
          }
          return;
        }
        _joinedAt = info.lastUpdatedAt;
        state = WatchPartyState(
          phase: WatchPartyPhase.inGroup,
          group: info,
          groupState: info.state,
        );
        _startClock();
        final joining = _joining;
        if (joining != null && !joining.isCompleted) joining.complete();
        _log.info('nel watch party (${info.participants.length} membri)');
      case UserJoined(:final groupId, :final userName) when _isCurrent(groupId):
        state = state.copyWith(
            group: state.group!
                .copyWith(participants: [...state.members, userName]));
      case UserLeft(:final groupId, :final userName) when _isCurrent(groupId):
        final members = [...state.members]..remove(userName);
        state = state.copyWith(
            group: state.group!.copyWith(participants: members));
      case GroupStateUpdate(:final groupId, state: final groupState)
          when _isCurrent(groupId):
        state = state.copyWith(groupState: groupState);
      case PlayQueueUpdate(:final groupId, :final queue)
          when _isCurrent(groupId):
        final current = state.queue;
        if (current != null && queue.lastUpdate.isBefore(current.lastUpdate)) {
          return;
        }
        state = state.copyWith(queue: queue);
      case GroupLeft() || NotInGroup():
        if (state.inGroup) {
          _log.info('il server ci ha tolto dal watch party');
          _reset();
        }
      case GroupDoesNotExist():
        _failJoin(WatchPartyFailure.groupGone);
      case LibraryAccessDenied():
        _failJoin(WatchPartyFailure.accessDenied);
      default:
        break;
    }
  }

  void _failJoin(WatchPartyFailure failure) {
    final joining = _joining;
    if (joining != null && !joining.isCompleted) {
      joining.completeError(WatchPartyException(failure));
    }
  }

  void _onCommand(SyncPlayCommand command) {
    if (!state.inGroup || !_isCurrent(command.groupId)) return;
    final joinedAt = _joinedAt;
    if (joinedAt != null && command.emittedAt.isBefore(joinedAt)) return;
    _lastCommand = command;
    _commands.add(command);
  }
}

final watchPartySessionProvider =
    NotifierProvider<WatchPartySession, WatchPartyState>(
        WatchPartySession.new);
```

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/features/watch_party/watch_party_session_test.dart`
Expected: PASS. Se il test "coda non impostata" fallisce perché l'eccezione lanciata in `onCall` esce da `_record`, è corretto: `setNewQueue` del fake la propaga come farebbe il server.

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/watch_party_providers.dart lib/features/watch_party/watch_party_session.dart test/features/watch_party/watch_party_session_test.dart
git commit -m "feat: add the watch party session"
```

---

### Task 10: apertura del player dal gruppo

**Files:**
- Create: `lib/features/watch_party/watch_party_routing.dart`
- Modify: `lib/app/app.dart`
- Modify: `test/support/watch_party_fakes.dart`
- Test: `test/features/watch_party/watch_party_routing_test.dart`

- [ ] **Step 1: aggiungi il navigatore finto**

In `test/support/watch_party_fakes.dart` aggiungi l'import `import 'package:wonderflix/features/watch_party/watch_party_routing.dart';` e in fondo:

```dart
/// Navigazione in memoria: registra le aperture del player.
class FakePartyNavigator implements PartyNavigator {
  FakePartyNavigator([String location = '/home'])
      : location = Uri.parse(location);

  @override
  Uri location;

  final opened = <String>[];
  final replaced = <String>[];

  @override
  void open(String route) {
    opened.add(route);
    location = Uri.parse(route);
  }

  @override
  void replace(String route) {
    replaced.add(route);
    location = Uri.parse(route);
  }
}
```

- [ ] **Step 2: scrivi i test**

`test/features/watch_party/watch_party_routing_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_routing.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late FakePartyNavigator navigator;
  late ProviderContainer container;

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    navigator = FakePartyNavigator();
    container = ProviderContainer.test(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      partyNavigatorProvider.overrideWithValue(navigator),
    ]);
    container.listen(watchPartyRoutingProvider, (_, _) {});
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  Future<void> joinAndQueue(PlayQueue queue) async {
    await container.read(watchPartySessionProvider.notifier).join('g1');
    events.add(SyncPlayGroupUpdated(PlayQueueUpdate('g1', queue)));
    await pumpEventQueue();
  }

  test('la coda del gruppo apre il player', () async {
    await joinAndQueue(testQueue(start: const Duration(minutes: 1)));
    expect(navigator.opened, ['/play/m1?start=60000&party=p1']);
    expect(navigator.replaced, isEmpty);
  });

  test('con un player già aperto lo sostituisce', () async {
    navigator.location = Uri.parse('/play/m9');
    await joinAndQueue(testQueue());
    expect(navigator.replaced, ['/play/m1?party=p1']);
    expect(navigator.opened, isEmpty);
  });

  test('stesso elemento già aperto: niente', () async {
    navigator.location = Uri.parse('/play/m1?party=p1');
    await joinAndQueue(testQueue());
    expect(navigator.opened, isEmpty);
    expect(navigator.replaced, isEmpty);
  });

  test('una coda di un altro gruppo non apre nulla', () async {
    events.add(SyncPlayGroupUpdated(PlayQueueUpdate('g1', testQueue())));
    await pumpEventQueue();
    expect(navigator.opened, isEmpty);
  });
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/features/watch_party/watch_party_routing_test.dart`
Expected: FAIL (`watch_party_routing.dart` mancante).

- [ ] **Step 4: scrivi il routing**

`lib/features/watch_party/watch_party_routing.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../app/router.dart';
import 'watch_party_session.dart';

/// Dove si trova l'app e come aprire il player (sostituibile nei test).
abstract interface class PartyNavigator {
  /// Percorso attuale, es. `/play/m1?party=p1`.
  Uri get location;

  void open(String route);

  /// Sostituisce la pagina attuale (il player aperto).
  void replace(String route);
}

class _RouterNavigator implements PartyNavigator {
  _RouterNavigator(this._router);

  final GoRouter _router;

  @override
  Uri get location => _router.routeInformationProvider.value.uri;

  @override
  void open(String route) => unawaited(_router.push<void>(route));

  @override
  void replace(String route) =>
      unawaited(_router.pushReplacement<void>(route));
}

final partyNavigatorProvider = Provider<PartyNavigator>(
    (ref) => _RouterNavigator(ref.watch(routerProvider)));

/// Apre il player quando il gruppo sceglie cosa guardare (ingresso, nuova
/// coda). Lo osserva `WonderflixApp`.
final watchPartyRoutingProvider = Provider<void>((ref) {
  ref.listen(
      watchPartySessionProvider.select(
          (s) => s.inGroup ? s.queue?.playing?.playlistItemId : null),
      (_, playlistItemId) {
    if (playlistItemId == null) return;
    final entry = ref.read(watchPartySessionProvider).queue!.playing!;
    final navigator = ref.read(partyNavigatorProvider);
    final location = navigator.location;
    if (location.queryParameters['party'] == playlistItemId) return;
    final route = playerRoute(entry.itemId,
        start: ref.read(watchPartySessionProvider.notifier).estimatedPosition(),
        party: playlistItemId);
    if (location.path.startsWith('/play/')) {
      navigator.replace(route);
    } else {
      navigator.open(route);
    }
  });
});
```

- [ ] **Step 5: collega il routing all'app**

In `lib/app/app.dart` aggiungi l'import `import '../features/watch_party/watch_party_routing.dart';` e, all'inizio di `build`:

```dart
    // Il watch party apre il player quando il gruppo sceglie cosa guardare.
    ref.watch(watchPartyRoutingProvider);
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/features/watch_party/`
Expected: PASS.

- [ ] **Step 7: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/watch_party_routing.dart lib/app/app.dart test/support/watch_party_fakes.dart test/features/watch_party/watch_party_routing_test.dart
git commit -m "feat: open the player when the watch party picks an item"
```

---
### Task 11: `GroupPlaybackDriver` — comandi e `Ready`

**Files:**
- Create: `lib/features/watch_party/group_playback_driver.dart`
- Test: `test/features/watch_party/group_playback_driver_test.dart`

Il driver collega il player aperto al gruppo (spec B §4.5–4.6). In questo task: comandi, doppioni, `Ready` all'apertura e dopo i salti. Buffering e correzione dello scarto arrivano nel Task 12.

Regole:
- **Unpause con istante futuro:** allineamento esatto (salto solo se lo scarto supera 40 ms, e solo a video fermo), poi `play()` all'istante previsto.
- **Unpause con istante passato:** salto alla posizione stimata (posizione + tempo trascorso sull'orologio del server) se il video è fermo, poi `play()`.
- **Pause:** `pause()` all'istante previsto (subito se passato), poi allineamento esatto.
- **Seek:** `pause()`, `seek()`, poi `Ready` (subito, o a fine buffering).
- **Stop:** `pause()`.
- **Doppione** (stesso comando, istante, posizione ed elemento): se il suo istante è futuro non si fa nulla; se è passato si controlla lo stato e si riapplica solo se non è coerente. Un `Seek` doppio e coerente rimanda `Ready`.
- Comandi per un altro elemento della coda: ignorati (tranne `Stop`).
- Comandi arrivati prima dell'apertura del file: si tiene l'ultimo e lo si applica dopo il `Ready` iniziale.

- [ ] **Step 1: scrivi i test**

`test/features/watch_party/group_playback_driver_test.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/server_clock.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/watch_party/group_playback_driver.dart';

import '../../support/playback_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeVideoEngine engine;
  late FakeSyncPlayApi api;
  late ServerClock serverClock;
  late StreamController<SyncPlayCommand> commands;
  late GroupPlaybackDriver driver;

  /// Tutto dentro la zona finta: file aperto a 10:00, orologio pronto
  /// (scarto zero). Con [load] il file è già caricato e il `Ready` iniziale
  /// è già partito (le chiamate vengono azzerate).
  void setUpDriver(FakeAsync async, {bool load = true}) {
    engine = FakeVideoEngine();
    unawaited(engine
        .open(const VideoSource(url: 'x', start: Duration(minutes: 10))));
    api = FakeSyncPlayApi();
    serverClock = ServerClock(fetch: () async {
      final now = clock.now().toUtc();
      return (serverReceived: now, serverSent: now);
    })
      ..start();
    commands = StreamController<SyncPlayCommand>.broadcast();
    driver = GroupPlaybackDriver(
      engine: engine,
      api: api,
      clock: serverClock,
      playlistItemId: 'p1',
      commands: commands.stream,
    )..start();
    async.flushMicrotasks();
    if (load) {
      unawaited(driver.onLoaded());
      async.flushMicrotasks();
    }
    engine.calls.clear();
    api.calls.clear();
  }

  void tearDownDriver(FakeAsync async) {
    unawaited(driver.dispose());
    serverClock.stop();
    unawaited(commands.close());
    async.flushMicrotasks();
  }

  /// Comando da eseguire tra [at] (negativo = già passato).
  SyncPlayCommand command(SyncPlayCommandType type,
      {Duration position = const Duration(minutes: 10),
      Duration at = Duration.zero,
      String item = 'p1'}) {
    final when = clock.now().toUtc().add(at);
    return SyncPlayCommand(
      groupId: 'g1',
      playlistItemId: item,
      when: when,
      position: position,
      type: type,
      emittedAt: when,
    );
  }

  void send(FakeAsync async, SyncPlayCommand command) {
    commands.add(command);
    async.flushMicrotasks();
  }

  test('a file aperto manda Ready, in pausa sulla posizione di partenza', () {
    fakeAsync((async) {
      setUpDriver(async, load: false);
      unawaited(driver.onLoaded());
      async.flushMicrotasks();
      expect(api.calls, ['ready']);
      final ready = api.readyStates.single;
      expect(ready.position, const Duration(minutes: 10));
      expect(ready.isPlaying, isFalse);
      expect(ready.playlistItemId, 'p1');
      tearDownDriver(async);
    });
  });

  test('comando arrivato prima dell\'apertura: applicato dopo il Ready', () {
    fakeAsync((async) {
      setUpDriver(async, load: false);
      send(async,
          command(SyncPlayCommandType.pause, position: const Duration(minutes: 12)));
      expect(engine.calls, isEmpty);
      unawaited(driver.onLoaded());
      async.flushMicrotasks();
      expect(api.calls, ['ready']);
      expect(engine.calls, ['pause']);
      expect(engine.seeks, [const Duration(minutes: 12)]);
      tearDownDriver(async);
    });
  });

  test('Unpause futuro: allinea da fermo e parte all\'istante previsto', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(
          async,
          command(SyncPlayCommandType.unpause,
              position: const Duration(minutes: 11),
              at: const Duration(milliseconds: 500)));
      expect(engine.seeks, [const Duration(minutes: 11)]);
      expect(engine.calls, isNot(contains('play')));
      async.elapse(const Duration(milliseconds: 499));
      expect(engine.calls, isNot(contains('play')));
      async.elapse(const Duration(milliseconds: 1));
      expect(engine.calls, ['play']);
      tearDownDriver(async);
    });
  });

  test('Unpause futuro con la posizione già giusta: nessun salto', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(
          async,
          command(SyncPlayCommandType.unpause,
              position: const Duration(minutes: 10, milliseconds: 30),
              at: const Duration(milliseconds: 200)));
      async.elapse(const Duration(milliseconds: 200));
      expect(engine.seeks, isEmpty);
      expect(engine.calls, ['play']);
      tearDownDriver(async);
    });
  });

  test('Unpause già passato: salta alla posizione stimata e parte', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async,
          command(SyncPlayCommandType.unpause, at: const Duration(seconds: -2)));
      expect(engine.seeks, [const Duration(minutes: 10, seconds: 2)]);
      expect(engine.calls, ['play']);
      tearDownDriver(async);
    });
  });

  test('Pause: ferma e si allinea alla posizione del gruppo', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async, command(SyncPlayCommandType.unpause));
      engine.calls.clear();
      send(async,
          command(SyncPlayCommandType.pause, position: const Duration(minutes: 12)));
      expect(engine.calls, ['pause']);
      expect(engine.seeks, [const Duration(minutes: 12)]);
      tearDownDriver(async);
    });
  });

  test('Pause futura: ferma all\'istante previsto', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async, command(SyncPlayCommandType.unpause));
      engine.calls.clear();
      send(
          async,
          command(SyncPlayCommandType.pause,
              at: const Duration(milliseconds: 300)));
      expect(engine.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 300));
      expect(engine.calls, ['pause']);
      tearDownDriver(async);
    });
  });

  test('Seek: pausa, salto e Ready', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async,
          command(SyncPlayCommandType.seek, position: const Duration(minutes: 20)));
      expect(engine.calls, ['pause']);
      expect(engine.seeks, [const Duration(minutes: 20)]);
      expect(api.calls, ['ready']);
      expect(api.readyStates.last.position, const Duration(minutes: 20));
      expect(api.readyStates.last.isPlaying, isFalse);
      tearDownDriver(async);
    });
  });

  test('Seek durante il buffering: Ready a buffering finito', () {
    fakeAsync((async) {
      setUpDriver(async);
      engine.emitBuffering(true);
      async.flushMicrotasks();
      send(async,
          command(SyncPlayCommandType.seek, position: const Duration(minutes: 20)));
      expect(api.calls, isEmpty);
      engine.emitBuffering(false);
      async.flushMicrotasks();
      expect(api.calls, ['ready']);
      tearDownDriver(async);
    });
  });

  test('Stop: pausa', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async, command(SyncPlayCommandType.unpause));
      engine.calls.clear();
      send(async, command(SyncPlayCommandType.stop, item: ''));
      expect(engine.calls, ['pause']);
      tearDownDriver(async);
    });
  });

  test('comandi doppi: non si riapplicano se lo stato è coerente', () {
    fakeAsync((async) {
      setUpDriver(async);
      final unpause = command(SyncPlayCommandType.unpause,
          at: const Duration(milliseconds: 300));
      send(async, unpause);
      send(async, unpause);
      async.elapse(const Duration(milliseconds: 300));
      send(async, unpause);
      expect(engine.calls.where((c) => c == 'play'), hasLength(1));

      final pause = command(SyncPlayCommandType.pause,
          position: const Duration(minutes: 12));
      send(async, pause);
      send(async, pause);
      expect(engine.seeks, [const Duration(minutes: 12)]);

      final seek = command(SyncPlayCommandType.seek,
          position: const Duration(minutes: 20));
      send(async, seek);
      send(async, seek);
      expect(engine.seeks,
          [const Duration(minutes: 12), const Duration(minutes: 20)]);
      // Il server ripete il Seek finché non riceve un Ready valido.
      expect(api.calls.where((c) => c == 'ready'), hasLength(2));
      tearDownDriver(async);
    });
  });

  test('comando doppio con lo stato non coerente: si riapplica', () {
    fakeAsync((async) {
      setUpDriver(async);
      final unpause = command(SyncPlayCommandType.unpause);
      send(async, unpause);
      // Il player si è fermato da solo (es. dopo un "Riprova").
      unawaited(engine.pause());
      engine.calls.clear();
      send(async, unpause);
      expect(engine.calls, ['play']);
      tearDownDriver(async);
    });
  });

  test('comandi per un altro elemento della coda: ignorati', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async, command(SyncPlayCommandType.pause, item: 'p2'));
      send(async, command(SyncPlayCommandType.unpause, item: 'p2'));
      expect(engine.calls, isEmpty);
      expect(engine.seeks, isEmpty);
      tearDownDriver(async);
    });
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/watch_party/group_playback_driver_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi il driver**

`lib/features/watch_party/group_playback_driver.dart`:

```dart
import 'dart:async';

import 'package:logging/logging.dart';

import '../../core/syncplay/server_clock.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../core/video/video_engine.dart';

final _log = Logger('watchparty');

/// Collega il player aperto al gruppo (spec B §4.5–4.6):
/// - esegue i comandi del gruppo all'istante giusto;
/// - manda `Ready` a file aperto e dopo i salti.
class GroupPlaybackDriver {
  GroupPlaybackDriver({
    required VideoEngine engine,
    required SyncPlayApi api,
    required ServerClock clock,
    required this.playlistItemId,
    required Stream<SyncPlayCommand> commands,
    SyncPlayCommand? lastCommand,
  })  : _engine = engine,
        _api = api,
        _clock = clock,
        _commandStream = commands,
        _pending = lastCommand;

  /// Sotto questo scarto, a video fermo, non si salta.
  static const alignTolerance = Duration(milliseconds: 40);

  /// Attesa massima della prima misura dell'orologio prima del `Ready`.
  static const clockWait = Duration(seconds: 3);

  final VideoEngine _engine;
  final SyncPlayApi _api;
  final ServerClock _clock;
  final Stream<SyncPlayCommand> _commandStream;

  /// Elemento della coda aperto in questo player.
  final String playlistItemId;

  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Ultimo comando arrivato prima dell'apertura del file.
  SyncPlayCommand? _pending;

  /// Ultimo comando applicato.
  SyncPlayCommand? _current;
  Timer? _scheduled;
  bool _loaded = false;
  bool _buffering = false;
  bool _readyPending = false;
  bool _disposed = false;

  void start() {
    _subscriptions.addAll([
      _commandStream.listen(_receive),
      _engine.bufferingStream.listen(_onBuffering),
    ]);
  }

  /// Il file è aperto, in pausa sulla posizione di partenza (anche dopo un
  /// "Riprova" o il ripiego sulla transcodifica): il gruppo può partire.
  Future<void> onLoaded() async {
    if (_disposed) return;
    _loaded = true;
    if (!_clock.ready) {
      await _clock.firstSample.timeout(clockWait, onTimeout: () {});
      if (_disposed) return;
    }
    await _sendReady();
    final pending = _pending;
    _pending = null;
    if (pending != null) _receive(pending);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _scheduled?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }

  void _receive(SyncPlayCommand command) {
    if (_disposed) return;
    if (command.type != SyncPlayCommandType.stop &&
        command.playlistItemId != playlistItemId) {
      return;
    }
    if (!_loaded) {
      _pending = command;
      return;
    }
    final current = _current;
    if (current != null && current.sameAs(command)) {
      unawaited(_recheck(command));
      return;
    }
    _current = command;
    unawaited(_apply(command));
  }

  Future<void> _apply(SyncPlayCommand command) async {
    _scheduled?.cancel();
    _scheduled = null;
    final wait = _clock.toLocal(command.when).difference(_clock.now());
    _log.info('comando ${command.type.name} a ${command.position} '
        '(tra ${wait.inMilliseconds} ms)');
    switch (command.type) {
      case SyncPlayCommandType.unpause:
        if (wait > Duration.zero) {
          if (!_engine.playing) await _align(command.position);
          _scheduled = Timer(wait, () => unawaited(_play(command)));
        } else {
          if (!_engine.playing) await _align(_expectedPosition(command));
          await _play(command);
        }
      case SyncPlayCommandType.pause:
        if (wait > Duration.zero) {
          _scheduled = Timer(wait, () => unawaited(_pauseAt(command)));
        } else {
          await _pauseAt(command);
        }
      case SyncPlayCommandType.seek:
        await _engine.pause();
        await _engine.seek(command.position);
        _readyPending = true;
        if (!_buffering) await _sendReady();
      case SyncPlayCommandType.stop:
        await _engine.pause();
    }
  }

  /// Comando già ricevuto: si riapplica solo se lo stato non è coerente.
  Future<void> _recheck(SyncPlayCommand command) async {
    if (_clock.toLocal(command.when).isAfter(_clock.now())) return;
    final off = (_engine.position - command.position).abs() > alignTolerance;
    final stale = switch (command.type) {
      SyncPlayCommandType.unpause => !_engine.playing,
      SyncPlayCommandType.pause ||
      SyncPlayCommandType.seek =>
        _engine.playing || off,
      SyncPlayCommandType.stop => _engine.playing,
    };
    if (stale) {
      _current = command;
      await _apply(command);
    } else if (command.type == SyncPlayCommandType.seek) {
      await _sendReady();
    }
  }

  /// Posizione del gruppo adesso, per un comando `Unpause`.
  Duration _expectedPosition(SyncPlayCommand command) {
    final elapsed = _clock.serverNow().difference(command.when);
    return elapsed.isNegative ? command.position : command.position + elapsed;
  }

  Future<void> _play(SyncPlayCommand command) async {
    if (_disposed || !identical(_current, command)) return;
    await _engine.play();
  }

  Future<void> _pauseAt(SyncPlayCommand command) async {
    if (_disposed || !identical(_current, command)) return;
    await _engine.pause();
    await _align(command.position);
  }

  /// Allineamento esatto: a video fermo il salto non si vede.
  Future<void> _align(Duration target) async {
    if ((_engine.position - target).abs() > alignTolerance) {
      await _engine.seek(target);
    }
  }

  void _onBuffering(bool buffering) {
    if (_disposed) return;
    _buffering = buffering;
    if (!buffering && _readyPending) unawaited(_sendReady());
  }

  ClientPlaybackState _snapshot() => ClientPlaybackState(
        when: _clock.serverNow(),
        position: _engine.position,
        isPlaying: _engine.playing,
        playlistItemId: playlistItemId,
      );

  Future<void> _sendReady() async {
    _readyPending = false;
    await _send('ready', () => _api.ready(_snapshot()));
  }

  Future<void> _send(String what, Future<void> Function() request) async {
    try {
      await request();
    } on Object catch (error) {
      _log.warning('$what non inviato al gruppo: $error');
    }
  }
}
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/watch_party/group_playback_driver_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/group_playback_driver.dart test/features/watch_party/group_playback_driver_test.dart
git commit -m "feat: apply watch party commands to the player"
```

---

### Task 12: `GroupPlaybackDriver` — buffering e correzione dello scarto

**Files:**
- Modify: `lib/features/watch_party/group_playback_driver.dart`
- Modify: `test/features/watch_party/group_playback_driver_test.dart`

Regole:
- Il motore in buffering per oltre **1 s** continuo, con il gruppo in riproduzione (ultimo comando `Unpause`), fa partire `Buffering`. A buffering finito parte `Ready`.
- Ogni 500 ms, con il video in riproduzione dopo un `Unpause`, il driver chiede al `DriftCorrector` cosa fare dello scarto (posizione attesa − posizione locale) e applica velocità o salto.
- Ogni nuovo comando e la chiusura riportano la velocità a 1,0.

- [ ] **Step 1: scrivi i test**

In `test/features/watch_party/group_playback_driver_test.dart`, dentro `main()`, dopo `send`:

```dart
  /// Fa scorrere [duration] con il video in ritardo di [lag] rispetto al
  /// gruppo, partito con [from]. La posizione viene impostata prima di ogni
  /// passo, così al controllo (ogni 500 ms) è esatta.
  void runPlayback(FakeAsync async, Duration duration,
      {required SyncPlayCommand from, Duration lag = Duration.zero}) {
    const step = Duration(milliseconds: 100);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
      final next = clock.now().toUtc().add(step);
      engine.emitPosition(from.position + next.difference(from.when) - lag);
      async.elapse(step);
    }
  }
```

e in fondo a `main()`:

```dart
  group('buffering', () {
    test('sotto 1 s: il gruppo non lo sa', () {
      fakeAsync((async) {
        setUpDriver(async);
        send(async, command(SyncPlayCommandType.unpause));
        engine.emitBuffering(true);
        async.elapse(const Duration(milliseconds: 900));
        engine.emitBuffering(false);
        async.elapse(const Duration(seconds: 2));
        expect(api.calls, isEmpty);
        tearDownDriver(async);
      });
    });

    test('oltre 1 s: Buffering, poi Ready', () {
      fakeAsync((async) {
        setUpDriver(async);
        send(async, command(SyncPlayCommandType.unpause));
        engine.emitBuffering(true);
        async.elapse(const Duration(milliseconds: 999));
        expect(api.calls, isEmpty);
        async.elapse(const Duration(milliseconds: 2));
        expect(api.calls, ['buffering']);
        expect(api.bufferingStates.single.isPlaying, isTrue);
        engine.emitBuffering(false);
        async.flushMicrotasks();
        expect(api.calls, ['buffering', 'ready']);
        tearDownDriver(async);
      });
    });

    test('a gruppo fermo non si segnala', () {
      fakeAsync((async) {
        setUpDriver(async);
        engine.emitBuffering(true);
        async.elapse(const Duration(seconds: 3));
        expect(api.calls, isEmpty);
        tearDownDriver(async);
      });
    });
  });

  group('scarto', () {
    test('in pari: nessuna correzione', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 10), from: unpause);
        expect(engine.rates, isEmpty);
        tearDownDriver(async);
      });
    });

    test('300 ms indietro: 1,05×, poi di nuovo 1,0× a scarto recuperato', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 3),
            from: unpause, lag: const Duration(milliseconds: 300));
        expect(engine.rates, [1.05]);
        runPlayback(async, const Duration(seconds: 3), from: unpause);
        expect(engine.rates, [1.05, 1.0]);
        tearDownDriver(async);
      });
    });

    test('300 ms avanti: 0,95×', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 3),
            from: unpause, lag: const Duration(milliseconds: -300));
        expect(engine.rates, [0.95]);
        tearDownDriver(async);
      });
    });

    test('nei primi 1,5 s dopo la ripresa: nessuna correzione', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(milliseconds: 1400),
            from: unpause, lag: const Duration(seconds: 2));
        expect(engine.rates, isEmpty);
        tearDownDriver(async);
      });
    });

    test('4 s indietro: un salto, poi 5 s senza correzioni', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 3),
            from: unpause, lag: const Duration(seconds: 4));
        expect(engine.seeks, hasLength(1));
        expect(engine.seeks.single,
            greaterThan(const Duration(minutes: 10, seconds: 2)));
        runPlayback(async, const Duration(seconds: 4),
            from: unpause, lag: const Duration(seconds: 4));
        expect(engine.seeks, hasLength(1));
        expect(engine.rates, isEmpty);
        tearDownDriver(async);
      });
    });

    test('durante il buffering: nessuna correzione', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        engine.emitBuffering(true);
        runPlayback(async, const Duration(seconds: 4),
            from: unpause, lag: const Duration(milliseconds: 500));
        expect(engine.rates, isEmpty);
        tearDownDriver(async);
      });
    });

    test('un nuovo comando e la chiusura riportano la velocità a 1,0', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 3),
            from: unpause, lag: const Duration(milliseconds: 300));
        expect(engine.currentRate, 1.05);
        send(async, command(SyncPlayCommandType.pause));
        expect(engine.currentRate, 1.0);

        final again = command(SyncPlayCommandType.unpause,
            position: const Duration(minutes: 20));
        send(async, again);
        runPlayback(async, const Duration(seconds: 3),
            from: again, lag: const Duration(milliseconds: 300));
        expect(engine.currentRate, 1.05);
        unawaited(driver.dispose());
        async.flushMicrotasks();
        expect(engine.currentRate, 1.0);
        serverClock.stop();
      });
    });
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/watch_party/group_playback_driver_test.dart`
Expected: FAIL nei gruppi `buffering` e `scarto`.

- [ ] **Step 3: aggiungi buffering e correzione**

In `lib/features/watch_party/group_playback_driver.dart`:

1. Aggiungi l'import `import '../../core/syncplay/drift_corrector.dart';`.
2. Aggiorna la documentazione della classe:

```dart
/// Collega il player aperto al gruppo (spec B §4.5–4.6):
/// - esegue i comandi del gruppo all'istante giusto;
/// - manda `Ready` a file aperto e dopo i salti, `Buffering` se il buffering
///   dura più di 1 s con il gruppo in riproduzione;
/// - durante la visione corregge lo scarto con la velocità
///   ([DriftCorrector]), con un salto solo se è troppo grande.
```

3. Dopo `static const clockWait = …;`:

```dart
  /// Buffering più breve di così: il gruppo non lo sa.
  static const bufferingThreshold = Duration(seconds: 1);

  /// Ogni quanto si misura lo scarto.
  static const tick = Duration(milliseconds: 500);
```

4. Dopo `final _subscriptions = …;`:

```dart
  final _corrector = DriftCorrector();
  Timer? _bufferingTimer;
  Timer? _ticker;
  bool _reportedBuffering = false;
  double _rate = 1.0;

  /// Da quando il video va dopo l'ultimo `Unpause` (per il periodo iniziale).
  DateTime? _playingSince;
  DateTime? _lastResync;
```

5. In `start()`, dopo `_subscriptions.addAll([...]);`:

```dart
    _ticker = Timer.periodic(tick, (_) => _onTick());
```

6. Sostituisci `dispose()`:

```dart
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _scheduled?.cancel();
    _bufferingTimer?.cancel();
    _ticker?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_rate != 1.0) {
      _rate = 1.0;
      try {
        await _engine.setRate(1.0);
      } on Object catch (error) {
        // Il motore può essere già chiuso insieme al player.
        _log.info('velocità non ripristinata: $error');
      }
    }
  }
```

7. All'inizio di `_apply`, dopo `_scheduled = null;`:

```dart
    _corrector.reset();
    _playingSince = null;
    await _setRate(1.0);
```

8. In `_play`, dopo `await _engine.play();`:

```dart
    _playingSince = _clock.now();
```

9. Sostituisci `_onBuffering`:

```dart
  void _onBuffering(bool buffering) {
    if (_disposed) return;
    _buffering = buffering;
    if (buffering) {
      _bufferingTimer ??= Timer(bufferingThreshold, _reportBuffering);
      return;
    }
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    if (_reportedBuffering || _readyPending) {
      _reportedBuffering = false;
      unawaited(_sendReady());
    }
  }

  void _reportBuffering() {
    _bufferingTimer = null;
    if (_disposed ||
        !_buffering ||
        _current?.type != SyncPlayCommandType.unpause) {
      return;
    }
    _reportedBuffering = true;
    _log.info('buffering da oltre ${bufferingThreshold.inSeconds} s: '
        'il gruppo aspetta');
    unawaited(_send('buffering', () => _api.buffering(_snapshot())));
  }

  void _onTick() {
    final command = _current;
    final since = _playingSince;
    if (_disposed ||
        command == null ||
        since == null ||
        command.type != SyncPlayCommandType.unpause ||
        !_engine.playing ||
        _buffering) {
      return;
    }
    final expected = _expectedPosition(command);
    final now = _clock.now();
    final lastResync = _lastResync;
    final action = _corrector.update(
      drift: expected - _engine.position,
      rate: _rate,
      sinceUnpause: now.difference(since),
      sinceResync: lastResync == null ? null : now.difference(lastResync),
    );
    switch (action) {
      case KeepRate():
        break;
      case ChangeRate(:final rate):
        _log.info('scarto ${_corrector.lastDrift?.inMilliseconds} ms: '
            'velocità $rate');
        unawaited(_setRate(rate));
      case Resync():
        _lastResync = now;
        _log.info('scarto oltre ${DriftCorrector.resyncThreshold.inSeconds} s: '
            'riallineamento a $expected');
        unawaited(_engine.seek(expected));
    }
  }

  Future<void> _setRate(double rate) async {
    if (_rate == rate) return;
    _rate = rate;
    try {
      await _engine.setRate(rate);
    } on Object catch (error) {
      _log.warning('velocità non impostata: $error');
    }
  }
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/watch_party/group_playback_driver_test.dart`
Expected: PASS (anche i test del Task 11).

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/group_playback_driver.dart test/features/watch_party/group_playback_driver_test.dart
git commit -m "feat: report buffering and correct drift in the watch party"
```

---

### Task 13: `GroupAuthority`

**Files:**
- Create: `lib/features/watch_party/group_authority.dart`
- Test: `test/features/watch_party/group_authority_test.dart`

- [ ] **Step 1: scrivi i test**

`test/features/watch_party/group_authority_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/watch_party/group_authority.dart';

import '../../support/playback_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeVideoEngine engine;
  late FakeSyncPlayApi api;
  late GroupAuthority authority;

  setUp(() {
    engine = FakeVideoEngine();
    api = FakeSyncPlayApi();
    authority = GroupAuthority(api: api, engine: engine);
  });

  test('play chiede la ripresa al gruppo, senza muovere il motore', () async {
    await authority.play();
    expect(api.calls, ['unpause']);
    expect(engine.calls, isEmpty);
  });

  test('pause ferma subito anche il motore', () async {
    await authority.play();
    await engine.play();
    engine.calls.clear();
    await authority.pause();
    expect(engine.calls, ['pause']);
    expect(api.calls.last, 'pause');
  });

  test('seekTo mette in pausa sulla posizione scelta e la chiede al gruppo',
      () async {
    await authority.seekTo(const Duration(minutes: 30));
    expect(engine.calls, ['pause']);
    expect(engine.seeks, [const Duration(minutes: 30)]);
    expect(api.calls, ['seek ${const Duration(minutes: 30)}']);
  });

  test('errori di rete: nessuna eccezione verso il player', () async {
    api.error = const ServerUnreachableException();
    await authority.play();
    await authority.pause();
    await authority.seekTo(Duration.zero);
    expect(api.calls, ['unpause', 'pause', 'seek 0:00:00.000000']);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/watch_party/group_authority_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi l'autorità**

`lib/features/watch_party/group_authority.dart`:

```dart
import 'package:logging/logging.dart';

import '../../core/syncplay/syncplay_api.dart';
import '../../core/video/video_engine.dart';
import '../player/playback_authority.dart';

final _log = Logger('watchparty');

/// Nel watch party pausa, ripresa e salti dell'utente diventano richieste al
/// gruppo (spec B §6.1). Il motore si muove con i comandi del gruppo, tranne
/// la pausa e il salto, che si vedono subito.
class GroupAuthority implements PlaybackAuthority {
  GroupAuthority({required SyncPlayApi api, required VideoEngine engine})
      : _api = api,
        _engine = engine;

  final SyncPlayApi _api;
  final VideoEngine _engine;

  /// Con il gruppo in attesa fa ripartire tutti senza aspettare.
  @override
  Future<void> play() => _send('ripresa', _api.unpause);

  @override
  Future<void> pause() async {
    await _engine.pause();
    await _send('pausa', _api.pause);
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _engine.pause();
    await _engine.seek(position);
    await _send('salto', () => _api.seek(position));
  }

  Future<void> _send(String what, Future<void> Function() request) async {
    try {
      await request();
    } on Object catch (error) {
      _log.warning('$what non inviata al gruppo: $error');
    }
  }
}
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/watch_party/group_authority_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/group_authority.dart test/features/watch_party/group_authority_test.dart
git commit -m "feat: route player controls to the watch party group"
```

---
### Task 14: il player nel watch party

**Files:**
- Create: `lib/features/watch_party/party_badge.dart`
- Create: `lib/features/watch_party/party_waiting_overlay.dart`
- Modify: `lib/features/player/player_overlay.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/watch_party/party_player_test.dart`

Cosa cambia nel player quando `args.party` è valorizzato:
- al primo `build` si creano `GroupPlaybackDriver` e `GroupAuthority` (se la sessione è davvero nel gruppo);
- quando il player diventa `ready` (anche dopo "Riprova") si chiama `driver.onLoaded()`. Se il gruppo non c'è, il player parte da solo, come fuori dal watch party;
- distintivo "Watch party · N" nei controlli in alto, con i membri ed "Esci dal watch party";
- schermata di attesa con il gruppo in `Waiting` (dopo 1 s), sotto i controlli;
- uscire dal player (freccia, Esc, chiusura della finestra) fa uscire dal gruppo;
- niente episodio successivo (pulsante, scheda, tasti) e niente uscita automatica a fine video: nel 5a il gruppo resta sull'ultimo fotogramma;
- se il server ci toglie dal gruppo, il player continua da solo.

- [ ] **Step 1: scrivi i test**

`test/features/watch_party/party_player_test.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  late FakeVideoEngine engine;
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late FakeLibraryApi library;
  late ProviderContainer container;
  late GoRouter router;

  void emit(GroupUpdate update) => events.add(SyncPlayGroupUpdated(update));

  /// Home con il player del watch party aperto sopra: l'utente è già nel
  /// gruppo `g1` (Mario e Luigi), che guarda `e4` (`p1`).
  Future<void> pumpPartyPlayer(WidgetTester tester) async {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
    final playback = FakePlaybackApi();
    library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(
        id: 'e4',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 4,
        seasonIndex: 1,
      )
      ..nextEpisodes['e4'] = testItem(
          id: 'e5', name: 'Cat\'s in the Bag', kind: ItemKind.episode);
    router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home'))),
      GoRoute(
        path: '/play/:id',
        builder: (context, state) => PlayerScreen(
          key: ValueKey(state.uri.toString()),
          args: (
            itemId: state.pathParameters['id']!,
            start: playerStartFrom(state.uri),
            party: state.uri.queryParameters['party'],
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    container = ProviderContainer(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        playbackApiProvider.overrideWithValue(playback),
        playbackServiceProvider.overrideWithValue(PlaybackService(
          api: playback,
          serverUrl: testServerUrl,
          authorization: () => 'MediaBrowser Token="t1"',
        )),
        videoEngineFactoryProvider.overrideWithValue(() => engine),
        playerWindowProvider.overrideWithValue(FakePlayerWindow()),
        mediaSessionProvider.overrideWithValue(FakeMediaSession()),
        playerSettingsProvider
            .overrideWith(() => FakePlayerSettings(const PlayerSettings())),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        appConfigProvider.overrideWithValue(testAppConfig),
        imageBuilderProvider.overrideWithValue(
            (image, fit) => const ColoredBox(color: Color(0xFF333333))),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
      ],
      retry: (_, _) => null,
    );
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    api.onCall = (call) {
      if (call.startsWith('join')) {
        emit(GroupJoined(
            'g1', testGroup(participants: ['Mario', 'Luigi'])));
      }
    };
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pump();
    await tester.pump();
    unawaited(router.push(playerRoute('e4', party: 'p1')));
    await tester.pumpAndSettle();
  }

  /// Smonta tutto: chiude il player, ferma l'orologio del gruppo e lascia
  /// scadere i timer.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    container.dispose();
    await tester.pump();
  }

  SyncPlayCommand command(SyncPlayCommandType type) {
    final now = clock.now().toUtc();
    return SyncPlayCommand(
      groupId: 'g1',
      playlistItemId: 'p1',
      when: now,
      position: Duration.zero,
      type: type,
      emittedAt: now.add(const Duration(days: 365 * 100)),
    );
  }

  testWidgets('a file aperto: Ready al gruppo, il video non parte da solo',
      (tester) async {
    await pumpPartyPlayer(tester);
    expect(api.calls, contains('ready'));
    expect(engine.calls, isNot(contains('play')));
    await finish(tester);
  });

  testWidgets('il pulsante play chiede la ripresa al gruppo', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(api.calls, contains('unpause'));
    expect(engine.calls, isNot(contains('play')));
    await finish(tester);
  });

  testWidgets('il comando del gruppo fa partire il video', (tester) async {
    await pumpPartyPlayer(tester);
    events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.unpause)));
    await tester.pump();
    await tester.pump();
    expect(engine.calls, contains('play'));
    await finish(tester);
  });

  testWidgets('distintivo con i membri e uscita dal gruppo', (tester) async {
    await pumpPartyPlayer(tester);
    expect(find.text(l.watchPartyButton(2)), findsOneWidget);
    await tester.tap(find.byKey(const Key('party-badge')));
    await tester.pumpAndSettle();
    expect(find.text('Luigi'), findsOneWidget);
    await tester.tap(find.text(l.watchPartyLeave));
    await tester.pumpAndSettle();
    expect(api.calls, contains('leave'));
    expect(find.text('home'), findsOneWidget);
    expect(container.read(watchPartySessionProvider).inGroup, isFalse);
    await finish(tester);
  });

  testWidgets('attesa del gruppo: dopo 1 s, con "Riprendi senza aspettare"',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
    await tester.pump();
    expect(find.text(l.watchPartyWaiting), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l.watchPartyWaiting), findsOneWidget);
    await tester.tap(find.text(l.watchPartyResumeNow));
    await tester.pump();
    expect(api.calls, contains('unpause'));

    emit(const GroupStateUpdate('g1', GroupState.playing, 'Ready'));
    await tester.pump();
    expect(find.text(l.watchPartyWaiting), findsNothing);
    await finish(tester);
  });

  testWidgets('nel watch party non c\'è l\'episodio successivo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.pump();
    expect(find.byTooltip(l.playerNextEpisode), findsNothing);
    await finish(tester);
  });

  testWidgets('gruppo chiuso dal server: il player continua da solo',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyButton(2)), findsNothing);
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(engine.calls, contains('play'));
    await finish(tester);
  });
}
```

`emittedAt` nel futuro: il comando è sicuramente successivo all'ingresso nel gruppo (`lastUpdatedAt` di `testGroup` è fisso).

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/watch_party/party_player_test.dart`
Expected: FAIL (file `party_badge.dart` e simili mancanti, o comportamenti assenti).

- [ ] **Step 3: crea il distintivo**

`lib/features/watch_party/party_badge.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'watch_party_session.dart';

/// Etichetta con bordo oro e icona del gruppo (barra in alto e player).
class PartyChip extends StatelessWidget {
  const PartyChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: WfColors.gold),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.users, size: 16, color: WfColors.gold),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: WfColors.gold, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Iniziale di un membro: il server dà solo i nomi utente.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 13,
        backgroundColor: WfColors.surfaceHigh,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(
                color: WfColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );
}

/// "Watch party · N" nei controlli del player: apre i membri ed "Esci dal
/// watch party".
class PartyBadge extends ConsumerWidget {
  const PartyBadge({super.key, required this.onLeave});

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final party = ref.watch(watchPartySessionProvider);
    final members = party.members;
    return PopupMenuButton<String>(
      key: const Key('party-badge'),
      tooltip: party.group?.name,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'leave') onLeave();
      },
      itemBuilder: (context) => [
        for (final member in members)
          PopupMenuItem<String>(
            enabled: false,
            child: Row(
              children: [
                MemberAvatar(name: member),
                const SizedBox(width: 12),
                Text(member, style: const TextStyle(color: WfColors.cream)),
              ],
            ),
          ),
        if (members.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'leave',
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 18, color: WfColors.error),
              const SizedBox(width: 12),
              Text(l.watchPartyLeave),
            ],
          ),
        ),
      ],
      child: PartyChip(label: l.watchPartyButton(members.length)),
    );
  }
}
```

- [ ] **Step 4: crea la schermata di attesa**

`lib/features/watch_party/party_waiting_overlay.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';

/// Il gruppo aspetta qualcuno (buffering, ingresso di un membro). Compare
/// dopo [delay], per non lampeggiare nelle attese brevi (spec B §7.1).
class PartyWaitingOverlay extends StatefulWidget {
  const PartyWaitingOverlay({
    super.key,
    required this.waiting,
    required this.onResume,
  });

  static const delay = Duration(seconds: 1);

  final bool waiting;

  /// "Riprendi senza aspettare".
  final VoidCallback onResume;

  @override
  State<PartyWaitingOverlay> createState() => _PartyWaitingOverlayState();
}

class _PartyWaitingOverlayState extends State<PartyWaitingOverlay> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PartyWaitingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waiting != widget.waiting) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    _visible = false;
    if (!widget.waiting) return;
    _timer = Timer(PartyWaitingOverlay.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return ColoredBox(
      color: const Color(0x99000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.hourglass, size: 40, color: WfColors.gold),
            const SizedBox(height: 16),
            Text(l.watchPartyWaiting, style: WfText.display(28)),
            const SizedBox(height: 20),
            WfButton.secondary(
              label: l.watchPartyResumeNow,
              icon: LucideIcons.play,
              onPressed: widget.onResume,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: spazio per il distintivo nei controlli**

In `lib/features/player/player_overlay.dart`:
- nel costruttore, dopo `this.preview,`: `this.partyBadge,`
- dopo `final Widget? Function(Duration position)? preview;`:

```dart

  /// Distintivo del watch party, in alto a destra; `null` fuori dal gruppo.
  final Widget? partyBadge;
```

- nella `Row` in alto, dopo il blocco `if (item != null) Expanded(...)`, aggiungi:

```dart
                    if (partyBadge != null) ...[
                      if (item == null) const Spacer(),
                      const SizedBox(width: 16),
                      partyBadge!,
                    ],
```

- [ ] **Step 6: modalità gruppo in `PlayerScreen`**

In `lib/features/player/player_screen.dart`:

1. Import (in ordine alfabetico con gli altri):

```dart
import '../../core/syncplay/syncplay_models.dart';
import '../watch_party/group_authority.dart';
import '../watch_party/group_playback_driver.dart';
import '../watch_party/party_badge.dart';
import '../watch_party/party_waiting_overlay.dart';
import '../watch_party/watch_party_session.dart';
```

2. In `_PlayerScreenState`, dopo `Timer? _timelineTimer;`:

```dart
  /// Nel watch party: applica i comandi del gruppo al motore.
  GroupPlaybackDriver? _driver;

  bool get _inParty => widget.args.party != null;
```

3. In `dispose()`, prima di `super.dispose();`:

```dart
    unawaited(_driver?.dispose());
```

4. Sostituisci `_onWindowClose`:

```dart
  Future<void> _onWindowClose() async {
    await Future.wait([
      _controller.close(),
      if (_inParty) ref.read(watchPartySessionProvider.notifier).leave(),
    ]).timeout(PlayerScreen.closeTimeout, onTimeout: () => const []);
    await _window.destroy();
  }
```

5. In `_exit()`, subito dopo `_leaving = true;`:

```dart
    // Chiudere il player fa uscire dal watch party: gli altri continuano.
    if (_inParty) {
      unawaited(ref.read(watchPartySessionProvider.notifier).leave());
    }
```

6. In `_playNext`, la condizione di uscita diventa:

```dart
    if (next == null || _leaving || _inParty) return;
```

7. All'inizio di `_onFinished`:

```dart
    // Nel watch party la fine la decide il gruppo: si resta sul video.
    if (_inParty) return;
```

8. Dopo `_publishMetadata`, aggiungi:

```dart
  /// Nel watch party il player segue il gruppo: il driver applica i comandi,
  /// l'autorità manda al gruppo pausa, ripresa e salti.
  void _attachParty(PlayerController controller) {
    final party = widget.args.party;
    if (party == null || _driver != null) return;
    final current = ref.read(watchPartySessionProvider);
    final session = ref.read(watchPartySessionProvider.notifier);
    final serverClock = session.serverClock;
    if (!current.inGroup || serverClock == null) return;
    _driver = GroupPlaybackDriver(
      engine: controller.engine,
      api: session.api,
      clock: serverClock,
      playlistItemId: party,
      commands: session.commands,
      lastCommand: session.lastCommand,
    )..start();
    controller.setAuthority(
        GroupAuthority(api: session.api, engine: controller.engine));
  }

  /// Il server ci ha tolto dal gruppo: si continua da soli.
  void _detachParty() {
    final driver = _driver;
    _driver = null;
    unawaited(driver?.dispose());
    _controller.setAuthority(null);
  }
```

9. In `build`, dopo `final next = view.nextEpisode;`:

```dart
    if (_inParty) _attachParty(controller);
    final party = _inParty ? ref.watch(watchPartySessionProvider) : null;
```

e, dopo gli altri `ref.listen`:

```dart
    ref.listen(provider.select((s) => s.status), (_, status) {
      if (status != PlayerStatus.ready) return;
      final driver = _driver;
      if (driver != null) {
        unawaited(driver.onLoaded());
      } else if (_inParty) {
        // Gruppo non disponibile: il player parte da solo.
        unawaited(controller.play());
      }
    });
    if (_inParty) {
      ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
          (_, inGroup) {
        if (!inGroup && _driver != null) _detachParty();
      });
    }
```

10. Nello `Stack`, subito **prima** del blocco `if (view.status == PlayerStatus.error) _PlayerError(...) else ExcludeFocus(...)` (così i controlli restano sopra):

```dart
                if (party != null && view.status == PlayerStatus.ready)
                  Positioned.fill(
                    child: ExcludeFocus(
                      child: PartyWaitingOverlay(
                        waiting: party.inGroup &&
                            party.groupState == GroupState.waiting &&
                            !view.buffering,
                        onResume: () => unawaited(controller.play()),
                      ),
                    ),
                  ),
```

11. Nel `PlayerOverlay`:

```dart
                          onNextEpisode:
                              next == null || _inParty ? null : _playNext,
```

e dopo `preview: _previewFor(view),`:

```dart
                          partyBadge: party != null && party.inGroup
                              ? PartyBadge(onLeave: _exit)
                              : null,
```

12. La scheda "Prossimo episodio": la condizione `if (next != null && !_nextCardDismissed)` diventa `if (next != null && !_nextCardDismissed && !_inParty)`.

- [ ] **Step 7: verifica che passino**

Run: `flutter test test/features/watch_party/party_player_test.dart test/features/player/`
Expected: PASS. Se un test resta con "A Timer is still pending", controlla che `finish` smonti prima i widget e poi chiuda il container (l'orologio del gruppo si ferma con la sessione).

- [ ] **Step 8: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/party_badge.dart lib/features/watch_party/party_waiting_overlay.dart lib/features/player/player_overlay.dart lib/features/player/player_screen.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: play in sync with the watch party group"
```

---

### Task 15: elenco dei gruppi, barra in alto e "Guarda insieme"

**Files:**
- Create: `lib/features/watch_party/watch_party_directory.dart`
- Create: `lib/features/watch_party/watch_party_actions.dart`
- Create: `lib/features/watch_party/watch_party_button.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/features/detail/detail_header.dart`
- Modify: `test/support/watch_party_fakes.dart`, `test/app/app_shell_test.dart`, `test/app/app_shell_back_button_test.dart`
- Test: `test/features/watch_party/watch_party_directory_test.dart`, `test/features/watch_party/watch_party_button_test.dart`, `test/features/detail/movie_detail_test.dart`

- [ ] **Step 1: scrivi i test dell'elenco**

`test/features/watch_party/watch_party_directory_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;

  setUp(() => api = FakeSyncPlayApi());

  ProviderContainer mount() {
    final container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
    ]);
    container.listen(watchPartyDirectoryProvider, (_, _) {});
    return container;
  }

  test('elenco all\'avvio e poi ogni 30 s', () {
    fakeAsync((async) {
      final container = mount();
      async.flushMicrotasks();
      expect(api.calls, ['list']);
      expect(container.read(watchPartyDirectoryProvider), isEmpty);

      api.groups = [testGroup()];
      async.elapse(const Duration(seconds: 30));
      expect(api.calls, ['list', 'list']);
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g1');
      container.dispose();
    });
  });

  test('con il player aperto non chiede nulla; all\'uscita aggiorna', () {
    fakeAsync((async) {
      final container = mount();
      async.flushMicrotasks();
      container.read(playerActiveProvider.notifier).enter();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 60));
      expect(api.calls, ['list']);

      container.read(playerActiveProvider.notifier).leave();
      async.flushMicrotasks();
      expect(api.calls, ['list', 'list']);
      container.dispose();
    });
  });

  test('errore di rete: resta l\'elenco precedente', () {
    fakeAsync((async) {
      api.groups = [testGroup()];
      final container = mount();
      async.flushMicrotasks();
      api.error = const ServerUnreachableException();
      async.elapse(const Duration(seconds: 30));
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g1');
      container.dispose();
    });
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/watch_party/watch_party_directory_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: scrivi l'elenco**

`lib/features/watch_party/watch_party_directory.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/syncplay/syncplay_models.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import 'watch_party_providers.dart';

final _log = Logger('watchparty');

/// Gruppi attivi sul server, per il pulsante della barra in alto. Si
/// aggiorna ogni [interval], ma non con il player aperto (spec B §5.8).
class WatchPartyDirectory extends Notifier<List<GroupInfo>> {
  static const interval = Duration(seconds: 30);

  @override
  List<GroupInfo> build() {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (userId == null) return const [];
    final timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    ref.onDispose(timer.cancel);
    ref.listen(playerActiveProvider, (_, active) {
      if (!active) unawaited(refresh());
    });
    unawaited(Future.microtask(refresh));
    return const [];
  }

  Future<void> refresh() async {
    if (ref.read(playerActiveProvider)) return;
    try {
      final groups = await ref.read(syncPlayApiProvider).list();
      if (ref.mounted) state = groups;
    } on Object catch (error) {
      _log.info('elenco dei watch party non disponibile: $error');
    }
  }
}

final watchPartyDirectoryProvider =
    NotifierProvider<WatchPartyDirectory, List<GroupInfo>>(
        WatchPartyDirectory.new);
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/features/watch_party/watch_party_directory_test.dart`
Expected: PASS.

- [ ] **Step 5: fake dell'elenco e `pumpApp`**

In `test/support/watch_party_fakes.dart` aggiungi l'import `import 'package:wonderflix/features/watch_party/watch_party_directory.dart';` e in fondo:

```dart
/// Elenco dei gruppi fisso, senza richieste né timer.
class FakeWatchPartyDirectory extends WatchPartyDirectory {
  FakeWatchPartyDirectory([this.initial = const []]);

  final List<GroupInfo> initial;
  int refreshCalls = 0;

  @override
  List<GroupInfo> build() => initial;

  @override
  Future<void> refresh() async => refreshCalls++;
}
```

I due test che montano `AppShell` devono usare l'elenco finto (niente richieste né timer). **Non** metterlo in `pumpApp`: i test del pulsante sovrascrivono lo stesso provider, e Riverpod rifiuta due override dello stesso provider.

In `test/app/app_shell_test.dart` aggiungi gli import `import 'package:wonderflix/features/watch_party/watch_party_directory.dart';` e `import '../support/watch_party_fakes.dart';`, e negli `overrides` di `pumpApp`:

```dart
        // Nessun elenco dei watch party (né timer).
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
```

In `test/app/app_shell_back_button_test.dart` aggiungi gli stessi due import e la stessa riga negli `overrides` del `ProviderScope`, dopo `serverEventsBindingProvider.overrideWithValue(null),`.

- [ ] **Step 6: scrivi i test del pulsante**

`test/features/watch_party/watch_party_button_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_button.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
  });

  tearDown(() => events.close());

  Future<void> pumpButton(WidgetTester tester, List<GroupInfo> groups) =>
      pumpApp(
        tester,
        const Scaffold(
            body: Align(
                alignment: Alignment.topRight, child: WatchPartyButton())),
        overrides: [
          watchPartyDirectoryProvider
              .overrideWith(() => FakeWatchPartyDirectory(groups)),
          syncPlayApiProvider.overrideWithValue(api),
          watchPartyEventsProvider.overrideWithValue(events.stream),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
      );

  /// Esce dal gruppo: ferma l'orologio (i suoi timer non devono restare).
  Future<void> leave(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WatchPartyButton)));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets('nessun gruppo: nessun pulsante', (tester) async {
    await pumpButton(tester, const []);
    expect(find.byKey(const Key('watch-party-button')), findsNothing);
  });

  testWidgets('elenco dei gruppi e ingresso', (tester) async {
    await pumpButton(tester, [
      testGroup(state: GroupState.playing, participants: ['Mario', 'Luigi']),
    ]);
    expect(find.text('Watch party · 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('watch-party-button')));
    await tester.pumpAndSettle();
    expect(find.text('Mario · Dune'), findsOneWidget);
    expect(find.text('2 persone · In riproduzione'), findsOneWidget);
    expect(find.text('Mario, Luigi'), findsOneWidget);

    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
    await tester.tap(find.text('Unisciti'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('join g1'));
    await leave(tester);
  });

  testWidgets('gruppo non più esistente: avviso', (tester) async {
    await pumpButton(tester, [testGroup()]);
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(const SyncPlayGroupUpdated(GroupDoesNotExist('')));
      }
    };
    await tester.tap(find.byKey(const Key('watch-party-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unisciti'));
    await tester.pumpAndSettle();
    expect(find.text('Questo watch party non esiste più.'), findsOneWidget);
  });
}
```

- [ ] **Step 7: verifica che fallisca**

Run: `flutter test test/features/watch_party/watch_party_button_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 8: scrivi azioni e pulsante**

`lib/features/watch_party/watch_party_actions.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'watch_party_session.dart';

/// "Guarda insieme": crea il gruppo; il player si apre quando il server
/// conferma la coda (`watchPartyRoutingProvider`).
Future<void> startWatchParty(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item, {
  Duration start = Duration.zero,
}) =>
    _run(
      context,
      () => ref
          .read(watchPartySessionProvider.notifier)
          .create(item, start: start),
      creating: true,
    );

/// "Unisciti" dall'elenco dei gruppi.
Future<void> joinWatchParty(
        BuildContext context, WidgetRef ref, String groupId) =>
    _run(
      context,
      () => ref.read(watchPartySessionProvider.notifier).join(groupId),
      creating: false,
    );

Future<void> _run(BuildContext context, Future<void> Function() action,
    {required bool creating}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(
        content: Text(watchPartyErrorText(l, error, creating: creating))));
  }
}

String watchPartyErrorText(AppLocalizations l, Object error,
        {required bool creating}) =>
    switch (error) {
      WatchPartyException(failure: WatchPartyFailure.groupGone) =>
        l.watchPartyGone,
      WatchPartyException(failure: WatchPartyFailure.accessDenied) =>
        l.watchPartyAccessDenied,
      _ => creating ? l.watchPartyCreateError : l.watchPartyJoinError,
    };

String groupStateLabel(AppLocalizations l, GroupState state) =>
    switch (state) {
      GroupState.idle => l.watchPartyStateIdle,
      GroupState.waiting => l.watchPartyStateWaiting,
      GroupState.paused => l.watchPartyStatePaused,
      GroupState.playing => l.watchPartyStatePlaying,
    };
```

`lib/features/watch_party/watch_party_button.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'party_badge.dart';
import 'watch_party_actions.dart';
import 'watch_party_directory.dart';

/// "Watch party · N" nella barra in alto: compare solo se esiste almeno un
/// gruppo e apre l'elenco con "Unisciti".
class WatchPartyButton extends ConsumerWidget {
  const WatchPartyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(watchPartyDirectoryProvider);
    if (groups.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: const Key('watch-party-button'),
      tooltip: l.watchPartyListTitle,
      position: PopupMenuPosition.under,
      onOpened: () =>
          unawaited(ref.read(watchPartyDirectoryProvider.notifier).refresh()),
      onSelected: (groupId) => unawaited(joinWatchParty(context, ref, groupId)),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(l.watchPartyListTitle.toUpperCase(),
              style: const TextStyle(
                  color: WfColors.creamMuted,
                  fontSize: 12,
                  letterSpacing: 1)),
        ),
        for (final group in groups)
          PopupMenuItem<String>(
            value: group.id,
            height: 64,
            child: _GroupTile(group: group),
          ),
      ],
      child: PartyChip(label: l.watchPartyButton(groups.length)),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});

  final GroupInfo group;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 12);
    return SizedBox(
      width: 320,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    '${l.watchPartyMembers(group.participants.length)} · '
                    '${groupStateLabel(l, group.state)}',
                    style: muted),
                if (group.participants.isNotEmpty)
                  Text(group.participants.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(l.watchPartyJoin,
              style: const TextStyle(
                  color: WfColors.gold, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 9: pulsante nella barra in alto**

In `lib/app/app_shell.dart` aggiungi l'import `import '../features/watch_party/watch_party_button.dart';` e nella `Row` sostituisci:

```dart
                  const Spacer(),
                  if (user != null) _UserMenu(user: user),
```

con:

```dart
                  const Spacer(),
                  const WatchPartyButton(),
                  const SizedBox(width: 16),
                  if (user != null) _UserMenu(user: user),
```

- [ ] **Step 10: verifica il pulsante**

Run: `flutter test test/features/watch_party/watch_party_button_test.dart test/app/`
Expected: PASS.

- [ ] **Step 11: scrivi il test di "Guarda insieme"**

In `test/features/detail/movie_detail_test.dart` aggiungi gli import:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/watch_party_fakes.dart';
```

(se `flutter_riverpod` è già importato, non duplicarlo) e in fondo a `main()`:

```dart
  testWidgets('Guarda insieme: crea il gruppo dal punto di ripresa',
      (tester) async {
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
    expect(syncPlay.calls, ['create Mario · Dune: Parte Due', 'queue m1']);
    // positionTicks 13940000000 = 23:14.
    expect(syncPlay.queues.single.start,
        const Duration(minutes: 23, seconds: 14));

    final container = ProviderScope.containerOf(
        tester.element(find.byType(ItemDetailScreen)));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });
```

- [ ] **Step 12: verifica che fallisca**

Run: `flutter test test/features/detail/movie_detail_test.dart`
Expected: FAIL (nessun "Guarda insieme").

- [ ] **Step 13: aggiungi il pulsante nei dettagli**

In `lib/features/detail/detail_header.dart` aggiungi l'import `import '../watch_party/watch_party_actions.dart';` e nel `Wrap` delle azioni, dopo il blocco `if (action is ResumeAction) WfButton.secondary(...)`:

```dart
                    // Nel Piano 5a solo i film; serie ed episodi nel 5b.
                    if (action != null && item.kind == ItemKind.movie)
                      WfButton.secondary(
                        label: l.watchPartyWatchTogether,
                        icon: LucideIcons.users,
                        onPressed: () => unawaited(startWatchParty(
                          context,
                          ref,
                          action.target,
                          start: action is ResumeAction
                              ? action.position
                              : Duration.zero,
                        )),
                      ),
```

- [ ] **Step 14: verifica che passi**

Run: `flutter test test/features/detail/ test/features/watch_party/`
Expected: PASS.

- [ ] **Step 15: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/watch_party_directory.dart lib/features/watch_party/watch_party_actions.dart lib/features/watch_party/watch_party_button.dart lib/app/app_shell.dart lib/features/detail/detail_header.dart test/support/watch_party_fakes.dart test/app/app_shell_test.dart test/app/app_shell_back_button_test.dart test/features/watch_party/watch_party_directory_test.dart test/features/watch_party/watch_party_button_test.dart test/features/detail/movie_detail_test.dart
git commit -m "feat: list, join and start watch parties"
```

---

### Task 16: seconda istanza per le prove

**Files:**
- Create: `lib/core/device/dev_profile.dart`
- Test: `test/core/device/dev_profile_test.dart`
- Modify: `lib/core/storage/session_store.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/core/logging/app_log.dart`
- Modify: `lib/main.dart`
- Modify: `windows/runner/main.cpp`

Con `WONDERFLIX_PROFILE=<nome>` (lettere e cifre, massimo 16 caratteri) si avvia un'istanza separata: mutex, preferenze (e quindi `DeviceId` e finestra), credenziali e log propri. Senza la variabile non cambia nulla.

- [ ] **Step 1: scrivi i test**

`test/core/device/dev_profile_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/device/dev_profile.dart';

void main() {
  test('devProfile legge e valida la variabile', () {
    expect(devProfile({}), isNull);
    expect(devProfile({'WONDERFLIX_PROFILE': ''}), isNull);
    expect(devProfile({'WONDERFLIX_PROFILE': '  '}), isNull);
    expect(devProfile({'WONDERFLIX_PROFILE': ' B '}), 'b');
    expect(devProfile({'WONDERFLIX_PROFILE': 'luigi2'}), 'luigi2');
    expect(devProfile({'WONDERFLIX_PROFILE': '../x'}), isNull);
    expect(devProfile({'WONDERFLIX_PROFILE': 'a' * 17}), isNull);
  });

  test('nomi per profilo', () {
    expect(prefsPrefixFor(null), 'flutter.');
    expect(prefsPrefixFor('b'), 'flutter.b.');
    expect(sessionKeyFor(null), 'wonderflix.session');
    expect(sessionKeyFor('b'), 'wonderflix.session.b');
    expect(logsFolderFor(null), 'logs');
    expect(logsFolderFor('b'), 'logs-b');
  });
}
```

In `test/core/storage/session_store_test.dart`, dentro `main()`, in fondo:

```dart
  test('chiave personalizzata: sessioni separate', () async {
    final first = SecureSessionStore();
    final other = SecureSessionStore(null, 'wonderflix.session.b');
    await first.write(const StoredSession(userId: 'u1', accessToken: 'a'));
    await other.write(const StoredSession(userId: 'u2', accessToken: 'b'));
    expect((await first.read())?.userId, 'u1');
    expect((await other.read())?.userId, 'u2');
    await other.clear();
    expect(await other.read(), isNull);
    expect((await first.read())?.userId, 'u1');
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/device/dev_profile_test.dart test/core/storage/session_store_test.dart`
Expected: FAIL.

- [ ] **Step 3: scrivi il profilo**

`lib/core/device/dev_profile.dart`:

```dart
import 'dart:io';

import '../storage/session_store.dart';

/// Profilo di sviluppo (variabile d'ambiente `WONDERFLIX_PROFILE`): una
/// seconda istanza con dati e `DeviceId` propri, per provare il watch party
/// sullo stesso PC (spec B §7.2). `null` = istanza normale.
String? devProfile([Map<String, String>? environment]) {
  final value = (environment ?? Platform.environment)['WONDERFLIX_PROFILE']
      ?.trim()
      .toLowerCase();
  if (value == null || !RegExp(r'^[a-z0-9]{1,16}$').hasMatch(value)) {
    return null;
  }
  return value;
}

/// Prefisso delle `SharedPreferences` (quello predefinito è `flutter.`).
String prefsPrefixFor(String? profile) =>
    profile == null ? 'flutter.' : 'flutter.$profile.';

/// Chiave della sessione nel Gestore credenziali.
String sessionKeyFor(String? profile) => profile == null
    ? SecureSessionStore.key
    : '${SecureSessionStore.key}.$profile';

/// Cartella dei log dentro `%LocalAppData%\WonderFlix`.
String logsFolderFor(String? profile) =>
    profile == null ? 'logs' : 'logs-$profile';
```

- [ ] **Step 4: chiave configurabile della sessione**

In `lib/core/storage/session_store.dart`, nella classe `SecureSessionStore`:

```dart
/// Salva la sessione nel Gestore credenziali di Windows.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage, String? storageKey])
      : _storage = storage ?? const FlutterSecureStorage(),
        storageKey = storageKey ?? key;

  static const key = 'wonderflix.session';

  final FlutterSecureStorage _storage;

  /// Chiave usata da questa istanza (diversa per un profilo di sviluppo).
  final String storageKey;
```

e in `read`, `write` e `clear` sostituisci `key: key` con `key: storageKey`.

In `lib/app/providers.dart` aggiungi l'import `import '../core/device/dev_profile.dart';` e sostituisci `sessionStoreProvider`:

```dart
final sessionStoreProvider = Provider<SessionStore>(
    (ref) => SecureSessionStore(null, sessionKeyFor(devProfile())));
```

- [ ] **Step 5: log e preferenze per profilo**

In `lib/core/logging/app_log.dart` aggiungi l'import `import '../device/dev_profile.dart';` e in `logsDirectory()` sostituisci l'ultima riga con:

```dart
  return Directory('$root\\WonderFlix\\${logsFolderFor(devProfile())}');
```

(aggiorna anche il commento: `%LocalAppData%\WonderFlix\logs`, oppure `logs-<profilo>` per un profilo di sviluppo).

In `lib/main.dart` (file CRLF: usa Edit) aggiungi l'import `import 'core/device/dev_profile.dart';` e, dentro il `try`, **prima** di `final prefs = await SharedPreferences.getInstance();`:

```dart
    // Sviluppo: seconda istanza con dati separati (WONDERFLIX_PROFILE).
    final profile = devProfile();
    if (profile != null) {
      SharedPreferences.setPrefix(prefsPrefixFor(profile));
      _log.info('profilo di sviluppo: $profile');
    }
```

- [ ] **Step 6: mutex per profilo**

In `windows/runner/main.cpp`:
- dopo `#include <shobjidl.h>` aggiungi:

```cpp
#include <cwctype>
#include <string>
```

- prima di `int APIENTRY wWinMain(`:

```cpp
// Sviluppo: WONDERFLIX_PROFILE=<nome> avvia un'istanza separata, con dati e
// DeviceId propri (lib/core/device/dev_profile.dart), per provare il watch
// party con due istanze sullo stesso PC. Stesse regole del lato Dart: lettere
// e cifre, massimo 16 caratteri, maiuscole ignorate.
static std::wstring InstanceMutexName() {
  std::wstring name = L"Local\\WonderFlix.SingleInstance";
  wchar_t buffer[64];
  DWORD length = ::GetEnvironmentVariableW(L"WONDERFLIX_PROFILE", buffer, 64);
  if (length == 0 || length >= 64) return name;
  std::wstring profile;
  for (DWORD i = 0; i < length; i++) {
    wchar_t c = buffer[i];
    if (c == L' ') continue;
    if (c > 127 || !std::iswalnum(c)) return name;
    profile += static_cast<wchar_t>(std::towlower(c));
  }
  if (profile.empty() || profile.size() > 16) return name;
  return name + L"." + profile;
}

```

- in `wWinMain` sostituisci:

```cpp
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\WonderFlix.SingleInstance");
```

con:

```cpp
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, InstanceMutexName().c_str());
```

Nota: il lato C++ ignora gli spazi interni, il lato Dart solo quelli ai bordi. Con valori sensati (`b`, `luigi`) coincidono.

- [ ] **Step 7: verifica**

Run: `flutter test test/core/`
Expected: PASS.

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

Compila il runner per verificare il C++ (in Git Bash):

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
flutter build windows --debug
```

Expected: `Built build\windows\x64\runner\Debug\wonderflix.exe`. Se fallisce con `LNK1168`, chiudi l'app aperta (`taskkill //IM wonderflix.exe //F`) e riprova.

- [ ] **Step 8: commit**

```bash
git add lib/core/device/dev_profile.dart test/core/device/dev_profile_test.dart lib/core/storage/session_store.dart test/core/storage/session_store_test.dart lib/app/providers.dart lib/core/logging/app_log.dart lib/main.dart windows/runner/main.cpp
git commit -m "feat: allow a separate development instance for watch party tests"
```

---

### Task 17: verifica finale

**Files:** nessuno (salvo correzioni).

- [ ] **Step 1: analisi e test**

```bash
flutter analyze
flutter test
```

Expected: `No issues found!` e tutti i test verdi (erano 468 prima del piano).

- [ ] **Step 2: build di release**

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
flutter build windows --release
```

Expected: `Built build\windows\x64\runner\Release\wonderflix.exe`.

- [ ] **Step 3: controllo dei file generati**

Run: `git status --short`
Expected: nessun file modificato. Se compaiono solo `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/`.

- [ ] **Step 4: istruzioni per la prova manuale (da riportare all'utente)**

L'app avviata da Claude viene virtualizzata (pacchetto MSIX): le due istanze le avvia l'utente.

1. Prima istanza: doppio clic su `build\windows\x64\runner\Release\wonderflix.exe` e login con l'utente A.
2. Seconda istanza, da PowerShell nella cartella `build\windows\x64\runner\Release`:

   ```powershell
   $env:WONDERFLIX_PROFILE = 'b'; .\wonderflix.exe
   ```

   Login con l'utente B (la prima volta chiede il login: dati separati).
3. Da controllare:
   - A: dettagli di un film → "Guarda insieme" → si apre il player in pausa, poi parte;
   - B: compare "Watch party · 1" in alto (entro 30 s) → "Unisciti" → A va in pausa un attimo, poi partono insieme;
   - pausa, ripresa e salto (barra, ←/→) da A e da B: l'altro segue;
   - "Watch party · 2" nel player con i membri; "Esci dal watch party" da B: A continua;
   - rete limitata su B (es. limite di banda nel router o Wi-Fi debole): A vede "In attesa degli altri membri…" e può usare "Riprendi senza aspettare";
   - dopo 30 minuti insieme: nessun salto visibile. Nei log (`%LocalAppData%\WonderFlix\logs` e `logs-b`) le righe `[watchparty]` mostrano scarto, velocità e riallineamenti;
   - con la qualità dello streaming più bassa su B (transcodifica), il gruppo resta in sincronia.
