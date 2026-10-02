# WonderFlix — Piano 11: barra di avanzamento e chiusura col player aperto

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** correggere l'issue #9 (la barra di avanzamento sulle card resta grigia, senza la parte oro) e l'issue #8 (chiudendo l'app col player aperto il video diventa nero e la finestra resta ferma ~300 ms prima di chiudersi).

**Cause verificate (2026-10-02):**
1. **#9** — In `ProgressStrip` (`lib/ui/poster_card.dart`) il `Container` con `alignment` passa al figlio vincoli larghi (altezza 0–3). Il `FractionallySizedBox` fissa solo la larghezza e lascia passare l'altezza 0–3; il `ColoredBox` senza figlio prende la misura minima, quindi **altezza 0**. Misurato con una prova: con `progress: 0.5` su 200 px la parte oro è `Size(100.0, 0.0)`. Il difetto c'è dal primo commit della barra (`dc2bb81`); il test esistente controlla solo che la barra ci sia. La stessa barra è usata da `PosterCard`, `LandscapeCard`, anteprima della card e lista episodi.
2. **#8** — `PlayerScreen._onWindowClose` (`lib/features/player/player_screen.dart`) fa tutto il lavoro di uscita **a finestra visibile** e solo alla fine chiama `destroy()`: `PlayerController.close()` manda la fine della sessione al server, poi spegne il motore (qui il video diventa nero), poi rilegge i dati utente; in parallelo escono dal party e il volume si scrive. Tutto entro `PlayerScreen.closeTimeout` (2 s).

**Decisioni prese con l'utente (2026-10-02):**
1. Solo piano, niente spec separato (cause e correzioni chiare).
2. #8: la finestra si **nasconde subito**, il lavoro di uscita resta uguale (posizione esatta salvata sul server, uscita dal party, volume) ma non si vede più; poi `destroy()` come oggi.
3. Dopo la prova: merge, push, **release 0.5.1 non obbligatoria**; commento e chiusura delle issue #8 e #9 solo con l'ok dell'utente.

**Architecture:**
- `ProgressStrip`: la parte oro prende tutta l'altezza della barra (`heightFactor: 1`), come già fanno `play-now-fill` (`player_extras.dart`) e `skip-line` (`skip_button.dart`).
- `PlayerWindow` guadagna `hide()` (`windowManager.hide()` nella versione reale). `PlayerScreen._onWindowClose` la chiama per prima; se fallisce la chiusura va avanti come prima.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, window_manager 0.5.2.

