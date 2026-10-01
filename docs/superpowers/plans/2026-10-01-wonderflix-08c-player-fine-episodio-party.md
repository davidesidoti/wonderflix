# WonderFlix — Piano 8c: player, fine episodio, "Salta intro" e watch party

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** terzo e ultimo piano dello Spec D (rinnovo del player). Comprende:
- il post-play: il film si rimpicciolisce sui titoli di coda noti e accanto si presenta il prossimo episodio;
- la scheda piccola rinnovata, negli ultimi 30 s senza titoli noti;
- "Riproduci ora · N" con il riempimento oro;
- "Salta intro" con la linea che si accorcia e la pillola "Intro saltata";
- il badge del watch party con le iniziali dei membri e l'attesa del gruppo animata.

**Decisioni prese con l'utente (2026-10-01):**
1. **Post-play:**
   - il film è al 42% in alto a sinistra (margine 32 px);
   - sotto: "PROSSIMO EPISODIO", serie, episodio, trama e pulsanti;
   - a destra: l'immagine dell'episodio, che riempie lo spazio rimasto.
2. **Clic ed Esc nel post-play:**
   - un clic sul film piccolo chiude il post-play; lo sfondo fuori dal film non fa nulla;
   - Esc chiude il post-play ("Guarda i titoli"), ma a video finito esce;
   - con la scheda piccola Esc vale "Annulla";
   - ordine di Esc: pannello → post-play o scheda → schermo intero → uscita.
3. **Pannello e pausa:** se i titoli iniziano con il pannello aperto, il pannello si chiude. La schermata di pausa non compare durante il post-play.
4. **Badge:**
   - chi esce si restringe (animazione della larghezza), senza una dissolvenza a parte;
   - il chip della barra in alto (`PartyChip`) resta com'è; le iniziali (al massimo 3, poi "+N") sono solo nel badge del player.
5. **Testi:** nuovi "Riproduci ora · {n}", "Guarda i titoli", "Intro saltata", "Riassunto saltato"; tolto "Inizia tra {n} s".
6. **Conto alla rovescia:** resta un `Timer` al secondo (fermo in pausa e durante il buffering). Il riempimento oro si anima di secondo in secondo: nessuna animazione continua di 10 s, quindi `pumpAndSettle` non fa partire l'episodio da solo.
7. **Release 0.4.0** (non obbligatoria) dopo il merge e la prova dell'utente; si pubblica con il suo ok (non fa parte di questo piano).

**Architecture:**
- **`lib/features/player/segments.dart`:** `outroStart`, `EndZone` (`none`, `credits`, `lastSeconds`), `endZoneAt`.
- **`PlayerChromeController`:**
  - `postPlayDismissed` / `dismissPostPlay()` (vale per post-play e scheda);
  - nuovo riscontro `SkipFeedback` per la pillola.
- **`PlayerScreen`:**
  - tiene `_endZone`, aggiornata dalla posizione del motore (cambia poche volte);
  - calcola `_postPlayShown` / `_cardShown` (episodio successivo, nel party il prossimo della coda, pronto, non rifiutato);
  - avvolge il video in `PostPlayFrame`, che lo rimpicciolisce;
  - mostra `PostPlayLayer` o la `NextEpisodeCard` dentro un `AnimatedSwitcher` sempre presente (chiavi dello `Stack` stabili).
- **`lib/features/player/player_extras.dart`:** `PlayNowButton` (conto alla rovescia con riempimento) e `NextEpisodeCard` rinnovata.
- **`lib/features/player/post_play.dart`:** `PostPlayFrame`, `PostPlayLayer`.
- **`lib/features/player/skip_button.dart`:** `SkipSegmentButton`. `PlayerController.autoSkips` (stream) → pillola.
- **`lib/features/watch_party/party_badge.dart`:** `MemberAvatarStack`, `PartyBadge` con sobbalzo e menu animato.
- **`party_waiting_overlay.dart`:** dissolvenza, clessidra, puntini, entrata scaglionata.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, media_kit_video 2.0.1, lucide_icons_flutter 3.1.20, clock, fake_async.

**Spec:** `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md` (§5.1, §9.1, §12, §13, §15.2, §15.3). **Worktree:** `.claude/worktrees/rinnovo-player-8c`, branch `feat/rinnovo-player-8c`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/rinnovo-player-8c`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git. Niente script heredoc o Python inline in Bash (il controllo dei permessi li rifiuta): per i file usa Edit/Write.
- **Prima di ogni commit:**
  - `flutter analyze` senza nessun problema;
  - `flutter test` tutto verde (a inizio piano: 1014 test); un test rosso deve fermare il commit (niente `;` tra test e commit);
  - dopo aver toccato gli ARB: `flutter gen-l10n`;
  - `git checkout -- windows/flutter/` (soli cambi di fine riga nei file generati).
- **Formattazione:** niente `dart format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`).
- **Regole di stile:**
  - colori solo `WfColors`;
  - durate e curve: token di `WfMotion` o costanti nominate e commentate;
  - tempo: `clock.now()`, mai `DateTime.now()`;
  - icone solo `LucideIcons`;
  - testi UI negli ARB (it + en);
  - commenti in italiano.
- **`Stack` di `PlayerScreen`:**
  - ogni figlio diretto ha una `ValueKey` (i figli si abbinano per posizione: uno strato condizionale che compare farebbe rimontare quelli vicini);
  - i nuovi strati hanno una chiave e, dove possibile, sono **sempre presenti** con il contenuto dentro un `AnimatedSwitcher`;
  - un test (`'strati dello stack: gli altri non si rimontano'`) controlla che `PlayerOverlay`, `PlayerLoadingLayer`, `PlayerPill`, `TracksPanelHost` e `PauseScreen` non si rimontino.
- **Widget test:**
  - `pumpApp` usa il movimento ridotto salvo `motion: MotionLevel.full`; `player_screen_test` e `party_player_test` girano senza `WfMotionScope` (ridotto);
  - `LoadingLine`, `CircularProgressIndicator`, e (con animazioni complete) clessidra e puntini dell'attesa girano senza fermarsi: mai `pumpAndSettle` mentre si vedono. Dopo `pumpPlayer` il caricamento non c'è più;
  - i widget che sfumano via restano nell'albero fino a fine dissolvenza (più un fotogramma per l'`onEnd`);
  - un clic sul film aspetta `kDoubleTapTimeout`, perché il film ha anche il doppio clic;
  - un `Completer`/`Future` creato nel `setUp` vive fuori dalla zona di tempo finto.
- **Fake:**
  - `FakeVideoEngine`: `emitPosition`, `emitCompleted`, `emitDuration` (durata predefinita 2 h), `seeks`, `holdFirstFrame`;
  - `FakePlaybackApi.segments`;
  - `FakeLibraryApi` (`itemsById`, `nextEpisodes`);
  - `testItem(overview:, …)`;
  - `FakePlayerSettings`.
- **Se il codice del piano ha un errore** (analyzer, import, firma di un'API, dettaglio di un test): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **Fine episodio, oggi** (`player_screen.dart`):
  - la scheda è un `PositionSelector<bool>` con `nextEpisodeCardFrom(view.segments, engine.duration)`;
  - "Annulla" imposta `_nextCardDismissed`;
  - `_onFinished`: nel party `nextItem`; da soli, con episodio successivo, riproduzione automatica e scheda non rifiutata parte il successivo, altrimenti si esce;
  - `_playNext` segna come visto se la posizione ha passato `nextEpisodeCardFrom`.
- **`NextEpisodeCard`** (`player_extras.dart`) ha oggi il suo `Timer.periodic` di 10 s con `paused`; "PROSSIMO EPISODIO" è `l.playerNextEpisodeTitle.toUpperCase()`. `PlayerController._loadExtras` chiede l'episodio successivo con `Overview`.
- **Salto automatico** (`PlayerController._onPosition`): solo da soli, con l'impostazione, una volta per segmento; dopo `close()` `_ready` è falso, quindi non salta più.
- **`PopupMenuButton.popUpAnimationStyle`** esiste; `wfPopUpAnimation(context)` è in `lib/ui/wf_menus.dart`. `PartyChip` si usa anche in `watch_party_button.dart` (barra in alto): non va cambiato.
- **`Matrix4`:** per comporre si usano `Matrix4.translationValues(…)` e `.multiplied(Matrix4.diagonal3Values(…))` (non i metodi deprecati `translate`/`scale`). `Transform` trasforma anche il test dei clic.
- **`AnimatedFractionallySizedBox`** esiste nel framework.
- **`WatchPartyState.nextEntry`** (`lib/features/watch_party/watch_party_session.dart`): prossimo elemento della coda del gruppo.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi nuovi; via `playerNextEpisodeIn` (Task 2) |
| `lib/features/player/segments.dart` | modifica | `outroStart`, `EndZone`, `endZoneAt` |
| `lib/features/player/player_chrome.dart` | modifica | `postPlayDismissed`, `dismissPostPlay`, `SkipFeedback` |
| `lib/features/player/player_pill.dart` | modifica | testo, icona e tipo di `SkipFeedback` |
| `lib/features/player/player_extras.dart` | modifica | `PlayNowButton`, `NextEpisodeCard` rinnovata; via `PositionSelector` (Task 5) |
| `lib/features/player/post_play.dart` | crea | `PostPlayFrame`, `PostPlayLayer` |
| `lib/features/player/skip_button.dart` | crea | `SkipSegmentButton` |
| `lib/features/player/player_controller.dart` | modifica | `autoSkips` |
| `lib/features/player/player_screen.dart` | modifica | collega tutto |
| `lib/features/watch_party/party_badge.dart` | modifica | `MemberAvatarStack`, badge animato |
| `lib/features/watch_party/party_waiting_overlay.dart` | modifica | attesa animata |
| `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md` | modifica | allineato all'implementazione |
| test | crea/modifica | vedi i singoli task |

## Gruppi per i subagent

- **Gruppo A (Task 1):** testi, zone di fine, chiusura del post-play, riscontro del salto.
- **Gruppo B (Task 2–3):** pulsante con il conto alla rovescia, scheda, post-play (widget).
- **Gruppo C (Task 4):** fine episodio nel player.
- **Gruppo D (Task 5–7):** "Salta intro", badge, attesa del gruppo.
- **Gruppo E (Task 8):** spec e verifica finale.

---

### Task 1: fondamenta

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify: `lib/features/player/segments.dart`, `lib/features/player/player_chrome.dart`, `lib/features/player/player_pill.dart`
- Create: `test/app/l10n_plan8c_test.dart`
- Test: `test/features/player/segments_test.dart`, `test/features/player/player_chrome_test.dart`, `test/features/player/player_pill_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/app/l10n_plan8c_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 8c', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerPlayNowIn(7), 'Riproduci ora · 7');
    expect(it.playerWatchCredits, 'Guarda i titoli');
    expect(it.playerIntroSkipped, 'Intro saltata');
    expect(it.playerRecapSkipped, 'Riassunto saltato');
    expect(en.playerPlayNowIn(7), 'Play now · 7');
    expect(en.playerWatchCredits, 'Watch credits');
    expect(en.playerIntroSkipped, 'Intro skipped');
    expect(en.playerRecapSkipped, 'Recap skipped');
  });
}
```

In `test/features/player/segments_test.dart`, in fondo a `main()`, aggiungi:

```dart
  group('fine episodio', () {
    const outro = MediaSegment(
        type: MediaSegmentType.outro,
        start: Duration(minutes: 40),
        end: Duration(minutes: 42));
    const duration = Duration(minutes: 42);

    test('outroStart: solo un Outro che non parte da 0', () {
      expect(outroStart(const [outro]), const Duration(minutes: 40));
      expect(outroStart(const []), isNull);
      expect(
          outroStart(const [
            MediaSegment(
                type: MediaSegmentType.outro,
                start: Duration.zero,
                end: Duration(minutes: 1)),
          ]),
          isNull);
    });

    test('con i titoli noti: zona dei titoli dall\'inizio dell\'Outro', () {
      expect(endZoneAt(const [outro], duration, const Duration(minutes: 39)),
          EndZone.none);
      expect(endZoneAt(const [outro], duration, const Duration(minutes: 40)),
          EndZone.credits);
      expect(
          endZoneAt(const [outro], duration,
              const Duration(minutes: 41, seconds: 45)),
          EndZone.credits,
          reason: 'anche negli ultimi 30 s: post-play, non la scheda');
    });

    test('senza titoli noti: ultimi 30 s', () {
      expect(
          endZoneAt(
              const [], duration, const Duration(minutes: 41, seconds: 29)),
          EndZone.none);
      expect(
          endZoneAt(
              const [], duration, const Duration(minutes: 41, seconds: 30)),
          EndZone.lastSeconds);
      expect(endZoneAt(const [], Duration.zero, const Duration(minutes: 1)),
          EndZone.none,
          reason: 'durata ancora ignota');
    });
  });
