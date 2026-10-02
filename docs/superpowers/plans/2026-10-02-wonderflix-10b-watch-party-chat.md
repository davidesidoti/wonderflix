# WonderFlix — Piano 10b: chat del watch party nel player

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** secondo piano dello Spec E. La chat leggera del watch party nel player: bolle in basso a sinistra che svaniscono, campo con lo storico che si apre con Invio o con il pulsante, errori di invio, chiusura automatica, contatore dei non letti sul chip "Nel watch party" fuori dal player e puntino oro sul pulsante chat. La parte dati (`PartyChannel`) c'è già dal piano 10a.

**Decisioni prese con l'utente (2026-10-02):**
1. Posizione fissa: `left: 24`, `bottom: 150` (sopra la zona dei controlli, alta ~142 px; come "Salta intro" e la scheda del prossimo episodio a destra).
2. Il player ha un `FocusNode` suo; chiusa la chat il focus torna lì. Il campo tiene il focus quando si clicca sui controlli (`onTapOutside` vuoto); il clic sul **film** chiude la chat senza mettere in pausa.
3. A chat chiusa Invio (anche del tastierino) la apre, solo nel gruppo con il canale attivo. A chat aperta `_onKey` lascia passare tutto al campo tranne Esc, che chiude la chat.
4. Nel `PlayerChromeController` il pannello diventa un "riquadro" (`PlayerPopup.tracks`, `PlayerPopup.chat`; le reazioni nel 10c), uno alla volta. Con la chat i controlli si nascondono come sempre; la schermata "Stai guardando" non parte e si chiude all'apertura.
5. Bolle: max 3, 8 s ciascuna; entrata `medium` con 8 px verso l'alto (`emphasized`), uscita `fast` (`accelerate`); con le animazioni ridotte solo dissolvenza. Max 4 righe, larghezza max 360.
6. Campo e storico: storico alto al massimo il 40% della finestra, scende in fondo da solo coi messaggi nuovi se si era in fondo; limite di 200 punti di codice con un formatter (il `maxLength` di Flutter conta i grafemi); contatore da 180; invio fallito → riga rossa e testo rimesso (chat riaperta se era chiusa); chiusura da sola a campo vuoto dopo 20 s.
7. Emoji: `fontFamilyFallback: ['Segoe UI Emoji']` su bolle, storico e campo (verificato: Flutter le disegna a colori).
8. Non letti: contatore oro "1"…"9+" sul chip "Nel watch party" (riusa `CountBadge`); nel player puntino oro sul pulsante chat finché non la si apre. Il livello della chat si registra nel canale (`attachChatLayer`), così le bolle non contano come non lette.
9. Pulsante `LucideIcons.messageCircle`, tooltip "Chat (Invio)", al posto di "Guarda insieme" (che nel gruppo non c'è mai).
10. File nuovi: `lib/features/watch_party/party_chat_layer.dart` (livello, campo, storico, formatter) e `party_chat_bubble.dart` (riga, bolla, stile).

**Architecture:**
- `PlayerChromeController`: `PlayerPopup? popup`, `openPopup`, `closePopup`, `togglePopup`; `panelOpen`/`togglePanel`/`closePanel` restano come scorciatoie.
- `PartyChatEntry.key`: identità stabile di un messaggio per l'interfaccia (il nostro messaggio tiene la stessa chiave da "in attesa" a "confermato").
- `PartyChatLayer` (`ConsumerStatefulWidget`): ascolta `chatArrivals` per le bolle e legge `messages` per storico e contenuto delle bolle; manda con `sendChat`; `attachChatLayer`/`detachChatLayer` a montaggio e smontaggio; `markRead` all'apertura.
- `PlayerScreen`: `FocusNode`, Invio/Esc in `_onKey`, clic sul film, livello `player-party-chat` tra `player-party-waiting-post-play` e `player-pill-layer`, pulsante e puntino via `PlayerOverlay`.
- `PartyChip` con `count`, letto da `_InPartyButton`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, fake_async, lucide_icons_flutter.

**Spec:** `docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md` (§9, §11, §14). **Worktree:** `.claude/worktrees/piano-10b`, branch `feat/piano-10b`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves`), nemmeno come verbi normali.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree. Comandi git semplici, niente `git -C`, niente variabili nei comandi git. Prima dei comandi Flutter: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"`.
- **Prima di ogni commit:** `flutter analyze` senza problemi e `flutter test` tutto verde (a inizio piano: 1164 test). Se `flutter test`/`pub get` riscrivono `windows/flutter/generated_plugin*` con soli fine riga, `git checkout -- windows/flutter/`. Dopo una modifica agli ARB: `flutter gen-l10n` (`lib/l10n/gen/` non si committa).
- **Formattazione e fine riga:** niente `dart format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`).
- **Durate e misure:** costanti nominate e commentate, token di `WfMotion`. Commenti in italiano, codice in inglese. `clock.now()`, mai `DateTime.now()`.
- **Riverpod 3:** mai cambiare lo stato di un provider durante una build (`initState`, `didUpdateWidget`, `build`): si rimanda al fotogramma dopo. `ref.mounted`/`mounted` dopo ogni `await`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **Emoji:** con `fontFamily`/`fontFamilyFallback` `'Segoe UI Emoji'` Flutter su Windows disegna a colori le emoji di Windows (verificato il 2026-10-02 con un'immagine di prova).
- **Tasti e campi di testo:** gli eventi di un `TextField` con il focus risalgono a `_onKey` (il `Focus` del player è un antenato) **prima** delle scorciatoie di modifica del testo, che stanno sopra, in `WidgetsApp`. Se `_onKey` li gestisse, frecce e Backspace non funzionerebbero nel campo: con la chat aperta deve restituire `ignored` per tutto tranne Esc. Su Windows `EditableText` toglie il focus a ogni clic fuori dal campo: con `onTapOutside: (_) {}` il campo lo tiene. Con `onEditingComplete: () {}` il campo resta a fuoco dopo `onSubmitted`.
- **`find.text` e `Text.rich`:** `find.textContaining('ciao')` trova il testo di un `Text.rich`.
- **Nei test** `tester.sendKeyEvent` non scrive caratteri in un `TextField` (serve `tester.enterText`); `tester.testTextInput.receiveAction(TextInputAction.send)` chiama `onSubmitted`.
- **Clic sul film nei test:** `tester.tapAt(const Offset(700, 300))` e poi `tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50))`: il `GestureDetector` del film ha anche `onDoubleTap`.
- **Timer del gruppo:** entrando in un gruppo parte l'orologio del server (timer periodici). I test che entrano in un gruppo con `pumpApp` escono dal gruppo alla fine (`leave`), come `watch_party_actions_test.dart`.
- **`pumpPartyPlayer`** (`party_player_test.dart`) ha già `channelApi = FakePartyChannelApi()..install()` e l'override di `partyChannelApiProvider`; `events` è lo `StreamController<ServerEvent>` del WebSocket finto; i messaggi arrivano con `events.add(PartyChannelReceived(partyPayload({'Type': 'Chat', 'Text': …}, id: …)))`. Senza `WfMotionScope`, `WfMotion.of` è ridotto.
- **`Positioned` con solo `left`/`bottom`:** il figlio non ha un'altezza massima finita; l'altezza dello storico si calcola da `MediaQuery.sizeOf(context).height`.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `lib/features/player/player_chrome.dart` | modifica | `PlayerPopup`, riquadri uno alla volta |
| `lib/features/watch_party/party_channel.dart` | modifica | `PartyChatEntry.key` |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi della chat |
| `lib/features/watch_party/party_chat_bubble.dart` | crea | stile del testo, riga, bolla, bolla animata |
| `lib/features/watch_party/party_chat_layer.dart` | crea | livello della chat, `ChatLengthFormatter` |
| `lib/features/player/player_overlay.dart` | modifica | pulsante chat e puntino |
| `lib/features/player/player_screen.dart` | modifica | focus, tasti, clic sul film, livello |
| `lib/ui/poster_card.dart` | modifica | `CountBadge.max` |
| `lib/features/watch_party/party_badge.dart`, `watch_party_button.dart` | modifica | contatore sul chip |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md` | modifica | allineamento |

## Gruppi per i subagent

- **Gruppo A (Task 1–2):** riquadri del player, testi, chiave dei messaggi.
- **Gruppo B (Task 3–5):** livello della chat da solo.
- **Gruppo C (Task 6–7):** pulsante e integrazione nel player.
- **Gruppo D (Task 8):** contatore sul chip "Nel watch party".
- **Gruppo E (Task 9):** spec e verifica finale.

---

## Gruppo A — fondamenta

### Task 1: riquadri del player (`PlayerPopup`)

**Files:**
- Modify: `lib/features/player/player_chrome.dart`
- Test: `test/features/player/player_chrome_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

In fondo a `main()` di `test/features/player/player_chrome_test.dart`:

```dart
  test('chat (spec E §9.6): i controlli si nascondono, la pausa non compare',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      chrome.openPopup(PlayerPopup.chat);
      expect(chrome.chatOpen, isTrue);
      expect(chrome.panelOpen, isFalse);
      async.elapse(PlayerChromeController.hideDelay);
      expect(chrome.controlsVisible, isFalse,
          reason: 'la chat non tiene su i controlli');
      chrome.setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(const Duration(seconds: 20));
      expect(chrome.pauseScreen, isFalse);
      chrome.closePopup(PlayerPopup.chat);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      expect(chrome.pauseScreen, isTrue);
      chrome.openPopup(PlayerPopup.chat);
      expect(chrome.pauseScreen, isFalse, reason: 'aprire la chat la chiude');
      chrome.dispose();
    });
  });

  test('un riquadro alla volta: tracce e chat si sostituiscono', () {
    final chrome = PlayerChromeController();
    var notified = 0;
    chrome.addListener(() => notified++);
    chrome.openPopup(PlayerPopup.chat);
    chrome.togglePanel();
    expect(chrome.popup, PlayerPopup.tracks);
    expect(chrome.chatOpen, isFalse);
    chrome.closePopup(PlayerPopup.chat);
    expect(chrome.panelOpen, isTrue,
        reason: 'chiude solo il riquadro indicato');
    chrome.closePopup();
    expect(chrome.popup, isNull);
    chrome.togglePopup(PlayerPopup.chat);
    chrome.togglePopup(PlayerPopup.chat);
    expect(chrome.popup, isNull);
    expect(notified, 5);
    chrome.dispose();
  });
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/player/player_chrome_test.dart`
Expected: FAIL in compilazione (`PlayerPopup`, `openPopup`, … non esistono).

- [ ] **Step 3: implementa**

In `lib/features/player/player_chrome.dart`, prima di `class PlayerChromeController`:

```dart
/// Riquadri del player che si aprono uno alla volta (spec E §11): il
/// pannello "Audio e sottotitoli" e la chat del watch party.
enum PlayerPopup { tracks, chat }

```

Sostituisci il campo `bool _panelOpen = false;` con:

```dart
  PlayerPopup? _popup;
```

Sostituisci `bool get panelOpen => _panelOpen;` con:

```dart
  /// Riquadro aperto; `null` = nessuno.
  PlayerPopup? get popup => _popup;

  bool get panelOpen => _popup == PlayerPopup.tracks;

  bool get chatOpen => _popup == PlayerPopup.chat;
```

Sostituisci i metodi `togglePanel` e `closePanel` con:

```dart
  /// Apre [popup], chiudendo l'altro. Il pannello "Audio e sottotitoli"
  /// mostra i controlli e li tiene su; la chat no (spec E §9.6). Tutti e due
  /// chiudono la schermata di pausa.
  void openPopup(PlayerPopup popup) {
    if (_popup == popup) return;
    _popup = popup;
    _pauseScreen = false;
    if (popup == PlayerPopup.tracks) _controlsVisible = true;
    notifyListeners();
    _scheduleHide();
  }

  /// Chiude [popup] se è quello aperto; senza argomento chiude quello
  /// aperto.
  void closePopup([PlayerPopup? popup]) {
    if (_popup == null || (popup != null && _popup != popup)) return;
    _popup = null;
    notifyListeners();
    _scheduleHide();
  }

  void togglePopup(PlayerPopup popup) {
    if (_popup == popup) {
      closePopup(popup);
    } else {
      openPopup(popup);
    }
  }

  /// Apre o chiude il pannello "Audio e sottotitoli": i controlli si vedono
  /// e, a pannello aperto, restano.
  void togglePanel() => togglePopup(PlayerPopup.tracks);

  void closePanel() => closePopup(PlayerPopup.tracks);
```

In `_scheduleHide` sostituisci il commento e la riga `if (_panelOpen) return;`:

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
```

con:

```dart
  /// In riproduzione i controlli si nascondono dopo [hideDelay]; in pausa,
  /// se ammessa, dopo [pauseScreenDelay] compare la schermata di pausa (e i
  /// controlli si nascondono). Con il pannello aperto nessuno dei due; con
  /// la chat aperta i controlli si nascondono ma la schermata di pausa non
  /// parte (si sta scrivendo, spec E §9.6).
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    if (_popup == PlayerPopup.tracks) return;
```

e la condizione `} else if (_canShowPauseScreen && !_pauseScreen) {` con:

```dart
    } else if (_canShowPauseScreen &&
        !_pauseScreen &&
        _popup != PlayerPopup.chat) {
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/player/`
Expected: PASS (anche i test esistenti del pannello e dello schermo).

- [ ] **Step 5: commit**

```bash
git add lib/features/player/player_chrome.dart test/features/player/player_chrome_test.dart
git commit -m "feat: open one player popup at a time"
```

### Task 2: testi della chat e chiave stabile dei messaggi

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify: `lib/features/watch_party/party_channel.dart` (`PartyChatEntry`, `sendChat`)
- Test: `test/features/watch_party/party_channel_test.dart`

- [ ] **Step 1: testi**

In `l10n/app_it.arb`, subito dopo la riga di `"watchPartyNoticeRemoved"`:

```json
  "partyChatYou": "Tu",
  "partyChatOpen": "Chat (Invio)",
  "partyChatHint": "Scrivi un messaggio…",
  "partyChatNotSent": "Non inviato, riprova",
  "partyChatTooMany": "Troppi messaggi, aspetta un attimo",
```

In `l10n/app_en.arb`, subito dopo la riga di `"watchPartyNoticeRemoved"`:

```json
  "partyChatYou": "You",
  "partyChatOpen": "Chat (Enter)",
  "partyChatHint": "Write a message…",
  "partyChatNotSent": "Not sent, try again",
  "partyChatTooMany": "Too many messages, wait a moment",
```

Run: `flutter gen-l10n`.

- [ ] **Step 2: scrivi il test che fallisce**

In `test/features/watch_party/party_channel_test.dart`, nel test `'sendChat: subito in attesa, poi confermato'`, dopo `expect(chats.single.pending, isTrue);` aggiungi:

```dart
      final key = chats.single.key;
      expect(key, startsWith('local-'));
```

e dopo `expect(channel().messages.single.event.id, 'srv-1');`:

```dart
      expect(channel().messages.single.key, key,
          reason: 'la bolla del nostro messaggio resta la stessa');
```

Nel test `'ricezione: annunci agli avvisi, chat, reazioni'`, dopo `expect(chats.single.event.userName, 'Luigi');`:

```dart
      expect(chats.single.key, 'c1', reason: 'i messaggi altrui: l\'id');
```

- [ ] **Step 3: esegui il test e verifica che fallisca**

Run: `flutter test test/features/watch_party/party_channel_test.dart`
Expected: FAIL in compilazione (`key` non esiste).

- [ ] **Step 4: implementa**

In `lib/features/watch_party/party_channel.dart` sostituisci la classe `PartyChatEntry`:

```dart
/// Un messaggio della chat.
class PartyChatEntry {
  const PartyChatEntry(this.event, {required this.mine, this.pending = false});
```

con:

```dart
/// Un messaggio della chat.
class PartyChatEntry {
  PartyChatEntry(this.event,
      {required this.mine, this.pending = false, String? key})
      : key = key ?? event.id;
```

e aggiungi, dopo il campo `pending`:

```dart

  /// Identità del messaggio per l'interfaccia: l'`id` dell'evento; per i
  /// nostri messaggi quello locale anche dopo la conferma, così la bolla e
  /// la riga dello storico restano le stesse (spec E §9.4).
  final String key;
```

In `sendChat` sostituisci:

```dart
      final confirmed = PartyChatEntry(
          stamped is PartyChatEvent ? stamped : local.event,
          mine: true);
```

con:

```dart
      final confirmed = PartyChatEntry(
          stamped is PartyChatEvent ? stamped : local.event,
          mine: true,
          key: local.key);
```

(Se altrove nel codice o nei test compare `const PartyChatEntry(`, togli il `const`.)

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add l10n/app_it.arb l10n/app_en.arb lib/features/watch_party/party_channel.dart test/features/watch_party/party_channel_test.dart
git commit -m "feat: add chat strings and stable chat message keys"
```

---

## Gruppo B — il livello della chat

### Task 3: riga, bolla e stile del testo

**Files:**
- Create: `lib/features/watch_party/party_chat_bubble.dart`
- Create: `test/features/watch_party/party_chat_bubble_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

Crea `test/features/watch_party/party_chat_bubble_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_chat_bubble.dart';

import '../../support/pump_app.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  PartyChatEntry entry(String text,
          {bool mine = false, bool pending = false}) =>
      PartyChatEntry(testChatEvent(text), mine: mine, pending: pending);

  testWidgets('riga: nome in oro e testo, emoji di Windows come ripiego',
      (tester) async {
    await pumpApp(
        tester, Scaffold(body: PartyChatMessage(entry: entry('che scena'))));
    expect(find.textContaining('Luigi'), findsOneWidget);
    expect(find.textContaining('che scena'), findsOneWidget);
    final rich = tester.widget<Text>(find.byType(Text).first);
    expect(rich.style?.fontFamilyFallback, ['Segoe UI Emoji']);
    final name = (rich.textSpan! as TextSpan).children!.first as TextSpan;
    expect(name.style?.color, WfColors.gold);
  });

  testWidgets('i nostri: "Tu"; in attesa più trasparenti', (tester) async {
    await pumpApp(
        tester,
        Scaffold(
            body: PartyChatMessage(
                entry: entry('ci siamo', mine: true, pending: true))));
    expect(find.textContaining('Tu'), findsOneWidget);
    expect(find.textContaining('Luigi'), findsNothing);
    expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        PartyChatMessage.pendingOpacity);
  });

  testWidgets('bolla: al massimo 4 righe e 360 px', (tester) async {
    await pumpApp(
        tester,
        Scaffold(
            body: Align(
                alignment: Alignment.bottomLeft,
                child: PartyChatBubble(entry: entry('parola ' * 200)))));
    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.maxLines, PartyChatBubble.maxLines);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.byType(PartyChatBubble)).width,
        lessThanOrEqualTo(PartyChatBubble.width));
  });

  testWidgets('bolla animata: esce sfumando e poi avvisa', (tester) async {
    var gone = 0;
    final leaving = ValueNotifier(false);
    await pumpApp(
        tester,
        Scaffold(
            body: ValueListenableBuilder<bool>(
                valueListenable: leaving,
                builder: (context, isLeaving, _) => AnimatedChatBubble(
                    entry: entry('ciao'),
                    leaving: isLeaving,
                    onGone: () => gone++))));
    await tester.pump(const Duration(seconds: 1));
    expect(gone, 0);
    leaving.value = true;
    await tester.pumpAndSettle();
    expect(gone, 1);
  });
}
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_chat_bubble_test.dart`
Expected: FAIL in compilazione (`party_chat_bubble.dart` non esiste).

- [ ] **Step 3: implementa**

Crea `lib/features/watch_party/party_chat_bubble.dart`:

```dart
import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'party_channel.dart';

