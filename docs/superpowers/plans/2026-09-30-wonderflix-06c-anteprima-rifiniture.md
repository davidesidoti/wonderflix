# WonderFlix — Piano 6c: anteprima delle card e rifiniture

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ultima parte dello Spec C (rinnovo grafico):
- **anteprima espansa delle card** (stile Netflix): dopo 500 ms di sosta del mouse su una `PosterCard` o `LandscapeCard` si apre, sopra tutto, un riquadro con sfondo, logo o titolo, Riproduci/Riprendi, La mia lista, Visto, Dettagli, dati, generi e avanzamento; "Dettagli" apre la scheda con il volo Hero dallo sfondo dell'anteprima; con un'anteprima aperta il carosello si ferma;
- **griglie scaglionate** (Catalogo, La mia lista, Ricerca, Persona): entrano solo le card nuove, al massimo 12 per blocco;
- **avvio e login**: logo dello splash con riflesso oro, login che sale in dissolvenza, schermate d'ingresso in dissolvenza;
- **menu, avvisi, invito, banner**: menu a comparsa con i token, snackbar flottanti nel tema, card d'invito che entra da destra, banner d'aggiornamento che sale dal basso;
- **Impostazioni** scaglionate; bordo delle card dai token.

**Decisioni prese con l'utente (2026-09-30):**
1. L'anteprima si disegna nell'overlay **principale** (`OverlayChildLocation.rootOverlay`): sta sopra anche la barra in alto.
2. L'immagine dell'anteprima è **lo stesso sfondo della testata** (`ImageUrls.backdrop(item)`, 1920 px): il volo verso la scheda lo trova già scaricato.
3. **Card degli episodi** ("Continua a guardare", "Prossimi episodi"): titolo della serie con "S1:E4 · titolo"; Riprendi fa ripartire l'episodio, Visto vale per l'episodio, Dettagli apre la serie; **niente cuore**.
4. **Nessun dialogo** nell'app: niente `showWfDialog`. Menu dai token (i 3 fuori dal player; il badge del player non si tocca), snackbar flottanti nel tema.
5. **Splash:** nessuna attesa aggiunta; se la sessione si ripristina prima, l'animazione si interrompe.
6. Griglie a blocchi (un controller per blocco caricato); con un'anteprima aperta il carosello si ferma; bordo delle card → `WfMotion.fast`.
7. Dopo la prova: merge, push, **release 0.3.0 non obbligatoria** (fuori da questo piano, procedura `docs/RELEASING.md`).

**Architecture:**
- `lib/ui/card_preview.dart`: costanti, `previewRect` (funzione pura), `CardPreviewController` + `cardPreviewProvider` (quale anteprima è aperta, quando si è chiusa l'ultima), `CardPreview` (il contenuto).
- `lib/ui/card_preview_host.dart`: `CardPreviewHost` avvolge una card: sosta del mouse, `OverlayPortal.overlayChildLayoutBuilder` nell'overlay principale, apertura/chiusura animate, regole di chiusura (uscita del mouse, rotella, scroll, Esc, finestra non attiva, pagina coperta, altra anteprima), uscita verso la scheda con il volo.
- `lib/ui/staggered_entrance.dart`: si estrae `EntranceTransition` (l'effetto rise/fly) da `StaggerItem`; si aggiungono `BatchedEntrance`/`BatchedEntranceItem` per le griglie.
- `lib/ui/wf_menus.dart`: `wfPopUpAnimation(context)`.
- Splash, login, rotte d'ingresso (`entryPage`), `UpdateGate`, invito del watch party: animazioni dai token.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, `clock`.

**Spec:** `docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md` (§7, §11.3–§11.6). **Piani precedenti:** `…-06a-…`, `…-06b-…` (su `main`). **Worktree:** `.claude/worktrees/rinnovo-6c`, branch `feat/rinnovo-6c`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/rinnovo-6c`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde (a inizio piano: 832 test). Dopo aver cambiato gli ARB: `flutter gen-l10n`.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione e fine riga:** niente `dart format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`). Gli ARB in copia di lavoro sono CRLF: mantieni le fini riga.
- **Icone:** solo `LucideIcons`. **Colori:** solo `WfColors` (anche con `withValues(alpha: …)`). **Durate, curve, misure:** token di `WfMotion` o costanti nominate e commentate. **Tempo:** `clock.now()`, mai `DateTime.now()`. Il player non si tocca.
- **Widget test:** `pumpApp` monta `WfMotionScope` ridotto (default), carosello senza autoplay (default). Con `motion: MotionLevel.full` shimmer e Ken Burns sono continui: mai `pumpAndSettle` mentre sono visibili. Qualunque `Timer` aperto a fine test fa fallire il test: il timer della sosta si cancella in `dispose` e all'uscita del mouse.
- **Mouse nei test:** `final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse); addTearDown(mouse.removePointer); await mouse.addPointer(location: Offset.zero); await mouse.moveTo(punto);`. Rotella: `TestPointer(1, PointerDeviceKind.mouse)` con `hover` e `scroll` (vedi `test/ui/smooth_scroll_test.dart`). Tasti: `tester.sendKeyEvent(LogicalKeyboardKey.escape)`.
- **Fake:** `FakeLibraryApi`, `testItem`, `pageOf` in `test/support/library_fakes.dart`; `FakeSessionController`; `testUser`. `userDataOverridesProvider` gestisce preferiti e visti (vedi `lib/features/library/user_data.dart`).
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API di Flutter con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate (Flutter 3.47)

- **`OverlayPortal.overlayChildLayoutBuilder({controller, overlayChildBuilder: (context, OverlayChildLayoutInfo info) {...}, overlayLocation, child})`**: `info.childSize` è la dimensione della card, `info.childPaintTransform` la sua trasformazione nelle coordinate dell'overlay, `info.overlaySize` la dimensione dell'overlay. Rettangolo della card: `MatrixUtils.transformRect(info.childPaintTransform, Offset.zero & info.childSize)`. `overlayLocation: OverlayChildLocation.rootOverlay` usa l'overlay principale (sopra la barra). Il figlio dell'overlay eredita gli `InheritedWidget` dalla posizione della card (tema, `WfMotionScope`, `WfHeroScope`, `ProviderScope`, `GoRouter`).
- **Hero e overlay:** `Hero._allHeroesFor` visita gli elementi con `visitChildren`, e l'elemento di `OverlayPortal` include il figlio dell'overlay (`_OverlayPortalElement.visitChildren`). `Navigator.of(hero)` risale gli antenati logici: per un `Hero` nell'anteprima trova il navigatore della shell. Il volo dall'anteprima alla scheda funziona; va solo evitato che nella stessa pagina esistano due `Hero` con lo stesso tag (la card e l'anteprima): l'anteprima usa la sorgente `<sorgente della card>.preview`.
- **Chiudere l'anteprima troppo presto annulla il volo:** il volo parte nel fotogramma dopo il `push` e raccoglie gli eroi in quel momento. Con "Dettagli" l'anteprima entra in modalità **uscita**: il corpo (pulsanti, dati) sparisce subito e non riceve clic, l'immagine resta (vola), e l'anteprima si chiude quando la transizione della pagina è finita (`secondaryAnimation` della rotta della card completata) o se la pagina della card torna in cima.
- **Il player è una rotta fuori dalla shell:** aprendolo, la rotta della card resta "corrente" nel navigatore della shell. "Riproduci" chiude l'anteprima prima di avviare.
- **Riverpod in `dispose`:** `ref` non si usa in `dispose`; il controller dell'anteprima va letto prima (`late final … = ref.read(cardPreviewProvider.notifier)` in `initState`) e la chiusura rinviata con `Future.microtask` per non modificare un provider mentre l'albero si smonta.
- **Finestra non attiva:** su Windows la perdita del focus porta l'app in `AppLifecycleState.inactive` (`WidgetsBindingObserver.didChangeAppLifecycleState`).
- **Nessun `showDialog`** nell'app. I `PopupMenuButton` sono in `app_shell.dart` (menu utente), `watch_party_button.dart` (due) e `party_badge.dart` (player: non si tocca). `popUpAnimationStyle` è un parametro di `PopupMenuButton`, non del tema.
- **`TabBarView`** del login scorre già tra Password e Quick Connect: resta com'è.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `lib/core/jellyfin/item_query.dart` | modifica | `Genres` nei campi delle liste |
| `lib/ui/card_preview.dart` | crea | costanti, `previewRect`, controller, contenuto dell'anteprima |
| `lib/ui/card_preview_host.dart` | crea | sosta, overlay, apertura/chiusura, uscita con volo |
| `lib/ui/poster_card.dart`, `lib/ui/landscape_card.dart` | modifica | `CardPreviewHost`; via `onPlay`/`CardPlayButton`; bordo dai token |
| `lib/ui/card_play_button.dart` | elimina | sostituito dall'anteprima |
| `lib/features/home/home_screen.dart` | modifica | niente `onPlay` |
| `lib/features/home/hero_carousel.dart` | modifica | pausa con un'anteprima aperta |
| `lib/ui/staggered_entrance.dart` | modifica | `EntranceTransition`, `BatchedEntrance`, `BatchedEntranceItem` |
| `lib/features/catalog/catalog_screen.dart`, `mylist/my_list_screen.dart`, `search/search_screen.dart`, `person/person_screen.dart`, `settings/settings_screen.dart` | modifica | entrate |
| `lib/features/startup/splash_screen.dart`, `lib/features/auth/login_screen.dart`, `lib/app/router.dart`, `lib/app/page_transitions.dart` | modifica | avvio e login |
| `lib/features/update/update_gate.dart`, `lib/features/watch_party/watch_party_invites.dart` | modifica | banner, schermata obbligatoria, invito |
| `lib/ui/wf_menus.dart` | crea | animazione dei menu |
| `lib/app/app_shell.dart`, `lib/features/watch_party/watch_party_button.dart` | modifica | menu dai token |
| `lib/app/theme.dart` | modifica | snackbar flottanti |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | `previewResume` |
| `docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md` | modifica | §7, §11.3, §11.4 allineati |

## Gruppi per i subagent

- **Gruppo A (Task 1–4):** anteprima.
- **Gruppo B (Task 5–7):** griglie, avvio e login, menu e avvisi.
- **Gruppo C (Task 8):** spec e verifica finale.

---

### Task 1: dati, posizione e controller dell'anteprima

**Files:**
- Modify: `lib/core/jellyfin/item_query.dart`
- Create: `lib/ui/card_preview.dart` (prima parte)
- Test: `test/ui/card_preview_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/card_preview.dart';

void main() {
  const overlay = Size(1440, 900);

  test('previewRect: centrata sulla card, larga 1,8 volte', () {
    const card = Rect.fromLTWH(600, 300, 200, 300);
    final r = previewRect(card: card, overlay: overlay);
    expect(r.width, 360);
    expect(r.height, 360 * 9 / 16 + previewBodyHeight);
    expect(r.center.dx, card.center.dx);
    expect(r.center.dy, card.center.dy);
  });

  test('previewRect: minimo 300 di larghezza', () {
    final r = previewRect(card: const Rect.fromLTWH(600, 300, 100, 150), overlay: overlay);
    expect(r.width, previewMinWidth);
  });

  test('previewRect: vicino ai bordi resta dentro con 16 px di margine', () {
    final left = previewRect(card: const Rect.fromLTWH(0, 300, 160, 240), overlay: overlay);
    expect(left.left, previewMargin);
    final right = previewRect(card: const Rect.fromLTWH(1380, 300, 160, 240), overlay: overlay);
    expect(right.right, overlay.width - previewMargin);
    final top = previewRect(card: const Rect.fromLTWH(600, -100, 160, 240), overlay: overlay);
    expect(top.top, previewMargin);
    final bottom = previewRect(card: const Rect.fromLTWH(600, 850, 160, 240), overlay: overlay);
    expect(bottom.bottom, overlay.height - previewMargin);
  });

  test('controller: una sola aperta, e catena subito dopo la chiusura', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final previews = container.read(cardPreviewProvider.notifier);
      final a = Object();
      final b = Object();
      expect(previews.opensImmediately(), isFalse);
      previews.open(a);
      expect(container.read(cardPreviewProvider).openId, a);
      expect(previews.opensImmediately(), isTrue);
      previews.open(b);
      expect(container.read(cardPreviewProvider).openId, b);
      // Chiudere un'anteprima non aperta non cambia nulla.
      previews.close(a);
      expect(container.read(cardPreviewProvider).openId, b);
      previews.close(b);
      expect(container.read(cardPreviewProvider).openId, isNull);
      expect(previews.opensImmediately(), isTrue);
      async.elapse(previewChainWindow + const Duration(milliseconds: 1));
      expect(previews.opensImmediately(), isFalse);
    }, initialTime: DateTime(2026, 9, 30));
  });
}
```

  (`fakeAsync` rende finto anche `clock.now()` dentro la zona: il controller usa `clock`.)

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/card_preview_test.dart`
Expected: FAIL (file inesistente).

