# WonderFlix — Piano 3b: funzioni extra del player

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** completare il player della spec §7 sopra la base del Piano 3a:
- **salta intro e riassunto** (MediaSegments), anche in automatico;
- **prossimo episodio:** pulsante, tasto N, scheda con conto alla rovescia di 10 s ai crediti o negli ultimi 30 s, passaggio automatico a fine episodio (disattivabile), schermo intero conservato;
- **barra di avanzamento:** anteprime trickplay al passaggio del mouse e tacche dei capitoli;
- **trailer locali** nel player (punto rimandato 4), con ripiego sul trailer remoto nel browser;
- **impostazioni del player:** qualità, decodifica hardware, dimensione dei sottotitoli, salto automatico, riproduzione automatica; lingue di audio e sottotitoli salvate sul server;
- **Home:** `nextUpDateCutoff` nella riga "Prossimi episodi" (punto rimandato 5);
- **pannello media di Windows (SMTC)** con `smtc_windows`: titolo, locandina, tasti multimediali anche con l'app in secondo piano.

**Architecture:**
- **Dati e API:**
  - `JellyfinItem` legge capitoli e informazioni trickplay;
  - `LibraryApi` ottiene episodio successivo, trailer locali e il limite di data per i prossimi episodi;
  - `PlaybackApi` ottiene i MediaSegments;
  - `UserConfigApi` legge e salva la configurazione utente sul server.
- **Logica pura in `lib/features/player/`:**
  - `segments.dart`: quale segmento saltare e quando mostrare la scheda;
  - `trickplay.dart`: quale mosaico e quale riquadro mostrare;
  - `player_settings.dart`: preferenze locali con shared_preferences.
- **`PlayerController`:**
  - legge le impostazioni (qualità, dimensione dei sottotitoli);
  - dopo la partenza carica segmenti ed episodio successivo, senza ritardare l'avvio;
  - salta l'intro, a comando o in automatico.
- **UI:**
  - la barra di avanzamento mostra tacche dei capitoli e anteprima;
  - `PositionSelector` fa ricostruire solo i widget legati alla posizione;
  - scheda "Prossimo episodio";
  - la schermata passa all'episodio successivo con `pushReplacement` e il parametro `fs=1` per restare a schermo intero;
  - nelle Impostazioni: sezione Player e sezione lingue.
- **SMTC:**
  - interfaccia `MediaSession`, con un'implementazione vuota di default (e nei test);
  - `SmtcMediaSession`, attivata in `main` solo se `SMTCWindows.initialize()` riesce.

**Tech Stack:** Flutter 3.47.5, media_kit 1.2.6 (libmpv), flutter_riverpod 3, go_router 18, shared_preferences, cached_network_image (immagini con autenticazione), smtc_windows 1.1.0 (Rust tramite cargokit); test con i fake del Piano 3a e fake_async.

**Spec:** `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md`, sezione 7. **Piano precedente:** `docs/superpowers/plans/2026-09-29-wonderflix-03a-player-base.md` (note tecniche su media_kit). **Punti rimandati:** `docs/superpowers/handoff/2026-09-29-handoff-piano-3.md` (4 e 5).

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…". Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/player-extra`, branch `feat/player-extra`).
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde. Se `lib/l10n/gen` manca, esegui prima `flutter gen-l10n`.
- **Icone:** solo `LucideIcons`, niente emoji. I nomi usati nel piano sono verificati sulla versione 3.1.20.
- **Widget test:**
  - `pumpApp` non mette uno `Scaffold`: Slider, IconButton, InkWell, Switch, Dropdown e SnackBar richiedono `Scaffold(body: …)`.
  - Le liste lazy non costruiscono le sezioni in basso: alza la superficie con `tester.binding.setSurfaceSize(const Size(1440, 1600))`.
  - Il font dei test ha glifi più larghi: se una `Row` va in overflow **solo nei test**, correggi con `Flexible`/`Wrap` e segnalalo.
  - I fake del motore usano stream broadcast asincroni: dopo `engine.emit*` può servire un `await tester.pump()` in più.
- **Fake:**
  - `FakeLibraryApi` (`test/support/library_fakes.dart`);
  - `FakePlaybackApi`, `FakeVideoEngine`, `FakePlayerWindow` (`test/support/playback_fakes.dart`), estesi in questo piano con `FakePlayerSettings` e `FakeMediaSession`;
  - `FakeUserConfigApi` (`test/support/settings_fakes.dart`, nuovo).
  - Niente mocktail.
- **Lint `use_null_aware_elements`:** scrivi `'key': ?value`.
- **Import:** se l'analyzer segnala un import come superfluo (`unnecessary_import`) o mancante, correggilo e segnalalo.
- **File generati:** se `flutter test` riscrive `windows/flutter/generated_plugin*` con soli cambi di fine riga, esegui `git checkout -- windows/flutter/`. Nel Task 20 i cambi sono veri (nuovo plugin) e vanno committati.
- **App aperta:** se una build fallisce con `LNK1168`, esegui `taskkill //IM wonderflix.exe //F`.
- **Riferimento API:** `docs/reference/jellyfin-openapi-10.11.9.json`.

## Note tecniche verificate

- **MediaSegments:** `GET /MediaSegments/{itemId}` → `{Items: [{Type, StartTicks, EndTicks}]}`. `Type`: `Intro`, `Outro`, `Recap`, `Preview`, `Commercial`, `Unknown`. Senza un plugin che li calcola (es. Intro Skipper) la lista è vuota.
- **Trickplay:**
  - Il campo `Trickplay` dell'elemento è una mappa `mediaSourceId → larghezza → {Width, Height, TileWidth, TileHeight, ThumbnailCount, Interval (ms)}`.
  - Il mosaico `index` è `GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg?mediaSourceId=…` e **richiede l'header `Authorization`**.
  - Anteprima n = posizione / Interval. Mosaico = n / (TileWidth·TileHeight). Nel mosaico: colonna = resto % TileWidth, riga = resto / TileWidth.
- **Capitoli:** campo `Chapters` dell'elemento (`StartPositionTicks`, `Name`). `GET /Items/{id}` restituisce `Chapters` e `Trickplay` senza bisogno di `fields`.
- **Episodio successivo:** `GET /Shows/{seriesId}/Episodes?startItemId={id}&limit=2&isMissing=false`. La lista parte dall'episodio stesso (compreso); il secondo elemento è il successivo, anche nella stagione dopo.
- **Trailer locali:** `GET /Items/{itemId}/LocalTrailers?userId=` restituisce un **array** di elementi, non `{Items}`.
- **Configurazione utente:** `GET /Users/Me` → `Configuration` (`AudioLanguagePreference`, `SubtitleLanguagePreference`, `SubtitleMode` tra `Default`, `Always`, `OnlyForced`, `None`, `Smart`). `POST /Users/Configuration?userId=` **sostituisce tutta la configurazione**: si rimanda la mappa completa ricevuta, cambiando solo i tre campi. La stringa vuota vuol dire "qualsiasi lingua".
- **Prossimi episodi:** `nextUpDateCutoff` (data ISO in UTC). jellyfin-web usa "oggi meno 365 giorni".
- **smtc_windows 1.1.0:**
  - Si inizializza con `SMTCWindows.initialize()`. Poi si crea `SMTCWindows(config: SMTCConfig(...))`.
  - Metodi: `updateMetadata(MusicMetadata(title, artist, thumbnail))`, `setPlaybackStatus(PlaybackStatus.playing|paused)`, `updateTimeline(PlaybackTimeline(startTimeMs, endTimeMs, positionMs, minSeekTimeMs, maxSeekTimeMs))`, `setIsNextEnabled(bool)`, `buttonPressStream` (`PressedButton.play|pause|next|stop|…`), `disableSmtc()`, `dispose()`.
  - Compila Rust con cargokit, senza binari precompilati: serve `rustup` (Task 20).
- **Slider:** in questo piano la traccia della barra ha un margine orizzontale fisso di 16 px (`overlayShape` con raggio 16). Serve a calcolare la posizione sotto il mouse e a disegnare le tacche.

## Mappa dei file

```
lib/core/jellyfin/item_models.dart        (+ ChapterMark, TrickplayInfo, JellyfinItem.chapters/trickplay)
lib/core/jellyfin/library_api.dart        (+ nextEpisode, localTrailers, nextUp(dateCutoff))
lib/core/jellyfin/playback_models.dart    (+ MediaSegmentType, MediaSegment)
lib/core/jellyfin/playback_api.dart       (+ mediaSegments)
lib/core/jellyfin/user_config_api.dart    UserConfigApi, LanguagePreferences, playbackLanguages
lib/core/video/video_engine.dart          (+ setSubtitleScale)
lib/core/video/media_kit_engine.dart      (+ setSubtitleScale)
lib/core/media_session/media_session.dart MediaButton, MediaSession, NoopMediaSession
lib/core/media_session/smtc_media_session.dart SmtcMediaSession
lib/features/player/segments.dart         SkipKind, SkipTarget, skipTargetAt, nextEpisodeCardFrom
lib/features/player/trickplay.dart        TrickplayTile, pickTrickplay, trickplayTileAt, trickplaySheetUrl
lib/features/player/player_settings.dart  StreamQuality, subtitleScaleOptions, PlayerSettings, PlayerSettingsController, playerSettingsProvider
lib/features/player/player_providers.dart (+ factory con decodifica hardware, authImageProvider, mediaSessionFactoryProvider)
lib/features/player/player_controller.dart (+ impostazioni, segmenti, episodio successivo, salto intro)
lib/features/player/seek_bar.dart         (+ capitoli, anteprima, chapterAt, ChapterTicksPainter)
lib/features/player/trickplay_preview.dart TrickplayPreview
lib/features/player/player_extras.dart    PositionSelector, NextEpisodeCard
lib/features/player/player_overlay.dart   (+ capitoli, anteprima, pulsante episodio successivo)
lib/features/player/player_commands.dart  (+ N / traccia successiva)
lib/features/player/player_screen.dart    (+ salta intro, prossimo episodio, schermo intero conservato, SMTC)
lib/features/playback/play_launcher.dart  (+ playTrailer, remoteTrailerUri)
lib/features/detail/detail_header.dart    (Trailer: locale o remoto)
lib/features/home/home_data.dart          (+ nextUpCutoff)
lib/features/settings/player_settings_section.dart  PlayerSettingsSection
lib/features/settings/language_preferences.dart     userConfigApiProvider, LanguagePreferencesController, languagePreferencesProvider
lib/features/settings/language_settings_section.dart LanguageSettingsSection
lib/features/settings/settings_screen.dart (+ sezioni)
lib/app/navigation.dart, lib/app/router.dart (+ fs=1)
lib/main.dart                             (+ SMTC)
.github/workflows/ci.yml                  (+ Rust)
l10n/app_it.arb, l10n/app_en.arb          (nuove stringhe)
test/support/library_fakes.dart, test/support/playback_fakes.dart, test/support/settings_fakes.dart
```

---

### Task 1: capitoli e anteprime nei modelli

**Files:**
- Modify: `lib/core/jellyfin/item_models.dart`, `test/support/library_fakes.dart`
- Test: `test/core/jellyfin/item_models_test.dart` (aggiunte)

- [ ] **Step 1: aggiungi i test** in fondo al `main()` di `test/core/jellyfin/item_models_test.dart`:

```dart
  test('capitoli e anteprime trickplay', () {
    final item = JellyfinItem.fromJson({
      'Id': 'm1',
      'Name': 'Dune',
      'Type': 'Movie',
      'Chapters': [
        {'StartPositionTicks': 0, 'Name': 'Inizio'},
        {'StartPositionTicks': 27000000000, 'Name': 'Arrakis'},
      ],
      'Trickplay': {
        'ms1': {
          '320': {
            'Width': 320,
            'Height': 180,
            'TileWidth': 10,
            'TileHeight': 10,
            'ThumbnailCount': 700,
            'Interval': 10000,
          },
        },
      },
    });
    expect(item.chapters.map((c) => c.name), ['Inizio', 'Arrakis']);
    expect(item.chapters[1].start, const Duration(minutes: 45));
    final info = item.trickplay['ms1']![320]!;
    expect(info.width, 320);
    expect(info.height, 180);
    expect(info.tileWidth, 10);
    expect(info.tileHeight, 10);
    expect(info.thumbnailCount, 700);
    expect(info.interval, const Duration(seconds: 10));
  });

  test('senza capitoli né trickplay', () {
    final item =
        JellyfinItem.fromJson({'Id': 'm1', 'Name': 'Dune', 'Type': 'Movie'});
    expect(item.chapters, isEmpty);
    expect(item.trickplay, isEmpty);
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/core/jellyfin/item_models_test.dart`
Expected: FAIL (`chapters` e `trickplay` non esistono).

- [ ] **Step 3: implementa** in `lib/core/jellyfin/item_models.dart`.

Prima di `class JellyfinItem` aggiungi:

```dart
/// Inizio di un capitolo del video.
class ChapterMark {
  const ChapterMark({required this.start, this.name});

  factory ChapterMark.fromJson(Map<String, dynamic> json) => ChapterMark(
        start: ticksToDuration(_int(json['StartPositionTicks']) ?? 0),
        name: json['Name'] as String?,
      );

  final Duration start;
  final String? name;
}

/// Mosaici di anteprime (trickplay) di una larghezza: ogni immagine
/// contiene [tileWidth] × [tileHeight] anteprime di [width] × [height] pixel,
/// una ogni [interval].
class TrickplayInfo {
  const TrickplayInfo({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
    required this.interval,
  });

  factory TrickplayInfo.fromJson(Map<String, dynamic> json) => TrickplayInfo(
        width: _int(json['Width']) ?? 0,
        height: _int(json['Height']) ?? 0,
        tileWidth: _int(json['TileWidth']) ?? 0,
        tileHeight: _int(json['TileHeight']) ?? 0,
        thumbnailCount: _int(json['ThumbnailCount']) ?? 0,
        interval: Duration(milliseconds: _int(json['Interval']) ?? 0),
      );

  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int thumbnailCount;
  final Duration interval;
}

/// `Trickplay` dell'API: sorgente → larghezza → informazioni.
Map<String, Map<int, TrickplayInfo>> _trickplay(Object? value) {
  final result = <String, Map<int, TrickplayInfo>>{};
  if (value is! Map) return result;
  for (final source in value.entries) {
    final widths = source.value;
    if (widths is! Map) continue;
    final byWidth = <int, TrickplayInfo>{};
    for (final entry in widths.entries) {
      final width = int.tryParse('${entry.key}');
      final info = entry.value;
      if (width != null && info is Map<String, dynamic>) {
        byWidth[width] = TrickplayInfo.fromJson(info);
      }
    }
    if (byWidth.isNotEmpty) result['${source.key}'] = byWidth;
  }
  return result;
}
```

In `JellyfinItem`:
- al costruttore aggiungi `this.chapters = const [],` e `this.trickplay = const {},` (dopo `this.childCount,`);
- in `fromJson`, dopo `childCount: …`, aggiungi:

```dart
      chapters: _objectList(json['Chapters']).map(ChapterMark.fromJson).toList(),
      trickplay: _trickplay(json['Trickplay']),
```

- dopo il campo `childCount` aggiungi:

```dart
  /// Capitoli del video, in ordine.
  final List<ChapterMark> chapters;

  /// Anteprime per la barra di avanzamento: sorgente → larghezza → info.
  final Map<String, Map<int, TrickplayInfo>> trickplay;
```

