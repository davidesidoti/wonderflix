# WonderFlix — Piano 6b: Home, scheda del titolo, caricamento

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** seconda parte dello Spec C (rinnovo grafico):
- **caricamento:** un'unica onda oro-crema attraversa tutti gli scheletri della pagina (`WfShimmer`); scheletri che imitano la pagina vera per scheda, episodi, catalogo, La mia lista, ricerca e persona; dissolvenza incrociata scheletro → contenuto;
- **entrate scaglionate** senza timer (`StaggerGroup`/`StaggerItem`): righe della Home (una volta per sessione) con le card che "volano" dentro; testata e righe della scheda dopo il volo Hero; episodi al cambio di stagione;
- **carosello "In evidenza" cinematografico:** dissolvenza incrociata, Ken Burns, testi scaglionati, puntino che si riempie in 8 s, pausa con il mouse sopra;
- **scheda del titolo:** parallasse dello sfondo (metà velocità, zoom fino a 1,08, scurimento), testo che sfuma salendo, **titolo e "Riproduci" nella barra** quando la testata esce;
- **stagioni:** indicatore oro che scorre tra le stagioni (stesso widget della barra).

**Decisioni prese con l'utente (2026-09-30):**
1. Titolo nella barra con un meccanismo **per istanza di pagina** (come lo stato "scorsa" del 6a), non un provider globale: tornando indietro la barra ritrova il titolo della pagina in cima. Lo spec §9.2 va aggiornato (Task 9).
2. Entrata delle righe della Home **una sola volta per sessione**; le schede la rifanno a ogni apertura.
3. Il titolo compare nella barra dopo **380 px** di scroll (costante da ritoccare nella prova).
4. Carosello con un `AnimationController` di 8 s al posto di `Timer.periodic` (niente timer; la pagina coperta ferma i ticker da sola).
5. Pulizia delle durate rimaste a mano: frecce delle righe → `WfMotion.medium`, dissolvenza delle immagini → `WfMotion.fast`. Il bordo delle card (120 ms) resta al 6c.
6. Scheletri in questo piano; l'entrata scaglionata delle **griglie** resta al 6c.

**Architecture:**
- `lib/ui/shimmer.dart`: `WfShimmer` (un controller per pagina) e il pittore dei blocchi; `SkeletonBox` (in `states.dart`) dipinge il gradiente in coordinate di `WfShimmer`.
- `lib/ui/skeletons.dart`: scheletri delle pagine; `lib/ui/wf_switcher.dart`: dissolvenza scheletro → contenuto.
- `lib/ui/staggered_entrance.dart`: `staggerInterval` (funzione pura), `StaggerGroup`, `StaggerItem`, `EntranceEffect`.
- `lib/ui/sliding_underline.dart`: linea oro scorrevole, usata dalla barra e dalle stagioni.
- `lib/features/detail/header_parallax.dart`: `headerParallax` (funzione pura) e costanti della testata.
- `lib/app/app_shell.dart`: `ShellHeader`, `ShellHeaderPublisher`, titolo nella barra; `ShellPageFrame` pubblica anche il titolo.
- `lib/features/home/hero_carousel.dart`: riscritto; `carouselAutoplayProvider` (spento nei test salvo richiesta).

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18.

**Spec:** `docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md` (§8, §9, §10). **Piano precedente:** `…-06a-movimento-navigazione.md` (su `main`). **Worktree:** `.claude/worktrees/rinnovo-6b`, branch `feat/rinnovo-6b`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…". Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/rinnovo-6b`). Comandi git semplici, non composti con variabili, niente `git -C`.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde (a inizio piano: 772 test). Se `lib/l10n/gen` manca o è vecchio, esegui prima `flutter gen-l10n`.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione e fine riga:** non eseguire `dart format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`): non convertire interi file.
- **Icone:** solo `LucideIcons`. **Colori:** solo `WfColors` (anche con `withValues(alpha: …)`). **Durate e curve:** solo token di `WfMotion` o costanti nominate e commentate di questo piano. Il player non si tocca.
- **Widget test:** qualunque `Timer` rimasto aperto a fine test fa fallire il test. `pumpApp` monta `WfMotionScope` in modalità **ridotta** (default) e, da questo piano, il carosello **senza autoplay** (`carouselAutoplay: false`, default). Con `motion: MotionLevel.full` lo shimmer e il Ken Burns sono animazioni continue: in quei test usa `pump(durata)`, **mai** `pumpAndSettle` mentre sono visibili. Con le animazioni ridotte gli scheletri sono fermi.
- **Dissolvenza scheletro → contenuto:** dopo l'arrivo dei dati il vecchio figlio resta per `WfMotion.fast` (ridotte) o `medium`: un test che verifica che lo scheletro o l'indicatore non ci siano più deve fare `pumpAndSettle` (o `pump(WfMotion.medium)`) prima.
- **Router:** con go_router 18 dopo `push` la pagina in cima è `GoRouter.of(context).state.uri`.
- **Fake:** niente mocktail. `FakeLibraryApi`, `testItem`, `pageOf` in `test/support/library_fakes.dart`; `FakeSessionController`; `FakeWatchPartyDirectory`, `FakeSyncPlayApi`; `testUser`. Per tenere una schermata in caricamento: `itemProvider('m1').overrideWith((ref) => Completer<JellyfinItem>().future)` (vedi `test/features/detail/detail_hero_test.dart`).
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **Shimmer (ricetta ufficiale Flutter, "Create a shimmer loading effect"):** un antenato possiede il controller; ogni blocco dipinge lo stesso gradiente, spostato della propria posizione rispetto all'antenato (`localToGlobal(Offset.zero, ancestor: shimmerBox)`), con un `GradientTransform` che trasla il gradiente. Qui ogni blocco è un `CustomPainter` con `repaint:` il controller: si ridipinge senza ricostruire widget. `localToGlobal` in `paint` è ammesso (il layout è finito).
- **Pagina coperta:** le rotte sotto una rotta opaca sono fuori scena e i loro ticker sono spenti (`TickerMode`): un `AnimationController` del carosello si ferma da solo quando la Home è coperta e riparte quando torna in cima.
- **`Animation.drive(CurveTween(curve: Interval(a, b, curve: c)))`** crea un'animazione derivata senza `CurvedAnimation` da liberare.
- **`AnimatedSwitcher`**: con `layoutBuilder` predefinito usa uno `Stack` a dimensione libera; per le pagine intere serve `StackFit.expand` (vedi `WfSwitcher`).
- **Stato del 6a da riusare:**
  - `ShellPageFrame` (`lib/app/app_shell.dart`) avvolge ogni pagina della shell (da `_page()` in `page_transitions.dart`), ricorda se la pagina è scorsa e lo pubblica alla barra con `_publish()` quando la sua rotta è in cima (con rinvio a fine fotogramma se si è in costruzione);
  - `DetailBackdrop` (`lib/features/detail/detail_backdrop.dart`) è lo sfondo della scheda come livello dietro al contenuto, dentro un `Positioned(top: 0, height: detailHeaderHeight)` in `ItemDetailScreen`; oggi trasla di `-offset`;
  - `_NavBar` in `app_shell.dart` misura la voce attiva con `GlobalKey` + `addPostFrameCallback` e anima una linea (`Key('nav-indicator')`, `KeyedSubtree(Key('nav-<route>'))`).
- **Testata e righe sotto:** con la parallasse lo sfondo sale più lento del contenuto, quindi sporgerebbe sotto la testata (dietro al cast). Va ritagliato all'altezza visibile della testata: `560 − offset`.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `lib/ui/shimmer.dart` | crea | `WfShimmer`, pittore dei blocchi, `shimmerShaderRect` |
| `lib/ui/states.dart` | modifica | `SkeletonBox` con onda se sotto `WfShimmer` |
| `lib/ui/wf_switcher.dart` | crea | dissolvenza scheletro → contenuto |
| `lib/ui/skeletons.dart` | crea | scheletri di scheda, righe, episodi, griglia, ricerca, persona |
| `lib/ui/staggered_entrance.dart` | crea | entrate scaglionate |
| `lib/ui/sliding_underline.dart` | crea | linea oro scorrevole |
| `lib/ui/media_row.dart` | modifica | card che volano dentro (`entranceDelay`), durata delle frecce |
| `lib/ui/wf_image.dart` | modifica | dissolvenza delle immagini dai token |
| `lib/features/home/home_screen.dart` | modifica | entrata una volta per sessione, scheletro con onda, switcher |
| `lib/features/home/hero_carousel.dart` | riscrivi | carosello cinematografico |
| `lib/features/detail/header_parallax.dart` | crea | parallasse, soglia del titolo |
| `lib/features/detail/detail_backdrop.dart` | modifica | parallasse, ritaglio, scurimento |
| `lib/features/detail/detail_header.dart` | modifica | testo che sfuma, entrata scaglionata |
| `lib/features/detail/item_detail_screen.dart` | modifica | scheletri, switcher, ritardo dell'entrata |
| `lib/features/detail/movie_detail_view.dart`, `series_detail_view.dart` | modifica | entrata, titolo nella barra, stagioni, episodi |
| `lib/features/detail/detail_rows.dart` | modifica | righe con entrata |
| `lib/features/catalog/catalog_screen.dart`, `mylist/my_list_screen.dart`, `search/search_screen.dart`, `person/person_screen.dart` | modifica | scheletri + switcher |
| `lib/app/app_shell.dart` | modifica | `ShellHeader`, `ShellHeaderPublisher`, titolo nella barra, `_NavBar` su `SlidingUnderline` |
| `test/support/pump_app.dart` | modifica | `carouselAutoplay` |
| `docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md` | modifica | §8.1, §8.2, §9.2 allineati alle decisioni |

## Gruppi per i subagent

- **Gruppo A (Task 1–3):** onda, scheletri, entrate scaglionate.
- **Gruppo B (Task 4–5):** Home (righe e carosello).
- **Gruppo C (Task 6–8):** scheda (stagioni, parallasse ed entrata, titolo nella barra).
- **Gruppo D (Task 9–10):** pulizia, spec, verifica finale.

---

### Task 1: onda sincronizzata (`WfShimmer`)

