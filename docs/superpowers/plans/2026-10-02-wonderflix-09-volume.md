# WonderFlix — Piano 9: volume ricordato e rotella del mouse

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** realizzare l'issue #3 (il volume scelto passa ai media successivi e ai riavvii dell'app) e l'issue #4 (la rotella del mouse cambia il volume in tutto il player, barra del volume compresa).

**Decisioni prese con l'utente (2026-10-02):**
1. Si ricorda **solo il livello** (0–100), non il muto: ogni player parte senza muto. 0 si salva com'è.
2. Valore in un provider a sé (`player.volume`), non in `PlayerSettings`. In memoria cambia subito; su disco si scrive 500 ms dopo l'ultimo cambio.
3. Rotella: **5 per scatto** come ↑/↓, uno scatto per evento. Fa quello che fa un tasto: pillola "Volume N%", schermata di pausa chiusa, controlli che non compaiono.
4. Rotella attiva **in tutto il player tranne il pannello "Audio e sottotitoli"**, dove scorre la lista e non tocca mai il volume.
5. Dopo la prova: merge, push, **release 0.4.1 non obbligatoria**; chiusura delle issue solo con l'ok dell'utente.

**Architecture:**
- `lib/features/player/player_volume.dart`: `PlayerVolumeController` (`Notifier<double>`) e `playerVolumeProvider`. Legge e scrive `player.volume` in `SharedPreferences`, con scrittura differita.
- `PlayerController` parte dal volume salvato e lo aggiorna in `setVolume` (barra, ↑/↓ e rotella passano tutte da lì).
- `PlayerScreen`: il `Listener` esterno gestisce `onPointerSignal` tramite `pointerSignalResolver` e chiama `keyActivity()` + `_run(volumeUp/volumeDown)`.
- `TracksPanel`: un `Listener` registra un'azione vuota per ogni rotella, così la rotella non esce mai dal pannello.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, shared_preferences 2.5, fake_async.

