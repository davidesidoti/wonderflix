# WonderFlix — Piano 10c: reazioni del watch party e release

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ultimo piano dello Spec E. Le reazioni del watch party: barretta con le sei emoji sopra il pulsante, tasti 1–6, emoji che salgono in basso a destra con il nome. Poi documentazione della release del plugin e allineamento dello spec; dopo la prova e il merge, release del plugin 1.0.0 e di WonderFlix 0.5.0.

**Decisioni prese con l'utente (2026-10-02):**
1. **Barretta:** livello a sé nel player, agganciato al pulsante con `CompositedTransformTarget`/`CompositedTransformFollower` (come i menu di Flutter: un widget che sporge fuori dai bordi del suo genitore non riceve i clic). Sta sopra chat, "Salta intro" e scheda, sotto pillola e pannello. Entrata: dissolvenza + scala 0,9 → 1 dal pulsante (`medium`, `emphasized`); uscita `fast`; con le animazioni ridotte solo dissolvenza.
2. **Chiusura della barretta:** clic sul film (che non fa altro), Esc, di nuovo il pulsante, o 5 s senza il mouse sopra. Finché è aperta i controlli restano visibili. Terzo riquadro di `PlayerPopup` (`reactions`), uno alla volta con chat e tracce.
3. **Tasti 1–6** (anche tastierino): solo con il focus al player (a chat aperta i numeri vanno nel campo), anche a controlli nascosti; ripetizione ignorata; al massimo una reazione ogni 200 ms (anche con i clic); niente controlli né pillola.
4. **Volo:** `PartyReactionsLayer` in basso a destra (`right: 24`, `bottom: 150`, come la chat), scostamento orizzontale 0–80 px calcolato dall'id; emoji 40 px con il nome sotto ("Tu" per le proprie). Complete: scala 0,6 → 1 in 200 ms, salita di 140 px in 2,4 s rallentando, dissolvenza negli ultimi 600 ms. Ridotte: compare in 150 ms, resta 1,6 s, sfuma in 300 ms. Max 12 in volo (le nuove oltre il limite si scartano). Un solo ticker, `RepaintBoundary`, `IgnorePointer`.
5. **Testi:** etichette delle sei reazioni (tooltip della barretta) e "Reazioni (1–6)".
6. **Release** (dopo la prova e il merge, ogni push e tag solo con l'ok dell'utente): plugin 1.0.0 (tag `watch-party-plugin-v1.0.0`, pre-release dal workflow, voce nel manifest), sul server via `ssh ultra` si toglie la cartella installata a mano e l'utente installa dal Catalogo; poi WonderFlix 0.5.0 non obbligatoria.

**Architecture:**
- `PlayerChromeController`: `PlayerPopup.reactions` come `tracks` (controlli su, niente pausa).
- `lib/features/watch_party/party_reactions_layer.dart`: `reactionFrame` e `reactionJitter` (funzioni pure) e `PartyReactionsLayer` (ascolta `PartyChannel.reactions`, un `Ticker`).
- `lib/features/watch_party/party_reactions_tray.dart`: `PartyReactionsTray` (`open`, `onReaction`, `onClose`; si chiude da sola) e `partyReactionLabel`.
- `PlayerOverlay`: pulsante `smilePlus` dentro un `CompositedTransformTarget` (`reactionsLink`).
- `PlayerScreen`: `LayerLink`, livelli `player-party-reactions` (prima della chat) e `player-party-reactions-tray` (dopo la chat), tasti 1–6, limite di frequenza.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, clock.

