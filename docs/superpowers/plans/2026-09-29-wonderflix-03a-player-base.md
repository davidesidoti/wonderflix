# WonderFlix — Piano 3a: player di base

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "Riproduci" apre un player vero, basato su mpv:
- direct play dal file originale, con il token nell'header e la ripresa dal minutaggio all'apertura;
- un solo ripiego automatico sulla transcodifica HLS se il direct play non parte;
- tracce audio e sottotitoli (interni, esterni, grafici), ritardo dei sottotitoli ±0,1 s;
- overlay dei controlli, tastiera, schermo intero;
- avanzamento inviato a Jellyfin, con il minutaggio aggiornato subito in tutta l'app.

**Architecture:**
- **`lib/core/video/`:** `VideoEngine`, l'interfaccia del motore video, e `MediaKitEngine`, l'implementazione su media_kit. Nei test si usa `FakeVideoEngine`.
- **`lib/core/jellyfin/`:** modelli di PlaybackInfo, profilo del dispositivo, `PlaybackApi` (PlaybackInfo, `Sessions/Playing*`, dati utente).
- **`lib/features/player/`:**
  - `PlaybackService`: sceglie tra direct play e transcodifica;
  - `ProgressReporter`: report dell'avanzamento;
  - `PlayerController`: Notifier Riverpod che coordina motore, servizio e report;
  - widget: `SeekBar`, `TracksPanel`, `PlayerOverlay`, `PlayerScreen`.
- **Route `/play/:id`** sul navigatore radice, fuori dalla `ShellRoute`. Il nuovo `playItem(context, ref, item)` diventa l'unico punto d'ingresso della riproduzione.

**Tech Stack:** Flutter 3.47.5, media_kit 1.2.6, media_kit_video 2.0.1, media_kit_libs_windows_video 1.0.11 (libmpv), window_manager (schermo intero, chiusura della finestra), flutter_riverpod 3, go_router 18; test con `FakeVideoEngine`, `FakePlaybackApi`, `FakePlayerWindow` e fake_async.

**Spec:** `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md`, sezione 7. **Passaggio di consegne:** `docs/superpowers/handoff/2026-09-29-handoff-piano-3.md` (punti rimandati 1–3). **Piani precedenti:** `docs/superpowers/plans/2026-09-29-wonderflix-01-fondamenta-login.md`, `…-02-home-catalogo.md`.

**Fuori da questo piano (Piano 3b, da scrivere dopo la prova del 3a):**
- MediaSegments (salta intro e riassunto);
- prossimo episodio (tasto N e scheda con conto alla rovescia);
- trickplay e capitoli;
- trailer locali (punto rimandato 4);
- impostazioni del player: qualità, decodifica hardware, dimensione dei sottotitoli, salto automatico, riproduzione automatica, lingue sul server;
- `nextUpDateCutoff` (punto rimandato 5);
- pannello media di Windows (SMTC) con `smtc_windows`. Richiede `rustup`: decisione dell'utente, opzione (a).

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…". Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/player-base`, branch `feat/player-base`).
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde. Se `lib/l10n/gen` manca, esegui prima `flutter gen-l10n`.
- **Icone:** solo `LucideIcons` (`package:lucide_icons_flutter/lucide_icons.dart`), niente emoji. I nomi usati nel piano sono stati verificati sulla versione 3.1.20.
- **Widget test:**
  - `pumpApp` (`test/support/pump_app.dart`) non mette uno `Scaffold`. Slider, IconButton, InkWell e SnackBar richiedono `Scaffold(body: …)`.
  - Il font dei test ha glifi più larghi di quelli reali. Se una `Row` va in overflow **solo nei test**, correggi al minimo con `Flexible`/`Wrap` e segnalalo.
- **Fake:** `FakeLibraryApi` (`test/support/library_fakes.dart`) per la libreria; `FakePlaybackApi`, `FakeVideoEngine` e `FakePlayerWindow` (`test/support/playback_fakes.dart`, Task 6 e 11) per la riproduzione. Niente mocktail.
- **media_kit non si prova nei test:** `MediaKitEngine` richiede libmpv. Viene verificato da `flutter analyze`, dalla build e dalla prova manuale (Task 20).
- **File generati:** `flutter pub get` / `flutter test` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga. Se `git diff` non mostra cambi di contenuto, esegui `git checkout -- windows/flutter/`. Nel Task 1 i cambi sono veri (nuovi plugin nativi) e vanno committati.
- **App aperta:** se una build fallisce con `LNK1168`, esegui `taskkill //IM wonderflix.exe //F` e riprova.
- **Riferimento API:** `docs/reference/jellyfin-openapi-10.11.9.json`.

## Note tecniche verificate nella pub cache (media_kit 1.2.6)

- `Media(String uri, {Map<String, String>? httpHeaders, Duration? start, Duration? end, Map<String, dynamic>? extras})`. `httpHeaders` e `start` vengono applicati nell'hook `on_load` di mpv, come `http-header-fields` (array di stringhe, quindi le virgole dell'header `Authorization` non creano problemi) e come proprietà `start`. Gli header restano attivi finché il file è aperto, quindi valgono anche per i `sub-add` verso il server.
- I `Track` di media_kit **non** contengono `ff-index`. Il valore si legge con `NativePlayer.getProperty('track-list/N/ff-index')` (stringa, `""` se assente). Il player nativo si ottiene con `player.platform as NativePlayer`.
- `PlayerConfiguration.libass` è **false** di default: serve `libass: true`, altrimenti i sottotitoli li disegna un widget Flutter e gli stili ASS si perdono. Con libass va spento il widget: `SubtitleViewConfiguration(visible: false)`.
- Il widget `Video` blocca già salvaschermo e sospensione (`wakelock: true` di default, tramite wakelock_plus). Non serve un pacchetto in più.
- Lo schermo intero di media_kit apre una route in più. Qui si usa `windowManager.setFullScreen`.
- `stream.error` di media_kit emette anche errori non fatali. `MediaKitEngine.open` considera fallita l'apertura solo se arriva un errore prima che la durata sia nota (o dopo 60 s senza durata).
- `smtc_windows` 1.1.0 compila codice Rust con cargokit, senza binari precompilati: richiede `rustup`. Per questo è rimandato al Piano 3b.

## Mappa dei file

```
lib/core/jellyfin/api_exception.dart     (+ PlaybackUnavailableException)
lib/core/jellyfin/item_models.dart       (+ durationToTicks, UserItemData.copyWith con minutaggio)
lib/core/jellyfin/playback_models.dart   PlayMethod, StreamKind, MediaStreamInfo, MediaSourceInfo, PlaybackInfoResult, PlaybackReport, resolveServerUrl
lib/core/jellyfin/device_profile.dart    originalQualityBitrate, buildDeviceProfile
lib/core/jellyfin/playback_api.dart      PlaybackApi
lib/core/video/video_engine.dart         VideoEngine, VideoSource, EngineTrack, EngineTrackType, EngineOpenException
lib/core/video/media_kit_engine.dart     MediaKitEngine
lib/features/player/track_mapping.dart   engineTrackFor
lib/features/player/playback_service.dart PlaybackPlan, PlaybackService
lib/features/player/progress_reporter.dart ProgressReporter
lib/features/player/player_window.dart   PlayerWindow, WindowManagerPlayerWindow
lib/features/player/player_providers.dart playbackApiProvider, playbackServiceProvider, videoEngineFactoryProvider, playerWindowProvider
lib/features/player/player_controller.dart PlayerArgs, PlayerStatus, PlayerViewState, PlayerController, playerControllerProvider
lib/features/player/player_commands.dart PlayerCommand, playerCommandFor, seekStep, volumeStep, subtitleDelayStep
lib/features/player/seek_bar.dart        SeekBar, TimeLabel
lib/features/player/tracks_panel.dart    TracksPanel, trackLabel, formatSubtitleDelay
lib/features/player/player_overlay.dart  PlayerOverlay
lib/features/player/player_screen.dart   PlayerScreen
lib/features/playback/play_launcher.dart playItem (riscritto)
lib/features/detail/detail_providers.dart (+ findNextEpisode)
lib/features/detail/detail_header.dart, lib/features/home/hero_carousel.dart,
lib/features/detail/series_detail_view.dart (nuova firma di playItem)
lib/app/navigation.dart                  (+ playerRoute, playerStartFrom)
lib/app/router.dart                      (+ /play/:id)
lib/app/error_text.dart                  (+ errori della riproduzione)
lib/main.dart                            (+ MediaKit.ensureInitialized)
l10n/app_it.arb, l10n/app_en.arb         (stringhe del player; via playbackComingSoon)
test/support/playback_fakes.dart         FakePlaybackApi, FakeVideoEngine, FakePlayerWindow, testPlaybackInfo, testEngineTracks
```

---

### Task 1: dipendenze media_kit

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`, `lib/main.dart`, `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugins.cmake`

- [ ] **Step 1: dipendenze**

```bash
flutter pub add media_kit media_kit_video media_kit_libs_windows_video
grep -A2 -E "^  media_kit(_video|_libs_windows_video)?:" pubspec.lock
```
Expected: `media_kit` 1.2.6, `media_kit_video` 2.0.1, `media_kit_libs_windows_video` 1.0.11. Se le versioni risolte sono diverse, segnalalo prima di continuare: le note tecniche del piano valgono per queste.

- [ ] **Step 2: inizializzazione in `lib/main.dart`**

Aggiungi l'import:

```dart
import 'package:media_kit/media_kit.dart';
```

e subito dopo `WidgetsFlutterBinding.ensureInitialized();`:

```dart
  WidgetsFlutterBinding.ensureInitialized();
  // Carica libmpv: va fatto prima di creare qualunque Player.
  MediaKit.ensureInitialized();
```

- [ ] **Step 3: verifica e build**

```bash
flutter analyze && flutter test
flutter build windows --debug
```
Expected: nessun problema, tutti i test PASS, build riuscita. La prima build scarica libmpv (serve internet e può richiedere qualche minuto).

- [ ] **Step 4: file generati**

```bash
git diff --stat windows/flutter/
```
Expected: `generated_plugins.cmake` e `generated_plugin_registrant.cc` contengono i nuovi plugin (`media_kit_libs_windows_video`, `media_kit_video`…). Sono cambi veri e vanno committati.

- [ ] **Step 5: commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart windows/flutter
git commit -m "chore: add media_kit for video playback"
```

---

### Task 2: tick e minutaggio nei dati utente

**Files:**
- Modify: `lib/core/jellyfin/item_models.dart`
- Test: `test/core/jellyfin/item_models_test.dart` (aggiunte)

- [ ] **Step 1: aggiungi i test** in fondo al `main()` di `test/core/jellyfin/item_models_test.dart`:

```dart
  test('durationToTicks è l\'inverso di ticksToDuration', () {
    expect(durationToTicks(const Duration(seconds: 90)), 900000000);
    expect(ticksToDuration(durationToTicks(const Duration(minutes: 23))),
        const Duration(minutes: 23));
  });

  test('copyWith aggiorna minutaggio e percentuale', () {
    const data = UserItemData(
        isFavorite: true, playbackPositionTicks: 10, playedPercentage: 1);
    final next =
        data.copyWith(playbackPositionTicks: 600000000, playedPercentage: 50);
    expect(next.playbackPositionTicks, 600000000);
    expect(next.playedPercentage, 50);
    expect(next.isFavorite, isTrue);
    expect(data.copyWith(played: true).playbackPositionTicks, 10);
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/core/jellyfin/item_models_test.dart`
Expected: FAIL (`durationToTicks` non esiste, `copyWith` non ha `playbackPositionTicks`).

- [ ] **Step 3: implementa** in `lib/core/jellyfin/item_models.dart`.

Sotto `ticksToDuration`:

```dart
/// Inverso di [ticksToDuration].
int durationToTicks(Duration duration) => duration.inMicroseconds * 10;
```

Sostituisci `UserItemData.copyWith` con:

```dart
  UserItemData copyWith({
    bool? played,
    bool? isFavorite,
    int? playbackPositionTicks,
    double? playedPercentage,
  }) =>
      UserItemData(
        played: played ?? this.played,
        isFavorite: isFavorite ?? this.isFavorite,
        playbackPositionTicks:
            playbackPositionTicks ?? this.playbackPositionTicks,
        playedPercentage: playedPercentage ?? this.playedPercentage,
        unplayedItemCount: unplayedItemCount,
      );
```

- [ ] **Step 4: esegui e verifica che passino**

Run: `flutter test test/core/jellyfin/item_models_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin/item_models.dart test/core/jellyfin/item_models_test.dart
git commit -m "feat: add tick conversion and playback position to user data copyWith"
```

---

### Task 3: modelli della riproduzione

**Files:**
- Modify: `lib/core/jellyfin/api_exception.dart`
- Create: `lib/core/jellyfin/playback_models.dart`
- Test: `test/core/jellyfin/playback_models_test.dart`

- [ ] **Step 1: scrivi il test** `test/core/jellyfin/playback_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';

void main() {
  test('PlaybackInfo: sorgente, tracce e indici predefiniti', () {
    final result = PlaybackInfoResult.fromJson({
      'PlaySessionId': 'ps1',
      'MediaSources': [
        {
          'Id': 'ms1',
          'SupportsDirectPlay': true,
          'DefaultAudioStreamIndex': 1,
          'DefaultSubtitleStreamIndex': -1,
          'MediaStreams': [
            {'Index': 0, 'Type': 'Video', 'Codec': 'hevc'},
            {
              'Index': 1,
              'Type': 'Audio',
              'Language': 'ita',
              'DisplayTitle': 'Italiano',
              'IsDefault': true,
            },
            {
              'Index': 2,
              'Type': 'Subtitle',
              'Codec': 'PGSSUB',
              'DeliveryMethod': 'Embed',
            },
            {
              'Index': 3,
              'Type': 'Subtitle',
              'Codec': 'srt',
              'IsExternal': true,
              'IsTextSubtitleStream': true,
              'DeliveryMethod': 'External',
              'DeliveryUrl': '/Videos/m1/ms1/Subtitles/3/0/Stream.srt',
            },
            {'Index': 4, 'Type': 'Attachment'},
          ],
        },
      ],
    });
    expect(result.playSessionId, 'ps1');
    expect(result.errorCode, isNull);
    final source = result.mediaSources.single;
    expect(source.id, 'ms1');
    expect(source.supportsDirectPlay, isTrue);
    expect(source.transcodingUrl, isNull);
    expect(source.defaultAudioStreamIndex, 1);
    expect(source.defaultSubtitleStreamIndex, -1);
    expect(source.audioStreams.map((s) => s.index), [1]);
    expect(source.subtitleStreams.map((s) => s.index), [2, 3]);
    expect(source.stream(1)?.displayTitle, 'Italiano');
    expect(source.stream(1)?.isDefault, isTrue);
    expect(source.stream(4)?.kind, StreamKind.other);
    expect(source.stream(9), isNull);
    expect(source.stream(2)?.deliveredExternally, isFalse);
    expect(source.stream(3)?.deliveredExternally, isTrue);
    expect(source.stream(3)?.isExternal, isTrue);
  });

  test('PlaybackInfo con errore', () {
    final result = PlaybackInfoResult.fromJson(
        {'ErrorCode': 'NotAllowed', 'MediaSources': []});
    expect(result.errorCode, 'NotAllowed');
    expect(result.mediaSources, isEmpty);
  });

  test('resolveServerUrl mantiene il sotto-percorso del server', () {
    final server = Uri.parse('https://host.example.com/jellyfin');
    expect(resolveServerUrl(server, '/videos/m1/master.m3u8?a=1'),
        'https://host.example.com/jellyfin/videos/m1/master.m3u8?a=1');
    expect(resolveServerUrl(server, 'videos/m1/x.srt'),
        'https://host.example.com/jellyfin/videos/m1/x.srt');
    expect(resolveServerUrl(server, 'https://cdn.example.com/s.srt'),
        'https://cdn.example.com/s.srt');
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/core/jellyfin/playback_models_test.dart`
Expected: FAIL (il file `playback_models.dart` non esiste).

- [ ] **Step 3: aggiungi l'eccezione** in fondo alle classi di `lib/core/jellyfin/api_exception.dart`, dopo `RequestCancelledException`:

```dart
/// Il server non consente di riprodurre l'elemento (`PlaybackInfo.ErrorCode`:
/// `NotAllowed`, `NoCompatibleStream`, `RateLimitExceeded`) oppure non
/// propone nessun modo di riprodurlo.
final class PlaybackUnavailableException extends ApiException {
  const PlaybackUnavailableException(this.code);
  final String? code;

  @override
  String toString() => 'PlaybackUnavailableException($code)';
}
```

- [ ] **Step 4: crea** `lib/core/jellyfin/playback_models.dart`:

