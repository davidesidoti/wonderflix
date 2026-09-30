# WonderFlix — Piano 6a: fondamenta del movimento e navigazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** prima parte dello Spec C (rinnovo grafico):
- **fondamenta:** token di movimento (`WfMotion`), livello completo/ridotto, impostazione "Animazioni" (Come Windows / Complete / Ridotte) e lettura di "Effetti di animazione" di Windows;
- **scroll morbido** con la rotella del mouse in tutte le pagine (il touchpad resta com'è);
- **transizioni tra le pagine:** "fade through" tra le voci della barra, dissolvenza verso scheda e persona;
- **barra in alto sovrapposta** al contenuto (Home e scheda arrivano fino al bordo della finestra), **sottolineatura oro scorrevole**, **barra scura e sfocata** quando la pagina scorre, voci e icone che si tingono d'oro al passaggio del mouse;
- **volo Hero** dell'immagine: card → testata della scheda, volto del cast → foto della persona;
- **pulsanti vivi:** alone oro e scala al passaggio del mouse, "pressione" al clic, "pop" di cuore e spunta.

**Decisioni prese con l'utente (2026-09-30):** divisione in 6a/6b/6c; senza `WfMotionScope` il livello è **ridotto** (i test esistenti non cambiano); passo della rotella **×1,6** (costante da ritoccare nella prova); carosello (460 px) e testata (560 px) restano alti uguali e partono dal bordo della finestra; le card ricevono `heroSource` e aprono la scheda da sole; i pulsanti play sulle card restano fino al 6c.

**Rimandato ad altri piani (non farlo qui):** entrata scaglionata del contenuto della scheda dopo il volo, shimmer, carosello, parallasse, titolo nella barra (6b); anteprima delle card, griglie scaglionate, splash e login, menu e dialoghi (6c). Il `PartyChip` del watch party nella barra resta com'è (è già oro).

**Architecture:**
- `lib/app/motion.dart`: `MotionLevel`, `WfMotion` (token + `of(context)`), `WfMotionScope` (InheritedWidget sopra il router).
- `lib/core/system/windows_animation_pref.dart`: `AnimationPreference` + `WindowsAnimationPreference` (FFI `SystemParametersInfoW`).
- `lib/features/settings/appearance_settings.dart`: `MotionSetting`, `MotionSettingController`, `SystemAnimationsController`, `resolveMotionLevel`, `motionLevelProvider`; `appearance_settings_section.dart` in Impostazioni.
- `lib/ui/smooth_scroll.dart`: `SmoothScrollController` / `SmoothScrollPosition` (ridefinisce `pointerScroll`).
- `lib/app/page_transitions.dart`: `shellPage`, `detailPage`, `pageTransition`.
- `lib/app/hero_launch.dart`: `WfHeroTag`, `HeroLaunch`, `WfHero`, `wfHeroFlight`.
- `lib/ui/hover_builder.dart`: `HoverBuilder`.
- `lib/features/detail/detail_backdrop.dart`: lo sfondo della scheda diventa un livello separato dietro al contenuto (segue lo scroll; nel 6b diventerà la parallasse), presente **già durante il caricamento** grazie a `HeroLaunch`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, window_manager, `dart:ffi` + `package:ffi`, shared_preferences, `logging`.

**Spec:** `docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md` (§4, §5, §6, §11.1, §11.2). **Worktree:** `.claude/worktrees/rinnovo-6a`, branch `feat/rinnovo-6a`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…". Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/rinnovo-6a`, branch `feat/rinnovo-6a`). Comandi git semplici, non composti con variabili.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde. Se `lib/l10n/gen` manca o è vecchio, esegui prima `flutter gen-l10n`.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione:** non eseguire `dart format` su file interi.
- **Fine riga:** molti file sono CRLF (ARB, `app_shell.dart`, `router.dart`, `poster_card.dart`, `detail_header.dart`, `person_screen.dart`, …). Edit mirati che mantengono le fini riga; non riscriverli da zero. I file **nuovi** vanno in LF.
- **Import:** se l'analyzer segnala un import superfluo o mancante, correggilo e segnalalo.
- **Icone:** solo `LucideIcons`, niente emoji. **Colori:** solo `WfColors`.
- **Durate e curve:** solo dai token di `WfMotion` (o dalle costanti nominate di questo piano). Il player non si tocca.
- **Widget test:** qualunque `Timer` rimasto aperto a fine test fa fallire il test. `pumpApp` monta ora `WfMotionScope` in modalità **ridotta**: nei test che provano un'animazione passa `motion: MotionLevel.full`. `find.byType` non trova le sottoclassi: per `WfButton` cerca il testo.
- **Router:** con go_router 18 dopo `push` la pagina in cima è `GoRouter.of(context).state.uri`, non `routeInformationProvider.value.uri`.
- **Fake:** niente mocktail. `FakeLibraryApi`, `testItem` in `test/support/library_fakes.dart`; `FakeSessionController` in `test/support/fake_session_controller.dart`; `FakeWatchPartyDirectory`, `FakeSyncPlayApi` in `test/support/watch_party_fakes.dart`; `testUser` in `test/support/test_data.dart`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test sfuggito al piano): correggilo in modo minimo, nello spirito del piano, e segnalalo. I test descrivono il comportamento: preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **Rotella:** `Scrollable._handlePointerScroll` chiama `position.pointerScroll(delta)` **solo** per `PointerScrollEvent`, dopo aver scelto lo scrollable con `GestureBinding.instance.pointerSignalResolver` (vince il più interno che può muoversi). Il touchpad di precisione su Windows manda `PointerPanZoom*`, gestiti come trascinamento: non passa da `pointerScroll`. `pointerScroll(0)` arriva con `PointerScrollInertiaCancelEvent` e fa `goBallistic(0)`.
- **Righe orizzontali:** per un asse orizzontale `Scrollable` usa `scrollDelta.dx` (con Shift, per il mouse, scambia gli assi). La rotella verticale sopra una riga dà delta 0: la riga non si registra e scorre la pagina.
- **`ScrollPositionWithSingleContext.animateTo`** crea subito un `DrivenScrollActivity` (sincrono): dopo la chiamata `activity` è quello dell'animazione. Un trascinamento, un `jumpTo` o un altro `animateTo` sostituiscono l'attività.
- **Windows e animazioni:** `MediaQuery.disableAnimations` è sempre falso su Windows (l'engine manda solo il contrasto elevato). `SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION = 0x1042, 0, BOOL*, 0)` legge "Effetti di animazione" (Impostazioni → Accessibilità → Effetti visivi).
- **Hero e go_router:** il navigatore della `ShellRoute` ha il suo `HeroControllerScope` (go_router ≥ 6.0.7). Il volo parte nel fotogramma del `push`: il `Hero` di destinazione deve esistere **subito**, anche se la scheda sta ancora caricando. Due `Hero` con lo stesso tag nella stessa pagina sono un errore; tra le due pagine volano **tutti** i tag in comune (per questo il tag contiene la sorgente, e la sorgente contiene l'id della pagina: `cast.<itemId>.<i>`, `similar.<itemId>.<i>`).
- **`flightShuttleBuilder`:** riceve l'animazione della rotta (0→1 in `push`, 1→0 in `pop`) e i contesti dei due `Hero`; `fromHeroContext` è quello della pagina che si lascia.
- **`CustomTransitionPage`:** `animation` è l'entrata della pagina, `secondaryAnimation` sale quando un'altra pagina le entra sopra.
- **`AnimatedOpacity` a 0** non dipinge il figlio: un `BackdropFilter` sotto opacità 0 non costa nulla.
- **`ProviderScope.containerOf(context, listen: false)`** legge un provider da una funzione che ha solo il `BuildContext` (Riverpod 3).

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `lib/app/motion.dart` | crea | token, livello, `WfMotion.of`, `WfMotionScope` |
| `lib/core/system/windows_animation_pref.dart` | crea | lettura FFI di "Effetti di animazione" |
| `lib/features/settings/appearance_settings.dart` | crea | impostazione, preferenza di sistema, livello effettivo |
| `lib/features/settings/appearance_settings_section.dart` | crea | sezione "Aspetto" |
| `lib/features/settings/settings_screen.dart` | modifica | sezione "Aspetto", scroll morbido |
| `lib/app/app.dart` | modifica | `WfMotionScope` + ascolto del focus della finestra |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | 6 stringhe |
| `test/support/pump_app.dart` | modifica | `WfMotionScope` (ridotto per default) |
| `lib/ui/smooth_scroll.dart` | crea | scroll morbido con la rotella |
| `lib/ui/media_row.dart`, `lib/features/home/home_screen.dart`, `lib/features/catalog/catalog_screen.dart`, `lib/features/mylist/my_list_screen.dart`, `lib/features/search/search_screen.dart` | modifica | `SmoothScrollController`, `heroSource` |
| `lib/app/page_transitions.dart` | crea | pagine e transizioni della shell |
| `lib/app/router.dart` | modifica | `pageBuilder` delle rotte della shell, `HeroLaunch` da `extra` |
| `lib/ui/hover_builder.dart` | crea | stato di passaggio del mouse |
| `lib/app/app_shell.dart` | modifica | barra sovrapposta, sottolineatura, barra scura, oro al passaggio |
| `lib/app/hero_launch.dart` | crea | tag, dati del volo, `WfHero`, volo con dissolvenza |
| `lib/app/navigation.dart` | modifica | `openItem`/`openPerson` con `heroSource` |
| `lib/ui/poster_card.dart`, `lib/ui/landscape_card.dart` | modifica | `heroSource`, `Hero`, apertura di default |
| `lib/features/detail/detail_rows.dart` | modifica | `Hero` del cast, sorgenti |
| `lib/features/detail/detail_backdrop.dart` | crea | livello dello sfondo della scheda |
| `lib/features/detail/detail_header.dart` | modifica | `detailHeaderHeight`, niente sfondo interno |
| `lib/features/detail/item_detail_screen.dart` | modifica | stateful, controller, `HeroLaunch`, sfondo durante il caricamento |
| `lib/features/detail/movie_detail_view.dart`, `series_detail_view.dart` | modifica | parametro `controller` |
| `lib/features/person/person_screen.dart` | modifica | testata stabile con la foto (`Hero`), scroll morbido |
| `lib/ui/wf_buttons.dart` | modifica | alone, scala, pressione, pop |

## Gruppi per i subagent

- **Gruppo A (Task 1–3):** fondamenta del movimento.
- **Gruppo B (Task 4–5):** scroll morbido.
- **Gruppo C (Task 6–7):** transizioni e barra in alto.
- **Gruppo D (Task 8–10):** volo Hero.
- **Gruppo E (Task 11–12):** pulsanti e verifica finale.

---

### Task 1: token e livello di movimento (`WfMotion`)

**Files:**
- Create: `lib/app/motion.dart`
- Test: `test/app/motion_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';

void main() {
  test('pick e duration seguono il livello', () {
    const full = WfMotion(MotionLevel.full);
    const reduced = WfMotion(MotionLevel.reduced);
    expect(full.isReduced, isFalse);
    expect(reduced.isReduced, isTrue);
    expect(full.pick(full: 1, reduced: 2), 1);
    expect(reduced.pick(full: 1, reduced: 2), 2);
    expect(full.duration(WfMotion.slow), WfMotion.slow);
    expect(reduced.duration(WfMotion.slow), WfMotion.fast);
    expect(const WfMotion(MotionLevel.full), full);
  });

  testWidgets('of: livello dello scope, ridotto se manca', (tester) async {
    late WfMotion outside;
    late WfMotion inside;
    await tester.pumpWidget(Builder(builder: (context) {
      outside = WfMotion.of(context);
      return WfMotionScope(
        motion: const WfMotion(MotionLevel.full),
        child: Builder(builder: (context) {
          inside = WfMotion.of(context);
          return const SizedBox();
        }),
      );
    }));
    expect(outside.level, MotionLevel.reduced);
    expect(inside.level, MotionLevel.full);
  });

  testWidgets('lo scope avvisa chi dipende quando cambia il livello',
      (tester) async {
    var builds = 0;
    Widget tree(MotionLevel level) => WfMotionScope(
          motion: WfMotion(level),
          child: Builder(builder: (context) {
            WfMotion.of(context);
            builds++;
            return const SizedBox();
          }),
        );
    await tester.pumpWidget(tree(MotionLevel.full));
    await tester.pumpWidget(tree(MotionLevel.full));
    final afterSame = builds;
    await tester.pumpWidget(tree(MotionLevel.reduced));
    expect(builds, afterSame + 1);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/motion_test.dart`
Expected: FAIL (`motion.dart` non esiste).

- [ ] **Step 3: implementa**

```dart
import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

/// Quanto si muove l'interfaccia (spec C §4.2).
enum MotionLevel { full, reduced }

/// Token di movimento: durate, curve e livello. I widget li leggono con
/// [WfMotion.of]; nessuna durata scritta a mano (il player escluso).
@immutable
class WfMotion {
  const WfMotion(this.level);

  final MotionLevel level;

  /// Dissolvenze brevi, uscite, tutto il movimento in modalità ridotta.
  static const fast = Duration(milliseconds: 150);

  /// Anteprima, sottolineatura della barra, scheletro → contenuto.
  static const medium = Duration(milliseconds: 300);

  /// Entrate di righe e card.
  static const slow = Duration(milliseconds: 450);

  /// Volo dell'immagine card → scheda.
  static const hero = Duration(milliseconds: 420);

  /// Diapositive del carosello.
  static const crossfade = Duration(milliseconds: 900);

  /// Ritardo tra elementi della stessa entrata.
  static const stagger = Duration(milliseconds: 60);

  /// Curva principale: entrate, voli, anteprima.
  static const Curve emphasized = Cubic(0.2, 0.8, 0.2, 1);

  /// Dissolvenze.
  static const Curve standard = Curves.easeInOut;

  /// Entrate "volanti" e apertura dell'anteprima, con un leggero rimbalzo.
  static const Curve bounce = Cubic(0.2, 0.9, 0.25, 1.2);

  bool get isReduced => level == MotionLevel.reduced;

  /// [full] con le animazioni complete, [reduced] con quelle ridotte.
  T pick<T>({required T full, required T reduced}) =>
      isReduced ? reduced : full;

  /// Durata di un effetto: con il livello ridotto diventa [fast].
  Duration duration(Duration full) => isReduced ? fast : full;

  /// Livello più vicino a [context]. Senza [WfMotionScope] (test che
  /// montano l'app a mano) è ridotto: niente animazioni lunghe o infinite.
  static WfMotion of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WfMotionScope>()?.motion ??
      const WfMotion(MotionLevel.reduced);

  @override
  bool operator ==(Object other) => other is WfMotion && other.level == level;

  @override
  int get hashCode => level.hashCode;

  @override
  String toString() => 'WfMotion(${level.name})';
}

/// Rende disponibile [WfMotion] a tutto l'albero sotto di sé.
class WfMotionScope extends InheritedWidget {
  const WfMotionScope({super.key, required this.motion, required super.child});

  final WfMotion motion;

  @override
  bool updateShouldNotify(WfMotionScope oldWidget) =>
      oldWidget.motion != motion;
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/app/motion_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/app/motion.dart test/app/motion_test.dart
git commit -m "feat: add motion tokens and level scope"
```

---

### Task 2: impostazione "Animazioni" e preferenza di Windows

**Files:**
- Create: `lib/core/system/windows_animation_pref.dart`
- Create: `lib/features/settings/appearance_settings.dart`
- Test: `test/features/settings/appearance_settings_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/system/windows_animation_pref.dart';
import 'package:wonderflix/features/settings/appearance_settings.dart';

class FakeAnimationPreference implements AnimationPreference {
  FakeAnimationPreference(this.enabled);

  bool enabled;
  int reads = 0;

  @override
  bool animationsEnabled() {
    reads++;
    return enabled;
  }
}

void main() {
  test('resolveMotionLevel: tabella dello spec §4.5', () {
    expect(resolveMotionLevel(MotionSetting.system, systemAnimations: true),
        MotionLevel.full);
    expect(resolveMotionLevel(MotionSetting.system, systemAnimations: false),
        MotionLevel.reduced);
    expect(resolveMotionLevel(MotionSetting.full, systemAnimations: false),
        MotionLevel.full);
    expect(resolveMotionLevel(MotionSetting.reduced, systemAnimations: true),
        MotionLevel.reduced);
  });

  Future<(ProviderContainer, FakeAnimationPreference, SharedPreferences)>
      setUpContainer({Map<String, Object> values = const {}, bool system = true}) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final pref = FakeAnimationPreference(system);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      animationPreferenceProvider.overrideWithValue(pref),
    ]);
    addTearDown(container.dispose);
    return (container, pref, prefs);
  }

  test('predefinito: Come Windows', () async {
    final (container, _, _) = await setUpContainer(system: false);
    expect(container.read(motionSettingProvider), MotionSetting.system);
    expect(container.read(motionLevelProvider), MotionLevel.reduced);
  });

  test('l\'impostazione si salva e si rilegge', () async {
    final (container, _, prefs) = await setUpContainer();
    await container.read(motionSettingProvider.notifier).set(MotionSetting.reduced);
    expect(prefs.getString('appearance.motion'), 'reduced');
    expect(container.read(motionLevelProvider), MotionLevel.reduced);

    final (other, _, _) =
        await setUpContainer(values: {'appearance.motion': 'full'}, system: false);
    expect(other.read(motionSettingProvider), MotionSetting.full);
    expect(other.read(motionLevelProvider), MotionLevel.full);
  });

  test('valore salvato sconosciuto: Come Windows', () async {
    final (container, _, _) =
        await setUpContainer(values: {'appearance.motion': 'boh'});
    expect(container.read(motionSettingProvider), MotionSetting.system);
  });

  test('refresh rilegge la preferenza di Windows', () async {
    final (container, pref, _) = await setUpContainer();
    expect(container.read(motionLevelProvider), MotionLevel.full);
    pref.enabled = false;
    container.read(systemAnimationsProvider.notifier).refresh();
    expect(container.read(motionLevelProvider), MotionLevel.reduced);
    expect(pref.reads, 2);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/settings/appearance_settings_test.dart`
Expected: FAIL (file inesistenti).

- [ ] **Step 3: implementa la lettura di Windows** (`lib/core/system/windows_animation_pref.dart`)

```dart
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

/// Preferenza di sistema per le animazioni.
abstract interface class AnimationPreference {
  /// `true` se il sistema ha le animazioni attive.
  bool animationsEnabled();
}

/// `SPI_GETCLIENTAREAANIMATION`: voce "Effetti di animazione" di Windows.
const _spiGetClientAreaAnimation = 0x1042;

/// Legge "Effetti di animazione" con `SystemParametersInfoW`. Flutter su
/// Windows non la passa a `MediaQuery.disableAnimations` (spec C §4.4).
class WindowsAnimationPreference implements AnimationPreference {
  static final _log = Logger('motion');

  @override
  bool animationsEnabled() {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final systemParametersInfo = user32.lookupFunction<
          Int32 Function(Uint32, Uint32, Pointer<Void>, Uint32),
          int Function(int, int, Pointer<Void>, int)>('SystemParametersInfoW');
      final value = calloc<Int32>();
      try {
        final ok = systemParametersInfo(
            _spiGetClientAreaAnimation, 0, value.cast(), 0);
        if (ok == 0) {
          _log.warning('SystemParametersInfoW non riuscita: animazioni complete');
          return true;
        }
        return value.value != 0;
      } finally {
        calloc.free(value);
      }
    } on Object catch (e) {
      _log.warning('preferenza delle animazioni non leggibile: $e');
      return true;
    }
  }
}
```

- [ ] **Step 4: implementa impostazione e livello** (`lib/features/settings/appearance_settings.dart`)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/system/windows_animation_pref.dart';

/// Voce "Animazioni" delle impostazioni (spec C §4.3).
enum MotionSetting { system, full, reduced }

/// Livello effettivo (spec C §4.5).
MotionLevel resolveMotionLevel(MotionSetting setting,
        {required bool systemAnimations}) =>
    switch (setting) {
      MotionSetting.full => MotionLevel.full,
      MotionSetting.reduced => MotionLevel.reduced,
      MotionSetting.system =>
        systemAnimations ? MotionLevel.full : MotionLevel.reduced,
    };

class MotionSettingController extends Notifier<MotionSetting> {
  static const _key = 'appearance.motion';

  @override
  MotionSetting build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return MotionSetting.values.asNameMap()[saved] ?? MotionSetting.system;
  }

  Future<void> set(MotionSetting value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setString(_key, value.name);
  }
}

final motionSettingProvider =
    NotifierProvider<MotionSettingController, MotionSetting>(
        MotionSettingController.new);

/// Sostituito nei test.
final animationPreferenceProvider =
    Provider<AnimationPreference>((ref) => WindowsAnimationPreference());

/// "Effetti di animazione" di Windows; [refresh] al ritorno del focus.
class SystemAnimationsController extends Notifier<bool> {
  @override
  bool build() => ref.watch(animationPreferenceProvider).animationsEnabled();

  void refresh() =>
      state = ref.read(animationPreferenceProvider).animationsEnabled();
}

final systemAnimationsProvider =
    NotifierProvider<SystemAnimationsController, bool>(
        SystemAnimationsController.new);

final motionLevelProvider = Provider<MotionLevel>((ref) => resolveMotionLevel(
      ref.watch(motionSettingProvider),
      systemAnimations: ref.watch(systemAnimationsProvider),
    ));
```

- [ ] **Step 5: verifica che passi**

Run: `flutter test test/features/settings/appearance_settings_test.dart`
Expected: PASS.

- [ ] **Step 6: commit**

```bash
git add lib/core/system/windows_animation_pref.dart lib/features/settings/appearance_settings.dart test/features/settings/appearance_settings_test.dart
git commit -m "feat: add animations setting and windows preference"
```

---

### Task 3: collegamento all'app, sezione "Aspetto", helper dei test

**Files:**
- Modify: `lib/app/app.dart`
- Create: `lib/features/settings/appearance_settings_section.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify: `test/support/pump_app.dart`
- Test: `test/app/l10n_plan6a_test.dart`, `test/features/settings/appearance_settings_section_test.dart`

- [ ] **Step 1: stringhe.** In `l10n/app_it.arb`, prima della `}` finale (aggiungi la virgola alla riga precedente, mantieni CRLF):

```json
  "settingsAppearance": "Aspetto",
  "settingsAnimations": "Animazioni",
  "settingsAnimationsHint": "«Come Windows» segue «Effetti di animazione» nelle impostazioni di Windows. Con «Ridotte» restano solo dissolvenze brevi.",
  "settingsAnimationsSystem": "Come Windows",
  "settingsAnimationsFull": "Complete",
  "settingsAnimationsReduced": "Ridotte"
```

In `l10n/app_en.arb`:

```json
  "settingsAppearance": "Appearance",
  "settingsAnimations": "Animations",
  "settingsAnimationsHint": "“Same as Windows” follows “Animation effects” in the Windows settings. “Reduced” keeps only short fades.",
  "settingsAnimationsSystem": "Same as Windows",
  "settingsAnimationsFull": "Full",
  "settingsAnimationsReduced": "Reduced"
```

Poi `flutter gen-l10n`.

- [ ] **Step 2: scrivi i test che falliscono**

`test/app/l10n_plan6a_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 6a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.settingsAppearance, 'Aspetto');
    expect(en.settingsAppearance, 'Appearance');
    expect(it.settingsAnimations, 'Animazioni');
    expect(it.settingsAnimationsSystem, 'Come Windows');
    expect(it.settingsAnimationsFull, 'Complete');
    expect(it.settingsAnimationsReduced, 'Ridotte');
    expect(en.settingsAnimationsSystem, 'Same as Windows');
    expect(en.settingsAnimationsReduced, 'Reduced');
  });
}
```

`test/features/settings/appearance_settings_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/settings/appearance_settings_section.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('sceglie "Ridotte" e lo salva', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(
      tester,
      const Scaffold(body: AppearanceSettingsSection()),
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(find.text('Animazioni'), findsOneWidget);
    expect(find.text('Come Windows'), findsOneWidget);
    await tester.tap(find.text('Ridotte'));
    await tester.pumpAndSettle();
    expect(prefs.getString('appearance.motion'), 'reduced');
  });
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/app/l10n_plan6a_test.dart test/features/settings/appearance_settings_section_test.dart`
Expected: il primo PASS dopo `gen-l10n`; il secondo FAIL (sezione inesistente).

- [ ] **Step 4: sezione "Aspetto"** (`lib/features/settings/appearance_settings_section.dart`)

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'appearance_settings.dart';

/// Voce "Animazioni" (spec C §4.3).
class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final setting = ref.watch(motionSettingProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.settingsAnimations),
          const SizedBox(height: 6),
          SegmentedButton<MotionSetting>(
            key: const Key('appearance-motion'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: MotionSetting.system,
                  label: Text(l.settingsAnimationsSystem)),
              ButtonSegment(
                  value: MotionSetting.full, label: Text(l.settingsAnimationsFull)),
              ButtonSegment(
                  value: MotionSetting.reduced,
                  label: Text(l.settingsAnimationsReduced)),
            ],
            selected: {setting},
            onSelectionChanged: (selection) => unawaited(
                ref.read(motionSettingProvider.notifier).set(selection.first)),
          ),
          const SizedBox(height: 8),
          Text(l.settingsAnimationsHint,
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 12.5)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Impostazioni.** In `lib/features/settings/settings_screen.dart`, subito prima di `section(l.settingsPlayer),`:

```dart
          section(l.settingsAppearance),
          const AppearanceSettingsSection(),
```

con l'import `import 'appearance_settings_section.dart';`.

- [ ] **Step 6: app.** In `lib/app/app.dart`:
  - import `package:window_manager/window_manager.dart`, `motion.dart`, `../features/settings/appearance_settings.dart`;
  - aggiungi in fondo al file:

```dart
/// Rilegge "Effetti di animazione" quando la finestra torna in primo piano:
/// un cambio nelle impostazioni di Windows vale senza riavviare l'app.
class _AnimationPreferenceRefresher with WindowListener {
  _AnimationPreferenceRefresher(this._refresh);

  final VoidCallback _refresh;

  @override
  void onWindowFocus() => _refresh();
}
```

  - nello stato: campo `late final _AnimationPreferenceRefresher _refresher;`; in `initState` (dopo `restore`):

```dart
    _refresher = _AnimationPreferenceRefresher(
        () => ref.read(systemAnimationsProvider.notifier).refresh());
    windowManager.addListener(_refresher);
```

  - aggiungi:

```dart
  @override
  void dispose() {
    windowManager.removeListener(_refresher);
    super.dispose();
  }
```

  - in `build`, prima del `return`: `final motion = WfMotion(ref.watch(motionLevelProvider));` e il `builder` diventa:

