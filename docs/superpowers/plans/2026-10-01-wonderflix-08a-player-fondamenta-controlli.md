# WonderFlix — Piano 8a: player, fondamenta e controlli

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** primo piano dello Spec D (rinnovo del player): `PlayerChromeController`, token di movimento nel player e nella sua pagina, pulsanti e comparsa dei controlli rinnovati, barra di avanzamento a segmenti con zone e anteprima animata, pillola in alto per il riscontro dei tasti e gli avvisi del watch party.

**Decisioni prese con l'utente (2026-10-01):**
1. Il controller cresce piano per piano: in 8a gestisce controlli, pannello e riscontri dei tasti. Schermata di pausa (8b) e post-play (8c) arrivano dopo. Fino all'8b in pausa i controlli restano visibili, come oggi.
2. I tasti non mostrano più i controlli: mostrano solo la pillola. I controlli compaiono solo muovendo il mouse.
3. Barra: widget proprio; aritmetica di segmenti e zone in funzioni pure; margine orizzontale 8 px, area cliccabile alta 28 px; `Semantics` da slider; l'anteprima segue anche il trascinamento.
4. Pillola dei salti: arrivo = partenza + somma dei salti, tra 0 e la durata; segno con il trattino ("-10 s"), come il ritardo dei sottotitoli.
5. `playerPage(context, state, child)`: entrata `medium` in dissolvenza incrociata, uscita `fast`. Quando un player ne sostituisce un altro (`extra: playerReplacement`) resta lo sfondo nero sotto la transizione (altrimenti si vedrebbe la pagina sotto i due player).
6. `PlayerScreen.hideDelay` diventa `PlayerChromeController.hideDelay` (3 s).
7. Il volume resta lo `Slider` di oggi.

**Architecture:**
- `lib/features/player/player_chrome.dart`: `PlayerChromeController` (`ChangeNotifier` in Dart puro, con `clock` e `Timer`) e i riscontri dei tasti (`PlayerFeedback` sigillata: `PlayFeedback`, `SeekFeedback`, `VolumeFeedback`, `SubtitleDelayFeedback`). `PlayerScreen` lo crea, lo ascolta con `setState` e lo distrugge.
- `lib/features/player/seek_segments.dart`: funzioni pure `seekSegments`, `seekZones`, `zoneAt`. `seek_bar.dart`: `SeekBar` riscritta con `CustomPaint` (`SeekBarPainter`) e `GestureDetector`.
- `lib/features/player/player_pill.dart`: `PlayerPill` (riscontro del tasto, altrimenti avviso del party), `playerFeedbackText`, `playerFeedbackIcon`, `formatSeekOffset`. Sostituisce `PartyNoticePill`, che sparisce; `partyNoticeText` resta e si aggiunge `partyNoticeIcon`.
- `player_overlay.dart`: `PlayerIconButton`, `PlayPauseIcon`, parametro `visible` con dissolvenza e scivolamento delle due parti.
- `PartyNotices.mine(kind, {position, show = true})`: con `show: false` registra solo l'eco.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, media_kit_video 2.0.1, lucide_icons_flutter 3.1.20, clock, fake_async.

**Spec:** `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md` (§5, §6, §7, §8, §9, §15.1). **Worktree:** `.claude/worktrees/rinnovo-player-8a`, branch `feat/rinnovo-player-8a`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/rinnovo-player-8a`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde (a inizio piano: 918 test). Dopo aver toccato gli ARB: `flutter gen-l10n` (i file generati in `lib/l10n/gen/` non sono nel repository).
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione e fine riga:** niente `dart format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`). I file nuovi si scrivono interi.
- **Colori:** solo `WfColors`. **Durate e curve:** token di `WfMotion` o costanti nominate e commentate. **Tempo:** `clock.now()`, mai `DateTime.now()`. **Icone:** solo `LucideIcons`. **Testi UI:** negli ARB (it + en).
- **Widget test:** `pumpApp` (`test/support/pump_app.dart`, finestra 1440×900, movimento **ridotto** salvo `motion: MotionLevel.full`). `player_screen_test` e `party_player_test` montano l'app a mano senza `WfMotionScope`: `WfMotion.of` è ridotto. In questo piano non ci sono animazioni continue nel player: `pumpAndSettle` va bene.
- **Animazioni in uscita:** `AnimatedSwitcher`, la pillola e l'anteprima della barra tengono il contenuto vecchio nell'albero finché sfuma (150 ms). Un test che si aspetta un testo sparito deve prima avanzare (`pumpAndSettle`, o `pump()` + `pump(WfMotion.fast)` + `pump()`).
- **`AnimationController`** risulta completato solo al fotogramma dopo aver raggiunto la durata; il valore però è già 1 nel fotogramma in cui la durata è raggiunta.
- **Fake:** `FakeVideoEngine` (`test/support/playback_fakes.dart`: `emitPosition`, `emitDuration`, `emitBuffer`, `seeks`, `volumes`, `subtitleDelays`; `seek` emette subito la posizione; durata predefinita 2 h), `FakePartyNotices` (`test/support/watch_party_fakes.dart`), `testItem` (`test/support/library_fakes.dart`).
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **`IconButton` (Material 3):** il parametro `hoverColor` viene mappato nello stile (`WidgetState.hovered`), quindi funziona anche con `useMaterial3: true`.
- **go_router 18:** `pushReplacement(location, {Object? extra})`; l'`extra` arriva in `state.extra` del `pageBuilder`. `pushReplacement` usa sempre una chiave di pagina nuova (la transizione parte).
- **Transizioni:** durante l'animazione la voce dell'overlay di una pagina non è opaca, quindi la pagina sotto resta dipinta (e `find.text` la trova).
- **`fake_async`** fa girare il codice con un `clock` finto: `clock.now()` avanza con `elapse`.
- **`GroupAuthority`** (`lib/features/watch_party/group_authority.dart`): `seekTo` sposta subito il motore e manda il salto al gruppo dopo `seekDebounce` (400 ms), poi chiama `onAction(seeked)`; `play` aspetta `_flushSeek()` prima di `onAction(resumed)`; `pause` chiama `onAction(paused)` dopo `engine.pause()`.
- **`PlayerController`:** `setVolume`, `changeVolumeBy`, `toggleMute` e `shiftSubtitleDelay` aggiornano lo stato (`_emit`) **prima** del primo `await`: subito dopo la chiamata `ref.read(provider)` ha già il valore nuovo. `togglePlay` non fa nulla se il player non è `ready`.
- **`formatClock`** (`lib/features/library/item_labels.dart`): "00:10" sotto l'ora, "1:02:03" sopra.
- **`partyNoticesProvider`** dipende dalla sessione del watch party: si legge solo nel player di un gruppo (`widget.args.party != null`), come oggi.
- **`PartyNoticePill`** si usa solo in `player_screen.dart`.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi della pillola e delle zone |
| `lib/features/watch_party/party_notices.dart` | modifica | `mine(..., show:)` |
| `lib/features/watch_party/party_notice_pill.dart` | modifica | `partyNoticeIcon`; via `PartyNoticePill` (Task 8) |
| `lib/features/player/player_chrome.dart` | crea | `PlayerChromeController`, `PlayerFeedback` |
| `lib/app/navigation.dart` | modifica | `PlayerReplacement`, `playerReplacement` |
| `lib/app/router.dart` | modifica | `playerPage` con i token |
| `lib/features/watch_party/watch_party_routing.dart` | modifica | `replace` con `extra: playerReplacement` |
| `lib/features/player/player_overlay.dart` | modifica | `PlayerIconButton`, `PlayPauseIcon`, `visible` |
| `lib/features/player/seek_segments.dart` | crea | `SeekSegment`, `SeekZone`, `seekSegments`, `seekZones`, `zoneAt` |
| `lib/features/player/seek_bar.dart` | modifica (riscrittura) | `SeekBar`, `SeekBarPainter`, `seekZoneLabel` |
| `lib/features/player/player_pill.dart` | crea | `PlayerPill`, testi e icone dei riscontri |
| `lib/features/player/player_screen.dart` | modifica | collega controller, pillola, tasti, `onAction` |
| `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md` | modifica | §6.3: nero sotto la sostituzione |
| test | crea/modifica | vedi i singoli task |

## Gruppi per i subagent

- **Gruppo A (Task 1–3):** fondamenta.
- **Gruppo B (Task 4–5):** controlli.
- **Gruppo C (Task 6–7):** barra.
- **Gruppo D (Task 8–9):** pillola e collegamento.
- **Gruppo E (Task 10):** verifica finale.

---

### Task 1: testi, `PartyNotices.mine(show:)` e icone degli avvisi

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify: `lib/features/watch_party/party_notices.dart`
- Modify: `lib/features/watch_party/party_notice_pill.dart`
- Modify: `test/support/watch_party_fakes.dart`
- Create: `test/app/l10n_plan8a_test.dart`
- Test: `test/features/watch_party/party_notices_test.dart`, `test/features/watch_party/party_notice_pill_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/app/l10n_plan8a_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 8a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerFeedbackPlaying, 'Riproduzione');
    expect(it.playerFeedbackPaused, 'In pausa');
    expect(it.playerFeedbackSeek('+20 s', '18:02'), '+20 s · 18:02');
    expect(it.playerFeedbackVolume(70), 'Volume 70%');
    expect(it.playerFeedbackMuted, 'Audio disattivato');
    expect(it.playerFeedbackSubtitles('+0,3 s'), 'Sottotitoli +0,3 s');
    expect(it.playerSegmentRecap, 'Riassunto');
    expect(it.playerSegmentIntro, 'Intro');
    expect(it.playerSegmentOutro, 'Titoli di coda');
    expect(en.playerFeedbackPlaying, 'Playing');
    expect(en.playerFeedbackPaused, 'Paused');
    expect(en.playerFeedbackSeek('-10 s', '17:32'), '-10 s · 17:32');
    expect(en.playerFeedbackVolume(70), 'Volume 70%');
    expect(en.playerFeedbackMuted, 'Muted');
    expect(en.playerFeedbackSubtitles('+0.3 s'), 'Subtitles +0.3 s');
    expect(en.playerSegmentRecap, 'Recap');
    expect(en.playerSegmentIntro, 'Intro');
    expect(en.playerSegmentOutro, 'End credits');
  });
}
```

In `test/features/watch_party/party_notices_test.dart`, subito dopo il test `'la mia ripresa copre la ripresa senza aspettare'`, aggiungi:

```dart
  test('mia azione senza avviso: niente pillola, ma l\'eco resta registrata',
      () {
    fakeAsync((async) {
      mount(async);
      notices().mine(PartyNoticeKind.paused, show: false);
      expect(current(), isNull);
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      expect(current(), isNull, reason: 'è l\'eco della mia pausa');
      finish(async);
    });
  });
```

In `test/features/watch_party/party_notice_pill_test.dart` aggiungi l'import `import 'package:lucide_icons_flutter/lucide_icons.dart';` e, dopo il test `'testi di tutti gli avvisi'`, il test:

```dart
  test('icone degli avvisi', () {
    expect(partyNoticeIcon(PartyNoticeKind.paused), LucideIcons.pause);
    expect(partyNoticeIcon(PartyNoticeKind.resumed), LucideIcons.play);
    expect(partyNoticeIcon(PartyNoticeKind.forcedResume), LucideIcons.play);
    expect(partyNoticeIcon(PartyNoticeKind.seeked), LucideIcons.fastForward);
    expect(partyNoticeIcon(PartyNoticeKind.joined), LucideIcons.userPlus);
    expect(partyNoticeIcon(PartyNoticeKind.left), LucideIcons.userMinus);
    expect(partyNoticeIcon(PartyNoticeKind.nextEpisode), LucideIcons.skipForward);
    expect(partyNoticeIcon(PartyNoticeKind.nowWatching), LucideIcons.clapperboard);
    expect(partyNoticeIcon(PartyNoticeKind.resync), LucideIcons.refreshCw);
    expect(partyNoticeIcon(PartyNoticeKind.ended), LucideIcons.circleStop);
    expect(partyNoticeIcon(PartyNoticeKind.removed), LucideIcons.logOut);
  });
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/app/l10n_plan8a_test.dart test/features/watch_party/party_notices_test.dart test/features/watch_party/party_notice_pill_test.dart`
Expected: FAIL (getter `playerFeedbackPlaying` inesistente, parametro `show` inesistente, `partyNoticeIcon` non definita).

- [ ] **Step 3: testi.** In `l10n/app_it.arb` sostituisci l'ultima voce

```json
  "previewResume": "Riprendi"
}
```

con

```json
  "previewResume": "Riprendi",
  "playerFeedbackPlaying": "Riproduzione",
  "playerFeedbackPaused": "In pausa",
  "playerFeedbackSeek": "{offset} · {time}",
  "@playerFeedbackSeek": {"placeholders": {"offset": {"type": "String"}, "time": {"type": "String"}}},
  "playerFeedbackVolume": "Volume {percent}%",
  "@playerFeedbackVolume": {"placeholders": {"percent": {"type": "int"}}},
  "playerFeedbackMuted": "Audio disattivato",
  "playerFeedbackSubtitles": "Sottotitoli {delay}",
  "@playerFeedbackSubtitles": {"placeholders": {"delay": {"type": "String"}}},
  "playerSegmentRecap": "Riassunto",
  "playerSegmentIntro": "Intro",
  "playerSegmentOutro": "Titoli di coda"
}
```

In `l10n/app_en.arb` sostituisci

```json
  "previewResume": "Resume"
}
```

con

```json
  "previewResume": "Resume",
  "playerFeedbackPlaying": "Playing",
  "playerFeedbackPaused": "Paused",
  "playerFeedbackSeek": "{offset} · {time}",
  "@playerFeedbackSeek": {"placeholders": {"offset": {"type": "String"}, "time": {"type": "String"}}},
  "playerFeedbackVolume": "Volume {percent}%",
  "@playerFeedbackVolume": {"placeholders": {"percent": {"type": "int"}}},
  "playerFeedbackMuted": "Muted",
  "playerFeedbackSubtitles": "Subtitles {delay}",
  "@playerFeedbackSubtitles": {"placeholders": {"delay": {"type": "String"}}},
  "playerSegmentRecap": "Recap",
  "playerSegmentIntro": "Intro",
  "playerSegmentOutro": "End credits"
}
```

Poi: `flutter gen-l10n`.

- [ ] **Step 4: `mine` con `show`.** In `lib/features/watch_party/party_notices.dart` sostituisci

```dart
  /// Azione dell'utente: l'avviso compare subito, e l'eco del server (entro
  /// [echoWindow]) non ne produce un secondo.
  void mine(PartyNoticeKind kind, {Duration? position}) {
    _echoes.add((kind: kind, at: clock.now()));
    show(PartyNotice(kind, mine: true, position: position));
  }