```

In `test/features/player/player_chrome_test.dart`, prima del test `'dispose: nessun timer in sospeso'`, aggiungi:

```dart
  test('post-play chiuso: resta chiuso, i controlli tornano', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      var notified = 0;
      chrome.addListener(() => notified++);
      expect(chrome.postPlayDismissed, isFalse);
      chrome.dismissPostPlay();
      expect(chrome.postPlayDismissed, isTrue);
      expect(chrome.controlsVisible, isTrue);
      expect(notified, 1);
      chrome.dismissPostPlay();
      expect(notified, 1, reason: 'già chiuso');
      chrome.dispose();
    });
  });
```

In `test/features/player/player_pill_test.dart` aggiungi l'import `import 'package:wonderflix/features/player/segments.dart';` e, nel test `'testi e icone dei riscontri'`, prima della chiusura, le righe:

```dart
    expect(text(const SkipFeedback(SkipKind.intro)), 'Intro saltata');
    expect(text(const SkipFeedback(SkipKind.recap)), 'Riassunto saltato');
    expect(playerFeedbackIcon(const SkipFeedback(SkipKind.intro)),
        LucideIcons.skipForward);
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/app/l10n_plan8c_test.dart test/features/player/segments_test.dart test/features/player/player_chrome_test.dart test/features/player/player_pill_test.dart`
Expected: FAIL (testi, `outroStart`, `EndZone`, `dismissPostPlay`, `SkipFeedback` non esistono).

- [ ] **Step 3: testi.** In `l10n/app_it.arb` sostituisci

```json
  "playerClosePanel": "Chiudi"
}
```

con

```json
  "playerClosePanel": "Chiudi",
  "playerPlayNowIn": "Riproduci ora · {seconds}",
  "@playerPlayNowIn": {"placeholders": {"seconds": {"type": "int"}}},
  "playerWatchCredits": "Guarda i titoli",
  "playerIntroSkipped": "Intro saltata",
  "playerRecapSkipped": "Riassunto saltato"
}
```

In `l10n/app_en.arb` sostituisci

```json
  "playerClosePanel": "Close"
}
```

con

```json
  "playerClosePanel": "Close",
  "playerPlayNowIn": "Play now · {seconds}",
  "@playerPlayNowIn": {"placeholders": {"seconds": {"type": "int"}}},
  "playerWatchCredits": "Watch credits",
  "playerIntroSkipped": "Intro skipped",
  "playerRecapSkipped": "Recap skipped"
}
```

Poi `flutter gen-l10n`.

- [ ] **Step 4: zone di fine.** In `lib/features/player/segments.dart` sostituisci tutta la funzione `nextEpisodeCardFrom` (con il suo commento) con:

```dart
/// Inizio dei titoli di coda (`Outro`) se Jellyfin li conosce; `null`
/// altrimenti (spec D §12).
Duration? outroStart(List<MediaSegment> segments) {
  for (final segment in segments) {
    if (segment.type == MediaSegmentType.outro &&
        segment.start > Duration.zero) {
      return segment.start;
    }
  }
  return null;
}

/// Da quando si propone il prossimo episodio (e l'episodio lasciato conta
/// come visto): inizio dei titoli di coda, altrimenti gli ultimi 30 s.
/// `null` se la durata non è ancora nota.
Duration? nextEpisodeCardFrom(List<MediaSegment> segments, Duration duration) {
  final outro = outroStart(segments);
  if (outro != null) return outro;
  if (duration <= Duration.zero) return null;
  final from = duration - const Duration(seconds: 30);
  return from < Duration.zero ? Duration.zero : from;
}

/// Dove si è rispetto alla fine dell'episodio (spec D §12).
enum EndZone {
  /// Prima della fine.
  none,

  /// Nei titoli di coda noti (`Outro`): post-play.
  credits,

  /// Negli ultimi 30 s, senza titoli noti: scheda piccola.
  lastSeconds,
}

EndZone endZoneAt(
    List<MediaSegment> segments, Duration duration, Duration position) {
  final outro = outroStart(segments);
  if (outro != null) {
    return position >= outro ? EndZone.credits : EndZone.none;
  }
  final from = nextEpisodeCardFrom(segments, duration);
  return from != null && position >= from
      ? EndZone.lastSeconds
      : EndZone.none;
}
```

- [ ] **Step 5: chiusura del post-play e riscontro del salto.** In `lib/features/player/player_chrome.dart`:

1. Aggiungi l'import `import 'segments.dart';` dopo `import '../watch_party/party_notices.dart';`.

2. Dopo la classe `SubtitleDelayFeedback` aggiungi:

```dart

/// Salto automatico di intro o riassunto (spec D §13).
final class SkipFeedback extends PlayerFeedback {
  const SkipFeedback(this.kind);

  final SkipKind kind;
}
```

3. Sostituisci `  bool _pauseScreen = false;` con:

```dart
  bool _pauseScreen = false;
  bool _postPlayDismissed = false;
```

4. Dopo `  bool get pauseScreen => _pauseScreen;` aggiungi:

```dart

  /// L'utente ha chiuso il post-play o la scheda ("Guarda i titoli",
  /// "Annulla", Esc): per questo episodio non tornano.
  bool get postPlayDismissed => _postPlayDismissed;
```

5. Dopo il metodo `closePanel` aggiungi:

```dart

  /// Post-play o scheda chiusi: tornano i controlli (e il loro conto).
  void dismissPostPlay() {
    if (_postPlayDismissed) return;
    _postPlayDismissed = true;
    _controlsVisible = true;
    notifyListeners();
    _scheduleHide();
  }
```

In `lib/features/player/player_pill.dart`:

- in `playerFeedbackText`, dopo il caso `SubtitleDelayFeedback(...)`, aggiungi:

```dart
      SkipFeedback(kind: SkipKind.intro) => l.playerIntroSkipped,
      SkipFeedback() => l.playerRecapSkipped,
```

- in `playerFeedbackIcon`, dopo `SubtitleDelayFeedback() => LucideIcons.captions,`, aggiungi `      SkipFeedback() => LucideIcons.skipForward,`;
- nello `switch` di `kind` in `_content`, dopo `SubtitleDelayFeedback() => SubtitleDelayFeedback,`, aggiungi `          SkipFeedback() => SkipFeedback,`;
- aggiungi l'import `import 'segments.dart';`.

- [ ] **Step 6: verifica.**

Run: `flutter test test/app/l10n_plan8c_test.dart test/features/player/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 7: commit.**