```dart
      builder: (context, child) => WfMotionScope(
        motion: motion,
        child: UpdateGate(child: child ?? const SizedBox.shrink()),
      ),
```

- [ ] **Step 7: helper dei test.** In `test/support/pump_app.dart`: import `package:wonderflix/app/motion.dart`; `pumpApp` riceve il parametro `MotionLevel motion = MotionLevel.reduced` e il `MaterialApp` ottiene:

```dart
      builder: (context, child) =>
          WfMotionScope(motion: WfMotion(motion), child: child!),
```

- [ ] **Step 8: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 9: commit**

```bash
git add lib/app/app.dart lib/features/settings/appearance_settings_section.dart lib/features/settings/settings_screen.dart l10n/app_it.arb l10n/app_en.arb test/support/pump_app.dart test/app/l10n_plan6a_test.dart test/features/settings/appearance_settings_section_test.dart
git commit -m "feat: add appearance settings and motion scope"
```

---

### Task 4: scroll morbido con la rotella

**Files:**
- Create: `lib/ui/smooth_scroll.dart`
- Test: `test/ui/smooth_scroll_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/smooth_scroll.dart';

void main() {
  const step = 60 * wheelScrollMultiplier;

  Future<SmoothScrollController> pumpList(WidgetTester tester) async {
    final controller = SmoothScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ListView.builder(
        controller: controller,
        itemCount: 100,
        itemExtent: 100,
        itemBuilder: (context, i) => Text('riga $i'),
      ),
    ));
    return controller;
  }

  Future<void> wheel(WidgetTester tester, Finder target, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(target)));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  }

  testWidgets('uno scatto arriva a destinazione in modo animato', (tester) async {
    final controller = await pumpList(tester);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(step));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(step, 0.01));
  });

  testWidgets('gli scatti ravvicinati si sommano', (tester) async {
    final controller = await pumpList(tester);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pump(const Duration(milliseconds: 50));
    await wheel(tester, find.byType(ListView), 60);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(2 * step, 0.01));
  });

  testWidgets('la destinazione resta nei limiti', (tester) async {
    final controller = await pumpList(tester);
    final max = controller.position.maxScrollExtent;
    controller.jumpTo(max - 20);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pumpAndSettle();
    expect(controller.offset, max);
    await wheel(tester, find.byType(ListView), -60);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(max - step, 0.01));
  });

  testWidgets('jumpTo annulla la destinazione in sospeso', (tester) async {
    final controller = await pumpList(tester);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pump(const Duration(milliseconds: 50));
    controller.jumpTo(500);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(500 + step, 0.01));
  });

  testWidgets('un trascinamento annulla la destinazione in sospeso',
      (tester) async {
    final controller = await pumpList(tester);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final afterDrag = controller.offset;
    await wheel(tester, find.byType(ListView), 60);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(afterDrag + step, 0.01));
  });

  testWidgets('rotella verticale sopra una riga orizzontale: scorre la pagina',
      (tester) async {
    final page = SmoothScrollController();
    final row = SmoothScrollController();
    addTearDown(page.dispose);
    addTearDown(row.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ListView(
        controller: page,
        children: [
          SizedBox(
            height: 200,
            child: ListView.builder(
              key: const Key('row'),
              controller: row,
              scrollDirection: Axis.horizontal,
              itemCount: 50,
              itemExtent: 150,
              itemBuilder: (context, i) => Text('card $i'),
            ),
          ),
          for (var i = 0; i < 30; i++) SizedBox(height: 100, child: Text('riga $i')),
        ],
      ),
    ));
    await wheel(tester, find.byKey(const Key('row')), 60);
    await tester.pumpAndSettle();
    expect(page.offset, closeTo(step, 0.01));
    expect(row.offset, 0);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/smooth_scroll_test.dart`
Expected: FAIL (`smooth_scroll.dart` non esiste).

- [ ] **Step 3: implementa**

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';

/// Moltiplicatore dello scatto della rotella: Windows dà circa 60 px
/// (3 righe × 20 px), i browser circa 100. Da ritoccare nella prova.
const wheelScrollMultiplier = 1.6;