```

con

```dart
  /// Azione dell'utente: l'avviso compare subito, e l'eco del server (entro
  /// [echoWindow]) non ne produce un secondo. Con [show] `false` si registra
  /// solo l'eco: l'azione l'ha già mostrata la pillola del tasto (spec D
  /// §9.3).
  void mine(PartyNoticeKind kind, {Duration? position, bool show = true}) {
    _echoes.add((kind: kind, at: clock.now()));
    if (show) this.show(PartyNotice(kind, mine: true, position: position));
  }
```

In `test/support/watch_party_fakes.dart`, in `FakePartyNotices`, sostituisci

```dart
  final mineCalls = <(PartyNoticeKind, Duration?)>[];

  @override
  PartyNotice? build() => initial;

  @override
  void show(PartyNotice notice) => shown.add(notice);

  @override
  void mine(PartyNoticeKind kind, {Duration? position}) =>
      mineCalls.add((kind, position));
```

con

```dart
  final mineCalls = <(PartyNoticeKind, Duration?)>[];

  /// Azioni registrate con `show: false` (solo l'eco, nessun avviso).
  final hiddenMineCalls = <PartyNoticeKind>[];

  @override
  PartyNotice? build() => initial;

  @override
  void show(PartyNotice notice) => shown.add(notice);

  @override
  void mine(PartyNoticeKind kind, {Duration? position, bool show = true}) {
    mineCalls.add((kind, position));
    if (!show) hiddenMineCalls.add(kind);
  }
```

- [ ] **Step 5: icone.** In `lib/features/watch_party/party_notice_pill.dart` aggiungi l'import `import 'package:lucide_icons_flutter/lucide_icons.dart';` (dopo `flutter_riverpod`) e, subito dopo la funzione `partyNoticeText`, la funzione:

```dart
/// Icona oro dell'avviso nella pillola del player (spec D §15.1).
IconData partyNoticeIcon(PartyNoticeKind kind) => switch (kind) {
      PartyNoticeKind.paused => LucideIcons.pause,
      PartyNoticeKind.resumed ||
      PartyNoticeKind.forcedResume =>
        LucideIcons.play,
      PartyNoticeKind.seeked => LucideIcons.fastForward,
      PartyNoticeKind.joined => LucideIcons.userPlus,
      PartyNoticeKind.left => LucideIcons.userMinus,
      PartyNoticeKind.nextEpisode => LucideIcons.skipForward,
      PartyNoticeKind.nowWatching => LucideIcons.clapperboard,
      PartyNoticeKind.resync => LucideIcons.refreshCw,
      PartyNoticeKind.ended => LucideIcons.circleStop,
      PartyNoticeKind.removed => LucideIcons.logOut,
    };
```

- [ ] **Step 6: verifica.**

Run: `flutter test test/app/l10n_plan8a_test.dart test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

- [ ] **Step 7: commit.**

```bash
git add l10n/app_it.arb l10n/app_en.arb lib/features/watch_party/party_notices.dart lib/features/watch_party/party_notice_pill.dart test/support/watch_party_fakes.dart test/app/l10n_plan8a_test.dart test/features/watch_party/party_notices_test.dart test/features/watch_party/party_notice_pill_test.dart
git commit -m "feat: add player pill strings, silent own notices and notice icons"
```

---

### Task 2: `PlayerChromeController`

**Files:**
- Create: `lib/features/player/player_chrome.dart`
- Test: `test/features/player/player_chrome_test.dart`

- [ ] **Step 1: test che fallisce.** Crea `test/features/player/player_chrome_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/player_chrome.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';

void main() {
  const duration = Duration(minutes: 40);
  const step = Duration(seconds: 10);

  test('in riproduzione i controlli spariscono dopo 3 s; il mouse li riporta',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      var notified = 0;
      chrome.addListener(() => notified++);
      expect(chrome.controlsVisible, isTrue);
      chrome.setPlaying(true);
      async.elapse(const Duration(milliseconds: 2900));
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(milliseconds: 100));
      expect(chrome.controlsVisible, isFalse);
      expect(notified, 1);

      chrome.pointerActivity();
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(seconds: 2));
      chrome.pointerActivity(); // il conto riparte
      async.elapse(const Duration(seconds: 2));
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(seconds: 1));
      expect(chrome.controlsVisible, isFalse);
      chrome.dispose();
    });
  });

  test('in pausa i controlli restano', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()..setPlaying(true);
      async.elapse(const Duration(seconds: 1));
      chrome.setPlaying(false);
      async.elapse(const Duration(seconds: 10));
      expect(chrome.controlsVisible, isTrue);
      chrome.dispose();
    });
  });

  test('pannello aperto: i controlli restano; chiuso, il conto riparte', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()..setPlaying(true);
      async.elapse(const Duration(seconds: 5));
      expect(chrome.controlsVisible, isFalse);
      chrome.togglePanel();
      expect(chrome.panelOpen, isTrue);
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(seconds: 10));
      expect(chrome.controlsVisible, isTrue);
      chrome.closePanel();
      expect(chrome.panelOpen, isFalse);
      async.elapse(PlayerChromeController.hideDelay);
      expect(chrome.controlsVisible, isFalse);
      chrome.dispose();
    });
  });

  test('riscontro: resta 1,2 s dall\'ultimo tasto e non mostra i controlli',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()..setPlaying(true);
      async.elapse(const Duration(seconds: 3));
      chrome.showFeedback(const VolumeFeedback(volume: 70, muted: false));
      expect(chrome.feedback, isA<VolumeFeedback>());
      expect(chrome.controlsVisible, isFalse);
      async.elapse(const Duration(seconds: 1));
      chrome.showFeedback(const VolumeFeedback(volume: 75, muted: false));
      async.elapse(const Duration(seconds: 1));
      expect((chrome.feedback! as VolumeFeedback).volume, 75);
      async.elapse(const Duration(milliseconds: 200));
      expect(chrome.feedback, isNull);
      chrome.dispose();
    });
  });

  test('salti: si sommano nella stessa direzione entro 1 s', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      chrome.seek(step, from: const Duration(minutes: 17), duration: duration);
      async.elapse(const Duration(milliseconds: 500));
      // La posizione del motore può essere ancora quella di prima: conta
      // l'arrivo del salto precedente.
      chrome.seek(step, from: const Duration(minutes: 17), duration: duration);
      var seek = chrome.feedback! as SeekFeedback;
      expect(seek.offset, const Duration(seconds: 20));
      expect(seek.target, const Duration(minutes: 17, seconds: 20));

      // Direzione opposta: si ricomincia.
      chrome.seek(-step,
          from: const Duration(minutes: 17, seconds: 20), duration: duration);
      seek = chrome.feedback! as SeekFeedback;
      expect(seek.offset, -step);
      expect(seek.target, const Duration(minutes: 17, seconds: 10));

      // Oltre 1 s: si ricomincia.
      async.elapse(const Duration(milliseconds: 1100));
      chrome.seek(-step,
          from: const Duration(minutes: 17, seconds: 10), duration: duration);
      seek = chrome.feedback! as SeekFeedback;
      expect(seek.offset, -step);
      expect(seek.target, const Duration(minutes: 17));
      chrome.dispose();
    });
  });

  test('salti: arrivo tra 0 e la durata', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      chrome.seek(-step, from: const Duration(seconds: 4), duration: duration);
      expect((chrome.feedback! as SeekFeedback).target, Duration.zero);
      async.elapse(const Duration(seconds: 2));
      chrome.seek(step,
          from: const Duration(minutes: 39, seconds: 55), duration: duration);
      expect((chrome.feedback! as SeekFeedback).target, duration);
      chrome.dispose();
    });
  });

  test('azione recente da tastiera: stesso tipo, entro 1 s', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      expect(chrome.isRecentKeyAction(PartyNoticeKind.paused), isFalse);
      chrome.showFeedback(const PlayFeedback(playing: false));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.paused), isTrue);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.resumed), isFalse);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isFalse);
      chrome.seek(step, from: Duration.zero, duration: duration);
      async.elapse(const Duration(milliseconds: 400));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isTrue);
      async.elapse(const Duration(milliseconds: 700));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isFalse,
          reason: 'la pillola è sparita da poco, ma è passato più di 1 s');
      expect(chrome.isRecentKeyAction(PartyNoticeKind.joined), isFalse);
      chrome.dispose();
    });
  });

  test('dispose: nessun timer in sospeso', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()..setPlaying(true);
      chrome.showFeedback(const PlayFeedback(playing: true));
      chrome.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
```

- [ ] **Step 2: verifica che fallisca.**

Run: `flutter test test/features/player/player_chrome_test.dart`
Expected: FAIL (file `player_chrome.dart` inesistente).

- [ ] **Step 3: implementazione.** Crea `lib/features/player/player_chrome.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../watch_party/party_notices.dart';

/// Riscontro di un tasto nella pillola del player (spec D §9.2).
@immutable
sealed class PlayerFeedback {
  const PlayerFeedback();
}

/// Spazio: [playing] è lo stato dopo il tasto.
final class PlayFeedback extends PlayerFeedback {
  const PlayFeedback({required this.playing});

  final bool playing;
}

/// ←/→: [offset] è la somma dei salti di fila, [target] la posizione di
/// arrivo.
final class SeekFeedback extends PlayerFeedback {
  const SeekFeedback({required this.offset, required this.target});

  final Duration offset;
  final Duration target;
}

/// ↑/↓ e M: volume (0–100) e muto dopo il tasto.
final class VolumeFeedback extends PlayerFeedback {
  const VolumeFeedback({required this.volume, required this.muted});

  final double volume;
  final bool muted;
}

/// G/H: ritardo dei sottotitoli dopo il tasto.
final class SubtitleDelayFeedback extends PlayerFeedback {
  const SubtitleDelayFeedback(this.delay);

  final Duration delay;
}

/// Stato dell'interfaccia del player (spec D §5.1): controlli, pannello e
/// riscontro dei tasti. Lo stato della riproduzione resta nel
/// `PlayerController`. Lo crea e lo distrugge `PlayerScreen`.
class PlayerChromeController extends ChangeNotifier {
  /// Mouse fermo per così, in riproduzione: i controlli spariscono.
  static const hideDelay = Duration(seconds: 3);

  /// Quanto resta la pillola dopo l'ultimo tasto.
  static const feedbackDuration = Duration(milliseconds: 1200);

  /// Salti nella stessa direzione entro questo tempo: si sommano.
  static const seekSumWindow = Duration(seconds: 1);

  /// Nel watch party l'avviso "Hai…" di un'azione arriva fino a 400 ms dopo
  /// il tasto (`GroupAuthority.seekDebounce`): entro questo tempo è la
  /// stessa azione, già mostrata dalla pillola del tasto.
  static const keyActionWindow = Duration(seconds: 1);

  bool _controlsVisible = true;
  bool _panelOpen = false;
  bool _playing = false;
  PlayerFeedback? _feedback;

  /// Ultimo riscontro e quando è arrivato: restano anche dopo che la
  /// pillola è sparita (somma dei salti, [isRecentKeyAction]).
  PlayerFeedback? _lastFeedback;
  DateTime? _lastFeedbackAt;
  Timer? _hideTimer;
  Timer? _feedbackTimer;

  bool get controlsVisible => _controlsVisible;

  bool get panelOpen => _panelOpen;

  /// Riscontro da mostrare adesso; `null` = nessuno.
  PlayerFeedback? get feedback => _feedback;

  /// Il mouse si è mosso: controlli visibili, e il conto per nasconderli
  /// riparte.
  void pointerActivity() {
    if (!_controlsVisible) {
      _controlsVisible = true;
      notifyListeners();
    }
    _scheduleHide();
  }

  /// Riproduzione o pausa. In pausa i controlli restano dove sono.
  void setPlaying(bool playing) {
    _playing = playing;
    _scheduleHide();
  }

  /// Apre o chiude il pannello "Audio e sottotitoli": i controlli si vedono
  /// e, a pannello aperto, restano.
  void togglePanel() {
    _panelOpen = !_panelOpen;
    _controlsVisible = true;
    notifyListeners();
    _scheduleHide();
  }

  void closePanel() {
    if (!_panelOpen) return;
    _panelOpen = false;
    notifyListeners();
    _scheduleHide();
  }

  /// Mostra [feedback] per [feedbackDuration]. I controlli non compaiono.
  void showFeedback(PlayerFeedback feedback) {
    _feedback = feedback;
    _lastFeedback = feedback;
    _lastFeedbackAt = clock.now();
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(feedbackDuration, () {
      _feedback = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Salto di [step] da [from]. Se continua una serie nella stessa
  /// direzione (entro [seekSumWindow]) somma l'offset e parte dall'arrivo
  /// precedente. L'arrivo resta tra 0 e [duration] (se nota).
  void seek(Duration step,
      {required Duration from, required Duration duration}) {
    final previous = _lastFeedback;
    final at = _lastFeedbackAt;
    SeekFeedback? series;
    if (previous is SeekFeedback &&
        at != null &&
        clock.now().difference(at) <= seekSumWindow &&
        previous.offset.isNegative == step.isNegative) {
      series = previous;
    }
    final offset = (series?.offset ?? Duration.zero) + step;
    var target = (series?.target ?? from) + step;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    showFeedback(SeekFeedback(offset: offset, target: target));
  }

  /// `true` se l'ultimo tasto (entro [keyActionWindow]) ha fatto la stessa
  /// azione di gruppo [kind]: pausa, ripresa o salto.
  bool isRecentKeyAction(PartyNoticeKind kind) {
    final last = _lastFeedback;
    final at = _lastFeedbackAt;
    if (last == null || at == null) return false;
    if (clock.now().difference(at) > keyActionWindow) return false;
    return switch (kind) {
      PartyNoticeKind.paused => last is PlayFeedback && !last.playing,
      PartyNoticeKind.resumed => last is PlayFeedback && last.playing,
      PartyNoticeKind.seeked => last is SeekFeedback,
      _ => false,
    };
  }

  /// I controlli si nascondono solo in riproduzione e a pannello chiuso.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_playing || _panelOpen || !_controlsVisible) return;
    _hideTimer = Timer(hideDelay, () {
      _controlsVisible = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/player_chrome_test.dart`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/player_chrome.dart test/features/player/player_chrome_test.dart