**Files:**
- Create: `lib/ui/shimmer.dart`
- Modify: `lib/ui/states.dart`
- Test: `test/ui/shimmer_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/shimmer.dart';
import 'package:wonderflix/ui/states.dart';

void main() {
  test('il gradiente copre tutta l\'onda, spostato del blocco', () {
    expect(shimmerShaderRect(const Size(800, 600), const Offset(120, 40)),
        const Rect.fromLTWH(-120, -40, 800, 600));
  });

  Widget page(MotionLevel level) => Directionality(
        textDirection: TextDirection.ltr,
        child: WfMotionScope(
          motion: WfMotion(level),
          child: const WfShimmer(
            child: Column(children: [
              SkeletonBox(width: 200, height: 40),
              SizedBox(height: 20),
              SkeletonBox(width: 300, height: 60),
            ]),
          ),
        ),
      );

  testWidgets('completa: un solo controller anima tutti i blocchi',
      (tester) async {
    await tester.pumpWidget(page(MotionLevel.full));
    expect(find.byKey(shimmerPaintKey), findsNWidgets(2));
    expect(SchedulerBinding.instance.transientCallbackCount, 1);
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    // Via l'albero: il controller si ferma.
    await tester.pumpWidget(const SizedBox());
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('ridotta: blocchi fermi, nessuna animazione', (tester) async {
    await tester.pumpWidget(page(MotionLevel.reduced));
    expect(find.byKey(shimmerPaintKey), findsNothing);
    expect(find.byType(SkeletonBox), findsNWidgets(2));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('SkeletonBox senza WfShimmer: fermo come prima', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: WfMotionScope(
        motion: WfMotion(MotionLevel.full),
        child: Center(child: SkeletonBox(width: 100, height: 20)),
      ),
    ));
    expect(find.byKey(shimmerPaintKey), findsNothing);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/shimmer_test.dart`
Expected: FAIL (`shimmer.dart` non esiste).

- [ ] **Step 3: implementa** (`lib/ui/shimmer.dart`)

```dart
import 'package:flutter/widgets.dart';

import '../app/motion.dart';
import '../app/theme.dart';

/// Giro completo dell'onda sugli scheletri (spec C §10.1).
const shimmerPeriod = Duration(milliseconds: 1800);

/// Chiave del pittore dell'onda (per i test).
const shimmerPaintKey = ValueKey<String>('wf-shimmer-paint');

/// Rettangolo del gradiente per un blocco a [offset] dentro un'onda grande
/// [shimmerSize]: lo stesso gradiente per tutti, spostato, così si vede
/// un'unica onda.
Rect shimmerShaderRect(Size shimmerSize, Offset offset) => Rect.fromLTWH(
    -offset.dx, -offset.dy, shimmerSize.width, shimmerSize.height);

/// Onda oro-crema diagonale che attraversa tutti gli [SkeletonBox] sotto di
/// sé (spec C §10.1). Un solo controller per pagina; con le animazioni
/// ridotte nessun controller e blocchi fermi.
class WfShimmer extends StatefulWidget {
  const WfShimmer({super.key, required this.child});

  final Widget child;

  /// Onda più vicina a [context], se c'è e si muove.
  static WfShimmerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WfShimmerScope>();

  @override
  State<WfShimmer> createState() => _WfShimmerState();
}

class _WfShimmerState extends State<WfShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = WfMotion.of(context).isReduced;
    if (!reduced && _controller == null) {
      _controller = AnimationController(vsync: this, duration: shimmerPeriod)
        ..repeat();
    } else if (reduced && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  RenderBox? _box() => context.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // RepaintBoundary: l'onda ridipinge solo lo scheletro.
    final child = RepaintBoundary(child: widget.child);
    if (controller == null) return child;
    return WfShimmerScope(animation: controller, box: _box, child: child);
  }
}

class WfShimmerScope extends InheritedWidget {
  const WfShimmerScope(
      {super.key, required this.animation, required this.box, required super.child});

  final Animation<double> animation;

  /// Area dell'onda (per la posizione dei blocchi).
  final RenderBox? Function() box;

  @override
  bool updateShouldNotify(WfShimmerScope oldWidget) =>
      oldWidget.animation != animation;
}

/// Dipinge un blocco dello scheletro con l'onda.
class ShimmerBlockPainter extends CustomPainter {
  ShimmerBlockPainter({
    required this.animation,
    required this.shimmerBox,
    required this.selfBox,
    required this.radius,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final RenderBox? Function() shimmerBox;
  final RenderBox? Function() selfBox;
  final double radius;

  static final _colors = [
    WfColors.gold.withValues(alpha: 0),
    WfColors.gold.withValues(alpha: 0.10),
    WfColors.cream.withValues(alpha: 0.10),
    WfColors.gold.withValues(alpha: 0.10),
    WfColors.gold.withValues(alpha: 0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()..color = WfColors.surfaceHigh);
    final area = shimmerBox();
    final self = selfBox();
    if (area == null || self == null || !area.hasSize || !self.attached) return;
    final offset = self.localToGlobal(Offset.zero, ancestor: area);
    final gradient = LinearGradient(
      begin: const Alignment(-1, -0.3),
      end: const Alignment(1, 0.3),
      colors: _colors,
      stops: const [0.35, 0.47, 0.5, 0.53, 0.65],
      transform: _Slide(animation.value),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader =
            gradient.createShader(shimmerShaderRect(area.size, offset)),
    );
  }

  @override
  bool shouldRepaint(ShimmerBlockPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.animation != animation;
}

/// Sposta il gradiente da una larghezza a sinistra a una a destra.
class _Slide extends GradientTransform {
  const _Slide(this.value);

  final double value;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (value * 2 - 1), 0, 0);
}
```

- [ ] **Step 4: `SkeletonBox`.** In `lib/ui/states.dart` (import `shimmer.dart`), `SkeletonBox` diventa `StatelessWidget` che sceglie:

```dart
  @override
  Widget build(BuildContext context) {
    final shimmer = WfShimmer.maybeOf(context);
    if (shimmer == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: WfColors.surfaceHigh,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: Builder(
        builder: (context) => CustomPaint(
          key: shimmerPaintKey,
          painter: ShimmerBlockPainter(
            animation: shimmer.animation,
            shimmerBox: shimmer.box,
            selfBox: () => context.findRenderObject() as RenderBox?,
            radius: radius,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
```

  Aggiorna il commento della classe: "Blocco dello scheletro; sotto un [WfShimmer] lo attraversa l'onda."

- [ ] **Step 5: verifica**

Run: `flutter test test/ui/shimmer_test.dart test/ui/states_test.dart`
Expected: PASS. Poi `flutter analyze` e `flutter test`: tutto verde.

- [ ] **Step 6: commit**

```bash
git add lib/ui/shimmer.dart lib/ui/states.dart test/ui/shimmer_test.dart
git commit -m "feat: add synced gold shimmer for skeletons"
```

---

### Task 2: scheletri delle pagine e dissolvenza verso il contenuto

**Files:**
- Create: `lib/ui/wf_switcher.dart`, `lib/ui/skeletons.dart`
- Modify: `lib/features/home/home_screen.dart`, `lib/features/detail/item_detail_screen.dart`, `lib/features/detail/series_detail_view.dart`, `lib/features/catalog/catalog_screen.dart`, `lib/features/mylist/my_list_screen.dart`, `lib/features/search/search_screen.dart`, `lib/features/person/person_screen.dart`
- Test: `test/ui/skeletons_test.dart`, più adattamenti di `test/features/detail/detail_hero_test.dart`