- [ ] **Step 4: parametro dei trailer locali nei test.** In `test/support/library_fakes.dart`, nella funzione `testItem`:
  - aggiungi il parametro `int localTrailers = 0,` dopo `trailers`;
  - nella mappa aggiungi `'LocalTrailerCount': localTrailers,` dopo `'RemoteTrailers': trailers,`.

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter test`
Expected: tutti PASS.

- [ ] **Step 6: commit**

```bash
git add lib/core/jellyfin/item_models.dart test/core/jellyfin/item_models_test.dart test/support/library_fakes.dart
git commit -m "feat: read chapters and trickplay info from items"
```

---

### Task 2: `LibraryApi` — episodio successivo, trailer locali, limite dei prossimi episodi

**Files:**
- Modify: `lib/core/jellyfin/library_api.dart`, `test/support/library_fakes.dart`
- Test: `test/core/jellyfin/library_api_test.dart` (aggiunte)

- [ ] **Step 1: aggiungi i test** in fondo al `main()` di `test/core/jellyfin/library_api_test.dart`:

```dart
  test('nextEpisode: l\'episodio dopo quello indicato', () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['e4', 'e5']));
    final next = await api.nextEpisode('u1', 's1', 'e4');
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['startItemId'], 'e4');
    expect(last().query['limit'], 2);
    expect(last().query['isMissing'], false);
    expect(last().query['userId'], 'u1');
    expect(next?.id, 'e5');

    adapter.handler = (_) => FakeResponse(200, itemsResult(['e9']));
    expect(await api.nextEpisode('u1', 's1', 'e9'), isNull,
        reason: 'ultimo episodio');
  });

  test('localTrailers: array di elementi', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {'Id': 't1', 'Name': 'Trailer', 'Type': 'Trailer'},
        ]);
    final trailers = await api.localTrailers('u1', 'm1');
    expect(last().path, '/Items/m1/LocalTrailers');
    expect(last().query['userId'], 'u1');
    expect(trailers.single.id, 't1');
  });

  test('nextUp con limite di data', () async {
    await api.nextUp('u1',
        limit: 20, dateCutoff: DateTime.utc(2025, 9, 29, 10, 30));
    expect(last().query['nextUpDateCutoff'], '2025-09-29T10:30:00.000Z');

    await api.nextUp('u1', limit: 20);
    expect(last().query.containsKey('nextUpDateCutoff'), isFalse);
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/core/jellyfin/library_api_test.dart`
Expected: FAIL (metodi e parametro mancanti).

- [ ] **Step 3: implementa** in `lib/core/jellyfin/library_api.dart`.
- aggiungi `import 'api_exception.dart';` in testa;
- sostituisci `nextUp` con:

```dart
  /// [dateCutoff]: ignora le serie non guardate da prima di questa data.
  Future<List<JellyfinItem>> nextUp(
    String userId, {
    String? seriesId,
    int limit = 20,
    bool enableResumable = false,
    DateTime? dateCutoff,
  }) async =>
      _list(await _http.get('/Shows/NextUp', query: {
        ...cardImageParams,
        'userId': userId,
        'limit': limit,
        'enableResumable': enableResumable,
        'seriesId': ?seriesId,
        'nextUpDateCutoff': ?dateCutoff?.toUtc().toIso8601String(),
      }));
```

- dopo `episodes(...)` aggiungi:

```dart
  /// Episodio che segue [episodeId] nella serie, anche nella stagione dopo;
  /// `null` se è l'ultimo.
  Future<JellyfinItem?> nextEpisode(
      String userId, String seriesId, String episodeId) async {
    final episodes = _list(await _http.get('/Shows/$seriesId/Episodes', query: {
      ...cardImageParams,
      'userId': userId,
      'startItemId': episodeId,
      'limit': 2,
      'isMissing': false,
      'fields': 'Overview,PrimaryImageAspectRatio',
    }));
    final index = episodes.indexWhere((e) => e.id == episodeId);
    return index >= 0 && index + 1 < episodes.length ? episodes[index + 1] : null;
  }

  /// Trailer salvati sul server accanto all'elemento.
  Future<List<JellyfinItem>> localTrailers(String userId, String itemId) async {
    final data = await _http
        .get('/Items/$itemId/LocalTrailers', query: {'userId': userId});
    if (data is! List) throw const ServerErrorException(null);
    return data
        .whereType<Map<String, dynamic>>()
        .map(JellyfinItem.fromJson)
        .toList();
  }
```

- [ ] **Step 4: aggiorna `FakeLibraryApi`** in `test/support/library_fakes.dart`:
- nuovi campi, accanto agli altri:

```dart
  /// Episodio successivo, per id dell'episodio corrente.
  final Map<String, JellyfinItem> nextEpisodes = {};

  /// Trailer locali, per id dell'elemento.
  final Map<String, List<JellyfinItem>> localTrailerItems = {};
  final nextEpisodeCalls = <String>[];
  final nextUpCutoffs = <DateTime?>[];
```

- sostituisci l'override di `nextUp` con:

```dart
  @override
  Future<List<JellyfinItem>> nextUp(String userId,
      {String? seriesId,
      int limit = 20,
      bool enableResumable = false,
      DateTime? dateCutoff}) {
    nextUpCalls.add(seriesId);
    nextUpCutoffs.add(dateCutoff);
    return _answer(() => nextUpItems);
  }
```

- aggiungi:

```dart
  @override
  Future<JellyfinItem?> nextEpisode(
      String userId, String seriesId, String episodeId) {
    nextEpisodeCalls.add(episodeId);
    return _answer(() => nextEpisodes[episodeId]);
  }

  @override
  Future<List<JellyfinItem>> localTrailers(String userId, String itemId) =>
      _answer(() => localTrailerItems[itemId] ?? const []);
```

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 6: commit**

```bash
git add lib/core/jellyfin/library_api.dart test/core/jellyfin/library_api_test.dart test/support/library_fakes.dart
git commit -m "feat: add next episode, local trailers and next-up date cutoff to LibraryApi"
```

---

### Task 3: MediaSegments

**Files:**
- Modify: `lib/core/jellyfin/playback_models.dart`, `lib/core/jellyfin/playback_api.dart`, `test/support/playback_fakes.dart`
- Test: `test/core/jellyfin/playback_api_test.dart` (aggiunta)

- [ ] **Step 1: aggiungi il test** in fondo al `main()` di `test/core/jellyfin/playback_api_test.dart`:

```dart
  test('mediaSegments: intro, crediti e tipi sconosciuti', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {'Type': 'Intro', 'StartTicks': 100000000, 'EndTicks': 900000000},
            {'Type': 'Outro', 'StartTicks': 24000000000, 'EndTicks': 25200000000},
            {'Type': 'Nuovo', 'StartTicks': 0, 'EndTicks': 10},
          ],
          'TotalRecordCount': 3,
        });
    final segments = await api.mediaSegments('e4');
    expect(adapter.requests.last.path, '/MediaSegments/e4');
    expect(segments.map((s) => s.type), [
      MediaSegmentType.intro,
      MediaSegmentType.outro,
      MediaSegmentType.unknown,
    ]);
    expect(segments.first.start, const Duration(seconds: 10));
    expect(segments.first.end, const Duration(seconds: 90));
    expect(segments[1].start, const Duration(minutes: 40));
  });
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/core/jellyfin/playback_api_test.dart`
Expected: FAIL (`mediaSegments` non esiste).

- [ ] **Step 3: modello** in fondo a `lib/core/jellyfin/playback_models.dart`, prima di `resolveServerUrl`:

```dart
/// Tipo di segmento del video (valore `Type` di `MediaSegmentDto`).
enum MediaSegmentType {
  intro('Intro'),
  recap('Recap'),
  outro('Outro'),
  preview('Preview'),
  commercial('Commercial'),
  unknown('Unknown');

  const MediaSegmentType(this.apiName);

  final String apiName;

  static MediaSegmentType parse(Object? value) {
    for (final type in values) {
      if (type.apiName == value) return type;
    }
    return unknown;
  }
}

/// Parte del video riconosciuta dal server (intro, riassunto, crediti…).
class MediaSegment {
  const MediaSegment({
    required this.type,
    required this.start,
    required this.end,
  });

  factory MediaSegment.fromJson(Map<String, dynamic> json) => MediaSegment(
        type: MediaSegmentType.parse(json['Type']),
        start: ticksToDuration(_int(json['StartTicks']) ?? 0),
        end: ticksToDuration(_int(json['EndTicks']) ?? 0),
      );