git commit -m "feat: add the player chrome controller"
```

---

### Task 3: `playerPage` con i token e sostituzione dei player

**Files:**
- Modify: `lib/app/navigation.dart`
- Modify: `lib/app/router.dart`
- Modify: `lib/features/player/player_screen.dart` (le due `pushReplacement`)
- Modify: `lib/features/watch_party/watch_party_routing.dart`
- Modify: `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md` (§6.3)
- Test: `test/app/router_test.dart`

- [ ] **Step 1: test che falliscono.** In `test/app/router_test.dart` aggiungi l'import `import 'package:wonderflix/app/navigation.dart';` se manca e sostituisci tutto il test `'player: sotto la transizione solo nero, mai la pagina sotto'` con:

```dart
  GoRouter playerTestRouter() {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home'))),
      GoRoute(
        path: '/play/:id',
        pageBuilder: (context, state) => playerPage(
            context, state, Text('player ${state.pathParameters['id']}')),
      ),
    ]);
    addTearDown(router.dispose);
    return router;
  }

  testWidgets('player dalla Home: dissolvenza incrociata, senza nero',
      (tester) async {
    final router = playerTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.push('/play/e4');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const Key('player-replacement-backdrop')), findsNothing);
    expect(find.text('home'), findsOneWidget,
        reason: 'la pagina di partenza resta sotto mentre il player sfuma');
    await tester.pumpAndSettle();
    expect(find.text('player e4'), findsOneWidget);
  });

  testWidgets('player che ne sostituisce un altro: sotto solo nero',
      (tester) async {
    final router = playerTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/play/e4');
    await tester.pumpAndSettle();

    router.pushReplacement('/play/e5', extra: playerReplacement);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final backdrop = find.byKey(const Key('player-replacement-backdrop'));
    expect(tester.widget<ColoredBox>(backdrop).color, Colors.black);
    expect(tester.getSize(backdrop),
        tester.view.physicalSize / tester.view.devicePixelRatio);
    await tester.pumpAndSettle();
    expect(find.text('player e5'), findsOneWidget);
    expect(find.text('player e4'), findsNothing);
  });
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/app/router_test.dart`
Expected: FAIL (`playerPage` vuole due argomenti, `playerReplacement` non esiste).

- [ ] **Step 3: marcatore della sostituzione.** In `lib/app/navigation.dart`, subito prima della funzione `playerRoute`, aggiungi:

```dart
/// `extra` di un player che ne sostituisce un altro (episodio successivo,
/// passaggio al player del gruppo): sotto la transizione serve il nero,
/// altrimenti si vedrebbe la pagina sotto i due player (spec D §6.3).
class PlayerReplacement {
  const PlayerReplacement();
}

const playerReplacement = PlayerReplacement();

```

- [ ] **Step 4: `playerPage`.** In `lib/app/router.dart` aggiungi l'import `import 'motion.dart';` (dopo `import 'hero_launch.dart';`) e sostituisci

```dart
/// Pagina del player. Con l'episodio successivo il nuovo player sostituisce
/// il precedente (`pushReplacement`, pagina nuova): con la transizione
/// predefinita, mentre compare, si vedrebbe la pagina sotto (dettaglio o
/// Home). Qui dal primo fotogramma c'è uno sfondo nero opaco e il player
/// appare in dissolvenza sopra.
Page<void> playerPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          ColoredBox(
        color: Colors.black,
        child: FadeTransition(opacity: animation, child: child),
      ),
    );