/// Durata dell'animazione di uno scatto.
const wheelScrollDuration = Duration(milliseconds: 200);

/// `ScrollController` con la rotella del mouse animata (spec C §5). Il
/// touchpad di precisione (PanZoom) e il trascinamento restano quelli di
/// Flutter.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      SmoothScrollPosition(
        physics: physics,
        context: context,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
        debugLabel: debugLabel,
      );
}

class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double? _target;
  ScrollActivity? _wheelActivity;

  /// Destinazione della rotella ancora in corso. Un trascinamento, un
  /// `jumpTo` o un `animateTo` esterno cambiano l'attività e la annullano.
  double? get _pendingTarget =>
      identical(activity, _wheelActivity) ? _target : null;

  /// Solo per la rotella: Flutter la chiama per `PointerScrollEvent`.
  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      super.pointerScroll(delta);
      return;
    }
    final from = _pendingTarget ?? pixels;
    final target = (from + delta * wheelScrollMultiplier)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
    if (target == from) return;
    _target = target;
    unawaited(animateTo(target,
        duration: wheelScrollDuration, curve: Curves.easeOutCubic));
    _wheelActivity = activity;
  }
}
```

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/ui/smooth_scroll_test.dart`
Expected: PASS. Se `activity` non è accessibile dalla sottoclasse (analyzer), usa il getter protetto esistente di `ScrollPosition` con `// ignore: invalid_use_of_protected_member` solo se l'analyzer lo chiede, e segnalalo.

- [ ] **Step 5: commit**

```bash
git add lib/ui/smooth_scroll.dart test/ui/smooth_scroll_test.dart
git commit -m "feat: add smooth mouse wheel scrolling"
```

---

### Task 5: scroll morbido nelle pagine

**Files:**
- Modify: `lib/ui/media_row.dart`, `lib/features/home/home_screen.dart`, `lib/features/catalog/catalog_screen.dart`, `lib/features/mylist/my_list_screen.dart`, `lib/features/search/search_screen.dart`, `lib/features/settings/settings_screen.dart`
- Test: `test/ui/cards_test.dart`

(La scheda del titolo e la pagina della persona ricevono lo scroll morbido nel Task 10, insieme al volo Hero.)

- [ ] **Step 1: scrivi il test che fallisce.** In `test/ui/cards_test.dart`, nel test `'MediaRow: titolo e frecce'` (o in un nuovo test con la stessa `MediaRow`), aggiungi dopo il `pumpApp`:

```dart
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.controller, isA<SmoothScrollController>());
```

con l'import `package:wonderflix/ui/smooth_scroll.dart`.

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/cards_test.dart`
Expected: FAIL (`ScrollController` semplice).

- [ ] **Step 3: sostituisci i controller**
  - `media_row.dart`: `final _controller = SmoothScrollController();` (import `smooth_scroll.dart`).
  - `catalog_screen.dart`: `final _scroll = SmoothScrollController();` (import `../../ui/smooth_scroll.dart`).
  - `home_screen.dart`: `HomeScreen` diventa `ConsumerStatefulWidget` con `final _scroll = SmoothScrollController();` (liberato in `dispose`), e il `ListView` dei dati riceve `controller: _scroll`. I metodi `_posterRow`/`_landscapeRow` passano nello stato (usano `ref` dello stato). Nello scheletro `_HomeSkeleton` il padding diventa `EdgeInsets.fromLTRB(32, 96, 32, 32)` (la Home ora parte dal bordo della finestra, sotto la barra: Task 7).
  - `my_list_screen.dart`: `MyListScreen` diventa `ConsumerStatefulWidget` con `SmoothScrollController`, passato al `CustomScrollView`.
  - `search_screen.dart`: `SearchScreen` diventa `ConsumerStatefulWidget` con `SmoothScrollController`, passato al `ListView`; i metodi di supporto passano nello stato.
  - `settings_screen.dart`: `SettingsScreen` diventa `ConsumerStatefulWidget` con `SmoothScrollController` passato al `SingleChildScrollView`.

In tutti i casi: `@override void dispose() { _scroll.dispose(); super.dispose(); }`.

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/ui/media_row.dart lib/features/home/home_screen.dart lib/features/catalog/catalog_screen.dart lib/features/mylist/my_list_screen.dart lib/features/search/search_screen.dart lib/features/settings/settings_screen.dart test/ui/cards_test.dart
git commit -m "feat: use smooth scrolling in pages and rows"
```

---

### Task 6: transizioni tra le pagine

**Files:**
- Create: `lib/app/page_transitions.dart`
- Modify: `lib/app/router.dart`
- Test: `test/app/page_transitions_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/page_transitions.dart';

void main() {
  /// Prodotto delle opacità sopra il testo 'pagina'.
  double opacityOf(WidgetTester tester) => tester
      .widgetList<FadeTransition>(find.ancestor(
          of: find.text('pagina'), matching: find.byType(FadeTransition)))
      .fold(1.0, (value, fade) => value * fade.opacity.value);

  Future<void> pumpTransition(WidgetTester tester, MotionLevel level,
      double animation, double secondary) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: pageTransition(
        WfMotion(level),
        AlwaysStoppedAnimation(animation),
        AlwaysStoppedAnimation(secondary),
        const Text('pagina'),
      ),
    ));
  }

  testWidgets('completa: entra dopo che la vecchia è uscita', (tester) async {
    await pumpTransition(tester, MotionLevel.full, 0.2, 0);
    expect(opacityOf(tester), 0);
    await pumpTransition(tester, MotionLevel.full, 1, 0);
    expect(opacityOf(tester), 1);
    final scale = tester.widget<ScaleTransition>(find.ancestor(
        of: find.text('pagina'), matching: find.byType(ScaleTransition)));
    expect(scale.scale.value, 1);
  });

  testWidgets('completa: esce quando un\'altra pagina entra sopra',
      (tester) async {
    await pumpTransition(tester, MotionLevel.full, 1, 0.5);
    expect(opacityOf(tester), 0);
  });

  testWidgets('ridotta: sola dissolvenza lineare', (tester) async {
    await pumpTransition(tester, MotionLevel.reduced, 0.5, 0);
    expect(opacityOf(tester), 0.5);
    expect(find.byType(ScaleTransition), findsNothing);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/page_transitions_test.dart`
Expected: FAIL (file inesistente).

