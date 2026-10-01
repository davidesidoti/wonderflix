# WonderFlix — Piano 8b: player, caricamento, pausa e pannello

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** secondo piano dello Spec D (rinnovo del player): caricamento con sfondo, logo e linea oro fino al primo fotogramma; spinner del buffering solo oltre 300 ms; errore sullo sfondo del titolo con entrata scaglionata; schermata di pausa "Stai guardando"; pannello "Audio e sottotitoli" laterale con la dimensione dei sottotitoli.

**Decisioni prese con l'utente (2026-10-01):**
1. Il pannello è a tutta altezza **sopra** i controlli: copre la parte destra della barra (icone dei sottotitoli e dello schermo intero). Si chiude con ×, Esc o un clic sul film.
2. La dimensione dei sottotitoli nel pannello: quattro "pillole" selezionabili (non il `SegmentedButton` delle Impostazioni). Si applica subito e si salva nelle Impostazioni.
3. Durante il caricamento la freccia "indietro" sta nello strato del caricamento (stessa posizione di quella dei controlli); i controlli veri restano nascosti finché il video non parte.
4. Se il motore non segnala il primo fotogramma entro **3 s** da `ready` (`PlayerScreen.firstFrameTimeout`), il caricamento sfuma comunque.
5. La schermata di pausa non compare mentre il gruppo è "in attesa" (stato del gruppo, non la comparsa ritardata del suo avviso). Il controller riceve `setPlayback(playing:, canShowPauseScreen:)` al posto di `setPlaying`; ogni tasto chiama `keyActivity()`.
6. Testi nuovi: "Stai guardando", "Dimensione", "Chiudi". "In pausa" riusa quello della pillola.

**Architecture:**
- `PlayerChromeController` (`lib/features/player/player_chrome.dart`): `pauseScreen`, `pauseScreenDelay` (8 s), `setPlayback`, `keyActivity`. `PlayerScreen._syncPlayback()` calcola se la pausa è ammessa (pronto, fermo, niente buffering, non finito, elemento arrivato, gruppo non in attesa).
- `VideoEngine.firstFrame` (`MediaKitEngine`: `VideoController.waitUntilFirstFrameRendered`). `PlayerScreen` tiene `_firstFrame` (più il timer di sicurezza).
- `lib/features/player/player_loading.dart`: `PlayerLoadingLayer`, `LoadingLine`, `BufferingSpinner`, `PlayerErrorLayer`. Sostituisce `_PlayerError` e lo spinner di `player_screen.dart`.
- `lib/features/player/pause_screen.dart`: `PauseScreen`, `pauseScreenMeta`.
- `lib/features/player/tracks_panel.dart` riscritto: `TracksPanel` in colonna con voci scaglionate e dimensione dei sottotitoli; `TracksPanelHost` (entrata e uscita, velo sul film). `PlayerController.setSubtitleScale`; `subtitleScaleLabel` in `player_settings.dart`, condivisa con le Impostazioni.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, media_kit_video 2.0.1, lucide_icons_flutter 3.1.20, clock, fake_async.

**Spec:** `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md` (§5.1, §10, §11, §14). **Worktree:** `.claude/worktrees/rinnovo-player-8b`, branch `feat/rinnovo-player-8b`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/rinnovo-player-8b`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git. Niente script heredoc o Python inline in Bash (il controllo dei permessi del worktree li rifiuta): per i file usa gli strumenti Edit/Write.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde (a inizio piano: 971 test). Dopo aver toccato gli ARB: `flutter gen-l10n`. Un test rosso deve fermare il commit (niente `;` tra test e commit).
- **File generati:** `flutter analyze`/`flutter test` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga: `git checkout -- windows/flutter/` prima di ogni commit.
- **Formattazione e fine riga:** niente `dart format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`). I file nuovi si scrivono interi.
- **Colori:** solo `WfColors`. **Durate e curve:** token di `WfMotion` o costanti nominate e commentate. **Tempo:** `clock.now()`, mai `DateTime.now()`. **Icone:** solo `LucideIcons`. **Testi UI:** negli ARB (it + en). Commenti in italiano.
- **Widget test:**
  - `pumpApp` (`test/support/pump_app.dart`): finestra 1440×900, movimento **ridotto** salvo `motion: MotionLevel.full`.
  - `player_screen_test` e `party_player_test` montano l'app senza `WfMotionScope`: movimento ridotto.
  - **Animazioni continue:** `LoadingLine` e lo spinner (`CircularProgressIndicator`) girano finché sono a schermo. Mai `pumpAndSettle` mentre si vedono (si blocca): `pump(durata)`. Il caricamento, sfumato via, esce dall'albero; nei test del player il motore finto si apre subito, quindi dopo `pumpPlayer` (che fa `pumpAndSettle`) il caricamento non c'è più.
  - **Uscite:** i widget che sfumano via (spinner, pausa, pannello, caricamento) restano nell'albero fino alla fine della dissolvenza (e un fotogramma in più per l'`onEnd`): prima di aspettarsi che un testo sia sparito, `pumpAndSettle` (se non c'è un'animazione continua) o `pump()` + `pump(durata)` + `pump()`.
  - `AnimationController` risulta completato solo al fotogramma dopo aver raggiunto la durata.
- **Fake:**
  - `FakeVideoEngine` (`test/support/playback_fakes.dart`): `emitBuffering`, `emitPosition`, `subtitleScales`, `failOpens`; dopo il Task 4 anche `holdFirstFrame` e `completeFirstFrame()`.
  - `FakePlayerSettings` (`update` cambia lo stato).
  - `testItem` (`test/support/library_fakes.dart`): `overview`, `genres`, `year`, `runtimeMinutes`; ha uno sfondo, nessun logo.
- **Se il codice del piano ha un errore** (analyzer, import, un'API con firma diversa, un dettaglio di un test): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **media_kit_video 2.0.1:**
  - `VideoController.waitUntilFirstFrameRendered` è un `Future<void>`.
  - Su Windows si completa al primo `VideoOutput.Resize` con dimensioni valide, **una volta per controller** (cioè per motore: il player ne crea uno per schermata). Per "Riprova" e per il ripiego sulla conversione è già completato.
- **`PlayerController`:**
  - legge le impostazioni una volta sola in `build` (`_settings`): `setSubtitleScale` deve aggiornare anche quella copia;
  - `buffering` arriva da `engine.bufferingStream`.
- **`imageUrlsProvider`** sta in `lib/features/library/library_providers.dart`:
  - `urls.backdrop(item)` (1920 px, la stessa della testata della scheda), `urls.poster(item)`, `urls.logo(item)` (per gli episodi quello della serie);
  - `BackdropImage` (`lib/ui/backdrop_image.dart`) usa la locandina sfocata se manca lo sfondo.
- **`StaggerGroup(count:, stagger:, itemDuration:, child:)` e `StaggerItem(index:, child:)`** (`lib/ui/staggered_entrance.dart`): con le animazioni ridotte tutto è subito visibile.
- **`JellyfinItem.runtime`** (`Duration?`); `formatRuntime` e `cardTitle`/`cardSubtitle` in `lib/features/library/item_labels.dart`.
- **`ref.listen` nel `build` di `PlayerScreen`:** le callback partono quando il provider cambia, non durante la build. Il controller dell'interfaccia può quindi notificare (e la schermata fare `setState`) da lì.
- **`TweenAnimationBuilder`** anima da `begin` alla prima build e da dove si trova quando cambia `end`: serve per le entrate di widget appena montati.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | "Stai guardando", "Dimensione", "Chiudi" |
| `lib/features/player/player_settings.dart` | modifica | `subtitleScaleLabel` |
| `lib/features/settings/player_settings_section.dart` | modifica | usa `subtitleScaleLabel` |
| `lib/features/player/player_chrome.dart` | modifica | pausa: `pauseScreen`, `setPlayback`, `keyActivity` |
| `lib/core/video/video_engine.dart`, `lib/core/video/media_kit_engine.dart` | modifica | `firstFrame` |
| `test/support/playback_fakes.dart` | modifica | `FakeVideoEngine.firstFrame`, `holdFirstFrame`, `completeFirstFrame` |
| `lib/features/player/player_loading.dart` | crea | caricamento, linea, spinner, errore |
| `lib/features/player/pause_screen.dart` | crea | schermata di pausa |
| `lib/features/player/player_controller.dart` | modifica | `setSubtitleScale` |
| `lib/features/player/tracks_panel.dart` | modifica (riscrittura) | pannello laterale e host |
| `lib/features/player/player_screen.dart` | modifica | collega strati, pausa, pannello |
| `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md` | modifica | §10.1, §14 |
| test | crea/modifica | vedi i singoli task |

## Gruppi per i subagent

- **Gruppo A (Task 1–2):** testi ed etichette; pausa nel controller.
- **Gruppo B (Task 3–4):** caricamento, buffering, errore.
- **Gruppo C (Task 5–6):** schermata di pausa.
- **Gruppo D (Task 7–9):** dimensione dei sottotitoli e pannello.
- **Gruppo E (Task 10):** spec e verifica finale.

---

### Task 1: testi ed etichette delle dimensioni

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify: `lib/features/player/player_settings.dart`
- Modify: `lib/features/settings/player_settings_section.dart`
- Create: `test/app/l10n_plan8b_test.dart`
- Test: `test/features/player/player_settings_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/app/l10n_plan8b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 8b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerWatching, 'Stai guardando');
    expect(it.playerSubtitleSize, 'Dimensione');
    expect(it.playerClosePanel, 'Chiudi');
    expect(en.playerWatching, "You're watching");
    expect(en.playerSubtitleSize, 'Size');
    expect(en.playerClosePanel, 'Close');
  });
}
```

In `test/features/player/player_settings_test.dart` aggiungi gli import `import 'package:flutter/widgets.dart';` e `import 'package:wonderflix/l10n/gen/app_localizations.dart';` (se mancano) e, in fondo a `main()`, il test:

```dart
  test('nomi delle dimensioni dei sottotitoli', () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect([for (final scale in subtitleScaleOptions) subtitleScaleLabel(l, scale)],
        ['Piccoli', 'Normali', 'Grandi', 'Molto grandi']);
  });
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/app/l10n_plan8b_test.dart test/features/player/player_settings_test.dart`
Expected: FAIL (`playerWatching` e `subtitleScaleLabel` non esistono).

- [ ] **Step 3: testi.** In `l10n/app_it.arb` sostituisci

```json
  "playerSegmentOutro": "Titoli di coda"
}
```

con

```json
  "playerSegmentOutro": "Titoli di coda",
  "playerWatching": "Stai guardando",
  "playerSubtitleSize": "Dimensione",
  "playerClosePanel": "Chiudi"
}
```

In `l10n/app_en.arb` sostituisci

```json
  "playerSegmentOutro": "End credits"
}
```

con

```json
  "playerSegmentOutro": "End credits",
  "playerWatching": "You're watching",
  "playerSubtitleSize": "Size",
  "playerClosePanel": "Close"
}
```

Poi: `flutter gen-l10n`.

- [ ] **Step 4: etichette condivise.** In `lib/features/player/player_settings.dart` aggiungi l'import `import '../../l10n/gen/app_localizations.dart';` (dopo quelli esistenti) e, subito dopo `const subtitleScaleOptions = [0.8, 1.0, 1.25, 1.5];`, la funzione:

```dart