```bash
git add l10n/app_it.arb l10n/app_en.arb lib/features/player/segments.dart lib/features/player/player_chrome.dart lib/features/player/player_pill.dart test/app/l10n_plan8c_test.dart test/features/player/segments_test.dart test/features/player/player_chrome_test.dart test/features/player/player_pill_test.dart
git commit -m "feat: add end-of-episode zones, post-play dismissal and skip feedback"
```

---

### Task 2: "Riproduci ora" con il conto alla rovescia e scheda rinnovata

**Files:**
- Modify: `lib/features/player/player_extras.dart`
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb` (via `playerNextEpisodeIn`)
- Test: `test/features/player/player_extras_test.dart`, `test/app/l10n_plan3b_test.dart`, `test/features/player/player_screen_test.dart`, `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono.** In `test/features/player/player_extras_test.dart` sostituisci i tre test della scheda (`'scheda: conto alla rovescia di 10 s, poi riproduce'`, `'scheda: in pausa il conto alla rovescia si ferma'`, `'scheda senza conto alla rovescia: solo i pulsanti'`) con:

```dart
  testWidgets('pulsante: conto alla rovescia di 10 s, poi riproduce',
      (tester) async {
    var played = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: PlayNowButton(countdown: true, onPressed: () => played++),
        ),
      ),
    );
    expect(find.text('Riproduci ora · 10'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Riproduci ora · 9'), findsOneWidget);
    final fill = tester.widget<AnimatedFractionallySizedBox>(
        find.byType(AnimatedFractionallySizedBox));
    expect(fill.widthFactor, closeTo(0.1, 0.001));
    await tester.pump(const Duration(seconds: 9));
    expect(played, 1);
  });

  testWidgets('pulsante: in pausa il conto si ferma', (tester) async {
    var played = 0;
    final paused = ValueNotifier(false);
    addTearDown(paused.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: paused,
            builder: (context, value, _) => PlayNowButton(
                countdown: true, paused: value, onPressed: () => played++),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Riproduci ora · 7'), findsOneWidget);
    paused.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Riproduci ora · 7'), findsOneWidget);
    expect(played, 0);
    paused.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Riproduci ora · 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(played, 1);
  });

  testWidgets('pulsante senza conto alla rovescia', (tester) async {
    var played = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: PlayNowButton(countdown: false, onPressed: () => played++),
        ),
      ),
    );
    expect(find.text('Riproduci ora'), findsOneWidget);
    expect(find.byType(AnimatedFractionallySizedBox), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(played, 0);
    await tester.tap(find.text('Riproduci ora'));
    expect(played, 1);
  });

  testWidgets('scheda: episodio, pulsanti, entra da destra', (tester) async {
    var played = 0;
    var cancelled = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: NextEpisodeCard(
            episode: episode,
            countdown: false,
            onPlay: () => played++,
            onCancel: () => cancelled++,
          ),
        ),
      ),
      motion: MotionLevel.full,
    );
    double shift() => tester
        .widget<Transform>(find
            .ancestor(
                of: find.text('PROSSIMO EPISODIO'),
                matching: find.byType(Transform))
            .first)
        .transform
        .getTranslation()
        .x;
    await tester.pump(const Duration(milliseconds: 50));
    expect(shift(), greaterThan(0));
    await tester.pumpAndSettle();
    expect(shift(), 0);
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    await tester.tap(find.text('Riproduci ora'));
    await tester.tap(find.text('Annulla'));
    expect((played, cancelled), (1, 1));
  });
```

e aggiungi l'import `import 'package:wonderflix/app/motion.dart';`.

In `test/app/l10n_plan3b_test.dart` togli le due righe di `playerNextEpisodeIn`.

In `test/features/player/player_screen_test.dart` sostituisci ogni `find.text('Inizia tra 10 s')` con `find.text('Riproduci ora · 10')`, `find.text('Inizia tra 7 s')` con `find.text('Riproduci ora · 7')` e `find.textContaining('Inizia tra')` con `find.textContaining('Riproduci ora ·')`. In `test/features/watch_party/party_player_test.dart` sostituisci ogni `find.textContaining('Inizia tra')` con `find.textContaining('Riproduci ora ·')`.

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/player_extras_test.dart`
Expected: FAIL (`PlayNowButton` non esiste).

- [ ] **Step 3: implementazione.** In `lib/features/player/player_extras.dart` aggiungi l'import `import '../../app/motion.dart';` e sostituisci tutta la classe `NextEpisodeCard` e il suo stato (dal commento `/// Scheda "Prossimo episodio": …` alla fine del file) con:

```dart
/// "Riproduci ora" del post-play e della scheda (spec D §12): con
/// [countdown] il fondo si riempie d'oro in [countdownFrom] secondi e
/// l'etichetta conta; con [paused] il conto si ferma; a zero chiama
/// [onPressed]. Un timer al secondo, non un'animazione continua: fermo non
/// chiede fotogrammi.
class PlayNowButton extends StatefulWidget {
  const PlayNowButton({
    super.key,
    required this.countdown,
    required this.onPressed,
    this.paused = false,
  });

  final bool countdown;

  /// Video in pausa o in caricamento: il conto alla rovescia è fermo.
  final bool paused;
  final VoidCallback onPressed;

  static const countdownFrom = 10;

  /// Ogni secondo il riempimento avanza di un passo, a velocità costante.
  static const fillStep = Duration(seconds: 1);
  static const fillCurve = Curves.linear;

  @override
  State<PlayNowButton> createState() => _PlayNowButtonState();
}

class _PlayNowButtonState extends State<PlayNowButton> {
  int _left = PlayNowButton.countdownFrom;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.countdown) {
      // Un solo timer: i secondi in pausa non contano.
      _timer = Timer.periodic(PlayNowButton.fillStep, (timer) {
        if (widget.paused) return;
        if (_left <= 1) {
          timer.cancel();
          setState(() => _left = 0);
          widget.onPressed();
        } else {
          setState(() => _left--);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final reduced = WfMotion.of(context).isReduced;
    final counting = widget.countdown && _left > 0;
    final progress = widget.countdown
        ? (PlayNowButton.countdownFrom - _left) / PlayNowButton.countdownFrom
        : 1.0;
    // Come `WfButton.primary` (altezza 44, angoli 6, testo del tema), con il
    // riempimento oro sotto l'etichetta.
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Material(
        color: widget.countdown
            ? WfColors.gold.withValues(alpha: 0.35)
            : WfColors.gold,
        child: InkWell(
          onTap: widget.onPressed,
          child: Stack(
            children: [
              if (widget.countdown)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      widthFactor: progress,
                      heightFactor: 1,
                      duration:
                          reduced ? Duration.zero : PlayNowButton.fillStep,
                      curve: PlayNowButton.fillCurve,
                      child: const ColoredBox(color: WfColors.gold),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.play,
                          size: 18, color: WfColors.bg),
                      const SizedBox(width: 8),
                      Text(
                        counting ? l.playerPlayNowIn(_left) : l.playerPlayNow,
                        style: const TextStyle(
                            color: WfColors.bg,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            // Cifre della stessa larghezza: il pulsante non
                            // balla a ogni secondo.
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scheda "Prossimo episodio" negli ultimi 30 s, quando Jellyfin non
/// conosce i titoli di coda (spec D §12.2): entra da destra con un piccolo
/// rimbalzo; il film resta a tutto schermo.
class NextEpisodeCard extends ConsumerWidget {
  const NextEpisodeCard({
    super.key,
    required this.episode,
    required this.countdown,
    required this.onPlay,
    required this.onCancel,
    this.paused = false,
  });

  final JellyfinItem episode;
  final bool countdown;

  /// Video in pausa o in caricamento: il conto alla rovescia è fermo.
  final bool paused;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  /// Di quanto arriva da destra entrando.
  static const enterShift = 40.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion.duration(WfMotion.medium),
      curve: motion.isReduced ? WfMotion.standard : WfMotion.bounce,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(motion.isReduced ? 0 : (1 - t) * enterShift, 0),
          child: child,
        ),
      ),
      child: Material(
        color: WfColors.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.playerNextEpisodeTitle.toUpperCase(),
                    style: WfText.display(20, color: WfColors.gold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: WfImage(
                              image: ref
                                  .watch(imageUrlsProvider)
                                  .landscape(episode)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        cardSubtitle(episode) ?? episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PlayNowButton(
                        countdown: countdown, paused: paused, onPressed: onPlay),
                    WfButton.secondary(
                        label: l.playerCancel,
                        icon: LucideIcons.x,
                        onPressed: onCancel),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

Togli da `l10n/app_it.arb` le righe

```json
  "playerNextEpisodeIn": "Inizia tra {seconds} s",
  "@playerNextEpisodeIn": {"placeholders": {"seconds": {"type": "int"}}},
```

e da `l10n/app_en.arb` le righe

```json
  "playerNextEpisodeIn": "Starts in {seconds} s",
  "@playerNextEpisodeIn": {"placeholders": {"seconds": {"type": "int"}}},
```

poi `flutter gen-l10n`. `player_screen.dart` usa già `NextEpisodeCard(episode:, countdown:, paused:, onPlay:, onCancel:)`: non serve cambiarlo.

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/ test/features/watch_party/ test/app/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/player_extras.dart l10n/app_it.arb l10n/app_en.arb test/features/player/player_extras_test.dart test/app/l10n_plan3b_test.dart test/features/player/player_screen_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: fill the play-now button with the countdown"
```

---

### Task 3: post-play (widget)