- [ ] **Step 1: scrivi il test che fallisce** (`test/ui/skeletons_test.dart`)

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/detail_providers.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';
import 'package:wonderflix/ui/shimmer.dart';
import 'package:wonderflix/ui/skeletons.dart';
import 'package:wonderflix/ui/states.dart';
import 'package:wonderflix/ui/wf_switcher.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final signedIn = sessionControllerProvider
      .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser)));

  testWidgets('scheda in caricamento: scheletro con l\'onda, niente spinner',
      (tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
      overrides: [
        itemProvider('m1').overrideWith((ref) => Completer<JellyfinItem>().future),
      ],
      motion: MotionLevel.full,
    );
    expect(find.byType(DetailSkeleton), findsOneWidget);
    expect(find.byType(WfShimmer), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('La mia lista in caricamento: griglia di scheletri',
      (tester) async {
    final api = FakeLibraryApi()..favoritesGate = Completer<void>();
    await pumpApp(tester, const Scaffold(body: MyListScreen()),
        overrides: [libraryApiProvider.overrideWithValue(api), signedIn]);
    expect(find.byType(PosterGridSkeleton), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
  });

  testWidgets('WfSwitcher: dissolvenza verso il contenuto', (tester) async {
    Widget tree(bool loaded) => MaterialApp(
          home: WfMotionScope(
            motion: const WfMotion(MotionLevel.full),
            child: WfSwitcher(
              expand: true,
              child: loaded
                  ? const Text('contenuto', key: ValueKey('dati'))
                  : const PosterGridSkeleton(key: ValueKey('attesa')),
            ),
          ),
        );
    await tester.pumpWidget(tree(false));
    await tester.pumpWidget(tree(true));
    await tester.pump(const Duration(milliseconds: 100));
    // A metà: ci sono tutti e due.
    expect(find.text('contenuto'), findsOneWidget);
    expect(find.byType(PosterGridSkeleton), findsOneWidget);
    await tester.pump(WfMotion.medium);
    expect(find.byType(PosterGridSkeleton), findsNothing);
  });
}
```

  `FakeLibraryApi` oggi non ha un modo per tenere in sospeso i preferiti: aggiungi in `test/support/library_fakes.dart` un campo `Completer<void>? favoritesGate;` e in cima al metodo che restituisce i preferiti (quello usato da `favoritesProvider`; cercalo nel fake) `await favoritesGate?.future;`. Se il metodo non è `async`, rendilo tale senza cambiare il comportamento.

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/skeletons_test.dart`
Expected: FAIL (file inesistenti).

- [ ] **Step 3: `WfSwitcher`** (`lib/ui/wf_switcher.dart`)

```dart
import 'package:flutter/widgets.dart';

import '../app/motion.dart';

/// Dissolvenza incrociata tra scheletro e contenuto (spec C §10.3). Il
/// [child] deve avere una chiave diversa per ogni stato. Con [expand] il
/// contenuto occupa tutto lo spazio (pagine intere); senza, prende la sua
/// altezza (sezioni dentro una lista).
class WfSwitcher extends StatelessWidget {
  const WfSwitcher({super.key, required this.child, this.expand = false});

  final Widget child;
  final bool expand;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: WfMotion.of(context).duration(WfMotion.medium),
        switchInCurve: WfMotion.standard,
        switchOutCurve: WfMotion.standard,
        layoutBuilder: (current, previous) => Stack(
          fit: expand ? StackFit.expand : StackFit.loose,
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: child,
      );
}
```

- [ ] **Step 4: scheletri** (`lib/ui/skeletons.dart`)

```dart
import 'package:flutter/widgets.dart';

import 'shimmer.dart';
import 'states.dart';

/// Riga di locandine (cast, "Simili") sotto la testata della scheda.
class DetailRowsSkeleton extends StatelessWidget {
  const DetailRowsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var row = 0; row < 2; row++) ...[
              const SkeletonBox(width: 200, height: 22),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: Row(children: [
                  for (var i = 0; i < 6; i++) ...[
                    const SkeletonBox(width: 130, height: 195),
                    const SizedBox(width: 16),
                  ],
                ]),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      );
}

/// Scheda del titolo in caricamento senza volo Hero: testata e righe.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key, required this.headerHeight});

  final double headerHeight;

  @override
  Widget build(BuildContext context) => WfShimmer(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: headerHeight,
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(32, 0, 32, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 420, height: 90),
                      SizedBox(height: 16),
                      SkeletonBox(width: 260, height: 14),
                      SizedBox(height: 12),
                      SkeletonBox(width: 560, height: 14),
                      SizedBox(height: 8),
                      SkeletonBox(width: 480, height: 14),
                      SizedBox(height: 20),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        SkeletonBox(width: 150, height: 44),
                        SizedBox(width: 12),
                        SkeletonBox(width: 150, height: 44),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
            const DetailRowsSkeleton(),
          ],
        ),
      );
}

/// Elenco degli episodi di una stagione.
class EpisodeListSkeleton extends StatelessWidget {
  const EpisodeListSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) => WfShimmer(
        child: Column(children: [
          for (var i = 0; i < count; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 200, height: 112, radius: 5),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 240, height: 14),
                      SizedBox(height: 8),
                      SkeletonBox(width: 120, height: 12),
                      SizedBox(height: 10),
                      SkeletonBox(width: 420, height: 12),
                    ],
                  ),
                ],
              ),
            ),
        ]),
      );
}

/// Griglia di locandine (Catalogo, La mia lista, filmografia): stessa
/// griglia delle pagine vere.
class PosterGridSkeleton extends StatelessWidget {
  const PosterGridSkeleton({super.key, this.count = 12, this.shrinkWrap = false});

  final int count;

  /// `true` dentro un'altra lista (filmografia della persona).
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) => WfShimmer(
        child: GridView.builder(
          shrinkWrap: shrinkWrap,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 24,
            crossAxisSpacing: 16,
            childAspectRatio: 0.55,
          ),
          itemCount: count,
          itemBuilder: (context, i) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SkeletonBox()),
              SizedBox(height: 8),
              SkeletonBox(width: 110, height: 12),
              SizedBox(height: 6),
              SkeletonBox(width: 40, height: 10),
            ],
          ),
        ),
      );
}

/// Risultati della ricerca: una sezione di locandine.
class SearchResultsSkeleton extends StatelessWidget {
  const SearchResultsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const WfShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 140, height: 24),
            SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 24,
              children: [
                for (var i = 0; i < 6; i++)
                  SkeletonBox(width: 150, height: 225),
              ],
            ),
          ],
        ),
      );
}

/// Pagina della persona senza volo Hero: foto, nome, biografia.
class PersonSkeleton extends StatelessWidget {
  const PersonSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const WfShimmer(
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 32, 32, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 200, height: 300, radius: 8),
              SizedBox(width: 32),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 320, height: 44),
                  SizedBox(height: 16),
                  SkeletonBox(width: 520, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 480, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 500, height: 14),
                ],
              ),
            ],
          ),
        ),
      );
}
```

(`SkeletonBox()` senza misure dentro `Expanded` riempie la cella: `SizedBox(width: null, height: null)` con `SizedBox.expand` prende i vincoli della cella. Se l'analyzer o un test segnalano vincoli infiniti in qualche uso, correggi con misure esplicite e segnalalo.)

- [ ] **Step 5: uso nelle schermate** (sempre con una chiave per stato nel figlio del `WfSwitcher`):
  - **Home** (`home_screen.dart`): `_HomeSkeleton` diventa un `WfShimmer` attorno alla `ListView` di oggi; `home.when(...)` è avvolto in `WfSwitcher(expand: true, child: KeyedSubtree(key: ValueKey(<'loading'|'error'|'empty'|'data'>), child: …))`.
  - **Scheda** (`item_detail_screen.dart`, import `../../ui/skeletons.dart`, `../../ui/wf_switcher.dart`):
    - caricamento **senza** `launch`: `DetailSkeleton(headerHeight: detailHeaderHeight)`;
    - caricamento **con** `launch`: la `ListView` di oggi con `SizedBox(height: detailHeaderHeight)` e, al posto del `Padding(LoadingView)`, `const WfShimmer(child: DetailRowsSkeleton())`;
    - il `content` è avvolto in `WfSwitcher(expand: true, child: KeyedSubtree(key: ValueKey(<stato>), child: content))`. Attenzione: il `SmoothScrollController` non può stare su due `ListView` insieme; durante la dissolvenza lo scheletro con `launch` e la vista dei dati esisterebbero entrambi. Soluzione: la `ListView` di caricamento **non** usa `_scroll` (nessun controller: durante il caricamento non si scorre, `physics: NeverScrollableScrollPhysics()`), e `DetailBackdrop` legge l'offset solo se `controller.hasClients` (già così).
  - **Episodi** (`series_detail_view.dart`, `_EpisodeList`): caricamento → `const EpisodeListSkeleton()`; caricamento delle stagioni → `const EpisodeListSkeleton(count: 2)`; `WfSwitcher` (senza `expand`) attorno al `when`.
  - **Catalogo** (`catalog_screen.dart`): `if (state.loading) return const LoadingView();` (lista vuota) → `const PosterGridSkeleton()`; `WfSwitcher(expand: true)` attorno al risultato di `_body`. Il `LoadingView` in fondo alla griglia (pagina successiva) resta.
  - **La mia lista**: `loading: () => const PosterGridSkeleton()` con un `Padding(top: 32 + 40 + 20)` che lascia lo spazio del titolo (o uno `SkeletonBox` per il titolo sopra la griglia in una `Column`); `WfSwitcher(expand: true)`.
  - **Ricerca**: `if (results == null) return const SearchResultsSkeleton();`, `WfSwitcher` (senza `expand`) attorno a `_results`.
  - **Persona**: caricamento senza `launch` → `const PersonSkeleton()`; filmografia in caricamento (`films == null` o `films.when(loading: …)`) → `SliverToBoxAdapter(child: PosterGridSkeleton(count: 6, shrinkWrap: true))`.

- [ ] **Step 6: test esistenti.** In `test/features/detail/detail_hero_test.dart` le attese su `LoadingView` durante il caricamento diventano attese sugli scheletri (`DetailRowsSkeleton` con `launch`, `DetailSkeleton` senza); dove si verifica che il caricamento **non** ci sia più, fai prima `await tester.pumpAndSettle();` (la dissolvenza lascia il vecchio figlio per `WfMotion.fast`). Il test che conta un solo `Scrollable` collegato al controller resta valido: la `ListView` di caricamento non usa più il controller. Adatta allo stesso modo eventuali altri test che cercavano `LoadingView` nelle schermate toccate (`grep -rn "LoadingView" test`), senza indebolire cosa verificano.

- [ ] **Step 7: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 8: commit**

```bash
git add lib/ui/wf_switcher.dart lib/ui/skeletons.dart lib/features test/ui/skeletons_test.dart test/support/library_fakes.dart test/features
git commit -m "feat: add page skeletons and crossfade to content"
```

---

### Task 3: entrate scaglionate senza timer

**Files:**
- Create: `lib/ui/staggered_entrance.dart`
- Test: `test/ui/staggered_entrance_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

void main() {
  test('staggerInterval: ritardo, passo e durata in frazioni del totale', () {
    const delay = Duration(milliseconds: 100);
    const step = Duration(milliseconds: 50);
    const item = Duration(milliseconds: 300);
    final total = staggerTotal(count: 3, delay: delay, stagger: step, item: item);
    expect(total, const Duration(milliseconds: 500));
    final first = staggerInterval(index: 0, delay: delay, stagger: step, item: item, total: total);
    expect(first.begin, closeTo(0.2, 1e-9));
    expect(first.end, closeTo(0.8, 1e-9));
    final last = staggerInterval(index: 2, delay: delay, stagger: step, item: item, total: total);
    expect(last.begin, closeTo(0.4, 1e-9));
    expect(last.end, closeTo(1.0, 1e-9));
  });

  Widget group(MotionLevel level, {bool play = true, VoidCallback? onPlayed}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: WfMotionScope(
          motion: WfMotion(level),
          child: StaggerGroup(
            count: 3,
            play: play,
            onPlayed: onPlayed,
            child: Column(children: [
              for (var i = 0; i < 4; i++)
                StaggerItem(index: i, child: Text('riga $i')),
            ]),
          ),
        ),
      );

  double opacityOf(WidgetTester tester, String text) {
    final fades = tester.widgetList<Opacity>(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)));
    return fades.isEmpty ? 1 : fades.first.opacity;
  }

  testWidgets('completa: entrano uno dopo l\'altro, poi tutti visibili',
      (tester) async {
    var played = 0;
    await tester.pumpWidget(group(MotionLevel.full, onPlayed: () => played++));
    expect(opacityOf(tester, 'riga 0'), 0);
    await tester.pump(WfMotion.stagger + const Duration(milliseconds: 100));
    expect(opacityOf(tester, 'riga 0'), greaterThan(opacityOf(tester, 'riga 2')));
    // Oltre `count`: nessuna entrata.
    expect(opacityOf(tester, 'riga 3'), 1);
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(opacityOf(tester, 'riga $i'), 1);
    }
    expect(played, 1);
  });

  testWidgets('ridotta o play spento: subito visibili', (tester) async {
    await tester.pumpWidget(group(MotionLevel.reduced));
    expect(opacityOf(tester, 'riga 0'), 1);
    await tester.pumpWidget(group(MotionLevel.full, play: false));
    expect(opacityOf(tester, 'riga 0'), 1);
  });

  testWidgets('StaggerItem senza gruppo: il solo figlio', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: StaggerItem(index: 0, child: Text('solo')),
    ));
    expect(opacityOf(tester, 'solo'), 1);
  });

  testWidgets('fly: parte da destra e più piccolo', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: WfMotionScope(
        motion: WfMotion(MotionLevel.full),
        child: StaggerGroup(
          count: 1,
          child: StaggerItem(
              index: 0, effect: EntranceEffect.fly, child: Text('card')),
        ),
      ),
    ));
    final transform = tester.widget<Transform>(find
        .ancestor(of: find.text('card'), matching: find.byType(Transform))
        .first);
    expect(transform.transform.getTranslation().x, greaterThan(0));
    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/staggered_entrance_test.dart`
Expected: FAIL (file inesistente).

- [ ] **Step 3: implementa** (`lib/ui/staggered_entrance.dart`)

```dart
import 'package:flutter/widgets.dart';

import '../app/motion.dart';

/// Come entra un elemento (spec C §8.2).
enum EntranceEffect {
  /// Sale di 20 px in dissolvenza (righe, testi).
  rise,

  /// Arriva da destra (40 px) crescendo da 0,85, con un leggero rimbalzo
  /// (card nelle righe).
  fly,
}

/// Durata totale di un'entrata di [count] elementi.
Duration staggerTotal({
  required int count,
  required Duration delay,
  required Duration stagger,
  required Duration item,
}) =>
    delay + stagger * (count > 0 ? count - 1 : 0) + item;

/// Frazioni della durata totale in cui entra l'elemento [index].
({double begin, double end}) staggerInterval({
  required int index,
  required Duration delay,
  required Duration stagger,
  required Duration item,
  required Duration total,
}) {
  final start = delay + stagger * index;
  final totalMs = total.inMicroseconds;
  return (
    begin: (start.inMicroseconds / totalMs).clamp(0.0, 1.0),
    end: ((start + item).inMicroseconds / totalMs).clamp(0.0, 1.0),
  );
}

/// Gruppo di elementi che entrano uno dopo l'altro, con un solo
/// `AnimationController` e nessun timer. Entrano i primi [count] figli
/// [StaggerItem]; gli altri compaiono subito. Con le animazioni ridotte o
/// [play] spento tutto è subito visibile.
class StaggerGroup extends StatefulWidget {
  const StaggerGroup({
    super.key,
    required this.count,
    required this.child,
    this.delay = Duration.zero,
    this.stagger = WfMotion.stagger,
    this.itemDuration = WfMotion.slow,
    this.play = true,
    this.onPlayed,
  });

  final int count;
  final Widget child;
  final Duration delay;
  final Duration stagger;
  final Duration itemDuration;
  final bool play;

  /// Chiamato una volta quando l'entrata parte (dopo il primo fotogramma).
  final VoidCallback? onPlayed;

  @override
  State<StaggerGroup> createState() => _StaggerGroupState();
}

class _StaggerGroupState extends State<StaggerGroup>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Duration _total;

  @override
  void initState() {
    super.initState();
    _total = staggerTotal(
      count: widget.count,
      delay: widget.delay,
      stagger: widget.stagger,
      item: widget.itemDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Si decide una volta sola, alla prima costruzione.
    if (_controller != null || !widget.play || widget.count == 0) return;
    if (WfMotion.of(context).isReduced) return;
    _controller = AnimationController(vsync: this, duration: _total)..forward();
    final onPlayed = widget.onPlayed;
    if (onPlayed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onPlayed());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StaggerScope(
        controller: _controller,
        group: widget,
        total: _total,
        child: widget.child,
      );
}

class _StaggerScope extends InheritedWidget {
  const _StaggerScope({
    required this.controller,
    required this.group,
    required this.total,
    required super.child,
  });

  final AnimationController? controller;
  final StaggerGroup group;
  final Duration total;

  @override
  bool updateShouldNotify(_StaggerScope oldWidget) =>
      oldWidget.controller != controller;
}

/// Elemento [index] di uno [StaggerGroup].
class StaggerItem extends StatelessWidget {
  const StaggerItem({
    super.key,
    required this.index,
    this.effect = EntranceEffect.rise,
    required this.child,
  });

  final int index;
  final EntranceEffect effect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_StaggerScope>();
    final controller = scope?.controller;
    if (scope == null || controller == null || index >= scope.group.count) {
      return child;
    }
    final interval = staggerInterval(
      index: index,
      delay: scope.group.delay,
      stagger: scope.group.stagger,
      item: scope.group.itemDuration,
      total: scope.total,
    );
    final curve = effect == EntranceEffect.fly
        ? WfMotion.bounce
        : WfMotion.emphasized;
    final progress = controller.drive(CurveTween(
        curve: Interval(interval.begin, interval.end, curve: curve)));
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final t = progress.value;
        final opacity = t.clamp(0.0, 1.0);
        final Matrix4 matrix = switch (effect) {
          EntranceEffect.rise => Matrix4.translationValues(0, 20 * (1 - t), 0),
          EntranceEffect.fly => Matrix4.translationValues(40 * (1 - t), 0, 0)
            ..scaleByDouble(0.85 + 0.15 * t, 0.85 + 0.15 * t, 1, 1),
        };
        return Opacity(
          opacity: opacity,
          child: Transform(
            transform: matrix,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    );
  }
}
```

(Se `Matrix4.scaleByDouble` non esiste nella versione di `vector_math` del progetto, usa `..scale(s, s, 1.0)` e segnalalo.)

- [ ] **Step 4: verifica**

Run: `flutter test test/ui/staggered_entrance_test.dart`, poi `flutter analyze` e `flutter test`
Expected: PASS, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/ui/staggered_entrance.dart test/ui/staggered_entrance_test.dart
git commit -m "feat: add timer-free staggered entrances"
```

---

### Task 4: entrata delle righe della Home e delle card

**Files:**
- Modify: `lib/ui/media_row.dart`, `lib/features/home/home_screen.dart`, `lib/features/detail/detail_rows.dart`
- Test: `test/features/home/home_entrance_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..resumeItems = [testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)]
      ..onItems = (query, start, limit) => query.kinds.contains(ItemKind.series)
          ? pageOf([testItem(id: 's1', name: 'The Bear', kind: ItemKind.series)])
          : pageOf([testItem(id: 'm1', name: 'Dune')]);
  });

  List<Override> overrides() => [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ];

  testWidgets('prima volta: le righe entrano scaglionate', (tester) async {
    await pumpApp(tester, const HomeScreen(),
        overrides: overrides(), motion: MotionLevel.full);
    await tester.pump();
    await tester.pump();
    expect(find.byType(StaggerGroup), findsWidgets);
    final rows = tester.widget<StaggerGroup>(find.byKey(const Key('home-rows')));
    expect(rows.play, isTrue);
    await tester.pump(const Duration(seconds: 2));
  });

  // La "sessione" è il ProviderScope: togliere e rimettere la Home nello
  // stesso scope è come cambiare voce nella barra e tornare.
  testWidgets('seconda volta nella stessa sessione: nessuna entrata',
      (tester) async {
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pumpApp(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, value, _) =>
            value ? const HomeScreen() : const SizedBox(),
      ),
      overrides: overrides(),
      motion: MotionLevel.full,
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    // Via e di nuovo (come cambiare voce e tornare alla Home).
    shown.value = false;
    await tester.pump();
    shown.value = true;
    await tester.pump();
    await tester.pump();
    final rows = tester.widget<StaggerGroup>(find.byKey(const Key('home-rows')));
    expect(rows.play, isFalse);
  });
}
```

  (In Riverpod 3 `Override` sta in `package:flutter_riverpod/misc.dart`, come in `test/support/pump_app.dart`.)

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/home/home_entrance_test.dart`
Expected: FAIL (`homeEntrancePlayedProvider`, chiave `home-rows` assenti).

