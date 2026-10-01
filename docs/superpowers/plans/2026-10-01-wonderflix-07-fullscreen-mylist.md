# WonderFlix — Piano 7: schermo intero vero e filtri in "La mia lista"

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** correggere l'issue #2 (a finestra massimizzata lo schermo intero del player lascia barra del titolo e bordi) e realizzare l'issue #1 (ordinamento e filtri in "La mia lista", come in Film e Serie ma senza filtro per tipo).

**Decisioni prese con l'utente (2026-10-01):**
1. Causa di #2 confermata: `window_manager` 0.5.2 non toglie la cornice se la finestra è massimizzata. Si usa lo schermo intero nativo di `media_kit_video`, con lo stato tenuto da noi.
2. La mia lista: **stessa barra del catalogo, senza filtro per tipo** (Ordina per, Genere, Anno, Tutti/Non visti/Visti, Azzera filtri) e conteggio "N titoli".
3. Filtri e ordine **nell'app**, sulla lista già caricata (una sola richiesta, max 500): niente scheletro a ogni cambio; generi e anni dai titoli della lista.
4. "Data di aggiunta" = aggiunta alla libreria (Jellyfin non registra quando si mette il cuore).
5. Dopo la prova: merge, push, **release 0.3.1 non obbligatoria**; chiusura delle issue solo con l'ok dell'utente.

**Architecture:**
- `lib/core/system/native_fullscreen.dart`: `NativeFullScreen` (stato + `enter`/`exit` con `defaultEnterNativeFullscreen`/`defaultExitNativeFullscreen` di `media_kit_video`) e l'istanza condivisa `nativeFullScreen`, usata da `WindowManagerPlayerWindow` e dal salvataggio della posizione (`shouldSaveBounds`).
- `JellyfinItem` legge `SortName` e `DateCreated`; `ItemQuery` ha `includeSortFields` e `clearFilters()`.
- `lib/features/mylist/my_list_view.dart`: funzione pura `buildMyListView` (preferiti col cuore → filtri → ordine; opzioni di genere e anno).
- `CatalogFiltersBar` riceve generi e anni come parametro: la usano il catalogo (dati del server) e La mia lista (dati ricavati).

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, media_kit_video 2.0.1, window_manager 0.5.2.