**Spec:** `docs/superpowers/specs/2026-10-02-wonderflix-volume-design.md`. **Worktree:** `.claude/worktrees/piano-9`, branch `feat/piano-9`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves`): solo il riferimento `(#3)`/`(#4)` dove indicato.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-9`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde (a inizio piano: 1087 test). Nessuna stringa nuova: gli ARB non si toccano.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione e fine riga:** niente `dart format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`).
- **Durate e misure:** costanti nominate e commentate. Commenti in italiano, codice in inglese, come nel resto del codice.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **`SharedPreferences` (legacy, quella dell'app):** `setDouble` aggiorna subito la cache in memoria, poi scrive su disco in modo asincrono; `getDouble` legge la cache. Nei test, `SharedPreferences.setMockInitialValues(…)` e poi `await SharedPreferences.getInstance()` danno un'istanza nuova con quei valori (come in `test/features/player/player_settings_test.dart`).
- **`sharedPreferencesProvider`** (`lib/app/providers.dart`) lancia `UnimplementedError` se non è sovrascritto. Dopo il Task 2 `PlayerController` legge `playerVolumeProvider`: **ogni** test che crea un player deve sovrascriverlo con `FakePlayerVolume`. I file sono quattro: `test/features/player/player_controller_test.dart`, `test/features/player/player_screen_test.dart`, `test/features/watch_party/party_handover_test.dart`, `test/features/watch_party/party_player_test.dart` (gli unici che sovrascrivono `videoEngineFactoryProvider`).
- **Riverpod 3:** `overrideWith(() => …)` costruisce il notifier quando il provider si legge la prima volta: una variabile cambiata nel test prima di `start()`/`pumpPlayer` vale (come `settings` con `FakePlayerSettings`). `NotifierProvider` senza `.autoDispose` resta vivo finché vive il container. Dentro `ref.onDispose` non si usa `ref`: `PlayerVolumeController` tiene da parte `SharedPreferences` in `build()`.
- **Rotella in Flutter:** uno scatto arriva come `PointerScrollEvent` (`scrollDelta.dy` > 0 = rotella in giù; su Windows circa 60 px). Il touchpad di precisione arriva come `PointerPanZoom…`, non come `PointerScrollEvent`. `GestureBinding.instance.pointerSignalResolver.register(event, callback)`: **vince il primo che registra**, e l'evento arriva prima al widget più interno. Uno `Scrollable` registra solo se può scorrere in quella direzione. `GestureBinding` risolve dopo che tutti i `Listener` sul percorso hanno ricevuto l'evento.
- **Nei widget test:** `TestPointer(1, PointerDeviceKind.mouse)`, `tester.sendEventToBinding(pointer.hover(posizione))`, poi `tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)))` (come in `test/ui/smooth_scroll_test.dart`). `scroll` usa l'ultima posizione del puntatore: si può scorrere **senza** un nuovo `hover`. Serve, perché `hover` fa comparire i controlli (`MouseRegion.onHover` → `pointerActivity`). `package:flutter/gestures.dart` non è esportato da `material.dart`: va importato dove si usano `GestureBinding`, `PointerScrollEvent`, `PointerDeviceKind`.
- **Funzioni locali nei test:** in `player_screen_test.dart` gli helper (`controlsOpacity`, `pauseUntilPauseScreen`, `withNextEpisode`) sono funzioni locali di `main()`: un test può usarle solo se sta **dopo** la loro dichiarazione.
- **Volume e pillola oggi:** `PlayerScreen._run(PlayerCommand.volumeUp/volumeDown)` chiama `controller.changeVolumeBy(±volumeStep)` e `_showVolume()`. `setVolume` emette lo stato nuovo prima di qualsiasi `await`, quindi la pillola legge già il valore nuovo. `_onKey` chiama `_chrome.keyActivity()` prima del comando.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `lib/features/player/player_volume.dart` | crea | `PlayerVolumeController`, `playerVolumeProvider` |
| `lib/features/player/player_controller.dart` | modifica | volume iniziale dal provider; `setVolume` lo aggiorna |
| `lib/features/player/tracks_panel.dart` | modifica | `Listener` che tiene la rotella dentro il pannello |
| `lib/features/player/player_screen.dart` | modifica | rotella → volume (`_onPointerSignal`) |
| `test/support/playback_fakes.dart` | modifica | `FakePlayerVolume` |
| `test/features/player/player_volume_test.dart` | crea | lettura, scrittura differita, chiusura |
| `test/features/player/player_controller_test.dart` | modifica | override + test del volume |
| `test/features/player/player_screen_test.dart` | modifica | override + test episodio successivo e rotella |
| `test/features/player/tracks_panel_test.dart` | modifica | test della rotella sul pannello |
| `test/features/watch_party/party_handover_test.dart`, `party_player_test.dart` | modifica | solo override |

## Gruppi per i subagent

- **Gruppo A (Task 1–2):** volume ricordato (#3).
- **Gruppo B (Task 3–4):** rotella (#4).
- **Gruppo C (Task 5):** verifica finale.

---

### Task 1: volume salvato (`PlayerVolumeController`)

**Files:**
- Create: `lib/features/player/player_volume.dart`
- Create: `test/features/player/player_volume_test.dart`
- Modify: `test/support/playback_fakes.dart` (aggiunge `FakePlayerVolume` dopo `FakePlayerSettings`)

- [ ] **Step 1: scrivi i test che falliscono**

Crea `test/features/player/player_volume_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/player/player_volume.dart';

void main() {
  const key = 'player.volume';

  Future<SharedPreferences> prefsWith(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    return SharedPreferences.getInstance();
  }

  ProviderContainer containerFor(SharedPreferences prefs) =>
      ProviderContainer.test(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);

  test('volume salvato: assente, valido, fuori intervallo, NaN', () async {
    Future<double> read(Map<String, Object> saved) async =>
        containerFor(await prefsWith(saved)).read(playerVolumeProvider);
    expect(await read({}), 100);
    expect(await read({key: 35.0}), 35);
    expect(await read({key: 150.0}), 100);
    expect(await read({key: -5.0}), 0);
    expect(await read({key: double.nan}), 100);
  });

  test('set: stato subito, disco dopo 500 ms dall\'ultimo cambio', () async {
    final prefs = await prefsWith({});
    fakeAsync((async) {
      final container = containerFor(prefs);
      final volume = container.read(playerVolumeProvider.notifier);
      volume.set(80);
      expect(container.read(playerVolumeProvider), 80);
      async.elapse(const Duration(milliseconds: 300));
      volume.set(60);
      expect(container.read(playerVolumeProvider), 60);
      // 700 ms dal primo cambio: il conto è ripartito con il secondo, l'80
      // non è mai stato scritto.
      async.elapse(const Duration(milliseconds: 400));
      expect(prefs.getDouble(key), isNull);
      async.elapse(const Duration(milliseconds: 100));
      expect(prefs.getDouble(key), 60);
    });
  });

  test('set: stesso valore, fuori intervallo, NaN', () async {
    final prefs = await prefsWith({});
    fakeAsync((async) {
      final container = containerFor(prefs);
      final volume = container.read(playerVolumeProvider.notifier);
      // 100 è già lo stato (chiave assente): niente da scrivere.
      volume.set(100);
      volume.set(150);
      volume.set(double.nan);
      async.elapse(PlayerVolumeController.saveDelay);
      expect(container.read(playerVolumeProvider), 100);
      expect(prefs.getDouble(key), isNull);

      volume.set(-5);
      expect(container.read(playerVolumeProvider), 0);
      async.elapse(PlayerVolumeController.saveDelay);
      expect(prefs.getDouble(key), 0);
    });
  });

  test('chiusura con una scrittura in sospeso: scritta subito', () async {
    final prefs = await prefsWith({});
    fakeAsync((async) {
      final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      container.read(playerVolumeProvider.notifier).set(30);
      expect(prefs.getDouble(key), isNull);
      container.dispose();
      expect(prefs.getDouble(key), 30);
      // Il timer è fermo: nessun'altra scrittura.
      async.elapse(PlayerVolumeController.saveDelay);
      expect(prefs.getDouble(key), 30);
    });
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/player/player_volume_test.dart`
Expected: FAIL in compilazione (`player_volume.dart` non esiste).

- [ ] **Step 3: scrivi `lib/features/player/player_volume.dart`**

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';

/// Volume del player ricordato tra un media e l'altro e tra un avvio e
/// l'altro (issue #3): solo il livello 0–100, il muto no.
class PlayerVolumeController extends Notifier<double> {
  static const _key = 'player.volume';

  /// Pausa dall'ultimo cambio prima di scrivere su disco: trascinando la
  /// barra i cambi arrivano a decine al secondo.
  static const saveDelay = Duration(milliseconds: 500);

  /// Tenute da parte in [build]: in `onDispose` non si può usare `ref`.
  late SharedPreferences _prefs;
  Timer? _timer;

  /// Valore ancora da scrivere su disco.
  double? _pending;

  @override
  double build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    ref.onDispose(_write);
    final saved = _prefs.getDouble(_key);
    if (saved == null || saved.isNaN) return 100;
    return saved.clamp(0.0, 100.0);
  }

  /// Nuovo volume, portato tra 0 e 100: lo stato cambia subito, il disco
  /// dopo [saveDelay] dall'ultimo cambio.
  void set(double volume) {
    if (volume.isNaN) return;
    final value = volume.clamp(0.0, 100.0);
    if (value == state) return;
    state = value;
    _pending = value;
    _timer?.cancel();
    _timer = Timer(saveDelay, _write);
  }

  /// Scrive il valore in sospeso, se c'è (anche alla chiusura del provider).
  void _write() {
    _timer?.cancel();
    _timer = null;
    final value = _pending;
    if (value == null) return;
    _pending = null;
    unawaited(_prefs.setDouble(_key, value));
  }
}

final playerVolumeProvider =
    NotifierProvider<PlayerVolumeController, double>(
        PlayerVolumeController.new);
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/player/player_volume_test.dart`
Expected: PASS (4 test).

- [ ] **Step 5: aggiungi `FakePlayerVolume` ai fake**

In `test/support/playback_fakes.dart`, tra gli import aggiungi (in ordine alfabetico, vicino agli altri `package:wonderflix/features/player/…`):

```dart
import 'package:wonderflix/features/player/player_volume.dart';
```

e subito dopo la classe `FakePlayerSettings`:

```dart
/// Volume ricordato solo in memoria: niente disco né timer.
class FakePlayerVolume extends PlayerVolumeController {
  FakePlayerVolume([this.initial = 100]);

  final double initial;

  @override
  double build() => initial;

  @override
  void set(double volume) => state = volume.clamp(0.0, 100.0);
}
```

- [ ] **Step 6: analyze e test, poi commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde, 1091 test).

```bash
git add lib/features/player/player_volume.dart test/features/player/player_volume_test.dart test/support/playback_fakes.dart
git commit -m "feat: remember the player volume level (#3)"
```

---

### Task 2: il player parte dal volume salvato e lo aggiorna

**Files:**
- Modify: `lib/features/player/player_controller.dart` (import; `build()`; `setVolume`)
- Modify: `test/features/player/player_controller_test.dart`
- Modify: `test/features/player/player_screen_test.dart`
- Modify: `test/features/watch_party/party_handover_test.dart`
- Modify: `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: override di `playerVolumeProvider` nei quattro file di test**

In tutti e quattro aggiungi l'import:

```dart
import 'package:wonderflix/features/player/player_volume.dart';
```

`test/features/player/player_controller_test.dart`: accanto a `var settings = const PlayerSettings();` aggiungi

```dart
  var savedVolume = 100.0;
```

in `setUp`, dopo `settings = const PlayerSettings();`:

```dart
    savedVolume = 100;
```

e nella lista degli `overrides`, subito dopo la riga di `playerSettingsProvider`:

```dart
        playerVolumeProvider.overrideWith(() => FakePlayerVolume(savedVolume)),
```

`test/features/player/player_screen_test.dart`: stesse tre aggiunte (`var savedVolume = 100.0;` accanto a `var settings`, `savedVolume = 100;` in `setUp` dopo `settings = const PlayerSettings();`, override dopo `playerSettingsProvider` in `pumpPlayer`).

`test/features/watch_party/party_handover_test.dart` e `test/features/watch_party/party_player_test.dart`: solo l'override, dopo quello di `playerSettingsProvider`:

```dart
        playerVolumeProvider.overrideWith(FakePlayerVolume.new),
```

- [ ] **Step 2: scrivi i test che falliscono**

In `test/features/player/player_controller_test.dart`, dopo il test `'comandi: pausa, salti nei limiti, volume, muto, ritardo'`:

```dart
  test('volume: parte da quello salvato, senza muto', () async {
    savedVolume = 40;
    await start();
    expect(view().volume, 40);
    expect(view().muted, isFalse);
    expect(engine.volumes.first, 40, reason: 'applicato all\'apertura');
  });

  test('volume: barra e tasti lo salvano, il muto no', () async {
    final controller = await start();
    await controller.setVolume(70);
    expect(container.read(playerVolumeProvider), 70);
    await controller.changeVolumeBy(-5);
    expect(container.read(playerVolumeProvider), 65);
    await controller.toggleMute();
    expect(container.read(playerVolumeProvider), 65,
        reason: 'il muto non si salva');
  });
```

In `test/features/player/player_screen_test.dart`, subito dopo il test `'episodio successivo già iniziato: riprende da dove era'` (deve stare dopo `withNextEpisode`):

```dart
  testWidgets('volume: l\'episodio successivo parte dall\'ultimo scelto',
      (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.volumes.last, 90);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumes.last, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(engines, hasLength(2));
    expect(engines.last.volumes.first, 90,
        reason: 'stesso volume, senza muto');
    await unmount(tester);
  });
```

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart`
Expected: FAIL nei tre test nuovi (il volume parte da 100; `playerVolumeProvider` resta 100 dopo `setVolume`). Gli altri passano.

- [ ] **Step 4: implementa in `lib/features/player/player_controller.dart`**

Import, dopo `import 'player_settings.dart';`:

```dart
import 'player_volume.dart';
```

In `build()`, sostituisci

```dart
    _settings = ref.read(playerSettingsProvider);
    _listenToEngine();
```

con

```dart
    _settings = ref.read(playerSettingsProvider);
    // Ogni player parte dall'ultimo volume scelto, senza muto (issue #3).
    _view = _view.copyWith(volume: ref.read(playerVolumeProvider));
    _listenToEngine();
```

Sostituisci `setVolume`:

```dart
  /// 0–100. Toglie anche il muto e diventa il volume dei prossimi player
  /// (issue #3).
  Future<void> setVolume(double volume) async {
    final value = volume.clamp(0.0, 100.0);
    _emit(_view.copyWith(volume: value, muted: false));
    if (ref.mounted) ref.read(playerVolumeProvider.notifier).set(value);
    await _engine.setVolume(value);
  }
```

`toggleMute` e `changeVolumeBy` non cambiano.

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart test/features/watch_party`
Expected: PASS.

- [ ] **Step 6: analyze e test, poi commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde, 1094 test).

```bash
git add lib/features/player/player_controller.dart test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart test/features/watch_party/party_handover_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: start each player from the saved volume (#3)"
```

---

### Task 3: la rotella resta dentro il pannello "Audio e sottotitoli"

**Files:**
- Modify: `lib/features/player/tracks_panel.dart` (import; fine di `TracksPanel.build`)
- Modify: `test/features/player/tracks_panel_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

In `test/features/player/tracks_panel_test.dart` aggiungi l'import `import 'package:flutter/gestures.dart';` (primo della lista) e, in fondo a `main()`:

```dart
  /// Il pannello a destra, dentro un `Listener` che conta le rotelle che
  /// arrivano fin lì (come il player sotto il pannello).
  Future<int Function()> pumpOverPlayer(WidgetTester tester,
      {List<MediaStreamInfo>? subtitles}) async {
    var outside = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) => GestureBinding
              .instance.pointerSignalResolver
              .register(event, (_) => outside++),
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: TracksPanel.width,
              child: panel(subtitles: subtitles),
            ),
          ),
        ),
      ),
    );
    return () => outside;
  }

  testWidgets('rotella: lista corta, non esce dal pannello', (tester) async {
    final outside = await pumpOverPlayer(tester);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.byType(TracksPanel))));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    expect(outside(), 0);

    // Fuori dal pannello arriva a chi sta sotto.
    await tester.sendEventToBinding(wheel.hover(const Offset(200, 450)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    expect(outside(), 1);
  });

  testWidgets('rotella: una lista lunga scorre', (tester) async {
    final outside = await pumpOverPlayer(tester, subtitles: [
      for (var i = 0; i < 20; i++)
        MediaStreamInfo(
            index: 10 + i,
            kind: StreamKind.subtitle,
            displayTitle: 'Sottotitolo $i'),
    ]);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.byType(TracksPanel))));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.descendant(
            of: find.byType(TracksPanel), matching: find.byType(Scrollable)))
        .position;
    expect(position.pixels, greaterThan(0));
    expect(outside(), 0);
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/player/tracks_panel_test.dart`
Expected: FAIL in `'rotella: lista corta, non esce dal pannello'` (`outside()` vale 2). Il test della lista lunga passa già: lo `Scrollable` registra per primo.

- [ ] **Step 3: implementa in `lib/features/player/tracks_panel.dart`**

Import, prima di `import 'package:flutter/material.dart';`:

```dart
import 'package:flutter/gestures.dart';
```

In `TracksPanel.build` cambia la prima riga del `return` finale: da

```dart
    return Material(
      color: WfColors.surface.withValues(alpha: 0.94),
```

a

```dart
    final content = Material(
      color: WfColors.surface.withValues(alpha: 0.94),
```

(il resto del `Material` e il suo `);` restano identici, senza reindentare) e subito dopo quel `);`, prima della `}` di chiusura di `build`, aggiungi:

```dart
    // La rotella sul pannello non arriva mai al volume del player (issue
    // #4). Vince chi registra per primo, cioè il widget più interno: se la
    // lista può scorrere registra lei; se no (in cima, in fondo, lista
    // corta) vince questa azione vuota.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver
              .register(event, (_) {});
        }
      },
      child: content,
    );
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/player/tracks_panel_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze e test, poi commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde, 1096 test).