/// Nome di una dimensione dei sottotitoli (Impostazioni e pannello del
/// player).
String subtitleScaleLabel(AppLocalizations l, double scale) => switch (scale) {
      0.8 => l.settingsSubtitleSmall,
      1.25 => l.settingsSubtitleLarge,
      1.5 => l.settingsSubtitleHuge,
      _ => l.settingsSubtitleNormal,
    };
```

In `lib/features/settings/player_settings_section.dart` togli la mappa

```dart
    final scaleLabels = {
      0.8: l.settingsSubtitleSmall,
      1.0: l.settingsSubtitleNormal,
      1.25: l.settingsSubtitleLarge,
      1.5: l.settingsSubtitleHuge,
    };

```

e sostituisci `ButtonSegment(value: scale, label: Text(scaleLabels[scale]!)),` con `ButtonSegment(value: scale, label: Text(subtitleScaleLabel(l, scale))),` (`player_settings.dart` è già importato: lo usa per `subtitleScaleOptions`).

- [ ] **Step 5: verifica.**

Run: `flutter test test/app/l10n_plan8b_test.dart test/features/player/player_settings_test.dart test/features/settings/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 6: commit.**

```bash
git add l10n/app_it.arb l10n/app_en.arb lib/features/player/player_settings.dart lib/features/settings/player_settings_section.dart test/app/l10n_plan8b_test.dart test/features/player/player_settings_test.dart
git commit -m "feat: add pause screen and panel strings, shared subtitle size labels"
```

---

### Task 2: la pausa nel `PlayerChromeController`

**Files:**
- Modify: `lib/features/player/player_chrome.dart`
- Modify: `lib/features/player/player_screen.dart` (una riga)
- Test: `test/features/player/player_chrome_test.dart`

- [ ] **Step 1: test che falliscono.** In `test/features/player/player_chrome_test.dart` sostituisci (tutte le occorrenze) `setPlaying(true)` con `setPlayback(playing: true)` e `setPlaying(false)` con `setPlayback(playing: false)`. Poi aggiungi, prima del test `'dispose: nessun timer in sospeso'`:

```dart
  test('in pausa, 8 s senza mouse né tasti: schermata di pausa', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      var notified = 0;
      chrome.addListener(() => notified++);
      chrome.setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay -
          const Duration(milliseconds: 100));
      expect(chrome.pauseScreen, isFalse);
      async.elapse(const Duration(milliseconds: 100));
      expect(chrome.pauseScreen, isTrue);
      expect(chrome.controlsVisible, isFalse);
      expect(notified, 1);
      chrome.dispose();
    });
  });

  test('pausa: il mouse la chiude e riporta i controlli; il conto riparte',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      chrome.pointerActivity();
      expect(chrome.pauseScreen, isFalse);
      expect(chrome.controlsVisible, isTrue);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      expect(chrome.pauseScreen, isTrue);
      chrome.dispose();
    });
  });

  test('pausa: un tasto la chiude senza mostrare i controlli', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      chrome.keyActivity();
      expect(chrome.pauseScreen, isFalse);
      expect(chrome.controlsVisible, isFalse);
      async.elapse(const Duration(seconds: 4));
      chrome.keyActivity(); // il conto riparte dal tasto
      async.elapse(const Duration(seconds: 7));
      expect(chrome.pauseScreen, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(chrome.pauseScreen, isTrue);
      chrome.dispose();
    });
  });

  test('pausa non ammessa: niente schermata; se smette di esserlo si chiude',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: false);
      async.elapse(const Duration(seconds: 20));
      expect(chrome.pauseScreen, isFalse);
      expect(chrome.controlsVisible, isTrue);

      chrome.setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      expect(chrome.pauseScreen, isTrue);
      chrome.setPlayback(playing: false, canShowPauseScreen: false);
      expect(chrome.pauseScreen, isFalse);
      chrome.dispose();
    });
  });

  test('pausa: la ripresa la chiude', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      chrome.setPlayback(playing: true);
      expect(chrome.pauseScreen, isFalse);
      chrome.dispose();
    });
  });

  test('pausa: con il pannello aperto non compare', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: true)
        ..togglePanel();
      async.elapse(const Duration(seconds: 20));
      expect(chrome.pauseScreen, isFalse);
      chrome.closePanel();
      async.elapse(PlayerChromeController.pauseScreenDelay);
      expect(chrome.pauseScreen, isTrue);
      chrome.togglePanel();
      expect(chrome.pauseScreen, isFalse, reason: 'aprire il pannello la chiude');
      chrome.dispose();
    });
  });

  test('stessi valori di nuovo: i conti non ripartono', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()..setPlayback(playing: true);
      async.elapse(const Duration(seconds: 2));
      chrome.setPlayback(playing: true);
      async.elapse(const Duration(seconds: 1));
      expect(chrome.controlsVisible, isFalse);
      chrome.dispose();
    });
  });
```

e nel test `'dispose: nessun timer in sospeso'` aggiungi, prima di `chrome.dispose();`, la riga `chrome.setPlayback(playing: false, canShowPauseScreen: true);` (così resta in sospeso anche il timer della pausa).

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/player_chrome_test.dart`
Expected: FAIL (`setPlayback`, `pauseScreen`, `keyActivity`, `pauseScreenDelay` non esistono).

- [ ] **Step 3: implementazione.** In `lib/features/player/player_chrome.dart`:

1. Subito dopo la costante `keyActionWindow` aggiungi:

```dart

  /// In pausa, mouse e tasti fermi per questo tempo: compare la schermata
  /// "Stai guardando" (spec D §11.1).
  static const pauseScreenDelay = Duration(seconds: 8);
```

2. Sostituisci `  bool _playing = false;` con:

```dart
  bool _playing = false;
  bool _pauseScreen = false;

  /// La schermata di pausa è ammessa adesso (lo decide `PlayerScreen`).
  bool _canShowPauseScreen = false;
```

3. Sostituisci `  Timer? _feedbackTimer;` (nei campi) con:

```dart
  Timer? _feedbackTimer;
  Timer? _pauseTimer;
```

4. Dopo `  bool get panelOpen => _panelOpen;` aggiungi:

```dart

  /// Schermata "Stai guardando" mostrata.
  bool get pauseScreen => _pauseScreen;
```

5. Sostituisci il metodo `pointerActivity` con:

```dart
  /// Il mouse si è mosso: controlli visibili, schermata di pausa chiusa, e
  /// i conti per nasconderli ripartono.
  void pointerActivity() {
    final changed = !_controlsVisible || _pauseScreen;
    _controlsVisible = true;
    _pauseScreen = false;
    if (changed) notifyListeners();
    _scheduleHide();
  }

  /// Un tasto: chiude la schermata di pausa e fa ripartire il conto, senza
  /// mostrare i controlli (spec D §9.1).
  void keyActivity() {
    if (_pauseScreen) {
      _pauseScreen = false;
      notifyListeners();
    }
    _scheduleHide();
  }
