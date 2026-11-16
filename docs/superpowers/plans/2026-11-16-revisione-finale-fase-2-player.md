# Revisione finale, fase 2: player e trailer — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il player e il trailer della spec §4: comandi a gruppi che dicono il loro tasto, tempo che resta e ora di fine, scheda "Tasti", Velocità, pannello tracce rifatto, telefono e TV coi loro layout, errore, post-play e trailer nella stessa lingua.

**Architecture:** Tre file piccoli nuovi in `features/player/` (`player_keys.dart` per tasti e scheda, `playback_rate.dart` per la Velocità, `player_time.dart` per i tempi); il resto sono modifiche ai file del player che già esistono. La Velocità vive nello stato del `PlayerController` (non nelle impostazioni): ogni titolo è un `PlayerScreen` nuovo, quindi riparte da 1×.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, lucide_icons_flutter, `package:clock` (già dipendenza), intl `DateFormat`, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-16-revisione-finale-ui-design.md` §4 (tutta), §2 (Qualità fuori), §3.1, §3.5, §12 (test del player). Bozza: `docs/superpowers/specs/2026-11-16-revisione-finale-bozze/player.html`.

**Prima di questa fase** è eseguita la fase 1 (`2026-11-16-revisione-finale-fase-1-comuni.md`). Da lei, già fatti e da non rifare: `compact && !tv` in `player_side_panel_host.dart`, `pause_screen.dart`, `post_play.dart` (in TV immagine sì, trama no), `player_screen.dart` (posizioni); "Riprova" col focus nell'errore in TV dentro un livello di focus proprio; "Stai guardando" senza `toUpperCase`; i temi di chip/checkbox (`theme.dart`). Se un punto di questa lista manca quando inizi, fermati e segnalalo.

## Global Constraints

- Lavoro nel worktree `.claude/worktrees/revisione-finale`, branch `revisione-finale-ui`. Comandi da `app/`. In Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Il worktree ha bisogno di `config/wonderflix.json` copiato da `C:\Users\sidot\Documents\Github\wonderflix\app\config\` e di `flutter pub get` e `flutter gen-l10n` prima di `analyze`/`test`.
- Nessun colore nuovo: solo `WfColors` (`bg`, `surface`, `surfaceHigh`, `border`, `gold`, `cream`, `creamMuted`, `error`, `online`). Titoli con `WfText.display(n)`. Tempi e conti con `FontFeature.tabularFigures()`.
- Testi in `l10n/app_it.arb` e `l10n/app_en.arb`; le chiavi che non usa più nessuno si tolgono. Niente etichette in maiuscolo. Episodi con `cardSubtitle`/`episodeCode` ("S1:E4"), generi con `genreLabel`.
- Fuori dalla TV il comportamento TV non cambia, e viceversa: layout TV con `compact && !tv`, telefono con `compact && !tv` (finestra stretta compresa) o `touch` dove la spec parla di dito.
- I tasti si mostrano solo dove esistono: `!tv && !touch`. Il tasto `?`, la scheda "Tasti" e i riquadri dei tasti non ci sono su TV e telefono.
- La Qualità nel player è fuori (spec §2). Il ritardo dei sottotitoli resta fuori dalla TV.
- In un party (`_inParty` di `PlayerScreen`: `widget.args.party != null && !_partyDetached`) la velocità resta 1×: il `GroupPlaybackDriver` usa `setRate` per recuperare gli scarti.
- `dart format` solo sulle righe toccate.
- Commit: messaggio in italiano, nessun trailer `Co-Authored-By`, mai le parole `closes`/`fixes`/`resolves`. Messaggi su più righe con `git commit -F <file>` (file senza BOM).
- Mai chiudere processi per nome immagine (`taskkill /IM`, `pkill`).
- Nessun cambio al plugin.

## Review Focus

- **Velocità e riapertura del video:** cambio d'audio sul web (`selectsEmbeddedTracks: false`, il video si riapre) o "Riprova" con 1,5× scelto: la velocità resta 1,5×, non torna a 1× di nascosto. Test in Task 2.
- **Durata ancora ignota (0) o posizione oltre la durata:** niente "−… · finisce alle …" sbagliato (nessun testo a destra finché la durata non c'è; il resto non va sotto zero). Test in Task 3.
- **`?` da una tastiera italiana** (Shift+' : `logicalKey` non è `question`, `character` è `'?'`) apre la scheda; con la chat del party aperta il `?` va al campo e la scheda non si apre. Test in Task 6.
- **Telefono 390×780, party con tutti i comandi (chat, reazioni, coda, ⏮, ⏭) e testo a 1,3:** quattro pulsanti con la parola, nessun overflow, i comandi in più sono tutti in "Altro". Test in Task 8.
- **TV, nome sotto il pulsante col focus:** non sposta la fila e non esce in basso dallo schermo a 960×540. Test in Task 9.

---

### Task 1: Tasti nei tooltip

**Files:**
- Create: `app/lib/features/player/player_keys.dart`
- Modify: `app/lib/features/player/player_overlay.dart` (`PlayerIconButton`, i pulsanti in `build`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/player/player_keys_test.dart` (nuovo), `app/test/features/player/player_overlay_test.dart`

**Interfaces:**
- Produces:
  - `class KeyCap extends StatelessWidget { const KeyCap(this.label, {super.key}); }`: riquadro del tasto come il `kbd` della bozza: alto 22, largo almeno 22, padding orizzontale 6, fondo `surfaceHigh`, bordo `border` 1 (in basso 2), angoli 4, testo `cream` 11 w600.
  - `class KeyTooltip extends StatelessWidget { const KeyTooltip({super.key, required String message, String? shortcut, required Widget child}); }`: con `shortcut == null` è un `Tooltip(message:)`; con il tasto usa `RawTooltip(semanticsTooltip: message, tooltipBuilder: ...)` con un riquadro `surface`, bordo `border`, angoli 6, padding 7×10, testo 12,5 e `KeyCap(shortcut)` a destra (gap 10). `RawTooltip` tiene `find.byTooltip(message)` funzionante (il finder guarda `semanticsTooltip`).
  - `PlayerIconButton(..., String? shortcut)`: nuovo parametro; il pulsante passa `tooltip: null` all'`IconButton` e si avvolge in `KeyTooltip`. Il tasto si mostra solo con `!tv && !touch`.