- [ ] **Step 3: `MediaRow`.** In `lib/ui/media_row.dart` (import `staggered_entrance.dart`):
  - nuovo parametro:

```dart
  /// Se presente, le prime card visibili entrano "volando" da destra dopo
  /// questo ritardo (spec C §8.2). `null` = nessuna entrata.
  final Duration? entranceDelay;
```

  - costanti in cima al file:

```dart
/// Card di una riga che entrano volando (le prime visibili).
const rowEntranceCount = 8;

/// Passo tra una card e l'altra nell'entrata di una riga.
const rowEntranceStagger = Duration(milliseconds: 40);
```

  - il `ListView.separated` diventa il figlio di uno `StaggerGroup` quando `entranceDelay != null`, e ogni card è avvolta:

```dart
    Widget list = ListView.separated(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      itemCount: widget.itemCount,
      separatorBuilder: (context, index) => const SizedBox(width: 16),
      itemBuilder: (context, i) => StaggerItem(
        index: i,
        effect: EntranceEffect.fly,
        child: widget.itemBuilder(context, i),
      ),
    );
    final delay = widget.entranceDelay;
    if (delay != null) {
      list = StaggerGroup(
        count: rowEntranceCount,
        delay: delay,
        stagger: rowEntranceStagger,
        child: list,
      );
    }
```

  (senza gruppo, `StaggerItem` restituisce il solo figlio).

- [ ] **Step 4: Home.** In `home_screen.dart` (import `../../ui/staggered_entrance.dart`):

```dart
/// L'entrata delle righe della Home si vede una volta per sessione
/// (decisione 6b): tornando alla Home dalla barra non si ripete.
class HomeEntrancePlayed extends Notifier<bool> {
  @override
  bool build() => false;

  void markPlayed() => state = true;
}

final homeEntrancePlayedProvider =
    NotifierProvider<HomeEntrancePlayed, bool>(HomeEntrancePlayed.new);

/// Ritardo tra una riga e l'altra nell'entrata della Home.
const homeRowStagger = Duration(milliseconds: 80);
```

  - nello stato di `HomeScreen`: `late final bool _animate = !ref.read(homeEntrancePlayedProvider);`
  - la lista dei dati: i figli **righe** (non il carosello) sono avvolti in `StaggerItem(index: <n>)` con `n` crescente dalla prima riga, e la `ListView` è figlia di:

```dart
StaggerGroup(
  key: const Key('home-rows'),
  count: rowCount,
  stagger: homeRowStagger,
  play: _animate,
  onPlayed: () =>
      ref.read(homeEntrancePlayedProvider.notifier).markPlayed(),
  child: ListView(...),
)
```

  dove `rowCount` è il numero di righe presenti.
  - `_posterRow`/`_landscapeRow` ricevono l'indice della riga e passano a `MediaRow` `entranceDelay: _animate ? homeRowStagger * rowIndex : null`.

- [ ] **Step 5: righe della scheda.** In `detail_rows.dart`, `CastRow` e `SimilarRow` passano `entranceDelay: Duration.zero` a `MediaRow` quando le animazioni sono complete (`WfMotion.of(context).isReduced` ⇒ `null`); la card del cast entra così appena la riga compare (la riga "Simili" arriva dopo, con i suoi dati).

- [ ] **Step 6: verifica**

Run: `flutter test test/features/home/home_entrance_test.dart test/features/home/home_screen_test.dart test/ui/cards_test.dart`, poi `flutter analyze` e `flutter test`
Expected: PASS, tutto verde.

- [ ] **Step 7: commit**

```bash
git add lib/ui/media_row.dart lib/features/home/home_screen.dart lib/features/detail/detail_rows.dart test/features/home/home_entrance_test.dart
git commit -m "feat: stagger home rows once per session and fly cards in"
```

---

### Task 5: carosello cinematografico

**Files:**
- Modify (riscrivi la parte di stato e layout): `lib/features/home/hero_carousel.dart`
- Modify: `test/support/pump_app.dart`, `test/features/home/hero_carousel_test.dart`

- [ ] **Step 1: helper dei test.** In `test/support/pump_app.dart` (import `package:wonderflix/features/home/hero_carousel.dart`): `pumpApp` riceve `bool carouselAutoplay = false` e aggiunge **prima** di `...overrides` l'override `carouselAutoplayProvider.overrideWithValue(carouselAutoplay)`. (Nessun test deve sovrascrivere di nuovo `carouselAutoplayProvider` negli `overrides`: usa il parametro.)

- [ ] **Step 2: scrivi i test che falliscono.** In `test/features/home/hero_carousel_test.dart`:
  - `pumpHero` riceve `{bool autoplay = false, MotionLevel motion = MotionLevel.reduced}` e li passa a `pumpApp` (`carouselAutoplay: autoplay, motion: motion`);
  - il test `"non avanza se la Home è coperta da un'altra pagina"` usa `autoplay: true`; dopo `Navigator.of(context).pop()` sostituisci `await tester.pumpAndSettle();` con `await tester.pump(const Duration(milliseconds: 400));` (con l'autoplay l'animazione non si ferma mai);
  - aggiungi:

```dart
  testWidgets('autoplay: dopo 8 s passa alla diapositiva successiva',
      (tester) async {
    await pumpHero(tester, autoplay: true);
    expect(find.text('DUNE'), findsOneWidget);
    await tester.pump(HeroCarousel.interval);
    await tester.pump(WfMotion.fast);
    await tester.pump(WfMotion.fast);
    expect(find.text('ALIEN'), findsOneWidget);
    expect(find.text('DUNE'), findsNothing);
  });

  testWidgets('mouse sopra: il carosello si ferma', (tester) async {
    await pumpHero(tester, autoplay: true);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(HeroCarousel)));
    await tester.pump();
    await tester.pump(HeroCarousel.interval * 2);
    expect(find.text('DUNE'), findsOneWidget);
    await mouse.moveTo(const Offset(5, 895));
    await tester.pump();
    await tester.pump(HeroCarousel.interval);
    await tester.pump(WfMotion.fast);
    await tester.pump(WfMotion.fast);
    expect(find.text('ALIEN'), findsOneWidget);
  });

  testWidgets('puntino attivo: si riempie con il tempo', (tester) async {
    await pumpHero(tester, autoplay: true);
    double fill() => tester
        .widget<FractionallySizedBox>(find.byKey(const Key('hero-dot-fill')))
        .widthFactor!;
    expect(fill(), closeTo(0, 0.01));
    await tester.pump(HeroCarousel.interval ~/ 2);
    expect(fill(), closeTo(0.5, 0.02));
  });

  testWidgets('completa: Ken Burns sullo sfondo attivo', (tester) async {
    await pumpHero(tester, autoplay: true, motion: MotionLevel.full);
    Matrix4 kenBurns() => tester
        .widget<Transform>(find.byKey(const Key('hero-ken-burns')).first)
        .transform;
    final start = kenBurns().getMaxScaleOnAxis();
    await tester.pump(HeroCarousel.interval ~/ 2);
    expect(kenBurns().getMaxScaleOnAxis(), greaterThan(start));
  });
```

  (import `package:flutter/gestures.dart`, `package:wonderflix/app/motion.dart`.) Il test `'i puntini sono cliccabili'` e quello del riposizionamento restano: senza autoplay `pumpAndSettle` termina.

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/features/home/hero_carousel_test.dart`
Expected: FAIL (`carouselAutoplayProvider`, chiavi e comportamento assenti).

- [ ] **Step 4: implementa.** In `lib/features/home/hero_carousel.dart`:
  - costanti e provider in cima:

```dart
/// Autoplay del carosello; spento nei widget test (`pumpApp`) salvo
/// richiesta, perché un carosello che avanza da solo non si ferma mai.
final carouselAutoplayProvider = Provider<bool>((ref) => true);

/// Ken Burns: zoom e deriva laterale durante una diapositiva (spec C §8.1).
const kenBurnsScale = 0.1;
const kenBurnsDrift = 0.02;

/// Testi della diapositiva che entra: ritardo e passo (spec C §8.1).
const heroTextDelay = Duration(milliseconds: 250);
const heroTextStagger = Duration(milliseconds: 90);
```

  - `HeroCarousel` diventa `ConsumerStatefulWidget` (stessi campi, `interval` invariato, aggiungi `static const height = 460.0;`). Stato:

```dart
class _HeroCarouselState extends ConsumerState<HeroCarousel>
    with TickerProviderStateMixin {
  /// Tempo della diapositiva: riempie il puntino e guida il Ken Burns; a
  /// fine corsa passa alla successiva. Si ferma da solo quando la Home è
  /// coperta (ticker spenti) e con il mouse sopra.
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: HeroCarousel.interval)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _goTo(_index + 1);
        });

  /// Dissolvenza della diapositiva che entra (anche i testi).
  late final AnimationController _fade =
      AnimationController(vsync: this, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _previous != null) {
            setState(() => _previous = null);
          }
        });

  int _index = 0;
  int? _previous;
  double _previousProgress = 0;
  bool _hovered = false;

  bool get _autoplay =>
      ref.read(carouselAutoplayProvider) && widget.items.length > 1;

  @override
  void initState() {
    super.initState();
    if (_autoplay) _progress.forward();
  }

  @override
  void didUpdateWidget(HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length == widget.items.length) return;
    final last = widget.items.length - 1;
    if (last >= 0 && _index > last) _index = last;
    _previous = null;
    _progress.value = 0;
    if (_autoplay && !_hovered) _progress.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    final count = widget.items.length;
    if (count == 0) return;
    final next = page % count;
    if (next == _index) return;
    final motion = WfMotion.of(context);
    setState(() {
      _previous = _index;
      _previousProgress = _progress.value;
      _index = next;
    });
    _fade.duration = motion.duration(WfMotion.crossfade);
    _fade.forward(from: 0);
    _progress.value = 0;
    if (_autoplay && !_hovered) _progress.forward();
  }

  void _hover(bool hovered) {
    _hovered = hovered;
    if (hovered) {
      _progress.stop();
    } else if (_autoplay) {
      _progress.forward();
    }
  }