**Spec:** `docs/superpowers/specs/2026-10-01-wonderflix-fullscreen-mylist-design.md`. **Worktree:** `.claude/worktrees/piano-7`, branch `fix/piano-7`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves`): solo il riferimento `(#1)`/`(#2)` dove indicato.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-7`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde (a inizio piano: 880 test). Nessuna stringa nuova: gli ARB non si toccano.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione e fine riga:** niente `dart format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`).
- **Colori:** solo `WfColors`. **Durate, curve, misure:** token di `WfMotion` o costanti nominate e commentate. **Tempo:** `clock.now()`, mai `DateTime.now()`. Il player (`lib/features/player/`) si tocca solo in `player_window.dart`.
- **Widget test:** `pumpApp` (finestra 1440×900, movimento ridotto). `DropdownButton` e `SegmentedButton` vogliono un `Material` sopra: le pagine si montano dentro `Scaffold` (come in `test/features/catalog/catalog_screen_test.dart`). In movimento ridotto `pumpAndSettle` va bene.
- **Fake:** `FakeLibraryApi`, `testItem`, `pageOf` in `test/support/library_fakes.dart`; `FakeSessionController`; `testUser`. `userDataOverridesProvider` (`lib/features/library/user_data.dart`) tiene cuore e visto cambiati in sessione.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **`window_manager` 0.5.2** (`windows/window_manager.cpp`, `SetFullScreen`): a finestra massimizzata non chiama `SetAsFrameless()` e toglie solo `WS_THICKFRAME | WS_MAXIMIZEBOX`; `WS_CAPTION` resta. Il suo gestore di `WM_NCCALCSIZE` interviene solo se il **suo** schermo intero è attivo, se la finestra è senza cornice o se la barra è nascosta: con lo schermo intero di media_kit nessuno dei tre casi si verifica.
- **`media_kit_video` 2.0.1**: `defaultEnterNativeFullscreen()` e `defaultExitNativeFullscreen()` sono esportate da `package:media_kit_video/media_kit_video.dart`. Su Windows (e macOS/Linux) chiamano il canale `com.alexmercerind/media_kit_video` con `Utils.EnterNativeFullscreen` / `Utils.ExitNativeFullscreen`; gli errori del canale sono presi e solo stampati (`debugPrint`). Il codice nativo (`windows/utils.cc`) toglie tutto `WS_OVERLAPPEDWINDOW` dalla finestra principale (`GetAncestor(…, GA_ROOT)`) e la allarga al monitor; all'uscita rimette lo stile e, se la finestra non è massimizzata, la riporta alla posizione normale. Ha già un suo flag che ignora le chiamate ripetute.
- **Nei test** il canale si simula con `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.alexmercerind/media_kit_video'), …)` dopo `TestWidgetsFlutterBinding.ensureInitialized()`.
- **`_BoundsSaver`** riceve `resized`/`moved` solo alla fine di un trascinamento dell'utente (`WM_EXITSIZEMOVE`), non per i `SetWindowPos` del codice nativo; il controllo dello schermo intero resta comunque, come oggi.
- **Jellyfin:** `SortName` e `DateCreated` arrivano solo se chiesti in `fields`. `DateTime.tryParse('2024-03-01T10:20:30.1234567Z')` funziona (le cifre oltre i microsecondi si ignorano). `GET /Items/Filters` non accetta `isFavorite`.
- **`WfSwitcher.isOutgoing(context)`** guarda solo il `WfSwitcher` più vicino. In La mia lista ce ne sono due annidati (stato della pagina, poi griglia/nessun risultato): la griglia prende `_scroll` solo se non esce né dall'uno né dall'altro.
- **`BatchedEntrance`** fa entrare le card quando nasce; una griglia con chiave nuova nasce di nuovo, quindi le card rientrano.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `lib/core/system/native_fullscreen.dart` | crea | stato e comandi dello schermo intero nativo |
| `lib/features/player/player_window.dart` | modifica | `setFullScreen`/`isFullScreen` via `NativeFullScreen` |
| `lib/app/window_setup.dart` | modifica | `shouldSaveBounds`; `_BoundsSaver` legge `nativeFullScreen` |
| `lib/core/jellyfin/item_models.dart` | modifica | `sortName`, `dateCreated` |
| `lib/core/jellyfin/item_query.dart` | modifica | `includeSortFields`, `clearFilters()` |
| `lib/features/mylist/my_list_view.dart` | crea | `myListInitialFilters`, `MyListView`, `buildMyListView` |
| `lib/features/catalog/catalog_filters_bar.dart` | modifica | generi e anni come parametro; azzera con `clearFilters()` |
| `lib/features/catalog/catalog_screen.dart` | modifica | passa i filtri del server alla barra |
| `lib/features/mylist/my_list_screen.dart` | modifica | titolo con conteggio, barra, griglia filtrata |
| `test/support/library_fakes.dart` | modifica | `testItem` con generi, voto, `SortName`, `DateCreated` |
| test | crea/modifica | vedi i singoli task |

## Gruppi per i subagent

- **Gruppo A (Task 1–2):** schermo intero.
- **Gruppo B (Task 3–4):** dati e logica di La mia lista.
- **Gruppo C (Task 5–6):** barra condivisa e pagina.
- **Gruppo D (Task 7):** verifica finale.

---

### Task 1: stato dello schermo intero nativo

**Files:**
- Create: `lib/core/system/native_fullscreen.dart`
- Test: `test/core/system/native_fullscreen_test.dart`

- [ ] **Step 1: test che fallisce.** Crea `test/core/system/native_fullscreen_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/system/native_fullscreen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('entra ed esce con il codice nativo di media_kit', () async {
    final fullScreen = NativeFullScreen();
    expect(fullScreen.active, isFalse);

    await fullScreen.enter();
    expect(fullScreen.active, isTrue);
    expect(calls, ['Utils.EnterNativeFullscreen']);

    await fullScreen.exit();
    expect(fullScreen.active, isFalse);
    expect(calls, ['Utils.EnterNativeFullscreen', 'Utils.ExitNativeFullscreen']);
  });

  test('richieste ripetute arrivano una volta sola', () async {
    final fullScreen = NativeFullScreen();
    await fullScreen.enter();
    await fullScreen.enter();
    await fullScreen.exit();
    await fullScreen.exit();
    expect(calls, ['Utils.EnterNativeFullscreen', 'Utils.ExitNativeFullscreen']);
  });

  test('uscire senza essere entrati non chiama nulla', () async {
    final fullScreen = NativeFullScreen();
    await fullScreen.exit();
    expect(fullScreen.active, isFalse);
    expect(calls, isEmpty);
  });

  test('due ingressi ravvicinati: una sola chiamata', () async {
    final fullScreen = NativeFullScreen();
    await Future.wait([fullScreen.enter(), fullScreen.enter()]);
    expect(calls, ['Utils.EnterNativeFullscreen']);
  });
}
```

- [ ] **Step 2: verifica che fallisca.** Run: `flutter test test/core/system/native_fullscreen_test.dart`. Expected: FAIL (file `native_fullscreen.dart` mancante).

- [ ] **Step 3: implementazione.** Crea `lib/core/system/native_fullscreen.dart`:

```dart
import 'package:media_kit_video/media_kit_video.dart'
    show defaultEnterNativeFullscreen, defaultExitNativeFullscreen;

/// Schermo intero della finestra con il codice nativo di `media_kit_video`.
///
/// `windowManager.setFullScreen` lascia barra del titolo e bordo se la
/// finestra è massimizzata (issue #2); media_kit toglie tutto
/// `WS_OVERLAPPEDWINDOW` e all'uscita rimette la finestra com'era.
class NativeFullScreen {
  bool _active = false;

  /// `true` tra [enter] e [exit].
  bool get active => _active;

  /// Lo stato cambia prima della chiamata nativa: due richieste ravvicinate
  /// non arrivano due volte al codice nativo.
  Future<void> enter() async {
    if (_active) return;
    _active = true;
    await defaultEnterNativeFullscreen();
  }

  Future<void> exit() async {
    if (!_active) return;
    _active = false;
    await defaultExitNativeFullscreen();
  }
}

/// Una sola finestra: lo stato è condiviso dal player e dal salvataggio
/// della posizione (`window_setup.dart`).
final nativeFullScreen = NativeFullScreen();
```

- [ ] **Step 4: verifica che passi.** Run: `flutter test test/core/system/native_fullscreen_test.dart`. Expected: 4 test PASS.

- [ ] **Step 5: commit.** `flutter analyze` e `flutter test` verdi, poi:

```bash
git add lib/core/system/native_fullscreen.dart test/core/system/native_fullscreen_test.dart
git commit -m "feat: add native fullscreen state backed by media_kit"
```

---

### Task 2: player e posizione della finestra con lo schermo intero nativo

**Files:**
- Modify: `lib/features/player/player_window.dart`
- Modify: `lib/app/window_setup.dart`
- Test: `test/features/player/player_window_test.dart` (crea), `test/app/window_setup_test.dart` (modifica)

- [ ] **Step 1: test che falliscono.** Crea `test/features/player/player_window_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/system/native_fullscreen.dart';
import 'package:wonderflix/features/player/player_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('schermo intero con il codice nativo di media_kit', () async {
    final fullScreen = NativeFullScreen();
    final window = WindowManagerPlayerWindow(fullScreen: fullScreen);

    await window.setFullScreen(true);
    expect(await window.isFullScreen(), isTrue);
    expect(fullScreen.active, isTrue);

    await window.setFullScreen(false);
    expect(await window.isFullScreen(), isFalse);
    expect(calls, ['Utils.EnterNativeFullscreen', 'Utils.ExitNativeFullscreen']);
  });

  test('senza argomenti usa lo stato condiviso', () async {
    final window = WindowManagerPlayerWindow();
    await window.setFullScreen(true);
    expect(nativeFullScreen.active, isTrue);
    await window.setFullScreen(false);
    expect(nativeFullScreen.active, isFalse);
  });
}
```

In `test/app/window_setup_test.dart`, prima della chiusura di `main` (dopo il `group('isVisibleOnAnyDisplay', …)`), aggiungi:

```dart
  test('la posizione si salva solo per la finestra normale', () {
    expect(
        shouldSaveBounds(minimized: false, maximized: false, fullScreen: false),
        isTrue);
    expect(
        shouldSaveBounds(minimized: true, maximized: false, fullScreen: false),
        isFalse);
    expect(
        shouldSaveBounds(minimized: false, maximized: true, fullScreen: false),
        isFalse);
    expect(
        shouldSaveBounds(minimized: false, maximized: false, fullScreen: true),
        isFalse);
  });
```

- [ ] **Step 2: verifica che falliscano.** Run: `flutter test test/features/player/player_window_test.dart test/app/window_setup_test.dart`. Expected: FAIL (parametro `fullScreen` e `shouldSaveBounds` mancanti).

- [ ] **Step 3: player.** In `lib/features/player/player_window.dart`:

Aggiungi l'import dopo quello di `window_manager`:

```dart
import '../../core/system/native_fullscreen.dart';
```

Sostituisci l'inizio di `WindowManagerPlayerWindow` e i due metodi dello schermo intero:

```dart
class WindowManagerPlayerWindow implements PlayerWindow {
  WindowManagerPlayerWindow({NativeFullScreen? fullScreen})
      : _fullScreen = fullScreen ?? nativeFullScreen;

  /// Schermo intero nativo: quello di `window_manager` a finestra
  /// massimizzata lascia la barra del titolo (issue #2).
  final NativeFullScreen _fullScreen;

  final _listeners = <Future<void> Function(), _CloseListener>{};
```

(il commento e il campo `_preventCloseRequests` restano dove sono)

```dart
  @override
  Future<void> setFullScreen(bool value) =>
      value ? _fullScreen.enter() : _fullScreen.exit();

  @override
  Future<bool> isFullScreen() async => _fullScreen.active;
```

Chiusura, `setPreventClose`, `destroy` e ascoltatori restano su `windowManager`.

- [ ] **Step 4: posizione della finestra.** In `lib/app/window_setup.dart`:

Aggiungi l'import dopo quello di `window_manager`:

```dart
import '../core/system/native_fullscreen.dart';
```

Dopo `isVisibleOnAnyDisplay` aggiungi:

```dart
/// La posizione si ricorda solo per la finestra "normale": né ridotta a
/// icona, né massimizzata, né a schermo intero.
bool shouldSaveBounds({
  required bool minimized,
  required bool maximized,
  required bool fullScreen,
}) =>
    !minimized && !maximized && !fullScreen;
```

Sostituisci `_save` di `_BoundsSaver`:

```dart
  Future<void> _save() async {
    // Lo schermo intero è nativo (`NativeFullScreen`): `window_manager` non
    // lo vede.
    final save = shouldSaveBounds(
      minimized: await windowManager.isMinimized(),
      maximized: await windowManager.isMaximized(),
      fullScreen: nativeFullScreen.active,
    );
    if (!save) return;
    await _prefs.setString(_boundsKey, encodeBounds(await windowManager.getBounds()));
  }
```

- [ ] **Step 5: verifica che passino.** Run: `flutter test test/features/player/player_window_test.dart test/app/window_setup_test.dart`. Expected: PASS. Poi `grep -rn "windowManager.setFullScreen\|windowManager.isFullScreen" lib` non deve trovare nulla.

- [ ] **Step 6: commit.** `flutter analyze` e `flutter test` verdi, poi:

```bash
git add lib/features/player/player_window.dart lib/app/window_setup.dart test/features/player/player_window_test.dart test/app/window_setup_test.dart
git commit -m "fix: keep fullscreen free of the title bar on a maximized window (#2)"
```

---

### Task 3: chiave d'ordinamento, data di aggiunta, azzera filtri

**Files:**
- Modify: `lib/core/jellyfin/item_models.dart`
- Modify: `lib/core/jellyfin/item_query.dart`
- Test: `test/core/jellyfin/item_models_test.dart`, `test/core/jellyfin/item_query_test.dart`

- [ ] **Step 1: test che falliscono.** In `test/core/jellyfin/item_models_test.dart`, nel test `'campi mancanti e tipo sconosciuto hanno valori di default'` aggiungi in fondo:

```dart
    expect(item.sortName, isNull);
    expect(item.dateCreated, isNull);
```

e dopo quel test aggiungi:

```dart
  test('chiave d\'ordinamento e data di aggiunta', () {
    final item = JellyfinItem.fromJson({
      'Id': 'm1',
      'Name': 'The Matrix',
      'Type': 'Movie',
      'SortName': 'matrix',
      'DateCreated': '2024-03-01T10:20:30.1234567Z',
    });
    expect(item.sortName, 'matrix');
    expect(item.dateCreated, DateTime.utc(2024, 3, 1, 10, 20, 30, 123, 456));
  });

  test('data di aggiunta non valida: null', () {
    final item = JellyfinItem.fromJson(
        {'Id': 'm1', 'Type': 'Movie', 'DateCreated': 'ieri'});
    expect(item.dateCreated, isNull);
  });
```

In `test/core/jellyfin/item_query_test.dart`, prima della chiusura di `main`, aggiungi:

```dart
  test('campi per ordinare nell\'app solo se richiesti', () {
    Map<String, dynamic> p(ItemQuery q) =>
        q.toQueryParameters(userId: 'u', startIndex: 0, limit: 1);
    expect(p(const ItemQuery(kinds: {ItemKind.movie}))['fields'],
        'PrimaryImageAspectRatio,Genres');
    expect(
        p(const ItemQuery(kinds: {ItemKind.movie}, includeSortFields: true))[
            'fields'],
        'PrimaryImageAspectRatio,Genres,SortName,DateCreated');
    expect(
        const ItemQuery(kinds: {ItemKind.movie}, includeSortFields: true)
            .copyWith(year: 2020)
            .includeSortFields,
        isTrue);
  });

  test('clearFilters toglie solo genere, anno e visti', () {
    const query = ItemQuery(
      kinds: {ItemKind.movie, ItemKind.series},
      sort: CatalogSort.year,
      genres: {'Dramma'},
      year: 2020,
      watched: WatchedFilter.watched,
      favoritesOnly: true,
      searchTerm: 'dune',
      personId: 'p9',
      includeSortFields: true,
    );
    final cleared = query.clearFilters();
    expect(cleared.hasFilters, isFalse);
    expect(cleared.genres, isEmpty);
    expect(cleared.year, isNull);
    expect(cleared.watched, WatchedFilter.all);
    expect(cleared.kinds, {ItemKind.movie, ItemKind.series});
    expect(cleared.sort, CatalogSort.year);
    expect(cleared.favoritesOnly, isTrue);
    expect(cleared.searchTerm, 'dune');
    expect(cleared.personId, 'p9');
    expect(cleared.includeSortFields, isTrue);
  });
```

- [ ] **Step 2: verifica che falliscano.** Run: `flutter test test/core/jellyfin/item_models_test.dart test/core/jellyfin/item_query_test.dart`. Expected: FAIL (`sortName`, `dateCreated`, `includeSortFields`, `clearFilters` mancanti).

- [ ] **Step 3: modello.** In `lib/core/jellyfin/item_models.dart`:

Dopo `double? _double(Object? value) => …;` aggiungi:

```dart
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
```

Nel costruttore di `JellyfinItem`, dopo `this.genres = const [],`:

```dart
    this.sortName,
    this.dateCreated,
```

In `JellyfinItem.fromJson`, dopo `genres: _stringList(json['Genres']),`:

```dart
      sortName: json['SortName'] as String?,
      dateCreated: _date(json['DateCreated']),
```

Nei campi, dopo `final List<String> genres;`:

```dart

  /// Chiave d'ordinamento di Jellyfin (es. senza "The"). Arriva solo se
  /// chiesta (`ItemQuery.includeSortFields`).
  final String? sortName;

  /// Aggiunta alla libreria. Arriva solo se chiesta
  /// (`ItemQuery.includeSortFields`).
  final DateTime? dateCreated;
```

- [ ] **Step 4: interrogazione.** In `lib/core/jellyfin/item_query.dart`:

Nel costruttore di `ItemQuery`, dopo `this.personId,`:

```dart
    this.includeSortFields = false,
```

Dopo `final String? personId;`:

```dart

  /// Chiede anche `SortName` e `DateCreated`, per ordinare nell'app
  /// (La mia lista).
  final bool includeSortFields;
```

In `copyWith`, dopo `personId: personId,`:

```dart
        includeSortFields: includeSortFields,
```

Dopo `copyWith` aggiungi:

```dart
  /// Toglie genere, anno e visti; il resto (tipi, ordinamento, preferiti,
  /// ricerca, persona, campi) resta.
  ItemQuery clearFilters() => ItemQuery(
        kinds: kinds,
        sort: sort,
        favoritesOnly: favoritesOnly,
        searchTerm: searchTerm,
        personId: personId,
        includeSortFields: includeSortFields,
      );
```

In `toQueryParameters`, subito dopo `...cardImageParams,`:

```dart
      if (includeSortFields)
        'fields': '${cardImageParams['fields']},SortName,DateCreated',
```

- [ ] **Step 5: verifica che passino.** Run: `flutter test test/core/jellyfin/item_models_test.dart test/core/jellyfin/item_query_test.dart`. Expected: PASS.

- [ ] **Step 6: commit.** `flutter analyze` e `flutter test` verdi, poi:

```bash
git add lib/core/jellyfin/item_models.dart lib/core/jellyfin/item_query.dart test/core/jellyfin/item_models_test.dart test/core/jellyfin/item_query_test.dart
git commit -m "feat: request sort name and date added for client-side sorting"
```

---

### Task 4: filtri e ordine di La mia lista (funzione pura)

**Files:**
- Create: `lib/features/mylist/my_list_view.dart`
- Test: `test/features/mylist/my_list_view_test.dart`

- [ ] **Step 1: test che fallisce.** Crea `test/features/mylist/my_list_view_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/mylist/my_list_view.dart';

/// Preferito col cuore.
JellyfinItem fav(
  String id, {
  String? name,
  String? sortName,
  int? year,
  double? rating,
  DateTime? added,
  List<String> genres = const [],
  bool played = false,
}) =>
    JellyfinItem(
      id: id,
      name: name ?? id,
      kind: ItemKind.movie,
      sortName: sortName,
      productionYear: year,
      communityRating: rating,
      dateCreated: added,
      genres: genres,
      userData: UserItemData(isFavorite: true, played: played),
    );

List<String> ids(MyListView view) => [for (final item in view.items) item.id];

MyListView view(
  List<JellyfinItem> items, [
  ItemQuery filters = myListInitialFilters,
  Map<String, UserItemData> overrides = const {},
]) =>
    buildMyListView(items, filters, overrides);

ItemQuery sortedBy(CatalogSort sort) => myListInitialFilters.copyWith(sort: sort);

void main() {
  test('filtri iniziali: film e serie dalla data di aggiunta, senza filtri', () {
    expect(myListInitialFilters.kinds, {ItemKind.movie, ItemKind.series});
    expect(myListInitialFilters.sort, CatalogSort.dateAdded);
    expect(myListInitialFilters.hasFilters, isFalse);
  });

  group('ordine', () {
    test('titolo: per SortName senza maiuscole, il nome se manca', () {
      final result = view([
        fav('a', name: 'The Matrix', sortName: 'matrix'),
        fav('b', name: 'alien'),
        fav('c', name: 'Blade Runner', sortName: 'Blade Runner'),
      ], sortedBy(CatalogSort.title));
      expect(ids(result), ['b', 'c', 'a']);
    });

    test('titoli uguali: per id, sempre nello stesso ordine', () {
      final result = view([fav('2', name: 'Heat'), fav('1', name: 'Heat')],
          sortedBy(CatalogSort.title));
      expect(ids(result), ['1', '2']);
    });

    test('data di aggiunta: dalla più recente, senza data in fondo', () {
      final result = view([
        fav('old', added: DateTime.utc(2020)),
        fav('none'),
        fav('new', added: DateTime.utc(2024)),
      ], sortedBy(CatalogSort.dateAdded));
      expect(ids(result), ['new', 'old', 'none']);
    });

    test('anno: dal più recente, a parità per titolo, senza anno in fondo', () {
      final result = view([
        fav('z', name: 'Zodiac', year: 2007),
        fav('n', name: 'Nessuno'),
        fav('a', name: 'Alien', year: 2007),
        fav('d', name: 'Dune', year: 2021),
      ], sortedBy(CatalogSort.year));
      expect(ids(result), ['d', 'a', 'z', 'n']);
    });

    test('voto: dal più alto, senza voto in fondo per titolo', () {
      final result = view([
        fav('b', name: 'B', rating: 7.1),
        fav('y', name: 'Y'),
        fav('x', name: 'X'),
        fav('a', name: 'A', rating: 8.4),
      ], sortedBy(CatalogSort.rating));
      expect(ids(result), ['a', 'b', 'x', 'y']);
    });
  });

  group('filtri', () {
    final items = [
      fav('d', name: 'Dune', year: 2021, genres: ['Fantascienza', 'Avventura'],
          played: true),
      fav('h', name: 'Heat', year: 1995, genres: ['Crimine']),
      fav('a', name: 'Arrival', year: 2016, genres: ['Fantascienza']),
    ];
    final byTitle = sortedBy(CatalogSort.title);

    test('genere', () {
      expect(ids(view(items, byTitle.copyWith(genres: {'Fantascienza'}))),
          ['a', 'd']);
    });

    test('anno', () {
      expect(ids(view(items, byTitle.copyWith(year: 1995))), ['h']);
    });

    test('visti e non visti', () {
      expect(ids(view(items, byTitle.copyWith(watched: WatchedFilter.watched))),
          ['d']);
      expect(
          ids(view(items, byTitle.copyWith(watched: WatchedFilter.unwatched))),
          ['a', 'h']);
    });

    test('più filtri insieme', () {
      expect(
          ids(view(
              items,
              byTitle.copyWith(
                  genres: {'Fantascienza'}, watched: WatchedFilter.unwatched))),
          ['a']);
    });

    test('visto segnato in questa sessione', () {
      final result = view(
          items,
          byTitle.copyWith(watched: WatchedFilter.watched),
          {'h': const UserItemData(isFavorite: true, played: true)});
      expect(ids(result), ['d', 'h']);
    });
  });

  group('cuore', () {
    test('tolto in questa sessione: sparisce, la lista resta vuota', () {
      final result = view([fav('d', name: 'Dune')], myListInitialFilters,
          {'d': const UserItemData()});
      expect(result.items, isEmpty);
      expect(result.listEmpty, isTrue);
    });

    test('titoli presenti ma nessun risultato: la lista non è vuota', () {
      final result = view([fav('d', name: 'Dune', year: 2021)],
          myListInitialFilters.copyWith(year: 1990));
      expect(result.items, isEmpty);
      expect(result.listEmpty, isFalse);
    });
  });

  group('opzioni', () {
    test('generi senza doppioni in ordine alfabetico, anni dal più recente', () {
      final result = view([
        fav('d', year: 2021, genres: ['fantascienza', 'Avventura']),
        fav('a', year: 2016, genres: ['Avventura', 'Dramma']),
        fav('x', year: 2021),
        fav('n'),
      ]);
      expect(result.options.genres, ['Avventura', 'Dramma', 'fantascienza']);
      expect(result.options.years, [2021, 2016]);
    });

    test('la scelta attiva resta anche senza titoli', () {
      final result = view([fav('d', year: 2021, genres: ['Dramma'])],
          myListInitialFilters.copyWith(genres: {'Horror'}, year: 1990));
      expect(result.options.genres, ['Dramma', 'Horror']);
      expect(result.options.years, [2021, 1990]);
      expect(result.items, isEmpty);
    });

    test('i titoli tolti dal cuore non portano opzioni', () {
      final result = view([fav('d', year: 2021, genres: ['Dramma'])],
          myListInitialFilters, {'d': const UserItemData()});
      expect(result.options.genres, isEmpty);
      expect(result.options.years, isEmpty);
    });
  });
}
```

- [ ] **Step 2: verifica che fallisca.** Run: `flutter test test/features/mylist/my_list_view_test.dart`. Expected: FAIL (file `my_list_view.dart` mancante).

- [ ] **Step 3: implementazione.** Crea `lib/features/mylist/my_list_view.dart`:

```dart
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';

/// Filtri iniziali di La mia lista: film e serie dalla data di aggiunta,
/// l'ordine di sempre.
const myListInitialFilters = ItemQuery(
  kinds: {ItemKind.movie, ItemKind.series},
  sort: CatalogSort.dateAdded,
);

/// Cosa mostra La mia lista con i filtri scelti.
class MyListView {
  const MyListView({
    required this.items,
    required this.options,
    required this.listEmpty,
  });

  /// Titoli da mostrare, filtrati e ordinati.
  final List<JellyfinItem> items;

  /// Generi e anni da proporre nella barra dei filtri.
  final LibraryFilters options;

  /// Nessun titolo col cuore, prima dei filtri.
  final bool listEmpty;
}

/// Filtra e ordina nell'app i preferiti già caricati, come fa Jellyfin nel
/// catalogo. [overrides]: dati utente cambiati in questa sessione (cuore e
/// visto).
MyListView buildMyListView(
  List<JellyfinItem> items,
  ItemQuery filters,
  Map<String, UserItemData> overrides,
) {
  UserItemData userData(JellyfinItem item) =>
      overrides[item.id] ?? item.userData;
  // Tolti dal cuore in questa sessione: spariscono subito.
  final favorites = items.where((i) => userData(i).isFavorite).toList();
  final visible = favorites
      .where((i) => _matches(i, filters, played: userData(i).played))
      .toList()
    ..sort(_comparator(filters.sort));
  return MyListView(
    items: visible,
    options: _options(favorites, filters),
    listEmpty: favorites.isEmpty,
  );
}

bool _matches(JellyfinItem item, ItemQuery filters, {required bool played}) {
  if (filters.genres.isNotEmpty && !filters.genres.any(item.genres.contains)) {
    return false;
  }
  if (filters.year != null && item.productionYear != filters.year) return false;
  return switch (filters.watched) {
    WatchedFilter.all => true,
    WatchedFilter.unwatched => !played,
    WatchedFilter.watched => played,
  };
}

Comparator<JellyfinItem> _comparator(CatalogSort sort) => switch (sort) {
      CatalogSort.title => _byTitle,
      CatalogSort.dateAdded => _descending((i) => i.dateCreated),
      CatalogSort.year => _descending((i) => i.productionYear),
      CatalogSort.rating => _descending((i) => i.communityRating),
    };

/// `SortName` di Jellyfin (es. "matrix" per "The Matrix"), il nome se manca;
/// senza maiuscole.
String _titleKey(JellyfinItem item) =>
    (item.sortName ?? item.name).toLowerCase();

/// Per titolo; a parità per id, così l'ordine non cambia da un calcolo
/// all'altro.
int _byTitle(JellyfinItem a, JellyfinItem b) {
  final byKey = _titleKey(a).compareTo(_titleKey(b));
  return byKey != 0 ? byKey : a.id.compareTo(b.id);
}

/// Dal valore più alto; chi non ce l'ha va in fondo. A parità, per titolo.
Comparator<JellyfinItem> _descending(
        Comparable<Object>? Function(JellyfinItem item) value) =>
    (a, b) {
      final va = value(a);
      final vb = value(b);
      if (va == null || vb == null) {
        if (va != null) return -1;
        if (vb != null) return 1;
        return _byTitle(a, b);
      }
      final byValue = vb.compareTo(va);
      return byValue != 0 ? byValue : _byTitle(a, b);
    };

/// Generi e anni dei preferiti. La scelta attiva resta anche se nessun
/// titolo la ha più: il menu la mostra e la pagina dice che non c'è nulla.
LibraryFilters _options(List<JellyfinItem> favorites, ItemQuery filters) {
  final genres = {
    for (final item in favorites) ...item.genres,
    ...filters.genres,
  }.toList()
    ..sort((a, b) {
      final byLower = a.toLowerCase().compareTo(b.toLowerCase());
      return byLower != 0 ? byLower : a.compareTo(b);
    });
  final years = {
    for (final item in favorites) ?item.productionYear,
    ?filters.year,
  }.toList()
    ..sort((a, b) => b.compareTo(a));
  return LibraryFilters(genres: genres, years: years);
}
```

- [ ] **Step 4: verifica che passi.** Run: `flutter test test/features/mylist/my_list_view_test.dart`. Expected: PASS (tutti).

- [ ] **Step 5: commit.** `flutter analyze` e `flutter test` verdi, poi:

```bash
git add lib/features/mylist/my_list_view.dart test/features/mylist/my_list_view_test.dart
git commit -m "feat: filter and sort My List on the client"
```

---

### Task 5: barra dei filtri con generi e anni come parametro

**Files:**
- Modify: `lib/features/catalog/catalog_filters_bar.dart`
- Modify: `lib/features/catalog/catalog_screen.dart`
- Test: `test/features/catalog/catalog_screen_test.dart`

- [ ] **Step 1: test di protezione.** In `test/features/catalog/catalog_screen_test.dart`, dopo il test `'filtro "Visti" senza risultati e azzeramento'`, aggiungi:

```dart
  testWidgets('menu dei generi con i generi del server', (tester) async {
    await pumpCatalog(tester);
    await tester.tap(find.text('Tutti i generi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dramma').last);
    await tester.pumpAndSettle();
    expect(api.itemQueries.last.genres, {'Dramma'});
  });
```

- [ ] **Step 2: verifica.** Run: `flutter test test/features/catalog/catalog_screen_test.dart`. Expected: PASS già ora (protegge il cambio che segue).

- [ ] **Step 3: barra.** In `lib/features/catalog/catalog_filters_bar.dart`:

Togli gli import di `flutter_riverpod` e di `catalog_controller.dart`. Sostituisci la classe `CatalogFiltersBar` fino alla riga `final genre = …;` compresa:

```dart
/// Ordinamento, genere, anno e visto/non visto. Generi e anni li dà chi la
/// usa: il catalogo quelli del server, La mia lista quelli dei suoi titoli.
class CatalogFiltersBar extends StatelessWidget {
  const CatalogFiltersBar({
    super.key,
    required this.filters,
    required this.query,
    required this.onChanged,
  });

  /// Generi e anni proposti nei menu.
  final LibraryFilters filters;
  final ItemQuery query;
  final ValueChanged<ItemQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final genre = query.genres.isEmpty ? null : query.genres.first;
```

e il pulsante in fondo:

```dart
        if (query.hasFilters)
          TextButton(
            onPressed: () => onChanged(query.clearFilters()),
            child: Text(l.catalogClearFilters),
          ),
```

Il resto (menu, `SegmentedButton`, `_Picker`) non cambia.

- [ ] **Step 4: catalogo.** In `lib/features/catalog/catalog_screen.dart`:

In `build`, dopo `final controller = ref.read(provider.notifier);`:

```dart
    final filters = ref.watch(catalogFiltersProvider(widget.kind)).value ??
        const LibraryFilters();
```

La barra:

```dart
          child: CatalogFiltersBar(
            filters: filters,
            query: state.query,
            onChanged: (query) => unawaited(controller.setQuery(query)),
          ),
```

Nello stato vuoto di `_body`:

```dart
                onPressed: () => unawaited(
                    controller.setQuery(state.query.clearFilters())),
```

Togli l'import `'../../core/jellyfin/item_query.dart'`, che resta inutilizzato.

- [ ] **Step 5: verifica.** Run: `flutter test test/features/catalog/`. Expected: PASS.

- [ ] **Step 6: commit.** `flutter analyze` e `flutter test` verdi, poi:

```bash
git add lib/features/catalog/catalog_filters_bar.dart lib/features/catalog/catalog_screen.dart test/features/catalog/catalog_screen_test.dart
git commit -m "refactor: pass genres and years to the catalog filters bar"
```

---

### Task 6: pagina La mia lista con barra, conteggio e griglia filtrata

**Files:**
- Modify: `lib/features/mylist/my_list_screen.dart`
- Modify: `test/support/library_fakes.dart`
- Test: `test/features/mylist/my_list_screen_test.dart`

- [ ] **Step 1: `testItem` più ricco.** In `test/support/library_fakes.dart`, nei parametri di `testItem` dopo `int localTrailers = 0,`:

```dart
  List<String> genres = const [],
  double? rating,
  String? sortName,
  String? dateCreated,
```

e nella mappa dopo `'LocalTrailerCount': localTrailers,`:

```dart
      if (genres.isNotEmpty) 'Genres': genres,
      'CommunityRating': ?rating,
      'SortName': ?sortName,
      'DateCreated': ?dateCreated,
```

- [ ] **Step 2: test che falliscono.** In `test/features/mylist/my_list_screen_test.dart`:

Aggiungi gli import:

```dart
import 'package:flutter/material.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/catalog/catalog_filters_bar.dart';
```

In `pumpList` monta la pagina dentro uno `Scaffold` (la barra vuole un `Material` sopra, come nell'app):

```dart
    await pumpApp(tester, const Scaffold(body: MyListScreen()), overrides: [
```

Nel test `'mostra i preferiti'` aggiungi in fondo:

```dart
    expect(api.itemQueries.single.includeSortFields, isTrue);
```

Nel test `'lista vuota'` aggiungi in fondo:

```dart
    expect(find.byType(CatalogFiltersBar), findsNothing);
```

Prima di `pumpList` (dentro `main`) aggiungi:

```dart
  List<JellyfinItem> library() => [
        testItem(
            id: 'd',
            name: 'Dune',
            year: 2021,
            genres: ['Fantascienza'],
            favorite: true,
            dateCreated: '2024-05-01T00:00:00Z'),
        testItem(
            id: 'h',
            name: 'Heat',
            year: 1995,
            genres: ['Crimine'],
            favorite: true,
            played: true,
            dateCreated: '2023-01-01T00:00:00Z'),
        testItem(
            id: 'a',
            name: 'Arrival',
            year: 2016,
            genres: ['Fantascienza'],
            favorite: true,
            dateCreated: '2022-01-01T00:00:00Z'),
      ];

  FakeLibraryApi apiWith(List<JellyfinItem> items) => FakeLibraryApi()
    ..onItems = (query, start, limit) =>
        query.favoritesOnly ? pageOf(items) : pageOf([]);

  double xOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dx;
```

In fondo a `main` aggiungi:

```dart
  testWidgets('barra dei filtri, conteggio e ordine per data di aggiunta',
      (tester) async {
    await pumpList(tester, apiWith(library()));
    expect(find.byType(CatalogFiltersBar), findsOneWidget);
    expect(find.text('3 titoli'), findsOneWidget);
    expect(xOf(tester, 'Dune'), lessThan(xOf(tester, 'Heat')));
    expect(xOf(tester, 'Heat'), lessThan(xOf(tester, 'Arrival')));
  });

  testWidgets('ordinamento per titolo', (tester) async {
    final api = await pumpList(tester, apiWith(library()));
    await tester.tap(find.text('Ordina per: Data di aggiunta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina per: Titolo').last);
    await tester.pumpAndSettle();
    expect(xOf(tester, 'Arrival'), lessThan(xOf(tester, 'Dune')));
    expect(xOf(tester, 'Dune'), lessThan(xOf(tester, 'Heat')));
    // Si ordina nell'app: nessuna nuova richiesta.
    expect(api.itemQueries, hasLength(1));
  });

  testWidgets('filtro per genere: griglia e conteggio', (tester) async {
    final api = await pumpList(tester, apiWith(library()));
    await tester.tap(find.text('Tutti i generi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crimine').last);
    await tester.pumpAndSettle();
    expect(find.text('1 titolo'), findsOneWidget);
    expect(find.text('Heat'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
    expect(api.itemQueries, hasLength(1));
  });

  testWidgets('"Visti" senza risultati e azzeramento', (tester) async {
    await pumpList(tester, apiWith([testItem(id: 'd', name: 'Dune', favorite: true)]));
    await tester.tap(find.text('Visti'));
    await tester.pumpAndSettle();
    expect(find.text('Nessun titolo con questi filtri.'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);

    await tester.tap(find.text('Azzera filtri').last);
    await tester.pumpAndSettle();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Nessun titolo con questi filtri.'), findsNothing);
  });
```

- [ ] **Step 3: verifica che falliscano.** Run: `flutter test test/features/mylist/my_list_screen_test.dart`. Expected: FAIL (niente barra né conteggio, `includeSortFields` falso).

- [ ] **Step 4: pagina.** Sostituisci tutto `lib/features/mylist/my_list_screen.dart` con:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import '../catalog/catalog_filters_bar.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import 'my_list_view.dart';

final favoritesProvider = FutureProvider.autoDispose<List<JellyfinItem>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final page = await ref.watch(libraryApiProvider).items(
        const ItemQuery(
          kinds: {ItemKind.movie, ItemKind.series},
          sort: CatalogSort.dateAdded,
          favoritesOnly: true,
          // Ordine e filtri si applicano nell'app (`buildMyListView`).
          includeSortFields: true,
        ),
        userId: ref.watch(currentUserIdProvider),
        startIndex: 0,
        limit: 500,
      );
  return page.items;
});