```bash
git add lib/features/player/tracks_panel.dart test/features/player/tracks_panel_test.dart
git commit -m "feat: keep the mouse wheel inside the tracks panel (#4)"
```

---

### Task 4: la rotella cambia il volume nel player

**Files:**
- Modify: `lib/features/player/player_screen.dart` (`Listener` in `build`; nuovo metodo `_onPointerSignal` dopo `_onKey`)
- Modify: `test/features/player/player_screen_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

In `test/features/player/player_screen_test.dart`, subito dopo il test `'pausa: con il pannello aperto non compare'` (deve stare dopo `pauseUntilPauseScreen`):

```dart
  testWidgets('rotella: volume come le frecce, anche sulla barra del volume',
      (tester) async {
    savedVolume = 50;
    await pumpPlayer(tester);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(const Offset(720, 450)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(engine.volumes.last, 45);
    expect(find.text('Volume 45%'), findsOneWidget);

    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    await tester.pumpAndSettle();
    expect(engine.volumes.last, 55);
    expect(find.text('Volume 55%'), findsOneWidget);

    // Scorrimento orizzontale: niente.
    final count = engine.volumes.length;
    await tester.sendEventToBinding(wheel.scroll(const Offset(60, 0)));
    await tester.pumpAndSettle();
    expect(engine.volumes, hasLength(count));

    // Sopra la barra del volume.
    final slider = find.byKey(const Key('volume-slider'));
    await tester.sendEventToBinding(wheel.hover(tester.getCenter(slider)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    await tester.pumpAndSettle();
    expect(engine.volumes.last, 60);
    expect(tester.widget<Slider>(slider).value, 60);
    await unmount(tester);
  });

  testWidgets('rotella: i controlli non compaiono; chiude "Stai guardando"',
      (tester) async {
    await pumpPlayer(tester);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(const Offset(720, 450)));
    await tester.pump(PlayerChromeController.hideDelay);
    await tester.pumpAndSettle();
    expect(controlsOpacity(tester), 0);

    // Senza un nuovo movimento del mouse, come un tasto.
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(find.text('Volume 95%'), findsOneWidget);
    expect(controlsOpacity(tester), 0);

    await pauseUntilPauseScreen(tester);
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    expect(controlsOpacity(tester), 0);
    expect(engine.volumes.last, 90);
    await unmount(tester);
  });

  testWidgets('rotella sul pannello: il volume non cambia', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    final count = engine.volumes.length;
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.byType(TracksPanel))));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    await tester.pumpAndSettle();
    expect(engine.volumes, hasLength(count));
    expect(find.text('Volume 95%'), findsNothing);
    expect(find.text('Volume 100%'), findsNothing);
    await unmount(tester);
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/player/player_screen_test.dart`
Expected: FAIL nei primi due test nuovi (la rotella non fa nulla). Il terzo passa già.

- [ ] **Step 3: implementa in `lib/features/player/player_screen.dart`**

Nel `Listener` di `build` (quello con `onPointerDown` per il tasto "indietro" del mouse), dopo `onPointerMove: (_) => _chrome.pointerActivity(),` aggiungi:

```dart
          onPointerSignal: _onPointerSignal,