  final MediaSegmentType type;
  final Duration start;
  final Duration end;
}
```

- [ ] **Step 4: endpoint** in `lib/core/jellyfin/playback_api.dart`, prima di `userData`:

```dart
  /// Intro, riassunti, crediti… dell'elemento. Vuota se il server non ha un
  /// plugin che li riconosce.
  Future<List<MediaSegment>> mediaSegments(String itemId) async => parseJson(
        await _http.get('/MediaSegments/$itemId'),
        (json) => (json['Items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaSegment.fromJson)
            .toList(),
      );
```

- [ ] **Step 5: aggiorna `FakePlaybackApi`** in `test/support/playback_fakes.dart`:

```dart
  /// Segmenti restituiti da [mediaSegments].
  List<MediaSegment> segments = const [];

  /// Se valorizzato, solo [mediaSegments] lancia questo errore.
  Object? segmentsError;
  final segmentsCalls = <String>[];

  @override
  Future<List<MediaSegment>> mediaSegments(String itemId) async {
    segmentsCalls.add(itemId);
    final failure = segmentsError;
    if (failure != null) throw failure;
    return segments;
  }
```

- [ ] **Step 6: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 7: commit**

```bash
git add lib/core/jellyfin/playback_models.dart lib/core/jellyfin/playback_api.dart test/core/jellyfin/playback_api_test.dart test/support/playback_fakes.dart
git commit -m "feat: fetch media segments"
```

---

### Task 4: configurazione utente sul server

**Files:**
- Create: `lib/core/jellyfin/user_config_api.dart`, `test/support/settings_fakes.dart`
- Test: `test/core/jellyfin/user_config_api_test.dart`

- [ ] **Step 1: scrivi il test** `test/core/jellyfin/user_config_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/user_config_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late UserConfigApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = UserConfigApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('configuration legge tutti i campi', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Id': 'u1',
          'Name': 'Mario',
          'Configuration': {
            'AudioLanguagePreference': 'ita',
            'SubtitleMode': 'Smart',
            'HidePlayedInLatest': true,
          },
        });
    final config = await api.configuration();
    expect(adapter.requests.last.path, '/Users/Me');
    expect(config, {
      'AudioLanguagePreference': 'ita',
      'SubtitleMode': 'Smart',
      'HidePlayedInLatest': true,
    });
  });

  test('saveConfiguration invia la configurazione completa', () async {
    await api.saveConfiguration('u1', {'SubtitleMode': 'None', 'X': 1});
    final request = adapter.requests.last;
    expect(request.method, 'POST');
    expect(request.path, '/Users/Configuration');
    expect(request.queryParameters, {'userId': 'u1'});
    expect(request.data, {'SubtitleMode': 'None', 'X': 1});
  });

  test('LanguagePreferences: lettura e scrittura senza perdere altri campi',
      () {
    final prefs = LanguagePreferences.fromConfiguration(const {
      'AudioLanguagePreference': 'jpn',
      'SubtitleLanguagePreference': null,
      'HidePlayedInLatest': true,
    });
    expect(prefs.audioLanguage, 'jpn');
    expect(prefs.subtitleLanguage, '');
    expect(prefs.subtitleMode, 'Default');

    final updated = prefs
        .copyWith(subtitleLanguage: 'ita', subtitleMode: 'Always')
        .applyTo(const {'HidePlayedInLatest': true, 'SubtitleMode': 'Default'});
    expect(updated, {
      'HidePlayedInLatest': true,
      'SubtitleMode': 'Always',
      'AudioLanguagePreference': 'jpn',
      'SubtitleLanguagePreference': 'ita',
    });
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/core/jellyfin/user_config_api_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/core/jellyfin/user_config_api.dart`:

```dart
import 'jellyfin_http.dart';

/// Lingue proposte nelle impostazioni (codici ISO 639-2 usati da Jellyfin),
/// con il nome nella lingua stessa.
const playbackLanguages = <String, String>{
  'ita': 'Italiano',
  'eng': 'English',
  'jpn': '日本語',
  'fra': 'Français',
  'deu': 'Deutsch',
  'spa': 'Español',
  'por': 'Português',
  'kor': '한국어',
  'zho': '中文',
};

/// Modi dei sottotitoli di Jellyfin (`SubtitlePlaybackMode`).
const subtitleModes = ['Default', 'Always', 'OnlyForced', 'None', 'Smart'];

/// Configurazione dell'utente salvata sul server (vale per tutti i client).
class UserConfigApi {
  UserConfigApi(this._http);

  final JellyfinHttp _http;

  /// Configurazione completa, compresi i campi che l'app non usa.
  Future<Map<String, dynamic>> configuration() async {
    final me = asJsonMap(await _http.get('/Users/Me'));
    final config = me['Configuration'];
    return config is Map<String, dynamic>
        ? Map<String, dynamic>.of(config)
        : <String, dynamic>{};
  }

  /// Il server sostituisce tutta la configurazione: [configuration] deve
  /// essere quella completa letta da [configuration()], modificata.
  Future<void> saveConfiguration(
      String userId, Map<String, dynamic> configuration) async {
    await _http.post('/Users/Configuration',
        query: {'userId': userId}, body: configuration);
  }
}

/// Lingue di audio e sottotitoli preferite. Stringa vuota = qualsiasi.
class LanguagePreferences {
  const LanguagePreferences({
    this.audioLanguage = '',
    this.subtitleLanguage = '',
    this.subtitleMode = 'Default',
  });

  factory LanguagePreferences.fromConfiguration(Map<String, dynamic> config) =>
      LanguagePreferences(
        audioLanguage: config['AudioLanguagePreference'] as String? ?? '',
        subtitleLanguage: config['SubtitleLanguagePreference'] as String? ?? '',
        subtitleMode: config['SubtitleMode'] as String? ?? 'Default',
      );

  final String audioLanguage;
  final String subtitleLanguage;

  /// Uno di [subtitleModes].
  final String subtitleMode;

  LanguagePreferences copyWith({
    String? audioLanguage,
    String? subtitleLanguage,
    String? subtitleMode,
  }) =>
      LanguagePreferences(
        audioLanguage: audioLanguage ?? this.audioLanguage,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
        subtitleMode: subtitleMode ?? this.subtitleMode,
      );

  /// [configuration] con queste preferenze; gli altri campi restano uguali.
  Map<String, dynamic> applyTo(Map<String, dynamic> configuration) => {
        ...configuration,
        'AudioLanguagePreference': audioLanguage,
        'SubtitleLanguagePreference': subtitleLanguage,
        'SubtitleMode': subtitleMode,
      };
}
```

- [ ] **Step 4: crea** `test/support/settings_fakes.dart`:

```dart
import 'package:wonderflix/core/jellyfin/user_config_api.dart';

/// `UserConfigApi` in memoria.
class FakeUserConfigApi implements UserConfigApi {
  Map<String, dynamic> config = {
    'AudioLanguagePreference': 'ita',
    'SubtitleLanguagePreference': '',
    'SubtitleMode': 'Default',
    'HidePlayedInLatest': true,
  };

  /// Se valorizzato, [saveConfiguration] lancia questo errore.
  Object? saveError;
  final saved = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> configuration() async =>
      Map<String, dynamic>.of(config);

  @override
  Future<void> saveConfiguration(
      String userId, Map<String, dynamic> configuration) async {
    final failure = saveError;
    if (failure != null) throw failure;
    saved.add((userId, configuration));
    config = Map<String, dynamic>.of(configuration);
  }
}
```

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 6: commit**

```bash
git add lib/core/jellyfin/user_config_api.dart test/core/jellyfin/user_config_api_test.dart test/support/settings_fakes.dart
git commit -m "feat: read and save user language preferences on the server"
```

---

### Task 5: logica dei segmenti

**Files:**
- Create: `lib/features/player/segments.dart`
- Test: `test/features/player/segments_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/segments_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/segments.dart';

void main() {
  const recap = MediaSegment(
      type: MediaSegmentType.recap,
      start: Duration.zero,
      end: Duration(seconds: 8));
  const intro = MediaSegment(
      type: MediaSegmentType.intro,
      start: Duration(seconds: 10),
      end: Duration(seconds: 90));
  const outro = MediaSegment(
      type: MediaSegmentType.outro,
      start: Duration(minutes: 40),
      end: Duration(minutes: 42));
  const all = [recap, intro, outro];

  test('pulsante durante riassunto e intro', () {
    expect(skipTargetAt(all, const Duration(seconds: 3))?.kind, SkipKind.recap);
    final target = skipTargetAt(all, const Duration(seconds: 20));
    expect(target?.kind, SkipKind.intro);
    expect(target?.end, const Duration(seconds: 90));
    expect(skipTargetAt(all, const Duration(seconds: 89, milliseconds: 500)),
        isNull,
        reason: 'nell\'ultimo secondo il pulsante non serve');
    expect(skipTargetAt(all, const Duration(minutes: 41)), isNull,
        reason: 'i crediti portano alla scheda, non al pulsante');
    expect(skipTargetAt(const [], Duration.zero), isNull);
  });

  test('scheda del prossimo episodio: crediti o ultimi 30 s', () {
    expect(nextEpisodeCardFrom([intro, outro], const Duration(minutes: 42)),
        const Duration(minutes: 40));
    expect(nextEpisodeCardFrom([intro], const Duration(minutes: 42)),
        const Duration(minutes: 41, seconds: 30));
    expect(nextEpisodeCardFrom(const [], const Duration(seconds: 20)),
        Duration.zero);
    expect(nextEpisodeCardFrom(const [], Duration.zero), isNull,
        reason: 'durata non ancora nota');
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/segments_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/segments.dart`:

```dart
import '../../core/jellyfin/playback_models.dart';

enum SkipKind { intro, recap }

/// Segmento che si può saltare con il pulsante.
class SkipTarget {
  const SkipTarget(this.kind, this.segment);

  final SkipKind kind;
  final MediaSegment segment;

  Duration get end => segment.end;
}

/// Intro o riassunto in corso in [position]. Nell'ultimo secondo del
/// segmento non si propone più il salto (si sta già uscendo).
SkipTarget? skipTargetAt(List<MediaSegment> segments, Duration position) {
  for (final segment in segments) {
    final kind = switch (segment.type) {
      MediaSegmentType.intro => SkipKind.intro,
      MediaSegmentType.recap => SkipKind.recap,
      _ => null,
    };
    if (kind == null) continue;
    if (position >= segment.start &&
        position < segment.end - const Duration(seconds: 1)) {
      return SkipTarget(kind, segment);
    }
  }
  return null;
}

/// Da quando mostrare la scheda "Prossimo episodio": inizio dei crediti
/// (Outro), altrimenti gli ultimi 30 secondi. `null` se la durata non è
/// ancora nota.
Duration? nextEpisodeCardFrom(List<MediaSegment> segments, Duration duration) {
  for (final segment in segments) {
    if (segment.type == MediaSegmentType.outro && segment.start > Duration.zero) {
      return segment.start;
    }
  }
  if (duration <= Duration.zero) return null;
  final from = duration - const Duration(seconds: 30);
  return from < Duration.zero ? Duration.zero : from;
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/segments_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/player/segments.dart test/features/player/segments_test.dart
git commit -m "feat: decide skip button and next-episode card from media segments"
```

---

### Task 6: logica delle anteprime trickplay

**Files:**
- Create: `lib/features/player/trickplay.dart`
- Test: `test/features/player/trickplay_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/trickplay_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/trickplay.dart';

void main() {
  const info = TrickplayInfo(
    width: 320,
    height: 180,
    tileWidth: 10,
    tileHeight: 10,
    thumbnailCount: 700,
    interval: Duration(seconds: 10),
  );

  test('mosaico, colonna e riga per posizione', () {
    final first = trickplayTileAt(info, const Duration(minutes: 1))!;
    expect((first.sheet, first.column, first.row), (0, 6, 0));
    final hour = trickplayTileAt(info, const Duration(hours: 1))!;
    expect((hour.sheet, hour.column, hour.row), (3, 0, 6));
    final beyond = trickplayTileAt(info, const Duration(hours: 5))!;
    expect((beyond.sheet, beyond.column, beyond.row), (6, 9, 9),
        reason: 'oltre l\'ultima anteprima si usa l\'ultima');
    const empty = TrickplayInfo(
        width: 320,
        height: 180,
        tileWidth: 10,
        tileHeight: 10,
        thumbnailCount: 0,
        interval: Duration(seconds: 10));
    expect(trickplayTileAt(empty, Duration.zero), isNull);
  });

  test('URL del mosaico sotto il sotto-percorso del server', () {
    expect(
      trickplaySheetUrl(Uri.parse('https://host.example.com/jellyfin'),
          itemId: 'm1', width: 320, sheet: 3, mediaSourceId: 'ms1'),
      'https://host.example.com/jellyfin/Videos/m1/Trickplay/320/3.jpg?mediaSourceId=ms1',
    );
  });

  test('pickTrickplay: sorgente giusta e larghezza più vicina', () {
    Map<String, dynamic> width(int w) => {
          'Width': w,
          'Height': w * 9 ~/ 16,
          'TileWidth': 10,
          'TileHeight': 10,
          'ThumbnailCount': 100,
          'Interval': 10000,
        };
    final item = JellyfinItem.fromJson({
      'Id': 'm1',
      'Name': 'Dune',
      'Type': 'Movie',
      'Trickplay': {
        'ms1': {'160': width(160), '320': width(320), '640': width(640)},
        'ms2': {'480': width(480)},
      },
    });
    expect(pickTrickplay(item, 'ms1')?.width, 320);
    expect(pickTrickplay(item, 'ms1', preferredWidth: 600)?.width, 640);
    expect(pickTrickplay(item, 'ms2')?.width, 480);
    expect(pickTrickplay(item, 'altra')?.width, 320,
        reason: 'sorgente sconosciuta: la prima disponibile');
    expect(
        pickTrickplay(
            JellyfinItem.fromJson({'Id': 'x', 'Name': 'x', 'Type': 'Movie'}),
            'ms1'),
        isNull);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/trickplay_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/trickplay.dart`:

```dart
import '../../core/jellyfin/item_models.dart';

/// Posizione di un'anteprima: mosaico (immagine) e cella dentro il mosaico.
class TrickplayTile {
  const TrickplayTile({
    required this.sheet,
    required this.column,
    required this.row,
  });

  final int sheet;
  final int column;
  final int row;
}

/// Anteprime della sorgente [mediaSourceId] (o della prima disponibile),
/// nella larghezza più vicina a [preferredWidth].
TrickplayInfo? pickTrickplay(JellyfinItem item, String mediaSourceId,
    {int preferredWidth = 320}) {
  final byWidth =
      item.trickplay[mediaSourceId] ?? item.trickplay.values.firstOrNull;
  if (byWidth == null) return null;
  TrickplayInfo? best;
  for (final info in byWidth.values) {
    if (best == null ||
        (info.width - preferredWidth).abs() <
            (best.width - preferredWidth).abs()) {
      best = info;
    }
  }
  return best;
}

/// Anteprima da mostrare per [position]; `null` se non ci sono anteprime.
TrickplayTile? trickplayTileAt(TrickplayInfo info, Duration position) {
  final perSheet = info.tileWidth * info.tileHeight;
  if (info.interval <= Duration.zero ||
      info.thumbnailCount <= 0 ||
      perSheet <= 0) {
    return null;
  }
  final index = (position.inMilliseconds ~/ info.interval.inMilliseconds)
      .clamp(0, info.thumbnailCount - 1);
  final inSheet = index % perSheet;
  return TrickplayTile(
    sheet: index ~/ perSheet,
    column: inSheet % info.tileWidth,
    row: inSheet ~/ info.tileWidth,
  );
}

/// URL di un mosaico (richiede l'header di autenticazione).
String trickplaySheetUrl(
  Uri serverUrl, {
  required String itemId,
  required int width,
  required int sheet,
  required String mediaSourceId,
}) =>
    Uri.parse('$serverUrl/Videos/$itemId/Trickplay/$width/$sheet.jpg')
        .replace(queryParameters: {'mediaSourceId': mediaSourceId}).toString();
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/trickplay_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/player/trickplay.dart test/features/player/trickplay_test.dart
git commit -m "feat: locate trickplay thumbnails for a playback position"
```

---

### Task 7: impostazioni del player

**Files:**
- Create: `lib/features/player/player_settings.dart`
- Modify: `test/support/playback_fakes.dart` (aggiunta di `FakePlayerSettings`)
- Test: `test/features/player/player_settings_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/player_settings_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/device_profile.dart';
import 'package:wonderflix/features/player/player_settings.dart';

void main() {
  Future<ProviderContainer> container(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  }

  test('valori predefiniti', () async {
    final settings = (await container({})).read(playerSettingsProvider);
    expect(settings.quality, StreamQuality.original);
    expect(settings.hardwareDecoding, isTrue);
    expect(settings.subtitleScale, 1.0);
    expect(settings.autoSkipIntro, isFalse);
    expect(settings.autoplayNext, isTrue);
  });

  test('salva e rilegge', () async {
    final first = await container({});
    await first.read(playerSettingsProvider.notifier).update(const PlayerSettings(
          quality: StreamQuality.mbps8,
          hardwareDecoding: false,
          subtitleScale: 1.25,
          autoSkipIntro: true,
          autoplayNext: false,
        ));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('player.quality'), 'mbps8');

    final again = ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final settings = again.read(playerSettingsProvider);
    expect(settings.quality, StreamQuality.mbps8);
    expect(settings.hardwareDecoding, isFalse);
    expect(settings.subtitleScale, 1.25);
    expect(settings.autoSkipIntro, isTrue);
    expect(settings.autoplayNext, isFalse);
  });

  test('valori salvati non validi: predefiniti', () async {
    final settings = (await container({
      'player.quality': 'boh',
      'player.subtitleScale': 3.0,
    }))
        .read(playerSettingsProvider);
    expect(settings.quality, StreamQuality.original);
    expect(settings.subtitleScale, 1.0);
  });

  test('bitrate delle qualità', () {
    expect(StreamQuality.original.bitrate, originalQualityBitrate);
    expect(StreamQuality.mbps20.bitrate, 20000000);
    expect(StreamQuality.mbps8.bitrate, 8000000);
    expect(StreamQuality.mbps4.bitrate, 4000000);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/player_settings_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/player_settings.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/device_profile.dart';

/// Qualità massima dello streaming. Sotto il bitrate del file il server
/// converte il video.
enum StreamQuality {
  original(originalQualityBitrate),
  mbps20(20000000),
  mbps8(8000000),
  mbps4(4000000);

  const StreamQuality(this.bitrate);

  final int bitrate;
}

/// Dimensioni dei sottotitoli proposte (scala di mpv `sub-scale`).
const subtitleScaleOptions = [0.8, 1.0, 1.25, 1.5];

/// Preferenze del player salvate su questo PC.
class PlayerSettings {
  const PlayerSettings({
    this.quality = StreamQuality.original,
    this.hardwareDecoding = true,
    this.subtitleScale = 1.0,
    this.autoSkipIntro = false,
    this.autoplayNext = true,
  });

  final StreamQuality quality;
  final bool hardwareDecoding;
  final double subtitleScale;
  final bool autoSkipIntro;
  final bool autoplayNext;

  PlayerSettings copyWith({
    StreamQuality? quality,
    bool? hardwareDecoding,
    double? subtitleScale,
    bool? autoSkipIntro,
    bool? autoplayNext,
  }) =>
      PlayerSettings(
        quality: quality ?? this.quality,
        hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
        subtitleScale: subtitleScale ?? this.subtitleScale,
        autoSkipIntro: autoSkipIntro ?? this.autoSkipIntro,
        autoplayNext: autoplayNext ?? this.autoplayNext,
      );
}

class PlayerSettingsController extends Notifier<PlayerSettings> {
  static const _quality = 'player.quality';
  static const _hardwareDecoding = 'player.hardwareDecoding';
  static const _subtitleScale = 'player.subtitleScale';
  static const _autoSkipIntro = 'player.autoSkipIntro';
  static const _autoplayNext = 'player.autoplayNext';

  @override
  PlayerSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    const defaults = PlayerSettings();
    final scale = prefs.getDouble(_subtitleScale);
    return PlayerSettings(
      quality: StreamQuality.values.asNameMap()[prefs.getString(_quality)] ??
          defaults.quality,
      hardwareDecoding:
          prefs.getBool(_hardwareDecoding) ?? defaults.hardwareDecoding,
      subtitleScale: scale != null && subtitleScaleOptions.contains(scale)
          ? scale
          : defaults.subtitleScale,
      autoSkipIntro: prefs.getBool(_autoSkipIntro) ?? defaults.autoSkipIntro,
      autoplayNext: prefs.getBool(_autoplayNext) ?? defaults.autoplayNext,
    );
  }

  Future<void> update(PlayerSettings next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setString(_quality, next.quality.name),
      prefs.setBool(_hardwareDecoding, next.hardwareDecoding),
      prefs.setDouble(_subtitleScale, next.subtitleScale),
      prefs.setBool(_autoSkipIntro, next.autoSkipIntro),
      prefs.setBool(_autoplayNext, next.autoplayNext),
    ]);
  }
}

final playerSettingsProvider =
    NotifierProvider<PlayerSettingsController, PlayerSettings>(
        PlayerSettingsController.new);
```

- [ ] **Step 4: aggiungi `FakePlayerSettings`** in fondo a `test/support/playback_fakes.dart` (con `import 'package:wonderflix/features/player/player_settings.dart';` in testa):

```dart
/// Impostazioni del player in memoria (senza shared_preferences).
class FakePlayerSettings extends PlayerSettingsController {
  FakePlayerSettings([this.initial = const PlayerSettings()]);

  final PlayerSettings initial;

  @override
  PlayerSettings build() => initial;

  @override
  Future<void> update(PlayerSettings next) async {
    state = next;
  }
}
```

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 6: commit**

```bash
git add lib/features/player/player_settings.dart test/features/player/player_settings_test.dart test/support/playback_fakes.dart
git commit -m "feat: add local player settings"
```

---

### Task 8: qualità, decodifica hardware e dimensione dei sottotitoli

**Files:**
- Modify: `lib/core/video/video_engine.dart`, `lib/core/video/media_kit_engine.dart`, `lib/features/player/player_providers.dart`, `lib/features/player/player_controller.dart`, `test/support/playback_fakes.dart`
- Test: `test/features/player/player_controller_test.dart`, `test/features/player/player_screen_test.dart` (harness e aggiunte)

Da qui il controller legge `playerSettingsProvider`: gli harness dei test del controller e della schermata devono sostituirlo con `FakePlayerSettings`, altrimenti cercano shared_preferences.

- [ ] **Step 1: aggiorna gli harness dei test.**

In `test/features/player/player_controller_test.dart`:
- aggiungi `import 'package:wonderflix/features/player/player_settings.dart';`;
- dopo `late ProviderContainer container;` aggiungi `var settings = const PlayerSettings();`;
- all'inizio di `setUp` aggiungi `settings = const PlayerSettings();`;
- nella lista `overrides` del container aggiungi:

```dart
        playerSettingsProvider.overrideWith(() => FakePlayerSettings(settings)),
```

In `test/features/player/player_screen_test.dart`, allo stesso modo:
- aggiungi l'import di `player_settings.dart`;
- aggiungi `var settings = const PlayerSettings();` accanto alle altre variabili `late`, e `settings = const PlayerSettings();` nel `setUp`;
- aggiungi l'override nella `ProviderScope` di `pumpPlayer`.

La closure legge `settings` quando il provider viene creato: un test può cambiarla prima di avviare il player.

- [ ] **Step 2: aggiungi i test** in fondo al `main()` di `test/features/player/player_controller_test.dart`:

```dart
  test('qualità scelta: bitrate massimo nella richiesta', () async {
    settings = const PlayerSettings(quality: StreamQuality.mbps8);
    await start();
    expect(playback.playbackInfoCalls.first.maxBitrate, 8000000);
  });

  test('dimensione dei sottotitoli applicata all\'apertura', () async {
    settings = const PlayerSettings(subtitleScale: 1.25);
    await start();
    expect(engine.subtitleScales, [1.25]);
  });

  test('dimensione normale: nessuna modifica', () async {
    await start();
    expect(engine.subtitleScales, isEmpty);
  });
```

- [ ] **Step 3: esegui e verifica che falliscano**

Run: `flutter test test/features/player/player_controller_test.dart`
Expected: FAIL (`subtitleScales` non esiste e la qualità non è usata).

- [ ] **Step 4: motore.**
- In `lib/core/video/video_engine.dart`, dentro `VideoEngine`, dopo `setSubtitleDelay`:

```dart
  /// Dimensione dei sottotitoli: 1.0 = normale.
  Future<void> setSubtitleScale(double scale);
```

- In `lib/core/video/media_kit_engine.dart`, dopo `setSubtitleDelay`:

```dart
  @override
  Future<void> setSubtitleScale(double scale) =>
      _native.setProperty('sub-scale', scale.toStringAsFixed(2));
```

- In `FakeVideoEngine` (`test/support/playback_fakes.dart`): aggiungi il campo `final subtitleScales = <double>[];` e il metodo seguente. Non aggiungerlo al registro `calls`, per non cambiare gli ordini già verificati dai test:

```dart
  @override
  Future<void> setSubtitleScale(double scale) async =>
      subtitleScales.add(scale);
```

- [ ] **Step 5: decodifica hardware.** In `lib/features/player/player_providers.dart`:
- aggiungi `import 'player_settings.dart';`;
- sostituisci `videoEngineFactoryProvider` con:

```dart
/// Crea un motore video per ogni riproduzione; nei test si usa un motore finto.
/// La decodifica hardware segue le impostazioni (vale dal video successivo).
final videoEngineFactoryProvider = Provider<VideoEngine Function()>((ref) {
  final hardware =
      ref.watch(playerSettingsProvider.select((s) => s.hardwareDecoding));
  return () => MediaKitEngine(hwdec: hardware ? 'auto-safe' : 'no');
});
```

- [ ] **Step 6: controller.** In `lib/features/player/player_controller.dart`:
- aggiungi `import 'player_settings.dart';`;
- aggiungi il campo `late PlayerSettings _settings;` accanto agli altri `late`;
- in `build()`, prima di `_listenToEngine();`, aggiungi `_settings = ref.read(playerSettingsProvider);`;
- nella chiamata `_service.prepare(...)` dentro `_start`, aggiungi l'argomento `maxBitrate: _settings.quality.bitrate,`;
- subito dopo `await _engine.setVolume(_view.muted ? 0 : _view.volume);` aggiungi:

```dart
      if (_settings.subtitleScale != 1.0) {
        await _engine.setSubtitleScale(_settings.subtitleScale);
      }
```

- [ ] **Step 7: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 8: commit**

```bash
git add lib test
git commit -m "feat: apply quality, hardware decoding and subtitle size settings"
```

---

### Task 9: controller — segmenti, episodio successivo, salto dell'intro

**Files:**
- Modify: `lib/features/player/player_controller.dart`
- Test: `test/features/player/player_controller_test.dart` (aggiunte)

- [ ] **Step 1: aggiungi i test** in fondo al `main()` di `test/features/player/player_controller_test.dart` (aggiungi in testa gli import di `package:wonderflix/core/jellyfin/playback_models.dart` e `package:wonderflix/core/jellyfin/item_models.dart` se mancano):

```dart
  test('segmenti ed episodio successivo caricati dopo la partenza', () async {
    library.itemsById['m1'] =
        testItem(id: 'm1', kind: ItemKind.episode, seriesId: 's1');
    library.nextEpisodes['m1'] =
        testItem(id: 'm2', kind: ItemKind.episode, seriesId: 's1');
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    await start();
    expect(view().segments.single.type, MediaSegmentType.intro);
    expect(view().nextEpisode?.id, 'm2');
    expect(library.nextEpisodeCalls, ['m1']);
    expect(playback.segmentsCalls, ['m1']);
  });

  test('film: nessun episodio successivo; segmenti non disponibili ignorati',
      () async {
    playback.segmentsError = const ServerUnreachableException();
    await start();
    expect(view().status, PlayerStatus.ready);
    expect(view().segments, isEmpty);
    expect(view().nextEpisode, isNull);
    expect(library.nextEpisodeCalls, isEmpty);
  });

  test('salta il segmento in corso', () async {
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.recap,
          start: Duration.zero,
          end: Duration(seconds: 60)),
    ];
    final controller = await start();
    engine.emitPosition(const Duration(seconds: 5));
    await controller.skipCurrentSegment();
    expect(engine.seeks.last, const Duration(seconds: 60));
  });

  test('salto automatico dell\'intro: una volta sola', () async {
    settings = const PlayerSettings(autoSkipIntro: true);
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    await start();
    engine.emitPosition(const Duration(seconds: 20));
    await pumpEventQueue();
    expect(engine.seeks, [const Duration(seconds: 90)]);

    // Tornando indietro nell'intro non la salta più.
    engine.emitPosition(const Duration(seconds: 30));
    await pumpEventQueue();
    expect(engine.seeks, hasLength(1));
  });

  test('salto automatico spento: nessun salto', () async {
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    await start();
    engine.emitPosition(const Duration(seconds: 20));
    await pumpEventQueue();
    expect(engine.seeks, isEmpty);
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/player/player_controller_test.dart`
Expected: FAIL (`segments`, `nextEpisode`, `skipCurrentSegment` non esistono).

- [ ] **Step 3: stato.** In `PlayerViewState` (`lib/features/player/player_controller.dart`):
- aggiungi al costruttore `this.segments = const [],` e `this.nextEpisode,`;
- aggiungi i campi:

```dart
  /// Intro, riassunto, crediti… (vuoto finché non sono caricati).
  final List<MediaSegment> segments;

  /// Episodio che segue quello in riproduzione (solo per le serie).
  final JellyfinItem? nextEpisode;
```

- in `copyWith` aggiungi i parametri `List<MediaSegment>? segments,` e `JellyfinItem? nextEpisode,` e, nel costruttore restituito, `segments: segments ?? this.segments,` e `nextEpisode: nextEpisode ?? this.nextEpisode,`.

- [ ] **Step 4: controller.** In `PlayerController`:
- aggiungi `import 'segments.dart';`;
- aggiungi i campi:

```dart
  /// Segmenti ed episodio successivo si caricano una volta sola.
  bool _extrasRequested = false;

  /// Inizio dei segmenti già saltati in automatico.
  final _autoSkipped = <Duration>{};
```

- in `_listenToEngine`, dentro la lista, aggiungi `_engine.positionStream.listen(_onPosition),`;
- in `_start`, subito dopo l'`_emit(...)` che porta lo stato a `ready`, aggiungi:

```dart
      if (!_extrasRequested) {
        _extrasRequested = true;
        unawaited(_loadExtras(item));
      }
```

- dopo `shiftSubtitleDelay` aggiungi:

```dart
  /// Salta l'intro o il riassunto in corso.
  Future<void> skipCurrentSegment() async {
    final target = skipTargetAt(_view.segments, _engine.position);
    if (target != null) await seekTo(target.end);
  }

  /// Salto automatico di intro e riassunti (se attivo nelle impostazioni):
  /// una volta per segmento, così tornando indietro lo si può rivedere.
  void _onPosition(Duration position) {
    if (!_settings.autoSkipIntro || !_ready) return;
    final target = skipTargetAt(_view.segments, position);
    if (target == null || !_autoSkipped.add(target.segment.start)) return;
    unawaited(seekTo(target.end));
  }

  /// Segmenti ed episodio successivo, a riproduzione già partita: se non
  /// arrivano il player funziona lo stesso, senza pulsanti extra.
  Future<void> _loadExtras(JellyfinItem item) async {
    Future<T> safely<T>(Future<T> Function() load, T fallback, String what) async {
      try {
        return await load();
      } on Object catch (error) {
        debugPrint('[player] $what non disponibili: $error');
        return fallback;
      }
    }

    final seriesId = item.seriesId;
    final segments = safely(
        () => _api.mediaSegments(item.id), const <MediaSegment>[], 'segmenti');
    final next = item.kind == ItemKind.episode && seriesId != null
        ? safely<JellyfinItem?>(
            () => _library.nextEpisode(_userId, seriesId, item.id),
            null,
            'episodio successivo')
        : Future<JellyfinItem?>.value();
    final loadedSegments = await segments;
    final loadedNext = await next;
    if (_closing != null) return;
    _emit(_view.copyWith(segments: loadedSegments, nextEpisode: loadedNext));
  }
```

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 6: commit**

```bash
git add lib/features/player/player_controller.dart test/features/player/player_controller_test.dart
git commit -m "feat: load media segments and next episode, skip intro"
```

---

### Task 10: stringhe del Piano 3b

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan3b_test.dart`

- [ ] **Step 1: scrivi il test** `test/app/l10n_plan3b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 3b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerNextEpisodeIn(7), 'Inizia tra 7 s');
    expect(en.playerNextEpisodeIn(7), 'Starts in 7 s');
    expect(it.settingsQualityMbps(8), '8 Mbps');
    expect(it.playerSkipIntro, 'Salta intro');
    expect(en.settingsSubtitleModeOnlyForced, 'Forced only');
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter gen-l10n && flutter test test/app/l10n_plan3b_test.dart`
Expected: FAIL (stringhe mancanti).

- [ ] **Step 3: aggiungi le stringhe.** In `l10n/app_it.arb`, prima della `}` finale (virgola dopo l'ultima voce esistente):

```json
  "playerSkipIntro": "Salta intro",
  "playerSkipRecap": "Salta riassunto",
  "playerNextEpisode": "Episodio successivo",
  "playerNextEpisodeTitle": "Prossimo episodio",
  "playerNextEpisodeIn": "Inizia tra {seconds} s",
  "@playerNextEpisodeIn": {"placeholders": {"seconds": {"type": "int"}}},
  "playerPlayNow": "Riproduci ora",
  "playerCancel": "Annulla",
  "settingsPlayer": "Player",
  "settingsPlayerHint": "Le modifiche valgono dal prossimo video.",
  "settingsQuality": "Qualità dello streaming",
  "settingsQualityOriginal": "Originale",
  "settingsQualityMbps": "{mbps} Mbps",
  "@settingsQualityMbps": {"placeholders": {"mbps": {"type": "int"}}},
  "settingsSubtitleSize": "Dimensione dei sottotitoli",
  "settingsSubtitleSmall": "Piccoli",
  "settingsSubtitleNormal": "Normali",
  "settingsSubtitleLarge": "Grandi",
  "settingsSubtitleHuge": "Molto grandi",
  "settingsHardwareDecoding": "Decodifica hardware",
  "settingsAutoSkipIntro": "Salta automaticamente intro e riassunti",
  "settingsAutoplayNext": "Avvia automaticamente il prossimo episodio",
  "settingsLanguages": "Lingue di riproduzione",
  "settingsLanguagesHint": "Salvate sul server: valgono anche negli altri client Jellyfin.",
  "settingsAudioLanguage": "Lingua dell'audio",
  "settingsSubtitleLanguage": "Lingua dei sottotitoli",
  "settingsSubtitleMode": "Quando mostrare i sottotitoli",
  "settingsLanguageAny": "Qualsiasi",
  "settingsSubtitleModeDefault": "Predefinito",
  "settingsSubtitleModeAlways": "Sempre",
  "settingsSubtitleModeOnlyForced": "Solo forzati",
  "settingsSubtitleModeNone": "Mai",
  "settingsSubtitleModeSmart": "Se l'audio è in un'altra lingua",
  "settingsSaveError": "Impossibile salvare. Riprova."
```

In `l10n/app_en.arb`, allo stesso modo:

```json
  "playerSkipIntro": "Skip intro",
  "playerSkipRecap": "Skip recap",
  "playerNextEpisode": "Next episode",
  "playerNextEpisodeTitle": "Next episode",
  "playerNextEpisodeIn": "Starts in {seconds} s",
  "@playerNextEpisodeIn": {"placeholders": {"seconds": {"type": "int"}}},
  "playerPlayNow": "Play now",
  "playerCancel": "Cancel",
  "settingsPlayer": "Player",
  "settingsPlayerHint": "Changes apply from the next video.",
  "settingsQuality": "Streaming quality",
  "settingsQualityOriginal": "Original",
  "settingsQualityMbps": "{mbps} Mbps",
  "@settingsQualityMbps": {"placeholders": {"mbps": {"type": "int"}}},
  "settingsSubtitleSize": "Subtitle size",
  "settingsSubtitleSmall": "Small",
  "settingsSubtitleNormal": "Normal",
  "settingsSubtitleLarge": "Large",
  "settingsSubtitleHuge": "Extra large",
  "settingsHardwareDecoding": "Hardware decoding",
  "settingsAutoSkipIntro": "Automatically skip intros and recaps",
  "settingsAutoplayNext": "Automatically play the next episode",
  "settingsLanguages": "Playback languages",
  "settingsLanguagesHint": "Saved on the server: they also apply to other Jellyfin clients.",
  "settingsAudioLanguage": "Audio language",
  "settingsSubtitleLanguage": "Subtitle language",
  "settingsSubtitleMode": "When to show subtitles",
  "settingsLanguageAny": "Any",
  "settingsSubtitleModeDefault": "Default",
  "settingsSubtitleModeAlways": "Always",
  "settingsSubtitleModeOnlyForced": "Forced only",
  "settingsSubtitleModeNone": "Never",
  "settingsSubtitleModeSmart": "When the audio is in another language",
  "settingsSaveError": "Couldn't save. Try again."
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter gen-l10n && flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 5: commit**

```bash
git add l10n test/app/l10n_plan3b_test.dart
git commit -m "feat: add plan 3b strings"
```

---

### Task 11: barra di avanzamento con capitoli e anteprime

**Files:**
- Modify: `lib/features/player/seek_bar.dart`, `lib/features/player/player_providers.dart`
- Create: `lib/features/player/trickplay_preview.dart`
- Test: `test/features/player/seek_bar_test.dart` (aggiunte), `test/features/player/trickplay_preview_test.dart`

- [ ] **Step 1: aggiungi i test.**

In fondo al `main()` di `test/features/player/seek_bar_test.dart` (import in testa: `package:flutter/gestures.dart`, `package:wonderflix/core/jellyfin/item_models.dart`):

```dart
  testWidgets('tacche dei capitoli (non quella all\'inizio)', (tester) async {
    final engine = FakeVideoEngine();
    await pumpApp(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(40),
          child: SeekBar(
            engine: engine,
            onSeek: (_) {},
            chapters: const [
              ChapterMark(start: Duration.zero, name: 'Inizio'),
              ChapterMark(start: Duration(minutes: 30), name: 'Arrakis'),
              ChapterMark(start: Duration(hours: 1), name: 'Deserto'),
            ],
          ),
        ),
      ),
    );
    final paint = tester.widget<CustomPaint>(find.byKey(const Key('chapter-ticks')));
    expect((paint.painter! as ChapterTicksPainter).fractions, [0.25, 0.5]);
  });

  testWidgets('anteprima al passaggio del mouse: tempo, capitolo, immagine',
      (tester) async {
    final engine = FakeVideoEngine();
    final previews = <Duration>[];
    await pumpApp(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(40, 300, 40, 40),
          child: SeekBar(
            engine: engine,
            onSeek: (_) {},
            chapters: const [
              ChapterMark(start: Duration.zero, name: 'Inizio'),
              ChapterMark(start: Duration(minutes: 45), name: 'Arrakis'),
            ],
            preview: (position) {
              previews.add(position);
              return const SizedBox(
                  key: Key('preview-image'), width: 240, height: 135);
            },
          ),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(SeekBar)));
    await tester.pump();
    expect(find.text('1:00:00 · Arrakis'), findsOneWidget);
    expect(find.byKey(const Key('preview-image')), findsOneWidget);
    expect(previews.last, const Duration(hours: 1));

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('1:00:00 · Arrakis'), findsNothing);
  });

  test('chapterAt', () {
    const chapters = [
      ChapterMark(start: Duration.zero, name: 'A'),
      ChapterMark(start: Duration(minutes: 10), name: 'B'),
    ];
    expect(chapterAt(chapters, const Duration(minutes: 5))?.name, 'A');
    expect(chapterAt(chapters, const Duration(minutes: 10))?.name, 'B');
    expect(chapterAt(const [], Duration.zero), isNull);
  });
```

Crea `test/features/player/trickplay_preview_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/trickplay.dart';
import 'package:wonderflix/features/player/trickplay_preview.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('ritaglia la cella del mosaico con l\'autenticazione',
      (tester) async {
    final urls = <String>[];
    await pumpApp(
      tester,
      const Center(
        child: TrickplayPreview(
          url: 'https://media.example.com/Videos/m1/Trickplay/320/3.jpg',
          info: TrickplayInfo(
            width: 320,
            height: 180,
            tileWidth: 10,
            tileHeight: 10,
            thumbnailCount: 700,
            interval: Duration(seconds: 10),
          ),
          tile: TrickplayTile(sheet: 3, column: 2, row: 6),
        ),
      ),
      overrides: [
        authImageProvider.overrideWithValue((url) {
          urls.add(url);
          return MemoryImage(Uint8List.fromList(transparentPng));
        }),
      ],
    );
    expect(urls, ['https://media.example.com/Videos/m1/Trickplay/320/3.jpg']);
    expect(tester.getSize(find.byType(TrickplayPreview)), const Size(240, 135));
  });
}
```

In fondo a `test/support/playback_fakes.dart` aggiungi l'immagine di prova:

```dart
/// PNG trasparente 1×1, per sostituire le immagini di rete nei test.
const transparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/player/seek_bar_test.dart test/features/player/trickplay_preview_test.dart`
Expected: FAIL (parametri, classi e provider mancanti).

- [ ] **Step 3: immagini con autenticazione.** In `lib/features/player/player_providers.dart`:
- aggiungi gli import `package:cached_network_image/cached_network_image.dart`, `package:flutter/widgets.dart` e `../../ui/wf_image.dart`;
- in fondo aggiungi:

```dart
/// Immagine che richiede l'header di autenticazione (mosaici trickplay).
final authImageProvider = Provider<ImageProvider Function(String url)>((ref) {
  final http = ref.watch(jellyfinHttpProvider);
  return (url) => CachedNetworkImageProvider(
        url,
        headers: {'Authorization': http.authorizationHeader},
        cacheManager: wonderflixImageCache,
      );
});
```

- [ ] **Step 4: crea** `lib/features/player/trickplay_preview.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import 'player_providers.dart';
import 'trickplay.dart';

/// Una cella di un mosaico trickplay, ridimensionata a [width].
class TrickplayPreview extends ConsumerWidget {
  const TrickplayPreview({
    super.key,
    required this.url,
    required this.info,
    required this.tile,
    this.width = 240,
  });

  final String url;
  final TrickplayInfo info;
  final TrickplayTile tile;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = width / info.width;
    final cellWidth = info.width * scale;
    final cellHeight = info.height * scale;
    final sheetWidth = cellWidth * info.tileWidth;
    final sheetHeight = cellHeight * info.tileHeight;
    return SizedBox(
      width: cellWidth,
      height: cellHeight,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: sheetWidth,
          maxHeight: sheetHeight,
          child: Transform.translate(
            offset: Offset(-tile.column * cellWidth, -tile.row * cellHeight),
            child: Image(
              image: ref.watch(authImageProvider)(url),
              width: sheetWidth,
              height: sheetHeight,
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: barra.** In `lib/features/player/seek_bar.dart`:
- aggiungi l'import `../../core/jellyfin/item_models.dart`;
- sostituisci **solo** le classi `SeekBar` e `_SeekBarState` (lascia `TimeLabel` com'è) con:

```dart
/// Capitolo in corso in [position] (l'ultimo iniziato).
ChapterMark? chapterAt(List<ChapterMark> chapters, Duration position) {
  ChapterMark? current;
  for (final chapter in chapters) {
    if (chapter.start <= position) current = chapter;
  }
  return current;
}

/// Tacche dei capitoli sulla traccia della barra.
class ChapterTicksPainter extends CustomPainter {
  ChapterTicksPainter({required this.fractions, required this.inset});

  /// Posizione di ogni tacca, 0–1.
  final List<double> fractions;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = WfColors.cream.withValues(alpha: 0.7);
    final track = size.width - 2 * inset;
    for (final fraction in fractions) {
      final x = inset + fraction.clamp(0.0, 1.0) * track;
      canvas.drawRect(
          Rect.fromCenter(center: Offset(x, size.height / 2), width: 2, height: 10),
          paint);
    }
  }

  @override
  bool shouldRepaint(ChapterTicksPainter oldDelegate) =>
      !listEquals(oldDelegate.fractions, fractions) || oldDelegate.inset != inset;
}

/// Barra di avanzamento: posizione, parte già scaricata, tacche dei
/// capitoli, anteprima al passaggio del mouse, salto con clic o
/// trascinamento.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.engine,
    required this.onSeek,
    this.chapters = const [],
    this.preview,
  });

  final VideoEngine engine;
  final ValueChanged<Duration> onSeek;
  final List<ChapterMark> chapters;

  /// Immagine di anteprima per una posizione (trickplay); `null` = solo il
  /// tempo.
  final Widget? Function(Duration position)? preview;

  /// Margine orizzontale della traccia dentro lo Slider (= raggio
  /// dell'alone del cursore): serve a sapere a che punto è il mouse.
  static const trackInset = 16.0;

  static const previewWidth = 240.0;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  late Duration _position;
  late Duration _duration;
  late Duration _buffer;

  /// Valore durante il trascinamento (secondi): non segue il video.
  double? _dragSeconds;

  /// Posizione orizzontale del mouse sopra la barra.
  double? _hoverX;
  final _subscriptions = <StreamSubscription<Duration>>[];

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
    super.dispose();
  }

  static double _seconds(Duration duration) => duration.inMilliseconds / 1000;

  @override
  Widget build(BuildContext context) {
    final durationSeconds = _seconds(_duration);
    final max = math.max(durationSeconds, 1.0);
    double clamp(double value) => value.clamp(0.0, max);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final track = math.max(width - 2 * SeekBar.trackInset, 1.0);
      Duration positionAt(double x) {
        final fraction = ((x - SeekBar.trackInset) / track).clamp(0.0, 1.0);
        return Duration(milliseconds: (fraction * durationSeconds * 1000).round());
      }

      final hoverX = _hoverX;
      final hovered = hoverX == null || durationSeconds <= 0
          ? null
          : positionAt(hoverX);
      return MouseRegion(
        onHover: (event) => setState(() => _hoverX = event.localPosition.dx),
        onExit: (_) => setState(() => _hoverX = null),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (durationSeconds > 0 && widget.chapters.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('chapter-ticks'),
                    painter: ChapterTicksPainter(
                      fractions: [
                        for (final chapter in widget.chapters)
                          if (chapter.start > Duration.zero)
                            _seconds(chapter.start) / durationSeconds,
                      ],
                      inset: SeekBar.trackInset,
                    ),
                  ),
                ),
              ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: WfColors.gold,
                secondaryActiveTrackColor: WfColors.cream.withValues(alpha: 0.35),
                inactiveTrackColor: WfColors.cream.withValues(alpha: 0.15),
                thumbColor: WfColors.gold,
                overlayColor: WfColors.gold.withValues(alpha: 0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: SeekBar.trackInset),
              ),
              child: Slider(
                value: clamp(_dragSeconds ?? _seconds(_position)),
                max: max,
                secondaryTrackValue: clamp(_seconds(_buffer)),
                onChangeStart: (value) => setState(() => _dragSeconds = value),
                onChanged: (value) => setState(() => _dragSeconds = value),
                onChangeEnd: (value) {
                  final target = Duration(milliseconds: (value * 1000).round());
                  setState(() {
                    _dragSeconds = null;
                    _position = target;
                  });
                  widget.onSeek(target);
                },
              ),
            ),
            if (hoverX != null && hovered != null)
              Positioned(
                left: (hoverX - SeekBar.previewWidth / 2).clamp(
                    0.0, math.max(width - SeekBar.previewWidth, 0.0)),
                bottom: 40,
                width: SeekBar.previewWidth,
                child: IgnorePointer(
                  child: _SeekPreview(
                    position: hovered,
                    chapter: chapterAt(widget.chapters, hovered),
                    image: widget.preview?.call(hovered),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview({required this.position, this.chapter, this.image});

  final Duration position;
  final ChapterMark? chapter;
  final Widget? image;

  @override
  Widget build(BuildContext context) {
    final name = chapter?.name;
    final picture = image;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (picture != null)
          ClipRRect(borderRadius: BorderRadius.circular(6), child: picture),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name == null
                ? formatClock(position)
                : '${formatClock(position)} · $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: WfColors.cream),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS (anche i test del Piano 3a sulla barra).

- [ ] **Step 7: commit**

```bash
git add lib/features/player test/features/player test/support/playback_fakes.dart
git commit -m "feat: show chapter ticks and trickplay previews on the seek bar"
```

---

### Task 12: widget per intro e prossimo episodio

**Files:**
- Create: `lib/features/player/player_extras.dart`
- Test: `test/features/player/player_extras_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/player_extras_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_extras.dart';

import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('PositionSelector ricostruisce solo quando cambia il valore',
      (tester) async {
    final engine = FakeVideoEngine();
    var builds = 0;
    await pumpApp(
      tester,
      PositionSelector<bool>(
        engine: engine,
        select: (position) => position >= const Duration(minutes: 1),
        builder: (context, after) {
          builds++;
          return Text(after ? 'dopo' : 'prima');
        },
      ),
    );
    expect(find.text('prima'), findsOneWidget);
    final initial = builds;
    engine.emitPosition(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump();
    expect(builds, initial, reason: 'valore invariato');
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();
    await tester.pump();
    expect(find.text('dopo'), findsOneWidget);
    expect(builds, initial + 1);
  });

  final episode = testItem(
      id: 'e5',
      name: 'Cat in the Bag',
      kind: ItemKind.episode,
      seriesName: 'Breaking Bad',
      index: 5,
      seasonIndex: 1);

  testWidgets('scheda: conto alla rovescia di 10 s, poi riproduce',
      (tester) async {
    var played = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: NextEpisodeCard(
            episode: episode,
            countdown: true,
            onPlay: () => played++,
            onCancel: () {},
          ),
        ),
      ),
    );
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    expect(find.text('Inizia tra 10 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Inizia tra 9 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(played, 1);
  });

  testWidgets('scheda senza conto alla rovescia: solo i pulsanti',
      (tester) async {
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
    );
    expect(find.textContaining('Inizia tra'), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(played, 0);
    await tester.tap(find.text('Riproduci ora'));
    await tester.tap(find.text('Annulla'));
    expect(played, 1);
    expect(cancelled, 1);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/player_extras_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/player_extras.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';

/// Ricostruisce [builder] solo quando cambia il valore che [select] ricava
/// dalla posizione del video (la posizione cambia molte volte al secondo).
class PositionSelector<T> extends StatefulWidget {
  const PositionSelector({
    super.key,
    required this.engine,
    required this.select,
    required this.builder,
  });

  final VideoEngine engine;
  final T Function(Duration position) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<PositionSelector<T>> createState() => _PositionSelectorState<T>();
}

class _PositionSelectorState<T> extends State<PositionSelector<T>> {
  late T _value;
  StreamSubscription<Duration>? _subscription;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.engine.position);
    _subscription = widget.engine.positionStream.listen((position) {
      final value = widget.select(position);
      if (value != _value) setState(() => _value = value);
    });
  }

  @override
  void didUpdateWidget(PositionSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // [select] può dipendere da dati arrivati dopo (es. i segmenti).
    _value = widget.select(widget.engine.position);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// Scheda "Prossimo episodio": con [countdown] parte da sola dopo
/// [countdownFrom] secondi.
class NextEpisodeCard extends ConsumerStatefulWidget {
  const NextEpisodeCard({
    super.key,
    required this.episode,
    required this.countdown,
    required this.onPlay,
    required this.onCancel,
  });

  final JellyfinItem episode;
  final bool countdown;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  static const countdownFrom = 10;

  @override
  ConsumerState<NextEpisodeCard> createState() => _NextEpisodeCardState();
}

class _NextEpisodeCardState extends ConsumerState<NextEpisodeCard> {
  int _left = NextEpisodeCard.countdownFrom;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.countdown) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_left <= 1) {
          timer.cancel();
          widget.onPlay();
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
    final episode = widget.episode;
    return Material(
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
                            image: ref.watch(imageUrlsProvider).landscape(episode)),
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
              if (widget.countdown) ...[
                const SizedBox(height: 8),
                Text(l.playerNextEpisodeIn(_left),
                    style: const TextStyle(color: WfColors.creamMuted)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  WfButton.primary(
                      label: l.playerPlayNow,
                      icon: LucideIcons.play,
                      onPressed: widget.onPlay),
                  WfButton.secondary(
                      label: l.playerCancel,
                      icon: LucideIcons.x,
                      onPressed: widget.onCancel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/player_extras_test.dart`
Expected: PASS.

- [ ] **Step 5: analizza e commit**

```bash
flutter analyze
git add lib/features/player/player_extras.dart test/features/player/player_extras_test.dart
git commit -m "feat: add position selector and next-episode card"
```

---

### Task 13: overlay — capitoli, anteprime, episodio successivo

**Files:**
- Modify: `lib/features/player/player_overlay.dart`
- Test: `test/features/player/player_overlay_test.dart` (aggiunte)

I nuovi parametri sono facoltativi: la schermata continua a compilare e li userà nel Task 14.

- [ ] **Step 1: aggiungi i test** in fondo al `main()` di `test/features/player/player_overlay_test.dart` (aggiungi in testa l'import di `package:wonderflix/features/player/seek_bar.dart`):

```dart
  testWidgets('episodio successivo, capitoli e anteprima', (tester) async {
    var next = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: PlayerOverlay(
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
          onNextEpisode: () => next++,
          chapters: const [ChapterMark(start: Duration(minutes: 10))],
          preview: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Episodio successivo'));
    expect(next, 1);
    final bar = tester.widget<SeekBar>(find.byType(SeekBar));
    expect(bar.chapters, hasLength(1));
    expect(bar.preview, isNotNull);
  });

  testWidgets('senza episodio successivo: nessun pulsante', (tester) async {
    await pumpOverlay(tester,
        const PlayerViewState(status: PlayerStatus.ready, playing: true));
    expect(find.byTooltip('Episodio successivo'), findsNothing);
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/player/player_overlay_test.dart`
Expected: FAIL (parametri mancanti).

- [ ] **Step 3: implementa** in `lib/features/player/player_overlay.dart`:
- aggiungi al costruttore `this.onNextEpisode,`, `this.chapters = const [],` e `this.preview,` e i campi:

```dart
  /// `null` se non c'è un episodio successivo.
  final VoidCallback? onNextEpisode;
  final List<ChapterMark> chapters;
  final Widget? Function(Duration position)? preview;
```

- sostituisci `SeekBar(engine: engine, onSeek: onSeekTo),` con:

```dart
                    SeekBar(
                      engine: engine,
                      onSeek: onSeekTo,
                      chapters: chapters,
                      preview: preview,
                    ),
```

- nella `Row` dei comandi, subito dopo `const Spacer(),`, aggiungi:

```dart
                        if (onNextEpisode != null)
                          IconButton(
                            icon: const Icon(LucideIcons.skipForward),
                            tooltip: l.playerNextEpisode,
                            onPressed: onNextEpisode,
                          ),
```

- [ ] **Step 4: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/player/player_overlay.dart test/features/player/player_overlay_test.dart
git commit -m "feat: add next-episode button, chapters and previews to the overlay"
```

---

### Task 14: schermata — salta intro, prossimo episodio, schermo intero conservato

**Files:**
- Modify: `lib/features/player/player_commands.dart`, `lib/app/navigation.dart`, `lib/app/router.dart`, `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_commands_test.dart`, `test/app/navigation_test.dart`, `test/features/player/player_screen_test.dart` (aggiunte e harness)

- [ ] **Step 1: aggiungi i test brevi.**

In `test/features/player/player_commands_test.dart`, dentro il test `'tasti della spec'`:

```dart
    expect(playerCommandFor(down(LogicalKeyboardKey.keyN)),
        PlayerCommand.nextEpisode);
    expect(playerCommandFor(down(LogicalKeyboardKey.mediaTrackNext)),
        PlayerCommand.nextEpisode);
```

In fondo al `main()` di `test/app/navigation_test.dart`:

```dart
  test('playerRoute con schermo intero', () {
    expect(playerRoute('e5', fullscreen: true), '/play/e5?fs=1');
    expect(
        playerRoute('e5', start: const Duration(seconds: 1), fullscreen: true),
        '/play/e5?start=1000&fs=1');
  });
```

- [ ] **Step 2: aggiorna l'harness di `test/features/player/player_screen_test.dart`.**
- import in testa: `package:wonderflix/app/navigation.dart`, `package:wonderflix/app/providers.dart`, `package:wonderflix/core/jellyfin/playback_models.dart`, `package:wonderflix/ui/wf_image.dart`, `dart:typed_data`, `../../support/pump_app.dart` (per `testAppConfig`).
- sposta la `FakeLibraryApi` fuori da `pumpPlayer`: `late FakeLibraryApi library;` accanto alle altre variabili e, nel `setUp`:

```dart
    library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(
        id: 'e4',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 4,
        seasonIndex: 1,
      );
    authImageUrls = [];
```

- aggiungi `late List<String> authImageUrls;`;
- in `pumpPlayer` elimina la creazione locale della libreria e cambia la route del player, come nel router dell'app:

```dart
      GoRoute(
        path: '/play/:id',
        builder: (context, state) => PlayerScreen(
          key: ValueKey(state.uri.toString()),
          args: (
            itemId: state.pathParameters['id']!,
            start: playerStartFrom(state.uri),
          ),
          fullscreen: state.uri.queryParameters['fs'] == '1',
        ),
      ),
```

- aggiungi alla lista `overrides`:

```dart
        appConfigProvider.overrideWithValue(testAppConfig),
        imageBuilderProvider
            .overrideWithValue((image, fit) => const ColoredBox(color: Color(0xFF333333))),
        authImageProvider.overrideWithValue((url) {
          authImageUrls.add(url);
          return MemoryImage(Uint8List.fromList(transparentPng));
        }),
```

- [ ] **Step 3: aggiungi i test della schermata** in fondo al `main()`:

```dart
  JellyfinItem episode5() => testItem(
        id: 'e5',
        name: 'Cat in the Bag',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 5,
        seasonIndex: 1,
      );

  void withNextEpisode() {
    final next = episode5();
    library.itemsById['e5'] = next;
    library.nextEpisodes['e4'] = next;
  }

  testWidgets('salta intro: pulsante durante l\'intro', (tester) async {
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
    await tester.tap(find.text('Salta intro'));
    await tester.pump();
    expect(engine.seeks.last, const Duration(seconds: 90));
    await unmount(tester);
  });

  testWidgets('prossimo episodio: scheda e conto alla rovescia', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.text('Inizia tra 10 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    expect(playback.stopped.first.itemId, 'e4');
    await unmount(tester);
  });

  testWidgets('Annulla: a fine episodio si esce', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Annulla'));
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);

    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('fine episodio: parte il successivo', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('riproduzione automatica spenta: niente conto alla rovescia',
      (tester) async {
    settings = const PlayerSettings(autoplayNext: false);
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.textContaining('Inizia tra'), findsNothing);

    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('N a schermo intero: il successivo resta a schermo intero',
      (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    expect(window.fullScreenCalls, [true], reason: 'mai uscito');
    expect(find.byTooltip('Esci da schermo intero'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('anteprima trickplay sulla barra', (tester) async {
    library.itemsById['e4'] = JellyfinItem.fromJson({
      'Id': 'e4',
      'Name': 'Pilot',
      'Type': 'Episode',
      'Trickplay': {
        'ms1': {
          '320': {
            'Width': 320,
            'Height': 180,
            'TileWidth': 10,
            'TileHeight': 10,
            'ThumbnailCount': 700,
            'Interval': 10000,
          },
        },
      },
    });
    await pumpPlayer(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(SeekBar)));
    await tester.pump();
    expect(authImageUrls.last,
        'https://media.example.com/Videos/e4/Trickplay/320/3.jpg?mediaSourceId=ms1');
    await unmount(tester);
  });
```

Aggiungi in testa l'import di `package:wonderflix/features/player/seek_bar.dart`.

- [ ] **Step 4: esegui e verifica che falliscano**

Run: `flutter test test/features/player test/app/navigation_test.dart`
Expected: FAIL (comando, parametro `fullscreen` e comportamento mancanti).

- [ ] **Step 5: comando N.** In `lib/features/player/player_commands.dart`:
- nell'enum `PlayerCommand`, dopo `subtitleDelayUp,`, aggiungi `nextEpisode,`;
- nella mappa `_commands` aggiungi:

```dart
  LogicalKeyboardKey.keyN: PlayerCommand.nextEpisode,
  LogicalKeyboardKey.mediaTrackNext: PlayerCommand.nextEpisode,
```

- [ ] **Step 6: percorso con schermo intero.** In `lib/app/navigation.dart` sostituisci `playerRoute` con:

```dart
/// Percorso del player; [start] è la posizione di partenza, [fullscreen]
/// dice che la finestra è già a schermo intero (passaggio all'episodio
/// successivo).
String playerRoute(String itemId,
    {Duration start = Duration.zero, bool fullscreen = false}) {
  final query = {
    if (start > Duration.zero) 'start': '${start.inMilliseconds}',
    if (fullscreen) 'fs': '1',
  };
  return Uri(
    path: '/play/$itemId',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}
```

In `lib/app/router.dart`, nella route `/play/:id`, aggiungi a `PlayerScreen(...)` l'argomento `fullscreen: state.uri.queryParameters['fs'] == '1',`.

- [ ] **Step 7: schermata.** Sostituisci `lib/features/player/player_screen.dart` con:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../detail/primary_action.dart';
import '../library/user_data.dart';
import 'player_commands.dart';
import 'player_controller.dart';
import 'player_extras.dart';
import 'player_overlay.dart';
import 'player_providers.dart';
import 'player_settings.dart';
import 'player_window.dart';
import 'segments.dart';
import 'tracks_panel.dart';
import 'trickplay.dart';
import 'trickplay_preview.dart';

/// Schermata del player: video a tutta finestra, controlli in
/// sovrimpressione, tastiera, schermo intero, salta intro, prossimo
/// episodio e chiusura sicura della finestra (prima si segnala la fine a
/// Jellyfin).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args, this.fullscreen = false});

  final PlayerArgs args;

  /// La finestra è già a schermo intero (arrivo dall'episodio precedente).
  final bool fullscreen;

  /// Inattività del mouse dopo cui i controlli spariscono.
  static const hideDelay = Duration(seconds: 3);

  /// Attesa massima del report di fine alla chiusura della finestra.
  static const closeTimeout = Duration(seconds: 2);

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlayerWindow _window;
  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _tracksOpen = false;
  late bool _fullscreen = widget.fullscreen;
  bool _leaving = false;

  /// Si passa all'episodio successivo: la finestra resta com'è.
  bool _handingOver = false;

  /// L'utente ha chiuso la scheda "Prossimo episodio".
  bool _nextCardDismissed = false;

  PlayerController get _controller =>
      ref.read(playerControllerProvider(widget.args).notifier);

  @override
  void initState() {
    super.initState();
    _window = ref.read(playerWindowProvider);
    _window.addCloseListener(_onWindowClose);
    unawaited(_window.setPreventClose(true));
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _window.removeCloseListener(_onWindowClose);
    unawaited(_window.setPreventClose(false));
    if (_fullscreen && !_handingOver) unawaited(_window.setFullScreen(false));
    super.dispose();
  }

  Future<void> _onWindowClose() async {
    await _controller
        .close()
        .timeout(PlayerScreen.closeTimeout, onTimeout: () {});
    await _window.destroy();
  }

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

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    await _window.setFullScreen(next);
  }

  void _exit() {
    if (_leaving) return;
    _leaving = true;
    unawaited(_controller.close());
    if (_fullscreen) {
      _fullscreen = false;
      unawaited(_window.setFullScreen(false));
    }
    // Gli avvisi di conversione riguardano il player: non devono restare
    // (né arrivare dalla coda) sulla schermata a cui si torna.
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  /// Passa all'episodio successivo (da dove era rimasto, se iniziato),
  /// mantenendo lo schermo intero.
  void _playNext() {
    final next = ref.read(playerControllerProvider(widget.args)).nextEpisode;
    if (next == null || _leaving) return;
    _leaving = true;
    _handingOver = true;
    unawaited(_controller.close());
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    final userData =
        ref.read(userDataOverridesProvider)[next.id] ?? next.userData;
    final action = primaryActionFor(next, userData);
    final start = action is ResumeAction ? action.position : Duration.zero;
    context.pushReplacement(
        playerRoute(next.id, start: start, fullscreen: _fullscreen));
  }

  /// Fine del video: episodio successivo se previsto, altrimenti uscita.
  void _onFinished() {
    final view = ref.read(playerControllerProvider(widget.args));
    final autoplay = ref.read(playerSettingsProvider).autoplayNext;
    if (view.nextEpisode != null && autoplay && !_nextCardDismissed) {
      _playNext();
    } else {
      _exit();
    }
  }

  void _escape() {
    if (_tracksOpen) {
      setState(() => _tracksOpen = false);
    } else if (_fullscreen) {
      unawaited(_toggleFullscreen());
    } else {
      _exit();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final command = playerCommandFor(event,
        altPressed: HardwareKeyboard.instance.isAltPressed);
    if (command == null) return KeyEventResult.ignored;
    _run(command);
    return KeyEventResult.handled;
  }

  void _run(PlayerCommand command) {
    final controller = _controller;
    switch (command) {
      case PlayerCommand.togglePlay:
        unawaited(controller.togglePlay());
      case PlayerCommand.seekBack:
        unawaited(controller.seekBy(-seekStep));
      case PlayerCommand.seekForward:
        unawaited(controller.seekBy(seekStep));
      case PlayerCommand.volumeUp:
        unawaited(controller.changeVolumeBy(volumeStep));
      case PlayerCommand.volumeDown:
        unawaited(controller.changeVolumeBy(-volumeStep));
      case PlayerCommand.toggleMute:
        unawaited(controller.toggleMute());
      case PlayerCommand.subtitleDelayDown:
        unawaited(controller.shiftSubtitleDelay(-subtitleDelayStep));
      case PlayerCommand.subtitleDelayUp:
        unawaited(controller.shiftSubtitleDelay(subtitleDelayStep));
      case PlayerCommand.toggleFullscreen:
        unawaited(_toggleFullscreen());
      case PlayerCommand.nextEpisode:
        _playNext();
        return;
      case PlayerCommand.escape:
        _escape();
        return;
      case PlayerCommand.exit:
        _exit();
        return;
    }
    _showControls();
  }

  /// Anteprima trickplay per la barra; `null` se il server non ne ha.
  Widget? Function(Duration)? _previewFor(PlayerViewState view) {
    final item = view.item;
    final plan = view.plan;
    if (item == null || plan == null) return null;
    final mediaSourceId = plan.mediaSource.id;
    final info = pickTrickplay(item, mediaSourceId);
    if (info == null) return null;
    final serverUrl = ref.read(appConfigProvider).serverUrl;
    return (position) {
      final tile = trickplayTileAt(info, position);
      if (tile == null) return null;
      return TrickplayPreview(
        url: trickplaySheetUrl(serverUrl,
            itemId: item.id,
            width: info.width,
            sheet: tile.sheet,
            mediaSourceId: mediaSourceId),
        info: info,
        tile: tile,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = playerControllerProvider(widget.args);
    final view = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final settings = ref.watch(playerSettingsProvider);
    final next = view.nextEpisode;

    ref.listen(provider.select((s) => s.finished), (_, finished) {
      if (finished) _onFinished();
    });
    ref.listen(provider.select((s) => s.playing), (_, playing) {
      if (playing) _scheduleHide();
    });
    ref.listen(provider.select((s) => s.transcodingFallback), (_, fallback) {
      if (fallback) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.playerTranscoding)));
      }
    });

    final loading = view.status == PlayerStatus.loading ||
        (view.status == PlayerStatus.ready && view.buffering);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons & kBackMouseButton != 0) _exit();
          },
          child: MouseRegion(
            cursor: _controlsVisible
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onHover: (_) => _showControls(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_tracksOpen) {
                      setState(() => _tracksOpen = false);
                    } else {
                      unawaited(controller.togglePlay());
                    }
                  },
                  onDoubleTap: () => unawaited(_toggleFullscreen()),
                  child: controller.engine.buildView(),
                ),
                if (loading)
                  const Center(
                      child: CircularProgressIndicator(color: WfColors.gold)),
                if (view.status == PlayerStatus.error)
                  _PlayerError(
                    error: view.error,
                    onRetry: () => unawaited(controller.retry()),
                    onBack: _exit,
                  )
                else
                  // I controlli non prendono il focus della tastiera: le
                  // scorciatoie restano sempre attive.
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
                          onNextEpisode: next == null ? null : _playNext,
                          chapters: view.item?.chapters ?? const [],
                          preview: _previewFor(view),
                        ),
                      ),
                    ),
                  ),
                if (view.status == PlayerStatus.ready) ...[
                  // Salta intro / riassunto: visibile anche a controlli
                  // nascosti.
                  Positioned(
                    right: 32,
                    bottom: 150,
                    child: ExcludeFocus(
                      child: PositionSelector<SkipKind?>(
                        engine: controller.engine,
                        select: (position) =>
                            skipTargetAt(view.segments, position)?.kind,
                        builder: (context, kind) => kind == null
                            ? const SizedBox.shrink()
                            : WfButton.secondary(
                                label: kind == SkipKind.intro
                                    ? l.playerSkipIntro
                                    : l.playerSkipRecap,
                                icon: LucideIcons.skipForward,
                                onPressed: () =>
                                    unawaited(controller.skipCurrentSegment()),
                              ),
                      ),
                    ),
                  ),
                  if (next != null && !_nextCardDismissed)
                    Positioned(
                      right: 32,
                      bottom: 150,
                      child: ExcludeFocus(
                        child: PositionSelector<bool>(
                          engine: controller.engine,
                          select: (position) {
                            final from = nextEpisodeCardFrom(
                                view.segments, controller.engine.duration);
                            return from != null && position >= from;
                          },
                          builder: (context, show) => show
                              ? NextEpisodeCard(
                                  episode: next,
                                  countdown: settings.autoplayNext,
                                  onPlay: _playNext,
                                  onCancel: () =>
                                      setState(() => _nextCardDismissed = true),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
                if (_tracksOpen && view.plan != null)
                  Positioned(
                    right: 24,
                    bottom: 120,
                    child: ExcludeFocus(
                      child: TracksPanel(
                        audio: view.audioStreams,
                        subtitles: view.subtitleStreams,
                        audioIndex: view.audioIndex,
                        subtitleIndex: view.subtitleIndex,
                        subtitleDelay: view.subtitleDelay,
                        onAudio: (index) =>
                            unawaited(controller.selectAudio(index)),
                        onSubtitle: (index) =>
                            unawaited(controller.selectSubtitle(index)),
                        onDelayStep: (step) =>
                            unawaited(controller.shiftSubtitleDelay(step)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final failure = error;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.circleAlert, size: 44, color: WfColors.error),
          const SizedBox(height: 16),
          Text(l.playerErrorTitle, style: WfText.display(34)),
          const SizedBox(height: 8),
          Text(
            failure == null ? l.errorGeneric : describeError(l, failure),
            style: const TextStyle(color: WfColors.creamMuted),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            children: [
              WfButton.primary(
                  label: l.retry,
                  icon: LucideIcons.rotateCcw,
                  onPressed: onRetry),
              WfButton.secondary(
                  label: l.playerBack,
                  icon: LucideIcons.arrowLeft,
                  onPressed: onBack),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS, compresi i test della schermata del Piano 3a. Se un test resta appeso su `pumpAndSettle`, controlla che non ci sia uno spinner visibile.

- [ ] **Step 9: commit**

```bash
git add lib test
git commit -m "feat: skip intro, next-episode card and keep fullscreen across episodes"
```

---

### Task 15: trailer locali

**Files:**
- Modify: `lib/features/playback/play_launcher.dart`, `lib/features/detail/detail_header.dart`
- Test: `test/features/playback/play_launcher_test.dart`, `test/features/detail/movie_detail_test.dart` (aggiunte)

- [ ] **Step 1: aggiungi i test.**

In `test/features/playback/play_launcher_test.dart`:
- aggiungi a `pumpLauncher` il parametro `{bool fromStart = false, bool trailer = false}`;
- nel `TextButton` usa `onPressed: () => trailer ? playTrailer(context, ref, item) : playItem(context, ref, item, fromStart: fromStart),`;
- aggiungi in fondo al `main()`:

```dart
  testWidgets('trailer locale: si apre nel player dall\'inizio',
      (tester) async {
    library.localTrailerItems['m1'] = [
      testItem(id: 't1', kind: ItemKind.other),
    ];
    await pumpLauncher(
        tester, testItem(id: 'm1', localTrailers: 1, positionTicks: minutes23),
        trailer: true);
    await tapPlay(tester);
    expect(find.text('player t1 -'), findsOneWidget);
  });
```

In fondo al `main()` di `test/features/detail/movie_detail_test.dart`:

```dart
  testWidgets('solo trailer locale: pulsante presente', (tester) async {
    api.itemsById['m1'] = testItem(id: 'm1', localTrailers: 1);
    await pumpDetail(tester);
    expect(find.text('Trailer'), findsOneWidget);
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/playback test/features/detail`
Expected: FAIL (`playTrailer` non esiste e il pulsante manca).

- [ ] **Step 3: launcher.** In `lib/features/playback/play_launcher.dart`:
- aggiungi l'import `package:url_launcher/url_launcher.dart` (`debugPrint` arriva già da `material.dart`);
- in `playItem`, sostituisci le tre righe finali:

```dart
    final opened = context.push<void>(playerRoute(target.id, start: start));
    launch.pushed = true;
    await opened;
```

con `await _open(context, launch, playerRoute(target.id, start: start));`;
- in fondo al file aggiungi:

```dart
/// Apre il player e aspetta che l'utente ne esca.
Future<void> _open(BuildContext context, _Launch launch, String route) async {
  final opened = context.push<void>(route);
  launch.pushed = true;
  await opened;
}

/// Primo trailer remoto con indirizzo web valido (solo `http`/`https`).
Uri? remoteTrailerUri(JellyfinItem item) {
  if (item.remoteTrailers.isEmpty) return null;
  final uri = Uri.tryParse(item.remoteTrailers.first.url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return null;
  }
  return uri;
}

/// Trailer di [item]: quello salvato sul server nel player, altrimenti il
/// trailer remoto (YouTube) nel browser.
Future<void> playTrailer(
    BuildContext context, WidgetRef ref, JellyfinItem item) async {
  if (_launchInProgress(context)) return;
  final launch = _launch = _Launch();
  try {
    if (item.localTrailerCount > 0) {
      List<JellyfinItem> trailers;
      try {
        trailers = await ref
            .read(libraryApiProvider)
            .localTrailers(ref.read(currentUserIdProvider), item.id);
      } on Object catch (error) {
        debugPrint('Trailer locali non disponibili: $error');
        trailers = const [];
      }
      if (!context.mounted) return;
      if (trailers.isNotEmpty) {
        await _open(context, launch, playerRoute(trailers.first.id));
        return;
      }
    }
    final remote = remoteTrailerUri(item);
    if (remote != null) {
      await launchUrl(remote, mode: LaunchMode.externalApplication);
    }
  } finally {
    if (identical(_launch, launch)) _launch = null;
  }
}
```

- [ ] **Step 4: pulsante Trailer.** In `lib/features/detail/detail_header.dart`:
- elimina la funzione privata `_trailerUri` e l'import di `url_launcher` (se non serve più);
- sostituisci `final trailerUri = _trailerUri(item);` con:

```dart
    final hasTrailer =
        item.localTrailerCount > 0 || remoteTrailerUri(item) != null;
```

- sostituisci il blocco `if (trailerUri != null) WfButton.secondary(...)` con:

```dart
                    if (hasTrailer)
                      WfButton.secondary(
                        label: l.actionTrailer,
                        icon: LucideIcons.clapperboard,
                        onPressed: () =>
                            unawaited(playTrailer(context, ref, item)),
                      ),
```

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 6: commit**

```bash
git add lib test
git commit -m "feat: play local trailers in the player"
```

---

### Task 16: Home — limite di data dei prossimi episodi

**Files:**
- Modify: `lib/features/home/home_data.dart`
- Test: `test/features/home/home_data_test.dart` (aggiunte)

- [ ] **Step 1: aggiungi i test** in fondo al `main()` di `test/features/home/home_data_test.dart`:

```dart
  test('prossimi episodi: solo serie guardate nell\'ultimo anno', () async {
    final api = FakeLibraryApi();
    final before = DateTime.now();
    await loadHome(api, 'u1');
    final cutoff = api.nextUpCutoffs.single!;
    expect(before.difference(cutoff).inDays, inInclusiveRange(364, 365));
  });

  test('nextUpCutoff', () {
    expect(nextUpCutoff(DateTime.utc(2026, 9, 29)), DateTime.utc(2025, 9, 29));
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/home/home_data_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa** in `lib/features/home/home_data.dart`:
- prima di `loadHome` aggiungi:

```dart
/// Come jellyfin-web: nei "Prossimi episodi" solo le serie guardate negli
/// ultimi 365 giorni.
DateTime nextUpCutoff(DateTime now) => now.subtract(const Duration(days: 365));
```

- in `loadHome` sostituisci `api.nextUp(userId, limit: 20),` con:

```dart
    api.nextUp(userId, limit: 20, dateCutoff: nextUpCutoff(DateTime.now())),
```

- [ ] **Step 4: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/home/home_data.dart test/features/home/home_data_test.dart
git commit -m "feat: limit Home next-up row to series watched in the last year"
```

---

### Task 17: Impostazioni — sezione Player

**Files:**
- Create: `lib/features/settings/player_settings_section.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/features/settings/settings_test.dart` (modifiche e aggiunte)

- [ ] **Step 1: aggiorna e aggiungi i test** in `test/features/settings/settings_test.dart`.
- Nel test `'schermata: utente, lingua, versione, esci'`: sostituisci `const SettingsScreen()` con `const Scaffold(body: SettingsScreen())` (servono Material e Switch), e prima di `pumpApp` aggiungi:

```dart
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
```

- Aggiungi in fondo al `main()` (import in testa: `package:wonderflix/features/player/player_settings.dart`):

```dart
  testWidgets('sezione Player: qualità, sottotitoli, interruttori',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    await pumpApp(tester, const Scaffold(body: SettingsScreen()), overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
    ]);

    expect(find.text('Player'), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-quality')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8 Mbps').last);
    await tester.pumpAndSettle();
    expect(prefs.getString('player.quality'), 'mbps8');

    await tester.tap(find.text('Grandi'));
    await tester.pump();
    expect(prefs.getDouble('player.subtitleScale'), 1.25);

    await tester.tap(find.text('Decodifica hardware'));
    await tester.pump();
    expect(prefs.getBool('player.hardwareDecoding'), isFalse);

    await tester.tap(find.text('Salta automaticamente intro e riassunti'));
    await tester.pump();
    expect(prefs.getBool('player.autoSkipIntro'), isTrue);

    await tester.tap(find.text('Avvia automaticamente il prossimo episodio'));
    await tester.pump();
    expect(prefs.getBool('player.autoplayNext'), isFalse);
  });
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/settings/settings_test.dart`
Expected: FAIL (sezione mancante).

- [ ] **Step 3: crea** `lib/features/settings/player_settings_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../player/player_settings.dart';

String qualityLabel(AppLocalizations l, StreamQuality quality) =>
    quality == StreamQuality.original
        ? l.settingsQualityOriginal
        : l.settingsQualityMbps(quality.bitrate ~/ 1000000);

/// Impostazioni del player salvate su questo PC.
class PlayerSettingsSection extends ConsumerWidget {
  const PlayerSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(playerSettingsProvider);
    void save(PlayerSettings next) =>
        unawaited(ref.read(playerSettingsProvider.notifier).update(next));

    final scaleLabels = {
      0.8: l.settingsSubtitleSmall,
      1.0: l.settingsSubtitleNormal,
      1.25: l.settingsSubtitleLarge,
      1.5: l.settingsSubtitleHuge,
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.settingsPlayerHint,
              style: const TextStyle(color: WfColors.creamMuted)),
          const SizedBox(height: 16),
          Text(l.settingsQuality),
          const SizedBox(height: 6),
          DropdownButton<StreamQuality>(
            key: const Key('player-quality'),
            value: settings.quality,
            items: [
              for (final quality in StreamQuality.values)
                DropdownMenuItem(
                    value: quality, child: Text(qualityLabel(l, quality))),
            ],
            onChanged: (quality) {
              if (quality != null) save(settings.copyWith(quality: quality));
            },
          ),
          const SizedBox(height: 16),
          Text(l.settingsSubtitleSize),
          const SizedBox(height: 6),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: [
              for (final scale in subtitleScaleOptions)
                ButtonSegment(value: scale, label: Text(scaleLabels[scale]!)),
            ],
            selected: {settings.subtitleScale},
            onSelectionChanged: (selection) =>
                save(settings.copyWith(subtitleScale: selection.first)),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsHardwareDecoding),
            value: settings.hardwareDecoding,
            onChanged: (value) =>
                save(settings.copyWith(hardwareDecoding: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsAutoSkipIntro),
            value: settings.autoSkipIntro,
            onChanged: (value) => save(settings.copyWith(autoSkipIntro: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsAutoplayNext),
            value: settings.autoplayNext,
            onChanged: (value) => save(settings.copyWith(autoplayNext: value)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: schermata.** In `lib/features/settings/settings_screen.dart`:
- aggiungi `import 'player_settings_section.dart';`;
- nella `ListView`, dopo il `SegmentedButton` della lingua (prima di `section(l.settingsAccount)`), aggiungi:

```dart
        section(l.settingsPlayer),
        const PlayerSettingsSection(),
```

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 6: commit**

```bash
git add lib/features/settings test/features/settings
git commit -m "feat: add player section to settings"
```

---

### Task 18: Impostazioni — lingue sul server

**Files:**
- Create: `lib/features/settings/language_preferences.dart`, `lib/features/settings/language_settings_section.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/features/settings/settings_test.dart` (modifiche e aggiunte)

- [ ] **Step 1: aggiorna e aggiungi i test** in `test/features/settings/settings_test.dart`.
- Import in testa: `package:wonderflix/features/settings/language_preferences.dart` e `../../support/settings_fakes.dart`.
- Nei due widget test esistenti (`'schermata: …'` e `'sezione Player: …'`) aggiungi agli `overrides`:

```dart
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
```

- Aggiungi in fondo al `main()`:

```dart
  Future<FakeUserConfigApi> pumpSettings(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final configApi = FakeUserConfigApi();
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    await pumpApp(tester, const Scaffold(body: SettingsScreen()), overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(configApi),
    ]);
    await tester.pump();
    return configApi;
  }

  testWidgets('lingue: valori dal server, salvataggio completo',
      (tester) async {
    final configApi = await pumpSettings(tester);
    expect(find.text('Lingue di riproduzione'), findsOneWidget);
    expect(find.text('Italiano'), findsWidgets);

    await tester.tap(find.byKey(const Key('subtitle-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mai').last);
    await tester.pumpAndSettle();

    final (userId, saved) = configApi.saved.single;
    expect(userId, 'u1');
    expect(saved['SubtitleMode'], 'None');
    expect(saved['AudioLanguagePreference'], 'ita');
    expect(saved['HidePlayedInLatest'], isTrue,
        reason: 'gli altri campi restano');
  });

  testWidgets('lingue: errore di salvataggio, avviso e valore precedente',
      (tester) async {
    final configApi = await pumpSettings(tester);
    configApi.saveError = const ServerUnreachableException();

    await tester.tap(find.byKey(const Key('subtitle-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sempre').last);
    await tester.pumpAndSettle();

    expect(find.text('Impossibile salvare. Riprova.'), findsOneWidget);
    expect(
        tester
            .widget<DropdownButton<String>>(find.byKey(const Key('subtitle-mode')))
            .value,
        'Default',
        reason: 'torna al valore di prima');
    expect(configApi.saved, isEmpty);
  });
```

(aggiungi l'import di `package:wonderflix/core/jellyfin/api_exception.dart`).

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/settings/settings_test.dart`
Expected: FAIL.

- [ ] **Step 3: crea** `lib/features/settings/language_preferences.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../library/library_providers.dart';

final userConfigApiProvider =
    Provider<UserConfigApi>((ref) => UserConfigApi(ref.watch(jellyfinHttpProvider)));

/// Lingue di riproduzione dell'utente, salvate sul server.
class LanguagePreferencesController extends AsyncNotifier<LanguagePreferences> {
  /// Configurazione completa letta dal server: si rimanda tutta.
  Map<String, dynamic> _configuration = const {};

  @override
  Future<LanguagePreferences> build() async {
    _configuration = await ref.watch(userConfigApiProvider).configuration();
    return LanguagePreferences.fromConfiguration(_configuration);
  }

  /// Aggiorna subito la schermata; se il server rifiuta, torna al valore di
  /// prima e rilancia l'errore.
  Future<void> save(LanguagePreferences next) async {
    final previous = state.value;
    state = AsyncData(next);
    try {
      final updated = next.applyTo(_configuration);
      await ref
          .read(userConfigApiProvider)
          .saveConfiguration(ref.read(currentUserIdProvider), updated);
      _configuration = updated;
    } on Object {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

final languagePreferencesProvider = AsyncNotifierProvider.autoDispose<
    LanguagePreferencesController,
    LanguagePreferences>(LanguagePreferencesController.new);
```

- [ ] **Step 4: crea** `lib/features/settings/language_settings_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../../l10n/gen/app_localizations.dart';
import 'language_preferences.dart';

/// Lingue di audio e sottotitoli e quando mostrare i sottotitoli: sono
/// salvate sul server e il server le usa per scegliere le tracce.
class LanguageSettingsSection extends ConsumerWidget {
  const LanguageSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return switch (ref.watch(languagePreferencesProvider)) {
      AsyncData(:final value) => _LanguageForm(preferences: value),
      AsyncError(:final error) => Row(
          children: [
            Flexible(child: Text(describeError(l, error))),
            TextButton(
              onPressed: () => ref.invalidate(languagePreferencesProvider),
              child: Text(l.retry),
            ),
          ],
        ),
      _ => const Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
    };
  }
}

class _LanguageForm extends ConsumerWidget {
  const _LanguageForm({required this.preferences});

  final LanguagePreferences preferences;

  Future<void> _save(
      BuildContext context, WidgetRef ref, LanguagePreferences next) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(languagePreferencesProvider.notifier).save(next);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l.settingsSaveError)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    List<DropdownMenuItem<String>> languages(String current) => [
          DropdownMenuItem(value: '', child: Text(l.settingsLanguageAny)),
          for (final entry in playbackLanguages.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          if (current.isNotEmpty && !playbackLanguages.containsKey(current))
            DropdownMenuItem(value: current, child: Text(current)),
        ];
    final modes = {
      'Default': l.settingsSubtitleModeDefault,
      'Always': l.settingsSubtitleModeAlways,
      'OnlyForced': l.settingsSubtitleModeOnlyForced,
      'None': l.settingsSubtitleModeNone,
      'Smart': l.settingsSubtitleModeSmart,
    };
    final mode = subtitleModes.contains(preferences.subtitleMode)
        ? preferences.subtitleMode
        : 'Default';

    Widget labeled(String label, Widget field) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label), const SizedBox(height: 6), field],
          ),
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.settingsLanguagesHint,
              style: const TextStyle(color: WfColors.creamMuted)),
          const SizedBox(height: 16),
          labeled(
            l.settingsAudioLanguage,
            DropdownButton<String>(
              key: const Key('audio-language'),
              value: preferences.audioLanguage,
              items: languages(preferences.audioLanguage),
              onChanged: (value) => unawaited(_save(context, ref,
                  preferences.copyWith(audioLanguage: value ?? ''))),
            ),
          ),
          labeled(
            l.settingsSubtitleLanguage,
            DropdownButton<String>(
              key: const Key('subtitle-language'),
              value: preferences.subtitleLanguage,
              items: languages(preferences.subtitleLanguage),
              onChanged: (value) => unawaited(_save(context, ref,
                  preferences.copyWith(subtitleLanguage: value ?? ''))),
            ),
          ),
          labeled(
            l.settingsSubtitleMode,
            DropdownButton<String>(
              key: const Key('subtitle-mode'),
              value: mode,
              items: [
                for (final entry in modes.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => unawaited(_save(
                  context, ref, preferences.copyWith(subtitleMode: value))),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: schermata.** In `lib/features/settings/settings_screen.dart`:
- aggiungi `import 'language_settings_section.dart';`;
- subito dopo la sezione Player del Task 17 aggiungi:

```dart
        section(l.settingsLanguages),
        const LanguageSettingsSection(),
```

- [ ] **Step 6: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 7: commit**

```bash
git add lib/features/settings test/features/settings
git commit -m "feat: edit playback languages saved on the server"
```

---

### Task 19: sessione media (interfaccia e collegamento al player)

**Files:**
- Create: `lib/core/media_session/media_session.dart`
- Modify: `lib/features/player/player_providers.dart`, `lib/features/player/player_screen.dart`, `test/support/playback_fakes.dart`
- Test: `test/features/player/player_screen_test.dart` (aggiunte)

Qui c'è solo l'interfaccia, con un'implementazione vuota di default: nessun codice nativo. Quella vera, con SMTC, arriva nel Task 20.

- [ ] **Step 1: crea** `lib/core/media_session/media_session.dart`:

```dart
/// Pulsanti del pannello media di sistema e dei tasti multimediali.
enum MediaButton { play, pause, next, stop }

/// Pannello media di sistema (su Windows: SMTC): titolo, immagine, stato
/// e tasti multimediali, attivi anche con l'app in secondo piano.
abstract class MediaSession {
  Future<void> setMetadata({
    required String title,
    String? subtitle,
    String? thumbnailUrl,
  });

  Future<void> setPlaying(bool playing);

  Future<void> setTimeline({
    required Duration position,
    required Duration duration,
  });

  Future<void> setNextEnabled(bool enabled);

  Stream<MediaButton> get buttons;

  Future<void> dispose();
}

/// Nessun pannello (test, o SMTC non disponibile).
class NoopMediaSession implements MediaSession {
  @override
  Future<void> setMetadata(
      {required String title, String? subtitle, String? thumbnailUrl}) async {}

  @override
  Future<void> setPlaying(bool playing) async {}

  @override
  Future<void> setTimeline(
      {required Duration position, required Duration duration}) async {}

  @override
  Future<void> setNextEnabled(bool enabled) async {}

  @override
  Stream<MediaButton> get buttons => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 2: provider.** In fondo a `lib/features/player/player_providers.dart` (import `../../core/media_session/media_session.dart`):

```dart
/// Crea la sessione media di ogni riproduzione. Di default non fa nulla;
/// `main` la sostituisce con SMTC se è disponibile.
final mediaSessionFactoryProvider =
    Provider<MediaSession Function()>((ref) => NoopMediaSession.new);
```

- [ ] **Step 3: fake.** In fondo a `test/support/playback_fakes.dart` (import `package:wonderflix/core/media_session/media_session.dart`):

```dart
/// Sessione media in memoria: registra gli aggiornamenti e simula i tasti.
class FakeMediaSession implements MediaSession {
  final metadata = <({String title, String? subtitle, String? thumbnailUrl})>[];
  final playingStates = <bool>[];
  final timelines = <Duration>[];
  final nextEnabled = <bool>[];
  bool disposed = false;
  final _buttons = StreamController<MediaButton>.broadcast();

  void press(MediaButton button) => _buttons.add(button);

  @override
  Future<void> setMetadata(
      {required String title, String? subtitle, String? thumbnailUrl}) async {
    metadata.add((title: title, subtitle: subtitle, thumbnailUrl: thumbnailUrl));
  }

  @override
  Future<void> setPlaying(bool playing) async => playingStates.add(playing);

  @override
  Future<void> setTimeline(
          {required Duration position, required Duration duration}) async =>
      timelines.add(position);

  @override
  Future<void> setNextEnabled(bool enabled) async => nextEnabled.add(enabled);

  @override
  Stream<MediaButton> get buttons => _buttons.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
```

- [ ] **Step 4: aggiungi i test** in `test/features/player/player_screen_test.dart`:
- import `package:wonderflix/core/media_session/media_session.dart`;
- `late FakeMediaSession mediaSession;` e, nel `setUp`, `mediaSession = FakeMediaSession();`;
- override in `pumpPlayer`: `mediaSessionFactoryProvider.overrideWithValue(() => mediaSession),`;
- in fondo al `main()`:

```dart
  testWidgets('pannello media: titolo, stato, tasti e chiusura',
      (tester) async {
    await pumpPlayer(tester);
    expect(mediaSession.metadata.last.title, 'Breaking Bad');
    expect(mediaSession.metadata.last.subtitle, 'S1:E4 · Pilot');
    expect(mediaSession.metadata.last.thumbnailUrl, isNotNull);
    expect(mediaSession.playingStates.last, isTrue);

    await tester.pump(const Duration(seconds: 5));
    expect(mediaSession.timelines, isNotEmpty);

    mediaSession.press(MediaButton.pause);
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isFalse);

    mediaSession.press(MediaButton.play);
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isTrue);

    mediaSession.press(MediaButton.stop);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(mediaSession.disposed, isTrue);
    await unmount(tester);
  });

  testWidgets('pannello media: "successivo" solo se c\'è un episodio dopo',
      (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    expect(mediaSession.nextEnabled.last, isTrue);
    mediaSession.press(MediaButton.next);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    await unmount(tester);
  });
```

- [ ] **Step 5: esegui e verifica che falliscano**

Run: `flutter test test/features/player/player_screen_test.dart`
Expected: FAIL (la schermata non usa ancora la sessione media).

- [ ] **Step 6: collega la schermata.** In `lib/features/player/player_screen.dart`:
- import: `../../core/jellyfin/item_models.dart`, `../../core/media_session/media_session.dart`, `../library/item_labels.dart`, `../library/library_providers.dart`;
- nuovi campi dello stato:

```dart
  late final MediaSession _mediaSession;
  StreamSubscription<MediaButton>? _mediaButtons;
  Timer? _timelineTimer;
```

- in `initState`, dopo `_window.setPreventClose(true)`:

```dart
    _mediaSession = ref.read(mediaSessionFactoryProvider)();
    _mediaButtons = _mediaSession.buttons.listen(_onMediaButton);
    _timelineTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendTimeline());
```

- in `dispose`, prima di `super.dispose()`:

```dart
    _timelineTimer?.cancel();
    unawaited(_mediaButtons?.cancel());
    unawaited(_mediaSession.dispose());
```

- nuovi metodi (dopo `_onFinished`):

```dart
  void _publishMetadata(JellyfinItem item) {
    unawaited(_mediaSession.setMetadata(
      title: cardTitle(item),
      subtitle: cardSubtitle(item),
      thumbnailUrl: ref.read(imageUrlsProvider).poster(item)?.url,
    ));
  }

  void _sendTimeline() {
    if (!mounted) return;
    if (ref.read(playerControllerProvider(widget.args)).status !=
        PlayerStatus.ready) {
      return;
    }
    final engine = _controller.engine;
    unawaited(_mediaSession.setTimeline(
        position: engine.position, duration: engine.duration));
  }

  /// Tasti del pannello media e della tastiera multimediale.
  void _onMediaButton(MediaButton button) {
    if (!mounted) return;
    final playing = ref.read(playerControllerProvider(widget.args)).playing;
    switch (button) {
      case MediaButton.play:
        if (!playing) unawaited(_controller.togglePlay());
      case MediaButton.pause:
        if (playing) unawaited(_controller.togglePlay());
      case MediaButton.next:
        _playNext();
      case MediaButton.stop:
        _exit();
    }
  }
```

- in `build`, sostituisci il listener di `playing` con:

```dart
    ref.listen(provider.select((s) => s.playing), (_, playing) {
      if (playing) _scheduleHide();
      unawaited(_mediaSession.setPlaying(playing));
    });
```

e aggiungi, accanto agli altri listener:

```dart
    ref.listen(provider.select((s) => s.item), (_, item) {
      if (item != null) _publishMetadata(item);
    });
    ref.listen(provider.select((s) => s.nextEpisode != null), (_, hasNext) {
      unawaited(_mediaSession.setNextEnabled(hasNext));
    });
```

- [ ] **Step 7: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 8: commit**

```bash
git add lib test
git commit -m "feat: publish playback to a media session and handle media buttons"
```

---

### Task 20: SMTC di Windows (smtc_windows)

**Files:**
- Create: `lib/core/media_session/smtc_media_session.dart`
- Modify: `pubspec.yaml`, `pubspec.lock`, `lib/main.dart`, `.github/workflows/ci.yml`, `windows/flutter/generated_plugin*`

- [ ] **Step 1: prerequisito Rust**

```bash
rustup --version && cargo --version
```
Expected: le versioni di rustup e cargo. **Se i comandi non esistono, FERMATI e riporta BLOCKED.** L'utente deve installare rustup (https://rustup.rs, oppure `winget install Rustlang.Rustup`) e riaprire il terminale. Non installarlo da solo.

- [ ] **Step 2: dipendenza**

```bash
flutter pub add smtc_windows
grep -A2 "^  smtc_windows:" pubspec.lock
```
Expected: versione 1.1.0. Se è diversa, segnalalo: le API del piano sono verificate sulla 1.1.0.

- [ ] **Step 3: crea** `lib/core/media_session/smtc_media_session.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import 'media_session.dart';

/// [MediaSession] sul pannello media di Windows (System Media Transport
/// Controls). Richiede `SMTCWindows.initialize()` all'avvio.
class SmtcMediaSession implements MediaSession {
  SmtcMediaSession()
      : _smtc = SMTCWindows(
          config: const SMTCConfig(
            playEnabled: true,
            pauseEnabled: true,
            stopEnabled: true,
            nextEnabled: false,
            prevEnabled: false,
            fastForwardEnabled: false,
            rewindEnabled: false,
          ),
        );

  final SMTCWindows _smtc;

  @override
  Future<void> setMetadata(
          {required String title, String? subtitle, String? thumbnailUrl}) =>
      _smtc.updateMetadata(
          MusicMetadata(title: title, artist: subtitle, thumbnail: thumbnailUrl));

  @override
  Future<void> setPlaying(bool playing) => _smtc.setPlaybackStatus(
      playing ? PlaybackStatus.playing : PlaybackStatus.paused);

  @override
  Future<void> setTimeline(
          {required Duration position, required Duration duration}) =>
      _smtc.updateTimeline(PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: duration.inMilliseconds,
        positionMs: position.inMilliseconds,
        minSeekTimeMs: 0,
        maxSeekTimeMs: duration.inMilliseconds,
      ));

  @override
  Future<void> setNextEnabled(bool enabled) => _smtc.setIsNextEnabled(enabled);

  @override
  Stream<MediaButton> get buttons => _smtc.buttonPressStream
      // Pulsanti che smtc_windows non conosce: ignorati.
      .handleError((Object error) => debugPrint('SMTC: $error'))
      .map(_button)
      .where((button) => button != null)
      .cast<MediaButton>();

  static MediaButton? _button(PressedButton button) => switch (button) {
        PressedButton.play => MediaButton.play,
        PressedButton.pause => MediaButton.pause,
        PressedButton.next => MediaButton.next,
        PressedButton.stop => MediaButton.stop,
        _ => null,
      };

  @override
  Future<void> dispose() async {
    await _smtc.disableSmtc();
    await _smtc.dispose();
  }
}
```

- [ ] **Step 4: avvio.** In `lib/main.dart`:
- import `package:smtc_windows/smtc_windows.dart`, `core/media_session/smtc_media_session.dart`, `features/player/player_providers.dart`;
- dopo `await setupWindow(prefs);`:

```dart
    // Pannello media di Windows: se non si avvia, il player funziona lo
    // stesso (senza tasti multimediali in secondo piano).
    var smtcReady = false;
    try {
      await SMTCWindows.initialize();
      smtcReady = true;
    } on Object catch (e) {
      debugPrint('SMTC non disponibile: $e');
    }
```

- nella lista `overrides` della `ProviderScope` aggiungi:

```dart
        if (smtcReady)
          mediaSessionFactoryProvider.overrideWithValue(SmtcMediaSession.new),
```

- [ ] **Step 5: CI.** In `.github/workflows/ci.yml`, dopo `- uses: subosito/flutter-action@v2` (e il suo blocco `with`), aggiungi:

```yaml
      - uses: dtolnay/rust-toolchain@stable
```

- [ ] **Step 6: verifica e build**

```bash
flutter analyze && flutter test
flutter build windows --debug
git diff --stat windows/flutter/
```
Expected: nessun problema, tutti PASS, build riuscita. La prima build compila Rust e può richiedere diversi minuti. I file `windows/flutter/generated_plugin*` contengono `smtc_windows`: sono cambi veri, da committare.

- [ ] **Step 7: commit**

```bash
git add pubspec.yaml pubspec.lock lib .github/workflows/ci.yml windows/flutter
git commit -m "feat: show playback in the Windows media controls"
```

---

### Task 21: verifica completa e prova sul server

**Files:** nessuna modifica prevista (solo eventuali correzioni emerse).

- [ ] **Step 1: controlli automatici**

```bash
flutter analyze
flutter test
flutter build windows --debug
```
Expected: nessun problema, tutti PASS, build riuscita.

- [ ] **Step 2: prova manuale sul server reale** (con `config/wonderflix.json` già presente nel worktree)

```bash
flutter run -d windows --dart-define-from-file=config/wonderflix.json
```

Checklist da fare con l'utente (annota l'esito). I punti 1–2 richiedono che il server riconosca i segmenti (plugin come Intro Skipper); il punto 5 richiede le anteprime trickplay generate dal server.
1. **Salta intro:** in un episodio con intro riconosciuta compare "Salta intro" (o "Salta riassunto") e porta alla fine del segmento.
2. **Salto automatico:** attivato nelle Impostazioni, l'intro viene saltata da sola, una volta.
3. **Prossimo episodio:**
   - ai crediti (o negli ultimi 30 s) compare la scheda con il conto alla rovescia di 10 s e poi parte l'episodio successivo;
   - "Annulla" la chiude e a fine episodio si torna alla scheda della serie;
   - "Riproduci ora", il pulsante nella barra e il tasto N passano subito al successivo;
   - con la riproduzione automatica spenta la scheda non conta e a fine episodio si esce;
   - a schermo intero il successivo resta a schermo intero.
4. **Minutaggio:** passando al successivo, l'episodio precedente risulta visto (o al punto giusto) in Home e in jellyfin-web.
5. **Barra:** passando il mouse compaiono l'anteprima, il tempo e il nome del capitolo; le tacche dei capitoli sono al posto giusto.
6. **Trailer:** un film con trailer locale lo apre nel player; senza trailer locale si apre quello remoto nel browser.
7. **Impostazioni del player** (dal video successivo):
   - qualità 4 Mbps → la Dashboard mostra la transcodifica;
   - dimensione dei sottotitoli visibile;
   - decodifica hardware spenta → il video parte lo stesso.
8. **Lingue sul server:** cambiando lingua dell'audio o dei sottotitoli, il video successivo parte con le tracce giuste e jellyfin-web mostra le stesse preferenze.
9. **Home:** la riga "Prossimi episodi" coincide con quella di jellyfin-web.
10. **Pannello media di Windows:**
    - il riquadro multimediale di Windows (tasti del volume o Win+A) mostra titolo e locandina;
    - Play/Pausa, Successivo e Stop funzionano anche con l'app in secondo piano;
    - uscendo dal player il pannello si svuota.
11. **Regressione del 3a:** ripresa, sottotitoli, ritardo, chiusura della finestra con il minutaggio salvato.

- [ ] **Step 3: correzioni**

Se la prova rivela problemi, correggili con TDD (prima il test che fallisce, poi la correzione), un commit per problema, con messaggio `fix: …`.