Tasti (spec §4.1): Pausa/Riproduci `Spazio`; −10 s `←`; +10 s `→`; muto `M`; schermo intero `F`; episodio/titolo successivo `N`, precedente `P`; Chat `Invio`; Reazioni `1–6`; il cursore del volume ha un `KeyTooltip(message: l.playerVolume, shortcut: '↑/↓')`. Testi: `partyChatOpen` "Chat (Invio)" → "Chat" (en "Chat"), `partyReactionsOpen` "Reazioni (1–6)" → "Reazioni" (en "Reactions"); nuove `playerVolume` "Volume", `playerKeySpace` "Spazio" (en "Space"), `playerKeyEnter` "Invio" (en "Enter").

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('il tooltip di Pausa mostra Spazio', (t) async {
  // pumpOverlay con playing: true; hover sul pulsante Pausa e pump(1 s)
  expect(find.byTooltip('Pausa'), findsOneWidget);
  expect(find.descendant(of: find.byType(KeyCap), matching: find.text('Spazio')), findsOneWidget);
});
testWidgets('ogni comando ha il suo tasto', (t) async {
  // per ogni coppia: ('Indietro di 10 secondi','←'), ('Avanti di 10 secondi','→'),
  // ('Disattiva audio','M'), ('Schermo intero','F'), ('Episodio successivo','N'),
  // ('Episodio precedente','P'), ('Chat','Invio'), ('Reazioni','1–6'):
  // il KeyTooltip con quel message ha quel shortcut.
  final tip = t.widget<KeyTooltip>(find.byWidgetPredicate((w) => w is KeyTooltip && w.message == 'Chat'));
  expect(tip.shortcut, 'Invio');
});
testWidgets('col dito e in TV nessun tasto', (t) async {
  // touch: true → tutti i KeyTooltip hanno shortcut null; idem con tv: true a 960×540
});
```

- [ ] **Step 2:** `flutter test test/features/player/player_keys_test.dart test/features/player/player_overlay_test.dart` → FAIL.
- [ ] **Step 3:** crea `player_keys.dart` con `KeyCap` e `KeyTooltip`, aggiungi `shortcut` a `PlayerIconButton`, passa i tasti ai pulsanti dell'overlay (anche ai comandi di `_compactCommands` che restano pulsanti), cambia le chiavi arb; `flutter gen-l10n`.
- [ ] **Step 4:** stessi test → PASS; poi `flutter test test/features/player test/features/watch_party` → PASS (i test che cercavano `'Chat (Invio)'`/`'Reazioni (1–6)'` passano ai testi nuovi).
- [ ] **Step 5: Commit** `feat(app): i tooltip del player dicono il loro tasto`

### Task 2: Velocità nel controller

**Files:**
- Create: `app/lib/features/player/playback_rate.dart`
- Modify: `app/lib/features/player/player_controller.dart` (`PlayerViewState`, `PlayerController`)
- Test: `app/test/features/player/playback_rate_test.dart` (nuovo), `app/test/features/player/player_controller_test.dart`

**Interfaces:**
- Produces:
  - `const playbackRates = [0.75, 1.0, 1.25, 1.5, 2.0];`
  - `String formatRate(double rate, String decimalSeparator)`: "0,75×", "1×", "1,25×", "1,5×", "2×" (niente zeri in coda).
  - `PlayerViewState.rate` (`double`, default `1.0`, in `copyWith`).
  - `Future<void> PlayerController.setRate(double rate)`: `engine.setRate(rate)` e `rate` nello stato. Dopo ogni apertura (dove oggi `_start` riapplica volume e ritardo, ~`player_controller.dart:304-310`) riapplica `_view.rate` se non è 1.
  - `Future<void> showSpeedMenu(BuildContext anchor, {required double rate, required ValueChanged<double> onSelected})` in `playback_rate.dart`: menu (`showMenu` ancorato al box di `anchor`, come il ⋯ dello stretto) con le cinque velocità, spunta oro sulla scelta.

- [ ] **Step 1: Test che falliscono**

```dart
test('velocità scritte con la virgola', () {
  expect(playbackRates.map((r) => formatRate(r, ',')), ['0,75×', '1×', '1,25×', '1,5×', '2×']);
});
test('setRate arriva al motore e allo stato', () async {
  // controller su FakeVideoEngine, stato ready → setRate(1.5)
  expect(engine.rates.last, 1.5);
  expect(container.read(playerControllerProvider(args)).rate, 1.5);
});
test('la velocità resta dopo una riapertura', () async {
  // FakeVideoEngine(selectsEmbeddedTracks: false): setRate(1.5), poi selectAudio(altra traccia)
  // (riapre il video) → engine.rates.last == 1.5; idem dopo retry()
});
test('un titolo nuovo parte da 1×', () {
  expect(const PlayerViewState().rate, 1.0);
});
```

- [ ] **Step 2:** `flutter test test/features/player/playback_rate_test.dart test/features/player/player_controller_test.dart` → FAIL.
- [ ] **Step 3:** implementa come da Interfaces.
- [ ] **Step 4:** stessi test → PASS.
- [ ] **Step 5: Commit** `feat(app): velocità di riproduzione nel player`

### Task 3: Tempi e seek bar

**Files:**
- Create: `app/lib/features/player/player_time.dart`
- Modify: `app/lib/features/player/seek_bar.dart` (cursore sempre visibile, `height`; `TimeLabel` si toglie), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/player/player_time_test.dart` (nuovo), `app/test/features/player/seek_bar_test.dart`

**Interfaces:**
- Produces:
  - `String? formatRemaining(AppLocalizations l, {required Duration position, required Duration duration, required DateTime now, double rate = 1, bool withEnd = true})`: `null` con `duration <= 0`; resto = `duration - position` (mai sotto zero); con `withEnd` l'ora di fine è `now + resto / rate` in `DateFormat.Hm(l.localeName)`. Chiave `playerTimeLeft` "−{left} · finisce alle {end}" (en "−{left} · ends at {end}"), `playerTimeLeftShort` "−{left}" (trailer). Il segno è il meno U+2212.
  - `class PositionLabel extends StatefulWidget { const PositionLabel({super.key, required VideoEngine engine}); }`: `formatClock(position)`, crema 13 w600, cifre tabellari, cambia al secondo (come il `TimeLabel` di oggi).
  - `class RemainingLabel extends StatefulWidget { const RemainingLabel({super.key, required VideoEngine engine, double rate = 1, bool withEnd = true}); }`: `formatRemaining(..., now: clock.now())` (`package:clock`), `creamMuted` 13 w500, tabellare; senza testo è `SizedBox.shrink()`.
  - `SeekBar(..., double height = SeekBar.height)`: area che risponde al dito; il cursore è sempre disegnato (`thumb: 1`, `thumbOpacity: 1`; il controller `_thumb` e la sua animazione si tolgono, il passaggio fa crescere solo la traccia).

- [ ] **Step 1: Test che falliscono**

```dart
test('tempo che resta e ora di fine', () {
  final l = lookupAppLocalizations(const Locale('it'));
  final now = DateTime(2026, 11, 16, 22, 51, 5);
  expect(formatRemaining(l, position: const Duration(minutes: 2, seconds: 5),
      duration: const Duration(minutes: 52), now: now), '−49:55 · finisce alle 23:41');
  expect(formatRemaining(l, position: const Duration(minutes: 2, seconds: 5),
      duration: const Duration(minutes: 52), now: now, rate: 2), '−49:55 · finisce alle 23:16');
  expect(formatRemaining(l, position: Duration.zero, duration: Duration.zero, now: now), isNull);
  expect(formatRemaining(l, position: const Duration(minutes: 60),
      duration: const Duration(minutes: 52), now: now), '−00:00 · finisce alle 22:51');
  expect(formatRemaining(l, position: Duration.zero, duration: const Duration(minutes: 2, seconds: 12),
      now: now, withEnd: false), '−02:12');
});
testWidgets("l'etichetta usa l'orologio del dispositivo", (t) async {
  await withClock(Clock.fixed(DateTime(2026, 11, 16, 22, 51, 5)), () async {
    // FakeVideoEngine con position 2:05 e duration 52:00 → find.text('−49:55 · finisce alle 23:41')
  });
});
testWidgets('il pallino si vede anche senza mouse', (t) async {
  // pumpBar senza hover: (t.widget<CustomPaint>(find.byKey(const Key('seek-bar-paint'))).painter
  //   as SeekBarPainter).thumb == 1
});
testWidgets('height allarga l\'area del dito', (t) async {
  // SeekBar(height: 44) → t.getSize(find.byType(SeekBar)).height == 44
});
```