```dart
/// Modelli della riproduzione (sottoinsieme di `PlaybackInfoResponse` e dei
/// report `Sessions/Playing*`).
library;

import 'item_models.dart';

/// Come viene riprodotto un elemento (valore `PlayMethod` dell'API).
enum PlayMethod {
  directPlay('DirectPlay'),
  transcode('Transcode');

  const PlayMethod(this.apiName);

  final String apiName;
}

enum StreamKind { video, audio, subtitle, other }

int? _int(Object? value) => (value as num?)?.toInt();

/// Una traccia del file (`MediaStream`).
class MediaStreamInfo {
  const MediaStreamInfo({
    required this.index,
    required this.kind,
    this.codec,
    this.language,
    this.title,
    this.displayTitle,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    this.isTextSubtitle = false,
    this.deliveryMethod,
    this.deliveryUrl,
  });

  factory MediaStreamInfo.fromJson(Map<String, dynamic> json) =>
      MediaStreamInfo(
        index: _int(json['Index']) ?? -1,
        kind: switch (json['Type']) {
          'Video' => StreamKind.video,
          'Audio' => StreamKind.audio,
          'Subtitle' => StreamKind.subtitle,
          _ => StreamKind.other,
        },
        codec: json['Codec'] as String?,
        language: json['Language'] as String?,
        title: json['Title'] as String?,
        displayTitle: json['DisplayTitle'] as String?,
        isDefault: json['IsDefault'] as bool? ?? false,
        isForced: json['IsForced'] as bool? ?? false,
        isExternal: json['IsExternal'] as bool? ?? false,
        isTextSubtitle: json['IsTextSubtitleStream'] as bool? ?? false,
        deliveryMethod: json['DeliveryMethod'] as String?,
        deliveryUrl: json['DeliveryUrl'] as String?,
      );

  /// `Index` di Jellyfin: per le tracce interne coincide con `ff-index` di mpv.
  final int index;
  final StreamKind kind;
  final String? codec;
  final String? language;
  final String? title;

  /// Nome già pronto per i menu (es. "Italiano - AC3 - 5.1 - Predefinito").
  final String? displayTitle;
  final bool isDefault;
  final bool isForced;

  /// File di sottotitoli separato, accanto al video.
  final bool isExternal;
  final bool isTextSubtitle;

  /// `Embed`, `External`, `Encode` (bruciato nel video), `Hls`, `Drop`.
  final String? deliveryMethod;

  /// Percorso (di solito relativo al server) da cui scaricare il sottotitolo.
  final String? deliveryUrl;

  /// Sottotitolo da caricare a parte: file esterno, oppure estratto dal
  /// server durante la transcodifica.
  bool get deliveredExternally =>
      deliveryMethod == 'External' && (deliveryUrl?.isNotEmpty ?? false);
}

/// Una sorgente riproducibile dell'elemento (`MediaSourceInfo`).
class MediaSourceInfo {
  const MediaSourceInfo({
    required this.id,
    this.supportsDirectPlay = false,
    this.transcodingUrl,
    this.defaultAudioStreamIndex,
    this.defaultSubtitleStreamIndex,
    this.streams = const [],
  });

  factory MediaSourceInfo.fromJson(Map<String, dynamic> json) =>
      MediaSourceInfo(
        id: json['Id'] as String,
        supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? false,
        transcodingUrl: json['TranscodingUrl'] as String?,
        defaultAudioStreamIndex: _int(json['DefaultAudioStreamIndex']),
        defaultSubtitleStreamIndex: _int(json['DefaultSubtitleStreamIndex']),
        streams: (json['MediaStreams'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaStreamInfo.fromJson)
            .toList(),
      );

  final String id;
  final bool supportsDirectPlay;

  /// URL HLS (relativo al server) proposto quando serve la transcodifica.
  final String? transcodingUrl;

  /// Tracce scelte dal server secondo le preferenze dell'utente.
  /// `-1` = nessun sottotitolo.
  final int? defaultAudioStreamIndex;
  final int? defaultSubtitleStreamIndex;
  final List<MediaStreamInfo> streams;

  List<MediaStreamInfo> get audioStreams =>
      [for (final s in streams) if (s.kind == StreamKind.audio) s];

  List<MediaStreamInfo> get subtitleStreams =>
      [for (final s in streams) if (s.kind == StreamKind.subtitle) s];

  MediaStreamInfo? stream(int index) {
    for (final s in streams) {
      if (s.index == index) return s;
    }
    return null;
  }
}

/// Risposta di `POST /Items/{id}/PlaybackInfo`.
class PlaybackInfoResult {
  const PlaybackInfoResult({
    required this.mediaSources,
    this.playSessionId,
    this.errorCode,
  });

  factory PlaybackInfoResult.fromJson(Map<String, dynamic> json) =>
      PlaybackInfoResult(
        mediaSources: (json['MediaSources'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaSourceInfo.fromJson)
            .toList(),
        playSessionId: json['PlaySessionId'] as String?,
        errorCode: json['ErrorCode'] as String?,
      );

  final List<MediaSourceInfo> mediaSources;
  final String? playSessionId;

  /// `NotAllowed`, `NoCompatibleStream`, `RateLimitExceeded`; `null` se va
  /// tutto bene.
  final String? errorCode;
}

/// Stato della riproduzione da inviare a Jellyfin.
class PlaybackReport {
  const PlaybackReport({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.position,
    required this.isPaused,
    required this.isMuted,
    required this.volume,
    required this.audioStreamIndex,
    required this.subtitleStreamIndex,
    required this.playMethod,
  });

  final String itemId;
  final String mediaSourceId;
  final String? playSessionId;
  final Duration position;
  final bool isPaused;
  final bool isMuted;

  /// 0–100.
  final int volume;
  final int? audioStreamIndex;

  /// `null` = nessun sottotitolo (inviato come `-1`).
  final int? subtitleStreamIndex;
  final PlayMethod playMethod;

  /// Corpo di `Sessions/Playing` e `Sessions/Playing/Progress`.
  Map<String, dynamic> toJson() => {
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PlaySessionId': ?playSessionId,
        'PositionTicks': durationToTicks(position),
        'IsPaused': isPaused,
        'IsMuted': isMuted,
        'VolumeLevel': volume,
        'AudioStreamIndex': ?audioStreamIndex,
        'SubtitleStreamIndex': subtitleStreamIndex ?? -1,
        'PlayMethod': playMethod.apiName,
        'CanSeek': true,
      };

  /// Corpo di `Sessions/Playing/Stopped`.
  Map<String, dynamic> toStoppedJson() => {
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PlaySessionId': ?playSessionId,
        'PositionTicks': durationToTicks(position),
        'Failed': false,
      };
}

/// URL assoluto per un percorso restituito dal server (`TranscodingUrl`,
/// `DeliveryUrl`). I percorsi relativi vanno sotto l'indirizzo del server,
/// compreso l'eventuale sotto-percorso (es. `/jellyfin`): per questo non si
/// usa `Uri.resolve`, che lo perderebbe.
String resolveServerUrl(Uri serverUrl, String url) {
  final parsed = Uri.tryParse(url);
  if (parsed != null && parsed.hasScheme) return url;
  final base = serverUrl.toString().replaceAll(RegExp(r'/+$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}
```

- [ ] **Step 5: esegui e verifica che passi**

Run: `flutter test test/core/jellyfin/playback_models_test.dart`
Expected: PASS.

- [ ] **Step 6: commit**

```bash
git add lib/core/jellyfin/api_exception.dart lib/core/jellyfin/playback_models.dart test/core/jellyfin/playback_models_test.dart
git commit -m "feat: add playback info models"
```

---

### Task 4: profilo del dispositivo

**Files:**
- Create: `lib/core/jellyfin/device_profile.dart`
- Test: `test/core/jellyfin/device_profile_test.dart`

- [ ] **Step 1: scrivi il test** `test/core/jellyfin/device_profile_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/device_profile.dart';

void main() {
  test('direct play di tutto, transcodifica HLS di ripiego, sottotitoli', () {
    final profile = buildDeviceProfile(maxBitrate: 8000000);
    expect(profile['MaxStreamingBitrate'], 8000000);
    expect(profile['MaxStaticBitrate'], 8000000);
    expect(profile['DirectPlayProfiles'], [
      {'Type': 'Video'},
      {'Type': 'Audio'},
    ]);

    final transcoding =
        (profile['TranscodingProfiles'] as List).single as Map<String, dynamic>;
    expect(transcoding['Protocol'], 'hls');
    expect(transcoding['Container'], 'ts');
    expect(transcoding['VideoCodec'], 'h264');

    final subtitles =
        (profile['SubtitleProfiles'] as List).cast<Map<String, dynamic>>();
    Set<String> formats(String method) => {
          for (final s in subtitles)
            if (s['Method'] == method) s['Format'] as String,
        };
    expect(formats('External'), containsAll(['srt', 'ass', 'ssa', 'vtt', 'sub']));
    expect(formats('External'), isNot(contains('pgssub')));
    expect(formats('Embed'), containsAll(['srt', 'ass', 'pgssub', 'dvdsub']));
  });

  test('qualità originale: nessun limite pratico', () {
    expect(buildDeviceProfile()['MaxStreamingBitrate'], originalQualityBitrate);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/core/jellyfin/device_profile_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/core/jellyfin/device_profile.dart`:

```dart
/// Profilo del dispositivo inviato a `PlaybackInfo`.
library;

/// Limite di bitrate per la qualità "Originale": abbastanza alto da non
/// forzare mai la transcodifica dei file originali.
const originalQualityBitrate = 200000000;

/// Sottotitoli testuali: in direct play si leggono dal file, in
/// transcodifica il server li consegna come file separati.
const textSubtitleFormats = [
  'srt',
  'subrip',
  'ass',
  'ssa',
  'vtt',
  'webvtt',
  'sub',
  'mov_text',
];

/// Sottotitoli grafici: in direct play si leggono dal file, in transcodifica
/// il server li brucia nel video.
const imageSubtitleFormats = ['pgssub', 'pgs', 'dvdsub', 'dvbsub', 'vobsub'];

/// Formati che il server può consegnare come file separato.
const externalSubtitleFormats = ['srt', 'ass', 'ssa', 'vtt', 'sub'];

/// mpv riproduce qualunque contenitore e codec, quindi il direct play non ha
/// limiti: un profilo senza contenitore né codec vale per tutti. La
/// transcodifica, usata solo come ripiego, produce HLS H.264.
///
/// Sottotitoli:
/// - `Embed` per tutti: in direct play le tracce del file restano nel file;
/// - `External` per i testuali: i file esterni, e in transcodifica quelli
///   estratti dal server, si scaricano a parte;
/// - in transcodifica i grafici non hanno un profilo esterno, quindi il
///   server li brucia nel video.
Map<String, dynamic> buildDeviceProfile(
        {int maxBitrate = originalQualityBitrate}) =>
    {
      'Name': 'WonderFlix (mpv)',
      'MaxStreamingBitrate': maxBitrate,
      'MaxStaticBitrate': maxBitrate,
      'DirectPlayProfiles': [
        {'Type': 'Video'},
        {'Type': 'Audio'},
      ],
      'TranscodingProfiles': [
        {
          'Type': 'Video',
          'Container': 'ts',
          'Protocol': 'hls',
          'Context': 'Streaming',
          'VideoCodec': 'h264',
          'AudioCodec': 'aac,mp3,ac3,eac3',
          'MaxAudioChannels': '6',
          'MinSegments': 1,
          'BreakOnNonKeyFrames': true,
        },
      ],
      'ContainerProfiles': <Object>[],
      'CodecProfiles': <Object>[],
      'SubtitleProfiles': [
        for (final format in [...textSubtitleFormats, ...imageSubtitleFormats])
          {'Format': format, 'Method': 'Embed'},
        for (final format in externalSubtitleFormats)
          {'Format': format, 'Method': 'External'},
      ],
    };
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/core/jellyfin/device_profile_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin/device_profile.dart test/core/jellyfin/device_profile_test.dart
git commit -m "feat: add mpv device profile for PlaybackInfo"
```

---

### Task 5: `PlaybackApi`

**Files:**
- Create: `lib/core/jellyfin/playback_api.dart`
- Test: `test/core/jellyfin/playback_api_test.dart`

- [ ] **Step 1: scrivi il test** `test/core/jellyfin/playback_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/playback_api.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late PlaybackApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = PlaybackApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('playbackInfo invia profilo, posizione e tracce', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'PlaySessionId': 'ps1',
          'MediaSources': [
            {'Id': 'ms1', 'SupportsDirectPlay': true, 'MediaStreams': []},
          ],
        });
    final result = await api.playbackInfo(
      'm1',
      userId: 'u1',
      start: const Duration(minutes: 1),
      maxBitrate: 8000000,
      allowDirect: false,
      mediaSourceId: 'ms1',
      audioStreamIndex: 2,
      subtitleStreamIndex: -1,
    );
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Items/m1/PlaybackInfo');
    final body = request.data as Map<String, dynamic>;
    expect(body['UserId'], 'u1');
    expect(body['StartTimeTicks'], 600000000);
    expect(body['MaxStreamingBitrate'], 8000000);
    expect(body['EnableDirectPlay'], false);
    expect(body['EnableDirectStream'], false);
    expect(body['EnableTranscoding'], true);
    expect(body['MediaSourceId'], 'ms1');
    expect(body['AudioStreamIndex'], 2);
    expect(body['SubtitleStreamIndex'], -1);
    expect(body['DeviceProfile'], isA<Map<String, dynamic>>());
    expect(result.playSessionId, 'ps1');
    expect(result.mediaSources.single.supportsDirectPlay, isTrue);
  });

  test('playbackInfo senza indici non li invia', () async {
    adapter.handler = (_) => const FakeResponse(200, {'MediaSources': []});
    await api.playbackInfo('m1',
        userId: 'u1',
        start: Duration.zero,
        maxBitrate: 1,
        allowDirect: true);
    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body['EnableDirectPlay'], true);
    expect(body.containsKey('AudioStreamIndex'), isFalse);
    expect(body.containsKey('SubtitleStreamIndex'), isFalse);
    expect(body.containsKey('MediaSourceId'), isFalse);
  });

  test('report di inizio, avanzamento e fine', () async {
    const report = PlaybackReport(
      itemId: 'm1',
      mediaSourceId: 'ms1',
      playSessionId: 'ps1',
      position: Duration(seconds: 90),
      isPaused: true,
      isMuted: false,
      volume: 80,
      audioStreamIndex: 1,
      subtitleStreamIndex: null,
      playMethod: PlayMethod.directPlay,
    );
    await api.reportStart(report);
    expect(adapter.requests.last.path, '/Sessions/Playing');
    expect(adapter.requests.last.data, {
      'ItemId': 'm1',
      'MediaSourceId': 'ms1',
      'PlaySessionId': 'ps1',
      'PositionTicks': 900000000,
      'IsPaused': true,
      'IsMuted': false,
      'VolumeLevel': 80,
      'AudioStreamIndex': 1,
      'SubtitleStreamIndex': -1,
      'PlayMethod': 'DirectPlay',
      'CanSeek': true,
    });

    await api.reportProgress(report);
    expect(adapter.requests.last.path, '/Sessions/Playing/Progress');

    await api.reportStopped(report);
    expect(adapter.requests.last.path, '/Sessions/Playing/Stopped');
    expect(adapter.requests.last.data, {
      'ItemId': 'm1',
      'MediaSourceId': 'ms1',
      'PlaySessionId': 'ps1',
      'PositionTicks': 900000000,
      'Failed': false,
    });
  });

  test('userData legge minutaggio e stato', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'PlaybackPositionTicks': 5,
          'Played': false,
          'PlayedPercentage': 12.5,
        });
    final data = await api.userData('u1', 'm1');
    expect(adapter.requests.last.method, 'GET');
    expect(adapter.requests.last.path, '/UserItems/m1/UserData');
    expect(adapter.requests.last.queryParameters, {'userId': 'u1'});
    expect(data.playbackPositionTicks, 5);
    expect(data.playedPercentage, 12.5);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/core/jellyfin/playback_api_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/core/jellyfin/playback_api.dart`:

```dart
import 'device_profile.dart';
import 'item_models.dart';
import 'jellyfin_http.dart';
import 'playback_models.dart';

/// Endpoint della riproduzione (Jellyfin 10.11). Lancia solo `ApiException`.
class PlaybackApi {
  PlaybackApi(this._http);

  final JellyfinHttp _http;

  /// Come riprodurre [itemId]: sorgenti, tracce, direct play o transcodifica.
  /// - Con [allowDirect] a `false` il server propone solo la transcodifica.
  /// - Senza indici il server sceglie le tracce secondo le preferenze
  ///   dell'utente. [subtitleStreamIndex] `-1` = nessun sottotitolo.
  Future<PlaybackInfoResult> playbackInfo(
    String itemId, {
    required String userId,
    required Duration start,
    required int maxBitrate,
    required bool allowDirect,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final data = await _http.post('/Items/$itemId/PlaybackInfo', body: {
      'UserId': userId,
      'StartTimeTicks': durationToTicks(start),
      'MaxStreamingBitrate': maxBitrate,
      'DeviceProfile': buildDeviceProfile(maxBitrate: maxBitrate),
      'EnableDirectPlay': allowDirect,
      'EnableDirectStream': allowDirect,
      'EnableTranscoding': true,
      'AutoOpenLiveStream': true,
      'MediaSourceId': ?mediaSourceId,
      'AudioStreamIndex': ?audioStreamIndex,
      'SubtitleStreamIndex': ?subtitleStreamIndex,
    });
    return parseJson(data, PlaybackInfoResult.fromJson);
  }

  Future<void> reportStart(PlaybackReport report) async {
    await _http.post('/Sessions/Playing', body: report.toJson());
  }

  Future<void> reportProgress(PlaybackReport report) async {
    await _http.post('/Sessions/Playing/Progress', body: report.toJson());
  }

  Future<void> reportStopped(PlaybackReport report) async {
    await _http.post('/Sessions/Playing/Stopped', body: report.toStoppedJson());
  }

  /// Dati utente aggiornati di un elemento (minutaggio, visto).
  Future<UserItemData> userData(String userId, String itemId) async =>
      parseJson(
          await _http
              .get('/UserItems/$itemId/UserData', query: {'userId': userId}),
          UserItemData.fromJson);
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/core/jellyfin/playback_api_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin/playback_api.dart test/core/jellyfin/playback_api_test.dart
git commit -m "feat: add PlaybackApi for playback info, session reports and user data"
```