- [ ] **Step 3: implementa** (`lib/app/page_transitions.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'motion.dart';

/// Durata del "fade through" tra le voci della barra: 90 ms di uscita e
/// 210 ms di entrata (spec C §6.1).
const shellTransitionDuration = Duration(milliseconds: 300);

/// Dissolvenza incrociata "fade through": la pagina entra dopo il primo 30%,
/// con una leggera scala; esce nel primo 30% quando un'altra le entra sopra.
/// Con le animazioni ridotte: sola dissolvenza.
Widget pageTransition(WfMotion motion, Animation<double> animation,
    Animation<double> secondaryAnimation, Widget child) {
  if (motion.isReduced) return FadeTransition(opacity: animation, child: child);
  final incoming = CurvedAnimation(
      parent: animation, curve: const Interval(0.3, 1, curve: Curves.easeOut));
  final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Interval(0, 0.3, curve: Curves.easeIn));
  return FadeTransition(
    opacity: ReverseAnimation(outgoing),
    child: FadeTransition(
      opacity: incoming,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1).animate(incoming),
        child: child,
      ),
    ),
  );
}

CustomTransitionPage<void> _page(BuildContext context, GoRouterState state,
    Widget child, Duration fullDuration) {
  final motion = WfMotion.of(context);
  final duration = motion.duration(fullDuration);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        pageTransition(motion, animation, secondaryAnimation, child),
  );
}

/// Pagina di una voce della barra (Home, Film, Serie, …).
Page<void> shellPage(BuildContext context, GoRouterState state, Widget child) =>
    _page(context, state, child, shellTransitionDuration);

/// Scheda del titolo e pagina della persona: dura quanto il volo Hero.
Page<void> detailPage(BuildContext context, GoRouterState state, Widget child) =>
    _page(context, state, child, WfMotion.hero);
```

- [ ] **Step 4: router.** In `lib/app/router.dart` (import `page_transitions.dart`), dentro la `ShellRoute` ogni `builder:` diventa `pageBuilder:` con la stessa pagina:
  - `/home`, `/movies`, `/series`, `/mylist`, `/search`, `/settings`: `pageBuilder: (context, state) => shellPage(context, state, const HomeScreen())` (e così via, con le stesse chiavi di oggi);
  - `/item/:id` e `/person/:id`: `pageBuilder: (context, state) => detailPage(context, state, ItemDetailScreen(...))` / `PersonScreen(...)`, argomenti invariati (il `HeroLaunch` arriva nel Task 8).

- [ ] **Step 5: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde (compresi `test/app/router_test.dart` e i test di navigazione).

- [ ] **Step 6: commit**

```bash
git add lib/app/page_transitions.dart lib/app/router.dart test/app/page_transitions_test.dart
git commit -m "feat: add fade through page transitions"
```

---

### Task 7: barra in alto sovrapposta, sottolineatura, barra scura

**Files:**
- Create: `lib/ui/hover_builder.dart`
- Modify: `lib/app/app_shell.dart`
- Test: `test/app/app_shell_motion_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

void main() {
  final overrides = [
    sessionControllerProvider
        .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    // Nessun elenco dei watch party (né timer).
    watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
    syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
    watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
  ];

  Widget page() => ListView(
        key: const Key('page'),
        children: [
          for (var i = 0; i < 40; i++) SizedBox(height: 100, child: Text('riga $i')),
        ],
      );

  Future<void> pumpShell(WidgetTester tester, String location,
      {MotionLevel motion = MotionLevel.reduced}) async {
    await pumpApp(tester, AppShell(location: location, child: page()),
        overrides: overrides, motion: motion);
    await tester.pumpAndSettle();
  }

  testWidgets('Home e scheda partono dal bordo alto, le altre sotto la barra',
      (tester) async {
    await pumpShell(tester, '/home');
    expect(tester.getTopLeft(find.byKey(const Key('page'))).dy, 0);
    await pumpShell(tester, '/item/m1');
    expect(tester.getTopLeft(find.byKey(const Key('page'))).dy, 0);
    await pumpShell(tester, '/movies');
    expect(tester.getTopLeft(find.byKey(const Key('page'))).dy, shellBarHeight);
  });

  testWidgets('la sottolineatura sta sotto la voce attiva', (tester) async {
    await pumpShell(tester, '/movies', motion: MotionLevel.full);
    final indicator = tester.getRect(find.byKey(const Key('nav-indicator')));
    final movies = tester.getRect(find.byKey(const Key('nav-/movies')));
    expect(indicator.left, closeTo(movies.left, 0.5));
    expect(indicator.width, closeTo(movies.width, 0.5));
  });

  testWidgets('nessuna voce attiva: nessuna sottolineatura', (tester) async {
    await pumpShell(tester, '/item/m1');
    expect(find.byKey(const Key('nav-indicator')), findsNothing);
  });

  testWidgets('la barra si scurisce quando la pagina scorre', (tester) async {
    await pumpShell(tester, '/movies');
    AnimatedOpacity backdrop() =>
        tester.widget<AnimatedOpacity>(find.byKey(const Key('shell-bar-backdrop')));
    expect(backdrop().opacity, 0);
    await tester.drag(find.byKey(const Key('page')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(backdrop().opacity, 1);
    await tester.drag(find.byKey(const Key('page')), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(backdrop().opacity, 0);
  });

  testWidgets('voce della barra oro al passaggio del mouse', (tester) async {
    await pumpShell(tester, '/home');
    Color labelColor() =>
        tester.widget<Text>(find.text('Film')).style!.color!;
    expect(labelColor(), WfColors.cream);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Film')));
    await tester.pumpAndSettle();
    expect(labelColor(), WfColors.gold);
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/app_shell_motion_test.dart`
Expected: FAIL (`shellBarHeight`, chiavi e comportamento assenti).

- [ ] **Step 3: `HoverBuilder`** (`lib/ui/hover_builder.dart`)

```dart
import 'package:flutter/widgets.dart';

/// Costruisce [builder] sapendo se il mouse è sopra.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({super.key, required this.builder, this.cursor = MouseCursor.defer});

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: widget.builder(context, _hovered),
      );
}
```

- [ ] **Step 4: `AppShell`.** In `lib/app/app_shell.dart` (import `dart:ui` per `ImageFilter`, `motion.dart`, `../ui/hover_builder.dart`):

  - aggiungi in cima, dopo gli import:

```dart
/// Altezza della barra in alto.
const shellBarHeight = 64.0;

/// Pagine con lo sfondo fino al bordo alto della finestra, sotto la barra
/// (spec C §11.1). Le altre iniziano sotto la barra, come prima.
bool isFullBleed(String location) =>
    location == '/home' || location.startsWith('/item/');
```

  - sostituisci la classe `AppShell` con:

```dart
/// Struttura comune alle schermate autenticate: contenuto con la barra
/// superiore sovrapposta.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// La pagina è scorsa: la barra diventa scura e sfocata.
  bool _scrolled = false;

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Una pagina nuova parte dall'alto.
    if (oldWidget.location != widget.location) _scrolled = false;
  }

  bool _onScroll(ScrollNotification notification) {
    // Solo lo scroll verticale della pagina, non le righe orizzontali.
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical) {
      final scrolled = notification.metrics.pixels > 4;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Tiene aperto il WebSocket degli eventi finché si è autenticati.
    ref.watch(serverEventsBindingProvider);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionSignedIn ? session.user : null;
    final l = AppLocalizations.of(context);
    final fade = WfMotion.of(context).duration(WfMotion.medium);
    final fullBleed = isFullBleed(widget.location);

    return Scaffold(
      body: BackNavigationHandler(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(top: fullBleed ? 0 : shellBarHeight),
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: widget.child,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: shellBarHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Pagine a tutta altezza: velo in cima per leggere la barra.
                  AnimatedOpacity(
                    opacity: fullBleed && !_scrolled ? 1 : 0,
                    duration: fade,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xB30A0A0A), Color(0x000A0A0A)],
                        ),
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    key: const Key('shell-bar-backdrop'),
                    opacity: _scrolled ? 1 : 0,
                    duration: fade,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: const ColoredBox(color: Color(0xBF0A0A0A)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const _BackButton(),
                        Image.asset('assets/brand/logo.png', height: 40),
                        const SizedBox(width: 32),
                        _NavBar(location: widget.location, items: [
                          (label: l.navHome, route: '/home', icon: null),
                          (label: l.navMovies, route: '/movies', icon: null),
                          (label: l.navSeries, route: '/series', icon: null),
                          (label: l.navMyList, route: '/mylist', icon: null),
                          (
                            label: l.navSearch,
                            route: '/search',
                            icon: LucideIcons.search
                          ),
                        ]),
                        const Spacer(),
                        const WatchPartyButton(),
                        const SizedBox(width: 16),
                        if (user != null) _UserMenu(user: user),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Invito a un watch party appena nato (spec B §5.8).
            const Positioned(top: 72, right: 24, child: WatchPartyInviteCard()),
          ],
        ),
      ),
    );
  }
}

typedef _NavEntry = ({String label, String route, IconData? icon});

/// Voci della barra con un'unica sottolineatura oro che scorre sotto
/// quella attiva (spec C §11.1).
class _NavBar extends StatefulWidget {
  const _NavBar({required this.location, required this.items});

  final String location;
  final List<_NavEntry> items;

  @override
  State<_NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<_NavBar> {
  final _stackKey = GlobalKey();
  final _itemKeys = <String, GlobalKey>{};

  /// Posizione della voce attiva nella barra; `null` = nessuna.
  Rect? _active;

  /// Ultima posizione nota, per far sparire la linea dov'era.
  Rect? _last;

  String? get _activeRoute {
    for (final item in widget.items) {
      if (widget.location.startsWith(item.route)) return item.route;
    }
    return null;
  }

  void _measure() {
    if (!mounted) return;
    final route = _activeRoute;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final box = route == null
        ? null
        : _itemKeys[route]?.currentContext?.findRenderObject() as RenderBox?;
    Rect? rect;
    if (stack != null && box != null && box.hasSize) {
      final offset = box.localToGlobal(Offset.zero, ancestor: stack);
      rect = offset & box.size;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final shown = _active ?? _last;
    return Stack(
      key: _stackKey,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in widget.items) ...[
              KeyedSubtree(
                key: Key('nav-${item.route}'),
                child: _NavItem(
                  key: _itemKeys.putIfAbsent(item.route, GlobalKey.new),
                  label: item.label,
                  icon: item.icon,
                  active: widget.location.startsWith(item.route),
                  onTap: () => context.go(item.route),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
        if (shown != null)
          AnimatedPositioned(
            key: const Key('nav-indicator'),
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

  - la `GlobalKey` del `_NavItem` serve a misurarlo; la `Key('nav-<route>')` del `KeyedSubtree` serve ai test.

  - `_BackButton`: l'`IconButton` riceve lo stile con l'oro al passaggio del mouse e l'icona senza colore fisso:

```dart
            ? IconButton(
                tooltip: AppLocalizations.of(context).navBack,
                onPressed: router.pop,
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.hovered)
                          ? WfColors.gold
                          : WfColors.cream),
                ),
                icon: const Icon(LucideIcons.arrowLeft),
              )