- [ ] **Step 2:** `flutter test test/features/player/player_time_test.dart test/features/player/seek_bar_test.dart` → FAIL.
- [ ] **Step 3:** implementa; l'anteprima resta sopra la barra (`bottom: widget.height + previewGap`). I test di oggi che guardavano il cursore nascosto a riposo si aggiornano.
- [ ] **Step 4:** stessi test → PASS.
- [ ] **Step 5: Commit** `feat(app): tempo che resta, ora di fine e pallino sempre visibile`

### Task 4: Barra a gruppi, Velocità e "Torna alla scheda"

**Files:**
- Modify: `app/lib/features/player/player_overlay.dart`, `app/lib/features/player/player_screen.dart` (passa `rate`, `onRate`, `backLabel`, `fromHome`), `app/lib/app/navigation.dart` (`playerRoute`), `app/lib/app/router.dart` (`/play/:id`), `app/lib/features/playback/play_launcher.dart` (`_open` o la riga 88), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/player/player_overlay_test.dart`, `app/test/features/player/player_screen_test.dart`, `app/test/app/navigation_test.dart` (se c'è; se no nel test del player)

**Interfaces:**
- Consumes: `KeyTooltip`/`shortcut` (Task 1), `showSpeedMenu`, `formatRate`, `PlayerController.setRate`, `PlayerViewState.rate` (Task 2), `PositionLabel`, `RemainingLabel` (Task 3).
- Produces:
  - `PlayerOverlay(..., required String backLabel, double rate = 1, ValueChanged<double>? onRate)`: `onRate == null` = niente Velocità (party). `backLabel` è il tooltip della ←.
  - `playerRoute(itemId, {..., bool fromHome = false})` aggiunge `from=home`; `PlayerScreen({..., bool fromHome = false})`, letto dal router come `fs`. Le sostituzioni (episodio successivo/precedente, `player_screen.dart` ~849, ~891, ~1009) lo passano avanti.
  - `play_launcher.dart`: `fromHome` = `GoRouter.of(context).routerDelegate.currentConfiguration.uri.path == '/home'` quando apre il player.
  - `String _backLabel` in `_PlayerScreenState`: `_inParty ? l.watchPartyLeave : widget.fromHome ? l.playerBackHome : l.playerBackToDetail`.
  - Chiavi: `playerBackToDetail` "Torna alla scheda" (en "Back to details"), `playerBackHome` "Torna alla Home" (en "Back to Home"), `playerSpeed` "Velocità" (en "Speed"). `playerBack` si toglie (lo usa solo l'errore, che passa a `_backLabel` in Task 10).

Layout desktop (non `compact`, non `tv`), spec §4.1 e bozza:
- Riga del tempo sopra i comandi: `PositionLabel` · `SeekBar` (Expanded) · `RemainingLabel(rate: view.rate)`, gap 14.
- Riga dei comandi, quattro gruppi separati da un filo verticale `WfColors.border` 1×20 con margine orizzontale 10 (un gruppo vuoto non lascia fili doppi): (1) −10, play/pausa, +10, muto, volume 120; (2) ⏮ ⏭; (3) Guarda insieme, Chat, Reazioni; poi uno `Spacer`; (4) Coda, Audio e sottotitoli, Velocità (icona `LucideIcons.gauge`, `PlayerIconButton` che apre `showSpeedMenu` col suo contesto), Schermo intero.
- Volume: traccia attiva e pallino `gold`, inattiva `cream` al 25%.
- TV: ordine e pulsanti come oggi (la TV cambia in Task 9), riga del tempo come il desktop.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('quattro gruppi nell\'ordine della spec', (t) async {
  // pumpOverlay con next, previous, onWatchTogether, chat, reactions, queue, onRate
  final xs = ['Indietro di 10 secondi', 'Pausa', 'Avanti di 10 secondi', 'Disattiva audio',
    'Episodio precedente', 'Episodio successivo', 'Guarda insieme', 'Chat', 'Reazioni',
    'Coda', 'Audio e sottotitoli', 'Velocità', 'Schermo intero']
      .map((m) => t.getCenter(find.byTooltip(m)).dx).toList();
  expect(xs, orderedEquals([...xs]..sort()));
  expect(find.byKey(const Key('player-group-divider')), findsNWidgets(3));
});
testWidgets('senza ⏮ ⏭ nessun filo doppio', (t) async { /* findsNWidgets(2) */ });
testWidgets('il volume è oro', (t) async {
  final slider = t.widget<SliderTheme>(find.ancestor(of: find.byKey(const Key('volume-slider')), matching: find.byType(SliderTheme)).first);
  expect(slider.data.activeTrackColor, WfColors.gold);
  expect(slider.data.thumbColor, WfColors.gold);
});
testWidgets('Velocità apre le cinque scelte e cambia', (t) async {
  // tap 'Velocità' → find.text('1,5×') → tap → onRate chiamato con 1.5
});
testWidgets('nel party niente Velocità', (t) async { /* onRate: null → find.byTooltip('Velocità') findsNothing */ });
testWidgets('la freccia dice dove torna', (t) async {
  // player_screen_test: aperto con playerRoute('e4') → find.byTooltip('Torna alla scheda');
  // aperto con playerRoute('e4', fromHome: true) → find.byTooltip('Torna alla Home');
  // find.byTooltip('Indietro') findsNothing (resta solo 'Indietro di 10 secondi')
});
test('playerRoute porta con sé da dove si parte', () {
  expect(playerRoute('e4', fromHome: true), '/play/e4?from=home');
});
```

