import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/client_info.dart';
import 'package:wonderflix/features/update/update_controller.dart';

import '../../support/pump_app.dart';
import '../../support/update_fakes.dart';

void main() {
  late FakeGitHubReleasesApi api;
  late Directory downloads;
  late List<File> installed;

  setUp(() {
    api = FakeGitHubReleasesApi();
    downloads = Directory.systemTemp.createTempSync('wf_update_');
    installed = [];
  });

  tearDown(() {
    if (downloads.existsSync()) downloads.deleteSync(recursive: true);
  });

  ProviderContainer container({String version = '0.1.0', bool enabled = true}) =>
      ProviderContainer.test(overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        clientInfoProvider.overrideWithValue(ClientInfo(
            client: 'WonderFlix', device: 'PC', deviceId: 'd', version: version)),
        githubReleasesApiProvider.overrideWithValue(api),
        updateChecksEnabledProvider.overrideWithValue(enabled),
        updateDownloadDirectoryProvider.overrideWithValue(downloads),
        installUpdateProvider.overrideWithValue((file) async => installed.add(file)),
      ]);

  Future<UpdateState> checked(ProviderContainer c) async {
    c.read(updateControllerProvider);
    await c.read(updateControllerProvider.notifier).check();
    return c.read(updateControllerProvider);
  }

  test('versione più nuova: scarica, verifica e segnala pronto', () async {
    api.latest = latestJson('0.2.0');
    final state = await checked(container());
    expect(state.release!.version, Version(0, 2, 0));
    expect(state.mandatory, isFalse);
    expect(state.ready, isTrue);
    expect(state.installer!.path, endsWith('WonderFlix-Setup-0.2.0.exe'));
    expect(state.installer!.readAsBytesSync(), [1, 2, 3]);
    expect(File('${state.installer!.path}.part').existsSync(), isFalse);
  });

  test('stessa versione o più vecchia: niente da fare', () async {
    api.latest = latestJson('0.1.0');
    final state = await checked(container());
    expect(state.release, isNull);
    expect(api.downloads, 0);
  });

  test('nessuna release (404): niente da fare', () async {
    api.latest = null;
    expect((await checked(container())).release, isNull);
  });

  test('min-version sopra la versione installata: obbligatorio', () async {
    api.latest = latestJson('0.2.0',
        body: 'Importante <!-- wonderflix:min-version=0.2.0 -->');
    final state = await checked(container());
    expect(state.mandatory, isTrue);
    expect(state.ready, isTrue);
    expect(state.release!.notes, 'Importante');
  });

  test('min-version già soddisfatta: facoltativo', () async {
    api.latest = latestJson('0.2.0',
        body: '<!-- wonderflix:min-version=0.1.0 -->');
    expect((await checked(container())).mandatory, isFalse);
  });

  test('SHA-256 diverso: file eliminato, nessun aggiornamento, avviso nel log',
      () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    api.latest = latestJson('0.2.0');
    api.installerBytes = const [9, 9, 9];
    final state = await checked(container());
    expect(state.release, isNull);
    expect(downloads.listSync(), isEmpty);
    expect(records.where((r) => r.level == Level.WARNING), isNotEmpty);
  });

  test('installer già scaricato e valido: nessun nuovo download', () async {
    api.latest = latestJson('0.2.0');
    File('${downloads.path}${Platform.pathSeparator}WonderFlix-Setup-0.2.0.exe')
        .writeAsBytesSync(const [1, 2, 3]);
    final state = await checked(container());
    expect(state.ready, isTrue);
    expect(api.downloads, 0);
  });

  test('toglie gli installer delle versioni precedenti', () async {
    api.latest = latestJson('0.2.0');
    final old = File(
        '${downloads.path}${Platform.pathSeparator}WonderFlix-Setup-0.1.5.exe')
      ..writeAsBytesSync(const [0]);
    await checked(container());
    expect(old.existsSync(), isFalse);
  });

  test('obbligatorio con download fallito: "failed", poi riprova', () async {
    api.latest = latestJson('0.2.0',
        body: '<!-- wonderflix:min-version=0.2.0 -->');
    api.downloadError = const SocketException('offline');
    final c = container();
    final failed = await checked(c);
    expect(failed.mandatory, isTrue);
    expect(failed.failed, isTrue);
    expect(failed.ready, isFalse);

    api.downloadError = null;
    c.read(updateControllerProvider.notifier).retry();
    expect(c.read(updateControllerProvider).failed, isFalse);
    // Il nuovo tentativo scrive su disco: si aspetta che finisca.
    for (var i = 0; i < 100 && !c.read(updateControllerProvider).ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(c.read(updateControllerProvider).ready, isTrue);
  });

  /// Aspetta che [done] sia vero (il controllo scrive su disco).
  Future<void> waitFor(ProviderContainer c, bool Function(UpdateState) done) async {
    for (var i = 0; i < 100 && !done(c.read(updateControllerProvider)); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('obbligatorio: un errore di rete al nuovo tentativo non sblocca l\'app',
      () async {
    api.latest = latestJson('0.2.0',
        body: '<!-- wonderflix:min-version=0.2.0 -->');
    api.downloadError = const SocketException('offline');
    final c = container();
    await checked(c);

    api.latestError = const SocketException('offline');
    c.read(updateControllerProvider.notifier).retry();
    await waitFor(c, (s) => s.failed || s.release == null);
    final state = c.read(updateControllerProvider);
    expect(state.mandatory, isTrue);
    expect(state.failed, isTrue);
    expect(state.release, isNotNull);
  });

  test('facoltativo con errore di rete: nessun segno per l\'utente', () async {
    api.latestError = const SocketException('offline');
    final state = await checked(container());
    expect(state.release, isNull);
    expect(state.failed, isFalse);
  });

  test('install avvia l\'installer scaricato', () async {
    api.latest = latestJson('0.2.0');
    final c = container();
    final state = await checked(c);
    await c.read(updateControllerProvider.notifier).install();
    expect(installed.single.path, state.installer!.path);
  });

  test('controlli disattivati (build di sviluppo): nessuna chiamata', () async {
    final c = container(enabled: false);
    c.read(updateControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(api.latestCalls, 0);
  });

  test('controllo all\'avvio e poi ogni 6 ore', () {
    fakeAsync((async) {
      final c = container();
      c.read(updateControllerProvider);
      async.flushMicrotasks();
      expect(api.latestCalls, 1);
      async.elapse(const Duration(hours: 6));
      expect(api.latestCalls, 2);
    });
  });
}