```

con

```dart
/// Pagina del player (spec D §6.3). Dalla scheda o dalla Home entra in
/// dissolvenza incrociata sopra la pagina di partenza (`medium`) ed esce in
/// `fast`. Quando sostituisce un altro player (`extra` [PlayerReplacement]:
/// episodio successivo, player del gruppo) la pagina sotto non è quella di
/// partenza: dal primo fotogramma c'è uno sfondo nero opaco e il player
/// appare sopra.
Page<void> playerPage(
    BuildContext context, GoRouterState state, Widget child) {
  final motion = WfMotion.of(context);
  final replacing = state.extra is PlayerReplacement;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: motion.duration(WfMotion.medium),
    reverseTransitionDuration: WfMotion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final faded = FadeTransition(
          opacity: animation.drive(CurveTween(curve: WfMotion.standard)),
          child: child);
      return replacing
          ? ColoredBox(
              key: const Key('player-replacement-backdrop'),
              color: Colors.black,
              child: faded)
          : faded;
    },
  );
}
```

Nella rotta del player, sempre in `router.dart`, sostituisci

```dart
        pageBuilder: (context, state) => playerPage(
          state,
          PlayerScreen(
```

con

```dart
        pageBuilder: (context, state) => playerPage(
          context,
          state,
          PlayerScreen(
```

- [ ] **Step 5: chi sostituisce un player.** In `lib/features/player/player_screen.dart` sostituisci

```dart
    context.pushReplacement(
        playerRoute(next.id, start: start, fullscreen: _fullscreen));
```

con

```dart
    context.pushReplacement(
        playerRoute(next.id, start: start, fullscreen: _fullscreen),
        extra: playerReplacement);
```

e sostituisci

```dart
    context.pushReplacement(playerRoute(
      entry.itemId,
      start: ref.read(watchPartySessionProvider.notifier).estimatedPosition(),
      fullscreen: _fullscreen,
      party: entry.playlistItemId,
    ));
```

con

```dart
    context.pushReplacement(
        playerRoute(
          entry.itemId,
          start:
              ref.read(watchPartySessionProvider.notifier).estimatedPosition(),
          fullscreen: _fullscreen,
          party: entry.playlistItemId,
        ),
        extra: playerReplacement);
```

In `lib/features/watch_party/watch_party_routing.dart` sostituisci

```dart
  @override
  void replace(String route) =>
      unawaited(_router.pushReplacement<void>(route));
```

con

```dart
  /// Sostituisce sempre un player con un altro (spec D §6.3).
  @override
  void replace(String route) => unawaited(
      _router.pushReplacement<void>(route, extra: playerReplacement));
```

(`navigation.dart` è già importato in entrambi i file per `playerRoute`.)

- [ ] **Step 6: spec.** In `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md`, §6.3, sostituisci

```markdown
- **ingresso:** dissolvenza incrociata in `medium` (niente `ColoredBox` nero): la scheda sfuma nello sfondo del caricamento, che è la stessa immagine della testata;
```

con

```markdown
- **ingresso:** dissolvenza incrociata in `medium` (niente `ColoredBox` nero): la scheda sfuma nello sfondo del caricamento, che è la stessa immagine della testata;
- **sostituzione di un player** (episodio successivo, player del gruppo: `pushReplacement` con `extra: playerReplacement`): resta il nero sotto la transizione, perché la pagina sotto non è quella di partenza;
```

- [ ] **Step 7: verifica.**

Run: `flutter test test/app/router_test.dart test/features/player/ test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 8: commit.**

```bash
git add lib/app/navigation.dart lib/app/router.dart lib/features/player/player_screen.dart lib/features/watch_party/watch_party_routing.dart docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md test/app/router_test.dart
git commit -m "feat: cross-fade into the player with motion tokens"
```

---

### Task 4: `PlayerIconButton`, `PlayPauseIcon` e comparsa dei controlli

**Files:**
- Modify (riscrittura): `lib/features/player/player_overlay.dart`
- Test: `test/features/player/player_overlay_test.dart`

- [ ] **Step 1: test che falliscono.** In `test/features/player/player_overlay_test.dart` aggiungi gli import:

```dart
import 'package:flutter/gestures.dart';
import 'package:wonderflix/app/motion.dart';
```

e, in fondo a `main()`, i test:

```dart
  Widget overlay({required bool visible}) => PlayerOverlay(
        visible: visible,
        view: const PlayerViewState(status: PlayerStatus.ready, playing: true),
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
      );

  double opacityOf(WidgetTester tester, String key) =>
      tester.widget<AnimatedOpacity>(find.byKey(Key(key))).opacity;

  double shiftOf(WidgetTester tester, String key) => tester
      .widget<AnimatedContainer>(find
          .descendant(
              of: find.byKey(Key(key)), matching: find.byType(AnimatedContainer))
          .first)
      .transform!
      .getTranslation()
      .y;

  testWidgets('controlli nascosti: sfumano e scivolano verso i bordi',
      (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, value, _) => overlay(visible: value),
        ),
      ),
      motion: MotionLevel.full,
    );
    expect(opacityOf(tester, 'player-controls-top'), 1);
    expect(shiftOf(tester, 'player-controls-top'), 0);

    visible.value = false;
    await tester.pump();
    expect(opacityOf(tester, 'player-controls-top'), 0);
    expect(opacityOf(tester, 'player-controls-bottom'), 0);
    expect(shiftOf(tester, 'player-controls-top'), -PlayerOverlay.hiddenShift);
    expect(shiftOf(tester, 'player-controls-bottom'), PlayerOverlay.hiddenShift);
    await tester.pumpAndSettle();
  });

  testWidgets('animazioni ridotte: i controlli sfumano senza spostarsi',
      (tester) async {
    await pumpApp(tester, Scaffold(body: overlay(visible: false)));
    expect(opacityOf(tester, 'player-controls-bottom'), 0);
    expect(shiftOf(tester, 'player-controls-bottom'), 0);
  });

  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    return gesture;
  }

  double scaleOf(WidgetTester tester) => tester
      .widget<AnimatedScale>(find.descendant(
          of: find.byType(PlayerIconButton),
          matching: find.byType(AnimatedScale)))
      .scale;

  List<BoxShadow>? glowOf(WidgetTester tester) => (tester
          .widget<AnimatedContainer>(find.byKey(const Key('player-button-glow')))
          .decoration! as BoxDecoration)
      .boxShadow;

  Widget captionsButton() => Scaffold(
        body: Center(
          child: PlayerIconButton(
            icon: const Icon(LucideIcons.captions),
            tooltip: 'Audio e sottotitoli',
            onPressed: () {},
          ),
        ),
      );

  testWidgets('pulsante: alone oro e scala 1,08 al passaggio del mouse',
      (tester) async {
    await pumpApp(tester, captionsButton(), motion: MotionLevel.full);
    expect(scaleOf(tester), 1);
    expect(glowOf(tester), isEmpty);
    await hover(tester, find.byType(PlayerIconButton));
    expect(scaleOf(tester), 1.08);
    expect(glowOf(tester), isNotEmpty);
  });

  testWidgets('pulsante: animazioni ridotte, alone senza scala',
      (tester) async {
    await pumpApp(tester, captionsButton());
    await hover(tester, find.byType(PlayerIconButton));
    expect(scaleOf(tester), 1);
    expect(glowOf(tester), isNotEmpty);
  });

  testWidgets('play/pausa: l\'icona cambia sfumando', (tester) async {
    final playing = ValueNotifier(true);
    addTearDown(playing.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: playing,
          builder: (context, value, _) => PlayPauseIcon(playing: value),
        ),
      ),
    );
    expect(find.byIcon(LucideIcons.pause), findsOneWidget);
    playing.value = false;
    await tester.pump();
    expect(find.byIcon(LucideIcons.play), findsOneWidget);
    expect(find.byIcon(LucideIcons.pause), findsOneWidget,
        reason: 'la vecchia sta ancora sfumando');
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.pause), findsNothing);
  });
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/player_overlay_test.dart`
Expected: FAIL (`visible`, `hiddenShift`, `PlayerIconButton`, `PlayPauseIcon` non esistono).

- [ ] **Step 3: implementazione.** Sostituisci tutto `lib/features/player/player_overlay.dart` con:

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'player_commands.dart';
import 'player_controller.dart';
import 'seek_bar.dart';

/// Controlli in sovrimpressione: in alto indietro e titolo, in basso barra
/// di avanzamento e comandi. A controlli nascosti ([visible] `false`) la
/// parte alta sale e la bassa scende mentre sfumano (spec D §7.1).
class PlayerOverlay extends StatelessWidget {
  const PlayerOverlay({
    super.key,
    required this.view,
    required this.engine,
    required this.fullscreen,
    required this.onBack,
    required this.onTogglePlay,
    required this.onSeekBy,
    required this.onSeekTo,
    required this.onVolume,
    required this.onToggleMute,
    required this.onToggleTracks,
    required this.onToggleFullscreen,
    this.visible = true,
    this.onNextEpisode,
    this.chapters = const [],
    this.preview,
    this.partyBadge,
    this.onWatchTogether,
  });

  final PlayerViewState view;
  final VideoEngine engine;
  final bool fullscreen;
  final VoidCallback onBack;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekBy;
  final ValueChanged<Duration> onSeekTo;
  final ValueChanged<double> onVolume;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleTracks;
  final VoidCallback onToggleFullscreen;

  /// Controlli mostrati.
  final bool visible;

  /// `null` se non c'è un episodio successivo.
  final VoidCallback? onNextEpisode;
  final List<ChapterMark> chapters;
  final Widget? Function(Duration position)? preview;

  /// Distintivo del watch party, in alto a destra; `null` fuori dal gruppo.
  final Widget? partyBadge;

  /// "Guarda insieme" (solo da soli e con il permesso); `null` = nessun
  /// pulsante.
  final VoidCallback? onWatchTogether;

  /// Di quanto la parte alta sale e la bassa scende a controlli nascosti.
  static const hiddenShift = 24.0;

  /// Parte alta o bassa: sfuma e scivola verso il suo bordo. Entrata
  /// `medium`, uscita `fast`; con le animazioni ridotte solo dissolvenza.
  Widget _part(BuildContext context,
      {required Key key, required bool top, required Widget child}) {
    final motion = WfMotion.of(context);
    final duration =
        visible ? motion.duration(WfMotion.medium) : WfMotion.fast;
    final curve = visible ? WfMotion.emphasized : WfMotion.accelerate;
    final shift = visible || motion.isReduced
        ? 0.0
        : (top ? -hiddenShift : hiddenShift);
    return AnimatedOpacity(
      key: key,
      opacity: visible ? 1 : 0,
      duration: duration,
      curve: curve,
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        transform: Matrix4.translationValues(0, shift, 0),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = view.item;
    final episode = item != null && item.kind == ItemKind.episode
        ? cardSubtitle(item)
        : null;
    final volume = view.muted ? 0.0 : view.volume;

    return IconButtonTheme(
      data: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: WfColors.cream)),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _part(
              context,
              key: const Key('player-controls-top'),
              top: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      WfColors.bg.withValues(alpha: 0.8),
                      WfColors.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 24, 48),
                  child: Row(
                    children: [
                      PlayerIconButton(
                        icon: const Icon(LucideIcons.arrowLeft),
                        tooltip: l.navBack,
                        onPressed: onBack,
                      ),
                      const SizedBox(width: 8),
                      if (item != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(cardTitle(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WfText.display(28)),
                              if (episode != null)
                                Text(episode,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: WfColors.creamMuted)),
                            ],
                          ),
                        ),
                      if (partyBadge != null) ...[
                        if (item == null) const Spacer(),
                        const SizedBox(width: 16),
                        partyBadge!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _part(
              context,
              key: const Key('player-controls-bottom'),
              top: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      WfColors.bg.withValues(alpha: 0.9),
                      WfColors.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SeekBar(
                        engine: engine,
                        onSeek: onSeekTo,
                        chapters: chapters,
                        preview: preview,
                      ),
                      Row(
                        children: [
                          PlayerIconButton(
                            icon: const Icon(LucideIcons.rewind),
                            tooltip: l.playerRewind,
                            onPressed: () => onSeekBy(-seekStep),
                          ),
                          PlayerIconButton(
                            iconSize: 34,
                            icon: PlayPauseIcon(playing: view.playing),
                            tooltip:
                                view.playing ? l.playerPause : l.actionPlay,
                            onPressed: onTogglePlay,
                          ),
                          PlayerIconButton(
                            icon: const Icon(LucideIcons.fastForward),
                            tooltip: l.playerForward,
                            onPressed: () => onSeekBy(seekStep),
                          ),
                          const SizedBox(width: 8),
                          PlayerIconButton(
                            icon: Icon(volume == 0
                                ? LucideIcons.volumeX
                                : LucideIcons.volume2),
                            tooltip:
                                view.muted ? l.playerUnmute : l.playerMute,
                            onPressed: onToggleMute,
                          ),
                          SizedBox(
                            width: 120,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: WfColors.cream,
                                inactiveTrackColor:
                                    WfColors.cream.withValues(alpha: 0.2),
                                thumbColor: WfColors.cream,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                              ),
                              child: Slider(
                                key: const Key('volume-slider'),
                                value: volume,
                                max: 100,
                                onChanged: onVolume,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TimeLabel(engine: engine),
                          const Spacer(),
                          if (onNextEpisode != null)
                            PlayerIconButton(
                              icon: const Icon(LucideIcons.skipForward),
                              tooltip: l.playerNextEpisode,
                              onPressed: onNextEpisode,
                            ),
                          if (onWatchTogether != null)
                            PlayerIconButton(
                              icon: const Icon(LucideIcons.users),
                              tooltip: l.watchPartyWatchTogether,
                              onPressed: onWatchTogether,
                            ),
                          PlayerIconButton(
                            icon: const Icon(LucideIcons.captions),
                            tooltip: l.playerAudioAndSubtitles,
                            onPressed: onToggleTracks,
                          ),
                          PlayerIconButton(
                            icon: Icon(fullscreen
                                ? LucideIcons.minimize
                                : LucideIcons.maximize),
                            tooltip: fullscreen
                                ? l.playerExitFullscreen
                                : l.playerFullscreen,
                            onPressed: onToggleFullscreen,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icona dei controlli del player con il linguaggio di `WfButton` (spec D
/// §7.2): al passaggio fondo crema tenue, alone oro e scala 1,08; premuta,
/// 0,97. Con le animazioni ridotte niente scala.
class PlayerIconButton extends StatefulWidget {
  const PlayerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 24,
  });

  /// Di solito un `Icon`; play/pausa passa un [PlayPauseIcon].
  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;

  @override
  State<PlayerIconButton> createState() => _PlayerIconButtonState();
}

class _PlayerIconButtonState extends State<PlayerIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final enabled = widget.onPressed != null;
    final hovered = enabled && _hovered;
    final scale = !enabled || motion.isReduced
        ? 1.0
        : _pressed
            ? 0.97
            : hovered
                ? 1.08
                : 1.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: WfMotion.fast,
          curve: WfMotion.emphasized,
          child: AnimatedContainer(
            key: const Key('player-button-glow'),
            duration: WfMotion.fast,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: hovered
                  ? [
                      BoxShadow(
                          color: WfColors.gold.withValues(alpha: 0.35),
                          blurRadius: 16),
                    ]
                  : const [],
            ),
            child: IconButton(
              icon: widget.icon,
              iconSize: widget.iconSize,
              tooltip: widget.tooltip,
              onPressed: widget.onPressed,
              color: WfColors.cream,
              // Spec D §7.2: fondo crema al 12% al passaggio.
              hoverColor: WfColors.cream.withValues(alpha: 0.12),
            ),
          ),
        ),
      ),
    );
  }
}

/// Play/pausa: l'icona cambia con una breve dissolvenza in scala (con le
/// animazioni ridotte solo dissolvenza).
class PlayPauseIcon extends StatelessWidget {
  const PlayPauseIcon({super.key, required this.playing});

  final bool playing;

  /// Scala da cui cresce l'icona nuova.
  static const _fromScale = 0.6;

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    return AnimatedSwitcher(
      duration: WfMotion.fast,
      transitionBuilder: (child, animation) => reduced
          ? FadeTransition(opacity: animation, child: child)
          : ScaleTransition(
              scale: Tween<double>(begin: _fromScale, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: WfMotion.emphasized)),
              child: FadeTransition(opacity: animation, child: child),
            ),
      child: Icon(playing ? LucideIcons.pause : LucideIcons.play,
          key: ValueKey(playing)),
    );
  }
}
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/player_overlay_test.dart test/features/player/player_screen_test.dart`
Expected: PASS (in `player_screen_test` la chiave `player-controls` esiste ancora: la toglie il Task 5). Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/player_overlay.dart test/features/player/player_overlay_test.dart
git commit -m "feat: animate the player controls and buttons"
```

---

### Task 5: `PlayerScreen` con il controller; i tasti non mostrano i controlli

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_screen_test.dart`

- [ ] **Step 1: test che fallisce.** In `test/features/player/player_screen_test.dart` aggiungi l'import `import 'package:wonderflix/features/player/player_chrome.dart';`, sostituisci l'helper

```dart
  double controlsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('player-controls')))
      .opacity;
```

con

```dart
  double controlsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('player-controls-bottom')))
      .opacity;
```

e, subito dopo il test `'controlli nascosti dopo 3 s, di nuovo visibili col mouse'`, aggiungi:

```dart
  testWidgets('i tasti non mostrano i controlli', (tester) async {
    await pumpPlayer(tester);
    await tester.pump(PlayerChromeController.hideDelay);
    await tester.pumpAndSettle();
    expect(controlsOpacity(tester), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(engine.seeks.last, const Duration(seconds: 10));
    expect(controlsOpacity(tester), 0);
    await unmount(tester);
  });
```

- [ ] **Step 2: verifica che fallisca.**

Run: `flutter test test/features/player/player_screen_test.dart`
Expected: FAIL (il nuovo test: dopo → i controlli tornano visibili; prima ancora, la chiave `player-controls-bottom` sta dentro un `AnimatedOpacity` esterno che ha ancora opacità propria).

- [ ] **Step 3: collega il controller.** In `lib/features/player/player_screen.dart`:

1. Aggiungi l'import `import 'player_chrome.dart';` dopo `import 'player_active.dart';`.

2. Togli da `PlayerScreen`:

```dart
  /// Inattività del mouse dopo cui i controlli spariscono.
  static const hideDelay = Duration(seconds: 3);

```

3. Sostituisci

```dart
  late final PlayerWindow _window;
  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _tracksOpen = false;
  late bool _fullscreen = widget.fullscreen;
```

con

```dart
  late final PlayerWindow _window;

  /// Controlli, pannello e riscontro dei tasti (spec D §5.1).
  final _chrome = PlayerChromeController();
  late bool _fullscreen = widget.fullscreen;
```

4. In `initState` sostituisci

```dart
    _timelineTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendTimeline());
    _scheduleHide();
  }
```

con

```dart
    _timelineTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendTimeline());
    _chrome.addListener(_onChromeChanged);
  }
```

5. In `dispose` sostituisci

```dart
    _hideTimer?.cancel();
    _window.removeCloseListener(_onWindowClose);
```

con

```dart
    _chrome
      ..removeListener(_onChromeChanged)
      ..dispose();
    _window.removeCloseListener(_onWindowClose);
```

6. Sostituisci i tre metodi

```dart
  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  /// I controlli si nascondono solo durante la riproduzione e a pannello
  /// chiuso.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(PlayerScreen.hideDelay, () {
      if (!mounted || _tracksOpen) return;
      if (!ref.read(playerControllerProvider(widget.args)).playing) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleTracks() {
    setState(() => _tracksOpen = !_tracksOpen);
    _showControls();
  }
```

con

```dart
  void _onChromeChanged() {
    if (mounted) setState(() {});
  }
```

7. In `_escape` sostituisci

```dart
    if (_tracksOpen) {
      setState(() => _tracksOpen = false);
    } else if (_fullscreen) {
```

con

```dart
    if (_chrome.panelOpen) {
      _chrome.closePanel();
    } else if (_fullscreen) {
```

8. In fondo a `_run` sostituisci

```dart
      case PlayerCommand.exit:
        _exit();
        return;
    }
    _showControls();
  }
```

con

```dart
      case PlayerCommand.exit:
        _exit();
        return;
    }
  }
```

9. In `build` sostituisci

```dart
    ref.listen(provider.select((s) => s.playing), (_, playing) {
      if (playing) _scheduleHide();
      unawaited(_mediaSession.setPlaying(playing));
    });
```

con

```dart
    ref.listen(provider.select((s) => s.playing), (_, playing) {
      _chrome.setPlaying(playing);
      unawaited(_mediaSession.setPlaying(playing));
    });