/// Ripiego per le emoji scritte nella chat: quelle a colori di Windows
/// (spec E §9.1).
const partyEmojiFontFallback = ['Segoe UI Emoji'];

/// Testo della chat: crema, con le emoji di Windows come ripiego. Il font
/// resta quello dell'app (si eredita).
const partyChatTextStyle = TextStyle(
  color: WfColors.cream,
  fontSize: 14,
  height: 1.35,
  fontFamilyFallback: partyEmojiFontFallback,
);

/// Una riga della chat: nome in oro e testo (spec E §9.1). I nostri
/// messaggi non ancora confermati sono più trasparenti (§9.4).
class PartyChatMessage extends StatelessWidget {
  const PartyChatMessage({super.key, required this.entry, this.maxLines});

  /// Opacità di un nostro messaggio non ancora confermato.
  static const pendingOpacity = 0.6;

  final PartyChatEntry entry;

  /// `null` = tutte le righe (storico).
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = entry.mine ? l.partyChatYou : entry.event.userName;
    return Opacity(
      opacity: entry.pending ? pendingOpacity : 1,
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: name,
              style: const TextStyle(
                  color: WfColors.gold, fontWeight: FontWeight.w600)),
          const TextSpan(text: '  '),
          TextSpan(text: entry.event.text),
        ]),
        style: partyChatTextStyle,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}