```

6. Sostituisci il metodo `setPlaying` (con il suo commento) con:

```dart
  /// Riproduzione o pausa, e se la schermata di pausa è ammessa adesso:
  /// file pronto e fermo, niente buffering, video non finito, gruppo non in
  /// attesa (lo calcola `PlayerScreen`). In riproduzione, o se non è più
  /// ammessa, la schermata di pausa si chiude.
  void setPlayback({required bool playing, bool canShowPauseScreen = false}) {
    if (playing == _playing && canShowPauseScreen == _canShowPauseScreen) {
      return;
    }
    _playing = playing;
    _canShowPauseScreen = canShowPauseScreen;
    if (_pauseScreen && (playing || !canShowPauseScreen)) {
      _pauseScreen = false;
      notifyListeners();
    }
    _scheduleHide();
  }
```

7. In `togglePanel` sostituisci

```dart
    _panelOpen = !_panelOpen;
    _controlsVisible = true;
```

con

```dart
    _panelOpen = !_panelOpen;
    _controlsVisible = true;
    _pauseScreen = false;
```

8. Sostituisci il metodo `_scheduleHide` (con il suo commento) con:

```dart
  /// In riproduzione i controlli si nascondono dopo [hideDelay]; in pausa,
  /// se ammessa, dopo [pauseScreenDelay] compare la schermata di pausa (e i
  /// controlli si nascondono). Con il pannello aperto nessuno dei due.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    if (_panelOpen) return;
    if (_playing) {
      if (!_controlsVisible) return;
      _hideTimer = Timer(hideDelay, () {
        _controlsVisible = false;
        notifyListeners();
      });
    } else if (_canShowPauseScreen && !_pauseScreen) {
      _pauseTimer = Timer(pauseScreenDelay, () {
        _pauseScreen = true;
        _controlsVisible = false;
        notifyListeners();
      });
    }
  }
```

9. In `dispose` aggiungi `_pauseTimer?.cancel();` dopo `_feedbackTimer?.cancel();`.

In `lib/features/player/player_screen.dart` sostituisci `_chrome.setPlaying(playing);` con `_chrome.setPlayback(playing: playing);` (il Task 6 lo sostituisce con il calcolo completo).

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/player_chrome.dart lib/features/player/player_screen.dart test/features/player/player_chrome_test.dart
git commit -m "feat: add the pause screen state to the player chrome"
```

---

### Task 3: strati di caricamento, buffering ed errore

**Files:**
- Create: `lib/features/player/player_loading.dart`
- Test: `test/features/player/player_loading_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/features/player/player_loading_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_loading.dart';
import 'package:wonderflix/ui/backdrop_image.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  group('caricamento', () {
    Future<ValueNotifier<(JellyfinItem?, bool)>> pumpLoading(
        WidgetTester tester, {VoidCallback? onBack}) async {
      final state = ValueNotifier<(JellyfinItem?, bool)>((null, true));
      addTearDown(state.dispose);
      // `Scaffold`: la freccia (`IconButton`) vuole un `Material` sopra.
      await pumpApp(
        tester,
        Scaffold(
          body: ValueListenableBuilder<(JellyfinItem?, bool)>(
            valueListenable: state,
            builder: (context, value, _) => PlayerLoadingLayer(
              item: value.$1,
              visible: value.$2,
              onBack: onBack ?? () {},
            ),
          ),
        ),
      );
      return state;
    }

    testWidgets('prima dell\'elemento: solo la linea e la freccia',
        (tester) async {
      var back = 0;
      await pumpLoading(tester, onBack: () => back++);
      expect(find.byType(LoadingLine), findsOneWidget);
      expect(find.byType(BackdropImage), findsNothing);
      await tester.tap(find.byTooltip('Indietro'));
      expect(back, 1);
    });

    testWidgets('con l\'elemento: sfondo e titolo (senza logo)',
        (tester) async {
      final state = await pumpLoading(tester);
      state.value = (testItem(name: 'Dune'), true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(BackdropImage), findsOneWidget);
      expect(find.text('DUNE'), findsOneWidget);
      expect(find.byType(LoadingLine), findsOneWidget);
    });

    testWidgets('con il logo non c\'è il titolo', (tester) async {
      final state = await pumpLoading(tester);
      state.value = (
        JellyfinItem.fromJson({
          'Id': 'm1',
          'Name': 'Dune',
          'Type': 'Movie',
          'ImageTags': {'Primary': 'p', 'Logo': 'l'},
          'BackdropImageTags': ['b'],
        }),
        true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('DUNE'), findsNothing);
    });

    testWidgets('nascosto: sfuma e poi esce dall\'albero', (tester) async {
      final state = await pumpLoading(tester);
      state.value = (testItem(name: 'Dune'), false);
      await tester.pump();
      expect(find.byType(LoadingLine), findsOneWidget,
          reason: 'resta mentre sfuma');
      await tester.pump(const Duration(milliseconds: 200));
      // `onEnd` arriva a dissolvenza finita, poi serve una build.
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('player-loading')), findsNothing);
      expect(find.byType(LoadingLine), findsNothing);

      // Di nuovo in caricamento ("Riprova"): torna.
      state.value = (testItem(name: 'Dune'), true);
      await tester.pump();
      expect(find.byType(LoadingLine), findsOneWidget);
    });
  });

  group('spinner del buffering', () {
    testWidgets('solo oltre 300 ms; sfuma via', (tester) async {
      final buffering = ValueNotifier(false);
      addTearDown(buffering.dispose);
      await pumpApp(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: buffering,
          builder: (context, value, _) => BufferingSpinner(buffering: value),
        ),
      );
      buffering.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      buffering.value = false;
      await tester.pump();
      await tester.pump(bufferingSpinnerDelay);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'attesa breve: niente spinner');

      buffering.value = true;
      await tester.pump();
      await tester.pump(bufferingSpinnerDelay);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      buffering.value = false;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('errore', () {
    testWidgets('sullo sfondo del titolo: testi e pulsanti', (tester) async {
      var retry = 0;
      var back = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: PlayerErrorLayer(
            item: testItem(name: 'Dune'),
            error: null,
            onRetry: () => retry++,
            onBack: () => back++,
            backLabel: 'Torna indietro',
          ),
        ),
      );
      expect(find.byType(BackdropImage), findsOneWidget);
      expect(find.text('Impossibile riprodurre il video'), findsOneWidget);
      await tester.tap(find.text('Riprova'));
      await tester.tap(find.text('Torna indietro'));
      expect((retry, back), (1, 1));
    });

    testWidgets('senza elemento: niente sfondo', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: PlayerErrorLayer(
            item: null,
            error: null,
            onRetry: () {},
            onBack: () {},
            backLabel: 'Torna indietro',
          ),
        ),
      );
      expect(find.byType(BackdropImage), findsNothing);
      expect(find.text('Riprova'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/player_loading_test.dart`
Expected: FAIL (file `player_loading.dart` inesistente).