---

### Task 6: interfaccia `VideoEngine` e fake di test

**Files:**
- Create: `lib/core/video/video_engine.dart`
- Create: `test/support/playback_fakes.dart`

L'interfaccia non contiene logica: la verifica è `flutter analyze`. I fake vengono usati dai task successivi.

- [ ] **Step 1: crea** `lib/core/video/video_engine.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Cosa aprire: URL, header HTTP (il token non va nell'URL) e posizione di
/// partenza (applicata all'apertura, non come salto successivo).
class VideoSource {
  const VideoSource({
    required this.url,
    this.headers = const {},
    this.start = Duration.zero,
  });

  final String url;
  final Map<String, String> headers;
  final Duration start;
}

enum EngineTrackType { video, audio, subtitle }

/// Traccia vista dal motore (per mpv: una voce di `track-list`).
class EngineTrack {
  const EngineTrack({
    required this.id,
    required this.type,
    this.ffIndex,
    this.external = false,
    this.title,
    this.language,
  });

  /// Id del motore (per mpv: il valore di `aid`/`sid`), numerato per tipo.
  final String id;
  final EngineTrackType type;

  /// Indice dello stream nel file (`ff-index`); `null` per le tracce esterne.
  final int? ffIndex;
  final bool external;
  final String? title;
  final String? language;
}

/// Il file non si è aperto (errore di rete o di formato, timeout).
class EngineOpenException implements Exception {
  const EngineOpenException(this.message);

  final String message;

  @override
  String toString() => 'EngineOpenException($message)';
}

/// Interfaccia del player video, indipendente da media_kit. Serve a provare
/// il player con un motore finto e, nello Spec B (watch party), a
/// controllarne posizione e velocità.
abstract class VideoEngine {
  /// Apre [source] e avvia la riproduzione. Si completa quando il file è
  /// caricato; lancia [EngineOpenException] se non si apre.
  Future<void> open(VideoSource source);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// 0–100.
  Future<void> setVolume(double volume);

  Future<List<EngineTrack>> tracks();

  /// Id da [tracks]; `null` = nessuna traccia.
  Future<void> selectAudio(String? id);

  Future<void> selectSubtitle(String? id);

  /// Carica e seleziona un sottotitolo esterno. Restituisce il suo id.
  Future<String?> addSubtitle(String url, {String? title, String? language});

  /// Positivo = sottotitoli più tardi.
  Future<void> setSubtitleDelay(Duration delay);

  Future<void> dispose();

  Duration get position;

  Duration get duration;

  /// Fin dove il video è già scaricato.
  Duration get buffer;

  bool get playing;

  Stream<Duration> get positionStream;

  Stream<Duration> get durationStream;

  Stream<Duration> get bufferStream;

  Stream<bool> get playingStream;

  Stream<bool> get bufferingStream;

  /// `true` alla fine del video.
  Stream<bool> get completedStream;

  /// Errori segnalati dal motore durante la riproduzione (solo per il log).
  Stream<String> get errorStream;

  /// Superficie su cui viene disegnato il video.
  Widget buildView();
}
```

- [ ] **Step 2: crea** `test/support/playback_fakes.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_api.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/core/video/video_engine.dart';

/// Stream del file di prova, come li restituisce Jellyfin. In transcodifica
/// il server consegna a parte i sottotitoli testuali e brucia nel video
/// quelli grafici.
List<Map<String, dynamic>> testStreams({bool transcode = false}) => [
      {'Index': 0, 'Type': 'Video', 'Codec': 'hevc'},
      {
        'Index': 1,
        'Type': 'Audio',
        'Codec': 'eac3',
        'Language': 'ita',
        'DisplayTitle': 'Italiano - E-AC3 5.1',
        'IsDefault': true,
      },
      {
        'Index': 2,
        'Type': 'Audio',
        'Codec': 'aac',
        'Language': 'eng',
        'DisplayTitle': 'English - AAC Stereo',
      },
      {
        'Index': 3,
        'Type': 'Subtitle',
        'Codec': 'ass',
        'Language': 'ita',
        'DisplayTitle': 'Italiano - ASS',
        'IsTextSubtitleStream': true,
        'DeliveryMethod': transcode ? 'External' : 'Embed',
        'DeliveryUrl':
            ?(transcode ? '/Videos/m1/ms1/Subtitles/3/0/Stream.ass' : null),
      },
      {
        'Index': 4,
        'Type': 'Subtitle',
        'Codec': 'PGSSUB',
        'Language': 'eng',
        'DisplayTitle': 'English - PGS',
        'DeliveryMethod': transcode ? 'Encode' : 'Embed',
      },
      {
        'Index': 5,
        'Type': 'Subtitle',
        'Codec': 'srt',
        'Language': 'ita',
        'DisplayTitle': 'Italiano - SRT - Esterno',
        'IsExternal': true,
        'IsTextSubtitleStream': true,
        'DeliveryMethod': 'External',
        'DeliveryUrl': '/Videos/m1/ms1/Subtitles/5/0/Stream.srt',
      },
    ];

/// Risposta di PlaybackInfo per il file di prova: sorgente `ms1`, sessione
/// `ps1`, audio predefinito 1, sottotitolo predefinito [defaultSubtitle].
PlaybackInfoResult testPlaybackInfo({
  bool directPlay = true,
  int? defaultSubtitle = 3,
  String? errorCode,
}) =>
    PlaybackInfoResult.fromJson({
      'PlaySessionId': 'ps1',
      'ErrorCode': ?errorCode,
      'MediaSources': [
        {
          'Id': 'ms1',
          'SupportsDirectPlay': directPlay,
          'SupportsDirectStream': directPlay,
          'TranscodingUrl': ?(directPlay
              ? null
              : '/videos/m1/master.m3u8?MediaSourceId=ms1&PlaySessionId=ps1'),
          'DefaultAudioStreamIndex': 1,
          'DefaultSubtitleStreamIndex': defaultSubtitle ?? -1,
          'MediaStreams': testStreams(transcode: !directPlay),
        },
      ],
    });

/// Tracce che mpv mostrerebbe per il file di prova in direct play: id
/// numerati per tipo, `ff-index` uguale all'`Index` di Jellyfin.
const testEngineTracks = [
  EngineTrack(id: '1', type: EngineTrackType.video, ffIndex: 0),
  EngineTrack(id: '1', type: EngineTrackType.audio, ffIndex: 1, language: 'ita'),
  EngineTrack(id: '2', type: EngineTrackType.audio, ffIndex: 2, language: 'eng'),
  EngineTrack(
      id: '1', type: EngineTrackType.subtitle, ffIndex: 3, language: 'ita'),
  EngineTrack(
      id: '2', type: EngineTrackType.subtitle, ffIndex: 4, language: 'eng'),
];

typedef PlaybackInfoCall = ({
  String itemId,
  Duration start,
  bool allowDirect,
  int maxBitrate,
  String? mediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
});

/// `PlaybackApi` in memoria: risposte configurabili e chiamate registrate.
class FakePlaybackApi implements PlaybackApi {
  /// Di default risponde come il server: direct play se consentito,
  /// altrimenti transcodifica.
  PlaybackInfoResult Function(PlaybackInfoCall call) onPlaybackInfo =
      (call) => testPlaybackInfo(directPlay: call.allowDirect);
  UserItemData userDataResult = const UserItemData();

  /// Se valorizzato, ogni chiamata lancia questo errore (dopo averla
  /// registrata).
  Object? error;

  /// Ritardo simulato di ogni risposta.
  Duration delay = Duration.zero;

  final playbackInfoCalls = <PlaybackInfoCall>[];
  final started = <PlaybackReport>[];
  final progress = <PlaybackReport>[];
  final stopped = <PlaybackReport>[];
  final userDataCalls = <String>[];

  Future<T> _answer<T>(T Function() value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final failure = error;
    if (failure != null) throw failure;
    return value();
  }

  @override
  Future<PlaybackInfoResult> playbackInfo(
    String itemId, {
    required String userId,
    required Duration start,
    required int maxBitrate,
    required bool allowDirect,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final call = (
      itemId: itemId,
      start: start,
      allowDirect: allowDirect,
      maxBitrate: maxBitrate,
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
    playbackInfoCalls.add(call);
    return _answer(() => onPlaybackInfo(call));
  }

  @override
  Future<void> reportStart(PlaybackReport report) {
    started.add(report);
    return _answer(() {});
  }

  @override
  Future<void> reportProgress(PlaybackReport report) {
    progress.add(report);
    return _answer(() {});
  }

  @override
  Future<void> reportStopped(PlaybackReport report) {
    stopped.add(report);
    return _answer(() {});
  }

  @override
  Future<UserItemData> userData(String userId, String itemId) {
    userDataCalls.add(itemId);
    return _answer(() => userDataResult);
  }
}

/// Motore video in memoria: registra i comandi e simula gli eventi di mpv.
class FakeVideoEngine implements VideoEngine {
  /// Quante delle prossime aperture devono fallire.
  int failOpens = 0;
  List<EngineTrack> engineTracks = const [];

  final opened = <VideoSource>[];
  final selectedAudio = <String?>[];
  final selectedSubtitle = <String?>[];
  final addedSubtitles = <String>[];
  final subtitleDelays = <Duration>[];
  final seeks = <Duration>[];
  final volumes = <double>[];
  bool disposed = false;
  int _nextSubtitleId = 100;

  Duration _position = Duration.zero;
  Duration _duration = const Duration(hours: 2);
  Duration _buffer = Duration.zero;
  bool _playing = false;

  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _buffers = StreamController<Duration>.broadcast();
  final _playingEvents = StreamController<bool>.broadcast();
  final _bufferingEvents = StreamController<bool>.broadcast();
  final _completedEvents = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();

  void emitPosition(Duration position) {
    _position = position;
    _positions.add(position);
  }

  void emitDuration(Duration duration) {
    _duration = duration;
    _durations.add(duration);
  }

  void emitBuffer(Duration buffer) {
    _buffer = buffer;
    _buffers.add(buffer);
  }

  void emitBuffering(bool buffering) => _bufferingEvents.add(buffering);

  void emitError(String message) => _errors.add(message);

  void emitCompleted() {
    _setPlaying(false);
    _completedEvents.add(true);
  }

  void _setPlaying(bool playing) {
    _playing = playing;
    _playingEvents.add(playing);
  }

  @override
  Future<void> open(VideoSource source) async {
    opened.add(source);
    if (failOpens > 0) {
      failOpens--;
      throw const EngineOpenException('apertura simulata non riuscita');
    }
    _position = source.start;
    _setPlaying(true);
  }

  @override
  Future<void> play() async => _setPlaying(true);

  @override
  Future<void> pause() async => _setPlaying(false);

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    emitPosition(position);
  }

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<List<EngineTrack>> tracks() async => engineTracks;

  @override
  Future<void> selectAudio(String? id) async => selectedAudio.add(id);

  @override
  Future<void> selectSubtitle(String? id) async => selectedSubtitle.add(id);

  @override
  Future<String?> addSubtitle(String url,
      {String? title, String? language}) async {
    addedSubtitles.add(url);
    final id = '${_nextSubtitleId++}';
    selectedSubtitle.add(id);
    return id;
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async =>
      subtitleDelays.add(delay);

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  Duration get buffer => _buffer;

  @override
  bool get playing => _playing;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration> get durationStream => _durations.stream;

  @override
  Stream<Duration> get bufferStream => _buffers.stream;

  @override
  Stream<bool> get playingStream => _playingEvents.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingEvents.stream;

  @override
  Stream<bool> get completedStream => _completedEvents.stream;

  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  Widget buildView() =>
      const ColoredBox(key: Key('fake-video'), color: Color(0xFF000000));
}
```

- [ ] **Step 3: analizza e fai girare i test**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti i test PASS.

- [ ] **Step 4: commit**

```bash
git add lib/core/video/video_engine.dart test/support/playback_fakes.dart
git commit -m "feat: add VideoEngine interface and playback test fakes"
```

---

### Task 7: `MediaKitEngine`

**Files:**
- Create: `lib/core/video/media_kit_engine.dart`

Nessun unit test: richiede libmpv. Viene verificato con analyze, build e prova manuale (Task 20).

- [ ] **Step 1: crea** `lib/core/video/media_kit_engine.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_engine.dart';

/// [VideoEngine] sopra media_kit (libmpv).
/// - Sottotitoli disegnati da libass dentro il video (niente widget Flutter).
/// - Decodifica hardware `auto-safe`.
/// - Tracce lette da mpv (`track-list`), perché media_kit non espone
///   `ff-index`.
class MediaKitEngine implements VideoEngine {
  MediaKitEngine({String hwdec = 'auto-safe'})
      : _player = Player(
          configuration: const PlayerConfiguration(
            title: 'WonderFlix',
            libass: true,
            bufferSize: 64 * 1024 * 1024,
          ),
        ) {
    _video = VideoController(
      _player,
      configuration: VideoControllerConfiguration(hwdec: hwdec),
    );
  }

  /// La transcodifica sul server può impiegare parecchi secondi a partire.
  static const openTimeout = Duration(seconds: 60);

  final Player _player;
  late final VideoController _video;

  NativePlayer get _native => _player.platform! as NativePlayer;

  @override
  Future<void> open(VideoSource source) async {
    // Azzera lo stato del file precedente (durata compresa) prima di aprire.
    await _player.stop();
    final loaded = Completer<void>();
    // L'eventuale errore viene letto più sotto: evita che risulti "non gestito".
    loaded.future.ignore();
    final subscriptions = [
      _player.stream.duration.listen((duration) {
        if (duration > Duration.zero && !loaded.isCompleted) loaded.complete();
      }),
      // Un errore prima che la durata sia nota = il file non si è aperto.
      _player.stream.error.listen((message) {
        if (!loaded.isCompleted) {
          loaded.completeError(EngineOpenException(message));
        }
      }),
    ];
    try {
      await _player.open(Media(
        source.url,
        httpHeaders: source.headers,
        start: source.start > Duration.zero ? source.start : null,
      ));
      await loaded.future.timeout(openTimeout,
          onTimeout: () => throw const EngineOpenException('timeout'));
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<List<EngineTrack>> tracks() async {
    final count =
        int.tryParse(await _native.getProperty('track-list/count')) ?? 0;
    final tracks = <EngineTrack>[];
    for (var i = 0; i < count; i++) {
      Future<String> property(String name) =>
          _native.getProperty('track-list/$i/$name');
      final type = switch (await property('type')) {
        'video' => EngineTrackType.video,
        'audio' => EngineTrackType.audio,
        'sub' => EngineTrackType.subtitle,
        _ => null,
      };
      if (type == null) continue;
      final title = await property('title');
      final language = await property('lang');
      tracks.add(EngineTrack(
        id: await property('id'),
        type: type,
        ffIndex: int.tryParse(await property('ff-index')),
        external: await property('external') == 'yes',
        title: title.isEmpty ? null : title,
        language: language.isEmpty ? null : language,
      ));
    }
    return tracks;
  }

  @override
  Future<void> selectAudio(String? id) =>
      _native.setProperty('aid', id ?? 'no');

  @override
  Future<void> selectSubtitle(String? id) =>
      _native.setProperty('sid', id ?? 'no');

  @override
  Future<String?> addSubtitle(String url,
      {String? title, String? language}) async {
    await _native.command(
        ['sub-add', url, 'select', title ?? 'external', language ?? 'auto']);
    final id = await _native.getProperty('sid');
    return id.isEmpty || id == 'no' ? null : id;
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) => _native.setProperty(
      'sub-delay', (delay.inMilliseconds / 1000).toStringAsFixed(3));

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  Duration get buffer => _player.state.buffer;

  @override
  bool get playing => _player.state.playing;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<Duration> get bufferStream => _player.stream.buffer;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Widget buildView() => Video(
        controller: _video,
        controls: NoVideoControls,
        fill: Colors.black,
        // Pausa e ripresa le decide il player, non lo stato della finestra.
        pauseUponEnteringBackgroundMode: false,
        // Con libass i sottotitoli sono già disegnati nel video.
        subtitleViewConfiguration:
            const SubtitleViewConfiguration(visible: false),
      );
}
```

- [ ] **Step 2: analizza e compila**

```bash
flutter analyze
flutter build windows --debug
```
Expected: nessun problema, build riuscita. Se un nome dell'API di media_kit non corrisponde, confrontalo con il sorgente in `$LOCALAPPDATA/Pub/Cache/hosted/pub.dev/media_kit-1.2.6/lib/src/player/native/player/real.dart`, correggi e segnalalo.

- [ ] **Step 3: commit**

```bash
git add lib/core/video/media_kit_engine.dart
git commit -m "feat: add media_kit video engine with libass and mpv track list"
```

---

### Task 8: mappatura delle tracce