**Spec:** `docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md` (§10, §11, §14). **Worktree:** `.claude/worktrees/piano-10c`, branch `feat/piano-10c`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves`), nemmeno come verbi normali.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** Git Bash su Windows, dalla root del worktree. Comandi git semplici, niente `git -C`. Prima dei comandi Flutter: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"`.
- **Prima di ogni commit:** `flutter analyze` senza problemi e `flutter test` tutto verde (a inizio piano: 1217 test). Se `flutter test` riscrive `windows/flutter/generated_plugin*` con soli fine riga, `git checkout -- windows/flutter/`. Dopo una modifica agli ARB: `flutter gen-l10n`.
- **Formattazione:** niente `dart format` su file interi; edit mirati. LF nel repository.
- **Durate e misure:** costanti nominate e commentate, token di `WfMotion`. Commenti in italiano, codice in inglese. `clock.now()`, mai `DateTime.now()`.
- **Riverpod/Flutter:** mai cambiare lo stato di un provider durante una build; `mounted` dopo ogni `await`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **`CompositedTransformFollower`** non controlla le proprie dimensioni nel test dei clic (`RenderFollowerLayer.hitTest` va dritto ai figli): messo in un `Positioned(left: 0, top: 0)` dello `Stack` del player, riceve i clic dove è disegnato, accanto al suo `CompositedTransformTarget`. Con `showWhenUnlinked: false` senza target (es. strato d'errore al posto dei controlli) non si vede né prende clic.
- **Animazioni nei test:** un `AnimationController` finisce solo quando il tempo trascorso supera **strettamente** la durata: per attendere la fine si pompa `durata + 1 ms`. `pumpApp` usa le animazioni ridotte salvo `motion: MotionLevel.full`.
- **Ticker:** `SingleTickerProviderStateMixin` + `createTicker`; `elapsed` riparte da zero a ogni `start()`. I ticker silenziati da `TickerMode` non avanzano, ma qui il player è sempre in primo piano.
- **Tasti nei test:** `tester.sendKeyEvent(LogicalKeyboardKey.digit1)`, `tester.sendKeyRepeatEvent(...)` per la ripetizione; `FocusManager.instance.primaryFocus?.debugLabel` è `'player'` con il focus al player.
- **`pumpPartyPlayer`** (`party_player_test.dart`) installa già `FakePartyChannelApi` (`channelApi`); `channelApi.sent` contiene gli eventi mandati (`PartyOutgoingReaction`); le reazioni degli altri arrivano con `events.add(PartyChannelReceived(partyPayload({'Type': 'Reaction', 'Reaction': 'joy'}, id: 'r1')))`.
- **`PartyChannel.sendReaction`** emette subito la reazione propria su `reactions` (con `userId` dell'utente) e poi la manda.
- I tooltip della barretta e del pulsante si cercano con `find.byTooltip(…)`.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `lib/features/player/player_chrome.dart` | modifica | `PlayerPopup.reactions` |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi delle reazioni |
| `lib/features/watch_party/party_reactions_layer.dart` | crea | volo delle reazioni |
| `lib/features/watch_party/party_reactions_tray.dart` | crea | barretta |
| `lib/features/player/player_overlay.dart` | modifica | pulsante reazioni con `CompositedTransformTarget` |
| `lib/features/player/player_screen.dart` | modifica | livelli, tasti 1–6, limite |
| `docs/RELEASING.md` | modifica | release del plugin |
| `docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md` | modifica | allineamento |
| `test/…` | crea/modifica | test |

## Gruppi per i subagent

- **Gruppo A (Task 1):** riquadro `reactions` e testi.
- **Gruppo B (Task 2):** livello del volo.
- **Gruppo C (Task 3–4):** barretta e pulsante.
- **Gruppo D (Task 5):** integrazione nel player.
- **Gruppo E (Task 6):** documentazione, spec, verifica finale.
- Poi, fuori dai subagent: prova manuale, merge, release (sezione finale).

---

### Task 1: riquadro delle reazioni e testi

**Files:**
- Modify: `lib/features/player/player_chrome.dart`
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/features/player/player_chrome_test.dart`

- [ ] **Step 1: testi**

In `l10n/app_it.arb`, subito dopo `"partyChatTooMany": …,`:

```json
  "partyReactionsOpen": "Reazioni (1–6)",
  "partyReactionJoy": "Risata",
  "partyReactionScream": "Spavento",
  "partyReactionCry": "Triste",
  "partyReactionWow": "Stupore",
  "partyReactionClap": "Applauso",
  "partyReactionFacepalm": "Facepalm",
```

In `l10n/app_en.arb`, subito dopo `"partyChatTooMany": …,`:

```json
  "partyReactionsOpen": "Reactions (1–6)",
  "partyReactionJoy": "Laughing",
  "partyReactionScream": "Scared",
  "partyReactionCry": "Sad",
  "partyReactionWow": "Amazed",
  "partyReactionClap": "Applause",
  "partyReactionFacepalm": "Facepalm",
```

Run: `flutter gen-l10n`.

- [ ] **Step 2: scrivi il test che fallisce**

In fondo a `main()` di `test/features/player/player_chrome_test.dart`:

```dart
  test('barretta delle reazioni (spec E §10.2): controlli su, niente pausa, '
      'uno alla volta', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      async.elapse(PlayerChromeController.hideDelay);
      expect(chrome.controlsVisible, isFalse);
      chrome.openPopup(PlayerPopup.reactions);
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(seconds: 10));
      expect(chrome.controlsVisible, isTrue);
      chrome.setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(const Duration(seconds: 20));
      expect(chrome.pauseScreen, isFalse);
      chrome.openPopup(PlayerPopup.chat);
      expect(chrome.popup, PlayerPopup.chat);
      chrome.closePopup();
      async.elapse(PlayerChromeController.pauseScreenDelay);
      expect(chrome.pauseScreen, isTrue);
      chrome.dispose();
    });
  });
```

- [ ] **Step 3: esegui il test e verifica che fallisca**

Run: `flutter test test/features/player/player_chrome_test.dart`
Expected: FAIL in compilazione (`PlayerPopup.reactions` non esiste).

- [ ] **Step 4: implementa**

In `lib/features/player/player_chrome.dart` sostituisci l'enum:

```dart
/// Riquadri del player che si aprono uno alla volta (spec E §11): il
/// pannello "Audio e sottotitoli" e la chat del watch party.
enum PlayerPopup { tracks, chat }
```

con:

```dart
/// Riquadri del player che si aprono uno alla volta (spec E §11): il
/// pannello "Audio e sottotitoli", la chat e la barretta delle reazioni del
/// watch party.
enum PlayerPopup { tracks, chat, reactions }
```

In `openPopup` sostituisci `if (popup == PlayerPopup.tracks) _controlsVisible = true;` con:

```dart
    // Pannello e barretta stanno nei controlli: si vedono e restano.
    if (popup != PlayerPopup.chat) _controlsVisible = true;
```

e aggiorna il suo commento: "Il pannello "Audio e sottotitoli" e la barretta delle reazioni mostrano i controlli e li tengono su; la chat no (spec E §9.6). Tutti chiudono la schermata di pausa."

In `_scheduleHide` sostituisci `if (_popup == PlayerPopup.tracks) return;` con:

```dart
    if (_popup == PlayerPopup.tracks || _popup == PlayerPopup.reactions) {
      return;
    }
```

e nel suo commento "Con il pannello aperto nessuno dei due" con "Con il pannello o la barretta delle reazioni aperti nessuno dei due".

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/player/player_chrome.dart l10n/app_it.arb l10n/app_en.arb test/features/player/player_chrome_test.dart
git commit -m "feat: add the reactions popup and strings"
```

---

### Task 2: reazioni in volo (`PartyReactionsLayer`)