- [ ] **Step 2:** `flutter test test/features/player/player_overlay_test.dart test/features/player/player_screen_test.dart` → FAIL.
- [ ] **Step 3:** implementa; in `player_screen.dart` `onRate: _inParty ? null : (r) => unawaited(controller.setRate(r))`, `rate: view.rate`, `backLabel: _backLabel`.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/features/player test/features/playback test/features/watch_party` → PASS (i test che toccavano `'Indietro'` per uscire passano a `'Torna alla scheda'`).
- [ ] **Step 5: Commit** `feat(app): comandi del player a gruppi, Velocità e Torna alla scheda`

### Task 5: Avvisi nella pastiglia

**Files:**
- Modify: `app/lib/features/player/player_chrome.dart`, `app/lib/features/player/player_pill.dart`, `app/lib/features/player/player_screen.dart` (~1327 e ~1558)
- Test: `app/test/features/player/player_pill_test.dart`, `app/test/features/player/player_chrome_test.dart`, `app/test/features/player/player_subtitle_refresh_test.dart`, `app/test/features/player/player_screen_test.dart`

**Interfaces:**
- Produces:
  - `enum PlayerNotice { transcoding, subtitleNextPlayback }`; `final class NoticeFeedback extends PlayerFeedback { const NoticeFeedback(this.notice); final PlayerNotice notice; }`.
  - `PlayerChromeController.showFeedback(PlayerFeedback feedback, {Duration? duration})`: default `feedbackDuration`; per gli avvisi `noticeDuration = Duration(seconds: 4)`.
  - Pillola: icona `LucideIcons.info`, testi `l.playerTranscoding` e `l.subtitlesNextPlayback`.
- In `player_screen.dart` le due `showSnackBar` diventano `_chrome.showFeedback(NoticeFeedback(...), duration: PlayerChromeController.noticeDuration)`; i `clearSnackBars()` restano.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('la conversione si annuncia nella pastiglia', (t) async {
  // player_screen_test: transcodingFallback → find.descendant(of: find.byKey(const Key('player-pill')),
  //   matching: find.text('Il server sta convertendo questo video.')) findsOneWidget;
  // find.byType(SnackBar) findsNothing; dopo 4 s la pastiglia sparisce
});
testWidgets('sottotitolo dalla prossima riproduzione nella pastiglia', (t) async {
  // player_subtitle_refresh_test, caso nextPlayback → testo nella pastiglia, nessuna SnackBar
});
test('un avviso dura 4 s', () { /* fakeAsync: showFeedback(NoticeFeedback(...), duration: noticeDuration);
  elapse(3 s) → feedback non null; elapse(1 s) → null */ });
```

- [ ] **Step 2:** `flutter test` sui quattro file → FAIL.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** stessi test → PASS.
- [ ] **Step 5: Commit** `feat(app): gli avvisi del player stanno nella pastiglia`

### Task 6: Pausa e scheda "Tasti"

**Files:**
- Modify: `app/lib/features/player/player_keys.dart` (aggiungi la scheda), `app/lib/features/player/pause_screen.dart`, `app/lib/features/player/player_chrome.dart`, `app/lib/features/player/player_screen.dart` (`_onKey`, `_escape`, strato della pausa e della scheda), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/player/pause_screen_test.dart`, `app/test/features/player/player_keys_test.dart`, `app/test/features/player/player_screen_test.dart`, `app/test/features/player/player_chrome_test.dart`

**Interfaces:**
- Consumes: `KeyCap` (Task 1), `formatRemaining` (Task 3), `genreLabel` (`core/jellyfin/genre_labels.dart`).
- Produces:
  - `class PlayerKeysCard extends StatelessWidget { const PlayerKeysCard({super.key}); }`: largo 420, fondo `surface`, bordo `gold` 1 e un secondo filo `gold` al 35% rientrato di 8 (doppio filo), angoli 4, padding `fromLTRB(30, 26, 30, 22)`; titolo `WfText.display(40)` "Tasti" centrato con l'ornamento (due fili oro e un rombo); sotto `creamMuted` 12 "Valgono in tutto il player. ? apre e chiude questa scheda."; gruppi con titolo `gold` 11,5 w600 e righe "azione ……… tasti" (puntini: un `Expanded` con bordo inferiore punteggiato `cream` al 28%, un `CustomPaint` va bene), tasti con `KeyCap`.
  - Righe (copia esatta della bozza): **Riproduzione**: Pausa e riprendi `Spazio`; Indietro e avanti di 10 secondi `←` `→`; Volume `↑` `↓`; Disattiva e riattiva l'audio `M`; Schermo intero `F`. **Episodi e sottotitoli**: Episodio successivo e precedente `N` `P`; Sottotitoli prima e dopo `G` `H`. **In compagnia**: Chat `Invio`; Reazioni `1–6`. In fondo, fuori dai gruppi: Chiudi un pannello o esci `Esc`. Chiavi arb `playerKeys*` (nomi a scelta, una per testo).
  - `PlayerChromeController`: `bool get keysCard`, `void toggleKeysCard()`, `void closeKeysCard()`.
  - `PauseScreen({super.key, required JellyfinItem item, required bool visible, required VideoEngine engine, required VoidCallback onResume})`:
    - "Stai guardando" `gold` 14 w600 (frase normale);
    - meta con i generi passati da `genreLabel` (senza doppioni), al massimo due;
    - un solo `WfButton.primary` "Riprendi" (`l.playerResume`, icona play) e accanto, con `!tv && !touch`, "oppure" (`l.playerResumeOr`) + `KeyCap(l.playerKeySpace)`;
    - in basso (al posto di `_PausedBadge`) una riga: `formatClock(posizione)` · barra sottile (alta 3, oro sul `cream` al 15%) · `l.playerPauseLeft(resto)` "resta {left}" (en "{left} left");
    - a destra `PlayerKeysCard` solo con `!compact && !tv && !touch`;
    - lo strato resta `IgnorePointer` tranne il pulsante (il clic altrove arriva al video, che riprende; il mouse che si muove chiude la pausa via `pointerActivity`, come oggi).
  - `_onKey`: con `!tv`, un `KeyDownEvent` con `event.character == '?'` (o `logicalKey == LogicalKeyboardKey.question`) chiama `_chrome.toggleKeysCard()`; sta dopo i rami di chat, ricerca della coda e commento del voto (che si tengono i loro tasti). `_escape`: la scheda aperta si chiude per prima.
  - Strato `player-keys-card` in `player_screen.dart`, sopra i controlli e sotto la pastiglia: `PlayerKeysCard` a destra (`right: 64, top: 96`; nello stretto centrata), `ExcludeFocus`, visibile con `_chrome.keysCard`.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('pausa: frase normale, Riprendi con Spazio, tempo che resta', (t) async {
  // pumpPause a 1440×900, item episodio, engine position 23:12 di 52:00
  expect(find.text('Stai guardando'), findsOneWidget);
  expect(find.widgetWithText(WfButton, 'Riprendi'), findsOneWidget);
  expect(find.text('Spazio'), findsOneWidget);
  expect(find.text('resta 28:48'), findsOneWidget);
  expect(find.text('In pausa'), findsNothing);
  expect(find.byType(PlayerKeysCard), findsOneWidget);
});
testWidgets('pausa: Riprendi chiama onResume', (t) async { /* tap → onResume */ });
testWidgets('pausa sul telefono e in TV: niente scheda né tasto', (t) async {
  // touch: true a 390×780 e tv: true a 960×540 → PlayerKeysCard findsNothing, 'Spazio' findsNothing
});
testWidgets('pausa: generi in italiano', (t) async {
  // genres ['Crime', 'Drama'] → '… · Poliziesco · Dramma'
});
testWidgets('la scheda elenca tutti i tasti', (t) async {
  for (final k in ['Spazio', '←', '→', '↑', '↓', 'M', 'F', 'N', 'P', 'G', 'H', 'Invio', '1–6', 'Esc']) {
    expect(find.descendant(of: find.byType(PlayerKeysCard), matching: find.text(k)), findsOneWidget);
  }
  expect(find.text('Tasti'), findsOneWidget);
});
testWidgets('? apre e chiude la scheda, Esc la chiude', (t) async {
  // player_screen_test: sendKeyDownEvent(LogicalKeyboardKey.question, character: '?') + up
  // → PlayerKeysCard findsOneWidget; di nuovo → findsNothing; ? poi Esc → findsNothing e il player resta aperto
});
testWidgets('? da tastiera italiana', (t) async {
  // sendKeyDownEvent(LogicalKeyboardKey.quote, character: '?') → la scheda si apre
});
testWidgets('con la chat aperta ? va al campo', (t) async {
  // party_player_test (chat attiva): openPopup(chat), ? → PlayerKeysCard findsNothing
});
testWidgets('TV: ? non fa niente', (t) async { /* tv: true → findsNothing */ });
testWidgets('in pausa il mouse riporta i comandi', (t) async {
  // player_screen_test: pausa, pump(pauseScreenDelay) → Key('pause-screen') c'è;
  // hover del mouse sul video → la pausa sfuma via e Key('player-controls-top') ha opacità 1
  // (oggi dovrebbe già passare: il test lo fissa)
});
```