- [ ] **Step 3: implementazione.** Crea `lib/features/player/player_loading.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/backdrop_image.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'player_overlay.dart';

/// Periodo della linea oro del caricamento (spec D §10.1).
const loadingLinePeriod = Duration(milliseconds: 1200);

/// Un buffering più breve di così non mostra lo spinner (spec D §10.2).
const bufferingSpinnerDelay = Duration(milliseconds: 300);

/// Sfondo del titolo con un velo scuro (caricamento ed errore). Stesso URL
/// della testata della scheda: l'immagine è già in cache.
class _DimmedBackdrop extends ConsumerWidget {
  const _DimmedBackdrop({super.key, required this.item, required this.dim});

  final JellyfinItem item;

  /// Opacità del velo, 0–1.
  final double dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropImage(
            backdrop: urls.backdrop(item), fallback: urls.poster(item)),
        ColoredBox(color: WfColors.bg.withValues(alpha: dim)),
      ],
    );
  }
}

/// Caricamento del player (spec D §10.1): sfondo del titolo scurito, logo
/// (o titolo) al centro e una linea oro che scorre; in alto a sinistra la
/// freccia per uscire. Nascosto sfuma e poi esce dall'albero (la linea non
/// gira più).
class PlayerLoadingLayer extends ConsumerStatefulWidget {
  const PlayerLoadingLayer({
    super.key,
    required this.item,
    required this.visible,
    required this.onBack,
  });

  /// `null` finché l'elemento non è arrivato: solo il nero e la linea.
  final JellyfinItem? item;
  final bool visible;
  final VoidCallback onBack;

  /// Velo sullo sfondo.
  static const dim = 0.55;

  /// Il logo: al massimo così alto e largo questa parte della finestra.
  static const logoMaxHeight = 160.0;
  static const logoWidthFraction = 0.4;

  /// Senza logo, il titolo: largo al massimo questa parte della finestra.
  static const titleWidthFraction = 0.6;

  /// Spazio tra il logo e la linea.
  static const logoGap = 28.0;

  @override
  ConsumerState<PlayerLoadingLayer> createState() =>
      _PlayerLoadingLayerState();
}

class _PlayerLoadingLayerState extends ConsumerState<PlayerLoadingLayer> {
  /// Sfumato via: lo strato non è più nell'albero.
  bool _gone = false;

  @override
  void didUpdateWidget(PlayerLoadingLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) _gone = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final item = widget.item;
    final logo = item == null ? null : urls.logo(item);
    final width = MediaQuery.sizeOf(context).width;
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        key: const Key('player-loading'),
        opacity: widget.visible ? 1 : 0,
        duration: motion.duration(WfMotion.slow),
        curve: WfMotion.standard,
        onEnd: () {
          if (!widget.visible && mounted) setState(() => _gone = true);
        },
        child: ColoredBox(
          color: WfColors.bg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: WfMotion.fast,
                child: item == null
                    ? const SizedBox.expand()
                    : _DimmedBackdrop(
                        key: ValueKey(item.id),
                        item: item,
                        dim: PlayerLoadingLayer.dim),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: WfMotion.fast,
                      child: item == null
                          ? const SizedBox.shrink()
                          : Padding(
                              key: ValueKey(item.id),
                              padding: const EdgeInsets.only(
                                  bottom: PlayerLoadingLayer.logoGap),
                              child: logo != null
                                  ? SizedBox(
                                      width: width *
                                          PlayerLoadingLayer.logoWidthFraction,
                                      height: PlayerLoadingLayer.logoMaxHeight,
                                      child: WfImage(
                                          image: logo,
                                          fit: BoxFit.contain,
                                          fallbackIcon: null),
                                    )
                                  : ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: width *
                                              PlayerLoadingLayer
                                                  .titleWidthFraction),
                                      child: Text(
                                        cardTitle(item).toUpperCase(),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        style: WfText.display(64),
                                      ),
                                    ),
                            ),
                    ),
                    const LoadingLine(),
                  ],
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                child: PlayerIconButton(
                  icon: const Icon(LucideIcons.arrowLeft),
                  tooltip: l.navBack,
                  onPressed: widget.onBack,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linea oro che scorre: c'è un'attesa (spec D §10.1). Gira anche con le
/// animazioni ridotte, come uno spinner.
class LoadingLine extends StatefulWidget {
  const LoadingLine({super.key});

  static const width = 200.0;
  static const height = 3.0;

  /// Parte oro della linea, rispetto alla sua lunghezza.
  static const segment = 0.35;

  @override
  State<LoadingLine> createState() => _LoadingLineState();
}

class _LoadingLineState extends State<LoadingLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: loadingLinePeriod)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const segment = LoadingLine.width * LoadingLine.segment;
    return SizedBox(
      width: LoadingLine.width,
      height: LoadingLine.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LoadingLine.height),
        child: ColoredBox(
          color: WfColors.cream.withValues(alpha: 0.15),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = WfMotion.standard.transform(_controller.value);
              return Stack(
                children: [
                  Positioned(
                    left: -segment + t * (LoadingLine.width + segment),
                    top: 0,
                    bottom: 0,
                    width: segment,
                    child: const ColoredBox(color: WfColors.gold),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Spinner oro del buffering (spec D §10.2): compare solo se l'attesa dura
/// più di [bufferingSpinnerDelay] e sfuma in entrata e in uscita. Sparito,
/// non è nell'albero.
class BufferingSpinner extends StatefulWidget {
  const BufferingSpinner({super.key, required this.buffering});

  final bool buffering;

  @override
  State<BufferingSpinner> createState() => _BufferingSpinnerState();
}

class _BufferingSpinnerState extends State<BufferingSpinner> {
  Timer? _timer;
  bool _shown = false;

  /// Nell'albero: mostrato o mentre sfuma via.
  bool _present = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(BufferingSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buffering != widget.buffering) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!widget.buffering) {
      _shown = false;
      return;
    }
    _timer = Timer(bufferingSpinnerDelay, () {
      if (mounted) {
        setState(() {
          _shown = true;
          _present = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const SizedBox.shrink();
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: const Key('buffering-spinner'),
        tween: Tween(begin: 0, end: _shown ? 1 : 0),
        duration: WfMotion.fast,
        onEnd: () {
          if (!_shown && mounted) setState(() => _present = false);
        },
        builder: (context, t, child) =>
            Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        child: const Center(
            child: CircularProgressIndicator(color: WfColors.gold)),
      ),
    );
  }
}

/// Errore di riproduzione (spec D §10.3): sullo sfondo del titolo molto
/// scurito (o sul nero) icona, titolo, testo e pulsanti entrano
/// scaglionati.
class PlayerErrorLayer extends StatelessWidget {
  const PlayerErrorLayer({
    super.key,
    required this.item,
    required this.error,
    required this.onRetry,
    required this.onBack,
    required this.backLabel,
  });

  final JellyfinItem? item;
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final String backLabel;

  /// Velo sullo sfondo.
  static const dim = 0.75;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final failure = error;
    final current = item;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (current != null)
          _DimmedBackdrop(item: current, dim: dim)
        else
          const ColoredBox(color: WfColors.bg),
        Center(
          child: StaggerGroup(
            count: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StaggerItem(
                  index: 0,
                  child: Icon(LucideIcons.circleAlert,
                      size: 44, color: WfColors.error),
                ),
                const SizedBox(height: 16),
                StaggerItem(
                  index: 1,
                  child:
                      Text(l.playerErrorTitle, style: WfText.display(34)),
                ),
                const SizedBox(height: 8),
                StaggerItem(
                  index: 2,
                  child: Text(
                    failure == null
                        ? l.errorGeneric
                        : describeError(l, failure),
                    style: const TextStyle(color: WfColors.creamMuted),
                  ),
                ),
                const SizedBox(height: 24),
                StaggerItem(
                  index: 3,
                  child: Wrap(
                    spacing: 12,
                    children: [
                      WfButton.primary(
                          label: l.retry,
                          icon: LucideIcons.rotateCcw,
                          onPressed: onRetry),
                      WfButton.secondary(
                          label: backLabel,
                          icon: LucideIcons.arrowLeft,
                          onPressed: onBack),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/player_loading_test.dart`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/player_loading.dart test/features/player/player_loading_test.dart