```

  - `build`:

```dart
  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final previous = _previous;
    return MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: SizedBox(
        height: HeroCarousel.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (previous != null && previous < widget.items.length)
              _HeroSlide(
                key: ValueKey('slide-${widget.items[previous].id}-out'),
                item: widget.items[previous],
                kenBurns: motion.isReduced
                    ? null
                    : AlwaysStoppedAnimation(_previousProgress),
                entrance: null,
              ),
            FadeTransition(
              opacity: _fade.drive(CurveTween(curve: WfMotion.standard)),
              child: _HeroSlide(
                key: ValueKey('slide-${widget.items[_index].id}'),
                item: widget.items[_index],
                kenBurns: motion.isReduced ? null : _progress,
                entrance: motion.isReduced ? null : _fade,
              ),
            ),
            Positioned(right: 32, bottom: 20, child: _dots()),
          ],
        ),
      ),
    );
  }

  Widget _dots() => Row(
        children: [
          for (var i = 0; i < widget.items.length; i++)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('hero-dot-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _goTo(i),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(3, 8, 3, 8),
                  child: AnimatedContainer(
                    duration: WfMotion.medium,
                    curve: WfMotion.emphasized,
                    width: i == _index ? 26 : 6,
                    height: 6,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? WfColors.cream.withValues(alpha: 0.3)
                          : WfColors.creamMuted,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: i == _index
                        ? AnimatedBuilder(
                            animation: _progress,
                            builder: (context, _) => FractionallySizedBox(
                              key: const Key('hero-dot-fill'),
                              alignment: Alignment.centerLeft,
                              widthFactor: _progress.value,
                              child: const ColoredBox(color: WfColors.gold),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      );
}
```

  - `_HeroSlide` riceve `required this.kenBurns` (`Animation<double>?`) e `required this.entrance` (`Animation<double>?`):
    - lo sfondo `WfImage(image: urls.backdrop(item))` diventa, se `kenBurns != null`:

```dart
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: kenBurns!,
            builder: (context, child) {
              final t = kenBurns!.value;
              return Transform(
                key: const Key('hero-ken-burns'),
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(
                      -kenBurnsDrift * t * MediaQuery.sizeOf(context).width,
                      0, 0, 1)
                  ..scaleByDouble(1 + kenBurnsScale * t,
                      1 + kenBurnsScale * t, 1, 1),
                child: child,
              );
            },
            child: WfImage(image: urls.backdrop(item)),
          ),
        ),
```

      (se `translateByDouble`/`scaleByDouble` non esistono nella versione di `vector_math`, usa `..translate(x)` e `..scale(s, s)` e segnalalo);
    - ogni elemento del blocco testi (logo o titolo, dati, trama, pulsanti: nell'ordine, indici 0–3) è avvolto, se `entrance != null`, in:

```dart
Widget _enter(Animation<double>? entrance, int index, Widget child) {
  if (entrance == null) return child;
  final total = WfMotion.crossfade.inMicroseconds;
  final begin = (heroTextDelay + heroTextStagger * index).inMicroseconds / total;
  final end = (begin + WfMotion.medium.inMicroseconds / total).clamp(0.0, 1.0);
  final t = entrance.drive(CurveTween(
      curve: Interval(begin, end, curve: WfMotion.emphasized)));
  return AnimatedBuilder(
    animation: t,
    child: child,
    builder: (context, child) => Opacity(
      opacity: t.value.clamp(0.0, 1.0),
      child: Transform.translate(
          offset: Offset(0, 10 * (1 - t.value)), child: child),
    ),
  );
}
```

  - togli `PageView`, `PageController`, `Timer` e l'import `dart:async` se non serve più (resta per `unawaited` dei pulsanti).

- [ ] **Step 5: verifica**

Run: `flutter test test/features/home/hero_carousel_test.dart test/features/home/home_screen_test.dart`, poi `flutter analyze` e `flutter test`
Expected: PASS, tutto verde. Nessun test deve sovrascrivere `carouselAutoplayProvider` due volte.

- [ ] **Step 6: commit**

```bash
git add lib/features/home/hero_carousel.dart test/support/pump_app.dart test/features/home/hero_carousel_test.dart
git commit -m "feat: crossfade hero carousel with ken burns and dot progress"
```

---

### Task 6: linea scorrevole condivisa, stagioni ed episodi

**Files:**
- Create: `lib/ui/sliding_underline.dart`
- Modify: `lib/app/app_shell.dart` (`_NavBar`), `lib/features/detail/series_detail_view.dart`
- Test: `test/ui/sliding_underline_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/sliding_underline.dart';

void main() {
  final keys = {for (final k in ['a', 'b', 'c']) k: GlobalKey()};

  Widget tree(String? selected) => Directionality(
        textDirection: TextDirection.ltr,
        child: WfMotionScope(
          motion: const WfMotion(MotionLevel.full),
          child: Align(
            alignment: Alignment.topLeft,
            child: SlidingUnderline(
              selected: selected,
              itemKeys: keys,
              indicatorKey: const Key('linea'),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final k in ['a', 'b', 'c'])
                  SizedBox(key: keys[k], width: k == 'b' ? 120 : 60, height: 30),
              ]),
            ),
          ),
        ),
      );

  testWidgets('sotto l\'elemento scelto, poi scorre al nuovo', (tester) async {
    await tester.pumpWidget(tree('a'));
    await tester.pump();
    expect(tester.getRect(find.byKey(const Key('linea'))).left, 0);
    await tester.pumpWidget(tree('b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.getRect(find.byKey(const Key('linea'))).left;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(60));
    await tester.pumpAndSettle();
    final line = tester.getRect(find.byKey(const Key('linea')));
    expect(line.left, 60);
    expect(line.width, 120);
    expect(line.height, 2);
  });

  testWidgets('nessuna scelta: nessuna linea', (tester) async {
    await tester.pumpWidget(tree(null));
    await tester.pump();
    expect(find.byKey(const Key('linea')), findsNothing);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/sliding_underline_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa** (`lib/ui/sliding_underline.dart`), spostando qui la logica di misura di `_NavBar`:

```dart
import 'package:flutter/widgets.dart';

import '../app/motion.dart';
import '../app/theme.dart';

/// Linea oro di 2 px sotto l'elemento [selected] di un gruppo (voci della
/// barra, stagioni); scorre da un elemento all'altro (spec C §9.3, §11.1).
/// Gli elementi hanno le [itemKeys] come chiavi: la linea li misura dopo il
/// layout. Si rimisura se cambia la dimensione del testo.
class SlidingUnderline extends StatefulWidget {
  const SlidingUnderline({
    super.key,
    required this.selected,
    required this.itemKeys,
    required this.child,
    this.indicatorKey,
  });

  final Object? selected;
  final Map<Object, GlobalKey> itemKeys;
  final Widget child;
  final Key? indicatorKey;

  @override
  State<SlidingUnderline> createState() => _SlidingUnderlineState();
}

class _SlidingUnderlineState extends State<SlidingUnderline> {
  final _stackKey = GlobalKey();

  /// Posizione dell'elemento scelto; `null` = nessuno.
  Rect? _active;

  /// Ultima posizione nota, per far sparire la linea dov'era.
  Rect? _last;

  void _measure() {
    if (!mounted) return;
    final selected = widget.selected;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final box = selected == null
        ? null
        : widget.itemKeys[selected]?.currentContext?.findRenderObject()
            as RenderBox?;
    Rect? rect;
    if (stack != null && box != null && box.hasSize) {
      rect = box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
    }
    if (rect != _active) {
      setState(() {
        _active = rect;
        if (rect != null) _last = rect;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    // Dipendenza: un cambio della dimensione del testo cambia le larghezze.
    MediaQuery.maybeTextScalerOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final shown = _active ?? _last;
    return Stack(
      key: _stackKey,
      children: [
        widget.child,
        if (shown != null)
          AnimatedPositioned(
            key: widget.indicatorKey,
            left: shown.left,
            width: shown.width,
            top: shown.bottom - 2,
            height: 2,
            duration: motion.pick(full: WfMotion.medium, reduced: Duration.zero),
            curve: WfMotion.emphasized,
            child: AnimatedOpacity(
              opacity: _active == null ? 0 : 1,
              duration: WfMotion.fast,
              child: const ColoredBox(color: WfColors.gold),
            ),
          ),
      ],
    );
  }
}
```

  (`maybeTextScalerOf`: il test monta il widget senza `MaterialApp`, quindi senza `MediaQuery`.)

- [ ] **Step 4: `_NavBar`** usa `SlidingUnderline(selected: _activeRoute, itemKeys: _itemKeys, indicatorKey: const Key('nav-indicator'), child: Row(...))` e perde la propria logica di misura (`_stackKey`, `_active`, `_last`, `_measure`, lo `Stack`). `_itemKeys` diventa `Map<Object, GlobalKey>`. I test della barra (`test/app/app_shell_motion_test.dart`, `app_shell_router_test.dart`) devono restare verdi senza modifiche.

- [ ] **Step 5: stagioni ed episodi** (`series_detail_view.dart`, import `../../ui/sliding_underline.dart`, `../../ui/staggered_entrance.dart`, `../../ui/wf_switcher.dart`):
  - `_SeasonTabs` diventa `StatefulWidget` con `final _keys = <Object, GlobalKey>{};`; il `Wrap` è avvolto in `SlidingUnderline(selected: selectedId, itemKeys: _keys, indicatorKey: const Key('season-indicator'), child: Wrap(...))`; ogni voce ha `key: _keys.putIfAbsent(season.id, GlobalKey.new)` sul `Container` e **niente** bordo proprio (tieni colore oro del testo per la scelta);
  - `_EpisodeList`, nel ramo `data`, restituisce:

```dart
StaggerGroup(
  key: ValueKey('episodes-$seasonId'),
  count: math.min(episodes.length, 10),
  child: Column(children: [
    for (final (i, episode) in episodes.indexed)
      StaggerItem(
        index: i,
        child: EpisodeTile(
            episode: episode, highlighted: episode.id == highlightId),
      ),
  ]),
)
```

    (import `dart:math` as `math`); il `when` intero è avvolto in `WfSwitcher(child: KeyedSubtree(key: ValueKey('$seasonId-<stato>'), child: …))`, così il cambio di stagione fa una dissolvenza incrociata e poi l'entrata degli episodi.
  - Test in `test/features/detail/series_detail_test.dart` (aggiungi, con le stesse impostazioni dei test esistenti della serie): cambiando stagione con due stagioni finte compare `Key('season-indicator')` sotto la nuova stagione dopo `pumpAndSettle` (`tester.getRect(...).left` ≈ `tester.getRect(find.text('<nome stagione 2>')).left - 8`, tolleranza 1).

- [ ] **Step 6: verifica**

Run: `flutter test test/ui/sliding_underline_test.dart test/features/detail test/app`, poi `flutter analyze` e `flutter test`
Expected: PASS, tutto verde.

- [ ] **Step 7: commit**

```bash
git add lib/ui/sliding_underline.dart lib/app/app_shell.dart lib/features/detail/series_detail_view.dart test/ui/sliding_underline_test.dart test/features/detail/series_detail_test.dart
git commit -m "feat: share sliding underline with season tabs and stagger episodes"
```

---

### Task 7: parallasse della testata ed entrata della scheda

**Files:**
- Create: `lib/features/detail/header_parallax.dart`
- Modify: `lib/features/detail/detail_backdrop.dart`, `lib/features/detail/detail_header.dart`, `lib/features/detail/movie_detail_view.dart`, `lib/features/detail/series_detail_view.dart`, `lib/features/detail/item_detail_screen.dart`
- Test: `test/features/detail/header_parallax_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/detail/detail_header.dart';
import 'package:wonderflix/features/detail/header_parallax.dart';

void main() {
  test('in cima: tutto fermo', () {
    final p = headerParallax(0, reduced: false);
    expect(p.backdropShift, 0);
    expect(p.backdropScale, 1);
    expect(p.dim, 0);
    expect(p.textOpacity, 1);
    expect(p.textShift, 0);
    expect(p.visibleHeight, detailHeaderHeight);
  });

  test('a metà: sfondo a metà velocità, zoom e scurimento parziali', () {
    const offset = detailHeaderHeight / 2;
    final p = headerParallax(offset, reduced: false);
    expect(p.backdropShift, -offset / 2);
    expect(p.backdropScale, closeTo(1.04, 1e-9));
    expect(p.dim, closeTo(0.25, 1e-9));
    expect(p.textOpacity, closeTo(0.2, 1e-9));
    expect(p.textShift, closeTo(-offset * 0.15, 1e-9));
    expect(p.visibleHeight, detailHeaderHeight - offset);
  });

  test('oltre la testata: limiti', () {
    final p = headerParallax(2000, reduced: false);
    expect(p.backdropScale, closeTo(1.08, 1e-9));
    expect(p.dim, closeTo(0.5, 1e-9));
    expect(p.textOpacity, 0);
    expect(p.visibleHeight, 0);
  });

  test('ridotte: lo sfondo segue lo scroll, niente effetti', () {
    final p = headerParallax(200, reduced: true);
    expect(p.backdropShift, -200);
    expect(p.backdropScale, 1);
    expect(p.dim, 0);
    expect(p.textOpacity, 1);
    expect(p.textShift, 0);
    expect(p.visibleHeight, detailHeaderHeight - 200);
  });

  test('scroll negativo (rimbalzo): come in cima', () {
    expect(headerParallax(-30, reduced: false).backdropShift, 0);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/detail/header_parallax_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa** (`lib/features/detail/header_parallax.dart`)

```dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'detail_header.dart';

/// Velocità dello sfondo rispetto al contenuto (spec C §9.1).
const parallaxFactor = 0.5;

/// Zoom massimo dello sfondo e scurimento massimo.
const parallaxMaxZoom = 0.08;
const parallaxMaxDim = 0.5;

/// Il testo della testata sparisce a questa frazione di testata scorsa.
const parallaxTextFadeEnd = 0.625;

/// Salita del testo rispetto allo scroll.
const parallaxTextRise = 0.15;

/// Posizione della testata per uno scroll (spec C §9.1).
@immutable
class HeaderParallax {
  const HeaderParallax({
    required this.backdropShift,
    required this.backdropScale,
    required this.dim,
    required this.textOpacity,
    required this.textShift,
    required this.visibleHeight,
  });

  /// Spostamento verticale dello sfondo.
  final double backdropShift;
  final double backdropScale;

  /// Opacità del velo scuro sopra lo sfondo.
  final double dim;
  final double textOpacity;
  final double textShift;

  /// Parte della testata ancora sullo schermo: lo sfondo si ritaglia lì,
  /// altrimenti sporgerebbe dietro alle righe sotto.
  final double visibleHeight;
}

HeaderParallax headerParallax(double offset, {required bool reduced}) {
  final o = math.max(0.0, offset);
  final visible = (detailHeaderHeight - o).clamp(0.0, detailHeaderHeight);
  if (reduced) {
    return HeaderParallax(
      backdropShift: -o,
      backdropScale: 1,
      dim: 0,
      textOpacity: 1,
      textShift: 0,
      visibleHeight: visible,
    );
  }
  final k = (o / detailHeaderHeight).clamp(0.0, 1.0);
  return HeaderParallax(
    backdropShift: -o * parallaxFactor,
    backdropScale: 1 + parallaxMaxZoom * k,
    dim: parallaxMaxDim * k,
    textOpacity: (1 - k / parallaxTextFadeEnd).clamp(0.0, 1.0),
    textShift: -o * parallaxTextRise,
    visibleHeight: visible,
  );
}
```

- [ ] **Step 4: sfondo.** `DetailBackdrop` (`detail_backdrop.dart`, import `../../app/motion.dart`, `../../app/theme.dart`, `header_parallax.dart`) nel `build`:

```dart
    final reduced = WfMotion.of(context).isReduced;
    return AnimatedBuilder(
      animation: controller,
      child: WfHero(
          tag: launch?.tag, borderRadius: BorderRadius.zero, child: image),
      builder: (context, child) {
        final p = headerParallax(
            controller.hasClients ? controller.offset : 0, reduced: reduced);
        return ClipRect(
          clipper: _VisibleHeader(p.visibleHeight),
          child: Transform.translate(
            offset: Offset(0, p.backdropShift),
            child: Transform.scale(
              scale: p.backdropScale,
              alignment: Alignment.topCenter,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child!,
                  if (p.dim > 0)
                    ColoredBox(color: WfColors.bg.withValues(alpha: p.dim)),
                ],
              ),
            ),
          ),
        );
      },
    );
```

  con in fondo al file:

```dart
/// Ritaglia lo sfondo alla parte della testata ancora sullo schermo.
class _VisibleHeader extends CustomClipper<Rect> {
  const _VisibleHeader(this.height);

  final double height;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width, height.clamp(0.0, size.height));

  @override
  bool shouldReclip(_VisibleHeader oldClipper) => oldClipper.height != height;
}
```

  Aggiorna il commento della classe (la parallasse ora c'è). Un test widget in `test/features/detail/detail_hero_test.dart` (o nuovo file): `DetailBackdrop` con un `ScrollController` attaccato a una `ListView` alta, motion completa, `controller.jumpTo(200)` → il `Transform` di traslazione ha `getTranslation().y == -100`.

- [ ] **Step 5: testo della testata ed entrata.** `DetailHeader` riceve due parametri opzionali:

```dart
  /// Scroll della pagina: il testo sfuma salendo (spec C §9.1).
  final ScrollController? controller;
```

  Il `Positioned` con la `Column` del testo diventa:

```dart
          Positioned(
            left: 32,
            right: 32,
            bottom: 28,
            child: _ScrollFade(
              controller: controller,
              child: Column(... come oggi, ma ogni figlio "logico" avvolto
                  in StaggerItem(index: n) con n = 0 logo/titolo, 1 dati,
                  2 generi, 3 trama, 4 pulsanti ...),
            ),
          ),
```

  con:

```dart
/// Opacità e salita del testo della testata con lo scroll.
class _ScrollFade extends StatelessWidget {
  const _ScrollFade({required this.controller, required this.child});

  final ScrollController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scroll = controller;
    if (scroll == null) return child;
    final reduced = WfMotion.of(context).isReduced;
    return AnimatedBuilder(
      animation: scroll,
      child: child,
      builder: (context, child) {
        final p = headerParallax(
            scroll.hasClients ? scroll.offset : 0, reduced: reduced);
        return Opacity(
          opacity: p.textOpacity,
          child: Transform.translate(
              offset: Offset(0, p.textShift), child: child),
        );
      },
    );
  }
}
```

  (`import 'dart:math'` non serve; import `header_parallax.dart`, `../../app/motion.dart`, `../../ui/staggered_entrance.dart`. Attenzione all'import circolare: `header_parallax.dart` importa `detail_header.dart` per `detailHeaderHeight` e viceversa; se l'analyzer lo segnala, sposta `detailHeaderHeight` in `header_parallax.dart` e riesportalo da `detail_header.dart` con `export 'header_parallax.dart' show detailHeaderHeight;`.)

- [ ] **Step 6: gruppo della scheda.** `MovieDetailView` e `SeriesDetailView` ricevono `this.entranceDelay = Duration.zero` (`final Duration entranceDelay;`) e avvolgono la loro `ListView` in:

```dart
StaggerGroup(
  count: detailEntranceCount,
  delay: entranceDelay,
  child: ListView(...),
)
```

  con in `detail_header.dart`:

```dart
/// Elementi della scheda che entrano scaglionati: 5 della testata (logo,
/// dati, generi, trama, pulsanti) e le righe sotto.
const detailEntranceCount = 8;
```

  Le righe sotto la testata (stagioni/episodi per la serie, cast, "Simili") sono avvolte in `StaggerItem(index: 5)`, `StaggerItem(index: 6)`, `StaggerItem(index: 7)` nell'ordine in cui compaiono. `DetailHeader` riceve `controller: controller`.
  In `ItemDetailScreen` le viste ricevono `entranceDelay: widget.launch != null ? WfMotion.hero : Duration.zero` (il contenuto entra a volo finito).

- [ ] **Step 7: verifica**

Run: `flutter test test/features/detail`, poi `flutter analyze` e `flutter test`
Expected: PASS, tutto verde. I test esistenti delle schede sono in modalità ridotta: il gruppo non parte e il testo resta visibile.

- [ ] **Step 8: commit**

```bash
git add lib/features/detail test/features/detail
git commit -m "feat: add header parallax and staggered detail entrance"
```

---

### Task 8: titolo e "Riproduci" nella barra

**Files:**
- Modify: `lib/app/app_shell.dart`, `lib/features/detail/movie_detail_view.dart`, `lib/features/detail/series_detail_view.dart`, `lib/features/detail/header_parallax.dart`
- Test: `test/app/shell_header_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/page_transitions.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