- [ ] **Step 3: implementa.** In `item_query.dart` `'fields': 'PrimaryImageAspectRatio,Genres'` (i generi dell'anteprima, spec §7.4). In `lib/ui/card_preview.dart`:

```dart
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sosta del mouse su una card prima che si apra l'anteprima (spec C §7.1).
const previewHoverDelay = Duration(milliseconds: 500);

/// Entro questo tempo dalla chiusura di un'anteprima, la card su cui passa
/// il mouse apre la sua subito (passaggio da una card all'altra).
const previewChainWindow = Duration(milliseconds: 400);

/// Larghezza dell'anteprima rispetto alla card, e minimo (spec C §7.2).
const previewWidthFactor = 1.8;
const previewMinWidth = 300.0;

/// Altezza della parte sotto l'immagine 16:9: pulsanti, dati, generi,
/// avanzamento.
const previewBodyHeight = 124.0;

/// Distanza minima dai bordi della finestra.
const previewMargin = 16.0;

/// Rettangolo dell'anteprima di una card: centrata sulla card, larga
/// [previewWidthFactor] volte (almeno [previewMinWidth]), dentro l'overlay
/// con [previewMargin] di margine.
Rect previewRect({required Rect card, required Size overlay}) {
  final maxWidth = math.max(0.0, overlay.width - 2 * previewMargin);
  final width = math
      .max(previewMinWidth, card.width * previewWidthFactor)
      .clamp(0.0, maxWidth)
      .toDouble();
  final height = width * 9 / 16 + previewBodyHeight;
  final left = (card.center.dx - width / 2).clamp(
      previewMargin, math.max(previewMargin, overlay.width - previewMargin - width));
  final top = (card.center.dy - height / 2).clamp(
      previewMargin, math.max(previewMargin, overlay.height - previewMargin - height));
  return Rect.fromLTWH(left.toDouble(), top.toDouble(), width, height);
}

/// Quale anteprima è aperta (al massimo una) e quando si è chiusa l'ultima.
@immutable
class CardPreviewState {
  const CardPreviewState({this.openId, this.closedAt});

  /// Identità della card che mostra l'anteprima (lo stato del suo host).
  final Object? openId;
  final DateTime? closedAt;
}

class CardPreviewController extends Notifier<CardPreviewState> {
  @override
  CardPreviewState build() => const CardPreviewState();

  void open(Object id) => state = CardPreviewState(openId: id);

  /// Chiude l'anteprima di [id], se è quella aperta.
  void close(Object id) {
    if (!identical(state.openId, id)) return;
    state = CardPreviewState(closedAt: clock.now());
  }

  /// Un'anteprima è aperta o si è appena chiusa: la prossima si apre subito.
  bool opensImmediately() {
    if (state.openId != null) return true;
    final closed = state.closedAt;
    return closed != null && clock.now().difference(closed) < previewChainWindow;
  }
}

final cardPreviewProvider =
    NotifierProvider<CardPreviewController, CardPreviewState>(
        CardPreviewController.new);
```

- [ ] **Step 4: verifica e commit**

Run: `flutter test test/ui/card_preview_test.dart`, poi `flutter analyze` e `flutter test`.
Expected: PASS, tutto verde.

```bash
git add lib/core/jellyfin/item_query.dart lib/ui/card_preview.dart test/ui/card_preview_test.dart
git commit -m "feat: add card preview layout and controller"
```

---

### Task 2: contenuto dell'anteprima

**Files:**
- Modify: `lib/ui/card_preview.dart` (seconda parte), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/ui/card_preview_content_test.dart`, `test/app/l10n_plan6c_test.dart`

- [ ] **Step 1: stringhe.** In `l10n/app_it.arb` (prima della `}` finale, virgola alla riga precedente, CRLF): `"previewResume": "Riprendi"`; in `l10n/app_en.arb`: `"previewResume": "Resume"`. Poi `flutter gen-l10n`. Test `test/app/l10n_plan6c_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 6c', () {
    expect(lookupAppLocalizations(const Locale('it')).previewResume, 'Riprendi');
    expect(lookupAppLocalizations(const Locale('en')).previewResume, 'Resume');
  });
}
```

- [ ] **Step 2: scrivi il test che fallisce** (`test/ui/card_preview_content_test.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/card_preview.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final signedIn = sessionControllerProvider
      .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser)));

  Future<List<String>> pumpPreview(WidgetTester tester, JellyfinItem item,
      {FakeLibraryApi? api}) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Center(
        child: SizedBox(
          width: 360,
          height: 360 * 9 / 16 + previewBodyHeight,
          child: CardPreview(
            item: item,
            heroTag: null,
            onPlay: () => calls.add('play'),
            onDetails: () => calls.add('details'),
          ),
        ),
      ),
      overrides: [
        signedIn,
        libraryApiProvider.overrideWithValue(api ?? FakeLibraryApi()),
      ],
    );
    return calls;
  }

  testWidgets('film: titolo, dati, generi, pulsanti', (tester) async {
    final calls = await pumpPreview(tester, testItem(id: 'm1'));
    expect(find.text('DUNE: PARTE DUE'), findsOneWidget);
    expect(find.textContaining('2024'), findsWidgets);
    expect(find.byTooltip('Riproduci'), findsOneWidget);
    expect(find.byTooltip('Aggiungi a La mia lista'), findsOneWidget);
    expect(find.byTooltip('Segna come visto'), findsOneWidget);
    await tester.tap(find.byTooltip('Riproduci'));
    await tester.tap(find.byTooltip('Dettagli'));
    expect(calls, ['play', 'details']);
  });

  testWidgets('iniziato: "Riprendi" e barra dell\'avanzamento', (tester) async {
    await pumpPreview(tester, testItem(id: 'm1', playedPercentage: 40));
    expect(find.byTooltip('Riprendi'), findsOneWidget);
    expect(find.byKey(const Key('preview-progress')), findsOneWidget);
  });

  testWidgets('episodio: titolo della serie, codice, niente cuore',
      (tester) async {
    await pumpPreview(
      tester,
      testItem(
        id: 'e4',
        name: 'Please Hold',
        kind: ItemKind.episode,
        seriesName: 'The Last of Us',
        index: 4,
        seasonIndex: 1,
      ),
    );
    expect(find.text('THE LAST OF US'), findsOneWidget);
    expect(find.text('S1:E4 · Please Hold'), findsOneWidget);
    expect(find.byTooltip('Aggiungi a La mia lista'), findsNothing);
    expect(find.byTooltip('Segna come visto'), findsOneWidget);
  });

  testWidgets('clic sull\'immagine: come "Dettagli"', (tester) async {
    final calls = await pumpPreview(tester, testItem(id: 'm1'));
    await tester.tap(find.byKey(const Key('preview-image')));
    expect(calls, ['details']);
  });

  testWidgets('cuore: aggiunge a La mia lista', (tester) async {
    final api = FakeLibraryApi();
    await pumpPreview(tester, testItem(id: 'm1'), api: api);
    await tester.tap(find.byTooltip('Aggiungi a La mia lista'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Togli da La mia lista'), findsOneWidget);
    expect(find.byIcon(LucideIcons.heart), findsOneWidget);
  });
}
```

  (Se il tooltip per togliere dalla lista ha un altro testo in `app_it.arb` — cerca `actionRemoveFromList` — usa quello. Se il fake registra le chiamate ai preferiti con un altro nome, aggiungi l'attesa su quello invece del cambio di tooltip.)

- [ ] **Step 3: verifica che fallisca**

Run: `flutter test test/ui/card_preview_content_test.dart`
Expected: FAIL (`CardPreview` non esiste).

- [ ] **Step 4: implementa** in `lib/ui/card_preview.dart` (import `dart:async`, `package:flutter/material.dart` al posto di `widgets.dart`, `package:lucide_icons_flutter/lucide_icons.dart`, `../app/error_text.dart`, `../app/hero_launch.dart`, `../app/theme.dart`, `../core/jellyfin/item_models.dart`, `../features/detail/detail_header.dart` per `MetaLine`, `../features/library/item_labels.dart`, `../features/library/library_providers.dart`, `../features/library/user_data.dart`, `../l10n/gen/app_localizations.dart`, `backdrop_image.dart`, `poster_card.dart` per `ProgressStrip`, `wf_buttons.dart`, `wf_image.dart`):

```dart
/// Contenuto dell'anteprima di una card (spec C §7.3). [onPlay] e
/// [onDetails] li decide l'host (chiude l'anteprima, avvia il volo).
class CardPreview extends ConsumerWidget {
  const CardPreview({
    super.key,
    required this.item,
    required this.heroTag,
    required this.onPlay,
    required this.onDetails,
    this.body = kAlwaysCompleteAnimation,
  });

  final JellyfinItem item;

  /// Tag del volo verso la scheda (sorgente della card + `.preview`).
  final WfHeroTag? heroTag;
  final VoidCallback onPlay;
  final VoidCallback onDetails;

  /// Opacità della parte sotto l'immagine e del titolo: in uscita verso la
  /// scheda sparisce subito, mentre l'immagine vola.
  final Animation<double> body;

  Future<void> _toggle(BuildContext context, Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final userData = watchUserData(ref, item);
    final overrides = ref.read(userDataOverridesProvider.notifier);
    final progress = userData.progress;
    final episode = item.kind == ItemKind.episode;
    final logo = episode ? null : urls.logo(item);
    final subtitle = episode ? cardSubtitle(item) : null;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 12);

    return Material(
      color: WfColors.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      shadowColor: WfColors.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: WfColors.gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: GestureDetector(
              key: const Key('preview-image'),
              onTap: onDetails,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    WfHero(
                      tag: heroTag,
                      borderRadius: BorderRadius.zero,
                      child: BackdropImage(
                          backdrop: urls.backdrop(item),
                          fallback: urls.poster(item)),
                    ),
                    FadeTransition(
                      opacity: body,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [WfColors.surface, Color(0x00121212)],
                            stops: [0, 0.6],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 8,
                      child: FadeTransition(
                        opacity: body,
                        child: logo != null
                            ? SizedBox(
                                height: 44,
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  child: WfImage(image: logo, fit: BoxFit.contain),
                                ),
                              )
                            : Text(cardTitle(item).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WfText.display(26)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FadeTransition(
              opacity: body,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _RoundButton(
                          icon: LucideIcons.play,
                          tooltip: progress != null ? l.previewResume : l.actionPlay,
                          filled: true,
                          onPressed: onPlay,
                        ),
                        const SizedBox(width: 8),
                        if (!episode) ...[
                          WfIconToggle(
                            icon: LucideIcons.heart,
                            selected: userData.isFavorite,
                            tooltip: userData.isFavorite
                                ? l.actionRemoveFromList
                                : l.actionAddToList,
                            onPressed: () => unawaited(_toggle(
                                context, () => overrides.toggleFavorite(item))),
                          ),
                          const SizedBox(width: 8),
                        ],
                        WfIconToggle(
                          icon: LucideIcons.check,
                          selected: userData.played,
                          tooltip: userData.played
                              ? l.actionMarkUnwatched
                              : l.actionMarkWatched,
                          onPressed: () => unawaited(_toggle(
                              context, () => overrides.togglePlayed(item))),
                        ),
                        const Spacer(),
                        _RoundButton(
                          icon: LucideIcons.chevronDown,
                          tooltip: l.actionDetails,
                          onPressed: onDetails,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (subtitle != null)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    DefaultTextStyle.merge(
                      style: const TextStyle(fontSize: 12),
                      child: MetaLine(item: item),
                    ),
                    if (item.genres.isNotEmpty)
                      Text(item.genres.take(3).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted),
                    const Spacer(),
                    if (progress != null)
                      SizedBox(
                        key: const Key('preview-progress'),
                        height: 3,
                        child: ProgressStrip(progress: progress),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsante tondo dell'anteprima (play pieno oro, dettagli a contorno).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size(36, 36),
          backgroundColor: filled ? WfColors.gold : Colors.transparent,
          foregroundColor: filled ? WfColors.bg : WfColors.cream,
          side: filled ? null : const BorderSide(color: WfColors.creamMuted),
        ),
        icon: Icon(icon, size: 18),
      );
}
```

  (`MetaLine` è in `detail_header.dart`; se l'import crea un ciclo con `lib/ui`, spostala in `lib/features/library/item_labels.dart` o in un file proprio e segnalalo. Se `WfIconToggle` a 44 px non entra nell'altezza `previewBodyHeight`, riduci i pulsanti a 36 px con un parametro `size` opzionale su `WfIconToggle` e segnalalo.)

- [ ] **Step 5: verifica e commit**

Run: `flutter test test/ui/card_preview_content_test.dart test/app/l10n_plan6c_test.dart`, poi `flutter analyze` e `flutter test`.
Expected: PASS, tutto verde.

```bash
git add lib/ui/card_preview.dart l10n test/ui/card_preview_content_test.dart test/app/l10n_plan6c_test.dart
git commit -m "feat: add card preview content"
```

---

### Task 3: host dell'anteprima sulle card

**Files:**
- Create: `lib/ui/card_preview_host.dart`
- Modify: `lib/ui/poster_card.dart`, `lib/ui/landscape_card.dart`, `lib/features/home/home_screen.dart`
- Delete: `lib/ui/card_play_button.dart`
- Test: `test/ui/card_preview_host_test.dart`, `test/ui/cards_test.dart`

- [ ] **Step 1: scrivi il test che fallisce** (`test/ui/card_preview_host_test.dart`)

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/poster_card.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final overrides = [
    sessionControllerProvider
        .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    libraryApiProvider.overrideWithValue(FakeLibraryApi()),
  ];

  Future<void> pumpCards(WidgetTester tester, {List<VoidCallback>? taps}) async {
    await pumpApp(
      tester,
      Scaffold(
        body: ListView(
          key: const Key('page'),
          padding: const EdgeInsets.all(200),
          children: [
            Row(children: [
              PosterCard(
                  key: const Key('card-a'),
                  item: testItem(id: 'a', name: 'Alien'),
                  width: 160,
                  onTap: taps?[0]),
              const SizedBox(width: 400),
              PosterCard(
                  key: const Key('card-b'),
                  item: testItem(id: 'b', name: 'Heat'),
                  width: 160,
                  onTap: taps?[1]),
            ]),
            const SizedBox(height: 2000),
          ],
        ),
      ),
      overrides: overrides,
    );
  }

  Future<TestGesture> mouseOver(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    return mouse;
  }

  testWidgets('si apre dopo 500 ms di sosta, non prima', (tester) async {
    await pumpCards(tester);
    await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(CardPreview), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byType(CardPreview), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('si chiude quando il mouse esce', (tester) async {
    await pumpCards(tester);
    final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('uscire prima dei 500 ms: niente anteprima, nessun timer',
      (tester) async {
    await pumpCards(tester);
    final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(const Duration(milliseconds: 200));
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('Esc la chiude', (tester) async {
    await pumpCards(tester);
    await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('la rotella la chiude', (tester) async {
    await pumpCards(tester);
    await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    final wheel = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.byType(CardPreview))));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('da un\'anteprima a un\'altra card: si apre subito, una sola',
      (tester) async {
    await pumpCards(tester);
    final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('card-b'))));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CardPreview), findsOneWidget);
    expect(find.text('HEAT'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('tocco: apre la scheda, niente anteprima', (tester) async {
    var taps = 0;
    await pumpCards(tester, taps: [() => taps++, () {}]);
    await tester.tap(find.byKey(const Key('card-a')));
    await tester.pump(const Duration(seconds: 1));
    expect(taps, 1);
    expect(find.byType(CardPreview), findsNothing);
  });
}
```

  (La seconda card è a 400 px dalla prima: l'anteprima di A, larga 300, non la copre. Se la geometria dei test cambia, tienila così: il test "da un'anteprima a un'altra card" deve uscire dall'anteprima e **entrare** in B.)

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/card_preview_host_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa** (`lib/ui/card_preview_host.dart`)

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/hero_launch.dart';
import '../app/motion.dart';
import '../app/navigation.dart';
import '../core/jellyfin/item_models.dart';
import '../features/playback/play_launcher.dart';
import 'card_preview.dart';

/// Suffisso della sorgente del volo per l'anteprima: la card e la sua
/// anteprima stanno nella stessa pagina e non possono avere lo stesso tag.
const previewHeroSuffix = '.preview';

/// Avvolge una card: con il mouse fermo sopra per [previewHoverDelay] apre
/// l'anteprima nell'overlay principale (spec C §7). Solo con il mouse: con
/// tocco e tastiera il clic della card apre la scheda.
class CardPreviewHost extends ConsumerStatefulWidget {
  const CardPreviewHost({
    super.key,
    required this.item,
    required this.heroSource,
    required this.child,
  });

  final JellyfinItem item;

  /// Sorgente del volo della card (già resa unica per la pagina), o `null`.
  final String? heroSource;
  final Widget child;

  @override
  ConsumerState<CardPreviewHost> createState() => _CardPreviewHostState();
}

class _CardPreviewHostState extends ConsumerState<CardPreviewHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _portal = OverlayPortalController();
  late final CardPreviewController _previews =
      ref.read(cardPreviewProvider.notifier);
  late final AnimationController _open =
      AnimationController(vsync: this, duration: WfMotion.medium);

  /// Corpo dell'anteprima: 1 normalmente, 0 in uscita verso la scheda.
  late final AnimationController _body =
      AnimationController(vsync: this, duration: WfMotion.fast, value: 1);

  Timer? _hoverTimer;
  ScrollPosition? _scroll;
  Animation<double>? _routeCover;

  /// "Dettagli": l'immagine vola, il resto è già sparito.
  bool _leaving = false;

  bool get _showing => _portal.isShowing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La pagina della card non è più in cima (push, go): via l'anteprima,
    // salvo l'uscita verso la scheda, che si chiude a transizione finita.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (!current && _showing && !_leaving) _hide(immediately: true);
    if (current && _leaving) _hide(immediately: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hide(immediately: true);
  }

  void _onEnter(PointerEnterEvent event) {
    if (event.kind != PointerDeviceKind.mouse || _showing) return;
    _hoverTimer?.cancel();
    if (_previews.opensImmediately()) {
      _show();
    } else {
      _hoverTimer = Timer(previewHoverDelay, _show);
    }
  }

  void _onExitCard(PointerExitEvent event) => _hoverTimer?.cancel();

  void _show() {
    _hoverTimer?.cancel();
    if (!mounted || _showing) return;
    final motion = WfMotion.of(context);
    _previews.open(this);
    _leaving = false;
    _body.value = 1;
    _open.duration = motion.duration(WfMotion.medium);
    _portal.show();
    unawaited(_open.forward(from: 0));
    _scroll = Scrollable.maybeOf(context)?.position;
    _scroll?.addListener(_onScroll);
    HardwareKeyboard.instance.addHandler(_onKey);
    setState(() {});
  }

  void _onScroll() => _hide(immediately: true);

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _hide();
      return true;
    }
    return false;
  }

  void _detach() {
    _scroll?.removeListener(_onScroll);
    _scroll = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _routeCover?.removeStatusListener(_onRouteCover);
    _routeCover = null;
  }

  /// Chiude l'anteprima: in dissolvenza breve, o subito.
  void _hide({bool immediately = false}) {
    _hoverTimer?.cancel();
    if (!_showing) return;
    _detach();
    _previews.close(this);
    void done() {
      if (!mounted) return;
      _leaving = false;
      _portal.hide();
      setState(() {});
    }

    if (immediately) {
      _open.value = 0;
      done();
    } else {
      _open.duration = WfMotion.fast;
      unawaited(_open.reverse().whenComplete(done));
    }
  }

  void _play() {
    _hide(immediately: true);
    unawaited(playItem(context, ref, widget.item));
  }

  void _details() {
    final source = widget.heroSource;
    if (source == null || WfMotion.of(context).isReduced) {
      _hide(immediately: true);
      openItem(context, widget.item);
      return;
    }
    // L'immagine vola verso la testata: resta finché la pagina nuova è
    // entrata; il resto sparisce subito e non riceve più clic.
    setState(() => _leaving = true);
    _detach();
    unawaited(_body.animateTo(0, duration: WfMotion.fast));
    final cover = ModalRoute.of(context)?.secondaryAnimation;
    _routeCover = cover;
    cover?.addStatusListener(_onRouteCover);
    openItem(context, widget.item, heroSource: '$source$previewHeroSuffix');
  }

  void _onRouteCover(AnimationStatus status) {
    if (status == AnimationStatus.completed) _hide(immediately: true);
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _detach();
    WidgetsBinding.instance.removeObserver(this);
    final previews = _previews;
    final id = this;
    // Non si modifica un provider mentre l'albero si smonta.
    unawaited(Future.microtask(() => previews.close(id)));
    _open.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Un'altra card ha aperto la sua anteprima: questa si chiude.
    ref.listen(cardPreviewProvider, (previous, next) {
      if (_showing && !_leaving && !identical(next.openId, this)) {
        _hide(immediately: true);
      }
    });
    final motion = WfMotion.of(context);
    final source = widget.heroSource;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context, info) {
        final card = MatrixUtils.transformRect(
            info.childPaintTransform, Offset.zero & info.childSize);
        final rect = previewRect(card: card, overlay: info.overlaySize);
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: MouseRegion(
                onExit: (_) {
                  if (!_leaving) _hide();
                },
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) _hide(immediately: true);
                  },
                  child: IgnorePointer(
                    ignoring: _leaving,
                    child: AnimatedBuilder(
                      animation: _open,
                      builder: (context, child) {
                        final t = _open.value;
                        final scale = motion.isReduced
                            ? 1.0
                            : 0.6 + 0.4 * WfMotion.bounce.transform(t);
                        return Opacity(
                          opacity: WfMotion.standard.transform(t).clamp(0.0, 1.0),
                          child: Transform.scale(scale: scale, child: child),
                        );
                      },
                      child: RepaintBoundary(
                        child: CardPreview(
                          item: widget.item,
                          heroTag: source == null
                              ? null
                              : WfHeroTag(widget.item.id,
                                  '$source$previewHeroSuffix'),
                          body: _body,
                          onPlay: _play,
                          onDetails: _details,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: MouseRegion(
        onEnter: _onEnter,
        onExit: _onExitCard,
        child: widget.child,
      ),
    );
  }
}
```

  (Se `OverlayPortal.overlayChildLayoutBuilder` vuole il figlio già posizionato in modo diverso — per esempio non accetta uno `Stack` a tutta dimensione — segui la documentazione dell'SDK in `packages/flutter/lib/src/widgets/overlay.dart` e segnalalo. Lo `Stack` non intercetta il mouse fuori dall'anteprima.)

- [ ] **Step 4: card.** In `poster_card.dart` e `landscape_card.dart`:
  - togli `onPlay`, `CardPlayButton` e il suo import; elimina `lib/ui/card_play_button.dart`;
  - il bordo usa `duration: WfMotion.fast` (import `../app/motion.dart`);
  - il `MouseRegion` della card resta (bordo oro); la card intera (il `SizedBox` esterno) è avvolta in `CardPreviewHost(item: widget.item, heroSource: heroSource, child: …)` (dove `heroSource` è la sorgente già resa unica con `WfHeroScope.source`).
  - In `home_screen.dart` togli gli `onPlay` passati alle card (e l'import di `play_launcher.dart` se non serve più).

- [ ] **Step 5: test esistenti.** In `test/ui/cards_test.dart` il gruppo `'pulsante play al passaggio del mouse'` e le attese su `CardPlayButton` verificano un comportamento tolto per decisione dello spec (§7.1): sostituiscili con **un** test che, passando il mouse su una `PosterCard` per `previewHoverDelay`, trova `CardPreview` (il resto è coperto da `card_preview_host_test.dart`). Cerca altri usi di `onPlay` delle card e di `CardPlayButton` in `test/` e aggiornali allo stesso modo, spiegando nel resoconto.

- [ ] **Step 6: verifica e commit**

Run: `flutter test test/ui`, poi `flutter analyze` e `flutter test`.
Expected: PASS, tutto verde.

```bash
git add -A lib/ui lib/features/home/home_screen.dart test/ui
git commit -m "feat: open card previews on hover"
```

---

### Task 4: volo dall'anteprima e pausa del carosello

**Files:**
- Modify: `lib/features/home/hero_carousel.dart`
- Test: `test/app/hero_router_test.dart` (aggiunta), `test/features/home/hero_carousel_test.dart` (aggiunta)

- [ ] **Step 1: scrivi i test che falliscono**
  - In `test/app/hero_router_test.dart` (usa la stessa impostazione del test "volo reale nella ShellRoute", animazioni complete): passa il mouse su una card con `heroSource` per `previewHoverDelay`, `pumpAndSettle`; tocca `find.byTooltip('Dettagli')`; `pump()` e `pump(const Duration(milliseconds: 100))` → `find.byKey(wfHeroFlightKey)` trova qualcosa (il volo parte dall'anteprima); `pumpAndSettle` → la scheda è in cima e `find.byType(CardPreview)` trova nulla; nessuna eccezione (`tester.takeException()` null). Se nel test la scheda carica con uno scheletro visibile (onda continua), sostituisci `pumpAndSettle` con `pump(WfMotion.hero)` + `pump(WfMotion.medium)`.
  - In `test/features/home/hero_carousel_test.dart`: con autoplay acceso, aprire un'anteprima (basta `container.read(cardPreviewProvider.notifier).open(Object())`, prendendo il container con `ProviderScope.containerOf(tester.element(find.byType(HeroCarousel)))`) → `pump(HeroCarousel.interval * 2)` → resta 'DUNE'; chiuderla (`close` con lo stesso oggetto) → dopo un intervallo più la dissolvenza compare 'ALIEN' (usa l'helper `pumpUntilShown` del file).

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/app/hero_router_test.dart test/features/home/hero_carousel_test.dart`
Expected: FAIL (il carosello non conosce l'anteprima; il volo dall'anteprima va verificato).

- [ ] **Step 3: carosello.** In `hero_carousel.dart` (import `../../ui/card_preview.dart`), nello stato: `bool _previewOpen = false;`; in `build`:

```dart
    ref.listen(cardPreviewProvider.select((s) => s.openId != null),
        (previous, open) {
      _previewOpen = open;
      _syncProgress();
    });
```

  e `_syncProgress()` considera `_previewOpen` come il mouse sopra (il tempo scorre solo se autoplay, niente mouse sopra, nessuna anteprima, Home non coperta). Aggiorna il commento del controller.

- [ ] **Step 4: volo.** Se il test del volo dall'anteprima fallisce per un motivo diverso dal carosello (per esempio l'anteprima chiusa prima che il volo parta, o il tag non trovato), correggi `CardPreviewHost._details` rispettando le "Note tecniche verificate" e spiega la causa.

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` e `flutter test`.
Expected: tutto verde.

```bash
git add lib/features/home/hero_carousel.dart lib/ui test/app/hero_router_test.dart test/features/home/hero_carousel_test.dart
git commit -m "feat: fly from the card preview and pause the carousel while it is open"
```

---

### Task 5: griglie a blocchi e Impostazioni scaglionate

**Files:**
- Modify: `lib/ui/staggered_entrance.dart`, `lib/features/catalog/catalog_screen.dart`, `lib/features/mylist/my_list_screen.dart`, `lib/features/search/search_screen.dart`, `lib/features/person/person_screen.dart`, `lib/features/settings/settings_screen.dart`
- Test: `test/ui/batched_entrance_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

void main() {
  Widget grid(int count, {Object? reset, MotionLevel level = MotionLevel.full}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: WfMotionScope(
          motion: WfMotion(level),
          child: BatchedEntrance(
            itemCount: count,
            resetKey: reset,
            child: Column(children: [
              for (var i = 0; i < count; i++)
                BatchedEntranceItem(index: i, child: Text('card $i')),
            ]),
          ),
        ),
      );

  double opacityOf(WidgetTester tester, String text) {
    final fades = tester.widgetList<Opacity>(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)));
    return fades.isEmpty ? 1 : fades.first.opacity;
  }

  testWidgets('primo blocco: entrano al massimo 12', (tester) async {
    await tester.pumpWidget(grid(14));
    expect(opacityOf(tester, 'card 0'), 0);
    expect(opacityOf(tester, 'card 12'), 1, reason: 'oltre il massimo');
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'card 0'), 1);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('pagina successiva: entrano solo le nuove', (tester) async {
    await tester.pumpWidget(grid(4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(grid(8));
    expect(opacityOf(tester, 'card 0'), 1);
    expect(opacityOf(tester, 'card 4'), 0);
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'card 7'), 1);
  });

  testWidgets('elementi tolti: nessuna entrata', (tester) async {
    await tester.pumpWidget(grid(6));
    await tester.pumpAndSettle();
    await tester.pumpWidget(grid(5));
    expect(opacityOf(tester, 'card 0'), 1);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('nuova chiave (filtro): si riparte dall\'inizio', (tester) async {
    await tester.pumpWidget(grid(4, reset: 'a'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(grid(4, reset: 'b'));
    expect(opacityOf(tester, 'card 0'), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('ridotte: nessuna entrata', (tester) async {
    await tester.pumpWidget(grid(4, level: MotionLevel.reduced));
    expect(opacityOf(tester, 'card 0'), 1);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/batched_entrance_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa** in `lib/ui/staggered_entrance.dart`:
  - estrai da `StaggerItem` l'effetto in un widget pubblico riusabile:

```dart
/// Effetto d'entrata guidato da [progress] (0 → 1): usato dagli elementi
/// degli scaglionamenti e dei blocchi delle griglie.
class EntranceTransition extends StatelessWidget {
  const EntranceTransition({
    super.key,
    required this.progress,
    this.effect = EntranceEffect.rise,
    required this.child,
  });

  final Animation<double> progress;
  final EntranceEffect effect;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: progress,
        child: child,
        builder: (context, child) { /* il corpo di oggi di StaggerItem */ },
      );
}
```

    e `StaggerItem` lo usa (comportamento invariato: i test esistenti devono restare verdi);
  - aggiungi:

```dart
/// Card di una griglia che entrano per ogni blocco caricato (spec C §11.5).
const gridEntranceMax = 12;

/// Passo tra una card e l'altra nell'entrata di un blocco.
const gridEntranceStagger = Duration(milliseconds: 40);

/// Entrata a blocchi per le griglie con caricamento a pagine: quando
/// [itemCount] cresce entrano solo gli elementi nuovi (al massimo
/// [gridEntranceMax]); se cala (elementi tolti) nessuna entrata; se
/// cambia [resetKey] (filtro, ricerca) si riparte dall'inizio. Un
/// controller per blocco, liberato a entrata finita. Con le animazioni
/// ridotte nessuna entrata.
class BatchedEntrance extends StatefulWidget {
  const BatchedEntrance({
    super.key,
    required this.itemCount,
    required this.child,
    this.resetKey,
  });

  final int itemCount;
  final Object? resetKey;
  final Widget child;

  @override
  State<BatchedEntrance> createState() => _BatchedEntranceState();
}

class _Batch {
  _Batch(this.start, this.count, this.controller, this.total);

  final int start;
  final int count;
  final AnimationController controller;
  final Duration total;

  bool contains(int index) => index >= start && index < start + count;
}

class _BatchedEntranceState extends State<BatchedEntrance>
    with TickerProviderStateMixin {
  final _batches = <_Batch>[];
  int _known = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _add(0, widget.itemCount);
  }

  @override
  void didUpdateWidget(BatchedEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _clear();
      _add(0, widget.itemCount);
    } else if (widget.itemCount > _known) {
      _add(_known, widget.itemCount - _known);
    } else if (widget.itemCount < _known) {
      _known = widget.itemCount;
    }
  }

  void _add(int start, int count) {
    _known = start + count;
    if (count <= 0 || WfMotion.of(context).isReduced) return;
    final n = count < gridEntranceMax ? count : gridEntranceMax;
    final total = staggerTotal(
        count: n,
        delay: Duration.zero,
        stagger: gridEntranceStagger,
        item: WfMotion.slow);
    final controller = AnimationController(vsync: this, duration: total);
    final batch = _Batch(start, n, controller, total);
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() => _batches.remove(batch));
      controller.dispose();
    });
    _batches.add(batch);
    unawaited(controller.forward());
  }

  void _clear() {
    for (final batch in _batches) {
      batch.controller.dispose();
    }
    _batches.clear();
    _known = 0;
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _BatchScope(batches: List.unmodifiable(_batches), child: widget.child);
}

class _BatchScope extends InheritedWidget {
  const _BatchScope({required this.batches, required super.child});

  final List<_Batch> batches;

  @override
  bool updateShouldNotify(_BatchScope oldWidget) =>
      !identical(oldWidget.batches, batches);
}

/// Elemento [index] di una griglia con [BatchedEntrance].
class BatchedEntranceItem extends StatelessWidget {
  const BatchedEntranceItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final batches =
        context.dependOnInheritedWidgetOfExactType<_BatchScope>()?.batches;
    final batch = batches?.where((b) => b.contains(index)).firstOrNull;
    if (batch == null) return child;
    final interval = staggerInterval(
      index: index - batch.start,
      delay: Duration.zero,
      stagger: gridEntranceStagger,
      item: WfMotion.slow,
      total: batch.total,
    );
    return EntranceTransition(
      progress: batch.controller.drive(CurveTween(
          curve: Interval(interval.begin, interval.end,
              curve: WfMotion.emphasized))),
      child: child,
    );
  }
}
```

  (import `dart:async` per `unawaited`.)

- [ ] **Step 4: uso.**
  - **Catalogo:** `BatchedEntrance(itemCount: state.items.length, resetKey: state.query, child: CustomScrollView(...))` e nel `SliverChildBuilderDelegate` `BatchedEntranceItem(index: i, child: PosterCard(...))`. Attenzione: il `CustomScrollView` del catalogo usa `_scroll` solo se non è il figlio uscente del `WfSwitcher` (6b): non cambiarlo.
  - **La mia lista:** `BatchedEntrance(itemCount: visible.length, child: …)`, card avvolte.
  - **Ricerca:** ogni sezione di locandine in `BatchedEntrance(itemCount: items.length, resetKey: state.term, child: Wrap(...))`, card avvolte.
  - **Persona:** la griglia della filmografia in `BatchedEntrance(itemCount: items.length, child: …)`, card avvolte.
  - **Impostazioni:** le sezioni (titolo + contenuto di ogni sezione, nell'ordine) diventano figli `StaggerItem(index: n)` di uno `StaggerGroup(count: <numero di sezioni>, child: Column(...))`; il titolo "IMPOSTAZIONI" è l'elemento 0.
  - Aggiungi un test widget per il catalogo: con animazioni complete e una prima pagina di 3 titoli, subito dopo l'arrivo dei dati la prima card ha un `Opacity` < 1 sopra di sé (usa `pump` a passi, mai `pumpAndSettle` se è visibile lo scheletro).

- [ ] **Step 5: verifica e commit**

Run: `flutter test test/ui test/features`, poi `flutter analyze` e `flutter test`.
Expected: PASS, tutto verde.

```bash
git add lib/ui/staggered_entrance.dart lib/features test/ui/batched_entrance_test.dart test/features
git commit -m "feat: stagger grid pages and settings sections"
```

---

### Task 6: avvio, login e schermate d'ingresso

**Files:**
- Modify: `lib/features/startup/splash_screen.dart`, `lib/features/auth/login_screen.dart`, `lib/app/page_transitions.dart`, `lib/app/router.dart`, `lib/features/update/update_gate.dart`
- Test: `test/features/startup/splash_screen_test.dart` (nuovo o esistente), `test/features/auth/login_screen_test.dart` (aggiunta)

- [ ] **Step 1: scrivi i test che falliscono**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/startup/splash_screen.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('completa: il logo compare e il riflesso passa una volta',
      (tester) async {
    await pumpApp(tester, const SplashScreen(), motion: MotionLevel.full);
    final logo = find.byKey(const Key('splash-logo'));
    double opacity() => tester
        .widget<Opacity>(find.ancestor(of: logo, matching: find.byType(Opacity)).first)
        .opacity;
    expect(opacity(), lessThan(1));
    expect(find.byKey(const Key('splash-sheen')), findsOneWidget);
    await tester.pump(splashIntroDuration);
    await tester.pump();
    expect(opacity(), 1);
  });

  testWidgets('ridotta: logo fermo, nessun riflesso', (tester) async {
    await pumpApp(tester, const SplashScreen());
    expect(find.byKey(const Key('splash-sheen')), findsNothing);
    final fades = tester.widgetList<Opacity>(find.ancestor(
        of: find.byKey(const Key('splash-logo')), matching: find.byType(Opacity)));
    expect(fades.every((f) => f.opacity == 1), isTrue);
  });
}
```

  (Lo spinner dello splash è un'animazione continua: niente `pumpAndSettle`. Se esiste già un test dello splash, aggiungi lì questi casi.) Nel test del login aggiungi, con animazioni complete, che logo e pannello siano `StaggerItem` di uno `StaggerGroup` (`find.byType(StaggerGroup)` trova uno e il pannello ha un `Opacity` < 1 subito dopo il pump; poi `pumpAndSettle` se nessuna animazione continua è visibile, altrimenti `pump(const Duration(seconds: 1))`).

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/startup test/features/auth`
Expected: FAIL.

- [ ] **Step 3: splash.** `SplashScreen` diventa `StatefulWidget` con `SingleTickerProviderStateMixin`:

```dart
/// Entrata del logo dello splash: comparsa e un solo riflesso oro (spec C
/// §11.3). Non allunga l'avvio: se la sessione è pronta prima, si va avanti.
const splashIntroDuration = Duration(milliseconds: 1200);
```

  - in `didChangeDependencies` (una volta): se le animazioni non sono ridotte crea `AnimationController(duration: splashIntroDuration)..forward()`;
  - il logo (`Image.asset(..., key: const Key('splash-logo'))`) è avvolto, se c'è il controller, in: opacità su `Interval(0, 0.35, curve: WfMotion.standard)`, scala da 0,9 a 1 su `Interval(0, 0.5, curve: WfMotion.emphasized)`, e un `ShaderMask(key: const Key('splash-sheen'), blendMode: BlendMode.srcATop, shaderCallback: …)` con un gradiente lineare trasparente → oro 60% → trasparente che attraversa il logo da sinistra a destra su `Interval(0.45, 1)` (fuori dall'intervallo il gradiente è tutto trasparente);
  - lo spinner resta com'è.

- [ ] **Step 4: login.** Il logo e il pannello della `Row` di `LoginScreen` diventano `StaggerItem(index: 0)` e `StaggerItem(index: 1)` di uno `StaggerGroup(count: 2, child: Row(...))`. Il `TabBarView` tra Password e Quick Connect resta (scorre già).

- [ ] **Step 5: rotte d'ingresso.** In `page_transitions.dart`:

```dart
/// Splash, login, server non raggiungibile: dissolvenza (spec C §11.3).
Page<void> entryPage(BuildContext context, GoRouterState state, Widget child) {
  final motion = WfMotion.of(context);
  final duration = motion.duration(WfMotion.medium);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
            opacity: animation.drive(CurveTween(curve: WfMotion.standard)),
            child: child),
  );
}
```

  e in `router.dart` `/splash`, `/login`, `/unreachable` usano `pageBuilder: (context, state) => entryPage(context, state, const …())`.

- [ ] **Step 6: aggiornamento obbligatorio.** In `update_gate.dart` il blocco `if (blocked) Positioned.fill(child: MandatoryUpdateScreen(...))` diventa sempre presente:

```dart
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: WfMotion.of(context).duration(WfMotion.medium),
            child: blocked
                ? MandatoryUpdateScreen(
                    key: const ValueKey('mandatory-update'),
                    update: update,
                    onInstall: () => unawaited(controller.install()),
                    onRetry: controller.retry,
                  )
                : const SizedBox.shrink(key: ValueKey('no-update')),
          ),
        ),
```

  e il banner (`if (showBanner) Positioned(...)`) diventa un `Positioned(left: 24, right: 24, bottom: 24, child: Center(child: AnimatedSwitcher(duration: …medium, transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: WfMotion.emphasized)), child: child)), child: showBanner ? UpdateBanner(key: ValueKey(release.version.toString()), …) : const SizedBox.shrink())))` (sale dal basso: il banner è in basso; lo spec §11.4 va corretto nel Task 8). Controlla i test di `update_gate_test.dart`: dove verificano che la schermata o il banner **non** ci siano più, serve `pumpAndSettle` (dissolvenza di `fast` con le animazioni ridotte).

- [ ] **Step 7: verifica e commit**

Run: `flutter test test/features test/app`, poi `flutter analyze` e `flutter test`.
Expected: PASS, tutto verde.

```bash
git add lib/features/startup lib/features/auth/login_screen.dart lib/app/page_transitions.dart lib/app/router.dart lib/features/update/update_gate.dart test
git commit -m "feat: animate splash, login and entry screens"
```

---

### Task 7: menu, avvisi, invito, bordo delle card

**Files:**
- Create: `lib/ui/wf_menus.dart`
- Modify: `lib/app/app_shell.dart`, `lib/features/watch_party/watch_party_button.dart`, `lib/app/theme.dart`, `lib/features/watch_party/watch_party_invites.dart`
- Test: `test/ui/wf_menus_test.dart`, `test/app/theme_test.dart` (aggiunta), test dell'invito (aggiunta)

- [ ] **Step 1: scrivi i test che falliscono**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/wf_menus.dart';

void main() {
  testWidgets('menu: durata e curva dai token', (tester) async {
    late AnimationStyle full;
    late AnimationStyle reduced;
    await tester.pumpWidget(WfMotionScope(
      motion: const WfMotion(MotionLevel.full),
      child: Builder(builder: (context) {
        full = wfPopUpAnimation(context);
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(WfMotionScope(
      motion: const WfMotion(MotionLevel.reduced),
      child: Builder(builder: (context) {
        reduced = wfPopUpAnimation(context);
        return const SizedBox();
      }),
    ));
    expect(full.duration, WfMotion.medium);
    expect(full.curve, WfMotion.emphasized);
    expect(full.reverseDuration, WfMotion.fast);
    expect(reduced.duration, WfMotion.fast);
  });
}
```

  In `test/app/theme_test.dart`: `buildWonderflixTheme().snackBarTheme.behavior == SnackBarBehavior.floating` e `backgroundColor == WfColors.surfaceHigh`. Nel test dell'invito (cerca `watch-party-invite` in `test/`): con animazioni complete la card entra con uno `SlideTransition` (trovato come antenato di `Key('watch-party-invite')`) e dopo "Chiudi" sparisce a dissolvenza finita (`pumpAndSettle`).

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/ui/wf_menus_test.dart test/app/theme_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa.**
  - `lib/ui/wf_menus.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../app/motion.dart';

/// Animazione dei menu a comparsa dai token (spec C §11.4). Va passata a
/// ogni `PopupMenuButton` (non esiste nel tema).
AnimationStyle wfPopUpAnimation(BuildContext context) {
  final motion = WfMotion.of(context);
  return AnimationStyle(
    duration: motion.duration(WfMotion.medium),
    curve: WfMotion.emphasized,
    reverseDuration: WfMotion.fast,
  );
}
```

  - `popUpAnimationStyle: wfPopUpAnimation(context)` sui `PopupMenuButton` di `app_shell.dart` (menu utente) e dei due di `watch_party_button.dart`. `party_badge.dart` (player) no.
  - `theme.dart`, in `base.copyWith(...)`:

```dart
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: WfColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: WfColors.cream),
      actionTextColor: WfColors.gold,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: WfColors.border),
      ),
    ),
```

  - `watch_party_invites.dart`: il `build` restituisce un `AnimatedSwitcher(duration: WfMotion.of(context).duration(WfMotion.medium), transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: WfMotion.emphasized)), child: child)), child: group == null ? const SizedBox.shrink(key: ValueKey('no-invite')) : KeyedSubtree(key: ValueKey(group.id), child: Material(key: const Key('watch-party-invite'), …come oggi…)))`. I test esistenti dell'invito che verificano la sparizione subito dopo "Chiudi" o dopo 10 s devono fare `pumpAndSettle` (dissolvenza `fast` con le animazioni ridotte): adattali spiegando.

- [ ] **Step 4: verifica e commit**

Run: `flutter analyze` e `flutter test`.
Expected: tutto verde.

```bash
git add lib/ui/wf_menus.dart lib/app/app_shell.dart lib/features/watch_party lib/app/theme.dart test
git commit -m "feat: token menus, floating snackbars and sliding invite card"
```

---

### Task 8: spec e verifica finale

**Files:**
- Modify: `docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md`

- [ ] **Step 1: spec.**
  - §7.1: l'anteprima si disegna nell'overlay principale; il timer della sosta e la regola "subito dopo un'altra anteprima" (entro `previewChainWindow`, 400 ms); si chiude anche quando la pagina della card non è più in cima e quando la finestra non è attiva.
  - §7.3: per gli episodi niente cuore; "Riproduci" chiude l'anteprima e avvia; "Dettagli" vola dallo sfondo dell'anteprima (sorgente `<card>.preview`); tornando indietro la scheda rientra con la sola dissolvenza (l'anteprima non c'è più).
  - §7.4: i campi delle liste diventano `PrimaryImageAspectRatio,Genres`; l'anteprima usa lo sfondo a 1920 px, lo stesso della testata.
  - §11.3: il login usa il `TabBarView` esistente (scorre già) tra Password e Quick Connect.
  - §11.4: nessun dialogo nell'app, quindi nessun `showWfDialog`; menu con `wfPopUpAnimation` sui tre menu fuori dal player; il banner d'aggiornamento **sale dal basso** (è in basso).
- [ ] **Step 2:** `flutter gen-l10n`, `flutter analyze`, `flutter test`: tutto verde. Annota il numero dei test (erano 832).
- [ ] **Step 3:** cerca durate e curve scritte a mano: `grep -rn "Duration(milliseconds\|Curves\." lib --include=*.dart | grep -v "lib/features/player"`: devono restare solo token e costanti nominate e commentate. Segnala cosa resta.
- [ ] **Step 4:** build: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` e `flutter build windows --debug` (se l'app dell'utente è aperta e dà `LNK1168`/`LNK1104`, **non** chiuderla: segnalalo).
- [ ] **Step 5:** commit dello spec (e di eventuali correzioni):

```bash
git add docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md
git commit -m "docs: align spec C with the card preview and finishing touches"
```

## Prova manuale (con l'utente, sul server reale)

Build di release: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` e `flutter build windows --release --dart-define-from-file=config/wonderflix.json`; l'exe lo avvia l'utente.

- **Anteprima:**
  - si apre dopo mezzo secondo sulle locandine di Home, "Simili", Catalogo, La mia lista, Ricerca, Persona, e sulle card di "Continua a guardare" e "Prossimi episodi" (episodio: niente cuore); mai sulle card degli episodi nella scheda della serie;
  - sta sopra la barra, dentro la finestra vicino ai bordi;
  - passando da una card all'altra si apre subito; una sola aperta;
  - si chiude uscendo con il mouse, con la rotella, con Esc, cambiando finestra (Alt+Tab);
  - Riproduci / Riprendi avvia (e l'anteprima sparisce); cuore e spunta; Dettagli e clic sull'immagine: volo dallo sfondo dell'anteprima alla testata, senza rettangoli strani; indietro;
  - con un'anteprima aperta sulla Home il carosello si ferma.
- **Griglie:** Catalogo (anche scroll infinito e cambio di filtro), La mia lista, Ricerca, Persona: le card entrano scaglionate solo quando arrivano; togliere un preferito da La mia lista non fa rientrare nulla.
- **Impostazioni:** le sezioni entrano scaglionate.
- **Avvio e login:** logo dello splash con il riflesso oro (se l'avvio è rapido può non vedersi tutto); login che sale; "Server non raggiungibile" in dissolvenza.
- **Menu e avvisi:** menu utente e watch party; snackbar flottanti (per esempio un errore di rete su "La mia lista"); card d'invito che entra da destra; banner d'aggiornamento (se capita) che sale dal basso.
- **Animazioni ridotte:** anteprima in sola dissolvenza, nessuna entrata, splash fermo.
- **Regressioni:** volo Hero dalle card, barra e titolo nella barra, carosello, player, watch party, Discord.

## Dopo la prova (fuori dai task)

Con l'ok dell'utente: merge fast-forward su `main`, push, rimozione di worktree e branch; poi **release 0.3.0 non obbligatoria** secondo `docs/RELEASING.md` (versione in `pubspec.yaml`, commit `chore: release 0.3.0`, tag solo con l'ok dell'utente, note in italiano scritte nella bozza da `git log v0.2.0..v0.3.0`, **senza** marcatore `min-version`; la pubblicazione la fa l'utente).