git commit -m "feat: add player loading, buffering and error layers"
```

---

### Task 4: primo fotogramma e collegamento degli strati

**Files:**
- Modify: `lib/core/video/video_engine.dart`, `lib/core/video/media_kit_engine.dart`
- Modify: `test/support/playback_fakes.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_screen_test.dart`

- [ ] **Step 1: test che falliscono.** In `test/features/player/player_screen_test.dart`:

1. Aggiungi l'import `import 'package:wonderflix/features/player/player_loading.dart';`.

2. Cambia la firma di `pumpPlayer` in `Future<void> pumpPlayer(WidgetTester tester, {bool settle = true}) async {` e la sua ultima riga `await tester.pumpAndSettle();` in:

```dart
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // Caricamento visibile: la linea gira, niente `pumpAndSettle`.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }
```

3. Dopo il test `'video, titolo, episodio e controlli'` aggiungi:

```dart
  testWidgets('caricamento: sfondo e titolo finché arriva il primo fotogramma',
      (tester) async {
    engine.holdFirstFrame = true;
    await pumpPlayer(tester, settle: false);
    final layer = find.byKey(const Key('player-loading'));
    expect(layer, findsOneWidget);
    expect(find.descendant(of: layer, matching: find.text('BREAKING BAD')),
        findsOneWidget);
    expect(find.descendant(of: layer, matching: find.byTooltip('Indietro')),
        findsOneWidget);
    expect(controlsOpacity(tester), 0, reason: 'controlli nascosti');

    engine.completeFirstFrame();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(layer, findsNothing);
    expect(find.byType(LoadingLine), findsNothing);
    expect(controlsOpacity(tester), 1);
    await unmount(tester);
  });

  testWidgets('caricamento: senza primo fotogramma sfuma dopo 3 s',
      (tester) async {
    engine.holdFirstFrame = true;
    await pumpPlayer(tester, settle: false);
    // Margine: il conto parte da `ready`, raggiunto durante i primi pump.
    await tester.pump(PlayerScreen.firstFrameTimeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-loading')), findsNothing);
    await unmount(tester);
  });

  testWidgets('buffering: lo spinner solo oltre 300 ms', (tester) async {
    await pumpPlayer(tester);
    engine.emitBuffering(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    engine.emitBuffering(false);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await unmount(tester);
  });
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/player_screen_test.dart`
Expected: FAIL (`holdFirstFrame`, `completeFirstFrame`, `firstFrameTimeout` non esistono).

- [ ] **Step 3: il motore.** In `lib/core/video/video_engine.dart` sostituisci

```dart
  /// Superficie su cui viene disegnato il video.
  Widget buildView();
```

con

```dart
  /// Si completa quando il primo fotogramma è disegnato. Vale una volta per
  /// motore: per le aperture successive ("Riprova", ripiego sulla
  /// conversione) è già completato.
  Future<void> get firstFrame;

  /// Superficie su cui viene disegnato il video.
  Widget buildView();
```

In `lib/core/video/media_kit_engine.dart`, prima di `@override\n  Widget buildView() => Video(`, aggiungi:

```dart
  @override
  Future<void> get firstFrame => _video.waitUntilFirstFrameRendered;

```

In `test/support/playback_fakes.dart`, in `FakeVideoEngine`:

- dopo `bool disposed = false;` aggiungi:

```dart

  /// Con `true` il primo fotogramma arriva solo con [completeFirstFrame];
  /// altrimenti alla prima apertura riuscita.
  bool holdFirstFrame = false;
  final _firstFrame = Completer<void>();

  void completeFirstFrame() {
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }

  @override
  Future<void> get firstFrame => _firstFrame.future;
```

- in `open`, dopo `    // Come mpv: il file si apre in pausa.\n    _position = source.start;\n    _setPlaying(false);` aggiungi `    if (!holdFirstFrame) completeFirstFrame();`.

- [ ] **Step 4: collegamento.** In `lib/features/player/player_screen.dart`:

1. Aggiungi l'import `import 'player_loading.dart';` (dopo `import 'player_handover.dart';`).

2. In `PlayerScreen`, dopo `static const closeTimeout = Duration(seconds: 2);` aggiungi:

```dart

  /// Se il motore non segnala il primo fotogramma entro questo tempo da
  /// `ready` (per esempio un video del gruppo aperto in pausa), il
  /// caricamento sfuma comunque.
  static const firstFrameTimeout = Duration(seconds: 3);
```

3. In `_PlayerScreenState`, dopo `final _chrome = PlayerChromeController();` aggiungi:

```dart

  /// Il motore ha disegnato il primo fotogramma (o è passato
  /// [PlayerScreen.firstFrameTimeout] da `ready`): il caricamento sfuma.
  bool _firstFrame = false;
  Timer? _firstFrameTimer;
```

4. In `initState`, dopo `_chrome.addListener(_onChromeChanged);` aggiungi:

```dart
    // Il caricamento resta finché il motore non disegna il primo
    // fotogramma (spec D §10.1).
    unawaited(_controller.engine.firstFrame.then((_) => _onFirstFrame()));
```

5. In `dispose`, dopo `_timelineTimer?.cancel();` aggiungi `_firstFrameTimer?.cancel();`.

6. Dopo il metodo `_onChromeChanged` aggiungi:

```dart

  void _onFirstFrame() {
    _firstFrameTimer?.cancel();
    if (mounted && !_firstFrame) setState(() => _firstFrame = true);
  }
```

7. Nel listener dello stato (`ref.listen(provider.select((s) => s.status), …)`) sostituisci

```dart
        return;
      }
      final driver = _driver;
      if (driver != null) {
```

con

```dart
        return;
      }
      if (!_firstFrame) {
        _firstFrameTimer?.cancel();
        _firstFrameTimer =
            Timer(PlayerScreen.firstFrameTimeout, _onFirstFrame);
      }
      final driver = _driver;
      if (driver != null) {
```

8. Sostituisci

```dart
    final loading = view.status == PlayerStatus.loading ||
        (view.status == PlayerStatus.ready && view.buffering);
```

con

```dart
    // Caricamento: finché il file non è pronto e il motore non ha disegnato
    // il primo fotogramma (spec D §10.1).
    final loading = view.status == PlayerStatus.loading ||
        (view.status == PlayerStatus.ready && !_firstFrame);
```

9. Sostituisci

```dart
                if (loading)
                  const Center(
                      child: CircularProgressIndicator(color: WfColors.gold)),
```

con

```dart
                if (view.status == PlayerStatus.ready && !loading)
                  BufferingSpinner(buffering: view.buffering),
```

10. Sostituisci

```dart
                if (view.status == PlayerStatus.error)
                  _PlayerError(
                    error: view.error,
```

con

```dart
                if (view.status == PlayerStatus.error)
                  PlayerErrorLayer(
                    item: view.item,
                    error: view.error,
```

11. Nel blocco dei controlli sostituisci

```dart
                      ignoring: !_chrome.controlsVisible,
                      child: PlayerOverlay(
                        visible: _chrome.controlsVisible,
```

con

```dart
                      ignoring: !_chrome.controlsVisible || loading,
                      child: PlayerOverlay(
                        // Durante il caricamento la freccia per uscire sta
                        // nello strato del caricamento.
                        visible: _chrome.controlsVisible && !loading,
```

12. Subito dopo la fine del blocco dei controlli (la riga `                  ),` che chiude `ExcludeFocus` del `PlayerOverlay`, prima di `                if (view.status == PlayerStatus.ready) ...[`) aggiungi:

```dart
                // Caricamento sopra il film e i controlli; sfumato via esce
                // dall'albero.
                if (view.status != PlayerStatus.error)
                  Positioned.fill(
                    child: ExcludeFocus(
                      child: PlayerLoadingLayer(
                        item: view.item,
                        visible: loading,
                        onBack: _exit,
                      ),
                    ),
                  ),
```

13. Togli la classe `_PlayerError` (in fondo al file) e gli import che `flutter analyze` segnala come non più usati (probabilmente `../../app/error_text.dart` e, se nient'altro usa `WfColors`/`WfText`, `../../app/theme.dart`).

- [ ] **Step 5: verifica.**

Run: `flutter test test/features/player/ test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 6: commit.**

```bash
git add lib/core/video/video_engine.dart lib/core/video/media_kit_engine.dart test/support/playback_fakes.dart lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
git commit -m "feat: show the loading layer until the first video frame"
```

---

### Task 5: `PauseScreen`

**Files:**
- Create: `lib/features/player/pause_screen.dart`
- Test: `test/features/player/pause_screen_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/features/player/pause_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/pause_screen.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  test('anno, durata e al massimo due generi; si omette ciò che manca', () {
    expect(
        pauseScreenMeta(testItem(
            year: 2024,
            runtimeMinutes: 166,
            genres: ['Fantascienza', 'Avventura', 'Dramma'])),
        '2024 · 2h 46m · Fantascienza · Avventura');
    expect(pauseScreenMeta(testItem(year: null, runtimeMinutes: null)), '');
  });

  Future<ValueNotifier<bool>> pumpPause(WidgetTester tester, JellyfinItem item,
      {bool visible = false, MotionLevel motion = MotionLevel.reduced}) async {
    final shown = ValueNotifier(visible);
    addTearDown(shown.dispose);
    await pumpApp(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, value, _) => PauseScreen(item: item, visible: value),
      ),
      motion: motion,
    );
    return shown;
  }

  testWidgets('nascosta non è nell\'albero; mostrata, tutti i dati',
      (tester) async {
    final shown = await pumpPause(
        tester,
        testItem(
          id: 'e4',
          name: 'Pilot',
          kind: ItemKind.episode,
          seriesName: 'Breaking Bad',
          index: 4,
          seasonIndex: 1,
          year: 2008,
          runtimeMinutes: 58,
          genres: ['Dramma'],
          overview: 'Un professore scopre di essere malato.',
        ));
    expect(find.byKey(const Key('pause-screen')), findsNothing);

    shown.value = true;
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsOneWidget);
    expect(find.text('BREAKING BAD'), findsOneWidget);
    expect(find.text('S1:E4 · Pilot'), findsOneWidget);
    expect(find.text('2008 · 58m · Dramma'), findsOneWidget);
    expect(find.text('Un professore scopre di essere malato.'), findsOneWidget);
    expect(find.text('In pausa'), findsOneWidget);

    shown.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pause-screen')), findsNothing);
  });

  testWidgets('animazioni complete: il testo sale entrando', (tester) async {
    final shown = await pumpPause(tester, testItem(name: 'Dune'),
        motion: MotionLevel.full);
    shown.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    double rise() => tester
        .widget<Transform>(find
            .ancestor(
                of: find.text('STAI GUARDANDO'),
                matching: find.byType(Transform))
            .first)
        .transform
        .getTranslation()
        .y;
    expect(rise(), greaterThan(0));
    await tester.pumpAndSettle();
    expect(rise(), 0);
  });
}
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/pause_screen_test.dart`
Expected: FAIL (file `pause_screen.dart` inesistente).

- [ ] **Step 3: implementazione.** Crea `lib/features/player/pause_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';

/// "Anno · durata · generi" della schermata di pausa: al massimo due
/// generi, si omette ciò che manca.
String pauseScreenMeta(JellyfinItem item) {
  final runtime = item.runtime;
  return [
    if (item.productionYear != null) '${item.productionYear}',
    if (runtime != null) formatRuntime(runtime),
    ...item.genres.take(2),
  ].join(' · ');
}

/// Schermata "Stai guardando" sopra il fermo immagine (spec D §11): entra
/// sfumando con il testo che sale, esce in fretta. Non prende clic (un clic
/// sul film lo riprende). Nascosta, non è nell'albero.
class PauseScreen extends StatefulWidget {
  const PauseScreen({super.key, required this.item, required this.visible});

  final JellyfinItem item;
  final bool visible;

  /// Di quanto sale il testo entrando.
  static const textRise = 16.0;

  /// Larghezza massima del testo a sinistra.
  static const textWidth = 560.0;

  /// Margine del testo dal bordo sinistro.
  static const textInset = 64.0;

  @override
  State<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends State<PauseScreen> {
  /// Nell'albero: mostrata o mentre sfuma via.
  late bool _present = widget.visible;

  @override
  void didUpdateWidget(PauseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) _present = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const SizedBox.shrink();
    final motion = WfMotion.of(context);
    final visible = widget.visible;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: const Key('pause-screen'),
        tween: Tween(begin: 0, end: visible ? 1 : 0),
        duration: visible ? motion.duration(WfMotion.slow) : WfMotion.fast,
        curve: visible ? WfMotion.emphasized : WfMotion.accelerate,
        onEnd: () {
          if (!widget.visible && mounted) setState(() => _present = false);
        },
        builder: (context, t, text) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _PauseShade(),
              Positioned(
                left: PauseScreen.textInset,
                right: PauseScreen.textInset,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(
                        0,
                        motion.isReduced
                            ? 0
                            : (1 - t) * PauseScreen.textRise),
                    child: text,
                  ),
                ),
              ),
              const Positioned(right: 32, bottom: 32, child: _PausedBadge()),
            ],
          ),
        ),
        child: _PauseText(item: widget.item),
      ),
    );
  }
}