/// Pagina finta che pubblica un titolo dopo 380 px, come la scheda.
class _FakeDetail extends StatefulWidget {
  const _FakeDetail({required this.title, required this.onPlay});

  final String title;
  final VoidCallback onPlay;

  @override
  State<_FakeDetail> createState() => _FakeDetailState();
}

class _FakeDetailState extends State<_FakeDetail> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellHeaderPublisher(
        controller: _scroll,
        threshold: 380,
        header: ShellHeader(
            title: widget.title, actionLabel: 'Riproduci', onAction: widget.onPlay),
        child: ListView(
          key: const Key('detail-list'),
          controller: _scroll,
          children: [
            for (var i = 0; i < 40; i++) SizedBox(height: 100, child: Text('r$i')),
          ],
        ),
      );
}

void main() {
  testWidgets('il titolo compare nella barra oltre la soglia, e va via',
      (tester) async {
    var plays = 0;
    final router = GoRouter(initialLocation: '/home', routes: [
      ShellRoute(
        builder: appShellBuilder,
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => shellPage(
                context, state, const Text('home'), underBar: false),
          ),
          GoRoute(
            path: '/item/:id',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              _FakeDetail(title: 'Dune', onPlay: () => plays++),
              underBar: false,
            ),
          ),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    unawaited(router.push('/item/m1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-bar-title')), findsNothing);

    await tester.drag(find.byKey(const Key('detail-list')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shell-bar-play')));
    expect(plays, 1);

    await tester.drag(find.byKey(const Key('detail-list')), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsNothing);

    // Di nuovo sotto la soglia e poi indietro: la Home non ha titolo.
    await tester.drag(find.byKey(const Key('detail-list')), const Offset(0, -500));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsNothing);
  });
}
```

  (import `dart:async` per `unawaited`. Se `appShellBuilder` ha un nome o una firma diversi in `router.dart`, adatta l'uso e segnalalo.)

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/shell_header_test.dart`
Expected: FAIL (`ShellHeader`, `ShellHeaderPublisher` assenti).

- [ ] **Step 3: implementa** in `lib/app/app_shell.dart`:
  - modello:

```dart
/// Titolo e azione della pagina mostrati nella barra quando la sua testata
/// è uscita dallo schermo (spec C §9.2).
@immutable
class ShellHeader {
  const ShellHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  bool operator ==(Object other) =>
      other is ShellHeader &&
      other.title == title &&
      other.actionLabel == actionLabel;

  @override
  int get hashCode => Object.hash(title, actionLabel);
}
```

  (l'uguaglianza ignora il callback: cambia a ogni build.)
  - `_AppShellState` ha anche `final _header = ValueNotifier<ShellHeader?>(null);` (liberato in `dispose`); lo scope oggi chiamato `_ShellScrolledScope` porta **entrambi** i notifier (rinominalo `_ShellBarScope` con i campi `scrolled` e `header`);
  - `ShellPageFrame` ricorda anche `ShellHeader? _pageHeader` e, in `_publish()`, scrive **entrambi** i valori (`scrolled` e `header`) quando la pagina è in cima; espone:

```dart
  /// Imposta il titolo della pagina che contiene [context] (`null` = via).
  static void setHeader(BuildContext context, ShellHeader? header) =>
      context.findAncestorStateOfType<_ShellPageFrameState>()?._setHeader(header);
```

  con nello stato:

```dart
  void _setHeader(ShellHeader? header) {
    _pageHeader = header;
    if (_current) _publish();
  }
```

  - editore:

```dart
/// Pubblica [header] nella barra quando lo scroll di [controller] supera
/// [threshold], e lo toglie sotto la soglia o alla chiusura.
class ShellHeaderPublisher extends StatefulWidget {
  const ShellHeaderPublisher({
    super.key,
    required this.controller,
    required this.threshold,
    required this.header,
    required this.child,
  });

  final ScrollController controller;
  final double threshold;

  /// `null` finché non si sa cosa mostrare.
  final ShellHeader? header;
  final Widget child;

  @override
  State<ShellHeaderPublisher> createState() => _ShellHeaderPublisherState();
}

class _ShellHeaderPublisherState extends State<ShellHeaderPublisher> {
  _ShellPageFrameState? _frame;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frame = context.findAncestorStateOfType<_ShellPageFrameState>();
  }

  @override
  void didUpdateWidget(ShellHeaderPublisher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    if (_shown && oldWidget.header != widget.header) {
      _frame?._setHeader(widget.header);
    }
  }

  void _onScroll() {
    final controller = widget.controller;
    final shown =
        controller.hasClients && controller.offset >= widget.threshold;
    if (shown == _shown) return;
    _shown = shown;
    _frame?._setHeader(shown ? widget.header : null);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    if (_shown) _frame?._setHeader(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

  - nella barra, fra `_NavBar` e lo `Spacer`:

```dart
                        const SizedBox(width: 24),
                        _BarTitle(header: _header),
```

  con:

```dart
/// Titolo e piccolo "Riproduci" della pagina in cima (spec C §9.2).
class _BarTitle extends StatelessWidget {
  const _BarTitle({required this.header});

  final ValueNotifier<ShellHeader?> header;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    return Flexible(
      child: ValueListenableBuilder<ShellHeader?>(
        valueListenable: header,
        builder: (context, value, _) => AnimatedSwitcher(
          duration: motion.duration(WfMotion.medium),
          switchInCurve: WfMotion.emphasized,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                  .animate(animation),
              child: child,
            ),
          ),
          child: value == null
              ? const SizedBox.shrink()
              : Row(
                  key: const Key('shell-bar-title'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(value.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WfText.display(22)),
                    ),
                    if (value.onAction != null) ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        key: const Key('shell-bar-play'),
                        onPressed: value.onAction,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        icon: const Icon(LucideIcons.play, size: 14),
                        label: Text(value.actionLabel ?? ''),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: soglia e schede.** In `header_parallax.dart`:

```dart
/// Oltre questo scroll il titolo e "Riproduci" compaiono nella barra: la
/// riga dei pulsanti della testata è passata sotto la barra (decisione 6b,
/// da ritoccare nella prova).
const detailBarTitleOffset = 380.0;
```

  `MovieDetailView` e `SeriesDetailView` avvolgono lo `StaggerGroup` (Task 7) in:

```dart
ShellHeaderPublisher(
  controller: controller!,
  threshold: detailBarTitleOffset,
  header: ShellHeader(
    title: item.name,
    actionLabel: action == null ? null : primaryActionLabel(l, action),
    onAction: action == null
        ? null
        : () => unawaited(playItem(context, ref, action.target)),
  ),
  child: ...,
)
```

  solo se `controller != null` (nei test che montano le viste da sole senza controller: niente editore). `action` è la stessa `PrimaryAction` passata a `DetailHeader` (per la serie: quella del prossimo episodio). Import `dart:async`, `../../app/app_shell.dart`, `../../l10n/gen/app_localizations.dart`, `../playback/play_launcher.dart`, e dove sta `primaryActionLabel`.

- [ ] **Step 5: verifica**

Run: `flutter test test/app/shell_header_test.dart test/app test/features/detail`, poi `flutter analyze` e `flutter test`
Expected: PASS, tutto verde.

- [ ] **Step 6: commit**

```bash
git add lib/app/app_shell.dart lib/features/detail test/app/shell_header_test.dart
git commit -m "feat: show title and play in the bar past the detail header"
```

---

### Task 9: durate rimaste e spec

**Files:**
- Modify: `lib/ui/media_row.dart`, `lib/ui/wf_image.dart`, `docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md`

- [ ] **Step 1:** in `media_row.dart` `_scroll` usa `duration: WfMotion.medium, curve: WfMotion.decelerate` (import `../app/motion.dart`); in `wf_image.dart` `fadeInDuration: WfMotion.fast` (import `../app/motion.dart`).
- [ ] **Step 2: spec.** In `docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md`:
  - §8.1: aggiungi che il tempo della diapositiva è un `AnimationController` (niente timer) e che nei widget test l'autoplay è spento (`carouselAutoplayProvider`);
  - §8.2: "Non si ripete tornando alla Home" diventa "Si vede una volta per sessione dell'app: tornando alla Home, anche dalla barra, non si ripete";
  - §9.2: sostituisci il paragrafo **Realizzazione** con: "la scheda pubblica `ShellHeader(title, actionLabel, onAction)` con `ShellHeaderPublisher` quando lo scroll supera `detailBarTitleOffset` (380 px); `ShellPageFrame` lo ricorda per la propria pagina e lo passa alla barra quando la pagina è in cima, come lo stato "scorsa". Tornando indietro la barra ritrova il titolo della pagina tornata in cima."
  - §10.1: "Ogni `SkeletonBox` dipinge…" → "Ogni `SkeletonBox` è un `CustomPainter` che si ridipinge con il controller dell'onda (senza ricostruire widget) e dipinge il gradiente in coordinate di `WfShimmer`".
- [ ] **Step 3: verifica e commit**

Run: `flutter analyze` e `flutter test`
Expected: tutto verde.

```bash
git add lib/ui/media_row.dart lib/ui/wf_image.dart docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md
git commit -m "chore: move remaining durations to motion tokens and align spec C"
```

---

### Task 10: verifica finale

**Files:** nessuno (salvo correzioni emerse).

- [ ] **Step 1:** `flutter gen-l10n`, `flutter analyze`, `flutter test`: nessun problema, tutto verde. Annota il numero dei test (erano 772).
- [ ] **Step 2:** cerca durate e curve scritte a mano nei file toccati da questo piano: `grep -rn "Duration(milliseconds\|Curves\." lib/ui lib/features/home lib/features/detail lib/app`. Tutte devono venire da `WfMotion` o da costanti nominate e commentate (`shimmerPeriod`, `rowEntranceStagger`, `homeRowStagger`, `heroTextDelay`, `heroTextStagger`, `wheelScrollDuration`, `shellTransitionDuration`…). Restano fuori solo il player e il bordo delle card (6c). Segnala cosa hai trovato.
- [ ] **Step 3:** build di prova: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` e `flutter build windows --debug` deve riuscire (se l'app dell'utente è aperta e dà `LNK1168`/`LNK1104`, **non** chiuderla: segnalalo).
- [ ] **Step 4:** se hai corretto qualcosa, commit `fix: …` che dica cosa.

## Prova manuale (con l'utente, sul server reale)

Build di release: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` e `flutter build windows --release --dart-define-from-file=config/wonderflix.json`; l'exe lo avvia l'utente.

- **Caricamento:** onda oro unica su Home (all'avvio), scheda aperta senza volo (dal carosello "Dettagli"), episodi al cambio di stagione, Catalogo, La mia lista, Ricerca, persona; passaggio in dissolvenza al contenuto.
- **Home:** righe che salgono una dopo l'altra e card che volano dentro solo la prima volta; tornando alla Home dalla barra niente entrata.
- **Carosello:** dissolvenza cinematografica, Ken Burns, testi che entrano scaglionati, puntino che si riempie in 8 s; mouse sopra = pausa (puntino fermo); clic sui puntini; Home coperta da una scheda e ritorno: riprende da dov'era.
- **Scheda:** dopo il volo il contenuto entra scaglionato; parallasse dello sfondo (lento, zoom, scurimento) e testo che sfuma salendo; lo sfondo non sporge dietro al cast; titolo e "Riproduci" nella barra dopo circa 380 px (va bene la soglia?), "Riproduci" parte davvero; scheda → persona → indietro: il titolo torna quello della scheda (se era scorsa).
- **Serie:** linea oro che scorre tra le stagioni, episodi in dissolvenza e poi scaglionati.
- **Animazioni ridotte:** niente Ken Burns, niente parallasse (lo sfondo segue lo scroll), niente entrate; scheletri fermi; titolo nella barra sì.
- **Prestazioni:** con `flutter run --profile` (o la release) scorrere Home e scheda: fluido? carosello e onda senza scatti.
- **Regressioni:** volo Hero, barra, player, watch party.