- [ ] **Step 2:** `flutter test test/features/player/pause_screen_test.dart test/features/player/player_keys_test.dart test/features/player/player_screen_test.dart test/features/watch_party/party_player_test.dart` → FAIL.
- [ ] **Step 3:** implementa; in `player_screen.dart` `PauseScreen(..., engine: controller.engine, onResume: () => unawaited(controller.togglePlay()))` e l'`ExcludeFocus` intorno resta.
- [ ] **Step 4:** stessi test → PASS.
- [ ] **Step 5: Commit** `feat(app): pausa con Riprendi e la scheda dei tasti`

### Task 7: Pannello Audio e sottotitoli

**Files:**
- Create: `app/lib/core/jellyfin/media_labels.dart` (test `app/test/core/jellyfin/media_labels_test.dart`)
- Modify: `app/lib/features/player/tracks_panel.dart`, `app/lib/core/jellyfin/playback_models.dart` (`MediaStreamInfo.channelLayout` da `ChannelLayout`), `app/lib/ui/tv_focusable.dart` (`focusScale`), `app/lib/features/player/player_screen.dart` (parametri nuovi), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/player/tracks_panel_test.dart`, `app/test/core/jellyfin/playback_models_test.dart` (o dove si prova `fromJson`), `app/test/features/watch_party/party_player_test.dart`

**Interfaces:**
- Consumes: `playbackRates`, `formatRate` (Task 2), `KeyCap` (Task 1).
- Produces:
  - Nuovo file condiviso `app/lib/core/jellyfin/media_labels.dart` (lo riusa la fase 4 per Info tecniche, Sottotitoli e Locandina: un solo posto per codec e lingue), funzioni pure:
    - `String? trackLanguageName(String? code, String localeName)`: ISO 639-2 (e i codici a 2 lettere it/en/ja/fr/de/es/pt/ko/zh/ru portati a 3) → nome. it: ita Italiano, eng Inglese, jpn Giapponese, fre/fra Francese, ger/deu Tedesco, spa Spagnolo, por Portoghese, kor Coreano, chi/zho Cinese, rus Russo; en: gli stessi in inglese. Sconosciuto o vuoto → `null`.
    - `String codecLabel(String? codec)`: hevc/h265 "HEVC", h264/avc "H.264", av1 "AV1", vp9 "VP9", mpeg2video "MPEG-2", eac3 "E-AC-3", ac3 "AC-3", aac "AAC", dts "DTS", truehd "TrueHD", flac "FLAC", opus "Opus", mp3 "MP3", subrip/srt "SRT", ass/ssa "ASS", pgssub "PGS", dvdsub/dvd_subtitle "VobSub", webvtt/vtt "WebVTT"; altro in maiuscolo; null/vuoto → ''.
    - `String? channelsLabel(int? channels)`: 1 "Mono", 2 "2.0", 6 "5.1", 8 "7.1", altri null.
  - `String trackDetail(AppLocalizations l, MediaStreamInfo stream)`: `[codec channelLayout]`, poi il `title` se c'è, poi "predefinita" (`isDefault`), "forzati" (`isForced`), per i sottotitoli "esterno" (`isExternal`) o "nel file"; uniti da " · ". Codec con `codecLabel`, canali con `channelLayout` o `channelsLabel`. Chiavi `playerTrackDefault`, `playerTrackForced`, `playerTrackExternal`, `playerTrackEmbedded`.
  - `TracksPanel(..., JellyfinItem? item, double rate = 1, ValueChanged<double>? onRate)`; `onRate == null` = party.
  - `TvFocusable(..., double focusScale = tvFocusScale)`.

Contenuto (spec §4.3, bozza):
- Testa: `WfText.display(30)` "Audio e sottotitoli" e ✕ (44×44 nello stretto); sotto, con `item`, lo still 64 (16:9, `urls.landscape`) e due righe: `cardTitle(item)` 13 w600, `cardSubtitle(item)` `creamMuted` 12; filo `border` sotto.
- Titoli delle sezioni: Inter 12 w600 `creamMuted`, con a destra un valore o i tasti: "Ritardo dei sottotitoli" (`playerSubtitleDelay` cambia così) + `KeyCap('G')` `KeyCap('H')` (solo `!touch`); "Dimensione · Normali" (`playerSubtitleSizeValue(size)`); "Velocità".
- Righe: alte almeno 44 (48 nello stretto, 52 in TV), etichetta `trackLanguageName ?? trackLabel`, sotto `trackDetail` in `creamMuted` 11,5; scelta in `gold` w600 con fondo `gold` al 10% e la spunta a destra. In TV `TvFocusable(focusScale: 1.03)`. "Nessuno" senza dettaglio.
- Ritardo (solo `!tv`): due pulsanti 44×38 (`surfaceHigh`, bordo `border`, angoli 6, `WfButtonFeedback`), icone − e +, tooltip `playerSubtitlesEarlier`/`Later` senza "(G)"/"(H)" ("Sottotitoli prima", "Sottotitoli dopo"); in mezzo il valore 14 w600 tabellare largo 70; sotto `playerSubtitleDelayHint` "− prima, + dopo l'audio" 11,5.
- Dimensione: cinque pastiglie "Aa" larghe 46, il testo grande `20 * scale` (minimo 10), `Semantics(label: subtitleScaleLabel(...))`; chiavi `subtitle-scale-$scale` come oggi.
- Velocità: cinque pastiglie con `formatRate`, chiavi `playback-rate-$rate`. Con `onRate == null` spente, scelta 1× e sotto `playerSpeedPartyNote` "In compagnia la velocità resta 1×" (en "In a party the speed stays 1×").
- Niente bordo sinistro nello stretto (lo mette l'host come foglio, Task 8); fuori dallo stretto resta.
- Larghezza (spec §4.5, bozza `.side`): `PlayerSidePanelHost.defaultWidth = 380.0` e `defaultMaxWidthFraction = 0.4` (con 0,35 a 960 sarebbero 336). Se la fase 1 l'ha già fatto, lascia così.

- [ ] **Step 1: Test che falliscono**

```dart
test('dettaglio delle tracce', () {
  expect(trackDetail(l, const MediaStreamInfo(index: 1, kind: StreamKind.audio, codec: 'ac3', channelLayout: '5.1', isDefault: true)), 'AC3 5.1 · predefinita');
  expect(trackDetail(l, const MediaStreamInfo(index: 3, kind: StreamKind.subtitle, codec: 'subrip', isExternal: true)), 'SRT · esterno');
  expect(trackDetail(l, const MediaStreamInfo(index: 4, kind: StreamKind.subtitle, codec: 'subrip')), 'SRT · nel file');
  expect(trackLanguageName('eng', 'it'), 'Inglese');
  expect(trackLanguageName('xyz', 'it'), isNull);
});
test('ChannelLayout dal server', () { /* MediaStreamInfo.fromJson({'ChannelLayout': '5.1', ...}).channelLayout == '5.1' */ });
testWidgets('testa col titolo e righe col dettaglio', (t) async {
  // item episodio L'Istituto S1:E4 → find.text("L'Istituto"), find.text('S1:E4 · La scatola');
  // riga 'Italiano' con 'AC3 5.1 · predefinita'; altezza della riga >= 44
});
testWidgets('Dimensione dice la scelta', (t) async { /* scale 0.8 → find.text('Dimensione · Normali') */ });
testWidgets('Velocità sceglie', (t) async { /* tap '1,25×' → onRate(1.25) */ });
testWidgets('Velocità nel party: 1× e la frase', (t) async {
  // onRate: null → find.text('In compagnia la velocità resta 1×'); tap '2×' non chiama niente
});
testWidgets('TV: righe alte 52, niente ritardo, pannello largo 380', (t) async {
  // tv: true a 960×540 → riga >= 52; find.text('Ritardo dei sottotitoli') findsNothing;
  // host aperto: t.getSize(find.byType(TracksPanel)).width == 380
});
testWidgets('party: nel player la velocità resta 1×', (t) async {
  // party_player_test: apri Audio e sottotitoli, tap '2×' → engine.rates non contiene 2.0
});
```

- [ ] **Step 2:** `flutter test test/features/player/tracks_panel_test.dart test/features/watch_party/party_player_test.dart` → FAIL.
- [ ] **Step 3:** implementa; in `player_screen.dart` `item: view.item`, `rate: view.rate`, `onRate: _inParty ? null : (r) => unawaited(controller.setRate(r))`.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/features/player test/ui` → PASS (i test di `'Ritardo sottotitoli'` e dei tooltip "(G)" si aggiornano).
- [ ] **Step 5: Commit** `feat(app): pannello Audio e sottotitoli rifatto, con la Velocità`