**Files:**
- Create: `lib/features/player/post_play.dart`
- Test: `test/features/player/post_play_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/features/player/post_play_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_extras.dart';
import 'package:wonderflix/features/player/post_play.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final episode = testItem(
    id: 'e5',
    name: 'Cat in the Bag',
    kind: ItemKind.episode,
    seriesName: 'Breaking Bad',
    index: 5,
    seasonIndex: 1,
    overview: 'Walter e Jesse devono liberarsi di un corpo.',
  );

  group('PostPlayFrame', () {
    Future<ValueNotifier<bool>> pumpFrame(WidgetTester tester,
        {MotionLevel motion = MotionLevel.reduced}) async {
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      await pumpApp(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, value, _) => PostPlayFrame(
            active: value,
            child: const ColoredBox(
                key: Key('film'), color: Color(0xFF00FF00)),
          ),
        ),
        motion: motion,
      );
      return active;
    }

    testWidgets('si rimpicciolisce in alto a sinistra e torna', (tester) async {
      final active = await pumpFrame(tester, motion: MotionLevel.full);
      final full = tester.getRect(find.byKey(const Key('film')));
      expect(full, const Rect.fromLTWH(0, 0, 1440, 900));

      active.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.getRect(find.byKey(const Key('film')));
      expect(mid.width, inExclusiveRange(1440 * postPlayScale, 1440));
      await tester.pumpAndSettle();
      final small = tester.getRect(find.byKey(const Key('film')));
      expect(small.left, closeTo(postPlayInset, 0.01));
      expect(small.top, closeTo(postPlayInset, 0.01));
      expect(small.width, closeTo(1440 * postPlayScale, 0.01));
      expect(small.height, closeTo(900 * postPlayScale, 0.01));

      active.value = false;
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const Key('film'))), full);
    });

    testWidgets('il figlio non si rimonta passando al post-play',
        (tester) async {
      final active = await pumpFrame(tester);
      final before = tester.element(find.byKey(const Key('film')));
      active.value = true;
      await tester.pumpAndSettle();
      expect(tester.element(find.byKey(const Key('film'))), same(before));
    });
  });

  group('PostPlayLayer', () {
    testWidgets('dati del prossimo episodio e pulsanti', (tester) async {
      var played = 0;
      var credits = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: PostPlayLayer(
            episode: episode,
            countdown: true,
            paused: false,
            onPlay: () => played++,
            onWatchCredits: () => credits++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
      expect(find.text('BREAKING BAD'), findsOneWidget);
      expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
      expect(find.text('Walter e Jesse devono liberarsi di un corpo.'),
          findsOneWidget);
      expect(find.text('Riproduci ora · 10'), findsOneWidget);
      expect(find.byType(PlayNowButton), findsOneWidget);

      // Le informazioni stanno sotto il film piccolo, l'immagine a destra.
      final eyebrow = tester.getTopLeft(find.text('PROSSIMO EPISODIO'));
      expect(eyebrow.dx, closeTo(postPlayInset, 0.5));
      expect(eyebrow.dy,
          greaterThan(postPlayInset + 900 * postPlayScale));
      final image = tester.getRect(find.byKey(const Key('post-play-image')));
      expect(image.left, greaterThan(postPlayInset + 1440 * postPlayScale));
      expect(image.right, closeTo(1440 - postPlayInset, 0.5));

      await tester.tap(find.text('Guarda i titoli'));
      expect(credits, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(played, 1, reason: 'conto alla rovescia finito');
    });

    testWidgets('senza conto alla rovescia: "Riproduci ora"', (tester) async {
      var played = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: PostPlayLayer(
            episode: episode,
            countdown: false,
            paused: false,
            onPlay: () => played++,
            onWatchCredits: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riproduci ora'));
      expect(played, 1);
    });
  });
}
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/post_play_test.dart`
Expected: FAIL (file `post_play.dart` inesistente).

- [ ] **Step 3: implementazione.** Crea `lib/features/player/post_play.dart`:

```dart
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'player_extras.dart';

/// Quanto diventa piccolo il film nel post-play (spec D §12.1).
const postPlayScale = 0.42;

/// Margine del film piccolo (e del resto) dai bordi.
const postPlayInset = 32.0;

/// Angoli del film piccolo e dell'immagine.
const postPlayRadius = 12.0;

/// Spazio tra il film piccolo, le informazioni e l'immagine.
const postPlayGap = 24.0;

/// Il film: nel post-play si rimpicciolisce in alto a sinistra con angoli
/// arrotondati e un bordo crema, poi torna a tutto schermo. La struttura
/// non cambia mai (il video non si rimonta); il `Transform` sposta anche i
/// clic.
class PostPlayFrame extends StatelessWidget {
  const PostPlayFrame({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: active ? 1 : 0),
      duration: motion.duration(WfMotion.slow),
      curve: WfMotion.emphasized,
      builder: (context, t, child) {
        final scale = lerpDouble(1, postPlayScale, t)!;
        final inset = postPlayInset * t;
        // Raggio e bordo nelle coordinate del figlio (che è scalato).
        final radius = BorderRadius.circular(postPlayRadius * t / scale);
        return Transform(
          transform: Matrix4.translationValues(inset, inset, 0)
              .multiplied(Matrix4.diagonal3Values(scale, scale, 1)),
          child: ClipRRect(
            borderRadius: radius,
            clipBehavior: t == 0 ? Clip.none : Clip.antiAlias,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: t == 0
                  ? const BoxDecoration()
                  : BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                          color: WfColors.cream.withValues(alpha: 0.35 * t),
                          width: 1.5 / scale),
                    ),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// Informazioni del post-play (spec D §12.1): sotto il film piccolo
/// "PROSSIMO EPISODIO", serie, episodio, trama e pulsanti; a destra
/// l'immagine dell'episodio. Entra sfumando a metà del rimpicciolimento.
class PostPlayLayer extends ConsumerWidget {
  const PostPlayLayer({
    super.key,
    required this.episode,
    required this.countdown,
    required this.paused,
    required this.onPlay,
    required this.onWatchCredits,
  });

  final JellyfinItem episode;
  final bool countdown;

  /// Video in pausa o in caricamento: il conto alla rovescia è fermo.
  final bool paused;
  final VoidCallback onPlay;
  final VoidCallback onWatchCredits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final shrink = motion.duration(WfMotion.slow);
    final fade = motion.duration(WfMotion.medium);
    final total = shrink ~/ 2 + fade;
    final start = (shrink ~/ 2).inMicroseconds / total.inMicroseconds;
    final overview = episode.overview;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: WfMotion.standard),
      builder: (context, t, child) =>
          Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final filmWidth = width * postPlayScale;
        final filmHeight = height * postPlayScale;
        return Stack(
          children: [
            Positioned(
              left: postPlayInset,
              top: postPlayInset + filmHeight + postPlayGap,
              width: filmWidth,
              bottom: postPlayInset,
              child: Align(
                alignment: Alignment.topLeft,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.playerNextEpisodeTitle.toUpperCase(),
                          style: WfText.display(20, color: WfColors.gold)),
                      const SizedBox(height: 8),
                      Text(cardTitle(episode).toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WfText.display(40)),
                      const SizedBox(height: 6),
                      Text(cardSubtitle(episode) ?? episode.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      if (overview != null) ...[
                        const SizedBox(height: 10),
                        Text(overview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: WfColors.creamMuted, height: 1.45)),
                      ],
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          PlayNowButton(
                              countdown: countdown,
                              paused: paused,
                              onPressed: onPlay),
                          WfButton.secondary(
                            label: l.playerWatchCredits,
                            icon: LucideIcons.film,
                            onPressed: onWatchCredits,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              key: const Key('post-play-image'),
              top: postPlayInset,
              left: postPlayInset + filmWidth + postPlayGap,
              right: postPlayInset,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(postPlayRadius),
                    boxShadow: [
                      BoxShadow(
                          color: WfColors.bg.withValues(alpha: 0.8),
                          blurRadius: 32,
                          offset: const Offset(0, 12)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(postPlayRadius),
                    child: WfImage(image: urls.landscape(episode)),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/post_play_test.dart`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/post_play.dart test/features/player/post_play_test.dart
git commit -m "feat: add the post-play frame and layer"
```

---

### Task 4: fine episodio nel player

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_screen_test.dart`, `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono.** In `test/features/player/player_screen_test.dart` aggiungi l'import `import 'package:wonderflix/features/player/post_play.dart';` e, dopo il test `'riproduzione automatica spenta: niente conto alla rovescia'`, i test:

```dart
  /// Episodio con i titoli di coda noti (dall'1:55:00) e il successivo.
  void withCredits() {
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration(hours: 1, minutes: 55),
          end: Duration(hours: 2)),
    ];
    final next = testItem(
      id: 'e5',
      name: 'Cat in the Bag',
      kind: ItemKind.episode,
      seriesName: 'Breaking Bad',
      seriesId: 's1',
      index: 5,
      seasonIndex: 1,
      overview: 'Walter e Jesse devono liberarsi di un corpo.',
    );
    library.itemsById['e5'] = next;
    library.nextEpisodes['e4'] = next;
  }

  Future<void> toCredits(WidgetTester tester) async {
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  bool shrunk(WidgetTester tester) =>
      tester.widget<PostPlayFrame>(find.byType(PostPlayFrame)).active;

  testWidgets('post-play: sui titoli il film si rimpicciolisce, poi parte il '
      'successivo', (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    expect(shrunk(tester), isTrue);
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.text('Guarda i titoli'), findsOneWidget);
    expect(find.text('Riproduci ora · 10'), findsOneWidget);
    expect(controlsOpacity(tester), 0, reason: 'i controlli si nascondono');

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(engines, hasLength(2));
    expect(library.playedCalls, [('e4', true)]);
    await unmount(tester);
  });

  testWidgets('post-play: "Guarda i titoli" torna a tutto schermo; a fine '
      'video si esce', (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    await tester.tap(find.text('Guarda i titoli'));
    await tester.pumpAndSettle();
    expect(shrunk(tester), isFalse);
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);
    expect(controlsOpacity(tester), 1);

    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('post-play: Esc lo chiude e si resta nel player',
      (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(shrunk(tester), isFalse);
    expect(find.text('home'), findsNothing);
    await unmount(tester);
  });

  testWidgets('post-play: un clic sul film piccolo lo chiude', (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    await tester.tapAt(Offset(postPlayInset + 1440 * postPlayScale / 2,
        postPlayInset + 900 * postPlayScale / 2));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(shrunk(tester), isFalse);
    expect(engine.playing, isTrue, reason: 'il clic chiude, non mette in pausa');
    await unmount(tester);
  });

  testWidgets('post-play senza conto alla rovescia: a fine video si resta; '
      'Esc esce', (tester) async {
    settings = const PlayerSettings(autoplayNext: false);
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    expect(find.textContaining('Riproduci ora ·'), findsNothing);
    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsNothing);
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('post-play: niente schermata di pausa; il pannello si chiude',
      (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    await toCredits(tester);
    expect(find.text('Dimensione'), findsNothing,
        reason: 'all\'inizio dei titoli il pannello si chiude');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    await unmount(tester);
  });

  testWidgets('scheda piccola: Esc vale "Annulla"', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(shrunk(tester), isFalse, reason: 'senza titoli noti il film resta');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);
    expect(find.text('home'), findsNothing);
    await unmount(tester);
  });