/// Sfumatura nera da sinistra sopra il fermo immagine.
class _PauseShade extends StatelessWidget {
  const _PauseShade();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              WfColors.bg.withValues(alpha: 0.88),
              WfColors.bg.withValues(alpha: 0.6),
              WfColors.bg.withValues(alpha: 0.15),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
      );
}

class _PausedBadge extends StatelessWidget {
  const _PausedBadge();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.pause, size: 18, color: WfColors.gold),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context).playerFeedbackPaused,
              style: const TextStyle(color: WfColors.creamMuted)),
        ],
      );
}

/// "STAI GUARDANDO", logo (o titolo), episodio, dati e trama.
class _PauseText extends ConsumerWidget {
  const _PauseText({required this.item});

  final JellyfinItem item;

  /// Spazio per il logo.
  static const logoHeight = 120.0;
  static const logoWidth = 420.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final logo = ref.watch(imageUrlsProvider).logo(item);
    final episode = item.kind == ItemKind.episode ? cardSubtitle(item) : null;
    final meta = pauseScreenMeta(item);
    final overview = item.overview;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: PauseScreen.textWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.playerWatching.toUpperCase(),
            style: const TextStyle(
                color: WfColors.gold,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          if (logo != null)
            SizedBox(
              height: logoHeight,
              width: logoWidth,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: WfImage(
                    image: logo, fit: BoxFit.contain, fallbackIcon: null),
              ),
            )
          else
            Text(cardTitle(item).toUpperCase(),
                maxLines: 2, style: WfText.display(64)),
          if (episode != null) ...[
            const SizedBox(height: 12),
            Text(episode,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(meta, style: const TextStyle(color: WfColors.creamMuted)),
          ],
          if (overview != null) ...[
            const SizedBox(height: 16),
            Text(overview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.45)),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/pause_screen_test.dart`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/pause_screen.dart test/features/player/pause_screen_test.dart
git commit -m "feat: add the player pause screen"
```

---

### Task 6: la pausa nel player

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_screen_test.dart`, `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono.** In `test/features/player/player_screen_test.dart`, dopo il test `'i tasti non mostrano i controlli'`, aggiungi:

```dart
  testWidgets('pausa: dopo 8 s senza mouse né tasti, "Stai guardando"',
      (tester) async {
    library.itemsById['e4'] = testItem(
      id: 'e4',
      name: 'Pilot',
      kind: ItemKind.episode,
      seriesName: 'Breaking Bad',
      seriesId: 's1',
      index: 4,
      seasonIndex: 1,
      overview: 'Un professore scopre di essere malato.',
    );
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(PlayerChromeController.pauseScreenDelay -
        const Duration(seconds: 1));
    expect(find.text('STAI GUARDANDO'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsOneWidget);
    expect(find.text('Un professore scopre di essere malato.'), findsOneWidget);
    expect(controlsOpacity(tester), 0);

    // Un tasto la chiude senza mostrare i controlli.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    expect(controlsOpacity(tester), 0);

    // Di nuovo dopo 8 s; il mouse la chiude e riporta i controlli.
    await tester.pump(PlayerChromeController.pauseScreenDelay);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsOneWidget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(700, 400));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(720, 420));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    expect(controlsOpacity(tester), 1);
    await unmount(tester);
  });

  testWidgets('pausa: con il pannello aperto non compare', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    await unmount(tester);
  });
```

In `test/features/watch_party/party_player_test.dart`, dopo il test `'attesa del gruppo: dopo 1 s, con "Riprendi senza aspettare"'`, aggiungi:

```dart
  testWidgets('pausa del gruppo: "Stai guardando", ma non mentre aspetta',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(find.text(l.playerWatching.toUpperCase()), findsNothing);

    emit(const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
    await tester.pump();
    await tester.pump();
    await tester.pump(PlayerChromeController.pauseScreenDelay);
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatching.toUpperCase()), findsOneWidget);
    await finish(tester);
  });
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/player_screen_test.dart test/features/watch_party/party_player_test.dart`
Expected: FAIL (nessuna schermata di pausa nel player).

- [ ] **Step 3: collegamento.** In `lib/features/player/player_screen.dart`:

1. Aggiungi l'import `import 'pause_screen.dart';` (prima di `import 'player_commands.dart';`).

2. Dopo il metodo `_onFirstFrame` aggiungi:

```dart

  /// Dice al controller dell'interfaccia se si sta guardando e se la
  /// schermata di pausa è ammessa adesso (spec D §11.1): file pronto e
  /// fermo, niente buffering, video non finito, elemento arrivato, gruppo
  /// non in attesa.
  void _syncPlayback() {
    final view = ref.read(playerControllerProvider(widget.args));
    final party = _inParty ? ref.read(watchPartySessionProvider) : null;
    final groupWaiting = party != null &&
        party.inGroup &&
        party.groupState == GroupState.waiting;
    _chrome.setPlayback(
      playing: view.playing,
      canShowPauseScreen: view.status == PlayerStatus.ready &&
          !view.playing &&
          !view.buffering &&
          !view.finished &&
          view.item != null &&
          !groupWaiting,
    );
  }
```

3. In `_onKey` sostituisci

```dart
    if (command == null) return KeyEventResult.ignored;
    _run(command);
```

con

```dart
    if (command == null) return KeyEventResult.ignored;
    _chrome.keyActivity();
    _run(command);
```

4. In `build` sostituisci `_chrome.setPlayback(playing: playing);` con `_syncPlayback();` e, subito dopo la chiusura di quel listener (`    });`), aggiungi:

```dart
    ref.listen(
        provider.select(
            (s) => (s.status, s.buffering, s.finished, s.item != null)),
        (_, _) => _syncPlayback());
```

5. All'inizio del blocco `if (_inParty) {` che contiene i listener del gruppo (quello con `s.inGroup && s.hasNext`), aggiungi come primo listener:

```dart
      ref.listen(
          watchPartySessionProvider.select(
              (s) => s.inGroup && s.groupState == GroupState.waiting),
          (_, _) => _syncPlayback());
```

6. Subito dopo il blocco di `PartyWaitingOverlay` (che finisce con le parentesi di `Positioned.fill(... ExcludeFocus(... PartyWaitingOverlay(...))))`) aggiungi:

```dart
                // "Stai guardando" sopra il fermo immagine, sotto i
                // controlli (spec D §11).
                if (view.status == PlayerStatus.ready && view.item != null)
                  Positioned.fill(
                    child: ExcludeFocus(
                      child: PauseScreen(
                          item: view.item!, visible: _chrome.pauseScreen),
                    ),
                  ),
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/ test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/player_screen.dart test/features/player/player_screen_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: show the pause screen in the player"
```

---

### Task 7: `PlayerController.setSubtitleScale`

**Files:**
- Modify: `lib/features/player/player_controller.dart`
- Test: `test/features/player/player_controller_test.dart`

- [ ] **Step 1: test che fallisce.** In `test/features/player/player_controller_test.dart`, in fondo a `main()`, aggiungi:

```dart
  test('dimensione dei sottotitoli dal pannello: subito e salvata', () async {
    final controller = await start();
    await controller.setSubtitleScale(1.25);
    expect(engine.subtitleScales.last, 1.25);
    expect(container.read(playerSettingsProvider).subtitleScale, 1.25);

    // "Riprova" riapre con la dimensione nuova.
    await controller.retry();
    await pumpEventQueue();
    expect(engine.subtitleScales.last, 1.25);
  });
```

- [ ] **Step 2: verifica che fallisca.**

Run: `flutter test test/features/player/player_controller_test.dart`
Expected: FAIL (`setSubtitleScale` non esiste).

- [ ] **Step 3: implementazione.** In `lib/features/player/player_controller.dart`, subito dopo il metodo `shiftSubtitleDelay`, aggiungi:

```dart

  /// Dimensione dei sottotitoli scelta nel pannello del player: si applica
  /// subito e diventa la preferenza delle Impostazioni (spec D §14).
  Future<void> setSubtitleScale(double scale) async {
    _settings = _settings.copyWith(subtitleScale: scale);
    final settings = ref.read(playerSettingsProvider.notifier);
    final current = ref.read(playerSettingsProvider);
    await Future.wait([
      _engine.setSubtitleScale(scale),
      settings.update(current.copyWith(subtitleScale: scale)),
    ]);
  }
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/player_controller_test.dart`
Expected: PASS. Se `retry()` nel test non riapre (per esempio perché il controller non era in errore), sostituisci quella parte con una verifica equivalente su `_settings` attraverso un'apertura successiva e segnalalo. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/player_controller.dart test/features/player/player_controller_test.dart
git commit -m "feat: set the subtitle size from the player"
```

---

### Task 8: pannello laterale

**Files:**
- Modify (riscrittura): `lib/features/player/tracks_panel.dart`
- Test (riscrittura): `test/features/player/tracks_panel_test.dart`

- [ ] **Step 1: test che falliscono.** Sostituisci tutto `test/features/player/tracks_panel_test.dart` con:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/tracks_panel.dart';

import '../../support/pump_app.dart';

void main() {
  test('formatSubtitleDelay', () {
    expect(formatSubtitleDelay(Duration.zero, ','), '0,0 s');
    expect(formatSubtitleDelay(const Duration(milliseconds: 300), ','),
        '+0,3 s');
    expect(formatSubtitleDelay(const Duration(milliseconds: -1200), '.'),
        '-1.2 s');
  });

  TracksPanel panel({
    ValueChanged<int>? onAudio,
    ValueChanged<int?>? onSubtitle,
    ValueChanged<Duration>? onDelayStep,
    ValueChanged<double>? onSubtitleScale,
    VoidCallback? onClose,
  }) =>
      TracksPanel(
        audio: const [
          MediaStreamInfo(
              index: 1,
              kind: StreamKind.audio,
              displayTitle: 'Italiano - E-AC3 5.1'),
          MediaStreamInfo(
              index: 2, kind: StreamKind.audio, displayTitle: 'English - AAC'),
        ],
        subtitles: const [
          MediaStreamInfo(
              index: 3,
              kind: StreamKind.subtitle,
              displayTitle: 'Italiano - ASS'),
          MediaStreamInfo(index: 7, kind: StreamKind.subtitle),
        ],
        audioIndex: 1,
        subtitleIndex: null,
        subtitleDelay: const Duration(milliseconds: 300),
        subtitleScale: 1.0,
        onAudio: onAudio ?? (_) {},
        onSubtitle: onSubtitle ?? (_) {},
        onDelayStep: onDelayStep ?? (_) {},
        onSubtitleScale: onSubtitleScale ?? (_) {},
        onClose: onClose ?? () {},
      );

  testWidgets('tracce, selezione, ritardo, dimensione e chiusura',
      (tester) async {
    int? audioPicked;
    int? subtitlePicked = -99;
    Duration? step;
    double? scale;
    var closed = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: TracksPanel.width,
            child: panel(
              onAudio: (i) => audioPicked = i,
              onSubtitle: (i) => subtitlePicked = i,
              onDelayStep: (s) => step = s,
              onSubtitleScale: (s) => scale = s,
              onClose: () => closed++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Audio e sottotitoli'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Sottotitoli'), findsOneWidget);
    expect(find.text('Traccia 7'), findsOneWidget, reason: 'senza nome');
    expect(find.text('+0,3 s'), findsOneWidget);
    // Selezionati: audio 1 e "Nessuno".
    expect(find.byIcon(LucideIcons.check), findsNWidgets(2));
    expect(find.text('Dimensione'), findsOneWidget);
    for (final label in ['Piccoli', 'Normali', 'Grandi', 'Molto grandi']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('English - AAC'));
    expect(audioPicked, 2);
    await tester.tap(find.text('Italiano - ASS'));
    expect(subtitlePicked, 3);
    await tester.tap(find.text('Nessuno'));
    expect(subtitlePicked, isNull);
    await tester.tap(find.byTooltip('Sottotitoli prima (G)'));
    expect(step, const Duration(milliseconds: -100));
    await tester.tap(find.byTooltip('Sottotitoli dopo (H)'));
    expect(step, const Duration(milliseconds: 100));
    await tester.tap(find.text('Grandi'));
    expect(scale, 1.25);
    await tester.tap(find.byTooltip('Chiudi'));
    expect(closed, 1);
  });

  Future<ValueNotifier<bool>> pumpHost(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) async {
    final open = ValueNotifier(false);
    addTearDown(open.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (context, value, _) =>
              TracksPanelHost(open: value, panel: panel()),
        ),
      ),
      motion: motion,
    );
    return open;
  }

  testWidgets('host: entra scorrendo da destra, esce e lascia l\'albero',
      (tester) async {
    final open = await pumpHost(tester, motion: MotionLevel.full);
    expect(find.byType(TracksPanel), findsNothing);

    open.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final slide = tester.widget<FractionalTranslation>(find.ancestor(
        of: find.byType(TracksPanel),
        matching: find.byType(FractionalTranslation)));
    expect(slide.translation.dx, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FractionalTranslation>(find.ancestor(
                of: find.byType(TracksPanel),
                matching: find.byType(FractionalTranslation)))
            .translation
            .dx,
        0);
    // Largo 360 px (al massimo il 35% della finestra).
    expect(tester.getSize(find.byType(TracksPanel)).width, TracksPanel.width);

    open.value = false;
    await tester.pump();
    expect(find.byType(TracksPanel), findsOneWidget, reason: 'sta uscendo');
    await tester.pumpAndSettle();
    expect(find.byType(TracksPanel), findsNothing);
  });

  testWidgets('host: animazioni ridotte, solo dissolvenza', (tester) async {
    final open = await pumpHost(tester);
    open.value = true;
    await tester.pumpAndSettle();
    expect(
        find.ancestor(
            of: find.byType(TracksPanel),
            matching: find.byType(FractionalTranslation)),
        findsNothing);
    expect(find.byType(TracksPanel), findsOneWidget);
  });
}
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/tracks_panel_test.dart`
Expected: FAIL (`subtitleScale`, `onSubtitleScale`, `onClose`, `TracksPanelHost` non esistono).

- [ ] **Step 3: implementazione.** Sostituisci tutto `lib/features/player/tracks_panel.dart` con:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/staggered_entrance.dart';
import 'player_commands.dart';
import 'player_settings.dart';

/// Nome di una traccia nei menu: quello preparato dal server, se c'è.
String trackLabel(AppLocalizations l, MediaStreamInfo stream) =>
    stream.displayTitle ??
    stream.title ??
    stream.language ??
    l.playerTrack(stream.index);

/// "+0,3 s", "0,0 s", "-1,2 s".
String formatSubtitleDelay(Duration delay, String decimalSeparator) {
  final tenths = (delay.inMilliseconds / 100).round();
  final sign = tenths > 0 ? '+' : (tenths < 0 ? '-' : '');
  final value = tenths.abs();
  return '$sign${value ~/ 10}$decimalSeparator${value % 10} s';
}

/// Pannello "Audio e sottotitoli" (spec D §14): tracce audio, sottotitoli,
/// ritardo e dimensione, in colonna; le voci entrano scaglionate.
class TracksPanel extends StatelessWidget {
  const TracksPanel({
    super.key,
    required this.audio,
    required this.subtitles,
    required this.audioIndex,
    required this.subtitleIndex,
    required this.subtitleDelay,
    required this.subtitleScale,
    required this.onAudio,
    required this.onSubtitle,
    required this.onDelayStep,
    required this.onSubtitleScale,
    required this.onClose,
  });

  final List<MediaStreamInfo> audio;
  final List<MediaStreamInfo> subtitles;
  final int? audioIndex;
  final int? subtitleIndex;
  final Duration subtitleDelay;

  /// Uno di `subtitleScaleOptions`.
  final double subtitleScale;
  final ValueChanged<int> onAudio;

  /// `null` = nessun sottotitolo.
  final ValueChanged<int?> onSubtitle;
  final ValueChanged<Duration> onDelayStep;
  final ValueChanged<double> onSubtitleScale;
  final VoidCallback onClose;

  /// Larghezza del pannello, e la parte della finestra che può occupare al
  /// massimo.
  static const width = 360.0;
  static const maxWidthFraction = 0.35;

  /// Distanza tra l'entrata di una voce e la successiva.
  static const itemStagger = Duration(milliseconds: 40);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(l.playerAudioAndSubtitles, style: WfText.display(24)),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x),
            tooltip: l.playerClosePanel,
            color: WfColors.cream,
            onPressed: onClose,
          ),
        ],
      ),
      const SizedBox(height: 12),
      _SectionTitle(l.playerAudio),
      for (final stream in audio)
        _TrackTile(
          label: trackLabel(l, stream),
          selected: stream.index == audioIndex,
          onTap: () => onAudio(stream.index),
        ),
      const SizedBox(height: 16),
      _SectionTitle(l.playerSubtitles),
      _TrackTile(
        label: l.playerSubtitlesOff,
        selected: subtitleIndex == null,
        onTap: () => onSubtitle(null),
      ),
      for (final stream in subtitles)
        _TrackTile(
          label: trackLabel(l, stream),
          selected: stream.index == subtitleIndex,
          onTap: () => onSubtitle(stream.index),
        ),
      const SizedBox(height: 12),
      _DelayRow(delay: subtitleDelay, onDelayStep: onDelayStep),
      const SizedBox(height: 16),
      Text(l.playerSubtitleSize,
          style: const TextStyle(color: WfColors.creamMuted)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final scale in subtitleScaleOptions)
            _ScaleChip(
              key: ValueKey('subtitle-scale-$scale'),
              label: subtitleScaleLabel(l, scale),
              selected: scale == subtitleScale,
              onTap: () => onSubtitleScale(scale),
            ),
        ],
      ),
    ];
    return Material(
      color: WfColors.surface.withValues(alpha: 0.94),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: WfColors.border)),
        ),
        child: StaggerGroup(
          count: items.length,
          stagger: itemStagger,
          itemDuration: WfMotion.medium,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (var i = 0; i < items.length; i++)
                StaggerItem(index: i, child: items[i]),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title, style: WfText.display(20, color: WfColors.gold)),
      );
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: selected
                    ? const _PopIn(
                        child: Icon(LucideIcons.check,
                            size: 16, color: WfColors.gold))
                    : null,
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? WfColors.cream : WfColors.creamMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// La spunta compare con un piccolo rimbalzo (con le animazioni ridotte
/// solo sfumando).
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: WfMotion.fast,
      curve: reduced ? WfMotion.standard : WfMotion.bounce,
      builder: (context, t, child) => reduced
          ? Opacity(opacity: t.clamp(0.0, 1.0), child: child)
          : Transform.scale(scale: t, child: child),
      child: child,
    );
  }
}