```

10. Sostituisci

```dart
          child: MouseRegion(
            cursor: _controlsVisible
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onHover: (_) => _showControls(),
```

con

```dart
          child: MouseRegion(
            cursor: _chrome.controlsVisible
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onHover: (_) => _chrome.pointerActivity(),
```

11. Sostituisci

```dart
                  onTap: () {
                    if (_tracksOpen) {
                      setState(() => _tracksOpen = false);
                    } else {
```

con

```dart
                  onTap: () {
                    if (_chrome.panelOpen) {
                      _chrome.closePanel();
                    } else {
```

12. Sostituisci il blocco dei controlli

```dart
                  ExcludeFocus(
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: AnimatedOpacity(
                        key: const Key('player-controls'),
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: PlayerOverlay(
                          view: view,
                          engine: controller.engine,
                          fullscreen: _fullscreen,
                          onBack: _exit,
                          onTogglePlay: () =>
                              unawaited(controller.togglePlay()),
                          onSeekBy: (offset) =>
                              unawaited(controller.seekBy(offset)),
                          onSeekTo: (position) =>
                              unawaited(controller.seekTo(position)),
                          onVolume: (volume) =>
                              unawaited(controller.setVolume(volume)),
                          onToggleMute: () =>
                              unawaited(controller.toggleMute()),
                          onToggleTracks: _toggleTracks,
                          onToggleFullscreen: () =>
                              unawaited(_toggleFullscreen()),
                          onNextEpisode: _inParty
                              ? (party != null && party.hasNext
                                  ? _playNext
                                  : null)
                              : (next == null ? null : _playNext),
                          chapters: view.item?.chapters ?? const [],
                          preview: _previewFor(view),
                          partyBadge: party != null && party.inGroup
                              ? PartyBadge(onLeave: _exit)
                              : null,
                          onWatchTogether: canWatchTogether
                              ? () => unawaited(_watchTogether())
                              : null,
                        ),
                      ),
                    ),
                  ),
```

con

```dart
                  ExcludeFocus(
                    child: IgnorePointer(
                      ignoring: !_chrome.controlsVisible,
                      child: PlayerOverlay(
                        visible: _chrome.controlsVisible,
                        view: view,
                        engine: controller.engine,
                        fullscreen: _fullscreen,
                        onBack: _exit,
                        onTogglePlay: () => unawaited(controller.togglePlay()),
                        onSeekBy: (offset) =>
                            unawaited(controller.seekBy(offset)),
                        onSeekTo: (position) =>
                            unawaited(controller.seekTo(position)),
                        onVolume: (volume) =>
                            unawaited(controller.setVolume(volume)),
                        onToggleMute: () => unawaited(controller.toggleMute()),
                        onToggleTracks: _chrome.togglePanel,
                        onToggleFullscreen: () =>
                            unawaited(_toggleFullscreen()),
                        onNextEpisode: _inParty
                            ? (party != null && party.hasNext
                                ? _playNext
                                : null)
                            : (next == null ? null : _playNext),
                        chapters: view.item?.chapters ?? const [],
                        preview: _previewFor(view),
                        partyBadge: party != null && party.inGroup
                            ? PartyBadge(onLeave: _exit)
                            : null,
                        onWatchTogether: canWatchTogether
                            ? () => unawaited(_watchTogether())
                            : null,
                      ),
                    ),
                  ),
```

13. Sostituisci `if (_tracksOpen && view.plan != null)` con `if (_chrome.panelOpen && view.plan != null)`.

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/ test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` (nessun `_hideTimer`/`_tracksOpen`/`_showControls` rimasto) e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
git commit -m "feat: drive the player controls from the chrome controller"
```

---

### Task 6: segmenti e zone della barra (funzioni pure)

**Files:**
- Create: `lib/features/player/seek_segments.dart`
- Test: `test/features/player/seek_segments_test.dart`

- [ ] **Step 1: test che fallisce.** Crea `test/features/player/seek_segments_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/seek_segments.dart';

void main() {
  const hour = Duration(hours: 1);
  const twoHours = Duration(hours: 2);

  group('seekSegments', () {
    test('senza capitoli: una barra sola', () {
      expect(seekSegments(const [], twoHours, 1000),
          const [SeekSegment(Duration.zero, twoHours)]);
    });

    test('un tratto per capitolo; quello all\'inizio non ne apre un altro',
        () {
      expect(
        seekSegments(const [
          ChapterMark(start: Duration.zero, name: 'Inizio'),
          ChapterMark(start: Duration(minutes: 30), name: 'Arrakis'),
          ChapterMark(start: hour, name: 'Deserto'),
        ], twoHours, 1000),
        const [
          SeekSegment(Duration.zero, Duration(minutes: 30)),
          SeekSegment(Duration(minutes: 30), hour),
          SeekSegment(hour, twoHours),
        ],
      );
    });

    test('tratti più corti di 8 px: uniti al precedente', () {
      // 1000 px per 100 min: 1 min = 10 px, 30 s = 5 px.
      expect(
        seekSegments(const [
          ChapterMark(start: Duration(minutes: 10)),
          ChapterMark(start: Duration(minutes: 40)),
          ChapterMark(start: Duration(minutes: 40, seconds: 30)),
        ], const Duration(minutes: 100), 1000),
        const [
          SeekSegment(Duration.zero, Duration(minutes: 10)),
          SeekSegment(Duration(minutes: 10), Duration(minutes: 40, seconds: 30)),
          SeekSegment(
              Duration(minutes: 40, seconds: 30), Duration(minutes: 100)),
        ],
      );
    });

    test('primo tratto troppo corto: unito al successivo', () {
      expect(
        seekSegments(const [
          ChapterMark(start: Duration(seconds: 20)),
          ChapterMark(start: Duration(minutes: 50)),
        ], const Duration(minutes: 100), 1000),
        const [
          SeekSegment(Duration.zero, Duration(minutes: 50)),
          SeekSegment(Duration(minutes: 50), Duration(minutes: 100)),
        ],
      );
    });

    test('capitoli fuori ordine, doppi o oltre la fine', () {
      expect(
        seekSegments(const [
          ChapterMark(start: hour),
          ChapterMark(start: Duration(minutes: 30)),
          ChapterMark(start: Duration(minutes: 30)),
          ChapterMark(start: Duration(hours: 3)),
        ], twoHours, 1000),
        const [
          SeekSegment(Duration.zero, Duration(minutes: 30)),
          SeekSegment(Duration(minutes: 30), hour),
          SeekSegment(hour, twoHours),
        ],
      );
    });

    test('durata non ancora nota: una barra sola', () {
      expect(
          seekSegments(const [ChapterMark(start: hour)], Duration.zero, 1000),
          const [SeekSegment(Duration.zero, Duration.zero)]);
    });
  });

  group('zone', () {
    const segments = [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 55),
          end: Duration(seconds: 130)),
      MediaSegment(
          type: MediaSegmentType.commercial,
          start: Duration(minutes: 10),
          end: Duration(minutes: 11)),
      MediaSegment(
          type: MediaSegmentType.recap,
          start: Duration.zero,
          end: Duration(seconds: 55)),
      MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration(minutes: 44),
          end: Duration(minutes: 46)),
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(minutes: 20),
          end: Duration(minutes: 20)),
    ];

    test('solo riassunto, intro e titoli di coda, non vuote', () {
      expect(seekZones(segments), const [
        SeekZone(SeekZoneKind.intro, Duration(seconds: 55),
            Duration(seconds: 130)),
        SeekZone(SeekZoneKind.recap, Duration.zero, Duration(seconds: 55)),
        SeekZone(SeekZoneKind.outro, Duration(minutes: 44),
            Duration(minutes: 46)),
      ]);
    });

    test('zoneAt: inizio compreso, fine esclusa', () {
      final zones = seekZones(segments);
      expect(zoneAt(zones, Duration.zero)?.kind, SeekZoneKind.recap);
      expect(zoneAt(zones, const Duration(seconds: 55))?.kind,
          SeekZoneKind.intro);
      expect(zoneAt(zones, const Duration(seconds: 130)), isNull);
      expect(zoneAt(zones, const Duration(minutes: 10, seconds: 30)), isNull);
    });
  });
}
```

- [ ] **Step 2: verifica che fallisca.**

Run: `flutter test test/features/player/seek_segments_test.dart`
Expected: FAIL (file `seek_segments.dart` inesistente).

- [ ] **Step 3: implementazione.** Crea `lib/features/player/seek_segments.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/playback_models.dart';

/// Spazio tra due tratti della barra (spec D §8.1).
const seekSegmentGap = 3.0;

/// Un tratto più corto di così, sullo schermo, si unisce al precedente.
const seekSegmentMinWidth = 8.0;

/// Un tratto della barra: un capitolo (o più, uniti) o tutta la barra.
@immutable
class SeekSegment {
  const SeekSegment(this.start, this.end);

  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) =>
      other is SeekSegment && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SeekSegment($start, $end)';
}

/// Tratti della barra per [chapters] su una traccia larga [trackWidth] px
/// (spec D §8.1): un tratto per capitolo; i tratti più corti di
/// [seekSegmentMinWidth] si uniscono al precedente (il primo al
/// successivo). Senza durata o capitoli: un tratto solo.
List<SeekSegment> seekSegments(
    List<ChapterMark> chapters, Duration duration, double trackWidth) {
  if (duration <= Duration.zero) return [SeekSegment(Duration.zero, duration)];
  final starts = {
    for (final chapter in chapters)
      if (chapter.start > Duration.zero && chapter.start < duration)
        chapter.start,
  }.toList()
    ..sort();
  final bounds = [Duration.zero, ...starts, duration];
  double width(SeekSegment segment) =>
      (segment.end - segment.start).inMicroseconds /
      duration.inMicroseconds *
      trackWidth;
  final merged = <SeekSegment>[];
  for (var i = 0; i + 1 < bounds.length; i++) {
    final segment = SeekSegment(bounds[i], bounds[i + 1]);
    if (merged.isNotEmpty && width(segment) < seekSegmentMinWidth) {
      merged.last = SeekSegment(merged.last.start, segment.end);
    } else {
      merged.add(segment);
    }
  }
  // Il primo non ha un precedente: se è troppo corto va con il successivo.
  if (merged.length > 1 && width(merged.first) < seekSegmentMinWidth) {
    merged.replaceRange(
        0, 2, [SeekSegment(merged[0].start, merged[1].end)]);
  }
  return merged;
}

/// Parti che Jellyfin conosce e che la barra mostra rigate (spec D §8.3).
enum SeekZoneKind { recap, intro, outro }

@immutable
class SeekZone {
  const SeekZone(this.kind, this.start, this.end);

  final SeekZoneKind kind;
  final Duration start;
  final Duration end;

  /// Inizio compreso, fine esclusa.
  bool contains(Duration position) => position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      other is SeekZone &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => 'SeekZone($kind, $start, $end)';
}

/// Zone della barra dai segmenti di Jellyfin: solo `Recap`, `Intro` e
/// `Outro`, e solo se non vuote.
List<SeekZone> seekZones(List<MediaSegment> segments) {
  final zones = <SeekZone>[];
  for (final segment in segments) {
    final kind = switch (segment.type) {
      MediaSegmentType.recap => SeekZoneKind.recap,
      MediaSegmentType.intro => SeekZoneKind.intro,
      MediaSegmentType.outro => SeekZoneKind.outro,
      _ => null,
    };
    if (kind != null && segment.end > segment.start) {
      zones.add(SeekZone(kind, segment.start, segment.end));
    }
  }
  return zones;
}

/// Zona in cui cade [position]; `null` = nessuna.
SeekZone? zoneAt(List<SeekZone> zones, Duration position) {
  for (final zone in zones) {
    if (zone.contains(position)) return zone;
  }
  return null;
}
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/seek_segments_test.dart`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/seek_segments.dart test/features/player/seek_segments_test.dart
git commit -m "feat: compute seek bar segments and zones"
```

---

### Task 7: nuova `SeekBar`

**Files:**
- Modify (riscrittura): `lib/features/player/seek_bar.dart`
- Modify: `lib/features/player/player_overlay.dart`
- Test (riscrittura): `test/features/player/seek_bar_test.dart`