```

Sempre in `player_screen_test.dart`, la scheda ora sfuma via (un `AnimatedSwitcher`), quindi resta nell'albero per un attimo dopo "Annulla":

- nel test `'strati dello stack: gli altri non si rimontano'`, dopo `await tester.tap(find.text('Annulla'));`, sostituisci il solo `await tester.pump();` con:

```dart
    await tester.pump();
    await tester.pump(WfMotion.fast); // la scheda sfuma via
    await tester.pump();
```

  (lì niente `pumpAndSettle`: lo spinner può girare);
- nel test `'Annulla: a fine episodio si esce'`, dopo `await tester.tap(find.text('Annulla'));`, sostituisci `await tester.pump();` con `await tester.pumpAndSettle();`.

In `test/features/watch_party/party_player_test.dart`:

- aggiungi l'import `import 'package:wonderflix/core/jellyfin/playback_models.dart';` (dopo quello di `item_models.dart`);
- cambia la firma di `pumpPartyPlayer` in `Future<void> pumpPartyPlayer(WidgetTester tester, {int failOpens = 0, List<MediaSegment> segments = const []}) async {` e, dopo `final playback = FakePlaybackApi();`, aggiungi `playback.segments = segments;`;
- dopo il test `'titoli di coda: scheda senza conto alla rovescia'` aggiungi:

```dart
  testWidgets('titoli noti nel gruppo: post-play senza conto alla rovescia',
      (tester) async {
    await pumpPartyPlayer(tester, segments: const [
      MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration(hours: 1, minutes: 55),
          end: Duration(hours: 2)),
    ]);
    await queueSeries(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatchCredits), findsOneWidget);
    expect(find.textContaining('Riproduci ora ·'), findsNothing);
    await tester.tap(find.text(l.playerPlayNow));
    await tester.pump();
    expect(api.calls, contains('next p1'));
    await finish(tester);
  });
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/player_screen_test.dart test/features/watch_party/party_player_test.dart`
Expected: FAIL (nessun post-play nel player).

- [ ] **Step 3: collegamento.** In `lib/features/player/player_screen.dart`:

1. Aggiungi gli import `import '../../app/motion.dart';` (prima di `import '../../app/navigation.dart';`) e `import 'post_play.dart';` (dopo `import 'pause_screen.dart';`).

2. Sostituisci

```dart
  /// L'utente ha chiuso la scheda "Prossimo episodio".
  bool _nextCardDismissed = false;
```

con

```dart
  /// Dove si è rispetto alla fine dell'episodio (spec D §12): cambia poche
  /// volte, e solo allora la schermata si ricostruisce.
  EndZone _endZone = EndZone.none;
  StreamSubscription<Duration>? _positions;
```

3. In `initState`, dopo `        .then((_) => _onFirstFrame(), onError: (Object _) {}));` (la fine di `unawaited(_controller.engine.firstFrame…`), aggiungi:

```dart
    _positions = _controller.engine.positionStream.listen(_onPosition);
```

4. In `dispose`, dopo `_firstFrameTimer?.cancel();` aggiungi `unawaited(_positions?.cancel());`.

5. Dopo il metodo `_syncPlayback` aggiungi:

```dart

  void _onPosition(Duration position) {
    if (!mounted) return;
    final view = ref.read(playerControllerProvider(widget.args));
    final zone =
        endZoneAt(view.segments, _controller.engine.duration, position);
    if (zone == _endZone) return;
    setState(() => _endZone = zone);
    // All'inizio dei titoli il pannello si chiude (sotto c'è il post-play).
    if (_postPlayShown(view)) _chrome.closePanel();
    _syncPlayback();
  }

  /// C'è un episodio successivo da proporre (nel gruppo solo se è il
  /// prossimo della coda, che è quello che parte) e l'utente non l'ha
  /// rifiutato.
  bool _canOfferNext(PlayerViewState view) {
    final next = view.nextEpisode;
    if (next == null ||
        view.status != PlayerStatus.ready ||
        _chrome.postPlayDismissed) {
      return false;
    }
    if (!_inParty) return true;
    return next.id == ref.read(watchPartySessionProvider).nextEntry?.itemId;
  }

  /// Post-play: titoli di coda noti (spec D §12.1).
  bool _postPlayShown(PlayerViewState view) =>
      _endZone == EndZone.credits && _canOfferNext(view);

  /// Scheda piccola: ultimi 30 s senza titoli noti (spec D §12.2).
  bool _cardShown(PlayerViewState view) =>
      _endZone == EndZone.lastSeconds && _canOfferNext(view);

  /// "Guarda i titoli", "Annulla", Esc, clic sul film piccolo.
  void _dismissNext() {
    _chrome.dismissPostPlay();
    _syncPlayback();
  }
```

6. In `_syncPlayback` sostituisci `          !groupWaiting,` con:

```dart
          !groupWaiting &&
          !_postPlayShown(view),
```

7. In `_onFinished` sostituisci

```dart
    if (view.nextEpisode != null && autoplay && !_nextCardDismissed) {
      _playNext(finished: true);
    } else {
      _exit();
    }
```

con

```dart
    if (view.nextEpisode != null && autoplay && !_chrome.postPlayDismissed) {
      _playNext(finished: true);
    } else if (!_postPlayShown(view)) {
      _exit();
    }
    // Post-play aperto e nessun conto alla rovescia: si resta lì (film
    // fermo sull'ultimo fotogramma) finché non si sceglie (spec D §12.1).
```

8. Sostituisci il metodo `_escape` con:

```dart
  /// Esc: pannello → post-play o scheda → schermo intero → uscita (spec D
  /// §9.1). A video finito il post-play non si chiude: si esce.
  void _escape() {
    final view = ref.read(playerControllerProvider(widget.args));
    if (_chrome.panelOpen) {
      _chrome.closePanel();
    } else if ((_postPlayShown(view) && !view.finished) || _cardShown(view)) {
      _dismissNext();
    } else if (_fullscreen) {
      unawaited(_toggleFullscreen());
    } else {
      _exit();
    }
  }
```

9. In `build`, subito dopo `final loading = …;` (la riga che finisce con `(view.status == PlayerStatus.ready && !_firstFrame);`), aggiungi:

```dart
    final postPlay = _postPlayShown(view);
    final card = _cardShown(view);
```

10. Sostituisci

```dart
            cursor: _chrome.controlsVisible
                ? MouseCursor.defer
                : SystemMouseCursors.none,
```

con

```dart
            // Nel post-play i controlli non ci sono ma il cursore resta.
            cursor: _chrome.controlsVisible || postPlay
                ? MouseCursor.defer
                : SystemMouseCursors.none,
```

11. Sostituisci il primo figlio dello `Stack` (il `GestureDetector` con `key: const ValueKey('player-video')`) con:

```dart
                // Il film: nel post-play si rimpicciolisce (spec D §12.1).
                PostPlayFrame(
                  key: const ValueKey('player-video'),
                  active: postPlay,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_chrome.panelOpen) {
                        _chrome.closePanel();
                      } else if (_postPlayShown(ref.read(provider))) {
                        // Clic sul film piccolo: torna a tutto schermo.
                        _dismissNext();
                      } else {
                        unawaited(controller.togglePlay());
                      }
                    },
                    onDoubleTap: () => unawaited(_toggleFullscreen()),
                    child: controller.engine.buildView(),
                  ),
                ),