**Files:**
- Create: `lib/features/watch_party/party_reactions_layer.dart`
- Create: `test/features/watch_party/party_reactions_layer_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

Crea `test/features/watch_party/party_reactions_layer_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_reactions_layer.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  group('reactionFrame (spec E §10.4)', () {
    const ms = Duration(milliseconds: 1);

    test('animazioni complete: scala, salita, dissolvenza', () {
      final start = reactionFrame(Duration.zero, reduced: false);
      expect(start.scale, PartyReactionsLayer.popFrom);
      expect(start.lift, 0);
      expect(start.opacity, 1);
      final popped =
          reactionFrame(PartyReactionsLayer.popDuration, reduced: false);
      expect(popped.scale, closeTo(1, 1e-9));
      final fadeStart = PartyReactionsLayer.flightDuration -
          PartyReactionsLayer.fadeOutDuration;
      expect(reactionFrame(fadeStart, reduced: false).opacity, 1);
      expect(reactionFrame(fadeStart + PartyReactionsLayer.fadeOutDuration ~/ 2,
                  reduced: false)
              .opacity,
          closeTo(0.5, 0.01));
      final end =
          reactionFrame(PartyReactionsLayer.flightDuration, reduced: false);
      expect(end.lift, PartyReactionsLayer.rise);
      expect(end.opacity, 0);
      expect(reactionFrame(ms * 1200, reduced: false).lift,
          greaterThan(PartyReactionsLayer.rise / 2),
          reason: 'la salita rallenta: a metà tempo è oltre metà strada');
    });

    test('animazioni ridotte: niente scala né salita', () {
      expect(
          PartyReactionsLayer.reducedLifetime,
          PartyReactionsLayer.reducedFadeIn +
              PartyReactionsLayer.reducedHold +
              PartyReactionsLayer.reducedFadeOut);
      expect(reactionFrame(Duration.zero, reduced: true).opacity, 0);
      final shown =
          reactionFrame(PartyReactionsLayer.reducedFadeIn, reduced: true);
      expect(shown.opacity, 1);
      expect(shown.scale, 1);
      expect(shown.lift, 0);
      expect(
          reactionFrame(
                  PartyReactionsLayer.reducedFadeIn +
                      PartyReactionsLayer.reducedHold,
                  reduced: true)
              .opacity,
          1);
      expect(
          reactionFrame(PartyReactionsLayer.reducedLifetime, reduced: true)
              .opacity,
          0);
    });

    test('scostamento: da 0 a 80 px, sempre uguale per lo stesso id', () {
      for (final id in ['r1', 'local-7', 'a8f3c2e19b', '']) {
        final jitter = reactionJitter(id);
        expect(jitter, inInclusiveRange(0, PartyReactionsLayer.maxJitter));
        expect(reactionJitter(id), jitter);
      }
      expect(reactionJitter('r1'), isNot(reactionJitter('r2')));
    });
  });

  group('livello (spec E §10.4)', () {
    late FakeSyncPlayApi api;
    late FakePartyChannelApi channelApi;
    late StreamController<ServerEvent> events;

    setUp(() {
      api = FakeSyncPlayApi();
      channelApi = FakePartyChannelApi()..install();
      events = StreamController<ServerEvent>.broadcast();
      api.onCall = (call) {
        if (call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(GroupJoined(
              'g1', testGroup(participants: ['Mario', 'Luigi']))));
        }
      };
    });

    tearDown(() => events.close());

    ProviderContainer container(WidgetTester tester) => ProviderScope
        .containerOf(tester.element(find.byType(PartyReactionsLayer)));

    Future<void> pumpLayer(WidgetTester tester,
        {MotionLevel motion = MotionLevel.reduced}) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: Stack(children: [
            Positioned(
              right: PartyReactionsLayer.right,
              bottom: PartyReactionsLayer.bottom,
              child: PartyReactionsLayer(),
            ),
          ]),
        ),
        motion: motion,
        overrides: [
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          syncPlayApiProvider.overrideWithValue(api),
          watchPartyEventsProvider.overrideWithValue(events.stream),
          partyChannelApiProvider.overrideWithValue(channelApi),
        ],
      );
      unawaited(container(tester)
          .read(watchPartySessionProvider.notifier)
          .join('g1'));
      await tester.pump();
      await tester.pump();
      expect(container(tester).read(partyChannelProvider).active, isTrue);
    }

    Future<void> leave(WidgetTester tester) async {
      await container(tester).read(watchPartySessionProvider.notifier).leave();
      await tester.pump(PartyReactionsLayer.flightDuration);
    }

    Future<void> receive(WidgetTester tester, String reaction,
        {required String id}) async {
      events.add(PartyChannelReceived(
          partyPayload({'Type': 'Reaction', 'Reaction': reaction}, id: id)));
      await tester.pump();
      await tester.pump();
    }

    Finder inLayer(Finder finder) =>
        find.descendant(of: find.byType(PartyReactionsLayer), matching: finder);

    testWidgets('reazione degli altri: emoji e nome; poi sparisce',
        (tester) async {
      await pumpLayer(tester);
      await receive(tester, 'clap', id: 'r1');
      expect(inLayer(find.text('👏')), findsOneWidget);
      expect(inLayer(find.text('Luigi')), findsOneWidget);
      await tester.pump(PartyReactionsLayer.reducedLifetime);
      await tester.pump();
      expect(inLayer(find.text('👏')), findsNothing);
      await leave(tester);
    });

    testWidgets('la nostra: subito, con "Tu"', (tester) async {
      await pumpLayer(tester);
      container(tester)
          .read(partyChannelProvider.notifier)
          .sendReaction(PartyReaction.joy);
      await tester.pump();
      await tester.pump();
      expect(inLayer(find.text('😂')), findsOneWidget);
      expect(inLayer(find.text('Tu')), findsOneWidget);
      await leave(tester);
    });

    testWidgets('al massimo 12 in volo: le altre si scartano', (tester) async {
      await pumpLayer(tester);
      for (var i = 0; i < PartyReactionsLayer.maxInFlight + 2; i++) {
        events.add(PartyChannelReceived(partyPayload(
            {'Type': 'Reaction', 'Reaction': 'wow'},
            id: 'r$i')));
      }
      await tester.pump();
      await tester.pump();
      expect(inLayer(find.text('😮')),
          findsNWidgets(PartyReactionsLayer.maxInFlight));
      await leave(tester);
    });

    testWidgets('animazioni complete: sale', (tester) async {
      await pumpLayer(tester, motion: MotionLevel.full);
      await receive(tester, 'joy', id: 'r1');
      final start = tester.getTopLeft(inLayer(find.text('😂'))).dy;
      await tester.pump(const Duration(seconds: 1));
      final later = tester.getTopLeft(inLayer(find.text('😂'))).dy;
      expect(later, lessThan(start - 50));
      await leave(tester);
    });

    testWidgets('non prende i clic', (tester) async {
      await pumpLayer(tester);
      expect(
          find.descendant(
              of: find.byType(PartyReactionsLayer),
              matching: find.byType(IgnorePointer)),
          findsWidgets);
      await leave(tester);
    });
  });
}
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_reactions_layer_test.dart`
Expected: FAIL in compilazione (`party_reactions_layer.dart` non esiste).

- [ ] **Step 3: implementa**

Crea `lib/features/watch_party/party_reactions_layer.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/session_controller.dart';
import 'party_channel.dart';
import 'party_chat_bubble.dart';

/// Un fotogramma di una reazione in volo: opacità, scala e di quanto è
/// salita.
typedef ReactionFrame = ({double opacity, double scale, double lift});