/// Bolla della chat chiusa: un messaggio su fondo scuro, al massimo
/// [maxLines] righe (spec E §9.2).
class PartyChatBubble extends StatelessWidget {
  const PartyChatBubble({super.key, required this.entry});

  /// Larghezza massima di bolle, storico e campo.
  static const width = 360.0;
  static const maxLines = 4;
  static const radius = 10.0;

  /// Opacità del fondo.
  static const backgroundAlpha = 0.72;

  /// Spazio sopra ogni bolla.
  static const gap = 6.0;

  final PartyChatEntry entry;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: width),
        margin: const EdgeInsets.only(top: gap),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: WfColors.bg.withValues(alpha: backgroundAlpha),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: PartyChatMessage(entry: entry, maxLines: maxLines),
      );
}

/// Una bolla che entra (dissolvenza e [rise] px verso l'alto; con le
/// animazioni ridotte solo dissolvenza) ed esce sfumando quando [leaving]
/// diventa `true`; finita l'uscita chiama [onGone].
class AnimatedChatBubble extends StatelessWidget {
  const AnimatedChatBubble({
    super.key,
    required this.entry,
    required this.leaving,
    required this.onGone,
  });

  /// Di quanto sale entrando.
  static const rise = 8.0;

  final PartyChatEntry entry;
  final bool leaving;
  final VoidCallback onGone;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    return AnimatedOpacity(
      opacity: leaving ? 0 : 1,
      duration: WfMotion.fast,
      curve: WfMotion.accelerate,
      onEnd: leaving ? onGone : null,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motion.duration(WfMotion.medium),
        curve: WfMotion.emphasized,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, motion.isReduced ? 0 : (1 - t) * rise),
            child: child,
          ),
        ),
        child: PartyChatBubble(entry: entry),
      ),
    );
  }
}
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/watch_party/party_chat_bubble_test.dart`
Expected: PASS (4 test).

- [ ] **Step 5: commit**

```bash
git add lib/features/watch_party/party_chat_bubble.dart test/features/watch_party/party_chat_bubble_test.dart
git commit -m "feat: add the watch party chat message and bubble"
```

### Task 4: livello della chat — bolle a chat chiusa

**Files:**
- Create: `lib/features/watch_party/party_chat_layer.dart`
- Create: `test/features/watch_party/party_chat_layer_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