class _DelayRow extends StatelessWidget {
  const _DelayRow({required this.delay, required this.onDelayStep});

  final Duration delay;
  final ValueChanged<Duration> onDelayStep;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(l.playerSubtitleDelay,
              style: const TextStyle(color: WfColors.creamMuted)),
        ),
        IconButton(
          icon: const Icon(LucideIcons.minus, size: 18),
          tooltip: l.playerSubtitlesEarlier,
          onPressed: () => onDelayStep(-subtitleDelayStep),
        ),
        SizedBox(
          width: 64,
          child: Text(
            formatSubtitleDelay(delay, l.decimalSeparator),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.plus, size: 18),
          tooltip: l.playerSubtitlesLater,
          onPressed: () => onDelayStep(subtitleDelayStep),
        ),
      ],
    );
  }
}

/// Una delle dimensioni dei sottotitoli: bordo e testo oro se scelta.
class _ScaleChip extends StatelessWidget {
  const _ScaleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: WfMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: selected ? WfColors.gold : WfColors.border),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? WfColors.gold : WfColors.creamMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
}

/// Il pannello a destra, a tutta altezza, con un velo sul film verso di lui
/// (spec D §14): entra scorrendo (`medium`), esce in `fast`; con le
/// animazioni ridotte solo dissolvenza. Chiuso, non è nell'albero (e le
/// voci rientrano scaglionate alla prossima apertura).
class TracksPanelHost extends StatefulWidget {
  const TracksPanelHost({super.key, required this.open, required this.panel});