```

  - sostituisci `_NavItem` con (niente più bordo proprio, niente padding esterno: la spaziatura è nel `_NavBar`):

```dart
class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final symbol = icon;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) {
        final color = active || hovered ? WfColors.gold : WfColors.cream;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (symbol != null) ...[
                  Icon(symbol, size: 16, color: color),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

  - `_UserMenu`: il `child` del `PopupMenuButton` diventa un `HoverBuilder` che colora il nome d'oro al passaggio del mouse:

```dart
      child: HoverBuilder(
        builder: (context, hovered) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: WfColors.gold,
              child: Text(initial,
                  style: const TextStyle(
                      color: WfColors.bg, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(user.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: hovered ? WfColors.gold : WfColors.cream)),
            ),
          ],
        ),
      ),
```

- [ ] **Step 5: verifica**

Run: `flutter test test/app/app_shell_motion_test.dart test/app/app_shell_test.dart test/app/app_shell_back_button_test.dart`
Expected: PASS. Poi `flutter analyze` e `flutter test`: tutto verde. Se qualche test esistente cercava un `InkWell` nelle voci della barra o il bordo, aggiornalo al nuovo `GestureDetector` e segnalalo.

- [ ] **Step 6: commit**

```bash
git add lib/ui/hover_builder.dart lib/app/app_shell.dart test/app/app_shell_motion_test.dart
git commit -m "feat: overlay top bar with sliding indicator and blur"
```

---

### Task 8: tag Hero, dati del volo, navigazione

**Files:**
- Create: `lib/app/hero_launch.dart`
- Modify: `lib/app/navigation.dart`, `lib/app/router.dart`
- Test: `test/app/hero_launch_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

import '../support/library_fakes.dart';
import '../support/pump_app.dart';

void main() {
  test('WfHeroTag: uguale solo con stesso titolo e stessa sorgente', () {
    expect(const WfHeroTag('m1', 'home.latest.0'),
        const WfHeroTag('m1', 'home.latest.0'));
    expect(const WfHeroTag('m1', 'home.latest.0') == const WfHeroTag('m1', 'home.latest.1'),
        isFalse);
    expect(const WfHeroTag('m1', 'a').hashCode, const WfHeroTag('m1', 'a').hashCode);
  });

  testWidgets('WfHero: Hero solo con tag e animazioni complete', (tester) async {
    const tag = WfHeroTag('m1', 'x');
    Widget tree(MotionLevel level, WfHeroTag? heroTag) => Directionality(
          textDirection: TextDirection.ltr,
          child: WfMotionScope(
            motion: WfMotion(level),
            child: WfHero(tag: heroTag, child: const SizedBox()),
          ),
        );
    await tester.pumpWidget(tree(MotionLevel.full, tag));
    expect(tester.widget<Hero>(find.byType(Hero)).tag, tag);
    await tester.pumpWidget(tree(MotionLevel.reduced, tag));
    expect(find.byType(Hero), findsNothing);
    await tester.pumpWidget(tree(MotionLevel.full, null));
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('volo: dissolvenza dalla card alla pagina', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        Hero(tag: 'card', child: Text('card')),
        Hero(tag: 'pagina', child: Text('pagina')),
      ]),
    ));
    final card = tester.element(find.byType(Hero).first);
    final page = tester.element(find.byType(Hero).last);
    Future<void> flight(double t, HeroFlightDirection direction) async {
      final from = direction == HeroFlightDirection.push ? card : page;
      final to = direction == HeroFlightDirection.push ? page : card;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: wfHeroFlight(card, AlwaysStoppedAnimation(t), direction, from, to),
      ));
    }

    double opacity(String text) => tester
        .widget<Opacity>(find.ancestor(of: find.text(text), matching: find.byType(Opacity)))
        .opacity;

    await flight(0, HeroFlightDirection.push);
    expect(opacity('card'), 1);
    expect(opacity('pagina'), 0);
    await flight(1, HeroFlightDirection.push);
    expect(opacity('card'), 0);
    expect(opacity('pagina'), 1);
    // Indietro: l'animazione scende da 1 a 0, la pagina sfuma nella card.
    await flight(1, HeroFlightDirection.pop);
    expect(opacity('pagina'), 1);
    await flight(0, HeroFlightDirection.pop);
    expect(opacity('card'), 1);
  });

  testWidgets('openItem con sorgente passa HeroLaunch alla scheda',
      (tester) async {
    Object? extra;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => TextButton(
          onPressed: () => openItem(context, testItem(id: 'm1'),
              heroSource: 'home.latest.2'),
          child: const Text('apri'),
        ),
      ),
      GoRoute(
        path: '/item/:id',
        builder: (context, state) {
          extra = state.extra;
          return const Text('scheda');
        },
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(testAppConfig)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    final launch = extra! as HeroLaunch;
    expect(launch.tag, const WfHeroTag('m1', 'home.latest.2'));
    expect(launch.image!.url, contains('/Items/m1/Images/Backdrop/0'));
    expect(launch.fallback!.url, contains('/Items/m1/Images/Primary'));
    expect(launch.title, 'Dune: Parte Due');
  });

  testWidgets('openItem senza sorgente: nessun HeroLaunch', (tester) async {
    Object? extra = 'non toccato';
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => TextButton(
          onPressed: () => openItem(context, testItem(id: 'm1', kind: ItemKind.movie)),
          child: const Text('apri'),
        ),
      ),
      GoRoute(
        path: '/item/:id',
        builder: (context, state) {
          extra = state.extra;
          return const Text('scheda');
        },
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(testAppConfig)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(extra, isNull);
  });
}
```

(`testAppConfig` viene da `test/support/pump_app.dart`; `imageUrlsProvider` dipende solo da `appConfigProvider`.)

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/hero_launch_test.dart`
Expected: FAIL (file inesistente, `heroSource` sconosciuto).

- [ ] **Step 3: implementa** (`lib/app/hero_launch.dart`)

```dart
import 'package:flutter/material.dart';

import '../core/jellyfin/image_urls.dart';
import 'motion.dart';

/// Tag del volo Hero: il titolo e la card da cui parte (riga o griglia +
/// posizione). Due card dello stesso titolo nella stessa pagina non vanno
/// in conflitto (spec C §6.2).
@immutable
class WfHeroTag {
  const WfHeroTag(this.itemId, this.source);

  final String itemId;
  final String source;

  @override
  bool operator ==(Object other) =>
      other is WfHeroTag && other.itemId == itemId && other.source == source;

  @override
  int get hashCode => Object.hash(itemId, source);

  @override
  String toString() => 'WfHeroTag($itemId, $source)';
}

/// Dati passati alla pagina aperta da una card (`extra` di go_router): il
/// tag e le immagini già note, per disegnare subito la destinazione del volo
/// mentre la pagina carica.
@immutable
class HeroLaunch {
  const HeroLaunch({required this.tag, this.image, this.fallback, this.title});

  final WfHeroTag tag;

  /// Sfondo (scheda) o foto (persona).
  final ImageRef? image;

  /// Locandina, se manca lo sfondo.
  final ImageRef? fallback;
  final String? title;
}

/// Volo con dissolvenza: parte dall'immagine della card e arriva a quella
/// della pagina (da una locandina 2:3 a uno sfondo 16:9); gli angoli passano
/// da 6 a 0. Tornando indietro fa il percorso inverso.
Widget wfHeroFlight(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final from = (fromHeroContext.widget as Hero).child;
  final to = (toHeroContext.widget as Hero).child;
  final push = direction == HeroFlightDirection.push;
  final card = push ? from : to;
  final page = push ? to : from;
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = WfMotion.emphasized.transform(animation.value.clamp(0.0, 1.0));
      return ClipRRect(
        borderRadius: BorderRadius.circular(6 * (1 - t)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: 1 - t, child: card),
            Opacity(opacity: t, child: page),
          ],
        ),
      );
    },
  );
}

/// [Hero] con [wfHeroFlight], solo se c'è un tag e le animazioni sono
/// complete; altrimenti il solo [child].
class WfHero extends StatelessWidget {
  const WfHero({super.key, required this.tag, required this.child});

  final WfHeroTag? tag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final heroTag = tag;
    if (heroTag == null || WfMotion.of(context).isReduced) return child;
    return Hero(tag: heroTag, flightShuttleBuilder: wfHeroFlight, child: child);
  }
}
```

- [ ] **Step 4: navigazione.** In `lib/app/navigation.dart` (import `package:flutter_riverpod/flutter_riverpod.dart`, `../features/library/library_providers.dart`, `hero_launch.dart`) sostituisci `openItem` e `openPerson`:

```dart
/// Apre [item]. Con [heroSource] (la card cliccata) la pagina riceve un
/// [HeroLaunch] e l'immagine vola nella testata.
void openItem(BuildContext context, JellyfinItem item, {String? heroSource}) {
  HeroLaunch? launch;
  if (heroSource != null) {
    final urls = ProviderScope.containerOf(context, listen: false)
        .read(imageUrlsProvider);
    launch = HeroLaunch(
      tag: WfHeroTag(item.id, heroSource),
      image: urls.backdrop(item),
      fallback: urls.poster(item),
      title: item.name,
    );
  }
  unawaited(context.push(itemRoute(item), extra: launch));
}

/// Apre la pagina di [person]; con [heroSource] la foto vola dal cast.
void openPerson(BuildContext context, PersonRef person, {String? heroSource}) {
  HeroLaunch? launch;
  if (heroSource != null) {
    final urls = ProviderScope.containerOf(context, listen: false)
        .read(imageUrlsProvider);
    launch = HeroLaunch(
      tag: WfHeroTag(person.id, heroSource),
      image: urls.person(person),
      title: person.name,
    );
  }
  unawaited(context.push('/person/${person.id}', extra: launch));
}
```

(import `dart:async` per `unawaited`. Oggi le due funzioni restituiscono il `Future` di `push` con `=>`; se qualche chiamante usava quel valore, l'analyzer lo segnala: adatta il chiamante e segnalalo.)

- [ ] **Step 5: router.** In `lib/app/router.dart` (import `hero_launch.dart`) la rotta `/item/:id` passa `launch: state.extra is HeroLaunch ? state.extra as HeroLaunch : null` a `ItemDetailScreen`, e `/person/:id` lo stesso a `PersonScreen`. I due costruttori ricevono il parametro nel Task 10: in questo task aggiungi solo il campo opzionale `final HeroLaunch? launch;` (con `this.launch` nel costruttore) a `ItemDetailScreen` e `PersonScreen`, senza usarlo.

- [ ] **Step 6: verifica**

Run: `flutter test test/app/hero_launch_test.dart`, poi `flutter analyze` e `flutter test`
Expected: PASS, nessun problema, tutto verde.

- [ ] **Step 7: commit**

```bash
git add lib/app/hero_launch.dart lib/app/navigation.dart lib/app/router.dart lib/features/detail/item_detail_screen.dart lib/features/person/person_screen.dart test/app/hero_launch_test.dart
git commit -m "feat: add hero tags and launch data for detail pages"
```

---

### Task 9: card con Hero e apertura di default

**Files:**
- Modify: `lib/ui/poster_card.dart`, `lib/ui/landscape_card.dart`
- Modify: `lib/features/home/home_screen.dart`, `lib/features/detail/detail_rows.dart`, `lib/features/catalog/catalog_screen.dart`, `lib/features/mylist/my_list_screen.dart`, `lib/features/person/person_screen.dart`, `lib/features/search/search_screen.dart`
- Test: `test/ui/cards_test.dart`

- [ ] **Step 1: scrivi il test che fallisce.** In `test/ui/cards_test.dart` (import `package:wonderflix/app/hero_launch.dart`, `package:wonderflix/app/motion.dart`):

```dart
  testWidgets('PosterCard con sorgente: Hero sulla locandina', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: PosterCard(
            item: testItem(id: 'm1'), width: 160, heroSource: 'home.latest.0'),
      ),
      overrides: [signedIn],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag,
        const WfHeroTag('m1', 'home.latest.0'));
  });

  testWidgets('PosterCard senza sorgente o con animazioni ridotte: niente Hero',
      (tester) async {
    await pumpApp(
      tester,
      Center(child: PosterCard(item: testItem(), width: 160, onTap: () {})),
      overrides: [signedIn],
      motion: MotionLevel.full,
    );
    expect(find.byType(Hero), findsNothing);
    await pumpApp(
      tester,
      Center(
        child: PosterCard(item: testItem(), width: 160, heroSource: 'x.0'),
      ),
      overrides: [signedIn],
    );
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('LandscapeCard con sorgente: Hero sull\'immagine', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: LandscapeCard(item: testItem(id: 'm1'), heroSource: 'home.resume.3'),
      ),
      overrides: [signedIn],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag,
        const WfHeroTag('m1', 'home.resume.3'));
  });
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/cards_test.dart`
Expected: FAIL (`heroSource` sconosciuto, `onTap` obbligatorio).

- [ ] **Step 3: card.** In `poster_card.dart` e `landscape_card.dart` (import `../app/hero_launch.dart`, `../app/navigation.dart`):
  - `onTap` diventa opzionale (`this.onTap`, `final VoidCallback? onTap;`) e si aggiunge:

```dart
  /// Card da cui parte il volo Hero (per esempio `home.latestMovies.3`).
  /// Senza [onTap], il clic apre la scheda con il volo da qui.
  final String? heroSource;
```

  - il `GestureDetector` usa:

```dart
          onTap: widget.onTap ??
              () => openItem(context, widget.item, heroSource: widget.heroSource),