Crea `test/features/watch_party/party_chat_layer_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_chat_bubble.dart';
import 'package:wonderflix/features/watch_party/party_chat_layer.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakePartyChannelApi channelApi;
  late StreamController<ServerEvent> events;
  late ValueNotifier<bool> open;

  setUp(() {
    api = FakeSyncPlayApi();
    channelApi = FakePartyChannelApi()..install();
    events = StreamController<ServerEvent>.broadcast();
    open = ValueNotifier(false);
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined(
            'g1', testGroup(participants: ['Mario', 'Luigi']))));
      }
    };
  });

  tearDown(() => events.close());

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PartyChatLayer)));

  PartyChannelState channel(WidgetTester tester) =>
      container(tester).read(partyChannelProvider);

  /// Il livello della chat in basso a sinistra, nel gruppo `g1` con il
  /// canale attivo. [open] decide se è aperta.
  Future<void> pumpChat(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Stack(children: [
          Positioned(
            left: PartyChatLayer.left,
            bottom: PartyChatLayer.bottom,
            child: ValueListenableBuilder<bool>(
              valueListenable: open,
              builder: (context, isOpen, _) => PartyChatLayer(
                open: isOpen,
                onOpen: () => open.value = true,
                onClose: () => open.value = false,
              ),
            ),
          ),
        ]),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider.overrideWithValue(channelApi),
      ],
    );
    unawaited(
        container(tester).read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pump();
    await tester.pump();
    expect(channel(tester).active, isTrue);
  }

  /// Esce dal gruppo: l'orologio del gruppo non deve lasciare timer.
  Future<void> leave(WidgetTester tester) async {
    await container(tester).read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  Future<void> receive(WidgetTester tester, String text,
      {required String id, String userId = 'u2', String userName = 'Luigi'}) async {
    events.add(PartyChannelReceived(partyPayload({'Type': 'Chat', 'Text': text},
        id: id, userId: userId, userName: userName)));
    await tester.pump();
    await tester.pump();
  }

  Finder bubbles() => find.byType(PartyChatBubble);

  group('chat chiusa: bolle (spec E §9.2)', () {
    testWidgets('nome e testo; spariscono dopo 8 s', (tester) async {
      await pumpChat(tester);
      await receive(tester, 'ciao a tutti', id: 'c1');
      expect(bubbles(), findsOneWidget);
      expect(find.textContaining('Luigi'), findsOneWidget);
      expect(find.textContaining('ciao a tutti'), findsOneWidget);
      await tester.pump(PartyChatLayer.bubbleLifetime -
          const Duration(milliseconds: 1));
      expect(bubbles(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(WfMotion.fast);
      await tester.pump();
      expect(bubbles(), findsNothing);
      await leave(tester);
    });

    testWidgets('al massimo 3: la più vecchia lascia il posto',
        (tester) async {
      await pumpChat(tester);
      for (var i = 1; i <= 4; i++) {
        await receive(tester, 'messaggio $i', id: 'c$i');
      }
      expect(bubbles(), findsNWidgets(PartyChatLayer.maxBubbles));
      expect(find.textContaining('messaggio 1'), findsNothing);
      expect(find.textContaining('messaggio 4'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('i nostri da un altro PC: "Tu"', (tester) async {
      await pumpChat(tester);
      await receive(tester, 'dal portatile',
          id: 'c1', userId: 'u1', userName: 'Mario');
      expect(find.textContaining('Tu'), findsOneWidget);
      expect(find.textContaining('Mario'), findsNothing);
      await leave(tester);
    });

    testWidgets('a schermo i messaggi non contano come non letti',
        (tester) async {
      await pumpChat(tester);
      await receive(tester, 'ciao', id: 'c1');
      expect(channel(tester).unread, 0);
      await leave(tester);
    });

    testWidgets('le bolle non prendono i clic', (tester) async {
      await pumpChat(tester);
      await receive(tester, 'ciao', id: 'c1');
      expect(
          find.ancestor(of: bubbles(), matching: find.byType(IgnorePointer)),
          findsWidgets);
      await leave(tester);
    });
  });
}
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_chat_layer_test.dart`
Expected: FAIL in compilazione (`party_chat_layer.dart` non esiste).

- [ ] **Step 3: implementa (parte chiusa e struttura)**

Crea `lib/features/watch_party/party_chat_layer.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/party_channel/party_channel_models.dart';
import 'party_channel.dart';
import 'party_chat_bubble.dart';

/// Tiene il testo entro [maxChatLength] punti di codice, come il plugin.
/// Il `maxLength` di Flutter conta i grafemi: alcune emoji composte
/// supererebbero il limite del server.
class ChatLengthFormatter extends TextInputFormatter {
  const ChatLengthFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (chatTextLength(newValue.text) <= maxChatLength) return newValue;
    final text = String.fromCharCodes(newValue.text.runes.take(maxChatLength));
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// La chat del watch party nel player (spec E §9), in basso a sinistra.
/// Chiusa, i messaggi in arrivo compaiono come bolle che svaniscono; aperta,
/// il campo per scrivere con lo storico sopra. Apertura e chiusura le
/// decide chi la monta (`PlayerScreen`), con [onOpen] e [onClose].
class PartyChatLayer extends ConsumerStatefulWidget {
  const PartyChatLayer({
    super.key,
    required this.open,
    required this.onOpen,
    required this.onClose,
  });

  final bool open;

  /// Riapre la chat (un messaggio non inviato torna nel campo).
  final VoidCallback onOpen;

  /// Chiude la chat (Invio a campo vuoto, chiusura automatica).
  final VoidCallback onClose;

  /// Posizione nel player: margine dei controlli, appena sopra la loro zona
  /// (come "Salta intro" e la scheda del prossimo episodio a destra).
  static const left = 24.0;
  static const bottom = 150.0;

  /// Quanto resta una bolla.
  static const bubbleLifetime = Duration(seconds: 8);

  /// Bolle insieme al massimo.
  static const maxBubbles = 3;

  /// Chat aperta con il campo vuoto e senza attività: si chiude da sola.
  static const idleClose = Duration(seconds: 20);

  /// Altezza massima dello storico rispetto alla finestra.
  static const historyHeightFraction = 0.4;

  /// Il contatore dei caratteri compare da qui.
  static const counterFrom = 180;

  @override
  ConsumerState<PartyChatLayer> createState() => _PartyChatLayerState();
}

/// Una bolla: il messaggio (la `key` di `PartyChatEntry`), il suo conto
/// alla rovescia e se sta uscendo.
class _Bubble {
  _Bubble(this.key);

  final String key;
  bool leaving = false;
  Timer? timer;
}

class _PartyChatLayerState extends ConsumerState<PartyChatLayer> {
  /// Distanza dal fondo entro cui lo storico segue i messaggi nuovi.
  static const _stickToEndSlack = 24.0;

  late final PartyChannel _channel;
  late final StreamSubscription<PartyChatEntry> _arrivals;
  final _bubbles = <_Bubble>[];
  final _field = TextEditingController();
  final _fieldFocus = FocusNode(debugLabel: 'party-chat');
  final _scroll = ScrollController();
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _channel = ref.read(partyChannelProvider.notifier)..attachChatLayer();
    _arrivals = _channel.chatArrivals.listen(_onArrival);
    _field.addListener(_onTextChanged);
    if (widget.open) _onOpened();
  }

  @override
  void didUpdateWidget(PartyChatLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      _onOpened();
    } else {
      _onClosed();
    }
  }

  @override
  void dispose() {
    _channel.detachChatLayer();
    unawaited(_arrivals.cancel());
    _idleTimer?.cancel();
    for (final bubble in _bubbles) {
      bubble.timer?.cancel();
    }
    _field.dispose();
    _fieldFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onOpened() {
    // Lo storico prende il posto delle bolle.
    for (final bubble in _bubbles) {
      bubble.timer?.cancel();
    }
    _bubbles.clear();
    _restartIdle();
    // Dopo il fotogramma: qui si è dentro una build (lo stato dei provider
    // non si cambia, e il campo non esiste ancora).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.open) return;
      _channel.markRead();
      _fieldFocus.requestFocus();
      _jumpToEnd();
    });
  }

  void _onClosed() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _onArrival(PartyChatEntry entry) {
    if (!mounted) return;
    if (widget.open) {
      // Chat aperta: il messaggio è nello storico; si scende in fondo se si
      // era già in fondo.
      final atEnd = !_scroll.hasClients ||
          _scroll.position.extentAfter < _stickToEndSlack;
      setState(() {});
      if (atEnd) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
      return;
    }
    final bubble = _Bubble(entry.key);
    bubble.timer = Timer(PartyChatLayer.bubbleLifetime, () => _leave(bubble));
    setState(() {
      _bubbles.add(bubble);
      while (_bubbles.length > PartyChatLayer.maxBubbles) {
        _bubbles.removeAt(0).timer?.cancel();
      }
    });
  }

  void _leave(_Bubble bubble) {
    if (!mounted) return;
    setState(() => bubble.leaving = true);
  }

  void _remove(_Bubble bubble) {
    if (!mounted) return;
    setState(() => _bubbles.remove(bubble));
  }

  void _jumpToEnd() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _onTextChanged() {
    _restartIdle();
    if (mounted) setState(() {});
  }

  void _restartIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!widget.open) return;
    _idleTimer = Timer(PartyChatLayer.idleClose, () {
      if (mounted && widget.open && _field.text.trim().isEmpty) {
        widget.onClose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(partyChannelProvider.select((s) => s.messages));
    return widget.open
        ? _buildOpen(context, messages)
        : _buildBubbles(messages);
  }

  Widget _buildBubbles(List<PartyChatEntry> messages) {
    final byKey = {for (final entry in messages) entry.key: entry};
    // Le bolle non prendono i clic: sotto c'è il film.
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final bubble in _bubbles)
            if (byKey[bubble.key] case final entry?)
              AnimatedChatBubble(
                key: ValueKey('party-chat-bubble-${bubble.key}'),
                entry: entry,
                leaving: bubble.leaving,
                onGone: () => _remove(bubble),
              ),
        ],
      ),
    );
  }

  // Parte aperta: Task 5.
  Widget _buildOpen(BuildContext context, List<PartyChatEntry> messages) =>
      const SizedBox.shrink();
}
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/watch_party/party_chat_layer_test.dart`
Expected: PASS (5 test). Gli import del test `package:flutter/services.dart` e `package:wonderflix/core/party_channel/party_channel_api.dart` servono solo al Task 5: in questo task toglili (li rimette il Task 5). Se l'analyzer segnala come inutilizzati `_fieldFocus`, `_scroll`, `_field` o `_stickToEndSlack`, non succede: sono già usati qui; se segnala altro, sposta quell'elemento nel Task 5.

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/watch_party/party_chat_layer.dart test/features/watch_party/party_chat_layer_test.dart
git commit -m "feat: show watch party chat bubbles in the player"
```

### Task 5: livello della chat — campo, storico, errori

**Files:**
- Modify: `lib/features/watch_party/party_chat_layer.dart` (`_buildOpen`)
- Test: `test/features/watch_party/party_chat_layer_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