- [ ] **Step 1: test che falliscono.** Sostituisci tutto `test/features/player/seek_bar_test.dart` con:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/seek_bar.dart';
import 'package:wonderflix/features/player/seek_segments.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  const chapters = [
    ChapterMark(start: Duration.zero, name: 'Inizio'),
    ChapterMark(start: Duration(hours: 1), name: 'Arrakis'),
  ];

  SeekBarPainter painter(WidgetTester tester) =>
      tester.widget<CustomPaint>(find.byKey(const Key('seek-bar-paint'))).painter!
          as SeekBarPainter;

  /// Punto della traccia a [fraction] (la traccia inizia dopo il margine).
  Offset at(WidgetTester tester, double fraction) {
    final bar = tester.getRect(find.byType(SeekBar));
    final track = bar.width - 2 * SeekBar.trackInset;
    return Offset(bar.left + SeekBar.trackInset + fraction * track,
        bar.center.dy);
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  Future<void> pumpBar(
    WidgetTester tester,
    FakeVideoEngine engine, {
    ValueChanged<Duration>? onSeek,
    List<ChapterMark> chapters = const [],
    List<SeekZone> zones = const [],
    Widget? Function(Duration)? preview,
    MotionLevel motion = MotionLevel.reduced,
  }) =>
      pumpApp(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(40, 300, 40, 40),
            child: Align(
              alignment: Alignment.topCenter,
              child: SeekBar(
                engine: engine,
                onSeek: onSeek ?? (_) {},
                chapters: chapters,
                zones: zones,
                preview: preview,
              ),
            ),
          ),
        ),
        motion: motion,
      );

  testWidgets('posizione, parte scaricata e salto con un clic', (tester) async {
    final engine = FakeVideoEngine();
    Duration? seeked;
    await pumpBar(tester, engine, onSeek: (p) => seeked = p);
    engine
      ..emitDuration(const Duration(hours: 2))
      ..emitPosition(const Duration(minutes: 30))
      ..emitBuffer(const Duration(minutes: 45));
    await tester.pump(); // consegna gli eventi degli stream
    await tester.pump();

    expect(painter(tester).duration, const Duration(hours: 2));
    expect(painter(tester).position, const Duration(minutes: 30));
    expect(painter(tester).buffer, const Duration(minutes: 45));

    await tester.tap(find.byType(SeekBar));
    await tester.pump();
    expect(seeked!.inSeconds, closeTo(3600, 5));
  });

  testWidgets('tempo trascorso e totale', (tester) async {
    final engine = FakeVideoEngine();
    await pumpApp(tester, Scaffold(body: TimeLabel(engine: engine)));
    engine
      ..emitDuration(const Duration(hours: 1, minutes: 45))
      ..emitPosition(const Duration(minutes: 12, seconds: 3));
    await tester.pump(); // consegna gli eventi degli stream
    await tester.pump();
    expect(find.text('12:03 / 1:45:00'), findsOneWidget);
  });

  testWidgets('un tratto per capitolo, le zone passano al disegno',
      (tester) async {
    const zones = [
      SeekZone(SeekZoneKind.intro, Duration(minutes: 1), Duration(minutes: 2)),
    ];
    await pumpBar(tester, FakeVideoEngine(), chapters: const [
      ChapterMark(start: Duration.zero, name: 'Inizio'),
      ChapterMark(start: Duration(minutes: 30), name: 'Arrakis'),
      ChapterMark(start: Duration(hours: 1), name: 'Deserto'),
    ], zones: zones);
    expect(painter(tester).segments, const [
      SeekSegment(Duration.zero, Duration(minutes: 30)),
      SeekSegment(Duration(minutes: 30), Duration(hours: 1)),
      SeekSegment(Duration(hours: 1), Duration(hours: 2)),
    ]);
    expect(painter(tester).zones, zones);
  });

  testWidgets('anteprima al passaggio del mouse: tempo, capitolo, immagine',
      (tester) async {
    final previews = <Duration>[];
    await pumpBar(tester, FakeVideoEngine(), chapters: chapters,
        preview: (position) {
      previews.add(position);
      return const SizedBox(key: Key('preview-image'), width: 240, height: 135);
    });
    final gesture = await mouse(tester);
    await gesture.moveTo(at(tester, 0.5));
    await tester.pump();
    expect(find.text('1:00:00 · Arrakis'), findsOneWidget);
    expect(find.byKey(const Key('preview-image')), findsOneWidget);
    expect(previews.last, const Duration(hours: 1));

    await gesture.moveTo(at(tester, 0.25));
    await tester.pump();
    expect(find.text('30:00 · Inizio'), findsOneWidget);
    expect(previews.last, const Duration(minutes: 30));

    // L'anteprima sfuma; finita la dissolvenza esce dall'albero.
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.textContaining('· Inizio'), findsNothing);
  });

  testWidgets('anteprima in una zona: etichetta oro con il nome',
      (tester) async {
    await pumpBar(tester, FakeVideoEngine(), chapters: chapters, zones: const [
      SeekZone(SeekZoneKind.outro, Duration(minutes: 90), Duration(hours: 2)),
    ]);
    final gesture = await mouse(tester);
    await gesture.moveTo(at(tester, 0.25));
    await tester.pump();
    expect(find.byKey(const Key('seek-zone-tag')), findsNothing);

    await gesture.moveTo(at(tester, 0.9));
    await tester.pump();
    expect(find.byKey(const Key('seek-zone-tag')), findsOneWidget);
    expect(find.text('Titoli di coda'), findsOneWidget);
  });

  testWidgets('mouse sopra: barra più alta, tratto sotto il mouse di più, '
      'cursore', (tester) async {
    await pumpBar(tester, FakeVideoEngine(),
        chapters: chapters, motion: MotionLevel.full);
    expect(painter(tester).hover, 0);
    expect(painter(tester).thumb, 0);

    final gesture = await mouse(tester);
    await gesture.moveTo(at(tester, 0.25));
    await tester.pump();
    await tester.pump(WfMotion.fast);
    expect(painter(tester).hover, 1);
    expect(painter(tester).hoveredSegment, 0);
    expect(painter(tester).emphasis, 1);
    expect(painter(tester).thumb, closeTo(1, 0.001));

    await gesture.moveTo(at(tester, 0.75));
    await tester.pump();
    expect(painter(tester).hoveredSegment, 1);

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(WfMotion.fast);
    expect(painter(tester).hover, 0);
    expect(painter(tester).hoveredSegment, isNull);
    expect(painter(tester).thumb, closeTo(0, 0.001));
    await tester.pumpAndSettle();
  });

  testWidgets('trascinamento: l\'anteprima segue, un solo salto alla fine',
      (tester) async {
    final seeks = <Duration>[];
    await pumpBar(tester, FakeVideoEngine(),
        onSeek: seeks.add,
        chapters: chapters,
        preview: (_) => const SizedBox(key: Key('preview-image'), width: 240));
    final gesture = await tester.startGesture(at(tester, 0.25));
    await gesture.moveTo(at(tester, 0.4));
    await tester.pump();
    expect(find.byKey(const Key('preview-image')), findsOneWidget);
    expect(seeks, isEmpty);
    expect(painter(tester).position.inMinutes, closeTo(48, 1),
        reason: 'durante il trascinamento la barra segue il dito');

    await gesture.moveTo(at(tester, 0.5));
    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single.inSeconds, closeTo(3600, 5));
    await tester.pumpAndSettle();
  });

  test('chapterAt', () {
    const marks = [
      ChapterMark(start: Duration.zero, name: 'A'),
      ChapterMark(start: Duration(minutes: 10), name: 'B'),
    ];
    expect(chapterAt(marks, const Duration(minutes: 5))?.name, 'A');
    expect(chapterAt(marks, const Duration(minutes: 10))?.name, 'B');
    expect(chapterAt(const [], Duration.zero), isNull);
  });
}
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/seek_bar_test.dart`
Expected: FAIL (`SeekBarPainter`, `zones`, chiave `seek-bar-paint` non esistono).

- [ ] **Step 3: implementazione.** Sostituisci tutto `lib/features/player/seek_bar.dart` con:

```dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'seek_segments.dart';

/// Capitolo in corso in [position] (l'ultimo iniziato).
ChapterMark? chapterAt(List<ChapterMark> chapters, Duration position) {
  ChapterMark? current;
  for (final chapter in chapters) {
    if (chapter.start <= position) current = chapter;
  }
  return current;
}

/// Nome della zona nell'anteprima della barra.
String seekZoneLabel(AppLocalizations l, SeekZoneKind kind) => switch (kind) {
      SeekZoneKind.recap => l.playerSegmentRecap,
      SeekZoneKind.intro => l.playerSegmentIntro,
      SeekZoneKind.outro => l.playerSegmentOutro,
    };

/// Disegno della barra (spec D §8): tratti per capitolo, parte scaricata e
/// vista, zone rigate, cursore.
class SeekBarPainter extends CustomPainter {
  SeekBarPainter({
    required this.segments,
    required this.zones,
    required this.duration,
    required this.position,
    required this.buffer,
    required this.hover,
    required this.hoveredSegment,
    required this.emphasis,
    required this.thumb,
  });

  final List<SeekSegment> segments;
  final List<SeekZone> zones;
  final Duration duration;
  final Duration position;
  final Duration buffer;

  /// 0 = a riposo, 1 = mouse sulla barra.
  final double hover;

  /// Tratto sotto il mouse (`null` = nessuno) e quanto è cresciuto (0–1).
  final int? hoveredSegment;
  final double emphasis;

  /// Scala del cursore: 0 nascosto, 1 intero (il rimbalzo può superarlo).
  final double thumb;

  /// Altezze della traccia (spec D §8.2).
  static const restHeight = 4.0;
  static const hoverHeight = 6.0;
  static const hoveredSegmentHeight = 9.0;
  static const thumbRadius = 7.0;

  /// Alone del cursore oltre il suo raggio.
  static const thumbHalo = 4.0;

  /// Passo e spessore delle righe delle zone (spec D §8.3).
  static const stripeSpacing = 6.0;
  static const stripeWidth = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = SeekBar.trackInset;
    final track = math.max(size.width - 2 * inset, 1.0);
    final centerY = size.height / 2;
    final total = duration.inMicroseconds;
    final base = lerpDouble(restHeight, hoverHeight, hover)!;
    final inactive = Paint()..color = WfColors.cream.withValues(alpha: 0.15);
    if (total <= 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(inset, centerY - base / 2, inset + track,
                  centerY + base / 2),
              Radius.circular(base / 2)),
          inactive);
      return;
    }
    double x(Duration value) =>
        inset + (value.inMicroseconds / total).clamp(0.0, 1.0) * track;
    final buffered = Paint()..color = WfColors.cream.withValues(alpha: 0.35);
    final played = Paint()..color = WfColors.gold;
    final stripe = Paint()
      ..color = WfColors.bg.withValues(alpha: 0.55)
      ..strokeWidth = stripeWidth;
    final last = segments.length - 1;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final left = x(segment.start) + (i > 0 ? seekSegmentGap / 2 : 0);
      final right = x(segment.end) - (i < last ? seekSegmentGap / 2 : 0);
      if (right <= left) continue;
      final height = i == hoveredSegment
          ? lerpDouble(base, hoveredSegmentHeight, emphasis)!
          : base;
      final rect = Rect.fromLTRB(
          left, centerY - height / 2, right, centerY + height / 2);
      void fill(double end, Paint paint) {
        final clipped = math.min(right, end);
        if (clipped > left) {
          canvas.drawRect(
              Rect.fromLTRB(left, rect.top, clipped, rect.bottom), paint);
        }
      }

      canvas.save();
      canvas.clipRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(height / 2)));
      canvas.drawRect(rect, inactive);
      fill(x(buffer), buffered);
      fill(x(position), played);
      for (final zone in zones) {
        final zoneLeft = math.max(left, x(zone.start));
        final zoneRight = math.min(right, x(zone.end));
        if (zoneRight <= zoneLeft) continue;
        canvas.save();
        canvas.clipRect(
            Rect.fromLTRB(zoneLeft, rect.top, zoneRight, rect.bottom));
        // Righe diagonali: si parte abbastanza a sinistra da coprire tutta
        // l'altezza fin dal bordo della zona.
        for (var start = zoneLeft - rect.height;
            start < zoneRight;
            start += stripeSpacing) {
          canvas.drawLine(Offset(start, rect.bottom),
              Offset(start + rect.height, rect.top), stripe);
        }
        canvas.restore();
      }
      canvas.restore();
    }
    if (thumb > 0) {
      final center = Offset(x(position), centerY);
      canvas.drawCircle(center, (thumbRadius + thumbHalo) * thumb,
          Paint()..color = WfColors.gold.withValues(alpha: 0.25));
      canvas.drawCircle(center, thumbRadius * thumb, played);
    }
  }

  @override
  bool shouldRepaint(SeekBarPainter oldDelegate) =>
      !listEquals(oldDelegate.segments, segments) ||
      !listEquals(oldDelegate.zones, zones) ||
      oldDelegate.duration != duration ||
      oldDelegate.position != position ||
      oldDelegate.buffer != buffer ||
      oldDelegate.hover != hover ||
      oldDelegate.hoveredSegment != hoveredSegment ||
      oldDelegate.emphasis != emphasis ||
      oldDelegate.thumb != thumb;
}