```

Subito dopo il metodo `_onKey` aggiungi:

```dart
  /// Rotella del mouse: volume come ↑/↓ (issue #4), con la pillola e senza
  /// mostrare i controlli. Si registra nel `pointerSignalResolver`, dove
  /// vince il widget più interno: sul pannello "Audio e sottotitoli" la
  /// rotella resta al pannello.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    // Orizzontale (o tilt della rotella): niente.
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      _chrome.keyActivity();
      _run(dy < 0 ? PlayerCommand.volumeUp : PlayerCommand.volumeDown);
    });
  }
```

`package:flutter/gestures.dart` è già importato.

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/player/player_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze e test, poi commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde, 1099 test).

```bash
git add lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
git commit -m "feat: change the volume with the mouse wheel (#4)"
```

---

### Task 5: verifica finale

**Files:**
- Modify: `docs/superpowers/specs/2026-10-02-wonderflix-volume-design.md` (solo se il codice si è discostato dallo spec)

- [ ] **Step 1:** `flutter analyze` senza problemi e `flutter test` tutto verde. Annota il numero dei test (erano 1087; attesi 1099).
- [ ] **Step 2:** `grep -rn "playerVolumeProvider" lib` trova solo `player_volume.dart` e `player_controller.dart`; `grep -rln "videoEngineFactoryProvider" test` dà i quattro file della mappa, e tutti contengono `FakePlayerVolume`.
- [ ] **Step 3:** build: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` e `flutter build windows --debug`. Se l'app dell'utente è aperta e dà `LNK1168`/`LNK1104`, **non** chiuderla: segnalalo.
- [ ] **Step 4:** se durante i task qualcosa è cambiato rispetto allo spec (nomi, comportamenti), allinea lo spec e fai commit:

```bash
git add docs/superpowers/specs/2026-10-02-wonderflix-volume-design.md
git commit -m "docs: align plan 9 spec with the implementation"
```

## Prova manuale (con l'utente, sul server reale)

Build di release dal worktree: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` e `flutter build windows --release --dart-define-from-file=D:/Github/wonderflix/config/wonderflix.json` (il worktree non ha la config). L'exe lo avvia l'utente da Esplora risorse: un'app avviata da questa sessione scrive le preferenze in una cartella virtualizzata.

- **Volume ricordato (#3):**
  - volume abbassato → episodio successivo (pulsante, post-play, conto alla rovescia): stesso volume;
  - volume abbassato → chiudere il player → aprire un altro film: stesso volume;
  - volume abbassato → chiudere l'app → riaprirla e avviare un titolo: stesso volume;
  - muto → episodio successivo: audio di nuovo attivo, al volume di prima;
  - watch party: "Guarda insieme" dal player non riporta il volume a 100.
- **Rotella (#4):**
  - sul film (controlli nascosti e visibili), sulla barra del volume, sulla barra di avanzamento, nel post-play, sulla schermata di pausa: pillola e volume corretti;
  - sul pannello "Audio e sottotitoli": la lista scorre, il volume no;
  - rotella "veloce" o a scorrimento libero (se disponibile): il volume non salta in modo strano.
- **Regressioni:** ↑/↓/M, trascinamento della barra del volume, scorrimento delle pagine fuori dal player.

## Dopo la prova (fuori dai task)

Con l'ok dell'utente: merge fast-forward su `main` (prima `git fetch`: se `origin/main` è avanti, rebase dei commit locali), push, rimozione di worktree e branch. Poi **release 0.4.1 non obbligatoria** secondo `docs/RELEASING.md`:
- versione in `pubspec.yaml` e commit `chore: release 0.4.1`;
- tag solo con l'ok dell'utente;
- note in italiano scritte nella bozza, da `git log v0.4.0..v0.4.1`, **senza** marcatore `min-version`;
- la pubblicazione la fa l'utente.

Dopo la pubblicazione, solo con l'ok dell'utente: commento e chiusura delle issue #3 e #4.

## Note di esecuzione (2026-10-02)

Differenze rispetto ai task, nate dalle revisioni:

- **Task 1** (`39f4523`, poi `bb4d5a9`): `_write` è diventato `Future<void> flush()` pubblico. Il provider dell'app non viene mai dismesso: la finestra si distrugge e il processo finisce. Il test del `NaN` ora lo prova davvero, perché `double.nan.clamp(0, 100)` vale 100. C'è un test in più per `flush`. `FakePlayerVolume` ignora `NaN` e conta i `flush`.
- **Task 2** (`4bb16a6`, poi `efd7cd2`): `PlayerScreen._onWindowClose` aspetta anche `flush()` prima di `destroy()`, con un test che lo prova (`FakePlayerVolume.holdFlush`).
- **Task 3** (`6082057`, poi `a56cef2`): il test della lista lunga prova anche la rotella in su con la lista ferma in cima.
- **Task 4** (`5c7f1e5`, poi `b3fddb0`): il test del pannello parte con la rotella in su, così prova il pannello e non la lista. I commenti di `_run` e `keyActivity` citano la rotella. C'è un test della rotella durante il caricamento.
- **Conteggi reali:** 1092 dopo il Task 1, 1096 dopo il Task 2, 1098 dopo il Task 3, 1102 dopo il Task 4.
- **Per la prova manuale:**
  - rotelle ad alta risoluzione e touchpad non di precisione possono dare più passi per scatto fisico;
  - in riproduzione, con la rotella sopra la barra del volume senza muovere il mouse, i controlli spariscono dopo 3 s, come con ↑/↓.