### Task 8: Telefono

**Files:**
- Modify: `app/lib/features/player/player_overlay.dart` (layout stretto), `app/lib/features/player/player_side_panel_host.dart` (foglio dal basso), `app/lib/features/player/player_screen.dart` (`onClose` agli host), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/player/player_compact_test.dart`, `app/test/features/player/tracks_panel_test.dart` (host)

**Interfaces:**
- Consumes: `showSpeedMenu` (Task 2), `PositionLabel`/`RemainingLabel`, `SeekBar(height:)` (Task 3).
- Produces:
  - `PlayerSidePanelHost(..., VoidCallback? onClose)`: nel layout stretto (non TV) il pannello è un foglio: angoli 16 in alto (`ClipRRect`), fondo `surface`, maniglia 36×4 `cream` al 30% centrata (margini 10/4), nessun bordo a sinistra; trascinare giù più di 80 px o con velocità > 700 chiama `onClose`. `player_screen.dart` passa `onClose` ai tre host (tracce, coda, voto).
  - `PlayerOverlay.centerPlaySize = 68.0`, `centerSeekSize = 52.0`.
  - Chiave `playerMore` "Altro" (en "More"); `playerMoreControls` si toglie se non serve più.

Layout `compact && !tv` (spec §4.4, bozza):
- Titolo `WfText.display(26)` (non più `titleLarge`).
- Seek bar con `height: touch ? 44 : SeekBar.height`; sotto una riga `PositionLabel` a sinistra e `RemainingLabel(rate:)` a destra.
- Sotto, griglia di 2 colonne (gap 10, pulsanti alti 44 allineati a sinistra, `WfButton.secondary` con icona e parola): Audio e sottotitoli, Episodio successivo (se c'è), Guarda insieme (se c'è), "Altro" sempre per ultimo.
- "Altro" (icona `ellipsis`, `PopupMenuButton` come il ⋯ di oggi, con il puntino della chat non letta e l'aggancio delle reazioni): Chat, Reazioni, Coda, Episodio precedente (o titolo precedente nel party), Velocità (apre `showSpeedMenu` ancorato ad "Altro"; non c'è nel party), Schermo intero, Disattiva/Riattiva audio. Solo quelli che ci sono.
- Il cursore del volume nello stretto si toglie (restano ↑/↓, la rotella e il muto in "Altro").

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('telefono: titolo Bebas, trio 52/68, quattro pulsanti con la parola', (t) async {
  // touch: true, 390×780
  expect(t.widget<Text>(find.text('Breaking Bad')).style?.fontFamily, WfText.display(26).fontFamily);
  expect(t.getSize(find.byTooltip('Pausa')).width, 68);
  for (final w in ['Audio e sottotitoli', 'Episodio successivo', 'Guarda insieme', 'Altro']) {
    expect(find.widgetWithText(WfButton, w), findsOneWidget);
  }
  expect(t.getSize(find.byType(SeekBar)).height, 44);
});
testWidgets('telefono: Altro tiene il resto', (t) async {
  // party: chat, reazioni, coda, previous; tap 'Altro' → 'Chat', 'Reazioni', 'Coda',
  // 'Titolo precedente', 'Schermo intero', 'Disattiva audio'; 'Velocità' assente nel party
});
testWidgets('telefono: nessun overflow col testo a 1,3', (t) async {
  // 390×780, textScaler 1.3, tutti i comandi → t.takeException() isNull
});
testWidgets('foglio: maniglia, angoli, si chiude trascinando giù', (t) async {
  // host compact (390×780) open → find.byKey(const Key('panel-sheet-handle')) findsOneWidget;
  // t.drag(find.byKey(const Key('panel-sheet-handle')), const Offset(0, 200)) → onClose chiamato
});
testWidgets('desktop e TV: nessuna maniglia', (t) async { /* 1440×900 e tv 960×540 → findsNothing */ });
```