**Worktree:** `.claude/worktrees/piano-11`, branch `fix/piano-11`. **Base:** `main` = `9330058` (1251 test Flutter).

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves`, ecc.) seguite dal numero: solo il riferimento `(#8)`/`(#9)` in fondo all'oggetto, come indicato.
- **Processi:** mai terminare processi per nome dell'eseguibile (`taskkill /IM …`, `pkill`, `killall`). Se un tuo comando resta appeso, ferma solo quello (per PID) oppure segnalalo.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-11`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde (a inizio piano: 1251 test). Nessuna stringa nuova: gli ARB non si toccano.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione e fine riga:** niente `dart format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`).
- **Commenti in italiano, codice in inglese**, come nel resto del codice.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **Vincoli in `ProgressStrip`:** `Container(height: 3, alignment: …)` = `ConstrainedBox` stretto in altezza + `Align`; `Align` allenta i vincoli del figlio (0–larghezza × 0–3). `FractionallySizedBox` senza `heightFactor` passa l'altezza così com'è (0–3). `ColoredBox` senza figlio misura `constraints.smallest`. Con `heightFactor: 1` l'altezza diventa 3 × 1 = 3.
- **Il puntino del carosello** (`hero-dot-fill` in `hero_carousel.dart`) non ha il difetto: l'`AnimatedContainer` con `width`/`height` e senza `alignment` passa vincoli stretti. Non va toccato.
- **`window_manager` 0.5.2:** `windowManager.hide()` → `ShowWindow(SW_HIDE)` sul lato nativo; l'app resta viva finché `destroy()` non chiude la finestra.
- **Chiusura nei test:** `FakePlayerWindow.simulateClose()` (`test/support/playback_fakes.dart`) chiama gli ascoltatori registrati con `addCloseListener`. In `test/features/player/player_screen_test.dart` le variabili `engine` (`FakeVideoEngine`, ha `disposed`) e `window` (`FakePlayerWindow`) sono create nel `setUp`. `FakePlayerVolume.holdFlush` tiene ferma la scrittura del volume (vedi il test "chiusura della finestra: il volume si scrive subito").
- **`PlayerWindow` ha due implementazioni:** `WindowManagerPlayerWindow` (`lib/features/player/player_window.dart`) e `FakePlayerWindow` (test). Aggiungendo un metodo all'interfaccia vanno aggiornate entrambe.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `lib/ui/poster_card.dart` | modifica | `ProgressStrip`: parte oro alta quanto la barra |
| `test/ui/cards_test.dart` | modifica | misura della parte oro |
| `lib/features/player/player_window.dart` | modifica | `PlayerWindow.hide()` + versione reale |
| `lib/features/player/player_screen.dart` | modifica | `_onWindowClose` nasconde subito la finestra |
| `test/support/playback_fakes.dart` | modifica | `FakePlayerWindow.hide()`, `hidden`, `onHide` |
| `test/features/player/player_screen_test.dart` | modifica | test dell'ordine nascondi → spegni → chiudi |

## Gruppi per i subagent

- **Gruppo A:** Task 1 (#9).
- **Gruppo B:** Task 2 (#8).
- **Gruppo C:** Task 3 (verifica finale, build di release).

---

### Task 1: la parte oro della barra di avanzamento si vede (#9)

**Files:**
- Modify: `lib/ui/poster_card.dart` (classe `ProgressStrip`, ~righe 120–140)
- Test: `test/ui/cards_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

In `test/ui/cards_test.dart` aggiungi l'import (in ordine, dopo `motion.dart`):

```dart
import 'package:wonderflix/app/theme.dart';
```

e subito dopo il test `'PosterCard: barra di avanzamento se iniziato'` aggiungi:

```dart
  testWidgets('ProgressStrip: la parte oro riempie la barra in altezza (#9)',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
            width: 200, height: 112, child: ProgressStrip(progress: 0.4)),
      ),
    ));
    final strip = tester.getRect(find.byType(ProgressStrip));
    final gold = find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == WfColors.gold);
    // In basso a sinistra, alta 3 px come la barra, larga il 40%.
    expect(tester.getRect(gold),
        Rect.fromLTWH(strip.left, strip.bottom - 3, 80, 3));
  });
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/cards_test.dart --plain-name "ProgressStrip: la parte oro"`
Expected: FAIL — il rettangolo trovato ha altezza 0, centrato in verticale nella barra (`Rect.fromLTRB(300.0, 354.5, 380.0, 354.5)` con la superficie di test 800×600).

- [ ] **Step 3: correggi `ProgressStrip`**

In `lib/ui/poster_card.dart` sostituisci il `FractionallySizedBox` di `ProgressStrip`:

```dart
        child: FractionallySizedBox(
          widthFactor: progress,
          child: const ColoredBox(color: WfColors.gold),
        ),