/// Barra di avanzamento (spec D §8): tratti per capitolo, zone rigate,
/// anteprima al passaggio del mouse e durante il trascinamento, salto con
/// clic o trascinamento.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.engine,
    required this.onSeek,
    this.chapters = const [],
    this.zones = const [],
    this.preview,
  });

  final VideoEngine engine;
  final ValueChanged<Duration> onSeek;
  final List<ChapterMark> chapters;

  /// Riassunto, intro e titoli di coda (`seekZones`).
  final List<SeekZone> zones;

  /// Immagine di anteprima per una posizione (trickplay); `null` = solo il
  /// tempo.
  final Widget? Function(Duration position)? preview;

  /// Margine orizzontale della traccia: il cursore (raggio 7) non esce dalla
  /// barra.
  static const trackInset = 8.0;

  /// Altezza dell'area che risponde a mouse e clic.
  static const height = 28.0;

  static const previewWidth = 240.0;

  /// Distanza dell'anteprima dalla barra.
  static const previewGap = 6.0;

  /// Scala da cui cresce l'anteprima (spec D §8.4).
  static const previewFromScale = 0.92;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> with TickerProviderStateMixin {
  late Duration _position;
  late Duration _duration;
  late Duration _buffer;
  final _subscriptions = <StreamSubscription<Duration>>[];

  /// Larghezza e tratti dell'ultimo layout.
  double _width = 0;
  List<SeekSegment> _segments = const [];

  /// Mouse sopra la barra e trascinamento in corso: posizione x.
  double? _hoverX;
  double? _dragX;

  /// Ultima posizione dell'anteprima: resta mentre sfuma via.
  double? _previewX;
  bool _previewShown = false;
  int? _hoveredSegment;

  late final AnimationController _hover =
      AnimationController(vsync: this, duration: WfMotion.fast);
  late final AnimationController _emphasis =
      AnimationController(vsync: this, duration: WfMotion.fast);
  late final AnimationController _thumb =
      AnimationController(vsync: this, duration: WfMotion.fast);

  @override
  void initState() {
    super.initState();
    final engine = widget.engine;
    _position = engine.position;
    _duration = engine.duration;
    _buffer = engine.buffer;
    _subscriptions.addAll([
      engine.positionStream.listen((value) => setState(() => _position = value)),
      engine.durationStream.listen((value) => setState(() => _duration = value)),
      engine.bufferStream.listen((value) => setState(() => _buffer = value)),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _hover.dispose();
    _emphasis.dispose();
    _thumb.dispose();
    super.dispose();
  }

  double get _track => math.max(_width - 2 * SeekBar.trackInset, 1.0);

  Duration _positionAt(double x) {
    final fraction = ((x - SeekBar.trackInset) / _track).clamp(0.0, 1.0);
    return Duration(
        milliseconds: (fraction * _duration.inMilliseconds).round());
  }

  int? _segmentAt(double x) {
    final position = _positionAt(x);
    for (var i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final last = i == _segments.length - 1;
      if (position >= segment.start &&
          (position < segment.end || (last && position <= segment.end))) {
        return i;
      }
    }
    return null;
  }

  /// Il puntatore è su [x] (passaggio del mouse o trascinamento).
  void _pointAt(double x) {
    final index = _segmentAt(x);
    setState(() {
      _previewX = x;
      _previewShown = true;
      if (index != _hoveredSegment) {
        _hoveredSegment = index;
        _emphasis.forward(from: 0);
      }
    });
    _hover.forward();
    _thumb.forward();
  }

  /// Né mouse né trascinamento: la barra torna a riposo.
  void _release() {
    if (_hoverX != null || _dragX != null) return;
    setState(() {
      _previewShown = false;
      _hoveredSegment = null;
    });
    _hover.reverse();
    _thumb.reverse();
  }

  void _seekTo(double x) {
    final target = _positionAt(x);
    setState(() => _position = target);
    widget.onSeek(target);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    final thumbCurve = reduced ? WfMotion.standard : WfMotion.bounce;
    return LayoutBuilder(builder: (context, constraints) {
      _width = constraints.maxWidth;
      _segments = seekSegments(widget.chapters, _duration, _track);
      final drag = _dragX;
      final shown = drag == null ? _position : _positionAt(drag);
      final previewX = _previewX;
      return Semantics(
        slider: true,
        value: formatClock(shown),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (event) {
            _hoverX = event.localPosition.dx;
            _pointAt(event.localPosition.dx);
          },
          onExit: (_) {
            _hoverX = null;
            _release();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _seekTo(details.localPosition.dx),
            onHorizontalDragStart: (details) {
              _dragX = details.localPosition.dx;
              _pointAt(details.localPosition.dx);
            },
            onHorizontalDragUpdate: (details) {
              _dragX = details.localPosition.dx;
              _pointAt(details.localPosition.dx);
            },
            onHorizontalDragEnd: (_) {
              final x = _dragX;
              _dragX = null;
              if (x != null) _seekTo(x);
              _release();
            },
            onHorizontalDragCancel: () {
              _dragX = null;
              _release();
            },
            child: SizedBox(
              height: SeekBar.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_hover, _emphasis, _thumb]),
                        builder: (context, _) => CustomPaint(
                          key: const Key('seek-bar-paint'),
                          painter: SeekBarPainter(
                            segments: _segments,
                            zones: widget.zones,
                            duration: _duration,
                            position: shown,
                            buffer: _buffer,
                            hover: _hover.value,
                            hoveredSegment: _hoveredSegment,
                            emphasis: _emphasis.value,
                            thumb: thumbCurve.transform(_thumb.value),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (previewX != null && _duration > Duration.zero)
                    Positioned(
                      left: (previewX - SeekBar.previewWidth / 2).clamp(
                          0.0, math.max(_width - SeekBar.previewWidth, 0.0)),
                      bottom: SeekBar.height + SeekBar.previewGap,
                      width: SeekBar.previewWidth,
                      child: IgnorePointer(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: _previewShown ? 1 : 0),
                          duration: WfMotion.fast,
                          curve: WfMotion.emphasized,
                          onEnd: () {
                            if (!_previewShown && mounted) {
                              setState(() => _previewX = null);
                            }
                          },
                          builder: (context, t, child) => Opacity(
                            opacity: t.clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: reduced
                                  ? 1
                                  : lerpDouble(SeekBar.previewFromScale, 1, t)!,
                              alignment: Alignment.bottomCenter,
                              child: child,
                            ),
                          ),
                          child: _SeekPreview(
                            position: _positionAt(previewX),
                            chapter:
                                chapterAt(widget.chapters, _positionAt(previewX)),
                            zone: zoneAt(widget.zones, _positionAt(previewX)),
                            image: widget.preview?.call(_positionAt(previewX)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview(
      {required this.position, this.chapter, this.zone, this.image});

  final Duration position;
  final ChapterMark? chapter;
  final SeekZone? zone;
  final Widget? image;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = chapter?.name;
    final picture = image;
    final kind = zone?.kind;
    final radius = BorderRadius.circular(6);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (picture != null)
          Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                    color: WfColors.bg.withValues(alpha: 0.8),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                  color: WfColors.cream.withValues(alpha: 0.85), width: 1.5),
            ),
            child: ClipRRect(borderRadius: radius, child: picture),
          ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: WfColors.bg.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name == null
                      ? formatClock(position)
                      : '${formatClock(position)} · $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: WfColors.cream),
                ),
              ),
              if (kind != null) ...[
                const SizedBox(width: 6),
                Container(
                  key: const Key('seek-zone-tag'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: WfColors.gold,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    seekZoneLabel(l, kind),
                    style: const TextStyle(
                        color: WfColors.bg,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Tempo trascorso e totale: "12:03 / 1:45:00".
class TimeLabel extends StatefulWidget {
  const TimeLabel({super.key, required this.engine});

  final VideoEngine engine;

  @override
  State<TimeLabel> createState() => _TimeLabelState();
}

class _TimeLabelState extends State<TimeLabel> {
  late Duration _position;
  late Duration _duration;
  final _subscriptions = <StreamSubscription<Duration>>[];

  @override
  void initState() {
    super.initState();
    _position = widget.engine.position;
    _duration = widget.engine.duration;
    _subscriptions.addAll([
      widget.engine.positionStream.listen((value) {
        // Il testo cambia solo ogni secondo.
        if (value.inSeconds != _position.inSeconds) {
          setState(() => _position = value);
        }
      }),
      widget.engine.durationStream
          .listen((value) => setState(() => _duration = value)),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        '${formatClock(_position)} / ${formatClock(_duration)}',
        style: const TextStyle(color: WfColors.cream),
      );
}
```

- [ ] **Step 4: la barra riceve le zone.** In `lib/features/player/player_overlay.dart` aggiungi l'import `import 'seek_segments.dart';` (dopo `import 'seek_bar.dart';`) e sostituisci

```dart
                      SeekBar(
                        engine: engine,
                        onSeek: onSeekTo,
                        chapters: chapters,
                        preview: preview,
                      ),
```

con

```dart
                      SeekBar(
                        engine: engine,
                        onSeek: onSeekTo,
                        chapters: chapters,
                        zones: seekZones(view.segments),
                        preview: preview,
                      ),
```

e `TimeLabel(engine: engine),` con `RepaintBoundary(child: TimeLabel(engine: engine)),`.

In `test/features/player/player_overlay_test.dart`, nel test `'episodio successivo, capitoli e anteprima'`, dopo `expect(bar.preview, isNotNull);` aggiungi `expect(bar.zones, isEmpty);`.

- [ ] **Step 5: verifica.**

Run: `flutter test test/features/player/`
Expected: PASS (anche i due test trickplay di `player_screen_test`, che passano il mouse sul centro della barra). Poi `flutter analyze` e `flutter test`.

- [ ] **Step 6: commit.**

```bash
git add lib/features/player/seek_bar.dart lib/features/player/player_overlay.dart test/features/player/seek_bar_test.dart test/features/player/player_overlay_test.dart
git commit -m "feat: draw the seek bar as chapter segments with zones"
```

---

### Task 8: `PlayerPill`

**Files:**
- Create: `lib/features/player/player_pill.dart`
- Modify: `lib/features/watch_party/party_notice_pill.dart` (via `PartyNoticePill`)
- Modify: `lib/features/player/player_screen.dart` (pillola al posto di `PartyNoticePill`)
- Create: `test/features/player/player_pill_test.dart`
- Modify: `test/features/watch_party/party_notice_pill_test.dart`, `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/features/player/player_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/player/player_chrome.dart';
import 'package:wonderflix/features/player/player_pill.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('testi e icone dei riscontri', () {
    String text(PlayerFeedback feedback) => playerFeedbackText(l, feedback);
    expect(text(const PlayFeedback(playing: true)), 'Riproduzione');
    expect(text(const PlayFeedback(playing: false)), 'In pausa');
    expect(
        text(const SeekFeedback(
            offset: Duration(seconds: 20),
            target: Duration(minutes: 18, seconds: 2))),
        '+20 s · 18:02');
    expect(
        text(const SeekFeedback(
            offset: Duration(seconds: -10),
            target: Duration(hours: 1, minutes: 2, seconds: 3))),
        '-10 s · 1:02:03');
    expect(text(const VolumeFeedback(volume: 70, muted: false)), 'Volume 70%');
    expect(text(const VolumeFeedback(volume: 70, muted: true)),
        'Audio disattivato');
    expect(text(const SubtitleDelayFeedback(Duration(milliseconds: 300))),
        'Sottotitoli +0,3 s');

    expect(playerFeedbackIcon(const PlayFeedback(playing: true)),
        LucideIcons.play);
    expect(playerFeedbackIcon(const PlayFeedback(playing: false)),
        LucideIcons.pause);
    expect(
        playerFeedbackIcon(const SeekFeedback(
            offset: Duration(seconds: -10), target: Duration.zero)),
        LucideIcons.rewind);
    expect(
        playerFeedbackIcon(const SeekFeedback(
            offset: Duration(seconds: 10), target: Duration.zero)),
        LucideIcons.fastForward);
    expect(playerFeedbackIcon(const VolumeFeedback(volume: 0, muted: false)),
        LucideIcons.volumeX);
    expect(playerFeedbackIcon(const VolumeFeedback(volume: 40, muted: true)),
        LucideIcons.volumeX);
    expect(playerFeedbackIcon(const VolumeFeedback(volume: 40, muted: false)),
        LucideIcons.volume2);
    expect(playerFeedbackIcon(const SubtitleDelayFeedback(Duration.zero)),
        LucideIcons.captions);
  });

  Future<ValueNotifier<(PlayerFeedback?, PartyNotice?)>> pumpPill(
      WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) async {
    final state = ValueNotifier<(PlayerFeedback?, PartyNotice?)>((null, null));
    addTearDown(state.dispose);
    await pumpApp(
      tester,
      Center(
        child: ValueListenableBuilder<(PlayerFeedback?, PartyNotice?)>(
          valueListenable: state,
          builder: (context, value, _) =>
              PlayerPill(feedback: value.$1, notice: value.$2),
        ),
      ),
      motion: motion,
    );
    return state;
  }

  testWidgets('avviso del party; il tasto lo copre; poi l\'avviso torna',
      (tester) async {
    final state = await pumpPill(tester);
    expect(find.byType(Text), findsNothing);

    const notice = PartyNotice(PartyNoticeKind.joined, name: 'Luigi');
    state.value = (null, notice);
    await tester.pumpAndSettle();
    expect(find.text('Luigi è nel watch party'), findsOneWidget);
    expect(find.byIcon(LucideIcons.userPlus), findsOneWidget);

    state.value = (const VolumeFeedback(volume: 70, muted: false), notice);
    await tester.pumpAndSettle();
    expect(find.text('Volume 70%'), findsOneWidget);
    expect(find.text('Luigi è nel watch party'), findsNothing);

    state.value = (null, notice);
    await tester.pumpAndSettle();
    expect(find.text('Luigi è nel watch party'), findsOneWidget);
  });

  testWidgets('senza contenuto sfuma, poi esce dall\'albero', (tester) async {
    final state = await pumpPill(tester);
    state.value = (const PlayFeedback(playing: false), null);
    await tester.pumpAndSettle();
    double opacity() => tester
        .widget<AnimatedOpacity>(find.byKey(const Key('player-pill')))
        .opacity;
    expect(opacity(), 1);

    state.value = (null, null);
    await tester.pump();
    expect(opacity(), 0);
    expect(find.text('In pausa'), findsOneWidget, reason: 'resta mentre sfuma');
    await tester.pumpAndSettle();
    expect(find.text('In pausa'), findsNothing);
  });

  testWidgets('animazioni complete: entra scendendo dall\'alto',
      (tester) async {
    final state = await pumpPill(tester, motion: MotionLevel.full);
    double shift() => tester
        .widget<AnimatedContainer>(find
            .descendant(
                of: find.byKey(const Key('player-pill')),
                matching: find.byType(AnimatedContainer))
            .first)
        .transform!
        .getTranslation()
        .y;
    expect(shift(), -PlayerPill.hiddenShift);
    state.value = (const PlayFeedback(playing: true), null);
    await tester.pump();
    expect(shift(), 0);
    await tester.pumpAndSettle();
  });
}
```

In `test/features/watch_party/party_notice_pill_test.dart` togli i due `testWidgets` (`'mostra l\'avviso attuale, niente senza avvisi'` e `'nessun avviso: nessuna pillola'`) e gli import che restano inutilizzati (`flutter/material.dart` → `flutter/widgets.dart`, `pump_app.dart`, `watch_party_fakes.dart`): restano i test di testi e icone.

In `test/features/watch_party/party_player_test.dart`, nel test `'avvisi: pillola nel player, e le mie azioni in seconda persona'`, sostituisci

```dart
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(l.watchPartyNoticePaused), findsNothing);
```

con

```dart
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle(); // la pillola sfuma via
    expect(find.text(l.watchPartyNoticePaused), findsNothing);
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/player_pill_test.dart`
Expected: FAIL (file `player_pill.dart` inesistente).

- [ ] **Step 3: la pillola.** Crea `lib/features/player/player_pill.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import '../watch_party/party_notice_pill.dart';
import '../watch_party/party_notices.dart';
import 'player_chrome.dart';
import 'tracks_panel.dart';

/// "+20 s", "-10 s".
String formatSeekOffset(Duration offset) =>
    '${offset.isNegative ? '-' : '+'}${offset.inSeconds.abs()} s';

/// Testo del riscontro di un tasto (spec D §9.2).
String playerFeedbackText(AppLocalizations l, PlayerFeedback feedback) =>
    switch (feedback) {
      PlayFeedback(playing: true) => l.playerFeedbackPlaying,
      PlayFeedback(playing: false) => l.playerFeedbackPaused,
      SeekFeedback(:final offset, :final target) =>
        l.playerFeedbackSeek(formatSeekOffset(offset), formatClock(target)),
      VolumeFeedback(muted: true) => l.playerFeedbackMuted,
      VolumeFeedback(:final volume) => l.playerFeedbackVolume(volume.round()),
      SubtitleDelayFeedback(:final delay) => l.playerFeedbackSubtitles(
          formatSubtitleDelay(delay, l.decimalSeparator)),
    };

/// Icona oro del riscontro di un tasto.
IconData playerFeedbackIcon(PlayerFeedback feedback) => switch (feedback) {
      PlayFeedback(:final playing) =>
        playing ? LucideIcons.play : LucideIcons.pause,
      SeekFeedback(:final offset) =>
        offset.isNegative ? LucideIcons.rewind : LucideIcons.fastForward,
      VolumeFeedback(:final volume, :final muted) =>
        muted || volume == 0 ? LucideIcons.volumeX : LucideIcons.volume2,
      SubtitleDelayFeedback() => LucideIcons.captions,
    };

/// Pillola in alto al centro del player (spec D §9.3): il riscontro dei
/// tasti o, senza, l'avviso corrente del watch party. Cambiando contenuto non
/// sparisce: testo e icona sfumano e la larghezza si adatta.
class PlayerPill extends StatefulWidget {
  const PlayerPill({super.key, this.feedback, this.notice});

  final PlayerFeedback? feedback;
  final PartyNotice? notice;

  /// Di quanto sta più in alto a pillola nascosta.
  static const hiddenShift = 12.0;

  @override
  State<PlayerPill> createState() => _PlayerPillState();
}

typedef _PillContent = ({IconData icon, String text});

class _PlayerPillState extends State<PlayerPill> {
  /// Ultimo contenuto mostrato: resta mentre la pillola sfuma via.
  _PillContent? _last;
  bool _visible = false;

  _PillContent? _content(AppLocalizations l) {
    final feedback = widget.feedback;
    if (feedback != null) {
      return (
        icon: playerFeedbackIcon(feedback),
        text: playerFeedbackText(l, feedback),
      );
    }
    final notice = widget.notice;
    if (notice != null) {
      return (
        icon: partyNoticeIcon(notice.kind),
        text: partyNoticeText(l, notice),
      );
    }
    return null;
  }

  void _onFaded() {
    if (!_visible && mounted) setState(() => _last = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final content = _content(l);
    _visible = content != null;
    if (content != null) _last = content;
    final shown = _last;
    final duration =
        _visible ? motion.duration(WfMotion.medium) : WfMotion.fast;
    final curve = _visible ? WfMotion.emphasized : WfMotion.accelerate;
    final shift =
        _visible || motion.isReduced ? 0.0 : -PlayerPill.hiddenShift;
    return AnimatedOpacity(
      key: const Key('player-pill'),
      opacity: _visible ? 1 : 0,
      duration: duration,
      curve: curve,
      onEnd: _onFaded,
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        transform: Matrix4.translationValues(0, shift, 0),
        child: shown == null ? const SizedBox.shrink() : _frame(shown, motion),
      ),
    );
  }

  Widget _frame(_PillContent content, WfMotion motion) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: WfColors.surfaceHigh.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: WfColors.border),
        ),
        child: AnimatedSize(
          duration: motion.duration(WfMotion.medium),
          curve: WfMotion.emphasized,
          child: AnimatedSwitcher(
            duration: WfMotion.fast,
            child: Row(
              key: ValueKey(content.text),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(content.icon, size: 18, color: WfColors.gold),
                const SizedBox(width: 8),
                Text(content.text,
                    style: const TextStyle(color: WfColors.cream)),
              ],
            ),
          ),
        ),
      );
}
```

- [ ] **Step 4: via `PartyNoticePill`.** In `lib/features/watch_party/party_notice_pill.dart` togli la classe `PartyNoticePill` (con il suo commento) e gli import non più usati, così che il file diventi:

```dart
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'party_notices.dart';
```

seguito da `partyNoticeText` e `partyNoticeIcon` invariate.

In `lib/features/player/player_screen.dart` sostituisci l'import `import '../watch_party/party_notice_pill.dart';` con nulla, aggiungi `import 'player_pill.dart';` (dopo `import 'player_overlay.dart';`) e sostituisci il blocco

```dart
                // Anche dopo l'uscita dal gruppo: gli avvisi "terminato" e
                // "non sei più nel watch party" devono vedersi.
                if (widget.args.party != null)
                  const Positioned(
                    top: 96,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(child: PartyNoticePill()),
                    ),
                  ),
```

con

```dart
                // Riscontro dei tasti e avvisi del watch party (anche dopo
                // l'uscita dal gruppo: "terminato" e "non sei più nel watch
                // party" devono vedersi).
                Positioned(
                  top: 96,
                  left: 0,
                  right: 0,
                  child: ExcludeFocus(
                    child: IgnorePointer(
                      child: Center(
                        child: RepaintBoundary(
                          child: widget.args.party == null
                              ? PlayerPill(feedback: _chrome.feedback)
                              : Consumer(
                                  builder: (context, ref, _) => PlayerPill(
                                    feedback: _chrome.feedback,
                                    notice: ref.watch(partyNoticesProvider),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
```

- [ ] **Step 5: verifica.**

Run: `flutter test test/features/player/ test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` (nessun riferimento a `PartyNoticePill`) e `flutter test`.

- [ ] **Step 6: commit.**

```bash
git add lib/features/player/player_pill.dart lib/features/watch_party/party_notice_pill.dart lib/features/player/player_screen.dart test/features/player/player_pill_test.dart test/features/watch_party/party_notice_pill_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: show party notices in the player pill"
```

---

### Task 9: riscontri dei tasti e avvisi "Hai…" nel watch party

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_screen_test.dart`, `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono.** In `test/features/player/player_screen_test.dart`, dopo il test `'tastiera: pausa, salto, volume, muto, ritardo'`, aggiungi:

```dart
  testWidgets('tastiera: pillola con i riscontri; i salti si sommano',
      (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('+10 s · 00:10'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('+20 s · 00:20'), findsOneWidget);
    expect(engine.seeks,
        [const Duration(seconds: 10), const Duration(seconds: 20)]);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('In pausa'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Volume 95%'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(find.text('Audio disattivato'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(find.text('Sottotitoli +0,1 s'), findsOneWidget);

    await tester.pump(PlayerChromeController.feedbackDuration);
    await tester.pumpAndSettle();
    expect(find.text('Sottotitoli +0,1 s'), findsNothing);
    await unmount(tester);
  });
```

In `test/features/watch_party/party_player_test.dart`, dopo il test `'avvisi: pillola nel player, e le mie azioni in seconda persona'`, aggiungi:

```dart
  testWidgets('tasti nel watch party: la pillola del tasto, niente "Hai…"',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('unpause'));
    expect(find.text(l.playerFeedbackPlaying), findsOneWidget);
    expect(find.text(l.watchPartyNoticeResumedByYou), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // Il salto parte verso il gruppo dopo 400 ms.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.textContaining('+10 s'), findsOneWidget);
    expect(find.textContaining('Hai saltato'), findsNothing);
    await finish(tester);
  });
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/player_screen_test.dart test/features/watch_party/party_player_test.dart`
Expected: FAIL (nessuna pillola per i tasti; nel party compare "Hai ripreso").

- [ ] **Step 3: i tasti danno il riscontro.** In `lib/features/player/player_screen.dart` sostituisci tutto il metodo `_run` con:

```dart
  /// Comando da tastiera: la pillola mostra il riscontro (spec D §9), i
  /// controlli non compaiono. Il riscontro va dato **prima** del comando:
  /// nel watch party l'avviso "Hai…" che segue controlla che la pillola ci
  /// sia già (vedi [_attachParty]).
  void _run(PlayerCommand command) {
    final controller = _controller;
    final ready = ref.read(playerControllerProvider(widget.args)).status ==
        PlayerStatus.ready;
    switch (command) {
      case PlayerCommand.togglePlay:
        if (ready) {
          _chrome.showFeedback(
              PlayFeedback(playing: !controller.engine.playing));
        }
        unawaited(controller.togglePlay());
      case PlayerCommand.seekBack:
        _seekBy(-seekStep, ready: ready);
      case PlayerCommand.seekForward:
        _seekBy(seekStep, ready: ready);
      case PlayerCommand.volumeUp:
        unawaited(controller.changeVolumeBy(volumeStep));
        _showVolume();
      case PlayerCommand.volumeDown:
        unawaited(controller.changeVolumeBy(-volumeStep));
        _showVolume();
      case PlayerCommand.toggleMute:
        unawaited(controller.toggleMute());
        _showVolume();
      case PlayerCommand.subtitleDelayDown:
        unawaited(controller.shiftSubtitleDelay(-subtitleDelayStep));
        _showSubtitleDelay();
      case PlayerCommand.subtitleDelayUp:
        unawaited(controller.shiftSubtitleDelay(subtitleDelayStep));
        _showSubtitleDelay();
      case PlayerCommand.toggleFullscreen:
        unawaited(_toggleFullscreen());
      case PlayerCommand.nextEpisode:
        _playNext();
      case PlayerCommand.escape:
        _escape();
      case PlayerCommand.exit:
        _exit();
    }
  }

  /// Salto da tastiera con la pillola (i salti di fila si sommano).
  void _seekBy(Duration step, {required bool ready}) {
    final engine = _controller.engine;
    if (ready) {
      _chrome.seek(step, from: engine.position, duration: engine.duration);
    }
    unawaited(_controller.seekBy(step));
  }

  /// Volume e muto dopo il tasto: il controller li aggiorna subito.
  void _showVolume() {
    final view = ref.read(playerControllerProvider(widget.args));
    _chrome.showFeedback(VolumeFeedback(volume: view.volume, muted: view.muted));
  }

  void _showSubtitleDelay() => _chrome.showFeedback(SubtitleDelayFeedback(
      ref.read(playerControllerProvider(widget.args)).subtitleDelay));
```

- [ ] **Step 4: niente "Hai…" dopo un tasto.** In `_attachParty` sostituisci

```dart
    final authority = GroupAuthority(
        api: session.api, engine: controller.engine, onAction: notices.mine);
```

con

```dart
    final authority = GroupAuthority(
      api: session.api,
      engine: controller.engine,
      // Spec D §9.3: un'azione appena data da tastiera ha già la sua
      // pillola; l'avviso "Hai…" registra solo l'eco.
      onAction: (kind, {position}) => notices.mine(kind,
          position: position, show: !_chrome.isRecentKeyAction(kind)),
    );
```

- [ ] **Step 5: verifica.**

Run: `flutter test test/features/player/ test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 6: commit.**

```bash
git add lib/features/player/player_screen.dart test/features/player/player_screen_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: show key feedback in the player pill"
```

---

### Task 10: verifica finale

**Files:** nessuno (solo verifica; correzioni minime se serve).

- [ ] **Step 1: analisi e test.**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: tutto verde (918 di partenza più quelli nuovi del piano).

- [ ] **Step 2: nessun residuo.**

Run: `grep -rn "PartyNoticePill\|PlayerScreen.hideDelay\|player-controls'\|milliseconds: 200\|milliseconds: 150" lib/features/player lib/app/router.dart lib/features/watch_party`
Expected: nessun risultato.

Run: `git log --format=%B main..HEAD | grep -ci "co-authored"`
Expected: `0`.

- [ ] **Step 3: build di debug.**

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
flutter build windows --debug --dart-define-from-file=D:/Github/wonderflix/config/wonderflix.json
```

Expected: build riuscita. Se `windows/flutter/` risulta modificato con soli fine riga: `git checkout -- windows/flutter/`.

- [ ] **Step 4: stato pulito.**

Run: `git status --short`
Expected: nessun file modificato o non tracciato (a parte `build/`, ignorata).