**Files:**
- Create: `lib/features/player/track_mapping.dart`
- Test: `test/features/player/track_mapping_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/track_mapping_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/player/track_mapping.dart';

void main() {
  const tracks = [
    EngineTrack(id: '1', type: EngineTrackType.video, ffIndex: 0),
    EngineTrack(id: '1', type: EngineTrackType.audio, ffIndex: 1),
    EngineTrack(id: '2', type: EngineTrackType.audio, ffIndex: 2),
    EngineTrack(id: '1', type: EngineTrackType.subtitle, ffIndex: 3),
    EngineTrack(
        id: '2', type: EngineTrackType.subtitle, ffIndex: 5, external: true),
  ];

  test('Index di Jellyfin = ff-index di mpv', () {
    expect(
        engineTrackFor(
                const MediaStreamInfo(index: 2, kind: StreamKind.audio), tracks)
            ?.id,
        '2');
    expect(
        engineTrackFor(
                const MediaStreamInfo(index: 3, kind: StreamKind.subtitle),
                tracks)
            ?.id,
        '1');
  });

  test('il tipo deve coincidere', () {
    expect(
        engineTrackFor(
            const MediaStreamInfo(index: 1, kind: StreamKind.subtitle), tracks),
        isNull);
  });

  test('le tracce esterne di mpv non si confrontano con gli indici del file',
      () {
    expect(
        engineTrackFor(
            const MediaStreamInfo(index: 5, kind: StreamKind.subtitle), tracks),
        isNull);
  });

  test('stream senza traccia corrispondente', () {
    expect(
        engineTrackFor(
            const MediaStreamInfo(index: 9, kind: StreamKind.audio), tracks),
        isNull);
    expect(
        engineTrackFor(
            const MediaStreamInfo(index: 0, kind: StreamKind.other), tracks),
        isNull);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/track_mapping_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/track_mapping.dart`:

```dart
import '../../core/jellyfin/playback_models.dart';
import '../../core/video/video_engine.dart';

/// Traccia del motore che corrisponde allo stream Jellyfin [stream] di un
/// file in direct play: l'`Index` di Jellyfin è l'`ff-index` di mpv. Le
/// tracce esterne del motore non vengono mai scelte, perché i loro indici
/// non sono quelli del file.
EngineTrack? engineTrackFor(MediaStreamInfo stream, List<EngineTrack> tracks) {
  final type = switch (stream.kind) {
    StreamKind.audio => EngineTrackType.audio,
    StreamKind.subtitle => EngineTrackType.subtitle,
    StreamKind.video => EngineTrackType.video,
    StreamKind.other => null,
  };
  if (type == null) return null;
  for (final track in tracks) {
    if (track.type == type && !track.external && track.ffIndex == stream.index) {
      return track;
    }
  }
  return null;
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/track_mapping_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/player/track_mapping.dart test/features/player/track_mapping_test.dart
git commit -m "feat: map Jellyfin stream indexes to mpv tracks"
```

---

### Task 9: `PlaybackService`

**Files:**
- Create: `lib/features/player/playback_service.dart`
- Test: `test/features/player/playback_service_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/playback_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/device_profile.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/playback_service.dart';

import '../../support/playback_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakePlaybackApi api;

  setUp(() => api = FakePlaybackApi());

  PlaybackService service({Uri? serverUrl, bool breakDirectPlay = false}) =>
      PlaybackService(
        api: api,
        serverUrl: serverUrl ?? testServerUrl,
        authorization: () => 'MediaBrowser Token="t1"',
        breakDirectPlay: breakDirectPlay,
      );

  test('direct play: stream statico con header e posizione', () async {
    final plan = await service().prepare(
        itemId: 'm1', userId: 'u1', start: const Duration(minutes: 3));
    final call = api.playbackInfoCalls.single;
    expect(call.itemId, 'm1');
    expect(call.allowDirect, isTrue);
    expect(call.start, const Duration(minutes: 3));
    expect(call.maxBitrate, originalQualityBitrate);
    expect(call.audioStreamIndex, isNull);
    expect(call.subtitleStreamIndex, isNull);
    expect(plan.method, PlayMethod.directPlay);
    expect(plan.isTranscode, isFalse);
    expect(plan.playSessionId, 'ps1');
    expect(plan.source.url,
        'https://media.example.com/Videos/m1/stream?static=true&mediaSourceId=ms1&playSessionId=ps1');
    expect(plan.source.headers, {'Authorization': 'MediaBrowser Token="t1"'});
    expect(plan.source.start, const Duration(minutes: 3));
    expect(plan.audioIndex, 1);
    expect(plan.subtitleIndex, 3);
  });

  test('il server non consente il direct play: HLS sotto il sotto-percorso',
      () async {
    api.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final plan = await service(
            serverUrl: Uri.parse('https://host.example.com/jellyfin'))
        .prepare(itemId: 'm1', userId: 'u1');
    expect(plan.method, PlayMethod.transcode);
    expect(plan.source.url,
        'https://host.example.com/jellyfin/videos/m1/master.m3u8?MediaSourceId=ms1&PlaySessionId=ps1');
  });

  test('forceTranscode: chiede solo la transcodifica e la usa', () async {
    final plan = await service().prepare(
      itemId: 'm1',
      userId: 'u1',
      forceTranscode: true,
      mediaSourceId: 'ms1',
      audioIndex: 2,
      subtitleIndex: -1,
    );
    final call = api.playbackInfoCalls.single;
    expect(call.allowDirect, isFalse);
    expect(call.mediaSourceId, 'ms1');
    expect(call.audioStreamIndex, 2);
    expect(call.subtitleStreamIndex, -1);
    expect(plan.method, PlayMethod.transcode);
    expect(plan.audioIndex, 2);
    expect(plan.subtitleIndex, isNull, reason: '-1 = nessun sottotitolo');
  });

  test('nessun sottotitolo predefinito', () async {
    api.onPlaybackInfo = (_) => testPlaybackInfo(defaultSubtitle: null);
    final plan = await service().prepare(itemId: 'm1', userId: 'u1');
    expect(plan.subtitleIndex, isNull);
  });

  test('errori: ErrorCode, nessuna sorgente, nessun modo di riprodurre',
      () async {
    api.onPlaybackInfo = (_) => testPlaybackInfo(errorCode: 'NotAllowed');
    await expectLater(
        service().prepare(itemId: 'm1', userId: 'u1'),
        throwsA(isA<PlaybackUnavailableException>()
            .having((e) => e.code, 'code', 'NotAllowed')));

    api.onPlaybackInfo =
        (_) => PlaybackInfoResult.fromJson({'MediaSources': []});
    await expectLater(service().prepare(itemId: 'm1', userId: 'u1'),
        throwsA(isA<PlaybackUnavailableException>()));

    api.onPlaybackInfo = (_) => PlaybackInfoResult.fromJson({
          'MediaSources': [
            {'Id': 'ms1', 'SupportsDirectPlay': false},
          ],
        });
    await expectLater(service().prepare(itemId: 'm1', userId: 'u1'),
        throwsA(isA<PlaybackUnavailableException>()));
  });

  test('burnsIn: solo sottotitoli non esterni in transcodifica', () async {
    api.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final transcode = await service().prepare(itemId: 'm1', userId: 'u1');
    expect(transcode.burnsIn(4), isTrue, reason: 'PGS bruciato');
    expect(transcode.burnsIn(3), isFalse, reason: 'ASS estratto a parte');
    expect(transcode.burnsIn(null), isFalse);

    api.onPlaybackInfo = (_) => testPlaybackInfo();
    final direct = await service().prepare(itemId: 'm1', userId: 'u1');
    expect(direct.burnsIn(4), isFalse);
  });

  test('subtitleUrl e breakDirectPlay', () async {
    final plan = await service().prepare(itemId: 'm1', userId: 'u1');
    expect(service().subtitleUrl(plan.mediaSource.stream(5)!),
        'https://media.example.com/Videos/m1/ms1/Subtitles/5/0/Stream.srt');

    final broken =
        await service(breakDirectPlay: true).prepare(itemId: 'm1', userId: 'u1');
    expect(broken.source.url, contains('mediaSourceId=wonderflix-test-invalid'));
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/playback_service_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/playback_service.dart`:

```dart
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/device_profile.dart';
import '../../core/jellyfin/playback_api.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../core/video/video_engine.dart';

/// Come riprodurre un elemento: sorgente, metodo, URL con header e tracce.
class PlaybackPlan {
  const PlaybackPlan({
    required this.itemId,
    required this.method,
    required this.mediaSource,
    required this.playSessionId,
    required this.source,
    this.audioIndex,
    this.subtitleIndex,
  });

  final String itemId;
  final PlayMethod method;
  final MediaSourceInfo mediaSource;
  final String? playSessionId;
  final VideoSource source;

  /// Indici Jellyfin delle tracce da mostrare; `null` = nessuna.
  final int? audioIndex;
  final int? subtitleIndex;

  bool get isTranscode => method == PlayMethod.transcode;

  /// `true` se il sottotitolo [index] viene bruciato nel video dal server
  /// (grafico, in transcodifica): cambiarlo richiede una nuova conversione.
  bool burnsIn(int? index) {
    if (!isTranscode || index == null) return false;
    final stream = mediaSource.stream(index);
    return stream != null && !stream.deliveredExternally;
  }
}

/// Sceglie come riprodurre un elemento: direct play dal file originale
/// quando il server lo consente, altrimenti la transcodifica HLS proposta
/// dal server.
class PlaybackService {
  PlaybackService({
    required PlaybackApi api,
    required Uri serverUrl,
    required String Function() authorization,
    this.breakDirectPlay = false,
  })  : _api = api,
        _serverUrl = serverUrl,
        _authorization = authorization;

  final PlaybackApi _api;
  final Uri _serverUrl;

  /// Header `Authorization` corrente: il token viaggia nell'header, non
  /// nell'URL.
  final String Function() _authorization;

  /// Solo per le prove manuali del ripiego: rende invalido l'URL del direct
  /// play, così l'apertura fallisce.
  final bool breakDirectPlay;

  /// - [forceTranscode]: chiede al server solo la transcodifica (ripiego o
  ///   cambio di traccia in transcodifica).
  /// - Indici `null`: tracce predefinite del server (preferenze dell'utente).
  /// - [subtitleIndex] `-1`: nessun sottotitolo.
  Future<PlaybackPlan> prepare({
    required String itemId,
    required String userId,
    Duration start = Duration.zero,
    bool forceTranscode = false,
    String? mediaSourceId,
    int? audioIndex,
    int? subtitleIndex,
    int maxBitrate = originalQualityBitrate,
  }) async {
    final info = await _api.playbackInfo(
      itemId,
      userId: userId,
      start: start,
      maxBitrate: maxBitrate,
      allowDirect: !forceTranscode,
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioIndex,
      subtitleStreamIndex: subtitleIndex,
    );
    final code = info.errorCode;
    if (code != null) throw PlaybackUnavailableException(code);
    final source = _pickSource(info.mediaSources, mediaSourceId);
    if (source == null) throw const PlaybackUnavailableException(null);

    final String url;
    final PlayMethod method;
    final transcodingUrl = source.transcodingUrl;
    if (!forceTranscode && source.supportsDirectPlay) {
      url = Uri.parse('$_serverUrl/Videos/$itemId/stream').replace(
        queryParameters: {
          'static': 'true',
          'mediaSourceId':
              breakDirectPlay ? 'wonderflix-test-invalid' : source.id,
          'playSessionId': ?info.playSessionId,
        },
      ).toString();
      method = PlayMethod.directPlay;
    } else if (transcodingUrl != null) {
      url = resolveServerUrl(_serverUrl, transcodingUrl);
      method = PlayMethod.transcode;
    } else {
      throw const PlaybackUnavailableException(null);
    }

    int? chosen(int? requested, int? fallback) {
      final value = requested ?? fallback;
      return value == null || value < 0 ? null : value;
    }

    return PlaybackPlan(
      itemId: itemId,
      method: method,
      mediaSource: source,
      playSessionId: info.playSessionId,
      source: VideoSource(
        url: url,
        headers: {'Authorization': _authorization()},
        start: start,
      ),
      audioIndex: chosen(audioIndex, source.defaultAudioStreamIndex),
      subtitleIndex: chosen(subtitleIndex, source.defaultSubtitleStreamIndex),
    );
  }

  /// URL assoluto di un sottotitolo da caricare a parte
  /// (`MediaStreamInfo.deliveredExternally`).
  String subtitleUrl(MediaStreamInfo stream) =>
      resolveServerUrl(_serverUrl, stream.deliveryUrl!);

  static MediaSourceInfo? _pickSource(
      List<MediaSourceInfo> sources, String? id) {
    if (id != null) {
      for (final source in sources) {
        if (source.id == id) return source;
      }
    }
    return sources.firstOrNull;
  }
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/playback_service_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/player/playback_service.dart test/features/player/playback_service_test.dart
git commit -m "feat: choose between direct play and HLS transcoding"
```

---

### Task 10: `ProgressReporter`

**Files:**
- Create: `lib/features/player/progress_reporter.dart`
- Test: `test/features/player/progress_reporter_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/progress_reporter_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/progress_reporter.dart';

import '../../support/playback_fakes.dart';

PlaybackReport reportAt(Duration position) => PlaybackReport(
      itemId: 'm1',
      mediaSourceId: 'ms1',
      playSessionId: 'ps1',
      position: position,
      isPaused: false,
      isMuted: false,
      volume: 100,
      audioStreamIndex: 1,
      subtitleStreamIndex: null,
      playMethod: PlayMethod.directPlay,
    );

void main() {
  test('inizio, avanzamento ogni 10 s e a ogni evento, fine una sola volta',
      () {
    fakeAsync((async) {
      final api = FakePlaybackApi();
      var position = Duration.zero;
      final reporter =
          ProgressReporter(api: api, snapshot: () => reportAt(position));

      unawaited(reporter.start());
      async.flushMicrotasks();
      expect(api.started, hasLength(1));

      async.elapse(const Duration(seconds: 25));
      expect(api.progress, hasLength(2));

      reporter.onEvent();
      async.flushMicrotasks();
      expect(api.progress, hasLength(3));

      position = const Duration(minutes: 5);
      unawaited(reporter.stop());
      unawaited(reporter.stop());
      async.flushMicrotasks();
      expect(api.stopped.single.position, const Duration(minutes: 5));

      async.elapse(const Duration(seconds: 30));
      reporter.onEvent();
      async.flushMicrotasks();
      expect(api.progress, hasLength(3), reason: 'niente report dopo la fine');
    });
  });

  test('la fine non aspetta più di 2 s', () {
    fakeAsync((async) {
      final api = FakePlaybackApi()..delay = const Duration(seconds: 10);
      final reporter =
          ProgressReporter(api: api, snapshot: () => reportAt(Duration.zero));
      unawaited(reporter.start());
      var done = false;
      unawaited(reporter.stop().then((_) => done = true));
      async.elapse(const Duration(milliseconds: 1900));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 200));
      expect(done, isTrue);
      // Lascia terminare le richieste lente.
      async.elapse(const Duration(seconds: 10));
    });
  });

  test('gli errori di rete non interrompono la riproduzione', () async {
    final api = FakePlaybackApi()..error = const ServerUnreachableException();
    final reporter =
        ProgressReporter(api: api, snapshot: () => reportAt(Duration.zero));
    await reporter.start();
    reporter.onEvent();
    await reporter.stop();
    expect(api.started, hasLength(1));
    expect(api.stopped, hasLength(1));
  });

  test('senza start, stop non invia nulla', () async {
    final api = FakePlaybackApi();
    await ProgressReporter(api: api, snapshot: () => reportAt(Duration.zero))
        .stop();
    expect(api.stopped, isEmpty);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/progress_reporter_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/progress_reporter.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/jellyfin/playback_api.dart';
import '../../core/jellyfin/playback_models.dart';

/// Invia a Jellyfin l'inizio, l'avanzamento (ogni [interval] e a ogni
/// evento) e la fine della riproduzione. Gli errori di rete vengono solo
/// scritti nel log: la riproduzione non si interrompe. In caso di crash si
/// perdono al massimo [interval] di avanzamento.
class ProgressReporter {
  ProgressReporter({
    required PlaybackApi api,
    required PlaybackReport Function() snapshot,
    this.interval = const Duration(seconds: 10),
    this.stopTimeout = const Duration(seconds: 2),
  })  : _api = api,
        _snapshot = snapshot;

  final PlaybackApi _api;

  /// Stato corrente della riproduzione, letto al momento di ogni invio.
  final PlaybackReport Function() _snapshot;
  final Duration interval;

  /// Attesa massima del report di fine (es. alla chiusura della finestra).
  final Duration stopTimeout;

  Timer? _timer;
  bool _started = false;
  bool _stopped = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(interval, (_) => onEvent());
    await _send(() => _api.reportStart(_snapshot()));
  }

  /// Avanzamento immediato: pausa, ripresa, salto, cambio traccia.
  void onEvent() {
    if (!_started || _stopped) return;
    unawaited(_send(() => _api.reportProgress(_snapshot())));
  }

  /// Fine della riproduzione. Si può chiamare più volte: invia una volta sola.
  Future<void> stop() async {
    if (!_started || _stopped) return;
    _stopped = true;
    _timer?.cancel();
    final report = _snapshot();
    await _send(() => _api.reportStopped(report))
        .timeout(stopTimeout, onTimeout: () {});
  }

  Future<void> _send(Future<void> Function() request) async {
    try {
      await request();
    } on Object catch (error) {
      debugPrint('[player] report non inviato: $error');
    }
  }
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/progress_reporter_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/player/progress_reporter.dart test/features/player/progress_reporter_test.dart
git commit -m "feat: report playback start, progress and stop to Jellyfin"
```

---

### Task 11: finestra del player e provider

**Files:**
- Create: `lib/features/player/player_window.dart`
- Create: `lib/features/player/player_providers.dart`
- Modify: `test/support/playback_fakes.dart` (aggiunta di `FakePlayerWindow`)

Solo collegamenti senza logica: la verifica è `flutter analyze`.

- [ ] **Step 1: crea** `lib/features/player/player_window.dart`:

```dart
import 'dart:async';

import 'package:window_manager/window_manager.dart';

/// Operazioni sulla finestra usate dal player (sostituibili nei test).
abstract class PlayerWindow {
  Future<void> setFullScreen(bool value);

  /// Con `true` la finestra non si chiude da sola: vengono chiamati gli
  /// ascoltatori di [addCloseListener], che poi devono chiamare [destroy].
  Future<void> setPreventClose(bool value);

  Future<void> destroy();

  void addCloseListener(Future<void> Function() onClose);

  void removeCloseListener(Future<void> Function() onClose);
}

class WindowManagerPlayerWindow implements PlayerWindow {
  final _listeners = <Future<void> Function(), _CloseListener>{};

  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);

  @override
  Future<void> setPreventClose(bool value) =>
      windowManager.setPreventClose(value);

  @override
  Future<void> destroy() => windowManager.destroy();

  @override
  void addCloseListener(Future<void> Function() onClose) {
    final listener = _CloseListener(onClose);
    _listeners[onClose] = listener;
    windowManager.addListener(listener);
  }

  @override
  void removeCloseListener(Future<void> Function() onClose) {
    final listener = _listeners.remove(onClose);
    if (listener != null) windowManager.removeListener(listener);
  }
}

class _CloseListener with WindowListener {
  _CloseListener(this._onClose);

  final Future<void> Function() _onClose;

  @override
  void onWindowClose() => unawaited(_onClose());
}
```

- [ ] **Step 2: crea** `lib/features/player/player_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/playback_api.dart';
import '../../core/video/media_kit_engine.dart';
import '../../core/video/video_engine.dart';
import 'playback_service.dart';
import 'player_window.dart';

final playbackApiProvider =
    Provider<PlaybackApi>((ref) => PlaybackApi(ref.watch(jellyfinHttpProvider)));

final playbackServiceProvider = Provider<PlaybackService>((ref) {
  final http = ref.watch(jellyfinHttpProvider);
  return PlaybackService(
    api: ref.watch(playbackApiProvider),
    serverUrl: ref.watch(appConfigProvider).serverUrl,
    authorization: () => http.authorizationHeader,
    // Solo per provare il ripiego: --dart-define=wfBreakDirectPlay=true
    breakDirectPlay: const bool.fromEnvironment('wfBreakDirectPlay'),
  );
});

/// Crea un motore video per ogni riproduzione; nei test si usa un motore finto.
final videoEngineFactoryProvider =
    Provider<VideoEngine Function()>((ref) => MediaKitEngine.new);

final playerWindowProvider =
    Provider<PlayerWindow>((ref) => WindowManagerPlayerWindow());
```

- [ ] **Step 3: aggiungi `FakePlayerWindow`** in fondo a `test/support/playback_fakes.dart`, con l'import `import 'package:wonderflix/features/player/player_window.dart';` in testa:

```dart
/// Finestra in memoria: registra le chiamate e simula la chiusura.
class FakePlayerWindow implements PlayerWindow {
  final fullScreenCalls = <bool>[];
  final preventCloseCalls = <bool>[];
  bool destroyed = false;
  final _closeListeners = <Future<void> Function()>[];

  @override
  Future<void> setFullScreen(bool value) async => fullScreenCalls.add(value);

  @override
  Future<void> setPreventClose(bool value) async =>
      preventCloseCalls.add(value);

  @override
  Future<void> destroy() async {
    destroyed = true;
  }

  @override
  void addCloseListener(Future<void> Function() onClose) =>
      _closeListeners.add(onClose);

  @override
  void removeCloseListener(Future<void> Function() onClose) =>
      _closeListeners.remove(onClose);

  /// Simula il clic sulla X della finestra.
  Future<void> simulateClose() =>
      Future.wait([for (final listener in [..._closeListeners]) listener()]);
}
```