```

con:

```dart
        child: FractionallySizedBox(
          widthFactor: progress,
          // Senza, l'oro (che non ha figli) prende l'altezza minima che
          // l'allineamento gli lascia, cioè 0, e non si vede (issue #9).
          heightFactor: 1,
          child: const ColoredBox(color: WfColors.gold),
        ),
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/ui/cards_test.dart`
Expected: PASS (tutti i test del file).

- [ ] **Step 5: analyze + suite completa**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → tutti verdi (1252).

- [ ] **Step 6: commit**

```bash
git add lib/ui/poster_card.dart test/ui/cards_test.dart
git commit -m "fix: show the gold part of the progress strip (#9)"
```

---

### Task 2: chiudendo l'app la finestra sparisce subito (#8)

**Files:**
- Modify: `lib/features/player/player_window.dart`
- Modify: `lib/features/player/player_screen.dart` (`_onWindowClose`, ~righe 263–272)
- Modify: `test/support/playback_fakes.dart` (`FakePlayerWindow`, ~righe 445–488)
- Test: `test/features/player/player_screen_test.dart` (vicino ai test "chiusura della finestra", ~righe 683–713)

- [ ] **Step 1: scrivi il test che fallisce**

In `test/features/player/player_screen_test.dart`, subito dopo il test `'chiusura della finestra: il volume si scrive subito'`, aggiungi:

```dart
  testWidgets(
      'chiusura della finestra: sparisce subito, prima che il video si spenga',
      (tester) async {
    await pumpPlayer(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    final volume =
        container.read(playerVolumeProvider.notifier) as FakePlayerVolume;
    volume.holdFlush = Completer<void>();
    bool? engineDisposedAtHide;
    window.onHide = () => engineDisposedAtHide = engine.disposed;
    final closing = window.simulateClose();
    await tester.pump();
    expect(engineDisposedAtHide, isFalse,
        reason: 'il motore si spegne solo a finestra già nascosta');
    expect(window.hidden, isTrue,
        reason: 'nascosta mentre il lavoro di uscita è ancora in corso');
    expect(window.destroyed, isFalse);
    volume.holdFlush!.complete();
    await tester.pump();
    await closing;
    expect(window.destroyed, isTrue);
    await unmount(tester);
  });
```

- [ ] **Step 2: aggiorna il finto per far compilare il test**

In `test/support/playback_fakes.dart`, dentro `FakePlayerWindow`, dopo `bool destroyed = false;` aggiungi:

```dart
  bool hidden = false;

  /// Chiamato a ogni [hide], prima che la finestra risulti nascosta (es. per
  /// controllare cosa è già successo in quel momento).
  void Function()? onHide;
```

e dopo il metodo `destroy()` aggiungi:

```dart
  @override
  Future<void> hide() async {
    onHide?.call();
    hidden = true;
  }
```

- [ ] **Step 3: verifica che fallisca**

Run: `flutter test test/features/player/player_screen_test.dart --plain-name "sparisce subito"`
Expected: FAIL — `engineDisposedAtHide` resta `null` (`Expected: false, Actual: <null>`): nessuno chiama ancora `hide`. Il test compila: un `@override` che non sovrascrive niente è solo un avviso dell'analyzer (`override_on_non_overriding_member`), che sparisce allo Step 4.

- [ ] **Step 4: aggiungi `hide()` a `PlayerWindow`**

In `lib/features/player/player_window.dart`, nell'interfaccia `PlayerWindow`, prima di `Future<void> destroy();`:

```dart
  /// Nasconde la finestra. L'app resta viva finché non si chiama [destroy].
  Future<void> hide();

```

e in `WindowManagerPlayerWindow`, prima di `destroy()`:

```dart
  @override
  Future<void> hide() => windowManager.hide();

```

- [ ] **Step 5: nascondi la finestra all'inizio della chiusura**

In `lib/features/player/player_screen.dart` sostituisci l'inizio di `_onWindowClose`:

```dart
  Future<void> _onWindowClose() async {
    await Future.wait([
```

con:

```dart
  Future<void> _onWindowClose() async {
    // La finestra sparisce subito: fine della sessione sul server, uscita dal
    // party e volume vanno avanti senza farsi vedere. Prima restava ferma a
    // video nero finché non finivano (issue #8).
    try {
      await _window.hide();
    } on Object {
      // Se non si nasconde, si chiude comunque come prima.
    }
    await Future.wait([
```

Il resto del metodo (il `Future.wait` con `closeTimeout` e `await _window.destroy()`) non cambia.

- [ ] **Step 6: verifica che passi**

Run: `flutter test test/features/player/player_screen_test.dart`
Expected: PASS (tutti i test del file, compresi i due "chiusura della finestra" già esistenti).

- [ ] **Step 7: analyze + suite completa**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → tutti verdi (1253).

- [ ] **Step 8: commit**

```bash
git add lib/features/player/player_window.dart lib/features/player/player_screen.dart test/support/playback_fakes.dart test/features/player/player_screen_test.dart
git commit -m "fix: hide the window first when closing with the player open (#8)"
```

---

### Task 3: verifica finale

- [ ] **Step 1:** `flutter analyze` → `No issues found!`
- [ ] **Step 2:** `flutter test` → 1253 test, tutti verdi.
- [ ] **Step 3:** copia la configurazione nel worktree (non è versionata) e fai la build di release:

```bash
cp ../../../config/wonderflix.json config/wonderflix.json
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

Expected: `√ Built build\windows\x64\runner\Release\wonderflix.exe`. Senza `--dart-define-from-file` l'app mostra "Configurazione mancante".

- [ ] **Step 4:** `git status` pulito (a parte `config/wonderflix.json`, che è ignorato, e i file `windows/flutter/generated_plugin*` da ripristinare se cambiano solo le fini riga). Nessun commit in questo task.

---

## Prova manuale (con l'utente, sul server reale)

Con `build/windows/x64/runner/Release/wonderflix.exe` del worktree:

1. **#9:** Home → "Continua a guardare": ogni card ha la barra oro lunga quanto il visto. Stessa cosa nella ricerca, nell'anteprima della card (passaggio del mouse) e nella lista episodi di una serie.
2. **#8:** apri un film, guarda qualche minuto, clicca la X della finestra → la finestra sparisce subito, senza video nero. Riapri l'app: il film riparte dal punto in cui avevi chiuso.
3. **#8 a schermo intero:** stessa prova a schermo intero.
4. **#8 nel watch party** (due istanze, `WONDERFLIX_PROFILE=b`): chiudi una delle due con la X → sparisce subito; nell'altra compare l'uscita dal gruppo.

## Dopo la prova (fuori dai task)

- Con l'ok dell'utente: merge fast-forward su `main`, `git fetch` e rebase se `origin/main` è avanti, push, rimozione di worktree e branch.
- Release **0.5.1 non obbligatoria** (`chore: release 0.5.1`, tag `v0.5.1`), note in italiano scritte nella bozza (senza `min-version`). La pubblica l'utente.
- Dopo la pubblicazione e con l'ok dell'utente: commento su #8 e #9 (causa, correzione, link a v0.5.1) e chiusura come completate.