/// Spazio della barra dei filtri mentre la lista si carica (altezza dei
/// menu più lo spazio sotto): lo scheletro sta dove sarà la griglia.
const _filtersBarSpace = 40.0 + 16;

class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  final _scroll = SmoothScrollController();

  /// Ordinamento e filtri scelti: si applicano alla lista già caricata.
  ItemQuery _filters = myListInitialFilters;

  /// Cresce a ogni scelta nella barra: la griglia nuova sostituisce la
  /// vecchia in dissolvenza e le card rientrano. Togliere un cuore non lo
  /// cambia: il titolo sparisce e basta.
  int _revision = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setFilters(ItemQuery filters) => setState(() {
        _filters = filters;
        _revision++;
      });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final overrides = ref.watch(userDataOverridesProvider);
    return WfSwitcher(
      expand: true,
      child: ref.watch(favoritesProvider).when(
            // Lo spazio di titolo e barra resta libero: la griglia è dove
            // sarà.
            loading: () => Column(
              key: const ValueKey('loading'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(l),
                const SizedBox(height: _filtersBarSpace),
                const Expanded(child: PosterGridSkeleton()),
              ],
            ),
            error: (error, _) => ErrorView(
                key: const ValueKey('error'),
                error: error,
                onRetry: () => ref.invalidate(favoritesProvider)),
            data: (items) {
              final view = buildMyListView(items, _filters, overrides);
              if (view.listEmpty) return _empty(l);
              return KeyedSubtree(
                key: const ValueKey('data'),
                child: Builder(builder: (context) => _content(context, l, view)),
              );
            },
          ),
    );
  }

  /// Titolo della pagina; con [count] anche il numero dei titoli mostrati,
  /// come nel catalogo.
  Widget _title(AppLocalizations l, {int count = 0}) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(l.navMyList.toUpperCase(), style: WfText.display(40)),
            if (count > 0) ...[
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(l.catalogCount(count),
                    style: const TextStyle(color: WfColors.creamMuted)),
              ),
            ],
          ],
        ),
      );

  /// Nessun preferito: niente barra né conteggio.
  Widget _empty(AppLocalizations l) => Column(
        key: const ValueKey('empty'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(l.myListEmpty,
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
        ],
      );

  Widget _content(BuildContext context, AppLocalizations l, MyListView view) {
    // Ricaricando la lista, la pagina vecchia sfuma mentre arriva la nuova:
    // `_scroll` va solo alla griglia che entra in entrambi i `WfSwitcher`.
    final leaving = WfSwitcher.isOutgoing(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(l, count: view.items.length),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: CatalogFiltersBar(
            filters: view.options,
            query: _filters,
            onChanged: _setFilters,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: WfSwitcher(
            expand: true,
            child: view.items.isEmpty
                ? _noResults(l)
                : KeyedSubtree(
                    key: ValueKey(('grid', _revision)),
                    child: Builder(
                      builder: (context) => _grid(view.items,
                          attachScroll:
                              !leaving && !WfSwitcher.isOutgoing(context)),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _noResults(AppLocalizations l) => Center(
        key: const ValueKey('no-results'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.catalogEmpty,
                style: const TextStyle(color: WfColors.creamMuted)),
            if (_filters.hasFilters)
              TextButton(
                onPressed: () => _setFilters(_filters.clearFilters()),
                child: Text(l.catalogClearFilters),
              ),
          ],
        ),
      );

  Widget _grid(List<JellyfinItem> items, {required bool attachScroll}) =>
      BatchedEntrance(
        itemCount: items.length,
        child: CustomScrollView(
          controller: attachScroll ? _scroll : null,
          primary: false,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.55,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => BatchedEntranceItem(
                    index: i,
                    child: PosterCard(item: items[i], heroSource: 'mylist.$i'),
                  ),
                  childCount: items.length,
                ),
              ),
            ),
          ],
        ),
      );
}
```

- [ ] **Step 5: verifica che passino.** Run: `flutter test test/features/mylist/ test/ui/skeletons_test.dart`. Expected: PASS (anche `'tolto dalla lista dall\'anteprima: l\'anteprima si chiude'` e `'La mia lista in caricamento: griglia di scheletri'`).

- [ ] **Step 6: commit.** `flutter analyze` e `flutter test` verdi, poi:

```bash
git add lib/features/mylist/my_list_screen.dart test/support/library_fakes.dart test/features/mylist/my_list_screen_test.dart
git commit -m "feat: add filters and sorting to My List (#1)"
```

---

### Task 7: verifica finale

**Files:**
- Modify: `docs/superpowers/specs/2026-10-01-wonderflix-fullscreen-mylist-design.md` (solo se il codice si è discostato dallo spec)

- [ ] **Step 1:** `flutter analyze` senza problemi e `flutter test` tutto verde. Annota il numero dei test (erano 880).
- [ ] **Step 2:** `grep -rn "windowManager.setFullScreen\|windowManager.isFullScreen" lib` non trova nulla; `grep -rn "catalogFiltersProvider" lib` trova solo `catalog_controller.dart` e `catalog_screen.dart`.
- [ ] **Step 3:** build: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` e `flutter build windows --debug` (se l'app dell'utente è aperta e dà `LNK1168`/`LNK1104`, **non** chiuderla: segnalalo).
- [ ] **Step 4:** se durante i task qualcosa è cambiato rispetto allo spec (nomi, comportamenti), allinea lo spec e fai commit:

```bash
git add docs/superpowers/specs/2026-10-01-wonderflix-fullscreen-mylist-design.md
git commit -m "docs: align plan 7 spec with the implementation"
```

## Prova manuale (con l'utente, sul server reale)

Build di release: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` e `flutter build windows --release --dart-define-from-file=config/wonderflix.json`; l'exe lo avvia l'utente.

- **Schermo intero (#2):**
  - finestra **massimizzata** e **non massimizzata**, con `F`, doppio click e pulsante: niente barra del titolo né bordi, taskbar nascosta;
  - all'uscita la finestra torna com'era (massimizzata, o stessa posizione e dimensione);
  - uscita chiudendo il player (freccia indietro) e passando all'episodio successivo;
  - watch party: player da solo a schermo intero → "Guarda insieme": il player riaperto resta a schermo intero;
  - posizione della finestra ricordata dopo un riavvio, anche dopo aver usato lo schermo intero.
- **La mia lista (#1):**
  - titolo con "N titoli", barra come in Film/Serie (senza tipo);
  - ogni ordinamento (Titolo con "The …" sotto la lettera giusta, Data di aggiunta, Anno, Voto), genere, anno, Visti/Non visti, Azzera filtri;
  - filtro senza risultati: testo e "Azzera filtri";
  - togliere un cuore e segnare un titolo visto dall'anteprima aggiornano subito la griglia filtrata;
  - aprire una scheda e tornare indietro: i filtri restano; cambiare pagina e tornare: si azzerano.
- **Regressioni:** filtri di Film e Serie, anteprima delle card, volo Hero da La mia lista, player.

## Dopo la prova (fuori dai task)

Con l'ok dell'utente: merge fast-forward su `main` (prima `git fetch`: se `origin/main` è avanti, rebase dei commit locali), push, rimozione di worktree e branch; poi **release 0.3.1 non obbligatoria** secondo `docs/RELEASING.md` (versione in `pubspec.yaml`, commit `chore: release 0.3.1`, tag solo con l'ok dell'utente, note in italiano scritte nella bozza da `git log v0.3.0..v0.3.1`, **senza** marcatore `min-version`; la pubblicazione la fa l'utente). Dopo la pubblicazione, solo con l'ok dell'utente: commento e chiusura delle issue #1 e #2.