- [ ] **Step 2:** `flutter test test/features/player/player_compact_test.dart test/features/player/tracks_panel_test.dart` → FAIL.
- [ ] **Step 3:** implementa; `_compactCommands` lascia il conteggio degli slot e tiene i comandi fissi qui sopra.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/features/player` → PASS.
- [ ] **Step 5: Commit** `feat(app): player del telefono con le parole e il foglio dal basso`

### Task 9: TV, pulsanti grandi col nome

**Files:**
- Modify: `app/lib/features/player/player_overlay.dart` (`PlayerIconButton` in TV)
- Test: `app/test/features/player/player_tv_controls_test.dart`

**Interfaces:**
- Produces: in TV `PlayerIconButton` è un cerchio di 56 (fondo `bg` al 35%), icona 30 (play/pausa 32), al focus `tvFocusSide` e scala `tvFocusScale` (le costanti di `theme.dart`/`tv_focusable.dart`); sotto il pulsante col focus, a 12 dal cerchio, il suo `tooltip` in 13 w600 su una riga, centrato e disegnato fuori dal layout (un `Stack` con `clipBehavior: Clip.none` o un `OverlayPortal`: la fila non si muove). Il focus si segue con un `Focus(canRequestFocus: false, skipTraversal: true, onFocusChange:)` intorno all'`IconButton`.
- Fuori dalla TV `PlayerIconButton` non cambia.

- [ ] **Step 1: Test che falliscono** (`tv: true`, `Size(960, 540)`)

```dart
testWidgets('TV: cerchi da 56 e icone da 30', (t) async {
  // controlli visibili → t.getSize(find.byTooltip('Audio e sottotitoli')).width == 56;
  // l'Icon dentro ha size 30; play/pausa 32
});
testWidgets('TV: il nome compare sotto il pulsante col focus', (t) async {
  // Giù → focus su play/pausa → find.text('Pausa') findsOneWidget, sotto il pulsante;
  // destra → find.text('Indietro di 10 secondi') e 'Pausa' sparito
  // la y dei pulsanti non cambia tra prima e dopo il focus
  // il nome finisce dentro lo schermo: getBottomLeft(find.text(...)).dy <= 540
});
testWidgets('TV: il pulsante col focus cresce', (t) async {
  // AnimatedScale antenato del pulsante col focus ha scale tvFocusScale
});
```

- [ ] **Step 2:** `flutter test test/features/player/player_tv_controls_test.dart` → FAIL.
- [ ] **Step 3:** implementa; se il nome esce dal fondo, alza la riga dei comandi TV quanto basta (padding inferiore).
- [ ] **Step 4:** `flutter test test/features/player/player_tv_controls_test.dart test/features/player/player_tv_keys_test.dart test/features/tv_focus_borders_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat(app): in TV i comandi del player sono grandi e dicono il loro nome`

### Task 10: Errore, caricamento, "Riproduci"

**Files:**
- Modify: `app/lib/features/player/player_loading.dart` (`PlayerErrorLayer`, `PlayerLoadingLayer`, `BufferingSpinner`; qui arriva anche lo strato "Riproduci"), `app/lib/features/player/player_screen.dart` (`_TapToPlayLayer` si sposta, `backLabel`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/player/player_loading_test.dart`, `app/test/features/player/player_play_blocked_test.dart`, `app/test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: `_backLabel` (Task 4), il livello di focus dell'errore (fase 1).
- Produces:
  - `String? playerErrorDetail(Object error)`: `ServerErrorException(statusCode: n)` → "HTTP n"; `EngineOpenException(message)` → `message`; `PlaybackUnavailableException(code: c)` con `c != null` → `c`; il resto `null`.
  - `PlayerErrorLayer`: colonna centrata, testi `textAlign: center` dentro `ConstrainedBox(maxWidth: PlayerErrorLayer.textMaxWidth)` con `textMaxWidth = 400.0` (circa 46 caratteri a 14 px); titolo `playerErrorTitle` "Il video non parte" (en "The video won't start"); testo `describeError(...)` 14, `cream` all'82%, alto 1,6, seguito (salvo `PlaybackUnavailableException`) da `playerErrorHint` "Di solito basta riprovare. Se succede ancora, scegli una qualità più bassa in Impostazioni."; azioni "Riprova" (primario, focus) e `backLabel` (secondario); sotto, se `playerErrorDetail` c'è, `playerErrorDetailLine(detail)` "Dettaglio per chi gestisce il server: {detail}" 12 `creamMuted`.
  - `class PlayBlockedLayer extends StatelessWidget { const PlayBlockedLayer({super.key, required VoidCallback onPlay, VoidCallback? onBack, String? backLabel}); }`: velo `bg` al 60%, al centro `WfButton.primary` "Riproduci" (`l.actionPlay`, icona play, `autofocus: true`), tocco ovunque = `onPlay`; con `onBack` la ← in alto a sinistra dentro `SafeArea`. Sostituisce `_TapToPlayLayer`; `playerTapToPlay` si toglie.
  - `PlayerLoadingLayer(..., required String backLabel)`: la ← dentro `SafeArea`, tooltip `backLabel`.
  - `BufferingSpinner`: al centro `LoadingLine()` al posto del `CircularProgressIndicator` (nome e chiave `buffering-spinner` restano).

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('errore centrato, largo al massimo 400, con il dettaglio', (t) async {
  // PlayerErrorLayer(error: ServerErrorException(504), backLabel: 'Torna alla scheda') a 1440×900
  expect(find.text('Il video non parte'), findsOneWidget);
  expect(find.text('Dettaglio per chi gestisce il server: HTTP 504'), findsOneWidget);
  expect(find.text('Torna alla scheda'), findsOneWidget);
  final body = find.textContaining('Di solito basta riprovare');
  expect(t.getSize(body).width, lessThanOrEqualTo(400));
  expect(t.widget<Text>(body).textAlign, TextAlign.center);
  expect(t.getCenter(body).dx, closeTo(720, 1));
});
testWidgets('contenuto non riproducibile: niente "riprova"', (t) async {
  // PlaybackUnavailableException(null) → textContaining('Di solito basta riprovare') findsNothing
});
testWidgets('buffering: la linea oro, non lo spinner', (t) async {
  // buffering oltre 300 ms → find.byType(LoadingLine) findsOneWidget; CircularProgressIndicator findsNothing
});
testWidgets('caricamento: la freccia sta sotto la tacca', (t) async {
  // MediaQuery padding top 47 → getTopLeft(find.byTooltip('Torna alla scheda')).dy >= 47
});
testWidgets('autoplay bloccato: Riproduci, anche col mouse', (t) async {
  // player_play_blocked_test: find.widgetWithText(WfButton, 'Riproduci'); 'Tocca per riprodurre' findsNothing
});
```

- [ ] **Step 2:** `flutter test test/features/player/player_loading_test.dart test/features/player/player_play_blocked_test.dart` → FAIL.
- [ ] **Step 3:** implementa; `player_screen.dart` passa `backLabel: _backLabel` all'errore, al caricamento e a `PlayBlockedLayer`.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/features/player` → PASS.
- [ ] **Step 5: Commit** `feat(app): errore del player centrato, buffering con la linea oro e Riproduci`

### Task 11: Post-play e carta del prossimo episodio

**Files:**
- Modify: `app/lib/features/player/post_play.dart`, `app/lib/features/player/player_extras.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/player/post_play_test.dart`, `app/test/features/player/player_extras_test.dart`