```

  - l'immagine nello `Stack` (`WfImage(image: …poster(item))` e `WfImage(image: …landscape(item))`) viene avvolta:

```dart
                        WfHero(
                          tag: widget.heroSource == null
                              ? null
                              : WfHeroTag(item.id, widget.heroSource!),
                          child: WfImage(
                              image: ref.watch(imageUrlsProvider).poster(item)),
                        ),
```

  (per `LandscapeCard` con `.landscape(item)`).

- [ ] **Step 4: chiamanti.** Al posto di `onTap: () => openItem(context, …)` le card ricevono `heroSource` (sorgente unica nella pagina; contiene l'id della pagina quando la pagina è una scheda o una persona):
  - `home_screen.dart`: `_posterRow` e `_landscapeRow` ricevono `String source`; le card `heroSource: '$source.$i'`. Sorgenti: `home.resume`, `home.nextUp`, `home.latestMovies`, `home.latestSeries`, `home.favorites`.
  - `detail_rows.dart` `SimilarRow`: `heroSource: 'similar.$itemId.$i'`.
  - `catalog_screen.dart`: `heroSource: 'catalog.${widget.kind.name}.$i'`.
  - `my_list_screen.dart`: `heroSource: 'mylist.$i'`.
  - `person_screen.dart`: `heroSource: 'person.$personId.$i'` (o `widget.personId` se la classe è già stateful).
  - `search_screen.dart`: `_posterSection` riceve `String source` (`search.movies`, `search.series`) e usa `for (final (i, item) in items.indexed) PosterCard(item: item, width: 150, heroSource: '$source.$i')`.
  - `CastRow` in `detail_rows.dart`: riceve `required this.itemId` (l'id della scheda; aggiorna i due chiamanti in `movie_detail_view.dart` e `series_detail_view.dart`: `CastRow(itemId: item.id, …)` / `CastRow(itemId: series.id, …)`); il clic diventa `openPerson(context, person, heroSource: 'cast.$itemId.$i')` e il `SizedBox` 90×90 dentro il `ClipOval` viene avvolto in `WfHero(tag: WfHeroTag(person.id, 'cast.$itemId.$i'), child: …)`.

- [ ] **Step 5: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 6: commit**

```bash
git add lib/ui/poster_card.dart lib/ui/landscape_card.dart lib/features/home/home_screen.dart lib/features/detail/detail_rows.dart lib/features/detail/movie_detail_view.dart lib/features/detail/series_detail_view.dart lib/features/catalog/catalog_screen.dart lib/features/mylist/my_list_screen.dart lib/features/person/person_screen.dart lib/features/search/search_screen.dart test/ui/cards_test.dart
git commit -m "feat: fly card images into detail pages"
```

---

### Task 10: destinazione del volo (scheda e persona)

**Files:**
- Create: `lib/features/detail/detail_backdrop.dart`
- Modify: `lib/features/detail/detail_header.dart`, `lib/features/detail/item_detail_screen.dart`, `lib/features/detail/movie_detail_view.dart`, `lib/features/detail/series_detail_view.dart`, `lib/features/person/person_screen.dart`
- Test: `test/features/detail/detail_hero_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/detail/detail_providers.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/person/person_screen.dart';
import 'package:wonderflix/ui/backdrop_image.dart';
import 'package:wonderflix/ui/smooth_scroll.dart';
import 'package:wonderflix/ui/states.dart';

import '../../support/pump_app.dart';

void main() {
  const launch = HeroLaunch(
    tag: WfHeroTag('m1', 'home.latest.0'),
    image: ImageRef('https://media.example.com/Items/m1/Images/Backdrop/0'),
    title: 'Dune',
  );

  testWidgets('scheda in caricamento: sfondo e Hero già presenti',
      (tester) async {
    final pending = Completer<JellyfinItem>();
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1', launch: launch)),
      overrides: [itemProvider('m1').overrideWith((ref) => pending.future)],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag, launch.tag);
    expect(find.byType(BackdropImage), findsOneWidget);
    expect(find.byType(LoadingView), findsOneWidget);
  });

  testWidgets('scheda in caricamento senza volo: solo l\'indicatore',
      (tester) async {
    final pending = Completer<JellyfinItem>();
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
      overrides: [itemProvider('m1').overrideWith((ref) => pending.future)],
      motion: MotionLevel.full,
    );
    expect(find.byType(Hero), findsNothing);
    expect(find.byType(BackdropImage), findsNothing);
    expect(find.byType(LoadingView), findsOneWidget);
  });

  testWidgets('persona in caricamento: foto (Hero) e nome già presenti',
      (tester) async {
    final pending = Completer<JellyfinItem>();
    const personLaunch = HeroLaunch(
      tag: WfHeroTag('p9', 'cast.m1.0'),
      image: ImageRef('https://media.example.com/Items/p9/Images/Primary'),
      title: 'Zendaya',
    );
    await pumpApp(
      tester,
      const Scaffold(body: PersonScreen(personId: 'p9', launch: personLaunch)),
      overrides: [itemProvider('p9').overrideWith((ref) => pending.future)],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag, personLaunch.tag);
    expect(find.text('ZENDAYA'), findsOneWidget);
    expect(find.byType(LoadingView), findsOneWidget);
    final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    expect(scroll.controller, isA<SmoothScrollController>());
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/detail/detail_hero_test.dart`
Expected: FAIL.

- [ ] **Step 3: altezza della testata.** In `detail_header.dart` aggiungi in cima:

```dart
/// Altezza della testata della scheda (sfondo, logo, dati, azioni).
const detailHeaderHeight = 560.0;
```

  e `SizedBox(height: 560, …)` diventa `SizedBox(height: detailHeaderHeight, …)`. **Togli** `BackdropImage(backdrop: urls.backdrop(item), fallback: urls.poster(item)),` dallo `Stack`: lo sfondo è ora un livello dietro alla pagina (`DetailBackdrop`); restano le due sfumature e il contenuto. Togli l'import di `backdrop_image.dart` se resta inutilizzato.

- [ ] **Step 4: livello dello sfondo** (`lib/features/detail/detail_backdrop.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/hero_launch.dart';
import '../../core/jellyfin/item_models.dart';
import '../../ui/backdrop_image.dart';
import '../library/library_providers.dart';

/// Sfondo della scheda, dietro al contenuto. Segue lo scroll della pagina
/// (nel piano 6b diventerà la parallasse). Mentre la scheda carica usa le
/// immagini di [launch]: è la destinazione del volo Hero, e deve esserci
/// dal primo fotogramma (spec C §6.2).
class DetailBackdrop extends ConsumerWidget {
  const DetailBackdrop({
    super.key,
    required this.item,
    required this.launch,
    required this.controller,
  });

  /// `null` mentre la scheda carica.
  final JellyfinItem? item;
  final HeroLaunch? launch;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    final current = item;
    // Stesso URL della card (`openItem` usa `urls.backdrop`): all'arrivo dei
    // dati l'immagine non cambia.
    final image = BackdropImage(
      backdrop: current != null ? urls.backdrop(current) : launch?.image,
      fallback: current != null ? urls.poster(current) : launch?.fallback,
    );
    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, controller.hasClients ? -controller.offset : 0),
          child: child,
        ),
        child: WfHero(tag: launch?.tag, child: image),
      ),
    );
  }
}
```

- [ ] **Step 5: viste con controller.** `MovieDetailView` e `SeriesDetailView` ricevono `this.controller` (`final ScrollController? controller;`) e il loro `ListView` riceve `controller: controller`.

- [ ] **Step 6: `ItemDetailScreen`** diventa stateful (import `dart:async` non serve; import `../../app/hero_launch.dart`, `../../ui/smooth_scroll.dart`, `detail_backdrop.dart`, `detail_header.dart`):

```dart
class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen(
      {super.key, required this.itemId, this.seasonId, this.launch});

  final String itemId;

  /// Stagione da mostrare aperta (solo per le serie).
  final String? seasonId;

  /// Dati del volo Hero dalla card cliccata (`extra` di go_router).
  final HeroLaunch? launch;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(itemProvider(widget.itemId));
    final launch = widget.launch;
    final item = async.value;
    final content = async.when(
      loading: () => launch == null
          ? const LoadingView()
          : ListView(
              controller: _scroll,
              children: const [
                SizedBox(height: detailHeaderHeight),
                Padding(padding: EdgeInsets.all(32), child: LoadingView()),
              ],
            ),
      error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(itemProvider(widget.itemId))),
      data: (item) => item.kind == ItemKind.series
          ? SeriesDetailView(
              series: item,
              initialSeasonId: widget.seasonId,
              controller: _scroll)
          : MovieDetailView(item: item, controller: _scroll),
    );
    if (item == null && launch == null) return content;
    if (async.hasError && item == null) return content;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: detailHeaderHeight,
          child: DetailBackdrop(item: item, launch: launch, controller: _scroll),
        ),
        Positioned.fill(child: content),
      ],
    );
  }
}
```

(`async.value` in Riverpod 3 è `null` durante il primo caricamento e resta il valore precedente durante un aggiornamento: la testata non sparisce.)

- [ ] **Step 7: `PersonScreen`** diventa stateful con `SmoothScrollController`, e la testata (foto + nome + biografia) sta **sempre** nella stessa posizione dell'albero, così il `Hero` della foto esiste già durante il caricamento. Struttura del `build`:

```dart
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(itemProvider(widget.personId));
    final person = async.value;
    final launch = widget.launch;
    if (person == null && (launch == null || async.hasError)) {
      return async.hasError
          ? ErrorView(
              error: async.error!,
              onRetry: () => ref.invalidate(itemProvider(widget.personId)))
          : const LoadingView();
    }
    final photo = person != null
        ? ref.watch(imageUrlsProvider).poster(person)
        : launch!.image;
    final name = person?.name ?? launch?.title ?? '';
    final bio = person?.overview;
    final films = person == null ? null : ref.watch(filmographyProvider(widget.personId));
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: WfHero(
                    tag: launch?.tag,
                    child: SizedBox(
                      width: 200,
                      height: 300,
                      child: WfImage(image: photo, fallbackIcon: LucideIcons.user),
                    ),
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.toUpperCase(), style: WfText.display(48)),
                      if (bio != null) ...[
                        const SizedBox(height: 12),
                        Text(bio,
                            maxLines: 10,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.5)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (films == null)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(32), child: LoadingView()),
          )
        else ...[
          // Titolo "Sul server" e griglia della filmografia: invariati rispetto
          // a oggi (films.when con loading/error/data), con le card che
          // ricevono heroSource: 'person.${widget.personId}.$i' (Task 9).
        ],
      ],
    );
  }
