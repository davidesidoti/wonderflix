import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/media_info_models.dart';
import 'package:wonderflix/core/subtitles/subtitle_models.dart';
import 'package:wonderflix/core/subtitles/subtitles_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/reports/reports_providers.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/subtitles/subtitle_file_picker.dart';
import 'package:wonderflix/features/subtitles/subtitles_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/report_fakes.dart';
import '../../support/settings_fakes.dart';
import '../../support/test_data.dart';

/// Registra anche i dati dell'ultimo caricamento.
class _RecordingSubtitlesApi extends FakeSubtitlesApi {
  SubtitleUpload? lastUpload;

  @override
  Future<void> upload(String itemId, SubtitleUpload upload) {
    lastUpload = upload;
    return super.upload(itemId, upload);
  }
}

SubtitleTrack _external(int index) => SubtitleTrack(
  index: index,
  language: 'ita',
  codec: 'srt',
  isExternal: true,
);

ItemMediaInfo _info(List<int> external) =>
    testMediaInfo(subtitles: [for (final i in external) _external(i)]);

void main() {
  late _RecordingSubtitlesApi api;
  late FakeLibraryApi library;
  late FakeSessionController session;
  late FakeUserConfigApi config;
  late ProviderContainer container;
  late ProviderSubscription<SubtitlesState> subscription;

  setUp(() {
    api = _RecordingSubtitlesApi();
    library = FakeLibraryApi()..mediaInfoById['e1'] = _info([1]);
    config = FakeUserConfigApi();
  });

  /// Un container con la sessione di [user] e il controller di `e1` attivo.
  void mount({JellyfinUser user = testUser}) {
    session = FakeSessionController(SessionSignedIn(user));
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...reportTestOverrides(subtitles: api),
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(() => session),
        userConfigApiProvider.overrideWithValue(config),
      ],
    );
    addTearDown(container.dispose);
    subscription = container.listen(
      subtitlesControllerProvider('e1'),
      (_, _) {},
    );
  }

  SubtitlesController controller() =>
      container.read(subtitlesControllerProvider('e1').notifier);
  SubtitlesState state() => container.read(subtitlesControllerProvider('e1'));

  test('la lingua iniziale è quella preferita, altrimenti ita', () async {
    for (final (preferred, expected) in [
      ('eng', 'eng'),
      ('', 'ita'),
      ('xxx', 'ita'),
    ]) {
      config.config['SubtitleLanguagePreference'] = preferred;
      mount();
      await container.read(languagePreferencesProvider.future);
      container.invalidate(subtitlesControllerProvider('e1'));
      expect(state().language, expected, reason: 'preferita "$preferred"');
    }
  });

  test('una preferenza arrivata dopo la ricerca non cambia la lingua', () async {
    config.config['SubtitleLanguagePreference'] = 'eng';
    mount();

    final searching = controller().search();
    await container.read(languagePreferencesProvider.future);
    await searching;

    expect(state().language, 'ita', reason: 'i risultati sono in italiano');
    expect(api.calls, ['search e1 ita -']);
  });

  test('search ordina i risultati', () async {
    mount();
    api.results.addAll([
      testSubtitle(id: 'a', name: 'a', downloadCount: 5),
      testSubtitle(id: 'b', name: 'b', downloadCount: 1, isHashMatch: true),
    ]);

    await controller().search();

    expect([for (final r in state().results!) r.id], ['b', 'a']);
    expect(state().searching, isFalse);
    expect(api.calls, ['search e1 ita -']);
  });

  test('download: rilegge ogni 2 s e si ferma alla traccia nuova', () {
    fakeAsync((async) {
      mount();
      bool? result;
      unawaited(
        controller()
            .download(testSubtitle(id: 's1'))
            .then((value) => result = value),
      );
      async.flushMicrotasks();

      // La foto prima della chiamata, poi l'attesa.
      expect(library.mediaInfoCalls, ['e1']);
      expect(api.calls, ['download e1 s1']);
      expect(state().notice, SubtitlesNotice.waiting);
      expect(state().busyId, 's1');

      async.elapse(subtitlePollInterval);
      async.elapse(subtitlePollInterval);
      expect(library.mediaInfoCalls, hasLength(3));
      expect(result, isNull);

      library.mediaInfoById['e1'] = _info([1, 5]);
      async.elapse(subtitlePollInterval);
      expect(
        library.mediaInfoCalls,
        hasLength(4),
        reason: 'foto + 3 riletture',
      );
      expect(result, isTrue);
      expect(state().notice, SubtitlesNotice.trackAdded);
      expect(state().busyId, isNull);

      async.elapse(subtitlePollTimeout);
      expect(library.mediaInfoCalls, hasLength(4));
    });
  });

  test('la traccia nuova invalida le tracce presenti', () {
    fakeAsync((async) {
      mount();
      container.listen(itemMediaInfoProvider('e1'), (_, _) {});
      async.flushMicrotasks();
      expect(library.mediaInfoCalls, hasLength(1));

      unawaited(controller().download(testSubtitle()));
      async.flushMicrotasks();
      library.mediaInfoById['e1'] = _info([1, 5]);
      async.elapse(subtitlePollInterval);

      // Lettura iniziale, foto, rilettura e la lettura dopo l'invalidazione.
      expect(library.mediaInfoCalls, hasLength(4));
    });
  });

  test('la traccia non compare entro 20 s', () {
    fakeAsync((async) {
      mount();
      bool? result;
      unawaited(
        controller().download(testSubtitle()).then((value) => result = value),
      );
      async.flushMicrotasks();

      async.elapse(subtitlePollTimeout);
      expect(result, isFalse);
      expect(state().notice, SubtitlesNotice.trackSoon);
      expect(state().busyId, isNull);
      // La foto e una rilettura ogni 2 s fino ai 20 s.
      expect(library.mediaInfoCalls, hasLength(1 + 10));

      async.elapse(const Duration(minutes: 1));
      expect(library.mediaInfoCalls, hasLength(1 + 10));
    });
  });

  test('download fallito (502): downloadFailed e nessuna rilettura', () {
    fakeAsync((async) {
      mount();
      api.nextFailure = SubtitlesFailure.failed;
      bool? result;
      unawaited(
        controller().download(testSubtitle()).then((value) => result = value),
      );
      async.flushMicrotasks();

      expect(result, isFalse);
      expect(state().notice, SubtitlesNotice.downloadFailed);
      expect(state().busyId, isNull);
      async.elapse(subtitlePollTimeout);
      expect(library.mediaInfoCalls, hasLength(1), reason: 'solo la foto');
    });
  });

  test('un 403 nella ricerca rilegge l\'utente', () async {
    mount();
    api.nextFailure = SubtitlesFailure.forbidden;

    await controller().search();

    expect(state().notice, SubtitlesNotice.noPermission);
    expect(session.refreshUserCalls, 1);
    expect(state().searching, isFalse);
  });

  test('una ricerca fallita mostra l\'errore generico', () async {
    mount();
    api.nextFailure = SubtitlesFailure.network;

    await controller().search();

    expect(state().notice, SubtitlesNotice.error);
    expect(state().error, isA<SubtitlesException>());
    expect(session.refreshUserCalls, 0);
  });

  group('upload', () {
    PickedSubtitleFile file(
      String name,
      int length, {
      Future<Uint8List> Function()? read,
    }) => PickedSubtitleFile(
      name: name,
      length: length,
      read: read ?? () async => Uint8List(length),
    );

    test('file troppo grande: senza chiamata', () async {
      mount();
      final result = await controller().upload(
        file(
          'a.srt',
          maxSubtitleFileBytes + 1,
          read: () => throw StateError('non si legge'),
        ),
        forced: false,
        hearingImpaired: false,
      );

      expect(result, isFalse);
      expect(state().notice, SubtitlesNotice.fileTooLarge);
      expect(api.calls, isEmpty);
      expect(library.mediaInfoCalls, isEmpty);
    });

    test(
      'formato dall\'estensione, lingua dal menu, Data della lunghezza giusta',
      () {
        fakeAsync((async) {
          mount();
          controller().setLanguage('eng');
          bool? result;
          unawaited(
            controller()
                .upload(
                  file('Film.IT.SRT', maxSubtitleFileBytes),
                  forced: true,
                  hearingImpaired: false,
                )
                .then((value) => result = value),
          );
          async.flushMicrotasks();

          expect(api.calls, ['upload e1 eng srt']);
          final sent = api.lastUpload!;
          expect(sent.bytes, hasLength(maxSubtitleFileBytes));
          expect(sent.isForced, isTrue);
          expect(sent.isHearingImpaired, isFalse);
          expect(state().uploading, isTrue);
          expect(state().notice, SubtitlesNotice.waiting);

          library.mediaInfoById['e1'] = _info([1, 7]);
          async.elapse(subtitlePollInterval);
          expect(result, isTrue);
          expect(state().uploading, isFalse);
          expect(state().notice, SubtitlesNotice.trackAdded);
        });
      },
    );

    test('caricamento fallito: uploadFailed', () async {
      mount();
      api.nextFailure = SubtitlesFailure.failed;

      final result = await controller().upload(
        file('a.srt', 3),
        forced: false,
        hearingImpaired: false,
      );

      expect(result, isFalse);
      expect(state().notice, SubtitlesNotice.uploadFailed);
      expect(state().uploading, isFalse);
    });
  });

  test('una seconda operazione mentre la prima è in volo si ignora', () async {
    mount();
    api.gate = Completer<void>();
    final first = controller().search();
    await Future<void>.delayed(Duration.zero);
    expect(state().searching, isTrue);

    await controller().search();
    final second = await controller().download(testSubtitle());
    expect(second, isFalse);
    expect(api.calls, ['search e1 ita -']);
    expect(library.mediaInfoCalls, isEmpty);

    api.gate!.complete();
    await first;
    expect(state().searching, isFalse);
  });

  test('chiudere durante l\'attesa ferma le riletture', () {
    fakeAsync((async) {
      mount();
      unawaited(controller().download(testSubtitle()));
      async.flushMicrotasks();
      async.elapse(subtitlePollInterval);
      expect(library.mediaInfoCalls, hasLength(2));

      container.dispose();
      async.elapse(subtitlePollTimeout);

      expect(library.mediaInfoCalls, hasLength(2));
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('un 403 dopo la chiusura rilegge l\'utente senza errori', () {
    fakeAsync((async) {
      mount();
      api.gate = Completer<void>();
      Object? thrown;
      unawaited(
        controller().search().then((_) {}, onError: (Object e) => thrown = e),
      );
      async.flushMicrotasks();
      expect(api.calls, ['search e1 ita -']);

      // Si chiude solo il controller: la sessione resta, come nell'app.
      subscription.close();
      async.elapse(Duration.zero);
      expect(container.exists(subtitlesControllerProvider('e1')), isFalse);

      api.nextFailure = SubtitlesFailure.forbidden;
      api.gate!.complete();
      async.flushMicrotasks();

      expect(thrown, isNull);
      expect(session.refreshUserCalls, 1);
    });
  });

  test('chiudere durante la foto non arriva alla chiamata', () {
    final logged = <String>[];
    final logs = Logger.root.onRecord.listen((r) => logged.add(r.message));
    addTearDown(logs.cancel);
    fakeAsync((async) {
      mount();
      library.delay = const Duration(seconds: 1);
      Object? thrown;
      unawaited(
        controller()
            .download(testSubtitle())
            .then((_) {}, onError: (Object e) => thrown = e),
      );
      async.flushMicrotasks();
      expect(library.mediaInfoCalls, hasLength(1));

      subscription.close();
      async.elapse(Duration.zero);
      async.elapse(const Duration(seconds: 1));

      expect(thrown, isNull);
      expect(api.calls, isEmpty);
      expect(session.refreshUserCalls, 0);
      expect(logged, isEmpty, reason: 'non è un fallimento');
    });
  });

  group('delete', () {
    test('l\'admin elimina una traccia esterna', () async {
      mount(user: testAdmin);

      await controller().delete(_external(5));

      expect(api.calls, ['delete e1 5']);
    });

    test('non admin o traccia nel file: ignorato', () async {
      mount();
      await controller().delete(_external(5));
      expect(api.calls, isEmpty);

      mount(user: testAdmin);
      await controller().delete(const SubtitleTrack(index: 2));
      expect(api.calls, isEmpty);
    });

    test('un 403 rilegge l\'utente', () async {
      mount(user: testAdmin);
      api.nextFailure = SubtitlesFailure.forbidden;

      await controller().delete(_external(5));

      expect(state().notice, SubtitlesNotice.noPermission);
      expect(session.refreshUserCalls, 1);
    });
  });
}