In `party_chat_layer_test.dart` (con gli import di `services.dart` e `party_channel_api.dart`), dopo il gruppo delle bolle, dentro `main()`:

```dart
  Finder field() => find.byKey(const Key('party-chat-field'));

  Future<void> openChat(WidgetTester tester) async {
    open.value = true;
    await tester.pump();
    await tester.pump();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(field(), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump();
  }

  group('chat aperta (spec E §9.3, §9.4)', () {
    testWidgets('campo a fuoco e storico al posto delle bolle',
        (tester) async {
      await pumpChat(tester);
      await receive(tester, 'primo', id: 'c1');
      await receive(tester, 'secondo', id: 'c2');
      await openChat(tester);
      expect(field(), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'party-chat');
      expect(find.byKey(const Key('party-chat-history')), findsOneWidget);
      expect(find.textContaining('primo'), findsOneWidget);
      expect(find.textContaining('secondo'), findsOneWidget);
      expect(find.byType(PartyChatBubble), findsNothing);
      await leave(tester);
    });

    testWidgets('Invio manda: in attesa, poi confermato; il campo si svuota',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      channelApi.sendGate = Completer<void>();
      await send(tester, 'che scena');
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'party-chat',
          reason: 'si continua a scrivere');
      Finder pending() => find.byWidgetPredicate((widget) =>
          widget is Opacity &&
          widget.opacity == PartyChatMessage.pendingOpacity);
      expect(find.textContaining('che scena'), findsOneWidget);
      expect(pending(), findsOneWidget);
      channelApi.sendGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(pending(), findsNothing);
      expect(find.textContaining('che scena'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('Invio a campo vuoto chiude', (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      await send(tester, '   ');
      expect(open.value, isFalse);
      expect(field(), findsNothing);
      expect(channelApi.sent, isEmpty);
      await leave(tester);
    });

    testWidgets('troppi messaggi: testo rimesso e riga rossa, che sparisce '
        'al tasto dopo', (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      channelApi.sendFailures.add(PartyChannelFailure.rateLimited);
      await send(tester, 'ciao');
      expect(tester.widget<TextField>(field()).controller!.text, 'ciao');
      expect(find.text('Troppi messaggi, aspetta un attimo'), findsOneWidget);
      await tester.enterText(field(), 'ciao!');
      await tester.pump();
      expect(find.text('Troppi messaggi, aspetta un attimo'), findsNothing);
      await leave(tester);
    });

    testWidgets('invio fallito a chat chiusa: si riapre con il testo',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      channelApi.sendGate = Completer<void>();
      channelApi.sendFailures.add(PartyChannelFailure.network);
      await send(tester, 'ci siete?');
      open.value = false;
      await tester.pump();
      channelApi.sendGate!.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(open.value, isTrue);
      expect(tester.widget<TextField>(field()).controller!.text, 'ci siete?');
      expect(find.text('Non inviato, riprova'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('contatore da 180; limite di 200 punti di codice',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      await tester.enterText(field(), 'x' * 179);
      await tester.pump();
      expect(find.text('179/200'), findsNothing);
      await tester.enterText(field(), 'x' * 180);
      await tester.pump();
      expect(find.text('180/200'), findsOneWidget);
      await tester.enterText(field(), '😂' * 250);
      await tester.pump();
      expect(
          tester.widget<TextField>(field()).controller!.text.runes.length, 200);
      await leave(tester);
    });

    testWidgets('a campo vuoto si chiude da sola dopo 20 s; con del testo no',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      await tester.pump(PartyChatLayer.idleClose);
      expect(open.value, isFalse);
      await openChat(tester);
      await tester.enterText(field(), 'sto scrivendo');
      await tester.pump(PartyChatLayer.idleClose + const Duration(seconds: 1));
      expect(open.value, isTrue);
      await leave(tester);
    });

    testWidgets('aprire la chat azzera i non letti', (tester) async {
      await pumpChat(tester);
      final notifier = container(tester).read(partyChannelProvider.notifier)
        // Come fuori dal player: nessun livello chat a schermo.
        ..detachChatLayer();
      await receive(tester, 'mentre eri via', id: 'c1');
      expect(channel(tester).unread, 1);
      notifier.attachChatLayer();
      await openChat(tester);
      expect(channel(tester).unread, 0);
      await leave(tester);
    });

    testWidgets('messaggio in arrivo a chat aperta: nello storico, niente bolla',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      await receive(tester, 'eccomi', id: 'c1');
      expect(find.textContaining('eccomi'), findsOneWidget);
      expect(find.byType(PartyChatBubble), findsNothing);
      await leave(tester);
    });
  });
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_chat_layer_test.dart`
Expected: i test del gruppo "chat aperta" FAIL (nessun campo); le bolle PASS.

