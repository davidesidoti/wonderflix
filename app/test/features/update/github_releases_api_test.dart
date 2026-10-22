import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/update/github_releases_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/raw_adapter.dart';

void main() {
  test('latestRelease: indirizzo, header e JSON', () async {
    final adapter =
        FakeAdapter((_) => const FakeResponse(200, {'tag_name': 'v0.2.0'}));
    final api = GitHubReleasesApi(userAgent: 'WonderFlix/0.1.0', adapter: adapter);
    expect(await api.latestRelease('owner/repo'), {'tag_name': 'v0.2.0'});
    final request = adapter.requests.single;
    expect(request.uri.toString(),
        'https://api.github.com/repos/owner/repo/releases/latest');
    expect(request.headers['User-Agent'], 'WonderFlix/0.1.0');
    expect(request.headers['Accept'], 'application/vnd.github+json');
    expect(request.headers.containsKey('Authorization'), isFalse);
  });

  test('latestRelease: nessuna release (404) → null', () async {
    final api = GitHubReleasesApi(
        userAgent: 'x', adapter: FakeAdapter((_) => const FakeResponse(404)));
    expect(await api.latestRelease('owner/repo'), isNull);
  });

  test('latestRelease: altri errori arrivano al chiamante', () async {
    final api = GitHubReleasesApi(
        userAgent: 'x', adapter: FakeAdapter((_) => const FakeResponse(403)));
    await expectLater(
        api.latestRelease('owner/repo'), throwsA(isA<DioException>()));
  });

  test('downloadText', () async {
    final api = GitHubReleasesApi(
        userAgent: 'x',
        adapter: RawAdapter(utf8.encode('abc  file.exe\n'),
            contentType: 'text/plain'));
    expect(await api.downloadText(Uri.parse('https://x/file.exe.sha256')),
        'abc  file.exe\n');
  });

  test('downloadFile: scrive i byte e segnala l\'avanzamento', () async {
    final temp = Directory.systemTemp.createTempSync('wf_dl_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final target = File('${temp.path}${Platform.pathSeparator}setup.exe');
    final api = GitHubReleasesApi(
        userAgent: 'x', adapter: RawAdapter(List.filled(1000, 7)));
    final progress = <double>[];
    await api.downloadFile(Uri.parse('https://x/setup.exe'), target,
        onProgress: progress.add);
    expect(target.lengthSync(), 1000);
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
  });
}