```

12. Nel blocco dei controlli sostituisci

```dart
                      ignoring: !_chrome.controlsVisible || loading,
                      child: PlayerOverlay(
                        // Durante il caricamento la freccia per uscire sta
                        // nello strato del caricamento.
                        visible: _chrome.controlsVisible && !loading,
```

con

```dart
                      ignoring: !_chrome.controlsVisible || loading || postPlay,
                      child: PlayerOverlay(
                        // Durante il caricamento la freccia per uscire sta
                        // nello strato del caricamento; nel post-play i
                        // controlli non ci sono.
                        visible:
                            _chrome.controlsVisible && !loading && !postPlay,
```

13. Sostituisci tutto il blocco della scheda

```dart
                  // Nel gruppo solo se l'episodio successivo della libreria è
                  // il prossimo della coda (che è quello che parte).
                  if (next != null &&
                      !_nextCardDismissed &&
                      (!_inParty || next.id == party?.nextEntry?.itemId))
                    Positioned(
                      key: const ValueKey('player-next-card'),
```

…fino alla parentesi che chiude quel `Positioned` (la riga `                    ),` prima di `                ],`), con:

```dart
                  // Scheda piccola negli ultimi 30 s senza titoli noti
                  // (spec D §12.2); sempre presente, il contenuto cambia.
                  Positioned(
                    key: const ValueKey('player-next-card'),
                    right: 32,
                    bottom: 150,
                    child: ExcludeFocus(
                      child: AnimatedSwitcher(
                        duration: WfMotion.fast,
                        child: card && next != null
                            ? NextEpisodeCard(
                                key: ValueKey(next.id),
                                episode: next,
                                // Nel gruppo nessun conto alla rovescia: si
                                // va avanti con il pulsante o a fine video.
                                countdown: !_inParty && settings.autoplayNext,
                                paused: !view.playing || view.buffering,
                                onPlay: _playNext,
                                onCancel: _dismissNext,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
```

14. Subito prima del blocco della pillola (il commento `// Riscontro dei tasti e avvisi del watch party …` e il suo `Positioned` con `key: const ValueKey('player-pill-layer')`) aggiungi:

```dart
                // Post-play: informazioni e pulsanti accanto al film piccolo
                // (spec D §12.1); sempre presente, il contenuto cambia.
                Positioned.fill(
                  key: const ValueKey('player-post-play'),
                  child: ExcludeFocus(
                    child: AnimatedSwitcher(
                      duration: WfMotion.fast,
                      child: postPlay && next != null
                          ? SizedBox.expand(
                              key: ValueKey(next.id),
                              child: PostPlayLayer(
                                episode: next,
                                countdown: !_inParty && settings.autoplayNext,
                                paused: !view.playing || view.buffering,
                                onPlay: _playNext,
                                onWatchCredits: _dismissNext,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
```

15. Controlla che non restino `PositionSelector<bool>` né `_nextCardDismissed`. `flutter analyze` deve essere pulito.

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/player/ test/features/watch_party/`
Expected: PASS, compreso `'strati dello stack: gli altri non si rimontano'`. Se quel test rompe per i nuovi strati, verifica che `player-post-play` e `player-next-card` siano sempre presenti (contenuto dentro l'`AnimatedSwitcher`) e correggi lo strato, non il test. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/player/player_screen.dart test/features/player/player_screen_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: shrink the film into the post-play on the end credits"
```

---

### Task 5: "Salta intro" e pillola del salto automatico

**Files:**
- Create: `lib/features/player/skip_button.dart`
- Modify: `lib/features/player/player_controller.dart`, `lib/features/player/player_screen.dart`, `lib/features/player/player_extras.dart` (via `PositionSelector`)
- Test: `test/features/player/skip_button_test.dart`, `test/features/player/player_controller_test.dart`, `test/features/player/player_screen_test.dart`, `test/features/player/player_extras_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/features/player/skip_button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/skip_button.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  const segments = [
    MediaSegment(
        type: MediaSegmentType.recap,
        start: Duration.zero,
        end: Duration(seconds: 10)),
    MediaSegment(
        type: MediaSegmentType.intro,
        start: Duration(seconds: 10),
        end: Duration(seconds: 90)),
  ];

  Future<FakeVideoEngine> pumpSkip(WidgetTester tester,
      {VoidCallback? onSkip, MotionLevel motion = MotionLevel.reduced}) async {
    final engine = FakeVideoEngine();
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: SkipSegmentButton(
              engine: engine, segments: segments, onSkip: onSkip ?? () {}),
        ),
      ),
      motion: motion,
    );
    return engine;
  }

  double lineFactor(WidgetTester tester) => tester
      .widget<FractionallySizedBox>(find.byKey(const Key('skip-line')))
      .widthFactor!;

  testWidgets('intro: pulsante e linea che si accorcia; clic salta',
      (tester) async {
    var skipped = 0;
    final engine = await pumpSkip(tester, onSkip: () => skipped++);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Salta intro'), findsOneWidget);
    expect(lineFactor(tester), closeTo(70 / 80, 0.01));

    engine.emitPosition(const Duration(seconds: 50));
    await tester.pump();
    await tester.pump();
    expect(lineFactor(tester), closeTo(40 / 80, 0.01));

    await tester.tap(find.text('Salta intro'));
    expect(skipped, 1);

    engine.emitPosition(const Duration(seconds: 95));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Salta intro'), findsNothing);
  });

  testWidgets('riassunto: "Salta riassunto"', (tester) async {
    final engine = await pumpSkip(tester);
    engine.emitPosition(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Salta riassunto'), findsOneWidget);
  });

  testWidgets('animazioni complete: entra da destra', (tester) async {
    final engine = await pumpSkip(tester, motion: MotionLevel.full);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Per chiave: dentro `WfButton` c'è anche il `Transform` della scala.
    final shift = tester
        .widget<Transform>(find.byKey(const Key('skip-enter')))
        .transform
        .getTranslation()
        .x;
    expect(shift, greaterThan(0));
    await tester.pumpAndSettle();
  });
}
```

In `test/features/player/player_controller_test.dart`, dopo il test del salto automatico (quello con `settings = const PlayerSettings(autoSkipIntro: true);` e `expect(engine.seeks, [const Duration(seconds: 90)]);`), aggiungi:

```dart
  test('salto automatico: lo segnala (per la pillola)', () async {
    settings = const PlayerSettings(autoSkipIntro: true);
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    final controller = await start();
    final skips = <SkipKind>[];
    final subscription = controller.autoSkips.listen(skips.add);
    addTearDown(subscription.cancel);
    engine.emitPosition(const Duration(seconds: 20));
    await pumpEventQueue();
    expect(skips, [SkipKind.intro]);
  });
```

e l'import `import 'package:wonderflix/features/player/segments.dart';` (dopo quello di `player_settings.dart`).

In `test/features/player/player_extras_test.dart` togli il test `'PositionSelector ricostruisce solo quando cambia il valore'` e l'import di `../../support/playback_fakes.dart` (il widget sparisce in questo task: non ha più usi).

In `test/features/player/player_screen_test.dart`, dopo il test `'salta intro: pulsante durante l\'intro'`, aggiungi:

```dart
  testWidgets('salto automatico: pillola "Intro saltata"', (tester) async {
    settings = const PlayerSettings(autoSkipIntro: true);
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(engine.seeks.last, const Duration(seconds: 90));
    expect(find.text('Intro saltata'), findsOneWidget);
    await unmount(tester);
  });
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/player/skip_button_test.dart test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart`
Expected: FAIL (`SkipSegmentButton`, `autoSkips` non esistono; nessuna pillola).

- [ ] **Step 3: il pulsante.** Crea `lib/features/player/skip_button.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'segments.dart';

/// "Salta intro" / "Salta riassunto" (spec D §13): entra da destra con un
/// piccolo rimbalzo, esce in fretta; una linea oro alla base si accorcia con
/// il tempo che manca alla fine del segmento.
class SkipSegmentButton extends StatefulWidget {
  const SkipSegmentButton({
    super.key,
    required this.engine,
    required this.segments,
    required this.onSkip,
  });

  final VideoEngine engine;
  final List<MediaSegment> segments;
  final VoidCallback onSkip;

  /// Di quanto arriva da destra entrando.
  static const enterShift = 40.0;

  /// Spessore della linea alla base.
  static const lineHeight = 3.0;

  /// Sotto questo cambio la linea non si ridisegna (meno ricostruzioni).
  static const lineEpsilon = 0.005;

  @override
  State<SkipSegmentButton> createState() => _SkipSegmentButtonState();
}

class _SkipSegmentButtonState extends State<SkipSegmentButton> {
  SkipTarget? _target;

  /// Parte del segmento che manca, 1 → 0.
  double _left = 0;
  StreamSubscription<Duration>? _subscription;

  @override
  void initState() {
    super.initState();
    _update(widget.engine.position, rebuild: false);
    _subscription = widget.engine.positionStream.listen(_update);
  }

  @override
  void didUpdateWidget(SkipSegmentButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // I segmenti arrivano dopo l'avvio.
    if (!identical(oldWidget.segments, widget.segments)) {
      _update(widget.engine.position, rebuild: false);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _update(Duration position, {bool rebuild = true}) {
    final target = skipTargetAt(widget.segments, position);
    var left = 0.0;
    if (target != null) {
      final length = target.end - target.segment.start;
      left = length <= Duration.zero
          ? 0
          : ((target.end - position).inMicroseconds / length.inMicroseconds)
              .clamp(0.0, 1.0);
    }
    final sameSegment = target?.segment.start == _target?.segment.start &&
        target?.kind == _target?.kind;
    if (sameSegment &&
        (left - _left).abs() < SkipSegmentButton.lineEpsilon) {
      return;
    }
    if (!rebuild) {
      _target = target;
      _left = left;
      return;
    }
    setState(() {
      _target = target;
      _left = left;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final target = _target;
    return AnimatedSwitcher(
      duration: motion.duration(WfMotion.medium),
      reverseDuration: WfMotion.fast,
      transitionBuilder: (child, animation) {
        if (motion.isReduced) {
          return FadeTransition(opacity: animation, child: child);
        }
        final slide = animation.drive(CurveTween(curve: WfMotion.bounce));
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: slide,
            builder: (context, child) => Transform.translate(
              key: const Key('skip-enter'),
              offset:
                  Offset((1 - slide.value) * SkipSegmentButton.enterShift, 0),
              child: child,
            ),
            child: child,
          ),
        );
      },
      child: target == null
          ? const SizedBox.shrink()
          : Stack(
              key: ValueKey(target.segment.start),
              children: [
                WfButton.secondary(
                  label: target.kind == SkipKind.intro
                      ? l.playerSkipIntro
                      : l.playerSkipRecap,
                  icon: LucideIcons.skipForward,
                  onPressed: widget.onSkip,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: SkipSegmentButton.lineHeight,
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(bottom: Radius.circular(6)),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          key: const Key('skip-line'),
                          widthFactor: _left,
                          heightFactor: 1,
                          child: const ColoredBox(color: WfColors.gold),
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
```

- [ ] **Step 4: lo stream dei salti automatici.** In `lib/features/player/player_controller.dart`:

1. Dopo `  final _autoSkipped = <Duration>{};` aggiungi:

```dart

  final _autoSkips = StreamController<SkipKind>.broadcast();

  /// Salti automatici di intro e riassunti, per la pillola (spec D §13).
  Stream<SkipKind> get autoSkips => _autoSkips.stream;
```

2. In `_onPosition` sostituisci `    unawaited(seekTo(target.end));` con:

```dart
    unawaited(seekTo(target.end));
    _autoSkips.add(target.kind);
```

3. In `_shutdown`, subito dopo `    _generation++;`, aggiungi `    unawaited(_autoSkips.close());` (dopo `close()` `_ready` è falso: `_onPosition` non aggiunge più nulla).

- [ ] **Step 5: collegamento.** In `lib/features/player/player_screen.dart`:

1. Aggiungi l'import `import 'skip_button.dart';` (dopo `import 'segments.dart';`).

2. Dopo `  StreamSubscription<Duration>? _positions;` aggiungi `  StreamSubscription<SkipKind>? _autoSkips;`.

3. In `initState`, dopo la riga di `_positions = …`, aggiungi:

```dart
    // Salto automatico di intro o riassunto: lo dice la pillola.
    _autoSkips = _controller.autoSkips
        .listen((kind) => _chrome.showFeedback(SkipFeedback(kind)));
```

4. In `dispose`, dopo `unawaited(_positions?.cancel());` aggiungi `unawaited(_autoSkips?.cancel());`.

5. Sostituisci il `child:` del `Positioned` con `key: const ValueKey('player-skip')` (cioè `ExcludeFocus(child: PositionSelector<SkipKind?>(…))`) con:

```dart
                    child: ExcludeFocus(
                      child: SkipSegmentButton(
                        engine: controller.engine,
                        segments: view.segments,
                        onSkip: () =>
                            unawaited(controller.skipCurrentSegment()),
                      ),
                    ),
```

6. Togli gli import `import 'package:lucide_icons_flutter/lucide_icons.dart';` e `import '../../ui/wf_buttons.dart';`: servivano solo al vecchio pulsante. `player_extras.dart` resta (serve per `NextEpisodeCard`).

7. In `lib/features/player/player_extras.dart` togli la classe `PositionSelector` con il suo stato (dal commento `/// Ricostruisce [builder] solo quando cambia…` fino a prima del commento di `PlayNowButton`) e l'import `import '../../core/video/video_engine.dart';`: non ha più usi (lo fanno `SkipSegmentButton` e `PlayerScreen._onPosition`).

- [ ] **Step 6: verifica.**

Run: `flutter test test/features/player/`
Expected: PASS (anche il vecchio `'salta intro: pulsante durante l\'intro'`). Poi `flutter analyze` e `flutter test`.

- [ ] **Step 7: commit.**

```bash
git add lib/features/player/skip_button.dart lib/features/player/player_controller.dart lib/features/player/player_screen.dart lib/features/player/player_extras.dart test/features/player/skip_button_test.dart test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart test/features/player/player_extras_test.dart
git commit -m "feat: animate the skip button and announce automatic skips"
```

---

### Task 6: badge del watch party

**Files:**
- Modify: `lib/features/watch_party/party_badge.dart`
- Test: `test/features/watch_party/party_badge_test.dart` (nuovo), `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/features/watch_party/party_badge_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/watch_party/party_badge.dart';

import '../../support/pump_app.dart';

void main() {
  Future<ValueNotifier<List<String>>> pumpStack(WidgetTester tester,
      List<String> members,
      {MotionLevel motion = MotionLevel.reduced}) async {
    final state = ValueNotifier(members);
    addTearDown(state.dispose);
    await pumpApp(
      tester,
      Center(
        child: ValueListenableBuilder<List<String>>(
          valueListenable: state,
          builder: (context, value, _) => MemberAvatarStack(members: value),
        ),
      ),
      motion: motion,
    );
    return state;
  }

  testWidgets('al massimo 3 iniziali, poi "+N"', (tester) async {
    await pumpStack(tester, ['Mario', 'Luigi', 'Sara', 'Anna']);
    await tester.pumpAndSettle();
    expect(find.text('M'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('chi entra compare con un "pop"', (tester) async {
    final state = await pumpStack(tester, ['Mario'], motion: MotionLevel.full);
    await tester.pumpAndSettle();
    state.value = ['Mario', 'Luigi'];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final pop = tester
        .widget<Transform>(find
            .ancestor(of: find.text('L'), matching: find.byType(Transform))
            .first)
        .transform
        .getMaxScaleOnAxis();
    expect(pop, lessThan(1));
    await tester.pumpAndSettle();
  });
}
```

In `test/features/watch_party/party_player_test.dart`, nel test `'distintivo con i membri e uscita dal gruppo'`, dopo `expect(find.text(l.watchPartyButton(2)), findsOneWidget);` aggiungi:

```dart
    expect(
        find.descendant(
            of: find.byKey(const Key('party-badge')), matching: find.text('M')),
        findsOneWidget,
        reason: 'le iniziali dei membri nel badge');
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/watch_party/party_badge_test.dart test/features/watch_party/party_player_test.dart`
Expected: FAIL (`MemberAvatarStack` non esiste; nessuna iniziale nel badge).

- [ ] **Step 3: implementazione.** In `lib/features/watch_party/party_badge.dart` aggiungi gli import `import 'dart:async';` (in cima), `import '../../app/motion.dart';` e `import '../../ui/wf_menus.dart';`. Poi sostituisci la classe `PartyBadge` (con il suo commento) con:

```dart
/// Iniziali dei membri, sovrapposte (spec D §15.2): al massimo
/// [maxShown], poi "+N". Chi entra compare con un "pop"; chi esce lascia
/// stringere la fila.
class MemberAvatarStack extends StatelessWidget {
  const MemberAvatarStack({super.key, required this.members});

  final List<String> members;

  static const maxShown = 3;

  /// Di quanto un'iniziale copre la precedente.
  static const overlap = 8.0;

  /// Diametro di `MemberAvatar` (raggio 13).
  static const avatarSize = 26.0;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final shown = members.take(maxShown).toList();
    final extra = members.length - shown.length;
    return AnimatedSize(
      duration: motion.duration(WfMotion.medium),
      curve: WfMotion.emphasized,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < shown.length; i++)
            Align(
              key: ValueKey(shown[i]),
              alignment: Alignment.centerRight,
              widthFactor: i == 0 ? 1 : (avatarSize - overlap) / avatarSize,
              child: _AvatarPop(child: MemberAvatar(name: shown[i])),
            ),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('+$extra',
                  style: const TextStyle(
                      color: WfColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

/// Un'iniziale nuova cresce con un piccolo rimbalzo (con le animazioni
/// ridotte sfuma soltanto).
class _AvatarPop extends StatelessWidget {
  const _AvatarPop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion.duration(WfMotion.medium),
      curve: motion.isReduced ? WfMotion.standard : WfMotion.bounce,
      builder: (context, t, child) => motion.isReduced
          ? Opacity(opacity: t.clamp(0.0, 1.0), child: child)
          : Transform.scale(scale: t, child: child),
      child: child,
    );
  }
}

/// "Watch party · N" nei controlli del player, con le iniziali dei membri:
/// apre i membri ed "Esci dal watch party". A ogni cambio di membri fa un
/// piccolo sobbalzo (spec D §15.2).
class PartyBadge extends ConsumerStatefulWidget {
  const PartyBadge({super.key, required this.onLeave});

  final VoidCallback onLeave;

  /// Scala massima del sobbalzo.
  static const bumpScale = 1.08;

  @override
  ConsumerState<PartyBadge> createState() => _PartyBadgeState();
}

class _PartyBadgeState extends ConsumerState<PartyBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bump =
      AnimationController(vsync: this, duration: WfMotion.medium);
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: PartyBadge.bumpScale)
            .chain(CurveTween(curve: WfMotion.decelerate)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: PartyBadge.bumpScale, end: 1.0)
            .chain(CurveTween(curve: WfMotion.bounce)),
        weight: 60),
  ]).animate(_bump);

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final party = ref.watch(watchPartySessionProvider);
    final members = party.members;
    final reduced = WfMotion.of(context).isReduced;
    ref.listen(watchPartySessionProvider.select((s) => s.members.length),
        (_, _) {
      if (!reduced) unawaited(_bump.forward(from: 0));
    });
    return PopupMenuButton<String>(
      key: const Key('party-badge'),
      tooltip: party.group?.name,
      position: PopupMenuPosition.under,
      popUpAnimationStyle: wfPopUpAnimation(context),
      onSelected: (value) {
        if (value == 'leave') widget.onLeave();
      },
      itemBuilder: (context) => [
        for (final member in members)
          PopupMenuItem<String>(
            enabled: false,
            child: Row(
              children: [
                MemberAvatar(name: member),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(member,
                      style: const TextStyle(color: WfColors.cream)),
                ),
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
              Flexible(child: Text(l.watchPartyLeave)),
            ],
          ),
        ),
      ],
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border.all(color: WfColors.gold),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MemberAvatarStack(members: members),
              const SizedBox(width: 8),
              Text(l.watchPartyButton(members.length),
                  style: const TextStyle(
                      color: WfColors.gold, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/watch_party/party_badge.dart test/features/watch_party/party_badge_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: show member initials in the watch party badge"
```

---

### Task 7: attesa del gruppo animata

**Files:**
- Modify: `lib/features/watch_party/party_waiting_overlay.dart`
- Test: `test/features/watch_party/party_waiting_overlay_test.dart` (nuovo), `test/features/watch_party/party_player_test.dart`

- [ ] **Step 1: test che falliscono.** Crea `test/features/watch_party/party_waiting_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/watch_party/party_waiting_overlay.dart';

import '../../support/pump_app.dart';

void main() {
  Future<ValueNotifier<bool>> pumpWaiting(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) async {
    final waiting = ValueNotifier(false);
    addTearDown(waiting.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: waiting,
          builder: (context, value, _) =>
              PartyWaitingOverlay(waiting: value, onResume: () {}),
        ),
      ),
      motion: motion,
    );
    return waiting;
  }

  testWidgets('dopo 1 s sfuma dentro; finita l\'attesa sfuma via',
      (tester) async {
    final waiting = await pumpWaiting(tester);
    waiting.value = true;
    await tester.pump();
    await tester.pump(PartyWaitingOverlay.delay);
    await tester.pump();
    expect(find.text('In attesa degli altri membri…'), findsOneWidget);
    double opacity() => tester
        .widget<Opacity>(find.byKey(const Key('party-waiting')))
        .opacity;
    expect(opacity(), lessThan(1), reason: 'sta entrando');
    await tester.pumpAndSettle();
    expect(opacity(), 1);

    waiting.value = false;
    await tester.pump();
    expect(find.text('In attesa degli altri membri…'), findsOneWidget,
        reason: 'resta mentre sfuma');
    await tester.pumpAndSettle();
    expect(find.text('In attesa degli altri membri…'), findsNothing);
  });

  testWidgets('animazioni complete: la clessidra si gira', (tester) async {
    final waiting = await pumpWaiting(tester, motion: MotionLevel.full);
    waiting.value = true;
    await tester.pump();
    await tester.pump(PartyWaitingOverlay.delay);
    await tester.pump();
    double angle() => tester
        .widget<Transform>(find.byKey(const Key('waiting-hourglass')))
        .transform
        .getRotation()
        .entry(1, 0);
    expect(angle(), 0);
    await tester.pump(hourglassPeriod * 0.85);
    expect(angle(), isNot(0));
    // Clessidra e puntini girano: niente pumpAndSettle.
    waiting.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(); // `onEnd` la toglie dall'albero
    expect(find.byKey(const Key('waiting-hourglass')), findsNothing);
  });

  testWidgets('animazioni ridotte: clessidra ferma', (tester) async {
    final waiting = await pumpWaiting(tester);
    waiting.value = true;
    await tester.pump();
    await tester.pump(PartyWaitingOverlay.delay);
    await tester.pumpAndSettle();
    await tester.pump(hourglassPeriod * 0.85);
    expect(
        tester
            .widget<Transform>(find.byKey(const Key('waiting-hourglass')))
            .transform
            .getRotation()
            .entry(1, 0),
        0);
  });
}
```

In `test/features/watch_party/party_player_test.dart`, nel test `'attesa del gruppo: dopo 1 s, con "Riprendi senza aspettare"'`, sostituisci l'ultimo blocco

```dart
    emit(const GroupStateUpdate('g1', GroupState.playing, 'Ready'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyWaiting), findsNothing);
```

con

```dart
    emit(const GroupStateUpdate('g1', GroupState.playing, 'Ready'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle(); // l'attesa sfuma via
    expect(find.text(l.watchPartyWaiting), findsNothing);
```

- [ ] **Step 2: verifica che falliscano.**

Run: `flutter test test/features/watch_party/party_waiting_overlay_test.dart`
Expected: FAIL (`hourglassPeriod`, chiavi `party-waiting`/`waiting-hourglass` non esistono).

- [ ] **Step 3: implementazione.** Sostituisci tutto `lib/features/watch_party/party_waiting_overlay.dart` con:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/wf_buttons.dart';

/// Periodo della clessidra: ferma per il 70%, poi si gira (spec D §15.3).
const hourglassPeriod = Duration(milliseconds: 2400);

/// Periodo dei tre puntini che pulsano.
const waitingDotsPeriod = Duration(milliseconds: 1200);

/// Il gruppo aspetta qualcuno (buffering, ingresso di un membro). Compare
/// dopo [delay], per non lampeggiare nelle attese brevi (spec B §7.1), e
/// sfuma dentro e fuori (spec D §15.3). Sparita, non è nell'albero.
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

  /// Nell'albero: mostrata o mentre sfuma via.
  bool _present = false;

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
      if (mounted) {
        setState(() {
          _visible = true;
          _present = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _visible ? 1 : 0),
      duration: _visible ? motion.duration(WfMotion.medium) : WfMotion.fast,
      curve: WfMotion.standard,
      onEnd: () {
        if (!_visible && mounted) setState(() => _present = false);
      },
      builder: (context, t, child) => Opacity(
        key: const Key('party-waiting'),
        opacity: t.clamp(0.0, 1.0),
        child: child,
      ),
      child: IgnorePointer(
        ignoring: !_visible,
        child: ColoredBox(
          color: WfColors.bg.withValues(alpha: 0.6),
          child: Center(
            child: StaggerGroup(
              count: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const StaggerItem(index: 0, child: _Hourglass()),
                  const SizedBox(height: 16),
                  StaggerItem(
                    index: 1,
                    child: Text(l.watchPartyWaiting, style: WfText.display(28)),
                  ),
                  const SizedBox(height: 12),
                  const StaggerItem(index: 2, child: _WaitingDots()),
                  const SizedBox(height: 20),
                  StaggerItem(
                    index: 3,
                    child: WfButton.secondary(
                      label: l.watchPartyResumeNow,
                      icon: LucideIcons.play,
                      onPressed: widget.onResume,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clessidra oro che si gira ogni [hourglassPeriod] (ferma con le
/// animazioni ridotte).
class _Hourglass extends StatefulWidget {
  const _Hourglass();

  /// Parte del periodo in cui la clessidra sta ferma prima di girarsi.
  static const restFraction = 0.7;

  @override
  State<_Hourglass> createState() => _HourglassState();
}

class _HourglassState extends State<_Hourglass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: hourglassPeriod);
  late final Animation<double> _turn = CurvedAnimation(
    parent: _controller,
    curve: const Interval(_Hourglass.restFraction, 1,
        curve: WfMotion.standard),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (WfMotion.of(context).isReduced) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _turn,
        builder: (context, child) => Transform.rotate(
          key: const Key('waiting-hourglass'),
          angle: _turn.value * math.pi,
          child: child,
        ),
        child: const Icon(LucideIcons.hourglass,
            size: 40, color: WfColors.gold),
      );
}

/// Tre puntini oro che pulsano uno dopo l'altro (fermi con le animazioni
/// ridotte).
class _WaitingDots extends StatefulWidget {
  const _WaitingDots();

  /// Opacità minima di un puntino.
  static const dimOpacity = 0.3;
  static const size = 8.0;

  @override
  State<_WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<_WaitingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: waitingDotsPeriod);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (WfMotion.of(context).isReduced) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Opacity(
                  opacity: _dotOpacity(i),
                  child: const SizedBox.square(
                    dimension: _WaitingDots.size,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: WfColors.gold, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  /// Ogni puntino è sfasato di un terzo di periodo.
  double _dotOpacity(int index) {
    if (!_controller.isAnimating) return _WaitingDots.dimOpacity;
    final phase = (_controller.value - index / 3) % 1;
    final wave = (math.sin(phase * 2 * math.pi) + 1) / 2;
    return _WaitingDots.dimOpacity + (1 - _WaitingDots.dimOpacity) * wave;
  }
}
```

- [ ] **Step 4: verifica.**

Run: `flutter test test/features/watch_party/`
Expected: PASS. Poi `flutter analyze` e `flutter test`.

- [ ] **Step 5: commit.**

```bash
git add lib/features/watch_party/party_waiting_overlay.dart test/features/watch_party/party_waiting_overlay_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: animate the watch party waiting overlay"
```

---

### Task 8: spec e verifica finale

**Files:**
- Modify: `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md`

- [ ] **Step 1: spec.** Nello spec:
  - riga **Stato** in cima: "realizzato nei piani 8a, 8b e 8c (`docs/superpowers/plans/2026-10-01-wonderflix-08a-…`, `…-08b-…`, `…-08c-…`), provato dall'utente";
  - §5.1:
    - il controller tiene `postPlayDismissed`/`dismissPostPlay()`;
    - post-play e scheda li calcola `PlayerScreen` (`_endZone` dalla posizione, `endZoneAt` in `segments.dart`), quindi il controller non ha uno stato `postPlay`;
  - §12.1:
    - aggiungi che un clic sul film piccolo chiude il post-play, mentre lo sfondo fuori dal film non fa nulla;
    - aggiungi che all'inizio dei titoli il pannello si chiude;
    - aggiungi che il riempimento oro avanza di secondo in secondo (`PlayNowButton`);
  - §13: aggiungi `PlayerController.autoSkips` e il riscontro `SkipFeedback` nella pillola;
  - §15.2: le iniziali sono `MemberAvatarStack` solo nel badge del player; `PartyChip` della barra in alto resta com'è; chi esce fa stringere la fila (`AnimatedSize`).

```bash
git add docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md
git commit -m "docs: mark Spec D as implemented and align the end-of-episode sections"
```

- [ ] **Step 2: analisi e test.**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: tutto verde.

- [ ] **Step 3: nessun residuo.**

Run: `grep -rn "playerNextEpisodeIn\|_nextCardDismissed\|PositionSelector" lib`
Expected: nessun risultato.

Run: `git log --format=%B main..HEAD | grep -ci "co-authored"`
Expected: `0`.

- [ ] **Step 4: build di debug.**

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
flutter build windows --debug --dart-define-from-file=config/wonderflix.json
```

Expected: build riuscita. Poi `git checkout -- windows/flutter/` e `git status --short` vuoto.