```

Nel ramo `else` sposta, **senza cambiarli**, il `SliverPadding` con `l.personOnServer` e lo `...films.when(...)` di oggi (con `widget.personId` al posto di `personId`). Import: `../../app/hero_launch.dart`, `../../ui/smooth_scroll.dart`.

- [ ] **Step 8: verifica**

Run: `flutter test test/features/detail/detail_hero_test.dart`, poi `flutter analyze` e `flutter test`
Expected: PASS, nessun problema, tutto verde (compresi `movie_detail_test`, `series_detail_test`, `person_screen_test`).

- [ ] **Step 9: commit**

```bash
git add lib/features/detail/detail_backdrop.dart lib/features/detail/detail_header.dart lib/features/detail/item_detail_screen.dart lib/features/detail/movie_detail_view.dart lib/features/detail/series_detail_view.dart lib/features/person/person_screen.dart test/features/detail/detail_hero_test.dart
git commit -m "feat: show hero destinations while detail pages load"
```

---

### Task 11: pulsanti e icone vivi

**Files:**
- Modify: `lib/ui/wf_buttons.dart`
- Test: `test/ui/wf_buttons_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../support/pump_app.dart';

void main() {
  double scaleOf(WidgetTester tester, Finder target) => tester
      .widget<AnimatedScale>(
          find.ancestor(of: target, matching: find.byType(AnimatedScale)).first)
      .scale;

  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
    return mouse;
  }

  testWidgets('WfButton: scala e alone oro al passaggio del mouse',
      (tester) async {
    await pumpApp(
      tester,
      Center(
        child: WfButton.primary(
            label: 'Riproduci', icon: LucideIcons.play, onPressed: () {}),
      ),
      motion: MotionLevel.full,
    );
    final label = find.text('Riproduci');
    expect(scaleOf(tester, label), 1);
    await hover(tester, label);
    expect(scaleOf(tester, label), 1.03);
    final glow = tester
        .widget<AnimatedContainer>(find.byKey(const Key('wf-button-glow')));
    expect((glow.decoration! as BoxDecoration).boxShadow, isNotEmpty);
  });

  testWidgets('WfButton ridotto: alone sì, scala no', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: WfButton.secondary(
            label: 'Dettagli', icon: LucideIcons.info, onPressed: () {}),
      ),
    );
    final label = find.text('Dettagli');
    await hover(tester, label);
    expect(scaleOf(tester, label), 1);
  });

  testWidgets('WfButton disattivato: nessun effetto', (tester) async {
    await pumpApp(
      tester,
      const Center(
        child: WfButton.primary(
            label: 'Riproduci', icon: LucideIcons.play, onPressed: null),
      ),
      motion: MotionLevel.full,
    );
    final label = find.text('Riproduci');
    await hover(tester, label);
    expect(scaleOf(tester, label), 1);
  });

  Widget toggleHost() {
    var selected = false;
    return Center(
      child: StatefulBuilder(
        builder: (context, setState) => WfIconToggle(
          icon: LucideIcons.heart,
          selected: selected,
          tooltip: 'La mia lista',
          onPressed: () => setState(() => selected = !selected),
        ),
      ),
    );
  }

  double popScale(WidgetTester tester) => tester
      .widget<ScaleTransition>(find.descendant(
          of: find.byType(WfIconToggle), matching: find.byType(ScaleTransition)))
      .scale
      .value;

  testWidgets('WfIconToggle: "pop" quando si attiva', (tester) async {
    await pumpApp(tester, toggleHost(), motion: MotionLevel.full);
    await tester.tap(find.byType(WfIconToggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(popScale(tester), greaterThan(1));
    await tester.pumpAndSettle();
    expect(popScale(tester), 1);
    // Disattivando: nessun pop.
    await tester.tap(find.byType(WfIconToggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(popScale(tester), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('WfIconToggle ridotto: nessun pop', (tester) async {
    await pumpApp(tester, toggleHost());
    await tester.tap(find.byType(WfIconToggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(popScale(tester), 1);
    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/ui/wf_buttons_test.dart`
Expected: FAIL (nessun `AnimatedScale`/`ScaleTransition`).

- [ ] **Step 3: implementa.** In `lib/ui/wf_buttons.dart` (import `../app/motion.dart`):
  - `WfButton` diventa `StatefulWidget` (stessi costruttori `const WfButton.primary`/`.secondary` e stessi campi). Lo stato:

```dart
class _WfButtonState extends State<WfButton> {
  bool _hovered = false;
  bool _pressed = false;

  Widget _button() {
    const size = Size(0, 44);
    const padding = EdgeInsets.symmetric(horizontal: 20);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
    if (widget.primary) {
      return FilledButton.icon(
        onPressed: widget.onPressed,
        autofocus: widget.autofocus,
        style: FilledButton.styleFrom(
            minimumSize: size, padding: padding, shape: shape),
        icon: Icon(widget.icon, size: 18),
        label: Text(widget.label),
      );
    }
    return OutlinedButton.icon(
      onPressed: widget.onPressed,
      autofocus: widget.autofocus,
      style: OutlinedButton.styleFrom(
        minimumSize: size,
        padding: padding,
        shape: shape,
        foregroundColor: WfColors.cream,
        side: const BorderSide(color: WfColors.border),
      ),
      icon: Icon(widget.icon, size: 18),
      label: Text(widget.label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final enabled = widget.onPressed != null;
    final hovered = enabled && _hovered;
    // Spec C §11.2: alone oro e scala 1,03 al passaggio, 0,97 al clic; con
    // le animazioni ridotte niente scala.
    final scale = !enabled || motion.isReduced
        ? 1.0
        : _pressed
            ? 0.97
            : hovered
                ? 1.03
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
            key: const Key('wf-button-glow'),
            duration: WfMotion.fast,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: hovered
                  ? [
                      BoxShadow(
                          color: WfColors.gold.withValues(alpha: 0.3),
                          blurRadius: 18),
                    ]
                  : const [],
            ),
            child: _button(),
          ),
        ),
      ),
    );
  }
}
```

  - `WfIconToggle` diventa `StatefulWidget` (stessi campi) con `SingleTickerProviderStateMixin`:

```dart
class _WfIconToggleState extends State<WfIconToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: WfMotion.medium);

  /// 1 → 1,3 → 1 (spec C §11.2).
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: WfMotion.bounce)),
        weight: 60),
  ]).animate(_pop);

  @override
  void didUpdateWidget(WfIconToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected &&
        widget.selected &&
        !WfMotion.of(context).isReduced) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return ScaleTransition(
      scale: _scale,
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        isSelected: selected,
        style: IconButton.styleFrom(
          fixedSize: const Size(44, 44),
          foregroundColor: selected ? WfColors.gold : WfColors.cream,
          // "Riempimento": fondo oro tenue quando è attivo.
          backgroundColor: selected
              ? WfColors.gold.withValues(alpha: 0.15)
              : Colors.transparent,
          side: BorderSide(color: selected ? WfColors.gold : WfColors.border),
        ),
        icon: Icon(widget.icon, size: 20),
      ),
    );
  }
}
```

  (`_scale` a riposo vale 1: `TweenSequence` a 0 dà l'inizio della prima tappa.)

- [ ] **Step 4: verifica**

Run: `flutter test test/ui/wf_buttons_test.dart`, poi `flutter analyze` e `flutter test`
Expected: PASS, nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/ui/wf_buttons.dart test/ui/wf_buttons_test.dart
git commit -m "feat: animate buttons and toggles"
```

---

### Task 12: verifica finale

**Files:** nessuno (salvo correzioni emerse).

- [ ] **Step 1:** `flutter gen-l10n`, `flutter analyze`, `flutter test`: nessun problema, tutto verde. Annota il numero dei test (erano 709).
- [ ] **Step 2:** cerca durate o curve scritte a mano nei file toccati da questo piano (esclusi player e costanti nominate): `grep -rn "Duration(milliseconds" lib/app lib/ui lib/features/detail lib/features/home lib/features/settings lib/features/person`. Quelle nuove devono venire da `WfMotion` o da una costante nominata (`wheelScrollDuration`, `shellTransitionDuration`); quelle vecchie non toccate da questo piano (per esempio `hero_carousel.dart`, `media_row.dart` frecce) restano per il 6b. Segnala cosa hai trovato.
- [ ] **Step 3:** build di prova: `flutter build windows --debug` deve riuscire (se l'app dell'utente è aperta e dà `LNK1168`, **non** chiuderla: segnalalo).
- [ ] **Step 4:** se hai corretto qualcosa, commit con un messaggio `fix: …` che dica cosa.

## Prova manuale (con l'utente, sul server reale)

Build di release: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` e `flutter build windows --release --dart-define-from-file=config/wonderflix.json`; l'exe lo avvia l'utente.

- **Rotella:** morbida su Home, scheda, catalogo (scroll infinito compreso), La mia lista, ricerca, persona, impostazioni; scatti veloci che si sommano; touchpad invariato; righe orizzontali con Shift + rotella e con le frecce. Il passo (×1,6) va bene?
- **Transizioni:** Home ↔ Film ↔ Serie ↔ La mia lista ↔ Cerca ↔ Impostazioni (fade through); verso la scheda e la persona; indietro (Esc, Alt+←, tasto del mouse).
- **Volo Hero:** da locandina (Home, "Simili", catalogo, La mia lista, ricerca, persona), da "Continua a guardare" e "Prossimi episodi" (episodio → serie), dal cast alla persona; indietro con il volo inverso; card fuori schermo al ritorno (nessun errore).
- **Barra:** Home e scheda sotto la barra fino al bordo della finestra; velo in cima; barra scura e sfocata quando si scorre; sottolineatura che scorre tra le voci e sparisce su scheda e persona; oro al passaggio del mouse su voci, freccia indietro e nome utente; card d'invito del watch party ancora al suo posto.
- **Pulsanti:** alone e scala su Riproduci/Dettagli/Guarda insieme; pop di cuore e spunta.
- **Animazioni:** Impostazioni → Aspetto → *Ridotte* (niente volo, niente scala, solo dissolvenze), *Complete*, *Come Windows* con "Effetti di animazione" spento e acceso in Windows (cambiandolo con l'app aperta: vale al ritorno sulla finestra).
- **Regressioni:** player (apertura, ritorno), watch party ("Guarda insieme" dalla scheda, badge, inviti), Discord.