  final bool open;
  final Widget panel;

  @override
  State<TracksPanelHost> createState() => _TracksPanelHostState();
}

class _TracksPanelHostState extends State<TracksPanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WfMotion.medium,
    reverseDuration: WfMotion.fast,
    value: widget.open ? 1 : 0,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: WfMotion.emphasized,
    reverseCurve: WfMotion.accelerate,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = WfMotion.of(context).duration(WfMotion.medium);
  }

  @override
  void didUpdateWidget(TracksPanelHost oldWidget) {
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    final width = math.min(TracksPanel.width,
        MediaQuery.sizeOf(context).width * TracksPanel.maxWidthFraction);
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
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/tracks_panel_test.dart`
Expected: PASS. `player_screen.dart` non compila ancora con il nuovo costruttore: il Task 9 lo collega. Per non lasciare l'albero rotto, **non committare** prima del Task 9: passa direttamente al Task 9 e committa insieme (lo dice il Task 9).

---

### Task 9: il pannello nel player

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_screen_test.dart`

- [ ] **Step 1: test.** In `test/features/player/player_screen_test.dart`, nel test `'pannello audio e sottotitoli; Esc lo chiude'`, sostituisci

```dart
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('English - AAC Stereo'), findsNothing);
```

con

```dart
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle(); // il pannello esce scorrendo
    expect(find.text('English - AAC Stereo'), findsNothing);
```

e dopo quel test aggiungi:

```dart
  testWidgets('pannello: dimensione dei sottotitoli subito e salvata; × chiude',
      (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grandi'));
    await tester.pump();
    expect(engine.subtitleScales.last, 1.25);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    expect(container.read(playerSettingsProvider).subtitleScale, 1.25);

    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.text('Grandi'), findsNothing);
    await unmount(tester);
  });

  testWidgets('pannello: un clic sul film lo chiude', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(300, 450));
    // Il film ha anche il doppio clic: il clic singolo vale dopo 300 ms.
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('Dimensione'), findsNothing);
    expect(engine.playing, isTrue, reason: 'il clic chiude, non mette in pausa');
    await unmount(tester);
  });
```

- [ ] **Step 2: collegamento.** In `lib/features/player/player_screen.dart` sostituisci il blocco

```dart
                if (_chrome.panelOpen && view.plan != null)
                  Positioned(
                    right: 24,
                    bottom: 120,
                    child: ExcludeFocus(
                      child: TracksPanel(
                        audio: view.audioStreams,
                        subtitles: view.subtitleStreams,
                        audioIndex: view.audioIndex,
                        subtitleIndex: view.subtitleIndex,
                        subtitleDelay: view.subtitleDelay,
                        onAudio: (index) =>
                            unawaited(controller.selectAudio(index)),
                        onSubtitle: (index) =>
                            unawaited(controller.selectSubtitle(index)),
                        onDelayStep: (step) =>
                            unawaited(controller.shiftSubtitleDelay(step)),
                      ),
                    ),
                  ),
```

con

```dart
                // Pannello "Audio e sottotitoli": scorre da destra, a tutta
                // altezza sopra i controlli (spec D §14).
                Positioned.fill(
                  child: ExcludeFocus(
                    child: TracksPanelHost(
                      open: _chrome.panelOpen && view.plan != null,
                      panel: TracksPanel(
                        audio: view.audioStreams,
                        subtitles: view.subtitleStreams,
                        audioIndex: view.audioIndex,
                        subtitleIndex: view.subtitleIndex,
                        subtitleDelay: view.subtitleDelay,
                        subtitleScale: settings.subtitleScale,
                        onAudio: (index) =>
                            unawaited(controller.selectAudio(index)),
                        onSubtitle: (index) =>
                            unawaited(controller.selectSubtitle(index)),
                        onDelayStep: (step) =>
                            unawaited(controller.shiftSubtitleDelay(step)),
                        onSubtitleScale: (scale) =>
                            unawaited(controller.setSubtitleScale(scale)),
                        onClose: _chrome.closePanel,
                      ),
                    ),
                  ),
                ),
```

- [ ] **Step 3: verifica.**

Run: `flutter test test/features/player/ test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 4: commit (Task 8 e 9 insieme).**

```bash
git add lib/features/player/tracks_panel.dart test/features/player/tracks_panel_test.dart lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
git commit -m "feat: slide in the audio and subtitles panel with subtitle size"
```

---

### Task 10: spec e verifica finale

**Files:**
- Modify: `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md`

- [ ] **Step 1: spec.** Nello spec:
  - §10.1, dopo il punto "Visibile finché lo stato è `loading`…", aggiungi: "- Se il motore non segnala il primo fotogramma entro 3 s da `ready` (`PlayerScreen.firstFrameTimeout`; per esempio un video del gruppo aperto in pausa), il caricamento sfuma comunque.";
  - §14, nel punto **Chiusura**, sostituisci "×, clic sul film, Esc, di nuovo l'icona dei sottotitoli." con "×, clic sul film o Esc (il pannello, sopra i controlli, copre l'icona dei sottotitoli).";
  - §14, nel punto **Dimensione**, aggiungi alla fine: "Quattro pillole selezionabili (non il selettore delle Impostazioni), con le stesse etichette (`subtitleScaleLabel`).".

```bash
git add docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md
git commit -m "docs: align Spec D loading and panel sections with plan 8b"
```

- [ ] **Step 2: analisi e test.**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: tutto verde (971 di partenza più quelli nuovi del piano).

- [ ] **Step 3: nessun residuo.**

Run: `grep -rn "_PlayerError\|CircularProgressIndicator(color: WfColors.gold)),\|setPlaying(" lib/features/player`
Expected: nessun risultato (lo spinner vive solo in `player_loading.dart`, dentro `BufferingSpinner`: `const Center(` + `child: CircularProgressIndicator(color: WfColors.gold))`, che questo grep non trova).

Run: `git log --format=%B main..HEAD | grep -ci "co-authored"`
Expected: `0`.

- [ ] **Step 4: build di debug.**

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
flutter build windows --debug --dart-define-from-file=config/wonderflix.json
```

Expected: build riuscita. Poi `git checkout -- windows/flutter/` e `git status --short` vuoto.