- [ ] **Step 3: implementa la parte aperta**

In `party_chat_layer.dart` aggiungi gli import (in ordine):

```dart
import 'package:flutter/gestures.dart';
```

```dart
import '../../app/theme.dart';
```

```dart
import '../../l10n/gen/app_localizations.dart';
```

In `_PartyChatLayerState`, dopo `_stickToEndSlack`:

```dart

  /// Opacità del fondo dello storico.
  static const _historyAlpha = 0.55;
```

dopo `Timer? _idleTimer;`:

```dart

  /// Esito dell'ultimo invio non riuscito: la riga rossa sotto il campo.
  PartyChatSendResult? _error;
```

sostituisci `_onTextChanged` con:

```dart
  void _onTextChanged() {
    _restartIdle();
    // Il tasto dopo un errore toglie la riga rossa.
    if (mounted) setState(() => _error = null);
  }
```

e dopo `_restartIdle` aggiungi:

```dart

  Future<void> _submit(String value) async {
    final text = normalizeChatText(value);
    _field.clear();
    if (text.isEmpty) {
      widget.onClose();
      return;
    }
    final result = await _channel.sendChat(text);
    if (!mounted || result == PartyChatSendResult.sent) return;
    // Non inviato: il testo torna nel campo (se intanto non se n'è scritto
    // altro) e la chat si riapre, con la riga rossa (spec E §9.4). La riga
    // si imposta dopo il testo: rimetterlo passa da `_onTextChanged`.
    if (_field.text.isEmpty) {
      _field.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    setState(() => _error = result);
    if (!widget.open) widget.onOpen();
  }
```

Poi sostituisci:

```dart
  // Parte aperta: Task 5.
  Widget _buildOpen(BuildContext context, List<PartyChatEntry> messages) =>
      const SizedBox.shrink();
```

con:

```dart
  Widget _buildOpen(BuildContext context, List<PartyChatEntry> messages) {
    final l = AppLocalizations.of(context);
    final length = chatTextLength(_field.text);
    final error = _error;
    final maxHistory = MediaQuery.sizeOf(context).height *
        PartyChatLayer.historyHeightFraction;
    return Listener(
      // La rotella sopra la chat aperta non cambia il volume: scorre lo
      // storico (che, più interno, si registra prima) o non fa nulla.
      onPointerSignal: (event) => GestureBinding.instance.pointerSignalResolver
          .register(event, (_) {}),
      child: MouseRegion(
        onHover: (_) => _restartIdle(),
        child: SizedBox(
          width: PartyChatBubble.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (messages.isNotEmpty)
                Container(
                  key: const Key('party-chat-history'),
                  constraints: BoxConstraints(maxHeight: maxHistory),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: WfColors.bg.withValues(alpha: _historyAlpha),
                    borderRadius:
                        BorderRadius.circular(PartyChatBubble.radius),
                  ),
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: messages.length,
                    itemBuilder: (context, index) => Padding(
                      key: ValueKey('party-chat-line-${messages[index].key}'),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      child: PartyChatMessage(entry: messages[index]),
                    ),
                  ),
                ),
              const SizedBox(height: PartyChatBubble.gap),
              TextField(
                key: const Key('party-chat-field'),
                controller: _field,
                focusNode: _fieldFocus,
                style: partyChatTextStyle,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                inputFormatters: const [ChatLengthFormatter()],
                // Il campo resta a fuoco: Invio lo svuota e si continua a
                // scrivere.
                onEditingComplete: () {},
                onSubmitted: (value) => unawaited(_submit(value)),
                // Un clic sui controlli non gli toglie il focus; il clic sul
                // film chiude la chat (lo fa `PlayerScreen`).
                onTapOutside: (_) {},
                decoration:
                    InputDecoration(hintText: l.partyChatHint, isDense: true),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    error == PartyChatSendResult.rateLimited
                        ? l.partyChatTooMany
                        : l.partyChatNotSent,
                    style:
                        const TextStyle(color: WfColors.error, fontSize: 12),
                  ),
                )
              else if (length >= PartyChatLayer.counterFrom)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$length/$maxChatLength',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        color: WfColors.creamMuted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/watch_party/party_chat_layer_test.dart`
Expected: PASS (14 test).

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/watch_party/party_chat_layer.dart test/features/watch_party/party_chat_layer_test.dart
git commit -m "feat: write in the watch party chat with its history"
```

---

## Gruppo C — dentro il player

### Task 6: pulsante chat e puntino nei controlli

**Files:**
- Modify: `lib/features/player/player_overlay.dart`
- Test: `test/features/player/player_overlay_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

In `test/features/player/player_overlay_test.dart` cambia l'helper `pumpOverlay`: aggiungi i parametri `bool chat = false, bool chatUnread = false` dopo `bool fullscreen = false,` e, nella costruzione di `PlayerOverlay`, dopo `onToggleFullscreen: …,`:

```dart
          onToggleChat: chat ? () => calls.add('chat') : null,
          chatUnread: chatUnread,
```

Poi aggiungi il test:

```dart
  testWidgets('chat del watch party: pulsante e puntino dei non letti '
      '(spec E §9.5)', (tester) async {
    final view = PlayerViewState(status: PlayerStatus.ready);
    await pumpOverlay(tester, view);
    expect(find.byTooltip('Chat (Invio)'), findsNothing);

    final calls = await pumpOverlay(tester, view, chat: true);
    expect(find.byKey(const Key('player-chat-unread')), findsNothing);
    await tester.tap(find.byTooltip('Chat (Invio)'));
    expect(calls, ['chat']);

    await pumpOverlay(tester, view, chat: true, chatUnread: true);
    expect(find.byKey(const Key('player-chat-unread')), findsOneWidget);
  });
```

- [ ] **Step 2: esegui il test e verifica che fallisca**

Run: `flutter test test/features/player/player_overlay_test.dart`
Expected: FAIL in compilazione (`onToggleChat` non esiste).

- [ ] **Step 3: implementa**

In `lib/features/player/player_overlay.dart`, nel costruttore di `PlayerOverlay` aggiungi dopo `this.onWatchTogether,`:

```dart
    this.onToggleChat,
    this.chatUnread = false,
```

e dopo il campo `onWatchTogether`:

```dart

  /// Chat del watch party (spec E §9.5): solo nel gruppo con il canale del
  /// plugin attivo; `null` = nessun pulsante. Sta dove fuori dal gruppo c'è
  /// "Guarda insieme".
  final VoidCallback? onToggleChat;

  /// Messaggi arrivati fuori dal player e non ancora letti: puntino oro.
  final bool chatUnread;
```

Nella riga dei comandi, dopo il blocco `if (onWatchTogether != null) PlayerIconButton(…),` aggiungi:

```dart
                          if (onToggleChat != null)
                            PlayerIconButton(
                              key: const Key('player-chat-button'),
                              icon: _WithDot(
                                show: chatUnread,
                                child: const Icon(LucideIcons.messageCircle),
                              ),
                              tooltip: l.partyChatOpen,
                              onPressed: onToggleChat,
                            ),
```

In fondo al file:

```dart

/// Puntino oro in alto a destra di un'icona (messaggi non letti).
class _WithDot extends StatelessWidget {
  const _WithDot({required this.show, required this.child});

  /// Diametro del puntino.
  static const size = 8.0;

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (show)
            const Positioned(
              key: Key('player-chat-unread'),
              top: -1,
              right: -1,
              child: SizedBox.square(
                dimension: size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: WfColors.gold, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      );
}
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/player/player_overlay_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/player/player_overlay.dart test/features/player/player_overlay_test.dart
git commit -m "feat: add the watch party chat button to the player controls"
```

### Task 7: la chat nel player

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