**Interfaces:**
- Produces:
  - `playerPlayNowIn` "Riproduci tra {seconds} s" (en "Play in {seconds} s").
  - Occhiello "Prossimo episodio" (o `label`) in Inter 14 w600 `gold`, senza `toUpperCase`, nel post-play e nella carta.
  - `NextEpisodeCard`: secondo pulsante `l.playerWatchCredits` "Guarda i titoli" (icona `film`); il parametro `onCancel` diventa `onWatchCredits`; niente `elevation`: `DecoratedBox` con fondo `surface` al 94%, bordo `border`, angoli 10. `playerCancel` si toglie se non lo usa nessuno.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('carta: Riproduci tra N s e Guarda i titoli', (t) async {
  // NextEpisodeCard(countdown: true, ...) → find.text('Riproduci tra 10 s'); dopo 2 s 'Riproduci tra 8 s';
  // find.text('Guarda i titoli') findsOneWidget; find.text('Annulla') findsNothing
  // nessun Material con elevation > 0 nella carta
});
testWidgets('post-play: occhiello in frase normale', (t) async {
  // find.text('Prossimo episodio') con style.fontFamily != Bebas; 'PROSSIMO EPISODIO' findsNothing
});
testWidgets('TV: il focus parte su Riproduci tra N s', (t) async {
  // tv: true a 960×540, PostPlayLayer con countdown → il PlayNowButton ha il focus
  // (oggi `autofocus` in TV c'è già: il test lo fissa)
});
```

- [ ] **Step 2:** `flutter test test/features/player/post_play_test.dart test/features/player/player_extras_test.dart` → FAIL.
- [ ] **Step 3:** implementa; aggiorna la chiamata in `player_screen.dart` (`onWatchCredits: _dismissNext`). I test del conto che cercavano "· 10" passano a "tra 10 s".
- [ ] **Step 4:** stessi test → PASS.
- [ ] **Step 5: Commit** `feat(app): post-play e carta con Riproduci tra N s e Guarda i titoli`

### Task 12: Trailer coi pezzi del player

**Files:**
- Modify: `app/lib/features/trailer/trailer_screen.dart`
- Test: `app/test/features/trailer/trailer_screen_test.dart`

**Interfaces:**
- Consumes: `PlayerPill`, `PlayerChromeController.showFeedback`/`seek` (feedback soltanto), `PositionLabel`, `RemainingLabel(withEnd: false)` (Task 3), `PlayBlockedLayer` (Task 10), `LoadingLine`.

Cambi (spec §4.8):
- Sfumature in alto e in basso come in `PlayerOverlay` (`bg` 0,8 e 0,9), comandi dentro `SafeArea`.
- In basso: play/pausa, `PositionLabel`, `SeekBar` (Expanded), `RemainingLabel(withEnd: false)`, muto e volume (oro, come Task 4; niente in TV e niente cursore col dito come oggi).
- Pastiglia in alto al centro (`PlayerPill(feedback:)`): volume e muto con `VolumeFeedback`, salti con `chrome.seek(...)` (somma dei salti); un `PlayerChromeController` del trailer, usato solo per il riscontro (`ListenableBuilder`). I tasti restano quelli di oggi (Spazio, ←/→, ↑/↓, M, Esc).
- Clic sul video: col mouse mette in pausa (`_togglePlay`), col dito mostra i controlli.
- In alto: titolo a sinistra e un solo `WfButton.secondary` "Chiudi" (icona `x`) a destra; la ✕ a sinistra si toglie. Con il trailer non disponibile: "Trailer non disponibile" al centro e solo quel "Chiudi", con `autofocus: true` e fuori dall'`ExcludeFocus` della TV.
- Mentre prepara: `LoadingLine()` al posto del `CircularProgressIndicator`.
- Autoplay bloccato: `PlayBlockedLayer(onPlay: () => unawaited(engine.play()))` al posto dell'`IconButton` (la chiave `trailer-tap-to-play` va sul `PlayBlockedLayer`).

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('non disponibile: un solo Chiudi, col focus', (t) async {
  // noneShowsUnavailable → find.text('Chiudi') findsOneWidget; find.byType(FilledButton) findsNothing;
  // il WfButton 'Chiudi' ha il focus (anche con tv: true)
});
testWidgets('un clic sul video mette in pausa', (t) async { /* tap al centro → engine.playing false */ });
testWidgets('volume nella pastiglia', (t) async {
  // ↑ → find.text('Volume 100%') o il valore atteso dentro Key('player-pill')
});
testWidgets('tempo tabellare', (t) async { /* position 0:48 durata 2:12 → '00:48' e '−01:24' */ });
testWidgets('autoplay bloccato: Riproduci', (t) async { /* playBlockedShowsAPlayButton aggiornato: widgetWithText(WfButton, 'Riproduci') */ });
```

- [ ] **Step 2:** `flutter test test/features/trailer/trailer_screen_test.dart` → FAIL.
- [ ] **Step 3:** implementa; i test di oggi che cercavano la ✕ (`byTooltip('Chiudi')`) o il cursore crema si aggiornano.
- [ ] **Step 4:** stesso comando → PASS.
- [ ] **Step 5: Commit** `feat(app): trailer con i pezzi del player e un solo Chiudi`

### Task 13: Checklist e verifica

**Files:**
- Modify: `docs/RELEASING.md`
- Test: tutti

- [ ] **Step 1:** in `docs/RELEASING.md`, sotto le righe della 0.42.0, aggiungi: `- [ ] Revisione finale, fase 2 (app 0.42.0): player con i comandi a gruppi e i tasti nei tooltip, "−49:55 · finisce alle …", pallino sempre visibile, volume oro, Velocità (menu e pannello; nel party resta 1× e lo dice; il titolo dopo riparte da 1×), "Torna alla scheda"/"Torna alla Home", avvisi nella pastiglia; pausa con Riprendi, avanzamento e scheda Tasti, ? la apre e la chiude; Audio e sottotitoli con lingue in italiano e dettagli; telefono con le parole, Altro e foglio che si trascina; TV con cerchi grandi e nome del pulsante col focus, Velocità sulla Fire Stick; errore centrato col dettaglio, buffering con la linea oro, "Riproduci"; post-play e carta con "Riproduci tra N s" e "Guarda i titoli"; trailer con un solo Chiudi, pastiglia e tempi.`
- [ ] **Step 2: Verifica completa:** `flutter gen-l10n`, `flutter analyze` (nessun problema nuovo), `flutter test` (tutti verdi; i flaky noti si rilanciano una volta). Un test di misura in più se non c'è già: `PlayerScreen` pronto a 1280×800, 390×780 (`touch`) e 960×540 (`tv`) senza eccezioni di overflow.
- [ ] **Step 3: Commit** `docs: checklist della revisione finale del player`

## Prova a mano (dopo la review finale)

Release build e avvio dal worktree (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`, poi `Start-Process build\windows\x64\runner\Release\wonderflix.exe`), un episodio de "L'Istituto" o "2012":
- barra a gruppi, tooltip coi tasti, tempo e ora di fine giusta (con 1,5× l'ora si avvicina), volume oro, pallino fermo;
- Velocità dal menu e dal pannello; da una serie, l'episodio dopo riparte da 1×; in un watch party la riga dice "In compagnia la velocità resta 1×";
- pausa: aspetta 8 s, Riprendi, mouse che riporta i comandi, scheda Tasti; `?` in riproduzione, Esc;
- dalla Home la freccia dice "Torna alla Home", dalla scheda "Torna alla scheda";
- un sottotitolo da "Cerca sottotitoli" che vale dalla prossima riproduzione: avviso nella pastiglia;
- finestra stretta: quattro pulsanti, Altro, foglio che si chiude trascinando;
- un trailer (anche uno che manca: un solo Chiudi).

APK sulla Fire Stick (comando in CLAUDE.md), con "2012": cerchi da 56 e nome sotto il pulsante col focus, Audio e sottotitoli laterale con righe da 52, **Velocità 1,5× che si sente davvero** (spec §11: se Media3 non la regge, la Velocità si toglie dalla TV), post-play con l'immagine e focus su "Riproduci tra N s", un video che fallisce con "Riprova" col telecomando. Poi i segni di visto di `davide.sidoti` in `UserData` (CLAUDE.md).