/// Il fotogramma di una reazione partita da [elapsed] (spec E §10.4).
/// Complete: scala da [PartyReactionsLayer.popFrom] a 1, salita di
/// [PartyReactionsLayer.rise] che rallenta, dissolvenza alla fine. Ridotte:
/// solo dissolvenza in entrata e in uscita, ferma.
ReactionFrame reactionFrame(Duration elapsed, {required bool reduced}) {
  double progress(Duration from, Duration span) => span == Duration.zero
      ? 1
      : ((elapsed - from).inMicroseconds / span.inMicroseconds).clamp(0, 1);
  if (reduced) {
    final fadeOutFrom =
        PartyReactionsLayer.reducedFadeIn + PartyReactionsLayer.reducedHold;
    final opacity = elapsed < PartyReactionsLayer.reducedFadeIn
        ? progress(Duration.zero, PartyReactionsLayer.reducedFadeIn)
        : 1 - progress(fadeOutFrom, PartyReactionsLayer.reducedFadeOut);
    return (opacity: opacity, scale: 1, lift: 0);
  }
  final pop = WfMotion.emphasized
      .transform(progress(Duration.zero, PartyReactionsLayer.popDuration));
  final scale = PartyReactionsLayer.popFrom +
      (1 - PartyReactionsLayer.popFrom) * pop;
  final lift = PartyReactionsLayer.rise *
      WfMotion.decelerate
          .transform(progress(Duration.zero, PartyReactionsLayer.flightDuration));
  final fadeFrom =
      PartyReactionsLayer.flightDuration - PartyReactionsLayer.fadeOutDuration;
  final opacity =
      1 - progress(fadeFrom, PartyReactionsLayer.fadeOutDuration);
  return (opacity: opacity, scale: scale, lift: lift);
}

/// Scostamento orizzontale di una reazione, da 0 a
/// [PartyReactionsLayer.maxJitter]: calcolato dall'id, così è stabile (anche
/// nei test) e reazioni diverse non si sovrappongono tutte.
double reactionJitter(String id) {
  var sum = 0;
  for (final unit in id.codeUnits) {
    sum = (sum * 31 + unit) & 0x7fffffff;
  }
  return (sum % (PartyReactionsLayer.maxJitter.toInt() + 1)).toDouble();
}

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Le reazioni in volo nel player (spec E §10.4): nascono in basso a destra,
/// salgono e svaniscono, con il nome di chi le ha mandate. Un solo ticker
/// per tutte; non prende i clic.
class PartyReactionsLayer extends ConsumerStatefulWidget {
  const PartyReactionsLayer({super.key});

  /// Posizione nel player: a destra, alla stessa altezza della chat.
  static const right = 24.0;
  static const bottom = 150.0;

  /// Scostamento orizzontale massimo.
  static const maxJitter = 80.0;

  /// Dimensione delle emoji.
  static const emojiSize = 40.0;

  /// Reazioni in volo insieme al massimo: le altre si scartano.
  static const maxInFlight = 12;

  /// Animazioni complete: la comparsa con la scala, il volo intero e la
  /// dissolvenza finale (dentro il volo).
  static const popDuration = Duration(milliseconds: 200);
  static const flightDuration = Duration(milliseconds: 2400);
  static const fadeOutDuration = Duration(milliseconds: 600);

  /// Scala di partenza.
  static const popFrom = 0.6;

  /// Di quanto sale.
  static const rise = 140.0;

  /// Animazioni ridotte: entrata, sosta, uscita.
  static const reducedFadeIn = WfMotion.fast;
  static const reducedHold = Duration(milliseconds: 1600);
  static const reducedFadeOut = Duration(milliseconds: 300);

  /// Vita con le animazioni ridotte: entrata + sosta + uscita (le `Duration`
  /// non si sommano in una costante).
  static const reducedLifetime = Duration(milliseconds: 2050);

  /// Spazio del livello: lo scostamento più un'emoji con il nome, e la
  /// salita più un'emoji con il nome.
  static const _itemExtent = 72.0;
  static const width = maxJitter + _itemExtent;
  static const height = rise + _itemExtent;

  @override
  ConsumerState<PartyReactionsLayer> createState() =>
      _PartyReactionsLayerState();
}

class _Flight {
  _Flight(this.event, this.startedAt, this.jitter);

  final PartyReactionEvent event;

  /// Tempo del ticker alla partenza.
  final Duration startedAt;
  final double jitter;
}