In `test/features/watch_party/party_player_test.dart`:
- aggiungi gli import `package:wonderflix/features/player/pause_screen.dart`, `package:wonderflix/features/player/tracks_panel.dart` (e `package:flutter/gestures.dart` se `kDoubleTapTimeout` non risulta definito);
- cambia la firma di `pumpPartyPlayer` aggiungendo `bool plugin = true` ai parametri con nome, e la riga `channelApi = FakePartyChannelApi()..install();` in:

```dart
    channelApi = FakePartyChannelApi();
    if (plugin) channelApi.install();
```

In fondo a `main()` (dopo tutti gli helper):

```dart
  Finder chatField() => find.byKey(const Key('party-chat-field'));

  Future<void> openChatWithEnter(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('chat: pulsante nel gruppo con il plugin, Invio la apre '
      '(spec E §9)', (tester) async {
    await pumpPartyPlayer(tester);
    expect(find.byTooltip(l.partyChatOpen), findsOneWidget);
    await openChatWithEnter(tester);
    expect(chatField(), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'party-chat');
    await finish(tester);
  });

  testWidgets('chat: senza plugin niente pulsante, Invio non fa nulla',
      (tester) async {
    await pumpPartyPlayer(tester, plugin: false);
    expect(find.byTooltip(l.partyChatOpen), findsNothing);
    await openChatWithEnter(tester);
    expect(chatField(), findsNothing);
    await finish(tester);
  });

  testWidgets('chat aperta: Spazio va al campo; Esc la chiude e i tasti '
      'tornano al player', (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.calls, isNot(contains('unpause')), reason: 'Spazio va al campo');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(chatField(), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget,
        reason: 'Esc chiude solo la chat');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.calls, contains('unpause'));
    await finish(tester);
  });

  testWidgets('chat aperta: il clic sul film la chiude senza mettere in pausa',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.partyChatOpen));
    await tester.pump();
    await tester.pump();
    expect(chatField(), findsOneWidget);
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(chatField(), findsNothing);
    expect(api.calls, isNot(contains('unpause')));
    await finish(tester);
  });

  testWidgets('chat e pannello "Audio e sottotitoli": uno alla volta',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.partyChatOpen));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip(l.playerAudioAndSubtitles));
    await tester.pumpAndSettle();
    expect(chatField(), findsNothing);
    expect(find.byType(TracksPanel), findsOneWidget);
    await finish(tester);
  });

  testWidgets('chat aperta: niente "Stai guardando"', (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    await tester.pump(PlayerChromeController.pauseScreenDelay +
        const Duration(seconds: 1));
    expect(tester.widget<PauseScreen>(find.byType(PauseScreen)).visible,
        isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(PlayerChromeController.pauseScreenDelay +
        const Duration(seconds: 1));
    expect(tester.widget<PauseScreen>(find.byType(PauseScreen)).visible,
        isTrue);
    await finish(tester);
  });

  testWidgets('chat: i messaggi arrivano come bolle, non come non letti',
      (tester) async {
    await pumpPartyPlayer(tester);
    events.add(PartyChannelReceived(
        partyPayload({'Type': 'Chat', 'Text': 'ciao a tutti'}, id: 'c1')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('ciao a tutti'), findsOneWidget);
    expect(find.byKey(const Key('player-chat-unread')), findsNothing);
    await finish(tester);
  });
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_player_test.dart`
Expected: i nuovi test FAIL (nessun pulsante chat); gli altri PASS.

- [ ] **Step 3: implementa**

In `lib/features/player/player_screen.dart`:

1. Import (in ordine): `import '../watch_party/party_chat_layer.dart';` dopo `import '../watch_party/party_channel.dart';`.

2. Campi, dopo `final _chrome = PlayerChromeController();`:

```dart

  /// Focus del player: i tasti arrivano a `_onKey`. Chiusa la chat (che
  /// aveva il focus nel suo campo) torna qui (spec E §11).
  final _focusNode = FocusNode(debugLabel: 'player');
  bool _chatWasOpen = false;

  /// Invio apre la chat. Non `const`: le chiavi ridefiniscono `==`.
  static final _openChatKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };
```

3. In `dispose`, dopo `..dispose();` del blocco `_chrome`, aggiungi `_focusNode.dispose();`.

4. Sostituisci `_onChromeChanged`:

```dart
  void _onChromeChanged() {
    if (mounted) setState(() {});
  }
```

con:

```dart
  void _onChromeChanged() {
    if (!mounted) return;
    final chatOpen = _chrome.chatOpen;
    if (chatOpen != _chatWasOpen) {
      _chatWasOpen = chatOpen;
      // Chiusa la chat (Esc, clic sul film, pannello, chiusura automatica):
      // i tasti tornano al player.
      if (!chatOpen) _focusNode.requestFocus();
    }
    setState(() {});
  }

  /// La chat del watch party si può aprire: nel gruppo, con il canale del
  /// plugin attivo (spec E §9.5).
  bool get _chatAvailable =>
      _inParty && ref.read(partyChannelProvider).active;
```

5. In `_escape` sostituisci:

```dart
    if (_chrome.panelOpen) {
      _chrome.closePanel();
    } else if
```

con:

```dart
    if (_chrome.popup != null) {
      _chrome.closePopup();
    } else if
```

e aggiorna il commento: `/// Esc: pannello o chat → post-play o scheda → schermo intero → uscita (spec D §9.1, spec E §11). …`.

6. All'inizio di `_onKey`, prima di `final command = …`:

```dart
    // Chat aperta: i tasti vanno al suo campo (lettere, Spazio, frecce,
    // Backspace, Invio), tranne Esc che la chiude (spec E §11). Contano
    // comunque come attività.
    if (_chrome.chatOpen) {
      if (event is! KeyUpEvent) _chrome.keyActivity();
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _chrome.closePopup(PlayerPopup.chat);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // Invio apre la chat del watch party.
    if (event is KeyDownEvent &&
        _openChatKeys.contains(event.logicalKey) &&
        _chatAvailable) {
      _chrome
        ..keyActivity()
        ..openPopup(PlayerPopup.chat);
      return KeyEventResult.handled;
    }
```

7. In `build`, dopo `final canWatchTogether = …;`:

```dart
    // Chat del watch party: c'è con il canale del plugin attivo (spec E §9).
    final chat = widget.args.party != null
        ? ref.watch(partyChannelProvider
            .select((s) => (active: s.active, unread: s.unread)))
        : null;
    final chatActive = _inParty && (chat?.active ?? false);
```

e, nel blocco `if (widget.args.party != null) { ref.listen(…setParty…) }`, aggiungi dentro le graffe:

```dart
      // Canale spento (plugin tolto) con la chat aperta: si chiude.
      ref.listen(partyChannelProvider.select((s) => s.active), (_, active) {
        if (!active) _chrome.closePopup(PlayerPopup.chat);
      });
```

Nel listener che stacca il player dal gruppo (`watchPartySessionProvider.select((s) => s.inGroup)`), dopo `setState(() => _partyDetached = true);` aggiungi `_chrome.closePopup(PlayerPopup.chat);`.

8. Sostituisci `body: Focus(autofocus: true, onKeyEvent: _onKey,` con:

```dart
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
```

9. Nel `GestureDetector` del film sostituisci:

```dart
                        onTap: () {
                          if (_chrome.panelOpen) {
                            _chrome.closePanel();
                          } else if
```

con:

```dart
                        onTap: () {
                          if (_chrome.popup != null) {
                            // Pannello o chat aperti: il clic li chiude e
                            // basta.
                            _chrome.closePopup();
                          } else if
```

10. In `PlayerOverlay(…)`, dopo `onWatchTogether: …,`:

```dart
                        onToggleChat: chatActive
                            ? () => _chrome.togglePopup(PlayerPopup.chat)
                            : null,
                        chatUnread: (chat?.unread ?? 0) > 0,
```

11. Nello `Stack`, dopo il `Positioned.fill` con chiave `'player-party-waiting-post-play'` e prima del `Positioned` con chiave `'player-pill-layer'`:

```dart
                // Chat del watch party (spec E §9): in basso a sinistra,
                // sopra post-play e attese, sotto la pillola e il pannello.
                // Non è dentro `ExcludeFocus`: il suo campo prende il focus.
                if (chatActive)
                  Positioned(
                    key: const ValueKey('player-party-chat'),
                    left: PartyChatLayer.left,
                    bottom: PartyChatLayer.bottom,
                    child: PartyChatLayer(
                      open: _chrome.chatOpen,
                      onOpen: () => _chrome.openPopup(PlayerPopup.chat),
                      onClose: () => _chrome.closePopup(PlayerPopup.chat),
                    ),
                  ),
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/watch_party/ test/features/player/`
Expected: PASS.

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/player/player_screen.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: chat in the watch party player"
```

---

## Gruppo D — non letti fuori dal player

### Task 8: contatore sul chip "Nel watch party"

**Files:**
- Modify: `lib/ui/poster_card.dart` (`CountBadge.max`)
- Modify: `lib/features/watch_party/party_badge.dart` (`PartyChip.count`)
- Modify: `lib/features/watch_party/watch_party_button.dart` (`_InPartyButton`)
- Test: `test/features/watch_party/watch_party_button_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

In `test/features/watch_party/watch_party_button_test.dart`:
- aggiungi l'import `package:wonderflix/features/watch_party/party_channel.dart`;
- tra le variabili `late` aggiungi `late FakePartyChannelApi channelApi;` e nel `setUp` `channelApi = FakePartyChannelApi()..install();`;
- negli `overrides` di `pumpInParty` aggiungi `partyChannelApiProvider.overrideWithValue(channelApi),`.

Poi in fondo a `main()`:

```dart
  testWidgets('messaggi arrivati fuori dal player: contatore fino a "9+" '
      '(spec E §9.5)', (tester) async {
    await pumpInParty(tester, queue: testQueue());
    await tester.pump();
    await tester.pump();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WatchPartyButton)));
    expect(container.read(partyChannelProvider).active, isTrue);
    expect(find.byKey(const Key('watch-party-unread')), findsNothing);

    for (var i = 1; i <= 10; i++) {
      events.add(PartyChannelReceived(
          partyPayload({'Type': 'Chat', 'Text': 'm$i'}, id: 'c$i')));
    }
    await tester.pump();
    await tester.pump();
    expect(
        find.descendant(
            of: find.byKey(const Key('watch-party-unread')),
            matching: find.text('9+')),
        findsOneWidget);

    container.read(partyChannelProvider.notifier).markRead();
    await tester.pump();
    expect(find.byKey(const Key('watch-party-unread')), findsNothing);

    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });
```

- [ ] **Step 2: esegui il test e verifica che fallisca**

Run: `flutter test test/features/watch_party/watch_party_button_test.dart`
Expected: il nuovo test FAIL (nessun contatore).

- [ ] **Step 3: implementa**

In `lib/ui/poster_card.dart` sostituisci la classe `CountBadge` con:

```dart
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.max});

  final int count;

  /// Oltre questo numero si scrive "[max]+"; `null` = sempre il numero.
  final int? max;

  @override
  Widget build(BuildContext context) {
    final max = this.max;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: WfColors.gold, borderRadius: BorderRadius.circular(10)),
      child: Text(max != null && count > max ? '$max+' : '$count',
          style: const TextStyle(
              color: WfColors.bg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
```

In `lib/features/watch_party/party_badge.dart` aggiungi l'import `import '../../ui/poster_card.dart';` (in ordine) e sostituisci `PartyChip`:

```dart
class PartyChip extends StatelessWidget {
  const PartyChip({super.key, required this.label});

  final String label;
```

con:

```dart
class PartyChip extends StatelessWidget {
  const PartyChip({super.key, required this.label, this.count = 0});

  final String label;

  /// Messaggi della chat non letti (spec E §9.5); 0 = nessun contatore.
  final int count;

  /// Oltre questo numero il contatore scrive "9+".
  static const maxCount = 9;
```

e, nella `Row` di `build`, dopo il `Text(label, …)`:

```dart
            if (count > 0) ...[
              const SizedBox(width: 6),
              CountBadge(
                  key: const Key('watch-party-unread'),
                  count: count,
                  max: maxCount),
            ],
```

In `lib/features/watch_party/watch_party_button.dart` aggiungi l'import `import 'party_channel.dart';` (in ordine). In `_InPartyButton.build`, dopo `final playing = party.queue?.playing;`:

```dart
    // Messaggi arrivati fuori dal player (spec E §9.5).
    final unread = ref.watch(partyChannelProvider.select((s) => s.unread));
```

e sostituisci `child: PartyChip(label: l.watchPartyInParty),` con `child: PartyChip(label: l.watchPartyInParty, count: unread),`.

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/watch_party/ test/ui/`
Expected: PASS.

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/ui/poster_card.dart lib/features/watch_party/party_badge.dart lib/features/watch_party/watch_party_button.dart test/features/watch_party/watch_party_button_test.dart
git commit -m "feat: count unread watch party messages on the party chip"
```

---

## Gruppo E — chiusura

### Task 9: spec allineato e verifica finale

**Files:**
- Modify: `docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md`

- [ ] **Step 1: allinea lo spec**

1. Riga **Stato**: `approvato; piani 10a e 10b realizzati (…-10a-watch-party-plugin-nomi.md, …-10b-watch-party-chat.md), 10c da fare` (con i percorsi completi in `docs/superpowers/plans/`).
2. **§9.1**: aggiungi che la posizione è `left: 24`, `bottom: 150` (`PartyChatLayer.left`/`bottom`) e che lo stile del testo è `partyChatTextStyle` (`party_chat_bubble.dart`).
3. **§9.2**: aggiungi: "I nostri messaggi mandati a chat aperta non diventano bolle (sono nello storico); i nostri da un altro PC sì, con "Tu"."
4. **§9.3**: sostituisci "**Clic sul film** con la chat aperta: chiude solo la chat (non mette in pausa e non mostra i controlli)." con "**Clic sul film** con la chat aperta: chiude solo la chat (non mette in pausa). Un clic sui controlli agisce e lascia il focus nel campo." e aggiungi "Il limite si applica con `ChatLengthFormatter` (punti di codice, non grafemi)."
5. **§9.4**: aggiungi "Il messaggio tiene la stessa identità (`PartyChatEntry.key`) da "in attesa" a confermato."
6. **§9.5**: "Fuori dal player" → il contatore è un `CountBadge` con `max: 9` dentro `PartyChip`.
7. **§11**: il `popup` di `PlayerChromeController` ha per ora `tracks` e `chat` (`reactions` arriva nel 10c); il player ha un `FocusNode` suo, a cui torna il focus quando la chat si chiude.

- [ ] **Step 2: verifica completa**

Run, dalla root del worktree:
- `flutter analyze` → `No issues found!`
- `flutter test` → tutto verde
- `git log --format=%B main..HEAD | grep -i -E "co-authored|generated with"` → nessuna riga
- `git status` pulito

- [ ] **Step 3: commit**

```bash
git add docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md
git commit -m "docs: align spec E with plan 10b"
```

- [ ] **Step 4: prova manuale (orchestratore e utente)**

Dopo la revisione finale e le correzioni approvate: build di release nel worktree (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`), l'utente avvia due istanze (`WONDERFLIX_PROFILE=b`). Il plugin sul server è già quello del piano 10a. Da provare: Invio e pulsante aprono la chat; bolle che svaniscono; storico; emoji (Win + .); Spazio e frecce nel campo; Esc; clic sul film; clic sui controlli con la chat aperta; pannello tracce; "Stai guardando" che non parte; errore con troppi messaggi (6 in 10 s); chiusura dopo 20 s; contatore sul chip fuori dal player e puntino nel player; sottotitoli lunghi e post-play sotto le bolle (spec E §17).