- [ ] **Step 4: analizza e fai girare i test**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti i test PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/player/player_window.dart lib/features/player/player_providers.dart test/support/playback_fakes.dart
git commit -m "feat: add player window abstraction and playback providers"
```

---

### Task 12: `PlayerController` — avvio, ripiego e chiusura

**Files:**
- Create: `lib/features/player/player_controller.dart`
- Test: `test/features/player/player_controller_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/player_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakePlaybackApi playback;
  late FakeVideoEngine engine;
  late ProviderContainer container;
  const args = (itemId: 'm1', start: Duration(minutes: 3));
  final provider = playerControllerProvider(args);

  setUp(() {
    library = FakeLibraryApi()
      ..itemsById['m1'] = testItem(id: 'm1', runtimeMinutes: 120);
    playback = FakePlaybackApi();
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        playbackApiProvider.overrideWithValue(playback),
        playbackServiceProvider.overrideWithValue(PlaybackService(
          api: playback,
          serverUrl: testServerUrl,
          authorization: () => 'MediaBrowser Token="t1"',
        )),
        videoEngineFactoryProvider.overrideWithValue(() => engine),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
  });

  /// Monta il controller (come fa la schermata) e aspetta l'avvio.
  Future<PlayerController> start() async {
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    return container.read(provider.notifier);
  }

  PlayerViewState view() => container.read(provider);

  test('direct play: stream con header, ripresa e tracce predefinite',
      () async {
    await start();
    expect(view().status, PlayerStatus.ready);
    expect(view().item?.id, 'm1');
    final source = engine.opened.single;
    expect(source.url,
        'https://media.example.com/Videos/m1/stream?static=true&mediaSourceId=ms1&playSessionId=ps1');
    expect(source.headers, {'Authorization': 'MediaBrowser Token="t1"'});
    expect(source.start, const Duration(minutes: 3));
    expect(engine.selectedAudio, ['1']);
    expect(engine.selectedSubtitle, ['1']);
    expect(view().audioIndex, 1);
    expect(view().subtitleIndex, 3);
    expect(view().playing, isTrue);
    final started = playback.started.single;
    expect(started.playMethod, PlayMethod.directPlay);
    expect(started.playSessionId, 'ps1');
    expect(started.position, const Duration(minutes: 3));
  });

  test('direct play non riuscito: un solo tentativo in transcodifica',
      () async {
    engine.failOpens = 1;
    await start();
    expect(playback.playbackInfoCalls.map((c) => c.allowDirect), [true, false]);
    final retry = playback.playbackInfoCalls.last;
    expect(retry.mediaSourceId, 'ms1');
    expect(retry.audioStreamIndex, 1);
    expect(retry.subtitleStreamIndex, 3);
    expect(retry.start, const Duration(minutes: 3));
    expect(engine.opened, hasLength(2));
    expect(engine.opened.last.url,
        'https://media.example.com/videos/m1/master.m3u8?MediaSourceId=ms1&PlaySessionId=ps1');
    expect(view().status, PlayerStatus.ready);
    expect(view().transcodingFallback, isTrue);
    // Sottotitolo testuale estratto dal server: caricato a parte.
    expect(engine.addedSubtitles,
        ['https://media.example.com/Videos/m1/ms1/Subtitles/3/0/Stream.ass']);
    expect(playback.started.single.playMethod, PlayMethod.transcode);
  });

  test('anche la transcodifica fallisce: errore, poi Riprova', () async {
    engine.failOpens = 2;
    final controller = await start();
    expect(view().status, PlayerStatus.error);
    expect(view().error, isA<EngineOpenException>());
    expect(playback.playbackInfoCalls, hasLength(2), reason: 'un solo ripiego');

    await controller.retry();
    expect(view().status, PlayerStatus.ready);
    expect(view().error, isNull);
    expect(playback.playbackInfoCalls.last.allowDirect, isFalse);
  });

  test('errore del server: nessuna apertura', () async {
    playback.error = const ServerUnreachableException();
    await start();
    expect(view().status, PlayerStatus.error);
    expect(view().error, isA<ServerUnreachableException>());
    expect(engine.opened, isEmpty);
  });

  test('fine del video', () async {
    await start();
    engine.emitCompleted();
    await pumpEventQueue();
    expect(view().finished, isTrue);
  });

  test('close: fine della sessione, motore liberato, minutaggio aggiornato',
      () async {
    final controller = await start();
    engine.emitPosition(const Duration(minutes: 60));
    playback.userDataResult = const UserItemData(
        playbackPositionTicks: 36000000000, playedPercentage: 50);

    await controller.close();
    expect(playback.stopped.single.position, const Duration(minutes: 60));
    expect(engine.disposed, isTrue);
    expect(playback.userDataCalls, ['m1']);
    expect(container.read(userDataOverridesProvider)['m1']?.playbackPositionTicks,
        36000000000);
    expect(container.read(userDataRevisionProvider), 1);

    await controller.close();
    expect(playback.stopped, hasLength(1));
  });

  test('close senza rete: stima locale del minutaggio', () async {
    final controller = await start();
    engine.emitPosition(const Duration(minutes: 30));
    playback.error = const ServerUnreachableException();

    await controller.close();
    final data = container.read(userDataOverridesProvider)['m1'];
    expect(data?.playbackPositionTicks,
        durationToTicks(const Duration(minutes: 30)));
    expect(data?.playedPercentage, 25);
    expect(container.read(userDataRevisionProvider), 1);
  });

  test('uscita dalla schermata: la dispose chiude la riproduzione', () async {
    final subscription = container.listen(provider, (_, _) {});
    await pumpEventQueue();
    subscription.close();
    await pumpEventQueue();
    expect(playback.stopped, hasLength(1));
    expect(engine.disposed, isTrue);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/player_controller_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/player_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/library_api.dart';
import '../../core/jellyfin/playback_api.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../core/video/video_engine.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import 'playback_service.dart';
import 'player_providers.dart';
import 'progress_reporter.dart';
import 'track_mapping.dart';

/// Elemento da riprodurre e posizione di partenza (chiave del provider).
typedef PlayerArgs = ({String itemId, Duration start});

enum PlayerStatus { loading, ready, error }

class PlayerViewState {
  const PlayerViewState({
    this.status = PlayerStatus.loading,
    this.item,
    this.plan,
    this.error,
    this.playing = false,
    this.buffering = false,
    this.volume = 100,
    this.muted = false,
    this.audioIndex,
    this.subtitleIndex,
    this.subtitleDelay = Duration.zero,
    this.transcodingFallback = false,
    this.finished = false,
  });

  final PlayerStatus status;
  final JellyfinItem? item;
  final PlaybackPlan? plan;
  final Object? error;
  final bool playing;
  final bool buffering;

  /// 0–100.
  final double volume;
  final bool muted;

  /// Indici Jellyfin (`MediaStream.Index`) delle tracce in uso; `null` =
  /// nessuna.
  final int? audioIndex;
  final int? subtitleIndex;
  final Duration subtitleDelay;

  /// `true` dopo il ripiego automatico sulla transcodifica.
  final bool transcodingFallback;

  /// Il video è arrivato alla fine: la schermata esce dal player.
  final bool finished;

  List<MediaStreamInfo> get audioStreams =>
      plan?.mediaSource.audioStreams ?? const [];

  List<MediaStreamInfo> get subtitleStreams =>
      plan?.mediaSource.subtitleStreams ?? const [];

  static const _keep = Object();

  /// `error`, `audioIndex` e `subtitleIndex` accettano `null` esplicito.
  PlayerViewState copyWith({
    PlayerStatus? status,
    JellyfinItem? item,
    PlaybackPlan? plan,
    Object? error = _keep,
    bool? playing,
    bool? buffering,
    double? volume,
    bool? muted,
    Object? audioIndex = _keep,
    Object? subtitleIndex = _keep,
    Duration? subtitleDelay,
    bool? transcodingFallback,
    bool? finished,
  }) =>
      PlayerViewState(
        status: status ?? this.status,
        item: item ?? this.item,
        plan: plan ?? this.plan,
        error: identical(error, _keep) ? this.error : error,
        playing: playing ?? this.playing,
        buffering: buffering ?? this.buffering,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        audioIndex:
            identical(audioIndex, _keep) ? this.audioIndex : audioIndex as int?,
        subtitleIndex: identical(subtitleIndex, _keep)
            ? this.subtitleIndex
            : subtitleIndex as int?,
        subtitleDelay: subtitleDelay ?? this.subtitleDelay,
        transcodingFallback: transcodingFallback ?? this.transcodingFallback,
        finished: finished ?? this.finished,
      );
}

/// Coordina una riproduzione:
/// - PlaybackInfo e apertura nel motore video;
/// - un solo ripiego automatico sulla transcodifica se il direct play non
///   parte;
/// - tracce audio e sottotitoli, comandi, report a Jellyfin;
/// - alla chiusura, fine della sessione e minutaggio aggiornato in tutta
///   l'app.
class PlayerController extends Notifier<PlayerViewState> {
  PlayerController(this.args);

  final PlayerArgs args;

  late VideoEngine _engine;
  late PlaybackService _service;
  late PlaybackApi _api;
  late LibraryApi _library;
  late String _userId;
  late UserDataOverrides _overrides;
  late UserDataRevision _userDataRevision;

  /// Copia dello stato, leggibile anche dopo la dispose del provider.
  PlayerViewState _view = const PlayerViewState();
  ProgressReporter? _reporter;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Sottotitoli esterni già caricati nel motore: indice Jellyfin → id.
  final _externalSubtitles = <int, String>{};
  Future<void>? _closing;
  int _generation = 0;
  Duration _resumeAt = Duration.zero;
  bool _forceTranscode = false;

  VideoEngine get engine => _engine;

  @override
  PlayerViewState build() {
    _engine = ref.read(videoEngineFactoryProvider)();
    _service = ref.read(playbackServiceProvider);
    _api = ref.read(playbackApiProvider);
    _library = ref.read(libraryApiProvider);
    _userId = ref.read(currentUserIdProvider);
    _overrides = ref.read(userDataOverridesProvider.notifier);
    _userDataRevision = ref.read(userDataRevisionProvider.notifier);
    _listenToEngine();
    ref.onDispose(() => unawaited(close()));
    unawaited(Future.microtask(() => _start(args.start)));
    return _view;
  }

  void _emit(PlayerViewState next) {
    _view = next;
    if (ref.mounted) state = next;
  }

  void _listenToEngine() {
    _subscriptions.addAll([
      _engine.playingStream.listen((playing) {
        if (playing == _view.playing) return;
        _emit(_view.copyWith(playing: playing));
        _reporter?.onEvent();
      }),
      _engine.bufferingStream
          .listen((buffering) => _emit(_view.copyWith(buffering: buffering))),
      _engine.completedStream.listen((completed) {
        if (completed && _view.status == PlayerStatus.ready) {
          _emit(_view.copyWith(finished: true));
        }
      }),
      _engine.errorStream
          .listen((message) => debugPrint('[player] motore: $message')),
    ]);
  }

  /// Prepara e apre la riproduzione da [start]. Senza indici si usano le
  /// tracce predefinite del server; `subtitleIndex: -1` = nessun sottotitolo.
  Future<void> _start(
    Duration start, {
    bool forceTranscode = false,
    String? mediaSourceId,
    int? audioIndex,
    int? subtitleIndex,
  }) async {
    final generation = ++_generation;
    bool stale() =>
        !ref.mounted || generation != _generation || _closing != null;
    _resumeAt = start;
    _forceTranscode = forceTranscode;
    final previous = _reporter;
    _reporter = null;
    _emit(_view.copyWith(
        status: PlayerStatus.loading, error: null, finished: false));
    // Una nuova apertura chiude la sessione precedente (cambio di traccia in
    // transcodifica).
    await previous?.stop();
    PlaybackPlan? plan;
    try {
      final item = _view.item ?? await _library.item(_userId, args.itemId);
      if (stale()) return;
      _emit(_view.copyWith(item: item));
      plan = await _service.prepare(
        itemId: args.itemId,
        userId: _userId,
        start: start,
        forceTranscode: forceTranscode,
        mediaSourceId: mediaSourceId ?? _view.plan?.mediaSource.id,
        audioIndex: audioIndex,
        subtitleIndex: subtitleIndex,
      );
      if (stale()) return;
      _externalSubtitles.clear();
      await _engine.open(plan.source);
      if (stale()) return;
      await _engine.setVolume(_view.muted ? 0 : _view.volume);
      if (_view.subtitleDelay != Duration.zero) {
        await _engine.setSubtitleDelay(_view.subtitleDelay);
      }
      await _applyTracks(plan);
      if (stale()) return;
      _emit(_view.copyWith(
        status: PlayerStatus.ready,
        plan: plan,
        audioIndex: plan.audioIndex,
        subtitleIndex: plan.subtitleIndex,
        playing: _engine.playing,
      ));
      final reporter =
          _reporter = ProgressReporter(api: _api, snapshot: _report);
      await reporter.start();
    } on EngineOpenException catch (error) {
      if (stale()) return;
      if (plan != null && !plan.isTranscode) {
        debugPrint(
            '[player] direct play non riuscito ($error): provo la transcodifica');
        _emit(_view.copyWith(transcodingFallback: true));
        return _start(
          start,
          forceTranscode: true,
          mediaSourceId: plan.mediaSource.id,
          audioIndex: plan.audioIndex,
          subtitleIndex: plan.subtitleIndex ?? -1,
        );
      }
      _fail(error);
    } on Object catch (error) {
      if (stale()) return;
      _fail(error);
    }
  }

  void _fail(Object error) {
    debugPrint('[player] errore: $error');
    _emit(_view.copyWith(status: PlayerStatus.error, error: error));
  }

  /// Seleziona nel motore le tracce del piano. In transcodifica l'audio è già
  /// quello scelto dal server.
  Future<void> _applyTracks(PlaybackPlan plan) async {
    final audioIndex = plan.audioIndex;
    if (!plan.isTranscode && audioIndex != null) {
      final stream = plan.mediaSource.stream(audioIndex);
      final track =
          stream == null ? null : engineTrackFor(stream, await _engine.tracks());
      if (track != null) await _engine.selectAudio(track.id);
    }
    await _showSubtitle(plan, plan.subtitleIndex);
  }

  /// Mostra il sottotitolo Jellyfin [index] (`null` = nessuno):
  /// - consegnato a parte (esterno o estratto dal server): caricato una
  ///   volta dal suo URL, poi riusato;
  /// - interno in direct play: la traccia del file con lo stesso `ff-index`;
  /// - bruciato in transcodifica: è già nel video, non c'è nulla da fare.
  Future<void> _showSubtitle(PlaybackPlan plan, int? index) async {
    final stream = index == null ? null : plan.mediaSource.stream(index);
    if (stream == null) return _engine.selectSubtitle(null);
    if (stream.deliveredExternally) {
      final known = _externalSubtitles[stream.index];
      if (known != null) return _engine.selectSubtitle(known);
      final id = await _engine.addSubtitle(_service.subtitleUrl(stream),
          title: stream.displayTitle, language: stream.language);
      if (id != null) _externalSubtitles[stream.index] = id;
      return;
    }
    if (plan.isTranscode) return;
    final track = engineTrackFor(stream, await _engine.tracks());
    await _engine.selectSubtitle(track?.id);
  }

  PlaybackReport _report() {
    final plan = _view.plan!;
    return PlaybackReport(
      itemId: args.itemId,
      mediaSourceId: plan.mediaSource.id,
      playSessionId: plan.playSessionId,
      position: _engine.position,
      isPaused: !_engine.playing,
      isMuted: _view.muted,
      volume: _view.volume.round(),
      audioStreamIndex: _view.audioIndex,
      subtitleStreamIndex: _view.subtitleIndex,
      playMethod: plan.method,
    );
  }

  /// Dopo un errore: stesso punto, stesso metodo (direct play o
  /// transcodifica), stesse tracce se erano già state scelte.
  Future<void> retry() {
    final hadPlan = _view.plan != null;
    return _start(
      _resumeAt,
      forceTranscode: _forceTranscode,
      audioIndex: hadPlan ? _view.audioIndex : null,
      subtitleIndex: hadPlan ? (_view.subtitleIndex ?? -1) : null,
    );
  }

  /// Chiude la riproduzione: segnala la fine a Jellyfin (attesa massima 2 s),
  /// libera il motore e aggiorna il minutaggio locale. Si può chiamare più
  /// volte.
  Future<void> close() => _closing ??= _shutdown();

  Future<void> _shutdown() async {
    _generation++;
    final item = _view.item;
    final position = _engine.position;
    final reporter = _reporter;
    _reporter = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    await reporter?.stop();
    try {
      await _engine.dispose();
    } on Object catch (error) {
      debugPrint('[player] chiusura del motore: $error');
    }
    if (reporter != null && item != null) {
      await _refreshUserData(item, position);
    }
  }

  /// Aggiorna subito minutaggio e percentuale in tutta l'app (Home, schede,
  /// prossimo episodio) senza aspettare il WebSocket: prima una stima
  /// locale, poi i dati del server se raggiungibile.
  Future<void> _refreshUserData(JellyfinItem item, Duration position) async {
    try {
      final ticks = durationToTicks(position);
      final runtime = item.runTimeTicks;
      _overrides.apply(
        item.id,
        _overrides.effective(item).copyWith(
              playbackPositionTicks: ticks,
              playedPercentage: runtime == null || runtime == 0
                  ? null
                  : ticks / runtime * 100,
            ),
      );
      try {
        _overrides.apply(item.id, await _api.userData(_userId, item.id));
      } on Object catch (error) {
        debugPrint('[player] dati utente non aggiornati dal server: $error');
      }
      _userDataRevision.bump();
    } on Object catch (error) {
      // Es. utente disconnesso nel frattempo: non c'è nulla da aggiornare.
      debugPrint('[player] dati utente non aggiornati: $error');
    }
  }
}

final playerControllerProvider = NotifierProvider.autoDispose
    .family<PlayerController, PlayerViewState, PlayerArgs>(
        PlayerController.new);
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/player_controller_test.dart`
Expected: PASS. Se il test "uscita dalla schermata" fallisce perché la dispose di Riverpod avviene più tardi, aggiungi un secondo `await pumpEventQueue();` prima delle `expect` e segnalalo.

- [ ] **Step 5: analizza e commit**

```bash
flutter analyze
git add lib/features/player/player_controller.dart test/features/player/player_controller_test.dart
git commit -m "feat: add player controller with transcoding fallback and progress sync"
```

---

### Task 13: `PlayerController` — comandi e tracce

**Files:**
- Modify: `lib/features/player/player_controller.dart`
- Test: `test/features/player/player_controller_test.dart` (aggiunte)

- [ ] **Step 1: aggiungi i test** in fondo al `main()` di `test/features/player/player_controller_test.dart`:

```dart
  test('sottotitoli: esterno caricato una volta, interni, nessuno', () async {
    final controller = await start();
    await controller.selectSubtitle(5);
    expect(engine.addedSubtitles,
        ['https://media.example.com/Videos/m1/ms1/Subtitles/5/0/Stream.srt']);
    expect(view().subtitleIndex, 5);

    await controller.selectSubtitle(4);
    expect(engine.selectedSubtitle.last, '2');

    await controller.selectSubtitle(5);
    expect(engine.addedSubtitles, hasLength(1), reason: 'già caricato');
    expect(engine.selectedSubtitle.last, '100');

    await controller.selectSubtitle(null);
    expect(engine.selectedSubtitle.last, isNull);
    expect(view().subtitleIndex, isNull);
    expect(playback.progress, isNotEmpty);
  });

  test('audio in direct play: cambia traccia senza riaprire', () async {
    final controller = await start();
    await controller.selectAudio(2);
    expect(engine.selectedAudio.last, '2');
    expect(view().audioIndex, 2);
    expect(engine.opened, hasLength(1));
  });

  test('audio in transcodifica: riapre la conversione dal punto attuale',
      () async {
    playback.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final controller = await start();
    engine.emitPosition(const Duration(minutes: 10));

    await controller.selectAudio(2);
    await pumpEventQueue();
    final call = playback.playbackInfoCalls.last;
    expect(call.allowDirect, isFalse);
    expect(call.audioStreamIndex, 2);
    expect(call.subtitleStreamIndex, 3);
    expect(call.start, const Duration(minutes: 10));
    expect(engine.opened, hasLength(2));
    expect(playback.stopped, hasLength(1),
        reason: 'la sessione precedente viene chiusa');
    expect(view().audioIndex, 2);
    expect(view().status, PlayerStatus.ready);
  });

  test('transcodifica: un sottotitolo bruciato richiede una nuova conversione',
      () async {
    playback.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final controller = await start();

    await controller.selectSubtitle(4);
    expect(playback.playbackInfoCalls.last.subtitleStreamIndex, 4);
    expect(engine.opened, hasLength(2));
    expect(view().subtitleIndex, 4);

    await controller.selectSubtitle(null);
    expect(playback.playbackInfoCalls.last.subtitleStreamIndex, -1);
    expect(engine.opened, hasLength(3));
    expect(view().subtitleIndex, isNull);
  });

  test('comandi: pausa, salti nei limiti, volume, muto, ritardo', () async {
    final controller = await start();
    await controller.togglePlay();
    expect(engine.playing, isFalse);
    await controller.togglePlay();
    expect(engine.playing, isTrue);

    await controller.seekBy(const Duration(minutes: -10));
    expect(engine.seeks.last, Duration.zero);
    await controller.seekTo(const Duration(hours: 3));
    expect(engine.seeks.last, const Duration(hours: 2));

    await controller.setVolume(150);
    expect(engine.volumes.last, 100);
    await controller.changeVolumeBy(-5);
    expect(engine.volumes.last, 95);
    await controller.toggleMute();
    expect(engine.volumes.last, 0);
    expect(view().muted, isTrue);
    await controller.toggleMute();
    expect(engine.volumes.last, 95);

    await controller.shiftSubtitleDelay(const Duration(milliseconds: 100));
    await controller.shiftSubtitleDelay(const Duration(milliseconds: 100));
    expect(engine.subtitleDelays.last, const Duration(milliseconds: 200));
    expect(view().subtitleDelay, const Duration(milliseconds: 200));
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/player/player_controller_test.dart`
Expected: FAIL (`selectSubtitle`, `selectAudio`, `togglePlay`… non esistono).

- [ ] **Step 3: implementa.** In `PlayerController` aggiungi, dopo il getter `engine`:

```dart
  bool get _ready => _view.status == PlayerStatus.ready && _closing == null;
```

e, dopo `retry()`:

```dart
  Future<void> togglePlay() async {
    if (!_ready) return;
    await (_engine.playing ? _engine.pause() : _engine.play());
  }

  /// Salta a [position], entro i limiti del video.
  Future<void> seekTo(Duration position) async {
    if (!_ready) return;
    final duration = _engine.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (duration > Duration.zero && target > duration) target = duration;
    await _engine.seek(target);
    _reporter?.onEvent();
  }

  Future<void> seekBy(Duration offset) => seekTo(_engine.position + offset);

  /// 0–100. Toglie anche il muto.
  Future<void> setVolume(double volume) async {
    final value = volume.clamp(0.0, 100.0);
    _emit(_view.copyWith(volume: value, muted: false));
    await _engine.setVolume(value);
  }

  Future<void> changeVolumeBy(double delta) => setVolume(_view.volume + delta);

  Future<void> toggleMute() async {
    final muted = !_view.muted;
    _emit(_view.copyWith(muted: muted));
    await _engine.setVolume(muted ? 0 : _view.volume);
    _reporter?.onEvent();
  }

  Future<void> selectAudio(int index) async {
    final plan = _view.plan;
    if (plan == null || !_ready || index == _view.audioIndex) return;
    if (plan.isTranscode) {
      // L'audio è scelto dal server nella conversione: va rifatta.
      return _start(_engine.position,
          forceTranscode: true,
          audioIndex: index,
          subtitleIndex: _view.subtitleIndex ?? -1);
    }
    final stream = plan.mediaSource.stream(index);
    final track =
        stream == null ? null : engineTrackFor(stream, await _engine.tracks());
    if (track == null) return;
    await _engine.selectAudio(track.id);
    _emit(_view.copyWith(audioIndex: index));
    _reporter?.onEvent();
  }

  /// `null` = nessun sottotitolo.
  Future<void> selectSubtitle(int? index) async {
    final plan = _view.plan;
    if (plan == null || !_ready || index == _view.subtitleIndex) return;
    if (plan.burnsIn(_view.subtitleIndex) || plan.burnsIn(index)) {
      // Sottotitolo bruciato nel video: il server deve rifare la conversione.
      return _start(_engine.position,
          forceTranscode: true,
          audioIndex: _view.audioIndex,
          subtitleIndex: index ?? -1);
    }
    await _showSubtitle(plan, index);
    _emit(_view.copyWith(subtitleIndex: index));
    _reporter?.onEvent();
  }

  /// Positivo = sottotitoli più tardi.
  Future<void> shiftSubtitleDelay(Duration step) async {
    final delay = _view.subtitleDelay + step;
    _emit(_view.copyWith(subtitleDelay: delay));
    await _engine.setSubtitleDelay(delay);
  }
```

- [ ] **Step 4: esegui e verifica che passino**

Run: `flutter test test/features/player/player_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: analizza e commit**

```bash
flutter analyze
git add lib/features/player/player_controller.dart test/features/player/player_controller_test.dart
git commit -m "feat: add playback commands and audio/subtitle track selection"
```

---

### Task 14: stringhe ed errori della riproduzione

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`, `lib/app/error_text.dart`
- Test: `test/app/l10n_plan3_test.dart`, `test/app/error_text_test.dart` (aggiunte)

- [ ] **Step 1: scrivi i test.**

Crea `test/app/l10n_plan3_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del player', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerTrack(3), 'Traccia 3');
    expect(en.playerTrack(3), 'Track 3');
    expect(it.decimalSeparator, ',');
    expect(en.decimalSeparator, '.');
    expect(it.playerAudioAndSubtitles, 'Audio e sottotitoli');
    expect(en.playerAudioAndSubtitles, 'Audio & subtitles');
  });
}
```

In fondo al `main()` di `test/app/error_text_test.dart` (aggiungi in testa `import 'package:wonderflix/core/video/video_engine.dart';`):

```dart
  test('errori della riproduzione', () {
    expect(describeError(l, const PlaybackUnavailableException('NotAllowed')),
        'Questo contenuto non si può riprodurre.');
    expect(describeError(l, const EngineOpenException('x')),
        'Il video non si è avviato.');
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter gen-l10n && flutter test test/app/l10n_plan3_test.dart test/app/error_text_test.dart`
Expected: FAIL (le stringhe non esistono).

- [ ] **Step 3: aggiungi le stringhe.** In `l10n/app_it.arb`, prima della `}` finale (aggiungi una virgola dopo l'ultima voce esistente):

```json
  "playerTranscoding": "Il server sta convertendo questo video.",
  "playerErrorTitle": "Impossibile riprodurre il video",
  "playerBack": "Torna indietro",
  "playerPause": "Pausa",
  "playerRewind": "Indietro di 10 secondi",
  "playerForward": "Avanti di 10 secondi",
  "playerMute": "Disattiva audio",
  "playerUnmute": "Riattiva audio",
  "playerFullscreen": "Schermo intero",
  "playerExitFullscreen": "Esci da schermo intero",
  "playerAudioAndSubtitles": "Audio e sottotitoli",
  "playerAudio": "Audio",
  "playerSubtitles": "Sottotitoli",
  "playerSubtitlesOff": "Nessuno",
  "playerSubtitleDelay": "Ritardo sottotitoli",
  "playerSubtitlesEarlier": "Sottotitoli prima (G)",
  "playerSubtitlesLater": "Sottotitoli dopo (H)",
  "playerTrack": "Traccia {number}",
  "@playerTrack": {"placeholders": {"number": {"type": "int"}}},
  "decimalSeparator": ",",
  "errorPlaybackFailed": "Il video non si è avviato.",
  "errorPlaybackUnavailable": "Questo contenuto non si può riprodurre."
```

In `l10n/app_en.arb`, allo stesso modo:

```json
  "playerTranscoding": "The server is converting this video.",
  "playerErrorTitle": "Can't play this video",
  "playerBack": "Go back",
  "playerPause": "Pause",
  "playerRewind": "Back 10 seconds",
  "playerForward": "Forward 10 seconds",
  "playerMute": "Mute",
  "playerUnmute": "Unmute",
  "playerFullscreen": "Full screen",
  "playerExitFullscreen": "Exit full screen",
  "playerAudioAndSubtitles": "Audio & subtitles",
  "playerAudio": "Audio",
  "playerSubtitles": "Subtitles",
  "playerSubtitlesOff": "Off",
  "playerSubtitleDelay": "Subtitle delay",
  "playerSubtitlesEarlier": "Subtitles earlier (G)",
  "playerSubtitlesLater": "Subtitles later (H)",
  "playerTrack": "Track {number}",
  "@playerTrack": {"placeholders": {"number": {"type": "int"}}},
  "decimalSeparator": ".",
  "errorPlaybackFailed": "The video didn't start.",
  "errorPlaybackUnavailable": "This content can't be played."
```

- [ ] **Step 4: messaggi di errore.** Sostituisci `lib/app/error_text.dart` con:

```dart
import '../core/jellyfin/api_exception.dart';
import '../core/video/video_engine.dart';
import '../l10n/gen/app_localizations.dart';

/// Messaggio per l'utente a partire da un errore qualsiasi.
String describeError(AppLocalizations l, Object error) => switch (error) {
      UnauthorizedException() => l.errorInvalidCredentials,
      ForbiddenException() => l.errorAccountDisabled,
      ServerUnreachableException() => l.errorServerUnreachable,
      PlaybackUnavailableException() => l.errorPlaybackUnavailable,
      EngineOpenException() => l.errorPlaybackFailed,
      _ => l.errorGeneric,
    };
```

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter gen-l10n && flutter analyze && flutter test`
Expected: nessun problema, tutti i test PASS.

- [ ] **Step 6: commit**

```bash
git add l10n lib/app/error_text.dart test/app/l10n_plan3_test.dart test/app/error_text_test.dart
git commit -m "feat: add player strings and playback error messages"
```

---

### Task 15: comandi da tastiera

**Files:**
- Create: `lib/features/player/player_commands.dart`
- Test: `test/features/player/player_commands_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/player_commands_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/player_commands.dart';

KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero);

KeyEvent repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero);

KeyEvent up(LogicalKeyboardKey key) => KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero);

void main() {
  test('tasti della spec', () {
    expect(playerCommandFor(down(LogicalKeyboardKey.space)),
        PlayerCommand.togglePlay);
    expect(playerCommandFor(down(LogicalKeyboardKey.mediaPlayPause)),
        PlayerCommand.togglePlay);
    expect(playerCommandFor(down(LogicalKeyboardKey.arrowLeft)),
        PlayerCommand.seekBack);
    expect(playerCommandFor(down(LogicalKeyboardKey.arrowRight)),
        PlayerCommand.seekForward);
    expect(playerCommandFor(down(LogicalKeyboardKey.arrowUp)),
        PlayerCommand.volumeUp);
    expect(playerCommandFor(down(LogicalKeyboardKey.arrowDown)),
        PlayerCommand.volumeDown);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyF)),
        PlayerCommand.toggleFullscreen);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyM)),
        PlayerCommand.toggleMute);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyG)),
        PlayerCommand.subtitleDelayDown);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyH)),
        PlayerCommand.subtitleDelayUp);
    expect(playerCommandFor(down(LogicalKeyboardKey.escape)),
        PlayerCommand.escape);
    expect(playerCommandFor(down(LogicalKeyboardKey.browserBack)),
        PlayerCommand.exit);
    expect(playerCommandFor(down(LogicalKeyboardKey.mediaStop)),
        PlayerCommand.exit);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyQ)), isNull);
  });

  test('Alt+← esce; con Alt gli altri tasti sono ignorati', () {
    expect(
        playerCommandFor(down(LogicalKeyboardKey.arrowLeft), altPressed: true),
        PlayerCommand.exit);
    expect(playerCommandFor(down(LogicalKeyboardKey.space), altPressed: true),
        isNull);
  });

  test('tasto tenuto premuto: si ripetono solo salti, volume e ritardo', () {
    expect(playerCommandFor(repeat(LogicalKeyboardKey.arrowRight)),
        PlayerCommand.seekForward);
    expect(playerCommandFor(repeat(LogicalKeyboardKey.arrowUp)),
        PlayerCommand.volumeUp);
    expect(playerCommandFor(repeat(LogicalKeyboardKey.keyH)),
        PlayerCommand.subtitleDelayUp);
    expect(playerCommandFor(repeat(LogicalKeyboardKey.space)), isNull);
    expect(playerCommandFor(repeat(LogicalKeyboardKey.keyF)), isNull);
    expect(
        playerCommandFor(repeat(LogicalKeyboardKey.arrowLeft), altPressed: true),
        isNull);
  });

  test('il rilascio del tasto non fa nulla', () {
    expect(playerCommandFor(up(LogicalKeyboardKey.space)), isNull);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/player_commands_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/player_commands.dart`:

```dart
import 'package:flutter/services.dart';

/// Salto di ←/→ e dei pulsanti.
const seekStep = Duration(seconds: 10);

/// Passo del volume con ↑/↓ (scala 0–100).
const volumeStep = 5.0;

/// Passo del ritardo dei sottotitoli con G/H.
const subtitleDelayStep = Duration(milliseconds: 100);

enum PlayerCommand {
  togglePlay,
  seekBack,
  seekForward,
  volumeUp,
  volumeDown,
  toggleFullscreen,
  toggleMute,
  subtitleDelayDown,
  subtitleDelayUp,

  /// Esc: chiude il pannello, poi esce dallo schermo intero, poi dal player.
  escape,

  /// Esce subito dal player.
  exit,
}

// Non `const`: le chiavi ridefiniscono `==`.
final _commands = <LogicalKeyboardKey, PlayerCommand>{
  LogicalKeyboardKey.space: PlayerCommand.togglePlay,
  LogicalKeyboardKey.mediaPlayPause: PlayerCommand.togglePlay,
  LogicalKeyboardKey.arrowLeft: PlayerCommand.seekBack,
  LogicalKeyboardKey.arrowRight: PlayerCommand.seekForward,
  LogicalKeyboardKey.arrowUp: PlayerCommand.volumeUp,
  LogicalKeyboardKey.arrowDown: PlayerCommand.volumeDown,
  LogicalKeyboardKey.keyF: PlayerCommand.toggleFullscreen,
  LogicalKeyboardKey.keyM: PlayerCommand.toggleMute,
  LogicalKeyboardKey.keyG: PlayerCommand.subtitleDelayDown,
  LogicalKeyboardKey.keyH: PlayerCommand.subtitleDelayUp,
  LogicalKeyboardKey.escape: PlayerCommand.escape,
  LogicalKeyboardKey.browserBack: PlayerCommand.exit,
  LogicalKeyboardKey.mediaStop: PlayerCommand.exit,
};

/// Comandi che si ripetono tenendo premuto il tasto.
const _repeatable = {
  PlayerCommand.seekBack,
  PlayerCommand.seekForward,
  PlayerCommand.volumeUp,
  PlayerCommand.volumeDown,
  PlayerCommand.subtitleDelayDown,
  PlayerCommand.subtitleDelayUp,
};

/// Comando del player per un evento di tastiera; `null` se il tasto non è
/// gestito. Con Alt premuto vale solo Alt+← (esci).
PlayerCommand? playerCommandFor(KeyEvent event, {bool altPressed = false}) {
  if (event is KeyUpEvent) return null;
  final repeat = event is KeyRepeatEvent;
  if (altPressed) {
    return !repeat && event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? PlayerCommand.exit
        : null;
  }
  final command = _commands[event.logicalKey];
  if (command == null || (repeat && !_repeatable.contains(command))) {
    return null;
  }
  return command;
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/player_commands_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/player/player_commands.dart test/features/player/player_commands_test.dart
git commit -m "feat: add player keyboard shortcuts"
```

---

### Task 16: barra di avanzamento e pannello delle tracce

**Files:**
- Create: `lib/features/player/seek_bar.dart`, `lib/features/player/tracks_panel.dart`
- Test: `test/features/player/seek_bar_test.dart`, `test/features/player/tracks_panel_test.dart`

- [ ] **Step 1: scrivi i test.**

`test/features/player/seek_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/seek_bar.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('posizione, parte scaricata e salto con un clic', (tester) async {
    final engine = FakeVideoEngine();
    Duration? seeked;
    await pumpApp(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(40),
          child: SeekBar(engine: engine, onSeek: (p) => seeked = p),
        ),
      ),
    );
    engine
      ..emitDuration(const Duration(hours: 2))
      ..emitPosition(const Duration(minutes: 30))
      ..emitBuffer(const Duration(minutes: 45));
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, 7200);
    expect(slider.value, 1800);
    expect(slider.secondaryTrackValue, 2700);

    await tester.tap(find.byType(Slider));
    await tester.pump();
    expect(seeked!.inSeconds, closeTo(3600, 5));
  });

  testWidgets('tempo trascorso e totale', (tester) async {
    final engine = FakeVideoEngine();
    await pumpApp(tester, Scaffold(body: TimeLabel(engine: engine)));
    engine
      ..emitDuration(const Duration(hours: 1, minutes: 45))
      ..emitPosition(const Duration(minutes: 12, seconds: 3));
    await tester.pump();
    expect(find.text('12:03 / 1:45:00'), findsOneWidget);
  });
}
```

`test/features/player/tracks_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/tracks_panel.dart';

import '../../support/pump_app.dart';

void main() {
  test('formatSubtitleDelay', () {
    expect(formatSubtitleDelay(Duration.zero, ','), '0,0 s');
    expect(formatSubtitleDelay(const Duration(milliseconds: 300), ','),
        '+0,3 s');
    expect(formatSubtitleDelay(const Duration(milliseconds: -1200), '.'),
        '-1.2 s');
  });

  testWidgets('tracce, selezione e ritardo', (tester) async {
    int? audioPicked;
    int? subtitlePicked = -99;
    Duration? step;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: TracksPanel(
            audio: const [
              MediaStreamInfo(
                  index: 1,
                  kind: StreamKind.audio,
                  displayTitle: 'Italiano - E-AC3 5.1'),
              MediaStreamInfo(
                  index: 2, kind: StreamKind.audio, displayTitle: 'English - AAC'),
            ],
            subtitles: const [
              MediaStreamInfo(
                  index: 3,
                  kind: StreamKind.subtitle,
                  displayTitle: 'Italiano - ASS'),
              MediaStreamInfo(index: 7, kind: StreamKind.subtitle),
            ],
            audioIndex: 1,
            subtitleIndex: null,
            subtitleDelay: const Duration(milliseconds: 300),
            onAudio: (i) => audioPicked = i,
            onSubtitle: (i) => subtitlePicked = i,
            onDelayStep: (s) => step = s,
          ),
        ),
      ),
    );

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Sottotitoli'), findsOneWidget);
    expect(find.text('Traccia 7'), findsOneWidget, reason: 'senza nome');
    expect(find.text('+0,3 s'), findsOneWidget);
    // Selezionati: audio 1 e "Nessuno".
    expect(find.byIcon(LucideIcons.check), findsNWidgets(2));

    await tester.tap(find.text('English - AAC'));
    expect(audioPicked, 2);
    await tester.tap(find.text('Italiano - ASS'));
    expect(subtitlePicked, 3);
    await tester.tap(find.text('Nessuno'));
    expect(subtitlePicked, isNull);
    await tester.tap(find.byTooltip('Sottotitoli prima (G)'));
    expect(step, const Duration(milliseconds: -100));
    await tester.tap(find.byTooltip('Sottotitoli dopo (H)'));
    expect(step, const Duration(milliseconds: 100));
  });
}
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/player/seek_bar_test.dart test/features/player/tracks_panel_test.dart`
Expected: FAIL (file mancanti).

- [ ] **Step 3: crea** `lib/features/player/seek_bar.dart`:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/video/video_engine.dart';
import '../library/item_labels.dart';

/// Barra di avanzamento: posizione, parte già scaricata, salto con clic o
/// trascinamento.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, required this.engine, required this.onSeek});

  final VideoEngine engine;
  final ValueChanged<Duration> onSeek;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  late Duration _position;
  late Duration _duration;
  late Duration _buffer;

  /// Valore durante il trascinamento (secondi): non segue il video.
  double? _dragSeconds;
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
    final max = math.max(_seconds(_duration), 1.0);
    double clamp(double value) => value.clamp(0.0, max);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: WfColors.gold,
        secondaryActiveTrackColor: WfColors.cream.withValues(alpha: 0.35),
        inactiveTrackColor: WfColors.cream.withValues(alpha: 0.15),
        thumbColor: WfColors.gold,
        overlayColor: WfColors.gold.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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

- [ ] **Step 4: crea** `lib/features/player/tracks_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'player_commands.dart';

/// Nome di una traccia nei menu: quello preparato dal server, se c'è.
String trackLabel(AppLocalizations l, MediaStreamInfo stream) =>
    stream.displayTitle ??
    stream.title ??
    stream.language ??
    l.playerTrack(stream.index);

/// "+0,3 s", "0,0 s", "-1,2 s".
String formatSubtitleDelay(Duration delay, String decimalSeparator) {
  final tenths = (delay.inMilliseconds / 100).round();
  final sign = tenths > 0 ? '+' : (tenths < 0 ? '-' : '');
  final value = tenths.abs();
  return '$sign${value ~/ 10}$decimalSeparator${value % 10} s';
}

/// Pannello "Audio e sottotitoli": tracce audio, sottotitoli e ritardo.
class TracksPanel extends StatelessWidget {
  const TracksPanel({
    super.key,
    required this.audio,
    required this.subtitles,
    required this.audioIndex,
    required this.subtitleIndex,
    required this.subtitleDelay,
    required this.onAudio,
    required this.onSubtitle,
    required this.onDelayStep,
  });

  final List<MediaStreamInfo> audio;
  final List<MediaStreamInfo> subtitles;
  final int? audioIndex;
  final int? subtitleIndex;
  final Duration subtitleDelay;
  final ValueChanged<int> onAudio;

  /// `null` = nessun sottotitolo.
  final ValueChanged<int?> onSubtitle;
  final ValueChanged<Duration> onDelayStep;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: WfColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 380),
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Section(
                title: l.playerAudio,
                children: [
                  for (final stream in audio)
                    _TrackTile(
                      label: trackLabel(l, stream),
                      selected: stream.index == audioIndex,
                      onTap: () => onAudio(stream.index),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: _Section(
                      title: l.playerSubtitles,
                      children: [
                        _TrackTile(
                          label: l.playerSubtitlesOff,
                          selected: subtitleIndex == null,
                          onTap: () => onSubtitle(null),
                        ),
                        for (final stream in subtitles)
                          _TrackTile(
                            label: trackLabel(l, stream),
                            selected: stream.index == subtitleIndex,
                            onTap: () => onSubtitle(stream.index),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(l.playerSubtitleDelay,
                            style: const TextStyle(color: WfColors.creamMuted)),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.minus, size: 18),
                        tooltip: l.playerSubtitlesEarlier,
                        onPressed: () => onDelayStep(-subtitleDelayStep),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          formatSubtitleDelay(subtitleDelay, l.decimalSeparator),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.plus, size: 18),
                        tooltip: l.playerSubtitlesLater,
                        onPressed: () => onDelayStep(subtitleDelayStep),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: WfText.display(22, color: WfColors.gold)),
          const SizedBox(height: 8),
          Flexible(child: ListView(shrinkWrap: true, children: children)),
        ],
      );
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: selected
                    ? const Icon(LucideIcons.check,
                        size: 16, color: WfColors.gold)
                    : null,
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? WfColors.cream : WfColors.creamMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
```

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter test test/features/player/seek_bar_test.dart test/features/player/tracks_panel_test.dart`
Expected: PASS.

- [ ] **Step 6: analizza e commit**

```bash
flutter analyze
git add lib/features/player/seek_bar.dart lib/features/player/tracks_panel.dart test/features/player/seek_bar_test.dart test/features/player/tracks_panel_test.dart
git commit -m "feat: add seek bar and audio/subtitle panel"
```

---

### Task 17: controlli in sovrimpressione

**Files:**
- Create: `lib/features/player/player_overlay.dart`
- Test: `test/features/player/player_overlay_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/player_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_overlay.dart';

import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<List<String>> pumpOverlay(
    WidgetTester tester,
    PlayerViewState view, {
    bool fullscreen = false,
  }) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: PlayerOverlay(
          view: view,
          engine: FakeVideoEngine(),
          fullscreen: fullscreen,
          onBack: () => calls.add('back'),
          onTogglePlay: () => calls.add('play'),
          onSeekBy: (offset) => calls.add('seek ${offset.inSeconds}'),
          onSeekTo: (_) => calls.add('seekTo'),
          onVolume: (_) => calls.add('volume'),
          onToggleMute: () => calls.add('mute'),
          onToggleTracks: () => calls.add('tracks'),
          onToggleFullscreen: () => calls.add('fullscreen'),
        ),
      ),
    );
    return calls;
  }

  testWidgets('titolo, episodio e comandi', (tester) async {
    final calls = await pumpOverlay(
      tester,
      PlayerViewState(
        status: PlayerStatus.ready,
        playing: true,
        item: testItem(
          id: 'e4',
          name: 'Pilot',
          kind: ItemKind.episode,
          seriesName: 'Breaking Bad',
          index: 4,
          seasonIndex: 1,
        ),
      ),
    );
    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('S1:E4 · Pilot'), findsOneWidget);

    await tester.tap(find.byTooltip('Indietro'));
    await tester.tap(find.byTooltip('Pausa'));
    await tester.tap(find.byTooltip('Indietro di 10 secondi'));
    await tester.tap(find.byTooltip('Avanti di 10 secondi'));
    await tester.tap(find.byTooltip('Disattiva audio'));
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.tap(find.byTooltip('Schermo intero'));
    expect(calls,
        ['back', 'play', 'seek -10', 'seek 10', 'mute', 'tracks', 'fullscreen']);
  });

  testWidgets('in pausa, muto e a schermo intero', (tester) async {
    await pumpOverlay(
      tester,
      const PlayerViewState(
          status: PlayerStatus.ready, playing: false, muted: true),
      fullscreen: true,
    );
    expect(find.byTooltip('Riproduci'), findsOneWidget);
    expect(find.byTooltip('Riattiva audio'), findsOneWidget);
    expect(find.byTooltip('Esci da schermo intero'), findsOneWidget);
    expect(find.byIcon(LucideIcons.volumeX), findsOneWidget);
    expect(
        tester.widget<Slider>(find.byKey(const Key('volume-slider'))).value, 0);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/player_overlay_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/player_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'player_commands.dart';
import 'player_controller.dart';
import 'seek_bar.dart';

/// Controlli in sovrimpressione: in alto indietro e titolo, in basso barra
/// di avanzamento e comandi.
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
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 24, 48),
                child: Row(
                  children: [
                    IconButton(
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
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xE6000000), Color(0x00000000)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SeekBar(engine: engine, onSeek: onSeekTo),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.rewind),
                          tooltip: l.playerRewind,
                          onPressed: () => onSeekBy(-seekStep),
                        ),
                        IconButton(
                          iconSize: 34,
                          icon: Icon(view.playing
                              ? LucideIcons.pause
                              : LucideIcons.play),
                          tooltip: view.playing ? l.playerPause : l.actionPlay,
                          onPressed: onTogglePlay,
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.fastForward),
                          tooltip: l.playerForward,
                          onPressed: () => onSeekBy(seekStep),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
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
                        IconButton(
                          icon: const Icon(LucideIcons.captions),
                          tooltip: l.playerAudioAndSubtitles,
                          onPressed: onToggleTracks,
                        ),
                        IconButton(
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
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/player_overlay_test.dart`
Expected: PASS.

- [ ] **Step 5: analizza e commit**

```bash
flutter analyze
git add lib/features/player/player_overlay.dart test/features/player/player_overlay_test.dart
git commit -m "feat: add player controls overlay"
```

---

### Task 18: schermata del player

**Files:**
- Create: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_screen_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/player/player_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeVideoEngine engine;
  late FakePlaybackApi playback;
  late FakePlayerWindow window;

  setUp(() {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    playback = FakePlaybackApi();
    window = FakePlayerWindow();
  });

  /// Home ('/') con il player aperto sopra, come nell'app.
  Future<void> pumpPlayer(WidgetTester tester) async {
    final library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(
        id: 'e4',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 4,
        seasonIndex: 1,
      );
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home'))),
      GoRoute(
        path: '/play/:id',
        builder: (context, state) => PlayerScreen(
            args: (itemId: state.pathParameters['id']!, start: Duration.zero)),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        playbackApiProvider.overrideWithValue(playback),
        playbackServiceProvider.overrideWithValue(PlaybackService(
          api: playback,
          serverUrl: testServerUrl,
          authorization: () => 'MediaBrowser Token="t1"',
        )),
        videoEngineFactoryProvider.overrideWithValue(() => engine),
        playerWindowProvider.overrideWithValue(window),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
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
    unawaited(router.push('/play/e4'));
    await tester.pumpAndSettle();
  }

  /// Smonta l'app e lascia scadere i timer (report di fine, attese).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  double controlsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('player-controls')))
      .opacity;

  testWidgets('video, titolo, episodio e controlli', (tester) async {
    await pumpPlayer(tester);
    expect(find.byKey(const Key('fake-video')), findsOneWidget);
    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('S1:E4 · Pilot'), findsOneWidget);
    expect(find.byTooltip('Pausa'), findsOneWidget);
    expect(window.preventCloseCalls, [true]);
    await unmount(tester);
  });

  testWidgets('tastiera: pausa, salto, volume, muto, ritardo', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.seeks.last, const Duration(seconds: 10));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.volumes.last, 95);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumes.last, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(engine.subtitleDelays.last, const Duration(milliseconds: 100));
    await unmount(tester);
  });

  testWidgets('F e Esc: schermo intero, poi finestra, poi uscita',
      (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(window.fullScreenCalls, [true]);
    expect(find.byTooltip('Esci da schermo intero'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(window.fullScreenCalls, [true, false]);
    expect(find.text('home'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(playback.stopped, hasLength(1));
    expect(window.preventCloseCalls, [true, false]);
    await unmount(tester);
  });

  testWidgets('controlli nascosti dopo 3 s, di nuovo visibili col mouse',
      (tester) async {
    await pumpPlayer(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(controlsOpacity(tester), 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(700, 400));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(720, 420));
    await tester.pump();
    expect(controlsOpacity(tester), 1);

    // In pausa i controlli restano visibili.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(seconds: 5));
    expect(controlsOpacity(tester), 1);
    await unmount(tester);
  });

  testWidgets('pannello audio e sottotitoli; Esc lo chiude', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    expect(find.text('English - AAC Stereo'), findsOneWidget);

    await tester.tap(find.text('English - AAC Stereo'));
    await tester.pump();
    expect(engine.selectedAudio.last, '2');

    await tester.tap(find.text('Nessuno'));
    await tester.pump();
    expect(engine.selectedSubtitle.last, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('English - AAC Stereo'), findsNothing);
    expect(find.text('home'), findsNothing);
    await unmount(tester);
  });

  testWidgets('errore: Riprova riavvia', (tester) async {
    engine.failOpens = 2;
    await pumpPlayer(tester);
    expect(find.text('Impossibile riprodurre il video'), findsOneWidget);
    expect(find.text('Il video non si è avviato.'), findsOneWidget);

    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pausa'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('errore: Torna indietro esce dal player', (tester) async {
    engine.failOpens = 2;
    await pumpPlayer(tester);
    await tester.tap(find.text('Torna indietro'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('chiusura della finestra: fine della sessione, poi chiusura',
      (tester) async {
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(minutes: 5));
    final closing = window.simulateClose();
    await tester.pump();
    await closing;
    expect(playback.stopped.single.position, const Duration(minutes: 5));
    expect(window.destroyed, isTrue);
    await unmount(tester);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/player/player_screen_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: crea** `lib/features/player/player_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'player_commands.dart';
import 'player_controller.dart';
import 'player_overlay.dart';
import 'player_providers.dart';
import 'player_window.dart';
import 'tracks_panel.dart';

/// Schermata del player: video a tutta finestra, controlli in
/// sovrimpressione, tastiera, schermo intero e chiusura sicura della
/// finestra (prima si segnala la fine a Jellyfin).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args});

  final PlayerArgs args;

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
  bool _fullscreen = false;
  bool _leaving = false;

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
    if (_fullscreen) unawaited(_window.setFullScreen(false));
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
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
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
      case PlayerCommand.escape:
        _escape();
        return;
      case PlayerCommand.exit:
        _exit();
        return;
    }
    _showControls();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = playerControllerProvider(widget.args);
    final view = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    ref.listen(provider.select((s) => s.finished), (_, finished) {
      if (finished) _exit();
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
                        ),
                      ),
                    ),
                  ),
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

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/player/player_screen_test.dart`
Expected: PASS. Se un test resta appeso su `pumpAndSettle`, è rimasta visibile un'animazione infinita (lo spinner): controlla che lo stato sia `ready` e che `buffering` sia `false`.

- [ ] **Step 5: analizza e commit**

```bash
flutter analyze
git add lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
git commit -m "feat: add player screen with keyboard, fullscreen and safe window close"
```

---

### Task 19: nuovo punto d'ingresso, route e chiamanti

**Files:**
- Modify: `lib/features/detail/detail_providers.dart`, `lib/app/navigation.dart`, `lib/app/router.dart`
- Modify: `lib/features/playback/play_launcher.dart` (riscritto)
- Modify: `lib/features/detail/detail_header.dart`, `lib/features/home/hero_carousel.dart`, `lib/features/detail/series_detail_view.dart`
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb` (tolta `playbackComingSoon`)
- Test: `test/features/playback/play_launcher_test.dart`, `test/app/navigation_test.dart` e `test/app/router_test.dart` (aggiunte)