class _PartyReactionsLayerState extends ConsumerState<PartyReactionsLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final StreamSubscription<PartyReactionEvent> _subscription;
  final _flights = <_Flight>[];
  Duration _now = Duration.zero;
  bool _reduced = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _subscription = ref
        .read(partyChannelProvider.notifier)
        .reactions
        .listen(_onReaction);
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _ticker.dispose();
    super.dispose();
  }

  Duration get _lifetime => _reduced
      ? PartyReactionsLayer.reducedLifetime
      : PartyReactionsLayer.flightDuration;

  void _onReaction(PartyReactionEvent event) {
    if (!mounted || _flights.length >= PartyReactionsLayer.maxInFlight) {
      return;
    }
    if (!_ticker.isActive) {
      // `elapsed` riparte da zero a ogni partenza del ticker.
      _now = Duration.zero;
      _ticker.start();
    }
    setState(() =>
        _flights.add(_Flight(event, _now, reactionJitter(event.id))));
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    setState(() => _flights
        .removeWhere((flight) => elapsed - flight.startedAt >= _lifetime));
    if (_flights.isEmpty) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    _reduced = WfMotion.of(context).isReduced;
    final l = AppLocalizations.of(context);
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox(
          width: PartyReactionsLayer.width,
          height: PartyReactionsLayer.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final flight in _flights)
                _buildFlight(flight, l,
                    mine: userId != null &&
                        _normalizeId(flight.event.userId) ==
                            _normalizeId(userId)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlight(_Flight flight, AppLocalizations l,
      {required bool mine}) {
    final frame = reactionFrame(_now - flight.startedAt, reduced: _reduced);
    return Positioned(
      key: ValueKey('party-reaction-flight-${flight.event.id}'),
      right: flight.jitter,
      bottom: frame.lift,
      child: Opacity(
        opacity: frame.opacity,
        child: Transform.scale(
          scale: frame.scale,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                flight.event.reaction.emoji,
                style: const TextStyle(
                  fontSize: PartyReactionsLayer.emojiSize,
                  height: 1.1,
                  fontFamilyFallback: partyEmojiFontFallback,
                ),
              ),
              const SizedBox(height: 2),
              _NameLabel(mine ? l.partyChatYou : flight.event.userName),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il nome sotto una reazione: piccolo, su fondo scuro.
class _NameLabel extends StatelessWidget {
  const _NameLabel(this.name);

  /// Opacità del fondo.
  static const backgroundAlpha = 0.65;

  final String name;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: WfColors.bg.withValues(alpha: backgroundAlpha),
          borderRadius: BorderRadius.circular(PartyChatBubble.radius),
        ),
        child: Text(name,
            style: const TextStyle(color: WfColors.cream, fontSize: 11)),
      );
}
```

(Se l'analyzer segnala l'import di `party_channel_models.dart` come non usato, toglilo: i tipi arrivano da `party_channel.dart`.)

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/watch_party/party_reactions_layer_test.dart`
Expected: PASS (8 test).

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/watch_party/party_reactions_layer.dart test/features/watch_party/party_reactions_layer_test.dart
git commit -m "feat: fly watch party reactions over the player"
```

---

### Task 3: barretta delle reazioni (`PartyReactionsTray`)

**Files:**
- Create: `lib/features/watch_party/party_reactions_tray.dart`
- Create: `test/features/watch_party/party_reactions_tray_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

Crea `test/features/watch_party/party_reactions_tray_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/features/watch_party/party_reactions_tray.dart';

import '../../support/pump_app.dart';

void main() {
  late List<PartyReaction> sent;
  late int closed;
  late ValueNotifier<bool> open;

  setUp(() {
    sent = [];
    closed = 0;
    open = ValueNotifier(true);
  });

  Future<void> pumpTray(WidgetTester tester) => pumpApp(
        tester,
        Scaffold(
          body: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: open,
              builder: (context, isOpen, _) => PartyReactionsTray(
                open: isOpen,
                onReaction: sent.add,
                onClose: () {
                  closed++;
                  open.value = false;
                },
              ),
            ),
          ),
        ),
      );

  testWidgets('sei emoji con il tasto e l\'etichetta', (tester) async {
    await pumpTray(tester);
    for (final reaction in PartyReaction.values) {
      expect(find.text(reaction.emoji), findsOneWidget);
      expect(find.text('${reaction.key}'), findsOneWidget);
    }
    expect(find.byTooltip('Risata'), findsOneWidget);
    expect(find.byTooltip('Facepalm'), findsOneWidget);
  });

  testWidgets('un clic manda la reazione e la barretta resta aperta',
      (tester) async {
    await pumpTray(tester);
    await tester.tap(find.byKey(const ValueKey('party-reaction-clap')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('party-reaction-joy')));
    await tester.pump();
    expect(sent, [PartyReaction.clap, PartyReaction.joy]);
    expect(closed, 0);
  });

  testWidgets('si chiude da sola dopo 5 s senza il mouse sopra; '
      'con il mouse sopra no', (tester) async {
    await pumpTray(tester);
    await tester.pump(
        PartyReactionsTray.idleClose - const Duration(milliseconds: 1));
    expect(closed, 0);
    final mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(PartyReactionsTray)));
    await tester.pump(PartyReactionsTray.idleClose * 2);
    expect(closed, 0, reason: 'mouse sopra');
    await mouse.moveTo(Offset.zero);
    await tester.pump(PartyReactionsTray.idleClose);
    expect(closed, 1);
  });

  testWidgets('chiusa: invisibile e senza clic', (tester) async {
    open.value = false;
    await pumpTray(tester);
    await tester.pumpAndSettle();
    final opacity = tester.widget<AnimatedOpacity>(find.descendant(
        of: find.byType(PartyReactionsTray),
        matching: find.byType(AnimatedOpacity)));
    expect(opacity.opacity, 0);
    await tester.tap(find.byKey(const ValueKey('party-reaction-joy')),
        warnIfMissed: false);
    expect(sent, isEmpty);
  });
}
```

(`PointerDeviceKind` viene da `package:flutter/gestures.dart`: se l'analyzer lo chiede, aggiungi l'import.)

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_reactions_tray_test.dart`
Expected: FAIL in compilazione (`party_reactions_tray.dart` non esiste).

- [ ] **Step 3: implementa**

Crea `lib/features/watch_party/party_reactions_tray.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'party_chat_bubble.dart';

/// Etichetta di una reazione (tooltip della barretta e testo accessibile).
String partyReactionLabel(AppLocalizations l, PartyReaction reaction) =>
    switch (reaction) {
      PartyReaction.joy => l.partyReactionJoy,
      PartyReaction.scream => l.partyReactionScream,
      PartyReaction.cry => l.partyReactionCry,
      PartyReaction.wow => l.partyReactionWow,
      PartyReaction.clap => l.partyReactionClap,
      PartyReaction.facepalm => l.partyReactionFacepalm,
    };

/// La barretta delle reazioni (spec E §10.2): le sei emoji con il loro
/// tasto. Un clic manda la reazione e la barretta resta aperta; senza il
/// mouse sopra si chiude da sola dopo [idleClose]. Sempre montata: chiusa è
/// invisibile e non prende i clic, così entra ed esce sfumando.
class PartyReactionsTray extends StatefulWidget {
  const PartyReactionsTray({
    super.key,
    required this.open,
    required this.onReaction,
    required this.onClose,
  });

  final bool open;
  final ValueChanged<PartyReaction> onReaction;
  final VoidCallback onClose;

  /// Senza il mouse sopra per questo tempo si chiude.
  static const idleClose = Duration(seconds: 5);

  /// Distanza dal pulsante.
  static const gap = 8.0;

  /// Dimensione delle emoji.
  static const emojiSize = 24.0;

  /// Opacità del fondo.
  static const backgroundAlpha = 0.94;

  /// Fondo crema al passaggio del mouse.
  static const hoverAlpha = 0.12;

  /// Scala di partenza dell'entrata.
  static const enterScale = 0.9;

  @override
  State<PartyReactionsTray> createState() => _PartyReactionsTrayState();
}

class _PartyReactionsTrayState extends State<PartyReactionsTray> {
  Timer? _idle;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.open) _restartIdle();
  }

  @override
  void didUpdateWidget(PartyReactionsTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) _restartIdle();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _restartIdle() {
    _idle?.cancel();
    _idle = null;
    if (!widget.open || _hovered) return;
    _idle = Timer(PartyReactionsTray.idleClose, () {
      if (mounted && widget.open && !_hovered) widget.onClose();
    });
  }

  void _setHovered(bool hovered) {
    _hovered = hovered;
    _restartIdle();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final open = widget.open;
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: open ? motion.duration(WfMotion.medium) : WfMotion.fast,
        curve: open ? WfMotion.emphasized : WfMotion.accelerate,
        child: AnimatedScale(
          scale: open || motion.isReduced ? 1 : PartyReactionsTray.enterScale,
          alignment: Alignment.bottomRight,
          duration: open ? motion.duration(WfMotion.medium) : WfMotion.fast,
          curve: open ? WfMotion.emphasized : WfMotion.accelerate,
          child: MouseRegion(
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
            child: Material(
              color: WfColors.surface
                  .withValues(alpha: PartyReactionsTray.backgroundAlpha),
              shape: const StadiumBorder(
                  side: BorderSide(color: WfColors.border)),
              elevation: 6,
              shadowColor: Colors.black,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final reaction in PartyReaction.values)
                      Tooltip(
                        message: partyReactionLabel(l, reaction),
                        child: InkWell(
                          key: ValueKey('party-reaction-${reaction.id}'),
                          borderRadius:
                              BorderRadius.circular(PartyChatBubble.radius),
                          hoverColor: WfColors.cream
                              .withValues(alpha: PartyReactionsTray.hoverAlpha),
                          onTap: () {
                            widget.onReaction(reaction);
                            _restartIdle();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 3),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  reaction.emoji,
                                  style: const TextStyle(
                                    fontSize: PartyReactionsTray.emojiSize,
                                    height: 1.1,
                                    fontFamilyFallback:
                                        partyEmojiFontFallback,
                                  ),
                                ),
                                Text('${reaction.key}',
                                    style: const TextStyle(
                                        color: WfColors.creamMuted,
                                        fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/watch_party/party_reactions_tray_test.dart`
Expected: PASS (4 test).

- [ ] **Step 5: commit**

```bash
git add lib/features/watch_party/party_reactions_tray.dart test/features/watch_party/party_reactions_tray_test.dart
git commit -m "feat: add the watch party reactions tray"
```

### Task 4: pulsante delle reazioni nei controlli

**Files:**
- Modify: `lib/features/player/player_overlay.dart`
- Test: `test/features/player/player_overlay_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

In `test/features/player/player_overlay_test.dart`, nell'helper `pumpOverlay` aggiungi il parametro `bool reactions = false` e, nella costruzione di `PlayerOverlay`:

```dart
          onToggleReactions: reactions ? () => calls.add('reactions') : null,
          reactionsLink: reactions ? LayerLink() : null,
```

Poi il test:

```dart
  testWidgets('reazioni del watch party: pulsante (spec E §10.2)',
      (tester) async {
    final view = PlayerViewState(status: PlayerStatus.ready);
    await pumpOverlay(tester, view);
    expect(find.byTooltip('Reazioni (1–6)'), findsNothing);
    final calls = await pumpOverlay(tester, view, reactions: true);
    expect(find.byType(CompositedTransformTarget), findsOneWidget);
    await tester.tap(find.byTooltip('Reazioni (1–6)'));
    expect(calls, ['reactions']);
  });
```

- [ ] **Step 2: esegui il test e verifica che fallisca**

Run: `flutter test test/features/player/player_overlay_test.dart`
Expected: FAIL in compilazione (`onToggleReactions` non esiste).

- [ ] **Step 3: implementa**

In `PlayerOverlay` aggiungi al costruttore, dopo `this.chatUnread = false,`:

```dart
    this.onToggleReactions,
    this.reactionsLink,
```

e i campi, dopo `chatUnread`:

```dart

  /// Barretta delle reazioni del watch party (spec E §10.2): alle stesse
  /// condizioni della chat; `null` = nessun pulsante.
  final VoidCallback? onToggleReactions;

  /// Aggancio della barretta al pulsante (la barretta è un livello a sé del
  /// player).
  final LayerLink? reactionsLink;
```

Dopo il blocco `if (onToggleChat != null) PlayerIconButton(…),`:

```dart
                          if (onToggleReactions != null)
                            _anchored(
                              reactionsLink,
                              PlayerIconButton(
                                key: const Key('player-reactions-button'),
                                icon: const Icon(LucideIcons.smilePlus),
                                tooltip: l.partyReactionsOpen,
                                onPressed: onToggleReactions,
                              ),
                            ),
```

e, nella classe `PlayerOverlay`, il metodo:

```dart
  /// [child] agganciato a [link] (se c'è), per un livello che lo segue.
  static Widget _anchored(LayerLink? link, Widget child) => link == null
      ? child
      : CompositedTransformTarget(link: link, child: child);
```

- [ ] **Step 4: esegui i test e commit**

Run: `flutter test test/features/player/player_overlay_test.dart` → PASS; `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/player/player_overlay.dart test/features/player/player_overlay_test.dart
git commit -m "feat: add the reactions button to the player controls"
```

---

### Task 5: reazioni nel player

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

In fondo a `main()` di `test/features/watch_party/party_player_test.dart` (dopo gli helper e i test della chat; importa `package:wonderflix/features/watch_party/party_reactions_layer.dart` e, se serve, `package:wonderflix/core/party_channel/party_channel_models.dart`):

```dart
  Finder flying(String emoji) => find.descendant(
      of: find.byType(PartyReactionsLayer), matching: find.text(emoji));

  List<Map<String, dynamic>> sentReactions() => [
        for (final event in channelApi.sent)
          if (event is PartyOutgoingReaction) event.toJson(),
      ];

  testWidgets('reazioni: barretta dal pulsante, un clic manda e fa salire '
      '(spec E §10)', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('party-reaction-clap')));
    await tester.pump();
    await tester.pump();
    expect(sentReactions(), [
      {'Type': 'Reaction', 'Reaction': 'clap'},
    ]);
    expect(flying('👏'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(PartyReactionsLayer), matching: find.text('Tu')),
        findsOneWidget);
    await finish(tester);
  });

  testWidgets('reazioni: tasti 1–6, niente ripetizione, una ogni 200 ms',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(sentReactions(), [
      {'Type': 'Reaction', 'Reaction': 'joy'},
    ], reason: 'ripetizione ignorata, la seconda entro 200 ms scartata');
    await tester.pump(PlayerScreen.reactionInterval);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad6);
    await tester.pump();
    expect(sentReactions().last, {'Type': 'Reaction', 'Reaction': 'facepalm'});
    await finish(tester);
  });

  testWidgets('reazioni: a chat aperta i numeri vanno al campo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(sentReactions(), isEmpty);
    await finish(tester);
  });

  testWidgets('reazioni degli altri: emoji e nome', (tester) async {
    await pumpPartyPlayer(tester);
    events.add(PartyChannelReceived(
        partyPayload({'Type': 'Reaction', 'Reaction': 'joy'}, id: 'r1')));
    await tester.pump();
    await tester.pump();
    expect(flying('😂'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(PartyReactionsLayer),
            matching: find.text('Luigi')),
        findsOneWidget);
    await finish(tester);
  });

  testWidgets('barretta: Esc e clic sul film la chiudono; con la chat uno '
      'alla volta', (tester) async {
    await pumpPartyPlayer(tester);
    Finder trayVisible() => find.byWidgetPredicate((widget) =>
        widget is AnimatedOpacity &&
        widget.opacity == 1 &&
        widget.child is AnimatedScale);
    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    expect(trayVisible(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(trayVisible(), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget,
        reason: 'Esc chiude solo la barretta');

    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(trayVisible(), findsNothing);
    expect(api.calls, isNot(contains('unpause')),
        reason: 'il clic chiude e basta');

    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(trayVisible(), findsNothing);
    expect(find.byKey(const Key('party-chat-field')), findsOneWidget);
    await finish(tester);
  });
```

(Se `trayVisible()` non individua in modo univoco la barretta, cerca l'`AnimatedOpacity` discendente di `PartyReactionsTray`, importando `party_reactions_tray.dart`.)

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_player_test.dart`
Expected: i nuovi test FAIL; gli altri PASS.

- [ ] **Step 3: implementa**

In `lib/features/player/player_screen.dart`:

1. Import (in ordine): `import 'package:clock/clock.dart';` (con gli altri `package:`, se manca), `import '../watch_party/party_reactions_layer.dart';` e `import '../watch_party/party_reactions_tray.dart';` (con gli altri `../watch_party/`).

2. In `PlayerScreen` (la classe del widget), accanto alle altre costanti statiche:

```dart
  /// Al massimo una reazione ogni questo tempo, da tasti e barretta (spec E
  /// §10.3).
  static const reactionInterval = Duration(milliseconds: 200);
```

3. Nello stato, dopo `_openChatKeys`:

```dart

  /// Tasti delle reazioni (spec E §10.3): 1–6 e tastierino. Non `const`: le
  /// chiavi ridefiniscono `==`.
  static final _reactionKeys = {
    LogicalKeyboardKey.digit1: PartyReaction.joy,
    LogicalKeyboardKey.digit2: PartyReaction.scream,
    LogicalKeyboardKey.digit3: PartyReaction.cry,
    LogicalKeyboardKey.digit4: PartyReaction.wow,
    LogicalKeyboardKey.digit5: PartyReaction.clap,
    LogicalKeyboardKey.digit6: PartyReaction.facepalm,
    LogicalKeyboardKey.numpad1: PartyReaction.joy,
    LogicalKeyboardKey.numpad2: PartyReaction.scream,
    LogicalKeyboardKey.numpad3: PartyReaction.cry,
    LogicalKeyboardKey.numpad4: PartyReaction.wow,
    LogicalKeyboardKey.numpad5: PartyReaction.clap,
    LogicalKeyboardKey.numpad6: PartyReaction.facepalm,
  };

  /// Aggancio della barretta delle reazioni al suo pulsante.
  final _reactionsLink = LayerLink();

  /// Ultima reazione mandata (limite di [PlayerScreen.reactionInterval]).
  DateTime? _lastReactionAt;
```

4. Dopo `_chatAvailable`:

```dart

  /// Manda una reazione (tasti o barretta), al massimo una ogni
  /// [PlayerScreen.reactionInterval].
  void _sendReaction(PartyReaction reaction) {
    final now = clock.now();
    final last = _lastReactionAt;
    if (last != null && now.difference(last) < PlayerScreen.reactionInterval) {
      return;
    }
    _lastReactionAt = now;
    ref.read(partyChannelProvider.notifier).sendReaction(reaction);
  }
```

5. In `_onKey`, subito dopo il blocco che apre la chat con Invio (prima di `final command = _commandFor(event);`):

```dart
    // 1–6 mandano una reazione (spec E §10.3), solo con il focus al player:
    // niente controlli né pillola, e tenendo premuto non si ripete.
    final reaction = _reactionKeys[event.logicalKey];
    if (reaction != null && _focusNode.hasPrimaryFocus && _chatAvailable) {
      if (event is KeyDownEvent) _sendReaction(reaction);
      if (event is! KeyUpEvent) _chrome.keyActivity();
      return KeyEventResult.handled;
    }
```

6. Nel listener del canale spento (`partyChannelProvider.select((s) => s.active)`), dopo `_chrome.closePopup(PlayerPopup.chat);` aggiungi `_chrome.closePopup(PlayerPopup.reactions);`; lo stesso nel listener che stacca il player dal gruppo.

7. In `PlayerOverlay(…)`, dopo `chatUnread: …,`:

```dart
                        onToggleReactions: chatActive
                            ? () => _chrome.togglePopup(PlayerPopup.reactions)
                            : null,
                        reactionsLink: _reactionsLink,
```

8. Nello `Stack`, **prima** del `Positioned` con chiave `'player-party-chat'`:

```dart
                // Reazioni in volo (spec E §10.4): in basso a destra, sotto
                // la chat; non prendono i clic.
                if (chatActive)
                  const Positioned(
                    key: ValueKey('player-party-reactions'),
                    right: PartyReactionsLayer.right,
                    bottom: PartyReactionsLayer.bottom,
                    child: PartyReactionsLayer(),
                  ),
```

e **dopo** il `Positioned` della chat (prima della pillola):

```dart
                // Barretta delle reazioni (spec E §10.2): segue il suo
                // pulsante nei controlli; sopra chat, "Salta intro" e scheda.
                if (chatActive)
                  Positioned(
                    key: const ValueKey('player-party-reactions-tray'),
                    left: 0,
                    top: 0,
                    child: CompositedTransformFollower(
                      link: _reactionsLink,
                      showWhenUnlinked: false,
                      targetAnchor: Alignment.topRight,
                      followerAnchor: Alignment.bottomRight,
                      offset: const Offset(0, -PartyReactionsTray.gap),
                      child: ExcludeFocus(
                        child: PartyReactionsTray(
                          open: _chrome.popup == PlayerPopup.reactions,
                          onReaction: _sendReaction,
                          onClose: () =>
                              _chrome.closePopup(PlayerPopup.reactions),
                        ),
                      ),
                    ),
                  ),
```

(Esc e clic sul film chiudono già qualunque riquadro aperto: `_escape` e il `GestureDetector` del film usano `closePopup()`.)

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/watch_party/ test/features/player/`
Expected: PASS.

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/player/player_screen.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: send and show watch party reactions in the player"
```

---

### Task 6: documentazione, spec e verifica finale

**Files:**
- Modify: `docs/RELEASING.md`
- Modify: `docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md`

- [ ] **Step 1: release del plugin in `docs/RELEASING.md`**

In fondo al file aggiungi:

````markdown

## Plugin "WonderFlix Watch Party"

Il plugin del server (cartella `jellyfin-plugin-watch-party/`, spec E) ha versioni e release sue, separate dall'app.

1. Aggiorna `<Version>` in `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj` (es. `1.0.1`) e fai commit su `main`.
2. Prova a mano sul server (README del plugin: `pack.sh` e copia via SFTP nei `plugins/` di Jellyfin).
3. Crea il tag e fai push:
   ```bash
   git tag watch-party-plugin-v1.0.1
   git push origin watch-party-plugin-v1.0.1
   ```
4. Il workflow **Watch party plugin** pubblica una **pre-release** con `wonderflix-watch-party_1.0.1.zip` e `.zip.md5`. È sempre pre-release e mai "latest": l'app legge `releases/latest` per i propri aggiornamenti.
5. Aggiungi la versione in cima a `versions` in `jellyfin-plugin-watch-party/manifest.json` e fai push su `main`:
   ```json
   {
     "version": "1.0.1.0",
     "changelog": "…",
     "targetAbi": "10.11.0.0",
     "sourceUrl": "https://github.com/davidesidoti/wonderflix/releases/download/watch-party-plugin-v1.0.1/wonderflix-watch-party_1.0.1.zip",
     "checksum": "<contenuto del file .md5>",
     "timestamp": "2026-10-02T12:00:00Z"
   }
   ```
6. Sul server: Dashboard → Plugin → Catalogo → aggiorna (o installa) **WonderFlix Watch Party**, poi riavvia Jellyfin (su Ultra.cc: `app-jellyfin restart`).

Il repository dei plugin si aggiunge una volta sola: Dashboard → Plugin → Repository → **+**, URL `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/jellyfin-plugin-watch-party/manifest.json`. Prima di installare dal Catalogo togli un'eventuale cartella copiata a mano.

**Jellyfin 12:** serve una build nuova (net10.0, `targetAbi` `12.0.0.0`) prima di aggiornare il server.
````

- [ ] **Step 2: allinea lo spec**

1. Riga **Stato**: `approvato; piani 10a, 10b e 10c realizzati (…10a…, …10b…, docs/superpowers/plans/2026-10-02-wonderflix-10c-watch-party-reazioni.md)`.
2. **§10.2**: la barretta è un livello a sé agganciato al pulsante (`CompositedTransformTarget`/`Follower`), sempre montata (chiusa: invisibile e senza clic); entrata con dissolvenza e scala 0,9 → 1 (`medium`), uscita `fast`.
3. **§10.3**: i tasti valgono solo con il focus al player; il limite di 200 ms vale anche per i clic sulla barretta (`PlayerScreen.reactionInterval`).
4. **§10.4**: valori in `PartyReactionsLayer` (`reactionFrame`, `reactionJitter`); `right: 24`, `bottom: 150`.
5. **§11**: `PlayerPopup` ha `tracks`, `chat` e `reactions`; ordine dei livelli: …, attesa sopra il post-play, reazioni, chat, barretta, pillola, pannello.

- [ ] **Step 3: verifica completa**

Run:
- `flutter analyze` → `No issues found!`
- `flutter test` → tutto verde
- `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → tutto verde
- `git log --format=%B main..HEAD | grep -i -E "co-authored|generated with"` → nessuna riga

- [ ] **Step 4: commit**

```bash
git add docs/RELEASING.md docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md
git commit -m "docs: document the plugin release and align spec E with plan 10c"
```

---

## Dopo l'implementazione (orchestratore e utente)

1. Revisione finale, correzioni approvate, build di release nel worktree, **prova manuale** con due istanze: barretta (apertura, clic, chiusure, 5 s), tasti 1–6 e tastierino, tenere premuto, reazioni degli altri con il nome, molte reazioni insieme, animazioni "Complete" e "Ridotte" (Impostazioni → Aspetto), barretta sopra "Salta intro".
2. Con l'ok dell'utente: merge fast-forward su `main`, push, rimozione di worktree e branch.
3. **Plugin 1.0.0** (ogni push e tag con l'ok dell'utente):
   - tag `watch-party-plugin-v1.0.0` e push; attesa del workflow; lettura dell'MD5 dalla pre-release (`gh release view watch-party-plugin-v1.0.0`);
   - voce `1.0.0.0` in `manifest.json` (changelog: "Prima versione: nomi, chat e reazioni nel watch party di WonderFlix."), commit `chore: publish the watch party plugin 1.0.0`, push;
   - via `ssh ultra` (controllo prima che nessuno stia guardando): togliere `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.0.0.0`, `app-jellyfin restart`;
   - l'utente aggiunge il repository e installa dal Catalogo; poi `app-jellyfin restart` e controllo nei log (`Loaded plugin: "WonderFlix Watch Party"`).
4. **WonderFlix 0.5.0** (non obbligatoria): `version: 0.5.0` in `pubspec.yaml`, commit `chore: release 0.5.0`, tag `v0.5.0` e push con l'ok dell'utente, attesa della pipeline, note in italiano nella bozza (`gh release edit v0.5.0 --notes-file …`, senza `min-version`); la pubblicazione la fa l'utente.