- [ ] **Step 1: scrivi i test.**

In fondo al `main()` di `test/app/navigation_test.dart`:

```dart
  test('playerRoute e playerStartFrom', () {
    expect(playerRoute('m1'), '/play/m1');
    expect(playerRoute('m1', start: const Duration(minutes: 23)),
        '/play/m1?start=1380000');
    expect(playerStartFrom(Uri.parse('/play/m1?start=1380000')),
        const Duration(minutes: 23));
    expect(playerStartFrom(Uri.parse('/play/m1')), Duration.zero);
    expect(playerStartFrom(Uri.parse('/play/m1?start=abc')), Duration.zero);
  });
```

In fondo al `main()` di `test/app/router_test.dart`:

```dart
  test('il player resta aperto da autenticati, porta al login da disconnessi',
      () {
    expect(sessionRedirect(signedIn, '/play/m1'), isNull);
    expect(sessionRedirect(const SessionSignedOut(expired: true), '/play/m1'),
        '/login');
  });
```

Crea `test/features/playback/play_launcher_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';
import 'package:wonderflix/features/playback/play_launcher.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;

  setUp(() => library = FakeLibraryApi());

  /// Pulsante "play" che chiama [playItem]; la route del player mostra id e
  /// posizione di partenza ricevuti.
  Future<void> pumpLauncher(WidgetTester tester, JellyfinItem item,
      {bool fromStart = false}) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => playItem(context, ref, item, fromStart: fromStart),
              child: const Text('play'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/play/:id',
        builder: (context, state) => Text(
            'player ${state.pathParameters['id']} ${state.uri.queryParameters['start'] ?? '-'}'),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
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
  }

  Future<void> tapPlay(WidgetTester tester) async {
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();
  }

  const minutes23 = 23 * 60 * 10000000;

  testWidgets('film iniziato: riprende dal minutaggio', (tester) async {
    await pumpLauncher(tester, testItem(id: 'm1', positionTicks: minutes23));
    await tapPlay(tester);
    expect(find.text('player m1 1380000'), findsOneWidget);
  });

  testWidgets('Ricomincia: dall\'inizio', (tester) async {
    await pumpLauncher(tester, testItem(id: 'm1', positionTicks: minutes23),
        fromStart: true);
    await tapPlay(tester);
    expect(find.text('player m1 -'), findsOneWidget);
  });

  testWidgets('film già visto: dall\'inizio', (tester) async {
    await pumpLauncher(
        tester, testItem(id: 'm1', played: true, positionTicks: minutes23));
    await tapPlay(tester);
    expect(find.text('player m1 -'), findsOneWidget);
  });

  testWidgets('i dati utente aggiornati hanno la precedenza', (tester) async {
    await pumpLauncher(tester, testItem(id: 'm1'));
    ProviderScope.containerOf(tester.element(find.text('play')))
        .read(userDataOverridesProvider.notifier)
        .apply('m1', const UserItemData(playbackPositionTicks: minutes23));
    await tapPlay(tester);
    expect(find.text('player m1 1380000'), findsOneWidget);
  });

  testWidgets('serie: riproduce il prossimo episodio', (tester) async {
    library.nextUpItems = [
      testItem(id: 'e5', kind: ItemKind.episode, seriesId: 's1'),
    ];
    await pumpLauncher(tester, testItem(id: 's1', kind: ItemKind.series));
    await tapPlay(tester);
    expect(find.text('player e5 -'), findsOneWidget);
    expect(library.nextUpCalls, ['s1']);
  });

  testWidgets('serie senza episodi: avviso', (tester) async {
    await pumpLauncher(tester, testItem(id: 's1', kind: ItemKind.series));
    await tapPlay(tester);
    expect(find.text('Nessun episodio disponibile.'), findsOneWidget);
    expect(find.text('play'), findsOneWidget);
  });
}
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/app/navigation_test.dart test/app/router_test.dart test/features/playback/play_launcher_test.dart`
Expected: FAIL (`playerRoute`, `playerStartFrom` e la nuova firma di `playItem` non esistono). Il test del router può già passare: `/play/m1` non è una route d'ingresso.

- [ ] **Step 3: prossimo episodio riusabile.** In `lib/features/detail/detail_providers.dart`:
- aggiungi `import '../../core/jellyfin/library_api.dart';`;
- sostituisci `seriesNextEpisodeProvider` con:

```dart
/// Episodio da proporre per una serie: il prossimo (o quello iniziato),
/// oppure il primo della prima stagione.
Future<JellyfinItem?> findNextEpisode(
    LibraryApi api, String userId, String seriesId) async {
  final next = await api.nextUp(userId,
      seriesId: seriesId, limit: 1, enableResumable: true);
  if (next.isNotEmpty) return next.first;
  final seasons = await api.seasons(userId, seriesId);
  final regular = seasons.where((s) => (s.indexNumber ?? 0) > 0);
  final first = regular.isNotEmpty ? regular.first : seasons.firstOrNull;
  if (first == null) return null;
  final episodes = await api.episodes(userId, seriesId, first.id);
  return episodes.firstOrNull;
}

final seriesNextEpisodeProvider = FutureProvider.autoDispose
    .family<JellyfinItem?, String>((ref, seriesId) {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  return findNextEpisode(
      ref.watch(libraryApiProvider), ref.watch(currentUserIdProvider), seriesId);
});
```

- [ ] **Step 4: percorso del player.** In fondo a `lib/app/navigation.dart`:

```dart
/// Percorso del player; [start] è la posizione di partenza.
String playerRoute(String itemId, {Duration start = Duration.zero}) => Uri(
      path: '/play/$itemId',
      queryParameters:
          start > Duration.zero ? {'start': '${start.inMilliseconds}'} : null,
    ).toString();

/// Posizione di partenza dal parametro `start` (millisecondi) del percorso.
Duration playerStartFrom(Uri uri) => Duration(
    milliseconds: int.tryParse(uri.queryParameters['start'] ?? '') ?? 0);
```

- [ ] **Step 5: route.** In `lib/app/router.dart`:
- aggiungi gli import `import '../features/player/player_screen.dart';` e `import 'navigation.dart';`;
- aggiungi la route dopo quella di `/unreachable`, fuori dalla `ShellRoute`, così il player sta sul navigatore radice senza barra superiore:

```dart
      GoRoute(
        path: '/play/:id',
        builder: (context, state) => PlayerScreen(
          key: ValueKey(state.uri.toString()),
          args: (
            itemId: state.pathParameters['id']!,
            start: playerStartFrom(state.uri),
          ),
        ),
      ),
```

- [ ] **Step 6: riscrivi** `lib/features/playback/play_launcher.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/error_text.dart';
import '../../app/navigation.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../detail/detail_providers.dart';
import '../detail/primary_action.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';

/// Unico punto d'ingresso della riproduzione.
/// - Per una serie riproduce il prossimo episodio (o il primo).
/// - Riprende dal minutaggio salvato, letto dai dati utente più recenti,
///   salvo [fromStart].
///
/// Si completa quando l'utente esce dal player.
Future<void> playItem(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item, {
  bool fromStart = false,
}) async {
  var target = item;
  if (item.kind == ItemKind.series) {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final JellyfinItem? next;
    try {
      next = await findNextEpisode(ref.read(libraryApiProvider),
          ref.read(currentUserIdProvider), item.id);
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
      return;
    }
    if (next == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.detailNoEpisodes)));
      return;
    }
    if (!context.mounted) return;
    target = next;
  }
  final userData =
      ref.read(userDataOverridesProvider)[target.id] ?? target.userData;
  final action = primaryActionFor(target, userData);
  final start =
      !fromStart && action is ResumeAction ? action.position : Duration.zero;
  await context.push<void>(playerRoute(target.id, start: start));
}
```

- [ ] **Step 7: chiamanti.**
- `lib/features/detail/detail_header.dart`: i due `onPressed` diventano
  `onPressed: () => unawaited(playItem(context, ref, action.target)),` e
  `onPressed: () => unawaited(playItem(context, ref, action.target, fromStart: true)),`.
- `lib/features/home/hero_carousel.dart`, in `_HeroSlide`:
  `onPressed: () => unawaited(playItem(context, ref, item)),`.
- `lib/features/detail/series_detail_view.dart`:
  - aggiungi in testa `import 'dart:async';`;
  - in `EpisodeTile`: `onTap: () => unawaited(playItem(context, ref, episode)),`.

- [ ] **Step 8: togli la stringa non più usata.** Elimina la riga `"playbackComingSoon": …` da `l10n/app_it.arb` e da `l10n/app_en.arb`, controllando che le virgole restino valide.

```bash
grep -rn "playbackComingSoon" lib l10n test --include=*.dart --include=*.arb | grep -v "lib/l10n/gen"
```
Expected: nessun risultato.

- [ ] **Step 9: esegui tutto**

Run: `flutter gen-l10n && flutter analyze && flutter test`
Expected: nessun problema, tutti i test PASS (compresi quelli del Piano 2 su schede e Home).

- [ ] **Step 10: commit**

```bash
git add lib l10n test
git commit -m "feat: route play buttons to the new player with resume and next episode"
```

---

### Task 20: verifica completa e prova sul server

**Files:** nessuna modifica prevista (solo eventuali correzioni emerse).

- [ ] **Step 1: controlli automatici**

```bash
flutter analyze
flutter test
flutter build windows --debug
```
Expected: nessun problema, tutti i test PASS, build riuscita.

- [ ] **Step 2: prova manuale sul server reale** (con `config/wonderflix.json` già presente nel worktree)

```bash
flutter run -d windows --dart-define-from-file=config/wonderflix.json
```

Checklist da fare con l'utente (annota l'esito di ogni punto):
1. **Avvio e ripresa:**
   - su un film iniziato, "Riprendi da mm:ss" parte dal punto giusto, senza partire da 0:00 e poi saltare;
   - nella Dashboard (Attività) la sessione "WonderFlix – <nome PC>" risulta in **riproduzione diretta**;
   - "Ricomincia" parte da 0:00.
2. **Sottotitoli** (MKV con ASS interni, PGS interni, SRT esterni):
   - resa corretta (stili ASS compresi) e sincronizzata;
   - cambio dal pannello "Audio e sottotitoli"; "Nessuno" li toglie.
3. **Ritardo:** G/H e i pulsanti −/+ spostano i sottotitoli di 0,1 s; il pannello mostra il valore.
4. **Audio:** il cambio di traccia avviene senza interruzioni.
5. **Controlli:**
   - dopo 3 s senza muovere il mouse spariscono controlli e puntatore; muovendo il mouse ricompaiono; in pausa restano;
   - clic = pausa; doppio clic = schermo intero;
   - la barra mostra la parte scaricata; clic e trascinamento spostano la posizione.
6. **Tastiera:**
   - Spazio, ←/→, ↑/↓, F, M, G/H;
   - Esc: prima esce dallo schermo intero, poi dal player;
   - Alt+← e il tasto indietro del mouse escono dal player;
   - il tasto Play/Pausa della tastiera funziona con l'app in primo piano.
7. **Minutaggio:** dopo un minuto di visione esci dal player:
   - in Home "Continua a guardare" e nella scheda il minutaggio è aggiornato subito;
   - jellyfin-web mostra lo stesso punto.
8. **Fine del video:** salta verso la fine e lascia finire:
   - il player si chiude da solo;
   - il titolo risulta visto, anche in jellyfin-web;
   - per una serie, la scheda propone l'episodio successivo.
9. **Chiusura della finestra** durante la riproduzione: riaprendo l'app, il minutaggio è salvato.
10. **Serie:** "Riproduci" dal carosello su una serie avvia il prossimo episodio; il clic su un episodio della lista lo avvia.
11. **Ripiego:** avvia con il ripiego forzato:
    ```bash
    flutter run -d windows --dart-define-from-file=config/wonderflix.json --dart-define=wfBreakDirectPlay=true
    ```
    - compare "Il server sta convertendo questo video." e il video parte (Dashboard: transcodifica);
    - in transcodifica funzionano il cambio audio, i sottotitoli testuali e un sottotitolo PGS (bruciato nel video).
12. **Errore:** con la rete staccata, il player mostra il messaggio con *Riprova* e *Torna indietro*; riattaccata la rete, *Riprova* avvia il video.
13. **Salvaschermo:** durante una visione lunga non parte il salvaschermo e il PC non va in sospensione.

- [ ] **Step 3: correzioni**

Se la prova rivela problemi, correggili con TDD (prima il test che fallisce, poi la correzione), un commit per problema, con messaggio `fix: …`.
